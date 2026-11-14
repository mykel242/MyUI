# SPEC — Rebar

Decisions only. Where the HTML reference shows alternatives, **this file is authoritative** —
the mock contains rejected explorations that must not be implemented.

Reference resolution for all coordinates below: the mock canvas is **1707 × 960**. Screen
centre is x = 853. Express everything as anchor offsets, never absolute pixels.

---

## 1. The premise

At rest the screen is the game. No frame is permanent. Every element is summoned by cursor,
modifier, state, or the peek key, and returns to its resting alpha when that stops being
true. Position is **fixed forever** — muscle memory survives because nothing ever moves.
Hidden must never mean lost.

Geometry is flat: 1px hairlines, no corner radius, no gradients, no fill above 14% opacity
except a data bar. All life comes from alpha, plus one scale pulse and one slide on entrance.
**The addon ships no texture assets at all** — every element is a solid fill or a 1px line.
See § 6 for why the one planned texture was cut.

---

## 2. Frames, anchors, resting alpha

| Frame | Anchor | Size | Resting alpha |
|---|---|---|---|
| `SelfStack` | BOTTOM, centred, 214 up from bottom edge | 240 wide | 0.35 |
| `Cooldowns` (rhythm line) | 18 below resource bar, centred | 240 × 4 | 0.25 |
| `TargetStrip` | TOP, centred, 20 down from top edge | 400 wide | 0 |
| `Rail` | LEFT, x = 20, vertically centred, 440 tall | 1px hairline | hairline 0.14, dots per § 6 |

### SelfStack internals (relative to the 240-wide group)

- Health bar — 240 × 4, trough `rgba(255,255,255,0.14)`
- Resource bar — 240 × 2, 4 below health
- Cast bar — 240 × 4, 6 below resource
- Health number — 40 wide, right-aligned, 8 left of the bar group, 12pt
- Threshold ticks on the health bar — static geometry, always present:
  - 20% mark at x = 48, `rgba(0,0,0,0.55)` (reads against the fill)
  - 40% mark at x = 96, `rgba(255,255,255,0.25)` (reads against the empty trough)

The ticks are the design's compliance keystone. They are fixed marks; the *bar* crossing them
is the event, and the player's eye does the comparison. Never compute their position from a
value.

### TargetStrip internals

- Name — 11pt, `rgba(240,241,243,1)`, left-aligned at group left
- Level — 11pt, `rgba(173,177,184,1)`, right-aligned at group right
- Health bar — 400 × 3, 20 below the name row
- Cast indicator — 3 × 6 tick, 9 below the bar

---

## 3. Low health — decision: **combined (4d)**

Two mechanisms on two independent channels. They do not duplicate each other.

### Continuous layer — `ColorCurveObject` on the health fill

Curve stops (linear interpolation between them):

| Health | Fill colour |
|---|---|
| 100 | `rgba(240,241,243,0.92)` |
| 58 | `rgba(242,214,150,0.92)` |
| 34 | `rgba(242,170,120,0.92)` |
| 17 | `rgba(242,120,100,0.94)` |
| 6 | `rgba(242,86,80,1)` |

The health number takes the same curve at full opacity.

### Continuous layer — inverted `MaskTexture` on the depleted region

A flat `rgba(242,107,97, α)` wash masked to the **inverse** of the fill, so it occupies only
the empty part of the trough. α ramps 0 → 0.22 across the same range as the curve. The trough
stops being empty space and becomes the thing consuming you. No logic — the mask is the
condition.

### Discrete layer — **one** `RegisterStateDriver` state

Not three. One boundary, one moment. On entry:

- Health number 12pt → 14pt. This is the only type-size change anywhere in the addon, which
  is what makes it register.
- Health group breathes alpha 1.0 ↔ 0.55 at 1.60s.
- A 1px danger hairline appears at the full screen edge, inset 0, at alpha 0.35. No gradient,
  no vignette, no blur. It works because it is the only shape in the design that is not a bar,
  and it lives in peripheral vision where a bar cannot.

Deepest state (if a second driver state is later added — **not in v1**): hairline breathes at
0.80s. v1 ships one state only.

Nothing else in the addon ever changes colour.

---

## 4. Reveal engine — four channels, one arbiter

All four resolve through a single arbiter that computes one target alpha per frame per tick.
Do not let frames manage their own visibility; that is the architectural mistake this design
is most vulnerable to.

| Channel | Trigger | Notes |
|---|---|---|
| Cursor proximity | Cursor within **32 units** of the frame, held **140ms** | The dwell is what stops brushing past while looting from flashing the HUD |
| Modifier held | Alt (primary) or Shift | Instant, no dwell |
| State change | Combat enter/exit, target acquired/lost, low-health driver state | Event-driven only |
| Tap-to-peek | Peek key | Reveals for **3s** on a visible drain clock, then fades |

Arbitration: highest claim wins. When all claims release, the frame returns to its resting
alpha from § 2 — never to zero unless its resting alpha is zero.

Fades: **120ms in, 260ms out.** Out is slower so release feels like settling rather than
snapping.

---

## 5. Rhythm line — **v2, not v1**

