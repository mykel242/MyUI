# MyUI — status

**Last updated:** 2026-08-27 · `0.1.0-phase0` · 81 addon / 15 lint checks, all green

Target: WoW Midnight 12.1.0, TOC `120100`. Reference source read at build **12.1.0.69497**.

---

## Where things stand

| Phase | State |
|---|---|
| -1 — Ground truth | **Complete.** Three corrections to the handoff, recorded with citations |
| 0 — Skeleton and compliance harness | **Complete offline.** Never loaded by the client |
| 1 — Anchors and frame registry | Not started |
| 2 — Reveal engine | Not started |
| 3 — Rail | Not started |
| 4 — Bars and low health | Not started |
| 5 — Edit mode | Not started |
| 6 — Polish and persistence | Not started |
| 7 (v2) — Rhythm line | Not started |

### The two things waiting on you

**1. Phase 0's in-game acceptance has never been run.** Deploy and `/reload`. Expected:
zero Lua errors, nothing visible on screen, `/myui audit` reporting an empty registry and
a clean guard.

```sh
python3 ~/Development/cc-addon/wowaddons.py --dev MyUI ~/Development/MyUI
python3 ~/Development/cc-addon/wowaddons.py --update MyUI
```

**2. `/myui conditionals` answers the one open design question.** See below.

---

## Open: the low-health driver state has no verified event source

SPEC.md § 3 gives the low-health moment three tells, all hanging on one
`RegisterStateDriver` state. `RegisterStateDriver` resolves through
`SecureCmdOptionParse`, which is engine-side and absent from Blizzard's Lua source, so the
conditional vocabulary cannot be read offline. Nothing resembling `[hp<20]` appears
anywhere, and `C_Secrets` turns out to be pure introspection about *whether* a value is
secret — no comparison, no health predicate.

**Two of the three tells need no event at all.** `SetAlpha` is `AllowedWhenTainted`, so a
scalar curve drives both the 1.60s breathe and the screen-edge danger hairline directly.

**One genuinely does.** The health number's 12pt → 14pt change. `SetScale` is
`AllowedWhenUntainted` and will refuse a forwarded secret, and font size is not alpha.

**To get the result back out:** run the command, then `/reload`. Every command's output is
persisted to `MyUIDB.lastOutput` with colour codes stripped, so it can be read straight off
disk from `WTF/Account/*/SavedVariables/MyUI.lua` with no copying. `/myui copy` gives an
in-game selectable window if a reload is inconvenient.

Run `/myui conditionals` in game. **No combat needed, and no need to be hurt** — it can be
run standing in a city.

It tests each candidate in both plain and negated form against two controls: `[combat]` /
`[nocombat]`, which proves the probe works, and a deliberate nonsense conditional, which
establishes what "the parser does not know this" looks like on the live client rather than
assuming it. A candidate whose signature differs from that unknown baseline is real. Both
halves matter — at full health a conditional that exists and evaluates false looks exactly
like one that does not exist, unless you have measured the difference.

- **If a row reads RECOGNISED** — SPEC § 3 ships as written. Confirm by running it again
  below the threshold; it should flip to a hit.
- **If none does** — the proposed amendment is two stacked FontStrings at 12pt and 14pt,
  cross-faded by curve-driven alpha. Same visual, alpha only, no event, no inspection.
  This is a spec change and wants sign-off, not a silent substitution.

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
2. `./smoke.sh`.
3. Deploy and run Phase 0's in-game acceptance.
4. `/myui conditionals`, and settle SPEC § 3.
5. Then Phase 1: `Scale.lua` and the frame registry from SPEC § 2.
