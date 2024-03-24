--- STEAMODDED HEADER
--- MOD_NAME: Divvy's Simulation
--- MOD_ID: dvsimulate
--- MOD_AUTHOR: [Divvy C.]
--- MOD_DESCRIPTION: A utility mod to simulate selected hand.

if not DV then DV = {} end

DV.SIM = {
   -- Table for saving and restoring game state:
   ORIG = {},
   -- Any joker names in the following array will be ignored by the simulation:
   IGNORED = {--[["Vagabond"]]}
}

--
-- MAIN FUNCTION:
--

-- Run a simulation.
--   played_cards: an array of Card objects that should be played
--   held_cards:   an array of Card objects that should be held in hand (excl. played cards)
--   jokers:       an array of joker Card objects that should be active
--
-- NOTE: this simulation assumes only vanilla jokers are used,
--       modded jokers should still work but there will likely be side-effects,
--       especially if they create/destroy/modify consumables or the deck.
function DV.SIM.run(played_cards, held_cards, jokers, deck)
   if #played_cards == 0 then return 0 end

   local play_to_simulate = DV.deep_copy(played_cards)
   DV.SIM.set_parameters(play_to_simulate)
   DV.SIM.save_state(played_cards, held_cards, jokers, deck)

   -- Account for any forced changes before evaluation even begins:
   -- Refer to G.FUNCS.play_cards_from_highlighted(); must simulate the whole sequence of events.
   DV.SIM.prep_before_play()

   -- Run evaluation if hand is not debuffed:
   -- The last argument to debuff_hand() signifies that it is a CHECK, and doesn't update effects!
   if not G.GAME.blind:debuff_hand(DV.SIM.data.played_cards, DV.SIM.data.poker_hands, DV.SIM.data.scoring_name, true) then
      -- 0. Effects from JOKERS that will run BEFORE evaluation (eg. levelling Spare Trousers):
      DV.SIM.eval_before_effects()
      -- 1. Set mult and chips to base hand values:
      DV.SIM.init_chips_mult()
      -- 1. Effects from BLIND:
      DV.SIM.eval_blind_effect()
      -- 2. Effects from SCORING CARDS (in played hand), and per-card joker effects:
      DV.SIM.eval_scoring_hand()
      -- 3. Effects from CARDS HELD IN HAND, and per-held-card joker effects:
      DV.SIM.eval_inhand_effects()
      -- 4. Effects from JOKERS (global, not per-card):
      DV.SIM.eval_joker_effects()
      -- 5. Effects from DECK:
      DV.SIM.eval_deck_effect()
   end

   DV.SIM.restore_state()

   return math.floor(DV.SIM.chips * DV.SIM.mult) or 0
end

--
-- CORE FUNCTIONS:
--

