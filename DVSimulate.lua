--- STEAMODDED HEADER
--- MOD_NAME: Divvy's Simulation
--- MOD_ID: dvsimulate
--- MOD_AUTHOR: [Divvy C.]
--- MOD_DESCRIPTION: A utility mod to simulate selected hand.

DV = {}
DV.SIM = {}

-- These jokers have side-effects that should not be simulated:
-- Some of these also provide a range of values (eg. Misprint), so they are also ignored to simulate worst case scenario.
DV.SIM.IGNORED = {"Misprint", "Bloodstone", "8 Ball", "DNA", "Sixth Sense", "Seance", "Vagabond", "Midas Mask", "Burnt Joker"}

-- Run simulation:
-- Returns total score from currently selected hand.
function DV.simulate()
   if #G.hand.highlighted == 0 then return 0 end

   local real_hand = G.hand.cards
   local sim_full_hand = DV.deep_copy(G.hand.cards)

   local sim_hand = {}
   for i=1, #sim_full_hand do
      if not sim_full_hand[i].highlighted then
         table.insert(sim_hand, sim_full_hand[i])
      end
   end
   G.hand.cards = sim_hand

   local real_jokers = G.jokers.cards
   G.jokers.cards = DV.deep_copy(G.jokers.cards)

   local sim_play = G.hand.highlighted
   local text, _, poker_hands, scoring_hand, _ = G.FUNCS.get_poker_hand_info(sim_play)

   scoring_hand = DV.SIM.adjust_scoring_hand(sim_play, scoring_hand)

   function get_context(cardarea, args)
      local context = {
         cardarea = cardarea,
         full_hand = sim_play,
         scoring_hand = scoring_hand,
         scoring_name = text,
         poker_hands = poker_hands
      }

      for k, v in pairs(args) do
         context[k] = v
      end

      return context
   end

   local sim_hand_info = G.GAME.hands[text]

   local is_hand_debuffed = G.GAME.blind:debuff_hand(sim_play, poker_hands, text)
   if is_hand_debuffed then
      mult, hand_chips = mod_mult(0), mod_chips(0)

      -- Debuffed-effects do not affect score!
      -- Evaluate DEBUFFED EFFECTS of current jokers:
      -- for i=1, #G.jokers.cards do
      --	 local effects = DV.eval_joker(G.jokers.cards[i], get_context(G.jokers, {debuffed_hand = true}))
      -- end
   else
      -- Before-effects do not affect score!
      -- Evaluate all BEFORE EFFECTS of current jokers:
      -- for i=1, #G.jokers.cards do
      --	 local effects = DV.eval_card(G.jokers.cards[i], get_context(G.jokers, {before = true}))
      -- end

      -- Set mult and chips to hand's base values:
      mult, hand_chips = mod_mult(sim_hand_info.mult), mod_chips(sim_hand_info.chips)

      mult, hand_chips = DV.SIM.eval_blind_effect(mult, hand_chips, sim_play, poker_hands, text)

      mult, hand_chips = DV.SIM.eval_scoring_hand(get_context, mult, hand_chips, scoring_hand)

      mult, hand_chips = DV.SIM.eval_inhand_effects(get_context, mult, hand_chips, sim_hand)

      mult, hand_chips = DV.SIM.eval_meta_effects(get_context, mult, hand_chips)

      mult, hand_chips = DV.SIM.eval_deck_effect(mult, hand_chips)
   end

   local RESULT = math.floor(hand_chips*mult)

   -- After-effects do not affect score!
   -- for i=1, #G.jokers.cards do
   --	  local effect = DV.eval_card(G.jokers.cards[i], get_context(G.jokers, {after = true}))
   -- end

   G.hand.cards = real_hand
   G.jokers.cards = real_jokers

   return RESULT or 0
end

--
-- CORE:
--

