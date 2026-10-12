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
        -- can't read it - an anti-sniping measure for PvP. For any
        -- ability above that turns out sealed, this approximate
        -- cooldown is used instead: the timer starts from when you cast
        -- it rather than reading the real value, so it won't auto-
        -- adjust if a talent changes the real cooldown, and its
        -- countdown text gets a trailing "*" as a reminder it's an
        -- estimate. Abilities that aren't sealed just ignore this and
        -- read live (exact, no "*"). These are rough baseline values -
        -- adjust any that don't match what you actually see in-game.
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
        },

        -- Debuffs you apply to your current target - tracked by the
        -- aura's real remaining duration (these aren't sealed, so
        -- they're exact), shown only while actually up and gone the
        -- instant it falls off or you switch target.
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
