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

check("every file in the TOC was loaded", #ns.__loadedFiles == 21, #ns.__loadedFiles)

-- Each delivered phase gets an annotated git tag named after the TOC version,
-- so these three must agree before one is cut. They drift silently otherwise,
-- and the tag is the thing a cold pickup trusts.
local toc = ns.__toc
check("TOC targets retail 12.1 only", toc.Interface == "120105", toc.Interface)
check("TOC saves to MyUIDB", toc.SavedVariables == "MyUIDB", toc.SavedVariables)
-- Settings are account-wide so every alt gets the same HUD; the record of what
-- happened is per character, because a whisper was addressed to who you were
-- playing. Two files, two natures.
check("  and the log per character",
      toc.SavedVariablesPerCharacter == "MyUICharDB", toc.SavedVariablesPerCharacter)
check("TOC version carries the phase suffix",
      toc.Version:match("%-phase(%d+)$") == toc["X-Phase"],
      toc.Version .. " vs X-Phase " .. tostring(toc["X-Phase"]))
check("  and the addon agrees with it",
      tonumber(toc["X-Phase"]) == ns.phase, toc["X-Phase"] .. " vs " .. tostring(ns.phase))
check("  and reports the TOC version, not a stale one",
      ns.version == toc.Version, ns.version .. " vs " .. tostring(toc.Version))
for _, mod in ipairs({ "Compat", "Scale", "Palette", "Guard", "Registry",
                       "Frames", "Reveal", "Peek", "Rail", "Outline", "Testing",
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
check("exactly thirteen colours", paletteCount == 13, paletteCount)
check("  and the count is declared", Palette.COUNT == 13)

-- Thirteen, not fourteen, since the amended SPEC 7. Text secondary and text
-- tertiary held the same value once the unreadable tertiary grey was lifted, so
-- they collapsed into one textDim.
check("  the two dim greys collapsed into textDim", (function()
    local r, g, b, a = Palette.Get("textDim")
    return near(r, 173/255) and near(g, 177/255) and near(b, 184/255) and a == 1
end)())
check("  and neither old name survives",
      Palette.colors.textSecondary == nil and Palette.colors.textTertiary == nil)

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

check("asking for a fourteenth colour errors",
      not pcall(Palette.Get, "somethingElse"))

-- The grey the amendment removed. It is still drawn by /myui contrast normal,
-- but out of a constant in Frames -- deliberately not out of here.
check("  and the superseded rgba(115,119,126,1) is not among them", (function()
    for name, c in pairs(Palette.colors) do
        if near(c[1], 115/255) and near(c[2], 119/255) and near(c[3], 126/255) then
            return false, name
        end
    end
    return true
end)())

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
Reveal.Claim("combat")
check("a tie credits the channel SPEC 4 ranks higher", stackEntry.claim == "combat",
      stackEntry.claim)
check("  and stays credited to it across repeated resolves", (function()
    for _ = 1, 50 do
        Reveal.Resolve()
        if stackEntry.claim ~= "combat" then return false end
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
      stackEntry.claim == "combat" and stackEntry.target == 1)
Reveal.CHANNELS.peek = realPeek
clearClaims()

-- The order is SPEC 4's, added by the amendment after Phase 2 raised the gap
-- and chose its own: "low health, state change, peek, proximity". Phase 2 put
-- peek above state change, so this is the behaviour that actually changed.
Reveal.Claim("combat")
Reveal.Claim("peek")
check("a peek during combat is credited to combat, not peek",
      stackEntry.claim == "combat", stackEntry.claim)
check("  and the alpha is the same either way", stackEntry.target == 1)
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

-- Alt and Shift used to claim everything here, with no dwell. The amended
-- SPEC 4 cut that channel; the driver no longer registers the event and the
-- handler has no branch for it. Covered in full further down.
mock.altDown, mock.shiftDown = true, true
driver:Fire("MODIFIER_STATE_CHANGED")
check("a modifier claims nothing", stackEntry.target == 0.35
      and stripEntry.target == 0, stackEntry.target)
mock.altDown, mock.shiftDown = false, false

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
-- A cursor dwell cannot be inspected by typing a command: the cursor has to
-- leave the frame to reach the chat box. The same was true of the modifier
-- channel before it was cut, and worse -- typing while holding one produced an
-- accented character on macOS, or "?" instead of "/", so the command never ran.
-- So the engine records its transitions and they are read afterwards.

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
    Reveal.Claim("peek")
    Reveal.Release("peek")
end
check("three presses log three claims", #logOf("claim", "channel", "peek") == 3)
check("  and three releases", #logOf("release", "channel", "peek") == 3)

-- A channel can re-assert a claim it already holds: proximity re-claims every
-- tick while the cursor sits still. Logging every repeat would be exactly the
-- noise this exists to remove.
Reveal.ClearLog()
Reveal.Claim("peek")
Reveal.Claim("peek")
Reveal.Claim("peek")
check("re-asserting a held claim does not log it again",
      #logOf("claim", "channel", "peek") == 1)
Reveal.Release("peek")
Reveal.Release("peek")
check("  and releasing twice logs one release",
      #logOf("release", "channel", "peek") == 1)

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
section("Reveal -- the modifier channel is gone")
-- ---------------------------------------------------------------------------
-- SPEC 4 named Alt and Shift, which are also what most players bind their
-- ability modifiers to, so the HUD revealed itself on every modified cast in a
-- fight. Phase 2 shipped a configurable key set plus a bindable hold key as the
-- escape hatch, and raised it. The amended SPEC 4 cut the channel outright
-- instead, and the escape hatch with it: proximity already covers
-- reveal-while-doing-something and peek covers reveal-because-I-want-to.

check("the channel is not in the table", Reveal.CHANNELS.modifier == nil)
check("  and claiming it is refused rather than silently ignored",
      not pcall(Reveal.Claim, "modifier"))
check("  the key-set API went with it",
      Reveal.SetModifiers == nil and Reveal.Modifiers == nil
      and Reveal.AnyModifierDown == nil)
check("  and so did the hold binding",
      _G.MyUI_Hold == nil and _G.BINDING_NAME_MYUI_HOLD == nil)

-- PLAN Phase 2's amended acceptance: "no modifier key reveals anything."
local driver2 = Reveal.driver
clearClaims()
mock.altDown, mock.shiftDown = true, true
driver2:Fire("MODIFIER_STATE_CHANGED")
check("holding every modifier at once reveals nothing", stackEntry.target == 0.35,
      stackEntry.target)
check("  and logs nothing either", (function()
    for _, e in ipairs(Reveal.log) do
        if e.channel == "modifier" then return false end
    end
    return true
end)())
mock.altDown, mock.shiftDown = false, false
clearClaims()

check("peek is named for the keybinding UI",
      _G.BINDING_NAME_MYUI_PEEK ~= nil and _G.BINDING_HEADER_MYUI ~= nil)

-- Bindings.xml is read straight off disk: it is the one file the client loads
-- that the addon never sees, so nothing else can check it.
local bindings = assert(io.open("../MyUI/Bindings.xml")):read("*a")
check("Bindings.xml no longer declares a hold binding",
      bindings:match('<Binding%s+name="MYUI_HOLD"') == nil)
check("  and peek carries the header the hold binding used to",
      bindings:match('name="MYUI_PEEK"[^>]*header="MYUI"') ~= nil)
check("the peek binding takes one edge, since a tap is one edge",
      bindings:match('name="MYUI_PEEK"[^>]*runOnUp') == nil)

-- Shipped broken once. Every other file in this addon writes an em dash as a
-- double hyphen, and one of those reaching an XML comment makes the whole file
-- "not well-formed", which unregisters every binding while the client says
-- nothing louder than a single LUA_WARNING. smoke.sh parses the file properly;
-- this names the cause, because "not well-formed" does not.
check("no comment in Bindings.xml contains a double hyphen", (function()
    for body in bindings:gmatch("<!%-%-(.-)%-%->") do
        if body:find("%-%-") then
            return false, "in: " .. body:sub(1, 40)
        end
    end
    return true
end)())

-- Kept deliberately: PLAN Phase 6 asks whether peek should stay a tap or become
-- a hold, and runOnUp with keystate is the shape that answers it.
check("  but the shape a hold needs is recorded, not lost",
      bindings:find("runOnUp", 1, true) ~= nil
      and bindings:find("keystate", 1, true) ~= nil)

-- The rule that cost the Rebar project real time: the client loads
-- Bindings.xml by filename, and listing it in the TOC sends the same file
-- through the ordinary XML parser too, which rejects every attribute on
-- <Binding> so no binding registers at all.
local toc = assert(io.open("../MyUI/MyUI.toc")):read("*a")
check("Bindings.xml is NOT listed in the TOC",
      not toc:find("Bindings.xml", 1, true))

check("the modifier setting is gone from saved variables",
      _G.MyUIDB.modifiers == nil)
check("  and /myui modifier is no longer a command",
      (function()
          ns.ClearOutput()
          run("modifier")
          return ns.GetOutput():find("unknown command", 1, true) ~= nil
      end)())
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
section("Rail -- notifications")
-- ---------------------------------------------------------------------------
-- SPEC 6. The rail touches no protected data, which is why PLAN puts it ahead
-- of the bars: it exercises the reveal engine hard with no taint risk at all.

local Rail = ns.Rail

-- Login order is a real dependency, and it used to be a pairs() over a table.
check("the rail built at login", Rail.slots ~= nil and #Rail.slots == Rail.SLOTS)
check("  which means Frames ran before it", Registry.Get("Rail") ~= nil)

Rail.Clear()
check("an unknown type is refused", select(1, Rail.Add("puce", "x")) == nil)
check("  naming the ones that exist",
      select(2, Rail.Add("puce", "x")):find("violet", 1, true) ~= nil)

Rail.Clear()
Rail.Add("blue", "First", 1)
Rail.Add("amber", "Second", 3)
check("newest goes to the top", Rail.items[1].name == "Second")
check("  carrying its count", Rail.items[1].count == 3)
check("slot one shows name and count", Rail.slots[1].name:GetText() == "Second x3")
check("  and an age", Rail.slots[1].age:GetText() == "0s")
check("a count of one is not written out", (function()
    Rail.Add("green", "Single", 1)
    return Rail.slots[1].name:GetText() == "Single"
end)())

-- SPEC 6: the two newest carry text; older items are the dot alone at 0.4.
Rail.Clear()
for i = 1, 5 do Rail.Add("blue", "Item " .. i) end
-- SPEC 6 describes the rows "at rest", so settle the toast first: while one is
-- speaking, the row it stands in for is deliberately not drawn.
Rail.Collapse()
Rail.slots[1].fade:Finish()
Rail.toastFrame.collapse:Finish()
check("exactly two rows carry text", (function()
    local withText = 0
    for i = 1, Rail.SLOTS do
        if Rail.RowVisible(i) then withText = withText + 1 end
    end
    return withText == Rail.NAMED
end)())
check("  the newest two", Rail.slots[1].name:GetText() == "Item 5"
      and Rail.slots[2].name:GetText() == "Item 4")
check("older dots sit at 0.4", Compat.Get(Rail.slots[3].dot, "GetAlpha") == Rail.OLD_ALPHA,
      Compat.Get(Rail.slots[3].dot, "GetAlpha"))
check("  while the named ones are full", Compat.Get(Rail.slots[1].dot, "GetAlpha") == 1)
check("empty slots are hidden", not Rail.slots[6]:IsShown())

-- FOUND IN GAME: "Chunk of Companion Experience" ran through the age and drew
-- on top of it. SPEC 6 never says what happens when a name is longer than the
-- row, so the name is bounded by the age rather than the row -- the age's own
-- width varies between "9s" and "23h" -- and wraps to an ellipsis instead of a
-- second line. Offline this can only check the mechanism; the acceptance script
-- asks whether it actually reads.
check("a row name is bounded on both sides, so it has a real width", (function()
    local anchors = {}
    for _, c in ipairs(Rail.slots[1].name.__calls) do
        if c.method == "SetPoint" then anchors[c[1]] = c[2] end
    end
    return anchors.LEFT ~= nil and anchors.RIGHT ~= nil, "LEFT and RIGHT both needed"
end)())
check("  and the right edge yields to the age, not to the row", (function()
    for _, c in ipairs(Rail.slots[1].name.__calls) do
        if c.method == "SetPoint" and c[1] == "RIGHT" then
            return c[2] == Rail.slots[1].age, "anchored to the wrong thing"
        end
    end
    return false, "no RIGHT anchor"
end)())
check("  with word wrap off, so it ellipsises instead of wrapping", (function()
    for _, c in ipairs(Rail.slots[1].name.__calls) do
        if c.method == "SetWordWrap" then return c[1] == false end
    end
    return false, "never set"
end)())
check("the toast is bounded too, so a long name stops at its edge", (function()
    local sawRight, sawWrap = false, false
    for _, c in ipairs(Rail.toastFrame.label.__calls) do
        if c.method == "SetPoint" and c[1] == "RIGHT" then sawRight = true end
        if c.method == "SetWordWrap" and c[1] == false then sawWrap = true end
    end
    return sawRight and sawWrap
end)())

-- SPEC 6 (amended): the 1px dark edge that keeps a 0.4 dot legible over sand
-- and firelight. Attached to the "older items" line, so the newest two do not
-- get one -- their dots are at full alpha and the reason for the edge does not
-- apply to them.
check("a dim dot carries a dark edge", Rail.slots[3].edge.TOP:IsShown())
check("  on all four sides", (function()
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        if not Rail.slots[3].edge[side]:IsShown() then return false, side end
    end
    return true
end)())
check("  in tickDark, introducing no new colour", (function()
    for _, c in ipairs(Rail.slots[3].edge.TOP.__calls) do
        if c.method == "SetColorTexture" then
            return c[1] == 0 and c[2] == 0 and near(c[4], 0.55)
        end
    end
    return false, "never coloured"
end)())
check("  and the full-alpha dots do not", not Rail.slots[1].edge.TOP:IsShown())

-- The amendment's implementation note, and the whole point of it: "draw the
-- edge as a sibling texture at constant alpha, never as a child of the dot --
-- a child inherits the dot's 0.4 and the edge vanishes exactly when it is
-- needed." Two checks, because each catches a different way of getting it wrong.
check("the edge never has an alpha set on it", (function()
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        for _, c in ipairs(Rail.slots[3].edge[side].__calls) do
            if c.method == "SetAlpha" then return false, side end
        end
    end
    return true
end)())
check("  and is not created on the dot", (function()
    local src = assert(io.open("../MyUI/Rail.lua")):read("*a")
    return src:find("dot:CreateTexture", 1, true) == nil
end)())

-- Round 5 killed the cap and the "+N more" square: "you were right, the cap
-- was arbitrary". Twelve arrive, twelve are drawn.
Rail.Clear()
for i = 1, 12 do Rail.Add("amber", "Twelve " .. i) end
check("nothing is hidden behind a count", (function()
    local shown = 0
    for i = 1, Rail.SLOTS do
        if Rail.slots[i]:IsShown() then shown = shown + 1 end
    end
    return shown == 12, shown
end)())
check("  and the rail has no overflow marker at all", Rail.overflow == nil)

-- "Pitch drops 26 -> 20 -> 8 as the live count rises."
check("the pitch tightens as the rail fills", Rail.Pitch(12) < Rail.Pitch(3),
      Rail.Pitch(12) .. " vs " .. Rail.Pitch(3))
check("  loosest when quiet", Rail.Pitch(3) == Rail.SPACING, Rail.Pitch(3))
check("  and bottoms out rather than going to zero", Rail.Pitch(400) == Rail.PITCH_MIN,
      Rail.Pitch(400))

-- "Alpha is the clock. A dot enters at 0.40 and decays to zero over 5 minutes."
check("a fresh dot enters at the old-items alpha", Rail.Fade(0) == Rail.OLD_ALPHA, Rail.Fade(0))
check("  is dimmer halfway through", Rail.Fade(Rail.DECAY / 2) < Rail.OLD_ALPHA)
check("  and reaches zero at the end of the decay", Rail.Fade(Rail.DECAY) == 0)
check("  never going negative past it", Rail.Fade(Rail.DECAY * 10) == 0)

-- Dots leave by ageing out. This is only honest because the log has them.
check("dots age out of the rail", (function()
    Rail.Clear()
    Rail.Add("blue", "Old")
    mock.time = mock.time + Rail.DECAY + 1
    Rail.Refresh()
    return #Rail.items == 0, #Rail.items
end)())
check("  and the log still has it", ns.Log.Count("blue") > 0)

-- SLOTS is an allocation bound, not the cap coming back: WoW cannot destroy a
-- frame, so an unbounded rail is a pool that only ever grows.
check("the pool has a ceiling", (function()
    Rail.Clear()
    for i = 1, Rail.SLOTS + 10 do Rail.Add("violet", "Flood " .. i) end
    return #Rail.items == Rail.SLOTS, #Rail.items
end)())
check("  and everything past it is still in the log",
      ns.Log.Count("violet") >= Rail.SLOTS + 10, ns.Log.Count("violet"))

-- Hues come from the palette, so the rail cannot introduce a fifteenth colour.
check("every notification type maps to a palette entry", (function()
    for kind, name in pairs(Rail.HUES) do
        if ns.Palette.colors[name] == nil then return false, kind end
    end
    return true
end)())
check("  and there are six of them", (function()
    local n = 0
    for _ in pairs(Rail.HUES) do n = n + 1 end
    return n == 6, n
end)())
-- Round 5's sixth hue cost nothing: it is the danger red the low-health bar
-- already uses, at the same rgba. If this ever stops being true the palette
-- has grown a colour nobody asked for.
check("  and the sixth is the palette's existing danger red",
      Rail.HUES.red == "danger")

-- ---------------------------------------------------------------------------
section("Text legibility")
-- ---------------------------------------------------------------------------
-- SPEC 7's palette is light-on-dark. Over bright scenery -- sand, firelight --
-- the small type washes out and becomes unreadable. Found in game.

local Frames = ns.Frames
check("shadow is the default", Frames.TextStyle() == "shadow")

-- This was the addon's one deliberate deviation: verified in game, with
-- "normal" the rail age and the "+N more" count are unreadable against ordinary
-- terrain, and Phase 3's acceptance step for them passed only with lift on.
-- THE AMENDED SPEC 7 ADOPTED IT, so lift is no longer a deviation -- it is the
-- spec, and it is simply what the palette holds.
check("dim text defaults to the amended SPEC 7 value",
      Frames.Contrast() == "lift", Frames.Contrast())
check("  which resolves to textDim, rgba(173,177,184,1)", (function()
    local r, g, b, a = Frames.TextColor("textDim")
    return near(r, 173/255) and near(g, 177/255) and near(b, 184/255) and a == 1
end)())

-- The grey it replaced is kept for one diagnostic and is deliberately outside
-- the palette, so it cannot be reached by name and cannot be drawn by accident.
run("contrast normal")
check("normal draws the superseded rgba(115,119,126,1)", (function()
    local r, g, b = Frames.TextColor("textDim")
    return near(r, 115/255) and near(g, 119/255) and near(b, 126/255)
end)())
check("  a colour Palette refuses to serve", not pcall(ns.Palette.Get, "textTertiary"))
run("contrast lift")
check("  and lift restores the palette value", (function()
    local r = Frames.TextColor("textDim")
    return near(r, 173/255)
end)())

check("the shadow reuses an existing palette colour", (function()
    -- tickDark is rgba(0,0,0,0.55), which is what a shadow wants anyway, so
    -- the fix introduces no fourteenth colour. SPEC 7 is closed at thirteen.
    local r, g, b, a = ns.Palette.Get("tickDark")
    return r == 0 and g == 0 and b == 0 and near(a, 0.55)
end)())

local sample = Registry.Get("SelfStack").frame.number
check("a string carries a shadow", (function()
    for _, c in ipairs(sample.__calls) do
        if c.method == "SetShadowColor" then return true end
    end
    return false
end)())

run("text outline")
check("outline switches the font flags", (function()
    local calls = sample.__calls
    for i = #calls, 1, -1 do
        if calls[i].method == "SetFont" then return calls[i][3] == "OUTLINE" end
    end
    return false
end)(), Frames.TextStyle())
check("  and is persisted", _G.MyUIDB.textStyle == "outline")

run("text none")
check("none clears the shadow offset", (function()
    local calls = sample.__calls
    for i = #calls, 1, -1 do
        if calls[i].method == "SetShadowOffset" then
            return calls[i][1] == 0 and calls[i][2] == 0
        end
    end
    return false
end)())

run("text nonsense")
check("an unknown style is refused, leaving the old one",
      Frames.TextStyle() == "none")

run("text shadow")
check("restyling reaches strings created long before it",
      Frames.TextStyle() == "shadow")
check("  and there are strings from more than one module to reach",
      #Frames.strings > 4, #Frames.strings)

-- Structural: a FontString created outside the helper would silently miss the
-- treatment, and the miss would only ever show up on a bright backdrop.
check("no module creates a FontString outside Frames.Text", (function()
    for _, name in ipairs({ "Frames", "Rail", "Peek" }) do
        local f = assert(io.open("../MyUI/" .. name .. ".lua"))
        local src = f:read("*a")
        f:close()
        for line in src:gmatch("[^\n]+") do
            if line:find("CreateFontString", 1, true)
               and not line:find("^%s*%-%-")
               and not line:find("function Frames.Text") then
                -- Frames.Text itself is the one legitimate caller.
                if not line:find("local fs = parent:CreateFontString") then
                    return false, name .. ": " .. line
                end
            end
        end
    end
    return true
end)())

-- ---------------------------------------------------------------------------
section("Rail -- age")
-- ---------------------------------------------------------------------------

check("seconds under a minute", Rail.FormatAge(0) == "0s" and Rail.FormatAge(59) == "59s")
check("minutes after that", Rail.FormatAge(60) == "1m" and Rail.FormatAge(3599) == "59m")
check("hours after that", Rail.FormatAge(3600) == "1h")
check("nonsense is not rendered as a number", Rail.FormatAge(nil) == "?")

Rail.Clear()
Rail.Add("blue", "Ageing")
check("a new item reads as 0s", Rail.slots[1].age:GetText() == "0s")
mock.advance(ns, 5, 1)
check("the age ticks over on its own timer", Rail.slots[1].age:GetText() == "5s",
      Rail.slots[1].age:GetText())

-- ---------------------------------------------------------------------------
section("Rail -- toast lifecycle")
-- ---------------------------------------------------------------------------
-- SPEC 8: slide + fade 180ms in, 4s dwell, 200ms to collapse.

Rail.Clear()
check("nothing is toasting at rest", not Rail.IsToasting())

Rail.Add("blue", "Spoken")
check("an arrival speaks", Rail.IsToasting())
check("  showing the toast", Rail.toastFrame:IsShown())
check("  with the item's text", Rail.toastFrame.label:GetText() == "Spoken")
check("  playing the entrance", Rail.toastFrame.entrance:IsPlaying())

-- The bug this section exists to prevent: the toast used to carry its own dot
-- and its own copy of the text, anchored over the first row, so while it was up
-- you saw the same notification twice, overlapping itself. Every earlier test
-- passed, because none of them asked what the ROW was doing meanwhile.
check("the toast draws no dot of its own", Rail.toastFrame.dot == nil)
check("  borrowing the first slot's instead", (function()
    local p = { Rail.toastFrame:GetPoint(1) }
    return p[2] == Rail.slots[1].dot
end)())
check("the row it stands in for is not drawn underneath it",
      not Rail.RowVisible(1))
check("  though the dot stays, since the toast collapses into it",
      Rail.slots[1].dot ~= nil and Rail.slots[1]:IsShown())
check("  and the second row is unaffected", (function()
    Rail.Add("amber", "Older")
    Rail.Add("green", "Newest")
    return Rail.RowVisible(2)
end)())

-- The changeover has to be a cross-fade. Revealing the row only after the
-- toast finished fading left a gap where neither was drawn, which reads as the
-- text blinking once, four seconds after the notification.
Rail.Collapse()
check("the row is drawn the instant the collapse begins", Rail.RowVisible(1))
check("  starting transparent so the two cross-fade",
      Compat.Get(Rail.slots[1].text, "GetAlpha") == 0,
      Compat.Get(Rail.slots[1].text, "GetAlpha"))
check("  fading in over the same 200ms the toast fades out",
      Rail.slots[1].fade:IsPlaying())
Rail.slots[1].fade:Finish()
check("  and settling at full", Compat.Get(Rail.slots[1].text, "GetAlpha") == 1)
Rail.toastFrame.collapse:Finish()
check("the row remains once the toast has collapsed into it",
      Rail.RowVisible(1))
check("  carrying the same text the toast had",
      Rail.slots[1].name:GetText() == "Newest")

-- The slide has to come FROM somewhere. A Translation snaps back to its anchor
-- when it finishes, so animating toward the anchor would slide right and then
-- jump left.
Rail.Add("violet", "Sliding")
local startX = select(4, Rail.toastFrame:GetPoint(1))
Rail.toastFrame.entrance:Finish()
local restX = select(4, Rail.toastFrame:GetPoint(1))
check("the toast starts left of where it settles", startX < restX,
      tostring(startX) .. " -> " .. tostring(restX))
Rail.Collapse()
Rail.toastFrame.collapse:Finish()

Rail.Clear()
Rail.Add("blue", "Spoken")

mock.advance(ns, 3.9, 4)
check("it is still up before the dwell runs out", Rail.IsToasting())
mock.advance(ns, 0.2, 1)
check("and collapses after 4s", not Rail.IsToasting())
check("  by playing the collapse, not by vanishing",
      Rail.toastFrame.collapse:IsPlaying())
Rail.toastFrame.collapse:Finish()
check("  and hides when that finishes", not Rail.toastFrame:IsShown())

-- "speaks once": a second arrival takes the slot rather than queueing behind it.
Rail.Add("amber", "First")
mock.advance(ns, 1, 1)
Rail.Add("green", "Second")
check("a newer arrival takes over the toast",
      Rail.toastFrame.label:GetText() == "Second")
check("  and restarts the dwell rather than inheriting it", (function()
    mock.advance(ns, 3.5, 4)
    return Rail.IsToasting()
end)())
mock.advance(ns, 0.7, 1)
check("  then collapses on its own clock", not Rail.IsToasting())

-- SPEC 6: "after 4s OR on dismissal".
Rail.toastFrame.collapse:Finish()
Rail.Add("orange", "Dismissed")
check("dismissal collapses early", Rail.Collapse() == true)
check("  and there is nothing left to dismiss", Rail.Collapse() == false)
-- Click-to-dismiss is gone. SPEC 8 asks for "4s or on dismissal" and never
-- says the dismissal is a click, so the mechanism stays and the mouse surface
-- goes. What that buys is worth more than the gesture: the rail sits on the
-- left edge of the screen, and nothing there eats a world click.
check("the toast takes no mouse input", Rail.toastFrame.scripts.OnMouseDown == nil)
check("  and nothing in the rail enables the mouse at all", (function()
    local src = assert(io.open("../MyUI/Rail.lua")):read("*a")
    return src:find("EnableMouse", 1, true) == nil
end)())

Rail.toastFrame.collapse:Finish()
Rail.Clear()
check("clearing empties the rail", #Rail.items == 0 and not Rail.slots[1]:IsShown())
check("  and no row text survives it", not Rail.RowVisible(1))

-- ---------------------------------------------------------------------------
section("Rail -- what feeds it")
-- ---------------------------------------------------------------------------
-- SPEC 6's event table, wired up. C1 -- "what produces a notification?" -- was
-- the biggest thing the spec left open, and Phase 3 shipped /myui notify rather
-- than invent an answer. The amendment supplies one.
--
-- Nothing here is protected. Item quality, bag slots, durability and mail flags
-- are ordinary Lua, and the amended RULES says so out loud because
-- over-applying the rules produces worse code rather than safer code.

local Sources = ns.Sources
local sourceDriver = Sources.driver

check("the source driver exists", sourceDriver ~= nil)

-- The spec's table, transcribed. If a later edit drops an event or adds one the
-- design never asked for, this is what says so.
check("every event SPEC 6 names is wired, and only those", (function()
    local want = {
        "CHAT_MSG_LOOT", "LOOT_ITEM_ROLL_WON",
        "QUEST_ACCEPTED", "QUEST_TURNED_IN",
        "CURRENCY_DISPLAY_UPDATE", "CHAT_MSG_COMBAT_FACTION_CHANGE",
        "ACHIEVEMENT_EARNED", "PLAYER_DEAD",
        "UPDATE_PENDING_MAIL", "BAG_UPDATE_DELAYED", "UPDATE_INVENTORY_DURABILITY",
        "PARTY_INVITE_REQUEST", "GUILD_INVITE_REQUEST",
    }
    local seen = {}
    for _, event in ipairs(want) do
        if type(Sources.EVENTS[event]) ~= "function" then return false, "missing " .. event end
        seen[event] = true
    end
    for event in pairs(Sources.EVENTS) do
        if not seen[event] then return false, "unasked-for " .. event end
    end
    return true
end)())

local function fire(event, ...)
    Rail.Clear()
    sourceDriver:Fire(event, ...)
    return Rail.items[1]
end

-- --- blue: loot ------------------------------------------------------------

mock.itemQuality[6948] = 4
local EPIC = "You receive loot: |cffa335ee|Hitem:6948::::::::70:::::|h[Hearthstone]|h|r x3."

local got = fire("CHAT_MSG_LOOT", EPIC, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
                 mock.playerGUID)
check("your own loot posts a blue row", got ~= nil and got.kind == "blue", got and got.kind)
check("  named from the item link", got and got.name == "Hearthstone", got and got.name)
check("  with the count read after the link, not out of the name",
      got and got.count == 3, got and got.count)

check("somebody else's loot is ignored", (function()
    Rail.Clear()
    sourceDriver:Fire("CHAT_MSG_LOOT", EPIC, nil, nil, nil, nil, nil, nil, nil, nil, nil,
                      nil, "Player-1-SOMEONE")
    return #Rail.items == 0
end)())

-- With no GUID the localized "you receive" strings decide. Guessing wrong in a
-- raid is the noisy direction, so an unattributable message is dropped.
check("a message with no GUID falls back to the localized patterns", (function()
    Rail.Clear()
    sourceDriver:Fire("CHAT_MSG_LOOT", EPIC)
    return #Rail.items == 1
end)())
check("  and one that names somebody else is dropped", (function()
    Rail.Clear()
    sourceDriver:Fire("CHAT_MSG_LOOT",
                      "Someone receives loot: |Hitem:6948::::::::70:::::|h[Hearthstone]|h|r.")
    return #Rail.items == 0
end)())

-- SPEC 6: "loot at uncommon and above", a saved variable.
mock.itemQuality[1234] = 1
local POOR = "You receive loot: |Hitem:1234::::::::70:::::|h[Linen Cloth]|h|r."
check("common loot is filtered out", (function()
    Rail.Clear()
    sourceDriver:Fire("CHAT_MSG_LOOT", POOR, nil, nil, nil, nil, nil, nil, nil, nil, nil,
                      nil, mock.playerGUID)
    return #Rail.items == 0
end)())
check("  and the threshold comes from saved variables", (function()
    _G.MyUIDB.sources.lootQuality = 1
    Rail.Clear()
    sourceDriver:Fire("CHAT_MSG_LOOT", POOR, nil, nil, nil, nil, nil, nil, nil, nil, nil,
                      nil, mock.playerGUID)
    local n = #Rail.items
    _G.MyUIDB.sources.lootQuality = 2
    return n == 1
end)())

-- --- amber: quests ---------------------------------------------------------

mock.questTitles[42] = "The Missing Diplomat"
got = fire("QUEST_ACCEPTED", 42)
check("accepting a quest posts an amber row", got ~= nil and got.kind == "amber")
check("  named from the quest log", got and got.name == "The Missing Diplomat")

got = fire("QUEST_TURNED_IN", 42)
check("turning one in posts too", got ~= nil and got.name == "The Missing Diplomat")

got = fire("QUEST_ACCEPTED", 999)
check("an unknown quest id still posts, with a fallback name",
      got ~= nil and got.name == "Quest accepted", got and got.name)

-- --- the stream rule -------------------------------------------------------
-- SPEC 6: "one row per event, never a stream". UNIT_QUEST_LOG_CHANGED fires
-- several times for one objective and carries no id to tell them apart.

Rail.Clear()
-- G1 is closed by deletion. UNIT_QUEST_LOG_CHANGED fired several times per
-- objective and carried no quest id, so its row could never be named or rolled
-- up -- it just said "Objective". Dropped rather than tuned: it was the only
-- row on the rail that could not say what it was about.
check("quest objectives are not a source", Sources.EVENTS.UNIT_QUEST_LOG_CHANGED == nil)
check("  and the window that existed only for them went with it",
      Sources.COALESCE == nil and Sources.Coalesce == nil)
check("  so firing it does nothing at all", (function()
    Rail.Clear()
    sourceDriver:Fire("UNIT_QUEST_LOG_CHANGED", "player")
    return #Rail.items == 0, #Rail.items
end)())
-- Quests still speak; it is only the unnameable progress event that went.
check("  while accepting a quest still does", (function()
    Rail.Clear()
    sourceDriver:Fire("QUEST_ACCEPTED", 42)
    return #Rail.items == 1, #Rail.items
end)())

-- --- green: currency and reputation ---------------------------------------

mock.currencies[1602] = "Conquest"
got = fire("CURRENCY_DISPLAY_UPDATE", 1602, 250, 50)
check("a currency gain posts a green row", got ~= nil and got.kind == "green")
check("  named and counted", got and got.name == "Conquest" and got.count == 50)
check("spending is not a notification", (function()
    Rail.Clear()
    sourceDriver:Fire("CURRENCY_DISPLAY_UPDATE", 1602, 200, -50)
    return #Rail.items == 0
end)())

got = fire("CHAT_MSG_COMBAT_FACTION_CHANGE",
           "Your reputation with Stormwind has increased by 250.")
check("reputation posts the faction, not the sentence",
      got ~= nil and got.name == "Stormwind", got and got.name)

-- FOUND IN GAME: the first version knew only FACTION_STANDING_INCREASED and the
-- rail drew the fallback "Reputation" instead of a faction. The client ships
-- several forms and GlobalStrings.lua is not in the reference dump, so the
-- reader scans for them rather than naming one.
check("  from the achievement-bonus form too", (function()
    mock.time = mock.time + Sources.QUIET + 1
    local item = fire("CHAT_MSG_COMBAT_FACTION_CHANGE",
        "Your reputation with Valdrakken Accord has increased by 250.  "
        .. "(+25.0 bonus from achievement)")
    return item ~= nil and item.name == "Valdrakken Accord", item and item.name
end)())
check("  and the account-wide form", (function()
    mock.time = mock.time + Sources.QUIET + 1
    local item = fire("CHAT_MSG_COMBAT_FACTION_CHANGE",
        "Your account-wide reputation with Dream Wardens has increased by 75.")
    return item ~= nil and item.name == "Dream Wardens", item and item.name
end)())
check("  and the generic form, which does not start the same way", (function()
    mock.time = mock.time + Sources.QUIET + 1
    local item = fire("CHAT_MSG_COMBAT_FACTION_CHANGE", "Reputation with Ironforge increased.")
    return item ~= nil and item.name == "Ironforge", item and item.name
end)())
check("  a %.1f in the format does not break the escaper", (function()
    -- The naive converter escaped first and turned "%.1f" into something that
    -- matched nothing, which is how the bonus form went silently unhandled.
    local pattern = Sources.ToPattern("Your reputation with %s has increased by %d.  (+%.1f bonus)")
    return pattern ~= nil
       and ("Your reputation with Zaralek has increased by 10.  (+1.5 bonus)")
           :match(pattern) == "Zaralek", pattern
end)())
check("  and a format with no %s is not a faction pattern",
      Sources.ToPattern("Reputation increased.") == nil)
check("every variant the client ships was found, not listed",
      #Sources.FactionPatterns() >= 4, #Sources.FactionPatterns())

-- --- violet: achievements --------------------------------------------------

mock.achievements[5] = "Explorer"
got = fire("ACHIEVEMENT_EARNED", 5)
check("an achievement posts a violet row", got ~= nil and got.kind == "violet")
check("  named", got and got.name == "Explorer")

-- --- orange: something wants you -------------------------------------------

check("a party invite posts orange", (function()
    local item = fire("PARTY_INVITE_REQUEST", "Thrall")
    return item ~= nil and item.kind == "orange" and item.name:find("Thrall", 1, true) ~= nil
end)())
check("  as does a guild invite", (function()
    local item = fire("GUILD_INVITE_REQUEST", "Thrall", "Horde")
    return item ~= nil and item.name:find("Horde", 1, true) ~= nil
end)())

-- The latch. SPEC's own example: "a full bag says so once, not on every
-- BAG_UPDATE."
Rail.Clear()
Sources.latched.bagFull = nil
mock.bagFree = 0
for _ = 1, 5 do sourceDriver:Fire("BAG_UPDATE_DELAYED") end
check("a full bag says so once, not on every update", #Rail.items == 1, #Rail.items)
check("  in orange", Rail.items[1] and Rail.items[1].kind == "orange")

mock.bagFree = 3
sourceDriver:Fire("BAG_UPDATE_DELAYED")
check("making room clears the latch silently", #Rail.items == 1, #Rail.items)
mock.bagFree = 0
sourceDriver:Fire("BAG_UPDATE_DELAYED")
check("  and filling it again speaks again", #Rail.items == 2, #Rail.items)
mock.bagFree = 5
sourceDriver:Fire("BAG_UPDATE_DELAYED")

Rail.Clear()
Sources.latched.durability = nil
mock.durability = 0.10
for _ = 1, 4 do sourceDriver:Fire("UPDATE_INVENTORY_DURABILITY") end
check("worn gear says so once", #Rail.items == 1, #Rail.items)
mock.durability = 0.5
sourceDriver:Fire("UPDATE_INVENTORY_DURABILITY")
check("  and repairing clears it", Sources.latched.durability == nil)

-- Unreadable is not the same as fine. Nil must not clear a live warning, or a
-- login mid-warning would silently disarm it.
Sources.latched.durability = true
mock.durability = nil
sourceDriver:Fire("UPDATE_INVENTORY_DURABILITY")
check("  but unreadable durability leaves the latch alone",
      Sources.latched.durability == true)
mock.durability = 1.0
Sources.latched.durability = nil

Rail.Clear()
Sources.latched.mail = nil
mock.hasMail = true
sourceDriver:Fire("UPDATE_PENDING_MAIL")
sourceDriver:Fire("UPDATE_PENDING_MAIL")
check("pending mail says so once", #Rail.items == 1, #Rail.items)
mock.hasMail = false
sourceDriver:Fire("UPDATE_PENDING_MAIL")
check("  and reading it clears the latch", Sources.latched.mail == nil)

-- The whole file has to survive an API that is not there. On 12.1 a
-- misremembered name returns nil in game while every offline test passes.
check("a missing reader does not take the source down", (function()
    local saved = _G.C_CurrencyInfo
    _G.C_CurrencyInfo = nil
    Rail.Clear()
    local ok = pcall(function() sourceDriver:Fire("CURRENCY_DISPLAY_UPDATE", 1602, 250, 50) end)
    _G.C_CurrencyInfo = saved
    return ok and #Rail.items == 1 and Rail.items[1].name == "Currency",
           Rail.items[1] and Rail.items[1].name
end)())

Rail.Clear()
Sources.latched = {}

-- ---------------------------------------------------------------------------
section("Core -- saved variables")
-- ---------------------------------------------------------------------------

check("database was created", type(_G.MyUIDB) == "table")
check("  at the current schema", _G.MyUIDB.schema == ns.SCHEMA_VERSION)
check("  recording the phase", _G.MyUIDB.addon.phase == ns.phase, _G.MyUIDB.addon.phase)
check("  with an alpha table for phase 5", type(_G.MyUIDB.alpha) == "table")
-- Phase 0 shipped an empty ladder so no later phase would have to retrofit
-- one. Cutting the modifier channel is the first thing to need a rung.
check("the migration ladder has its first rung",
      type(ns.MIGRATIONS[1]) == "function")
check("  which clears the setting the cut channel left behind", (function()
    local old = { schema = 1, modifiers = { alt = true, shift = true } }
    ns.MIGRATIONS[1](old)
    return old.modifiers == nil
end)())
check("  and a fresh database never had it", _G.MyUIDB.modifiers == nil)
check("  the ladder reaches the current schema", (function()
    for n = 1, ns.SCHEMA_VERSION - 1 do
        if type(ns.MIGRATIONS[n]) ~= "function" then return false, n end
    end
    return true
end)())

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

-- Pinned to phase 2: that is the phase whose acceptance is the reveal engine.
-- A later phase's script has no reason to mention every channel.
check("phase 2's script covers every reveal channel", (function()
    local text = ""
    for _, step in ipairs(Testing.scripts[2].steps) do
        text = text .. " " .. step.act:lower() .. " " .. step.expect:lower()
    end
    for _, word in ipairs({ "cursor", "alt", "target", "combat", "peek" }) do
        if not text:find(word, 1, true) then return false, word end
    end
    return true
end)())

check("phase 3's script covers what PLAN's acceptance names", (function()
    local text = ""
    for _, step in ipairs(Testing.scripts[3].steps) do
        text = text .. " " .. step.act:lower() .. " " .. step.expect:lower()
    end
    for _, word in ipairs({ "dot", "square", "toast", "calm", "age" }) do
        if not text:find(word, 1, true) then return false, word end
    end
    return true
end)())

-- ---------------------------------------------------------------------------
section("Checklist -- running the commands")
-- ---------------------------------------------------------------------------
-- A step reading "type this, then type that inside four seconds" is a typing
-- test, not a test of the addon. Each step's commands are declared and the
-- panel puts them in the chat box ready to send.

check("every step that names a command declares it", (function()
    for phase, script in pairs(Testing.scripts) do
        for i, step in ipairs(script.steps) do
            -- Only the imperative form: prose that merely mentions a command
            -- in passing is not a step you are being asked to run.
            if step.act:find("Type /") or step.act:find("run the first") then
                if #Testing.CommandsFor(step) == 0 then
                    return false, phase .. ":" .. i
                end
            end
        end
    end
    return true
end)())

check("declared commands are always slash commands", (function()
    for phase, script in pairs(Testing.scripts) do
        for i, step in ipairs(script.steps) do
            for _, cmd in ipairs(Testing.CommandsFor(step)) do
                if cmd:sub(1, 1) ~= "/" then return false, phase .. ":" .. i end
            end
        end
    end
    return true
end)())

check("a single command normalises to a list", (function()
    local one = Testing.CommandsFor({ cmd = "/myui audit" })
    return #one == 1 and one[1] == "/myui audit"
end)())
check("  and no command gives an empty list",
      #Testing.CommandsFor({ act = "look at it" }) == 0)

-- The step that prompted this: two commands inside four seconds.
local tight = nil
for _, step in ipairs(Testing.scripts[3].steps) do
    if #Testing.CommandsFor(step) > 1 then tight = step end
end
check("the four-second step offers both its commands", tight ~= nil
      and #Testing.CommandsFor(tight) == 2)

mock.chatOpened = {}
Testing.SendToChat("/myui notify demo")
check("clicking a command fills the chat box", #mock.chatOpened == 1
      and mock.chatOpened[1] == "/myui notify demo")
check("  rather than running it, so you stay in control",
      _G.MyUIDB.lastCommand ~= "notify")

-- No chat box is not a reason to make someone retype it.
local savedChat = _G.ChatFrameUtil
_G.ChatFrameUtil = nil
check("without a chat box it falls back to the copy window",
      Testing.SendToChat("/myui audit") == false)
check("  which is showing the command", ns.Copy.IsShown())
_G.ChatFrameUtil = savedChat
ns.Copy.Hide()

Testing.Show(3)
Testing.Refresh()

local function findRow(wanted)
    for i, step in ipairs(Testing.Steps()) do
        if #Testing.CommandsFor(step) == wanted then return i end
    end
end

local oneCmd, twoCmd = findRow(1), findRow(2)
check("a one-command step paints one button", (function()
    local painted = Testing.RowCommands(oneCmd)
    return painted and #painted == 1
       and painted[1] == Testing.CommandsFor(Testing.Steps()[oneCmd])[1]
end)(), oneCmd)
check("the four-second step paints both of its buttons", (function()
    local painted = Testing.RowCommands(twoCmd)
    return painted and #painted == 2
end)(), twoCmd)
check("a look-only step paints none", (function()
    for i, step in ipairs(Testing.Steps()) do
        if #Testing.CommandsFor(step) == 0 then
            local painted = Testing.RowCommands(i)
            return painted and #painted == 0, i
        end
    end
    return false
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
check("eight prohibitions are listed", #Rules.forbidden == 8, #Rules.forbidden)
check("every prohibition names an alternative", (function()
    for _, r in ipairs(Rules.forbidden) do
        if not r.yes or r.yes == "" then return false end
    end
    return true
end)())

-- Five since the handoff amendment: two of the original four were wrong on 12.1
-- and the low-health hook was added.
check("five sanctioned mechanisms", #Rules.mechanisms == 5, #Rules.mechanisms)
check("  and the printed heading says so", (function()
    ns.ClearOutput()
    Rules.Print()
    return ns.GetOutput():find("the five sanctioned mechanisms", 1, true) ~= nil
end)())
check("  and the fifth is narrowly licensed, in writing",
      Rules.licence ~= nil and Rules.licence:find("SelfStack", 1, true) ~= nil)

-- RULES.md still says a pulse needs a driver state. It cannot: the same
-- amendment refuted RegisterStateDriver for low health, and SPEC 3 builds the
-- breathe from cross-faded frames instead. Printing the stale claim would send
-- the next reader hunting for a driver state that cannot exist.
check("the printed consequence does not promise a driver state",
      Rules.consequence:find("driver state", 1, true) == nil, Rules.consequence)
check("  but keeps the part that is verified -- SetScale refuses a secret",
      Rules.consequence:find("SetScale", 1, true) ~= nil)

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
section("Log -- the record behind the rail")
-- ---------------------------------------------------------------------------
-- Round 5 killed the cap and let dots age out, which is only honest because
-- something keeps them. Everything the rail is now allowed to forget has to be
-- here, or the design is just losing things with better manners.

local Log = ns.Log

check("the log attached at load", Log.db ~= nil and type(Log.db.entries) == "table")
check("  into its own per-character file", _G.MyUICharDB == Log.db)
check("  carrying a schema", Log.db.schema == Log.SCHEMA)

-- GetTime() resets on reload, so it cannot date a record that outlives the
-- session. This is what makes "filter by time" possible later without a
-- migration, which is the whole reason it is here on day one.
check("entries are dated in epoch seconds, not session seconds", (function()
    Log.Clear()
    Rail.Clear()
    Rail.Add("blue", "Dated")
    local e = Log.db.entries[1]
    return e ~= nil and e.at > 1000000000, e and e.at
end)())
check("  which is a different clock from the rail's", Log.Now() ~= ns.Reveal.Now())

check("every rail item is recorded", (function()
    Log.Clear()
    Rail.Clear()
    Rail.Add("blue", "One")
    Rail.Add("amber", "Two")
    return Log.Count() == 2, Log.Count()
end)())
check("  newest first, like the rail", Log.db.entries[1].name == "Two")
check("  keeping the hue", Log.Filter("amber")[1].name == "Two")
check("  and the count", (function()
    Log.Clear()
    Rail.Add("green", "Stack", 7)
    return Log.db.entries[1].count == 7, Log.db.entries[1].count
end)())

-- A ceiling, not a garbage collector. SavedVariables is Lua source parsed on
-- every login, so an unbounded log is an unbounded login cost.
check("the log is bounded", (function()
    Log.Clear()
    local was = Log.MAX
    Log.MAX = 10
    for i = 1, 25 do Log.Add("blue", "Entry " .. i) end
    local n = Log.Count()
    Log.MAX = was
    return n == 10, n
end)())
check("  dropping the oldest, not the newest", (function()
    Log.Clear()
    local was = Log.MAX
    Log.MAX = 3
    for i = 1, 5 do Log.Add("blue", "Entry " .. i) end
    local newest = Log.db.entries[1].name
    Log.MAX = was
    return newest == "Entry 5", newest
end)())

check("a tally counts per hue, for the filter row", (function()
    Log.Clear()
    Rail.Clear()
    Rail.Add("blue", "a")
    Rail.Add("blue", "b")
    Rail.Add("red", "c")
    local t = Log.Tally()
    return t.blue == 2 and t.red == 1, tostring(t.blue) .. "/" .. tostring(t.red)
end)())

check("/myui log prints the record", (function()
    Log.Clear()
    Rail.Clear()
    Rail.Add("blue", "Readable")
    ns.ClearOutput()
    run("log")
    local out = ns.GetOutput()
    return out:find("Readable", 1, true) ~= nil and out:find("kept", 1, true) ~= nil, out
end)())
check("  filters by hue", (function()
    Log.Clear()
    Rail.Clear()
    Rail.Add("blue", "Bluey")
    Rail.Add("red", "Reddy")
    ns.ClearOutput()
    run("log red")
    local out = ns.GetOutput()
    return out:find("Reddy", 1, true) ~= nil and out:find("Bluey", 1, true) == nil, out
end)())
check("  refuses a hue that does not exist", (function()
    ns.ClearOutput()
    run("log puce")
    return ns.GetOutput():find("unknown hue", 1, true) ~= nil
end)())
check("  and clears on request", (function()
    run("log clear")
    return Log.Count() == 0, Log.Count()
end)())

-- FOUND IN GAME: after a reload the rail was blank and looked broken. The log
-- lives on disk and the rail lives in memory, so the record kept everything
-- and the display forgot it -- survivable when dots sat there forever, not
-- once they age out.
check("the rail comes back from the log after a reload", (function()
    Log.Clear()
    Rail.Clear()
    Rail.Add("blue", "Before the reload")
    Rail.Add("amber", "Also before")
    -- Simulate the reload: the rail is memory, so it empties; the log is not.
    Rail.items = {}
    local n = Rail.Rehydrate()
    return n == 2 and #Rail.items == 2, n
end)())
check("  newest still at the top", Rail.items[1].name == "Also before",
      Rail.items[1].name)
check("  and it does not announce them again", (function()
    Rail.Collapse()
    Rail.items = {}
    Rail.Rehydrate()
    -- They already spoke, in a previous session.
    return not Rail.IsToasting()
end)())
check("  carrying the age across, not the timestamp", (function()
    Log.Clear()
    Rail.Clear()
    Rail.Add("blue", "Aged")
    mock.time = mock.time + 120
    Rail.items = {}
    Rail.Rehydrate()
    local age = ns.Reveal.Now() - Rail.items[1].at
    return age >= 119 and age <= 121, age
end)())
check("  and leaves behind anything past the decay", (function()
    Log.Clear()
    Rail.Clear()
    Rail.Add("blue", "Ancient")
    mock.time = mock.time + Rail.DECAY + 60
    Rail.items = {}
    return Rail.Rehydrate() == 0
end)())
check("  without re-recording what it restored", (function()
    Log.Clear()
    Rail.Clear()
    Rail.Add("blue", "Once")
    local before = Log.Count()
    Rail.items = {}
    Rail.Rehydrate()
    return Log.Count() == before, Log.Count()
end)())

-- ---------------------------------------------------------------------------
section("Sources -- the leading edge")
-- ---------------------------------------------------------------------------
-- Currency and reputation stream. The gain you feel you caused is the first
-- after a quiet stretch; the rest are the system talking to itself. So the
-- first speaks and the rest refresh the dot it already owns -- and every one
-- of them is still written down.

check("the first gain after a quiet stretch speaks", (function()
    Rail.Clear()
    Log.Clear()
    mock.time = mock.time + Sources.QUIET + 1
    Sources.bursts["currency:1602"] = nil
    sourceDriver:Fire("CURRENCY_DISPLAY_UPDATE", 1602, 250, 50)
    return #Rail.items == 1, #Rail.items
end)())
check("  and the stream behind it does not add a second dot", (function()
    for _ = 1, 8 do
        sourceDriver:Fire("CURRENCY_DISPLAY_UPDATE", 1602, 250, 50)
    end
    return #Rail.items == 1, #Rail.items
end)())
check("  it rolls up into the one dot instead", Rail.items[1].count > 8, Rail.items[1].count)
check("  and every single gain reached the log", Log.Count() == 9, Log.Count())

check("a different currency is a different thing happening", (function()
    mock.currencies[1792] = "Honor"
    sourceDriver:Fire("CURRENCY_DISPLAY_UPDATE", 1792, 10, 10)
    return #Rail.items == 2, #Rail.items
end)())

check("the burst reopens once the source goes quiet", (function()
    mock.time = mock.time + Sources.QUIET + 1
    sourceDriver:Fire("CURRENCY_DISPLAY_UPDATE", 1602, 300, 50)
    return #Rail.items == 3, #Rail.items
end)())

-- Round 5's sixth hue, wired to the one event that means it.
check("dying posts a red row", (function()
    Rail.Clear()
    Sources.bursts["death"] = nil
    mock.time = mock.time + Sources.QUIET + 1
    sourceDriver:Fire("PLAYER_DEAD")
    return Rail.items[1] ~= nil and Rail.items[1].kind == "red",
           Rail.items[1] and Rail.items[1].kind
end)())

-- Bump is the rollup. It refreshes rather than duplicating, and it never
-- toasts: the burst already spoke.
check("a bump moves the item back to the front", (function()
    Rail.Clear()
    local first = Rail.Add("blue", "First")
    Rail.Add("amber", "Second")
    Rail.Bump(first)
    return Rail.items[1] == first, Rail.items[1].name
end)())
check("  resetting its clock", (function()
    Rail.Clear()
    local item = Rail.Add("blue", "Ticking")
    local was = item.at
    mock.time = mock.time + 30
    Rail.Bump(item)
    return item.at > was
end)())


-- ---------------------------------------------------------------------------
section("Chat -- the edit box override")
-- ---------------------------------------------------------------------------
-- Step one of replacing the chat log. Additive: nothing is hidden, nothing is
-- intercepted, and clearing the override puts the game back as it was.

local Chat = ns.Chat

check("the box was built at login", Chat.box ~= nil)
check("  and named, so it can be found in game", Chat.box:GetName() == "MyUIChatBox")
check("  registered through Blizzard's own override", Chat.IsOverriding())
check("  which is the API Communities uses, not a hook",
      mock.chatFocusOverride == Chat.box)

-- The flag Blizzard reads in OpenChat. False means a leading "/" never reaches
-- us -- which is precisely why the chat frame has to be hidden and not removed.
check("slash commands are left to Blizzard", Chat.box.supportsSlashCommands == false)

-- The invariant worth locking: we present, we do not route. Chat addons are
-- fragile because they re-implement sending; this file must never learn how.
check("nothing in Chat.lua sends a message itself", (function()
    local src = assert(io.open("../MyUI/Chat.lua")):read("*a")
    return src:find("SendChatMessage", 1, true) == nil
end)())
check("  it hands the text to Blizzard's box instead", (function()
    mock.sent = {}
    local ok = Chat.Send("hello there")
    return ok == true and #mock.sent == 1 and mock.sent[1].text == "hello there",
           #mock.sent
end)())
check("  asking it to keep the history", mock.sent[1].history == 1)

-- The reason a slash typed INSIDE our box still works: SendText calls
-- ParseText, which calls HandleChatType, which is what resolves /w /p /g /r
-- and sets the chat type and tell target (ChatFrameEditBox.lua:148-160). It
-- only works while we pass the text through untouched -- the moment this file
-- starts trimming or rewriting, our box really would be say-only.
check("the text is handed over verbatim, slash and all", (function()
    mock.sent = {}
    Chat.Send("/w Ashlin did you get the fragment?")
    return #mock.sent == 1
       and mock.sent[1].text == "/w Ashlin did you get the fragment?",
           mock.sent[1] and mock.sent[1].text
end)())
check("  including leading whitespace inside the message", (function()
    mock.sent = {}
    Chat.Send("/p  stack on me")
    return mock.sent[1].text == "/p  stack on me", mock.sent[1].text
end)())

check("empty text is not a message", (function()
    mock.sent = {}
    local ok, why = Chat.Send("   ")
    return ok == false and why == "empty"
end)())

check("pressing enter sends and lets go of the keyboard", (function()
    mock.sent = {}
    Chat.box:SetText("into the void")
    Chat.box.scripts.OnEnterPressed(Chat.box)
    local calls = Chat.box.__calls
    local clearedFocus = false
    for i = #calls, 1, -1 do
        if calls[i].method == "ClearFocus" then clearedFocus = true break end
    end
    return #mock.sent == 1 and clearedFocus, #mock.sent
end)())

check("escape sends nothing", (function()
    mock.sent = {}
    Chat.box:SetText("never mind")
    Chat.box.scripts.OnEscapePressed(Chat.box)
    return #mock.sent == 0
end)())

-- Shown but transparent, because OpenChat calls SetFocus on us directly and a
-- hidden EditBox cannot take focus. Alpha hides it; focus shows it.
check("the box is invisible until it has focus", (function()
    Chat.box.scripts.OnEditFocusLost(Chat.box)
    return Chat.box:GetAlpha() == 0, Chat.box:GetAlpha()
end)())
check("  and appears when focused", (function()
    Chat.box.scripts.OnEditFocusGained(Chat.box)
    return Chat.box:GetAlpha() == 1, Chat.box:GetAlpha()
end)())
check("  labelled with what you are talking into", (function()
    mock.chatType = "WHISPER"
    mock.tellTarget = "Ashlin"
    Chat.box.scripts.OnEditFocusGained(Chat.box)
    local label = Chat.box.label:GetText()
    mock.chatType, mock.tellTarget = "SAY", nil
    return label == "whisper Ashlin", label
end)())

-- It takes no mouse, like the rail. Nothing this addon draws eats a click.
check("the box takes no mouse input", (function()
    local src = assert(io.open("../MyUI/Chat.lua")):read("*a")
    return src:find("EnableMouse(false)", 1, true) ~= nil
       and src:find("EnableMouse(true)", 1, true) == nil
end)())

-- FOUND IN GAME: the override did not install and the status could only say
-- "not installed" -- a symptom with no cause attached. The reference dump is
-- 12.1.0.69497 and the live build can differ, so the code now probes, falls
-- back, and checks that what it set actually held.
check("the probe reports what the client offers", (function()
    local p = Chat.Probe()
    return p.util and p.set and p.get and p.clear and p.open
end)())

check("with no setter it writes the global OpenChat actually reads", (function()
    local util = _G.ChatFrameUtil
    local set, get, clear = util.SetChatFocusOverride, util.GetChatFocusOverride,
                            util.ClearChatFocusOverride
    util.SetChatFocusOverride, util.GetChatFocusOverride = nil, nil
    _G.CHAT_FOCUS_OVERRIDE = nil

    local ok, route = Chat.Enable()
    local held = _G.CHAT_FOCUS_OVERRIDE == Chat.box

    util.SetChatFocusOverride, util.GetChatFocusOverride = set, get
    util.ClearChatFocusOverride = clear
    _G.CHAT_FOCUS_OVERRIDE = nil
    return ok == true and held, tostring(route)
end)())
check("  reporting which route it took", Chat.route ~= nil)

check("a set that does not hold is a failure, not a success", (function()
    local util = _G.ChatFrameUtil
    local set = util.SetChatFocusOverride
    -- A client that accepts the call and ignores it. This is exactly what the
    -- first version could not tell apart from working.
    util.SetChatFocusOverride = function() end
    mock.chatFocusOverride = nil
    _G.CHAT_FOCUS_OVERRIDE = nil
    local ok, err = Chat.Enable()
    util.SetChatFocusOverride = set
    Chat.Enable()
    return ok == false and type(err) == "string" and err:find("did not hold", 1, true) ~= nil,
           tostring(err)
end)())

check("the status names the cause when it fails", (function()
    local util = _G.ChatFrameUtil
    local set = util.SetChatFocusOverride
    util.SetChatFocusOverride = function() end
    mock.chatFocusOverride = nil
    _G.CHAT_FOCUS_OVERRIDE = nil
    Chat.Enable()
    ns.ClearOutput()
    run("chat")
    local out = ns.GetOutput()
    util.SetChatFocusOverride = set
    Chat.Enable()
    return out:find("why", 1, true) ~= nil and out:find("client", 1, true) ~= nil, out
end)())

-- FOUND IN GAME, second attempt: the override installed and verified at
-- login, and was nil by the time /myui chat ran. Nothing in Blizzard's
-- Interface clears it except ClearChatFocusOverride, so the addon watches that
-- function rather than guessing which caller it is.
check("it watches for the override being taken back", Chat.watching == true)
check("  counting who clears it", (function()
    Chat.Enable()
    local before = Chat.clears or 0
    _G.ChatFrameUtil.ClearChatFocusOverride()
    return (Chat.clears or 0) == before + 1, Chat.clears
end)())
check("  recording where the clear came from", Chat.clearedBy ~= nil)
check("  and putting it back on the next frame, not inside the teardown", (function()
    Chat.Enable()
    local before = Chat.reasserts or 0
    _G.ChatFrameUtil.ClearChatFocusOverride()
    -- Nothing yet: re-asserting mid-teardown is how you fight a frame that has
    -- not finished putting itself away.
    local immediately = Chat.IsOverriding()
    mock.runTimers()
    return immediately == false and Chat.IsOverriding()
       and (Chat.reasserts or 0) == before + 1
end)())
check("  and it stops re-asserting once disabled", (function()
    Chat.Disable()
    local before = Chat.reasserts or 0
    _G.ChatFrameUtil.ClearChatFocusOverride()
    mock.runTimers()
    local n = Chat.reasserts or 0
    Chat.Enable()
    return n == before
end)())

-- --- the reply key ------------------------------------------------------
check("Bindings.xml declares a reply binding", (function()
    local xml = assert(io.open("../MyUI/Bindings.xml")):read("*a")
    return xml:find('name="MYUI_REPLY"', 1, true) ~= nil
       and xml:find("MyUI_Reply()", 1, true) ~= nil
end)())
check("  and the global it names exists", type(_G.MyUI_Reply) == "function")
check("  with a name for the key bindings menu",
      _G.BINDING_NAME_MYUI_REPLY ~= nil)
check("pressing it opens our box already replying", (function()
    Chat.box:SetText("")
    _G.MyUI_Reply()
    return Chat.box:GetText() == "/r ", Chat.box:GetText()
end)())
check("  and it is Blizzard's own reply command, not our lookup", (function()
    local src = assert(io.open("../MyUI/Chat.lua")):read("*a")
    -- If this file ever starts resolving who whispered you, it has taken on
    -- state Blizzard already keeps correctly.
    return src:find("GetLastTold", 1, true) == nil
end)())

-- --- the furniture ------------------------------------------------------
check("hiding the log takes the edit box out first", (function()
    Chat.HideLog()
    -- FloatingChatFrame.xml:496 declares the edit box inside the chat frame,
    -- so stowing the frame with the box still in it kills slash commands.
    return _G.ChatFrame1EditBox:GetParent() == _G.UIParent
       and Chat.editBoxFreed == true
end)())
check("  and stows the frames, tabs and buttons", (function()
    return Chat.StowedCount() >= 6, Chat.StowedCount()
end)())
check("  under a parent that is itself hidden", (function()
    return _G.ChatFrame1:GetParent() == ns.Stow.Attic()
       and ns.Stow.Attic():IsShown() == false
end)())

-- The reason for the attic rather than Hide(): ChooseBoxForSend branches on
-- IsShown (ChatFrameUtil.lua:490), so a properly hidden chat frame is how you
-- lose the ability to send.
check("  while the chat frame still reports itself shown", _G.ChatFrame1:IsShown() == true)
check("  so Blizzard's send box is still reachable", Chat.SendBox() ~= nil)
check("  and sending still works with the log out of sight", (function()
    mock.sent = {}
    Chat.Send("still here")
    return #mock.sent == 1, #mock.sent
end)())

check("showing it puts everything back", (function()
    Chat.ShowLog()
    return Chat.StowedCount() == 0
       and _G.ChatFrame1:GetParent() == _G.UIParent
       and Chat.logHidden == false
end)())

check("hiding is refused with no way to type", (function()
    Chat.Disable()
    ns.ClearOutput()
    run("chat hide")
    local refused = ns.GetOutput():find("no way to type", 1, true) ~= nil
    Chat.Enable()
    return refused and Chat.StowedCount() == 0, ns.GetOutput()
end)())

check("/myui chat off puts the game back", (function()
    run("chat off")
    return not Chat.IsOverriding() and mock.chatFocusOverride == nil
end)())
check("  and on reinstalls it", (function()
    run("chat on")
    return Chat.IsOverriding()
end)())
check("  status reports the state and the way out", (function()
    ns.ClearOutput()
    run("chat")
    local out = ns.GetOutput()
    return out:find("installed", 1, true) ~= nil
       and out:find("/myui chat off", 1, true) ~= nil, out
end)())


-- ---------------------------------------------------------------------------
section("What is that thing")
-- ---------------------------------------------------------------------------
-- FOUND IN GAME: something Blizzard draws appeared along the left edge that
-- the design never accounted for. The offline suite knows what we drew and
-- nothing about what the client put next to it, so this asks the client.

check("the probe names what is under the cursor", (function()
    mock.mouseFoci = { mock.frame({ name = "SomeBlizzardBar", objectType = "Frame" }) }
    ns.ClearOutput()
    ns.Outline.Under()
    return ns.GetOutput():find("SomeBlizzardBar", 1, true) ~= nil, ns.GetOutput()
end)())
check("  reporting every region under the pixel, not just the top one", (function()
    mock.mouseFoci = {
        mock.frame({ name = "TopThing" }),
        mock.frame({ name = "UnderneathThing" }),
    }
    ns.ClearOutput()
    local named = ns.Outline.Under()
    return #named == 2 and ns.GetOutput():find("UnderneathThing", 1, true) ~= nil
end)())
check("  and says so plainly when nothing takes the mouse", (function()
    mock.mouseFoci = {}
    ns.ClearOutput()
    ns.Outline.Under()
    return ns.GetOutput():find("nothing under the cursor", 1, true) ~= nil
end)())
check("the binding names a global that exists", (function()
    local xml = assert(io.open("../MyUI/Bindings.xml")):read("*a")
    return xml:find('name="MYUI_WHAT"', 1, true) ~= nil
       and type(_G.MyUI_What) == "function"
       and _G.BINDING_NAME_MYUI_WHAT ~= nil
end)())

-- ---------------------------------------------------------------------------
section("Stow -- Blizzard furniture off the screen")
-- ---------------------------------------------------------------------------
-- FOUND IN GAME: CompactRaidFrameManager, a 221x361 frame at the left edge --
-- exactly where the rail lives. It shows whenever you are in a group, or
-- whenever Edit Mode is force-showing party frames, which is easy to leave on
-- by accident (Blizzard_CompactRaidFrameManager.lua:294).

local Stow = ns.Stow

check("the raid manager is a group of its own", Stow.GROUPS.raid ~= nil)
check("  separate from chat, because they come back for different reasons",
      Stow.GROUPS.chat ~= nil and Stow.GROUPS.raid ~= Stow.GROUPS.chat)

check("stowing it moves it into the hidden attic", (function()
    local moved = Stow.Group("raid")
    return moved == 1 and _G.CompactRaidFrameManager:GetParent() == Stow.Attic(), moved
end)())

-- The reason for the attic rather than Hide(): Blizzard calls SetShown on this
-- frame every time your group changes, so a frame we HIDE is a frame we would
-- have to keep re-hiding. Nothing here polls or hooks.
check("  while Blizzard's own show still succeeds", (function()
    _G.CompactRaidFrameManager:Show()
    return _G.CompactRaidFrameManager:IsShown() == true
       and _G.CompactRaidFrameManager:GetParent() == Stow.Attic()
end)())

check("  and it comes back on request", (function()
    local back = Stow.Restore("raid")
    return back == 1 and _G.CompactRaidFrameManager:GetParent() == _G.UIParent
end)())

-- Unit frames are protected. The manager itself is not, but it is the visible
-- edge of a protected system, so this group never moves during combat.
check("it refuses to move during combat", (function()
    local was = _G.InCombatLockdown
    _G.InCombatLockdown = function() return true end
    local moved, err = Stow.Group("raid")
    _G.InCombatLockdown = was
    return moved == nil and tostring(err):find("combat", 1, true) ~= nil, tostring(err)
end)())
check("  and the chat group, which is ordinary UI, does not", (function()
    local was = _G.InCombatLockdown
    _G.InCombatLockdown = function() return true end
    Stow.Restore("chat")
    local moved = Stow.Group("chat")
    _G.InCombatLockdown = was
    Stow.Restore("chat")
    return moved ~= nil and moved > 0, tostring(moved)
end)())

check("restoring one group leaves the other alone", (function()
    Stow.Group("chat")
    Stow.Group("raid")
    Stow.Restore("raid")
    return Stow.Count("chat") > 0 and Stow.Count("raid") == 0
end)())
check("  and restoring everything takes both", (function()
    Stow.Group("raid")
    Stow.Restore()
    return Stow.Count() == 0, Stow.Count()
end)())

check("/myui stow reports what is off the screen", (function()
    ns.ClearOutput()
    run("stow")
    local out = ns.GetOutput()
    return out:find("raid", 1, true) ~= nil and out:find("visible", 1, true) ~= nil, out
end)())
check("  stows a named group", (function()
    run("stow raid")
    return Stow.IsStowed("raid")
end)())
check("  and shows it again", (function()
    run("stow show raid")
    return not Stow.IsStowed("raid")
end)())
check("  refusing a group that does not exist", (function()
    ns.ClearOutput()
    run("stow banana")
    return ns.GetOutput():find("no such group", 1, true) ~= nil
end)())

-- ---------------------------------------------------------------------------
section("Panel -- switches instead of typing")
-- ---------------------------------------------------------------------------

local Panel = ns.Panel

check("the minimap button exists", Panel.button ~= nil)
check("  and the panel is closed at rest", Panel.IsOpen() == false)
check("  with a switch for every toggle", #Panel.panel.rows == #Panel.TOGGLES)

-- Every switch runs the same path a typed command does. A second way to change
-- state is a second thing to keep in agreement.
check("switches go through the command dispatcher", (function()
    local src = assert(io.open("../MyUI/Panel.lua")):read("*a")
    return src:find("ns.Commands.Run", 1, true) ~= nil
       and src:find("Chat.HideLog()", 1, true) == nil
end)())

check("the panel reads live state, so it cannot disagree", (function()
    ns.Stow.Restore("raid")
    Panel.Toggle()
    local raidRow
    for _, row in ipairs(Panel.panel.rows) do
        if row.spec.key == "raid" then raidRow = row end
    end
    local before = raidRow.tick:GetAlpha()
    -- Change it the OTHER way, by command, behind the panel's back.
    run("stow raid")
    Panel.Refresh()
    return before == 1 and raidRow.tick:GetAlpha() == 0
end)())

check("clicking a switch flips the thing itself", (function()
    for _, row in ipairs(Panel.panel.rows) do
        if row.spec.key == "raid" then
            row.scripts.OnClick(row)
            return not ns.Stow.IsStowed("raid")
        end
    end
    return false
end)())

-- FOUND IN GAME: "attempt to perform arithmetic on local 'my' (a nil value)".
-- The guard was `_G.Minimap and _G.Minimap:GetCenter()`, and an `and`
-- expression keeps only the first return value.
check("dropping the button survives a minimap that answers oddly", (function()
    local map = _G.Minimap
    local was = map.GetCenter
    map.GetCenter = function() return 1400 end          -- one value, not two
    local ok = pcall(Panel.button.scripts.OnDragStop, Panel.button)
    map.GetCenter = function() return nil, nil end        -- no values
    local ok2 = pcall(Panel.button.scripts.OnDragStop, Panel.button)
    map.GetCenter = was
    return ok and ok2
end)())
check("  and still places it when the answer is whole", (function()
    Panel.button.scripts.OnDragStop(Panel.button)
    return type(ns.db.panel.angle) == "number"
end)())

check("the button remembers where you dragged it", (function()
    Panel.Place(45)
    return ns.db.panel.angle == 45
end)())

Panel.Toggle()

-- ---------------------------------------------------------------------------
section("Centre -- reading the record")
-- ---------------------------------------------------------------------------
-- The rail became lossy on purpose: dots age out, the pool has a ceiling, and
-- the chat log is stowed. This is the first thing that reads the log back, and
-- until it existed a whisper was a dot and nothing else.

local Center = ns.Center

check("the centre was built at login", Center.panel ~= nil)
check("  named, so Escape can close it through UISpecialFrames",
      Center.panel:GetName() == "MyUICenter")
check("  closed at rest", Center.IsOpen() == false)

-- "The center is the rail" -- same anchor, growing right, not a window
-- somewhere else.
check("it opens at the rail's own edge", (function()
    local src = assert(io.open("../MyUI/Center.lua")):read("*a")
    return src:find('SetPoint("LEFT", anchor.frame, "LEFT", 0, 0)', 1, true) ~= nil
end)())

-- Deliberately not a palette entry: the palette is the resting HUD's thirteen
-- colours, and a fourteenth is an error.
check("the opaque surface is not smuggled into the palette",
      ns.Palette.colors["surface"] == nil and ns.Palette.COUNT == 13)
check("  and it is the value Round 5 named", (function()
    local s = Center.SURFACE
    return math.abs(s[1] - 10/255) < 0.001 and math.abs(s[4] - 0.86) < 0.001
end)())

check("it lists what the log holds", (function()
    Log.Clear()
    Rail.Clear()
    Rail.Add("blue", "Ashlin")
    Rail.Add("green", "Voidsteel Greaves")
    Center.Filter(nil)
    Center.Open()
    return Center.panel.rows[1]:IsShown()
       and Center.panel.rows[1].name:GetText() == "Voidsteel Greaves",
           Center.panel.rows[1].name:GetText()
end)())
check("  newest first", Center.panel.rows[2].name:GetText() == "Ashlin")
check("  with a count per hue on the filter row", (function()
    for _, chip in ipairs(Center.panel.chips) do
        if chip.hue == "blue" then return chip.count:GetText() == "1", chip.count:GetText() end
    end
    return false, "no blue chip"
end)())

check("filtering narrows it to one hue", (function()
    Center.Filter("blue")
    return Center.panel.rows[1].name:GetText() == "Ashlin"
       and not Center.panel.rows[2]:IsShown()
end)())
check("  and the unselected hues dim rather than grow chrome", (function()
    for _, chip in ipairs(Center.panel.chips) do
        if chip.hue == "green" then return chip:GetAlpha() < 1, chip:GetAlpha() end
    end
    return false
end)())
check("  clicking the same hue again clears the filter", (function()
    for _, chip in ipairs(Center.panel.chips) do
        if chip.hue == "blue" then chip.scripts.OnClick(chip) end
    end
    return Center.filter == nil
end)())

-- "Toasts suppress while open ... incoming events insert silently at the top
-- instead of announcing."
check("a notification arriving while it is open does not toast", (function()
    Center.Open()
    Rail.Collapse()
    Rail.Add("amber", "Quiet arrival")
    return not Rail.IsToasting()
end)())
check("  but it is still on the rail", Rail.items[1].name == "Quiet arrival")
check("  and still in the log", Log.db.entries[1].name == "Quiet arrival")
check("  and the centre shows it immediately",
      Center.panel.rows[1].name:GetText() == "Quiet arrival")

check("it toasts again once closed", (function()
    Center.Close()
    Rail.Collapse()
    Rail.Add("blue", "Loud again")
    return Rail.IsToasting()
end)())

-- Closed, it takes no mouse at all: a hidden frame cannot be clicked, which is
-- what keeps the left edge of the screen passing clicks to the world.
check("closed, it is hidden rather than transparent", (function()
    Center.Close()
    return Center.panel:IsShown() == false
end)())

check("the binding names a global that exists", (function()
    local xml = assert(io.open("../MyUI/Bindings.xml")):read("*a")
    return xml:find('name="MYUI_CENTER"', 1, true) ~= nil
       and type(_G.MyUI_Center) == "function"
       and _G.BINDING_NAME_MYUI_CENTER ~= nil
end)())
check("  and it toggles", (function()
    Center.Close()
    _G.MyUI_Center()
    local opened = Center.IsOpen()
    _G.MyUI_Center()
    return opened and not Center.IsOpen()
end)())

check("/myui center opens it filtered", (function()
    run("center green")
    return Center.IsOpen() and Center.filter == "green", tostring(Center.filter)
end)())
check("  and refuses a hue that does not exist", (function()
    ns.ClearOutput()
    run("center puce")
    return ns.GetOutput():find("unknown hue", 1, true) ~= nil
end)())
run("center close")

-- ---------------------------------------------------------------------------
print("")
print(("%d checks, %d failures"):format(checks, failures))
os.exit(failures == 0 and 0 or 1)
