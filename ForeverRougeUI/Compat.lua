-- Thin wrappers over API calls that differ between retail, classic, and
-- the various private-server cores. Each function is defensive: if an
-- API doesn't exist it falls back to an older equivalent instead of
-- throwing, so the addon loads even if the exact client build is unknown.
ForeverRougeUI = ForeverRougeUI or {}
local addon = ForeverRougeUI

local ENERGY_POWER_TYPE = (Enum and Enum.PowerType and Enum.PowerType.Energy) or 3
local COMBO_POWER_TYPE = (Enum and Enum.PowerType and Enum.PowerType.ComboPoints) or 4

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
-- Spellbook scanning. This client only exposes the modern C_SpellBook /
-- C_Spell namespaces (no legacy GetSpellTabInfo/GetSpellCooldown(name)
-- globals at all), and C_Spell has no name->spellID lookup. So we walk
-- the player's actual spellbook via C_SpellBook, match by name to get a
-- slot index, read the spellID for that slot from C_SpellBook, and then
-- use that spellID with C_Spell for cooldown/texture.
-- ---------------------------------------------------------------------

local SPELL_BOOK_BANK = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0

local spellIndexCache = {}
local spellIDCache = {}

local function NormalizeName(name)
    return name and name:lower():gsub("^%s+", ""):gsub("%s+$", "")
end

local function ScanSpellbookFor(targetName)
    targetName = NormalizeName(targetName)
    if not targetName then return nil end
    if not (C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookSkillLineInfo and C_SpellBook.GetSpellBookItemName) then
        return nil
    end

    local okLines, numLines = pcall(C_SpellBook.GetNumSpellBookSkillLines)
    if not okLines or not numLines then return nil end

    for line = 1, numLines do
        local okInfo, lineInfo = pcall(C_SpellBook.GetSpellBookSkillLineInfo, line)
        if okInfo and lineInfo then
            local offset = lineInfo.itemIndexOffset or 0
            local numItems = lineInfo.numSpellBookItems or 0
            for i = offset + 1, offset + numItems do
                local okName, spellName = pcall(C_SpellBook.GetSpellBookItemName, i, SPELL_BOOK_BANK)
                if okName and spellName and NormalizeName(spellName) == targetName then
                    return i
                end
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

-- Resolves (and caches) the numeric spellID behind a spellbook index.
function addon.GetSpellIDForIndex(index)
    if not index then return nil end
    if spellIDCache[index] then return spellIDCache[index] end
    if not (C_SpellBook and C_SpellBook.GetSpellBookItemInfo) then return nil end

    local ok, info = pcall(C_SpellBook.GetSpellBookItemInfo, index, SPELL_BOOK_BANK)
    if ok and info and info.spellID then
        spellIDCache[index] = info.spellID
        return info.spellID
    end
    return nil
end

function addon.InvalidateSpellBookCache()
    wipe(spellIndexCache)
    wipe(spellIDCache)
end

-- Returns start, duration, isEnabled, texture for a spell looked up by name.
function addon.GetSpellCooldownInfo(name)
    local start, duration, enabled, texture

    local index = addon.GetSpellBookIndex(name)
    if not index then
        -- spellbook layout can shift (talents/runes) - rescan once before giving up
        index = addon.GetSpellBookIndex(name, true)
    end

    if index then
        if C_SpellBook and C_SpellBook.GetSpellBookItemTexture then
            local ok, tex = pcall(C_SpellBook.GetSpellBookItemTexture, index, SPELL_BOOK_BANK)
            if ok then
                texture = tex
            end
        end

        local spellID = addon.GetSpellIDForIndex(index)
        if spellID and C_Spell and C_Spell.GetSpellCooldown then
            local ok, info = pcall(C_Spell.GetSpellCooldown, spellID)
            if ok and info then
                start, duration, enabled = info.startTime, info.duration, info.isEnabled
            end
            if not texture and C_Spell.GetSpellTexture then
                local okTex, tex = pcall(C_Spell.GetSpellTexture, spellID)
                if okTex then texture = tex end
            end
        end
    end

    -- Legacy fallback, in case a future server patch brings these back.
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

    return start or 0, duration or 0, enabled ~= false, texture
end

-- Resolves an icon texture by spell name across API versions.
function addon.GetSpellIconTexture(name)
    local index = addon.GetSpellBookIndex(name)

    if index and C_SpellBook and C_SpellBook.GetSpellBookItemTexture then
        local ok, tex = pcall(C_SpellBook.GetSpellBookItemTexture, index, SPELL_BOOK_BANK)
        if ok and tex then
            return tex
        end
    end

    local spellID = index and addon.GetSpellIDForIndex(index)
    if spellID and C_Spell and C_Spell.GetSpellTexture then
        local ok, tex = pcall(C_Spell.GetSpellTexture, spellID)
        if ok and tex then
            return tex
        end
    end

    if type(GetSpellTexture) == "function" then
        local ok, tex = pcall(GetSpellTexture, name)
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

