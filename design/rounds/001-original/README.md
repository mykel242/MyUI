# Handoff: Rebar — a WoW UI addon that isn't there

## Overview

Rebar is a Retail 12.1 interface addon built on one premise: at rest the screen is the game.
No frame is permanent. Every element is summoned by cursor proximity, a held modifier, a state
change, or a peek key, and returns to a resting alpha when that stops being true. A single
left-edge rail holds anything that happened while you weren't looking.

## Read in this order

1. **RULES.md** — the 12.1 Secret Values compliance contract. Read before writing any Lua.
2. **SPEC.md** — the authoritative visual and behavioral spec.
3. **PLAN.md** — phased build order with acceptance tests.

## About the design files

`Rebar Proposal 2.dc.html` is a **design reference created in HTML** — a prototype showing
intended look and behavior. It is not production code and nothing in it should be ported.
The implementation target is Lua and the WoW frame API.

**Important:** the HTML contains multiple rounds of exploration, including options that were
argued against and rejected. Treat SPEC.md as the only source of decisions. If the mock shows
something SPEC.md does not mention, it was not chosen.

Open the HTML in a browser and jump to the `ROUND 4` section for the mechanisms this build
rests on. Sections `4a`, `4b`, and `4c` show the low-health and rhythm-line reasoning;
`SPEC.md § 3` records the resolution (a combination of 4a and 4b).

## Fidelity

**High-fidelity.** Colours, alphas, sizes, anchors and motion timings in SPEC.md are final and
should be matched exactly. The complete palette is fourteen RGBA float values and the addon
must not introduce a fifteenth.

## Why this handoff is shaped unusually

The hard constraint on this project is not visual. WoW 12.1's Secret Values system means the
failure mode for a mistake is a tainted execution path that can pass testing and fail in a
raid — not a layout that looks wrong.

The relevant point for an AI-assisted build: the overwhelming majority of published addon
source predates 12.1 and does precisely what is now forbidden — reads unit health, computes a
percentage, branches on a threshold. That pattern is the obvious solution and it is wrong here.
RULES.md exists to make the prohibition explicit and to name the legal alternative in each
case, and the Phase 0 compliance harness exists so that a violation fails loudly at the moment
it is written.

The governing principle, stated once: **forwarding a secret value is legal, inspecting one is
not.**

## Scope decisions already made

- Retail 12.1 only. No Classic fallback — neither `ColorCurveObject` nor Cooldown Manager
  exists there, so supporting it would be a different addon.
- One low-health driver state, not three.
- Slash-command configuration only in v1; no settings panel.
- The rhythm line ships in v2, not v1. It is fully specified in SPEC.md § 5 and scheduled as
  PLAN.md Phase 7.

## Files

| File | What it is |
|---|---|
| `RULES.md` | 12.1 compliance contract |
| `SPEC.md` | Authoritative design spec |
| `PLAN.md` | Build phases and acceptance tests |
| `Rebar Proposal 2.dc.html` | Visual reference (contains rejected options — see above) |
| `support.js` | Runtime for the HTML reference only; irrelevant to the addon |
| `assets/game-bg.png` | Backdrop used by the mock |
| `assets/bloom-32.png` | Cut texture, kept for reference only — do not implement |
| `assets/bloom-alpha-ladder.png` | Evidence for the cut: four opacities on the real backdrop |
| `assets/bloom-size-ladder.png` | Evidence for the cut: three sizes plus removal |

## Assets

**The addon needs no asset files.** Every element is a solid fill or a 1px hairline.

A soft bloom behind the rail dots was specified and then cut — it tested invisible against the
real game backdrop at every size and opacity tried. `assets/bloom-32.png` and the two ladder
images document that test; the texture is retained for reference only and must not be
implemented. See SPEC.md § 6.
