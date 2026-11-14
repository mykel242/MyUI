# Continuation brief

For a context picking this up cold. Read this, then `API-NOTES-12.1.md`, then the **amended**
handoff — `HANDBACK-RESPONSE.md` first, since it says what changed and why, then `RULES.md`
and `SPEC.md`. `STATUS.md` has the current-state detail; this file has the things that are
not obvious from the code.

---

## What this is

**MyUI** — a World of Warcraft Retail 12.1 HUD implementing a design handoff. The premise:
*at rest the screen is the game.* No frame is permanent; everything is summoned by cursor
proximity, a state change, low health, or a peek key, and returns to a resting alpha. Since
the amendment it also **clears Blizzard's own interface**, and can put it back.

Three directories, all separate git repos:

| Path | What |
|---|---|
| `~/Development/MyUI` | **This.** The addon. |
| `design/current` (in this repo) | The design handoff being built: `SPEC.md`, `PLAN.md`, `RULES.md`, and an HTML mock. A symlink into `design/rounds/`. Spec changes are commits here, alongside the code they govern. `~/Development/UI - Rebar` is a read-only archive. |
| `~/Development/Rebar` | A *different* addon by the same author: frame-layout tooling, `editmode.py`, and `API-NOTES-12.1.md`. Source of `Compat.lua` and much ground truth. |
| `~/Development/cc-addon` | `wowaddons.py` — deploys this addon to the live game folder. |

The design is called **Rebar**; the addon is called **MyUI** because the layout project
already owns that name, slash prefix and SavedVariables.

---

## Where it stands

Phases 0–3 delivered and accepted in game, each with an annotated tag.

```
v0.1.0-phase0   skeleton and compliance harness
v0.2.0-phase1   anchors and frame registry          15/15 in game
v0.3.0-phase2   the reveal engine                   16/16 in game
v0.4.0-phase3   the rail                            17/17 in game
```

**The handoff then came back amended.** All fourteen findings answered, `SPEC.md`,
`RULES.md` and `PLAN.md` revised in place. Everything the amendment changed in the accepted
phases is now built and offline-green at 476 checks, but **none of it has been re-run in
game**:

- the modifier reveal channel is cut, and the hold binding with it;
- the arbiter's tie precedence is SPEC's rather than ours, so a peek during combat is now
  credited to combat;
- the palette collapsed from fourteen colours to thirteen;
- the rail's dots carry a 1px dark edge, drawn as a sibling texture so the dot's 0.4 cannot
  reach it;
- and a new `Sources.lua` replaces `/myui notify` with SPEC § 6's seven real sources.

**Next: Phase 4 — bars and low health.** SPEC § 2's internals and § 3, now including the
low-health summon hook. PLAN calls it the riskiest compliance surface in v1 and says to
audit after each sub-step, not at phase end.

`git tag -n99` reads back what each phase actually contained, including what was verified
in game versus only offline.

---

## The one rule everything hangs on

> **Forwarding a secret value is legal. Inspecting one is not.**

On 12.1 a protected value may be handed to a widget setter or mapped through a curve. It may
never be read into a variable you then compare, measure, sort, or do arithmetic on. The
failure mode is not a visual bug — it is a tainted path that passes on a target dummy and
fails in a raid.

Most published addon source predates 12.1 and does exactly what is now forbidden. Do not
pattern-match from memory.

### How that is enforced

- **`Guard.Send(obj, method, ...)`** is the only route from a value to a widget. A secret is
  admitted only to `SetAlpha`, `SetVertexColor` and `SetValue`, each carrying its doc
  citation. Every other sink is refused — including unverified ones, because an unverified
  sink is a guess.
- **`/myui rules`** prints the contract in game: eight prohibitions and **five** sanctioned
  mechanisms. The fifth — a hook on Blizzard's `LowHealthFrame` — is licensed for one
  purpose only, letting low health summon `SelfStack`. Hooking any other Blizzard frame to
  recover an event is out of bounds; raise it instead.
- **`Guard.Refuse(reason)`** always fails. When the implementation seems to need an
  inspection, call it rather than working around; PLAN says to stop and raise, and this
  makes stopping easier than not.
- **`rules_lint.py`** — seven static rules, each proven to fire by a fixture in
  `test/fixtures/`. Run by `smoke.sh`.
