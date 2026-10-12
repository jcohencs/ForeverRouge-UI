# ForeverRogue UI

A lightweight Rogue HUD addon for World of Warcraft Forever: energy bar,
combo point pips, and a single auto-centering tracker row above the
energy bar for cooldowns, your bleeds/CC on your target, and your own
buffs.

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

Or use the in-game Options panel instead of slash commands: open the
game menu (Esc) → Options → AddOns (or Interface → AddOns on older
clients) → **ForeverRogue UI**, for a scale slider, a lock checkbox, and
a reset button.

## The tracker row

One row, anchored directly above the energy bar, always auto-centered
over it. Every icon in it is **hidden until it's actually active** and
only the currently-active ones are shown, packed together and
re-centered as things appear/disappear — so using one ability doesn't
leave a gap where an inactive one "would" be.

It tracks three kinds of things, configured in `Config.lua` under
`tracker`:

```lua
tracker = {
    cooldowns = {       -- true ability reuse cooldowns
        "Kick", "Blind", "Evasion", "Sprint", "Vanish",
        "Cloak of Shadows", "Adrenaline Rush", "Shadowstep", "Preparation",
    },
    targetDebuffs = {   -- things you put on your target
        "Rupture", "Garrote", "Kidney Shot", "Gouge",
    },
    playerBuffs = {     -- buffs on yourself
        "Blade Flurry",
        "Slice and Dice",
    },
},
```

- **cooldowns**: shows the moment you use it, counts down, pulses a
  glow in the last 5 seconds, disappears once ready. The global
  cooldown itself (~1.5s from using *any* ability) is filtered out so
  one ability use doesn't flash the whole row.
- **targetDebuffs**: for stuff you apply to your current target
  (bleeds, Kidney Shot's stun, Gouge). Tries to read the aura's *real*
  remaining duration first (exact, no `*`) — but this server appears to
  hide enemy debuff durations from addons entirely for some effects
  (Rupture/Gouge/Kidney Shot never read live here), so if that comes
  back empty it falls back to a self-timed estimate from
  `fallbackDurations` instead, same idea as the sealed-cooldown
  fallback below.
- **playerBuffs**: same idea, for buffs on yourself (Blade Flurry) —
  these have read live fine so far.

Move an ability between these three lists if it's being tracked the
wrong way — e.g. if something is really an effect you apply rather than
a cooldown you wait out, it belongs in `targetDebuffs`/`playerBuffs`,
not `cooldowns`. The exact spelling has to match the name in your
spellbook/aura.

If an ability still doesn't show up at all, run `/frui debug <name>`
in-game, e.g. `/frui debug Blade Flurry` — it prints what the cooldown
lookup found (or didn't). The most common reasons: it's not currently
in your spellbook (wrong spec, or on this server's rune-engraving
system the rune isn't engraved yet), or the name in `Config.lua`
doesn't exactly match the one in your spellbook/aura.

This server's aura reads are also a bit flaky at the API level for
effects that *do* read live — they can intermittently come back empty
for a split second even while the real effect is still up. The addon
tolerates up to 1 second of that (`AURA_FLAKE_GRACE` in `Tracker.lua`)
before actually hiding an icon, so brief hiccups don't cause flicker.

### Some cooldowns/durations are an estimate, on purpose

Blizzard deliberately seals the real cooldown numbers for some
abilities from addons entirely — interrupts, and apparently several CC
effects too on this server (an anti-sniping measure for PvP). This
server extends the same idea to some enemy debuff durations (Rupture,
Gouge, Kidney Shot never read live here). Not even passing a sealed
value through to another API is allowed, so there's no way to read the
actual number for those from here at all.

For anything in `tracker.cooldowns`/`targetDebuffs`/`playerBuffs` that
turns out unreadable, the addon instead times it itself using
`tracker.fallbackDurations`: the moment you cast it, it starts its own
stopwatch using the approximate duration you've set there and counts
down normally (glow included). Its countdown text gets a trailing `*`
as a reminder it's an estimate — if the real duration differs (talents,
gear, combo points, etc.), adjust the number to match what you see
in-game. Fallback durations are preset for every ability in the default
lists, but they're only ever used as a backup — anything that reads
live fine just ignores its fallback number and shows the exact value
(no `*`). If you ever see the chat message "`<ability>`'s cooldown is
sealed... no fallback duration is set" for a *new* ability you've added,
give it an entry in `fallbackDurations` too.

If an ability still doesn't show up at all even with a fallback
configured, run `/frui debug <name>` to check its spellbook lookup, or
`/frui auras target HARMFUL` (or `player HELPFUL` for a buff) / `/frui
auralog on` to watch the live aura data and confirm it's not just named
differently than expected.

## Layout

Top to bottom: the tracker row, energy bar, combo point pips. The
tracker row and combo points both anchor off the energy bar, so
resizing icons or the bar in `Config.lua` keeps everything aligned and
centered.
