ForeverRougeUI = ForeverRougeUI or {}
local addon = ForeverRougeUI

local bar, text, initialized

local function Update()
    local current, max = addon.GetEnergy()
    bar:SetMinMaxValues(0, max)
    bar:SetValue(current)
    if text then
        text:SetText(current .. " / " .. max)
    end
end

-- The energy bar is part of the addon's own resource display, same as
-- the combo bar - shown together only when "Use addon combo bar" is
-- checked, since Blizzard's Personal Resource Display already covers
-- health/power when that's the active choice instead. The ability
-- tracker above it is unaffected either way (see Tracker.lua).
function addon.ApplyEnergyBarVisibility()
    if bar then
        bar:SetShown(addon.GetDB().showComboPoints)
    end
end

function addon.InitEnergy()
    if initialized then
        Update()
        return
    end
    initialized = true

    local db = addon.GetDB().energy

    bar = CreateFrame("StatusBar", "ForeverRougeUIEnergyBar", addon.frame)
    addon.energyBar = bar
    bar:SetSize(db.width, db.height)
    bar:SetPoint("TOP", addon.frame, "TOP", 0, -40)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetStatusBarColor(1, 0.85, 0.1)
    bar:SetMinMaxValues(0, 100)

    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(bar)
    bg:SetColorTexture(0, 0, 0, 0.5)

    local border = CreateFrame("Frame", nil, bar, "BackdropTemplate")
    border:SetPoint("TOPLEFT", bar, "TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 1, -1)
    if border.SetBackdrop then
        border:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 8 })
        border:SetBackdropBorderColor(0, 0, 0, 1)
    end

    if db.showText then
        text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("CENTER", bar, "CENTER", 0, 0)
    end

    local watcher = CreateFrame("Frame")
    addon.SafeRegisterUnitEvent(watcher, "UNIT_POWER_UPDATE", "player")
    addon.SafeRegisterUnitEvent(watcher, "UNIT_POWER_FREQUENT", "player")
    addon.SafeRegisterUnitEvent(watcher, "UNIT_MAXPOWER", "player")
    addon.SafeRegisterEvent(watcher, "PLAYER_ENTERING_WORLD")
    watcher:SetScript("OnEvent", Update)

    Update()
    addon.ApplyEnergyBarVisibility()
end
