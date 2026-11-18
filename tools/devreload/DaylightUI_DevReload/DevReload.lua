-- Local dev helper, never shipped (it lives under tools/). After a new build is
-- copied into the game's AddOns folder, tools/game_reload.sh presses KEY in the
-- game, and this shows Daylight UI's own question box. Its Reload is a real
-- (secure) /reload: this client refuses ReloadUI() from addon code, so a click on
-- it is the one thing left to do.

local KEY = "CTRL-ALT-SHIFT-F12"   -- tools/game_reload.sh presses the same keys
local BUTTON = "DaylightUIDevReloadButton"
local TEXT = "A new Daylight UI build is in the AddOns folder. Reload to load it?"

local Dev = {}
DaylightUIDevReload = Dev
Dev.KEY, Dev.TEXT = KEY, TEXT

function Dev.Ask()
    local DUI = DaylightUI
    local W = DUI and DUI.Widgets
    if not (W and W.Ask) then return end
    local L = DUI.L or {}
    W.Ask({ key = "devReload", reload = true, text = TEXT,
            yes = RELOADUI or L["Reload"], no = LATER or L["Later"] })
end

-- The key clicks this button (an override binding, so the player's own key
-- bindings are left alone and nothing is saved).
local button = CreateFrame("Button", BUTTON, UIParent)
button:SetScript("OnClick", function() Dev.Ask() end)
Dev.button = button

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
    SetOverrideBindingClick(button, true, KEY, BUTTON, "LeftButton")
end)
