ForeverRougeUI = ForeverRougeUI or {}
local addon = ForeverRougeUI

local pips = {}
local row, initialized

-- Real Blizzard art, discovered via /framestack on this client's own
-- Personal Resource Display (source:
-- Interface/AddOns/Blizzard_UnitFrame/Mainline/RogueComboPoint.xml) -
-- the "Slash" combo point mark, in the only color this server's client
-- ships (confirmed via /frui atlases: no red or round variant exists
-- here, and the art itself isn't a tintable white base).
local COMBO_POINT_ATLAS = "UI-RogueCP-Slash-Blue"

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
        -- false = scale to our own pip size rather than the atlas's
        -- native dimensions.
        local ok = tex.SetAtlas and pcall(tex.SetAtlas, tex, COMBO_POINT_ATLAS, false)
        if not ok then
            -- This client doesn't have the atlas after all - fall back
            -- to a plain red square rather than showing nothing.
            tex:SetColorTexture(1, 0, 0, 1)
        end
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
