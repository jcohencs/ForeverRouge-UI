ForeverRougeUI = ForeverRougeUI or {}
local addon = ForeverRougeUI

local icons = {}
local initialized

local function FormatTime(remaining)
    if remaining >= 60 then
        return ("%dm"):format(math.ceil(remaining / 60))
    elseif remaining > 3 then
        return ("%d"):format(math.ceil(remaining))
    else
        return ("%.1f"):format(remaining)
    end
end

local function UpdateIcon(iconFrame)
    local start, duration, enabled, texture = addon.GetSpellCooldownInfo(iconFrame.spellName)

    if texture and iconFrame.texture:GetTexture() ~= texture then
        iconFrame.texture:SetTexture(texture)
    end

    if not enabled or duration == 0 or start == 0 then
        iconFrame.cooldown:Hide()
        iconFrame.text:SetText("")
        iconFrame.texture:SetDesaturated(false)
        iconFrame:SetAlpha(1)
        return
    end

    local remaining = (start + duration) - GetTime()
    if remaining <= 0 then
        iconFrame.cooldown:Hide()
        iconFrame.text:SetText("")
        iconFrame.texture:SetDesaturated(false)
        iconFrame:SetAlpha(1)
        return
    end

    iconFrame.cooldown:SetCooldown(start, duration)
    iconFrame.cooldown:Show()
    iconFrame.texture:SetDesaturated(true)
    iconFrame:SetAlpha(0.6)
    iconFrame.text:SetText(FormatTime(remaining))
end

local function UpdateAll()
    for _, iconFrame in ipairs(icons) do
        UpdateIcon(iconFrame)
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
        iconFrame:SetSize(db.iconSize, db.iconSize)
        iconFrame:SetPoint("LEFT", row, "LEFT", (i - 1) * (db.iconSize + db.spacing), 0)

        iconFrame.texture = iconFrame:CreateTexture(nil, "ARTWORK")
        iconFrame.texture:SetAllPoints(iconFrame)
        iconFrame.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        iconFrame.cooldown = CreateFrame("Cooldown", nil, iconFrame, "CooldownFrameTemplate")
        iconFrame.cooldown:SetAllPoints(iconFrame)
        iconFrame.cooldown:SetDrawEdge(true)
        iconFrame.cooldown:SetHideCountdownNumbers(true)

        iconFrame.text = iconFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        iconFrame.text:SetPoint("CENTER", iconFrame, "CENTER", 0, 0)

        iconFrame:EnableMouse(true)
        iconFrame:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(self.spellName)
            GameTooltip:Show()
        end)
        iconFrame:SetScript("OnLeave", GameTooltip_Hide)

        -- Show the real icon once the spell is known client-side.
        local texture = addon.GetSpellIconTexture(spellName)
        iconFrame.texture:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")

        icons[i] = iconFrame
    end

    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
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
