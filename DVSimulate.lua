--- STEAMODDED HEADER
--- MOD_NAME: Divvy's Simulation
--- MOD_ID: dvsimulate
--- MOD_AUTHOR: [Divvy C.]
--- MOD_DESCRIPTION: A utility mod to simulate selected hand.

if not DV then DV = {} end
if not DV.SIM then DV.SIM = {} end

-- These jokers have side-effects that should not be simulated:
-- Some of these also provide a range of values (eg. Misprint), so they are also ignored to simulate worst case scenario.
DV.SIM.IGNORED = {"Misprint", "Bloodstone", "8 Ball", "DNA", "Sixth Sense", "Seance", "Vagabond", "Midas Mask", "Burnt Joker"}

-- Run simulation:
-- Returns total score from currently selected hand.
function DV.SIM.simulate()
   if #G.hand.highlighted == 0 then return 0 end

   local real_jokers = G.jokers.cards
   G.jokers.cards = DV.deep_copy(G.jokers.cards)

   local real_hand = G.hand.cards
   G.hand.cards = DV.SIM.get_unhighlighted_cards()

   local play_to_simulate = DV.deep_copy(G.hand.highlighted)
   DV.SIM.set_parameters(play_to_simulate)

   -- Run evaluation if hand is not debuffed:
   if not G.GAME.blind:debuff_hand(DV.SIM.data.played_cards, DV.SIM.data.poker_hands, DV.SIM.data.scoring_name) then
      -- Set mult and chips to base hand values (with level):
      local hand_info = G.GAME.hands[DV.SIM.data.scoring_name]
      DV.SIM.mult = mod_mult(hand_info.mult)
      DV.SIM.chips = mod_chips(hand_info.chips)
      -- 1. Blind:
      DV.SIM.eval_blind_effect()
      -- 2. Scoring cards in played hand, and per-card joker effects:
      DV.SIM.eval_scoring_hand()
      -- 3. Cards held in hand, and per-held-card joker effects:
      DV.SIM.eval_inhand_effects()
      -- 4. Global joker effects:
      DV.SIM.eval_joker_effects()
      -- 5. Deck:
      DV.SIM.eval_deck_effect()
   end

   G.jokers.cards = real_jokers
   G.hand.cards = real_hand

   return math.floor(DV.SIM.chips * DV.SIM.mult) or 0
end

--
-- CORE:
--

