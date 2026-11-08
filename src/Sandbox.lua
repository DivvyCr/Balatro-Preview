--- Divvy's Preview for Balatro - Sandbox.lua
--
-- The "real game" accuracy engine.
--
-- Instead of re-implementing every joker, card and consumable by hand (which can never keep up
-- with mods and game updates), this engine runs the game's OWN play pipeline for the selected
-- cards: G.FUNCS.play_cards_from_highlighted, the event queue it fills, Blind:press_play and
-- G.FUNCS.evaluate_play, including every patch that Steamodded, Lovely and other mods applied
-- to them. Everything runs synchronously inside a rolled-back sandbox:
--
--   1. snapshot every piece of game state the play pipeline can touch (G.GAME, every card and
--      card area, the blind, the deck, tags, scoring parameters, the profile stats, ...),
--   2. swap in a private event manager and time-warp it, so the queued events of a hand play
--      (card moves, blind effects, ...) run in order, instantly, and never reach the real game,
--   3. no-op everything that is only presentation or persistence (sounds, popups, hand text,
--      unlocks, career stats, saving to disk, ...),
--   4. run evaluate_play, read the score exactly the way the game reads it, and capture money
--      that the hand would pay out or cost,
--   5. restore the snapshot, so the preview has no side effects on the run.
--
-- If anything goes wrong, the caller falls back to the legacy engine (DV.SIM).
--
-- Wrapped in do ... end because this file is appended to main.lua (local variable limit).

do

local SB = {}
DV.PRE.SB = SB

local next, type, rawget, rawset, getmetatable, pairs, ipairs, pcall, tostring =
      next, type, rawget, rawset, getmetatable, pairs, ipairs, pcall, tostring

SB.BUDGET_TABLES = 150000 -- Abort the snapshot (before touching anything) past this many tables.
SB.MAX_DEPTH     = 5      -- How deep below a root the snapshot follows plain tables.
-- Keys that lead to static data (card definitions, mod objects), never to run state. Not followed.
SB.skip_keys = {center = true, mod = true, mod_obj = true, atlas_obj = true, original_center = true}
SB.MAX_PASSES    = 80     -- Max passes over the private event queue per simulated play.
SB.TIME_BUDGET   = 0.5    -- Seconds one simulated play may take before it is abandoned.
SB.TIME_WARP     = 1000   -- Seconds added to every game timer per pass, so delayed events fire.
SB.MAX_RESUMES   = 5000   -- Max times scoring coroutines (Talisman, futil, ...) are resumed to completion.

SB.active    = false
SB.disabled  = nil   -- Set to a reason string if the engine switched itself off for the session.
SB.cooldown  = 0     -- Calls left to skip after repeated failures.
SB.fail_streak = 0
SB.stats = {runs = 0, ok = 0, failed = 0, last_ms = 0, avg_ms = 0, last_error = nil, tables = 0}

-- Global functions that only produce presentation or persistence. They are replaced by no-ops
-- for the duration of a simulated play. Other mods can extend the list with SB.register_stub.
SB.stub_globals = {
   -- Sound and visuals:
   "play_sound", "attention_text", "card_eval_status_text", "play_area_status_text",
   "update_hand_text", "juice_card", "juice_card_until", "highlight_card",
   "ease_background_colour", "ease_background_colour_blind",
   -- Persistence, profile and progression:
   "check_for_unlock", "unlock_card", "discover_card", "inc_career_stat", "set_hand_usage",
   "check_and_set_high_score", "set_joker_usage", "set_consumeable_usage", "set_voucher_usage",
   "save_run", "save_with_action",
   -- Input locking:
   "stop_use",
}

-- Settings of other mods that are forced to a value during a simulated play, then put back.
-- (futil/balatro-utils can run scoring asynchronously, which has no place in a synchronous replay.)
SB.setting_overrides = {
   {path = {"futil", "asyncScoring", "gfep"}, value = false},
   {path = {"futil", "asyncScoring", "er"}, value = false},
}

