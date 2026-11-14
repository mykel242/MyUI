# R3 — the Aug 28 work, inventoried against round 003

PLAN R3 steps 1–3. **Nothing has been deleted.** Step 4 is Mykel's ruling, which then goes
into SPEC. Branch `wip/aug28` (`4ae11e6`) compared with `main` at `v0.4.2-r2`.

## The headline

`wip/aug28` is **ahead of `main`, not beside it.** It already implements the round-002
amendment that round 003 builds on: the modifier channel is cut (SPEC § 4), the palette is
thirteen with `textDim` (§ 7), the sources table is wired (§ 6), and the precedence order
matches § 4. Its offline suite passes (617 checks) and the compliance lint is clean. The
three BugSack errors from August (`Sources.lua` failing to load, malformed `Bindings.xml`,
`Panel.lua:237`) are **all fixed** in the final state of the branch.

So the recommendation is to **merge `wip/aug28` into an R3 branch and cut from there**, not
to cherry-pick its files onto Phase 3. `main`'s R0–R2 work (harness, tools, docs) merges
across cleanly in kind; the conflicts are documents plus `Reveal`/`Commands`/`Testing`.

## 1. Inventory

| File | What it does | Against round 003 | Recommendation |
|---|---|---|---|
| `Log.lua` (new, 174) | Per-character notification record in `MyUICharDB`, epoch-timed, 5,000-entry ceiling, nothing expires by age | Exactly § 6 History | **Keep** |
| `Center.lua` (new, 294) | Notification centre: summoned by key, hue filter row, reads `Log` | § 6 names it the starting point for the history | **Keep, re-anchor** from the rail to its own summoned position; take hues from `Palette`, not `Rail.HUES` |
| `Sources.lua` (new, 524) | SPEC § 6 event table → notifications, with latches and burst-merging | § 6, but two rows wrong and one missing | **Keep, fix:** achievements → amber; drop "You died" (red, the sixth hue round 003 cuts); **add whispers → violet** (`CHAT_MSG_WHISPER`, `CHAT_MSG_BN_WHISPER`); post to toasts + log instead of `Rail.Add` |
| `Rail.lua` (+327) | Round 5's uncapped, ageing dot rail; also owns the **toast** | § 6: rail cut, toast kept | **Cut the dots and column. Extract the toast** into `Toast.lua` at a `ToastAnchor` (default position until R4's layout layer lets you place it) |
| `Chat.lua` (new, 475) | Our own edit box via Blizzard's supported focus override; reply key; "hide the chat log" via `Stow` | § 14: chat replaced, summoned; toast opens it | **Keep** the edit box and reply. Hiding the log: see § 3 below |
| `Stow.lua` (new, 158) | Reparents Blizzard frames under a hidden frame, by group (chat furniture, raid manager tab) | § 11 says filter / hide / adopt; Stow was never specified | **Keep as one of the techniques**, for the frames in § 3 only |
| `Panel.lua` (new, 257) | Minimap button + checklist of toggles | Round 002: slash commands only, no settings panel | **Your call** — see § 4 |
| `Reveal.lua` (−172 net) | Modifier channel removed; precedence reordered | Matches § 4 | **Keep wip's version.** Breaks the R2 harness's `modifier` test, which gets replaced by `peek` |
| `Palette.lua`, `Frames.lua` | 13 colours, `textDim`; `/myui contrast normal` keeps the old grey as a debug override | Matches § 7 | **Keep** |
| `Core.lua` | Schema 2 (drops `modifiers`), `MyUICharDB`, settings for sources/chat/stow | Fine | **Keep** |
| `Commands.lua` | Adds `log`, `stow`, `what`, `center`, `chat`, `sources`; drops `modifier` | Fine | **Keep**; `/myui restore` (§ 11) still to come |
| `Bindings.xml` | Drops `MYUI_HOLD`; adds Reply, Centre, What | Matches § 4 | **Keep** |
| `Testing.lua` | In-game checklists updated for the amendment | Largely superseded by `MyUI_Test` suites | Keep for now; retire once suites cover each phase |
| `test/*` | 1,532 lines of offline tests for all of the above | — | **Keep**, then cut the rail tests with the rail |
| `API-NOTES-12.1.md` | New § 7: the chat focus override, and why `ActivateChat` drops it | Still true on 12.1.5 | **Keep**, renumbered after `main`'s § 11 |
| `HANDBACK-2.md`, `DESIGN-QUESTIONS.md` | Questions sent / raised in August | Mostly answered by round 003 | Keep as record |
| `.luarc.json` | Editor globals list | — | Keep |