-- Debug helper: /frui auras <unit> <filter> dumps every aura currently
-- found on a unit (default target/HARMFUL), to see why a tracked debuff
-- or buff isn't matching - wrong name, wrong source, or not found at
-- all by either aura API.
function addon.DebugAuras(unit, filter)
    unit = unit or "target"
    filter = filter or "HARMFUL"
    print(("ForeverRogue UI aura dump: unit=%s filter=%s"):format(unit, filter))

    if not UnitExists(unit) then
        print("  unit does not exist")
        return
    end

    local count = 0
    for i = 1, 40 do
        local name, _, duration, expirationTime, source = addon.GetUnitAuraByIndex(unit, i, filter)
        if not name then break end
        count = count + 1
        print(("  [%d] '%s' source=%s duration=%s expirationTime=%s"):format(
            i, name, tostring(source), tostring(duration), tostring(expirationTime)))
    end

    if count == 0 then
        print("  (no auras found via either UnitAura or C_UnitAuras)")
    end
end

-- Debug helper: /frui env prints which spellbook/cooldown APIs this
-- client actually exposes, so we can target the real API instead of
-- guessing at another combination blind.
function addon.DebugEnvironment()
    local function yn(v) return v and "yes" or "no" end

    print("ForeverRogue UI environment probe:")
    print("  GetNumSpellTabs: " .. yn(type(GetNumSpellTabs) == "function"))
    print("  GetSpellTabInfo: " .. yn(type(GetSpellTabInfo) == "function"))
    print("  GetSpellBookItemName: " .. yn(type(GetSpellBookItemName) == "function"))
    print("  GetSpellBookItemTexture: " .. yn(type(GetSpellBookItemTexture) == "function"))
    print("  GetSpellBookItemInfo: " .. yn(type(GetSpellBookItemInfo) == "function"))
    print("  GetSpellCooldown: " .. yn(type(GetSpellCooldown) == "function"))
    print("  GetSpellTexture: " .. yn(type(GetSpellTexture) == "function"))
    print("  GetSpellInfo: " .. yn(type(GetSpellInfo) == "function"))
    print("  C_SpellBook: " .. yn(C_SpellBook ~= nil))
    if C_SpellBook then
        for _, fn in ipairs({ "GetNumSpellBookSkillLines", "GetSpellBookSkillLineInfo", "GetSpellBookItemName", "GetSpellBookItemInfo", "GetSpellBookItemTexture" }) do
            print("    C_SpellBook." .. fn .. ": " .. yn(type(C_SpellBook[fn]) == "function"))
        end
    end
    print("  C_Spell: " .. yn(C_Spell ~= nil))
    if C_Spell then
        for _, fn in ipairs({ "GetSpellCooldown", "GetSpellTexture", "GetSpellInfo", "GetSpellIdForName", "GetSpellName" }) do
            print("    C_Spell." .. fn .. ": " .. yn(type(C_Spell[fn]) == "function"))
        end
    end
    print("  C_UnitAuras: " .. yn(C_UnitAuras ~= nil))
    print("  UnitAura: " .. yn(type(UnitAura) == "function"))

    if type(GetNumSpellTabs) == "function" then
        local ok, n = pcall(GetNumSpellTabs)
        print("  GetNumSpellTabs() = " .. tostring(ok and n))
        if ok and n and n > 0 then
            local okTab, name, _, offset, numSpells = pcall(GetSpellTabInfo, 1)
            print("  GetSpellTabInfo(1) = " .. tostring(okTab) .. " " .. tostring(name) .. " offset=" .. tostring(offset) .. " numSpells=" .. tostring(numSpells))
        end
    end
    if C_SpellBook and type(C_SpellBook.GetNumSpellBookSkillLines) == "function" then
        local ok, n = pcall(C_SpellBook.GetNumSpellBookSkillLines)
        print("  C_SpellBook.GetNumSpellBookSkillLines() = " .. tostring(ok and n))
    end
end

-- Debug helper: /frui debug <ability name> prints what each lookup path
-- returns, to diagnose a specific ability that still won't show up.
function addon.DebugSpell(name)
    print("ForeverRogue UI debug: '" .. name .. "'")
    local index = addon.GetSpellBookIndex(name, true)
    print("  spellbook index: " .. tostring(index))
    if index then
        if C_SpellBook and C_SpellBook.GetSpellBookItemName then
            local ok, n = pcall(C_SpellBook.GetSpellBookItemName, index, SPELL_BOOK_BANK)
            print("  spellbook name at index: " .. tostring(ok and n))
        end
        print("  spellID: " .. tostring(addon.GetSpellIDForIndex(index)))
    end
    local start, duration, enabled, texture = addon.GetSpellCooldownInfo(name)
    print(("  start=%s duration=%s enabled=%s texture=%s"):format(
        tostring(start), tostring(duration), tostring(enabled), tostring(texture)))
end
