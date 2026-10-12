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
    },
},
```

- **cooldowns**: shows the moment you use it, counts down, pulses a
  glow in the last 5 seconds, disappears once ready. The global
  cooldown itself (~1.5s from using *any* ability) is filtered out so
  one ability use doesn't flash the whole row.
- **targetDebuffs**: for stuff you apply to your current target
  (bleeds, Kidney Shot's stun, Gouge). Reads the aura's *real*
  remaining duration, so it's exact — shows while it's up, disappears
  the instant it falls off or you switch target.
- **playerBuffs**: same idea, for buffs on yourself (Blade Flurry).

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

This server's aura reads (`targetDebuffs`/`playerBuffs`) are also a bit
flaky at the API level — they intermittently come back empty for a
split second even while the real effect is still up. The addon tolerates
up to 1 second of that (`AURA_FLAKE_GRACE` in `Tracker.lua`) before
actually hiding an icon, so brief hiccups don't cause flicker. If an
aura-tracked icon still never shows at all (not even flickering), run
`/frui auras target HARMFUL` (or `player HELPFUL` for a buff) while the
effect is active, or `/frui auralog on` to watch it live — that'll show
whether it's being found under a different name/filter than expected.

### Some cooldowns are an estimate, on purpose

Blizzard deliberately seals the real cooldown numbers for some
abilities from addons entirely — interrupts, and apparently several CC
effects too on this server (an anti-sniping measure for PvP). Not even
passing the sealed value through to another API is allowed, so there's
no way to read the actual cooldown for those from here at all.

For any ability in `tracker.cooldowns` that turns out sealed, the addon
instead times it itself using `tracker.fallbackDurations`: the moment
you cast it, it starts its own stopwatch using the approximate cooldown
you've set there and counts down normally (glow included). Its
countdown text gets a trailing `*` as a reminder it's an estimate —
if the real cooldown differs (talents, gear, etc.), adjust the number
to match what you see in-game. Fallback durations are preset for every
ability in the default `cooldowns` list, but they're only ever used if
that ability actually turns out to be sealed — anything that reads live
fine just ignores its fallback number and shows the exact value (no
`*`). If you ever see the chat message "`<ability>`'s cooldown is
sealed... no fallback duration is set", that ability is sealed and
needs an entry added to `fallbackDurations`.

## Layout

Top to bottom: the tracker row, energy bar, combo point pips. The
tracker row and combo points both anchor off the energy bar, so
resizing icons or the bar in `Config.lua` keeps everything aligned and
centered.
