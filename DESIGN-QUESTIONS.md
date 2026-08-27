# Design questions

Findings from building phases 0–3 of the handoff, for the designer.

The handoff says SPEC.md is authoritative and that a need to work around it means a spec
misreading rather than a missing workaround. Every item below is one of those moments,
recorded rather than quietly resolved. Nothing here is a complaint about the design; most
of it is the design meeting a client that has changed under it.

Each entry says what SPEC asks for, what actually happened, what was built, and what is
needed from you.

---

## 0. The question the mock answers and the spec never asks

**Whose job is the empty screen?**

The mock's backdrop is a bare screenshot — no action bars, no player frame, no minimap, no
chat, no bags. The intent is unmistakable. But **Rebar draws four things and the mock
removes about a dozen**: nothing in the design replaces the action bars, the minimap, the
chat frame or the bags. So the clean screen is either something Rebar produces, or a
precondition the player arranges — and the handoff never says which.

**Most of it the player can already do.** Edit Mode hides the target frame, the cast bar,
buffs and debuffs, party/raid/boss/arena frames natively, and every action bar has a
visibility setting.

**Except the player frame.** Twenty-three unit-frame settings and thirty-six account
settings, and not one hides it — only `HidePortrait`. It is the single element nothing but
an addon can remove, and it sits directly on top of what Phase 4 draws.

There is proven prior art, and it shows the technique changed at 12.1 — see API-NOTES § 7.
Pre-12.1 addons call `Hide()`; oUF, the one audited addon claiming 12.1 support, stopped
doing that and tags the frame with a roleset no UI mode includes, letting Blizzard's own
visibility system filter it out. A few lines, and reversible.

**Needed:** is the bare screen Rebar's output or its assumption? If it is the assumption,
the mock is showing a configured client and should say so. If it is the output, we need the
list element by element, and a position on the bars, minimap and chat, which nothing in the
design replaces.

---

## A. Verified failures in game

### A1. The age and the "+N more" count are unreadable — **one deviation shipped**

**SPEC § 6:** "age 10pt `rgba(115,119,126,1)` right-aligned."

That is a mid-grey. Against the mid-brown of ordinary terrain it has almost no contrast in
either direction, and a shadow cannot help — a shadow solves an edge problem, not a
contrast one. Phase 3's acceptance step for it fails with the specified value and passes
with the text lifted one palette step.

**Built:** `/myui contrast normal | lift`. Lift moves tertiary → secondary and
secondary → primary. Still inside § 7; no fifteenth colour.

**Shipped defaulting to `lift`** — the only deliberate deviation from SPEC in the addon.
Shipping a default demonstrated unreadable would be choosing fidelity over the thing
fidelity is for. `/myui contrast normal` restores the exact specified values.

**Needed:** either a revised value for tertiary text, or confirmation that lift is right.

### A2. The palette assumes a dark backdrop

§ 7 is light-on-dark throughout — near-white text, 14% white troughs, pale pastel dot
hues. Over sand, firelight or anything golden the whole HUD washes out. A1 is the sharpest
instance, but it affects everything, including the bars in Phase 4.

**Built:** every string carries a shadow drawn in `tickDark`, which is already
`rgba(0,0,0,0.55)` in the palette, so no fifteenth colour. `/myui text shadow | outline |
none`.

**Not built:** anything for the dots. The six older ones sit at the specified 0.4 and are
faint over bright ground. Three options, none of them ours to choose: leave it; a 1px dark
edge per dot, reusing `tickDark` and consistent with the "+N more" square already being an
outline; or a ≤14% dark backing behind rows with content, which stays inside § 1's fill
limit but adds a panel.

### A3. The modifier reveal conflicts with ordinary keybinds

**SPEC § 4:** "Modifier held | Alt (primary) or Shift | Instant, no dwell."

On the test machine `Ctrl+1-6` is the top action row, `Alt+1-6` the middle, bare `1-n` the
bottom. That is a conventional three-row layout and it leaves no modifier free. A HUD keyed
to one reveals itself on every modified cast in a fight — the incidental-reveal problem the
140ms dwell exists to prevent, arriving through a different door.

**Built:** `/myui modifier alt shift ctrl | none`, and a bindable **Hold to reveal** key so
the channel need not be a modifier at all. Default is still SPEC's Alt or Shift.

**Needed:** the channel probably wants a different default, or to be a binding by design
rather than as an escape hatch.

---

## B. Specified mechanisms that do not exist on 12.1

