ForeverRougeUI = ForeverRougeUI or {}
local addon = ForeverRougeUI

local frame = CreateFrame("Frame", "ForeverRougeUIFrame", UIParent)
addon.frame = frame
frame:SetSize(300, 150)
frame:SetMovable(true)
frame:SetClampedToScreen(true)
frame:EnableMouse(false)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local db = addon.GetDB()
    local point, _, _, x, y = self:GetPoint()
    db.point, db.x, db.y = point, x, y
end)

local function ApplyPosition()
    local db = addon.GetDB()
    frame:ClearAllPoints()
    frame:SetPoint(db.point, UIParent, db.point, db.x, db.y)
    frame:SetScale(db.scale)
end

local function ApplyLock()
    local db = addon.GetDB()
    frame:EnableMouse(not db.locked)
end

function addon.IsPlayerRogue()
    local _, class = UnitClass("player")
    return class == "ROGUE"
end

local eventFrame = CreateFrame("Frame")
addon.SafeRegisterEvent(eventFrame, "PLAYER_LOGIN")
addon.SafeRegisterEvent(eventFrame, "PLAYER_ENTERING_WORLD")
addon.SafeRegisterEvent(eventFrame, "SPELLS_CHANGED")
addon.SafeRegisterEvent(eventFrame, "LEARNED_SPELL_IN_TAB")
eventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        addon.GetDB()
        ApplyPosition()
        ApplyLock()
    end

    if event == "SPELLS_CHANGED" or event == "LEARNED_SPELL_IN_TAB" then
        if addon.InvalidateSpellBookCache then addon.InvalidateSpellBookCache() end
        return
    end

    if not addon.IsPlayerRogue() then
        frame:Hide()
        return
    end
    frame:Show()

    -- Order matters: the tracker row anchors above the energy bar, and
    -- combo points anchor below it.
    if addon.InitEnergy then addon.InitEnergy() end
    if addon.InitTracker then addon.InitTracker() end
    if addon.InitComboPoints then addon.InitComboPoints() end
end)

SLASH_FOREVERROGUEUI1 = "/frui"
SlashCmdList["FOREVERROGUEUI"] = function(msg)
    msg = strtrim((msg or ""):lower())
    local db = addon.GetDB()

    if msg == "lock" then
        db.locked = true
        ApplyLock()
        print("ForeverRogue UI: locked.")
    elseif msg == "unlock" then
        db.locked = false
        ApplyLock()
        print("ForeverRogue UI: unlocked, drag to move.")
    elseif msg == "reset" then
        db.point, db.x, db.y, db.scale = addon.defaults.point, addon.defaults.x, addon.defaults.y, addon.defaults.scale
        ApplyPosition()
        print("ForeverRogue UI: position reset.")
    elseif msg:match("^scale") then
        local value = tonumber(msg:match("scale%s+([%d%.]+)"))
        if value and value > 0.3 and value < 3 then
            db.scale = value
            ApplyPosition()
            print("ForeverRogue UI: scale set to " .. value)
        else
            print("ForeverRogue UI: usage /frui scale 1.0")
        end
    elseif msg == "env" then
        if addon.DebugEnvironment then addon.DebugEnvironment() end
    elseif msg:match("^debug") then
        local spellName = msg:match("^debug%s+(.+)$")
        if spellName and addon.DebugSpell then
            addon.DebugSpell(spellName)
        else
            print("ForeverRogue UI: usage /frui debug <spell name>")
        end
    elseif msg:match("^auras") then
        local unit, filter = msg:match("^auras%s*(%a*)%s*(%a*)$")
        unit = (unit and unit ~= "") and unit or "target"
        filter = (filter and filter ~= "") and filter:upper() or (unit == "player" and "HELPFUL" or "HARMFUL")
        if addon.DebugAuras then addon.DebugAuras(unit, filter) end
    elseif msg == "auralog on" then
        if addon.SetAuraLogging then addon.SetAuraLogging(true) end
    elseif msg == "auralog off" then
        if addon.SetAuraLogging then addon.SetAuraLogging(false) end
    elseif msg == "combo" then
        if addon.DebugComboPoints then addon.DebugComboPoints() end
    else
        print("ForeverRogue UI commands: /frui unlock, /frui lock, /frui reset, /frui scale <n>, /frui debug <spell name>, /frui env, /frui auras <unit> <filter>, /frui auralog on|off, /frui combo")
    end
end
