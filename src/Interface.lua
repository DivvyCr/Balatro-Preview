--- Divvy's Preview for Balatro - Interface.lua
--
-- The user interface components that display simulation results.

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

--
-- SETTINGS:
--

function DV.get_preview_settings_page()
   local function preview_score_toggle_callback(e)
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

   local function preview_dollars_toggle_callback(_)
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

   local function face_down_toggle_callback(_)
      if not G.HUD then return end

      DV.PRE.data = DV.PRE.simulate()
      G.HUD:recalculate()
   end

   local function minmax_toggle_callback(_)
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

   return
      {n=G.UIT.ROOT, config={align = "cm", padding = 0.05, colour = G.C.CLEAR}, nodes={
          create_toggle({id = "score_toggle",
                         label = "Enable Score Preview",
                         ref_table = G.SETTINGS.DV,
                         ref_value = "preview_score",
                         callback = preview_score_toggle_callback}),
          create_toggle({id = "dollars_toggle",
                         label = "Enable Money Preview",
                         ref_table = G.SETTINGS.DV,
                         ref_value = "preview_dollars",
                         callback = preview_dollars_toggle_callback}),
          create_toggle({label = "Show Min/Max Preview Instead of Exact",
                         ref_table = G.SETTINGS.DV,
                         ref_value = "show_min_max",
                         callback = minmax_toggle_callback}),
          create_toggle({label = "Hide Preview if Any Card is Face-Down",
                         ref_table = G.SETTINGS.DV,
                         ref_value = "hide_face_down",
                         callback = face_down_toggle_callback})
      }}
end
