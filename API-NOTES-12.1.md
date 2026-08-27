# 12.1 ground truth for MyUI

Verified against `Gethe/wow-ui-source` tag 12.1.0, build **12.1.0.69497**, read from
`Interface/AddOns/Blizzard_APIDocumentationGenerated/`. Nothing here is recalled; every
claim cites a file.

Companion to `../Rebar/API-NOTES-12.1.md`, which covers frame walking, viewport and Edit
Mode. This file covers only the mechanisms the HUD design rests on.

---

## Summary

The handoff's four "sanctioned mechanisms" survive verification with **three corrections**.
Two make the design simpler; one is unresolved and blocks part of SPEC § 3.

| Handoff assumption | Verdict |
|---|---|
| `ColorCurveObject` drives continuous colour | **Confirmed, and better than assumed** — see 1 |
| Inverted `MaskTexture` for the depleted wash | **Wrong mechanism** — no inversion flag exists; use reverse fill — see 3 |
| `RegisterStateDriver` for the low-health state | **Refuted** — no health conditional exists; hook `LowHealthFrame` instead — see 4 |
| CDM at alpha 0 + mirror frames | Present as `Blizzard_CooldownViewer`; not yet examined (v2 / Phase 7) |

---

## 1. The forwarding path is a first-class API, not a workaround

`UnitDocumentation.lua:1431`

```
UnitHealthPercent(unit, usePredicted, curve) -> LuaCurveEvaluatedResult
  SecretWhenCurveSecret = true
  SecretReturns = true
  SecretArguments = "AllowedWhenUntainted"
  "Returns percent of health remaining - can be scaled via a curve for display purposes"
  "If no curve is specified, a floating point percentage value. Else, the result of
   evaluating the curve with the percentage as the input."
```

You hand it a curve and receive the *evaluated result*. The percentage never enters Lua.
This is exactly SPEC § 3's continuous layer, and it is the API's intended use rather than
a clever reading of it.

`UnitPowerPercent` (`UnitDocumentation.lua:2749`) has the same shape — the resource bar
gets the same treatment for free.

Curve construction: `CurveUtil.CreateColorCurve()` (`CurveUtilDocumentation.lua:11`),
then `AddPoint(x, colorRGBA)` or `SetPoints{...}` (`LuaColorCurveObjectAPIDocumentation.lua`).
`LuaCurveObject` is the scalar counterpart for non-colour output.

`SetToDefaults` "resets all state on the curve, and clears the secret values flag" — so a
curve that has touched a secret stays flagged until reset. Build curves once at load, before
any secret reaches them.

---

## 2. Which setters accept a secret from a tainted (addon) caller

This is the load-bearing distinction and it is not uniform. `SimpleRegionAPIDocumentation.lua`,
`SimpleStatusBarAPIDocumentation.lua`.

| Setter | `SecretArguments` | Usable by us? |
|---|---|---|
| `SetAlpha` | `AllowedWhenTainted` | **Yes** — adds `SecretAspect.Alpha` |
| `SetVertexColor` | `AllowedWhenTainted` | **Yes** — adds `VertexColor` + `Alpha` |
| `StatusBar:SetValue` | `AllowedWhenTainted` | **Yes** — adds `SecretAspect.BarValue` |
| `SetScale` | `AllowedWhenUntainted` | **No** |
| `StatusBar:SetColorFill` | `AllowedWhenUntainted` | **No** |

Two consequences:

- **Colour the fill via `bar:GetStatusBarTexture():SetVertexColor(...)`, never `SetColorFill`.**
  The obvious-looking call is the one that refuses us.
- **`SetScale` cannot take a secret.** RULES.md's "size changes require an event" is
  confirmed from the source, not inferred.

---

## 3. There is no mask inversion — use reverse fill instead

SPEC § 3 asks for "a flat wash masked to the **inverse** of the fill."

`SimpleMaskTextureAPI` (`SimpleMaskTextureAPIDocumentation.lua`) declares **zero functions**.
Masking is `AddMaskTexture` / `RemoveMaskTexture` on `SimpleTexture`
(`SimpleTextureAPIDocumentation.lua:10`), with no inversion parameter anywhere in the
generated docs. Inversion would require a texture asset with an inverted alpha channel —
which the design forbids, since it ships no assets.

**Substitute:** a second `StatusBar` with `SetReverseFill(true)`
(`SimpleStatusBarAPIDocumentation.lua:79` documents the getter; the setter is its pair),
fed the same forwarded value, tinted `rgba(242,107,97,α)` with α from a scalar curve.
It occupies exactly the depleted region by construction.

This is strictly better than the spec's mechanism: zero assets, no mask, no inspection,
and the "empty part of the trough" is defined by the same secret value that fills the bar.

---

## 4. No health macro conditional exists. Blizzard's own frame is the event.

