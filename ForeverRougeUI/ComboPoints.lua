ForeverRougeUI = ForeverRougeUI or {}
local addon = ForeverRougeUI

-- Optional, off by default (see Options panel) - Blizzard's own
-- Personal Resource Display already shows combo points natively, so
-- this is an alternative for anyone who wants our own HUD-styled bar
-- instead. Enabling it disables Blizzard's (see
-- addon.ApplyComboBarChoice in Core.lua) so only one is ever shown.
-- Plain SetColorTexture boxes: the one rendering approach that's
-- actually worked reliably on this client, after :SetMask and
-- :SetAtlas both turned out to be silent no-ops here.

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

        -- Faint background, always visible, so empty slots still show.
        local bg = pip:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(pip)
        bg:SetColorTexture(1, 1, 1, 0.15)
        pip.bg = bg

        -- Solid blue box, hidden until this point is actually filled.
        local tex = pip:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints(pip)
        tex:SetColorTexture(0.1, 0.5, 1, 1)
        pip.texture = tex

        pips[i] = pip
    end
end

local lastMax = 0

-- Mutual exclusion with Blizzard's own Personal Resource Display is
-- handled by addon.ApplyComboBarChoice() in Core.lua (it flips the
-- nameplateShowSelf CVar opposite to this setting), not by anything
-- here - this row just follows the setting directly.
local function Update()
    local visible = addon.GetDB().showComboPoints
    row:SetShown(visible)
    if not visible then return end

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

-- Called whenever the Options panel checkbox is toggled, so the row
-- shows/hides immediately instead of waiting for the next combo point
-- event.
function addon.RefreshComboPointsVisibility()
    if row then Update() end
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
        -- Directly under the energy bar, not above it - the ability
        -- tracker is what goes above the energy bar (see
        -- addon.ReanchorTrackerRow in Tracker.lua).
        row:SetPoint("TOP", addon.energyBar, "BOTTOM", 0, -6)
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
