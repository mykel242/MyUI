# Design questions

Findings from building phases 0–3 of the handoff, for the designer.

> **All fourteen are answered, 2026-08-27.** The revised handoff is at
> `~/Development/UI - Rebar/in/current`; `HANDBACK-RESPONSE.md` carries the
> reasoning and `SPEC.md` / `RULES.md` / `PLAN.md` are amended in place. Where they and the
> response disagree, the specs win.
>
> Each entry below keeps its original text as the record, with the answer appended. **Two
> new things are raised back at the end** — §§ E and F — both found by implementing the
> amendment rather than by reading it.

| | Finding | Answer |
|---|---|---|
| 0 | Whose job is the empty screen? | Rebar's. New SPEC § 11, new PLAN Phase 6b |
| A1 | Tertiary text unreadable | Lift adopted; palette collapses to thirteen |
| A2 | Palette assumes a dark backdrop | Shadow accepted as built; dots get a 1px dark edge |
| A3 | Modifier reveal fights keybinds | Channel cut entirely, hold binding with it |
| B1 | No health macro conditional | Step curve accepted, now the specified mechanism |
| B2 | No mask inversion | Reverse-filled bar accepted, "better than what was asked for" |
| B3 | Low health cannot arbitrate | Correct — resolved by licensing a fifth mechanism |
| C1–C11 | Eleven silent decisions | C1 answered by seven real sources; **C5 superseded**; other nine stand |
| D | PLAN/SPEC bloom conflict | Struck from PLAN, adjudicated correctly |

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

> **Answered — Rebar's, and the element-by-element list is SPEC § 11.** Three techniques,
> split by what each frame permits: the player frame *filtered* by roleset; the action bars
> *hidden* via an Edit Mode layout named `Rebar` that records and restores the player's
> previous one; and minimap, chat and bags **adopted** — registered at resting alpha 0 and
> revealed by the ordinary engine rather than hidden at all.
>
> Adoption is the part worth noting, because it answers the bars/minimap/chat gap directly:
> § 1 says hidden must never mean lost, and a chat frame you cannot summon is lost. It also
> sidesteps combat lockdown, since alpha is not protected. Chat gets one extra reveal — an
> incoming whisper holds it for 8s.
>
> Scheduled as PLAN Phase 6b, after the polish phase, because it is the only phase that
> touches Blizzard's protected frames. `/myui restore` reverses all three. See § E2 for the
> one thing in it that still needs proving in game.

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

> **Answered — lift is right, and it collapses the palette.** `173,177,184` becomes the
> spec value. The consequence the finding did not spot: that *is* the existing
> `Text secondary`, so the two entries are now the same colour and collapse into one
> `Text dim`. The palette is thirteen, not fourteen. `115,119,126` survives only as
> `/myui contrast normal`, a debug affordance, and is no longer a palette entry.
>
> **Built.** One consequence found while building it, recorded in STATUS: the old lift was a
> blanket rule that also moved secondary → primary, so the TargetStrip's level text had been
> drawing at `rgba(240,241,243,1)` since Phase 1 instead of the `rgba(173,177,184,1)` SPEC
> § 2 names. Accepted three times without anyone seeing it. There is one dim grey now and no
> remapping, so it is correct by construction.

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

> **Answered — the 1px dark edge**, in `tickDark`, matching the "+N more" square. The
> backing was rejected on § 1's geometry rule: fills above 14% do not exist outside a data
> bar, and an edge stays inside the vocabulary the design already has. The shadow is
> accepted as built.
>
> With an implementation note that decides whether it works: **draw the edge as a sibling
> texture at constant alpha, never as a child of the dot** — a child inherits the dot's 0.4
> and the edge vanishes at exactly the alpha it was added to rescue.
>
> **Built**, sibling and all, with two tests guarding the note. One reading needed your eye
> and is in the acceptance script: the edge is attached to the *"Older items"* line and the
> reason given is legibility at 0.4, which does not apply to a dot at full alpha — so the
> newest two dots have no edge. That makes the rail a progression (solid, outlined, hollow
> square), which reads as deliberate to me, but it is a reading rather than a reading-off.

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

