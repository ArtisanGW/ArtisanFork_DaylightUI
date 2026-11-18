-- Debug only, not for release. /listed mappace times every frame while the world
-- map (with the quest log) opens and closes 3 times in 20 seconds, to find what
-- makes it hitch. For each frame: its length, the time all addons and each
-- loaded addon spent in it (C_AddOnProfiler) and memory made. Prints a summary
-- per open and close, and keeps
-- the last runs in DevMapPaceDB.mapPace, which the game saves on /reload.
--   /listed mappace          opens and closes the map itself (out of combat)
--   /listed mappace manual   you press M: open/close it 3 times in the 20 seconds
--   /listed mappace deep     automatic, and also times the game's own map steps
--                         (each map data provider, overlay and the game's quest
--                         list), to see where the game's part of the hitch goes.
--                         Runs twice in a row: with the game's quest pins on,
--                         then with them off (the questPOI setting, put back
--                         after, or at the next login if a reload cut the run
--                         short)
--   /listed mappace clear    empties the saved runs
-- The automatic run closes the map from addon code, and deep puts timers on the
-- game's map: every run ends asking for a /reload (see reloadSoon), which writes
-- the results and clears the taint.

-- A vanilla addon: it uses only the game, never another addon. Its own events,
-- slash command (/mappace) and saved variables (DevMapPaceDB).
local events, handlers = CreateFrame("Frame"), {}
events:SetScript("OnEvent", function(_, event, ...)
    for _, fn in ipairs(handlers[event]) do fn(event, ...) end
end)
local function on(event, fn)
    if not handlers[event] then handlers[event] = {}; events:RegisterEvent(event) end
    table.insert(handlers[event], fn)
end
-- Runs fn now, or once the fight is over.
local function afterCombat(fn)
    if not InCombatLockdown() then return fn() end
    local done = false
    on("PLAYER_REGEN_ENABLED", function() if not done then done = true; fn() end end)
end
local function store()
    _G.DevMapPaceDB = type(_G.DevMapPaceDB) == "table" and _G.DevMapPaceDB or {}
    return _G.DevMapPaceDB
end
local function command(fn)
    _G["SLASH_DEVMAPPACE1"] = "/mappace"
    SlashCmdList["DEVMAPPACE"] = function(msg) fn(msg or "") end
end

local Pace = {
    LENGTH = 20,          -- seconds per run
    -- seconds into the run: open, close, open, close, open, close
    STEPS = { 1, 4, 7.5, 10.5, 14, 17 },
    AFTER = 1,            -- seconds after an open or close that count towards it
    HITCH = 25,           -- ms: frames longer than this are kept in full
    RUNS = 5,             -- runs kept in the saved variables
    MAX_HITCHES = 60,     -- frames kept in full per run
}

local frame = CreateFrame("Frame")
frame:Hide()
Pace.frame = frame
local run              -- the run in progress
local spent = {}       -- "what" -> ms this frame, from the timed functions
local calls = {}       -- "what" -> times called this frame
local stacks = {}      -- "what" -> { [stack] = times }, for the functions asked to (deep)
local undo = {}        -- functions to put back when the run ends

local function report(text) print("mappace: " .. text) end

-- The end of the runs: a reload writes the results to disk and clears the map's
-- taint. Addon code can't call ReloadUI on this client, so it asks for /reload.
local function reloadSoon()
    report("saved: /reload to write the results (and clear the map's taint)")
end

local function db()
    local root = store()
    root.mapPace = root.mapPace or { runs = {} }
    root.mapPace.runs = root.mapPace.runs or {}
    return root.mapPace
end

local function now() return debugprofilestop() end

local function mapShown()
    local m = _G.WorldMapFrame
    return type(m) == "table" and m:IsShown() == true
end

