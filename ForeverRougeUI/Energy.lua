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
    if addon.cooldownRow then
        bar:SetPoint("TOP", addon.cooldownRow, "BOTTOM", 0, -8)
    else
        bar:SetPoint("TOP", addon.frame, "TOP", 0, 0)
    end
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
    watcher:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
    watcher:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
    watcher:RegisterUnitEvent("UNIT_MAXPOWER", "player")
    watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
    watcher:SetScript("OnEvent", Update)

    Update()
end