> **Answered — the channel is cut.** Not re-defaulted, not converted to a binding: removed.
> The reading is that this finding was really an argument that the channel was never
> load-bearing — proximity covers reveal-while-doing-something, peek covers
> reveal-because-I-want-to, and the modifier only ever covered reveal-while-casting, which
> is the case where it misfires. The hold binding comes out with it.
>
> **Built.** The channel, the key set, the binding, the saved setting and the `via` argument
> that existed only to tell the channel's two arms apart are all gone; a schema migration
> clears the stored setting. `Bindings.xml` keeps the `runOnUp` + `keystate` shape in a
> comment, because peek is now the only deliberate summon and PLAN Phase 6 asks whether it
> should become a hold.

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

> **Answered — accepted, and it is now the specified mechanism.** The duplicated-frame
> consequence is written into SPEC § 3, including the 12pt → 14pt number becoming two
> stacked labels: "the effect is what matters; the build is yours." RULES is corrected so
> `RegisterStateDriver` no longer claims to be the only legal event source, and it now says
> outright that there is no health conditional, so the next reader does not spend an
> afternoon looking for one.
>
> See § E1 — one paragraph of RULES.md was left behind by this correction and now
> contradicts SPEC § 3.

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

> **Answered — it reveals, `SelfStack` only.** The finding is accepted as correct about the
> step curve and routed around rather than argued with: the hook's show/hide is a **plain
> boolean**, not a secret, so it may be compared and may claim in the arbiter, which is
> exactly what the curve's alpha cannot do.
>
> The fifth mechanism enters RULES narrowly licensed — for this one purpose, with hooking
> further Blizzard frames to recover other events explicitly out of bounds. Accepted costs:
> Blizzard's fixed 35%, and a CVar the player can switch off, which `/myui audit` must
> report. No fallback threshold of our own, because that would be a comparison.
>
> Reveals `SelfStack` alone — not the cooldowns, not the target strip: "low health is a
> reason to see your own numbers, not a reason to redraw the screen." **See § E3**: under
> our own C6 inference, that makes the channel invisible for most of the time low health
> actually happens.

---

## C. Decisions made where SPEC is silent

All are one edit to change, and all are named in code beside what acts on them.

| # | Question | What was decided |
|---|---|---|
| C1 | **What produces a notification?** § 6 specifies the rail completely and never says what puts an item on it | **Answered** by the amendment's event table, and built in `Sources.lua`. `/myui notify` stays as the test source — no real source can be made to fire eight times in a row, which is what the acceptance step needs |
| C2 | Where does the toast sit? | It *is* the first row, expanded: no dot of its own, borrows slot one's, and that row's text hides until it has collapsed. Read straight out of "collapses into its dot" |
| C3 | What happens when two toasts arrive together? | The newer takes the slot and restarts its own dwell. The rail already holds every item, so the toast is the announcement, not the record |
| C4 | The drain clock has no geometry | A 1px hairline the width of the SelfStack, draining right to left, in `fillDim`. The only visual the spec names and then leaves undescribed |
| C5 | What alpha does each reveal channel claim? | All 1.0, so "highest wins" is trivially satisfied today. Ties are therefore the *normal* case, and a declared precedence resolves them. **Superseded:** the amendment writes a precedence into § 4 — *low health, state change, peek, proximity* — which is not the order Phase 2 chose. Adopted: `debug, combat, target, peek, cursor`. A peek during combat is now credited to combat |
| C6 | Which frames does each channel claim? | combat → SelfStack + Cooldowns; target → TargetStrip; peek → everything; cursor is per-frame by definition. Amended only by the modifier's removal — **but still our inference, never confirmed, and § E3 is now what hangs on it** |
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

---

## E. Raised back, from implementing the amendment

Four of these came out of building the rework rather than reading the response. Each is a
place where the amended handoff and the client disagree.

### E1. RULES.md still says a pulse needs a driver state. SPEC § 3 no longer agrees.

`RULES.md` keeps this paragraph, unedited, directly beneath its **new** five-mechanism
table:

> size changes, pulses, and breathing animations require an event. They are only legal
> inside a driver state. A curve cannot drive them. If the spec asks for a pulse, there is a
> driver state behind it; if there is no driver state, there is no pulse.

The first sentence is true and verified — `SetScale` is `AllowedWhenUntainted`, so no
forwarded secret will ever resize anything. **The conclusion no longer follows.** The same
amendment refuted `RegisterStateDriver` for low health, and its own SPEC § 3 builds both
the 12pt → 14pt number and the 1.60s breathe with no event and no driver state: duplicated
frames cross-faded by a step curve's alpha, with the animation permanently running on one
copy so nothing ever has to start it.