SPEC.md § 3's discrete layer hangs on `RegisterStateDriver`. Verified:

- `RegisterStateDriver` is a thin wrapper over `RegisterAttributeDriver`
  (`Blizzard_RestrictedAddOnEnvironment/SecureStateDriver.lua:26`) and resolves values
  through `SecureCmdOptionParse`, which is engine-side and absent from the Lua source.
- `C_Secrets` (`SecretPredicateAPIDocumentation.lua`) is entirely introspection about
  *whether* a value is secret. No comparison, no health predicate.

### Measured on a live client, 2026-08-27

**An unrecognised conditional is ignored, so the clause matches.** `[zzznope]` returns
`hit`; `[nozzznope]` returns `miss`. This is the opposite of what the probe first assumed,
and it matters: "unknown" then produces the same signature as "known and true", so a bare
`[hp<20]` reading `hit` proves nothing at unknown health.

The probe therefore tests numeric candidates as a **complementary pair** — one clause that
must always be false and one that must always be true if the conditional is real:

| Clauses | Unknown | Real |
|---|---|---|
| `[hp<0]` / `[hp<101]` | `hit/hit` | `miss/hit` |

That discriminates at any health. Both baselines are measured with a nonsense conditional
rather than assumed. Result on this client:

```
control: known     [combat] / [nocombat]        miss/hit    --
control: unknown   [zzznope] / [nozzznope]      hit/miss    --
control: unknown n [zzznope<0] / [zzznope<101]  hit/hit     --
hp                 [hp<0] / [hp<101]            hit/hit     not recognised
health             [health<0] / [health<101]    hit/hit     not recognised
hurt, lowhealth                                 hit/miss    not recognised
```

**No health conditional exists.** `RegisterStateDriver` cannot deliver SPEC § 3's state.

### The event source that does exist: `LowHealthFrame`

`Blizzard_FrameXML/Shared/LowHealthFrame.lua`, frame declared in
`Blizzard_FrameXML/Mainline/LowHealthFrame.xml:3` as a named global. It is Blizzard's own
low-health screen flash, and it does exactly what RULES.md forbids us:

```lua
function LowHealthFrameMixin:GetHealthPercent()
    local maxHealth = UnitHealthMax("player")
    if maxHealth <= 0.0 then return 1.0 end
    return UnitHealth("player") / maxHealth
end

function LowHealthFrameMixin:IsAtLowHealth()
    return self:GetHealthPercent() <= self.lowHealthPercentStart   -- .35
end
```

Blizzard's code is untainted and may do that. **We may not copy it — but we may watch the
result.** `HookScript("OnShow", ...)` on `LowHealthFrame` delivers a discrete event at the
moment health crosses the threshold, computed entirely inside Blizzard's own access. We
read no health, compute no percentage, and compare nothing. The threshold is Blizzard's,
never ours.

This satisfies the one principle, but it is **not one of RULES.md's four sanctioned
mechanisms** — it is a fifth. That is a rules amendment and wants sign-off rather than
quiet adoption.

Because it is a real event and not a forwarded secret, everything a driver state could
carry is legal inside it, including the `SetScale` and font-size changes that a forwarded
value can never drive (see § 2).

**What it costs:**

- **Threshold is fixed at 0.35**, not the ~20% SPEC's ticks imply. `lowHealthPercentStart`
  is a frame field, so it is readable but not ours to set.
- **Gated by the `doNotFlashLowHealthWarning` CVar.** If the player has turned the flash
  off, the frame never shows and the event never arrives. `GetCVarBool` is not secret, so
  this is detectable and worth warning about at load.
- **Suppressed while a fullscreen panel is open**, and the same frame is reused for the
  in-combat fullscreen flash. We cannot tell the two apart, but the fullscreen case only
  fires when a fullscreen panel is up, where the HUD is hidden anyway.

### What actually needs the event — two of the three tells, not one

An earlier reading of this claimed a curve could drive the breathe. It cannot. A curve maps
**health to a value**; a breathe maps **time to a value**. Nothing in the curve APIs
oscillates.

| SPEC § 3 tell | Needs an event? |
|---|---|
| Screen-edge hairline appears at alpha 0.35 | **No.** Static appearance, alpha as a function of health — exactly what a curve does. The v1 hairline does not breathe; SPEC defers that to a second driver state that v1 does not ship |
| Health number 12pt → 14pt | **Yes.** `SetScale` is `AllowedWhenUntainted`, and font size is not alpha |
| Health group breathes 1.0 ↔ 0.55 at 1.60s | **Yes.** An `AnimationGroup` has to be started, and only an event can start one |

Substitutes exist for both, and both are visibly worse:

- **Font size** — two stacked FontStrings at 12pt and 14pt, cross-faded by curve-driven
  alpha. Faithful; costs one extra FontString.
