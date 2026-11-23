# SPEC — MyUI

Decisions only. Where the HTML reference shows alternatives, **this file is authoritative** —
the mock contains rejected explorations that must not be implemented.

Reference resolution for all coordinates below: the mock canvas is **1707 × 960**. Screen
centre is x = 853. Express everything as anchor offsets, never absolute pixels.

---
**Round 004 (2026-11-14), decided by Mykel: the modal HUD.** The HUD is a function of WoW's
mode (§ 16): bars centred under the character with ALT / CTRL / ALT+CTRL pages (§ 17), two wings
on the bars' rows (§ 18), group frames and pinnable unit cards with a click map (§ 19), a target
strip in three kinds (§ 20), a boss mode (§ 21), the map on a key (§ 22), and Blizzard's old
toasts routed or quieted (§ 6). Where § 2's positions disagree with § 16–22, § 16–22 win.
Reasoning and the visual reference: `DECISIONS-004.md`.

**Round 003 (2026-11-14), decided by Mykel.** The addon and the design are both **MyUI** — the
name "Rebar" is retired as a design name and survives only as the old layout addon, which is
folded in (§ 9). The rail is cut (§ 6). MyUI now *replaces* minimap, chat and bags rather than
only quieting them (§ 10, § 11). Reasoning: `DECISIONS-003.md`.

## 1. The premise

At rest the screen is the game. No frame is permanent. Every element is summoned by cursor,
state, low health, or the peek key, and returns to its resting alpha when that stops being
true. Position is **set once in edit mode, then fixed** — muscle memory survives because nothing moves
during play.
Hidden must never mean lost.

Geometry is flat: 1px hairlines, no corner radius, no gradients, no fill above 14% opacity
except a data bar. All life comes from alpha, plus one scale pulse and one slide on entrance.
**The addon ships no texture assets at all** — every element is a solid fill or a 1px line.
See § 6 for why the one planned texture was cut.

---

## 2. Frames, anchors, resting alpha

| Frame | Anchor | Size | Resting alpha |
|---|---|---|---|
| `SelfStack` | BOTTOM, centred, 214 up from bottom edge | 240 wide | 0.35 |
| `Cooldowns` (rhythm line) | 18 below resource bar, centred | 240 × 4 | 0.25 |
| `TargetStrip` | TOP, centred, 20 down from top edge | 400 wide | 0 |
| `ToastAnchor` | Placed by the player in edit mode (§ 9) | — | 0 (toasts show only while speaking) |

Anchors above are defaults. The layout layer (§ 9) lets the player move any MyUI frame once,
in edit mode; it does not move during play.

### Replaced frames

MyUI clears Blizzard's minimap, chat and bags (§ 11) and draws **its own minimal versions**,
registered like every other MyUI frame and revealed by the same engine:

| Frame | Resting alpha | Revealed by | Status |
|---|---|---|---|
| Minimap | 0 | proximity, peek | **Square, minimal.** All Blizzard and addon minimap buttons gathered into one menu |
| Chat | 0 | a toast you interact with; a summon key | **Ignored by default.** Opens from a toast, or summoned with channel / log filters |
| Bags | 0 | proximity, peek, bag-open key | **Deferred** — adopted until designed |
| Objective tracker | see § 13 | — | behaviour carried over from ChatQuiet |

Until a replacement is built, the Blizzard frame is *adopted* as round 002 specified —
resting alpha 0, revealed by the engine, alpha only. Adoption is the interim, not the design.

### SelfStack internals (relative to the 240-wide group)

- Health bar — 240 × 4, trough `rgba(255,255,255,0.14)`
- Resource bar — 240 × 2, 4 below health
- Cast bar — 240 × 4, 6 below resource
- **With a pet out** (round 004, Mykel): SelfStack and a pet stack side by side, each 45% of the
  width with 10% between, together in SelfStack's place. The pet stack has the same text row,
  health (danger gradient) and resource, on a secure unit button (click target, right-click pet
  menu). The 20% / 40% marks stay at 20% / 40% of the narrower bar. Resizes out of combat.
- Name — 11pt, left; level — 11pt dim, right; **one row with the health number**, bottoms 2
  above the health bar, the same on the target strip (round 004, Mykel: "align the text"). The
  group grows upward to 33; the bars do not move.
