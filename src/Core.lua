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
   local function sim_func()
      DV.PRE.data = DV.PRE.simulate()
      return true
   end
   if DV.PRE.enabled() then
      if not G.SETTINGS.DV.manual_preview then
         G.E_MANAGER:add_event(Event({trigger = trigger, func = sim_func}))
      else
         if DV.PRE.previewing then
            -- Replace score preview with button:
            local score_node = G.HUD:get_UIE_by_ID("dv_pre_score")
            if score_node then
               score_node.parent:remove()
               G.HUD:add_child(DV.PRE.get_manual_preview_button(), G.HUD:get_UIE_by_ID("dv_pre_score_wrap"))
            elseif not G.HUD:get_UIE_by_ID("dv_pre_manual_button") then
               G.HUD:add_child(DV.PRE.get_manual_preview_button(), G.HUD:get_UIE_by_ID("dv_pre_score_wrap"))
            end

            DV.PRE.previewing = false
         end
      end
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
local orig_cardarea_update = CardArea.update
function CardArea:update(dt)
   orig_cardarea_update(self, dt)
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
   if cardarea.config.type == 'joker'
      and cardarea.cards[1].ability.set == 'Joker'                                 -- The consumables cardarea also has type 'joker' so must verify by checking first card.
      and not (cardarea.cards[1].edition and cardarea.cards[1].edition.mp_phantom) -- The Multiplayer mod has a special joker area that will cause lag here
   then
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
   local function reset_func()
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
   if DV.PRE.data and G.SETTINGS.DV.preview_score
      and not DV.PRE.delay.active and not G.HUD:get_UIE_by_ID("dv_pre_manual_button")
   then
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
      if e.config.id == "dv_pre_l" and DV.PRE.enabled() then
         if G.SETTINGS.DV.preview_score then
            new_preview_text = "??????"
         else
            new_preview_text = "Score Preview Off"
         end

         if G.SETTINGS.DV.show_min_max then
            new_preview_text = " ".. new_preview_text .." "
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
         if should_juice then
            G.FUNCS.text_super_juice(e, 5)
            e.config.object.colours = {G.C.MONEY}
         elseif new_preview_text:find("Off") then
            G.FUNCS.text_super_juice(e, 0)
            e.config.object.colours = {lighten(G.C.GREY, 0.33)}
         else
            G.FUNCS.text_super_juice(e, 0)
            e.config.object.colours = {G.C.UI.TEXT_LIGHT}
         end
      end
   end
end

function G.FUNCS.dv_pre_timer_UI_set(e)
   if DV.PRE.delay.active then
      local delay_elapsed = G.TIMERS.REAL - DV.PRE.delay.start
      local delay_remaining = G.SETTINGS.DV.delay_length - delay_elapsed
      local delay_str_len = math.floor(math.max(0, math.log(delay_remaining, 10))) + 3 -- Always have 1 decimal place
      DV.PRE.text.delay_timer = tostring(delay_remaining):sub(1, delay_str_len)

      e.config.object:update_text()

      if delay_remaining < 5 then
         e.config.object.colours = {mix_colours(G.C.UI.TEXT_LIGHT, lighten(G.C.GREY, 0.33), 1-(delay_remaining / math.min(G.SETTINGS.DV.delay_length, 5)))}
      end
   end
end

function G.FUNCS.dv_pre_dollars_UI_set(e)
   local new_preview_text = ""
   local new_colour = nil
   if DV.PRE.data and G.SETTINGS.DV.preview_dollars
      and not DV.PRE.delay.active and not G.HUD:get_UIE_by_ID("dv_pre_manual_button")
      and G.SETTINGS.DV.manual_preview
   then
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
      if e.config.id == "dv_pre_dollars_top" and G.SETTINGS.DV.preview_dollars then
         new_preview_text = " +??"
      else
         new_preview_text = ""
      end
      new_colour = DV.PRE.get_dollar_colour(0)
   end

   if (not DV.PRE.text.dollars[e.config.id:sub(-3)]) or new_preview_text ~= DV.PRE.text.dollars[e.config.id:sub(-3)] then
      DV.PRE.text.dollars[e.config.id:sub(-3)] = new_preview_text
      e.config.object.colours = {new_colour}
      e.config.object:update_text()
      if not G.TAROT_INTERRUPT_PULSE then e.config.object:pulse(0.25) end
   end
end

--
-- MANUAL PREVIEW:
--

local orig_game_update = Game.update
function Game:update(dt)
   orig_game_update(self, dt)

   if DV.PRE.delay.active and G.TIMERS.REAL > DV.PRE.delay.start + G.SETTINGS.DV.delay_length then
      DV.PRE.show_preview()
   end
end

function G.FUNCS.dv_pre_manual_run(e)
   print(G.SETTINGS.DV.delay_length)
   if G.SETTINGS.DV.delay_length > 0 then
      DV.PRE.delay.active = true
      DV.PRE.delay.start = G.TIMERS.REAL
      DV.PRE.show_timer()
   else
      DV.PRE.show_preview()
   end
end

function DV.PRE.show_timer()
   -- Replace button with timer:
   local manual_button = G.HUD:get_UIE_by_ID("dv_pre_manual_button")
   if manual_button then manual_button.parent:remove() end
   G.HUD:add_child(DV.PRE.get_timer_node(), G.HUD:get_UIE_by_ID("dv_pre_score_wrap"))
end

function DV.PRE.show_preview()
   -- Run simulation:
   local function sim_func()
      DV.PRE.data = DV.PRE.simulate()
      return true
   end
   G.E_MANAGER:add_event(Event({trigger = trigger, func = sim_func}))

   -- Replace button/timer with score preview:
   if DV.PRE.delay.active then
      DV.PRE.delay.active = false

      local timer_node = G.HUD:get_UIE_by_ID("dv_pre_timer")
      if timer_node then timer_node.parent:remove() end
   else
      local manual_button = G.HUD:get_UIE_by_ID("dv_pre_manual_button")
      if manual_button then manual_button.parent:remove() end
   end
   G.HUD:add_child(DV.PRE.get_score_node(), G.HUD:get_UIE_by_ID("dv_pre_score_wrap"))

   DV.PRE.previewing = true
end
