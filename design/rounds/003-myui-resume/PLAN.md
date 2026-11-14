# PLAN — build order, round 003

Every phase ends with an in-game acceptance test and a clean `/myui audit`. Do not start a
phase until the previous one passes. Do not build ahead.

Round 003 inserts a **Resume track (R0–R5)** before the remaining round-002 phases. The work
paused on 2026-08-28; the client has patched since, and a large amount of work was never
committed. Nothing new is built until the ground under it is confirmed.

| Decision | Round 003 answer |
|---|---|
| Name | **MyUI** — addon, design, slash prefix `/myui` |
| Notifications | Toasts + summonable history. **Rail cut** |
| Minimap, chat, bags | **Replaced** by MyUI's own minimal versions |
| Old Rebar addon | Folded in as the layout layer |
| ChatQuiet | Folded in as Chat + Tracker modules, then retired |
| HideBarTooltips | Stays separate; never a dependency |
| Dependencies | MyUI and Blizzard only |
| Low health, reveal channels, palette, rhythm line in v2 | Unchanged from round 002 |

---

## Working environment — read before every session

The game is kept playable at all times through `wowaddons.py` environments
(`~/Development/cc-addon`).

- **`newui` is the only environment development touches.** It holds MyUI, the old Rebar
  addon, `!BugGrabber` and `BugSack`.
- `nyx-minimal` and `raid` are **play environments. Never modify them.**
- **Never switch environments.** Switching needs the game closed and is Mykel's call.
- After editing code: `python3 wowaddons.py --update MyUI` (it copies; nothing is
  symlinked), then Mykel presses the reload key.
- **Freeze `newui` before each phase**, so every phase has a rollback point.
- To pause development, Mykel quits, runs `--env nyx-minimal`, and plays.

---

## R0 — Secure the ground

1. Freeze `newui`.
2. MyUI has ~3,700 lines of **uncommitted** work dated 2026-08-28 (`Log.lua`, `Center.lua`,
   `Stow.lua`, `Chat.lua`, `Panel.lua`, `Sources.lua`, and edits across 16 other files), plus
   an untracked `HANDBACK-2.md`. Commit it **exactly as found** on a branch `wip/aug28` — no
   cleanup, no judgement yet. That happens in R3.
3. The Aug 28 work cites a "Round 5" that lives in `in/000 - rebar proposal 2` and was never
   taken in through `./rebar intake`. Note it in `STATUS.md`; do not build from it.

4. **Remote.** Create `MyUI` on Mykel's Forgejo (on Cronus, the same host as `cc-addon`) and
   push `main`, `wip/aug28` and every tag. Forgejo push-mirrors to GitHub `mykel242/MyUI`;
   Mykel sets up the mirror and its token — do not handle the token.
   **The GitHub mirror is public.** Before the first push, scan every branch for personal data
   (character and realm names, WTF or SavedVariables contents, local paths) and report it to
   Mykel rather than pushing. Rebar already keeps its profiles outside the repo for this reason.
   `reference/` (third-party addon source read for best practice) is already gitignored and
   must stay that way — it is other people's code and never goes into a public repo. MyUI has
   no licence file: add **MIT** (as ChatQuiet), `## X-License: MIT` in the TOC, before the
   first public push.
5. **Bring the spec home.** Copy `UI - Rebar/in/` into `MyUI/design/rounds/` (keep the round
   folders as they are), point `design/current` at `003-myui-resume`, and update every doc
   that names `UI - Rebar/in/current` (`CONTINUATION.md`, `STATUS.md`, `README.md`) to
   `design/current`. `UI - Rebar` becomes a read-only archive with a README pointing here.
   From now on, spec changes are commits in MyUI, alongside the code they govern.

Source control from here: `main` always loads in game; one branch per phase
(`phase/r2-harness`), merged after acceptance; tags continue the existing scheme, e.g.
`v0.5.0-r2`. Approved screenshots are committed as cropped frame boxes, not full screens.
**Ask Mykel before every push.** After R4 and R5, the Rebar and ChatQuiet repos are archived
with a README pointing to MyUI.

