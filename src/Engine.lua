--- Divvy's Preview for Balatro - Engine.lua
--
-- Chooses which engine produces the preview, and audits the preview against the real score.
--
--   "real"   (default): runs the game's own scoring in a rolled-back sandbox (see Sandbox.lua),
--                       so every mod, joker, card, consumable and game update is counted as is.
--   "legacy":           the original hand-written simulation (DV.SIM, vanilla jokers only).
--                       Used if the real engine is switched off, or as a fallback if it fails.

do

function DV.PRE.setting(name, default)
   local s = G and G.SETTINGS and G.SETTINGS.DV
   if s and s[name] ~= nil then return s[name] end
   return default
end

local function zero_result()
   return {score = {min = 0, exact = 0, max = 0}, dollars = {min = 0, exact = 0, max = 0}}
end

function DV.PRE.run_engine()
   if not G.hand or #G.hand.highlighted < 1 then return zero_result() end

   if DV.PRE.setting("accurate_engine", true) and DV.PRE.SB then
      local ok, res, err = pcall(DV.PRE.SB.run)
      if not ok then DV.PRE.SB.active = false end
      if ok and res then
         DV.PRE.engine_used = "real"
         DV.PRE.engine_note = nil
         return res
      end
      DV.PRE.engine_note = tostring(ok and err or res)
      -- Always say why the accurate engine was not used (once per distinct reason):
      if DV.PRE.engine_note ~= DV.PRE.last_logged_note then
         DV.PRE.last_logged_note = DV.PRE.engine_note
         local fn = rawget(_G, "sendWarnMessage")
         if fn then pcall(fn, "[DVPreview] accurate engine not used: " .. DV.PRE.engine_note, "DVPreview") end
      end
   end

   DV.PRE.engine_used = "legacy"
   if DV.SIM and DV.SIM.run then
      local ok, res = pcall(DV.SIM.run)
      if ok and res then return res end
      -- The legacy engine edits game state while it runs; put it back if it died halfway.
      if DV.SIM.manage_state then pcall(DV.SIM.manage_state, "RESTORE") end
      DV.PRE.engine_note = tostring(res)
   end
   return zero_result()
end

--
-- ACCURACY AUDIT:
--
-- Every time a hand is really played, the preview that was on screen is compared with the score the
-- game actually produced. Results are kept in DV.PRE.audit and appended to DVPreview_audit.log in the
-- Balatro save folder, so any mod combination that still disagrees can be spotted (and reported).
--

DV.PRE.audit = {matched = 0, mismatched = 0, recent = {}, pending = nil, file = "DVPreview_audit.log", bytes = 0}

local function describe_setup()
   local keys = {}
   if G.jokers then
      for _, j in ipairs(G.jokers.cards) do
         keys[#keys + 1] = (j.config and j.config.center and j.config.center.key or "?")
      end
   end
   local cons = {}
   if G.consumeables then
      for _, c in ipairs(G.consumeables.cards) do
         cons[#cons + 1] = (c.config and c.config.center and c.config.center.key or "?")
      end
   end
   local blind = G.GAME and G.GAME.blind and G.GAME.blind.name or "?"
   return "blind=" .. tostring(blind) ..
          " jokers=[" .. table.concat(keys, ",") .. "] consumables=[" .. table.concat(cons, ",") .. "]"
end

local function tonum(x)
   if type(x) == "table" then return DV.PRE.SB and DV.PRE.SB.num(x) or (tonumber(x) or 0) end
   return x or 0
end

-- True from the moment Play is pressed until the hand reaches scoring. During that time the selected
-- cards are leaving the hand, so nothing may be re-simulated and the preview must stay as it was.
function DV.PRE.real_hand_in_flight()
   local started = DV.PRE.real_play_started
   if started then
      if G.TIMERS and G.TIMERS.REAL and G.TIMERS.REAL - started > 20 then
         DV.PRE.real_play_started = nil -- Safety: never stay blocked if the hand never finished scoring.
      else
         return true
      end
   end
   return (G.play and G.play.cards and G.play.cards[1] ~= nil) or false
end

function DV.PRE.audit_before_play()
   local a = DV.PRE.audit
   -- A simulated play (the preview's own hidden test play) must never touch the record of a real one:
   if DV.PRE.SB and DV.PRE.SB.active then return end
   a.pending = nil
   DV.PRE.real_play_started = G.TIMERS and G.TIMERS.REAL or 0
   if not DV.PRE.setting("audit_log", true) then return end
   if not DV.PRE.data or not DV.PRE.data.score then return end
   if G.SETTINGS.DV.manual_preview and not DV.PRE.previewing then return end -- No preview was on screen.
   if not DV.PRE.setting("preview_score", true) then return end

   a.pending = {
      exact = DV.PRE.data.score.exact,
      min = DV.PRE.data.score.min,
      max = DV.PRE.data.score.max,
      engine = DV.PRE.engine_used or "?",
      note = DV.PRE.engine_used == "legacy" and DV.PRE.engine_note or nil,
      setup = describe_setup(),
      hand = G.GAME.current_round and G.GAME.current_round.current_hand and G.GAME.current_round.current_hand.handname or "?",
   }
end

function DV.PRE.audit_after_eval()
   local a = DV.PRE.audit
   if DV.PRE.SB and DV.PRE.SB.active then return end
   DV.PRE.real_play_started = nil -- The real hand has reached scoring; previews may run again.
   local pending = a.pending
   a.pending = nil
   if not pending then return end

   local ok, actual = pcall(function()
      if SMODS and SMODS.calculate_round_score then return SMODS.calculate_round_score() end
      return (rawget(_G, "hand_chips") or 0) * (rawget(_G, "mult") or 0)
   end)
   if not ok then return end
   if type(actual) == "number" then actual = math.floor(actual) end

   local show_range = DV.PRE.setting("show_min_max", false)
   local matched
   if show_range then
      matched = tonum(actual) >= tonum(pending.min) and tonum(actual) <= tonum(pending.max)
   else
      matched = tonum(actual) == tonum(pending.exact)
   end

   if matched then a.matched = a.matched + 1 else a.mismatched = a.mismatched + 1 end

   local ms = DV.PRE.SB and DV.PRE.SB.stats and DV.PRE.SB.stats.last_ms or 0
   local note = pending.note and (" why=" .. tostring(pending.note):gsub("[\r\n]+", " "):sub(1, 300)) or ""
   local line = string.format("%s %s hand=%s engine=%s previewed=%s actual=%s %s%s",
      os.date("%Y-%m-%d %H:%M:%S"), matched and "OK  " or "DIFF", tostring(pending.hand), pending.engine,
      show_range and (tostring(tonum(pending.min)) .. ".." .. tostring(tonum(pending.max))) or tostring(tonum(pending.exact)),
      tostring(tonum(actual)), pending.setup, note)
   a.recent[#a.recent + 1] = line
   if #a.recent > 30 then table.remove(a.recent, 1) end

   -- Only write mismatches in full, to keep the log small; matches are counted in a short line.
   if love and love.filesystem and a.bytes < 262144 then
      local text = (matched and line:sub(1, 120) or line) .. "\n"
      local wrote = pcall(love.filesystem.append, a.file, text)
      if wrote then a.bytes = a.bytes + #text end
   end
end

end
