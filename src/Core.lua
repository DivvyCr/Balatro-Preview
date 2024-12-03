--- Divvy's Preview for Balatro - Core.lua
--
-- The functions responsible for running the simulation at appropriate times;
-- ie. whenever the player modifies card selection or card order.

function DV.PRE.simulate()
   -- Guard against simulating in redundant places:
   if not (G.STATE == G.STATES.SELECTING_HAND or
           G.STATE == G.STATES.DRAW_TO_HAND or
           G.STATE == G.STATES.PLAY_TAROT)
   then return {score = {min = 0, exact = 0, max = 0}, dollars = {min = 0, exact = 0, max = 0}}
   end

   if G.SETTINGS.DV.hide_face_down then
      for _, card in ipairs(G.hand.highlighted) do
         if card.facing == "back" then return nil end
      end
      if #(G.hand.highlighted) ~= 0 then
        for _, joker in ipairs(G.jokers.cards) do
          if joker.facing == "back" then return nil end
        end
      end
   end

   return DV.SIM.run()
end

--
-- SIMULATION UPDATE ADVICE:
--

function DV.PRE.add_update_event(trigger)
   function sim_func()
      DV.PRE.data = DV.PRE.simulate()
      return true
   end
   if DV.PRE.enabled() then
      G.E_MANAGER:add_event(Event({trigger = trigger, func = sim_func}))
   end
end

-- Update simulation after a consumable (eg. Tarot, Planet) is used:
local orig_use = Card.use_consumeable
function Card:use_consumeable(area, copier)
   orig_use(self, area, copier)
   DV.PRE.add_update_event("immediate")
end

-- Update simulation after card selection changed:
local orig_hl = CardArea.parse_highlighted
function CardArea:parse_highlighted()
   orig_hl(self)
   DV.PRE.add_update_event("immediate")
end

-- Update simulation after joker sold:
local orig_card_remove = Card.remove_from_area
function Card:remove_from_area()
   orig_card_remove(self)
   if self.config.type == 'joker' then
      DV.PRE.add_update_event("immediate")
   end
end

-- Update simulation after joker reordering:
local orig_update = CardArea.update
function CardArea:update(dt)
   orig_update(self, dt)
   DV.PRE.update_on_card_order_change(self)
end

function DV.PRE.update_on_card_order_change(cardarea)
   if #cardarea.cards == 0 or
      not (G.STATE == G.STATES.SELECTING_HAND or
           G.STATE == G.STATES.DRAW_TO_HAND or
           G.STATE == G.STATES.PLAY_TAROT)
   then return end
   -- Important not to update on G.STATES.HAND_PLAYED, because it would reset the preview text!

   local prev_order = nil
   if cardarea.config.type == 'joker' and cardarea.cards[1].ability.set == 'Joker' then
      -- Note that the consumables cardarea also has type 'joker' so must verify by checking first card.
      prev_order = DV.PRE.joker_order
   elseif cardarea.config.type == 'hand' then
      prev_order = DV.PRE.hand_order
   else
      return
   end

   -- Go through stored card IDs and check against current card IDs, in-order.
   -- If any mismatch occurs, toggle flag and update name for next time.
   local should_update = false
   if #cardarea.cards ~= #prev_order then
      prev_order = {}
   end
   for i, c in ipairs(cardarea.cards) do
      if c.sort_id ~= prev_order[i] then
         prev_order[i] = c.sort_id
         should_update = true
      end
   end

   if should_update then
      if cardarea.config.type == 'joker' or cardarea.cards[1].ability.set == 'Joker' then
         DV.PRE.joker_order = prev_order
      elseif cardarea.config.type == 'hand' then
         DV.PRE.hand_order = prev_order
      end

      DV.PRE.add_update_event("immediate")
   end
end

--
-- SIMULATION RESET ADVICE:
--

function DV.PRE.add_reset_event(trigger)
   function reset_func()
      DV.PRE.data = {score = {min = 0, exact = 0, max = 0}, dollars = {min = 0, exact = 0, max = 0}}
      return true
   end
   if DV.PRE.enabled() then
      G.E_MANAGER:add_event(Event({trigger = trigger, func = reset_func}))
   end
end

local orig_eval = G.FUNCS.evaluate_play
function G.FUNCS.evaluate_play(e)
   orig_eval(e)
   DV.PRE.add_reset_event("after")
end

local orig_discard = G.FUNCS.discard_cards_from_highlighted
function G.FUNCS.discard_cards_from_highlighted(e, is_hook_blind)
   orig_discard(e, is_hook_blind)
   if not is_hook_blind then
      DV.PRE.add_reset_event("immediate")
   end