function DV.SIM.eval_scoring_hand()
   for _, scoring_card in ipairs(DV.SIM.data.scoring_hand) do
      if not scoring_card.debuff then
         local reps = {1}

         -- Collect repetitions from red seals:
         local eval = DV.SIM.eval_card(scoring_card, DV.SIM.get_context(G.play, {repetition = true, repetition_only = true}))
         if next(eval) then
            for h = 1, eval.seals.repetitions do
               reps[#reps+1] = eval
            end
         end

         -- Collect repetitions from jokers:
         for _, joker in ipairs(G.jokers.cards) do
            local eval = DV.SIM.eval_card(joker, DV.SIM.get_context(G.play, {other_card = scoring_card, repetition = true}))
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
            local effects = {DV.SIM.eval_card(scoring_card, context)}
            for _, joker in ipairs(G.jokers.cards) do
               local eval = DV.SIM.eval_joker(joker, DV.SIM.get_context(G.play, {other_card = scoring_card, individual = true}))
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
         local effects = {DV.SIM.eval_card(held_card, DV.SIM.get_context(G.hand, {}))}

         -- Collect effects on this card from current jokers:
         for _, joker in ipairs(G.jokers.cards) do
            local eval = DV.SIM.eval_joker(joker, DV.SIM.get_context(G.hand, {other_card = held_card, individual = true}))
            if eval then table.insert(effects, eval) end
         end

         -- Collect repetitions:
         if reps[j] == 1 then
            -- Collect repetitions from red seal (in-hand):
            local eval = DV.SIM.eval_card(held_card, DV.SIM.get_context(G.hand, {repetition = true, repetition_only = true, card_effects = effects}))
            if next(eval) and (next(effects[1]) or #effects > 1) then
               for h = 1, eval.seals.repetitions do
                  reps[#reps+1] = eval
               end
            end

            -- Collect repetitions from jokers (in-hand):
            for _, joker in ipairs(G.jokers.cards) do
               local eval = DV.SIM.eval_card(joker, DV.SIM.get_context(G.hand, {other_card = held_card, repetition = true, card_effects = effects}))
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
      local edition_effects = DV.SIM.eval_card(_card, DV.SIM.get_context(G.jokers, {edition = true}))
      if edition_effects.jokers then
         edition_effects.jokers.edition = true
         if edition_effects.jokers.chip_mod then DV.SIM.add_chips(edition_effects.jokers.chip_mod) end
         if edition_effects.jokers.mult_mod then DV.SIM.add_mult(edition_effects.jokers.mult_mod) end
      end

      -- Evaluate overarching effects of current jokers (not tied to individual cards):
      local effects = DV.SIM.eval_card(_card, DV.SIM.get_context(G.jokers, {joker_main = true}))
      if effects.jokers then
         if effects.jokers.chip_mod then DV.SIM.add_chips(effects.jokers.chip_mod) end
         if effects.jokers.mult_mod then DV.SIM.add_mult(effects.jokers.mult_mod) end
         if effects.jokers.Xmult_mod then DV.SIM.x_mult(effects.jokers.Xmult_mod) end
      end

      -- Evaluate joker-on-joker effects of current jokers:
      for _, joker in ipairs(G.jokers.cards) do
         local effect = joker:calculate_joker{full_hand = DV.SIM.data.played_cards, scoring_hand = DV.SIM.data.scoring_hand, scoring_name = DV.SIM.data.scoring_name, poker_hands = DV.SIM.data.poker_hands, other_joker = _card}
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
   local nu_chip, nu_mult = G.GAME.selected_back:trigger_effect{context = 'final_scoring_step', chips = DV.SIM.chips, mult = DV.SIM.mult}
   DV.SIM.mult, DV.SIM.chips = mod_mult(nu_mult or DV.SIM.mult), mod_chips(nu_chip or DV.SIM.chips)
end

function DV.SIM.eval_blind_effect()
   local nu_mult, nu_chips, _ = G.GAME.blind:modify_hand(DV.SIM.data.played_cards, DV.SIM.data.poker_hands, DV.SIM.data.scoring_name, DV.SIM.mult, DV.SIM.chips)
   DV.SIM.mult, DV.SIM.chips = mod_mult(nu_mult), mod_chips(nu_chips)
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

function DV.SIM.get_unhighlighted_cards()
   local sim_hand = {}
   for _, sim_card in ipairs(DV.deep_copy(G.hand.cards)) do
      if not sim_card.highlighted then
         table.insert(sim_hand, sim_card)
      end
   end
   return sim_hand
end

function DV.SIM.set_parameters(played_cards)
   local text, _, poker_hands, scoring_hand, _ = G.FUNCS.get_poker_hand_info(played_cards)

   DV.SIM.chips = mod_chips(0)
   DV.SIM.mult = mod_mult(0)

   DV.SIM.data = {
      played_cards = played_cards,
      scoring_name = text,
      scoring_hand = DV.SIM.get_scoring_hand(played_cards, scoring_hand),
      poker_hands = poker_hands,
   }

   DV.SIM.get_context = function(cardarea, args)
      local context = {
         cardarea = cardarea,
         full_hand = DV.SIM.played_cards,
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

function DV.SIM.add_chips(chips)
   DV.SIM.chips = mod_chips(DV.SIM.chips + chips)
end

function DV.SIM.add_mult(mult)
   DV.SIM.mult = mod_mult(DV.SIM.mult + mult)
end

function DV.SIM.x_mult(x)
   DV.SIM.mult = mod_mult(DV.SIM.mult * x)
end

-- Evaluates all cards except IGNORED jokers:
function DV.SIM.eval_card(card, context)
   if (card.ability.set == "Joker") and DV.contains(card.ability.name, DV.SIM.IGNORED) then
      return {}
   end
   return eval_card(card, context)
end

-- Evaluates jokers via Card:calculate_joker(..) except IGNORED jokers:
function DV.SIM.eval_joker(joker, context)
   if DV.contains(joker.ability.name, DV.SIM.IGNORED) then
      return {}
   end
   return joker:calculate_joker(context)
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
