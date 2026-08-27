# MyUI

A World of Warcraft HUD built on one premise: **at rest, the screen is the game.**
No frame is permanent. Every element is summoned by cursor proximity, a held modifier, a
state change, or a peek key, and returns to a resting alpha when that stops being true.
A single left-edge rail holds anything that happened while you weren't looking.

Retail only. Targets **Midnight 12.1.0**, TOC `120100`. There is no Classic fallback —
neither the curve APIs nor Cooldown Manager exist there, so supporting it would be a
different addon.

Implements the design in `../UI - Rebar/design_handoff_rebar/`. `SPEC.md` there is
authoritative for every colour, alpha, size and timing; the HTML mock beside it contains
deliberately rejected explorations and must not be treated as a reference.

## Status

| Phase | State |
|---|---|
| **-1 — Ground truth** | **Complete.** Four mechanisms verified against Blizzard's 12.1 source; three corrections recorded |
| **0 — Skeleton and compliance harness** | **Delivered** — `v0.1.0-phase0`, verified in game |
| **1 — Anchors and frame registry** | **Delivered** — `v0.2.0-phase1`, 15/15 in game |
| **2 — Reveal engine** | **Delivered** — `v0.3.0-phase2`, 16/16 in game |
| **3 — Rail** | **Built.** 389 addon + 15 lint checks green. In-game acceptance not yet run |
| 4 — Bars and low health | Not started |
| 5 — Edit mode | Not started |
| 6 — Polish and persistence | Not started |
| 7 (v2) — Rhythm line | Not started |

Phase 0 draws nothing. That is the acceptance test: `/reload` clean, zero Lua errors,
nothing visible on screen.

## The one rule

> **Forwarding a secret value is legal. Inspecting one is not.**

On 12.1, a protected value may be handed to a widget setter or mapped through a curve. It
may never be read into a Lua variable you then compare, measure, sort, or do arithmetic on.

The overwhelming majority of published addon source predates 12.1 and does precisely what
is now forbidden — reads unit health, computes a percentage, branches on a threshold. That
pattern is the obvious solution and it is wrong here. The failure mode is not a layout that
looks wrong; it is a tainted execution path that passes testing on a dummy and fails in a
raid.

So the harness comes before the UI, and it has two halves:

- **`MyUI/Guard.lua`** — runtime. `Guard.Send` is the only sanctioned way to hand a value
  to a widget, and it refuses any sink not verified to accept a secret from an addon.
  `Guard.Refuse` is the deliberate escape hatch that always fails, so stopping to raise a
  spec question is the path of least resistance.
- **`rules_lint.py`** — static. Seven rules over the source, including the one PLAN.md's
  Phase 4 acceptance asks for by hand: arithmetic on a unit value, anywhere.

## Layout

```
MyUI/                 the addon
  MyUI.toc
  Compat.lua          safe-read layer: secret-aware, throw-safe
  Core.lua            namespace, versioned SavedVariables, migration ladder
  Guard.lua           the compliance harness -- sanctioned sinks and curves
  Scale.lua           SPEC.md's mock-canvas numbers -> WoW coordinates
  Palette.lua         SPEC.md 7, fourteen colours, closed
  Registry.lua        every frame and the resting alpha SPEC.md gives it
  Frames.lua          SPEC.md 2, built once at its permanent anchor
  Reveal.lua          SPEC.md 4: four channels, one arbiter, the only OnUpdate
  Peek.lua            tap-to-peek and its drain clock
  Rail.lua            SPEC.md 6: dots, rows, the 8-dot cap, the toast lifecycle
  Bindings.xml        peek and hold-to-reveal -- loaded by filename, NOT in the TOC
  Outline.lua         diagnostic boxes: placed wrong, or hidden?
  Testing.lua         the in-game acceptance checklist, per phase
  Rules.lua           the forbidden list, printable in game
  Copy.lua            selectable output window
  Commands.lua        /myui
rules_lint.py         static compliance scan, standard library only
smoke.sh             everything checkable without the client
test/
  mockwow.lua         12.1 mock: secrets throw, setters enforce the taint split
  run_tests.lua       81 addon checks
  test_lint.py        15 checks proving the lint catches what it claims
  fixtures/           one deliberate violation per rule
API-NOTES-12.1.md     verified 12.1 ground truth, with citations
STATUS.md             where things stand; read this first when resuming
```

## Commands

```
/myui help            this list
/myui copy            the last output in a selectable window
/myui show            force every frame to alpha 1, or release back to resting
/myui test            the acceptance checklist; test report | reset | <phase>
/myui outline         diagnostic boxes around every frame, above everything
/myui claims          who is claiming each frame, and every recent transition
/myui modifier        which keys reveal the HUD: alt shift ctrl, or none
/myui notify          feed the rail: <type> [name] [count] | demo | clear | dismiss
/myui rules           the compliance contract, printed
/myui audit           every frame, resting alpha, live alpha, reveal claim
/myui guard           strict | warn | reset
/myui conditionals    which macro conditionals the client's parser knows
/myui version         build and schema
```

