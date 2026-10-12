ForeverRougeUI = ForeverRougeUI or {}
local addon = ForeverRougeUI

-- A single row that tracks three kinds of things, each in its own
-- permanent slot left-aligned to the energy bar (ordered per
-- tracker.displayOrder, Slice and Dice first), showing only while
-- actually active - an inactive one just leaves its slot empty:
--   "cooldown"     - a true ability reuse cooldown (Kick, Sprint, ...)
--   "targetDebuff" - a debuff you applied to your target (Rupture,
--                    Kidney Shot's stun, Gouge) - tracked by the aura's
--                    real remaining duration, not a guess
--   "playerBuff"   - a buff on yourself (Blade Flurry) - same, via your
--                    own aura's real remaining duration

local icons = {}
local row, initialized

local GCD_THRESHOLD = 1.6
-- This server's aura API (UnitAura/C_UnitAuras) is flaky: it
-- intermittently returns no data for a unit even while the real aura
-- is confirmed still active (verified live - a known debuff vanished
-- from several consecutive reads, then reappeared with its
-- expirationTime completely unchanged, proving it was never actually
-- removed). Since the row polls every 0.1s, trusting a single miss
-- would hide-then-reshow icons faster than the eye can see, looking
-- like "it just doesn't work." So a miss only hides the icon once this
-- many seconds have passed with zero successful reads. Blade Flurry
-- showed the flakiness can run longer than a second at a stretch, so
-- this plus the cast-fallback timer (see CheckCastFallback) together
-- cover it: this bridges short gaps, the fallback timer covers the
-- rest if the live read doesn't come back before the buff should
-- actually be ending.
local AURA_FLAKE_GRACE = 2.5

-- Floors rather than rounds up, so the number never overstates how
-- much time is actually left - rounding up would show e.g. "1" for the
-- entire last second before an ability is really ready, which reads as
-- the tracker lagging behind the real timer.
local function FormatTime(remaining)
    if remaining >= 60 then
        return ("%dm"):format(math.floor(remaining / 60))
    elseif remaining > 3 then
        return ("%d"):format(math.floor(remaining))
    else
        return ("%.1f"):format(remaining)
    end
end

local function HideIcon(iconFrame)
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
    iconFrame.text:SetText(FormatTime(remaining))
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
    iconFrame.text:SetText(FormatTime(remaining))
end

local warnedNoFallback = {}

-- Some finishers' effect scales with combo points spent (Rupture's
-- duration, for one). Combo points reset to 0 the moment the finisher
-- lands, before we'd ever get a chance to read them - so this tracks
-- the last-seen *nonzero* combo count continuously, meaning by the
-- time a finisher's UNIT_SPELLCAST_SUCCEEDED fires, this still holds
-- however many points were spent on it.
local lastComboPoints = 0

local function TrackComboPoints()
    local current = addon.GetComboPoints()
    if current and current > 0 then
        lastComboPoints = current
    end
end

-- /frui combo prints both live values side by side, to check the
-- combo-scaled fallback (Rupture) is seeing what you actually spent.
function addon.DebugComboPoints()
    local current = addon.GetComboPoints()
    print(("ForeverRogue UI: live combo points=%s, last tracked nonzero=%s"):format(
        tostring(current), tostring(lastComboPoints)))
end

-- duration = base + perPoint * comboPointsSpent, for abilities whose
-- fallback timer needs to scale with combo points (see
-- tracker.comboScaledDurations in Config.lua). Falls back to the flat
-- tracker.fallbackDurations value for everything else.
local function GetFallbackDuration(spellName)
    local fullDB = addon.GetDB()
    local db = fullDB.tracker
    local scaling = db.comboScaledDurations and db.comboScaledDurations[spellName]
    if scaling then
        local maxPoints = (fullDB.comboPoints and fullDB.comboPoints.maxPoints) or 5
        local points = math.max(1, math.min(lastComboPoints, maxPoints))
        return scaling.base + scaling.perPoint * points
    end
    return db.fallbackDurations[spellName]
end

local function OnSpellCastSucceeded(spellID)
    for _, iconFrame in ipairs(icons) do
        if iconFrame.spellID == spellID then
            if iconFrame.kind == "cooldown" and iconFrame.secretMode then
                local duration = GetFallbackDuration(iconFrame.spellName)
                if duration then
                    iconFrame.fallbackStart = GetTime()
                    iconFrame.fallbackDuration = duration
                elseif not warnedNoFallback[iconFrame.spellName] then
                    warnedNoFallback[iconFrame.spellName] = true
                    print(("ForeverRogue UI: %s's cooldown is sealed by the client and no fallback duration is set - add one under tracker.fallbackDurations in Config.lua to track it."):format(iconFrame.spellName))
                end
            elseif iconFrame.kind ~= "cooldown" then
                -- Arm a self-timed backup too, in case the live aura
                -- read for this effect isn't available at all (e.g. this
                -- server seems to hide enemy debuff durations from
                -- addons, similar to how interrupt cooldowns are
                -- sealed). Only ever used if the live read comes up
                -- empty - see UpdateAuraIcon.
                local duration = GetFallbackDuration(iconFrame.spellName)
                if duration then
                    iconFrame.castFallbackStart = GetTime()
                    iconFrame.castFallbackDuration = duration
                end
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
        if not auraName then
            -- The read API is flaky - retry once immediately before
            -- concluding the list actually ends here, so one bad read
            -- doesn't wipe out every aura after it in this same scan.
            auraName, icon, duration, expirationTime, source = addon.GetUnitAuraByIndex(unit, i, filter)
            if not auraName then break end
        end
        if auraName:lower() == name and (filter == "HELPFUL" or source == "player" or source == nil) then
            return icon, duration, expirationTime
        end
    end
    return nil
