# MyUI — status

**Last updated:** 2026-08-27 · `0.4.0-phase3` · 476 addon checks / 7 lint rules over 16 files, all green

Target: WoW Midnight 12.1.0, TOC `120100`. Reference source read at build **12.1.0.69497**.

---

## Where things stand

| Phase | State |
|---|---|
| -1 — Ground truth | **Complete.** Three corrections to the handoff, recorded with citations |
| 0 — Skeleton and compliance harness | **Delivered** — `v0.1.0-phase0`, verified in game |
| 1 — Anchors and frame registry | **Delivered** — `v0.2.0-phase1`, 15/15 in game |
| 2 — Reveal engine | **Delivered** — `v0.3.0-phase2`, 16/16 in game |
| 3 — Rail | **Delivered** — `v0.4.0-phase3`, 17/17 in game |
| 4 — Bars and low health | Not started — **spec amended**, see below |
| 5 — Edit mode | Not started |
| 6 — Polish and persistence | Not started |
| **6b — Clearing the screen** | **New.** Added by the amendment. SPEC § 11 |
| 7 (v2) — Rhythm line | Not started |

### The handoff came back amended, 2026-08-27

`DESIGN-QUESTIONS.md` went to the designer with fourteen findings. **All fourteen
are answered**, and `SPEC.md`, `RULES.md` and `PLAN.md` are amended in place — the
reasoning is in the handoff's new `HANDBACK-RESPONSE.md`, which says explicitly
that where it and the specs disagree, the specs win.

The revised handoff is at `~/Development/UI - Rebar/in/current`, beside
the original. Read-only, like the original.

Both questions that were blocking or shaping Phase 4 are closed:

| Was open | Answer |
|---|---|
| Whose job is the empty screen? | **Rebar's.** New SPEC § 11, new PLAN Phase 6b. Player frame filtered by roleset, action bars via an Edit Mode layout, minimap/chat/bags *adopted* at resting alpha 0 rather than hidden. `/myui restore` reverses all three |
| Does low health summon, or only escalate? | **Summons — `SelfStack` only.** The fifth mechanism is licensed for this one purpose: a hook on Blizzard's `LowHealthFrame`, whose show/hide is a plain boolean and so *may* claim in the arbiter where a step curve's secret alpha cannot |

Other substantive changes: the **modifier reveal channel is cut**; the arbiter's
tie **precedence is now specified** and differs from ours; the **palette collapses
to thirteen** colours; the rail gains **seven real notification sources**; and the
dots get a **1px dark edge**.

### Reworked to match, before Phase 4

Three amendments landed in already-accepted phases. Done, `./smoke.sh` clean at
434 checks, **not yet re-verified in game**:

- **Modifier channel removed** — the channel, the configurable key set, the
  `Hold to reveal` binding, the saved setting (schema 1 → 2 clears it) and the
  `via` argument that existed only to tell its two arms apart. Phase 2's script
  drops from 16 steps to 13, Phase 3's from 17 to 16.