Any unambiguous prefix works. `/mui` is an alias.

## Getting output off the machine

WoW's chat frame cannot be copied from, and these reports exist to be read elsewhere.
Every command writes its output to `MyUIDB.lastOutput`, stripped of colour codes.

**Off disk, no copying.** SavedVariables flush on `/reload` or logout, so:

```
/myui conditionals
/reload
```

then read it directly:

```sh
grep -A200 'lastOutput' "/Applications/World of Warcraft/_retail_/WTF/Account"/*/SavedVariables/MyUI.lua
```

**In game.** `/myui copy` opens a selectable window on the previous command's output —
cmd-C, escape. Use this when a reload is inconvenient.

**Chat log.** `/chatlog` writes `_retail_/Logs/WoWChatLog.txt`. It captures the whole chat
stream rather than just this addon, and whether it picks up addon `AddMessage` output is
worth confirming before relying on it.

## Running a phase acceptance test

`/myui test` opens the checklist for the current phase, in game. PLAN.md ends every phase
with an in-game test and those are the only ones that matter — the offline suite cannot see
a frame in the wrong place or a hairline that renders grey. Reading that script off a second
screen is how steps get skipped, so it lives in the addon.

Steps MyUI can verify itself carry a check and answer on their own, marked `auto`. The rest
are the ones that genuinely need your eyes, and those get pass/fail buttons. An auto pass
**latches** — several steps test states that are mutually exclusive by design, so
re-evaluating everything at the end would fail whichever you did first.

Two rules the first live run taught, both enforced by tests:

- **One assertion per step.** A step that bundles four things into one question cannot be
  answered: a fail says something was wrong without saying what.
- **Never ask the user to type while holding a modifier.** It cannot be done — on macOS
  Option inserts accented characters and Shift turns `/` into `?`, so the command never
  runs. Transient state has to be recorded by the addon and read afterwards, which is a
  better test anyway: `/myui claims` shows which channel won on which frame and when.
- **Never depend on a toggle.** A step saying "type /myui show" is unanswerable if the
  command flips state — run when it was already on, it turns everything off. Steps use the
  explicit `on` / `off` forms.
- **An auto-check must verify the screen, not the intent.** Comparing only what the addon
  asked for lets a check pass over a UI that never changed.
- **Test what is painted, not what is behind it.** The window once kept showing "waiting"
  for a step that had already passed, and no test caught it, because every test read the
  results table directly. `Testing.MarkFor` decides and `Testing.RowMark` reports what is
  actually on screen, so both can be asserted.
- **Only ask for what the phase draws.** Phase 1 has no data, so its FontStrings are empty
  and its bars sit at zero — asking whether the health number is visible is asking to see
  something the phase is correct not to draw. The debug toggle now supplies placeholder
  text and a nominal fill so that geometry is judgeable without shipping data.

`report` prints the run and writes it to `MyUIDB.testRuns`, so after a `/reload` the whole
thing can be read off disk. `reset` starts over.

## Phase tags

Every delivered phase gets an annotated tag named after the TOC version:

```
v0.1.0-phase0    skeleton and compliance harness
```

The tag message records what the phase shipped, **what was verified in game versus only
offline**, and what is still open. That distinction is the point — a phase can be green on
116 offline checks and still have never met the client.

A phase is delivered when all four hold:

1. `./smoke.sh` clean
2. `/myui audit` clean in game
3. PLAN.md's acceptance test for that phase passes, in game
4. the tag is cut

There is no remote yet, so tags are local. Add one and `git push --follow-tags`.

## Running the tests

`luajit` (Lua 5.1, matching the game client) and Python 3. Nothing else.

```sh
./smoke.sh
```

Or individually:

```sh
cd test && luajit run_tests.lua     # the addon
python3 rules_lint.py               # the source
python3 test/test_lint.py           # the lint itself
```

These cannot replace the in-game test. What they do cover is the part that is hardest to
see by playing: that a secret cannot reach a setter which would refuse it, and that no
line of shipped source does arithmetic on a unit value.

## Deploying to the live folder

Uses the `cc-addon` tool's dev mode, which archives the working tree the way a release
workflow would, validates it, and only then swaps it in by rename.

```sh
python3 ~/Development/cc-addon/wowaddons.py --dev MyUI ~/Development/MyUI
python3 ~/Development/cc-addon/wowaddons.py --update MyUI
```

It sees tracked files only, so `git add` a new file before building it.

## Related projects

- **`../Rebar`** — a separate addon and offline toolchain for frame layout: viewport grid,
  anchor inspector, and `editmode.py`, which reads and writes Blizzard Edit Mode positions
  with the client closed. Useful for positioning work; `Compat.lua` here is ported from it.
- **`../cc-addon`** — addon updater and the `--dev` deploy path above.