So the paragraph is a leftover from before B1 was accepted, sitting two sections away from
the text that contradicts it. It is the paragraph a cold reader would take as binding, and
it would send them looking for a driver state that cannot exist.

**Built:** `/myui rules` prints the accurate version — *"a forwarded secret cannot resize
anything; cross-fade two frames with a step curve instead, which needs no event"* — and a
test asserts the printed consequence never promises a driver state. Flagged here because
the amendment is authoritative and this is us deviating from it in print.

**Needed:** strike or rewrite the paragraph.

### E2. `LowHealthFrame` has no hysteresis, and § 3 asks for no dwell and no timeout

`Blizzard_FrameXML/Shared/LowHealthFrame.lua`, read at build 12.1.0.69497:

```lua
function LowHealthFrameMixin:IsAtLowHealth()
    return self:GetHealthPercent() <= self.lowHealthPercentStart;   -- .35
end
```

One bare `<=`. There is no separate stop threshold, and `EvaluateVisibleState` runs on every
`UNIT_HEALTH` for the player. Health sitting near 35% — which is exactly where a fight gets
interesting — shows and hides the frame repeatedly.

SPEC § 3 specifies the channel as *"Claim 1.0, held for as long as the hook is shown. No
dwell in, no timeout out."* Taken literally that puts `SelfStack` through a 120ms-in /
260ms-out fade on every crossing. **This is A3's finding arriving through a third door:** an
incidental reveal driven by something the player did not deliberately do, which is the thing
the 140ms dwell exists to prevent.

Two things the source settles in the design's favour, worth recording so they are not
re-litigated: the frame does **not** hide itself after a few seconds — the fade at 2–3s only
dims its own pulse animation, and it stays shown while health stays low — and it does hide
promptly on recovery rather than going stale.

**Proposed, not built:** a minimum hold on release — the claim stays for some hundreds of
milliseconds after the hook hides, so a crossing at the boundary reads as one reveal rather
than a stutter. That contradicts "no timeout out" as written, so it is yours to rule on.

**Needed:** confirm the hold, or confirm that flapping at the boundary is acceptable.

### E3. Under C6, the summon is invisible for most of the time low health happens

C6 was our inference and is still unconfirmed: **combat claims `SelfStack` and `Cooldowns`.**
SPEC § 4 tabulates triggers and has never said which frames each one reveals.

If that inference is right, then during combat `SelfStack` is already claimed at 1.0, the
low-health summon also claims 1.0, and the two are indistinguishable. Low health
overwhelmingly happens in combat. So the channel the amendment just licensed a fifth
mechanism to build produces **no visible change at the moment it is for**, and its only
observable effects are out of combat: falling damage, a pull gone wrong after the fight
ends, and — genuinely useful — `SelfStack` staying up after combat while you are still hurt,
instead of settling to 0.35 the instant the fight ends.

That may be exactly what was wanted. But it means the value of the channel rests entirely on
a frame-scope inference we made in Phase 2 and flagged at the time, and the escalation
layers were already doing the in-combat work.

**Needed:** confirm or correct C6. If combat is *not* meant to reveal `SelfStack`, the
summon is doing real work and this is moot.

### E4. `SetRolesets` is a protected function, and SPEC § 11 now depends on it

`SimpleFrameAPIDocumentation.lua:1458` declares `SetRolesets` with
`IsProtectedFunction = true`, and `PlayerFrame` is a protected frame. oUF calls it from
addon code with no pcall and no version guard, which suggests it is permitted in practice —
but that is inference from someone else's shipping code, not something read off the API.

This was a research note when hiding the player frame was optional. § 11 makes it
ship-blocking for v1, so it is now a risk with a schedule attached.

**Needed:** nothing from you — it wants an in-game test before Phase 6b is planned, and it
is cheap to run early. Recorded here so it is not discovered in Phase 6b.

### E5. A small inconsistency: three channels or four?

PLAN's decision table says *"Reveal channels | Three — proximity, peek, state. Modifier
cut"*. SPEC § 4's table lists four rows, adding low health, and its prose still reads "All
four resolve through a single arbiter." `HANDBACK-RESPONSE.md` reconciles them — three now,
four once Phase 4 lands — but the two specs read as contradicting each other on their own.

**Built as four**, since § 4 is the authoritative one and the fourth arrives in the phase
being built next. No answer needed unless that is wrong.

---

## F. Carried forward, unresolved by both sides

**Motion timings.** 120ms in, 260ms out, 140ms dwell, 3s peek — guessed from feel, never
played. The amendment agrees and puts them in Phase 6.