- **Precedence is now SPEC § 4's**, not ours: `debug, combat, target, peek,
  cursor`. Phase 2 put peek above state change, so **a peek during combat is now
  credited to combat**. The alpha is identical either way; only `/myui claims`
  changes.
- **Palette collapsed to thirteen.** `textSecondary` and `textTertiary` became
  one `textDim`. `/myui contrast` survives with inverted meaning: `lift` is the
  spec, `normal` is the superseded grey, and that grey is deliberately no longer
  a palette entry — it lives as a constant in `Frames.lua`, the one colour in the
  addon `Palette.Get` cannot serve.

`/myui rules` was rewritten too: eight prohibitions, five mechanisms, and the
licence text limiting the fifth to `SelfStack`. It is the file that has to be
right before Phase 4 uses the new mechanisms.

**A real bug fell out of the palette collapse.** The old lift was a blanket rule —
tertiary → secondary *and* secondary → primary — so with lift on by default, the
TargetStrip's level text drew at `rgba(240,241,243,1)` instead of the
`rgba(173,177,184,1)` SPEC § 2 names for it. It has been wrong since Phase 1 and
was accepted three times without anyone seeing it, because nothing draws the two
levels next to each other. There is one dim grey now and no remapping, so it is
correct by construction.

### Phase 3's two amendments, also built

**The 1px dark dot edge.** In `tickDark`, on the same 10 × 10 rect as the dot so
it stays the specified size and reads as a bordered square rather than growing by
two pixels. Drawn by a `HairlineBox` helper the "+N more" square now shares —
SPEC § 6 asks the two to match, and two separate implementations of "a 1px box"
is how they stop matching.

Built as a **sibling of the dot, never a child**, which is the amendment's own
implementation note and the whole trick: a child inherits the dot's 0.4 and the
edge vanishes at exactly the alpha it was added to rescue. Two tests guard it —
one asserting no alpha is ever set on the edge, one reading `Rail.lua` off disk
to assert `dot:CreateTexture` never appears.

**One reading to check by eye.** SPEC attaches the edge to the *"Older items"*
line specifically, and gives legibility at 0.4 as the reason — which does not
apply to a dot at full alpha. So the newest two dots have no edge, and the rail
reads as a progression: solid dots, outlined dots, hollow square. That is a
defensible reading rather than an obvious one, and two acceptance steps ask
whether it looks deliberate or inconsistent.

**The seven real notification sources**, in a new `Sources.lua`. SPEC § 6's event
table wired verbatim, kept as data so a test can assert every event the spec
names is registered and nothing outside it is.

The interesting part is not the wiring but SPEC's *"one row per event, never a
stream"*, which needed two mechanisms because there are two shapes of noise:

- **A latch, for a condition.** Bag full, low durability and pending mail are
  states whose events fire on every change. The latch speaks on the way in and
  stays quiet until the condition clears, so a full bag says so once. Nil is
  deliberately not "fine" — an unreadable durability leaves a live warning
  latched rather than silently disarming it.
- **A coalesce window, for a burst.** `UNIT_QUEST_LOG_CHANGED` fires several
  times for one objective and carries no quest id to tell them apart. **Two
  seconds, invented** — SPEC gives no window. Flagged in `DESIGN-QUESTIONS.md`.

Every reader goes through one defensive `API()` helper, because on 12.1 a
misremembered name returns nil in game while every offline test passes — three
times on this project already. A source whose reader is missing still posts its
row under a fallback name rather than erroring on login.

`/myui sources` prints the thresholds, a live reading of free bag slots and worst
durability, and which conditions have already latched. A latched condition and
one that never fired look identical otherwise, which makes the stream rule
uncheckable in game without filling your bags twice.

### What is still not done

**An in-game run.** All of the above is offline-green only, at 476 checks.
Phase 2's script shrank (16 → 13 steps) and Phase 3's grew (17 → 23), and both
want re-running before Phase 4 builds on the arbiter.

The new steps below the `/myui sources` line are the first in this project that
cannot be driven by a command — they need loot to drop and a quest to hand in.
That is the point: the filters are guesses until something real goes through
them.


Running a phase acceptance test: `/myui test` in game, work down the checklist,
hit **report**, `/reload`. The report lands in `MyUIDB.testRuns` and can be read
off disk with nothing transcribed.

Deploying a build:

```sh
python3 ~/Development/cc-addon/wowaddons.py --update MyUI
```

---

## Answered: SPEC § 3 needs no event. Step curves do it.

Two probes settled this.

**No health macro conditional exists** (live client, 2026-08-27). `RegisterStateDriver`
cannot deliver SPEC § 3's state. The probe also found that an unrecognised conditional is
*ignored* by the parser, so the clause matches; it now tests numeric candidates as an
always-false / always-true pair, which discriminates at any health.

**But an event turned out not to be necessary.** Auditing four shipped unit-frame addons
surfaced the technique: a **Step curve** holding one alpha below a cutoff and another above
it, evaluated against health, yields an alpha that flips at the boundary. Forward it to
`SetAlpha` and the threshold exists with no comparison anywhere in Lua. Plater ships this
for its execute-range marker.

| Tell | How |
|---|---|
| Screen-edge hairline at 0.35 | Step alpha straight into `SetAlpha` |
| Number 12pt → 14pt | Two stacked FontStrings cross-faded by step alpha |
| Breathe 1.0 ↔ 0.55 | Two copies of the health group, one steady and one permanently animating, cross-faded by step alpha. The animation never starts or stops, so nothing has to start it |

Cost: duplicated frames for two tells. Against that, the alternative — hooking Blizzard's
`LowHealthFrame` — costs a CVar the player can switch off, a threshold fixed at 0.35 that
is not ours, and a fifth mechanism outside RULES.md's four.

**Recommendation: step curves.** They stay inside the existing rules and keep the threshold
ours. `Guard.StepCurve` and `Guard.AlphaAt` ship in Phase 0. **SPEC § 3 is unblocked** and
Phase 4 no longer waits on a decision — though the duplicated-frame approach is a change to
how § 3 is built, so it is worth your eye before Phase 4 starts.

---

## Corrections to the handoff, from Phase -1

Full detail with citations in `API-NOTES-12.1.md`.

1. **The forwarding path is a first-class API.** `UnitHealthPercent(unit, usePredicted,
   curve)` returns the *evaluated* result — the percentage never enters Lua.
   `UnitPowerPercent` matches, so the resource bar comes free. SPEC § 3's continuous layer
   is the API's documented intent rather than a clever reading of it.

2. **`SetColorFill` and `SetScale` refuse a forwarded secret.** They are
   `AllowedWhenUntainted`. Colour the health fill through
   `bar:GetStatusBarTexture():SetVertexColor(...)`. The obvious-looking call is the one
   that fails. `Guard.Send` enforces this, and `rules_lint.py` R3 catches it statically.

3. **There is no mask inversion.** `SimpleMaskTextureAPI` declares zero functions and no
   inversion parameter exists, so SPEC § 3's inverted-mask wash cannot be built — it would
   need a texture asset, which the zero-asset rule forbids. Substitute: a second StatusBar
   with `SetReverseFill(true)` fed the same forwarded value. It occupies exactly the
   depleted region by construction, and is strictly better than what the spec asked for.

---

## Decisions made at the start

| Question | Answer |
|---|---|
| Addon name | **MyUI** — the handoff says "Rebar", which collides with the layout framework's folder, slash prefix and SavedVariables |
| Repo | Its own, beside `Rebar` and `cc-addon` |
| Coordinates | SPEC's numbers are mock-canvas px on a 1707×960 canvas; × 0.8 gives UI units. "1px" means one physical pixel. Lives in `Scale.MOCK_TO_UNIT` — one edit if wrong |
| Low-health treatment | ~~Combined: curve + one driver state~~ → colour curve + step curve + summon hook (amended SPEC § 3) |
| Rhythm line in v1 | No — deferred to Phase 7 |
| Config surface | Slash commands only |

The scale factor lives in one constant, added in Phase 1 as `Scale.lua`, so the reading
above is one edit to revisit if it turns out wrong.

---

## Answered: SPEC's palette assumes a dark backdrop

Found in game during Phase 3. SPEC § 7 is light-on-dark — near-white text, faint white
troughs, pale pastel dot hues. Over bright scenery (desert sand, firelight, anything
golden) the whole HUD washes out and the small type becomes genuinely unreadable. **This
is not a rail problem**; it will hit the bars and the health number in Phase 4 identically.

**Fixed for text.** Every string now goes through `Frames.Text`, which applies a shadow
using `tickDark` — already `rgba(0,0,0,0.55)` in the palette, so no fifteenth colour is
introduced. `/myui text shadow | outline | none`, persisted. Outline is stronger but
thickens the type, which the design's restraint argues against, so it is offered rather
than imposed. A structural test fails the build if any module creates a FontString outside
the helper, because such a string would miss the treatment and the miss would only show up
on a bright backdrop.

**The dim greys needed more than a shadow.** `textTertiary` was `rgba(115,119,126,1)` — a
mid-grey. Against the mid-brown of ordinary terrain it has almost no contrast in either
direction, and a shadow cannot fix that: a shadow solves an edge problem, not a contrast
one. The age and the "+N more" count were reported unreadable in game.

Phase 3 shipped `/myui contrast lift` as a deviation and raised it. **The amendment adopted
the lift**, and took it further than expected: the lifted value *is* the existing secondary,
so the two entries collapsed and the palette is now thirteen colours, not fourteen. The old
grey survives only as `/myui contrast normal`, a debug affordance for looking at the
original intent, and it is deliberately not a palette entry.

**The dots: answered as the 1px dark edge**, in `tickDark`, matching the "+N more" square.
The backing option was rejected because § 1's geometry rule is that fills above 14% do not
exist outside a data bar, and an edge stays inside the vocabulary the design already has.

The amendment carries one implementation note that decides whether it works, worth repeating
because it is the kind of thing that passes offline and fails on screen: **draw the edge as
a sibling texture at constant alpha, never as a child of the dot.** A child inherits the
dot's 0.4 and the edge disappears at exactly the alpha it was added to rescue.

**Not built yet** — this is Phase 3 amendment work, alongside the seven notification
sources.

---

## Phase 3: what was decided where SPEC is silent

**Nothing produces a notification.** SPEC § 6 specifies the rail completely — dot size,
spacing, hues, cap, the two named rows, the toast's timings — and never says what puts an
item on it. Rather than invent a data binding the design never asked for, Phase 3 ships
`/myui notify` as the source. That is also exactly what the acceptance test needs: eight
at once, on demand. **The real sources are an open design question.**

**Where the toast sits.** Named in § 6 and § 8 with its timings, never with its geometry.

The first attempt gave it its own dot and its own copy of the text, anchored over the first
row — so while it was up you saw the same notification **twice, overlapping itself**. Found
in game; every offline test passed, because none of them asked what the row was doing
meanwhile.

Read literally, § 6's "collapses into its dot" says what the toast *is*: the newest item's
row, expanded. So it has no dot of its own, it borrows the first slot's, and that slot's
text stays hidden until the toast has collapsed into it. The slide comes from 12 left over
180ms — a Translation snaps back to its anchor when it finishes, so sliding *in* means
anchoring short of the destination and moving the anchor as the animation ends, not
animating toward it.

**What a second toast does.** § 6 says a toast "speaks once, then collapses after 4s or on
dismissal" and says nothing about two arriving together. A newer one takes the slot and
restarts its own dwell rather than queueing — the rail already holds every item, so the
toast is the announcement, not the record.

**Row text geometry.** § 6 gives the name and age their fonts and alignment but no
offsets. Name sits 8 right of the dot; age is right-aligned in a 160-wide row.

### A conflict between PLAN and SPEC

PLAN.md's Phase 3 scope line lists "bloom texture" among the things to build. SPEC § 6 cut
the bloom permanently and says explicitly **do not implement it**, with two ladder images
as evidence that it is invisible at every size and opacity tried. SPEC is authoritative
per its own first line, so the bloom is not built. PLAN's line is stale.

---

## Phase 2 acceptance: passed, 2026-08-27 16:58

**16 of 16**, `v0.3.0-phase2`. Every channel drives its frames in isolation, overlapping
claims hand over without the alpha moving, and releasing everything returns each frame to
its own resting alpha rather than to zero.

**The transition log found a defect the acceptance criteria could not.** Reading the live
log afterwards, one Alt press had produced three handover lines at three different
timestamps, and the credited winner flapped between `modifier` and `cursor`.

Cause: every channel claims 1.0, so ties are the *normal* case, and the arbiter iterated
the claim table with `pairs()` — Lua's internal order — using a strict `>`. Whichever
channel came out first won, and that changed between resolves. The alpha was never wrong;
only the attribution was. But the log is a diagnostic now, and one that invents events is
worse than none.

Fixed with a declared `Reveal.PRECEDENCE`, ordered most-deliberate-first:
`debug, peek, modifier, combat, target, cursor`. A fixed order plus a strict `>` means the
first channel to beat the running best keeps it, so ties resolve the same way every time.
`debug` leads because it is an override and the audit should say so; `cursor` trails
because it is the one claim you can make by accident. A test asserts the list covers every
channel exactly once, that repeated resolves never change the winner, and that precedence
breaks ties only — a genuinely higher claim still wins outright.

Also observed and correct: hovering the health bars reveals the cooldown line too. They sit
18 apart and the proximity zone is 25.6, so one cursor is legitimately near both.

### Two corrections from reviewing that diagnosis

**The log could not actually prove what I said it proved.** It recorded outcomes — a
frame's target or winner moved — and never inputs. So "Alt pressed three times" and "one
press with the winner re-attributed twice" produced identical lines. It now logs both, as
`+ modifier` / `- modifier` input entries alongside the outcome entries, and only when the
claim state really changes so a held key does not spam. (Re-reading the original log, no
`TargetStrip 1.00 -> 0.00` appears in that window and TargetStrip is claimed only by the
modifier, so Alt was held throughout — which does point back to re-attribution. But that is
inference, and the point is that it no longer has to be.)

**SPEC § 4's modifier channel conflicts with ordinary keybinds.** Not just the default —
the whole mechanism. On this machine `Ctrl+1-6` is the top action row, `Alt+1-6` the
middle, and bare `1-n` the bottom. That is a completely conventional three-row layout, and
it leaves no modifier free. A HUD keyed to one reveals itself on every modified cast in a
fight, which is the incidental-reveal problem the 140ms dwell exists to prevent, arriving
through a different door.

Two answers, both shipped:

- `/myui modifier alt shift ctrl` chooses the keys, `/myui modifier none` disables
  detection. Persisted; default remains SPEC's Alt or Shift.
- **A bindable "Hold to reveal" key**, so the channel need not be a modifier at all. It
  arms the same `modifier` channel, and `runOnUp="true"` with `keystate` gives both edges
  of the key — the identical shape Blizzard uses for `MOVEFORWARD` and the ping listener.

Recommended for a layout like this one: `/myui modifier none`, then bind **MyUI → Hold to
reveal** to any free key.

**Raised, and answered: the channel is cut entirely.** The amended SPEC § 4 removed it
rather than re-defaulting it, on the reading that this finding was really an argument that
the channel was never load-bearing — proximity covers reveal-while-doing-something and peek
covers reveal-because-I-want-to, and the modifier only ever covered reveal-while-casting,
which is the case where it misfires. The hold binding came out with it, since it was an
escape hatch from a channel that no longer exists.

Knock-on the amendment names: peek is now the only deliberate summon, so the 3s tap carries
more weight than it did, and PLAN Phase 6 should judge whether it still wants to be a tap or
a hold. `Bindings.xml` keeps the `runOnUp` + `keystate` shape in a comment for that reason —
it is the answer to "how do you bind a hold", and a test asserts it is still recorded.

**Verified in game 2026-08-27**: the modifier channel arms and releases cleanly, one input
entry with its three outcomes sharing a timestamp. The log now records `via binding` or
`via keys` on the claim, because both mechanisms arm the same channel and a log that cannot
tell them apart invites exactly the guessing it exists to end.

---

## Phase 2: what was decided where SPEC is silent

Four gaps, all named in code next to what acts on them.

**Per-channel claim alpha.** SPEC says "highest claim wins" but never gives a channel
an alpha, so all of them claim 1.0 and the maximum is trivially satisfied. The
arbitration is written for real values anyway — changing any one is a one-line edit —
and the tests lower a claim deliberately so highest-wins is actually exercised rather
than accidentally true.

**Which frames each channel claims.** SPEC tabulates triggers, not targets. Cursor
proximity is per-frame by definition; the rest are inferences: combat claims SelfStack
and Cooldowns, target claims TargetStrip, modifier and peek claim everything.

**The drain clock has no geometry.** The only visual in Phase 2 the spec names and
then leaves undescribed. Built as the least invented thing that satisfies "visible
drain clock" inside § 1's flat geometry: a 1px hairline the width of the SelfStack,
draining right to left, in `fillDim` which is already in the palette. **Wants your
eye.**

**"Within 32 units."** Converted like every other spec number (× 0.8 → 25.6 UI units),
but this is the one place the spec says "units" rather than leaving the number bare, so
it may not be a mock-canvas pixel. One constant if wrong.

### And one thing SPEC asks for that cannot be built

§ 4 lists the low-health driver state as a state-change channel. There is no driver
state, and § 3's replacement is a step curve whose output is **secret** — so it can
never enter an arbiter that compares claims. The arbiter deals only in plain numbers;
anything curve-driven lives on child frames where alpha multiplies on its own.

That is fine if § 3's continuous escalation was the whole intent. If the design also
wanted *"when I get low, the HUD comes up"*, that needs a discrete event and the only
source is hooking `LowHealthFrame`.

**Answered: it does summon, and the hook is licensed for exactly that.** The amendment
accepts the reasoning above and routes around it — the hook's show/hide is a *plain
boolean*, not a secret, so it may be compared and may claim, which is precisely what a step
curve's alpha cannot do. It reveals `SelfStack` alone: not the cooldowns, not the target
strip. Blizzard's fixed 35% and the CVar the player can switch off are accepted costs, and
`/myui audit` has to report which state that CVar is in.

See the new question raised back about this in `DESIGN-QUESTIONS.md` — under our own C6
inference, the channel is invisible for most of the time low health actually happens.

---

## Phase 1 acceptance: passed, 2026-08-27 16:08

**15 of 15**, `v0.2.0-phase1`. Every frame at its SPEC anchor, both threshold ticks
visible, 3.0000 physical pixels per unit, nothing moving between show and release.

It took three runs, and **every failure across all three was in the test tooling, not the
addon**. Worth recording, because the same mistakes are available in every later phase:

| Run | Result | What was actually wrong |
|---|---|---|
| 15:45 | 6/9 | Steps asked to see the health number, target labels and the dark tick — none of which Phase 1 draws, because it has no data and the dark tick reads against a fill that does not exist at value 0 |
| 15:57 | 10/15 | `/myui show` is a toggle and the script said "type /myui show", so running it when already on turned everything *off*. The auto-check compared only the addon's intent, so it passed over an unchanged screen. The debug fill was 0.65, burying the 40% tick under a 92%-white fill |
| 16:08 | **15/15** | — |

Five rules came out of it, all now enforced by tests:

1. **One assertion per step.** A compound question cannot be answered — a fail says
   something was wrong without saying what.
2. **Only ask for what the phase draws.** Debug mode supplies placeholder text and a
   nominal fill so geometry is judgeable before data exists.
3. **Never depend on a toggle.** Steps use explicit `on` / `off`.
4. **An auto-check must verify the screen, not the intent.** It reads the frame's real
   alpha, falling back to intent only when the alpha is genuinely secret, and says which.
5. **Not-done is not a failure.** Steps await the command that performs them and read
   "waiting" until it runs.

The debug fill is 0.30 for a reason worth keeping: SPEC says the 20% tick reads against the
fill and the 40% against the empty trough, so only a value between them shows both.

## Phase 1: two readings of SPEC worth your eye

Both are recorded in `Frames.lua` next to the code that acts on them.

**The rail's resting alpha.** SPEC § 2 gives it as "hairline 0.14, dots per § 6" — a
per-element alpha, not a frame one. 0.14 is exactly the `trough` colour in § 7, so the
hairline takes that palette entry and carries the alpha in its colour, leaving the Rail
container to rest at 1 for the reveal engine to claim. If the intent was a container
alpha of 0.14, the dots would all be dimmed by it too.

**Which side of the hairline the dots sit on.** § 6 gives the dots' vertical positions
(first 40 down, 26 spacing) but not their horizontal relationship to the hairline. The rail
sits at x = 20, so rightward is the only direction with room. Not built yet — Phase 3 — but
the container is a dot wide in anticipation.

---

## What Phase 0 actually ships

Nothing visible. The harness, and the machinery every later phase is graded against:

- **`Guard.Send`** is the only sanctioned route from a value to a widget. A plain value
  passes to any setter; a secret is admitted only to `SetAlpha`, `SetVertexColor` or
  `SetValue`, each verified against the generated API docs. Anything else is refused —
  including sinks nobody has checked, because an unverified sink is a guess.
- **`Guard.Refuse`** always fails. PLAN.md says to stop and raise rather than work around;
  this makes stopping easier than not.
- **`Registry`** owns every frame's resting alpha. Nothing else may.
- **`rules_lint.py`** — seven rules, each proven to fire by a fixture.
- **The mock enforces the taint split.** `SetScale` and `SetColorFill` throw on a secret
  exactly as the client does, so the guard's refusals are tested rather than asserted.

A mock's defaults are assertions about the real system. Every behaviour in `mockwow.lua`
traces to a citation in `API-NOTES-12.1.md`.

---

## If picking up cold

1. Read `CONTINUATION.md`, then this file, then `API-NOTES-12.1.md`, then the **amended**
   handoff at `~/Development/UI - Rebar/in/current` — `HANDBACK-RESPONSE.md`
   first, since it says what changed and why, then `RULES.md` and `SPEC.md`.
2. `./smoke.sh`, and `git tag -n99` for what each delivered phase actually contains.
3. Phase 4: bars and low health, now including the summon hook.

A phase is delivered when smoke is clean, `/myui audit` is clean in game, PLAN.md's
acceptance test for it passes in game, and the tag is cut. See README for the convention.
