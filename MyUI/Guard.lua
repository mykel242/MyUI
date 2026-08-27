-- MyUI :: Guard.lua
-- The compliance harness. RULES.md § "Compliance harness" asks for a wrapper
-- that errors, pointing back at the rules, the moment a protected value is used
-- somewhere it may not be.
--
-- The one principle, restated because it is the whole file:
--
--     Forwarding a secret value is legal. Inspecting one is not.
--
-- Compat.lua answers "can I safely look at this?". This file answers "am I
-- allowed to?", and its answer is enforced rather than advisory.

local ADDON, ns = ...

local Compat = ns.Compat
local Guard = {}
ns.Guard = Guard

local RULES = "see RULES.md -- forwarding a secret is legal, inspecting one is not"

-- ---------------------------------------------------------------------------
-- Sanctioned sinks
-- ---------------------------------------------------------------------------
-- Which widget setters actually accept a secret from a tainted (addon) caller
-- is NOT uniform, and the obvious-looking call is often the one that refuses.
-- Verified against Blizzard_APIDocumentationGenerated on build 12.1.0.69497;
-- see API-NOTES-12.1.md § 2. Anything not listed here is refused, because an
-- unverified sink is a guess and this file does not guess.

local SANCTIONED = {
    -- method            = doc source for SecretArguments = "AllowedWhenTainted"
    SetAlpha             = "SimpleRegionAPIDocumentation.lua:123",
    SetVertexColor       = "SimpleRegionAPIDocumentation.lua:191",
    SetValue             = "SimpleStatusBarAPIDocumentation.lua:355",
}

-- Named refusals, so the error explains itself instead of just saying no.
local REFUSED = {
    SetScale     = "SetScale is AllowedWhenUntainted -- an addon cannot pass it a secret. "
                .. "Size changes need a discrete event, not a forwarded value (RULES.md).",
    SetColorFill = "SetColorFill is AllowedWhenUntainted. Colour the fill through "
                .. "bar:GetStatusBarTexture():SetVertexColor(...) instead (API-NOTES § 2).",
}

-- ---------------------------------------------------------------------------
-- Violation log
-- ---------------------------------------------------------------------------

Guard.violations = {}
Guard.forwards   = 0
Guard.mode       = "strict"   -- strict = error, warn = log and continue

local MAX_LOGGED = 50

local function Record(message)
    local log = Guard.violations
    log[#log + 1] = message
    if #log > MAX_LOGGED then
        table.remove(log, 1)
    end
end

--- Raise, or log and continue, depending on mode. Always recorded.
local function Violation(message)
    local full = message .. "\n    " .. RULES
    Record(message)
    if Guard.mode == "strict" then
        error("MyUI compliance violation: " .. full, 3)
    end
    if ns.Print then
        ns.Print("|cffff6b61compliance:|r " .. message)
    end
end

Guard.Violation = Violation

--- Discard the violation log. Used by tests and by /myui audit --reset.
function Guard.Reset()
    Guard.violations = {}
    Guard.forwards = 0
end

-- ---------------------------------------------------------------------------
-- The three entry points
-- ---------------------------------------------------------------------------

--- Forward a value into a widget setter. The ONLY sanctioned way to hand
-- anything that might be secret to a frame.
--
--   Guard.Send(bar, "SetValue", UnitHealth("player"))
--
-- A plain value passes through to any setter. A secret is admitted only to a
-- setter verified to accept one from us.
function Guard.Send(obj, method, ...)
    local secret = false
    for i = 1, select("#", ...) do
        if Compat.IsSecret((select(i, ...))) then
            secret = true
            break
        end
    end

    if secret then
        local refusal = REFUSED[method]
        if refusal then
            Violation(("cannot forward a secret to %s -- %s"):format(method, refusal))
            return false
        end
        if not SANCTIONED[method] then
            Violation(("%s is not a verified secret sink. If it really accepts "):format(method)
                      .. "SecretArguments = \"AllowedWhenTainted\", verify it against the "
                      .. "generated API docs and add it to Guard.SANCTIONED with the citation.")
            return false
        end
        Guard.forwards = Guard.forwards + 1
    end

    local ok = Compat.CallN(obj, method, ...)
    if not ok then
        Record(("%s failed on a %s"):format(method, type(obj)))
        return false
    end
    return true
end

--- Assert a value is a plain number, safe for arithmetic.
-- Call this at the boundary of any maths. If the value turns out to be secret,
-- the failure names the place rather than surfacing as an engine throw three
-- frames later.
function Guard.Number(value, context)
    if Compat.IsSecret(value) then
        Violation(("arithmetic on a secret value in %s"):format(context or "?"))
        return nil
    end
    if type(value) ~= "number" then
        Violation(("expected a number in %s, got %s"):format(context or "?", type(value)))
        return nil
    end
    return value
end

--- The deliberate escape hatch, which always fails.
-- If the implementation seems to need an inspection, call this rather than
-- reaching for a workaround. PLAN.md's standing instructions say to stop and
-- raise it; this makes stopping the path of least resistance.
function Guard.Refuse(what)
    Violation(("inspection attempted: %s. The design was built to avoid this -- "):format(what)
              .. "a need for it means a spec misreading, not a missing workaround.")
end

--- True if the value is safe to store, print or branch on.
function Guard.IsPlain(value)
    return not Compat.IsSecret(value)
end

-- ---------------------------------------------------------------------------
-- Curves
-- ---------------------------------------------------------------------------
-- The sanctioned continuous path. UnitHealthPercent(unit, usePredicted, curve)
-- returns the *evaluated* result, so the percentage never enters Lua at all.
-- UnitDocumentation.lua:1431. See API-NOTES-12.1.md § 1.
--
-- Build curves once at load. A curve that has evaluated a secret carries the
-- secret-values flag until SetToDefaults clears it.

--- Build a colour curve from {x, {r,g,b,a}} stops, x in 0..100.
-- Returns nil plus a reason if the client cannot make one, so callers degrade
-- rather than throw on an unexpected build.
function Guard.ColorCurve(stops)
    local util = _G.CurveUtil
    if not util or type(util.CreateColorCurve) ~= "function" then
        return nil, "CurveUtil.CreateColorCurve unavailable"
    end
    local ok, curve = pcall(util.CreateColorCurve)
    if not ok or not curve then
        return nil, "CreateColorCurve failed"
    end
    for _, stop in ipairs(stops) do
        local x, c = stop[1], stop[2]
        local added = pcall(function()
            curve:AddPoint(x, CreateColor(c[1], c[2], c[3], c[4]))
        end)
        if not added then
            return nil, ("AddPoint failed at x=%s"):format(tostring(x))
        end
    end
    return curve
end

--- Forward a unit's health through a curve. Returns whatever the curve yields,
-- which is secret and must only ever be passed onward via Guard.Send.
function Guard.HealthThrough(unit, curve)
    local ok, result = pcall(_G.UnitHealthPercent, unit, true, curve)
    if not ok then
        return nil
    end
    return result
end

--- Same, for power. UnitDocumentation.lua:2749.
function Guard.PowerThrough(unit, curve)
    local ok, result = pcall(_G.UnitPowerPercent, unit, true, curve)
    if not ok then
        return nil
    end
    return result
end

Guard.SANCTIONED = SANCTIONED
Guard.REFUSED = REFUSED
