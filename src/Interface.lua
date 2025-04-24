--- Divvy's Preview for Balatro - Interface.lua
--
-- The user interface components that display simulation results.

-- Append node for preview text to the HUD:
local orig_hud = create_UIBox_HUD
function create_UIBox_HUD()
   local contents = orig_hud()

   local score_node_wrap = {n=G.UIT.R, config={id = "dv_pre_score_wrap", align = "cm", padding = 0.1}, nodes={}}
   if DV.PRE.enabled() then
      if G.SETTINGS.DV.manual_preview then
         table.insert(score_node_wrap.nodes, DV.PRE.get_manual_preview_button())
      else
         table.insert(score_node_wrap.nodes, DV.PRE.get_score_node())
      end
   end
   table.insert(contents.nodes[1].nodes[1].nodes[4].nodes[1].nodes, score_node_wrap)

   local dollars_node_wrap = {n=G.UIT.C, config={id = "dv_pre_dollars_wrap", align = "cm"}, nodes={}}
   if G.SETTINGS.DV.preview_dollars then table.insert(dollars_node_wrap.nodes, DV.PRE.get_dollars_node()) end
   table.insert(contents.nodes[1].nodes[1].nodes[5].nodes[2].nodes[3].nodes[1].nodes[1].nodes[1].nodes, dollars_node_wrap)

   return contents
end

function DV.PRE.get_score_node()
   -- TODO: Improve special case handling here. Possible to call G.FUNCS.dv_pre_score_UI_set(e) ?

   local text_colour = G.C.UI.TEXT_LIGHT
   local ui_scale = DV.PRE.get_score_ui_scale()

   -- This handles 'Score Preview Off' text (if present):
   if not G.SETTINGS.DV.preview_score then
      text_colour = lighten(G.C.GREY, 0.33)
      ui_scale.text_scale = 0.5
   end

   return {n = G.UIT.C, config = {id = "dv_pre_score", align = "cm", minh = ui_scale.node_height}, nodes={
              {n=G.UIT.O, config={id = "dv_pre_l", func = "dv_pre_score_UI_set", object = DynaText({string = {{ref_table = DV.PRE.text.score, ref_value = "l"}}, colours = {text_colour}, shadow = true, float = true, scale = ui_scale.text_scale})}},
              {n=G.UIT.O, config={id = "dv_pre_r", func = "dv_pre_score_UI_set", object = DynaText({string = {{ref_table = DV.PRE.text.score, ref_value = "r"}}, colours = {text_colour}, shadow = true, float = true, scale = ui_scale.text_scale})}},
   }}
end

function DV.PRE.get_timer_node()
   local ui_scale = DV.PRE.get_score_ui_scale()

   return {n = G.UIT.C, config={id = "dv_pre_timer", align = "cm", minh = ui_scale.node_height}, nodes={
              {n=G.UIT.O, config={id = "dv_pre_timer_text", func = "dv_pre_timer_UI_set", object = DynaText({string = {{ref_table = DV.PRE.text, ref_value = "delay_timer"}}, colours = {lighten(G.C.GREY, 0.33)}, shadow = true, float = true, scale = ui_scale.text_scale})}}
   }}
end

function DV.PRE.get_dollars_node()
   local top_color = DV.PRE.get_dollar_colour(0)
   local bot_color = top_color
   if DV.PRE.data ~= nil then
      top_color = DV.PRE.get_dollar_colour(DV.PRE.data.dollars.max)
      bot_color = DV.PRE.get_dollar_colour(DV.PRE.data.dollars.min)
   else
   end
   return {n=G.UIT.C, config={id = "dv_pre_dollars", align = "cm"}, nodes={
       {n=G.UIT.R, config={align = "cm"}, nodes={
           {n=G.UIT.O, config={id = "dv_pre_dollars_top", func = "dv_pre_dollars_UI_set", object = DynaText({string = {{ref_table = DV.PRE.text.dollars, ref_value = "top"}}, colours = {top_color}, shadow = true, spacing = 2, bump = true, scale = 0.5})}}
       }},
       {n=G.UIT.R, config={minh = 0.05}, nodes={}},
       {n=G.UIT.R, config={align = "cm"}, nodes={
           {n=G.UIT.O, config={id = "dv_pre_dollars_bot", func = "dv_pre_dollars_UI_set", object = DynaText({string = {{ref_table = DV.PRE.text.dollars, ref_value = "bot"}}, colours = {bot_color}, shadow = true, spacing = 2, bump = true, scale = 0.5})}},
       }}
   }}
end

function DV.PRE.get_manual_preview_button()
   local ui_scale = DV.PRE.get_score_ui_scale()

   return {n=G.UIT.C, config={id = "dv_pre_manual_button", button = "dv_pre_manual_run", align = "cm", minh = ui_scale.node_height, padding = 0.05, r = 0.02, colour = G.C.RED, hover = true, shadow = true}, nodes={
      {n=G.UIT.R, config={align = "cm"}, nodes={
         {n=G.UIT.T, config={text = " Preview Score ", colour = G.C.UI.TEXT_LIGHT, shadow = true, scale = 0.36}}
      }}
   }}
end

--
-- SETTINGS:
--

