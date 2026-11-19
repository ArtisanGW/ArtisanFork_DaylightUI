-- /dui bagcheck: an automatic in-game check of the "Controller: the game's bag"
-- prototype (OpenClose.lua, DaylightUI_Skins/Packs/Game/Bags.lua). A dev tool
-- for the prototype branch, not for release.
--
-- With the controller UI on and out of combat, it runs on its own for about
-- 15 s, with a timer at the top left: it flips the switch both ways, opens the
-- game's bag and checks where it lives, that it wears the Daylight look, and
-- lists every bit of the game's art still showing on it. It takes one game
-- screenshot while the bag is open, puts every setting back, saves the results
-- in DaylightUIBagCheckDB and ends with a reload box (which also clears any
-- taint from opening the bag from addon code).

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L

local Check = {}
ns.GameBagCheck = Check

local STEP_SECONDS = 1.5   -- room for the next frame's passes and the skin's second pass
local OPEN_SECONDS = 3     -- the bag stays open this long, the screenshot in the middle

local running = nil   -- the run in progress: { results, leftovers, blocked, started, steps }

local function record(name, passed, detail)
    local results = running.results
    results[#results + 1] = { name = name, passed = passed == true, detail = detail }
end

-- The game's own art and text still visible on a frame, Daylight UI's own left out.
local function isOurs(path)
    return type(path) == "string" and path:find("DaylightUI", 1, true) ~= nil
end

local WHITE_TEXTURE = 130871   -- Interface\Buttons\WHITE8X8

local function regionName(region)
    if region.GetDebugName then
        local ok, name = pcall(region.GetDebugName, region)
        if ok and type(name) == "string" and name ~= "" then return name end
    end
    return tostring(region:GetName() or region:GetObjectType())
end

local function effectiveAlpha(region)
    local alpha = region.GetAlpha and region:GetAlpha() or 1
    local parent = region.GetParent and region:GetParent()
    if parent and parent.GetEffectiveAlpha then alpha = alpha * parent:GetEffectiveAlpha() end
    return alpha
end

local function describeLeftover(region)
    if not (region.IsVisible and region:IsVisible()) or effectiveAlpha(region) <= 0.01 then return nil end
    local objectType = region:GetObjectType()
    if objectType == "Texture" then
        local atlas = region.GetAtlas and region:GetAtlas()
        local texture = region.GetTexture and region:GetTexture()
        -- Files loaded at run time (Daylight UI's media) have negative ids; 130871
        -- is the plain white texture behind Daylight UI's color fills.
        if isOurs(texture) or (type(texture) == "number" and texture < 0) or texture == WHITE_TEXTURE then return nil end
        if atlas then return "atlas " .. atlas end
        if texture ~= nil and texture ~= 0 then return "texture " .. tostring(texture) end
    elseif objectType == "FontString" then
        local text = region:GetText()
        local font = region:GetFont()
        if text and text ~= "" and not isOurs(font) then return "text \"" .. text .. "\" in " .. tostring(font) end
    end
    return nil
end

-- Walks the bag, item buttons apart (they get their own checks), into a list
-- of "name: what" lines.
local function listLeftovers(frame, itemButtons, lines, depth)
    lines = lines or {}
    depth = depth or 0
    if depth > 8 or #lines >= 80 then return lines end
    for _, region in ipairs({ frame:GetRegions() }) do
        local what = describeLeftover(region)
        if what then lines[#lines + 1] = regionName(region) .. ": " .. what end
    end
    for _, child in ipairs({ frame:GetChildren() }) do
        if not itemButtons[child] and child:IsVisible() then listLeftovers(child, itemButtons, lines, depth + 1) end
    end
    return lines
end

local function itemButtonsOf(bagFrame)
    local buttons, list = {}, {}
    if type(bagFrame.EnumerateValidItems) == "function" then
        for _, itemButton in bagFrame:EnumerateValidItems() do
            buttons[itemButton] = true
            list[#list + 1] = itemButton
        end
    end
    return buttons, list
end

local function hidden(region) return region == nil or region:GetAlpha() <= 0.01 or not region:IsShown() end

-- Every item button: dressed, the controller's slot art gone, its cursor kept.
local function checkItems(bagFrame)
    local Kit = DUI.Skins and DUI.Skins.Kit and DUI.Skins.Kit()
    local _, list = itemButtonsOf(bagFrame)
    record("the bag has item buttons", #list > 0, #list .. " buttons")
    local undressed, framed, pushed, bagPicture, cursor = 0, 0, 0, 0, 0
    for _, itemButton in ipairs(list) do
        if not (Kit and Kit.ShellOf(itemButton)) then undressed = undressed + 1 end
        if itemButton.GetNormalTexture and not hidden(itemButton:GetNormalTexture()) then framed = framed + 1 end
        if itemButton.GetPushedTexture and itemButton:GetPushedTexture() and itemButton:GetPushedTexture():GetAlpha() > 0.01 then
            pushed = pushed + 1
        end
        if itemButton.EmptyBagIcon and not hidden(itemButton.EmptyBagIcon) then bagPicture = bagPicture + 1 end
        if itemButton.Highlight then cursor = cursor + 1 end
    end
    record("every item wears the Daylight item look", undressed == 0, undressed .. " not dressed")
    record("no item shows the controller's slot frame (normal art)", framed == 0, framed .. " framed")
    record("no item has the controller's pressed art", pushed == 0, pushed .. " with it")
    record("no empty slot shows the gray bag picture", bagPicture == 0, bagPicture .. " showing it")
    record("the D-pad cursor (Highlight) is kept on items", #list == 0 or cursor == #list, cursor .. " of " .. #list)
    -- One item button's own leftovers, as a sample of what's left on items.
    if list[1] then
        local sample = listLeftovers(list[1], {})
        running.itemLeftovers = sample
    end
end

local function checkLook(bagFrame)
    local Kit = DUI.Skins and DUI.Skins.Kit and DUI.Skins.Kit()
    record("the skins module is there", Kit ~= nil)
    record("the bag wears the Daylight window look", Kit ~= nil and Kit.ShellOf(bagFrame) ~= nil)
    if bagFrame.NineSlice then record("the game's frame art (NineSlice) is gone", hidden(bagFrame.NineSlice)) end
    local title = bagFrame.TitleContainer and bagFrame.TitleContainer.TitleText or bagFrame.TitleText
    if title and title.GetFont then
        local font = title:GetFont()
        record("the title is in Daylight's font", font == DUI.Style.FONT, tostring(font))
    end
    checkItems(bagFrame)
    local buttons = itemButtonsOf(bagFrame)
    running.leftovers = listLeftovers(bagFrame, buttons)
    record("none of the game's art left on the bag", #running.leftovers == 0, #running.leftovers .. " pieces (listed in the results)")
end

-- Closes the game's bag, only while it's the one in use (see the steps' note on
-- Daylight's own bag).
local function closeGameBag()
    if ns.OpenClose.GameBagMode() and type(CloseAllBags) == "function" then CloseAllBags() end
end

local function setSwitch(value)
    DUI:Set("Bags", "padGameBag", value)
end

-- The steps, each run STEP_SECONDS after the one before (the open one longer).
local function buildSteps()
    local OC = ns.OpenClose
    local bagFrame = _G.ContainerFrameCombinedBags
    return {
        { label = "the options", run = function()
            local items = ns.OPTIONS.pages[1].groups[1].items
            record("Replace the game's bags is the first row", items[1].key == "enabled")
            record("Controller: the game's bag is right under it", items[2].key == "padGameBag")
            closeGameBag()
            setSwitch(false)
        end },
        { label = "switch off", run = function()
            record("off: the game's bag is parked", bagFrame:GetParent() == OC.hidden)
            record("off: the game's bag mode is off", OC.GameBagMode() == false)
            setSwitch(true)
        end },
        { label = "switch on", run = function()
            record("on: the game's bag mode is on", OC.GameBagMode() == true)
            record("on: the skins module is told", DUI.BagsUseGameBag() == true)
            record("on: the game's bag is under UIParent", bagFrame:GetParent() == UIParent)
            OpenAllBags()
        end },
        { label = "the bag open", seconds = OPEN_SECONDS, run = function()
            record("the game's bag opened", bagFrame:IsShown())
            record("Daylight's bag stayed shut", not (ns.window and ns.window:IsShown()))
            checkLook(bagFrame)
            C_Timer.After(OPEN_SECONDS / 2, function()
                if running and type(Screenshot) == "function" then
                    Screenshot()
                    running.screenshot = date("%H:%M:%S")
                end
            end)
        end },
        -- Daylight's own bag isn't opened or closed from here: called from addon
        -- code, OpenAllBags and CloseAllBags run its controller listing tainted,
        -- and the game then refuses its own SetPreferredGamepadInteractTarget
        -- until a reload (seen in the second run). The tests cover that bag.
        { label = "switch off", run = function()
            closeGameBag()
            setSwitch(false)
        end },
        { label = "the game's bag parked", run = function()
            record("off again: the game's bag is parked", bagFrame:GetParent() == OC.hidden)
            record("off again: the game's bag mode is off", OC.GameBagMode() == false)
            setSwitch(true)
            DUI:Set("Bags", "enabled", false)
        end },
        { label = "Replace off", run = function()
            record("Replace off turns the switch off", DUI:Get("Bags", "padGameBag") == false)
            DUI:Set("Bags", "enabled", true)
        end },
    }
end

-- Timer at the top left: what it's on and how long is left.
local timerFrame
local function showTimer(text)
    if not timerFrame then
        timerFrame = CreateFrame("Frame", nil, UIParent)
        timerFrame:SetFrameStrata("TOOLTIP")
        timerFrame:SetSize(420, 28)
        timerFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 60, -60)
        timerFrame.text = timerFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
        timerFrame.text:SetPoint("LEFT")
    end
    timerFrame.text:SetText(text)
    timerFrame:SetShown(text ~= nil)
end

local function secondsLeft(fromStep)
    local total = 0
    for i = fromStep, #running.steps do total = total + (running.steps[i].seconds or STEP_SECONDS) end
    return math.ceil(total)
end

local function onBlocked(event, addon, action)
    if not running then return end
    running.blocked[#running.blocked + 1] = { event = event, addon = tostring(addon), action = tostring(action), time = date("%H:%M:%S"),
        step = running.stepLabel }
end
DUI.RegisterEvent("ADDON_ACTION_BLOCKED", onBlocked)
DUI.RegisterEvent("ADDON_ACTION_FORBIDDEN", onBlocked)

local function finish(reason)
    local run = running
    running = nil
    -- Put every setting back as it was.
    closeGameBag()
    DUI:Set("Bags", "enabled", run.before.enabled)
    DUI:Set("Bags", "padGameBag", run.before.padGameBag)
    local failed = 0
    for _, result in ipairs(run.results) do if not result.passed then failed = failed + 1 end end
    local saved = {
        time = date("%Y-%m-%d %H:%M:%S"), stopped = reason, results = run.results, failed = failed,
        leftovers = run.leftovers or {}, itemLeftovers = run.itemLeftovers or {},
        blocked = run.blocked, screenshot = run.screenshot,
        restored = { enabled = DUI:Get("Bags", "enabled"), padGameBag = DUI:Get("Bags", "padGameBag") },
    }
    DaylightUIBagCheckDB = DaylightUIBagCheckDB or {}
    DaylightUIBagCheckDB.last = saved
    showTimer(nil)
    local summary = string.format("Bag check %s: %d of %d passed, %d of the game's art left, %d blocked.",
        reason or "done", #run.results - failed, #run.results, #saved.leftovers, #run.blocked)
    DUI.Print(summary)
    for _, result in ipairs(run.results) do
        if not result.passed then DUI.Print("  failed: " .. result.name .. (result.detail and (" (" .. result.detail .. ")") or "")) end
    end
    DUI.Widgets.Ask({ key = "bagcheck", reload = true,
        text = summary .. " Reload to save the results and clear the test's taint?" })
end

local function runStep(index)
    if not running then return end
    if InCombatLockdown() then
        DUI.AfterCombat(function() finish("stopped by a fight") end, "bagcheck:fight")
        return
    end
    local step = running.steps[index]
    if not step then return finish(nil) end
    running.stepLabel = step.label
    showTimer(string.format("Bag check: %s (%d s left)", step.label, secondsLeft(index)))
    local ok, err = pcall(step.run)
    if not ok then record("step '" .. step.label .. "' ran", false, tostring(err)) end
    C_Timer.After(step.seconds or STEP_SECONDS, function() runStep(index + 1) end)
end

function Check.Start()
    if running then return DUI.Print("The bag check is already running.") end
    if InCombatLockdown() then return DUI.Print("The bag check runs out of combat.") end
    if not (DUI.Pad and DUI.Pad.On()) then return DUI.Print("Turn on the controller UI first: the bag check is for the controller.") end
    if not (ns.OpenClose and ns.module and _G.ContainerFrameCombinedBags) then
        return DUI.Print("The bag check needs Replace the game's bags on and the game's combined bag.")
    end
    running = { results = {}, blocked = {}, steps = buildSteps(),
        before = { enabled = DUI:Get("Bags", "enabled"), padGameBag = DUI:Get("Bags", "padGameBag") } }
    runStep(1)
end

function Check.Running() return running ~= nil end

DUI.RegisterCommand("bagcheck", Check.Start, L["/dui bagcheck - dev: checks the controller's game's-bag prototype on its own, then asks to reload"])
