--- STEAMODDED HEADER
--- MOD_NAME: Divvy's Preview
--- MOD_ID: dvpreview
--- MOD_AUTHOR: [Divvy C.]
--- MOD_DESCRIPTION: Preview each hand's score!

if not DV then DV = {} end
if not DV.SIM then DV.SIM = {} end
if not DV.PRE then
   DV.PRE = {
      enabled = true,
      joker_order = {},
   }
end

local orig_start = Game.start_run
function Game:start_run(args)
   orig_start(self)
   self.GAME.current_round.current_hand.simulated_score = 0
   self.GAME.current_round.current_hand.preview_text = "0"
end

--
-- SIMULATION UPDATE ADVICE:
--

function DV.PRE.add_update_event(trigger)
   function sim_func()
      G.GAME.current_round.current_hand.simulated_score = DV.SIM.simulate()
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
   DV.PRE.update_on_joker_order_change(self)
end

function DV.PRE.update_on_joker_order_change(cardarea)
   -- Ensure that cardarea contains jokers, and only proceed if it has cards (ie. jokers);
   -- note that the consumables cardarea also has type 'joker' so must verify by checking first card.
   if #cardarea.cards == 0 or
      cardarea.config.type ~= 'joker' or
      cardarea.cards[1].ability.set ~= 'Joker'
   then
      return
   end

   -- Go through stored joker names (ordered) and check against current jokers, in-order.
   -- If any mismatch occurs, toggle flag and update name for next time.
   local should_update = false
   if #cardarea.cards ~= #DV.PRE.joker_order then
      DV.PRE.joker_order = {}
   end
   for i, j in ipairs(cardarea.cards) do
      if j.ability.name ~= DV.PRE.joker_order[i] then
         DV.PRE.joker_order[i] = j.ability.name
         should_update = true
      end
   end

   if should_update then
      DV.PRE.add_update_event("immediate")
   end
end

--
-- SIMULATION RESET ADVICE:
--

function DV.PRE.add_reset_event(trigger)
   function reset_func()
      G.GAME.current_round.current_hand.simulated_score = 0
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
function G.FUNCS.discard_cards_from_highlighted(e, hook)
   orig_discard(e, hook)
   DV.PRE.add_reset_event("immediate")
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
   local new_preview_text = number_format(G.GAME.current_round.current_hand.simulated_score)
   if (not G.GAME.current_round.current_hand.preview_text) or new_preview_text ~= G.GAME.current_round.current_hand.preview_text then
      G.GAME.current_round.current_hand.preview_text = new_preview_text
      e.config.object:update_text()
      -- Wobble:
      if not G.TAROT_INTERRUPT_PULSE then
         local scaled_juice = math.floor(math.log10(type(G.GAME.current_round.current_hand.simulated_score) == 'number' and G.GAME.current_round.current_hand.simulated_score or 1))
         G.FUNCS.text_super_juice(e, math.max(0, math.min(6, scaled_juice)))
      end
   end
end

-- Append toggle option to settings:
local orig_settings = G.UIDEF.settings_tab
function G.UIDEF.settings_tab(tab)
   function preview_toggle_callback(_)
      if not G.HUD then return end

      if not DV.PRE.enabled then
         -- Preview was just disabled, so remove preview node:
         G.HUD:get_UIE_by_ID("dv_sim").parent:remove()
      else
         -- Preview was just enabled, so add preview node:
         G.HUD:add_child(DV.PRE.get_sim_node(), G.HUD:get_UIE_by_ID("dv_sim_wrap"))
         G.GAME.current_round.current_hand.simulated_score = DV.SIM.simulate()
      end
      G.HUD:recalculate()
   end

   local contents = orig_settings(tab)
   if tab == 'Game' then
      local preview_toggle_node = create_toggle({label = "Enable Score Preview", ref_table = DV.PRE, ref_value = "enabled", callback = preview_toggle_callback})
      table.insert(contents.nodes, preview_toggle_node)
   end
   return contents
end

function DV.PRE.get_sim_node()
   return {n = G.UIT.C, config = {id = "dv_sim", align = "cm"}, nodes={
              {n=G.UIT.O, config={func = "simulation_UI_set", object = DynaText({string = {{ref_table = G.GAME.current_round.current_hand, ref_value = "preview_text"}}, colours = {G.C.UI.TEXT_LIGHT}, shadow = true, float = true, scale = 0.75})}}
   }}
end
