--- Divvy's Preview for Balatro - Init.lua
--
-- Global values that must be present for the rest of this mod to work.

if not DV then DV = {} end

if DV.PRE then error("Cannot load Divvy's Preview multiple times!") end

DV.PRE = {
   data = {
      score = {min = 0, exact = 0, max = 0},
      dollars = {min = 0, exact = 0, max = 0}
   },
   text = {
      score = {l = "", r = ""},
      dollars = {top = "", bot = ""},
      delay_timer = "0.0"
   },
   joker_order = {},
   hand_order = {},
   delay = {
      active = false,
      start = 0
   }
}

DV.PRE._start_up = Game.start_up
function Game:start_up()
   DV.PRE._start_up(self)

   if not G.SETTINGS.DV then G.SETTINGS.DV = {} end
   if not G.SETTINGS.DV.PRE then
      G.SETTINGS.DV.PRE = true

      G.SETTINGS.DV.preview_score = true
      G.SETTINGS.DV.preview_dollars = true
      G.SETTINGS.DV.hide_face_down = true
      G.SETTINGS.DV.show_min_max = false
      G.SETTINGS.DV.manual_preview = false
      G.SETTINGS.DV.delay_length = 5
   end

   if not DV.settings then error("Divvy's Preview requires Divvy's Setting tools; re-install Divvy's Preview mod and double-check that there is a 'DVSettings' folder") end
   G.DV.options["Score Preview"] = "get_preview_settings_page"
end