-- Methods (class table, key) that are replaced by no-ops, same idea as above.
SB.stub_methods = {
   {"Card", "juice_up"}, {"Moveable", "juice_up"}, {"Blind", "juice_up"}, {"Blind", "wiggle"},
   {"Game", "save_progress"}, {"Game", "save_settings"}, {"Game", "save_notify"},
}

-- Namespaced functions replaced by no-ops: {"Table", "key"}.
SB.stub_fields = {
   {"SMODS", "juice_up_blind"},
}

-- Extra state that other mods keep outside of G.GAME/cards and want rolled back:
-- SB.register_state("name", function() return saved end, function(saved) ... end)
SB.extra_state = {}

function SB.register_stub(name)
   table.insert(SB.stub_globals, name)
end

function SB.register_state(name, save_fn, restore_fn)
   SB.extra_state[name] = {save = save_fn, restore = restore_fn}
end

local function noop() end

local function log(level, msg)
   msg = "[DVPreview] " .. msg
   local fn = (level == "warn" and rawget(_G, "sendWarnMessage")) or rawget(_G, "sendDebugMessage")
   if fn then pcall(fn, msg, "DVPreview") else print(msg) end
end

local function num(x)
   if type(x) == "table" then
      if x.to_number then
         local ok, v = pcall(x.to_number, x)
         if ok and type(v) == "number" then return v end
      end
      return tonumber(x) or 0
   end
   return x or 0
end
SB.num = num

--
-- SNAPSHOT / RESTORE
--
-- Every plain table reachable from the roots keeps a shallow "shadow" copy of its contents.
-- Restoring writes the shadow back into the very same table, so identity and aliasing are
-- preserved, and tables created during the sandbox simply become unreachable.
--

-- Game objects (Card, CardArea, Blind, Sprite, UIBox, ...) have an `is` method through their class.
local function is_object(t)
   local mt = getmetatable(t)
   if not mt then return false end
   local idx = rawget(mt, "__index")
   if type(idx) == "table" then return type(idx.is) == "function" end
   return false
end

local record_value

local function record_shadow(snap, t, follow_objects, depth)
   snap.seen[t] = true
   local n = snap.n + 1
   snap.n = n
   if n > SB.BUDGET_TABLES then
      error("DVPreview snapshot budget exceeded (" .. SB.BUDGET_TABLES .. " tables) under root " ..
            tostring(snap.root), 0)
   end
   local shadow = {}
   snap.tabs[n] = t
   snap.shad[n] = shadow
   local skip, deeper = SB.skip_keys, depth < SB.MAX_DEPTH
   for k, v in next, t do
      shadow[k] = v
      if deeper and type(v) == "table" and not (type(k) == "string" and skip[k]) then
         record_value(snap, v, follow_objects, depth + 1)
      end
   end
end

-- Follow a value found inside a table that is being recorded.
record_value = function(snap, v, follow_objects, depth)
   if snap.seen[v] then return end
   if is_object(v) then
      -- Objects reached through plain data are only recorded if the caller asked for it
      -- (and then only their own fields, never the objects they point to).
      if follow_objects then record_shadow(snap, v, false, depth) end
   else
      record_shadow(snap, v, follow_objects, depth)
   end
end

local function record_plain(snap, t, follow_objects, root, maxdepth)
   if type(t) == "table" and not snap.seen[t] then
      snap.root = root or snap.root
      record_shadow(snap, t, follow_objects or false, SB.MAX_DEPTH - (maxdepth or SB.MAX_DEPTH))
   end
end

-- Record an object's own fields (and the plain tables they hold), never other objects.
local function record_object(snap, o, root)
   if type(o) == "table" and not snap.seen[o] then
      snap.root = root or snap.root
      record_shadow(snap, o, false, 0)
   end
end

