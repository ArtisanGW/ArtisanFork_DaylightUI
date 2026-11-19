-- The game's own combined bag, in the Daylight UI look, while Daylight UI's bags
-- leave it to the game on a controller (DaylightUI_Bags' "Controller: the game's
-- bag", a prototype). Never walked while Daylight UI's bag stands in for it.
--
-- The bag stays the game's: its item buttons, their clicks, the D-pad grid and
-- the footer are its own secure code. The footer's controller prompts are left
-- in the game's look for now. Only art is hidden (by alpha) and dressed,
-- like every skin here. The game hands its item buttons out of a pool each time
-- the bag opens or changes size, so they're dressed on every pass, and again
-- when the bag's contents settle (BAG_UPDATE_DELAYED) while it's open.

local _, ns = ...
local DUI = DaylightUI
local Engine = ns.Engine

local function covered()
    return not (type(DUI.BagsUseGameBag) == "function" and DUI.BagsUseGameBag())
end

-- Each item button the bag holds now: the game's own list of them. On a
-- controller the game gives each one its own slot art (ContainerFrame.lua,
-- ContainerFrameItemButtonMixin:OnLoad: ItemSlotFrame_* atlases) and, in an
-- empty slot, a gray picture of the bag (SetAppearanceToEmptyBagSlot); faded
-- here on every pass, as the game re-shows them. Its focus highlight stays:
-- that's the D-pad's cursor.
-- The game's hover art (ItemSlotFrame_Hover, BagSlotFrame_Expanded_Hover) swapped
-- for Daylight's hover wash, once per button.
local washed = setmetatable({}, { __mode = "k" })
local function swapHover(Kit, button)
    if type(button) ~= "table" or washed[button] or not button.GetHighlightTexture then return end
    washed[button] = true
    Kit.Hide(button:GetHighlightTexture())
    Kit.HoverWash(button)
end

local function dressItems(Kit, bagFrame)
    if type(bagFrame.EnumerateValidItems) ~= "function" then return end
    for _, itemButton in bagFrame:EnumerateValidItems() do
        Kit.Item(itemButton)
        if itemButton.GetPushedTexture then Kit.Hide(itemButton:GetPushedTexture()) end
        Kit.Hide(itemButton.EmptyBagIcon)
        swapHover(Kit, itemButton)
    end
end

local function titleOf(bagFrame)
    return bagFrame.TitleContainer and bagFrame.TitleContainer.TitleText or bagFrame.TitleText
end

-- The free-slot count ("(20)") sat on the hidden portrait, over the title: in
-- Daylight's font now, just after the title.
local function dressCount(Kit, bagFrame)
    local count = bagFrame.CountContainer and bagFrame.CountContainer.Count
    local title = titleOf(bagFrame)
    if type(count) ~= "table" or not count.SetPoint then return end
    Kit.Font(count)
    if type(title) == "table" and title.GetStringWidth then
        count:ClearAllPoints()
        count:SetPoint("LEFT", title, "LEFT", title:GetStringWidth() + 6, 0)
    end
end

-- The money at the bottom: Daylight's coins and font, without the game's gold-edged box.
local COIN_BUTTONS = { "GoldButton", "SilverButton", "CopperButton" }
local function dressMoney(Kit, bagFrame)
    local money = bagFrame.MoneyFrame
    if type(money) ~= "table" then return end
    Kit.Money(money)
    local border = money.Border
    if type(border) == "table" then
        for _, piece in ipairs({ "Left", "Right", "Middle" }) do Kit.Hide(border[piece]) end
    end
    for _, key in ipairs(COIN_BUTTONS) do
        local coinButton = money[key]
        local name = type(coinButton) == "table" and coinButton.GetName and coinButton:GetName()
        local text = type(coinButton) == "table" and (coinButton.Text or (name and _G[name .. "Text"]))
        if text then Kit.Font(text) end
    end
end

-- The controller's bag buttons beside the search box: the backpack and the bag
-- bar (GamepadBackpackButton, GamepadBagBar), with their "(0)" counts.
local function dressBagButton(Kit, button)
    if type(button) ~= "table" then return end
    local name = button.GetName and button:GetName()
    local count = button.Count or (name and _G[name .. "Count"])
    if count then Kit.Font(count) end
    swapHover(Kit, button)
end

local function dressBagButtons(Kit)
    dressBagButton(Kit, _G.GamepadBackpackButton)
    local bagBar = _G.GamepadBagBar
    if type(bagBar) ~= "table" then return end
    dressBagButton(Kit, bagBar)
    if bagBar.GetChildren then
        for _, child in ipairs({ bagBar:GetChildren() }) do dressBagButton(Kit, child) end
    end
end

local registration = Engine.Window({ key = "game:bags", pack = "system", frame = "ContainerFrameCombinedBags", watch = true,
    skip = covered,
    after = function(Kit, bagFrame)
        dressItems(Kit, bagFrame)
        dressCount(Kit, bagFrame)
        dressMoney(Kit, bagFrame)
        dressBagButtons(Kit)
    end })

DUI.RegisterEvent("BAG_UPDATE_DELAYED", function()
    local bagFrame = _G.ContainerFrameCombinedBags
    if type(bagFrame) == "table" and bagFrame.IsShown and bagFrame:IsShown() and not covered() and registration.again then
        registration.again()
    end
end)

-- The skin is skipped while Daylight UI's bag stands in for the game's, and
-- tried again when the bag is handed back (GameWindowBack). If the game's bag
-- opens before that ever happened (the mode was already on when the skins
-- started), it's tried when the bag shows.
local combinedBag = _G.ContainerFrameCombinedBags
if type(combinedBag) == "table" and combinedBag.HookScript then
    combinedBag:HookScript("OnShow", function()
        if not registration.done and not covered() then Engine.Try(registration) end
    end)
end