end

-- Checks this icon's self-timed backup (armed from OnSpellCastSucceeded
-- when a live aura read isn't available for it at all). Returns the
-- remaining seconds, or nil if there's no active backup timer.
local function CheckCastFallback(iconFrame)
    if not iconFrame.castFallbackStart then
        return nil
    end
    local remaining = (iconFrame.castFallbackStart + iconFrame.castFallbackDuration) - GetTime()
    if remaining <= 0 then
        iconFrame.castFallbackStart = nil
        return nil
    end
    return remaining
end

local function ShowFromCastFallback(iconFrame, remaining)
    iconFrame:Show()
    iconFrame.text:SetText(FormatTime(remaining))
end

local function UpdateAuraIcon(iconFrame)
    -- Keep retrying the spellbook texture, the same way cooldown-kind
    -- icons do every tick. These icons only otherwise get a texture
    -- from a live aura read, which never succeeds for some of them
    -- (the cast-fallback path doesn't carry one) - so if the very first
    -- lookup happened before the spellbook was fully populated, nothing
    -- would ever correct it without this.
    local spellTexture = addon.GetSpellIconTexture(iconFrame.spellName)
    if spellTexture and iconFrame.texture:GetTexture() ~= spellTexture then
        iconFrame.texture:SetTexture(spellTexture)
    end

    local unit = iconFrame.kind == "playerBuff" and "player" or "target"
    local filter = iconFrame.kind == "playerBuff" and "HELPFUL" or "HARMFUL"
    local targetGone = unit == "target" and not UnitExists("target")

    if not targetGone then
        local icon, duration, expirationTime = FindAura(unit, iconFrame.spellName, filter)
        if icon then
            iconFrame.lastSeenTime = GetTime()
            iconFrame:Show()
            if iconFrame.texture:GetTexture() ~= icon then
                iconFrame.texture:SetTexture(icon)
            end

            if duration and duration > 0 and expirationTime then
                iconFrame.lastKnownExpiration = expirationTime
                iconFrame.lastKnownDuration = duration
                local remaining = expirationTime - GetTime()
                if remaining > 0 then
                    iconFrame.text:SetText(FormatTime(remaining))
                    return
                end
            else
                iconFrame.lastKnownExpiration = nil
            end

            -- No duration info (permanent-style effect) - just show the icon.
            iconFrame.text:SetText("")
            return
        end

        -- Live read found nothing. Could be genuinely gone, or this
        -- server's flaky aura API missing a read it'd have gotten right
        -- a tick later - don't trust a miss until grace runs out. Keep
        -- counting down for real using the last known expiration time
        -- instead of freezing the display, so a run of misses doesn't
        -- leave the countdown visibly lagging behind the real timer.
        if iconFrame.lastSeenTime and (GetTime() - iconFrame.lastSeenTime) < AURA_FLAKE_GRACE then
            if iconFrame.lastKnownExpiration then
                local remaining = iconFrame.lastKnownExpiration - GetTime()
                if remaining > 0 then
                    iconFrame:Show()
                    iconFrame.text:SetText(FormatTime(remaining))
                    return
                end
                -- Cached expiration has actually passed - fall through
                -- to the normal hide/fallback handling below instead of
                -- holding it visible on stale data.
            else
                return -- nothing to extrapolate from, just hold as-is
            end
        end
    end

    iconFrame.lastSeenTime = nil
    iconFrame.lastKnownExpiration = nil

    -- No live data available at all (this server may hide enemy debuff
    -- durations from addons the same way it seals some cooldowns) - use
    -- our own cast-triggered stopwatch if one's running.
    local remaining = CheckCastFallback(iconFrame)
    if remaining then
        ShowFromCastFallback(iconFrame, remaining)
        return
    end

    HideIcon(iconFrame)
end

-- ---------------------------------------------------------------------
-- Shared update + fixed-slot layout
-- ---------------------------------------------------------------------

local function OnTargetChanged()
    -- A new target starts with a clean slate - don't let a grace
    -- window (or the expiration it was extrapolating from) armed for
    -- the previous target linger onto this one.
    for _, iconFrame in ipairs(icons) do
        if iconFrame.kind == "targetDebuff" then
            iconFrame.lastSeenTime = nil
            iconFrame.lastKnownExpiration = nil
        end
    end
end

local function UpdateIcon(iconFrame)
    if addon.GetDB().disabledAbilities[iconFrame.spellName] then
        -- Turned off via the Options panel - always hidden, in its own
        -- reserved slot, regardless of its real state.
        HideIcon(iconFrame)
        return
    end

    if iconFrame.kind == "cooldown" then
        UpdateCooldownIcon(iconFrame)
    else
        UpdateAuraIcon(iconFrame)
    end
end

-- Left-to-right rank for an icon: its position in tracker.displayOrder,
-- or (if not listed there) after everything that is, keeping its
-- original relative order among the other unlisted ones.
local function GetDisplayRank(displayOrder, spellName)
    if displayOrder then
        for i, name in ipairs(displayOrder) do
            if name == spellName then
                return i
            end
        end
    end
    return math.huge
end

-- Every tracked ability gets its own permanent slot, left-aligned to
-- the energy bar, in rank order - whether or not it's currently active.
-- An inactive one just leaves its slot empty rather than letting the
-- others shift left to fill the gap.
local function AssignFixedPositions(iconSize, spacing, displayOrder)
    local ordered = {}
    for originalIndex, iconFrame in ipairs(icons) do
        ordered[#ordered + 1] = {
            frame = iconFrame,
            rank = GetDisplayRank(displayOrder, iconFrame.spellName),
            originalIndex = originalIndex,
        }
    end

    table.sort(ordered, function(a, b)
        if a.rank ~= b.rank then
            return a.rank < b.rank
        end
        return a.originalIndex < b.originalIndex
    end)

    local count = #ordered
    row:SetSize(math.max(count * iconSize + math.max(0, count - 1) * spacing, 1), iconSize)
    for i, entry in ipairs(ordered) do
        entry.frame:ClearAllPoints()
        entry.frame:SetPoint("LEFT", row, "LEFT", (i - 1) * (iconSize + spacing), 0)
    end
end

local function UpdateAll()
    for _, iconFrame in ipairs(icons) do
        UpdateIcon(iconFrame)
    end
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

    -- No cooldown-swipe overlay at all - just the icon with a big,
    -- outlined countdown number on top of it.
    iconFrame.text = iconFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    iconFrame.text:SetPoint("CENTER", iconFrame, "CENTER", 0, 0)
    iconFrame.text:SetFont(iconFrame.text:GetFont(), 18, "OUTLINE")

    iconFrame:EnableMouse(true)
    iconFrame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(self.spellName)
        GameTooltip:Show()
    end)
    iconFrame:SetScript("OnLeave", GameTooltip_Hide)

    -- Resolved for every kind, not just "cooldown" - targetDebuff/
    -- playerBuff icons need it too, to match UNIT_SPELLCAST_SUCCEEDED
    -- and arm their own cast-triggered fallback timer. The spellbook
    -- icon is also the only texture source for icons that end up using
    -- the cast-fallback timer, since a live aura read (which would
    -- otherwise supply the texture) never succeeds for those.
    local index = addon.GetSpellBookIndex(spellName)
    iconFrame.spellID = index and addon.GetSpellIDForIndex(index)
    local texture = addon.GetSpellIconTexture(spellName)
    iconFrame.texture:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")

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
        row:SetPoint("BOTTOMLEFT", addon.energyBar, "TOPLEFT", 0, 8)
    else
        row:SetPoint("LEFT", addon.frame, "TOPLEFT", 0, -8)
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

    AssignFixedPositions(db.iconSize, db.spacing, db.displayOrder)

    local watcher = CreateFrame("Frame")
    addon.SafeRegisterEvent(watcher, "SPELL_UPDATE_COOLDOWN")
    addon.SafeRegisterEvent(watcher, "PLAYER_ENTERING_WORLD")
    addon.SafeRegisterEvent(watcher, "PLAYER_TARGET_CHANGED")
    addon.SafeRegisterUnitEvent(watcher, "UNIT_SPELLCAST_SUCCEEDED", "player")
    addon.SafeRegisterUnitEvent(watcher, "UNIT_AURA", "target")
    addon.SafeRegisterUnitEvent(watcher, "UNIT_AURA", "player")
    addon.SafeRegisterUnitEvent(watcher, "UNIT_POWER_UPDATE", "player")
    addon.SafeRegisterUnitEvent(watcher, "UNIT_POWER_FREQUENT", "player")
    watcher:SetScript("OnEvent", function(_, event, unit, _, spellID)
        if event == "UNIT_SPELLCAST_SUCCEEDED" and unit == "player" then
            OnSpellCastSucceeded(spellID)
        elseif event == "PLAYER_TARGET_CHANGED" then
            OnTargetChanged()
        elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT" then
            TrackComboPoints()
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
