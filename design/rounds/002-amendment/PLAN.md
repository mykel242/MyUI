# PLAN — build order

Every phase ends with an in-game acceptance test and a clean `/rebar audit`. Do not start a
phase until the previous one passes. Do not build ahead.

Defaults recorded here reflect the five scoping decisions; if the user overrides one, the
affected phases are noted.

| Decision | v1 answer |
|---|---|
| Low-health treatment | Combined: colour curve + step curve + summon hook (4d, amended) |
| Low health summons? | Yes — `SelfStack` only, via the fifth mechanism |
| Rhythm line in v1? | **No** — deferred to v2 |
| Discrete cutoffs | One |
| Reveal channels | Three — proximity, peek, state. **Modifier cut** |
| Screen clearing | Rebar's job — filter, hide, adopt (SPEC § 11). New Phase 6b |
| Config surface | Slash commands only |
| Target | Retail 12.1 only, declared in TOC |

---

## Phase 0 — Skeleton and compliance harness

TOC with retail-only interface version, addon namespace, saved variables, and the guard
described in RULES.md § Compliance harness. `/rebar audit` and `/rebar rules` both working.

**Acceptance:** `/reload` clean, zero Lua errors, nothing visible on screen.

Do not skip this. It exists because the most likely failure on this project is silent taint,
and a harness built first turns that into a loud error at the moment it is introduced.

---

## Phase 1 — Anchors and frame registry

Create every frame from SPEC.md § 2 at its permanent anchor with its resting alpha. No
behavior, no reveal logic, no data. A debug toggle forces all frames to alpha 1.

Position is fixed forever in this design — muscle memory is the whole argument for allowing
things to be invisible — so it must be correct before anything animates.

**Acceptance:** debug toggle shows every frame; positions and sizes match the mock; audit
lists each frame with the resting alpha from the spec table.

---

## Phase 2 — Reveal engine

The channels from SPEC.md § 4, resolving through **one arbiter** that computes a single
target alpha per frame. Frames do not manage their own visibility.

**Amended after build:** the modifier channel is cut, so this is three channels at build time
and four once the low-health summon lands in Phase 4. Remove the modifier bindings and the
keybinding escape hatch that was added for them.

This is the heart of the addon. Built piecemeal it becomes unmaintainable, and every later
phase depends on it, so it gets its own phase with nothing else in it.

**Acceptance:** each channel drives a test frame in isolation; overlapping claims resolve
predictably (highest wins); releasing all claims returns the frame to its resting alpha, not
to zero; 32-unit zone (25.6 converted) and 140ms dwell both verified by brushing past; no modifier key
reveals anything.

---

## Phase 3 — Rail

Moved ahead of the bars deliberately. The rail touches no protected data, so it is the safest
place to build momentum and it exercises the reveal engine hard without any taint risk.

SPEC.md § 6 — dots, the two-newest text rows, 8-dot cap, "+N more", toast lifecycle.

**The bloom is not in scope and never was** — § 6 cut it permanently and ships two ladder
images as evidence. The line that listed it here was a stale conflict; it is struck.

**Amended after build:** add the 1px dark dot edge as a sibling texture, and wire the seven
real notification sources from § 6 in place of the test command.

**Acceptance:** eight simultaneous notifications cap correctly and show "+N more"; a toast
speaks once and collapses after 4s; the rail at rest reads as calm.

---

## Phase 4 — Bars and low health

SPEC.md § 2 internals and § 3. Health, resource, cast, target strip. `ColorCurveObject` on
the fill, a **reverse-filled second bar** for the depleted wash, a **step curve** carrying the
size change, the breathe and the screen hairline, and the **low-health summon hook** claiming
`SelfStack` in the arbiter. Static threshold ticks.

The riskiest compliance surface in v1. Audit after each sub-step, not just at phase end.

**Acceptance:** colour ramps smoothly with no visible step; the reverse bar fills the depleted
region only and stays flush with the fill boundary at every value; the step curve delivers all
three tells at one boundary with no visible cross-fade seam; the summon hook reveals
`SelfStack` and nothing else; with Blizzard's low-health warning switched off, escalation
still works and `/rebar audit` says the summon channel is unavailable; **grep the diff for
arithmetic on any unit value — there must be none.**

---

## Phase 5 — Edit mode

SPEC.md § 9. Ghost outlines with printed resting alphas, grid, per-frame slider, reveal-group
toggle, preview-at-rest.

**Acceptance:** every frame from the Phase 1 registry is findable with the UI at rest;
preview-at-rest matches what the user actually sees in play.

---

## Phase 6 — Polish and persistence

Motion timings from SPEC.md § 8 tuned in-game — 120ms/260ms and the 140ms dwell were guessed
from feel and have never been played. With the modifier channel gone, peek is the only
deliberate summon, so judge whether 3s tap is still right or whether it wants to be hold.
Config persisted across sessions. Slash commands documented in `/rebar help`.

**Acceptance:** timings match the table; settings survive a reload; a fresh install with no
saved variables comes up at spec defaults.

---

## Phase 6b — Clearing the screen

SPEC.md § 11. The player frame filtered by roleset; an Edit Mode layout named `Rebar` with the
bars off, recording and restoring the player's previous layout; minimap, chat and bags adopted
into the registry at resting alpha 0. `/rebar restore` reverses all three.

Sits after Phase 6 because it is the only phase that touches Blizzard's protected frames, and
because everything it clears should already have a replacement drawn. It is ship-blocking for
v1 regardless: the mock's premise is a bare screen.

**Acceptance:** player frame gone and back again; entering combat with a queued hide does not
error and the hide lands on regen; the adopted frames summon from alpha 0 and return; a chat
whisper reveals chat for 8s; `/rebar restore` returns a fresh install to the player's original
layout with nothing left behind; disabling the addon does the same.

---

## Phase 7 (v2) — Rhythm line

SPEC.md § 5. Hidden CDM plus six mirror cells with forwarded values, swipe body, edge cap,
charge subdivision, all-up pulse.

Deferred because it is the most technically novel piece and the addon is coherent without it.
Building it last means its risk is isolated: if the mirror-frame approach turns out to need
rework, nothing else is blocked.

**Acceptance:** cells track real cooldowns with zero reads; charges subdivide; the came-up
edge is visible at 180ms; all-up pulses once; CDM itself remains invisible.

---

## Standing instructions for the whole build

- RULES.md is read before every phase, not just at the start.
- Any time the implementation seems to require inspecting a value, stop and raise it rather
  than working around it. The design was built to avoid that; a need for it means a spec
  misreading.
- Do not implement anything present in the HTML reference but absent from SPEC.md. The mock
  contains rejected variants on purpose.
- Prefer no feature to a non-compliant feature.
- Acceptance is the deliverable, not the paperwork. The phase 0–3 pattern held: almost every
  real bug was found in game, and 426 offline checks passed on a build whose toast drew itself
  twice. When something fails in play, suspect the test script first — in phase 1 all three
  failures were the script.
- Read shipping addons for the same client version before writing a mechanism, not after.
