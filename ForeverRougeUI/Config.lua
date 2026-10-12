ForeverRougeUI = ForeverRougeUI or {}
local addon = ForeverRougeUI

-- Everything here is meant to be edited to match your server/spec.
addon.defaults = {
    point = "CENTER",
    x = 0,
    y = -220,
    scale = 1.0,
    locked = false,

    energy = {
        width = 210,
        height = 20,
        showText = true,
    },

    comboPoints = {
        pointSize = 18,
        spacing = 4,
        maxPoints = 5, -- bumped automatically if the server reports more
    },

    -- One row, auto-centered directly above the energy bar, that shows
    -- an icon+countdown only while each thing below is actually active.
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
        -- (9s at 1 CP up to 21s at 5 CP) - adjust if either ever changes.
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

        -- Left-to-right order for whichever icons are currently active
        -- (not creation order). Anything not listed here falls after
        -- these, in whatever order it'd otherwise appear.
        displayOrder = {
            "Slice and Dice",
            "Rupture",
            "Blade Flurry",
        },
    },
}

-- Only these are genuine user-adjusted state that should survive
-- between sessions (set via the Options panel, /frui, or dragging).
local PERSISTED_KEYS = { "point", "x", "y", "scale", "locked" }

function addon.GetDB()
    ForeverRougeUIDB = ForeverRougeUIDB or {}
    local db = ForeverRougeUIDB

    for _, key in ipairs(PERSISTED_KEYS) do
        if db[key] == nil then
            db[key] = addon.defaults[key]
        end
    end

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
