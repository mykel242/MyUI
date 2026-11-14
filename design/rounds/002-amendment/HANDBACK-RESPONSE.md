# HANDBACK RESPONSE — answers to phases 0–3

Answering the fourteen findings and the six unblockers. **SPEC.md, RULES.md and PLAN.md are
already amended** — this file is the reasoning, not the source of truth. Where they disagree,
they win.

Nothing here asks for rework of accepted phases except one deletion in Phase 2.

---

## The six unblockers

### 01 · Whose job is the empty screen? — **Rebar's.** SPEC § 11 (new)

The mock is the output, not the assumption. Rebar ships a clean screen and can put it back.

You are right that this takes on combat lockdown, so the answer splits the dozen elements by
what each frame actually permits, and only one of the three techniques has a lockdown problem:

- **Filtered** — the player frame, by the roleset technique you found. The one thing only an
  addon can do.
- **Hidden** — the action bars, via an Edit Mode layout named `Rebar` that records and
  restores the player's previous one. Out-of-combat, queued on `PLAYER_REGEN_ENABLED`.
- **Adopted** — minimap, chat, bags: *not* hidden. Registered in the frame registry at resting
  alpha 0 and revealed by the ordinary engine.

Adoption is the part worth arguing for. § 1 says hidden must never mean lost, and a chat frame
you cannot summon is lost — bars you can live without, but whispers and bag contents you
cannot. Adopting them also sidesteps lockdown entirely, because alpha is not protected. Chat
gets one extra reveal: an incoming whisper holds it for 8s.

So Rebar clears the screen, and the only genuinely protected operations are the player frame
and the layout swap — both once, at load, out of combat.

`/rebar restore` reverses all three and prints what it undid. Disabling the addon does the
same. Nothing is destroyed.

### 02 · Does low health summon? — **Yes, `SelfStack` only.** SPEC § 3, RULES

The fifth mechanism enters the design, narrowly licensed. Two things make it acceptable:

The hook's show/hide is a **plain boolean**, not a secret, so it may be compared and may claim
in the arbiter — which is what B3 said was impossible for the step-curve alpha. B3 is right
about the step curve and does not apply to the hook.

And it reveals the self stack alone. Not the cooldowns, not the target strip. Low health is a
reason to see your own numbers, not a reason to redraw the screen — the narrow version is most
of the value with none of the "the HUD explodes when I get hit" problem.

Accepted costs: Blizzard's fixed 35%, and a setting the player can switch off. Rebar reads
that setting at load; if it is off, the summon channel is quietly unavailable, the escalation
layers are unaffected, and `/rebar audit` reports which state it is in. No fallback threshold
of our own — that would be a comparison.

RULES now licenses this mechanism for this one purpose and forbids hooking further Blizzard
frames to recover other events. Raise it instead.

### 03 · Tertiary text — **the lift is right, and it collapses the palette.** SPEC § 7

`173,177,184` becomes the spec value. You were right to ship it; shipping a default
demonstrated unreadable would be choosing fidelity over the thing fidelity is for.

One consequence the handback did not flag: that value *is* the existing `Text secondary`, so
tertiary and secondary are now the same colour. Rather than leave two identical entries, they
collapse into one — `Text dim` — and the palette goes from fourteen to thirteen. This costs
nothing: secondary is the target level and tertiary was the rail age, and they never appear in
the same row. The two-tier hierarchy was notional.

`115,119,126` survives only as `/rebar contrast normal`, a debug affordance. It is no longer a
palette entry.

The shadow-on-every-string change (A2) is accepted as built — `tickDark` was already in the
palette, so nothing new was introduced.

### 04 · Dots over bright ground — **1px dark edge.** SPEC § 6

`tickDark`, matching the "+N more" square. The backing option adds a panel, and § 1's whole
geometry rule is that fills above 14% don't exist outside a data bar — an edge stays inside
the vocabulary the design already has.

One implementation note that decides whether this works: **draw the edge as a sibling texture
at constant alpha, never as a child of the dot.** A child inherits the dot's 0.4 and the edge
disappears at exactly the alpha it was added to rescue.

### 05 · Modifier reveal — **cut the channel.** SPEC § 4

