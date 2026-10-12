ForeverRougeUI = ForeverRougeUI or {}
local addon = ForeverRougeUI

-- A single row that tracks three kinds of things, all rendered the same
-- way (icon + countdown + "coming up" glow), auto-centered above the
-- energy bar, showing only while actually active:
--   "cooldown"     - a true ability reuse cooldown (Kick, Sprint, ...)
--   "targetDebuff" - a debuff you applied to your target (Rupture,
--                    Kidney Shot's stun, Gouge) - tracked by the aura's
--                    real remaining duration, not a guess
--   "playerBuff"   - a buff on yourself (Blade Flurry) - same, via your
--                    own aura's real remaining duration

local icons = {}
local row, initialized

local GCD_THRESHOLD = 1.6
local READY_SOON_THRESHOLD = 5

local function FormatTime(remaining)
    if remaining >= 60 then
        return ("%dm"):format(math.ceil(remaining / 60))
    elseif remaining > 3 then
        return ("%d"):format(math.ceil(remaining))
    else
        return ("%.1f"):format(remaining)
    end
end

local function SetGlow(iconFrame, remaining)
    if remaining and remaining <= READY_SOON_THRESHOLD then
        iconFrame.glow:Show()
        local pulse = 0.5 + 0.5 * math.abs(math.sin(GetTime() * 6))
        iconFrame.glow:SetAlpha(pulse)
    else
        iconFrame.glow:Hide()
    end
end

local function HideIcon(iconFrame)
    iconFrame.cooldown:Hide()
    iconFrame.glow:Hide()
    iconFrame.text:SetText("")
    iconFrame:Hide()
end

-- ---------------------------------------------------------------------
-- Cooldown-type icons
-- ---------------------------------------------------------------------

-- Some abilities' real cooldown is sealed by the client (an anti-
-- sniping measure covering interrupts and several CC effects, at least
-- on this server) - not even passing the value through to another API
-- is allowed. For those we never touch the sealed value: we track the
-- cast ourselves with our own GetTime() clock plus a configured
-- approximate duration from cooldowns.fallbackDurations.
local function UpdateSecretCooldownIcon(iconFrame)
    if not iconFrame.fallbackStart then
        return -- waiting for a cast event to arm it
    end

    local remaining = (iconFrame.fallbackStart + iconFrame.fallbackDuration) - GetTime()
    if remaining <= 0 then
        iconFrame.fallbackStart = nil
        HideIcon(iconFrame)
        return
    end

    iconFrame:Show()
    iconFrame.cooldown:SetCooldown(iconFrame.fallbackStart, iconFrame.fallbackDuration)
    iconFrame.cooldown:Show()
    iconFrame.text:SetText(FormatTime(remaining) .. "*")
    SetGlow(iconFrame, remaining)
end

local function UpdateCooldownIcon(iconFrame)
    local start, duration, enabled, texture = addon.GetSpellCooldownInfo(iconFrame.spellName)

    if texture and iconFrame.texture:GetTexture() ~= texture then
        iconFrame.texture:SetTexture(texture)
    end

    if iconFrame.secretMode then
        UpdateSecretCooldownIcon(iconFrame)
        return
    end

    local ok, remaining = pcall(function() return (start + duration) - GetTime() end)
    if not ok then
        iconFrame.secretMode = true
        return
    end

    if not enabled or duration <= GCD_THRESHOLD or start == 0 or remaining <= 0 then
        HideIcon(iconFrame)
        return
    end

    iconFrame:Show()
    iconFrame.cooldown:SetCooldown(start, duration)
    iconFrame.cooldown:Show()
    iconFrame.text:SetText(FormatTime(remaining))
    SetGlow(iconFrame, remaining)
end

local warnedNoFallback = {}

local function OnSpellCastSucceeded(spellID)
    for _, iconFrame in ipairs(icons) do
        if iconFrame.kind == "cooldown" and iconFrame.secretMode and iconFrame.spellID == spellID then
            local duration = addon.GetDB().tracker.fallbackDurations[iconFrame.spellName]
            if duration then
                iconFrame.fallbackStart = GetTime()
                iconFrame.fallbackDuration = duration
            elseif not warnedNoFallback[iconFrame.spellName] then
                warnedNoFallback[iconFrame.spellName] = true
                print(("ForeverRogue UI: %s's cooldown is sealed by the client and no fallback duration is set - add one under tracker.fallbackDurations in Config.lua to track it."):format(iconFrame.spellName))
            end
        end
    end
end

-- ---------------------------------------------------------------------
-- Aura-type icons (debuffs on target, buffs on self) - real durations,
-- not sealed, so these are exact.
-- ---------------------------------------------------------------------

local function FindAura(unit, name, filter)
    name = name:lower()
    for i = 1, 40 do
        local auraName, icon, duration, expirationTime, source = addon.GetUnitAuraByIndex(unit, i, filter)
        if not auraName then break end
        if auraName:lower() == name and (filter == "HELPFUL" or source == "player" or source == nil) then
            return icon, duration, expirationTime
        end
    end
    return nil
end

local function UpdateAuraIcon(iconFrame)
    local unit = iconFrame.kind == "playerBuff" and "player" or "target"
    local filter = iconFrame.kind == "playerBuff" and "HELPFUL" or "HARMFUL"

    if unit == "target" and not UnitExists("target") then
        HideIcon(iconFrame)
        return
    end

    local icon, duration, expirationTime = FindAura(unit, iconFrame.spellName, filter)
    if not icon then
        HideIcon(iconFrame)
        return
    end

    iconFrame:Show()
    if iconFrame.texture:GetTexture() ~= icon then
        iconFrame.texture:SetTexture(icon)
    end

    if duration and duration > 0 and expirationTime then
        local remaining = expirationTime - GetTime()
        if remaining > 0 then
            iconFrame.cooldown:SetCooldown(expirationTime - duration, duration)
            iconFrame.cooldown:Show()
            iconFrame.text:SetText(FormatTime(remaining))
            SetGlow(iconFrame, remaining)
            return
        end
    end

    -- No duration info (permanent-style effect) - just show the icon.
    iconFrame.cooldown:Hide()
    iconFrame.glow:Hide()
    iconFrame.text:SetText("")
