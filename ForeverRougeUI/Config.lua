ForeverRougeUI = ForeverRougeUI or {}
local addon = ForeverRougeUI

-- Everything here is meant to be edited to match your server/spec.
addon.defaults = {
    point = "CENTER",
    x = 0,
    y = -220,
    scale = 1.0,
    locked = false,

    -- Which tracked abilities are turned off via the Options panel.
    -- {} = everything enabled. This is real user preference (unlike
    -- the tracker config below) so it's persisted across sessions.
    disabledAbilities = {},

    -- Left-to-right slot order, as customized via the Options panel's
    -- move up/down buttons. nil until the user first reorders
    -- something, at which point it's seeded from tracker.displayOrder
    -- and takes over completely from then on.
    abilityOrder = nil,

    -- Off by default: Blizzard's own Personal Resource Display shows
    -- combo points above your character. Check "Use addon combo bar" in
    -- the Options panel to show the addon's own bar instead (plain
    -- colored boxes, not a reproduction of Blizzard's art - see
    -- ComboPoints.lua for why).
    showComboPoints = false,

    energy = {
        width = 210,
        height = 20,
        showText = true,
    },

    -- Off by default - Blizzard's own Personal Resource Display
    -- already shows combo points above your character, and that's what
    -- shows unless "Use addon combo bar" is checked in the Options
    -- panel. maxPoints is also used for Rupture/Slice and Dice's
    -- combo-scaled fallback durations regardless of which bar is shown.
    comboPoints = {
        maxPoints = 5, -- bumped automatically if the server reports more
        pointSize = 18,
        spacing = 4,
    },

    -- One row, left-aligned to the energy bar, packing only the
    -- currently-active abilities together with no gaps (see
    -- displayOrder below for the left-to-right priority order).
    tracker = {
        iconSize = 32,
        spacing = 6,

        -- True ability reuse cooldowns. Tracked by spell name so this
        -- works regardless of spell ID differences between retail/
        -- classic/private-server cores. Add/remove/reorder freely.
        cooldowns = {
            "Kick",
            "Blind",
            "Cloak of Shadows",
            "Adrenaline Rush",
            "Shadowstep",
            "Preparation",
            "Eureka!",
        },

        -- Blizzard seals the real cooldown for some abilities (at least
        -- interrupts and several CC effects on this server) so addons
        -- can't read it - an anti-sniping measure for PvP. This server
        -- appears to extend the same idea to enemy debuff durations:
        -- Rupture/Gouge/Kidney Shot's real remaining time on target
        -- isn't readable at all here either. For any ability above (or
        -- in targetDebuffs/playerBuffs below) that turns out unreadable,
        -- this approximate duration is used instead, started from when
        -- you cast it rather than reading the real value, so it won't
        -- auto-adjust if a talent changes the real duration. These are
        -- rough baseline values - adjust any that don't match what you
        -- actually see.
        fallbackDurations = {
            Kick = 15,
            Blind = 120,
            ["Cloak of Shadows"] = 120,
            ["Adrenaline Rush"] = 180,
            Shadowstep = 20,
            Preparation = 300,
            -- Eureka! is the Gnome racial on WoW Forever ("your next 3
            -- non-periodic abilities cost 10% less and deal 10% more
            -- damage") - confirmed 2-minute cooldown. The exclamation
            -- mark is part of the real spell name - without it the
            -- name never matches anything in the spellbook, which is
            -- why it never showed up before.
            ["Eureka!"] = 120,
            -- Rupture's real duration scales with combo points spent
            -- (see comboScaledDurations below, which takes priority) -
            -- this flat value is never actually used, just a safety net.
            Rupture = 16,
            Garrote = 18,
            ["Kidney Shot"] = 6,
            Gouge = 4,
            -- Slice and Dice's real duration scales with combo points
            -- spent (see comboScaledDurations below, which takes
            -- priority) - this flat value is never actually used, just
            -- a safety net.
            ["Slice and Dice"] = 12,
            -- Expose Armor is flat 30s regardless of combo points spent
            -- (confirmed in-game) - not combo-scaled like Rupture/SnD.
            ["Expose Armor"] = 30,
            -- These read live fine, but the live read can flake out for
            -- longer than AURA_FLAKE_GRACE tolerates - this is the
            -- backup that kicks in rather than the icon just vanishing
            -- mid-buff. Adjust to match the real buff duration you see.
            ["Blade Flurry"] = 15,
            Evasion = 15,
            Sprint = 15,
        },

        -- For abilities whose fallback duration depends on combo points
        -- spent rather than being a flat number: duration = base +
        -- perPoint * (combo points spent on the finisher). The addon
        -- tracks the combo point count right up until a finisher
        -- consumes it, so this reflects what you actually spent, not a
        -- guess. Confirmed in-game: Rupture is 6 + 2 per point (8s at
        -- 1 CP up to 16s at 5 CP), Slice and Dice is 6 + 3 per point
        -- (9s at 1 CP up to 21s at 5 CP) - adjust if either ever
        -- changes. Expose Armor is NOT combo-scaled (flat 30s, see
        -- fallbackDurations above) so it has no entry here.
        comboScaledDurations = {
            Rupture = { base = 6, perPoint = 2 },
            ["Slice and Dice"] = { base = 6, perPoint = 3 },
        },

        -- Debuffs you apply to your current target. Tries to read the
        -- aura's real remaining duration first; if that comes back
        -- empty on this server, falls back to the estimate above,
        -- started from when you cast it. Shown only while actually up,
        -- gone the instant it falls off or you switch target (or, for
        -- the fallback estimate, once its time's up).
        targetDebuffs = {
            "Rupture",
            "Expose Armor",
            "Garrote",
            "Kidney Shot",
            "Gouge",
        },

        -- Buffs on yourself - same idea, read from your own auras.
        -- Evasion/Sprint live here (not in cooldowns above) because you
        -- want to see their active buff duration, not their full reuse
        -- cooldown.
        playerBuffs = {
            "Blade Flurry",
            "Slice and Dice",
            "Evasion",
            "Sprint",
        },

        -- Left-to-right priority order among whichever abilities are
        -- currently active - Slice and Dice always leads, Expose Armor
        -- is always second when it's up, then the rest in this order.
        -- Anything not listed here falls after these, in whatever
        -- order it'd otherwise appear.
        displayOrder = {
            "Slice and Dice",
            "Expose Armor",
            "Rupture",
            "Blade Flurry",
        },
    },
}