- **`test/mockwow.lua`** models secrets that *throw* on arithmetic, and setters that enforce
  the real taint split — `SetScale` and `SetColorFill` refuse a secret exactly as the client
  does. The guard's refusals are tested, not asserted.

---

## Working agreement

**Every phase ends with an in-game acceptance test.** `/myui test` carries the script for
the current phase; the user works down it and hits **report**, which writes the run to
`MyUIDB.testRuns`. A `/reload` flushes it and it is readable off disk at
`/Applications/World of Warcraft/_retail_/WTF/Account/*/SavedVariables/MyUI.lua`.
**Read the report rather than asking the user to transcribe it.**

A phase is delivered when: `./smoke.sh` clean, `/myui audit` clean in game, PLAN's
acceptance passes in game, and the tag is cut.

### Five rules for acceptance scripts, all learned the hard way and all enforced by tests

1. **One assertion per step.** A compound question cannot be answered — a fail says
   something was wrong without saying what.
2. **Only ask for what the phase draws.** Phase 1 had steps asking to see things it
   correctly did not draw. The debug toggle supplies placeholder text and a nominal fill so
   geometry is judgeable before data exists.
3. **Never depend on a toggle.** Steps use explicit `on` / `off`.
4. **An auto-check must verify the screen, not the intent.** One compared only the
   registry's own numbers and passed over a UI that had not changed.
5. **Not-done is not a failure.** Steps declare the command they await and read *waiting*
   until it runs.

Also: **never ask the user to type while holding a modifier** — on macOS Option inserts
accented characters and Shift turns `/` into `?`. That is what forced transient state to be
recorded and read afterwards (`/myui claims`); the modifier channel is gone now but the
technique outlived it, and the cursor dwell still needs it because the cursor has to leave
the frame to reach the chat box. Steps carry buttons that drop their command into the chat
box.

### The pattern worth internalising

**Almost every real bug in this project was found in game, not by the offline suite.** The
suite verifies what a thing *does*; it misses what it *looks like next to everything else*.
Duplicate toasts, a blinking changeover, unreadable greys, a stale window — all found by
eye. When something fails in game, suspect the test tooling first: in Phase 1 all three
failures were the script's fault, not the addon's.

---

## Ground truth worth not rediscovering

Full citations in `API-NOTES-12.1.md`. The load-bearing ones:

- **`C_CurveUtil.CreateColorCurve()`**, not `CurveUtil`. The wrong spelling returns nil in
  game while every offline test passes.
- **Curve input is a fraction, 0..1**, not a percentage. `Scale.U` and `Guard.Fraction`
  handle the conversions.
- **`UnitHealthPercent(unit, usePredicted, curve)`** returns the *evaluated* result — the
  percentage never enters Lua. Same for `UnitPowerPercent`.
- **A Step curve is a threshold without a branch.** `SetType(Enum.LuaCurveType.Step)`, one
  alpha below a cutoff and another above, forwarded to `SetAlpha`. This is how SPEC § 3's
  discrete moment is built — there is no health macro conditional, so `RegisterStateDriver`
  cannot do it.
- **`SetValue(value, Enum.StatusBarInterpolation.ExponentialEaseOut)`** — the engine
  animates the bar. No OnUpdate, no lerp, no arithmetic.
- **`string.format` is a legal pass-through for a secret.** That is how the health number
  gets drawn.
- **`SetColorFill` and `SetScale` refuse a forwarded secret.** Colour the fill through
  `bar:GetStatusBarTexture():SetVertexColor(...)`.
- **`Bindings.xml` must never be listed in the TOC.** The client loads it by filename;
  listing it double-parses and silently breaks every binding. A test guards this.

---

## Conventions

- **`Scale.U(n)`** converts SPEC's mock-canvas numbers (1707×960) to UI units by ×0.8. Every
  number from the spec is typed verbatim and wrapped in `U()`. `Scale.Hairline()` is one
  *physical* pixel, which is what "1px" means in the spec.
- **`Palette`** is closed at **thirteen** colours. Asking for a fourteenth errors. The one
  colour the addon draws that is not in it is `/myui contrast normal`'s superseded grey,
  which lives as a constant in `Frames.lua` precisely so `Palette.Get` cannot serve it.