Git in this setup needs file deletion allowed (for its lock files). If it is refused, stop and
ask Mykel rather than working around it.

**Acceptance:** `git status` clean; the freeze shows in `--freezes`; Forgejo has every branch
and tag; MyUI's docs point at `design/current`.

---

## R1 — Patch check

The build targets TOC `120100`; ChatQuiet already lists `120105, 120107`.

1. Read the client version; refresh reference source with Rebar's `fetch-reference.sh`.
2. Diff the API surface MyUI and Rebar use against `API-NOTES-12.1.md`. Record changes there.
3. Update the TOC. Run `./smoke.sh`.

**Acceptance:** a written list of API changes since August (an empty list is a result); MyUI
loads in game with zero Lua errors.

---

## R2 — Capture harness

The goal is to remove Mykel from the screenshot loop: he presses one key, and named, diffed
screenshots land in the repo. Each tool does **one job** — no multi-purpose tool.

| Piece | Where | Its one job |
|---|---|---|
| `MyUI_Test` | Addon, `newui` only | Run a suite: set each UI state (fake data where possible), wait, call `Screenshot()`, record test name and every frame's rect in a manifest |
| Reload key | Keybinding | Reload and start the queued suite on load |
| `watch_shots.py` | Mac | Move new screenshots into the repo, named by test |
| `diff_shots.py` | Mac, Pillow | Compare **only the frame rects** from the manifest against approved shots; write a highlighted diff |
| `approve_shots.py` | Mac | Promote a shot to the approved baseline |
| `check_deps.py` | Mac | Fail on any `.toc` dependency outside MyUI and Blizzard |

- `MyUI_Test` depends on MyUI. That is allowed: both are ours.
- **Pillow is allowed in dev tools only.** Nothing that ships uses it.
- Turn `TESTING-PHASE*.md` (MyUI and Rebar) into suites, so re-verification needs no hand steps.
- Test in a quiet spot with a fixed camera; the rect-only diff ignores the world behind.
- The manifest records resolution and UI scale; **approved shots are kept per screen shape**
  (laptop, ultrawide), and a phase passes only when both pass (SPEC § 15).
- **Login stays manual.** Nothing automates Battle.net sign-in or types into the client.

**Acceptance:** from a logged-in character, one keypress produces every suite's shots, named
and diffed, with Mykel touching no files; Claude reads the results from the repo.

---

## R3 — Reconcile the Aug 28 work with round 003

1. Inventory what each uncommitted file does, against SPEC.
2. Keep what serves toasts + history (`Log.lua`, `Center.lua`, `Sources.lua` are the likely
   keepers). Remove the rail's dots and column.
3. `Stow.lua` reparents Blizzard frames; SPEC § 11 filters and hides. Recommend one technique
   per frame, with reasons.
4. **Report to Mykel before deleting anything.** His ruling goes into SPEC.

**Acceptance:** Mykel's ruling recorded; harness suites green; merged to `main`.

---

## R3b — Clear the screen, early (added 2026-11-14)

Pulled forward from Phase 6b at Mykel's call: with toasts and the history in, MyUI's frames
overlap the Blizzard elements they stand in for. SPEC § 11's clearing, **minus the
replacements**:

1. Player frame **filtered** (roleset), out of combat only — its first in-game test (API-NOTES § 7).
2. A `MyUI` Edit Mode layout with the bars, target, cast bar and buffs off; the previous
   layout's name saved, so switching back is exact.
3. Chat, minimap and bags **adopted**: registered at resting alpha 0, revealed by the engine;
   chat also on an incoming whisper, held 8s. Alpha only.
4. `/myui restore` undoes all three, combat-safe, and says what it undid.

