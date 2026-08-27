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

### If that is rejected

Two of the state's three tells need no event at all: `SetAlpha` is `AllowedWhenTainted`,
so a scalar curve drives both the 1.60s breathe and the screen-edge hairline directly.
Only the health number's 12pt → 14pt change needs one, and the alpha-only substitute is
two stacked FontStrings at 12pt and 14pt cross-faded by curve-driven alpha.

## 5. Cooldown Manager

`Interface/AddOns/Blizzard_CooldownViewer` (and `Blizzard_CooldownBroadcaster`) exist.
Not examined — Phase 7 / v2.