function DV.SIM.eval_scoring_hand(get_context, mult, hand_chips, scoring_hand)
   for i=1, #scoring_hand do
      local scoring_card = scoring_hand[i]

      if not scoring_card.debuff then
         local reps = {1}

         -- Collect repetitions from red seals:
         local eval = DV.eval_card(scoring_card, get_context(G.play, {repetition = true, repetition_only = true}))
         if next(eval) then
            for h = 1, eval.seals.repetitions do
               reps[#reps+1] = eval
            end
         end

         -- Collect repetitions from jokers:
         for j=1, #G.jokers.cards do
            local eval = DV.eval_card(G.jokers.cards[j], get_context(G.play, {other_card = scoring_card, repetition = true}))
            if next(eval) and eval.jokers then
               for h = 1, eval.jokers.repetitions do
                  reps[#reps+1] = eval
               end
            end
         end

         -- Evaluate and apply effects of jokers on played cards:
         for j=1,#reps do
            -- Evaluation:
            local effects = {DV.eval_card(scoring_card, {cardarea = G.play, full_hand = sim_play, scoring_hand = scoring_hand, poker_hand = text})}
            for k=1, #G.jokers.cards do
               local eval = DV.eval_joker(G.jokers.cards[k], get_context(G.play, {other_card = scoring_card, individual = true}))
               if eval then
                  table.insert(effects, eval)
               end
            end
            scoring_card.lucky_trigger = nil

            -- Application:
            for ii = 1, #effects do
               if effects[ii].chips then
                  hand_chips = mod_chips(hand_chips + effects[ii].chips)
               end

               if effects[ii].mult then
                  mult = mod_mult(mult + effects[ii].mult)
               end

               if effects[ii].extra then
                  local extras = {mult = false, hand_chips = false}
                  if effects[ii].extra.mult_mod then mult =mod_mult( mult + effects[ii].extra.mult_mod);extras.mult = true end
                  if effects[ii].extra.chip_mod then hand_chips = mod_chips(hand_chips + effects[ii].extra.chip_mod);extras.hand_chips = true end
                  if effects[ii].extra.swap then
                     local old_mult = mult
                     mult = mod_mult(hand_chips)
                     hand_chips = mod_chips(old_mult)
                     extras.hand_chips = true; extras.mult = true
                  end
               end

               if effects[ii].x_mult then
                  mult = mod_mult(mult*effects[ii].x_mult)
               end

               if effects[ii].edition then
                  hand_chips = mod_chips(hand_chips + (effects[ii].edition.chip_mod or 0))
                  mult = mult + (effects[ii].edition.mult_mod or 0)
                  mult = mod_mult(mult*(effects[ii].edition.x_mult_mod or 1))
               end
            end
         end
      end
   end
   return mult, hand_chips
end

function DV.SIM.eval_inhand_effects(get_context, mult, hand_chips, sim_hand)
   for i=1, #sim_hand do
      local reps = {1}
      local j = 1
      while j <= #reps do
         local effects = {DV.eval_card(sim_hand[i], get_context(G.hand, {}))}

         -- Collect effects on this card from current jokers:
         for k=1, #G.jokers.cards do
            local eval = DV.eval_joker(G.jokers.cards[k], get_context(G.hand, {other_card = sim_hand[i], individual = true}))
            if eval then
               table.insert(effects, eval)
            end
         end

         -- Collect repetitions:
         if reps[j] == 1 then
            -- Collect repetitions from red seal (in-hand):
            local eval = DV.eval_card(sim_hand[i], get_context(G.hand, {repetition = true, repetition_only = true, card_effects = effects}))
            if next(eval) and (next(effects[1]) or #effects > 1) then
               for h  = 1, eval.seals.repetitions do
                  reps[#reps+1] = eval
               end
            end

            -- Collect repetitions from jokers (in-hand):
            for j=1, #G.jokers.cards do
               local eval = DV.eval_card(G.jokers.cards[j], get_context(G.hand, {other_card = sim_hand[i], repetition = true, card_effects = effects}))
               if next(eval) then
                  for h  = 1, eval.jokers.repetitions do
                     reps[#reps+1] = eval
                  end
               end
            end
         end

         -- Apply the effects:
         for ii = 1, #effects do
            if effects[ii].h_mult then
               mult = mod_mult(mult + effects[ii].h_mult)
            end
            if effects[ii].x_mult then
               mult = mod_mult(mult*effects[ii].x_mult)
            end
         end
         j = j +1
      end
   end
   return mult, hand_chips
end

function DV.SIM.eval_meta_effects(get_context, mult, hand_chips)
   for i=1, #G.jokers.cards + #G.consumeables.cards do
      local _card = G.jokers.cards[i] or G.consumeables.cards[i - #G.jokers.cards]

      -- Apply EDITION EFFECTS of current jokers (eg. foil, holographic):
      local edition_effects = DV.eval_card(_card, get_context(G.jokers, {edition = true}))
      if edition_effects.jokers then
         edition_effects.jokers.edition = true
         if edition_effects.jokers.chip_mod then
            hand_chips = mod_chips(hand_chips + edition_effects.jokers.chip_mod)
         end
         if edition_effects.jokers.mult_mod then
            mult = mod_mult(mult + edition_effects.jokers.mult_mod)
         end
      end

      -- Evaluate EFFECTS of current jokers (not tied to cards?):
      local effects = DV.eval_card(_card, get_context(G.jokers, {joker_main = true}))

      if effects.jokers then
         local extras = {mult = false, hand_chips = false}
         if effects.jokers.mult_mod then mult = mod_mult(mult + effects.jokers.mult_mod);extras.mult = true end
         if effects.jokers.chip_mod then hand_chips = mod_chips(hand_chips + effects.jokers.chip_mod);extras.hand_chips = true end
         if effects.jokers.Xmult_mod then mult = mod_mult(mult*effects.jokers.Xmult_mod);extras.mult = true  end
      end

      -- Evaluate JOKER EFFECTS of current jokers (joker-on-joker):
      for _, v in ipairs(G.jokers.cards) do
         local effect = v:calculate_joker{full_hand = sim_play, scoring_hand = scoring_hand, scoring_name = text, poker_hands = poker_hands, other_joker = _card}
         if effect then
            local extras = {mult = false, hand_chips = false}
            if effect.mult_mod then mult = mod_mult(mult + effect.mult_mod);extras.mult = true end
            if effect.chip_mod then hand_chips = mod_chips(hand_chips + effect.chip_mod);extras.hand_chips = true end
            if effect.Xmult_mod then mult = mod_mult(mult*effect.Xmult_mod);extras.mult = true  end
         end
      end

      -- (Continued) Apply EDITION EFFECTS of current jokers (ie. polychrome):
      if edition_effects.jokers then
         if edition_effects.jokers.x_mult_mod then
            mult = mod_mult(mult*edition_effects.jokers.x_mult_mod)
         end
      end
   end
   return mult, hand_chips
end

function DV.SIM.eval_deck_effect(mult, hand_chips)
   local nu_chip, nu_mult = G.GAME.selected_back:trigger_effect{context = 'final_scoring_step', chips = hand_chips, mult = mult}
   mult = mod_mult(nu_mult or mult)
   hand_chips = mod_chips(nu_chip or hand_chips)
   return mult, hand_chips
end

function DV.SIM.eval_blind_effect(mult, hand_chips, sim_play, poker_hands, text)
   mult, hand_chips, _ = G.GAME.blind:modify_hand(sim_play, poker_hands, text, mult, hand_chips)
   return mod_mult(mult), mod_chips(hand_chips)
end

function DV.SIM.adjust_scoring_hand(sim_play, scoring_hand)
   local pures = {}
   for i=1, #sim_play do
      if next(find_joker('Splash')) then
         scoring_hand[i] = sim_play[i]
      else
         if sim_play[i].ability.effect == 'Stone Card' then
            local inside = false
            for j=1, #scoring_hand do
               if scoring_hand[j] == sim_play[i] then
                  inside = true
               end
            end
            if not inside then table.insert(pures, sim_play[i]) end
         end
      end
   end
   for i=1, #pures do
      table.insert(scoring_hand, pures[i])
   end

   table.sort(scoring_hand, function (a, b) return a.T.x < b.T.x end )
   return scoring_hand
end

-- Evaluates all cards except IGNORED jokers:
function DV.eval_card(card, context)
   if (card.ability.set == "Joker") and DV.contains(card.ability.name, DV.SIM.IGNORED) then
      return {}
   end
   return eval_card(card, context)
end

-- Evaluates jokers via Card:calculate_joker(..) except IGNORED jokers:
function DV.eval_joker(joker, context)
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
