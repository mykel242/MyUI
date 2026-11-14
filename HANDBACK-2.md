# Rebar handback 2

Findings from building the amended handoff, for the designer.

**2026-08-28** · `0.4.0-phase3` · the amendment is implemented, deployed and played

> The first handback produced `HANDBACK-RESPONSE.md` and the amended SPEC, RULES and PLAN.
> All of it is built. **Two new things need a ruling** — H1 and H2 below. They were found in
> play rather than by reading, they are related, and H1's answer depends on H2's.
>
> Everything after them is recorded so the state is in one place. None of it needs an answer.

| | Finding | What we need |
|---|---|---|
| **H1** | A long name draws on top of the age | Confirm truncation, or say what gives instead |
| **H2** | § 6 implies a hover affordance never specified | The gesture, what it reveals, whether "+N more" opens |
| G1 | Quest objectives arrive in bursts with no id | Nothing — two-second window, unless that is wrong |
| — | The amendment as built | Nothing — listed for the record |
| — | Motion timings and peek's shape | Nothing — both sides agree they wait for Phase 6 |

The handoff says SPEC is authoritative and that a need to work around it means a spec
misreading rather than a missing workaround. Both findings below are one of those moments,
recorded rather than quietly resolved.

---

## H1. A long name draws on top of the age, and § 6 does not say what should happen

**SPEC § 6:** *"The two newest items carry name, count and age at rest — no hover required.
Name 11pt `rgba(240,241,243,1)`; age 10pt `rgba(173,177,184,1)` right-aligned."*

Found immediately once real loot started arriving. **"Chunk of Companion Experience"** ran
straight through the age and drew on top of it — neither the name nor the age was readable.
It is not an edge case: quest titles, currency names and companion items are routinely longer
than the row.

There is no spec answer to appeal to. § 6 gives both strings their font and alignment and
never says which one yields, and the 160-wide row is our own number, not yours.

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

---

## H2. § 6 implies a hover affordance that was never specified, and the rail now needs it

The same sentence, read closely:

> The two newest items carry name, count and age at rest — **no hover required**.

That qualifier only means something if hover shows something for the *other* dots. If nothing
is ever available on hover, "no hover required" has nothing to contrast with.

**In play this stopped being a wording question.** With the real sources running, a normal few
minutes fills the rail: eight dots and **"+7 more"** — fifteen things had happened, and two of
them could be read. A toast speaks once and collapses, and after that there is no way to find
out what it said. The rail is holding the record and not showing it.

This was invisible while the rail was fed by a test command, because that only ever put on it
what you had just typed.

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
summon — which § 11 has already ruled is not acceptable for Blizzard's frames. The rail should
probably answer it the same way.

---

## The amendment as built

For the record. Nothing here needs an answer.

- **Palette collapsed to thirteen.** Secondary and tertiary text are one dim value.
- **Contrast is a supersede, not a lift.** Normal contrast substitutes one dimmer value for
  the dim colour; the old blanket remap is gone. This fixed a real bug — the target strip's
  level had been drawing near-white since Phase 1.
- **The modifier reveal channel is cut**, along with its binding and its saved setting. Peek
  is now the only deliberate summon.
- **The dot edge**, one physical pixel, on rows three and below and on the overflow square.
  It is drawn beside the dot rather than inside it, so it does not inherit the dot's alpha.
- **The rail feeds itself.** Seven real sources: loot at uncommon and above, quests accepted
  and handed in, currency, reputation, achievements, and the orange conditions — mail, full
  bags, worn gear, party and guild invites.
- **The fifth mechanism** is in the rules with its licence: the low-health hook may summon the
  self stack and nothing else.

One deliberate deviation from RULES: the printed consequence never promises a driver state,
because on 12.1 there is no health macro conditional for one to key off.

---

## G1. Quest objectives arrive in bursts and the spec gives no window

**Decided without you, recorded here.**

§ 6 lists the quest-log event under "Quest objective" and says **"one row per event, never a
stream"**, illustrated with a condition — *"a full bag says so once, not on every bag
update"*.

Bag, durability and mail are conditions, so a latch answers them exactly: speak on the way in,
stay quiet until it clears. This event is not a condition. It fires several times for one
objective advancing and carries **no quest id**, so there is nothing to deduplicate against
and no name to give the row beyond "Objective".

**Decided:** a two-second coalescing window — long enough to swallow the burst from one
objective, short enough that two real objectives in a row still read as two. One edit to
change.

**Needed:** nothing, unless two seconds is wrong. Worth knowing that this is the one row on
the rail that cannot be named, which may be an argument for dropping the source rather than
tuning it.

---

## Still open on both sides, for Phase 6

**Motion timings.** 120ms in, 260ms out, 140ms dwell, 3s peek — guessed from feel, never
played. The amendment agrees and defers them.

**Peek's shape.** With the modifier channel cut, peek is the only deliberate summon, so
Phase 6 should judge tap versus hold.