**Peek's shape.** With the modifier channel cut, peek is the only deliberate summon, so
Phase 6 should judge tap versus hold. `Bindings.xml` keeps the `runOnUp` + `keystate` shape
in a comment for exactly this, and a test asserts it is still recorded — it is the answer to
"how do you bind a hold", and it was about to be deleted along with the binding that used
it.

---

## G. One decision made where the amendment is silent

The rest of § C stands as recorded. Building the sources produced exactly one new gap.

### G1. `UNIT_QUEST_LOG_CHANGED` arrives in bursts and the spec gives no window

SPEC § 6 lists it under "Quest objective" and says **"one row per event, never a stream"**,
illustrated with a condition — *"a full bag says so once, not on every `BAG_UPDATE`"*.

Bag, durability and mail are conditions, so a latch answers them exactly: speak on the way
in, stay quiet until it clears. `UNIT_QUEST_LOG_CHANGED` is not a condition. It fires several
times for one objective advancing and carries **no quest id**, so there is nothing to
deduplicate against and no name to give the row beyond "Objective".

**Decided:** a two-second coalescing window — long enough to swallow the burst from one
objective, short enough that two real objectives in a row still read as two. One edit to
change, in `Sources.COALESCE`.

**Needed:** nothing, unless two seconds is wrong. Worth knowing that this is the one row on
the rail that cannot be named, which may be an argument for dropping the source rather than
tuning it.

---

## H. Found in game, building the § 6 amendments

Two things the real sources exposed that `/myui notify` never could. They are related, and
H1's answer depends on H2's.

### H1. A long name draws on top of the age, and § 6 does not say what should happen

**SPEC § 6:** *"The two newest items carry name, count and age at rest — no hover required.
Name 11pt `rgba(240,241,243,1)`; age 10pt `rgba(173,177,184,1)` right-aligned."*

Found immediately once real loot started arriving. **"Chunk of Companion Experience"** ran
straight through the age and drew on top of it — neither the name nor the age was readable.
It is not an edge case: quest titles, currency names and companion items are routinely
longer than the row.

There is no spec answer to appeal to. § 6 gives both strings their font and alignment and
never says which one yields, and the 160-wide row is our own number (C11), not yours.

**Built: the name yields.** It is bounded on the right by the age's left edge rather than by
the row, so it gives way to however wide the age happens to be — `9s` and `23h` are not the
same width — and an over-long name ends in an ellipsis.

That choice was made on § 1's authority rather than § 6's: *"Position is fixed forever —
muscle memory survives because nothing ever moves."* Every other fix moves something. Putting
the age on the other side of the dot is not available — that is the screen edge — so it would
mean insetting the rail from `x = 20`, which is a § 6 change and breaks the one promise § 1
opens with.

**Needed:** confirm truncation, or tell us what should give instead. Note that truncating
*loses* information, which is only acceptable if something can recover it — see H2.

### H2. § 6 implies a hover affordance that was never specified, and the rail now needs it

The same sentence, read closely:

> The two newest items carry name, count and age at rest — **no hover required**.

That qualifier only means something if hover shows something for the *other* dots. If nothing
is ever available on hover, "no hover required" has nothing to contrast with.

**In play this stopped being a wording question.** With the real sources running, a normal few
minutes fills the rail: eight dots and **"+7 more"** — fifteen things had happened, and two of
them could be read. A toast speaks once and collapses, and after that there is no way to find
out what it said. The rail is holding the record and not showing it.

This was invisible in Phase 3 because `/myui notify` only ever put on the rail what you had
just typed.

**Not built** — it is an affordance the spec implies rather than specifies, and it is yours to
rule on. Three things we would need:

1. **Is hover the intended gesture?** Click is the alternative and would collide with the
   toast's click-to-dismiss.
2. **What does it reveal** — that one dot's row expanded in place, or the whole rail expanded
   for as long as the cursor is on it? The second is more useful and much closer to "summoned
   by cursor proximity", which the reveal engine already does.
3. **Does the "+N more" square open too**, or is the cap final and the overflow genuinely
   gone?

**Our reading, offered rather than assumed:** the rail is the one element in the design that
does not come and go, and § 1 says *hidden must never mean lost*. Fifteen notifications
collapsed into two readable rows and a count is the same failure as a chat frame you cannot
summon — which § 11 has already ruled is not acceptable for Blizzard's frames. The rail
should probably answer it the same way.
