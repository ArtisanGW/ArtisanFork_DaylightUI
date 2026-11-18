-- Debug only, not for release. /questlog records the game's quest tracker
-- (shown, alpha) and combat lockdown twice a second for a minute into
-- DevQuestLogDB.questLog, which the game writes to
-- WTF/Account/<account>/SavedVariables/DevQuestLog.lua on /reload or logout.
-- /questlog clear removes it.

-- A vanilla addon: it uses only the game, never another addon. Its own events,
-- slash command (/questlog) and saved variables (DevQuestLogDB).
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
    _G.DevQuestLogDB = type(_G.DevQuestLogDB) == "table" and _G.DevQuestLogDB or {}
    return _G.DevQuestLogDB
end
local function command(fn)
    _G["SLASH_DEVQUESTLOG1"] = "/questlog"
    SlashCmdList["DEVQUESTLOG"] = function(msg) fn(msg or "") end
end

local Debug = { EVERY = 0.5, FOR = 60 }

local ticker

local function line(start)
    -- The game's own quest tracker.
    local t = _G.ObjectiveTrackerFrame or _G.QuestWatchFrame
    return string.format("%.1f shown=%s alpha=%.2f lockdown=%s ui=%.2f",
        GetTime() - start, tostring(t and t:IsShown()), t and t:GetAlpha() or -1,
        tostring(InCombatLockdown()), UIParent:GetAlpha())
end

function Debug.Run(rest)
    if ticker then ticker:Cancel(); ticker = nil end
    if rest == "clear" then
        store().questLog = nil
        print("questlog: cleared, /reload to save")
        return
    end
    local log, start, n, total = {}, GetTime(), 0, Debug.FOR / Debug.EVERY
    store().questLog = log
    log[1] = line(start)
    ticker = C_Timer.NewTicker(Debug.EVERY, function()
        n = n + 1
        log[#log + 1] = line(start)
        if n >= total then
            ticker = nil
            print("questlog: done, /reload to save it")
        end
    end, total)
    print("questlog: recording for " .. Debug.FOR .. " s")
end

command(Debug.Run)
