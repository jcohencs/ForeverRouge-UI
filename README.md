# ForeverRogue UI

A lightweight Rogue HUD addon for World of Warcraft Forever: energy bar,
combo point pips, and a cooldown tracker for key abilities.

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
"Riposte", "Ambush") the same way.

## Layout

Top to bottom: cooldown icons, energy bar, combo point pips. Each row
anchors to the one above it, so resizing icons or the bar in `Config.lua`
keeps everything aligned.
