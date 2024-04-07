--- STEAMODDED HEADER
--- MOD_NAME: Divvy's Preview
--- MOD_ID: dvpreview
--- MOD_AUTHOR: [Divvy C.]
--- MOD_DESCRIPTION: Preview each hand's score! v2.2.1

if not DV then DV = {} end
if not DV.SIM then DV.SIM = {} end

if not G.SETTINGS.DV then
   G.SETTINGS.DV = {
      preview_score = true,
      preview_dollars = true,
      hide_face_down = true,
      show_min_max = false
   }
end

DV.PRE = {
   data = {
      score = {min = 0, exact = 0, max = 0},
      dollars = {min = 0, exact = 0, max = 0}
   },
   text = {
      score = {l = "", r = ""},
      dollars = {top = "", bot = ""}
   },
   joker_order = {},
   hand_order = {}
}

--
-- SIMULATION:
--

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

-- Append node for preview text to the HUD:
local orig_hud = create_UIBox_HUD
function create_UIBox_HUD()
   local contents = orig_hud()

   local score_node_wrap = {n=G.UIT.R, config={id = "dv_pre_score_wrap", align = "cm", padding = 0.1}, nodes={}}
   if G.SETTINGS.DV.preview_score then table.insert(score_node_wrap.nodes, DV.PRE.get_score_node()) end
   table.insert(contents.nodes[1].nodes[1].nodes[4].nodes[1].nodes, score_node_wrap)

   local dollars_node_wrap = {n=G.UIT.C, config={id = "dv_pre_dollars_wrap", align = "cm"}, nodes={}}
   if G.SETTINGS.DV.preview_dollars then table.insert(dollars_node_wrap.nodes, DV.PRE.get_dollars_node()) end
   table.insert(contents.nodes[1].nodes[1].nodes[5].nodes[2].nodes[3].nodes[1].nodes[1].nodes[1].nodes, dollars_node_wrap)

   return contents
end

-- Return true if additional chips will beat the current blind; false otherwise.
function DV.PRE.is_enough_to_win(chips)
   if G.GAME.blind and
      (G.STATE == G.STATES.SELECTING_HAND or
       G.STATE == G.STATES.DRAW_TO_HAND or
       G.STATE == G.STATES.PLAY_TAROT)
   then return (G.GAME.chips + chips >= G.GAME.blind.chips)
   else return false
   end
end

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

function DV.PRE.get_sign_str(n)
   if n >= 0 then return "+"
   else return "" -- Negative numbers already have a sign
   end
end

function DV.PRE.get_dollar_colour(n)
   if n == 0 then return HEX("7e7667")
   elseif n > 0 then return G.C.MONEY
   elseif n < 0 then return G.C.RED
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

