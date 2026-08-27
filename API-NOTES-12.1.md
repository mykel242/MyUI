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
| `RegisterStateDriver` for the low-health state | **Unresolved** — no health conditional found — see 4 |
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

## 4. UNRESOLVED — the low-health discrete state has no verified event source

SPEC § 3's discrete layer hangs on `RegisterStateDriver`. Verified:

- `RegisterStateDriver` exists and is a thin wrapper over `RegisterAttributeDriver`
  (`Blizzard_RestrictedAddOnEnvironment/SecureStateDriver.lua:26`).
- It resolves values through `SecureCmdOptionParse`, which is **engine-side** — it is not
  defined anywhere in the Lua source, so the conditional vocabulary cannot be enumerated
  from this checkout.
- `C_Secrets` (`SecretPredicateAPIDocumentation.lua`) is entirely introspection about
  *whether* a value is secret. It offers no comparison and no health predicate.
- Nothing resembling `[hp<20]` appears in the source.

**What still works without it.** Of the driver state's three tells, two need no event:

- Breathe 1.0 ↔ 0.55 — `SetAlpha` accepts secrets, so a scalar curve drives it directly.
- Screen-edge danger hairline — same, alpha 0 → 0.35 by curve.

**What genuinely needs it.** The health number's 12pt → 14pt change. `SetScale` refuses
secrets, and font size is not alpha.

**Proposed resolution if no conditional exists:** two stacked FontStrings, 12pt and 14pt,
cross-faded by curve-driven alpha. Same visual, alpha-only, no event, no inspection. This
is a SPEC § 3 amendment and needs sign-off, not a silent substitution.

**Still to check in game:** `/dump SecureCmdOptionParse("[...]")` against candidate
conditionals. The docs cannot answer this; the client can.

---

## 5. Cooldown Manager

`Interface/AddOns/Blizzard_CooldownViewer` (and `Blizzard_CooldownBroadcaster`) exist.
Not examined — Phase 7 / v2.
