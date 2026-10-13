# ForeverRogue UI

A lightweight Rogue HUD addon for World of Warcraft Forever: an energy
bar and a single tracker row — left-aligned to the energy bar, Slice
and Dice always first — for cooldowns, your bleeds/CC on your target,
and your own buffs, plus an optional combo point bar.

**The whole HUD is off by default.** Out of the box, this addon shows
nothing - you just get Blizzard's own Personal Resource Display for
combo points, same as if the addon weren't installed. Check **"Show
addon HUD"** in the Options panel (see below) to turn on the energy
bar, tracker row, and the addon's own combo bar together; unchecking
it goes back to Blizzard's display only, with the addon HUD hidden
entirely.

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

Open the game menu (Esc) → Options → AddOns (or Interface → AddOns on
older clients) → **ForeverRogue UI** and check **"Show addon HUD
(instead of Blizzard's resource display)"** — the HUD then appears for
Rogue characters, centered a bit below the middle of the screen. The
same panel also has a scale slider, a lock checkbox, a reset button,
and — per tracked ability — a checkbox to turn it off entirely plus
`^`/`v` buttons to move it earlier/later in the row. Reordering there
takes effect immediately and is remembered across sessions.

Once it's showing, drag it into place:

- `/frui unlock` — unlock the frame so you can drag it
- `/frui lock` — lock it back in place
- `/frui reset` — reset position to default
- `/frui scale 1.2` — resize the whole HUD

## The tracker row

One row, left-aligned to the energy bar, showing only the
currently-active abilities **packed together with no gaps** — an
inactive one just doesn't take up space, rather than leaving an empty
slot. They're packed in priority order set by `tracker.displayOrder`
(Slice and Dice always leads, Expose Armor is always second when it's
up, then Rupture, then Blade Flurry, then everything else) unless
you've customized the order in the Options panel, which then takes
over. If the active abilities would run wider than the energy bar, it
wraps onto a second row, stacked directly above the first, rather than
drifting off past the bar's right edge. Never more than 2 rows — past
that, each row just widens to fit everything in, instead of adding a
third.

It tracks three kinds of things, configured in `Config.lua` under
`tracker`:

```lua
tracker = {
    cooldowns = {       -- true ability reuse cooldowns
        "Kick", "Blind",
        "Cloak of Shadows", "Adrenaline Rush", "Shadowstep", "Preparation",
    },
    targetDebuffs = {   -- things you put on your target
        "Rupture", "Expose Armor", "Garrote", "Kidney Shot", "Gouge",
    },
    playerBuffs = {     -- buffs on yourself
        "Blade Flurry",
        "Slice and Dice",
        "Evasion",
        "Sprint",
    },
},
```

- **cooldowns**: shows the moment you use it, counts down, disappears
  once ready. The global cooldown itself (~1.5s from using *any*
  ability) is filtered out so one ability use doesn't flash the whole
  row.
- **targetDebuffs**: for stuff you apply to your current target
  (bleeds, Kidney Shot's stun, Gouge). Tries to read the aura's *real*
  remaining duration first — but this server appears to hide enemy
  debuff durations from addons entirely for some effects (Rupture/
  Gouge/Kidney Shot never read live here), so if that comes back empty
  it falls back to a self-timed estimate from `fallbackDurations`
  instead, same idea as the sealed-cooldown fallback below.
- **playerBuffs**: same idea, for buffs on yourself. Evasion and Sprint
  live here rather than in `cooldowns`, so you see their active buff
  duration instead of their (much longer) full reuse cooldown.

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
down normally — if the real duration differs (talents, gear, combo
points, etc.), adjust the number to match what you see in-game.
Fallback durations are preset for every ability in the default lists,
but they're only ever used as a backup — anything that reads live fine
just ignores its fallback number and shows the exact value. If you ever
see the chat message "`<ability>`'s cooldown is sealed... no fallback
duration is set" for a *new* ability you've added, give it an entry in
`fallbackDurations` too.

If an ability still doesn't show up at all even with a fallback
configured, run `/frui debug <name>` to check its spellbook lookup, or
`/frui auras target HARMFUL` (or `player HELPFUL` for a buff) / `/frui
auralog on` to watch the live aura data and confirm it's not just named
differently than expected.

## Layout

The tracker row anchors directly above Blizzard's own Personal
Resource Display (centered over it) when that frame exists on this
client, falling back to anchoring above the energy bar otherwise. This
only positions our own row relative to theirs as a reference point —
it never touches the Personal Resource Display's own position, so it
doesn't fight Edit Mode the way actually moving their frame would. The
energy bar sits in its own fixed spot on the addon's frame regardless.

## Combo points

With the addon HUD unchecked (the default), combo points show via
Blizzard's own **Personal Resource Display** above your character, not
drawn by this addon at all. That display is controlled by a client
setting (Options → Combat → "Personal Resource Display", CVar
`nameplateShowSelf`) which the addon leaves alone in this state. If you
want it positioned differently (e.g. nearer where the HUD would be),
use **Edit Mode** (Esc → Edit Mode) to drag it — that's the supported
way to move it, since Edit Mode re-applies its own saved position on
every login and would fight any attempt by this addon to reposition it
in code.

Checking **"Show addon HUD (instead of Blizzard's resource display)"**
in the Options panel switches to the addon's own combo point bar
(centered above the energy bar) and turns Blizzard's Personal Resource
Display off at the same time, so only one is ever shown. Turning
Blizzard's off is a two-part fix: the CVar alone didn't actually hide
its health/power bar, so the addon also directly `:Hide()`s that frame
and keeps re-hiding it if something tries to show it again (it gets
re-shown on things like entering combat regardless of the CVar).
Custom circular art, tinting the game's own combo point atlas
(`UI-RogueCP-Slash-Blue`, confirmed via `/framestack` as exactly what
this client's Personal Resource Display itself uses) was tried first,
but neither `:SetMask` nor `:SetAtlas` actually render anything on
this client (both accept the call without erroring, but nothing
shows) - so the addon's bar uses plain colored boxes instead. It's a
different style, not a reproduction of Blizzard's exact art.
