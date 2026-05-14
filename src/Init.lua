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
   },
   -- Localization
   loc = {
      ["en-us"] = {
         dv_settings_tab = "Score Preview",
         dv_enable_score = "Enable Score Preview",
         dv_enable_dollars = "Enable Money Preview",
         dv_show_minmax = "Show Min/Max Preview Instead of Exact",
         dv_hide_facedown = "Hide Preview if Any Card is Face-Down",
         dv_manual_trigger = "Manual Trigger for Preview",
         dv_delay_label = "Delay after Manual Trigger",
         dv_delay_info_1 = "In seconds, how long to wait after manual preview was triggered,",
         dv_delay_info_2 = "before showing the preview values. Does nothing if Manual Trigger is off.",
         dv_preview_score_btn = " Preview Score ",
         dv_score_off = "Score Preview Off",
      },
         ru = {
            dv_settings_tab = "Предпросмотр",
            dv_enable_score = "Предпросмотр очков",
         dv_enable_dollars = "Предпросмотр денег",
         dv_show_minmax = "Мин/Макс вместо точных",
         dv_hide_facedown = "Скрывать при закрытых картах",
         dv_manual_trigger = "Ручной запуск",
         dv_delay_label = "Задержка после запуска",
         dv_delay_info_1 = "Задержка в секундах после ручного запуска",
         dv_delay_info_2 = "перед показом результатов. Не работает без ручного режима.",
         dv_preview_score_btn = " Предпросмотр ",
         dv_score_off = "Предпросмотр выкл",
      },
   },
}

DV.PRE.t = function(key)
   local lang = (G.SETTINGS and G.SETTINGS.language == "ru") and "ru" or "en-us"
   return (DV.PRE.loc[lang] and DV.PRE.loc[lang][key]) or (DV.PRE.loc["en-us"][key]) or key
end

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
   G.DV.options[DV.PRE.t('dv_settings_tab')] = "get_preview_settings_page"
end
