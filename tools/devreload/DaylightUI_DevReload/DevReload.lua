-- Local dev helper, never shipped (it lives under tools/), and standalone: it
-- needs no other addon. After a new build is copied into the game's AddOns
-- folder, tools/game_reload.sh presses KEY in the game. The key clicks a secure
-- macro button whose macro is /reload, and a key press is a hardware click, so
-- the game reloads at once (it refuses ReloadUI() called from addon code).

local KEY = "ALT-CTRL-SHIFT-F9"    -- the game only reads modifiers in this order; game_reload.sh presses the same keys
local BUTTON = "DaylightUIDevReloadButton"

local Dev = {}
DaylightUIDevReload = Dev
Dev.KEY = KEY

local button = CreateFrame("Button", BUTTON, UIParent, "SecureActionButtonTemplate")
button:SetAttribute("type", "macro")
button:SetAttribute("macrotext", "/reload")
-- Key bindings click on the down or the up press depending on the
-- ActionButtonUseKeyDown setting; either reloads.
button:RegisterForClicks("AnyDown", "AnyUp")
Dev.button = button

-- An override binding, so the player's own key bindings are left alone and
-- nothing is saved. Bindings can't change in combat: then it waits.
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self, event)
    if InCombatLockdown() then
        self:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    SetOverrideBindingClick(button, true, KEY, BUTTON, "LeftButton")
end)
