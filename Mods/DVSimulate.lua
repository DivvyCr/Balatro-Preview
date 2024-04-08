--- STEAMODDED HEADER
--- MOD_NAME: Divvy's Simulation
--- MOD_ID: dvsimulate
--- MOD_AUTHOR: [Divvy C.]
--- MOD_DESCRIPTION: A utility mod to simulate selected hand. v2.2.1
--- PRIORITY: -80

if not DV then DV = {} end

DV.SIM = {
   running = {
      --- Table to store workings (ie. running totals):
      min   = {chips = 0, mult = 0, dollars = 0},
      exact = {chips = 0, mult = 0, dollars = 0},
      max   = {chips = 0, mult = 0, dollars = 0},
      reps = 0,
   },

   env = {
      --- Table to store data about the simulated play:
      jokers = {},        -- Derived from G.jokers.cards
      played_cards = {},  -- Derived from G.hand.highlighted
      scoring_cards = {}, -- Derived according to evaluate_play()
      held_cards = {},    -- Derived from G.hand minus G.hand.highlighted
      consumables = {},   -- Derived from G.consumeables.cards
      scoring_name = ""   -- Derived according to evaluate_play()
   },

   orig = {
      --- Table to store game data that gets modified during simulation:
      random_data = {}, -- G.GAME.pseudorandom
      hands_played = 0, -- G.GAME.current_round.hands_played
      hands_left = 0,   -- G.GAME.current_round.hands_left
      hand_data = {}    -- G.GAME.hands
   },

   misc = {
      --- Table to store ancillary status variables:
      next_stone_id = -1
   }
}

function DV.SIM.run()
   local null_ret = {score = {min=0, exact=0, max=0}, dollars = {min=0, exact=0, max=0}}
   if #G.hand.highlighted < 1 then return null_ret end

   DV.SIM.init()

   DV.SIM.manage_state("SAVE")

   if not DV.SIM.simulate_blind_debuffs() then
      DV.SIM.simulate_joker_before_effects()
      DV.SIM.update_state_variables()
      DV.SIM.add_base_chips_and_mult()
      DV.SIM.simulate_blind_effects()
      DV.SIM.simulate_scoring_cards()
      DV.SIM.simulate_held_cards()
      DV.SIM.simulate_joker_global_effects()
      DV.SIM.simulate_consumable_effects()
      DV.SIM.simulate_deck_effects()
   else -- Only Matador at this point:
      DV.SIM.simulate_all_jokers(G.jokers, {debuffed_hand = true})
   end

   DV.SIM.manage_state("RESTORE")

   return DV.SIM.get_results()
end