Verified against Blizzard's source at build 12.1.0.69497. Full citations in
`API-NOTES-12.1.md`.

### B1. There is no health macro conditional, so § 3's driver state has no event

`RegisterStateDriver` resolves through `SecureCmdOptionParse`, and probing the live client
found no health conditional of any spelling. `C_Secrets` turns out to be introspection
about *whether* a value is secret — no comparison, no predicate.

**Built:** a **step curve**, the technique Plater ships for its execute-range marker. A
curve holding one alpha below a cutoff and another above it, evaluated against health and
forwarded to `SetAlpha`, produces a hard threshold with no comparison in Lua. All three of
§ 3's tells are reachable this way.

**Needed:** nothing to unblock Phase 4 — but two of the three tells now require duplicated
frames cross-faded by the step alpha, which is a change to *how* § 3 is built.

### B2. `MaskTexture` has no inversion

§ 3 asks for "a flat wash masked to the **inverse** of the fill". `SimpleMaskTextureAPI`
declares zero functions and no inversion parameter exists; inverting would need a texture
asset, which § 6's zero-asset rule forbids.

**Built:** a second StatusBar with `SetReverseFill(true)` fed the same forwarded value. It
occupies exactly the depleted region by construction. **This is arguably better than what
was asked for** — no mask, no asset, same result.

### B3. The low-health channel in § 4 cannot exist

§ 4 lists the low-health driver state as a state-change channel feeding the arbiter. The
arbiter compares claims, and § 3's replacement produces a **secret** alpha, which may never
be compared. So low health cannot arbitrate.

That is fine if § 3's continuous escalation was the whole intent. **If the design also
wanted "when I get low, the HUD comes up"**, that needs a discrete event, and the only
source is hooking Blizzard's own `LowHealthFrame` — which brings a fixed 0.35 threshold, a
CVar the player can switch off, and a fifth mechanism outside RULES.md's four.

**Needed:** was low health meant to reveal the HUD, or only to escalate it?

---

## C. Decisions made where SPEC is silent

All are one edit to change, and all are named in code beside what acts on them.

| # | Question | What was decided |
|---|---|---|
| C1 | **What produces a notification?** § 6 specifies the rail completely and never says what puts an item on it | `/myui notify` is the source for now. **The real sources are an open design question** |
| C2 | Where does the toast sit? | It *is* the first row, expanded: no dot of its own, borrows slot one's, and that row's text hides until it has collapsed. Read straight out of "collapses into its dot" |
| C3 | What happens when two toasts arrive together? | The newer takes the slot and restarts its own dwell. The rail already holds every item, so the toast is the announcement, not the record |
| C4 | The drain clock has no geometry | A 1px hairline the width of the SelfStack, draining right to left, in `fillDim`. The only visual the spec names and then leaves undescribed |
| C5 | What alpha does each reveal channel claim? | All 1.0, so "highest wins" is trivially satisfied today. Ties are therefore the *normal* case, and a declared precedence resolves them: debug, peek, modifier, combat, target, cursor |
| C6 | Which frames does each channel claim? | combat → SelfStack + Cooldowns; target → TargetStrip; modifier and peek → everything; cursor is per-frame by definition |
| C7 | "Within **32 units**" | Converted × 0.8 like every other number, giving 25.6 UI units. This is the one place the spec says "units" rather than leaving the number bare, so it may not be a mock-canvas pixel |
| C8 | The Rail's resting alpha, given as "hairline 0.14, dots per § 6" | Read as per-element. 0.14 is exactly the `trough` colour, so the hairline carries it and the container rests at 1.0. **Consequence: the reveal engine never touches the rail** |
| C9 | Which side of the hairline do the dots sit on? | Rightward — the rail is at x = 20 and that is the only direction with room |
| C10 | No frame strata is specified anywhere | Explicit `MEDIUM`, which is what the default happened to be. Named rather than inherited, since a HUD sharing a layer with the action bars is one Edit Mode change from disappearing behind them |
| C11 | Row text offsets | Name 8 right of the dot; age right-aligned in a 160-wide row |

---

## D. A conflict inside the handoff

PLAN.md's Phase 3 scope line lists **"bloom texture"** among the things to build. SPEC § 6
cut the bloom permanently, says explicitly *do not implement it*, and ships two ladder
images as evidence that it is invisible at every size and opacity tried.

SPEC wins by its own first line, so the bloom is not built. PLAN's line is stale.
