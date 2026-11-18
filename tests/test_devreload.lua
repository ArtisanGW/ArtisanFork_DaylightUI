local stub = require("stub")   -- T (test helpers) is a global set by tests/run.lua

-- The local dev reload helper (tools/devreload, never shipped): tools/game_reload.sh
-- presses its key after a new build is copied into the game, and Daylight UI's
-- question box asks to reload, its Reload a real secure /reload.

local function load()
    stub.Load()
    local chunk = assert(loadfile("tools/devreload/DaylightUI_DevReload/DevReload.lua"))
    chunk("DaylightUI_DevReload", {})
    stub.FireEvent("PLAYER_LOGIN")
    return DaylightUIDevReload
end

T.test("devreload: its key clicks its button, and the click asks to reload", function()
    local Dev = load()
    local o = stub.overrides[Dev.KEY]
    T.truthy(o, "the key is bound")
    T.eq(o.click, "DaylightUIDevReloadButton")
    local W, real, asked = DaylightUI.Widgets, DaylightUI.Widgets.Ask, nil
    W.Ask = function(spec) asked = spec end
    _G[o.click]:Click()
    W.Ask = real
    T.truthy(asked, "asked")
    T.eq(asked.reload, true, "a secure Reload button")
    T.eq(asked.text, Dev.TEXT)
end)

T.test("devreload: the script presses the key the addon binds", function()
    local f = assert(io.open("tools/game_reload.sh")); local sh = f:read("*a"); f:close()
    T.truthy(sh:find('KEYS="ctrl+alt+shift+F12"', 1, true))
    T.eq(load().KEY, "CTRL-ALT-SHIFT-F12")
end)
