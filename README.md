# ForeverRogue UI

A lightweight Rogue HUD addon for World of Warcraft Forever: an energy
bar, a combo point bar, and a single ability tracker row — left-aligned
to the energy bar, Slice and Dice always first — for cooldowns, your
bleeds/CC on your target, and your own buffs.

The ability tracker row always shows for Rogue characters, regardless
of anything below. The energy bar and combo bar are a pair, and are
off by default - by default you just get Blizzard's own Personal
Resource Display for health/power/combo, same as without this addon.
Check **"Use addon combo bar"** in the Options panel (see below) to
turn on the addon's own energy + combo bar together (and turn
Blizzard's own display off); the ability tracker re-anchors itself
above whichever of the two is currently active either way.

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

The ability tracker row appears automatically for Rogue characters,
centered a bit below the middle of the screen (above whichever combo
display is active). Drag the frame into place:

- `/frui unlock` — unlock the frame so you can drag it
- `/frui lock` — lock it back in place
- `/frui reset` — reset position to default
- `/frui scale 1.2` — resize the whole HUD

Or use the in-game Options panel instead of slash commands: open the
game menu (Esc) → Options → AddOns (or Interface → AddOns on older
clients) → **ForeverRogue UI**, for a scale slider, a lock checkbox, a
reset button, the combo bar choice (see below), and — per tracked
ability — a checkbox to turn it off entirely plus `^`/`v` buttons to
move it earlier/later in the row. Reordering there takes effect
immediately and is remembered across sessions.

## The tracker row

One row, left-aligned to the energy bar's width (whether or not the
energy bar itself is currently showing - see Combo points below),
showing only the currently-active abilities **packed together with no
gaps** — an inactive one just doesn't take up space, rather than
leaving an empty slot. They're packed in priority order set by
`tracker.displayOrder` (Slice and Dice always leads, Expose Armor is
always second when it's up, then Rupture, then Blade Flurry, then
everything else) unless you've customized the order in the Options
panel, which then takes over. If the active abilities would run wider
than that, it wraps onto a second row, stacked directly above the
first, rather than drifting off past the edge. Never more than 2 rows
— past that, each row just widens to fit everything in, instead of
adding a third.

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
        "Eureka!", -- Gnome racial on WoW Forever
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
- **playerBuffs**: same idea, for buffs on yourself. Evasion, Sprint,
  and Eureka! live here rather than in `cooldowns`, so you see their
  active buff duration instead of their (much longer) full reuse
  cooldown. For an aura that stacks charges, like Eureka! (3 charges,
  one consumed per non-periodic damaging/healing ability or spell
  while it's up - not utility casts like Kick or Sprint, and not DoT
  ticks), the countdown text itself tints green → yellow → red as
  charges go from 3 → 2 → 1, so you can see at a glance how many uses
  are left without reading the number; it disappears on its own once
  the last charge is used or the duration runs out, whichever comes
  first.

  This server seals buff aura data while you're in combat (confirmed
  in-game: reading Eureka!'s aura mid-fight throws "Auras cannot be
  accessed when secret"), which is exactly when its charges matter -
  so the real remaining-charges count can't be read live at that
  point. The addon counts your own qualifying combat log hits itself
  instead (`SPELL_DAMAGE`/`SPELL_HEAL`, excluding periodic ticks and
  non-damaging casts), starting over at 3 each time the buff is
  (re)applied. `tracker.chargeCounts` in `Config.lua` is where that's
  configured per ability, in case a future charge-based ability needs
  the same treatment.

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

The tracker row anchors directly above whichever resource display is
currently active (centered over it): Blizzard's own Personal Resource
Display by default, or the addon's own energy bar if the addon combo
bar is enabled in the Options panel - it automatically switches to the
other one the moment you toggle that setting. This only positions our
own row relative to the other frame as a reference point — it never
touches that frame's own position, so it doesn't fight Edit Mode the
way actually moving Blizzard's frame would. The addon's own combo bar
sits directly *below* the energy bar, not above it, so it never
overlaps with the tracker row.

## Combo points

By default, shown via Blizzard's own **Personal Resource Display**
above your character, not drawn by this addon - and the addon's own
energy bar stays hidden too, since Blizzard's display already covers
health/power. That display is controlled by a client setting (Options
→ Combat → "Personal Resource Display", CVar `nameplateShowSelf`)
which this addon manages for you, so combo points show up out of the
box without having to go find that setting yourself. If you want it
positioned differently (e.g. nearer this HUD), use **Edit Mode** (Esc
→ Edit Mode) to drag it — that's the supported way to move it, since
Edit Mode re-applies its own saved position on every login and would
fight any attempt by this addon to reposition it in code.

If you'd rather have the addon draw its own resource bars instead,
check **"Use addon combo bar (instead of Blizzard's)"** in the Options
panel — this brings up both the addon's energy bar and its combo point
bar together (the combo bar centered directly below the energy bar),
and turns Blizzard's own display off at the same time (unchecking it
turns Blizzard's back on and hides the addon's energy/combo bars
again), so only one pair is ever shown. The ability tracker row keeps
showing regardless of this choice either way - it only changes which
resource/combo display is active, and the tracker re-anchors itself to
match. Turning Blizzard's off is a two-part fix: the CVar alone didn't
actually hide its health/power
bar, so the addon also directly `:Hide()`s that frame and keeps
re-hiding it if something tries to show it again (it gets re-shown on
things like entering combat regardless of the CVar).

**That checkbox is blocked while you're in combat** - switching it
touches Blizzard's protected Personal Resource Display frame, which
isn't allowed mid-fight and left things half-applied when tried
in-game. Clicking it in combat reverts the checkbox and prints a
message instead; the setting also re-applies itself once combat ends,
in case a switch was attempted right as combat started.

Custom circular
art, tinting the game's own combo point atlas (`UI-RogueCP-Slash-Blue`,
confirmed via `/framestack` as exactly what this client's Personal
Resource Display itself uses) was tried first, but neither `:SetMask`
nor `:SetAtlas` actually render anything on this client (both accept
the call without erroring, but nothing shows) - so the addon's bar
uses plain colored boxes instead. It's a different style, not a
reproduction of Blizzard's exact art.