## 2. Toasts + history: what changes

1. `Toast.lua`: the toast from `Rail.lua`, unchanged in behaviour (speaks once, 4s or dismiss,
   180ms in, 200ms out), anchored at `ToastAnchor`, stacking away from the anchor. Name
   truncates with an ellipsis; the age never yields (H1).
2. `Log.lua` stays the record. `Center.lua` becomes the summoned history; per § 14 it is
   provisionally **the same view** as chat, so it is built to split later.
3. `Rail.lua` goes, with its tests, its harness suite (`myui-p3`), and its approved shots.

## 3. Stow vs § 11, per frame

The rule underneath: **reparent only what is unprotected, that Blizzard keeps showing itself,
and that we have replaced.** Hiding such a frame means fighting Blizzard's own `Show()`
forever; reparenting lets every call succeed with nowhere to draw. But a reparented frame
cannot be summoned, so anything not yet replaced must stay **adopted** (alpha 0, revealed by
the engine) — § 11's "hidden must never mean lost". And nothing protected is ever reparented.

| Frame | Technique | Why |
|---|---|---|
| Player frame | **Filter** (roleset), as § 11 | Protected. Reparenting a secure frame taints its chain. `SetRolesets` is protected (API-NOTES § 7) and `ApplyRolesetFilters` is now combat-blocked (R1): out of combat only. Still needs its first in-game test |
| Action bars | **Edit Mode layout**, as § 11 | Secure. Never reparent |
| Chat log (`ChatFrameN`, tabs, dock, buttons) | **Adopt now; Stow once MyUI's chat view exists** | Unprotected, and Blizzard calls `Show` on it (`ChooseBoxForSend` reads `IsShown`), so Stow is right *eventually* — but until the summoned view exists, a stowed log is a lost log. Edit box stays freed (`Chat.FreeEditBox`) |
| Raid manager tab (`CompactRaidFrameManager`) | **Stow, queued out of combat** | Appears whenever you group, at the left edge; Blizzard re-shows it on every roster change. wip refuses in combat; it should queue and flush on `PLAYER_REGEN_ENABLED` per RULES |
| Minimap | **Adopt** until MyUI's minimap; decide then | Other addons parent buttons to `Minimap`; § 14 gathers them, so stowing the cluster would strand them |
| Bags | **Adopt** (deferred, § 10) | Not replaced |
| Objective tracker | **Alpha only**, as § 13 | ChatQuiet's taint lesson: never touch the manager |

## 4. Rulings needed

1. **Merge `wip/aug28` and cut from it** (recommended), rather than rebuild its pieces on `main`?
2. **The rail:** delete `Rail.lua`'s dots and column, keeping the toast as `Toast.lua`?
3. **Stow, per frame** as in § 3?
4. **`Panel.lua`.** Options: (a) cut it — slash commands only, as round 002 said; (b) keep it,
   no minimap button, opened by `/myui panel` as a dev aid; (c) keep it and make it MyUI's
   entry in the § 14 minimap menu once that exists. I lean (c), with (b) in the meantime.
5. **The centre's backing, `rgba(10,10,12,0.86)`**, is a fourteenth colour. Round 5 argued it
   as "summoned, not resting"; SPEC § 7 says nothing outside thirteen. Allow the exception
   (recorded in § 7), or back the history with an existing entry? The nearest is Tick dark,
   `rgba(0,0,0,0.55)` — Round 5 found 0.14-style fills unreadable for twelve rows of 11pt
   over daylight, and 0.55 is untested.

## 5. Findings carried in

- **Pixel-perfect on the laptop** (R2): uiScale 0.8 gives 2.33 px/unit at 3456×2234, so
  hairlines blur. 0.8 was chosen for the 5K display (exactly 3.0). § 15 needs a per-screen
  scale story; this is the laptop half of it.
- **R1 heads-ups that land here:** chat tabs gained looping flash animations (check the chat
  module's quieting against them); the minimap gained a coordinates child (one more thing for
  the minimap replacement to clear).