- **`Registry`** owns every frame's resting alpha; **`Reveal`** owns every frame's current
  alpha. Nothing else sets alpha on a registered frame.
- **`Sources.lua` is the one file RULES does not govern.** Item quality, free bag slots,
  durability and mail flags are ordinary values, and the amended RULES says so explicitly
  because over-applying the rules produces worse code rather than safer code. Its constraint
  is different and narrower: no source may read a unit value.
- **The arbiter deals only in plain numbers.** Anything curve-driven lives on *child* frames,
  where alpha multiplies down the hierarchy on its own. A secret never enters `Reveal.lua`.
- Comments explain *why*, especially where something looks wrong but is deliberate. Several
  say what was tried first and why it failed — keep that.

---

## Running it

```sh
./smoke.sh                                             # everything offline
cd test && luajit run_tests.lua                        # 426 addon checks
python3 rules_lint.py                                  # 7 compliance rules
python3 rules_lint.py --audit reference/audit/*/       # lint someone else's addon

python3 ~/Development/cc-addon/wowaddons.py --update MyUI    # deploy to the live folder
```

`reference/audit/` holds four cloned addons (oUF, Plater, Cell, ShadowedUnitFrames) —
gitignored, re-clonable, and the source of several findings. `~/Development/Rebar/reference/
wow-ui-source` is Blizzard's 12.1 source; `./fetch-reference.sh` restores it.

---

## Open decisions

`DESIGN-QUESTIONS.md` is the full list. **All fourteen original findings are answered** —
including the two that shaped Phase 4:

1. **Whose job is the empty screen?** — **Rebar's.** New SPEC § 11, new PLAN Phase 6b.
   Player frame filtered by roleset, action bars via an Edit Mode layout, and minimap, chat
   and bags *adopted* into the registry at resting alpha 0 rather than hidden — which also
   sidesteps combat lockdown, since alpha is not protected.
2. **Does low health reveal, or only escalate?** — **It reveals, `SelfStack` only.** The
   step-curve reasoning was accepted and routed around: the hook's show/hide is a plain
   boolean, not a secret, so it may be compared and may claim where the curve's alpha
   cannot.

**The one deviation that had shipped is now the spec.** Contrast defaults to `lift`, and
the amendment adopted that value — `/myui contrast normal` is now a debug affordance showing
the superseded grey, not a restore-to-spec.

Four things are raised back, in `DESIGN-QUESTIONS.md` § E. Two matter to Phase 4:

- **`RULES.md` still says a pulse needs a driver state.** It cannot — the same amendment
  refuted `RegisterStateDriver` for low health, and SPEC § 3 builds the breathe from
  cross-faded frames. `/myui rules` deliberately prints the accurate version instead.
- **`LowHealthFrame` has no hysteresis** — one bare `<= 0.35`, re-evaluated on every
  `UNIT_HEALTH`. SPEC § 3 asks for no dwell in and no timeout out, which puts `SelfStack`
  through a full fade on every crossing of the boundary. A short hold on release is
  proposed and not built.

---

## Phase 4, specifically

SPEC § 2's SelfStack internals and § 3's low-health treatment. The frames already exist at
their anchors from Phase 1; this phase gives them data.

- Health fill colour: `UnitHealthPercent(unit, true, colorCurve)` → `SetVertexColor` on the
  bar's texture. Never `SetColorFill` — it is `AllowedWhenUntainted` and refuses.
- Depleted wash: a second StatusBar with `SetReverseFill(true)` fed the same value. The spec
  asks for an inverted mask, which does not exist.
- Bar value: forward `UnitHealth` to `SetValue` with an interpolation mode.
- Health number: `string.format` on a curve-evaluated result.
- The discrete moment: a Step curve, cross-fading duplicated frames for the two tells that
  need more than alpha.
- **The summon**, new since the amendment: a secure hook on `LowHealthFrame`'s show/hide,
  claiming `SelfStack` and nothing else. It is a plain boolean, so it may claim in the
  arbiter — but see § E2 and E3 in `DESIGN-QUESTIONS.md` before wiring it as literally
  specified. `/myui audit` has to report whether the `doNotFlashLowHealthWarning` CVar has
  the channel switched off.
- The threshold ticks are already built and are static geometry — never computed.

**Audit after each sub-step.** `/myui audit` and `python3 rules_lint.py`, not just at the
end.
