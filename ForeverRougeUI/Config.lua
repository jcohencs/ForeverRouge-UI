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

    debuffs = {
        iconSize = 30,
        spacing = 6,
        -- Your own bleeds/DoTs to watch on the current target. Shows
        -- only while the debuff is actually up, with remaining time.
        tracked = {
            "Rupture",
            "Garrote",
        },
    },

    cooldowns = {
        iconSize = 36,
        spacing = 6,
        growDirection = "RIGHT", -- RIGHT, LEFT, UP, DOWN
        -- Tracked by spell name so this works regardless of spell ID
        -- differences between retail/classic/private-server cores.
        -- Add/remove/reorder freely.
        abilities = {
            "Kick",
            "Kidney Shot",
            "Blind",
            "Evasion",
            "Sprint",
            "Vanish",
            "Cloak of Shadows",
            "Adrenaline Rush",
            "Shadowstep",
            "Preparation",
        },

        -- Blizzard seals the real cooldown for interrupt-type abilities
        -- (Kick here) so addons can't read it - an anti-sniping measure
        -- for PvP. For those abilities only, give an approximate
        -- cooldown here so a timer can still be shown; it's started from
        -- when you cast it and won't auto-adjust if a talent changes the
        -- real cooldown, so its countdown text gets a trailing "*" as a
        -- reminder it's an estimate. Abilities not listed here don't
        -- need this - they're read live and are exact.
        fallbackDurations = {
            Kick = 15,
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