-- Sprites hold the visible face of a card (set_ability changes them), so they are rolled back too.
local function record_sprites(snap, children)
   if type(children) ~= "table" then return end
   for _, child in next, children do
      if type(child) == "table" and not snap.seen[child] and is_object(child) and
         (child.sprite_pos ~= nil or child.atlas ~= nil)
      then
         record_object(snap, child)
      end
   end
end

-- Record the raw field pointers of a table, so replaced or newly created fields get undone.
-- keep_new: only roll back fields that existed already, leave newly defined ones alone (used for _G).
local function record_fields(snap, t, keep_new)
   if type(t) ~= "table" then return end
   local ptrs = {}
   for k, v in next, t do ptrs[k] = v end
   snap.fields[#snap.fields + 1] = {t = t, ptrs = ptrs, keep_new = keep_new}
end

local function restore_table(t, shadow)
   for k in next, t do
      if shadow[k] == nil then rawset(t, k, nil) end
   end
   for k, v in next, shadow do
      if rawget(t, k) ~= v then rawset(t, k, v) end
   end
end

local function restore_fields(f)
   local t, ptrs = f.t, f.ptrs
   if f.keep_new then
      for k, v in next, ptrs do
         if rawget(t, k) ~= v then rawset(t, k, v) end
      end
   else
      restore_table(t, ptrs)
   end
end

function SB.snapshot()
   local snap = {seen = {}, tabs = {}, shad = {}, n = 0, fields = {}, extra = {}}

   -- Run state (money, hands, pseudorandom state, hand levels, mod data, ...). Objects found here
   -- (blind, back, tags, last joker, ...) get their own fields recorded as well.
   record_plain(snap, G.GAME, true, "G.GAME")

   -- Registries that every created node, card and area adds itself to:
   record_plain(snap, G.I, false, "G.I", 1)
   record_plain(snap, G.MOVEABLES, false, "G.MOVEABLES", 1)
   record_plain(snap, G.STAGE_OBJECTS, false, "G.STAGE_OBJECTS", 2)
   record_plain(snap, G.playing_cards, false, "G.playing_cards", 1)
   record_plain(snap, G.TIMERS, false, "G.TIMERS", 1)
   record_plain(snap, G.P_CENTER_POOLS, false, "G.P_CENTER_POOLS", 1)
   if G.CONTROLLER then
      record_plain(snap, G.CONTROLLER.interrupt)
      record_plain(snap, G.CONTROLLER.locks)
   end

   -- Every card and card area in the game, not just the ones this mod knows about:
   if G.I then
      for _, card in ipairs(G.I.CARD or {}) do
         record_object(snap, card, "G.I.CARD")
         record_sprites(snap, card.children)
      end
      for _, area in ipairs(G.I.CARDAREA or {}) do record_object(snap, area, "G.I.CARDAREA") end
   end
   for _, area in ipairs({G.hand, G.play, G.deck, G.discard, G.jokers, G.consumeables}) do
      record_object(snap, area)
   end

   -- Scoring parameters (current chips, mult, and mod-added ones):
   if SMODS then
      for _, param in pairs(SMODS.Scoring_Parameters or {}) do record_object(snap, param, "SMODS.Scoring_Parameters") end
      record_plain(snap, SMODS.last_hand, false, "SMODS.last_hand", 3)
      record_plain(snap, SMODS.drawn_cards, false, "SMODS.drawn_cards", 1)
   end

   -- Profile statistics the play pipeline likes to bump (the functions doing it are also stubbed):
   local profile = G.PROFILES and G.SETTINGS and G.PROFILES[G.SETTINGS.profile]
   if profile then
      record_plain(snap, profile.career_stats, false, "profile", 2)
      record_plain(snap, profile.hand_usage, false, "profile", 2)
      record_plain(snap, profile.high_scores, false, "profile", 2)
   end

   -- Plain flags on the main tables (G.STATE, G.STATE_COMPLETE, SMODS.displayed_hand, ...):
   record_fields(snap, G)
   record_fields(snap, G.FUNCS)
   record_fields(snap, SMODS)
   record_fields(snap, _G, true) -- Globals such as `mult`, `hand_chips`, `percent`, and any hooked function.

   -- Class methods that mods hook while scoring (eg. Card.calculate_joker), so a leaked hook is undone:
   for _, name in ipairs({"Card", "CardArea", "Blind", "Moveable", "Node", "Game", "Back", "Tag"}) do
      record_fields(snap, rawget(_G, name))
   end

   -- State registered by other mods:
   for name, s in pairs(SB.extra_state) do
      local ok, saved = pcall(s.save)
      if ok then snap.extra[name] = {saved = saved} end
   end

   SB.stats.tables = snap.n
   return snap
end

function SB.restore(snap)
   for i = 1, snap.n do restore_table(snap.tabs[i], snap.shad[i]) end
   for i = 1, #snap.fields do restore_fields(snap.fields[i]) end
   for name, e in pairs(snap.extra) do
      local s = SB.extra_state[name]
      if s then pcall(s.restore, e.saved) end
   end
end

-- A cheap fingerprint of the things a player would notice if the rollback were incomplete.
function SB.fingerprint()
   local out = {}
   local function add(x) out[#out + 1] = tostring(x) end
   local G_ = G.GAME
   add(G.STATE); add(G.STATE_COMPLETE)
   add(G_.dollars); add(G_.chips); add(G_.hands_played)
   add(G_.current_round and G_.current_round.hands_left)
   add(G_.current_round and G_.current_round.discards_left)
   add(G_.current_round and G_.current_round.current_hand and G_.current_round.current_hand.handname)
   if G_.pseudorandom then
      local sum = 0
      for k, v in pairs(G_.pseudorandom) do if type(v) == "number" then sum = sum + v end end
      add(sum)
   end
   if G_.hands then
      for name, h in pairs(G_.hands) do add(name); add(h.level); add(h.played); add(h.chips); add(h.mult) end
   end
   for _, area in ipairs({G.hand, G.play, G.deck, G.discard, G.jokers, G.consumeables}) do
      add("#"); add(#area.cards); add(#area.highlighted)
      if area == G.jokers or area == G.consumeables or area == G.hand then
         for _, c in ipairs(area.cards) do
            add(c.sort_id); add(c.highlighted); add(c.debuff); add(c.facing)
            local ab = c.ability
            if ab then
               add(ab.name); add(ab.mult); add(ab.x_mult); add(ab.h_mult); add(ab.bonus); add(ab.perma_bonus)
               add(ab.extra_value)
               if type(ab.extra) == "table" then
                  for k, v in pairs(ab.extra) do
                     if type(v) == "number" or type(v) == "string" or type(v) == "boolean" then add(k); add(v) end
                  end
               elseif ab.extra ~= nil then add(ab.extra) end
            end
            add(c.edition and c.edition.key); add(c.seal)
         end
      end
   end
   return table.concat(out, "|")
end

--
-- ONE SIMULATED PLAY
--

local DONE = {} -- Thrown to unwind out of the event queue as soon as the score has been read.

local function bump_timers(by)
   local timers = G.TIMERS
   for k, v in next, timers do
      if type(v) == "number" then rawset(timers, k, v + by) end
   end
end

-- Events waiting in a manager. Works for the vanilla array queues and for futil's linked queues.
local function queue_size(mgr)
   local n = 0
   for _, q in pairs(mgr.queues) do
      local c = type(q) == "table" and q.count
      n = n + (type(c) == "number" and c or #q)
   end
   return n
end

local function stub(st, tbl, key, fn)
   st.saved[#st.saved + 1] = {tbl, key, rawget(tbl, key)}
   rawset(tbl, key, fn)
end

-- Scoring may be driven by coroutines (Talisman, futil's async scoring, ...) that would normally be
-- resumed frame by frame. A simulated play resumes them until they are done.
local function finish_coroutines(st)
   local resumes = 0
   local i = 1
   while i <= #st.coroutines do
      local co = st.coroutines[i]
      while coroutine.status(co) == "suspended" do
         resumes = resumes + 1
         if resumes > SB.MAX_RESUMES then error("scoring coroutine did not finish", 0) end
         if os.clock() > st.deadline then error("simulated play took too long", 0) end
         local ok, err = coroutine.resume(co)
         if not ok then error(err, 0) end
      end
      i = i + 1 -- Coroutines started while resuming are appended and picked up here.
   end
end

local function install(st, mode)
   st.saved = {}

   for _, name in ipairs(SB.stub_globals) do
      if type(rawget(_G, name)) == "function" then stub(st, _G, name, noop) end
   end
   for _, m in ipairs(SB.stub_methods) do
      local cls = rawget(_G, m[1])
      if type(cls) == "table" and type(cls[m[2]]) == "function" then stub(st, cls, m[2], noop) end
   end
   for _, f in ipairs(SB.stub_fields) do
      local tbl = rawget(_G, f[1])
      if type(tbl) == "table" and type(tbl[f[2]]) == "function" then stub(st, tbl, f[2], noop) end
   end

   -- Settings of other mods that must not apply to a synchronous replay:
   for _, o in ipairs(SB.setting_overrides) do
      local t = G.SETTINGS
      for i = 1, #o.path - 1 do t = type(t) == "table" and t[o.path[i]] or nil end
      local key = o.path[#o.path]
      if type(t) == "table" and t[key] ~= nil then stub(st, t, key, o.value) end
   end

   -- Never let a simulated play write anything to disk:
   local lf = love and love.filesystem
   if lf then
      for _, key in ipairs({"write", "append", "remove"}) do
         if type(lf[key]) == "function" then stub(st, lf, key, function() return true end) end
      end
   end
   if G.SAVE_MANAGER then
      stub(st, G, "SAVE_MANAGER", {channel = {push = noop, pop = noop, peek = noop, supply = noop, demand = noop,
                                               getCount = function() return 0 end}, thread = G.SAVE_MANAGER.thread})
   end
   if G.CONTROLLER then stub(st, G.CONTROLLER, "save_cardarea_focus", noop) end

   -- Once the score is read, every remaining event of the replay is inert:
   local Event_ = rawget(_G, "Event")
   if type(Event_) == "table" and type(Event_.handle) == "function" then
      local real_handle = Event_.handle
      stub(st, Event_, "handle", function(self, res)
         if st.finished then
            if res then res.completed = true; res.time_done = true; res.blocking = false end
            self.complete = true
            return
         end
         return real_handle(self, res)
      end)
   end

   -- Collect coroutines started during the play, so they can be run to completion:
   local real_create = coroutine.create
   stub(st, coroutine, "create", function(f)
      local co = real_create(f)
      st.coroutines[#st.coroutines + 1] = co
      return co
   end)
   stub(st, coroutine, "wrap", function(f)
      local co = real_create(f)
      st.coroutines[#st.coroutines + 1] = co
      return function(...)
         local res = {coroutine.resume(co, ...)}
         if not res[1] then error(res[2], 0) end
         return (unpack or table.unpack)(res, 2)
      end
   end)

   -- Money: record everything the hand pays or costs (the real game applies it through queued events
   -- that a simulated play never reaches), but still run the real function so mods see it happen.
   local real_ease_dollars = rawget(_G, "ease_dollars")
   if type(real_ease_dollars) == "function" then
      stub(st, _G, "ease_dollars", function(mod, ...)
         if mod ~= nil then st.dollars = st.dollars + num(mod) end
         return real_ease_dollars(mod, ...)
      end)
   end

   -- For the minimum and maximum previews, force every dice roll to its extreme:
   if mode.forced then
      stub(st, _G, "pseudorandom", function(seed, min, max)
         if min ~= nil and max ~= nil then return (mode.ranged == "hi") and max or min end
         return (mode.chance == "lo") and 0 or 0.9999999
      end)
   end

   -- The moment scoring is complete, read the result and stop the replay:
   local real_eval = G.FUNCS.evaluate_play
   stub(st, G.FUNCS, "evaluate_play", function(...)
      st.in_eval = true
      local ret = real_eval(...)
      finish_coroutines(st)
      st.in_eval = false
      local score
      if SMODS and type(SMODS.calculate_round_score) == "function" then
         score = SMODS.calculate_round_score()
      else
         score = (rawget(_G, "hand_chips") or 0) * (rawget(_G, "mult") or 0)
      end
      if type(score) == "number" then score = math.floor(score) end
      st.score = score
      st.finished = true
      error(DONE, 0) -- Unwind now; the Event gate above covers a mod that swallows this error.
      return ret
   end)
end

local function uninstall(st)
   for i = #st.saved, 1, -1 do
      local s = st.saved[i]
      rawset(s[1], s[2], s[3])
   end
   st.saved = {}
end

-- Run the real "Play Hand" flow once, in the current (already snapshotted) state.
local function run_mode(mode)
   local st = {finished = false, in_eval = false, dollars = 0, saved = {}, coroutines = {}}
   local real_manager = G.E_MANAGER
   local real_results = G.ARGS and G.ARGS.event_manager_update
   st.deadline = os.clock() + SB.TIME_BUDGET

   -- A fresh manager of the very same kind the game uses (vanilla, futil's, ...):
   st.mgr = (getmetatable(real_manager) or EventManager)()
   G.E_MANAGER = st.mgr
   if G.ARGS then G.ARGS.event_manager_update = {} end -- Do not disturb the real manager's loop.

   local ok, err = pcall(function()
      install(st, mode)
      G.FUNCS.play_cards_from_highlighted(nil)

      -- Replay the queued events (card moves, press_play effects, ...) until scoring has completed.
      local last_size, stalled = -1, 0
      for _ = 1, SB.MAX_PASSES do
         if st.finished then break end
         local size = queue_size(st.mgr)
         if size == 0 then break end
         stalled = (size == last_size) and (stalled + 1) or 0
         if stalled >= 3 then error("event queue stopped making progress", 0) end
         last_size = size
         if os.clock() > st.deadline then error("simulated play took too long", 0) end
         bump_timers(SB.TIME_WARP)
         st.mgr:update(1 / 60, true)
      end
   end)
   if not ok and err == DONE then ok = true end

   uninstall(st)
   G.E_MANAGER = real_manager
   if G.ARGS then G.ARGS.event_manager_update = real_results end

   if not ok then return nil, tostring(err) end
   if not st.finished then return nil, "play flow never reached evaluate_play" end
   return st
end

-- Modes: the exact run uses the game's real random numbers; the others pin every roll to an extreme.
local EXACT = {name = "exact"}
local RANGE = {
   {name = "lucky_high", forced = true, chance = "lo", ranged = "hi"},
   {name = "lucky_low",  forced = true, chance = "lo", ranged = "lo"},
   {name = "unlucky_high", forced = true, chance = "hi", ranged = "hi"},
   {name = "unlucky_low",  forced = true, chance = "hi", ranged = "lo"},
}

function SB.can_run()
   if SB.disabled then return false, "disabled: " .. SB.disabled end
   if SB.active then return false, "already running" end
   if not (G and G.GAME and G.GAME.blind and G.hand and G.play and G.jokers and G.consumeables
           and G.E_MANAGER and G.FUNCS and G.FUNCS.play_cards_from_highlighted and G.FUNCS.evaluate_play
           and (getmetatable(G.E_MANAGER) or EventManager) and Event and G.TIMERS)
   then return false, "game not ready" end
   if G.SETTINGS and G.SETTINGS.paused then return false, "paused" end
   if G.play.cards[1] then return false, "play area busy" end
   -- A real hand is being played right now: never run a simulated one in the middle of it.
   if G.STATES and G.STATE == G.STATES.HAND_PLAYED then return false, "real hand in progress" end
   if DV.PRE.real_hand_in_flight and DV.PRE.real_hand_in_flight() then return false, "real hand in progress" end
   if #G.hand.highlighted < 1 then return false, "nothing selected" end
   return true
end

--- Returns {score = {min, exact, max}, dollars = {min, exact, max}} or nil and the reason.
function SB.run()
   if SB.cooldown > 0 then
      SB.cooldown = SB.cooldown - 1
      return nil, "cooling down after repeated failures: " .. tostring(SB.stats.last_error)
   end
   local ok_can, can, why = pcall(SB.can_run)
   if not ok_can then return nil, "can_run: " .. tostring(can) end
   if not can then return nil, why end

   local want_range = G.SETTINGS and G.SETTINGS.DV and G.SETTINGS.DV.show_min_max
   local started = os.clock()
   SB.stats.runs = SB.stats.runs + 1

   local ok_snap, snap = pcall(SB.snapshot)
   if not ok_snap then
      SB.stats.failed = SB.stats.failed + 1
      SB.stats.last_error = "snapshot: " .. tostring(snap)
      return nil, SB.stats.last_error
   end
   local ok_fp, before = pcall(SB.fingerprint)
   if not ok_fp then
      SB.stats.failed = SB.stats.failed + 1
      SB.stats.last_error = "fingerprint: " .. tostring(before)
      return nil, SB.stats.last_error
   end

   SB.active = true
   local exact, range_runs, err = nil, {}, nil
   local ok_run, run_err = pcall(function()
      local st, e = run_mode(EXACT)
      if not st then err = e; return end
      exact = st
      if want_range then
         for _, mode in ipairs(RANGE) do
            SB.restore(snap)
            local rs = run_mode(mode)
            if rs then range_runs[#range_runs + 1] = rs end -- A failed extreme just narrows the range.
         end
      end
   end)
   local ok_restore, restore_err = pcall(SB.restore, snap)
   SB.active = false

   -- Verify the rollback; if the game state is not exactly as before, never run again this session.
   local ok_fp2, after = pcall(SB.fingerprint)
   if not ok_restore or not ok_fp2 or after ~= before then
      SB.disabled = "state was not restored exactly (" .. tostring(restore_err or "fingerprint mismatch") .. ")"
      SB.stats.last_error = SB.disabled
      log("warn", "Accuracy engine switched off for this session: " .. SB.disabled)
      SB.stats.failed = SB.stats.failed + 1
      return nil, SB.disabled
   end

   if not ok_run or not exact then
      local msg = tostring(err or run_err)
      SB.stats.failed = SB.stats.failed + 1
      SB.fail_streak = SB.fail_streak + 1
      if msg ~= SB.stats.last_error then log("warn", "Simulated play failed, using legacy engine: " .. msg) end
      SB.stats.last_error = msg
      if SB.fail_streak >= 3 then SB.cooldown = 25 end
      return nil, msg
   end

   SB.fail_streak = 0
   SB.stats.ok = SB.stats.ok + 1
   local ms = (os.clock() - started) * 1000
   SB.stats.last_ms = ms
   SB.stats.avg_ms = SB.stats.avg_ms == 0 and ms or (SB.stats.avg_ms * 0.9 + ms * 0.1)

   -- Assemble exact/min/max:
   local score = {min = exact.score, exact = exact.score, max = exact.score}
   local dollars = {min = exact.dollars, exact = exact.dollars, max = exact.dollars}
   for _, rs in ipairs(range_runs) do
      if num(rs.score) < num(score.min) then score.min = rs.score end
      if num(rs.score) > num(score.max) then score.max = rs.score end
      if rs.dollars < dollars.min then dollars.min = rs.dollars end
      if rs.dollars > dollars.max then dollars.max = rs.dollars end
   end
   return {score = score, dollars = dollars}
end

end
