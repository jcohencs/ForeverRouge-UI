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

    -- Plain solid-color textures, clipped into circles with an alpha
    -- mask - this is a flat RGB fill with no base-texture brightness to
    -- fight against, so the red comes out exactly as bright as set.
    local CIRCLE_MASK = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"

    for i = 1, maxPoints do
        local pip = CreateFrame("Frame", nil, row)
        pip:SetSize(db.pointSize, db.pointSize)
        pip:SetPoint("LEFT", row, "LEFT", (i - 1) * (db.pointSize + db.spacing), 0)

        -- Black outline ring, always visible - drawn full-size, behind
        -- the fill, so it still shows as an empty circle before this
        -- point is filled.
        local outline = pip:CreateTexture(nil, "BORDER")
        outline:SetAllPoints(pip)
        outline:SetColorTexture(0, 0, 0, 1)
        outline:SetMask(CIRCLE_MASK)
        pip.outline = outline

        -- Colored fill, inset slightly so the outline reads as a ring,
        -- hidden (alpha 0) until this point is actually filled.
        local tex = pip:CreateTexture(nil, "ARTWORK")
        tex:SetPoint("TOPLEFT", pip, "TOPLEFT", 2, -2)
        tex:SetPoint("BOTTOMRIGHT", pip, "BOTTOMRIGHT", -2, 2)
        tex:SetColorTexture(1, 0, 0, 1) -- pure, maximally bright red
        tex:SetMask(CIRCLE_MASK)
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
        pip.texture:SetAlpha(i <= current and 1 or 0)
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
