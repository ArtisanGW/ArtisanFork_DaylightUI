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

-- Each item button the bag holds now: the game's own list of them.
local function dressItems(Kit, f)
    if type(f.EnumerateValidItems) ~= "function" then return end
    for _, button in f:EnumerateValidItems() do Kit.Item(button) end
end

local reg = Engine.Window({ key = "game:bags", pack = "system", frame = "ContainerFrameCombinedBags", watch = true,
    skip = covered,
    after = function(Kit, f) dressItems(Kit, f) end })

DUI.RegisterEvent("BAG_UPDATE_DELAYED", function()
    local f = _G.ContainerFrameCombinedBags
    if type(f) == "table" and f.IsShown and f:IsShown() and not covered() and reg.again then reg.again() end
end)
