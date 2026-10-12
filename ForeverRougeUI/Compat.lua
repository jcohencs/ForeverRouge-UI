-- Thin wrappers over API calls that differ between retail, classic, and
-- the various private-server cores. Each function is defensive: if an
-- API doesn't exist it falls back to an older equivalent instead of
-- throwing, so the addon loads even if the exact client build is unknown.
ForeverRougeUI = ForeverRougeUI or {}
local addon = ForeverRougeUI

local ENERGY_POWER_TYPE = (Enum and Enum.PowerType and Enum.PowerType.Energy) or 3
local COMBO_POWER_TYPE = (Enum and Enum.PowerType and Enum.PowerType.ComboPoints) or 4
local SPELL_BOOK_TYPE = BOOKTYPE_SPELL or "spell"

-- This server's core doesn't support every standard Blizzard event
-- (e.g. LEARNED_SPELL_IN_TAB), and an unknown event throws a hard error
-- on RegisterEvent instead of failing quietly. Use these everywhere
-- instead of calling RegisterEvent/RegisterUnitEvent directly.
function addon.SafeRegisterEvent(frame, event)
    pcall(frame.RegisterEvent, frame, event)
end

function addon.SafeRegisterUnitEvent(frame, event, unit)
    pcall(frame.RegisterUnitEvent, frame, event, unit)
end

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

-- ---------------------------------------------------------------------
-- Spellbook scanning. On this server, looking spells up by name via the
-- "modern" GetSpellCooldown(name)/GetSpellTexture(name) calls comes back
-- empty, so instead we walk the player's actual spellbook (the same data
-- the default Blizzard spellbook UI reads) and match by name to get a
-- slot index. That index is then the reliable way to read cooldown and
-- icon info for that ability.
-- ---------------------------------------------------------------------

local spellIndexCache = {}

local function NormalizeName(name)
    return name and name:lower():gsub("^%s+", ""):gsub("%s+$", "")
end

local function ScanSpellbookFor(targetName)
    targetName = NormalizeName(targetName)
    if not targetName then return nil end

    local numTabs = GetNumSpellTabs and GetNumSpellTabs() or 0
    for tab = 1, numTabs do
        local _, _, offset, numSpells = GetSpellTabInfo(tab)
        offset = offset or 0
        numSpells = numSpells or 0
        for i = offset + 1, offset + numSpells do
            local spellName
            if type(GetSpellBookItemName) == "function" then
                local ok, n = pcall(GetSpellBookItemName, i, SPELL_BOOK_TYPE)
                if ok then spellName = n end
            end
            if spellName and NormalizeName(spellName) == targetName then
                return i
            end
        end
    end
    return nil
end

-- Resolves (and caches) the spellbook slot index for a spell name.
-- Returns nil if the spell isn't currently in the player's spellbook
-- (not learned, rune not engraved yet, wrong spec, etc).
function addon.GetSpellBookIndex(name, forceRescan)
    if not forceRescan and spellIndexCache[name] then
        return spellIndexCache[name]
    end
    local index = ScanSpellbookFor(name)
    if index then
        spellIndexCache[name] = index
    end
    return index
end

function addon.InvalidateSpellBookCache()
    wipe(spellIndexCache)
end

-- Returns start, duration, isEnabled, texture for a spell looked up by name.
function addon.GetSpellCooldownInfo(name)
    local start, duration, enabled, texture

    -- Preferred path on this server: resolve via spellbook slot.
    local index = addon.GetSpellBookIndex(name)
    if not index then
        -- spellbook layout can shift (talents/runes) - rescan once before giving up
        index = addon.GetSpellBookIndex(name, true)
    end

    if index then
        if type(GetSpellCooldown) == "function" then
            local ok, s, d, e = pcall(GetSpellCooldown, index, SPELL_BOOK_TYPE)
            if ok and s then
                start, duration, enabled = s, d, e
            end
        end
        if type(GetSpellBookItemTexture) == "function" then
            local ok, tex = pcall(GetSpellBookItemTexture, index, SPELL_BOOK_TYPE)
            if ok then
                texture = tex
            end
        end
    end

    -- Retail fallback: name -> spellID -> C_Spell.
    if not start and C_Spell and C_Spell.GetSpellCooldown then
        local spellID = C_Spell.GetSpellIdForName and C_Spell.GetSpellIdForName(name)
        if spellID then
            local info = C_Spell.GetSpellCooldown(spellID)
            if info then
                start, duration, enabled = info.startTime, info.duration, info.isEnabled
            end
            if not texture and C_Spell.GetSpellTexture then
                texture = C_Spell.GetSpellTexture(spellID)
            end
        end
    end

    -- Last resort: the classic by-name global, in case this ability
    -- just isn't showing up in the spellbook scan for some reason.
    if not start and type(GetSpellCooldown) == "function" then
        local ok, s, d, e = pcall(GetSpellCooldown, name)
        if ok and s then
            start, duration, enabled = s, d, e
        end
    end
    if not texture and type(GetSpellTexture) == "function" then
        local ok, tex = pcall(GetSpellTexture, name)
        if ok and tex then
            texture = tex
        end
    end

    return start or 0, duration or 0, enabled ~= 0 and enabled ~= false, texture
end

-- Resolves an icon texture by spell name across API versions.
function addon.GetSpellIconTexture(name)
    local index = addon.GetSpellBookIndex(name)
    if index and type(GetSpellBookItemTexture) == "function" then
        local ok, tex = pcall(GetSpellBookItemTexture, index, SPELL_BOOK_TYPE)
        if ok and tex then
            return tex
        end
    end

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

-- Returns name, icon, duration, expirationTime, source for the aura at
-- a given index on a unit, regardless of whether this client exposes
-- the old UnitAura() global or only the newer C_UnitAuras namespace.
function addon.GetUnitAuraByIndex(unit, index, filter)
    if type(UnitAura) == "function" then
        local ok, name, icon, _, _, duration, expirationTime, source = pcall(UnitAura, unit, index, filter)
        if ok and name then
            return name, icon, duration, expirationTime, source
        end
    end

    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        local ok, data = pcall(C_UnitAuras.GetAuraDataByIndex, unit, index, filter)
        if ok and data then
            return data.name, data.icon, data.duration, data.expirationTime, data.sourceUnit
        end
    end

    return nil
end

-- Debug helper: /frui debug <ability name> prints what each lookup path
-- returns, to diagnose a specific ability that still won't show up.
function addon.DebugSpell(name)
    print("ForeverRogue UI debug: '" .. name .. "'")
    local index = addon.GetSpellBookIndex(name, true)
    print("  spellbook index: " .. tostring(index))
    if index then
        local n = GetSpellBookItemName and GetSpellBookItemName(index, SPELL_BOOK_TYPE)
        print("  spellbook name at index: " .. tostring(n))
    end
    local start, duration, enabled, texture = addon.GetSpellCooldownInfo(name)
    print(("  start=%s duration=%s enabled=%s texture=%s"):format(
        tostring(start), tostring(duration), tostring(enabled), tostring(texture)))
end
