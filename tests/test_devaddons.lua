local stub = require("stub")   -- T (test helpers) is a global set by tests/run.lua

-- The local dev tools (tools/devaddons, never shipped): each its own addon in the
-- game's Development Tools group, loaded after the module it looks into.

local TOOLS = {
    { addon = "DaylightUI_DevQuestLog", file = "QuestLog.lua", command = "questlog", load = { quests = true }, dep = "DaylightUI_Quests" },
    { addon = "DaylightUI_DevMapPace", file = "MapPace.lua", command = "mappace", load = { quests = true }, dep = "DaylightUI_Quests" },
    { addon = "DaylightUI_DevPadTaint", file = "PadTaint.lua", command = "padtaint", load = { bags = true }, dep = "DaylightUI_Bags" },
}

local function read(path)
    local f = assert(io.open(path)); local s = f:read("*a"); f:close(); return s
end

for _, t in ipairs(TOOLS) do
    local dir = "tools/devaddons/" .. t.addon .. "/"

    T.test("devaddons: " .. t.addon .. " loads after its module and adds /dui " .. t.command, function()
        stub.Load(t.load)
        T.falsy(DaylightUI.HasCommand(t.command), "not part of Daylight UI any more")
        local chunk = assert(loadfile(dir .. t.file))
        chunk(t.addon, {})
        T.truthy(DaylightUI.HasCommand(t.command), "its own addon adds it")
        stub.RunTimers()
        -- Only the tool's own errors: the bare test world has no bags, which the
        -- Bags module notices on its own (test_bags builds a bag world for that).
        local mine = {}
        for _, e in ipairs(stub.errors) do
            if tostring(e):find(t.file, 1, true) then mine[#mine + 1] = e end
        end
        T.eq(#mine, 0, tostring(mine[1]))
    end)

    T.test("devaddons: " .. t.addon .. "'s toc lists it with BugSack's Development Tools", function()
        local toc = read(dir .. t.addon .. ".toc")
        T.truthy(toc:find("## Category: Development Tools", 1, true))
        T.truthy(toc:find("## Category-frFR: Outils de Développement", 1, true), "the same group in each language")
        T.truthy(toc:find("## Dependencies: DaylightUI, " .. t.dep, 1, true), "loads after the module it reads")
        T.truthy(toc:find("\n" .. t.file .. "\n", 1, true))
    end)
end

T.test("devaddons: none of the tools ships with Daylight UI", function()
    for _, toc in ipairs({ "DaylightUI_Quests/DaylightUI_Quests.toc", "DaylightUI_Bags/DaylightUI_Bags.toc" }) do
        local s = read(toc)
        T.falsy(s:find("Debug.lua", 1, true) or s:find("MapPace.lua", 1, true), toc)
    end
end)

T.test("devaddons: the reload helper is in the same Development Tools group", function()
    T.truthy(read("tools/devreload/DaylightUI_DevReload/DaylightUI_DevReload.toc"):find("## Category: Development Tools", 1, true))
end)
