-- Debug only, not for release. /dui padtaint watches the game's controller state
-- (GamepadMode, its FrameControlsManager and shownFrames, the InputBindingManager
-- and its bindingSetStack, SmartNavigation) for fields last written by an addon.
-- Each newly tainted field is logged with who wrote it and the events just before
-- it, and every refused action (ADDON_ACTION_FORBIDDEN / BLOCKED) logs a full
-- snapshot. The game's "Interface action failed" chat message (no Lua error)
-- is logged with the stack that printed it, and so is each show or hide of the
-- game's navigation frame that an addon's code is on the stack of. Kept on across reloads until turned off. Written to
-- DaylightUIDB.padTaint, which the game saves on /reload or logout.
--   /dui padtaint        on / off
--   /dui padtaint now    a snapshot now
--   /dui padtaint clear  empties the log

-- A separate dev addon (tools/devaddons, never shipped). It reaches the
-- Bags module's namespace through DaylightUI:GetModule, which is internal and
-- not promised to plugins: fine for a local tool, kept out of the release.
local DUI = DaylightUI
local mod = DUI and DUI.GetModule and DUI:GetModule("Bags")
local ns = mod and mod.ns
if type(ns) ~= "table" then return end

local Debug = { EVERY = 0.5, MAX_LINES = 3000, RECENT = 12, STACK = 25 }
ns.Debug = Debug

local ticker
local recent = {}       -- the last few events, oldest first
local seen = {}         -- "label.key" -> who, as of the last scan
local printed = 0       -- notes already written out (each one only once)
local noted = 0

local function db()
    local root = _G.DaylightUIDB
    if type(root) ~= "table" then return nil end
    root.padTaint = root.padTaint or { log = {} }
    root.padTaint.log = root.padTaint.log or {}
    return root.padTaint
end

local function stamp() return date("%H:%M:%S") .. string.format(" %.1f", GetTime()) end

