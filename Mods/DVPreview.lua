--- STEAMODDED HEADER
--- MOD_NAME: Divvy's Preview
--- MOD_ID: dvpreview
--- MOD_AUTHOR: [Divvy C.]
--- MOD_DESCRIPTION: Preview each hand's score!

if not DV then DV = {} end
if not DV.SIM then DV.SIM = {} end

DV.PRE = {
   enabled = true,
   hide_face_down = true,
   show_min_max = false,
   joker_order = {},
   hand_order = {},
}

local orig_start = Game.start_run
function Game:start_run(args)
   orig_start(self, args)
   self.GAME.current_round.current_hand.simulated_data = {min = 0, exact = 0, max = 0}
   self.GAME.current_round.current_hand.preview_text = "0"
end

--
-- SIMULATION:
--

function DV.PRE.simulate()
   -- Guard against simulating in redundant places:
   if not (G.STATE == G.STATES.SELECTING_HAND or
           G.STATE == G.STATES.DRAW_TO_HAND or
           G.STATE == G.STATES.PLAY_TAROT)
   then return 0 end

   if DV.PRE.hide_face_down then
      for _, card in ipairs(G.hand.highlighted) do
         if card.facing == "back" then return nil end
      end
   end

   return DV.SIM.run(G.hand.highlighted, DV.PRE.get_held_cards(), G.jokers.cards, G.deck, DV.PRE.show_min_max)
end

function DV.PRE.get_held_cards()
   local sim_hand = {}
   for _, sim_card in ipairs(DV.deep_copy(G.hand.cards)) do
      if not sim_card.highlighted then
         table.insert(sim_hand, sim_card)
      end
   end
   return sim_hand
end

--
-- SIMULATION UPDATE ADVICE:
--

function DV.PRE.add_update_event(trigger)
   function sim_func()
      G.GAME.current_round.current_hand.simulated_data = DV.PRE.simulate()
      return true
   end
   if DV.PRE.enabled then
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

-- Update simulation after joker reordering:
local orig_update = CardArea.update
function CardArea:update(dt)
   orig_update(self, dt)
   DV.PRE.update_on_card_order_change(self)
end

function DV.PRE.update_on_card_order_change(cardarea)
   -- TODO: Account for the case where last joker is sold.
   -- (ie. #cardarea.cards is changed 1 -> 0)
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
      G.GAME.current_round.current_hand.simulated_data = {min = 0, exact = 0, max = 0}
      return true
   end
   if DV.PRE.enabled then
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

   local sim_node_wrap = {n=G.UIT.R, config={id = "dv_sim_wrap", align = "cm", padding = 0.1}, nodes={}}
   if DV.PRE.enabled then table.insert(sim_node_wrap.nodes, DV.PRE.get_sim_node()) end
   table.insert(contents.nodes[1].nodes[1].nodes[4].nodes[1].nodes, sim_node_wrap)

   return contents
end

-- Add animation to preview text:
function G.FUNCS.simulation_UI_set(e)
   local new_preview_text = ""
   local new_preview_data = G.GAME.current_round.current_hand.simulated_data
   local value_for_juice = 0
   if new_preview_data then
      if DV.PRE.show_min_max then
         if new_preview_data.min == new_preview_data.max then
            -- Superficial padding to fake text change, which is a prerequisite for animation update:
            new_preview_text = " " .. number_format(new_preview_data.min) .. " "
         else
            local new_preview_min_text = DV.PRE.format_number(new_preview_data.min)
            local new_preview_max_text = DV.PRE.format_number(new_preview_data.max)
            new_preview_text = new_preview_min_text .. " - " .. new_preview_max_text
         end
         value_for_juice = new_preview_data.min
      else
         new_preview_text = number_format(new_preview_data.exact)
         value_for_juice = new_preview_data.exact
      end
   else
      new_preview_text = "????"
   end
   if (not G.GAME.current_round.current_hand.preview_text) or new_preview_text ~= G.GAME.current_round.current_hand.preview_text then
      G.GAME.current_round.current_hand.preview_text = new_preview_text
      e.config.object:update_text()
      -- Wobble:
      if not G.TAROT_INTERRUPT_PULSE then
         local scaled_juice = math.floor(math.log10(type(value_for_juice) == 'number' and value_for_juice or 1))
         G.FUNCS.text_super_juice(e, math.max(0, math.min(4, scaled_juice)))
      end
   end
end

-- Append toggle option to settings:
local orig_settings = G.UIDEF.settings_tab
function G.UIDEF.settings_tab(tab)
   function preview_toggle_callback(_)
      if not G.HUD then return end

      if DV.PRE.enabled then
         -- Preview was just enabled, so add preview node:
         G.HUD:add_child(DV.PRE.get_sim_node(), G.HUD:get_UIE_by_ID("dv_sim_wrap"))
         G.GAME.current_round.current_hand.simulated_data = DV.PRE.simulate()
      else
         -- Preview was just disabled, so remove preview node:
         G.HUD:get_UIE_by_ID("dv_sim").parent:remove()
      end
      G.HUD:recalculate()
   end

   function face_down_toggle_callback(_)
      if not G.HUD then return end

      G.GAME.current_round.current_hand.simulated_data = DV.PRE.simulate()
      G.HUD:recalculate()
   end

   function minmax_toggle_callback(_)
      if not G.HUD then return end

      G.GAME.current_round.current_hand.simulated_data = DV.PRE.simulate()
      if not DV.PRE.show_min_max then
         -- Min-Max was just disabled, so increase scale:
         G.HUD:get_UIE_by_ID("dv_sim_text").config.object.scale = 0.75
      else
         -- Min-Max was just enabled, so decrease scale:
         G.HUD:get_UIE_by_ID("dv_sim_text").config.object.scale = 0.5
      end
      DV.PRE.force_update_preview_text = true
      G.HUD:recalculate()
   end

   local contents = orig_settings(tab)
   if tab == 'Game' then
      local preview_setting_nodes = {n = G.UIT.R, config = {align = "cm"}, nodes ={
                                        create_toggle({label = "Enable Score Preview", ref_table = DV.PRE, ref_value = "enabled", callback = preview_toggle_callback}),
                                        create_toggle({label = "Show Min-Max Score instead of Exact", ref_table = DV.PRE, ref_value = "show_min_max", callback = minmax_toggle_callback}),
                                        create_toggle({label = "Hide Score Preview if Any Card is Face-Down", ref_table = DV.PRE, ref_value = "hide_face_down", callback = face_down_toggle_callback})
                                    }}
      table.insert(contents.nodes, preview_setting_nodes)
   end
   return contents
end

function DV.PRE.get_sim_node()
   local text_scale = nil
   if DV.PRE.show_min_max then text_scale = 0.5
   else text_scale = 0.75 end

   return {n = G.UIT.C, config = {id = "dv_sim", align = "cm"}, nodes={
              {n=G.UIT.O, config={id = "dv_sim_text", func = "simulation_UI_set", object = DynaText({string = {{ref_table = G.GAME.current_round.current_hand, ref_value = "preview_text"}}, colours = {G.C.UI.TEXT_LIGHT}, shadow = true, float = true, scale = text_scale})}}
   }}
end

function DV.PRE.format_number(num)
   if not num or type(num) ~= 'number' then return num or '' end
   -- Start using e-notation earlier to reduce number length, if showing min and max for preview:
   if DV.PRE.show_min_max and num >= 1e7 then
      local x = string.format("%.4g",num)
      local fac = math.floor(math.log(tonumber(x), 10))
      return string.format("%.2f",x/(10^fac))..'e'..fac
   end
   return number_format(num) -- Default Balatro function.
end
