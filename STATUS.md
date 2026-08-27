# MyUI — status

**Last updated:** 2026-08-27 · `0.1.0-phase0` · 81 addon / 15 lint checks, all green

Target: WoW Midnight 12.1.0, TOC `120100`. Reference source read at build **12.1.0.69497**.

---

## Where things stand

| Phase | State |
|---|---|
| -1 — Ground truth | **Complete.** Three corrections to the handoff, recorded with citations |
| 0 — Skeleton and compliance harness | **Delivered** — `v0.1.0-phase0`, verified in game |
| 1 — Anchors and frame registry | **Delivered** — `v0.2.0-phase1`, 15/15 in game |
| 2 — Reveal engine | **Delivered** — `v0.3.0-phase2`, 16/16 in game |
| 3 — Rail | **Built**, awaiting in-game acceptance |
| 4 — Bars and low health | Not started |
| 5 — Edit mode | Not started |
| 6 — Polish and persistence | Not started |
| 7 (v2) — Rhythm line | Not started |

### The one thing waiting on you

**Phase 3's in-game acceptance.** `/myui test` — sixteen steps, three auto-checked.
`/myui notify demo` sends ten at once, which is what the cap and the "+N more"
square exist for.

One step is folded in from Phase 2: the **Hold to reveal** binding shipped after
that phase was accepted, so it has never been verified in game. Bind it to a free
key first.

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
| Low-health treatment | Combined: curve + one driver state (SPEC § 3) |
| Rhythm line in v1 | No — deferred to Phase 7 |
| Config surface | Slash commands only |

The scale factor lives in one constant, added in Phase 1 as `Scale.lua`, so the reading
above is one edit to revisit if it turns out wrong.

---

## Open: SPEC's palette assumes a dark backdrop

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

**Not fixed for the dots.** The two named dots are at full alpha but their hues are pale
pastels, and the six older ones sit at the specified 0.4 — over bright gold they are all
faint. Options, none of them mine to choose:

| | |
|---|---|
| Leave it | 0.4 is what § 6 asks for, and quiet is the design's whole premise |
| 1px dark edge on each dot | Uses `tickDark`, and the "+N more" square already establishes outlines in the rail's vocabulary. Changes the specified 10 × 10 solid dot |
| A ≤14% dark backing behind rows with content | Stays inside § 1's "no fill above 14%", but adds a panel, which sits badly with "no frame is permanent" |

**Worth raising with the designer** — the palette is declared complete, and a design that
is unreadable half the time is a spec problem rather than an implementation one.

---

## Phase 3: what was decided where SPEC is silent

**Nothing produces a notification.** SPEC § 6 specifies the rail completely — dot size,
spacing, hues, cap, the two named rows, the toast's timings — and never says what puts an
item on it. Rather than invent a data binding the design never asked for, Phase 3 ships
`/myui notify` as the source. That is also exactly what the acceptance test needs: eight
at once, on demand. **The real sources are an open design question.**

**Where the toast sits.** Named in § 6 and § 8 with its timings, never with its geometry.
Anchored to the newest dot and extending right, since that is what it collapses into.
Slides 12 in over 180ms. **Wants your eye.**

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

**Worth raising with the designer.** SPEC names Alt and Shift specifically. If a modifier
is unavailable in a normal layout, the channel wants either a different default or a
different mechanism, and that is a spec decision. The hold binding is an addition to § 4,
not something it asked for.

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
source is hooking `LowHealthFrame`. **Still open, still blocking nothing.**

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

1. Read this file, then `API-NOTES-12.1.md`, then the handoff's `RULES.md` and `SPEC.md`.
2. `./smoke.sh`, and `git tag -n99` for what each delivered phase actually contains.
3. Phase 2: the reveal engine, four channels through one arbiter.

A phase is delivered when smoke is clean, `/myui audit` is clean in game, PLAN.md's
acceptance test for it passes in game, and the tag is cut. See README for the convention.
