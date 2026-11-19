-- The game's own combined bag, in the Daylight UI look, while Daylight UI's bags
-- leave it to the game on a controller (DaylightUI_Bags' "Controller: the game's
-- bag", a prototype). Never walked while Daylight UI's bag stands in for it.
--
-- The bag stays the game's: its item buttons, their clicks, the D-pad grid and
-- the footer are its own secure code. Only art is hidden (by alpha) and dressed,
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
local function dressItems(Kit, bagFrame)
    if type(bagFrame.EnumerateValidItems) ~= "function" then return end
    for _, itemButton in bagFrame:EnumerateValidItems() do
        Kit.Item(itemButton)
        if itemButton.GetPushedTexture then Kit.Hide(itemButton:GetPushedTexture()) end
        Kit.Hide(itemButton.EmptyBagIcon)
    end
end

local registration = Engine.Window({ key = "game:bags", pack = "system", frame = "ContainerFrameCombinedBags", watch = true,
    skip = covered,
    after = function(Kit, bagFrame) dressItems(Kit, bagFrame) end })

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
