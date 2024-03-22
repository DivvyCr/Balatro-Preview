--- STEAMODDED HEADER
--- MOD_NAME: Divvy's Preview
--- MOD_ID: dvpreview
--- MOD_AUTHOR: [Divvy C.]
--- MOD_DESCRIPTION: Preview each hand's score!

-- Initialise mod:
local orig_init = Game.init
function Game:init()
   orig_init(self)
   G.SETTINGS.DV = true
end

-- Initialise simulation:
local orig_start = Game.start_run
function Game:start_run(args)
   orig_start(self)
   self.GAME.current_round.current_hand.simulation = 0
   self.GAME.current_round.current_hand.sim_text = "0"
end

-- Append to settings:
local orig_settings = G.UIDEF.settings_tab
function G.UIDEF.settings_tab(tab)
   local contents = orig_settings(tab)
   if tab == 'Game' then
      table.insert(contents.nodes, create_toggle({label = "Enable Score Preview", ref_table = G.SETTINGS, ref_value = "DV",
                                                  callback = function (_)
                                                     if G.HUD then
                                                        -- NOTE: The value is changed BEFORE the callback:
                                                        if not G.SETTINGS.DV then
                                                              G.HUD:get_UIE_by_ID("sim").parent:remove()
                                                        else
                                                           local simulation_node = {n=G.UIT.C, config={id = "sim", align = "cm"}, nodes={
                                                                                       {n=G.UIT.O, config={func = "simulation_UI_set", object = DynaText({string = {{ref_table = G.GAME.current_round.current_hand, ref_value = "sim_text"}}, colours = {G.C.UI.TEXT_LIGHT}, shadow = true, float = true, scale = 0.75})}}
                                                                                   }}
                                                           G.HUD:add_child(simulation_node, G.HUD:get_UIE_by_ID("dv"))
                                                           G.GAME.current_round.current_hand.simulation = DV.simulate()
                                                        end
                                                        G.HUD:recalculate()
                                                     end
                                                  end
      }))
   end
   return contents
end

-- Update simulation whenever selected cards are parsed:
local orig_hl = CardArea.parse_highlighted
function CardArea:parse_highlighted()
   orig_hl(self)

   if G.SETTINGS.DV and G.STATE == G.STATES.SELECTING_HAND then
      G.GAME.current_round.current_hand.simulation = DV.simulate()
   end
end

-- Reset simulation after play:
local orig_play = G.FUNCS.play_cards_from_highlighted
G.FUNCS.play_cards_from_highlighted = function(e)
   orig_play(e)
   if G.SETTINGS.DV then
      G.GAME.current_round.current_hand.simulation = 0
   end
end

-- Reset simulation after discard:
local orig_discard = G.FUNCS.discard_cards_from_highlighted
G.FUNCS.discard_cards_from_highlighted = function(e, hook)
   orig_discard(e, hook)
   if G.SETTINGS.DV then
      G.GAME.current_round.current_hand.simulation = 0
   end
end

-- Animate UI:
G.FUNCS.simulation_UI_set = function (e)
   local new_sim_text = number_format(G.GAME.current_round.current_hand.simulation)
   if (not G.GAME.current_round.current_hand.sim_text) or new_sim_text ~= G.GAME.current_round.current_hand.sim_text then
      G.GAME.current_round.current_hand.sim_text = new_sim_text
      e.config.object:update_text()
      -- Wobble:
      if not G.TAROT_INTERRUPT_PULSE then
         G.FUNCS.text_super_juice(e, math.max(0,math.floor(math.log10(type(G.GAME.current_round.current_hand.simulation) == 'number' and G.GAME.current_round.current_hand.simulation or 1))))
      end
   end
end

-- Append to UI:
local orig_hud = create_UIBox_HUD
function create_UIBox_HUD()
   local contents = orig_hud()

   if G.SETTINGS.DV then
      local simulation_node = {n=G.UIT.R, config={id = "dv", align = "cm", padding = 0.1}, nodes={
                                  {n=G.UIT.C, config={id = "sim", align = "cm"}, nodes={
                                      {n=G.UIT.O, config={func = "simulation_UI_set", object = DynaText({string = {{ref_table = G.GAME.current_round.current_hand, ref_value = "sim_text"}}, colours = {G.C.UI.TEXT_LIGHT}, shadow = true, float = true, scale = 0.75})}}
                                  }}
                              }}
      table.insert(contents.nodes[1].nodes[1].nodes[4].nodes[1].nodes, simulation_node)
   else
      local simulation_node = {n=G.UIT.R, config={id = "dv", align = "cm", padding = 0.1}, nodes={}}
      table.insert(contents.nodes[1].nodes[1].nodes[4].nodes[1].nodes, simulation_node)
   end

   return contents
end