- Health number — 12pt, **centred, just above the health bar** (round 004, Mykel: "much
  cleaner"; was 40 wide, right-aligned, 8 left of the bar group). `/myui pct pill` puts it on the
  bar on a `rgba(0,0,0,0.55)` pill instead.
- Danger gradient (round 004, Mykel) — under the health fill, over the first 35% (the low-health
  threshold): danger red at the empty end fading to clear. The fill hides it; falling health
  uncovers it from the clear end, so red appears only when low. Static; the same on the target
  strip and the low-health copy.
- Threshold ticks on the health bar — static geometry, always present:
  - 20% mark at x = 48, `rgba(0,0,0,0.55)` (reads against the fill)
  - 40% mark at x = 96, `rgba(255,255,255,0.25)` (reads against the empty trough)

The ticks are the design's compliance keystone. They are fixed marks; the *bar* crossing them
is the event, and the player's eye does the comparison. Never compute their position from a
value.

### The hover edge (round 004 play)

One hover language (Mykel: "tying all the hovers into a shared design language"): a 1 px line in
the fill colour around whatever the pointer is on, padded 6 clear of text — your bar, the pet
stack, the focus, the target strip, party rows, pet buttons (2 clear of the icon). Amber is kept
for "selected" (the targeted party member) and autocast.

### Focus strip (round 004 play)

Ctrl-click set a focus that showed nowhere (Blizzard's FocusFrame is hidden with the unit
frames). A strip in the target strip's grammar — name, percentage, level over a thin health bar
with the danger gradient — 240 wide, over the target strip (focus profile: its bar 16 above the
target's text row). On a secure unit button for `focus`: click targets it, right-click its menu.
Shown by a state driver while a focus exists, at full alpha: a focus is a deliberate choice.
Three slots by state driver: above the target strip with a target; in the target's place in
combat without one; and out of combat without one, lower still, in the faded action bar's row.
An × after the bar clears it.

### TargetStrip internals

- Name — 11pt, `rgba(240,241,243,1)`, left-aligned at the bar's left
- Level — 11pt, `rgba(173,177,184,1)`, right-aligned at the bar's right
- Round 004: name, health number and level on one row, bottoms 2 above the bar (the bar does
  not move; the name row used to sit at the group top)
- Health bar — 400 × 3, 20 below the name row
- Health number — 12pt, centred just above the bar, the same way as SelfStack's (round 004); a
  boss bar (§ 21) carries its number the same way
- Cast indicator — 3 × 6 tick, 9 below the bar

---

## 3. Low health — decision: **combined (4d)**, amended

Three layers now: a colour ramp, a depleted-region wash, and a discrete moment. They do not
duplicate each other. Two of the three are built differently from the original spec because
12.1 removed the mechanism each assumed — see HANDBACK-RESPONSE.md § B.

### Continuous layer — `ColorCurveObject` on the health fill

Curve stops (linear interpolation between them):

| Health | Fill colour |
|---|---|
| 100 | `rgba(240,241,243,0.92)` |
| 58 | `rgba(242,214,150,0.92)` |
| 34 | `rgba(242,170,120,0.92)` |
| 17 | `rgba(242,120,100,0.94)` |
| 6 | `rgba(242,86,80,1)` |

The health number takes the same curve at full opacity.

### Continuous layer — the depleted wash, as a reverse-filled bar

**Superseded:** `MaskTexture` has no inversion parameter on 12.1, and inverting it would need
a texture asset, which § 6 forbids.

Instead: a second bar occupying the same rect as the health bar, filled from the **right**,
fed the same forwarded value. It covers exactly the depleted region by construction — no mask,
no asset, and it cannot drift out of alignment with the fill boundary. Colour
`rgba(242,107,97, α)`, α ramping 0 → 0.22 across the same range as the curve.

### Discrete layer — **one** state, produced by a step curve

**Superseded:** `RegisterStateDriver` resolves through the macro-conditional parser and there
is no health conditional of any spelling on 12.1, so the driver state has no event to fire on.

Instead: a **step curve** — one alpha below the cutoff, another above it — evaluated against
the forwarded health value and passed to `SetAlpha`. This produces a hard threshold with no
comparison in Lua. Two of the three tells below therefore need duplicated frames cross-faded
by the step alpha rather than mutated in place. The effect is as specified; the build is not.

One boundary, one moment. On entry:

- Health number 12pt → 14pt. This is the only type-size change anywhere in the addon, which
  is what makes it register. *Built as two stacked labels, 12pt and 14pt, cross-faded by the
  step alpha.*
- Health group breathes alpha 1.0 ↔ 0.55 at 1.60s.
- A 1px danger hairline appears at the full screen edge, inset 0, at alpha 0.35. No gradient,
  no vignette, no blur. It works because it is the only shape in the design that is not a bar,
  and it lives in peripheral vision where a bar cannot.

Deepest state (if a second cutoff is later added — **not in v1**): hairline breathes at
0.80s. v1 ships one cutoff only.

### Does low health summon the HUD? — **yes, narrowly**

The step curve above produces a secret value, and a secret may never be compared, so it can
escalate the HUD but cannot claim in the arbiter. Summoning therefore uses a fifth mechanism
(RULES § Five sanctioned mechanisms): a secure hook on Blizzard's own low-health frame, whose
show/hide is a plain boolean event and may be compared freely.

- It reveals **`SelfStack` only.** Not the cooldowns, not the target strip. The narrow version
  is deliberate: low health is a reason to see your own numbers, not a reason to redraw the
  screen.
- Claim 1.0, held for as long as the hook is shown. No dwell in, no timeout out.
- Threshold is Blizzard's, fixed at 35%, and not ours to move.
- The player can switch the underlying warning off. MyUI reads that setting at load; if it is
  off, the summon channel is silently unavailable and the escalation layers still work. One
  line in `/myui audit` reports which.

Nothing else in the addon ever changes colour.

---

## 4. Reveal engine — four channels, one arbiter

**The modifier channel is cut.** A conventional three-row action bar layout leaves no modifier
free, so a HUD keyed to one reveals itself on every modified cast — the incidental-reveal
problem the 140ms dwell exists to prevent, arriving through a different door. Proximity and
peek already cover deliberate reveal. No modifier keys, and no escape hatch: one fewer channel
is worth more than the option.

All four resolve through a single arbiter that computes one target alpha per frame per tick.
Do not let frames manage their own visibility; that is the architectural mistake this design
is most vulnerable to.

| Channel | Trigger | Notes |
|---|---|---|
| Cursor proximity | Cursor within **32 units** of the frame, held **140ms** | The dwell is what stops brushing past while looting from flashing the HUD |
| State change | Combat enter/exit, target acquired/lost | Event-driven only |
| Low health | Blizzard low-health hook shown | Reveals `SelfStack` only; see § 3 |
| Tap-to-peek | Peek key | Reveals for **3s** on a visible drain clock, then fades |

Every channel claims **1.0**, so ties are the normal case rather than an edge one. Precedence
when tied, highest first: low health, state change, peek, proximity. This decides only which
channel is *credited* in `/myui claims`; the resulting alpha is identical either way.

Arbitration: highest claim wins. When all claims release, the frame returns to its resting
alpha from § 2 — never to zero unless its resting alpha is zero.

Fades: **120ms in, 260ms out.** Out is slower so release feels like settling rather than
snapping.

---

## 5. Rhythm line — **v2, not v1**

Specified fully so nothing is lost, but see PLAN.md: this is deferred out of the first
release as the highest-risk component. Build the addon coherent without it.

- Six cells, **38 × 4, gutter 2**, total 240 × 4. Uniform height forever.
- Position equals ability identity. Order is fixed user configuration. **Never computed.**
- CDM stays alive at alpha 0 doing all tracking. Each cell is a Cooldown frame receiving
  forwarded values and inspecting none.
- `SetSwipeColor` draws the recharge body — the depleting portion is the engine's swipe, not
  a width you calculate.
- `isDisplayingEdge` / `SetEdgeTexture` give the came-up moment a 1px cap for **180ms**. This
  is the peripheral event, delivered by the widget.
- Charges: cell subdivides with a 1px gutter, one segment per charge.
- All six up: line goes solid, one **1.35×** scale pulse. This is the whole point — the line
  going solid is a single peripheral event you never have to read.

**Cut, permanently:** variable cell height or alpha encoding priority. Priority is a ranking,
a ranking is a comparison, no 12.1 mechanism makes it legal, and no future patch will fix it
because it was never data — it was a rotation opinion. Rotation opinions belong to Hekili.

---

## 6. Notifications — toasts and a history

**The rail is cut** (round 003). It felt too rigid in play, and the build's handback found it
lossy: a normal few minutes produced eight dots and "+7 more", two of fifteen readable
(HANDBACK-2 H2). What survives is the part that worked — a toast that speaks once — plus a
record you can summon.

### Toasts

- A toast speaks once and leaves after **4s** or on dismissal. Slide + fade in, 180ms.
- **Toasts appear at `ToastAnchor`, wherever the player puts it** in edit mode (D1). Not a
  fixed column. A toast never covers `SelfStack` or `TargetStrip`. Until the layout layer
  (R4) can move it, the anchor sits at the left edge, upper third (x 20, 240 down).
- **A toast can be interacted with.** A whisper or other chat toast opens chat at that
  conversation; this is the main way into chat (§ 14).
- A long name **truncates with an ellipsis; the age never yields** (rules on HANDBACK-2 H1).
- Every string carries a shadow in `rgba(0,0,0,0.55)` — the existing tick-dark, no new colour.
- Simultaneous toasts stack away from the anchor's snapped corner. Cap: tune in Phase 6.

### History

- Every notification is written to a per-character log (`Log.lua`), with a hard ceiling
  (5,000) and nothing expiring by age.
- The history is **summoned by a key**, filtered by hue, and returns to nothing when closed.
  The Aug 28 notification centre (`Center.lua`) is the starting point, reattached to toasts
  instead of the rail.

### What feeds it

Round 002's seven sources plus whispers, still five hues (D1). Four hues mean *something happened*;
orange means *something wants you*.

| Hue | Sources | Events |
|---|---|---|
| Blue `rgba(140,200,255,1)` | Loot received | `CHAT_MSG_LOOT`, `LOOT_ITEM_ROLL_WON` |
| Amber `rgba(255,209,89,1)` | Quest objective, quest complete, achievement earned | `QUEST_ACCEPTED`, `QUEST_TURNED_IN`, `UNIT_QUEST_LOG_CHANGED`, `ACHIEVEMENT_EARNED` |
| Green `rgba(166,217,140,1)` | Currency, reputation | `CURRENCY_DISPLAY_UPDATE`, `CHAT_MSG_COMBAT_FACTION_CHANGE` |
| Violet `rgba(209,179,255,1)` | **Whisper** | `CHAT_MSG_WHISPER`, `CHAT_MSG_BN_WHISPER` |
| Orange `rgba(242,158,115,1)` | Mail, bag full, low durability, group and guild invites | `UPDATE_PENDING_MAIL`, `BAG_UPDATE_DELAYED`, `UPDATE_INVENTORY_DURABILITY`, `PARTY_INVITE_REQUEST`, `GUILD_INVITE_REQUEST` |

Two rules: **one toast per event, never a stream**, and **no source may read a unit value.**
Defaults: loot at uncommon and above; durability at 20%; bag notice at zero free slots. All
three are saved variables. Whispers take violet and achievements move to amber, so the palette stays at
**thirteen** (D1). The Aug 28 work's sixth hue is dropped.

The bloom stays cut; `assets/` keeps the evidence.


## 7. Colour table — complete

**Thirteen** colours, all RGBA float. Nothing outside this list.

Tertiary text is lifted to `rgba(173,177,184,1)`, which is the existing secondary value — so
the two collapse into one entry, `Text dim`. They never appear in the same row (secondary is
the target level, tertiary was the rail age), so the hierarchy loses nothing and the palette
gets one colour shorter. The old `115,119,126` survives only as `/myui contrast normal`, a
debug affordance for checking the original intent. It is not a palette entry.

```
Fill / primary      rgba(240,241,243,0.92)
Text primary        rgba(240,241,243,1)
Text dim            rgba(173,177,184,1)
Trough              rgba(255,255,255,0.14)
Fill dim            rgba(255,255,255,0.25)
Tick dark           rgba(0,0,0,0.55)
Danger              rgba(242,107,97,1)
Resource accent     rgba(140,211,255,1)
Notif blue          rgba(140,200,255,1)
Notif amber         rgba(255,209,89,1)
Notif green         rgba(166,217,140,1)
Notif violet        rgba(209,179,255,1)
Notif orange        rgba(242,158,115,1)
```

Curve intermediates (§ 3) are interpolation stops, not palette entries.

**One recorded exception (R3, 2026-11-14):** the summoned history's backing surface,
`rgba(10,10,12,0.86)`. It exists only while summoned — § 1's limits govern the resting HUD —
and twelve rows of 11pt over daylight terrain are unreadable on a 0.14 fill. It is not a
palette entry and nothing at rest may use it.

---

## 8. Motion table

| Event | Motion |
|---|---|
| Reveal in | alpha → target, 120ms |
| Reveal out | alpha → resting, 260ms |
| Toast entrance | slide + fade, 180ms |
| Toast leave | 4s dwell, then 200ms fade |
| Peek | 3s visible drain clock |
| Low-health breathe | 1.0 ↔ 0.55, 1.60s |
| Rhythm cell came-up | 1px edge cap, 180ms |
| Rhythm line all-up | 1.35× scale pulse, once |

No easing curve is specified anywhere in this design more expressive than a linear or
standard ease — the restraint is deliberate.

---

## 9. Edit mode and the layout layer

The old Rebar addon is **folded into MyUI** as its layout layer. It is not a dependency and
not a second addon: its code moves into the MyUI tree, and its repo becomes reference.

What comes across:

- The **viewport-aware, pixel-exact grid** (Rebar `Grid.lua`, verified from a native
  5120 × 2880 screenshot at uiScale 0.8).
- **Corner snapping and persistent positions** (Rebar `Manage.lua`). Rebar's in-game
  drag-snap was never tested; it is tested here for the first time.
- The 12.1 guard layer (`Compat.lua`) — already shared.
- The inspector and overlap scan, as **developer tools only**, behind `/myui dev`.

What does not: Rebar's "foreign profile adapters" (its unbuilt Phase 5). MyUI lays out MyUI's
frames and the Blizzard frames it adopts — never another addon's.

Edit mode itself, as round 002 specified:

- Screen dims to `rgba(0,0,0,0.55)`; the grid appears at 0.07 alpha, every 4th line at 0.14.
- Every frame gets a 1px ghost outline at `rgba(255,255,255,0.45)` with its name in 10pt
  letterspaced caps, and **its resting alpha printed next to it** (`rest 0.35`).
- Drag with snapping; per-frame alpha slider; reveal-group toggle.
- **Preview at rest** — drops the whole UI to resting alphas over the live game.

Positions saved by the old Rebar addon are migrated on first load, not lost.


## 10. Out of scope — say no to these

- Procs are not exposed; nothing here claims to show one.
- Damage meters and ability suggestions stay Blizzard's.
- No Classic support. Declare retail-only in the TOC.
- No comparative displays of any kind (RULES).
- **No dependencies** outside MyUI and Blizzard (RULES § Dependencies).
- No layout of other addons' frames (§ 9).

**Reversed in round 003:** round 002 said Rebar "offers nothing in [the minimap, chat and
bags'] place." MyUI now replaces them (§ 2, § 11). A clear screen that leaves the player
unable to find their bags is the confusion this project exists to remove.

**Plumber is declined** for now (D1) — too big to consider.

**DialogueUI is taken on** as a MyUI module, built from its behaviour, never its code. v1:
the quest and NPC dialog window; keyboard choices (number keys pick, space accepts); its dark
theme and overall look, **rebuilt flat in MyUI's palette** — no textures, per § 1 (D1).

**Bags are deferred** — a big topic, taken up later. Until then Blizzard's bags are adopted
(§ 2).


## 11. Clearing the screen — **MyUI's job**

The mock's bare backdrop is MyUI's output, not a precondition the player arranges. MyUI
ships a clean screen and can put it back.

Three techniques, by what each frame permits:

**~~Filtered — the player frame.~~ Superseded in R3b (2026-11-14).** The roleset filter was
probed in game and does not hide the frame: an unknown roleset is filtered only while a UI
mode's allowlist is active (API-NOTES § 13). The player, target and focus frames are
unregistered and hidden instead — see the table below.

**Hidden — the action bars.** MyUI creates and activates an Edit Mode layout named `MyUI`
with every bar disabled, recording the player's previous layout name in saved variables.
Disabling the addon, or `/myui restore`, switches back. Nothing is destroyed.

**Replaced — minimap, chat, bags.** MyUI draws its own (§ 2). Until each exists, the
Blizzard frame is adopted as below. Not hidden. Registered in the frame registry at resting
alpha 0 and revealed by the ordinary engine (§ 2, § 4). This is the § 1 premise applied to
Blizzard's frames rather than ours: hidden must never mean lost, and a chat frame you cannot
summon is lost. Chat additionally reveals on an incoming whisper and holds for 8s.

~~Everything else the mock removes — target frame, cast bar, buffs, party and raid frames — the
player already turns off in Edit Mode, and MyUI's layout does it for them.~~ **Corrected in R3b:**
Edit Mode's "Target and Focus", "Cast Bar" and "Buffs and Debuffs" settings only preview those
frames while Edit Mode is open; they hide nothing in play (API-NOTES § 13). Each is handled
in the table below.

**Combat lockdown is the whole risk here.** Protected frames may only be hidden or shown out
of combat. All filtering and layout activation happens on `PLAYER_ENTERING_WORLD` and on
addon enable; if `InCombatLockdown()` is true, queue and flush on `PLAYER_REGEN_ENABLED`.
Never in combat, in either direction. The adopted frames are alpha-only and therefore exempt —
which is the second reason they are adopted rather than hidden.

`/myui restore` reverses all three, in combat-safe order, and prints what it undid.

**Stowed — a fourth technique, ruled in R3 (2026-11-14).** `Stow.lua` reparents a frame under
a hidden parent, so Blizzard's own Show/Hide calls keep succeeding with nowhere to draw. It is
used only for a frame that is **unprotected, that Blizzard keeps showing itself, and that
MyUI has replaced**; anything not yet replaced stays adopted, because a stowed frame cannot
be summoned. Never for a protected frame.

| Frame | Technique |
|---|---|
| Player, target, focus frames | **Unregistered and hidden** (`UnregisterAllEvents` + `Hide`), out of combat only; a post-hook answers any later `Show` with a `Hide`. Restored by `/myui restore` plus `/reload` (R3b ruling) |
| Action bars | The `MyUI` Edit Mode layout **hides** every bar with a visibility setting (Phase 4 play ruling; was in-combat in R3b). Keybinds still work |
| Cooldown Manager | The `MyUI` layout shows its viewers **in combat only** — they carry cooldowns until the v2 rhythm line |
| Buffs, debuffs, player cast bar | **Adopted** (R3b ruling). The cast bar sets its own alpha when a cast starts, so it shows while casting |
| Main action bar, stance and pet bars | **Adopted**; hover or peek only (no visibility setting to hide them with) |
| Objective tracker, damage meter, XP bar | **Adopted** (Phase 4 play). Tracker: alpha on its frame only, never the manager |
| Micro menu; the chat panel's social button | **Adopted** (the social button also answers whispers) |
| The minimap's own map | **Adopted, and hidden once it settles at 0** — its arrow and blips draw regardless of alpha. Shown again before it fades in |
| Party and raid frames | **Adopted**; **per role** (tank, healer, DPS): `combat` (default), `hover` or `always` — `/myui group [role] <mode>` (§ 19) |
| Chat log, tabs, dock, buttons | Adopted now; **stowed** once MyUI's chat view exists. The edit box is freed first |
| Raid manager tab (`CompactRaidFrameManager`) | **Stowed**, queued out of combat |
| Minimap, bags | Adopted until replaced; decided when built |
| Objective tracker | Alpha only (§ 13) |


## 12. Modules carried in from the author's other addons

| From | Becomes | What it does |
|---|---|---|
| Rebar | Layout layer, § 9 | Grid, snapping, persistent positions, dev inspector |
| ChatQuiet | Chat module (§ 2) and Tracker module (§ 13) | Chat chrome hidden until hover, an alerting tab stays visible; tracker background cleared |
| HideBarTooltips | **Nothing — stays separate** | — |

ChatQuiet is retired once its two modules pass in game. Until then it stays in the play
environments (`nyx-minimal`, `raid`) and out of `newui`.

## 13. Objective tracker

Carried over from ChatQuiet unchanged: background cleared; resting alpha 0.1; hidden in
combat, **except in Mythic+ on trash**, where the timer and enemy forces live; alpha only,
never touching `ObjectiveTrackerManager` or Blizzard's alpha globals (both taint).

## 14. Minimap and chat — D1 answers

**Minimap.** Square and minimal. Every button that normally hangs around the minimap —
Blizzard's (tracking, calendar, mail, and the like) and other addons' — is gathered into
**one menu**, opened from the minimap.

This is the one place MyUI touches other addons' frames, and it does so **narrowly**: it moves
their minimap buttons into its menu and nothing else. No library is used to do it and none is
required; an addon with no minimap button is unaffected. § 9's rule otherwise stands.

**Chat.** Ignored by default — it has no resting presence. Two ways in:

1. **From a toast.** Interacting with a chat toast (whisper first) opens chat at that message.
2. **Summoned**, with filters by channel, and a log view.

**One view (D1, provisional — Mykel is not yet certain).** Chat and the notification history
(§ 6) are the same summoned view, filtered by notification hue and by chat channel. A chat
toast opens it at that message. Build it so splitting into two views later is cheap.

## 15. Screens — laptop to ultrawide

An original requirement, restated in round 003: MyUI must play well on a **laptop screen**
(the 16" MacBook Pro, `nyx-minimal`) and on a **widescreen / ultrawide** (`Pallas`).

- Every position is an **anchor offset**, never an absolute pixel (already § "Reference
  resolution"). The 1707 × 960 mock is a reference, not a target.
- The layout layer's grid is **viewport-aware** (§ 9): it measures the usable rect and stays
  pixel-exact at the display's scale.
- **Confirmed (D1):** on displays wider than 16:9, the centre
  cluster — `SelfStack`, `TargetStrip`, the dialog window — sits inside a centred 16:9 focus
  area so the eye does not travel; the edges hold only what is summoned.
- Saved positions live in each machine's own WTF, so a laptop and a desktop keep separate
  layouts without any sync.
- Every acceptance test runs on both screen shapes (PLAN R2).

---

## 16. The modal HUD — round 004

The HUD is a function of WoW's **mode**. Every mode is a plain game state; none needs a secret
value or a comparison of one. **Zones keep fixed positions in every mode** — a mode only decides
which zones are drawn (muscle memory survives); the one deliberate exception is the healer's
larger group frames (§ 19). Switching is a 120 ms cross-fade (§ 8). Peek and hover still summon
anything (§ 4).

| Mode | Driven by | Draws |
|---|---|---|
| Rest | `IsResting()`, not in combat | Nothing but the layout rail; toasts |
| Travel | mounted / flying | Layout rail, zone ribbon, flight vigour; the map on a key (§ 22) |
| Solo fight | `PLAYER_REGEN_DISABLED`, no group | Bars (§ 17), wings (§ 18), vitals (SelfStack), target strip (§ 20) |
| Group · DPS | combat in a party instance | Solo fight + group frames (§ 19) |
| Group · healer | combat + assigned role or spec `HEALER` | Solo fight + larger group frames |
| Raid boss | `ENCOUNTER_START` … `ENCOUNTER_END` | Boss mode (§ 21), raid grid, pinned cards |
| Vehicle | the override / vehicle bar shown | Vehicle bar in bar 1's place, vitals, target |

**Layout rail.** In rest and travel only: a short gold line with small round buttons, the current
layout large and gold-ringed (the housing UI's switcher). It shows the mode and lets the player
force one. In a fight the mode is obvious and the target or boss bar owns that space.

Mode changes that touch protected frames (bars, unit frames) happen out of combat; inside combat
only alpha moves (RULES).

## 16a. Layout profiles (round 004 play)

Blizzard's experience and second status bars sit at the **top edge** of the screen (Layout
`StatusBars`), shown as Blizzard shows them; MyUI's XP line under SelfStack is off.

The minimap is **on a key** by default (`peek`, since 2026-11-23: a fresh install on a second
machine showed the corner map nobody asked for). `/myui map calm` keeps it up **out of combat**
(Mykel: "enough of a map to see BugSack") — a `calm` reveal channel claimed outside combat.


Positions are personal preference (Mykel), so they live in **layout profiles** (`Layout.lua`):
where SelfStack, the target strip, the action bar (and with it the wings, stance and pet bars) and
the group frames sit, plus the wing gap and icon padding, in SPEC units. Built in:

- **focus** (default) — **2026-11-23** (Mykel: "All the unit frames above the action bars which
  move down"): the bar at the foot (24), then one stack that never overlaps — you (110), your
  target (157), your focus (220; with no target it drops into the target's place, in combat
  too — "[@target,exists] high; low", Mykel: "move down to avoid leaving gaps"; a profile may
  set `focusFixed` instead) — **all three 400 wide**
  (the target's width; the pet split still halves yours, to be sorted later), each labelled in
  amber at its left like FOCUS was: PLAYER, TARGET, FOCUS. The group list right of the target
  (248, 170 — clear of the focus's × by 26). Earlier: SelfStack (24), the bar (76), the target strip just over
  the bar (132); stance under the left wing and pet under the right (Mykel: "stances belong below
  the CDs"); Blizzard's zone / extra ability button with its frame art hidden, on bar 1's row past button 8,
  with the debuffs starting beyond it (`debuffGap`); the group list right
  of the target strip (224, 176) and, mirroring it on the left, the Cooldown Manager's tracked
  buff bars (-224) with Blizzard's zone / extra ability button beyond them (-460), all clear of
  the wings; icons 6 apart. The top of the screen is left free — boss mode's bar and
  timeline (§ 21) are the natural tenants.
- **spec** — SPEC 2's positions (SelfStack 214 up, target strip 20 from the top, bar at 48).

The debuffs sit past the zone button's place whether it is up or not. (They used to slide into
its place through a MyUI anchor frame, but Edit Mode resolves a named anchor through `_G`, and
reading an addon's global tainted the whole debuff frame. No Edit Mode anchor names a MyUI frame.)
`/myui layout` previews every placed part as a labelled box — debuffs, zone button, cooldowns,
utility, chosen buffs, stance, pet, buff bars, group — even when it has nothing to show.
`/myui profile` lists and switches; `/myui move self|target|bar|group dx dy` nudges (a built-in
profile is copied to "mine" first); `/myui spacing gap|padding n`; `/myui profile save|delete`.
The bar, group frames and Edit Mode placements move out of combat.

## 17. Action bars — bar 1 and three modifier pages

The player's own action bars, as they play them: **bar 1** plus three pages reached by holding
**ALT**, **CTRL** and **ALT+CTRL**. Centred under the character, low on the screen. Bar 1 is 44 px
buttons (8 shown); a page's buttons are 30 px when drawn small.

- **Paging is the client's**, by the modifier conditionals the parser knows (`[mod:alt]`,
  `[mod:ctrl]`, `[mod:alt,mod:ctrl]` — long-standing macro conditionals, unlike any health one;
  confirmed in game by probe P5).
- **Display style is a player setting** (round 004 play: default **Mini**):
  - *Mini* (Mykel) — Swap, plus the pages not in bar 1's place drawn at 45% side by side over it
    (ALT left, CTRL right), so their cooldowns are visible but quiet; a page's mini row hides while
    it is up full size, and while arranging. `/myui pages mini|swap`.
  - *Swap* — only one row drawn; holding a modifier puts that page in bar 1's place, labelled.
  - *Ghost* — unheld pages as thin strips, one tick per button, dark while cooling down.
- **Built as MyUI's own secure action buttons on Blizzard's action slots.** Blizzard's bars stay
  hidden (the MyUI layout) and keep the player's keybinds; MyUI's buttons draw the same slots and
  click them. Swap and Ghost page by a **secure state driver** on MyUI's header, the one way a
  display may change on a modifier in combat. Skinning Blizzard's bars was considered and is safer
  but cannot do either style (confirm with probe P5). Each modifier's page is **read from the
  player's own binds** — whatever ALT-1, CTRL-1 and ALT-CTRL-1 are bound to names the bar — so
  nothing has to be configured. One row of buttons per page, each modifier row fixed to its slots;
  the driver shows the held one. **The player's keys move onto MyUI's buttons** as override
  bindings (every key bound to a slot's command clicks MyUI's button for it), so a press, cast
  flash and proc glow show on MyUI's button and a key fires its slot even when the display has
  not seen the modifier. A vehicle, possession or pet battle hides MyUI's bar and drops the
  overrides in the restricted environment, so Blizzard's override bar takes over; a form's bonus
  bar (stealth, cat form, skyriding) still pages bar 1.
- **Pet bar** (round 004 play, Mykel: "I really hate this pet bar") — MyUI's own: only the slots
  that hold something, packed, at 18, right of the pet stack (level with its bars), drawn only while the pointer
  is on the pet stack or the bar (lingering 0.6 s). Secure buttons of type `pet`; right-click
  toggles autocast (`/petautocasttoggle`); edges show autocast (amber) and the active stance.
  Blizzard's pet bar is held at alpha 0, its keybinds still firing.
- **Stance (forms) bar** — Blizzard's own, placed by the MyUI layout under the cooldowns, at 30 px; they return with the
  bar (combat, a target). Round 004 play: they had been adopted and never came back.
- **Arranging**: every page drawn stacked above bar 1, labelled and held still — while a spell,
  item or macro is on the cursor, while the spellbook or macro window is open, or while the
  player toggles it (`/myui bars`, key "Arrange the action bars"). Out of combat; a fight folds it
  and it returns after.
- **The bar comes up with a target** as well as in combat (Mykel: target, hold ALT, tap a taunt to
  pull).
- **Items, trinkets and potions** need nothing special: they sit on action slots, usually as
  macros, and show icon, count and cooldown like any action. The Cooldowns wing (§ 18) may hold
  any action slot too.
- Button grammar: ready = the only state with a bright 1 px edge; cooling down = a dark sweep, no
  number; the number only in the last 3 s; charges top right in resource blue; unusable = dimmed,
  never hidden; **keybind top-left** (Blizzard's newest bars). Gold ring only for "selected".
- Order is the player's and never changes in play (RULES: no ranking by readiness).

## 18. The wings — on the bars' rows

Two small groups that line up row for row with the bar stack, so nothing floats.

- **Left — Cooldowns.** Major cooldowns on bar 1's row at bar-1 size; utility cooldowns above on
  the next row, small. Major cooldowns are **larger than bar 1** (55 vs 44) and 32 from the bar, so
  they don't read as more bar (round 004 play). **Built as the Cooldown Manager's own viewers** (Essential, Utility),
  placed by the MyUI Edit Mode layout at the bar's left edge, growing away from it, adopted at
  alpha 0 and revealed with the bar. Mirroring into MyUI buttons is not possible on 12.1:
  `Cooldown:SetCooldown` is protected (probe P2 answered from the API).
- **Right — On you.** Debuffs on you on bar 1's row, edged by dispel type; a **few chosen buffs**
  above, small — the chosen buffs are the Cooldown Manager's tracked buffs (BuffIcon viewer).
  Round 004 play: the chosen buffs moved to the **left**, over the utility row, for now (Mykel:
  "the other side, but I haven't decided where"); the tracked buff bars sit over them, growing up. **Debuffs are Blizzard's debuff frame**, placed on bar 1's row right
  of the bar at ~bar-1 size with its own dispel-type borders (built); Blizzard draws whatever
  arrives secret, so P1 no longer gates the wing — only MyUI's own unit cards (§ 19). Dispel types take the palette's notification hues — magic blue, curse violet,
  poison green, disease amber — so no colour is added. Whether aura data arrives secret in
  restricted content is unverified (PLAN probe P1); if it does, the same degrade-not-read rule as
  the cast bar applies.

## 19. Group frames and unit cards

**Frames.** MyUI's own, in **one area right of the character**: a short list for a party (name,
role, thin health), larger for a healer, a 5-wide grid of cells for a raid. Fixed order — role,
then group order — **never by health** (RULES). Built on Blizzard's protected unit buttons and
group header, so roster changes are handled securely in combat. Health through curves, like
TargetStrip. A small dispel-type dot shows on a name or cell that carries one.

**Built (M3, first part):** `Group.lua` — party list (role icon, name, thin health; larger for a
healer, resized on a spec change out of combat) and the raid grid, on `SecureGroupHeaderTemplate`
with every button made out of combat; click / ctrl-click / right-click as below. Blizzard's party
and raid frames are hidden outright. Not yet: shift-click pinning, cards, alt-click, dispel dot.

**Per role (2026-11-23).** Each role — tank, healer, DPS (no role reads as DPS) — keeps its own
**mode** and **look**, per machine (`MyUIDB.clear.groupBy`, `groupLook`):

| | |
|---|---|
| `combat` (default) | back in every fight, and on hover or peek |
| `hover` | never by combat; hover or peek only |
| `always` | up all the time (the `always` reveal channel, asked again on a role or spec change) |
| `list` | a column of rows — the healer's default |
| `icons` | **five tiny squares in a row, no names** (Mykel: "5 tiny icons that act"): health fills the square from the bottom in the **class colour**, the role mark centred (18 in 24); the same click map; the name on hover in MyUI's own small tip (a FontString, as a name may be secret) — the tank and DPS default |
| `boxes` | five small boxes in a row, role icon in the corner, name, health in the class colour — a choice |

`/myui group` shows all three; `/myui group [tank|healer|dps] <mode or look>` sets one (no role:
the current one). The old single setting migrates (`auto` was combat for healers only, hover for
the rest). The class colour is the one place group frames leave the palette; an unreadable class
falls back to it.

**Click map** — on every frame and every card, shown as a legend on a card:

| Click | Does |
|---|---|
| click | **target** (as in WoW) |
| shift-click | **pin / unpin** its card |
| ctrl-click | focus |
| alt-click | cast the player's chosen spell on that unit — a setting, defaulting by class, spec and level (e.g. their dispel) |
| right-click | Blizzard's unit menu |

Fixed bindings the player chooses. MyUI never chooses the spell or the unit by state.
Alt-click casting is legal as specified (`DECISIONS-004.md`) and is verified in game before it
ships (probe P3). Holding ALT to alt-click also shows the ALT page in Swap mode; harmless.

**Cards.** Rest on a frame for **0.4 s** and its card appears in a column at the far right; it
stays **1.5 s** after the pointer leaves, and holds while the pointer is over the cards. A card:
name, spec and what they are targeting; health and percentage; debuffs edged by dispel type with
stacks; a one-line note. **Clicking a card's name targets that unit**; the same click map works on
cards. **Pinned cards** stay in the column — edged gold, kept across modes, separate lists for
party and raid. Most important in the raid view.

**How pinning works in combat.** Assigning a unit to a protected button is blocked for addon code
in combat. So a pool of cards is created out of combat, and **shift-click pins through a
restricted script** on the protected unit button, which hands its unit to the next free card and
shows it — allowed in combat, the pattern click-casting addons use. The card's display (health,
debuffs) is ordinary MyUI code fed by curves.

## 20. Target strip — hostile, neutral, friendly

TargetStrip keeps its place and shape. One palette dot before the name says what it is:
**danger** for hostile, **notif amber** for neutral, **notif green** for friendly. Hostile: level,
health, the cast bar, and *your* effects on it. Friendly: role, health and their debuffs edged by
dispel type. In raid boss mode it sits under the boss bar.

## 21. Boss mode

On `ENCOUNTER_START`, for an elite or boss target: a wide **boss bar** — name, percentage, phase
marks (static ticks), the boss's cast — with a **timeline** under it of what is coming, sliding
toward NOW. Under that, **one critical alert at a time**, a banner with a countdown. Both from
Blizzard's own encounter systems (`C_EncounterTimeline`, encounter warnings), mirrored or
restyled after probe P4 — MyUI never predicts a boss.

## 22. The map on a key

In travel, a key (M) calls up Blizzard's world map translucent over the world, and closes it.
Mount, hearthstone and the like come up on hover.

**Built, round 005 (`Map.lua`, the "minimap" switch).** The key (MyUI → Show the map, or
`/myui map`) brings Blizzard's own minimap render — terrain, your arrow, quest blips, nodes, the
addon buttons on its edge — up big, at the zoom it had, in a summoned panel docked first in the right
column, the panels' one width (the world showing through at 85%), and hands it back to its corner when it closes. Header: the
zone and your coordinates (the zone alone where the client restricts position). Footer: "world
map" opens Blizzard's (out of combat). Wheel zooms, click pings. Pin, ×, and going away by itself
as the other panels do. While it is out the map is square, the minimap's ring, compass and zoom
buttons go (the wheel zooms), and every addon button from its edge plus Blizzard's landing-page orb
line up small in the footer's right side — all put back when it closes. Still to come: mount,
hearthstone and the like on hover.

## 23. Switches and the quest tracker (round 005)

**Switches.** Every place MyUI replaces or hides Blizzard chrome is one player switch
(`Switches.lua`): quests, chat, minimap, buffs, castbar, cooldowns, menu, meter, bars, unitframes,
group. On (default) is MyUI's way; off gives that piece back to Blizzard. Alpha-only switches apply
at once; bars, unitframes and group (protected frames) on `/reload`. `/myui override` lists them;
`/myui override <name> on|off` flips one. Saved in `MyUIDB.switches` (only the ones turned off).

**Quest tracker** (`Quests.lua`, the "quests" switch). Blizzard's objective tracker stays adopted
at 0; MyUI says what changes:
- **Toasts, amber.** An objective moving says its own line ("Boars slain: 4/10"); a quest
  finishing says "<title> -- ready to turn in" instead of its last objective; accepting and turning
  in say so too. The first read after login only records. `QUEST_LOG_UPDATE` is read once per burst.
- **The list, on demand** — the MyUI → Show the quest list key, `/myui quests`, or peek. Right
  edge, where the tracker was, compact (round 005 play: "details called up rather than all
  listed"): one line per quest — its title and a hairline progress bar under it, filling from
  the screen edge. Counts are noise unless pinned: only the waypoint quest carries one (`18/20`
  for one counted objective, a percentage otherwise) and shows what is left of it; a quest ready
  to turn in says `ready` in green. Order: the waypoint quest (amber), then ready, then the rest;
  eight at most, then "+N more", which opens the whole list ("fewer" closes it). Hover a quest:
  a card to its left with the whole title and every objective, done ones green. Left-click: waypoint arrow on it
  (again: off). Right-click: open it on the map (out of combat). Rows take clicks only while
  open; the pointer never wakes it; combat closes it.

**Summoned panels** (`Summon.lua`, round 005 play: the history "seems stuck open"; the two
panels "should match better"). The quest list and the history share one surface — SPEC 7's dark
exception, hairlines top and bottom, a header with a title (the history: its hue filters) and
**pin** / **×** at the right — and one behaviour: an unpinned panel goes 1.5 s after the pointer
leaves it, 10 s after opening if the pointer never came, and when combat starts. Pinned (amber
"pinned"), it stays through all of that and comes back open after `/reload`. × always closes and
unpins. The quest list's rows are left-aligned like the history's; its hover card wears the
same surface.

**Which chat box, and peek (2026-11-23).** With extras off, Enter opens Blizzard's box. With
extras on, Enter opens MyUI's box and `/` opens Blizzard's (which runs every slash command — MyUI
never routes them); Blizzard's box sits at the bottom left, or in the chat panel's footer while the
panel is open. With the chat panel on, Blizzard's chat window stays down on **peek** as well as on
whispers (Mykel: "peeking to the blizz chat window is annoying") — `Reveal.UNLESS.peek`.

**The debug log (2026-11-23, `Dev.lua`).** For testers, off unless `/myui dev on`. A left-docked
panel on the same grid: filters by kind — command (blue), error (orange), reveal (violet), layout
(green) — newest first, each with its clock time; under the filters, a line naming what is under
the pointer, the MyUI part that owns it, its alpha and the channels holding it up. Footer: **copy**
(the shown entries, oldest first, selected in the copy window for Ctrl+C — an addon cannot write
the clipboard), **clear** (what the filter shows), **report** (the debug report, then a reload);
left-click a row to copy it whole, right-click clears it. Errors are a command or module that
failed, a compliance violation, and an action Blizzard blocked for MyUI; while closed, an error
speaks one toast at most every 30 s and the title counts them. Reveals are claims and releases,
never the pointer's. Kept (200) in `MyUIDB.devlog` across reloads; it holds what commands printed,
names included, so the debug report never carries it. MyUI → Show the debug log; `/myui dev`.

**Tooltip.** Blizzard anchors its default tooltip to the HUD Tooltip Edit Mode system's corner, so
the MyUI layout moves that system (profile key `Tooltip`, bottom-right, growing up; `/myui move
tooltip`). Nothing of MyUI's touches the tooltip itself — it carries secret values.

**Quest kinds and filters** (round 005 play: "toast style filters ... tracked quests, events,
achievements ... world quests and temporary events"). The list holds tracked quests (or the log's
first twelve when none are tracked), tracked world quests, the events where you are (bonus
objectives and other area tasks), and tracked achievements (their criteria as objectives). A filter
row under the header — all · quests · world · events · achieve, each with its count — shows one
kind. Achievements: left-click opens it in the achievements window, right-click stops tracking.

**Chat panel** (`Talk.lua`, the "chat" switch). Chat as a summoned panel in the same style: the
last 200 messages kept by MyUI from the CHAT_MSG_ events (Blizzard's log stays hidden, untouched),
filters all · whispers · group · guild · say with what came in while it was closed, rows of who,
what (up to two lines) and age, oldest at the top. Click a message to answer on its channel; the
"type..." row opens Blizzard's box on the filter's channel — Blizzard does the sending. Toasts
(violet, people): whispers (Sources), party and instance chat outside a raid, guild and raid only
when they name you; nothing secret toasts. Secret senders and messages are forwarded to SetText via
Guard.Send, never joined or searched. A whisper no longer brings Blizzard's log back. Key: MyUI →
Show chat; `/myui chat`.

**Who's online** (`Social.lua`). Guild then friends (character and Battle.net), name and zone,
beside the chat panel; "online N" in the chat header, MyUI → Show who's online, `/myui social`.
Click a name to whisper. Logins (guild mates and friends) toast, gathered for 2 s: "Online: Aria,
Bren +3"; clicking that toast opens the list.

**Docking and squares** (round 005 play: the history and chat overlapped; "I like the color
coding ... the squares"). Summoned panels dock in two columns and stack instead of overlapping —
left: history, then chat; right: the map, the quest list, then who's online — each only as tall as what it
holds. While the left column is out, toasts speak beside it. The history's hue squares carry over:
chat filters and rows (whispers violet, group blue, guild green, say grey) and quest filters and
rows (quests amber, world blue, events green, achievements violet); an unchosen filter dims while
another is chosen.

**The grid** (round 005 play: "margins are inconsistent and the panels are arbitrary sizes").
Every summoned panel is built from `Summon.lua`'s numbers and builders only: one width (320), PAD
10 inside, a 26 header (title left — with the chosen filter's name, "Quests · world" — pin and ×
right), a 22 filter row of equal columns (all N, then each hue's square and count), rows on the
22 grid (a chat message is two lines, a quest is a line plus its bar), and a 22 footer: the panel's
action at the left (history: clear; chat: type...), "+N more" / "fewer" at the right on every
panel. Both dock columns start 200 from the top, 16 from their edge; toasts start there too.
The history rolls runs up ("Online: Aria, Bren +3", "Voidsteel Greaves x3"); clear empties what
the filter shows. While chat is open, Blizzard's typing box sits in its footer.

**Shapes, the top, the bottom, clicks** (round 005 play). Each hue keeps one shape everywhere —
toasts, history, chat, quests, who's online: violet circle, blue diamond, amber triangle, green
square, orange bar (`Summon.SHAPE`). The dock columns start just under the status bars at the top.
A panel never grows into the HUD at the bottom: it shows as many rows as fit (`Summon.FitRows`,
the panels above it counted) and "+N more" for the rest. History rows act: left-click a whisper
to answer it, a login for who's online, a chat line for the chat panel, a quest for the quest list,
loot or full bags for your bags; right-click clears that one notification (or the whole rolled-up
run). A quest toast opens the quest list.

**Under Blizzard's windows** (round 005 play). Summoned panels share MEDIUM with Blizzard's windows,
which raise themselves over them when opened. On the talents and specialization pages the bar does
not arrange, and it and the clickable strips go under the window; the spellbook page, or anything on
the cursor, brings the bar back on top.

## § 6 amendment — Blizzard's own toasts

Blizzard's Battle.net toast (friend online, and the like) and alert toasts are old, bordered and
blurry beside MyUI's. They go through MyUI's toasts where the event is one MyUI already shows,
and are quieted otherwise. Never a fourteenth colour.