local function write(text)
    local d = db()
    if not d then return end
    local log = d.log
    log[#log + 1] = stamp() .. " " .. text
    while #log > Debug.MAX_LINES do table.remove(log, 1) end
end

local function note(text)
    noted = noted + 1
    recent[#recent + 1] = { noted, stamp() .. " " .. text }
    while #recent > Debug.RECENT do table.remove(recent, 1) end
end

local function sources()
    local GM, GSU = _G.GamepadMode, _G.GamepadSharedUtility
    local m = type(GM) == "table" and GM.FrameControlsManager or nil
    local ibm = type(GSU) == "table" and GSU.InputBindingManager or nil
    return {
        { "GamepadMode", GM },
        { "FrameControlsManager", m },
        { "shownFrames", type(m) == "table" and m.shownFrames or nil },
        { "InputBindingManager", ibm },
        { "bindingSetStack", type(ibm) == "table" and ibm.bindingSetStack or nil },
        { "SmartNavigation", _G.SmartNavigation },
    }
end

-- What the world map's close runs through (its OnHide walks its data providers
-- and pins, the panel manager reads its own fields). Scanned in snapshots only,
-- since addons write some of these on purpose.
local function mapSources()
    local map = _G.WorldMapFrame
    local cb = type(_G.EventRegistry) == "table" and _G.EventRegistry.callbackTables
    local out = {
        { "FramePositionDelegate", _G.FramePositionDelegate },
        { "UIPanelWindows", _G.UIPanelWindows },
        { "WorldMapFrame", map },
    }
    for _, name in ipairs({ "BuffFrame", "DebuffFrame" }) do
        local f = _G[name]
        if type(f) == "table" then
            out[#out + 1] = { name, f }
            out[#out + 1] = { name .. ".auraInfo", f.auraInfo }
            if type(f.auraFrames) == "table" then
                out[#out + 1] = { name .. ".auraFrames", f.auraFrames }
                for i, b in ipairs(f.auraFrames) do
                    if i > 6 then break end
                    out[#out + 1] = { name .. ".aura" .. i, b }
                    if type(b) == "table" then out[#out + 1] = { name .. ".aura" .. i .. ".buttonInfo", b.buttonInfo } end
                end
            end
        end
    end
    if type(map) == "table" then
        out[#out + 1] = { "WorldMapFrame.dataProviders", map.dataProviders }
        out[#out + 1] = { "WorldMapFrame.ScrollContainer", map.ScrollContainer }
        out[#out + 1] = { "WorldMapFrame.pinPools", map.pinPools }
    end
    if type(cb) == "table" then
        for kind, t in pairs(cb) do
            if type(t) == "table" then
                for _, event in ipairs({ "WorldMapOnHide", "UIParentPanelManager.HideUIPanel", "ContainerFrame.CloseAllBags" }) do
                    out[#out + 1] = { "EventRegistry." .. tostring(kind) .. "." .. event, t[event] }
                end
            end
        end
    end
    return out
end

-- Every field of those tables last written by an addon: "label.key" -> who.
local function scan(list)
    local out = {}
    for _, s in ipairs(list or sources()) do
        local label, t = s[1], s[2]
        if type(t) == "table" then
            pcall(function()
                for k in pairs(t) do
                    local ok, secure, by = pcall(issecurevariable, t, k)
                    if ok and secure == false then out[label .. "." .. tostring(k)] = tostring(by) end
                end
            end)
        end
    end
    return out
end

local function shownList()
    local m = type(_G.GamepadMode) == "table" and _G.GamepadMode.FrameControlsManager
    local list = type(m) == "table" and m.shownFrames
    if type(list) ~= "table" then return "?" end
    local names = {}
    for i, f in ipairs(list) do
        local ok, name = pcall(function() return f:GetName() end)
        names[i] = ok and tostring(name) or "?"
    end
    return #names .. " [" .. table.concat(names, ", ") .. "]"
end

local function writeRecent()
    for _, e in ipairs(recent) do
        if e[1] > printed then write("    before: " .. e[2]) end
    end
    printed = noted
end

function Debug.Snapshot(why)
    local now = scan()
    write("SNAPSHOT " .. why .. "  shown=" .. shownList() .. "  lockdown=" .. tostring(InCombatLockdown()))
    local keys = {}
    for k in pairs(now) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do write("    tainted " .. k .. " by " .. now[k]) end
    if #keys == 0 then write("    nothing tainted") end
    local map = scan(mapSources())
    local mk, by = {}, {}
    for k in pairs(map) do mk[#mk + 1] = k end
    table.sort(mk)
    for _, k in ipairs(mk) do
        local who = map[k]
        by[who] = (by[who] or 0) + 1
        if not k:find("^WorldMapFrame%.[^.]*$") then write("    map: " .. k .. " by " .. who) end
    end
    for who, n in pairs(by) do write("    map fields by " .. who .. ": " .. n) end
    writeRecent()
end

function Debug.Tick()
    local now = scan()
    for k, by in pairs(now) do
        if seen[k] ~= by then
            write("NEW " .. k .. " by " .. by .. "  shown=" .. shownList())
            writeRecent()
        end
    end
    for k in pairs(seen) do
        if not now[k] then write("CLEAN " .. k) end
    end
    seen = now
end

local function stackText()
    local ok, text = pcall(debugstack, 3, Debug.STACK, 0)
    return ok and type(text) == "string" and text or ""
end

local function writeStack(text)
    for line in text:gmatch("[^\n]+") do write("    | " .. line) end
end

-- An addon's own file (not the game's, not this file) on the stack.
local function addonOn(text)
    for line in text:gmatch("[^\n]+") do
        local name = line:match("AddOns[/\\]([^/\\]+)")
        if name and not name:find("^Blizzard_") and not line:find("Debug%.lua") then return name end
    end
end

local function navChange(what)
    if not ticker then return end
    local text = stackText()
    local by = addonOn(text)
    note("SmartNavigation " .. what .. (by and (" from " .. by) or ""))
    if by then
        write("SmartNavigation " .. what .. " with " .. by .. " on the stack  shown=" .. shownList())
        writeRecent()
        writeStack(text)
    end
end

local hooked = false
local function hookOnce()
    if hooked then return end
    hooked = true
    if type(_G.DisplayInterfaceActionBlockedMessage) == "function" then
        hooksecurefunc("DisplayInterfaceActionBlockedMessage", function()
            if not ticker then return end
            note("BLOCKED MESSAGE")
            local text = stackText()
            Debug.Snapshot("BLOCKED MESSAGE (Interface action failed)")
            writeStack(text)
        end)
    end
    local nav = _G.SmartNavigation
    if type(nav) == "table" and nav.HookScript then
        nav:HookScript("OnShow", function() navChange("OnShow") end)
        nav:HookScript("OnHide", function() navChange("OnHide") end)
    end
    for _, name in ipairs({ "OpenAllBags", "CloseAllBags", "ToggleAllBags", "ToggleBackpack" }) do
        if type(_G[name]) == "function" then hooksecurefunc(name, function() note(name .. "  shown=" .. shownList()) end) end
    end
end

local function bagState()
    local w = ns.window
    if not w then return "no bag" end
    local away = DUI.Pad and DUI.Pad.Away and DUI.Pad.Away(w)
    local kids, shownKids = 0, 0
    for _, c in ipairs({ w:GetChildren() }) do
        kids = kids + 1
        if c:IsShown() then shownKids = shownKids + 1 end
    end
    return string.format("bag shown=%s alpha=%.2f away=%s parts %d/%d mouse=%s", tostring(w:IsShown()),
        w:GetAlpha(), tostring(away), shownKids, kids, tostring(w:IsMouseEnabled()))
end

local wrapped = false
local function wrapPad()
    local P = DUI.Pad
    if wrapped or not (P and P.PutAway and P.Back) then return end
    wrapped = true
    local put, back = P.PutAway, P.Back
    P.PutAway = function(frame)
        local r = put(frame)
        if ticker and frame == ns.window then
            write("PutAway -> " .. tostring(r) .. "  lockdown=" .. tostring(InCombatLockdown()) .. "  " .. bagState())
            writeStack(stackText())
        end
        return r
    end
    P.Back = function(frame)
        local was = P.Away(frame)
        back(frame)
        if ticker and frame == ns.window and was then
            write("Back  lockdown=" .. tostring(InCombatLockdown()) .. "  " .. bagState())
            writeStack(stackText())
        end
    end
end

local lastBag
local function watchBag()
    if not InCombatLockdown() then lastBag = nil; return end
    local s = bagState()
    if s ~= lastBag then write("in fight: " .. s); lastBag = s end
end

local function watchWindow()
    local w = ns.window
    if not w or w.padTaintHooked then return end
    w.padTaintHooked = true
    w:HookScript("OnShow", function() note("bag OnShow") end)
    w:HookScript("OnHide", function() note("bag OnHide") end)
end

function Debug.Start()
    hookOnce()
    seen = scan()
    if ticker then ticker:Cancel() end
    wrapPad()
    ticker = C_Timer.NewTicker(Debug.EVERY, function()
        watchWindow()
        watchBag()
        Debug.Tick()
    end)
    Debug.Snapshot("start")
end

function Debug.Stop()
    if ticker then ticker:Cancel(); ticker = nil end
end

local EVENTS = { "MERCHANT_SHOW", "MERCHANT_CLOSED", "PLAYER_INTERACTION_MANAGER_FRAME_SHOW",
    "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "GOSSIP_SHOW", "GOSSIP_CLOSED" }
for _, e in ipairs(EVENTS) do
    DUI.RegisterEvent(e, function(event, a) if ticker then note(event .. (a ~= nil and (" " .. tostring(a)) or "")) end end)
end
DUI.RegisterEvent("PLAYER_IN_COMBAT_CHANGED", function(_, on)
    if not ticker then return end
    note("PLAYER_IN_COMBAT_CHANGED " .. tostring(on))
    Debug.Snapshot("PLAYER_IN_COMBAT_CHANGED " .. tostring(on) .. "  " .. bagState())
end)
for _, e in ipairs({ "ADDON_ACTION_FORBIDDEN", "ADDON_ACTION_BLOCKED" }) do
    DUI.RegisterEvent(e, function(event, addon, fn)
        if not ticker then return end
        note(event .. " " .. tostring(addon) .. " " .. tostring(fn))
        Debug.Snapshot(event .. " " .. tostring(addon) .. " " .. tostring(fn))
    end)
end
DUI.RegisterEvent("PLAYER_LOGIN", function()
    local d = db()
    if d and d.on then Debug.Start() end
end)

function Debug.Run(rest)
    local d = db()
    if not d then return end
    if rest == "clear" then
        d.log = {}
        print("Daylight UI padtaint: log cleared")
    elseif rest == "now" then
        Debug.Snapshot("by hand")
        print("Daylight UI padtaint: snapshot taken, /reload to save")
    elseif d.on then
        d.on = nil
        Debug.Stop()
        print("Daylight UI padtaint: off")
    else
        d.on = true
        Debug.Start()
        print("Daylight UI padtaint: on, stays on across reloads (/dui padtaint to stop)")
    end
end

DUI.RegisterCommand("padtaint", Debug.Run)