function DV.get_preview_settings_page()
   local function update_manual_preview(_)
      if not G.HUD then return end

      local manual_button = G.HUD:get_UIE_by_ID("dv_pre_manual_button")
      local score_node = G.HUD:get_UIE_by_ID("dv_pre_score")

      if DV.PRE.enabled() and G.SETTINGS.DV.manual_preview
      then -- Manual preview was just enabled, so remove score and add button:

         if score_node then score_node.parent:remove() end

         if not manual_button then
            G.HUD:add_child(DV.PRE.get_manual_preview_button(), G.HUD:get_UIE_by_ID("dv_pre_score_wrap"))
         end

      else -- Manual preview was just disabled, so remove button and add score:

         if manual_button then manual_button.parent:remove() end

         if G.SETTINGS.DV.preview_score and not score_node then
            G.HUD:add_child(DV.PRE.get_score_node(), G.HUD:get_UIE_by_ID("dv_pre_score_wrap"))
         end

      end
      G.HUD:recalculate()
   end

   local function update_preview_score(_)
      if not G.HUD then return end

      if G.SETTINGS.DV.preview_score and not G.SETTINGS.DV.manual_preview
      then -- Preview was just enabled, so add score:
         G.HUD:add_child(DV.PRE.get_score_node(), G.HUD:get_UIE_by_ID("dv_pre_score_wrap"))
         DV.PRE.data = DV.PRE.simulate()
      else -- Preview was just disabled, so remove preview node:
         local score_node = G.HUD:get_UIE_by_ID("dv_pre_score")
         if score_node then score_node.parent:remove() end
      end

      update_manual_preview() -- Handle manual trigger, if necessary
      G.HUD:recalculate()
   end

   local function update_preview_dollars(_)
      if not G.HUD then return end

      if G.SETTINGS.DV.preview_dollars
      then -- Preview was just enabled, so add preview node:
         G.HUD:add_child(DV.PRE.get_dollars_node(), G.HUD:get_UIE_by_ID("dv_pre_dollars_wrap"))
         DV.PRE.data = DV.PRE.simulate()
      else -- Preview was just disabled, so remove preview node:
         local dollars_node = G.HUD:get_UIE_by_ID("dv_pre_dollars")
         if dollars_node then dollars_node.parent:remove() end
      end

      update_manual_preview() -- Handle manual trigger, if necessary
      G.HUD:recalculate()
   end

   local function toggle_face_down(_)
      if not G.HUD or not DV.PRE.enabled() then return end

      DV.PRE.data = DV.PRE.simulate()
      G.HUD:recalculate()
   end

   local function toggle_minmax(_)
      if not G.HUD or not DV.PRE.enabled() then return end

      DV.PRE.data = DV.PRE.simulate()

      local manual_button = G.HUD:get_UIE_by_ID("dv_pre_manual_button")
      if not G.SETTINGS.DV.show_min_max
      then -- Min-Max was just disabled, so increase scale:
         if not manual_button then
            G.HUD:get_UIE_by_ID("dv_pre_l").config.object.scale = 0.75
            G.HUD:get_UIE_by_ID("dv_pre_r").config.object.scale = 0.75
         else
            manual_button.config.minh = 0.62
         end
      else -- Min-Max was just enabled, so decrease scale:
         if not manual_button then
            G.HUD:get_UIE_by_ID("dv_pre_l").config.object.scale = 0.5
            G.HUD:get_UIE_by_ID("dv_pre_r").config.object.scale = 0.5
         else
            manual_button.config.minh = 0.42
         end
      end
      G.HUD:recalculate()
   end

   local delay_options = {0, 3, 5, 10, 15, 20, 30}

   local function option_val2idx(options, val, default)
      for i, v in ipairs(options) do
         if v == val then return i end
      end
      return default
   end

   return
      {n=G.UIT.ROOT, config={align = "cm", padding = 0.05, colour = G.C.CLEAR}, nodes={
          create_toggle({id = "score_toggle",
                         label = "Enable Score Preview",
                         ref_table = G.SETTINGS.DV,
                         ref_value = "preview_score",
                         callback = update_preview_score}),
          create_toggle({id = "dollars_toggle",
                         label = "Enable Money Preview",
                         ref_table = G.SETTINGS.DV,
                         ref_value = "preview_dollars",
                         callback = update_preview_dollars}),
          create_toggle({label = "Show Min/Max Preview Instead of Exact",
                         ref_table = G.SETTINGS.DV,
                         ref_value = "show_min_max",
                         callback = toggle_minmax}),
          create_toggle({label = "Hide Preview if Any Card is Face-Down",
                         ref_table = G.SETTINGS.DV,
                         ref_value = "hide_face_down",
                         callback = toggle_face_down}),
          create_toggle({label = "Manual Trigger for Preview",
                         ref_table = G.SETTINGS.DV,
                         ref_value = "manual_preview",
                         callback = update_manual_preview}),
          create_option_cycle({opt_callback = "dv_pre_set_delay_length",
                               label = "Delay after Manual Trigger",
                               options = delay_options,
                               current_option = option_val2idx(delay_options, G.SETTINGS.DV.delay_length, 3),
                               scale = 0.8,
                               info = {
                                  "In seconds, how long to wait after manual preview was triggered,",
                                  "before showing the preview values. Does nothing if Manual Trigger is off."
                               }})
      }
   }
end

function G.FUNCS.dv_pre_set_delay_length(args)
   G.SETTINGS.DV.delay_length = args.to_val
end