function DV.SIM.eval_scoring_hand()
   for _, scoring_card in ipairs(DV.SIM.data.scoring_hand) do
      if not scoring_card.debuff then
         local reps = {1}

         -- Collect repetitions from red seals:
         local eval = eval_card(scoring_card, DV.SIM.get_context(G.play, {repetition = true, repetition_only = true}))
         if next(eval) then
            for h = 1, eval.seals.repetitions do
               reps[#reps+1] = eval
            end
         end

         -- Collect repetitions from jokers:
         for _, joker in ipairs(G.jokers.cards) do
            local eval = eval_card(joker, DV.SIM.get_context(G.play, {other_card = scoring_card, repetition = true}))
            if next(eval) and eval.jokers then
               for h = 1, eval.jokers.repetitions do
                  reps[#reps+1] = eval
               end
            end
         end

         -- Evaluate and apply effects of jokers on played cards:
         for j=1, #reps do
            -- Evaluation:
            local context = {cardarea = G.play, full_hand = DV.SIM.data.played_cards, scoring_hand = DV.SIM.data.scoring_hand, poker_hand = DV.SIM.data.scoring_name}
            local effects = {eval_card(scoring_card, context)}
            for _, joker in ipairs(G.jokers.cards) do
               local eval = joker:calculate_joker(DV.SIM.get_context(G.play, {other_card = scoring_card, individual = true}))
               if eval then table.insert(effects, eval) end
            end
            scoring_card.lucky_trigger = nil

            -- Application:
            for _, effect in ipairs(effects) do
               if effect.chips then DV.SIM.add_chips(effect.chips) end
               if effect.mult then DV.SIM.add_mult(effect.mult) end

               if effect.extra then
                  if effect.extra.mult_mod then DV.SIM.add_mult(effect.extra.mult_mod) end
                  if effect.extra.chip_mod then DV.SIM.add_chips(effect.extra.chip_mod) end
                  if effect.extra.swap then
                     local old_mult = DV.SIM.mult
                     DV.SIM.mult = mod_mult(DV.SIM.chips)
                     DV.SIM.chips = mod_chips(old_mult)
                  end
               end

               if effect.x_mult then DV.SIM.x_mult(effect.x_mult) end

               if effect.edition then
                  DV.SIM.add_chips(effect.edition.chip_mod or 0)
                  DV.SIM.add_mult(effect.edition.mult_mod or 0)
                  DV.SIM.x_mult(effect.edition.x_mult_mod or 1)
               end
            end
         end
      end
   end
end

function DV.SIM.eval_inhand_effects()
   for _, held_card in ipairs(G.hand.cards) do
      local reps = {1}
      local j = 1
      while j <= #reps do
         local effects = {eval_card(held_card, DV.SIM.get_context(G.hand, {}))}

         -- Collect effects on this card from current jokers:
         for _, joker in ipairs(G.jokers.cards) do
            local eval = joker:calculate_joker(DV.SIM.get_context(G.hand, {other_card = held_card, individual = true}))
            if eval then table.insert(effects, eval) end
         end

         -- Collect repetitions:
         if reps[j] == 1 then
            -- Collect repetitions from red seal (in-hand):
            local eval = eval_card(held_card, DV.SIM.get_context(G.hand, {repetition = true, repetition_only = true, card_effects = effects}))
            if next(eval) and (next(effects[1]) or #effects > 1) then
               for h = 1, eval.seals.repetitions do
                  reps[#reps+1] = eval
               end
            end

            -- Collect repetitions from jokers (in-hand):
            for _, joker in ipairs(G.jokers.cards) do
               local eval = eval_card(joker, DV.SIM.get_context(G.hand, {other_card = held_card, repetition = true, card_effects = effects}))
               if next(eval) then
                  for h = 1, eval.jokers.repetitions do
                     reps[#reps+1] = eval
                  end
               end
            end
         end

         -- Apply the effects:
         for _, effect in ipairs(effects) do
            if effect.h_mult then DV.SIM.add_mult(effect.h_mult) end
            if effect.x_mult then DV.SIM.x_mult(effect.x_mult) end
         end
         j = j + 1
      end
   end
end

function DV.SIM.eval_joker_effects()
   for i=1, #G.jokers.cards + #G.consumeables.cards do
      local _card = G.jokers.cards[i] or G.consumeables.cards[i - #G.jokers.cards]

      -- Apply EDITION EFFECTS of current jokers (ie. foil, holographic):
      local edition_effects = eval_card(_card, DV.SIM.get_context(G.jokers, {edition = true}))
      if edition_effects.jokers then
         edition_effects.jokers.edition = true
         if edition_effects.jokers.chip_mod then DV.SIM.add_chips(edition_effects.jokers.chip_mod) end
         if edition_effects.jokers.mult_mod then DV.SIM.add_mult(edition_effects.jokers.mult_mod) end
      end

      -- Evaluate overarching effects of current jokers (not tied to individual cards):
      local effects = eval_card(_card, DV.SIM.get_context(G.jokers, {joker_main = true}))
      if effects.jokers then
         if effects.jokers.chip_mod then DV.SIM.add_chips(effects.jokers.chip_mod) end
         if effects.jokers.mult_mod then DV.SIM.add_mult(effects.jokers.mult_mod) end
         if effects.jokers.Xmult_mod then DV.SIM.x_mult(effects.jokers.Xmult_mod) end
      end

      -- Evaluate joker-on-joker effects of current jokers:
      for _, joker in ipairs(G.jokers.cards) do
		 local effect = joker:calculate_joker({full_hand = DV.SIM.data.played_cards, scoring_hand = DV.SIM.data.scoring_hand, scoring_name = DV.SIM.data.scoring_name, poker_hands = DV.SIM.data.poker_hands, other_joker = _card})
         if effect then
            if effect.chip_mod then DV.SIM.add_chips(effect.chip_mod) end
            if effect.mult_mod then DV.SIM.add_mult(effect.mult_mod) end
            if effect.Xmult_mod then DV.SIM.x_mult(effect.Xmult_mod) end
         end
      end

      -- (Continued) Apply EDITION EFFECTS of current jokers (ie. polychrome):
      if edition_effects.jokers and edition_effects.jokers.x_mult_mod then
         DV.SIM.x_mult(edition_effects.jokers.x_mult_mod)
      end
   end
end

function DV.SIM.eval_deck_effect()
   if G.GAME.selected_back.name == 'Plasma Deck' then
      -- Just avoiding animations here
      local sum = DV.SIM.mult + DV.SIM.chips
      DV.SIM.mult, DV.SIM.chips = mod_mult(math.floor(sum/2)), mod_mult(math.floor(sum/2))
   else
      local nu_chip, nu_mult = G.GAME.selected_back:trigger_effect{context = 'final_scoring_step', chips = DV.SIM.chips, mult = DV.SIM.mult}
      DV.SIM.mult, DV.SIM.chips = mod_mult(nu_mult or DV.SIM.mult), mod_chips(nu_chip or DV.SIM.chips)
   end
end

function DV.SIM.eval_blind_effect()
   local nu_mult, nu_chips, _ = G.GAME.blind:modify_hand(DV.SIM.data.played_cards, DV.SIM.data.poker_hands, DV.SIM.data.scoring_name, DV.SIM.mult, DV.SIM.chips)
   DV.SIM.mult, DV.SIM.chips = mod_mult(nu_mult), mod_chips(nu_chips)
end

function DV.SIM.eval_before_effects()
   for _, joker in ipairs(G.jokers.cards) do
      eval_card(joker, DV.SIM.get_context(G.jokers, {before = true}))
   end
end

function DV.SIM.prep_before_play()
   local hand_info = G.GAME.hands[DV.SIM.data.scoring_name]
   hand_info.played = hand_info.played + 1
   hand_info.played_this_round = hand_info.played_this_round + 1

   G.GAME.current_round.hands_left = G.GAME.current_round.hands_left - 1

   if G.GAME.blind.name == "The Hook" then
      for i = 1, math.min(2, #G.hand.cards) do
         local selected_card, card_key = pseudorandom_element(G.hand.cards, pseudoseed('hook'))
         table.remove(G.hand.cards, card_key)
      end
   end
end

function DV.SIM.init_chips_mult()
   local hand_info = G.GAME.hands[DV.SIM.data.scoring_name]
   if G.GAME.blind.name == "The Arm" then
      -- Account for -1 level:
      DV.SIM.mult = mod_mult(math.max(1, hand_info.mult - hand_info.l_mult))
      DV.SIM.chips = mod_chips(math.max(0, hand_info.chips - hand_info.l_chips))
   else
      -- Default:
      DV.SIM.mult = mod_mult(hand_info.mult)
      DV.SIM.chips = mod_chips(hand_info.chips)
   end
end

function DV.SIM.get_scoring_hand(played_cards, scoring_hand)
   local pures = {}
   for i=1, #played_cards do
      if next(find_joker('Splash')) then
         scoring_hand[i] = played_cards[i]
      else
         if played_cards[i].ability.effect == 'Stone Card' then
            local inside = false
            for j=1, #scoring_hand do
               if scoring_hand[j] == played_cards[i] then
                  inside = true
               end
            end
            if not inside then table.insert(pures, played_cards[i]) end
         end
      end
   end
   for i=1, #pures do
      table.insert(scoring_hand, pures[i])
   end

   table.sort(scoring_hand, function (a, b) return a.T.x < b.T.x end )
   return scoring_hand
end

function DV.SIM.set_parameters(played_cards)
   local hand_name, _, poker_hands, scoring_hand, _ = G.FUNCS.get_poker_hand_info(played_cards)

   DV.SIM.chips = mod_chips(0)
   DV.SIM.mult = mod_mult(0)

   DV.SIM.data = {
      played_cards = played_cards,
      scoring_name = hand_name,
      scoring_hand = DV.SIM.get_scoring_hand(played_cards, scoring_hand),
      poker_hands = poker_hands,
   }

   DV.SIM.get_context = function(cardarea, args)
      local context = {
         cardarea = cardarea,
         full_hand = DV.SIM.data.played_cards,
         scoring_name = DV.SIM.data.scoring_name,
         scoring_hand = DV.SIM.data.scoring_hand,
         poker_hands = DV.SIM.data.poker_hands
      }

      for k, v in pairs(args) do
         context[k] = v
      end

      return context
   end
end

function DV.SIM.save_state(played_cards, held_cards, jokers, deck)
   local DVSO = DV.SIM.ORIG

   DVSO.hand = G.hand.cards
   G.hand.cards = DV.deep_copy(held_cards)

   DVSO.jokers = G.jokers.cards
   G.jokers.cards = DV.deep_copy(jokers)

   DVSO.deck = G.deck
   G.deck = DV.deep_copy(deck)

   DVSO.rand = G.GAME.pseudorandom
   G.GAME.pseudorandom = DV.deep_copy(G.GAME.pseudorandom)

   DVSO.dollars = G.GAME.dollars

   local hand_info = G.GAME.hands[DV.SIM.data.scoring_name]
   DVSO.hands_played = hand_info.played
   DVSO.hands_played_round = hand_info.played_this_round

   DVSO.hands_left = G.GAME.current_round.hands_left

   -- Prevent consumeables from being created:
   G.GAME.consumeable_buffer = math.huge
end

function DV.SIM.restore_state()
   local DVSO = DV.SIM.ORIG
   G.hand.cards = DVSO.hand
   G.jokers.cards = DVSO.jokers
   G.deck = DVSO.deck
   G.GAME.pseudorandom = DVSO.rand
   G.GAME.dollars = DVSO.dollars
   local hand_name = DV.SIM.data.scoring_name
   G.GAME.hands[hand_name].played = DVSO.hands_played
   G.GAME.hands[hand_name].played_this_round = DVSO.hands_played_round
   G.GAME.current_round.hands_left = DVSO.hands_left

   -- Any bugs with consumable-creation might be solved by placing this in an after-event:
   G.GAME.consumeable_buffer = 0
end

function DV.SIM.add_chips(chips)
   DV.SIM.chips = mod_chips(DV.SIM.chips + chips)
end

function DV.SIM.add_mult(mult)
   DV.SIM.mult = mod_mult(DV.SIM.mult + mult)
end

function DV.SIM.x_mult(x)
   DV.SIM.mult = mod_mult(DV.SIM.mult * x)
end

--
-- CARD EVALUATION ADVICE:
--

local orig_eval_card = eval_card
function eval_card(card, context)
   -- Breaks with joker-on-joker effects:
   -- if (card.ability.set == "Joker") and DV.contains(card.ability.name, DV.SIM.IGNORED) then
   -- 	  return {}
   -- end
   return orig_eval_card(card, context)
end

local orig_eval_joker = Card.calculate_joker
function Card:calculate_joker(context)
   -- Breaks with joker-on-joker effects:
   -- if DV.contains(self.ability.name, DV.SIM.IGNORED) then
   -- 	  return {}
   -- end
   return orig_eval_joker(self, context)
end

--
-- MISC:
--

-- Recursively copies table contents by value:
function DV.deep_copy(obj, seen)
  if type(obj) ~= 'table' then return obj end
  if seen and seen[obj] then return seen[obj] end
  local s = seen or {}
  local res = setmetatable({}, getmetatable(obj))
  s[obj] = res
  for k, v in pairs(obj) do res[DV.deep_copy(k, s)] = DV.deep_copy(v, s) end
  return res
end

-- Checks whether x is in arr:
function DV.contains(x, arr)
   for _, a in ipairs(arr) do
      if x == a then
         return true
      end
   end
   return false
end