Everything queues on `InCombatLockdown()` and flushes on `PLAYER_REGEN_ENABLED`. MyUI's own
minimap, chat view and bags stay in Phase 6b; each lands before its stand-in is stowed.

**Acceptance:** a harness suite shoots the cleared screen and the restored one; nothing
protected is touched in combat (forced-combat test); `/myui restore` returns the exact prior
layout; zero Lua errors.

---

## R4 — Fold Rebar in as the layout layer

SPEC § 9. Port the grid, snapping and persistence into MyUI; inspector and overlap behind
`/myui dev`. Migrate positions from Rebar's SavedVariables. Remove the Rebar addon from `newui`.

**Pixel-exact scale per screen** (added 2026-11-14). Rebar set `uiScale 0.8` for the 5120×2880
display, where it is exactly 3 px/unit; it is one account-wide number, the maximised window
takes whatever display it opens on, and nothing recomputed it — 2.33 px/unit on the laptop
panel, where Mykel also found **everything too small to read** (2026-11-14).

So **readable first, then crisp.** On login and on a display change, out of combat, the
layout layer takes a target size (default: Blizzard's own, uiScale 1.0, i.e. height ÷ 768
px/unit), rounds it to the nearest whole number of physical pixels per unit, and applies that
scale to `UIParent` — which may sit just past the cvar's 1.0 ceiling. Laptop 3456×2234:
2.91 → **3 px/unit, scale 1.031**. 5120×2880: 3.75 → 4 (or 3 at 0.8 if the player prefers the
smaller size). It reports what it chose; the player can set the target size or pin a scale.
Never the nearest-smaller step for crispness alone: 2 px/unit on the laptop (0.6876) is
crisp and unreadable.

**Acceptance:** saved positions survive the migration; Rebar's never-run drag-snap test
passes; the grid is pixel-exact per the harness **on every screen it runs on**, and the
harness's `pixel-perfect` check passes; `check_deps.py` clean.

---

## R5 — Fold ChatQuiet in

SPEC § 12–13. Chat chrome and Tracker modules, alpha only. ChatQuiet stays in the play
environments until Mykel retires it.

**Acceptance:** chat chrome hides until hover; an alerting tab stays visible; the tracker
hides in combat but not on Mythic+ trash; no taint reported.

---

## D1 — Design round (Mykel, not the build)

Before Phase 4. Mocked as Design artifacts and returned as round 004:

**Partly answered 2026-11-14** — see DECISIONS-003 § D1 answers and SPEC § 6, § 14.
Remaining:

- Chat and the notification history as one view or two.
- Bags — deferred, not part of D1.
- Mocks of the minimap, its button menu, toasts, and the chat / history view.

The build does not invent these. Where one is needed and missing, raise it.

---

## Phases 4–7 — from round 002, renamed

- **Phase 4 — Bars and low health.** As round 002, `/rebar` read as `/myui`. Riskiest
  compliance surface in v1; audit after each sub-step.
- **Phase 5 — Edit mode.** Now SPEC § 9, on top of the R4 layout layer.
- **Phase 6 — Polish and persistence.** As round 002.
- **Phase 6b — The replacements.** The D1 minimap, chat view and bags; each replaces its
  adopted Blizzard frame (§ 11's clearing itself moved to R3b).
- **Phase 7 (v2) — Rhythm line.** Unchanged.

Every phase now adds its acceptance test as a harness suite, not a hand-run script.

---

## Standing instructions for the whole build

- RULES.md is read before every phase, not just at the start.
- Any time the implementation seems to require inspecting a value, stop and raise it.
- Do not implement anything present in the HTML reference but absent from SPEC.md.
- Prefer no feature to a non-compliant feature.
- Acceptance is the deliverable. Almost every real bug in phases 0–3 was found in game; when
  something fails in play, suspect the test script first.
- Read shipping addons for the same client version before writing a mechanism — to learn,
  never to copy or depend on.
- **Ask before adding scope.** A gap in the spec is a question for Mykel, not a design decision.
