# MyUI — status

**Last updated:** 2026-08-27 · `0.1.0-phase0` · 81 addon / 15 lint checks, all green

Target: WoW Midnight 12.1.0, TOC `120100`. Reference source read at build **12.1.0.69497**.

---

## Where things stand

| Phase | State |
|---|---|
| -1 — Ground truth | **Complete.** Three corrections to the handoff, recorded with citations |
| 0 — Skeleton and compliance harness | **Delivered** — `v0.1.0-phase0`, verified in game |
| 1 — Anchors and frame registry | **Built**, awaiting in-game acceptance |
| 2 — Reveal engine | Not started |
| 3 — Rail | Not started |
| 4 — Bars and low health | Not started |
| 5 — Edit mode | Not started |
| 6 — Polish and persistence | Not started |
| 7 (v2) — Rhythm line | Not started |

### The one thing waiting on you

**Phase 1's in-game acceptance.** Deploy, then:

```
/myui test
```

That opens the checklist in game — fifteen steps, four of which MyUI checks itself.
Work down it, click pass/fail on the ones that need your eyes, then hit **report**
and `/reload`. The report lands in `MyUIDB.testRuns` and `MyUIDB.lastOutput`, so
it can be read off disk with nothing transcribed.

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

## Phase 1: first acceptance run, 2026-08-27

**6 passed, 3 failed — and all three failures were the test script's fault, not the
addon's.** The bars, the target bar and the rail hairline all rendered where SPEC puts
them. What was missing was the health number, the target name and level, and the dark 20%
tick — none of which Phase 1 draws, because it has no data and the dark tick is specified
to read against a fill that does not exist at value 0.

Two fixes, both structural rather than one-off:

- **The debug toggle now supplies placeholder text and a nominal 0.65 fill.** Plain
  constants, cleared on release. Phase 4 replaces them with forwarded values. Without this
  a whole class of geometry is unjudgeable until Phase 4.
- **Every step now asks exactly one question**, and a test enforces it. The failing step
  bundled four assertions, so the report could not say which part was wrong.

Also added `/myui outline` — a green box at TOOLTIP strata around each registered frame.
"The frame is missing" and "the frame is behind your action bars" look identical on screen,
and this separates them. A box with nothing inside it means the geometry is right.

Frame strata is now explicit (`MEDIUM`, which is what was already working). SPEC never
mentions strata, and inheriting whatever the default happens to be is not a decision.

---

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
3. Run Phase 1's in-game acceptance: `/myui test`.
4. Then Phase 2: the reveal engine, four channels through one arbiter.

A phase is delivered when smoke is clean, `/myui audit` is clean in game, PLAN.md's
acceptance test for it passes in game, and the tag is cut. See README for the convention.
