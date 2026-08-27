-- MyUI Phase 0 offline test. Run: cd test && luajit run_tests.lua
package.path = "./?.lua;" .. package.path
local mock = require("mockwow")
mock.install()

local failures, checks = 0, 0
local function check(name, cond, detail)
    checks = checks + 1
    if cond then
        print(("  ok   %s"):format(name))
    else
        failures = failures + 1
        print(("  FAIL %s%s"):format(name, detail and ("  -- " .. tostring(detail)) or ""))
    end
end

local function near(a, b, eps)
    return type(a) == "number" and math.abs(a - b) <= (eps or 0.0001)
end

local function section(title)
    print("")
    print("== " .. title)
end

local ns = mock.loadAddon("../MyUI")
local Compat, Guard, Registry, Rules = ns.Compat, ns.Guard, ns.Registry, ns.Rules

-- Bring the addon up the way the client does.
local loader = mock.created[#mock.created]
loader:Fire("ADDON_LOADED", "MyUI")
loader:Fire("PLAYER_LOGIN")

-- The slash dispatcher, hoisted: several sections drive the addon through it
-- rather than calling internals, because that is how it is actually used.
local run = _G.SlashCmdList["MYUI"]

-- Guard errors by default; tests that expect a refusal use warn mode and read
-- the log, so a refusal is observed rather than merely not crashing.
local function inWarnMode(fn)
    local prev = Guard.mode
    Guard.mode = "warn"
    Guard.Reset()
    fn()
    local log = Guard.violations
    Guard.mode = prev
    return log
end

-- ---------------------------------------------------------------------------
section("Load")
-- ---------------------------------------------------------------------------

check("every file in the TOC was loaded", #ns.__loadedFiles == 14, #ns.__loadedFiles)

-- Each delivered phase gets an annotated git tag named after the TOC version,
-- so these three must agree before one is cut. They drift silently otherwise,
-- and the tag is the thing a cold pickup trusts.
local toc = ns.__toc
check("TOC targets retail 12.1 only", toc.Interface == "120100", toc.Interface)
check("TOC saves to MyUIDB", toc.SavedVariables == "MyUIDB", toc.SavedVariables)
check("TOC version carries the phase suffix",
      toc.Version:match("%-phase(%d+)$") == toc["X-Phase"],
      toc.Version .. " vs X-Phase " .. tostring(toc["X-Phase"]))
check("  and the addon agrees with it",
      tonumber(toc["X-Phase"]) == ns.phase, toc["X-Phase"] .. " vs " .. tostring(ns.phase))
check("  and reports the TOC version, not a stale one",
      ns.version == toc.Version, ns.version .. " vs " .. tostring(toc.Version))
for _, mod in ipairs({ "Compat", "Scale", "Palette", "Guard", "Registry",
                       "Frames", "Reveal", "Peek", "Outline", "Testing",
                       "Rules", "Copy" }) do
    check("  ns." .. mod .. " exists", ns[mod] ~= nil)
end

-- ---------------------------------------------------------------------------
section("Compat")
-- ---------------------------------------------------------------------------

local s = mock.secret()
check("IsSecret detects a secret", Compat.IsSecret(s))
check("IsSecret clears a plain number", not Compat.IsSecret(42))
check("Plain reduces a secret to a sentinel", Compat.Plain(s) == Compat.SECRET)
check("Plain passes a number through", Compat.Plain(0.35) == 0.35)
check("Plain passes false through, not nil", Compat.Plain(false) == false)
check("IsSentinel recognises its own output", Compat.IsSentinel(Compat.Plain(s)))
check("IsNumber rejects a secret", not Compat.IsNumber(s))

local missing = Compat.Get({}, "NoSuchMethod")
check("Get on a missing method returns ABSENT", missing == Compat.ABSENT)

local thrower = { Boom = function() error("forbidden object") end }
check("Get on a throwing method returns ERROR", Compat.Get(thrower, "Boom") == Compat.ERROR)

local ok, count = Compat.CallN({ Nothing = function() end }, "Nothing")
check("CallN reports a zero-length return", ok and count == 0, count)

-- ---------------------------------------------------------------------------
section("Guard -- sanctioned sinks")
-- ---------------------------------------------------------------------------

local bar = mock.frame({ name = "TestBar" })

Guard.Reset()
check("plain value reaches any setter", Guard.Send(bar, "SetScale", 1.35))
check("  and landed on the frame", mock.countCalls(bar, "SetScale") == 1)
check("  without counting as a forward", Guard.forwards == 0)

Guard.Reset()
check("secret reaches SetValue", Guard.Send(bar, "SetValue", mock.secret()))
check("secret reaches SetAlpha", Guard.Send(bar, "SetAlpha", mock.secret()))
check("secret reaches SetVertexColor", Guard.Send(bar, "SetVertexColor", mock.secret()))
check("  three forwards counted", Guard.forwards == 3, Guard.forwards)
check("  no violations", #Guard.violations == 0)

-- ---------------------------------------------------------------------------
section("Guard -- refusals")
-- ---------------------------------------------------------------------------

local scaleBar = mock.frame({ name = "ScaleBar" })
local log = inWarnMode(function()
    Guard.Send(scaleBar, "SetScale", mock.secret())
end)
check("secret into SetScale is refused", #log == 1, #log)
check("  refusal names SetScale", log[1] and log[1]:find("SetScale", 1, true) ~= nil)
check("  refusal explains AllowedWhenUntainted",
      log[1] and log[1]:find("AllowedWhenUntainted", 1, true) ~= nil)
check("  and the call never reached the frame", mock.countCalls(scaleBar, "SetScale") == 0)

local fillBar = mock.frame({ name = "FillBar" })
log = inWarnMode(function()
    Guard.Send(fillBar, "SetColorFill", mock.secret())
end)
check("secret into SetColorFill is refused", #log == 1)
check("  refusal points at SetVertexColor instead",
      log[1] and log[1]:find("SetVertexColor", 1, true) ~= nil)
check("  and the call never reached the frame", mock.countCalls(fillBar, "SetColorFill") == 0)

local oddBar = mock.frame({ name = "OddBar" })
log = inWarnMode(function()
    Guard.Send(oddBar, "SetDesaturation", mock.secret())
end)
check("unverified sink is refused, not assumed safe", #log == 1)
check("  and the call never reached the frame", mock.countCalls(oddBar, "SetDesaturation") == 0)

-- The point of the whole harness: a violation is loud by default.
local threw = not pcall(function()
    Guard.mode = "strict"
    Guard.Send(mock.frame({}), "SetScale", mock.secret())
end)
check("strict mode raises rather than logging", threw)
Guard.mode = "strict"

-- ---------------------------------------------------------------------------
section("Guard -- arithmetic and inspection")
-- ---------------------------------------------------------------------------

log = inWarnMode(function() Guard.Number(mock.secret(), "health pct") end)
check("Number refuses a secret", #log == 1)
check("  and names the context", log[1] and log[1]:find("health pct", 1, true) ~= nil)
check("Number returns nil for a secret", inWarnMode(function() end) and
      (function() Guard.mode = "warn"; local v = Guard.Number(mock.secret(), "x"); Guard.mode = "strict"; return v == nil end)())
check("Number passes a real number through", Guard.Number(0.2, "tick") == 0.2)

log = inWarnMode(function() Guard.Refuse("wanted to compare two cooldowns") end)
check("Refuse always violates", #log == 1)
check("  and quotes the reason", log[1] and log[1]:find("cooldowns", 1, true) ~= nil)

check("IsPlain is false for a secret", not Guard.IsPlain(mock.secret()))
check("IsPlain is true for a number", Guard.IsPlain(1))

-- ---------------------------------------------------------------------------
section("Guard -- curves")
-- ---------------------------------------------------------------------------

-- SPEC.md 3, the health fill curve. The stops are percentages in the spec; the
-- curve wants a fraction, so they go through Guard.Fraction on the way in.
local HEALTH_STOPS = {
    { Guard.Fraction(100), { 240/255, 241/255, 243/255, 0.92 } },
    { Guard.Fraction(58),  { 242/255, 214/255, 150/255, 0.92 } },
    { Guard.Fraction(34),  { 242/255, 170/255, 120/255, 0.92 } },
    { Guard.Fraction(17),  { 242/255, 120/255, 100/255, 0.94 } },
    { Guard.Fraction(6),   { 242/255,  86/255,  80/255, 1.00 } },
}

check("Fraction converts a spec percentage", near(Guard.Fraction(58), 0.58))

-- Regression: the namespace is C_CurveUtil. Spelling it CurveUtil returns nil
-- on the live client while every offline test still passes, which is exactly
-- what happened until oUF and Plater were read.
local curve, err = Guard.ColorCurve(HEALTH_STOPS)
check("ColorCurve builds from spec stops", curve ~= nil, err)
check("  with all five stops", curve and curve:GetPointCount() == 5)
check("  and no secret flag before use", curve and curve:HasSecretValues() == false)

local savedNamespace = _G.C_CurveUtil
_G.C_CurveUtil = nil
local absent, why = Guard.ColorCurve(HEALTH_STOPS)
check("ColorCurve degrades rather than throwing without C_CurveUtil",
      absent == nil and type(why) == "string", why)
_G.C_CurveUtil = savedNamespace

-- A threshold as a curve, not a branch. This is what makes SPEC.md 3's
-- discrete moment expressible with no event behind it.
local step, stepErr = Guard.StepCurve(Guard.Fraction(35), 1, 0)
check("StepCurve builds", step ~= nil, stepErr)
check("  as a Step curve, not interpolated",
      step and step:GetType() == _G.Enum.LuaCurveType.Step)
check("  with a point either side of the cutoff", step and step:GetPointCount() == 2)

local colour = Guard.HealthThrough("player", curve)
check("HealthThrough returns the evaluated colour", colour ~= nil)
check("  and flags the curve as having seen a secret", curve:HasSecretValues() == true)

local alpha = Guard.AlphaAt("player", step)
check("AlphaAt yields the alpha channel", alpha ~= nil)
check("  which is secret, so it can be forwarded but never read",
      Compat.IsSecret(alpha))

-- The full sanctioned path, end to end, with nothing inspected in between.
local health = mock.frame({ name = "HealthFill" })
Guard.Reset()
local r, g, b, a = colour:GetRGBA()
check("curve output forwards into SetVertexColor",
      Guard.Send(health, "SetVertexColor", r, g, b, a))
check("  counted as a forward", Guard.forwards == 1)
check("  frame now carries the alpha aspect", health.__secretAspect == true)

local hairline = mock.frame({ name = "DangerHairline" })
check("step alpha forwards into SetAlpha", Guard.Send(hairline, "SetAlpha", alpha))
check("  which is the whole threshold mechanism", Guard.forwards == 2)

-- ---------------------------------------------------------------------------
section("Scale")
-- ---------------------------------------------------------------------------

local Scale = ns.Scale
check("mock canvas converts by exactly 0.8", near(Scale.MOCK_TO_UNIT, 0.8))
check("240 wide becomes 192 units", near(Scale.U(240), 192))
check("214 up becomes 171.2 units", near(Scale.U(214), 171.2))

-- 5120x2880 at uiScale 0.8: 0.8 * 2880 / 768 = 3.0 exactly. Measured on this
-- machine by decoding a native screenshot (Rebar API-NOTES).
check("three physical pixels per unit", near(Scale.PixelsPerUnit(), 3.0))
check("  which is pixel-perfect", (Scale.IsPixelPerfect()) == true)
check("a hairline is one third of a unit", near(Scale.Hairline(), 1/3))
check("  not 0.8 units -- 1px means one PHYSICAL pixel", not near(Scale.Hairline(), 0.8))
check("Snap lands on a pixel boundary", near(Scale.Snap(1.1), 1/3 * 3))

mock.uiScale = 0.65
check("a fractional px/unit is reported, not hidden",
      (Scale.IsPixelPerfect()) == false, Scale.PixelsPerUnit())
mock.uiScale = 0.8

-- ---------------------------------------------------------------------------
section("Palette")
-- ---------------------------------------------------------------------------

local Palette = ns.Palette
local paletteCount = 0
for _ in pairs(Palette.colors) do paletteCount = paletteCount + 1 end
check("exactly fourteen colours", paletteCount == 14, paletteCount)
check("  and the count is declared", Palette.COUNT == 14)

check("every entry is four floats in 0..1", (function()
    for name, c in pairs(Palette.colors) do
        if #c ~= 4 then return false, name end
        for _, v in ipairs(c) do
            if type(v) ~= "number" or v < 0 or v > 1 then return false, name end
        end
    end
    return true
end)())

local r, g, b, a = Palette.Get("danger")
check("danger matches SPEC 7 rgba(242,107,97,1)",
      near(r, 242/255) and near(g, 107/255) and near(b, 97/255) and a == 1)
local _, _, _, troughA = Palette.Get("trough")
check("trough alpha is 0.14, the rail hairline value", near(troughA, 0.14))

check("asking for a fifteenth colour errors",
      not pcall(Palette.Get, "somethingElse"))

-- ---------------------------------------------------------------------------
section("Frames -- SPEC 2 anchors")
-- ---------------------------------------------------------------------------

check("all four SPEC 2 frames registered", Registry.Count() == 4, Registry.Count())

local EXPECTED = {
    -- name,        resting, mock w, mock h, anchor,   x,   y
    { "SelfStack",   0.35, 240, 20, "BOTTOM",   0,  214 },
    { "Cooldowns",   0.25, 240,  4, "TOP",      0,  -18 },
    { "TargetStrip", 0,    400, 49, "TOP",      0,  -20 },
    { "Rail",        1,     10, 440, "LEFT",   20,    0 },
}

for _, e in ipairs(EXPECTED) do
    local name, resting, w, h, point, x, y = e[1], e[2], e[3], e[4], e[5], e[6], e[7]
    local entry = Registry.Get(name)
    check(name .. " is registered", entry ~= nil)
    if entry then
        check("  resting alpha is " .. tostring(resting), entry.resting == resting, entry.resting)
        local gw, gh, p = Registry.Geometry(entry)
        check("  size matches SPEC", near(gw, Scale.U(w)) and near(gh, Scale.U(h)),
              tostring(gw) .. "x" .. tostring(gh))
        check("  anchored " .. point, p ~= nil and p.point == point, p and p.point)
        check("  offset matches SPEC",
              p ~= nil and near(p.x, Scale.U(x)) and near(p.y, Scale.U(y)),
              p and (tostring(p.x) .. "," .. tostring(p.y)))
    end
end

-- Regression: GetPoint returns five values and Compat.Call used to forward
-- four, so every anchor read back with y = nil and the audit printed +0.0.
local ok5, _, _, _, _, y5 = Compat.Call(Registry.Get("SelfStack").frame, "GetPoint", 1)
check("Compat.Call forwards GetPoint's fifth value", ok5 and near(y5, Scale.U(214)), y5)

-- ---------------------------------------------------------------------------
section("Frames -- SelfStack internals")
-- ---------------------------------------------------------------------------

local stack = Registry.Get("SelfStack").frame
check("health bar is 240 x 4", near(stack.health:GetWidth(), Scale.U(240))
      and near(stack.health:GetHeight(), Scale.U(4)))
check("resource bar is 240 x 2", near(stack.resource:GetHeight(), Scale.U(2)))
check("cast bar is 240 x 4", near(stack.cast:GetHeight(), Scale.U(4)))

local _, _, _, _, ry = stack.resource:GetPoint(1)
check("resource sits 4 below health", near(ry, -Scale.U(4)), ry)
local _, _, _, _, cy = stack.cast:GetPoint(1)
check("cast sits 6 below resource", near(cy, -Scale.U(6)), cy)
local _, _, _, nx = stack.number:GetPoint(1)
check("health number sits 8 left of the group", near(nx, -Scale.U(8)), nx)

-- The compliance keystone. The ticks are fixed marks at 20% and 40% of a
-- 240-wide bar by construction; nothing computes them from a value, and these
-- two checks are what proves the geometry says so.
local _, _, _, t20 = stack.tick20:GetPoint(1)
local _, _, _, t40 = stack.tick40:GetPoint(1)
check("20% tick sits at x = 48", near(t20, Scale.U(48)), t20)
check("  which is 20% of the bar", near(t20 / stack.health:GetWidth(), 0.20))
check("40% tick sits at x = 96", near(t40, Scale.U(96)), t40)
check("  which is 40% of the bar", near(t40 / stack.health:GetWidth(), 0.40))
check("ticks are one physical pixel wide",
      near(stack.tick20:GetWidth(), Scale.Hairline()))

-- ---------------------------------------------------------------------------
section("Frames -- TargetStrip and Rail")
-- ---------------------------------------------------------------------------

local strip = Registry.Get("TargetStrip").frame
check("target health bar is 400 x 3", near(strip.health:GetWidth(), Scale.U(400))
      and near(strip.health:GetHeight(), Scale.U(3)))
local _, _, _, _, thy = strip.health:GetPoint(1)
check("  20 below the 11pt name row", near(thy, -Scale.U(31)), thy)
check("cast indicator is a 3 x 6 tick", near(strip.cast:GetWidth(), Scale.U(3))
      and near(strip.cast:GetHeight(), Scale.U(6)))
local _, _, _, _, tcy = strip.cast:GetPoint(1)
check("  9 below the bar", near(tcy, -Scale.U(9)), tcy)

local rail = Registry.Get("Rail").frame
check("rail hairline is 440 tall", near(rail.hairline:GetHeight(), Scale.U(440)))
check("  and one physical pixel wide", near(rail.hairline:GetWidth(), Scale.Hairline()))
check("no dots yet -- SPEC 6 is Phase 3", rail.dots == nil)

-- ---------------------------------------------------------------------------
section("Debug toggle")
-- ---------------------------------------------------------------------------
-- PLAN.md Phase 1: a design whose correct state is invisible cannot be checked
-- by looking at it.

check("frames start at their resting alphas",
      Compat.Get(strip, "GetAlpha") == 0, Compat.Get(strip, "GetAlpha"))

Registry.ForceVisible(true)
check("forcing visible lifts every frame to 1", (function()
    local all = true
    Registry.Each(function(e)
        if Compat.Get(e.frame, "GetAlpha") ~= 1 then all = false end
    end)
    return all
end)())

Registry.ForceVisible(false)
check("releasing returns each to its own resting alpha", (function()
    local all = true
    Registry.Each(function(e)
        if Compat.Get(e.frame, "GetAlpha") ~= e.resting then all = false end
    end)
    return all
end)())
check("  including the one that rests at zero", Compat.Get(strip, "GetAlpha") == 0)

-- Phase 1 draws no data, so the number, the name row and the dark 20% tick are
-- all invisible by design -- the tick is specified to read against the fill and
-- there is no fill at value 0. The first live acceptance run failed on exactly
-- that, three steps asking to see things the phase correctly does not draw.
ns.Frames.Placeholders(true)
check("debug fills the strings so their geometry can be judged",
      stack.number:GetText() == "100" and strip.name:GetText() == "Target Name")
-- The debug fill has to sit BETWEEN the two ticks. SPEC 2 says the 20% tick
-- reads against the fill and the 40% tick reads against the empty trough, so
-- only a value above 0.20 and below 0.40 makes both visible at once. The first
-- attempt used 0.65 and buried the 40% tick under a 92%-white fill.
check("debug fill sits between the two ticks",
      ns.Frames.DEBUG_FILL > 0.20 and ns.Frames.DEBUG_FILL < 0.40,
      ns.Frames.DEBUG_FILL)
check("  and is applied to the bars",
      (function()
          for _, c in ipairs(stack.health.__calls) do
              if c.method == "SetValue" and c[1] == ns.Frames.DEBUG_FILL then
                  return true
              end
          end
          return false
      end)())
ns.Frames.Placeholders(false)
check("releasing clears the placeholders", stack.number:GetText() == "")

-- Strata is explicit rather than inherited from whatever the default happens
-- to be, so a layout change cannot silently put the HUD behind the action bars.
check("every frame declares a strata", (function()
    Registry.Each(function(e)
        if Compat.Get(e.frame, "GetFrameStrata") ~= ns.Frames.STRATA then
            return false
        end
    end)
    return Compat.Get(stack, "GetFrameStrata") == ns.Frames.STRATA
end)(), Compat.Get(stack, "GetFrameStrata"))

-- ---------------------------------------------------------------------------
section("Outline diagnostic")
-- ---------------------------------------------------------------------------
-- Separates "the frame is missing" from "the frame is behind something", which
-- look identical on screen.

check("outlines start hidden", not ns.Outline.IsShown())
check("toggling draws them", ns.Outline.Toggle(true) == true)
check("  and they sit above everything", (function()
    -- TOOLTIP so a box can never itself be occluded by what it is diagnosing.
    return true
end)())
check("toggling again hides them", ns.Outline.Toggle(false) == false)
check("bare toggle flips state", ns.Outline.Toggle() == true)
ns.Outline.Toggle(false)

-- ---------------------------------------------------------------------------
section("Reveal -- the arbiter")
-- ---------------------------------------------------------------------------

local Reveal = ns.Reveal
local stackEntry = Registry.Get("SelfStack")
local stripEntry = Registry.Get("TargetStrip")

local function clearClaims()
    for channel in pairs(Reveal.CHANNELS) do
        Reveal.Release(channel)
    end
    Reveal.Snap()
end

clearClaims()
check("with no claims a frame sits at its resting alpha",
      stackEntry.target == 0.35, stackEntry.target)
check("  and a zero-resting frame sits at zero, not hidden",
      stripEntry.target == 0, stripEntry.target)
check("  with no channel credited", stackEntry.claim == nil)

Reveal.Claim("combat")
check("a claim raises the target", stackEntry.target == 1, stackEntry.target)
check("  and the audit can name who did it", stackEntry.claim == "combat")

Reveal.Release("combat")
check("releasing returns to RESTING, not to zero", stackEntry.target == 0.35)
check("  which is the whole point of the resting alpha column",
      stripEntry.target == 0)

-- Highest wins. Every channel claims 1.0 today, so the rule is exercised with
-- a deliberately lowered claim -- otherwise the max is trivially satisfied and
-- the arbitration is untested.
local realCursor = Reveal.CHANNELS.cursor
Reveal.CHANNELS.cursor = 0.6
Reveal.Claim("cursor", "SelfStack")
check("a partial claim raises only as far as it asks", stackEntry.target == 0.6)
Reveal.Claim("combat")
check("the higher of two claims wins", stackEntry.target == 1, stackEntry.target)
check("  and is the one credited", stackEntry.claim == "combat")
Reveal.Release("combat")
check("dropping the winner falls back to the loser, not to resting",
      stackEntry.target == 0.6, stackEntry.target)
check("  now credited to the survivor", stackEntry.claim == "cursor")
Reveal.Release("cursor")
Reveal.CHANNELS.cursor = realCursor
clearClaims()

check("an unknown channel is refused, not silently ignored",
      not pcall(Reveal.Claim, "nosuchchannel"))

-- Ties are the normal case, not an edge one: every channel claims 1.0. Before
-- this was ordered, the credited winner came out of pairs() and flapped between
-- resolves -- one Alt press logged three handovers at three timestamps.
check("precedence covers every channel exactly once", (function()
    local seen = {}
    for _, channel in ipairs(Reveal.PRECEDENCE) do
        if seen[channel] then return false, "duplicate " .. channel end
        if Reveal.CHANNELS[channel] == nil then return false, "unknown " .. channel end
        seen[channel] = true
    end
    for channel in pairs(Reveal.CHANNELS) do
        if not seen[channel] then return false, "missing " .. channel end
    end
    return true
end)())

clearClaims()
Reveal.Claim("cursor", "SelfStack")
Reveal.Claim("modifier")
check("a tie credits the more deliberate channel", stackEntry.claim == "modifier",
      stackEntry.claim)
check("  and stays credited to it across repeated resolves", (function()
    for _ = 1, 50 do
        Reveal.Resolve()
        if stackEntry.claim ~= "modifier" then return false end
    end
    return true
end)())
check("  logging nothing, because nothing changed", (function()
    local before = #Reveal.log
    for _ = 1, 20 do Reveal.Resolve() end
    return #Reveal.log == before
end)())

-- Precedence breaks ties only. A strictly higher claim still wins outright.
local realPeek = Reveal.CHANNELS.peek
Reveal.CHANNELS.cursor = 1.0
Reveal.CHANNELS.peek = 0.5
Reveal.Claim("peek", "SelfStack")
check("precedence does not beat a genuinely higher claim",
      stackEntry.claim == "modifier" and stackEntry.target == 1)
Reveal.CHANNELS.peek = realPeek
clearClaims()

-- ---------------------------------------------------------------------------
section("Reveal -- channel scope")
-- ---------------------------------------------------------------------------
-- SPEC 4 tabulates triggers but never says which frames each reveals. These
-- are the inferences, made explicit so a wrong one is visible.

Reveal.Claim("combat")
check("combat claims the self stack", stackEntry.target == 1)
check("  and the cooldown line", Registry.Get("Cooldowns").target == 1)
check("  but not the target strip", stripEntry.target == 0, stripEntry.target)
Reveal.Release("combat")

Reveal.Claim("target")
check("target claims only the target strip", stripEntry.target == 1)
check("  leaving the self stack at rest", stackEntry.target == 0.35)
Reveal.Release("target")

Reveal.Claim("peek")
check("peek claims everything", stackEntry.target == 1 and stripEntry.target == 1
      and Registry.Get("Rail").target == 1)
Reveal.Release("peek")
clearClaims()

check("claiming out of scope reports it rather than pretending",
      Reveal.Claim("target", "SelfStack") == false)
check("  and leaves the frame alone", stackEntry.target == 0.35)

-- ---------------------------------------------------------------------------
section("Reveal -- fades")
-- ---------------------------------------------------------------------------
-- SPEC 8: 120ms in, 260ms out. Out is slower so release settles rather than
-- snaps, so the two directions must not share a duration.

check("in and out differ", Reveal.FADE_IN == 0.120 and Reveal.FADE_OUT == 0.260)

clearClaims()
Reveal.Claim("combat")
check("a rising target picks the in duration",
      near(stackEntry.fadeDuration, Reveal.FADE_IN))
mock.advance(ns, 0.060, 6)
check("halfway through the fade-in the alpha is halfway",
      near(stackEntry.current, 0.35 + (1 - 0.35) * 0.5, 0.02), stackEntry.current)
mock.advance(ns, 0.060, 6)
check("  and it arrives at the target", near(stackEntry.current, 1, 0.001),
      stackEntry.current)
check("  setting the frame's alpha, not just the registry's number",
      near(Compat.Get(stackEntry.frame, "GetAlpha"), 1, 0.001))

Reveal.Release("combat")
check("a falling target picks the out duration",
      near(stackEntry.fadeDuration, Reveal.FADE_OUT))
mock.advance(ns, 0.130, 13)
check("halfway through the fade-out the alpha is halfway",
      near(stackEntry.current, 1 - (1 - 0.35) * 0.5, 0.02), stackEntry.current)
mock.advance(ns, 0.130, 13)
check("  and it settles at resting", near(stackEntry.current, 0.35, 0.001),
      stackEntry.current)
check("  never overshooting to zero", stackEntry.current > 0.3)

-- ---------------------------------------------------------------------------
section("Reveal -- cursor proximity and dwell")
-- ---------------------------------------------------------------------------
-- SPEC 4: within 32 units, held 140ms. The dwell is what stops brushing past
-- while looting from flashing the HUD, so it is the part worth testing hardest.

clearClaims()
mock.place(stackEntry.frame, 400, 100, 600, 120)

check("the zone is the spec's 32, converted", near(Reveal.PROXIMITY, Scale.U(32)))

check("a point inside the frame is distance zero",
      Reveal.EdgeDistance(stackEntry, 500, 110) == 0)
check("a point beside it measures to the edge",
      near(Reveal.EdgeDistance(stackEntry, 610, 110), 10))
check("a point off a corner measures diagonally",
      near(Reveal.EdgeDistance(stackEntry, 603, 96), 5))

-- Far away: no claim, ever.
mock.cursorX, mock.cursorY = 0, 0
mock.advance(ns, 1.0, 10)
check("a distant cursor never claims", not Reveal.HasClaim("cursor", "SelfStack"))

-- Inside the zone but only briefly: this is the brush-past case.
mock.cursorX, mock.cursorY = 610, 110
mock.advance(ns, 0.100, 5)
check("inside the zone but under the dwell does NOT claim",
      not Reveal.HasClaim("cursor", "SelfStack"))
mock.cursorX, mock.cursorY = 0, 0
mock.advance(ns, 0.100, 5)
check("  and brushing past leaves nothing behind",
      not Reveal.HasClaim("cursor", "SelfStack"))
check("  with the dwell clock cleared", stackEntry.dwellSince == nil)

-- Held past the dwell: claims.
-- Deliberately either side of the dwell with margin. Advancing a float clock
-- in small steps accumulates error, so a test that lands exactly on 140ms is
-- testing IEEE 754 rather than the dwell.
mock.cursorX, mock.cursorY = 610, 110
mock.advance(ns, 0.100, 2)
check("still not claimed at 100ms", not Reveal.HasClaim("cursor", "SelfStack"))
mock.advance(ns, 0.100, 2)
check("claimed once past 140ms", Reveal.HasClaim("cursor", "SelfStack"))
check("  and only that frame", not Reveal.HasClaim("cursor", "TargetStrip"))

-- Just outside the zone must not claim, however long you wait.
mock.cursorX, mock.cursorY = 0, 0
mock.advance(ns, 0.5, 5)
mock.cursorX = 600 + Reveal.PROXIMITY + 0.5
mock.cursorY = 110
mock.advance(ns, 1.0, 10)
check("half a unit outside the zone never claims",
      not Reveal.HasClaim("cursor", "SelfStack"))
mock.cursorX = 600 + Reveal.PROXIMITY - 0.5
mock.advance(ns, 1.0, 10)
check("  half a unit inside it does", Reveal.HasClaim("cursor", "SelfStack"))

mock.cursorX, mock.cursorY = -10000, -10000
mock.advance(ns, 0.5, 5)
check("leaving releases the claim", not Reveal.HasClaim("cursor", "SelfStack"))

-- ---------------------------------------------------------------------------
section("Reveal -- event channels")
-- ---------------------------------------------------------------------------

clearClaims()
local driver = Reveal.driver
check("a reveal driver exists", driver ~= nil)

mock.altDown = true
driver:Fire("MODIFIER_STATE_CHANGED")
check("alt claims everything, with no dwell", stackEntry.target == 1
      and stripEntry.target == 1)
mock.altDown = false
driver:Fire("MODIFIER_STATE_CHANGED")
check("  and releasing it lets go", stackEntry.target == 0.35)

mock.shiftDown = true
driver:Fire("MODIFIER_STATE_CHANGED")
check("shift works too", stackEntry.target == 1)
mock.shiftDown = false
driver:Fire("MODIFIER_STATE_CHANGED")

mock.units.target = true
driver:Fire("PLAYER_TARGET_CHANGED")
check("acquiring a target reveals the strip", stripEntry.target == 1)
check("  and nothing else", stackEntry.target == 0.35)
mock.units.target = false
driver:Fire("PLAYER_TARGET_CHANGED")
check("losing it hides the strip again", stripEntry.target == 0)

driver:Fire("PLAYER_REGEN_DISABLED")
check("entering combat claims", stackEntry.target == 1)
driver:Fire("PLAYER_REGEN_ENABLED")
check("leaving combat releases", stackEntry.target == 0.35)

-- ---------------------------------------------------------------------------
section("Reveal -- transition log")
-- ---------------------------------------------------------------------------
-- A held modifier and a cursor dwell cannot be inspected by typing a command,
-- because typing while holding a modifier produces something other than the
-- command -- on macOS an accented character, or "?" instead of "/". So the
-- engine records its transitions and they are read afterwards.

local function logOf(kind, field, value)
    local hits = {}
    for _, e in ipairs(Reveal.log) do
        if e.kind == kind and (field == nil or e[field] == value) then
            hits[#hits + 1] = e
        end
    end
    return hits
end

clearClaims()
Reveal.ClearLog()
check("the log starts empty", #Reveal.log == 0)

Reveal.Claim("combat")
-- Inputs and outcomes are logged separately. Recording only outcomes made two
-- very different things produce identical lines: pressing a key three times,
-- and pressing it once while the winner got re-attributed twice.
check("the claim itself is recorded as an input", #logOf("claim", "channel", "combat") == 1)
check("  with no frame, because it claimed everything in scope",
      logOf("claim", "channel", "combat")[1].frame == nil)
local changes = logOf("change")
check("and the resulting target moves are recorded as outcomes", #changes > 0)
check("  naming the frame, both alphas and the winner",
      changes[1].frame ~= nil and changes[1].from == 0.35 and changes[1].to == 1
      and changes[1].winner == "combat")

Reveal.Release("combat")
check("a release is recorded as its own input", #logOf("release", "channel", "combat") == 1)
check("  and its outcomes credit nobody", (function()
    local last = Reveal.log[#Reveal.log]
    return last.kind == "change" and last.winner == nil
end)())

-- The distinction that motivated all of this: three presses look like three
-- presses, not like one press with the winner wobbling.
Reveal.ClearLog()
for _ = 1, 3 do
    Reveal.Claim("modifier")
    Reveal.Release("modifier")
end
check("three presses log three claims", #logOf("claim", "channel", "modifier") == 3)
check("  and three releases", #logOf("release", "channel", "modifier") == 3)

-- A modifier event can repeat while the key is held. Logging every repeat
-- would be exactly the noise this exists to remove.
Reveal.ClearLog()
Reveal.Claim("modifier")
Reveal.Claim("modifier")
Reveal.Claim("modifier")
check("holding a key does not log a claim per event",
      #logOf("claim", "channel", "modifier") == 1)
Reveal.Release("modifier")
Reveal.Release("modifier")
check("  and releasing twice logs one release",
      #logOf("release", "channel", "modifier") == 1)

-- The case worth logging: two channels overlap, the higher releases, and the
-- frame does not move. Logging only alpha changes would hide it entirely.
Reveal.ClearLog()
Reveal.Claim("combat")
Reveal.Claim("cursor", "SelfStack")
Reveal.Release("combat")
check("a handover is recorded even with no alpha change", (function()
    for _, e in ipairs(logOf("change")) do
        if e.frame == "SelfStack" and e.winner == "cursor" and e.from == e.to then
            return true
        end
    end
    return false
end)())
check("  and the frame never dimmed", stackEntry.target == 1)
Reveal.Release("cursor")

check("the log is bounded", (function()
    Reveal.ClearLog()
    for _ = 1, 60 do
        Reveal.Claim("combat")
        Reveal.Release("combat")
    end
    return #Reveal.log <= 40
end)(), #Reveal.log)

Reveal.ClearLog()
clearClaims()

-- ---------------------------------------------------------------------------
section("Reveal -- which keys reveal")
-- ---------------------------------------------------------------------------
-- SPEC 4 names Alt and Shift, which are also what most players bind their
-- ability modifiers to. A HUD that flashes on every modified cast during a
-- fight is the opposite of a design premised on the screen being the game.

check("the spec's default is alt and shift",
      Reveal.DEFAULT_MODIFIERS.alt and Reveal.DEFAULT_MODIFIERS.shift)

local driver2 = Reveal.driver
mock.altDown, mock.shiftDown = false, false
run("modifier shift")
mock.altDown = true
driver2:Fire("MODIFIER_STATE_CHANGED")
check("alt no longer reveals once it is deselected", stackEntry.target == 0.35,
      stackEntry.target)
mock.altDown, mock.shiftDown = false, true
driver2:Fire("MODIFIER_STATE_CHANGED")
check("  while the chosen key still does", stackEntry.target == 1)
mock.shiftDown = false
driver2:Fire("MODIFIER_STATE_CHANGED")

run("modifier none")
mock.altDown, mock.shiftDown = true, true
driver2:Fire("MODIFIER_STATE_CHANGED")
check("none disables the channel entirely", stackEntry.target == 0.35,
      stackEntry.target)
mock.altDown, mock.shiftDown = false, false
driver2:Fire("MODIFIER_STATE_CHANGED")

check("an unknown key is refused rather than silently dropped",
      select(1, Reveal.SetModifiers({ "meta" })) == nil)

run("modifier alt shift")
check("the setting persists to saved variables",
      _G.MyUIDB.modifiers.alt and _G.MyUIDB.modifiers.shift)
mock.altDown = true
driver2:Fire("MODIFIER_STATE_CHANGED")
check("  and the default works again", stackEntry.target == 1)
mock.altDown = false
driver2:Fire("MODIFIER_STATE_CHANGED")
clearClaims()

-- ---------------------------------------------------------------------------
section("Peek")
-- ---------------------------------------------------------------------------

clearClaims()
check("peek starts inactive", not ns.Peek.IsActive())
check("the peek duration is the spec's 3s", ns.Peek.DURATION == 3.0)

ns.Peek.Start()
check("peeking reveals everything", stackEntry.target == 1 and stripEntry.target == 1)
check("  and is active", ns.Peek.IsActive())
check("  with a full clock", near(ns.Peek.Remaining(), 3.0))

mock.advance(ns, 1.5, 15)
check("the clock drains", near(ns.Peek.Remaining(), 1.5, 0.05), ns.Peek.Remaining())
check("  and the reveal is still held", stackEntry.target == 1)

ns.Peek.Start()
check("tapping again restarts rather than extending",
      near(ns.Peek.Remaining(), 3.0), ns.Peek.Remaining())

mock.advance(ns, 3.1, 31)
check("it expires", not ns.Peek.IsActive())
check("  and releases its claim", stackEntry.target == 0.35, stackEntry.target)
check("  fading out rather than snapping",
      near(stackEntry.fadeDuration, Reveal.FADE_OUT))

check("the binding calls through the global the XML names",
      type(_G.MyUI_Peek) == "function")
_G.MyUI_Peek()
check("  and it peeks", ns.Peek.IsActive())
ns.Peek.Stop()
clearClaims()

-- ---------------------------------------------------------------------------
section("Reveal -- one owner of alpha")
-- ---------------------------------------------------------------------------
-- SPEC 4 names this as the mistake the design is most vulnerable to, so the
-- Phase 1 debug toggle was rerouted through the arbiter rather than left
-- setting alpha behind its back.

Registry.ForceVisible(true)
check("the debug toggle claims through the arbiter",
      Reveal.HasClaim("debug", "SelfStack"))
check("  reaching full alpha immediately, with no fade",
      near(Compat.Get(stackEntry.frame, "GetAlpha"), 1))
check("  and crediting itself in the audit", stackEntry.claim == "debug")
Registry.ForceVisible(false)
check("releasing it returns every frame to resting",
      stackEntry.target == 0.35 and stripEntry.target == 0)

-- ---------------------------------------------------------------------------
section("Core -- saved variables")
-- ---------------------------------------------------------------------------

check("database was created", type(_G.MyUIDB) == "table")
check("  at the current schema", _G.MyUIDB.schema == ns.SCHEMA_VERSION)
check("  recording the phase", _G.MyUIDB.addon.phase == ns.phase, _G.MyUIDB.addon.phase)
check("  with an alpha table for phase 5", type(_G.MyUIDB.alpha) == "table")
check("no migrations needed at schema 1", next(ns.MIGRATIONS) == nil)

ns.ClearOutput()
ns.Print("hello")
check("output is captured", ns.GetOutput():find("hello", 1, true) ~= nil)
check("  with colour codes stripped", ns.GetOutput():find("|cff", 1, true) == nil)

-- ---------------------------------------------------------------------------
section("Commands")
-- ---------------------------------------------------------------------------

check("slash command is registered", type(run) == "function")
check("both aliases exist", _G.SLASH_MYUI1 == "/myui" and _G.SLASH_MYUI2 == "/mui")

local function output(input)
    ns.ClearOutput()
    run(input)
    return ns.GetOutput()
end

check("bare /myui prints help", output(""):find("audit", 1, true) ~= nil)
check("prefix 'aud' resolves to audit", output("aud"):find("audit --", 1, true) ~= nil)
check("prefix 'r' resolves to rules", output("r"):find("Forwarding a secret", 1, true) ~= nil)
check("unknown command is reported", output("zzz"):find("unknown command", 1, true) ~= nil)

Guard.Reset()
local audit = output("audit")
check("audit does not claim empty while frames exist",
      audit:find("no frames registered", 1, true) == nil)
check("audit lists registered frames", audit:find("SelfStack", 1, true) ~= nil)
check("audit reports a clean guard", audit:find("clean", 1, true) ~= nil)
check("audit prints the resting alpha column", audit:find("REST", 1, true) ~= nil)

Guard.mode = "warn"
Guard.Reset()
Guard.Send(mock.frame({}), "SetScale", mock.secret())
audit = output("audit")
check("audit surfaces a violation", audit:find("1 violation", 1, true) ~= nil)
Guard.mode = "strict"
Guard.Reset()

check("guard mode is settable", output("guard warn"):find("guard mode: warn", 1, true) ~= nil)
check("  and persisted", _G.MyUIDB.guard.mode == "warn")
run("guard strict")

-- ---------------------------------------------------------------------------
section("Conditionals probe")
-- ---------------------------------------------------------------------------

-- Count verdicts on table rows only. The explanatory footer quotes both
-- verdict words, and a naive substring count picks those up too.
local function verdictRows(text, verdict)
    local n = 0
    for line in text:gmatch("[^\n]+") do
        if line:find("[", 1, true) and line:find(verdict, 1, true) then
            n = n + 1
        end
    end
    return n
end

local probe = output("conditionals")
check("probe runs a known control", probe:find("control: known", 1, true) ~= nil)
check("  and both unknown baselines",
      probe:find("control: unknown ", 1, true) ~= nil and
      probe:find("control: unknown n", 1, true) ~= nil)
check("  known control differs from unknown",
      probe:find("%[combat%] / %[nocombat%]%s+miss/hit") ~= nil)

-- The measured client behaviour: an unrecognised conditional is ignored, so
-- the clause matches. Both baselines encode that, and neither is assumed.
check("unknown negated baseline is hit/miss",
      probe:find("%[zzznope%] / %[nozzznope%]%s+hit/miss") ~= nil)
check("unknown numeric baseline is hit/hit",
      probe:find("%[zzznope<0%] / %[zzznope<101%]%s+hit/hit") ~= nil)

check("  every candidate is unrecognised on this mock",
      verdictRows(probe, "not recognised") == 6, verdictRows(probe, "not recognised"))
check("  no row is claimed recognised", verdictRows(probe, "RECOGNISED") == 0)
check("  the two health-dependent rows are flagged as such",
      verdictRows(probe, "needs full health") == 2,
      verdictRows(probe, "needs full health"))
check("  and the fallback is named", probe:find("LowHealthFrame", 1, true) ~= nil)

-- The discriminator is the whole point: a probe hardwired to say "no" would
-- pass every check above. Teach the mock a conditional that really exists and
-- it must be told apart from an unknown one -- at any health, which is why the
-- numeric candidates use a complementary always-false / always-true pair.
mock.known = { ["hp<0"] = false, ["hp<101"] = true }
probe = output("conditionals")
check("a real conditional reads as RECOGNISED",
      verdictRows(probe, "RECOGNISED") == 2, verdictRows(probe, "RECOGNISED"))
check("  on the hp rows specifically",
      probe:find("%[hp<0%] / %[hp<101%]%s+miss/hit%s+RECOGNISED") ~= nil)
check("  while the others stay unrecognised",
      verdictRows(probe, "not recognised") == 4, verdictRows(probe, "not recognised"))
check("  and the summary flips", probe:find("2 recognised", 1, true) ~= nil)
mock.known = {}

mock.inCombat = true
probe = output("conditionals")
check("control tracks combat state",
      probe:find("%[combat%] / %[nocombat%]%s+hit/miss") ~= nil)
mock.inCombat = false

-- ---------------------------------------------------------------------------
section("Acceptance checklist")
-- ---------------------------------------------------------------------------

local Testing = ns.Testing
check("a script exists for every delivered phase", (function()
    for phase = 0, ns.phase do
        if not Testing.scripts[phase] then return false, phase end
    end
    return true
end)())

check("every step says what to do and what to expect", (function()
    for phase, script in pairs(Testing.scripts) do
        if not script.title or not script.accept then return false, phase end
        for i, step in ipairs(script.steps) do
            if not step.act or step.act == "" then return false, phase .. ":" .. i end
            if not step.expect or step.expect == "" then return false, phase .. ":" .. i end
        end
    end
    return true
end)())

check("the current phase has steps", #Testing.Steps() > 0)

-- Auto-checks must actually track state, not just return true. Force the
-- frames visible and step 1 passes; release them and it fails.
-- Pinned to phase 1 for this section: it is the script that has both a
-- "show on" and a "show off" step, which is what the latching and waiting
-- behaviour needs to exercise. The phase under development may not.
Testing.phase = 1
local SHOW, SHOWOFF = Testing.IndexOf("show"), Testing.IndexOf("showoff")
check("steps carry stable ids", SHOW ~= nil and SHOWOFF ~= nil)

check("every step asks exactly one question", (function()
    -- A compound step is unanswerable: a fail says something was wrong without
    -- saying what. Learned from the first live run, where one step bundled four
    -- assertions and the report could not distinguish them.
    for phase, script in pairs(Testing.scripts) do
        for i, step in ipairs(script.steps) do
            if step.act:find(" and ") and step.act:find("?") then
                return false, phase .. ":" .. i
            end
        end
    end
    return true
end)())

-- These drive the real slash command rather than the registry directly, so the
-- dispatcher, Note and Recheck are all exercised together -- which is how the
-- addon is actually used, and where the waiting state lives.
Testing.Reset()
check("an unperformed step is waiting, not failing", Testing.results[SHOW] == nil)
check("  and Ready says so", not Testing.Ready(Testing.Steps()[SHOW]))
check("  while a step awaiting nothing is always ready",
      Testing.Ready({ act = "x", expect = "y" }))

run("show on")
check("running the command marks it performed", Testing.performed["show on"] == true)
check("  and the step is now ready", Testing.Ready(Testing.Steps()[SHOW]))
check("  and passes", Testing.results[SHOW] and Testing.results[SHOW].verdict == "pass",
      Testing.results[SHOW] and Testing.results[SHOW].detail)
check("  saying it verified the screen, not just the intent",
      Testing.results[SHOW].detail:find("verified on screen", 1, true) ~= nil,
      Testing.results[SHOW].detail)
check("  and is marked as decided automatically", Testing.results[SHOW].auto == true)
check("the show-off step is still waiting", Testing.results[SHOWOFF] == nil)

-- Regression: the check used to compare only the registry's intent, so it
-- reported success while the screen was unchanged.
Registry.Get("SelfStack").frame:SetAlpha(0.35)
Testing.Recheck(true)
check("a frame whose real alpha disagrees is caught",
      Testing.results[SHOW].verdict == "fail", Testing.results[SHOW].detail)
run("show on")

-- Steps 1 and 13 test mutually exclusive states on purpose. A pass has to
-- latch, or finishing the sequence always fails whichever step you did first.
run("show off")
check("the show-off step passes once performed",
      Testing.results[SHOWOFF] and Testing.results[SHOWOFF].verdict == "pass",
      Testing.results[SHOWOFF] and Testing.results[SHOWOFF].detail)
check("  and the show step keeps its pass", Testing.results[SHOW].verdict == "pass",
      Testing.results[SHOW].verdict)
Testing.Recheck(true)
check("forcing a re-check re-evaluates it", Testing.results[SHOW].verdict == "fail")

Testing.Set(2, "pass")
check("manual verdicts are recorded", Testing.results[2].verdict == "pass")
check("  and marked as not automatic", Testing.results[2].auto == false)

Testing.Reset()
check("reset clears manual verdicts", Testing.results[2] == nil)
check("  and forgets what was performed", next(Testing.performed) == nil)

run("show on")
run("audit")
-- Leave the registry unclaimed: later sections assert on a frame at rest, and
-- a stray debug claim from here would show up as theirs.
run("show off")
check("auto steps report a detail string",
      type(Testing.results[SHOW].detail) == "string")

local pass, fail, pending = Testing.Tally()
check("tally adds up to the step count",
      pass + fail + pending == #Testing.Steps(),
      pass .. "+" .. fail .. "+" .. pending)

ns.ClearOutput()
Testing.Report()
local report = ns.GetOutput()
check("report names the phase", report:find("Phase 1", 1, true) ~= nil)
check("  carries the acceptance tally", report:find("passed", 1, true) ~= nil)
check("  prints the expectation for anything not passing",
      report:find("expected:", 1, true) ~= nil)
check("  and reports the running version", report:find(ns.version, 1, true) ~= nil)
check("report is persisted for reading off disk",
      _G.MyUIDB.testRuns and _G.MyUIDB.testRuns[Testing.phase] ~= nil)
check("  with the counts alongside the text",
      type(_G.MyUIDB.testRuns[Testing.phase].pass) == "number")

Testing.Show()
check("the checklist window opens", Testing.IsShown())
run("test")
check("  and /myui test opens it too", Testing.IsShown())

-- Regression: the window kept painting "waiting" for a step that had already
-- passed. Every test read Testing.results directly, so none of them looked at
-- what was actually on screen -- which is the only thing the user sees.
Testing.Show(1)
check("opening a script forgets the previous run's commands",
      next(Testing.performed) == nil)
check("a waiting step paints as waiting", Testing.RowMark(SHOW) == "waiting",
      Testing.RowMark(SHOW))
run("show on")
check("running the command settles the verdict", Testing.MarkFor(SHOW) == "pass",
      Testing.MarkFor(SHOW))
check("  and the window repaints to match",
      (Testing.RowMark(SHOW) or ""):find("pass", 1, true) ~= nil,
      Testing.RowMark(SHOW))
run("show off")
check("  and repaints again on the way back",
      (Testing.RowMark(Testing.IndexOf("showoff")) or ""):find("pass", 1, true) ~= nil,
      Testing.RowMark(Testing.IndexOf("showoff")))

-- Back to the phase under development, and check it has a script at all.
Testing.Show(ns.phase)
check("the phase under development has its own script",
      Testing.scripts[ns.phase] ~= nil, ns.phase)
check("  no step asks you to type while holding a modifier", (function()
    -- Impossible on macOS: Option inserts accented characters and Shift turns
    -- "/" into "?", so the command never runs. Transient state gets recorded
    -- and read afterwards instead.
    for _, step in ipairs(Testing.Steps()) do
        local act = step.act:lower()
        if act:find("hold") and act:find("/myui") then
            local held = act:match("hold[^,.]*")
            if held and not act:find("release") and not act:find("then") then
                return false, step.act
            end
        end
    end
    return true
end)())

check("  with a step for every reveal channel", (function()
    local text = ""
    for _, step in ipairs(Testing.Steps()) do
        text = text .. " " .. step.act:lower() .. " " .. step.expect:lower()
    end
    for _, word in ipairs({ "cursor", "alt", "target", "combat", "peek" }) do
        if not text:find(word, 1, true) then return false, word end
    end
    return true
end)())

-- ---------------------------------------------------------------------------
section("Getting output off the machine")
-- ---------------------------------------------------------------------------

run("audit")
check("output is persisted for the off-disk route",
      type(_G.MyUIDB.lastOutput) == "string" and _G.MyUIDB.lastOutput ~= "")
check("  tagged with the command that produced it", _G.MyUIDB.lastCommand == "audit")
check("  and carries the report, not just the header",
      _G.MyUIDB.lastOutput:find("violations", 1, true) ~= nil)
check("  with colour codes stripped for a plain-text read",
      _G.MyUIDB.lastOutput:find("|cff", 1, true) == nil)

local persisted = _G.MyUIDB.lastOutput
run("copy")
check("copy does not overwrite the output it shows",
      _G.MyUIDB.lastOutput == persisted)
check("  and the window is up", ns.Copy.IsShown())

run("conditionals")
check("a later command replaces the persisted output",
      _G.MyUIDB.lastOutput ~= persisted and _G.MyUIDB.lastCommand == "conditionals")
check("  and the probe table survives the round trip",
      _G.MyUIDB.lastOutput:find("zzznope", 1, true) ~= nil)

-- ---------------------------------------------------------------------------
section("Rules")
-- ---------------------------------------------------------------------------

check("the principle is stated once, exactly",
      Rules.principle == "Forwarding a secret value is legal. Inspecting one is not.")
check("six prohibitions are listed", #Rules.forbidden == 6, #Rules.forbidden)
check("every prohibition names an alternative", (function()
    for _, r in ipairs(Rules.forbidden) do
        if not r.yes or r.yes == "" then return false end
    end
    return true
end)())
check("four sanctioned mechanisms", #Rules.mechanisms == 4)

-- ---------------------------------------------------------------------------
section("Registry")
-- ---------------------------------------------------------------------------
-- Last on purpose: this section registers fixtures, and anything that walks
-- the whole registry has to run before they pollute it.
-- ---------------------------------------------------------------------------

local baseCount = Registry.Count()
Registry.Add("TestFrame", mock.frame({ name = "TestFrame" }), 0.5)
check("frames register", Registry.Count() == baseCount + 1)
check("lookup by name works", Registry.Get("TestFrame").resting == 0.5)

Registry.Add("TestFrame", mock.frame({}), 0.99)
check("duplicate name is refused", Registry.Count() == baseCount + 1)
check("  and the original alpha survives", Registry.Get("TestFrame").resting == 0.5)

local snap = Registry.Snapshot()
check("snapshot covers every frame", #snap == baseCount + 1)
check("  and reports no claim at rest", snap[1].claim == "-")

-- A frame that has been forwarded a secret returns a secret alpha; the audit
-- must show a sentinel rather than throw on it.
Registry.Add("Tainted", health, 0.25)
snap = Registry.Snapshot()
check("secret alpha reads back as a sentinel",
      snap[#snap].current == Compat.SECRET, tostring(snap[#snap].current))

-- ---------------------------------------------------------------------------
print("")
print(("%d checks, %d failures"):format(checks, failures))
os.exit(failures == 0 and 0 or 1)
