# ForeverRogue UI

A lightweight Rogue HUD addon for World of Warcraft Forever: energy bar,
combo point pips, an on-cooldown ability tracker, and a bleed/DoT tracker
for your target.

## Install

Copy the `ForeverRougeUI` folder into your `Interface/AddOns` directory so
the path looks like:

```
Interface/AddOns/ForeverRougeUI/ForeverRougeUI.toc
```

Then enable "ForeverRogue UI" on the AddOns screen at the character select
or login screen.

## If it doesn't load

This server runs a custom core (not a standard Blizzard version), so if a
future server update marks the addon "incompatible" again: type
`/run print(GetBuildInfo())` in-game, take the fourth number it prints
(tocversion), and put that in the `## Interface:` line in
`ForeverRougeUI.toc`. As of this writing that's `16001` (client reports
version 1.60.1).

## Usage

The HUD appears automatically for Rogue characters, centered a bit below
the middle of the screen. Drag it into place:

- `/frui unlock` — unlock the frame so you can drag it
- `/frui lock` — lock it back in place
- `/frui reset` — reset position to default
- `/frui scale 1.2` — resize the whole HUD

## How the cooldown row behaves

Each ability icon is **hidden until you use it**. The moment it goes on
cooldown it appears with a countdown; in the last 5 seconds before it's
ready again it gets a pulsing glow as a "coming up" alert; then it
disappears once it's ready. The global cooldown itself (the ~1.5s flash
you get from using any ability) is filtered out so using an ability
doesn't flash every icon in the row.

If an ability still doesn't show up at all, run `/frui debug <name>`
in-game, e.g. `/frui debug Blade Flurry` — it prints what the lookup
found (or didn't) so the cause can be pinned down. The most common
reasons: it's not currently in your spellbook (wrong spec, or on this
server's rune-engraving system the rune isn't engraved yet), or the name
in `Config.lua` doesn't exactly match the one in your spellbook.

### Interrupts (Kick) look slightly different, on purpose

Blizzard deliberately hides the raw cooldown numbers for interrupt-type
abilities from addons (an anti-sniping measure for PvP), so Kick can't be
tracked the same custom way as Sprint/Vanish/etc. For those abilities the
icon still shows up the moment you use it and disappears once it's ready
again, but the countdown number is Blizzard's own built-in one instead of
this addon's styled text, and there's no 5-second "coming up" glow. That's
a platform restriction, not a bug.

## Configuring tracked abilities

Edit the `abilities` list in `Config.lua` — it's just spell names, so you
can add, remove, or reorder cooldowns without touching any other file:

```lua
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
```

Remove any ability your server/spec doesn't have, or add others (e.g.
"Blade Flurry", "Riposte", "Ambush") the same way — the exact spelling
has to match your spellbook entry.

## Bleed/DoT tracker (Rupture, Garrote, ...)

This is separate from the cooldown row, because a bleed is a debuff on
your *target*, not a cooldown on your character. It tracks the real
remaining duration of the debuff and disappears the instant it falls off
or you switch target. Configure it under `debuffs.tracked` in
`Config.lua`:

```lua
debuffs = {
    tracked = {
        "Rupture",
        "Garrote",
    },
},
```

Add any other bleed/poison you want watched the same way (e.g. "Deadly
Poison", "Crippling Poison").

## Layout

Top to bottom: cooldown icons, energy bar, combo point pips, bleed/DoT
tracker. Each row anchors to the one above it, so resizing icons or the
bar in `Config.lua` keeps everything aligned.
