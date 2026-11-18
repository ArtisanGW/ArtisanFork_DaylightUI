local stub = require("stub")   -- T (test helpers) is a global set by tests/run.lua

-- The local dev reload helper (tools/devreload, never shipped, needs no other
-- addon): tools/game_reload.sh presses its key after a new build is copied into
-- the game, and the key clicks a secure macro button that runs /reload.

local function load()
    stub.Load()
    local chunk = assert(loadfile("tools/devreload/DaylightUI_DevReload/DevReload.lua"))
    chunk("DaylightUI_DevReload", {})
    stub.FireEvent("PLAYER_LOGIN")
    return DaylightUIDevReload
end

T.test("devreload: its key clicks a secure button whose macro is /reload", function()
    local Dev = load()
    local o = stub.overrides[Dev.KEY]
    T.truthy(o, "the key is bound")
    T.eq(o.click, "DaylightUIDevReloadButton")
    local b = _G[o.click]
    T.eq(b:GetAttribute("type"), "macro")
    T.eq(b:GetAttribute("macrotext"), "/reload")
end)

T.test("devreload: it needs no other addon", function()
    local f = assert(io.open("tools/devreload/DaylightUI_DevReload/DaylightUI_DevReload.toc")); local toc = f:read("*a"); f:close()
    T.falsy(toc:find("Dependencies", 1, true))
    f = assert(io.open("tools/devreload/DaylightUI_DevReload/DevReload.lua")); local src = f:read("*a"); f:close()
    T.falsy(src:find("DaylightUI%.") or src:find("DaylightUI%s*$"), "never reaches into Daylight UI")
end)

T.test("devreload: the script presses the key the addon binds", function()
    local f = assert(io.open("tools/game_reload.sh")); local sh = f:read("*a"); f:close()
    T.truthy(sh:find('KEYS="ctrl+alt+shift+F9"', 1, true))
    T.eq(load().KEY, "CTRL-ALT-SHIFT-F9")
end)
