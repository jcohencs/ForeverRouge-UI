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
            "Evasion",
            "Sprint",
            "Vanish",
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
        -- this approximate duration is used instead: the timer starts
        -- from when you cast it rather than reading the real value, so
        -- it won't auto-adjust if a talent changes the real duration,
        -- and its countdown text gets a trailing "*" as a reminder it's
        -- an estimate. Anything that reads live fine just ignores this
        -- and shows the exact value (no "*"). These are rough baseline
        -- values - adjust any that don't match what you actually see.
        fallbackDurations = {
            Kick = 15,
            Blind = 120,
            Evasion = 120,
            Sprint = 60,
            Vanish = 120,
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
        },

        -- For abilities whose fallback duration depends on combo points
        -- spent rather than being a flat number: duration = base +
        -- perPoint * (combo points spent on the finisher). The addon
        -- tracks the combo point count right up until a finisher
        -- consumes it, so this reflects what you actually spent, not a
        -- guess. This server's Rupture is 6 + 2 per point (8s at 1 CP
        -- up to 16s at 5 CP, confirmed in-game) - adjust if that ever
        -- changes.
        comboScaledDurations = {
            Rupture = { base = 6, perPoint = 2 },
        },

        -- Debuffs you apply to your current target. Tries to read the
        -- aura's real remaining duration first (exact, no "*"); if that
        -- comes back empty on this server, falls back to the estimate
        -- above, started from when you cast it. Shown only while
        -- actually up, gone the instant it falls off or you switch
        -- target (or, for the fallback estimate, once its time's up).
        targetDebuffs = {
            "Rupture",
            "Garrote",
            "Kidney Shot",
            "Gouge",
        },

        -- Buffs on yourself - same idea, read from your own auras.
        playerBuffs = {
            "Blade Flurry",
        },
    },
}

function addon.GetDB()
    ForeverRougeUIDB = ForeverRougeUIDB or {}
    local db = ForeverRougeUIDB

    -- shallow-merge defaults into saved vars without clobbering user changes
    local function merge(dst, src)
        for k, v in pairs(src) do
            if type(v) == "table" then
                dst[k] = dst[k] or {}
                merge(dst[k], v)
            elseif dst[k] == nil then
                dst[k] = v
            end
        end
    end

    merge(db, addon.defaults)
    return db
end
