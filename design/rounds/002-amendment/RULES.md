# RULES — read this before writing any Lua

This addon targets **World of Warcraft Retail 12.1** and the Secret Values / Secret Aspects
system. These rules are not style preferences. Breaking one does not produce a visual bug —
it produces a tainted execution path that may work on a target dummy and fail in a raid.

**If a rule here conflicts with addon code you have seen before, this file wins.** Most
published addon source predates 12.1 and does exactly what is forbidden below.

---

## The one principle

> **Forwarding a secret value is legal. Inspecting one is not.**

A protected value may be handed to a widget setter, mapped through a curve object, or used
as a texture mask. It may never be read into a Lua variable you then compare, measure,
sort, or do arithmetic on.

The design in this handoff was built specifically so that nothing it draws requires an
inspection. If you find yourself needing one, the design is being implemented wrong — stop
and re-read SPEC.md rather than reaching for a workaround.

---

## Forbidden — with the legal alternative in each case

**Do not read health, resource, or cooldown values to drive appearance.**
No `UnitHealth("player") / UnitHealthMax("player")`, no `GetSpellCooldown` remaining-time
math, no percentage variables.
→ Forward the value to the widget, or map it with a `ColorCurveObject`.

**Do not write threshold branches.**
No `if pct < 0.2 then`. This is the single most likely mistake, because the visual design
genuinely does escalate at low health — but the escalation is produced by curves, never by a
comparison.
→ `ColorCurveObject` for continuous colour; a **step curve evaluated to alpha** for the
discrete-looking boundary. Note the consequence: a step curve changes an alpha, so a tell that
mutates a widget (12pt → 14pt) becomes two widgets cross-faded, not one widget resized.

`C_Secrets` does not help here. It is introspection about *whether* a value is secret — no
comparison, no predicate.

**Ordinary Lua on ordinary values is fine.**
The rail's sources (SPEC § 6) are item quality, free bag slots, durability, mail flags. None
are protected. Compare and filter them normally. This rule file governs unit and cooldown
values, not everything in the addon — over-applying it produces worse code, not safer code.

**Do not compare, rank, or sort anything derived from combat state.**
No "which cooldown is closest to ready", no "lowest health party member", no priority
ordering. The rhythm line originally encoded priority as bar height; that idea was cut from
the design for exactly this reason. Cell order is fixed configuration, never computed.
→ Fixed, user-configured order only.

**Do not hide or show a protected frame in combat.**
Rebar clears the screen (SPEC § 11), which means it touches Blizzard's own protected frames.
Filtering and Edit Mode layout changes are out-of-combat operations, always. Queue on
`InCombatLockdown()` and flush on `PLAYER_REGEN_ENABLED`.
→ Where a frame only needs to be quiet rather than gone, set alpha instead. Alpha is not
protected, so the adopted frames (minimap, chat, bags) have no lockdown problem at all.

**Do not treat `HasSecretValues()` as a signal.**
It reports that an object carries protected data. It is a **crash guard** — call it to avoid
attempting an illegal operation on a value type. It is not a low-health tell, not an event,
and not a boolean you may branch appearance on.
→ `RegisterStateDriver` is the only event source for discrete states.

**Do not poll combat state on `OnUpdate`.**
Beyond the taint risk, it is the standard cause of this class of addon being blamed for
frame drops.
→ Event-driven only. `OnUpdate` is acceptable *solely* for the cursor-proximity check and
the peek timer in the reveal engine, neither of which touches game state.

**Do not fight the layout engine or reparent CDM's own widgets into your layout.**
→ Keep Cooldown Manager alive at alpha 0 as the tracking source and mirror it with your own
frames receiving forwarded values. See SPEC.md § Rhythm line.

---

## The five sanctioned mechanisms

Each owns one job. Do not use one to do another's work. Amended after the phase 0 source
audit: two of the original four were wrong on 12.1, and one was added.

| Mechanism | Owns | Cannot do |
|---|---|---|
| Curve objects | Continuous colour as a function of a secret value (`ColorCurveObject`); **and**, as a step curve evaluated to alpha, a hard threshold with no comparison | Size or geometry. A step curve gives you an alpha, not an event |
| `MaskTexture` | Any texture bound to the bar's moving fill boundary, on either side of it | **Inversion — the API has none.** For the depleted region, use a second bar filled in reverse from the same value. Unused in v1 |
| `RegisterStateDriver` | Discrete state arrival as an attribute change, for states the macro-conditional parser knows | **There is no health conditional**, of any spelling. Low health is not reachable this way |
| CDM at alpha 0 + mirror frames | Cooldown, charge and proc tracking, forwarded to your own cells | Nothing you inspect |
| Secure hook on Blizzard's low-health frame | The single discrete low-health event, as a plain non-secret boolean | Any threshold but Blizzard's 35%. The player can disable it; handle its absence |

The fifth mechanism is narrowly licensed: it exists so low health can *summon* `SelfStack`
(SPEC § 3), and for nothing else. Hooking further Blizzard frames to recover other events is
out of bounds — raise it instead.

Consequence worth internalising: **size changes, pulses, and breathing animations require an
event.** They are only legal inside a driver state. A curve cannot drive them. If the spec
asks for a pulse, there is a driver state behind it; if there is no driver state, there is
no pulse.

---

## Compliance harness (build this in Phase 0, before any UI)

Ship a debug guard that makes violations loud:

- A wrapper around value access that errors with a pointer to this file when handed a
  protected value in an arithmetic or comparison context.
- `/rebar audit` — dumps every frame, its resting alpha, its current alpha, and which reveal
  channel is currently claiming it. Also reports whether Blizzard's low-health warning is
  enabled, since the summon channel depends on it.
- `/rebar rules` — prints the forbidden list, so it stays visible during development.
- `/rebar restore` — reverses everything in SPEC § 11, combat-safe. Build this in the same
  phase as the clearing, not after it.

The build names these `/myui *`. Either prefix is fine; pick one and make the docs match.

Run the audit at the end of every phase. A phase is not done until it is clean.
