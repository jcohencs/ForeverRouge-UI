ForeverRougeUI = ForeverRougeUI or {}
local addon = ForeverRougeUI

local icons = {}
local initialized

-- Treat anything this short as the global cooldown, not a real
-- ability cooldown, so using any spell doesn't flash every tracked icon.
local GCD_THRESHOLD = 1.6
-- How many seconds before an ability is ready to start glowing as a
-- "coming up" alert.
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

-- Blizzard deliberately "seals" the cooldown numbers for some abilities
-- (interrupts especially, like Kick) so addons can't do math on them -
-- an anti cooldown-sniping measure for PvP. Even just handing a sealed
-- value to another API (like the Cooldown widget's SetCooldown) is
-- blocked, not just our own math on it - there's no way to read or
-- relay the real value at all. So for these we never touch the sealed
-- value: we track the cast ourselves with our own GetTime() (that clock
-- is ours, not sealed) plus a configured approximate duration, and
-- render the countdown exactly like a normal tracked ability.
local function ArmFallbackCooldown(iconFrame, duration)
    iconFrame.fallbackStart = GetTime()
    iconFrame.fallbackDuration = duration
    iconFrame.cooldown:SetHideCountdownNumbers(true)
end

local function UpdateSecretIcon(iconFrame)
    if not iconFrame.fallbackStart then
        return -- waiting for a cast event to arm it; nothing to show
    end

    local remaining = (iconFrame.fallbackStart + iconFrame.fallbackDuration) - GetTime()
    if remaining <= 0 then
        iconFrame.fallbackStart = nil
        iconFrame.cooldown:Hide()
        iconFrame.glow:Hide()
        iconFrame.text:SetText("")
        iconFrame:Hide()
        return
    end

    iconFrame:Show()
    iconFrame.cooldown:SetCooldown(iconFrame.fallbackStart, iconFrame.fallbackDuration)
    iconFrame.cooldown:Show()
    iconFrame.text:SetText(FormatTime(remaining) .. "*")

    if remaining <= READY_SOON_THRESHOLD then
        iconFrame.glow:Show()
        local pulse = 0.5 + 0.5 * math.abs(math.sin(GetTime() * 6))
        iconFrame.glow:SetAlpha(pulse)
    else
        iconFrame.glow:Hide()
    end
end

local function UpdateIcon(iconFrame)
    local start, duration, enabled, texture = addon.GetSpellCooldownInfo(iconFrame.spellName)

    if texture and iconFrame.texture:GetTexture() ~= texture then
        iconFrame.texture:SetTexture(texture)
    end

    if iconFrame.secretMode then
        UpdateSecretIcon(iconFrame)
        return
    end

    local ok, remaining = pcall(function() return (start + duration) - GetTime() end)
    if not ok then
        -- First time we've seen this: this ability's cooldown is sealed.
        iconFrame.secretMode = true
        return
    end

    if not enabled or duration <= GCD_THRESHOLD or start == 0 or remaining <= 0 then
        -- Ready (or not usable right now) - nothing to show.
        iconFrame.cooldown:Hide()
        iconFrame.glow:Hide()
        iconFrame.text:SetText("")
        iconFrame:Hide()
        return
    end

    iconFrame:Show()
    iconFrame.cooldown:SetCooldown(start, duration)
    iconFrame.cooldown:Show()
    iconFrame.text:SetText(FormatTime(remaining))

    if remaining <= READY_SOON_THRESHOLD then
        iconFrame.glow:Show()
        local pulse = 0.5 + 0.5 * math.abs(math.sin(GetTime() * 6))
        iconFrame.glow:SetAlpha(pulse)
    else
        iconFrame.glow:Hide()
    end
end

local function UpdateAll()
    for _, iconFrame in ipairs(icons) do
        UpdateIcon(iconFrame)
    end
end

local warnedNoFallback = {}

local function OnSpellCastSucceeded(unit, spellID)
    if unit ~= "player" or not spellID then return end
    for _, iconFrame in ipairs(icons) do
        if iconFrame.secretMode and iconFrame.spellID == spellID then
            local duration = addon.GetDB().cooldowns.fallbackDurations[iconFrame.spellName]
            if duration then
                ArmFallbackCooldown(iconFrame, duration)
            elseif not warnedNoFallback[iconFrame.spellName] then
                warnedNoFallback[iconFrame.spellName] = true
                print(("ForeverRogue UI: %s's cooldown is sealed by the client and no fallback duration is set - add one under cooldowns.fallbackDurations in Config.lua to track it."):format(iconFrame.spellName))
            end
        end
    end
end

function addon.InitCooldowns()
    if initialized then
        UpdateAll()
        return
    end
    initialized = true

    local db = addon.GetDB().cooldowns

    local row = CreateFrame("Frame", "ForeverRougeUICooldownRow", addon.frame)
    addon.cooldownRow = row
    local count = #db.abilities
    local totalWidth = count * db.iconSize + math.max(0, count - 1) * db.spacing
    row:SetSize(totalWidth, db.iconSize)
    row:SetPoint("TOP", addon.frame, "TOP", 0, 0)

    for i, spellName in ipairs(db.abilities) do
        local iconFrame = CreateFrame("Frame", nil, row)
        iconFrame.spellName = spellName
        local index = addon.GetSpellBookIndex(spellName)
        iconFrame.spellID = index and addon.GetSpellIDForIndex(index)
        iconFrame:SetSize(db.iconSize, db.iconSize)
        iconFrame:SetPoint("LEFT", row, "LEFT", (i - 1) * (db.iconSize + db.spacing), 0)
        iconFrame:Hide() -- hidden by default; only shown while on cooldown

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

        local texture = addon.GetSpellIconTexture(spellName)
        iconFrame.texture:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")

        icons[i] = iconFrame
    end

    local watcher = CreateFrame("Frame")
    addon.SafeRegisterEvent(watcher, "SPELL_UPDATE_COOLDOWN")
    addon.SafeRegisterEvent(watcher, "PLAYER_ENTERING_WORLD")
    addon.SafeRegisterUnitEvent(watcher, "UNIT_SPELLCAST_SUCCEEDED", "player")
    watcher:SetScript("OnEvent", function(_, event, unit, _, spellID)
        if event == "UNIT_SPELLCAST_SUCCEEDED" then
            OnSpellCastSucceeded(unit, spellID)
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