-- Only these are genuine user-adjusted state that should survive
-- between sessions (set via the Options panel, /frui, or dragging).
local PERSISTED_KEYS = { "point", "x", "y", "scale", "locked", "showComboPoints" }

function addon.GetDB()
    ForeverRougeUIDB = ForeverRougeUIDB or {}
    local db = ForeverRougeUIDB

    for _, key in ipairs(PERSISTED_KEYS) do
        if db[key] == nil then
            db[key] = addon.defaults[key]
        end
    end

    -- Real user preference (set via the Options panel) - only
    -- initialize it if missing, never overwrite it like the config
    -- tables below. abilityOrder stays nil until the user actually
    -- reorders something (checked for explicitly wherever it's read).
    db.disabledAbilities = db.disabledAbilities or {}

    -- Everything else (ability lists, fallback durations, icon sizing,
    -- etc.) is config that lives in this file, not end-user state. Use
    -- it fresh every time instead of merging it into the saved table -
    -- a one-way "fill in missing keys" merge would otherwise let an
    -- old value saved by an earlier version of this file silently
    -- shadow an edit made here forever, since editing Config.lua can
    -- never remove or change a key that's already present in the
    -- saved copy from a previous session.
    db.energy = addon.defaults.energy
    db.comboPoints = addon.defaults.comboPoints
    db.tracker = addon.defaults.tracker

    return db
end