end

--
-- USER INTERFACE ADVICE:
--

-- Add animation to preview text:
function G.FUNCS.dv_pre_score_UI_set(e)
   local new_preview_text = ""
   local should_juice = false
   if DV.PRE.data then
      if G.SETTINGS.DV.show_min_max and (DV.PRE.data.score.min ~= DV.PRE.data.score.max) then
         -- Format as 'X - Y' :
         if e.config.id == "dv_pre_l" then
            new_preview_text = DV.PRE.format_number(DV.PRE.data.score.min) .. " - "
            if DV.PRE.is_enough_to_win(DV.PRE.data.score.min) then should_juice = true end
         elseif e.config.id == "dv_pre_r" then
            new_preview_text = DV.PRE.format_number(DV.PRE.data.score.max)
            if DV.PRE.is_enough_to_win(DV.PRE.data.score.max) then should_juice = true end
         end
      else
         -- Format as single number:
         if e.config.id == "dv_pre_l" then
            if G.SETTINGS.DV.show_min_max then
               -- Spaces around number necessary to distinguish Min/Max text from Exact text,
               -- which is itself necessary to force a HUD update when switching between Min/Max and Exact.
               new_preview_text = " " .. DV.PRE.format_number(DV.PRE.data.score.min) .. " "
               if DV.PRE.is_enough_to_win(DV.PRE.data.score.min) then should_juice = true end
            else
               new_preview_text = number_format(DV.PRE.data.score.exact)
               if DV.PRE.is_enough_to_win(DV.PRE.data.score.exact) then should_juice = true end
            end
         else
            new_preview_text = ""
         end
      end
   else
      -- Spaces around number necessary to distinguish Min/Max text from Exact text, same as above ^
      if e.config.id == "dv_pre_l" then
         if G.SETTINGS.DV.show_min_max then new_preview_text = " ?????? "
         else new_preview_text = "??????"
         end
      else
         new_preview_text = ""
      end
   end

   if (not DV.PRE.text.score[e.config.id:sub(-1)]) or new_preview_text ~= DV.PRE.text.score[e.config.id:sub(-1)] then
      DV.PRE.text.score[e.config.id:sub(-1)] = new_preview_text
      e.config.object:update_text()
      -- Wobble:
      if not G.TAROT_INTERRUPT_PULSE then
         if should_juice
         then
            G.FUNCS.text_super_juice(e, 5)
            e.config.object.colours = {G.C.MONEY}
         else
            G.FUNCS.text_super_juice(e, 0)
            e.config.object.colours = {G.C.UI.TEXT_LIGHT}
         end
      end
   end
end

function G.FUNCS.dv_pre_dollars_UI_set(e)
   local new_preview_text = ""
   local new_colour = nil
   if DV.PRE.data then
      if G.SETTINGS.DV.show_min_max and (DV.PRE.data.dollars.min ~= DV.PRE.data.dollars.max) then
         if e.config.id == "dv_pre_dollars_top" then
            new_preview_text = " " .. DV.PRE.get_sign_str(DV.PRE.data.dollars.max) .. DV.PRE.data.dollars.max
            new_colour = DV.PRE.get_dollar_colour(DV.PRE.data.dollars.max)
         elseif e.config.id == "dv_pre_dollars_bot" then
            new_preview_text = " " .. DV.PRE.get_sign_str(DV.PRE.data.dollars.min) .. DV.PRE.data.dollars.min
            new_colour = DV.PRE.get_dollar_colour(DV.PRE.data.dollars.min)
         end
      else
         if e.config.id == "dv_pre_dollars_top" then
            local _data = (G.SETTINGS.DV.show_min_max) and DV.PRE.data.dollars.min or DV.PRE.data.dollars.exact

            new_preview_text = " " .. DV.PRE.get_sign_str(_data) .. _data
            new_colour = DV.PRE.get_dollar_colour(_data)
         else
            new_preview_text = ""
            new_colour = DV.PRE.get_dollar_colour(0)
         end
      end
   else
      new_preview_text = " +??"
      new_colour = DV.PRE.get_dollar_colour(0)
   end

   if (not DV.PRE.text.dollars[e.config.id:sub(-3)]) or new_preview_text ~= DV.PRE.text.dollars[e.config.id:sub(-3)] then
      DV.PRE.text.dollars[e.config.id:sub(-3)] = new_preview_text
      e.config.object.colours = {new_colour}
      e.config.object:update_text()
      if not G.TAROT_INTERRUPT_PULSE then e.config.object:pulse(0.25) end
   end
end
