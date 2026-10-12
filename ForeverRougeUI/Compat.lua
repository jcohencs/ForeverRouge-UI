-- Thin wrappers over API calls that differ between retail, classic, and
-- the various private-server cores. Each function is defensive: if an
-- API doesn't exist it falls back to an older equivalent instead of
-- throwing, so the addon loads even if the exact client build is unknown.
ForeverRougeUI = ForeverRougeUI or {}
local addon = ForeverRougeUI

local ENERGY_POWER_TYPE = (Enum and Enum.PowerType and Enum.PowerType.Energy) or 3
local COMBO_POWER_TYPE = (Enum and Enum.PowerType and Enum.PowerType.ComboPoints) or 4

function addon.GetEnergy()
    local current = UnitPower("player", ENERGY_POWER_TYPE)
    local max = UnitPowerMax("player", ENERGY_POWER_TYPE)
    return current or 0, max or 100
end

function addon.GetComboPoints()
    -- Oldest API: global GetComboPoints(unit, target)
    if type(GetComboPoints) == "function" then
        local ok, points = pcall(GetComboPoints, "player", "target")
        if ok and points then
            return points, ForeverRougeUI.GetDB().comboPoints.maxPoints
        end
    end

    -- Newer API: combo points reported as a power type on the player
    local ok, current = pcall(UnitPower, "player", COMBO_POWER_TYPE)
    local maxOk, max = pcall(UnitPowerMax, "player", COMBO_POWER_TYPE)
    if ok and current then
        return current, (maxOk and max and max > 0) and max or ForeverRougeUI.GetDB().comboPoints.maxPoints
    end

    return 0, ForeverRougeUI.GetDB().comboPoints.maxPoints
end

-- Returns start, duration, isEnabled, texture for a spell looked up by name.
function addon.GetSpellCooldownInfo(name)
    local start, duration, enabled, texture

    if C_Spell and C_Spell.GetSpellCooldown then
        -- Retail: needs a spellID, so resolve the name first.
        local spellID = C_Spell.GetSpellIdForName and C_Spell.GetSpellIdForName(name)
        if spellID then
            local info = C_Spell.GetSpellCooldown(spellID)
            if info then
                start, duration, enabled = info.startTime, info.duration, info.isEnabled
            end
            local tex = C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellID)
            texture = tex
        end
    end

    if not start and type(GetSpellCooldown) == "function" then
        local ok, s, d, e = pcall(GetSpellCooldown, name)
        if ok then
            start, duration, enabled = s, d, e
        end
    end

    if not texture and type(GetSpellTexture) == "function" then
        local ok, tex = pcall(GetSpellTexture, name)
        if ok then
            texture = tex
        end
    end

    return start or 0, duration or 0, enabled ~= 0 and enabled ~= false, texture
end

-- Resolves an icon texture by spell name across API versions.
function addon.GetSpellIconTexture(name)
    if C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellIdForName then
        local spellID = C_Spell.GetSpellIdForName(name)
        if spellID then
            local tex = C_Spell.GetSpellTexture(spellID)
            if tex then
                return tex
            end
        end
    end

    if type(GetSpellTexture) == "function" then
        local ok, tex = pcall(GetSpellTexture, name)
        if ok and tex then
            return tex
        end
    end

    if type(GetSpellInfo) == "function" then
        local ok, _, _, tex = pcall(GetSpellInfo, name)
        if ok and tex then
            return tex
        end
    end

    return nil
end
