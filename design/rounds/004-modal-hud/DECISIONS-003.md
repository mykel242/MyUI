# DECISIONS — round 003

Made by Mykel on 2026-11-14, resuming after a pause since 2026-08-28. Replaces
`HANDBACK-RESPONSE.md` as the reasoning file for this round. Context, not contract —
where this and SPEC/RULES/PLAN disagree, those win.

The governing image: **metamorphic rock, not conglomerate.** One addon fused into one whole,
not separate pieces held together.

| # | Decision | Why |
|---|---|---|
| 1 | **Cut the rail; keep toasts, add a summonable history** | The rail felt too rigid in play. The toast idea is still liked. HANDBACK-2 H2 showed the rail lossy in practice |
| 2 | **MyUI replaces minimap, chat and bags** with minimal versions of its own | Reverses round 002 SPEC § 10. A cleared screen with nothing in its place leaves the player confused, which is what the project exists to remove |
| 3 | **The old Rebar addon becomes MyUI's layout layer** | It was a separate tool that MyUI only borrowed from. Positions are set once in edit mode, then fixed in play |
| 4 | **ChatQuiet folds into MyUI; HideBarTooltips stays separate** | ChatQuiet already does more than one job (chat and the tracker). HideBarTooltips is published on its own and stays that way |
| 5 | **The name is MyUI** — addon, design and `/myui` | Three things were named Rebar |
| 6 | Keep round 002's reveal engine, compliance rules, palette, and rhythm line in v2 | Fine for now; open to revisiting |
| 7 | **Dependencies: MyUI and Blizzard only** | Third-party code may be read for best practice, never depended on |
| 8 | **Keep the game playable** via `wowaddons.py` environments; develop only in `newui` | Development may pause at any time |
| 9 | **Automate visual tests** — the game takes its own screenshots, tools file and diff them | Removes the log in / stage / screenshot / paste / undo loop |
| 10 | Dev tools are **single-purpose**; Pillow allowed in dev tools only | Lesson from wowaddons.py: no Swiss Army knives |

## HANDBACK-2 rulings

- **H1 — long names over the age.** Moot for the rail. For toasts and the history: the name
  truncates with an ellipsis; the age never yields.
- **H2 — the rail holds a record it can't show.** Answered by decision 1: the history is the
  record, summoned by a key.

## Still open

- Toast placement, stacking and cap; the history view (design round D1).
- The look of MyUI's minimap, chat and bags (D1).
- Which DialogueUI and Plumber features to take on (Mykel's list, D1).
- Whether whispers get a sixth hue, which would be a fourteenth colour.
- `Stow.lua`'s reparenting versus SPEC § 11's filtering, per frame (PLAN R3).
- The Aug 28 work adds `Panel.lua`, but round 002 says slash commands only, no settings panel.
  Keep or cut (PLAN R3).

## D1 answers — 2026-11-14

- **Toasts** appear wherever the toast anchor is placed in edit mode.
- **Minimap:** square and minimal; Blizzard and addon minimap buttons gathered into one menu.
- **Chat:** mostly ignored unless he interacts with a toast; can be summoned, filtered by
  channel, with a log.
- **DialogueUI:** "just great" — taken on as a module, from its behaviour.
- **Plumber:** too big to consider right now — declined.

- **Chat + history:** one view, provisionally — "let's try that, not certain yet."
- **Screens:** must play well on laptop and widescreen — part of the original concept.

- **Ultrawide:** core HUD inside a centred 16:9 focus area — confirmed.

## D1 answers, continued — 2026-11-14

- **DialogueUI v1:** quest and NPC dialog window; keyboard choices; its dark theme and look.
- **Bags:** big topic, saved for later.
- **Whispers:** purple. **Palette stays at thirteen:** whispers take the existing violet;
  achievements move to amber, beside quest completion.
- **DialogueUI look:** rebuilt flat, in MyUI's palette. No texture exception.

## Source control — 2026-11-14

- **Remote:** Forgejo on Cronus, mirrored to GitHub.
- **The spec moves into the MyUI repo** (`design/`); `UI - Rebar` is archived.
- **GitHub mirror is public.**
- **Licence: MIT.**

## R3 rulings — 2026-11-14

On `R3-INVENTORY.md`:

1. **Merge `wip/aug28` and cut from it** — it is ahead of `main`, not beside it.
2. **The rail goes**; its toast moves to `Toast.lua` at `ToastAnchor`. `Log.lua` is the
   history's record and `Center.lua` the summoned view. `Sources.lua`: achievements → amber,
   "You died" (red) dropped, whispers → violet added.
3. **Stow, per frame**, as recorded in SPEC § 11.
4. **`Panel.lua`** stays as a dev aid opened by `/myui panel` (no minimap button); it becomes
   MyUI's entry in the § 14 minimap menu once that exists.