function DV.SIM.init()
   -- Reset:
   DV.SIM.running = {
      min   = {chips = 0, mult = 0, dollars = 0},
      exact = {chips = 0, mult = 0, dollars = 0},
      max   = {chips = 0, mult = 0, dollars = 0},
      reps = 0
   }

   -- Fetch metadata about simulated play:
   local hand_name, _, poker_hands, scoring_hand, _ = G.FUNCS.get_poker_hand_info(G.hand.highlighted)
   DV.SIM.env.scoring_name = hand_name

   -- Identify played cards and extract necessary data:
   DV.SIM.env.played_cards = {}
   DV.SIM.env.scoring_cards = {}
   local is_splash_joker = next(find_joker("Splash"))
   table.sort(G.hand.highlighted, function(a, b) return a.T.x < b.T.x end) -- Sorts by positional x-value to mirror card order!
   for _, card in ipairs(G.hand.highlighted) do
      local is_scoring = false
      for _, scoring_card in ipairs(scoring_hand) do
       -- Either card is scoring because it's part of the scoring hand,
       -- or there is Splash joker, or it's a Stone Card:
         if card.sort_id == scoring_card.sort_id
            or is_splash_joker
            or card.ability.effect == "Stone Card"
         then
            is_scoring = true
            break
         end
      end

      local card_data = DV.SIM.get_card_data(card)
      table.insert(DV.SIM.env.played_cards, card_data)
      if is_scoring then table.insert(DV.SIM.env.scoring_cards, card_data) end
   end

   -- Identify held cards and extract necessary data:
   DV.SIM.env.held_cards = {}
   for _, card in ipairs(G.hand.cards) do
      -- Highlighted cards are simulated as played cards:
      if not card.highlighted then
         local card_data = DV.SIM.get_card_data(card)
         table.insert(DV.SIM.env.held_cards, card_data)
      end
   end

   -- Extract necessary joker data:
   DV.SIM.env.jokers = {}
   for _, joker in ipairs(G.jokers.cards) do
      local joker_data = {
         -- P_CENTER keys for jokers have the form j_NAME, get rid of j_
         id = joker.config.center.key:sub(3, #joker.config.center.key),
         ability = copy_table(joker.ability),
         edition = copy_table(joker.edition),
         rarity = joker.config.center.rarity,
         debuff = joker.debuff
      }
      table.insert(DV.SIM.env.jokers, joker_data)
   end

   -- Extract necessary consumable data:
   DV.SIM.env.consumables = {}
   for _, consumable in ipairs(G.consumeables.cards) do
      local consumable_data = {
         -- P_CENTER keys have the form x_NAME, get rid of x_
         id = consumable.config.center.key:sub(3, #consumable.config.center.key),
         ability = copy_table(consumable.ability)
      }
      table.insert(DV.SIM.env.consumables, consumable_data)
   end

   -- Set extensible context template:
   DV.SIM.get_context = function(cardarea, args)
      local context = {
         cardarea = cardarea,
         full_hand = DV.SIM.env.played_cards,
         scoring_name = hand_name,
         scoring_hand = DV.SIM.env.scoring_cards,
         poker_hands = poker_hands
      }

      for k, v in pairs(args) do
         context[k] = v
      end

      return context
   end
end

function DV.SIM.get_card_data(card_obj)
   return {
      rank = card_obj.base.id,
      suit = card_obj.base.suit,
      base_chips = card_obj.base.nominal,
      ability = copy_table(card_obj.ability),
      edition = copy_table(card_obj.edition),
      seal = card_obj.seal,
      debuff = card_obj.debuff,
      lucky_trigger = {}
   }
end

function DV.SIM.get_results()
   local DVSR = DV.SIM.running

   local min_score   = math.floor(DVSR.min.chips   * DVSR.min.mult)
   local exact_score = math.floor(DVSR.exact.chips * DVSR.exact.mult)
   local max_score   = math.floor(DVSR.max.chips   * DVSR.max.mult)

   return {
      score   = {min = min_score,        exact = exact_score,        max = max_score},
      dollars = {min = DVSR.min.dollars, exact = DVSR.exact.dollars, max = DVSR.max.dollars}
   }
end

--
-- GAME STATE MANAGEMENT:
--

function DV.SIM.manage_state(save_or_restore)
   local DVSO = DV.SIM.orig

   if save_or_restore == "SAVE" then
      DVSO.random_data = copy_table(G.GAME.pseudorandom)
      DVSO.hands_played = G.GAME.current_round.hands_played
      DVSO.hands_left = G.GAME.current_round.hands_left
      DVSO.hand_data = copy_table(G.GAME.hands)
      return
   end

   if save_or_restore == "RESTORE" then
      G.GAME.pseudorandom = DVSO.random_data
      G.GAME.current_round.hands_played = DVSO.hands_played
      G.GAME.current_round.hands_left = DVSO.hands_left
      G.GAME.hands = DVSO.hand_data
      return
   end
end

function DV.SIM.update_state_variables()
   -- Increment hands played this round:
   G.GAME.current_round.hands_played = G.GAME.current_round.hands_played + 1
   G.GAME.current_round.hands_left = G.GAME.current_round.hands_left - 1

   -- Increment poker hand played this run/round:
   local hand_info = G.GAME.hands[DV.SIM.env.scoring_name]
   hand_info.played = hand_info.played + 1
   hand_info.played_this_round = hand_info.played_this_round + 1
end

--
-- MACRO LEVEL:
--

function DV.SIM.simulate_scoring_cards()
   for _, scoring_card in ipairs(DV.SIM.env.scoring_cards) do
      DV.SIM.simulate_card_in_context(scoring_card, G.play)
   end
end

function DV.SIM.simulate_held_cards()
   for _, held_card in ipairs(DV.SIM.env.held_cards) do
      DV.SIM.simulate_card_in_context(held_card, G.hand)
   end
end

function DV.SIM.simulate_joker_global_effects()
   for _, joker in ipairs(DV.SIM.env.jokers) do
      if joker.edition then -- Foil and Holo:
         if joker.edition.chips then DV.SIM.add_chips(joker.edition.chips) end
         if joker.edition.mult  then DV.SIM.add_mult(joker.edition.mult) end
      end

      DV.SIM.simulate_joker(joker, DV.SIM.get_context(G.jokers, {global = true}))

      -- Joker-on-joker effects (eg. Blueprint):
      DV.SIM.simulate_all_jokers(G.jokers, {other_joker = joker})

      if joker.edition then -- Poly:
         if joker.edition.x_mult then DV.SIM.x_mult(joker.edition.x_mult) end
      end
   end
end

function DV.SIM.simulate_consumable_effects()
   for _, consumable in ipairs(DV.SIM.env.consumables) do
      if consumable.ability.set == "Planet" and not consumable.debuff then
         if G.GAME.used_vouchers.v_observatory and consumable.ability.consumeable.hand_type == DV.SIM.env.scoring_name then
            DV.SIM.x_mult(G.P_CENTERS.v_observatory.config.extra)
         end
      end
   end
end

function DV.SIM.add_base_chips_and_mult()
   local played_hand_data = G.GAME.hands[DV.SIM.env.scoring_name]
   DV.SIM.add_chips(played_hand_data.chips)
   DV.SIM.add_mult(played_hand_data.mult)
end

function DV.SIM.simulate_joker_before_effects()
   for _, joker in ipairs(DV.SIM.env.jokers) do
      DV.SIM.simulate_joker(joker, DV.SIM.get_context(G.jokers, {before = true}))
   end
end

function DV.SIM.simulate_blind_effects()
   if G.GAME.blind.disabled then return end

   if G.GAME.blind.name == "The Flint" then
      local function flint(data)
         local half_chips = math.floor(data.chips/2 + 0.5)
         local half_mult = math.floor(data.mult/2 + 0.5)
         data.chips = mod_chips(math.max(half_chips, 0))
         data.mult  = mod_mult(math.max(half_mult, 1))
      end

      flint(DV.SIM.running.min)
      flint(DV.SIM.running.exact)
      flint(DV.SIM.running.max)
   else
      -- Other blinds do not impact scoring; refer to Blind:modify_hand(..)
   end
end

function DV.SIM.simulate_deck_effects()
   if G.GAME.selected_back.name == 'Plasma Deck' then
      local function plasma(data)
         local sum = data.chips + data.mult
         local half_sum = math.floor(sum/2)
         data.chips = mod_chips(half_sum)
         data.mult = mod_mult(half_sum)
      end

      plasma(DV.SIM.running.min)
      plasma(DV.SIM.running.exact)
      plasma(DV.SIM.running.max)
   else
      -- Other decks do not impact scoring; refer to Back:trigger_effect(..)
   end
end

function DV.SIM.simulate_blind_debuffs()
   local blind_obj = G.GAME.blind
   if blind_obj.disabled then return false end

   -- The following are part of Blind:press_play()

   if blind_obj.name == "The Hook" then
      blind_obj.triggered = true
      for _ = 1, math.min(2, #DV.SIM.env.held_cards) do
         -- TODO: Identify cards-in-hand that can affect score, simulate with/without them for min/max
         local selected_card, card_key = pseudorandom_element(DV.SIM.env.held_cards, pseudoseed('hook'))
         table.remove(DV.SIM.env.held_cards, card_key)
         for _, joker in ipairs(DV.SIM.env.jokers) do
            -- Note that the cardarea argument is largely arbitrary (used for DV.SIM.JOKERS),
            -- I use G.hand because The Hook discards from the hand
            DV.SIM.simulate_joker(joker, DV.SIM.get_context(G.hand, {discard = true, other_card = selected_card}))
         end
      end
   end

   if blind_obj.name == "The Tooth" then
      blind_obj.triggered = true
      DV.SIM.add_dollars((-1) * #DV.SIM.env.scoring_cards)
   end

   -- The following are part of Blind:debuff_hand(..)

   if blind_obj.name == "The Arm" then
      blind_obj.triggered = false

      local played_hand_name = DV.SIM.env.scoring_name
      if G.GAME.hands[played_hand_name].level > 1 then
         blind_obj.triggered = true
         -- NOTE: Important to save/restore G.GAME.hands for this:
         local played_hand_data = G.GAME.hands[played_hand_name]
         played_hand_data.level = math.max(1, played_hand_data.level - 1)
         played_hand_data.mult = math.max(1, played_hand_data.s_mult - played_hand_data.l_mult)
         played_hand_data.chips = math.max(0, played_hand_data.s_chips - played_hand_data.l_chips)
      end
      return false -- IMPORTANT: Avoid duplicate effects from Blind:debuff_hand() below
   end

   if blind_obj.name == "The Ox" then
      blind_obj.triggered = false

      if DV.SIM.env.scoring_name == G.GAME.current_round.most_played_poker_hand then
         blind_obj.triggered = true
         DV.SIM.add_dollars(-G.GAME.dollars)
      end
      return false -- IMPORTANT: Avoid duplicate effects from Blind:debuff_hand() below
   end

   return blind_obj:debuff_hand(DV.SIM.env.played_cards, DV.SIM.env.poker_hands, DV.SIM.env.scoring_name, true)
end

--
-- MICRO LEVEL (CARDS):
--

function DV.SIM.simulate_card_in_context(card, cardarea)
   -- Reset and collect repetitions:
   DV.SIM.running.reps = 1
   if card.seal == "Red" then DV.SIM.add_reps(1) end
   DV.SIM.simulate_all_jokers(cardarea, {other_card = card, repetition = true})

   -- Apply effects:
   for _ = 1, DV.SIM.running.reps do
      DV.SIM.simulate_card(card, DV.SIM.get_context(cardarea, {}))
      DV.SIM.simulate_all_jokers(cardarea, {other_card = card, individual = true})
   end
end

function DV.SIM.simulate_card(card_data, context)
   -- Do nothing if debuffed:
   if card_data.debuff then return end

   if context.cardarea == G.play then
      -- Chips:
      if card_data.ability.effect == "Stone Card" then
         DV.SIM.add_chips(card_data.ability.bonus + (card_data.ability.perma_bonus or 0))
      else
         DV.SIM.add_chips(card_data.base_chips + card_data.ability.bonus + (card_data.ability.perma_bonus or 0))
      end

      -- Mult:
      if card_data.ability.effect == "Lucky Card" then
         local exact_mult, min_mult, max_mult = DV.SIM.get_probabilistic_extremes(pseudorandom("lucky_mult"), 5, card_data.ability.mult, 0)
         DV.SIM.add_mult(exact_mult, min_mult, max_mult)
         -- Careful not to overwrite `card_data.lucky_trigger` outright:
         if exact_mult > 0 then card_data.lucky_trigger.exact = true end
         if min_mult > 0 then card_data.lucky_trigger.min = true end
         if max_mult > 0 then card_data.lucky_trigger.max = true end
      else
         DV.SIM.add_mult(card_data.ability.mult)
      end

      -- XMult:
      if card_data.ability.x_mult > 1 then
         DV.SIM.x_mult(card_data.ability.x_mult)
      end

      -- Dollars:
      if card_data.seal == "Gold" then
         DV.SIM.add_dollars(3)
      end
      if card_data.ability.p_dollars > 0 then
         if card_data.ability.effect == "Lucky Card" then
            local exact_dollars, min_dollars, max_dollars = DV.SIM.get_probabilistic_extremes(pseudorandom("lucky_money"), 15, card_data.ability.p_dollars, 0)
            DV.SIM.add_dollars(exact_dollars, min_dollars, max_dollars)
            -- Careful not to overwrite `card_data.lucky_trigger` outright:
            if exact_dollars > 0 then card_data.lucky_trigger.exact = true end
            if min_dollars > 0 then card_data.lucky_trigger.min = true end
            if max_dollars > 0 then card_data.lucky_trigger.max = true end
         else
            DV.SIM.add_dollars(card_data.ability.p_dollars)
         end
      end

     -- Edition:
      if card_data.edition then
         if card_data.edition.chips then DV.SIM.add_chips(card_data.edition.chips) end
         if card_data.edition.mult then DV.SIM.add_mult(card_data.edition.mult) end
         if card_data.edition.x_mult then DV.SIM.x_mult(card_data.edition.x_mult) end
      end

   elseif context.cardarea == G.hand then
      if card_data.ability.h_mult > 0 then
         DV.SIM.add_mult(card_data.ability.h_mult)
      end

      if card_data.ability.h_x_mult > 0 then
         DV.SIM.x_mult(card_data.ability.h_x_mult)
      end
   end
end

--
-- MICRO LEVEL (JOKERS):
--

function DV.SIM.simulate_all_jokers(cardarea, context_args)
   for _, joker in ipairs(DV.SIM.env.jokers) do
      DV.SIM.simulate_joker(joker, DV.SIM.get_context(cardarea, context_args))
   end
end

function DV.SIM.simulate_joker(joker_obj, context)
   -- Do nothing if debuffed:
   if joker_obj.debuff then return end

   local joker_simulation_function = DV.SIM.JOKERS["simulate_" .. joker_obj.id]
   if joker_simulation_function then joker_simulation_function(joker_obj, context) end
end

DV.SIM.JOKERS = {
   simulate_joker = function(joker_obj, context)
      if context.cardarea == G.jokers and context.global then
         DV.SIM.add_mult(joker_obj.ability.mult)
      end
   end,
   simulate_greedy_joker = function(joker_obj, context)
      DV.SIM.JOKERS.add_suit_mult(joker_obj, context)
   end,
   simulate_lusty_joker = function(joker_obj, context)
      DV.SIM.JOKERS.add_suit_mult(joker_obj, context)
   end,
   simulate_wrathful_joker = function(joker_obj, context)
      DV.SIM.JOKERS.add_suit_mult(joker_obj, context)
   end,
   simulate_gluttenous_joker = function(joker_obj, context)
      DV.SIM.JOKERS.add_suit_mult(joker_obj, context)
   end,
   simulate_jolly = function(joker_obj, context)
      DV.SIM.JOKERS.add_type_mult(joker_obj, context)
   end,
   simulate_zany = function(joker_obj, context)
      DV.SIM.JOKERS.add_type_mult(joker_obj, context)
   end,
   simulate_mad = function(joker_obj, context)
      DV.SIM.JOKERS.add_type_mult(joker_obj, context)
   end,
   simulate_crazy = function(joker_obj, context)
      DV.SIM.JOKERS.add_type_mult(joker_obj, context)
   end,
   simulate_droll = function(joker_obj, context)
      DV.SIM.JOKERS.add_type_mult(joker_obj, context)
   end,
   simulate_sly = function(joker_obj, context)
      DV.SIM.JOKERS.add_type_chips(joker_obj, context)
   end,
   simulate_wily = function(joker_obj, context)
      DV.SIM.JOKERS.add_type_chips(joker_obj, context)
   end,
   simulate_clever = function(joker_obj, context)
      DV.SIM.JOKERS.add_type_chips(joker_obj, context)
   end,
   simulate_devious = function(joker_obj, context)
      DV.SIM.JOKERS.add_type_chips(joker_obj, context)
   end,
   simulate_crafty = function(joker_obj, context)
      DV.SIM.JOKERS.add_type_chips(joker_obj, context)
   end,
   simulate_half = function(joker_obj, context)
      if context.cardarea == G.jokers and context.global then
         if #context.full_hand <= joker_obj.ability.extra.size then
            DV.SIM.add_mult(joker_obj.ability.extra.mult)
         end
      end
   end,
   simulate_stencil = function(joker_obj, context)
      if context.cardarea == G.jokers and context.global then
         local xmult = G.jokers.config.card_limit - #DV.SIM.env.jokers
         for _, joker in ipairs(DV.SIM.env.jokers) do
            if joker.ability.name == "Joker Stencil" then xmult = xmult + 1 end
         end
         if joker_obj.ability.x_mult > 1 then
            DV.SIM.x_mult(joker_obj.ability.x_mult)
         end
      end
   end,
   simulate_four_fingers = function(joker_obj, context)
      -- Effect not relevant (Meta)
   end,
   simulate_mime = function(joker_obj, context)
      if context.cardarea == G.hand and context.repetition then
         DV.SIM.add_reps(joker_obj.ability.extra)
      end
   end,
   simulate_credit_card = function(joker_obj, context)
      -- Effect not relevant (Meta)
   end,
   simulate_ceremonial = function(joker_obj, context)
      if context.cardarea == G.jokers and context.global then
         DV.SIM.add_mult(joker_obj.ability.mult)
      end
   end,
   simulate_banner = function(joker_obj, context)
      if context.cardarea == G.jokers and context.global then
         if G.GAME.current_round.discards_left > 0 then
            local chips = G.GAME.current_round.discards_left * joker_obj.ability.extra
            DV.SIM.add_chips(chips)
         end
      end
   end,
   simulate_mystic_summit = function(joker_obj, context)
      if context.cardarea == G.jokers and context.global then
         if G.GAME.current_round.discards_left == joker_obj.ability.extra.d_remaining then
            DV.SIM.add_mult(joker_obj.ability.extra.mult)
         end
      end
   end,
   simulate_marble = function(joker_obj, context)
      -- Effect not relevant (Blind)
   end,
   simulate_loyalty_card = function(joker_obj, context)
      if context.cardarea == G.jokers and context.global then
         local loyalty_diff = G.GAME.hands_played - joker_obj.ability.hands_played_at_create
         local loyalty_remaining = ((joker_obj.ability.extra.every-1) - loyalty_diff) % (joker_obj.ability.extra.every+1)
         if loyalty_remaining == joker_obj.ability.extra.every then
            DV.SIM.x_mult(joker_obj.ability.extra.Xmult)
         end
      end
   end,
   simulate_8_ball = function(joker_obj, context)
      -- Effect might be relevant?
   end,
   simulate_misprint = function(joker_obj, context)
      if context.cardarea == G.jokers and context.global then
         local exact_mult = pseudorandom("misprint", joker_obj.ability.extra.min, joker_obj.ability.extra.max)
         DV.SIM.add_mult(exact_mult, joker_obj.ability.extra.min, joker_obj.ability.extra.max)
      end
   end,
   simulate_dusk = function(joker_obj, context)
      if context.cardarea == G.play and context.repetition then
         if G.GAME.current_round.hands_left == 0 then
            DV.SIM.add_reps(joker_obj.ability.extra)
         end
      end
   end,
   simulate_raised_fist = function(joker_obj, context)
      if context.cardarea == G.hand and context.individual then
         local cur_mult, cur_rank = 15, 15
         local raised_card = nil
         for _, card in ipairs(DV.SIM.env.held_cards) do
            if cur_rank >= card.rank and card.ability.effect ~= 'Stone Card' then
               cur_mult = card.base_chips
               cur_rank = card.rank
               raised_card = card
            end
         end
         if raised_card == context.other_card and not context.other_card.debuff then
            DV.SIM.add_mult(2 * cur_mult)
         end
      end
   end,
   simulate_chaos = function(joker_obj, context)
      -- Effect not relevant (Free Reroll)
   end,
   simulate_fibonacci = function(joker_obj, context)
      if context.cardarea == G.play and context.individual then
         if DV.SIM.is_rank(context.other_card, {2, 3, 5, 8, 14}) and not context.other_card.debuff then
            DV.SIM.add_mult(joker_obj.ability.extra)
         end
      end
   end,
   simulate_steel_joker = function(joker_obj, context)
      if context.cardarea == G.jokers and context.global then
         DV.SIM.x_mult(1 + joker_obj.ability.extra * joker_obj.ability.steel_tally)
      end
   end,
   simulate_scary_face = function(joker_obj, context)
      if context.cardarea == G.play and context.individual then
         if DV.SIM.is_face(context.other_card) and not context.other_card.debuff then
            DV.SIM.add_chips(joker_obj.ability.extra)
         end
      end
   end,
   simulate_abstract = function(joker_obj, context)
      if context.cardarea == G.jokers and context.global then
         DV.SIM.add_mult(#DV.SIM.env.jokers * joker_obj.ability.extra)
      end
   end,
   simulate_delayed_grat = function(joker_obj, context)
      -- Effect not relevant (End of Round)
   end,
   simulate_hack = function(joker_obj, context)
      if context.cardarea == G.play and context.repetition then
         if not context.other_card.debuff and DV.SIM.is_rank(context.other_card, {2, 3, 4, 5}) then
            DV.SIM.add_reps(joker_obj.ability.extra)
         end
      end
   end,
   simulate_pareidolia = function(joker_obj, context)
      -- Effect not relevant (Meta)
   end,
   simulate_gros_michel = function(joker_obj, context)
      if context.cardarea == G.jokers and context.global then
         DV.SIM.add_mult(joker_obj.ability.extra.mult)
      end
   end,
   simulate_even_steven = function(joker_obj, context)
      if context.cardarea == G.play and context.individual then
         if not context.other_card.debuff and DV.SIM.check_rank_parity(context.other_card, true) then
            DV.SIM.add_mult(joker_obj.ability.extra)
         end
      end
   end,
   simulate_odd_todd = function(joker_obj, context)
      if context.cardarea == G.play and context.individual then
         if not context.other_card.debuff and DV.SIM.check_rank_parity(context.other_card, false) then
            DV.SIM.add_chips(joker_obj.ability.extra)
         end
      end
   end,
   simulate_scholar = function(joker_obj, context)
      if context.cardarea == G.play and context.individual then
         if DV.SIM.is_rank(context.other_card, 14) and not context.other_card.debuff then
            DV.SIM.add_chips(joker_obj.ability.extra.chips)
            DV.SIM.add_mult(joker_obj.ability.extra.mult)
         end
      end
   end,
   simulate_business = function(joker_obj, context)
      if context.cardarea == G.play and context.individual then
         if DV.SIM.is_face(context.other_card) and not context.other_card.debuff then
            local exact_dollars, min_dollars, max_dollars = DV.SIM.get_probabilistic_extremes(pseudorandom("business"), joker_obj.ability.extra, 2, 0)
            DV.SIM.add_dollars(exact_dollars, min_dollars, max_dollars)
         end
      end
   end,
   simulate_supernova = function(joker_obj, context)
      if context.cardarea == G.jokers and context.global then
         DV.SIM.add_mult(G.GAME.hands[context.scoring_name].played)
      end
   end,
   simulate_ride_the_bus = function(joker_obj, context)
      if context.cardarea == G.jokers and context.before and not context.blueprint then
         local faces = false
         for _, scoring_card in ipairs(context.scoring_hand) do
            if DV.SIM.is_face(scoring_card) then faces = true end
         end
         if faces then
            joker_obj.ability.mult = 0
         else
            joker_obj.ability.mult = joker_obj.ability.mult + joker_obj.ability.extra
         end
      end
      if context.cardarea == G.jokers and context.global then
         DV.SIM.add_mult(joker_obj.ability.mult)
      end
   end,
   simulate_space = function(joker_obj, context)
      -- TODO: Verify
      if context.cardarea == G.jokers and context.before then
         local hand_data = G.GAME.hands[DV.SIM.env.scoring_name]

         local rand = pseudorandom("space") -- Must reuse same pseudorandom value:
         local exact_chips, min_chips, max_chips = DV.SIM.get_probabilistic_extremes(rand, joker_obj.ability.extra, hand_data.l_chips, 0)
         local exact_mult,  min_mult,  max_mult  = DV.SIM.get_probabilistic_extremes(rand, joker_obj.ability.extra, hand_data.l_mult,  0)

         DV.SIM.add_chips(exact_chips, min_chips, max_chips)
         DV.SIM.add_mult(exact_mult, min_mult, max_mult)
      end
   end,
   simulate_egg = function(joker_obj, context)
      -- Effect not relevant (Meta)
   end,
   simulate_burglar = function(joker_obj, context)
      -- Effect not relevant (Meta)
   end,
   simulate_blackboard = function(joker_obj, context)
      if context.cardarea == G.jokers and context.global then
         local black_suits, all_cards = 0, 0
         for _, card in ipairs(DV.SIM.env.held_cards) do
            all_cards = all_cards + 1
            if DV.SIM.is_suit(card, "Clubs", true) or DV.SIM.is_suit(card, "Spades", true) then
               black_suits = black_suits + 1
            end
         end
         if black_suits == all_cards then
            DV.SIM.x_mult(joker_obj.ability.extra)
         end
      end
   end,
   simulate_runner = function(joker_obj, context)
      if context.cardarea == G.jokers and context.before and not context.blueprint then
         if next(context.poker_hands["Straight"]) then
            joker_obj.ability.extra.chips = joker_obj.ability.extra.chips + joker_obj.ability.extra.chip_mod
         end
      end
      if context.cardarea == G.jokers and context.global then
         DV.SIM.add_chips(joker_obj.ability.extra.chips)
      end
   end,
   simulate_ice_cream = function(joker_obj, context)
      if context.cardarea == G.jokers and context.global then
         DV.SIM.add_chips(joker_obj.ability.extra.chips)
      end
   end,
   simulate_dna = function(joker_obj, context)
      if context.cardarea == G.jokers and context.before then
         if G.GAME.current_round.hands_played == 0 and #context.full_hand == 1 then
            local new_card = copy_table(context.full_hand[1])
            table.insert(DV.SIM.env.held_cards, new_card)
         end
      end
   end,
   simulate_splash = function(joker_obj, context)
      -- Effect not relevant (Meta)
   end,
   simulate_blue_joker = function(joker_obj, context)
      if context.cardarea == G.jokers and context.global then
         DV.SIM.add_chips(joker_obj.ability.extra * #G.deck.cards)
      end
   end,
   simulate_sixth_sense = function(joker_obj, context)
      -- Effect might be relevant?
   end,
   simulate_constellation = function(joker_obj, context)
      DV.SIM.JOKERS.x_mult_if_global(joker_obj, context)
   end,
   simulate_hiker = function(joker_obj, context)
      if context.cardarea == G.play and context.individual then
         if not context.other_card.debuff then
            context.other_card.ability.perma_bonus = (context.other_card.ability.perma_bonus or 0) + joker_obj.ability.extra
         end
      end
   end,
   simulate_faceless = function(joker_obj, context)
      -- Effect not relevant (Discard)
   end,
   simulate_green_joker = function(joker_obj, context)
      if context.cardarea == G.jokers and context.before and not context.blueprint then
         joker_obj.ability.mult = joker_obj.ability.mult + joker_obj.ability.extra.hand_add
      end
      if context.cardarea == G.jokers and context.global then
         DV.SIM.add_mult(joker_obj.ability.mult)
      end
   end,
   simulate_superposition = function(joker_obj, context)
      -- Effect might be relevant?
   end,
   simulate_todo_list = function(joker_obj, context)
      if context.cardarea == G.jokers and context.before then
         if context.scoring_name == joker_obj.ability.to_do_poker_hand then
            DV.SIM.add_dollars(joker_obj.ability.extra.dollars)
         end
      end
   end,
   simulate_cavendish = function(joker_obj, context)
      if context.cardarea == G.jokers and context.global then
         DV.SIM.x_mult(joker_obj.ability.extra.Xmult)
      end
   end,
   simulate_card_sharp = function(joker_obj, context)
      if context.cardarea == G.jokers and context.global then
         if (G.GAME.hands[context.scoring_name]
            and G.GAME.hands[context.scoring_name].played_this_round > 1)
         then
            DV.SIM.x_mult(joker_obj.ability.extra.Xmult)
         end
      end
   end,
   simulate_red_card = function(joker_obj, context)
      if context.cardarea == G.jokers and context.global then
         DV.SIM.add_mult(joker_obj.ability.mult)
      end
   end,
   simulate_madness = function(joker_obj, context)
      DV.SIM.JOKERS.x_mult_if_global(joker_obj, context)
   end,
   simulate_square = function(joker_obj, context)
      if context.cardarea == G.jokers and context.before and not context.blueprint then
         if #context.full_hand == 4 then
            joker_obj.ability.extra.chips = joker_obj.ability.extra.chips + joker_obj.ability.extra.chip_mod
         end
      end
      if context.cardarea == G.jokers and context.global then
         DV.SIM.add_chips(joker_obj.ability.extra.chips)
      end
   end,
   simulate_seance = function(joker_obj, context)
      -- Effect might be relevant? (Consumable)
   end,
   simulate_riff_raff = function(joker_obj, context)
      -- Effect not relevant (Blind)
   end,
   simulate_vampire = function(joker_obj, context)
      if context.cardarea == G.jokers and context.before and not context.blueprint then
         local num_enhanced = 0
         for _, card in ipairs(context.scoring_hand) do
            if card.ability.name ~= "Default Base" and not card.debuff then
               num_enhanced = num_enhanced + 1
               DV.SIM.set_ability(card, G.P_CENTERS.c_base)
            end
         end
         if num_enhanced > 0 then
            joker_obj.ability.x_mult = joker_obj.ability.x_mult + (joker_obj.ability.extra * num_enhanced)
         end
      end

      DV.SIM.JOKERS.x_mult_if_global(joker_obj, context)
   end,
   simulate_shortcut = function(joker_obj, context)
      -- Effect not relevant (Meta)
   end,
   simulate_hologram = function(joker_obj, context)
      DV.SIM.JOKERS.x_mult_if_global(joker_obj, context)
   end,
   simulate_vagabond = function(joker_obj, context)
      -- Effect might be relevant? (Consumable)
   end,
   simulate_baron = function(joker_obj, context)
      if context.cardarea == G.hand and context.individual then
         if DV.SIM.is_rank(context.other_card, 13) and not context.other_card.debuff then
            DV.SIM.x_mult(joker_obj.ability.extra)
         end
      end
   end,
   simulate_cloud_9 = function(joker_obj, context)
      -- Effect not relevant (End of Round)
   end,
   simulate_rocket = function(joker_obj, context)
      -- Effect not relevant (End of Round)
   end,
   simulate_obelisk = function(joker_obj, context)
      if context.cardarea == G.jokers and context.before and not context.blueprint then
         local reset = true
         local play_more_than = (G.GAME.hands[context.scoring_name].played or 0)
         for hand_name, hand in pairs(G.GAME.hands) do
            if hand_name ~= context.scoring_name and hand.played >= play_more_than and hand.visible then
               reset = false
            end
         end
         if reset then
            joker_obj.ability.x_mult = 1
         else
            joker_obj.ability.x_mult = joker_obj.ability.x_mult + joker_obj.ability.extra
         end
      end
      DV.SIM.JOKERS.x_mult_if_global(joker_obj, context)
   end,
   simulate_midas_mask = function(joker_obj, context)
      if context.cardarea == G.jokers and context.before and not context.blueprint then
         for _, card in ipairs(context.scoring_hand) do
            if DV.SIM.is_face(card) then
               DV.SIM.set_ability(card, G.P_CENTERS.m_gold)
            end
         end
      end
   end,
   simulate_luchador = function(joker_obj, context)
      -- Effect not relevant (Meta)
   end,
   simulate_photograph = function(joker_obj, context)
      if context.cardarea == G.play and context.individual then
         local first_face = nil
         for i = 1, #context.scoring_hand do
            if DV.SIM.is_face(context.scoring_hand[i]) then first_face = context.scoring_hand[i]; break end
         end
         if context.other_card == first_face and not context.other_card.debuff then
            DV.SIM.x_mult(joker_obj.ability.extra)
         end
      end
   end,
   simulate_gift = function(joker_obj, context)
      -- Effect not relevant (Meta)
   end,
   simulate_turtle_bean = function(joker_obj, context)
      -- Effect not relevant (Meta)
   end,
   simulate_erosion = function(joker_obj, context)
      if context.cardarea == G.jokers and context.global then
         DV.SIM.add_mult(joker_obj.ability.extra * (G.GAME.starting_deck_size - #G.playing_cards))
      end
   end,
   simulate_reserved_parking = function(joker_obj, context)
      if context.cardarea == G.hand and context.individual then
         if DV.SIM.is_face(context.other_card) and not context.other_card.debuff then
            local exact_dollars, min_dollars, max_dollars = DV.SIM.get_probabilistic_extremes(pseudorandom("parking"), joker_obj.ability.extra.odds, joker_obj.ability.extra.dollars, 0)
            DV.SIM.add_dollars(exact_dollars, min_dollars, max_dollars)
         end
      end
   end,
   simulate_mail = function(joker_obj, context)
      if context.cardarea == G.hand and context.discard then
         if context.other_card.id == G.GAME.current_round.mail_card.id and not context.other_card.debuff then
            DV.SIM.add_dollars(joker_obj.ability.extra)
         end
      end
   end,
   simulate_to_the_moon = function(joker_obj, context)
      -- Effect not relevant (End of Round)
   end,
   simulate_hallucination = function(joker_obj, context)
      -- Effect not relevant (Outside of Play)
   end,
   simulate_fortune_teller = function(joker_obj, context)
      if context.cardarea == G.jokers and context.global then
         if G.GAME.consumeable_usage_total and G.GAME.consumeable_usage_total.tarot then
            DV.SIM.add_mult(G.GAME.consumeable_usage_total.tarot)
         end
      end
   end,
   simulate_juggler = function(joker_obj, context)
      -- Effect not relevant (Meta)
   end,
   simulate_drunkard = function(joker_obj, context)
      -- Effect not relevant (Meta)
   end,
   simulate_stone = function(joker_obj, context)
      if context.cardarea == G.jokers and context.global then
         DV.SIM.add_chips(joker_obj.ability.extra * joker_obj.ability.stone_tally)
      end
   end,
   simulate_golden = function(joker_obj, context)
      -- Effect not relevant (End of Round)
   end,
   simulate_lucky_cat = function(joker_obj, context)
      if not joker_obj.ability.x_mult_range then
         joker_obj.ability.x_mult_range = {
            min = joker_obj.ability.x_mult,
            exact = joker_obj.ability.x_mult,
            max = joker_obj.ability.x_mult,
         }
      end

      if context.cardarea == G.play and context.individual and not context.blueprint then
         local function lucky_cat(field)
            if context.other_card.lucky_trigger and context.other_card.lucky_trigger[field] then
               joker_obj.ability.x_mult_range[field] = joker_obj.ability.x_mult_range[field] + joker_obj.ability.extra
               if joker_obj.ability.x_mult_range[field] < 1 then joker_obj.ability.x_mult_range[field] = 1 end -- Precaution
            end
         end
         lucky_cat("min")
         lucky_cat("exact")
         lucky_cat("max")
      end

      if context.cardarea == G.jokers and context.global then
         DV.SIM.x_mult(joker_obj.ability.x_mult_range.exact, joker_obj.ability.x_mult_range.min, joker_obj.ability.x_mult_range.max)
      end
   end,
   simulate_baseball = function(joker_obj, context)
      if context.cardarea == G.jokers and context.other_joker then
         if context.other_joker.rarity == 2 and context.other_joker ~= joker_obj then
            DV.SIM.x_mult(joker_obj.ability.extra)
         end
      end
   end,
   simulate_bull = function(joker_obj, context)
      if context.cardarea == G.jokers and context.global then
         local function bull(data)
            return joker_obj.ability.extra * math.max(0, G.GAME.dollars + data.dollars)
         end
         local min_chips = bull(DV.SIM.running.min)
         local exact_chips = bull(DV.SIM.running.exact)
         local max_chips = bull(DV.SIM.running.max)
         DV.SIM.add_chips(exact_chips, min_chips, max_chips)
      end
   end,
   simulate_diet_cola = function(joker_obj, context)
      -- Effect not relevant (Meta)
   end,
   simulate_trading = function(joker_obj, context)
      -- Effect not relevant (Discard)
   end,
   simulate_flash = function(joker_obj, context)
      if context.cardarea == G.jokers and context.global then
         DV.SIM.add_mult(joker_obj.ability.mult)
      end
   end,
   simulate_popcorn = function(joker_obj, context)
      if context.cardarea == G.jokers and context.global then
         DV.SIM.add_mult(joker_obj.ability.mult)
      end
   end,
   simulate_trousers = function(joker_obj, context)
      if context.cardarea == G.jokers and context.before and not context.blueprint then
         if (next(context.poker_hands["Two Pair"]) or next(context.poker_hands["Full House"])) then
            joker_obj.ability.mult = joker_obj.ability.mult + joker_obj.ability.extra
         end
      end
      if context.cardarea == G.jokers and context.global then
         DV.SIM.add_mult(joker_obj.ability.mult)
      end
   end,
   simulate_ancient = function(joker_obj, context)
      if context.cardarea == G.play and context.individual then
         if DV.SIM.is_suit(context.other_card, G.GAME.current_round.ancient_card.suit) and not context.other_card.debuff then
            DV.SIM.x_mult(joker_obj.ability.extra)
         end
      end
   end,
   simulate_ramen = function(joker_obj, context)
      if context.cardarea == G.hand and context.discard then
         joker_obj.ability.x_mult = math.max(1, joker_obj.ability.x_mult - joker_obj.ability.extra)
      end
      DV.SIM.JOKERS.x_mult_if_global(joker_obj, context)
   end,
   simulate_walkie_talkie = function(joker_obj, context)
      if context.cardarea == G.play and context.individual then
         if DV.SIM.is_rank(context.other_card, {10, 4}) and not context.other_card.debuff then
            DV.SIM.add_chips(joker_obj.ability.extra.chips)
            DV.SIM.add_mult(joker_obj.ability.extra.mult)
         end
      end
   end,
   simulate_selzer = function(joker_obj, context)
      if context.cardarea == G.play and context.repetition then
         DV.SIM.add_reps(1)
      end
   end,
   simulate_castle = function(joker_obj, context)
      if context.cardarea == G.hand and context.discard and not context.blueprint then
         if DV.SIM.is_suit(context.other_card, G.GAME.current_round.castle_card.suit) and not context.other_card.debuff then
            joker_obj.ability.extra.chips = joker_obj.ability.extra.chips + joker_obj.ability.extra.chip_mod
         end
      end
      if context.cardarea == G.jokers and context.global then
         DV.SIM.add_chips(joker_obj.ability.extra.chips)
      end
   end,
   simulate_smiley = function(joker_obj, context)
      if context.cardarea == G.play and context.individual then
         if DV.SIM.is_face(context.other_card) and not context.other_card.debuff then
            DV.SIM.add_mult(joker_obj.ability.extra)
         end
      end
   end,
   simulate_campfire = function(joker_obj, context)
      DV.SIM.JOKERS.x_mult_if_global(joker_obj, context)
   end,
   simulate_ticket = function(joker_obj, context)
      if context.cardarea == G.play and context.individual then
         if context.other_card.ability.effect == "Gold Card" and not context.other_card.debuff then
            DV.SIM.add_dollars(joker_obj.ability.extra)
         end
      end
   end,
   simulate_mr_bones = function(joker_obj, context)
      -- Effect not relevant (Meta)
   end,
   simulate_acrobat = function(joker_obj, context)
      if context.cardarea == G.jokers and context.global then
         if G.GAME.current_round.hands_left == 0 then
            DV.SIM.x_mult(joker_obj.ability.extra)
         end
      end
   end,
   simulate_sock_and_buskin = function(joker_obj, context)
      if context.cardarea == G.play and context.repetition then
         if DV.SIM.is_face(context.other_card) and not context.other_card.debuff then
            DV.SIM.add_reps(joker_obj.ability.extra)
         end
      end
   end,
   simulate_swashbuckler = function(joker_obj, context)
      if context.cardarea == G.jokers and context.global then
         DV.SIM.add_mult(joker_obj.ability.mult)
      end
   end,
   simulate_troubadour = function(joker_obj, context)
      -- Effect not relevant (Meta)
   end,
   simulate_certificate = function(joker_obj, context)
      -- Effect not relevant (Meta)
   end,
   simulate_smeared = function(joker_obj, context)
      -- Effect not relevant (Meta)
   end,
   simulate_throwback = function(joker_obj, context)
      DV.SIM.JOKERS.x_mult_if_global(joker_obj, context)
   end,
   simulate_hanging_chad = function(joker_obj, context)
      if context.cardarea == G.play and context.repetition then
         if context.other_card == context.scoring_hand[1] and not context.other_card.debuff then
            DV.SIM.add_reps(joker_obj.ability.extra)
         end
      end
   end,
   simulate_rough_gem = function(joker_obj, context)
      if context.cardarea == G.play and context.individual then
         if DV.SIM.is_suit(context.other_card, "Diamonds") and not context.other_card.debuff then
            DV.SIM.add_dollars(joker_obj.ability.extra)
         end
      end
   end,
   simulate_bloodstone = function(joker_obj, context)
      if context.cardarea == G.play and context.individual then
         if DV.SIM.is_suit(context.other_card, "Hearts") and not context.other_card.debuff then
            local exact_xmult, min_xmult, max_xmult = DV.SIM.get_probabilistic_extremes(pseudorandom("bloodstone"), joker_obj.ability.extra.odds, joker_obj.ability.extra.Xmult, 1)
            DV.SIM.x_mult(exact_xmult, min_xmult, max_xmult)
         end
      end
   end,
   simulate_arrowhead = function(joker_obj, context)
      if context.cardarea == G.play and context.individual then
         if DV.SIM.is_suit(context.other_card, "Spades") and not context.other_card.debuff then
            DV.SIM.add_chips(joker_obj.ability.extra)
         end
      end
   end,
   simulate_onyx_agate = function(joker_obj, context)
      if context.cardarea == G.play and context.individual then
         if DV.SIM.is_suit(context.other_card, "Clubs") and not context.other_card.debuff then
            DV.SIM.add_mult(joker_obj.ability.extra)
         end
      end
   end,
   simulate_glass = function(joker_obj, context)
      DV.SIM.JOKERS.x_mult_if_global(joker_obj, context)
   end,
   simulate_ring_master = function(joker_obj, context)
      -- Effect not relevant (Note: this is actually Showman)
   end,
   simulate_flower_pot = function(joker_obj, context)
      if context.cardarea == G.jokers and context.global then
         local suit_count = {
            ["Hearts"] = 0,
            ["Diamonds"] = 0,
            ["Spades"] = 0,
            ["Clubs"] = 0
         }

         function inc_suit(suit)
            suit_count[suit] = suit_count[suit] + 1
         end

         -- Account for all 'real' suits:
         for _, card in ipairs(context.scoring_hand) do
            if card.ability.effect ~= "Wild Card" then
               if     DV.SIM.is_suit(card, "Hearts", true)   and suit_count["Hearts"] == 0   then inc_suit("Hearts")
               elseif DV.SIM.is_suit(card, "Diamonds", true) and suit_count["Diamonds"] == 0 then inc_suit("Diamonds")
               elseif DV.SIM.is_suit(card, "Spades", true)   and suit_count["Spades"] == 0   then inc_suit("Spades")
               elseif DV.SIM.is_suit(card, "Clubs", true)    and suit_count["Clubs"] == 0    then inc_suit("Clubs")
               end
            end
         end

         -- Let Wild Cards fill in the gaps:
         for _, card in ipairs(context.scoring_hand) do
            if card.ability.effect == "Wild Card" then
               if     DV.SIM.is_suit(card, "Hearts")   and suit_count["Hearts"] == 0   then inc_suit("Hearts")
               elseif DV.SIM.is_suit(card, "Diamonds") and suit_count["Diamonds"] == 0 then inc_suit("Diamonds")
               elseif DV.SIM.is_suit(card, "Spades")   and suit_count["Spades"] == 0   then inc_suit("Spades")
               elseif DV.SIM.is_suit(card, "Clubs")    and suit_count["Clubs"] == 0    then inc_suit("Clubs")
               end
            end
         end

         if suit_count["Hearts"] > 0 and suit_count["Diamonds"] > 0 and suit_count["Spades"] > 0 and suit_count["Clubs"] > 0 then
            DV.SIM.x_mult(joker_obj.ability.extra)
         end
      end
   end,
   simulate_blueprint = function(joker_obj, context)
      local joker_to_mimic = nil
      for idx, joker in ipairs(DV.SIM.env.jokers) do
         if joker == joker_obj then joker_to_mimic = DV.SIM.env.jokers[idx+1] end
      end
      if joker_to_mimic then
         context.blueprint = (context.blueprint and (context.blueprint + 1)) or 1
         if context.blueprint > #DV.SIM.env.jokers + 1 then return end
         DV.SIM.simulate_joker(joker_to_mimic, context)
      end
   end,
   simulate_wee = function(joker_obj, context)
      if context.cardarea == G.play and context.individual and not context.blueprint then
         if DV.SIM.is_rank(context.other_card, 2) and not context.other_card.debuff then
            joker_obj.ability.extra.chips = joker_obj.ability.extra.chips + joker_obj.ability.extra.chip_mod
         end
      end
      if context.cardarea == G.jokers and context.global then
         DV.SIM.add_chips(joker_obj.ability.extra.chips)
      end
   end,
   simulate_merry_andy = function(joker_obj, context)
      -- Effect not relevant (Meta)
   end,
   simulate_oops = function(joker_obj, context)
      -- Effect not relevant (Meta)
   end,
   simulate_idol = function(joker_obj, context)
      if context.cardarea == G.play and context.individual then
         if DV.SIM.is_rank(context.other_card, G.GAME.current_round.idol_card.id) and
            DV.SIM.is_suit(context.other_card, G.GAME.current_round.idol_card.suit) and
            not context.other_card.debuff
         then
            DV.SIM.x_mult(joker_obj.ability.extra)
         end
      end
   end,
   simulate_seeing_double = function(joker_obj, context)
      if context.cardarea == G.jokers and context.global then
         local suit_count = {
            ["Hearts"] = 0,
            ["Diamonds"] = 0,
            ["Spades"] = 0,
            ["Clubs"] = 0
         }

         function inc_suit(suit)
            suit_count[suit] = suit_count[suit] + 1
         end

         -- Account for all 'real' suits:
         for _, card in ipairs(context.scoring_hand) do
            if card.ability.effect ~= "Wild Card" then
               if DV.SIM.is_suit(card, "Hearts")   then inc_suit("Hearts") end
               if DV.SIM.is_suit(card, "Diamonds") then inc_suit("Diamonds") end
               if DV.SIM.is_suit(card, "Spades")   then inc_suit("Spades") end
               if DV.SIM.is_suit(card, "Clubs")    then inc_suit("Clubs") end
            end
         end

         -- Let Wild Cards fill in the gaps:
         for _, card in ipairs(context.scoring_hand) do
            if card.ability.effect == "Wild Card" then
               if     DV.SIM.is_suit(card, "Hearts")   and suit_count["Hearts"] == 0   then inc_suit("Hearts")
               elseif DV.SIM.is_suit(card, "Diamonds") and suit_count["Diamonds"] == 0 then inc_suit("Diamonds")
               elseif DV.SIM.is_suit(card, "Spades")   and suit_count["Spades"] == 0   then inc_suit("Spades")
               elseif DV.SIM.is_suit(card, "Clubs")    and suit_count["Clubs"] == 0    then inc_suit("Clubs")
               end
            end
         end

         if suit_count["Clubs"] > 0 and (suit_count["Hearts"] > 0 or suit_count["Diamonds"] > 0 or suit_count["Spades"] > 0) then
            DV.SIM.x_mult(joker_obj.ability.extra)
         end
      end
   end,
   simulate_matador = function(joker_obj, context)
      if context.cardarea == G.jokers and context.debuffed_hand then
         if G.GAME.blind.triggered then
            DV.SIM.add_dollars(joker_obj.ability.extra)
         end
      end
   end,
   simulate_hit_the_road = function(joker_obj, context)
      if context.cardarea == G.hand and context.discard and not context.blueprint then
         if context.other_card.id == 11 and not context.other_card.debuff then
            joker_obj.ability.x_mult = joker_obj.ability.x_mult + joker_obj.ability.extra
         end
      end
      DV.SIM.JOKERS.x_mult_if_global(joker_obj, context)
   end,
   simulate_duo = function(joker_obj, context)
      DV.SIM.JOKERS.x_mult_if_global(joker_obj, context)
   end,
   simulate_trio = function(joker_obj, context)
      DV.SIM.JOKERS.x_mult_if_global(joker_obj, context)
   end,
   simulate_family = function(joker_obj, context)
      DV.SIM.JOKERS.x_mult_if_global(joker_obj, context)
   end,
   simulate_order = function(joker_obj, context)
      DV.SIM.JOKERS.x_mult_if_global(joker_obj, context)
   end,
   simulate_tribe = function(joker_obj, context)
      DV.SIM.JOKERS.x_mult_if_global(joker_obj, context)
   end,
   simulate_stuntman = function(joker_obj, context)
      if context.cardarea == G.jokers and context.global then
         DV.SIM.add_chips(joker_obj.ability.extra.chip_mod)
      end
   end,
   simulate_invisible = function(joker_obj, context)
      -- Effect not relevant (Meta)
   end,
   simulate_brainstorm = function(joker_obj, context)
      local joker_to_mimic = DV.SIM.env.jokers[1]
      if joker_to_mimic and joker_to_mimic ~= joker_obj then
         context.blueprint = (context.blueprint and (context.blueprint + 1)) or 1
         if context.blueprint > #DV.SIM.env.jokers + 1 then return end
         DV.SIM.simulate_joker(joker_to_mimic, context)
      end
   end,
   simulate_satellite = function(joker_obj, context)
      -- Effect not relevant (End of Round)
   end,
   simulate_shoot_the_moon = function(joker_obj, context)
      if context.cardarea == G.hand and context.individual then
         if DV.SIM.is_rank(context.other_card, 12) and not context.other_card.debuff then
            DV.SIM.add_mult(13)
         end
      end
   end,
   simulate_drivers_license = function(joker_obj, context)
      if context.cardarea == G.jokers and context.global then
         if (joker_obj.ability.driver_tally or 0) >= 16 then
            DV.SIM.x_mult(joker_obj.ability.extra)
         end
      end
   end,
   simulate_cartomancer = function(joker_obj, context)
      -- Effect not relevant (Blind)
   end,
   simulate_astronomer = function(joker_obj, context)
      -- Effect not relevant (Meta)
   end,
   simulate_burnt = function(joker_obj, context)
      -- Effect not relevant (Discard)
   end,
   simulate_bootstraps = function(joker_obj, context)
      if context.cardarea == G.jokers and context.global then
         local function bootstraps(data)
            return joker_obj.ability.extra.mult * math.floor((G.GAME.dollars + data.dollars) / joker_obj.ability.extra.dollars)
         end
         local min_mult = bootstraps(DV.SIM.running.min)
         local exact_mult = bootstraps(DV.SIM.running.exact)
         local max_mult = bootstraps(DV.SIM.running.max)
         DV.SIM.add_mult(exact_mult, min_mult, max_mult)
      end
   end,
   simulate_caino = function(joker_obj, context)
      if context.cardarea == G.jokers and context.global then
         if joker_obj.ability.caino_xmult > 1 then
            DV.SIM.x_mult(joker_obj.ability.caino_xmult)
         end
      end
   end,
   simulate_triboulet = function(joker_obj, context)
      if context.cardarea == G.play and context.individual then
         if DV.SIM.is_rank(context.other_card, {12, 13}) and
            not context.other_card.debuff
         then
            DV.SIM.x_mult(joker_obj.ability.extra)
         end
      end
   end,
   simulate_yorick = function(joker_obj, context)
      if context.cardarea == G.hand and context.discard and not context.blueprint then
         -- This is only necessary for 'The Hook' blind.
         if joker_obj.ability.yorick_discards > 1 then
            joker_obj.ability.yorick_discards = joker_obj.ability.yorick_discards - 1
         else
            joker_obj.ability.yorick_discards = joker_obj.ability.extra.discards
            joker_obj.ability.x_mult = joker_obj.ability.x_mult + joker_obj.ability.extra.xmult
         end
      end

      DV.SIM.JOKERS.x_mult_if_global(joker_obj, context)
   end,
   simulate_chicot = function(joker_obj, context)
      -- Effect not relevant (Meta)
   end,
   simulate_perkeo = function(joker_obj, context)
      -- Effect not relevant (Blind)
   end,
}

--
-- UTILITIES:
--

function DV.SIM.JOKERS.add_suit_mult(joker_obj, context)
   if context.cardarea == G.play and context.individual then
      if DV.SIM.is_suit(context.other_card, joker_obj.ability.extra.suit) and not context.other_card.debuff then
         DV.SIM.add_mult(joker_obj.ability.extra.s_mult)
      end
   end
end

function DV.SIM.JOKERS.add_type_mult(joker_obj, context)
   if context.cardarea == G.jokers and context.global
      and next(context.poker_hands[joker_obj.ability.type])
   then
      DV.SIM.add_mult(joker_obj.ability.t_mult)
   end
end

function DV.SIM.JOKERS.add_type_chips(joker_obj, context)
   if context.cardarea == G.jokers and context.global
      and next(context.poker_hands[joker_obj.ability.type])
   then
      DV.SIM.add_chips(joker_obj.ability.t_chips)
   end
end

function DV.SIM.JOKERS.x_mult_if_global(joker_obj, context)
   if context.cardarea == G.jokers and context.global then
      if joker_obj.ability.x_mult > 1 and
         (joker_obj.ability.type == "" or next(context.poker_hands[joker_obj.ability.type])) then
         DV.SIM.x_mult(joker_obj.ability.x_mult)
      end
   end
end

function DV.SIM.get_probabilistic_extremes(random_value, odds, reward, default)
   -- Exact mirrors the game's probability calculation
   local exact = default
   if random_value < G.GAME.probabilities.normal/odds then
      exact = reward
   end

   -- Minimum is default unless probability is guaranteed (eg. 2 in 2 chance)
   local min = default
   if G.GAME.probabilities.normal >= odds then
      min = reward
   end

   -- Maximum is always reward (probability is always > 0); redundant variable is for readability
   local max = reward

   return exact, min, max
end

function DV.SIM.adjust_field_with_range(adj_func, field, mod_func, exact_value, min_value, max_value)
   if not exact_value then error("Cannot adjust field, exact_value is missing.") end

   if not min_value or not max_value then
      min_value = exact_value
      max_value = exact_value
   end

   DV.SIM.running.min[field]   = mod_func(adj_func(DV.SIM.running.min[field],   min_value))
   DV.SIM.running.exact[field] = mod_func(adj_func(DV.SIM.running.exact[field], exact_value))
   DV.SIM.running.max[field]   = mod_func(adj_func(DV.SIM.running.max[field],   max_value))
end

function DV.SIM.add_chips(exact, min, max)
   DV.SIM.adjust_field_with_range(function(x, y) return x + y end, "chips", mod_chips, exact, min, max)
end

function DV.SIM.add_mult(exact, min, max)
   DV.SIM.adjust_field_with_range(function(x, y) return x + y end, "mult", mod_mult, exact, min, max)
end

function DV.SIM.x_mult(exact, min, max)
   DV.SIM.adjust_field_with_range(function(x, y) return x * y end, "mult", mod_mult, exact, min, max)
end

function DV.SIM.add_dollars(exact, min, max)
   -- NOTE: no mod_func for dollars, so have to declare an identity function
   DV.SIM.adjust_field_with_range(function(x, y) return x + y end, "dollars", function(x) return x end, exact, min, max)
end

function DV.SIM.add_reps(n)
   DV.SIM.running.reps = DV.SIM.running.reps + n
end

--
-- MISC:
--

function DV.SIM.is_suit(card_data, suit, ignore_debuff)
   if card_data.debuff and not ignore_debuff then return end
   if card_data.ability.effect == "Stone Card" then
      return false
   end
   if card_data.ability.effect == "Wild Card" then
      return true
   end
   if next(find_joker("Smeared Joker")) then
      local is_card_suit_light  = (card_data.suit == "Hearts" or card_data.suit == "Diamonds")
      local is_check_suit_light = (suit == "Hearts"           or suit == "Diamonds")
      if is_card_suit_light == is_check_suit_light then return true end
   end
   return card_data.suit == suit
end

function DV.SIM.get_rank(card_data)
   if card_data.ability.effect == "Stone Card" and not card_data.vampired then
      DV.SIM.misc.next_stone_id = DV.SIM.misc.next_stone_id - 1
      return DV.SIM.misc.next_stone_id
   end
   return card_data.rank
end

function DV.SIM.is_rank(card_data, ranks)
   if card_data.ability.effect == "Stone Card" then return false end

   if type(ranks) == "number" then ranks = {ranks} end
   for _, r in ipairs(ranks) do
      if card_data.rank == r then return true end
   end
   return false
end

function DV.SIM.check_rank_parity(card_data, check_even)
   if check_even then
      local is_even_numbered = (card_data.rank <= 10 and card_data.rank >= 0 and card_data.rank % 2 == 0)
      return is_even_numbered
   else
      local is_odd_numbered  = (card_data.rank <= 10 and card_data.rank >= 0 and card_data.rank % 2 == 1)
      local is_ace = (card_data.rank == 14)
      return (is_odd_numbered or is_ace)
   end
end

function DV.SIM.is_face(card_data)
   return (DV.SIM.is_rank(card_data, {11, 12, 13}) or next(find_joker("Pareidolia")))
end

function DV.SIM.set_ability(card_data, center)
   -- See Card:set_ability()
   card_data.ability = {
      name = center.name,
      effect = center.effect,
      set = center.set,
      mult = center.config.mult or 0,
      h_mult = center.config.h_mult or 0,
      h_x_mult = center.config.h_x_mult or 0,
      h_dollars = center.config.h_dollars or 0,
      p_dollars = center.config.p_dollars or 0,
      t_mult = center.config.t_mult or 0,
      t_chips = center.config.t_chips or 0,
      x_mult = center.config.Xmult or 1,
      h_size = center.config.h_size or 0,
      d_size = center.config.d_size or 0,
      extra = copy_table(center.config.extra) or nil,
      extra_value = 0,
      type = center.config.type or '',
      order = center.order or nil,
      forced_selection = card_data.ability and card_data.ability.forced_selection or nil,
      perma_bonus = card_data.ability and card_data.ability.perma_bonus or 0,
      bonus = (card_data.ability.bonus or 0) + (center.config.bonus or 0)
   }
end

function DV.SIM.set_edition(card_data, edition)
   card_data.edition = nil
   if not edition then return end

   if edition.holo then
      if not card_data.edition then card_data.edition = {} end
      card_data.edition.mult = G.P_CENTERS.e_holo.config.extra
      card_data.edition.holo = true
      card_data.edition.type = 'holo'
   elseif edition.foil then
      if not card_data.edition then card_data.edition = {} end
      card_data.edition.chips = G.P_CENTERS.e_foil.config.extra
      card_data.edition.foil = true
      card_data.edition.type = 'foil'
   elseif edition.polychrome then
      if not card_data.edition then card_data.edition = {} end
      card_data.edition.x_mult = G.P_CENTERS.e_polychrome.config.extra
      card_data.edition.polychrome = true
      card_data.edition.type = 'polychrome'
   elseif edition.negative then
      -- TODO
   end
end
