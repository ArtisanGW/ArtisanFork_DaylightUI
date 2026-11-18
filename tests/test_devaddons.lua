local stub = require("stub")   -- T (test helpers) is a global set by tests/run.lua

-- The local dev tools (tools/devaddons, never shipped): vanilla addons that use
-- only the game, never another addon, each in the game's Development Tools
-- group. Run here against the fake game alone (stub.Reset), with no other addon.

local TOOLS = {
    { addon = "DevQuestLog", file = "QuestLog.lua", command = "questlog", slash = "DEVQUESTLOG", sv = "DevQuestLogDB" },
    { addon = "DevMapPace", file = "MapPace.lua", command = "mappace", slash = "DEVMAPPACE", sv = "DevMapPaceDB" },
    { addon = "DevPadTaint", file = "PadTaint.lua", command = "padtaint", slash = "DEVPADTAINT", sv = "DevPadTaintDB" },
}

local function read(path)
    local f = assert(io.open(path)); local s = f:read("*a"); f:close(); return s
end

for _, t in ipairs(TOOLS) do
    local dir = "tools/devaddons/" .. t.addon .. "/"

    T.test("devaddons: " .. t.addon .. " runs on the game alone and adds /" .. t.command, function()
        stub.Reset()
        T.eq(_G.DaylightUI, nil, "no other addon loaded")
        assert(loadfile(dir .. t.file))(t.addon, {})
        stub.FireEvent("PLAYER_LOGIN")
        T.eq(_G["SLASH_" .. t.slash .. "1"], "/" .. t.command, "its own slash command")
        SlashCmdList[t.slash]("clear")
        SlashCmdList[t.slash]("")
        stub.RunTimers()
        T.eq(type(_G[t.sv]), "table", "its own saved variables")
        T.eq(#stub.errors, 0, tostring(stub.errors[1]))
        _G[t.sv] = nil
    end)

    T.test("devaddons: " .. t.addon .. " never references another addon", function()
        local toc, src = read(dir .. t.addon .. ".toc"), read(dir .. t.file)
        T.falsy(toc:find("Dependencies", 1, true) or toc:find("OptionalDeps", 1, true), "no other addon in its toc")
        T.falsy(toc:find("Daylight", 1, true) or src:find("Daylight", 1, true), "nor Daylight UI anywhere")
        T.falsy(src:find("DUI", 1, true), "nor its namespace")
    end)

    T.test("devaddons: " .. t.addon .. " is listed with BugSack's Development Tools", function()
        local toc = read(dir .. t.addon .. ".toc")
        T.truthy(toc:find("## Category: Development Tools", 1, true))
        T.truthy(toc:find("## Category-frFR: Outils de Développement", 1, true), "the same group in each language")
        T.truthy(toc:find("## SavedVariables: " .. t.sv, 1, true))
        T.truthy(toc:find("\n" .. t.file .. "\n", 1, true))
    end)
end
