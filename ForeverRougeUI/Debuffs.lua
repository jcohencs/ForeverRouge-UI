ForeverRougeUI = ForeverRougeUI or {}
local addon = ForeverRougeUI

-- Tracks your own bleeds/DoTs (Rupture, Garrote, poisons...) on your
-- current target. Unlike the cooldown row, this isn't a spell cooldown:
-- it reads the debuff's remaining duration straight off the target and
-- disappears the moment the debuff is gone.

local icons = {}
local row, initialized

local function FindAura(name)
    name = name:lower()
    for i = 1, 40 do
        local auraName, icon, _, _, duration, expirationTime, source = UnitAura("target", i, "HARMFUL")
        if not auraName then break end
        if auraName:lower() == name and (source == "player" or source == nil) then
            return icon, duration, expirationTime
        end
    end
    return nil
end

local function UpdateIcon(iconFrame)
    if not UnitExists("target") then
        iconFrame:Hide()
        return
    end

    local icon, duration, expirationTime = FindAura(iconFrame.auraName)
    if not icon then
        iconFrame:Hide()
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
            if remaining >= 10 then
                iconFrame.text:SetText(("%d"):format(math.ceil(remaining)))
            else
                iconFrame.text:SetText(("%.1f"):format(remaining))
            end
            return
        end
    end

    -- No duration info (permanent-style debuff) - just show the icon.
    iconFrame.cooldown:Hide()
    iconFrame.text:SetText("")
end

local function UpdateAll()
    for _, iconFrame in ipairs(icons) do
        UpdateIcon(iconFrame)
    end
end

function addon.InitDebuffs()
    if initialized then
        UpdateAll()
        return
    end
    initialized = true

    local db = addon.GetDB().debuffs
    if not db or not db.tracked or #db.tracked == 0 then
        return
    end

    row = CreateFrame("Frame", "ForeverRougeUIDebuffRow", addon.frame)
    local count = #db.tracked
    local totalWidth = count * db.iconSize + math.max(0, count - 1) * db.spacing
    row:SetSize(totalWidth, db.iconSize)
    if addon.comboRow then
        row:SetPoint("TOP", addon.comboRow, "BOTTOM", 0, -8)
    else
        row:SetPoint("TOP", addon.frame, "TOP", 0, -70)
    end

    for i, auraName in ipairs(db.tracked) do
        local iconFrame = CreateFrame("Frame", nil, row)
        iconFrame.auraName = auraName
        iconFrame:SetSize(db.iconSize, db.iconSize)
        iconFrame:SetPoint("LEFT", row, "LEFT", (i - 1) * (db.iconSize + db.spacing), 0)
        iconFrame:Hide()

        iconFrame.texture = iconFrame:CreateTexture(nil, "ARTWORK")
        iconFrame.texture:SetAllPoints(iconFrame)
        iconFrame.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        iconFrame.cooldown = CreateFrame("Cooldown", nil, iconFrame, "CooldownFrameTemplate")
        iconFrame.cooldown:SetAllPoints(iconFrame)
        iconFrame.cooldown:SetReverse(true)
        iconFrame.cooldown:SetHideCountdownNumbers(true)

        iconFrame.text = iconFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        iconFrame.text:SetPoint("CENTER", iconFrame, "CENTER", 0, 0)

        iconFrame:EnableMouse(true)
        iconFrame:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(self.auraName)
            GameTooltip:Show()
        end)
        iconFrame:SetScript("OnLeave", GameTooltip_Hide)

        icons[i] = iconFrame
    end

    local watcher = CreateFrame("Frame")
    addon.SafeRegisterUnitEvent(watcher, "UNIT_AURA", "target")
    addon.SafeRegisterEvent(watcher, "PLAYER_TARGET_CHANGED")
    watcher:SetScript("OnEvent", UpdateAll)

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