-- Timing a function: t[key] is replaced by a timed copy until the run ends, then
-- set back to what t itself held (nil for a method it got from its mixin).
-- Errors pass through as they were; a nested call counts twice, fine here.
local function wrap(t, key, label, keepStack)
    if type(t) ~= "table" then return end
    local okGet, orig = pcall(function() return t[key] end)
    if not okGet or type(orig) ~= "function" then return end
    local raw = rawget(t, key)
    local function finish(t0, ok, ...)
        spent[label] = (spent[label] or 0) + (now() - t0)
        if not ok then error((...), 0) end
        return ...
    end
    local function timed(...)
        calls[label] = (calls[label] or 0) + 1
        if keepStack and debugstack then
            local st = stacks[label] or {}
            stacks[label] = st
            local trace = debugstack(2, 14, 0) or "?"
            st[trace] = (st[trace] or 0) + 1
        end
        return finish(now(), pcall(orig, ...))
    end
    t[key] = timed
    undo[#undo + 1] = function() if rawget(t, key) == timed then t[key] = raw end end
end

-- The game's mixin a map piece was made from, by its methods: "QuestDataProvider".
local mixinOf
local function mixinName(o, key)
    if not mixinOf then
        mixinOf = {}
        for name, v in pairs(_G) do
            if type(name) == "string" and name:find("Mixin$") and type(v) == "table" then
                pcall(function() for k, fn in pairs(v) do
                    if type(fn) == "function" then
                        local byKey = mixinOf[k] or {}
                        mixinOf[k] = byKey
                        -- the most specific mixin wins over a base one sharing the function
                        local had = byKey[fn]
                        if not had or (had:find("^MapCanvas") and not name:find("^MapCanvas")) then byKey[fn] = name end
                    end
                end end)
            end
        end
    end
    local fn = o[key]
    local name = mixinOf[key] and mixinOf[key][fn]
    if name then return (name:gsub("Mixin$", "")) end
    local okName, n = pcall(function() return o.GetName and o:GetName() end)
    return okName and type(n) == "string" and n or tostring(o):gsub("^table: ", "")
end

-- The game's own map steps, for /listed mappace deep.
local function wrapGame()
    local m = _G.WorldMapFrame
    if type(m) ~= "table" then return end
    for _, k in ipairs({ "OnShow", "OnHide", "OnMapChanged", "RefreshAll", "RefreshAllDataProviders", "RefreshOverlayFrames",
                         "RefreshDetailLayers", "SynchronizeDisplayState", "UpdateMaximizedSize", "UpdateSpacerFrameAnchoring" }) do
        wrap(m, k, "map." .. k)
    end
    local providers = {}
    if type(m.dataProviders) == "table" then
        for p in pairs(m.dataProviders) do providers[#providers + 1] = p end
    end
    for _, p in ipairs(providers) do
        if type(p) == "table" then
            local name = mixinName(p, "RefreshAllData")   -- before its methods are timed
            for _, k in ipairs({ "RefreshAllData", "OnShow", "OnHide", "OnMapChanged", "RemoveAllData" }) do
                if type(p[k]) == "function" then wrap(p, k, "provider." .. name .. "." .. k) end
            end
        end
    end
    -- who rebuilds the game's quest list, and how often
    wrap(m, "RemoveAllPinsByTemplate", "map.RemoveAllPinsByTemplate")
    wrap(m, "AcquirePin", "map.AcquirePin")
    for _, o in ipairs(type(m.overlayFrames) == "table" and m.overlayFrames or {}) do
        if type(o) == "table" and type(o.Refresh) == "function" then wrap(o, "Refresh", "overlay." .. mixinName(o, "Refresh") .. ".Refresh") end
    end
    for _, k in ipairs({ "QuestLogQuests_Update", "QuestMapFrame_UpdateAll", "QuestMapFrame_ShowQuestDetails",
                         "QuestMapFrame_OnShow", "QuestMapFrame_OnHide", "QuestMapFrame_UpdateQuestSessionState" }) do
        wrap(_G, k, "questlog." .. k, k == "QuestLogQuests_Update")
    end
    local qm = _G.QuestMapFrame
    if type(qm) == "table" then
        for _, k in ipairs({ "OnShow", "OnHide", "SetDisplayMode", "ValidateTabs", "UpdateQuestSessionState", "RefreshTabs" }) do
            wrap(qm, k, "questlog.QuestMapFrame." .. k)
        end
    end
    report(string.format("timing %d map providers, %d overlays", #providers, type(m.overlayFrames) == "table" and #m.overlayFrames or 0))
end


-- Nothing of another addon is timed: deep times the game's own map steps (wrapGame).
local function wrapAll() end

local function unwrapAll()
    for i = #undo, 1, -1 do undo[i]() end
    undo = {}
end

-- Every loaded addon, for the profiler.
local function addonNames()
    local out = {}
    local n = C_AddOns and C_AddOns.GetNumAddOns and C_AddOns.GetNumAddOns() or 0
    for i = 1, n do
        local name = C_AddOns.GetAddOnInfo(i)
        if type(name) == "string" and (not C_AddOns.IsAddOnLoaded or C_AddOns.IsAddOnLoaded(name)) then out[#out + 1] = name end
    end
    return out
end

local function profiler()
    local P, E = _G.C_AddOnProfiler, Enum and Enum.AddOnProfilerMetric
    if not (P and E and P.GetAddOnMetric and E.LastTime) then return nil end
    if P.IsEnabled and not P.IsEnabled() then return nil end
    return P, E.LastTime
end

-- Everything known about the frame that just ended.
local function sample(dt)
    local r = run
    local s = { t = (now() - r.start) / 1000, dt = dt, map = mapShown() }
    local P, M = profiler()
    if P then
        local ok, v = pcall(P.GetOverallMetric, M)
        s.addons = ok and type(v) == "number" and v or nil
        local listed, per = 0, {}
        for _, name in ipairs(r.addons) do
            local ok2, w = pcall(P.GetAddOnMetric, name, M)
            if ok2 and type(w) == "number" and w > 0 then
                listed = listed + w
                per[name] = w
            end
        end
        s.listed, s.per = listed, per
    end
    local kb = collectgarbage("count")
    s.kb = kb - r.kb
    r.kb = kb
    if next(spent) then
        s.spent = spent
        spent = {}
    end
    if next(calls) then
        s.calls = calls
        calls = {}
    end
    return s
end

-- The whole open or close call, the game's part included.
local function act(i)
    if InCombatLockdown() then return end
    local t0 = now()
    if i % 2 == 1 then
        if C_Map and C_Map.OpenWorldMap then pcall(C_Map.OpenWorldMap) end
        spent["call.open"] = (spent["call.open"] or 0) + (now() - t0)
    elseif mapShown() then
        if type(HideUIPanel) == "function" then pcall(HideUIPanel, _G.WorldMapFrame)
        else pcall(_G.WorldMapFrame.Hide, _G.WorldMapFrame) end
        spent["call.close"] = (spent["call.close"] or 0) + (now() - t0)
    end
end

local function fmt(n) return n and string.format("%.1f", n) or "-" end

local function topSpent(list, n)
    local sum = {}
    for _, s in ipairs(list) do
        for what, ms in pairs(s.spent or {}) do sum[what] = (sum[what] or 0) + ms end
    end
    local keys = {}
    for k in pairs(sum) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return sum[a] > sum[b] end)
    local parts = {}
    for i = 1, math.min(n, #keys) do parts[i] = string.format("%s %.1f", keys[i], sum[keys[i]]) end
    return table.concat(parts, ", ")
end

-- Deep: how often the game's quest list and pins were rebuilt.
local function topCalls(list)
    local sum = {}
    for _, s in ipairs(list) do
        for what, n in pairs(s.calls or {}) do sum[what] = (sum[what] or 0) + n end
    end
    local parts = {}
    for _, k in ipairs({ "questlog.QuestLogQuests_Update", "map.RemoveAllPinsByTemplate", "map.AcquirePin",
                         "provider.QuestDataProvider.RefreshAllData", "map.RefreshAllDataProviders" }) do
        if sum[k] then parts[#parts + 1] = string.format("%s x%d", k:gsub("^%w+%.", ""), sum[k]) end
    end
    return table.concat(parts, ", ")
end

-- A summary of the frames from an open or close up to Pace.AFTER seconds later.
local function window(r, mark)
    local list = {}
    for _, s in ipairs(r.frames) do
        if s.t >= mark.t and s.t < mark.t + Pace.AFTER then list[#list + 1] = s end
    end
    local worst, total, addons, listed, kb = nil, 0, 0, 0, 0
    for _, s in ipairs(list) do
        if not worst or s.dt > worst.dt then worst = s end
        total = total + s.dt
        addons = addons + (s.addons or 0)
        listed = listed + (s.listed or 0)
        kb = kb + math.max(0, s.kb or 0)
    end
    return {
        what = mark.what, t = mark.t, frames = #list,
        worst = worst and worst.dt, worstAddons = worst and worst.addons, worstListed = worst and worst.listed,
        addons = addons, listed = listed, kb = kb, top = topSpent(list, r.mode == "deep" and 10 or 5),
        calls = r.mode == "deep" and topCalls(list) or nil,
    }
end

local function percentile(sorted, p)
    if #sorted == 0 then return nil end
    return sorted[math.max(1, math.ceil(#sorted * p))]
end

local function finish()
    local r = run
    run = nil
    frame:Hide()
    unwrapAll()
    local dts = {}
    for i, s in ipairs(r.frames) do dts[i] = s.dt end
    table.sort(dts)
    local out = {
        when = date("%Y-%m-%d %H:%M:%S"), mode = r.mode, label = r.label, frames = #r.frames,
        median = percentile(dts, 0.5), p95 = percentile(dts, 0.95), p99 = percentile(dts, 0.99),
        max = dts[#dts], over33 = 0, over50 = 0, profiler = profiler() ~= nil,
        steps = {}, hitches = {}, dt = {}, stacks = {},
    }
    for _, d in ipairs(dts) do
        if d > 33.4 then out.over33 = out.over33 + 1 end
        if d > 50 then out.over50 = out.over50 + 1 end
    end
    report(string.format("%d frames, median %sms, p95 %sms, p99 %sms, worst %sms, >33ms %d, >50ms %d%s",
        out.frames, fmt(out.median), fmt(out.p95), fmt(out.p99), fmt(out.max), out.over33, out.over50,
        out.profiler and "" or " (addon profiler off: no addon times)"))
    for _, mark in ipairs(r.marks) do
        local w = window(r, mark)
        out.steps[#out.steps + 1] = w
        if w.calls and w.calls ~= "" then report(w.what .. " calls: " .. w.calls) end
        report(string.format("%s at %.1fs: worst frame %sms (all addons %s, each summed %s), next %ds: all addons %sms, each summed %sms, %d KB made%s",
            w.what, w.t, fmt(w.worst), fmt(w.worstAddons), fmt(w.worstListed), Pace.AFTER, fmt(w.addons), fmt(w.listed),
            math.floor(w.kb), w.top ~= "" and (" | " .. w.top) or ""))
    end
    -- the worst frames in full, and every frame's length in short
    local byLength = {}
    for _, s in ipairs(r.frames) do if s.dt > Pace.HITCH then byLength[#byLength + 1] = s end end
    table.sort(byLength, function(a, b) return a.dt > b.dt end)
    for i = 1, math.min(Pace.MAX_HITCHES, #byLength) do out.hitches[i] = byLength[i] end
    table.sort(out.hitches, function(a, b) return a.t < b.t end)
    local parts = {}
    for i, s in ipairs(r.frames) do parts[i] = string.format("%.1f", s.dt) end
    out.dt = table.concat(parts, ",")
    -- the callers, most frequent first
    for label, st in pairs(stacks) do
        local list = {}
        for trace, n in pairs(st) do list[#list + 1] = { n = n, trace = trace } end
        table.sort(list, function(a, b) return a.n > b.n end)
        local keep = {}
        for i = 1, math.min(6, #list) do keep[i] = list[i] end
        out.stacks[label] = keep
    end
    stacks = {}
    local d = db()
    if d then
        table.insert(d.runs, 1, out)
        while #d.runs > Pace.RUNS do table.remove(d.runs) end
        if not r.after then
            reloadSoon()
        end
    end
    if r.after then r.after() end
end

frame:SetScript("OnUpdate", function()
    local r = run
    if not r then frame:Hide(); return end
    local t = now()
    local dt = t - r.last
    r.last = t
    r.frames[#r.frames + 1] = sample(dt)
    local at = (t - r.start) / 1000
    if r.auto then
        local nextStep = Pace.STEPS[r.step + 1]
        if nextStep and at >= nextStep then
            r.step = r.step + 1
            act(r.step)
        end
    end
    local shown = mapShown()
    if shown ~= r.shown then
        r.shown = shown
        r.marks[#r.marks + 1] = { what = shown and "open" or "close", t = at }
    end
    if at >= Pace.LENGTH then finish() end
end)

function Pace.Start(mode, label, after)
    if run then report("already running"); return end
    local auto = mode ~= "manual"
    if auto and InCombatLockdown() then report("not in combat"); return end
    if auto and mapShown() then
        report("close the map first")
        return
    end
    wrapAll()
    if mode == "deep" then wrapGame() end
    local t = now()
    run = { mode = mode, auto = auto, label = label, after = after, start = t, last = t, step = 0, frames = {}, marks = {}, shown = mapShown(),
            kb = collectgarbage("count"), addons = addonNames() }
    spent, calls, stacks = {}, {}, {}
    frame:Show()
    if not profiler() then report("the game's addon profiler is off: frame times only") end
    report(auto and string.format("running %ds%s, the map opens and closes 3 times", Pace.LENGTH, label and (" (" .. label .. ")") or "")
        or string.format("running %ds: open and close the map (M) 3 times", Pace.LENGTH))
    return true
end

-- Deep's second run: the game's quest pins off, put back afterwards.
local function poiBack()
    local d = db()
    if d and d.poiWas ~= nil then
        if InCombatLockdown() then
            afterCombat(poiBack)
            return
        end
        if type(SetCVar) == "function" then pcall(SetCVar, "questPOI", d.poiWas) end
        report("the game's quest pins are back (questPOI " .. tostring(d.poiWas) .. ")")
        d.poiWas = nil
    end
end

local function secondRun()
    if InCombatLockdown() then report("combat: second run skipped"); return end
    local d = db()
    local was = type(GetCVar) == "function" and GetCVar("questPOI") or nil
    if d and was ~= nil then d.poiWas = was end
    if type(SetCVar) == "function" then pcall(SetCVar, "questPOI", "0") end
    local started = Pace.Start("deep", "quest pins off", function()
        poiBack()
        reloadSoon()
    end)
    if not started then poiBack() end
end

-- The second run starts as soon as the first ends: its first open is a second in.
function Pace.Deep()
    if run then report("already running"); return end
    Pace.Start("deep", "quest pins on", function()
        report("first run done, the second turns the game's quest pins off")
        secondRun()
    end)
end

on("PLAYER_REGEN_DISABLED", function()
    if run and run.auto then
        run.after = function() poiBack(); reloadSoon() end
        report("combat: stopped")
        finish()
    end
end)

-- A reload during the second run left the pins off.
on("PLAYER_LOGIN", function() C_Timer.After(1, poiBack) end)

function Pace.Run(rest)
    rest = rest or ""
    if rest == "clear" then
        local d = db()
        if d then d.runs = {} end
        report("saved runs cleared")
    elseif rest == "manual" then
        Pace.Start("manual")
    elseif rest == "deep" then
        Pace.Deep()
    else
        Pace.Start("auto")
    end
end

command(Pace.Run)
