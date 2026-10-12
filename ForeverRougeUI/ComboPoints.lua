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

    -- Real textures shipped with the addon - :SetMask doesn't work
    -- reliably on this server's client, so pre-made art, tinted via
    -- vertex color, is the only approach that's actually rendered as a
    -- circle. Both are pure white where opaque, so tinting gives back
    -- the exact color with no brightness cap from the base art.
    local RING_TEXTURE = "Interface\\AddOns\\ForeverRougeUI\\media\\circle_ring"
    local FILL_TEXTURE = "Interface\\AddOns\\ForeverRougeUI\\media\\circle"

    for i = 1, maxPoints do
        local pip = CreateFrame("Frame", nil, row)
        pip:SetSize(db.pointSize, db.pointSize)
        pip:SetPoint("LEFT", row, "LEFT", (i - 1) * (db.pointSize + db.spacing), 0)

        -- Black ring outline, always visible. This is a true ring (a
        -- ring shape with a transparent hole, not a filled disc), so
        -- the center stays genuinely transparent rather than reading
        -- as a solid black circle whenever the fill below is hidden.
        local outline = pip:CreateTexture(nil, "BORDER")
        outline:SetAllPoints(pip)
        outline:SetTexture(RING_TEXTURE)
        outline:SetVertexColor(0, 0, 0, 1)
        pip.outline = outline

        -- Colored fill, inset within the ring's hole, hidden (alpha 0)
        -- until this point is actually filled.
        local tex = pip:CreateTexture(nil, "ARTWORK")
        tex:SetPoint("TOPLEFT", pip, "TOPLEFT", 4, -4)
        tex:SetPoint("BOTTOMRIGHT", pip, "BOTTOMRIGHT", -4, 4)
        tex:SetTexture(FILL_TEXTURE)
        tex:SetVertexColor(1, 0, 0, 1) -- pure, maximally bright red
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
