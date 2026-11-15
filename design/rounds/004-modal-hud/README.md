# Handoff: MyUI — a WoW UI addon that isn't there

## Overview

MyUI is a Retail 12.1 interface addon built on one premise: at rest the screen is the game.
Every element is summoned by cursor proximity, a state change, low health, or a peek key, and
returns to a resting alpha when that stops being true. Notifications arrive as toasts and are
kept in a history you can summon. MyUI clears Blizzard's own interface, draws minimal
replacements for the minimap, chat and bags, and can put everything back.

One addon, depending only on itself and Blizzard. The old Rebar layout addon and ChatQuiet
are folded in as modules.

## Round 004 — the modal HUD (2026-11-14)

The HUD becomes a function of WoW's mode. Bars centred under the character with ALT / CTRL /
ALT+CTRL pages, cooldowns and "on you" wings on the bars' rows, group frames on the right with
hover cards you pin by shift-click, a click map (target, pin, focus, cast, menu), a target strip
in three kinds, a boss mode, the map on a key. SPEC § 16–22; reasoning and the mock in
`DECISIONS-004.md`; the MVP steps reshaped in PLAN.

## Read in this order

1. **RULES.md** — the 12.1 Secret Values compliance contract, plus the dependency rule.
2. **SPEC.md** — the authoritative visual and behavioral spec.
3. **PLAN.md** — working environment, the Resume track (R0–R5), then the remaining phases.
4. **DECISIONS-004.md** and **DECISIONS-003.md** — why rounds 004 and 003 changed what they did.
   Context, not contract.
5. `HANDBACK-RESPONSE.md` — round 002's reasoning, kept for history.

## Status — round 003, resuming after a pause (2026-11-14)

Phases 0–3 were built and accepted in game in August, then work paused on 2026-08-28 with a
large amount of it uncommitted. This round:

- **Cuts the rail.** Toasts stay; a summonable history replaces the dots (SPEC § 6).
- **Replaces** minimap, chat and bags instead of only quieting them (SPEC § 2, § 10, § 11).
- **Folds in** the old Rebar addon as the layout layer (§ 9) and ChatQuiet as the Chat and
  Tracker modules (§ 12–13). HideBarTooltips stays separate.
- **Renames** everything MyUI; `/myui` is the only prefix.
- **Adds** a dependency rule: MyUI and Blizzard only (RULES).
- **Adds** a Resume track before Phase 4: secure the uncommitted work, check the patch, build
  an automated screenshot harness, reconcile, fold in Rebar and ChatQuiet (PLAN R0–R5).

Open items needing Mykel are listed at the end of DECISIONS-003.md.

## About the design files

`Rebar Proposal 2.dc.html` (round 002, carried over unchanged) is a **design reference created in HTML** — a prototype showing
intended look and behavior. It is not production code and nothing in it should be ported.
The implementation target is Lua and the WoW frame API.

**Important:** the HTML contains multiple rounds of exploration, including options that were
argued against and rejected. Treat SPEC.md as the only source of decisions. If the mock shows
something SPEC.md does not mention, it was not chosen.

The mock's bare backdrop is now confirmed as MyUI's *output* (SPEC § 11), not a configured
client. It is the one thing in the mock that reads as scenery and is actually a requirement.

Open the HTML in a browser and jump to the `ROUND 4` section for the mechanisms this build
rests on. Sections `4a`, `4b`, and `4c` show the low-health and rhythm-line reasoning;
`SPEC.md § 3` records the resolution (a combination of 4a and 4b).

## Fidelity

**High-fidelity.** Colours, alphas, sizes, anchors and motion timings in SPEC.md are final and
should be matched exactly. The complete palette is **thirteen** RGBA float values and the
addon must not introduce a fourteenth.

Two exceptions, both settled: tertiary text ships at `173,177,184` rather than the originally
specified `115,119,126`, which tested unreadable over terrain — and motion timings (120ms in,
260ms out, 140ms dwell, 3s peek) were guessed from feel and are explicitly open for tuning in
Phase 6.

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
- One low-health cutoff, not three — and it is a step curve, not a driver state.
- MyUI clears Blizzard's interface and replaces minimap, chat and bags. Reversible, and out-of-combat only.
- Slash-command configuration only in v1; no settings panel.
- The rhythm line ships in v2, not v1. It is fully specified in SPEC.md § 5 and scheduled as
  PLAN.md Phase 7.

## Files

| File | What it is |
|---|---|
| `RULES.md` | 12.1 compliance contract |
| `SPEC.md` | Authoritative design spec |
| `PLAN.md` | Build phases and acceptance tests |
| `DECISIONS-003.md` | This round's decisions and reasoning |
| `HANDBACK-RESPONSE.md` | Round 002's answers to the phase 0–3 handback |
| `Rebar Proposal 2.dc.html` | Visual reference (contains rejected options — see above) |
| `support.js` | Runtime for the HTML reference only; irrelevant to the addon |
| `assets/game-bg.png` | Backdrop used by the mock |
| `assets/bloom-32.png` | Cut texture, kept for reference only — do not implement |
| `assets/bloom-alpha-ladder.png` | Evidence for the cut: four opacities on the real backdrop |
| `assets/bloom-size-ladder.png` | Evidence for the cut: three sizes plus removal |

## Assets

**The addon needs no asset files.** Every element is a solid fill or a 1px hairline.

A soft bloom behind the (now cut) rail dots was specified and then cut — it tested invisible against the
real game backdrop at every size and opacity tried. `assets/bloom-32.png` and the two ladder
images document that test; the texture is retained for reference only and must not be
implemented. See SPEC.md § 6.
