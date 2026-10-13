ForeverRougeUI = ForeverRougeUI or {}
local addon = ForeverRougeUI

-- A single row that tracks three kinds of things, left-aligned to the
-- energy bar, showing only the currently-active ones packed together
-- with no gaps, in priority order (Slice and Dice first, then Expose
-- Armor, then everything else per tracker.displayOrder/abilityOrder):
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
    iconFrame.text:SetTextColor(1, 1, 1)
    iconFrame.selfTrackedCharges = nil
    iconFrame:Hide()
end

-- For auras that stack/charge (e.g. Eureka!'s 3 charges) - tints the
-- countdown text green while full, yellow with one charge consumed,
-- red on the last charge, so it's obvious at a glance how many uses
-- are left without having to read the number. Auras with no charge
-- info just stay the default white.
local function ApplyChargeColor(iconFrame, charges)
    if not charges or charges <= 0 then
        iconFrame.text:SetTextColor(1, 1, 1)
    elseif charges >= 3 then
        iconFrame.text:SetTextColor(0.2, 0.9, 0.2)
    elseif charges == 2 then
        iconFrame.text:SetTextColor(1, 0.85, 0.1)
    else
        iconFrame.text:SetTextColor(1, 0.2, 0.2)
    end
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

local function GetMaxCharges(spellName)
    local db = addon.GetDB().tracker
    return db.chargeCounts and db.chargeCounts[spellName]
end

-- Consumes a charge from every charge-tracked icon that's currently
-- active, except the one that was just cast (casting Eureka! itself
-- shouldn't consume its own charge). Once charges hit 0, the icon
-- disappears immediately rather than waiting out the rest of the
-- duration.
local function ConsumeCharge(excludeIconFrame)
    for _, iconFrame in ipairs(icons) do
        if iconFrame ~= excludeIconFrame and iconFrame.selfTrackedCharges and iconFrame.selfTrackedCharges > 0 then
            iconFrame.selfTrackedCharges = iconFrame.selfTrackedCharges - 1
            if iconFrame.selfTrackedCharges <= 0 then
                -- Also clear the cast-fallback timer, or the next tick's
                -- UpdateAuraIcon would just re-show it from that.
                iconFrame.castFallbackStart = nil
                HideIcon(iconFrame)
            end
        end
    end
end

local function OnSpellCastSucceeded(spellID)
    local matchedIconFrame = nil

    for _, iconFrame in ipairs(icons) do
        if iconFrame.spellID == spellID then
            matchedIconFrame = iconFrame
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

                -- (Re)arm the self-tracked charge count too, for
                -- abilities like Eureka! - see ConsumeCharge above for
                -- why this is tracked ourselves instead of read live.
                local maxCharges = GetMaxCharges(iconFrame.spellName)
                if maxCharges then
                    iconFrame.selfTrackedCharges = maxCharges
                end
            end
        end
    end

    -- Consume a charge on any cast that ISN'T one of this addon's own
    -- tracked abilities - every ability in tracker.cooldowns/
    -- targetDebuffs/playerBuffs is utility/CC/a buff, not direct
    -- damage, so anything else successfully cast is a real attack and
    -- should eat a charge. This is a local approximation (it's not
    -- reading damage events at all, just "was this one of our own
    -- tracked spells") rather than consulting the combat log - this
    -- server seals buff aura data during combat anyway (confirmed:
    -- reading Eureka!'s aura mid-fight throws "Auras cannot be
    -- accessed when secret"), so there's no way to read the real
    -- remaining charges live right when it matters, and the combat-log
    -- approach tried first turned out not worth the extra moving
    -- parts. Not perfectly accurate (a non-damaging cast that isn't
    -- tracked, or a periodic tick re-triggering nothing here anyway,
    -- would still miss/eat a charge differently than the real
    -- ability), but close enough without the complexity.
    if not matchedIconFrame then
        ConsumeCharge(nil)
    end
end

-- UNIT_SPELLCAST_SUCCEEDED fires the instant a cast goes off, whether
-- or not it actually connects with the target - so the cast-fallback
-- timer armed above can start counting down a debuff/buff that never
-- actually landed (confirmed in-game: Rupture missed a player target
-- and the tracker still showed a countdown for it). COMBAT_LOG_EVENT_
-- UNFILTERED was tried to detect the miss and confirmed to be blocked
-- entirely by this server ("this action is only available to the
-- Blizzard UI", even just for registering/reading it - matches the
-- same lockdown pattern as the sealed cooldowns/auras elsewhere on
-- this server). Falling back to the old pre-combat-log mechanism
-- instead: the plain chat combat-text events (CHAT_MSG_SPELL_SELF_
-- MISSES / CHAT_MSG_COMBAT_SELF_MISSES), which just carry a plain
-- English sentence ("Your Rupture misses Playername.") - no combat log
-- involved, so nothing for this server to block. Matching by spell
-- name in the message text is less precise than a real spellId (and
-- locale-dependent - this only works on an English client), but it's
-- the only lever left.
local function OnSelfMissMessage(message)
    for _, iconFrame in ipairs(icons) do
        if iconFrame.kind ~= "cooldown" and iconFrame.castFallbackStart
            and message:find(iconFrame.spellName, 1, true) then
            iconFrame.castFallbackStart = nil
            HideIcon(iconFrame)
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
        local auraName, icon, duration, expirationTime, source, charges = addon.GetUnitAuraByIndex(unit, i, filter)
        if not auraName then
            -- The read API is flaky - retry once immediately before
            -- concluding the list actually ends here, so one bad read
            -- doesn't wipe out every aura after it in this same scan.
            auraName, icon, duration, expirationTime, source, charges = addon.GetUnitAuraByIndex(unit, i, filter)
            if not auraName then break end
        end
        if auraName:lower() == name and (filter == "HELPFUL" or source == "player" or source == nil) then
            return icon, duration, expirationTime, charges
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
    -- This is the path that actually runs for Eureka! during combat,
    -- since the live aura read is sealed right when charges matter -
    -- use the self-tracked count here rather than just resetting to
    -- white, which would leave it looking uncolored the whole fight.
    ApplyChargeColor(iconFrame, iconFrame.selfTrackedCharges)
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
        local icon, duration, expirationTime, charges = FindAura(unit, iconFrame.spellName, filter)
        if icon then
            iconFrame.lastSeenTime = GetTime()
            iconFrame.lastKnownCharges = charges
            iconFrame:Show()
            if iconFrame.texture:GetTexture() ~= icon then
                iconFrame.texture:SetTexture(icon)
            end
            -- Prefer the self-tracked count over whatever the live
            -- read reports, when there is one - this server seals the
            -- real charge data during combat, so a self-tracked icon's
            -- live "charges" value can't be trusted as current.
            ApplyChargeColor(iconFrame, iconFrame.selfTrackedCharges or charges)

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
                    ApplyChargeColor(iconFrame, iconFrame.selfTrackedCharges or iconFrame.lastKnownCharges)
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
    iconFrame.lastKnownCharges = nil

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

-- Left-to-right rank for an icon. The user's own drag-free reordering
-- (set via the Options panel's move up/down buttons, persisted in
-- abilityOrder) always wins when it covers this ability; otherwise
-- falls back to tracker.displayOrder, then to everything else in
-- whatever order it'd otherwise appear.
local function GetRank(displayOrder, abilityOrder, spellName)
    if abilityOrder then
        for i, name in ipairs(abilityOrder) do
            if name == spellName then
                return i
            end
        end
    end
    if displayOrder then
        for i, name in ipairs(displayOrder) do
            if name == spellName then
                return i + 0.5 -- sorts after any abilityOrder entries, which take priority
            end
        end
    end
    return math.huge
end

-- Never more than this many rows - if fitting everything within the
-- energy bar's width would need more, widen each row instead of
-- adding a third one.
local MAX_ROWS = 2

-- Packs only the currently-active icons together, left to right, with
-- no gaps - in rank order (Slice and Dice first, then Expose Armor,
-- then everything else). Wraps onto a second row, stacked directly
-- above the first, once a single row would run wider than the energy
-- bar itself.
local function PackVisibleIcons(iconSize, spacing, displayOrder, abilityOrder, maxRowWidth)
    local ordered = {}
    for originalIndex, iconFrame in ipairs(icons) do
        if iconFrame:IsShown() then
            ordered[#ordered + 1] = {
                frame = iconFrame,
                rank = GetRank(displayOrder, abilityOrder, iconFrame.spellName),
                originalIndex = originalIndex,
            }
        end
    end

    table.sort(ordered, function(a, b)
        if a.rank ~= b.rank then
            return a.rank < b.rank
        end
        return a.originalIndex < b.originalIndex
    end)

    local totalCount = #ordered
    local step = iconSize + spacing
    local perRow = math.max(1, math.floor((maxRowWidth + spacing) / step))
    if math.ceil(totalCount / perRow) > MAX_ROWS then
        perRow = math.ceil(totalCount / MAX_ROWS)
    end
    local numRows = math.max(1, math.min(MAX_ROWS, math.ceil(totalCount / perRow)))
    local colsInWidestRow = math.min(totalCount, perRow)

    row:SetSize(
        math.max(colsInWidestRow * step - spacing, 1),
        numRows * step - spacing
    )

    for i, entry in ipairs(ordered) do
        local col = (i - 1) % perRow
        local rowIndex = math.floor((i - 1) / perRow)
        entry.frame:ClearAllPoints()
        -- rowIndex 0 sits at the container's bottom (nearest the energy
        -- bar); the second row stacks directly above it.
        entry.frame:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", col * step, rowIndex * step)
    end
end

local function UpdateAll()
    for _, iconFrame in ipairs(icons) do
        UpdateIcon(iconFrame)
    end
    addon.RefreshTrackerLayout()
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

-- Re-pack the currently-visible icons with current config - called
-- every tick from UpdateAll (since which icons are visible changes
-- constantly), and also directly from the Options panel whenever the
-- user reorders an ability, so that shows up immediately too.
function addon.RefreshTrackerLayout()
    if not row then return end
    local db = addon.GetDB().tracker
    local fullDB = addon.GetDB()
    local energyWidth = (fullDB.energy and fullDB.energy.width) or (db.iconSize * 6)
    PackVisibleIcons(db.iconSize, db.spacing, db.displayOrder, fullDB.abilityOrder, energyWidth)
end

-- Anchors the tracker row above whichever resource display is
-- currently the active one - the addon's own energy bar if that's
-- enabled (the addon's combo bar sits *below* the energy bar, not
-- above it, so the energy bar is the right reference either way),
-- otherwise Blizzard's Personal Resource Display - so the icons always
-- end up next to whichever one is actually on screen, rather than
-- fixed to one of them regardless of the Options panel choice. This
-- only positions our own row relative to the other as a reference
-- point, never touches its position, so it doesn't fight Edit Mode the
-- way actually moving Blizzard's frame would. Falls back to the addon
-- frame if neither reference exists yet.
function addon.ReanchorTrackerRow()
    if not row then return end
    row:ClearAllPoints()

    local useAddonBar = addon.GetDB().showComboPoints
    local anchorFrame = useAddonBar and addon.energyBar or PersonalResourceDisplayFrame

    local ok = anchorFrame and pcall(function()
        row:SetPoint("BOTTOM", anchorFrame, "TOP", 0, 8)
    end)
    if not ok then
        if addon.energyBar then
            row:SetPoint("BOTTOMLEFT", addon.energyBar, "TOPLEFT", 0, 8)
        else
            row:SetPoint("LEFT", addon.frame, "TOPLEFT", 0, -8)
        end
    end
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

    addon.ReanchorTrackerRow()

    for _, name in ipairs(db.cooldowns) do
        CreateIcon(db, "cooldown", name)
    end
    for _, name in ipairs(db.targetDebuffs) do
        CreateIcon(db, "targetDebuff", name)
    end
    for _, name in ipairs(db.playerBuffs) do
        CreateIcon(db, "playerBuff", name)
    end

    addon.RefreshTrackerLayout()

    local watcher = CreateFrame("Frame")
    addon.SafeRegisterEvent(watcher, "SPELL_UPDATE_COOLDOWN")
    addon.SafeRegisterEvent(watcher, "PLAYER_ENTERING_WORLD")
    addon.SafeRegisterEvent(watcher, "PLAYER_TARGET_CHANGED")
    addon.SafeRegisterEvent(watcher, "CHAT_MSG_SPELL_SELF_MISSES")
    addon.SafeRegisterEvent(watcher, "CHAT_MSG_COMBAT_SELF_MISSES")
    addon.SafeRegisterUnitEvent(watcher, "UNIT_SPELLCAST_SUCCEEDED", "player")
    addon.SafeRegisterUnitEvent(watcher, "UNIT_AURA", "target")
    addon.SafeRegisterUnitEvent(watcher, "UNIT_AURA", "player")
    addon.SafeRegisterUnitEvent(watcher, "UNIT_POWER_UPDATE", "player")
    addon.SafeRegisterUnitEvent(watcher, "UNIT_POWER_FREQUENT", "player")
    -- arg1/arg2/arg3 mean different things per event: for
    -- UNIT_SPELLCAST_SUCCEEDED they're (unit, castGUID, spellID); for
    -- the CHAT_MSG_*_MISSES events arg1 is the plain-text message.
    watcher:SetScript("OnEvent", function(_, event, arg1, arg2, arg3)
        if event == "UNIT_SPELLCAST_SUCCEEDED" and arg1 == "player" then
            OnSpellCastSucceeded(arg3)
        elseif event == "PLAYER_TARGET_CHANGED" then
            OnTargetChanged()
        elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT" then
            TrackComboPoints()
        elseif event == "CHAT_MSG_SPELL_SELF_MISSES" or event == "CHAT_MSG_COMBAT_SELF_MISSES" then
            OnSelfMissMessage(arg1)
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
