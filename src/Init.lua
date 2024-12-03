--- Divvy's Preview for Balatro - Init.lua
--
-- Global values that must be present for the rest of this mod to work.

if not DV then DV = {} end

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

if not G.SETTINGS.DV then
   G.SETTINGS.DV = {
      preview_score = true,
      preview_dollars = true,
      hide_face_down = true,
      show_min_max = false
   }
end