end

-- ---------------------------------------------------------------------
-- Shared update + auto-centering layout
-- ---------------------------------------------------------------------

local function UpdateIcon(iconFrame)
    if iconFrame.kind == "cooldown" then
        UpdateCooldownIcon(iconFrame)
    else
        UpdateAuraIcon(iconFrame)
    end
end

local function ReflowVisibleIcons(iconSize, spacing)
    local visible = {}
    for _, iconFrame in ipairs(icons) do
        if iconFrame:IsShown() then
            visible[#visible + 1] = iconFrame
        end
    end

    local count = #visible
    row:SetSize(math.max(count * iconSize + math.max(0, count - 1) * spacing, 1), iconSize)
    for i, iconFrame in ipairs(visible) do
        iconFrame:ClearAllPoints()
        iconFrame:SetPoint("LEFT", row, "LEFT", (i - 1) * (iconSize + spacing), 0)
    end
end

local function UpdateAll()
    for _, iconFrame in ipairs(icons) do
        UpdateIcon(iconFrame)
    end
    local db = addon.GetDB().tracker
    ReflowVisibleIcons(db.iconSize, db.spacing)
end

local function CreateIcon(db, kind, spellName)
    local iconFrame = CreateFrame("Frame", nil, row)
    iconFrame.kind = kind
    iconFrame.spellName = spellName
    iconFrame:SetSize(db.iconSize, db.iconSize)
    iconFrame:Hide()

    iconFrame.texture = iconFrame:CreateTexture(nil, "ARTWORK")
    iconFrame.texture:SetAllPoints(iconFrame)
    iconFrame.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    iconFrame.cooldown = CreateFrame("Cooldown", nil, iconFrame, "CooldownFrameTemplate")
    iconFrame.cooldown:SetAllPoints(iconFrame)
    iconFrame.cooldown:SetDrawEdge(true)
    iconFrame.cooldown:SetHideCountdownNumbers(true)

    local glow = iconFrame:CreateTexture(nil, "OVERLAY")
    glow:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", -4, 4)
    glow:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", 4, -4)
    glow:SetTexture("Interface\\SpellActivationOverlay\\IconAlert")
    glow:SetTexCoord(0.00781250, 0.50781250, 0.53515625, 0.78515625)
    glow:SetBlendMode("ADD")
    glow:Hide()
    iconFrame.glow = glow

    iconFrame.text = iconFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    iconFrame.text:SetPoint("CENTER", iconFrame, "CENTER", 0, 0)

    iconFrame:EnableMouse(true)
    iconFrame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(self.spellName)
        GameTooltip:Show()
    end)
    iconFrame:SetScript("OnLeave", GameTooltip_Hide)

    if kind == "cooldown" then
        local index = addon.GetSpellBookIndex(spellName)
        iconFrame.spellID = index and addon.GetSpellIDForIndex(index)
        local texture = addon.GetSpellIconTexture(spellName)
        iconFrame.texture:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
    else
        iconFrame.texture:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end

    icons[#icons + 1] = iconFrame
    return iconFrame
end

function addon.InitTracker()
    if initialized then
        UpdateAll()
        return
    end
    initialized = true

    local db = addon.GetDB().tracker

    row = CreateFrame("Frame", "ForeverRougeUITrackerRow", addon.frame)
    addon.trackerRow = row
    row:SetSize(1, db.iconSize)
    if addon.energyBar then
        row:SetPoint("BOTTOM", addon.energyBar, "TOP", 0, 8)
    else
        row:SetPoint("BOTTOM", addon.frame, "TOP", 0, -8)
    end

    for _, name in ipairs(db.cooldowns) do
        CreateIcon(db, "cooldown", name)
    end
    for _, name in ipairs(db.targetDebuffs) do
        CreateIcon(db, "targetDebuff", name)
    end
    for _, name in ipairs(db.playerBuffs) do
        CreateIcon(db, "playerBuff", name)
    end

    local watcher = CreateFrame("Frame")
    addon.SafeRegisterEvent(watcher, "SPELL_UPDATE_COOLDOWN")
    addon.SafeRegisterEvent(watcher, "PLAYER_ENTERING_WORLD")
    addon.SafeRegisterEvent(watcher, "PLAYER_TARGET_CHANGED")
    addon.SafeRegisterUnitEvent(watcher, "UNIT_SPELLCAST_SUCCEEDED", "player")
    addon.SafeRegisterUnitEvent(watcher, "UNIT_AURA", "target")
    addon.SafeRegisterUnitEvent(watcher, "UNIT_AURA", "player")
    watcher:SetScript("OnEvent", function(_, event, unit, _, spellID)
        if event == "UNIT_SPELLCAST_SUCCEEDED" and unit == "player" then
            OnSpellCastSucceeded(spellID)
        end
        UpdateAll()
    end)

    local ticker = CreateFrame("Frame")
    local elapsedSinceUpdate = 0
    ticker:SetScript("OnUpdate", function(_, elapsed)
        elapsedSinceUpdate = elapsedSinceUpdate + elapsed
        if elapsedSinceUpdate >= 0.1 then
            elapsedSinceUpdate = 0
            UpdateAll()
        end
    end)

    UpdateAll()
end
