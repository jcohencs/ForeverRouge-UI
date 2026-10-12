ForeverRougeUI = ForeverRougeUI or {}
local addon = ForeverRougeUI

local pips = {}
local row, initialized

local function RebuildPips(maxPoints)
    local db = addon.GetDB().comboPoints
    for _, pip in ipairs(pips) do
        pip:Hide()
    end
    wipe(pips)

    local totalWidth = maxPoints * db.pointSize + math.max(0, maxPoints - 1) * db.spacing
    row:SetSize(totalWidth, db.pointSize)

    for i = 1, maxPoints do
        local pip = CreateFrame("Frame", nil, row)
        pip:SetSize(db.pointSize, db.pointSize)
        pip:SetPoint("LEFT", row, "LEFT", (i - 1) * (db.pointSize + db.spacing), 0)

        local tex = pip:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints(pip)
        tex:SetColorTexture(1, 0.2, 0.2, 1)
        pip.texture = tex

        pips[i] = pip
    end
end

local lastMax = 0

local function Update()
    local current, max = addon.GetComboPoints()
    max = max or 5

    if max ~= lastMax then
        lastMax = max
        RebuildPips(max)
    end

    for i, pip in ipairs(pips) do
        if i <= current then
            pip.texture:SetAlpha(1)
        else
            pip.texture:SetAlpha(0.25)
        end
    end
end

function addon.InitComboPoints()
    if initialized then
        Update()
        return
    end
    initialized = true

    row = CreateFrame("Frame", "ForeverRougeUIComboRow", addon.frame)
    addon.comboRow = row
    if addon.energyBar then
        row:SetPoint("TOP", addon.energyBar, "BOTTOM", 0, -8)
    else
        row:SetPoint("TOP", addon.frame, "TOP", 0, -40)
    end

    local watcher = CreateFrame("Frame")
    addon.SafeRegisterUnitEvent(watcher, "UNIT_POWER_UPDATE", "player")
    addon.SafeRegisterUnitEvent(watcher, "UNIT_POWER_FREQUENT", "player")
    addon.SafeRegisterUnitEvent(watcher, "UNIT_MAXPOWER", "player")
    addon.SafeRegisterEvent(watcher, "PLAYER_TARGET_CHANGED")
    addon.SafeRegisterEvent(watcher, "PLAYER_ENTERING_WORLD")
    watcher:SetScript("OnEvent", Update)

    Update()
end
