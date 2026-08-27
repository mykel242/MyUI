# MyUI — status

**Last updated:** 2026-08-27 · `0.1.0-phase0` · 81 addon / 15 lint checks, all green

Target: WoW Midnight 12.1.0, TOC `120100`. Reference source read at build **12.1.0.69497**.

---

## Where things stand

| Phase | State |
|---|---|
| -1 — Ground truth | **Complete.** Three corrections to the handoff, recorded with citations |
| 0 — Skeleton and compliance harness | **Delivered** — `v0.1.0-phase0`, verified in game |
| 1 — Anchors and frame registry | Not started |
| 2 — Reveal engine | Not started |
| 3 — Rail | Not started |
| 4 — Bars and low health | Not started |
| 5 — Edit mode | Not started |
| 6 — Polish and persistence | Not started |
| 7 (v2) — Rhythm line | Not started |

### The one thing waiting on you

**SPEC § 3 needs a decision.** The probe has run; the answer is below. It blocks Phase 4
only — Phases 1 to 3 can proceed either way.

Deploying a build:

```sh
python3 ~/Development/cc-addon/wowaddons.py --update MyUI
```

---

## Answered: no health conditional exists. Decision needed on the alternative.

Probed on a live client 2026-08-27. **`RegisterStateDriver` cannot deliver SPEC § 3's
state** — there is no health macro conditional. The probe also found that an unrecognised
conditional is *ignored* by the parser, so the clause matches; it now tests numeric
candidates as an always-false / always-true pair, which discriminates at any health.

### The alternative: hook Blizzard's `LowHealthFrame`

`LowHealthFrame` is a named global that Blizzard shows when player health crosses 0.35. It
computes that with `UnitHealth() / UnitHealthMax()` — which its untainted code may do and
ours may not. `HookScript("OnShow", ...)` gives us the moment without reading anything.

It satisfies the one principle, but it is **a fifth mechanism, not one of RULES.md's
four.** That is a rules amendment, so it wants your sign-off rather than quiet adoption.

Because it is a genuine event rather than a forwarded secret, everything a driver state
could carry is legal inside it — including the 12pt → 14pt change that no forwarded value
can drive.

What it costs:

| | |
|---|---|
| Threshold | Fixed at **0.35**, not the ~20% SPEC's ticks imply. Blizzard's number, not ours |
| CVar dependency | Off if the player disables `doNotFlashLowHealthWarning`. Detectable at load, so it can warn |
| Shared frame | Also used for the in-combat fullscreen flash, which we cannot distinguish — but that only fires behind a fullscreen panel, where the HUD is hidden anyway |

**If you reject it**, two of the three tells still work with no event: `SetAlpha` takes a
forwarded secret, so a curve drives both the breathe and the screen hairline. Only the
12pt → 14pt change needs the substitute — two stacked FontStrings cross-faded by
curve-driven alpha.

**Either way SPEC § 3 changes**, so this is a decision, not an implementation detail.
Phases 1-3 are unblocked regardless; the answer is only needed by Phase 4.

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
| Coordinates | SPEC's numbers are mock-canvas px on a 1707×960 canvas; × 0.8 gives UI units. "1px" means one physical pixel |
| Low-health treatment | Combined: curve + one driver state (SPEC § 3) |
| Rhythm line in v1 | No — deferred to Phase 7 |
| Config surface | Slash commands only |

The scale factor lives in one constant, added in Phase 1 as `Scale.lua`, so the reading
above is one edit to revisit if it turns out wrong.

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
3. Settle SPEC § 3 — the decision above.
4. Then Phase 1: `Scale.lua` and the frame registry from SPEC § 2.

A phase is delivered when smoke is clean, `/myui audit` is clean in game, PLAN.md's
acceptance test for it passes in game, and the tag is cut. See README for the convention.