- **Breathe** — a permanently animating overlay whose base alpha comes from a curve, so it
  is invisible at full health. But alpha composites *additively*: the overlay can pulse the
  group brighter, never dim it to 0.55 as specified. Dimming would need a backdrop-coloured
  wash over the group, which tints as well as dims because the game background behind it is
  not a fixed colour. There is no faithful alpha-only breathe.

So without an event, one tell ships as specified, one ships with an extra frame, and one
cannot ship at all.

## 6. Audit of shipped unit-frame addons

Four popular addons linted with `rules_lint.py --audit`, 2026-08-27. The portable rules
(R1/R2/R4/R6) say whether an addon still does what 12.1 forbids; the mechanism scan says
whether it has actually adopted the new APIs.

| Addon | TOC | Lua | R1 | R2 | R6 | 12.1 mechanisms |
|---|---|---|---|---|---|---|
| oUF | 120100 | 39 | 1 | 1 | 7 | ColorCurve, ReverseFill, UnitHealthPercent, C_Secrets |
| Plater | 120100 | 185 | 3 | 2 | 39 | ColorCurve, ReverseFill, UnitHealthPercent, C_Secrets |
| Cell | 120005 | 174 | 4 | 0 | 22 | ColorCurve, ReverseFill, UnitPowerPercent, C_Secrets |
| ShadowedUnitFrames | 30300 | 35 | 3 | 6 | 5 | none |

ShadowedUnitFrames is a control: TOC 30300, no 12.1 mechanism anywhere, and `fader.lua:131`
reads `UnitHealth(unit) ~= UnitHealthMax(unit)`. That is the pre-12.1 pattern RULES.md
warns is everywhere, and it is what an untargeted search would have surfaced first.

The remaining hits in the 12.1-aware three are mostly cast and threat code, not health.
**They have all migrated their health paths and none of them hooks `LowHealthFrame`.**

### Three corrections this produced, all to our own code

1. **The namespace is `C_CurveUtil`, not `CurveUtil`.** `CurveUtilDocumentation.lua`
   declares `Namespace = "C_CurveUtil"`. `Guard.ColorCurve` had it wrong and would have
   returned nil on the live client while every offline test passed, because the mock
   encoded the same wrong assumption. Third time that has happened on this project.

2. **The curve input is a fraction, 0..1 — not a percentage.**
   `Blizzard_SharedXMLBase/CurveConstants.lua` builds `ZeroToOne` from `AddPoint(0.0, 0.0)`
   to `AddPoint(1.0, 1.0)`, and `ScaleTo100` exists precisely because the input is not
   already a percentage. SPEC's stops are percentages and must be divided by 100.

3. **`Enum.LuaCurveType.Step` exists**, and it is the piece the design was missing.

### A threshold without a branch — Plater's execute-range technique

`Plater.lua:11693` and `:7120`. A Step curve holding one alpha below a cutoff and another
above it, evaluated against health, yields an alpha that flips at the boundary. It is
forwarded straight to `SetAlpha` and never compared:

```lua
local curve = C_CurveUtil.CreateColorCurve()
curve:SetType(Enum.LuaCurveType.Step)
curve:AddPoint(0,    CreateColor(0, 0, 0, 1))   -- below the cutoff
curve:AddPoint(0.35, CreateColor(0, 0, 0, 0))   -- above it

local _, _, _, a = UnitHealthPercent(unit, true, curve):GetRGBA()
frame:SetAlpha(a)                                -- forwarded, never read
```

Only the alpha channel carries signal; the colour channels are unused. Shipped as
`Guard.StepCurve` and `Guard.AlphaAt`.

### What this does to SPEC § 3

A hard boundary is now expressible with no event at all, which changes the answer recorded
in § 4:

| Tell | With a step curve |
|---|---|
| Screen-edge hairline at 0.35 | Forward the step alpha to `SetAlpha`. Done |
| Number 12pt → 14pt | Two stacked FontStrings, cross-faded by step alpha. The step makes the change instant rather than a fade |
| Breathe 1.0 ↔ 0.55 at 1.60s | Two copies of the health group — one steady, one running a permanent 1.60s alpha animation — cross-faded by step alpha. The animation never starts or stops, so no event is needed to start it |

The cost is duplicated frames for two of the three, and a threshold we choose rather than
Blizzard's 0.35. Against that, hooking `LowHealthFrame` costs a CVar dependency, a fixed
threshold, and a fifth mechanism outside RULES.md.

**Recommendation: step curves.** They stay inside the existing rules, keep the threshold
ours, and are the technique a shipped 12.1 addon already relies on.

## 5. Cooldown Manager

`Interface/AddOns/Blizzard_CooldownViewer` (and `Blizzard_CooldownBroadcaster`) exist.
Not examined — Phase 7 / v2.
