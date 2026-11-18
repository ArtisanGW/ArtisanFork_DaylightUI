local stub = require("stub")   -- T (test helpers) is a global set by tests/run.lua

-- The local dev reload helper (tools/devreload, never shipped, needs no other
-- addon): tools/game_reload.sh presses its key after a new build is copied into
-- the game, and the key clicks a secure macro button that runs /reload.

local function load()
    stub.Reset()
    local chunk = assert(loadfile("tools/devreload/DevReload/DevReload.lua"))
    chunk("DevReload", {})
    stub.FireEvent("PLAYER_LOGIN")
    return DevReload
end

T.test("devreload: its key clicks a secure button whose macro is /reload", function()
    local Dev = load()
    local o = stub.overrides[Dev.KEY]
    T.truthy(o, "the key is bound")
    T.eq(o.click, "DevReloadButton")
    local b = _G[o.click]
    T.eq(b:GetAttribute("type"), "macro")
    T.eq(b:GetAttribute("macrotext"), "/reload")
end)

T.test("devreload: it needs no other addon", function()
    local f = assert(io.open("tools/devreload/DevReload/DevReload.toc")); local toc = f:read("*a"); f:close()
    T.falsy(toc:find("Dependencies", 1, true))
    f = assert(io.open("tools/devreload/DevReload/DevReload.lua")); local src = f:read("*a"); f:close()
    T.falsy(src:find("Daylight", 1, true) or toc:find("Daylight", 1, true), "never references another addon")
end)

T.test("devreload: the script presses the key the addon binds", function()
    local f = assert(io.open("tools/game_reload.sh")); local sh = f:read("*a"); f:close()
    T.truthy(sh:find('KEYS="ctrl+alt+shift+F9"', 1, true))
    T.eq(load().KEY, "ALT-CTRL-SHIFT-F9")
end)