Specified fully so nothing is lost, but see PLAN.md: this is deferred out of the first
release as the highest-risk component. Build the addon coherent without it.

- Six cells, **38 × 4, gutter 2**, total 240 × 4. Uniform height forever.
- Position equals ability identity. Order is fixed user configuration. **Never computed.**
- CDM stays alive at alpha 0 doing all tracking. Each cell is a Cooldown frame receiving
  forwarded values and inspecting none.
- `SetSwipeColor` draws the recharge body — the depleting portion is the engine's swipe, not
  a width you calculate.
- `isDisplayingEdge` / `SetEdgeTexture` give the came-up moment a 1px cap for **180ms**. This
  is the peripheral event, delivered by the widget.
- Charges: cell subdivides with a 1px gutter, one segment per charge.
- All six up: line goes solid, one **1.35×** scale pulse. This is the whole point — the line
  going solid is a single peripheral event you never have to read.

**Cut, permanently:** variable cell height or alpha encoding priority. Priority is a ranking,
a ranking is a comparison, no 12.1 mechanism makes it legal, and no future patch will fix it
because it was never data — it was a rotation opinion. Rotation opinions belong to Hekili.

---

## 6. Rail

Left edge, x = 20, 1px hairline at alpha 0.14, 440 tall, vertically centred.

- Dots 10 × 10, first at 40 down from the hairline top, **26 spacing**.
- The two newest items carry name, count and age at rest — no hover required.
  Name 11pt `rgba(240,241,243,1)`; age 10pt `rgba(115,119,126,1)` right-aligned.
- Older items are the dot alone at alpha 0.4.
- Cap at **8 dots**; overflow collapses to a "+N more" hollow square.
- Notifications arrive as a **toast** that speaks once, then collapses into its dot after
  **4s** or on dismissal.

Dot hues by type: blue `rgba(140,200,255,1)`, amber `rgba(255,209,89,1)`, green
`rgba(166,217,140,1)`, violet `rgba(209,179,255,1)`, orange `rgba(242,158,115,1)`.

The rail touches no protected data. It is the safest part of the addon to build.

### Cut: the dot bloom

Earlier drafts placed a 32 × 32 soft bloom behind each dot at 0.16 alpha of the dot's hue.
It was tested against the real game backdrop at 0.16 / 0.30 / 0.45 / 0.65, and at 32 / 56 /
80 px. It is invisible in every combination — a 10px solid dot at full opacity is brighter
than any glow that can sit behind it without becoming a visible smudge. Rendered side by side,
the bloom at 5× spec strength is indistinguishable from no bloom.

The texture is still in `assets/bloom-32.png` if this is ever revisited, but **do not
implement it**. Its removal makes the addon zero-asset, which is more consistent with the
flat-geometry rule than the exception ever was.

Evidence: `assets/bloom-alpha-ladder.png`, `assets/bloom-size-ladder.png`.

---

## 7. Colour table — complete

Fourteen colours, all RGBA float. Nothing outside this list.

```
Fill / primary      rgba(240,241,243,0.92)
Text primary        rgba(240,241,243,1)
Text secondary      rgba(173,177,184,1)
Text tertiary       rgba(115,119,126,1)
Trough              rgba(255,255,255,0.14)
Fill dim            rgba(255,255,255,0.25)
Tick dark           rgba(0,0,0,0.55)
Danger              rgba(242,107,97,1)
Resource accent     rgba(140,211,255,1)
Notif blue          rgba(140,200,255,1)
Notif amber         rgba(255,209,89,1)
Notif green         rgba(166,217,140,1)
Notif violet        rgba(209,179,255,1)
Notif orange        rgba(242,158,115,1)
```

Curve intermediates (§ 3) are interpolation stops, not palette entries.

---

## 8. Motion table

| Event | Motion |
|---|---|
| Reveal in | alpha → target, 120ms |
| Reveal out | alpha → resting, 260ms |
| Toast entrance | slide + fade, 180ms |
| Toast collapse to dot | 4s dwell, then 200ms |
| Peek | 3s visible drain clock |
| Low-health breathe | 1.0 ↔ 0.55, 1.60s |
| Rhythm cell came-up | 1px edge cap, 180ms |
| Rhythm line all-up | 1.35× scale pulse, once |

No easing curve is specified anywhere in this design more expressive than a linear or
standard ease — the restraint is deliberate.

---

## 9. Edit mode

Invisible frames must be findable.

- Screen dims to `rgba(0,0,0,0.55)`; a 106 × 60 grid appears at 0.07 alpha, every 4th line
  at 0.14.
- Every frame gets a 1px ghost outline at `rgba(255,255,255,0.45)` with its name in 10pt
  letterspaced caps, and **its resting alpha printed next to it** (`rest 0.35`).
- Per-frame alpha slider.
- Reveal-group toggle.
- **Preview at rest** button — drops the whole UI to resting alphas over the live game so the
  user can judge the actual quiet state.

---

## 10. Out of scope — say no to these

- Procs are not exposed; nothing here claims to show one.
- Damage meters and ability suggestions stay Blizzard's.
- No Classic support. The curve and CDM do not exist there; a fallback would be a different
  addon. Declare retail-only in the TOC.
- No comparative displays of any kind (§ RULES).