-- Append toggle option to settings:
local orig_settings = G.UIDEF.settings_tab
function G.UIDEF.settings_tab(tab)
   function preview_score_toggle_callback(e)
      if not G.HUD then return end

      if G.SETTINGS.DV.preview_score then
         -- Preview was just enabled, so add preview node:
         G.HUD:add_child(DV.PRE.get_score_node(), G.HUD:get_UIE_by_ID("dv_pre_score_wrap"))
         DV.PRE.data = DV.PRE.simulate()
      else
         -- Preview was just disabled, so remove preview node:
         G.HUD:get_UIE_by_ID("dv_pre_score").parent:remove()
      end
      G.HUD:recalculate()
   end

   function preview_dollars_toggle_callback(_)
      if not G.HUD then return end

      if G.SETTINGS.DV.preview_dollars then
         -- Preview was just enabled, so add preview node:
         G.HUD:add_child(DV.PRE.get_dollars_node(), G.HUD:get_UIE_by_ID("dv_pre_dollars_wrap"))
         DV.PRE.data = DV.PRE.simulate()
      else
         -- Preview was just disabled, so remove preview node:
         G.HUD:get_UIE_by_ID("dv_pre_dollars").parent:remove()
      end
      G.HUD:recalculate()
   end

   function face_down_toggle_callback(_)
      if not G.HUD then return end

      DV.PRE.data = DV.PRE.simulate()
      G.HUD:recalculate()
   end

   function minmax_toggle_callback(_)
      if not G.HUD or not DV.PRE.enabled() then return end

      DV.PRE.data = DV.PRE.simulate()

      if G.SETTINGS.DV.preview_score then
         if not G.SETTINGS.DV.show_min_max then
            -- Min-Max was just disabled, so increase scale:
            G.HUD:get_UIE_by_ID("dv_pre_l").config.object.scale = 0.75
            G.HUD:get_UIE_by_ID("dv_pre_r").config.object.scale = 0.75
         else
            -- Min-Max was just enabled, so decrease scale:
            G.HUD:get_UIE_by_ID("dv_pre_l").config.object.scale = 0.5
            G.HUD:get_UIE_by_ID("dv_pre_r").config.object.scale = 0.5
         end
         G.HUD:recalculate()
      end
   end

   local contents = orig_settings(tab)
   if tab == 'Game' then
      local preview_setting_nodes = {n = G.UIT.R, config = {align = "cm"}, nodes ={
                                        create_toggle({id = "score_toggle", label = "Enable Score Preview", ref_table = G.SETTINGS.DV, ref_value = "preview_score", callback = preview_score_toggle_callback}),
                                        create_toggle({id = "dollars_toggle", label = "Enable Money Preview", ref_table = G.SETTINGS.DV, ref_value = "preview_dollars", callback = preview_dollars_toggle_callback}),
                                        create_toggle({label = "Show Min/Max Preview Instead of Exact", ref_table = G.SETTINGS.DV, ref_value = "show_min_max", callback = minmax_toggle_callback}),
                                        create_toggle({label = "Hide Preview if Any Card is Face-Down", ref_table = G.SETTINGS.DV, ref_value = "hide_face_down", callback = face_down_toggle_callback})
                                    }}
      table.insert(contents.nodes, preview_setting_nodes)
   end
   return contents
end

function DV.PRE.get_score_node()
   local text_scale = nil
   if G.SETTINGS.DV.show_min_max then text_scale = 0.5
   else text_scale = 0.75 end

   return {n = G.UIT.C, config = {id = "dv_pre_score", align = "cm"}, nodes={
              {n=G.UIT.O, config={id = "dv_pre_l", func = "dv_pre_score_UI_set", object = DynaText({string = {{ref_table = DV.PRE.text.score, ref_value = "l"}}, colours = {G.C.UI.TEXT_LIGHT}, shadow = true, float = true, scale = text_scale})}},
              {n=G.UIT.O, config={id = "dv_pre_r", func = "dv_pre_score_UI_set", object = DynaText({string = {{ref_table = DV.PRE.text.score, ref_value = "r"}}, colours = {G.C.UI.TEXT_LIGHT}, shadow = true, float = true, scale = text_scale})}},
   }}
end

function DV.PRE.get_dollars_node()
   return {n=G.UIT.C, config={id = "dv_pre_dollars", align = "cm"}, nodes={
       {n=G.UIT.R, config={align = "cm"}, nodes={
           {n=G.UIT.O, config={id = "dv_pre_dollars_top", func = "dv_pre_dollars_UI_set", object = DynaText({string = {{ref_table = DV.PRE.text.dollars, ref_value = "top"}}, colours = {DV.PRE.get_dollar_colour(DV.PRE.data.dollars.max)}, shadow = true, spacing = 2, bump = true, scale = 0.5})}}
       }},
       {n=G.UIT.R, config={minh = 0.05}, nodes={}},
       {n=G.UIT.R, config={align = "cm"}, nodes={
           {n=G.UIT.O, config={id = "dv_pre_dollars_bot", func = "dv_pre_dollars_UI_set", object = DynaText({string = {{ref_table = DV.PRE.text.dollars, ref_value = "bot"}}, colours = {DV.PRE.get_dollar_colour(DV.PRE.data.dollars.min)}, shadow = true, spacing = 2, bump = true, scale = 0.5})}},
       }}
   }}
end

function DV.PRE.format_number(num)
   if not num or type(num) ~= 'number' then return num or '' end
   -- Start using e-notation earlier to reduce number length, if showing min and max for preview:
   if G.SETTINGS.DV.show_min_max and num >= 1e7 then
      local x = string.format("%.4g",num)
      local fac = math.floor(math.log(tonumber(x), 10))
      return string.format("%.2f",x/(10^fac))..'e'..fac
   end
   return number_format(num) -- Default Balatro function.
end

function DV.PRE.enabled()
   return G.SETTINGS.DV.preview_score or G.SETTINGS.DV.preview_dollars
end