Not a keybinding, not a modifier with an escape hatch. Gone.

Your A3 finding is really an argument that the channel was never load-bearing: proximity
covers reveal-while-doing-something, peek covers reveal-because-I-want-to, and the modifier
only ever covered reveal-while-casting — which is the case where it misfires. One fewer
channel is worth more than the option, and the keybinding escape hatch you built can come out
with it.

Four channels becomes three, then four again when the low-health summon lands in Phase 4.

Knock-on: peek is now the only deliberate summon, so the 3s tap carries more weight than it
did. Phase 6 should judge whether it still wants to be a tap or wants to be a hold. That is
now on the list with the 120/260/140 timings, which have also never been played.

### 06 · What feeds the rail — **all seven.** SPEC § 6

Seven sources, five hues, mapped so the hue means something: four hues say *something
happened*, orange says *something wants you* (mail, bag full, durability, invites). Event list
is in the spec.

Worth saying plainly because the harness may over-apply RULES here: **none of this data is
protected.** Item quality, free bag slots, durability percentage, mail flags — compare and
filter them as ordinary Lua. RULES governs unit and cooldown values; over-applying it produces
worse code, not safer code. That is now written into RULES.

Two constraints: one row per event, never a stream (a full bag says so once, not on every
`BAG_UPDATE`), and no source may be added that reads a unit value. Defaults — uncommon and
above, 20% durability, zero free slots — are saved variables.

### C8 · The rail's resting alpha — **your reading is correct**

Per-element, container at 1.0, reveal engine never touches the rail. That is intended: the
rail is always there and quiet because its parts are quiet. It is the one thing in the design
that does not come and go, which is why notifications can be trusted to it.

---

## B · Mechanisms the client removed — all three substitutions accepted

**B1 · No health macro conditional.** Step curve accepted, and it is now the specified
mechanism. The consequence you flagged — two tells need duplicated frames cross-faded by the
step alpha rather than one widget mutated — is written into the spec, including for the 12pt →
14pt number, which becomes two stacked labels. The effect is what matters; the build is yours.

RULES is corrected: `RegisterStateDriver` no longer claims to be the only legal event source,
and it now says explicitly that there is no health conditional, so the next reader doesn't
spend an afternoon looking for one. Also noted: `C_Secrets` is introspection, not a predicate.

**B2 · No mask inversion.** Reverse-filled bar accepted, and you are right that it is better
than what was asked for — no asset, no mask, and it cannot drift out of alignment because it
occupies the depleted region by construction. Spec updated to specify it rather than the mask.
`MaskTexture` stays in the mechanism table but is unused in v1.

**B3 · Low health as a reveal channel.** Correct about the step curve, resolved by the hook —
see 02.

---

## A2 and the palette

Accepted as built. The dots are handled by 04.

---

## C · The eleven silent decisions — all accepted

C1 is answered by 06. C8 is confirmed above. The other nine stand as decided:

C2 toast as the first row borrowing its dot; C3 newer takes the slot and restarts its dwell;
C4 the 1px hairline drain clock, self-stack width, right to left; C5 all channels claim 1.0
(now with an explicit precedence written into § 4 so the credited winner stops flapping — the
alpha was always identical, only `/rebar claims` was inconsistent); C6 amended only by the
modifier's removal; C7 25.6; C9 rightward; C10 named layers; C11 the offsets as built.

C5 deserves a note: you found the tie-flapping with a diagnostic built for something else, and
that is the second time in the report that a debug tool caught a bug it wasn't for. Keep
building them.

---

## D1 · The bloom line

Struck from PLAN Phase 3, and from Phase 6 where it also appeared. You adjudicated it
correctly. The ladder images stay in `assets/` as the evidence.

---

## Two things carried forward, unresolved

**Motion timings.** 120ms in, 260ms out, 140ms dwell, 3s peek — all guessed from feel, none
played. Phase 6 owns them. Peek's shape (tap vs hold) joins the list now that it is the only
deliberate summon.

**Nothing else.** Both original unknowns are now closed or scheduled: the one-vs-three driver
state question is settled at one cutoff, and it is a step curve rather than a driver.
