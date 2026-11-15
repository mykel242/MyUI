# DECISIONS — round 004: the modal HUD

Worked out with Mykel on 2026-11-14 over an interactive mock, after the first Phase 4 play left
the UI "both minimal and unusably busy". Context, not contract — where this and SPEC/RULES/PLAN
disagree, those win.

**Visual reference:** the concept canvas *MyUI combat HUD concepts* (claude.ai artifact
`CCfBPgK475QveeDx3oJFGK`, private to Mykel): an interactive board with mode, modifier,
mod-bar-style and target switches and a notes toggle; a mode-by-zone grid; a button grammar
board. Like the round-002 HTML, it is a reference for intent, not code to port, and it contains
explorations SPEC does not adopt.

## The governing idea

> MMOs need a lot of buttons and unit frames to play efficiently, but can feel like flying a
> 747. Everything stuck on the screen when it is contextually wrong is the whole challenge…
> and WoW is super modal. — Mykel

So **the HUD is a function of WoW's mode**, not one fixed layout. Every mode is a plain game
state (resting, mounted, in combat, instance type, role, encounter, vehicle) — legal to branch
on, no secret value involved. A mode decides which zones are drawn; zones never move.

## Decisions

| # | Decision | Why / Mykel's words |
|---|---|---|
| 1 | **Modal HUD**: rest, travel, solo fight, group (DPS), group (healer), raid boss, vehicle | "WoW is super modal" |
| 2 | **Action bars stay WoW's bars, as Mykel plays them**: bar 1 plus three modifier pages — ALT, CTRL and **ALT+CTRL** — centred under the character, lower and smaller than the first mock | "I use ALT and CTRL as modifiers to get to the other 2 bars already" · "I can have a 4th state (alt + ctrl + key)" · "too much of a wall of buttons — move that whole mess down a bit, scale it all down" · "bars need to be centered" |
| 3 | **Two wings on the bars' rows**: Cooldowns on the left, *On you* (chosen buffs, debuffs edged by dispel type) on the right | The first cooldowns "feel tacked on and not aligned with anything"; debuffs and "very specific buffs" were missing |
| 4 | **Party and raid in one area, right of the character**; small for DPS, larger for a healer, a grid for a raid | "put all the party or raid frames in the same area on the right" |
| 5 | **Click targets, as in WoW**; **rest 0.4s for a card**, which lingers 1.5s so it can be reached; clicking a card targets too | "in actual raids clicking on a unit frame switches to that as a target… hover + timer (to show cards… with time to pin them); clicking on the card should target" |
| 6 | **Pinned cards** in a column on the far right, kept across modes, separate for party and raid; **most important in the raid view** | "focusing the tank and that one guy who always needs to be dispelled" · "arguably most important for the raid view" |
| 7 | **A click map on every frame and card**: click target, shift pin, ctrl focus, alt cast a chosen spell, right Blizzard's menu — shown as a legend on the card | "can we do that shift click event? … alt click, ctrl click?" · picked option 2 (pin by a protected click) over a Pin button |
| 8 | **Target strip in three kinds**: hostile, neutral, friendly — a palette dot, never more colour | "we don't have an example of a friendly or neutral target" |
| 9 | **Boss mode**: a boss bar with phase marks and the cast, a timeline of what is coming, one critical alert at a time | Boss alerts were missing |
| 10 | **Travel**: the map called up on a key, translucent over the world | "a way to call up the map" |
| 11 | **Look**: directionally the housing UI — Blizzard's newest — few things, gold ring for "selected", a small round layout rail for the mode, keybinds top-left on buttons | "the most recent form of blizzard UI and is directionally nice" |
| 12 | **Blizzard's own toasts are old and blurry**: Battle.net and alert toasts go through MyUI's toasts or stay quiet | Seen in play: the friend-online toast |
| 13 | **No arcs; no contextual interrupt prompts** | "I don't want arcs, contextual interrupts I know are forbidden" |

## On alt-click casting — is it still legal?

Mykel was not sure. Read against 12.1.5.70783:

- Blizzard ships **its own Click Casting** (`Blizzard_ClickBindingUI`, `C_ClickBindings`) on
  this build. Click-casting is a sanctioned game feature, not an exploit addons get away with.
- The secure action button's `spell` action (`Blizzard_FrameXML/SecureTemplates.lua:393`,
  `SECURE_ACTIONS.spell` → `CastSpellByID/Name(spell, unit)`) is **unchanged since 12.1.0** and
  carries no addon-restriction check.
- What 12.1 forbids is an addon **deciding** — reading health, debuffs or cooldowns and choosing
  a spell or a unit from them. A fixed binding the player chose, fired by the player's own click
  on a unit they chose, decides nothing. MyUI never picks the spell or the unit by state (it
  cannot: it never reads the values).

**Verdict: legal as specified — verify in game before relying on it** (PLAN probe P3). Open:
whether to drive it with MyUI's own attributes or to inherit Blizzard's Click Casting bindings
on MyUI's unit buttons, so the player configures it in one place.

## Answered later the same day

- **Mod-bar display is a player setting**: Swap and Ghost offered (Mykel likes both); Dim dropped.
- **The alt-click spell is the player's choice**, with a default from class, spec and level —
  plain data (a per-class table, `IsSpellKnown`), never a reading of combat state.
- **Bars: MyUI's own secure action buttons on Blizzard's action slots** (recommended; P5 confirms).
  Skinning Blizzard's bars is safest but cannot do Swap or Ghost: both change what is shown when a
  modifier is held, in combat, and Blizzard's bars are protected — only a secure state driver on
  MyUI's own header may page or show them in combat, which is what Bartender and Dominos do.
  Blizzard's bars stay hidden by the MyUI layout and keep the keybinds; MyUI's buttons draw the
  same slots and are clickable.
- **Items, trinkets, potions**: no special handling. They live on action slots (often as macros
  — `/use 13`, a potion macro), so MyUI's buttons show them like anything else: icon, count,
  cooldown. The Cooldowns wing may also hold any action slot, so an on-use trinket or a potion can
  sit beside the major cooldowns.

## Still open
- Boss timeline and alerts: mirror `C_EncounterTimeline` / encounter warnings into MyUI frames,
  or restyle Blizzard's — after probe P4.
- A collected enemy list (still the first nice-to-have after MVP; needs its own design round —
  RULES forbids ordering by health or threat).
