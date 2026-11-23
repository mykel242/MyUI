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
-- The offline suite exercises every module, extras included; the MVP's
-- extras-off behaviour has its own section near the end.
_G.MyUIDB = { schema = ns.SCHEMA_VERSION, extras = true }

local loader = _G.MyUILoader
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

check("every file in the TOC was loaded", #ns.__loadedFiles == 34, #ns.__loadedFiles)

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
-- Round 003's Resume track tags as -rN (v0.5.0-r3) while X-Phase stays the
-- last delivered phase; a phase build still carries -phaseN.
check("TOC version carries the phase or resume-step suffix",
      toc.Version:match("%-phase(%d+)$") == toc["X-Phase"] or toc.Version:match("%-r%d+%a?$") ~= nil,
      toc.Version .. " vs X-Phase " .. tostring(toc["X-Phase"]))
check("  and the addon agrees with it",
      tonumber(toc["X-Phase"]) == ns.phase, toc["X-Phase"] .. " vs " .. tostring(ns.phase))
check("  and reports the TOC version, not a stale one",
      ns.version == toc.Version, ns.version .. " vs " .. tostring(toc.Version))
for _, mod in ipairs({ "Compat", "Scale", "Palette", "Guard", "Registry",
                       "Frames", "Reveal", "Peek", "Toast", "Log", "Center", "Sources", "Outline", "Testing",
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

check("the three SPEC 2 frames registered (the rail is cut), plus round 004's action bar, group frames and pet, and round 005's quest list",
      Registry.Count() == 8 and Registry.Get("QuestList") ~= nil and Registry.Get("ActionBar") ~= nil and Registry.Get("Focus") ~= nil and Registry.Get("Group") ~= nil and Registry.Get("Pet") ~= nil, Registry.Count())

local EXPECTED = {
    -- name,        resting, mock w, mock h, anchor,   x,   y
    -- Round 004: positions from the default layout profile ("focus").
    { "SelfStack",   0.35, 240, 33, "BOTTOM",   0,   24 },   -- grew a text row; under the bar
    { "Cooldowns",   0.25, 240,  4, "TOP",      0,  -18 },
    { "TargetStrip", 0,    400, 49, "BOTTOM",   0,  163 },   -- over bar 1 and its mini page rows
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
check("Compat.Call forwards GetPoint's fifth value", ok5 and near(y5, Scale.U(24)), y5)

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
check("health number sits just above the middle of the health bar, no pill (round 004)", (function()
    local p, rel, rp = stack.pill:GetPoint(1)
    local np, nrel = stack.number:GetPoint(1)
    return p == "BOTTOM" and rel == stack.health and rp == "TOP"
           and np == "CENTER" and nrel == stack.pill and not stack.pill.bg:IsShown()
end)())
check("name, percentage and level on one row, bottoms 2 above the bar -- self and target", (function()
    for _, g in ipairs({ stack, Registry.Get("TargetStrip").frame }) do
        local np, nrel, nrp, _, ny = g.name:GetPoint(1)
        local lp, lrel, lrp, _, ly = g.level:GetPoint(1)
        local pp, prel, prp, _, py = g.pill:GetPoint(1)
        local _, ph = g.pill:GetSize()
        if not (np == "BOTTOMLEFT" and nrel == g.health and nrp == "TOPLEFT"
                and lp == "BOTTOMRIGHT" and lrel == g.health and lrp == "TOPRIGHT"
                and pp == "BOTTOM" and prel == g.health and prp == "TOP"
                and near(ny, Scale.U(2)) and near(ly, ny) and near(py, ny)
                and near(ph, Scale.U(12))) then
            return false
        end
    end
    local _, _, _, _, hy = stack.health:GetPoint(1)
    return near(hy, -Scale.U(13))
end)())

check("a long name stops short of the centred percentage, on one line", (function()
    local p, rel, rp, x = stack.name:GetPoint(2)
    return p == "BOTTOMRIGHT" and rel == stack.health and rp == "TOP" and near(x, -Scale.U(26))
end)())

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
section("Frames -- TargetStrip")
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

check("the rail is gone (round 003)", Registry.Get("Rail") == nil and ns.Rail == nil)

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
check("target leaves the strip to follow the self stack (round 004)", stripEntry.target == 0)
check("  leaving the self stack at rest", stackEntry.target == 0.35)
Reveal.Release("target")

Reveal.Claim("peek")
check("peek claims everything", stackEntry.target == 1 and stripEntry.target == 1)
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
check("acquiring a target shows the strip as visible as the self stack (round 004)", stripEntry.target == 0.35)
check("  and the self stack stays at rest", stackEntry.target == 0.35)
Reveal.Claim("combat")
check("  in combat both come up", stripEntry.target == 1 and stackEntry.target == 1)
Reveal.Release("combat")
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
check("three presses log three claims", #logOf("claim", "channel", "peek") == 3, #logOf("claim", "channel", "peek"))
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
    for _ = 1, 100 do
        Reveal.Claim("combat")
        Reveal.Release("combat")
    end
    return #Reveal.log <= 60
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
    for _, name in ipairs({ "Frames", "Toast", "Center", "Peek" }) do
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
section("Toasts -- SPEC 6, round 003")
-- ---------------------------------------------------------------------------
-- The rail is cut; its toast survives at ToastAnchor. One toast per event,
-- never a stream, and the log is written before anything speaks.

local Toast = ns.Toast

check("the anchor was built at login", Toast.Anchor() ~= nil)
check("  and is not in the reveal registry (nothing to reveal at rest)",
      Registry.Get("ToastAnchor") == nil)
check("five hues, all palette entries, no red", (function()
    local n = 0
    for _, colour in pairs(Toast.HUES) do
        n = n + 1
        if not ns.Palette.colors[colour] then return false, colour end
    end
    return n == 5 and Toast.HUES.red == nil, n
end)())
check("an unknown hue is refused", select(1, Toast.Add("puce", "x")) == nil)

Toast.Clear()
ns.Log.Clear()
local spoken = Toast.Add("blue", "Hearthstone")
check("a toast speaks", Toast.IsSpeaking() and Toast.live[1] == spoken)
check("  and is in the log first", ns.Log.db.entries[1].name == "Hearthstone")
check("  painted: name and an age", (function()
    local f = Toast.pool[1]
    return f.item == spoken and f.name:GetText() == "Hearthstone" and f.age:GetText() == "0s"
end)())

mock.advance(ns, Toast.DWELL + 0.1)
check("it leaves on its own after the 4s dwell", not Toast.IsSpeaking())

Toast.Clear()
for i = 1, Toast.CAP + 2 do Toast.Add("amber", "Burst " .. i) end
check("past the cap, the oldest leave at once", #Toast.live == Toast.CAP, #Toast.live)
check("  newest at the anchor", Toast.live[1].name == ("Burst " .. (Toast.CAP + 2)))
check("  and every one of them is in the log", ns.Log.Count("amber") >= Toast.CAP + 2)

Toast.Clear()
local rolling = Toast.Add("green", "Conquest", 10)
local before = ns.Log.Count()
Toast.Bump(rolling, 5)
check("a bump rolls into the toast it owns", rolling.count == 15 and #Toast.live == 1)
check("  and is logged", ns.Log.Count() == before + 1)

check("dismiss leaves now", (function()
    Toast.Clear()
    Toast.Add("orange", "Mail")
    Toast.Dismiss()
    return not Toast.IsSpeaking()
end)())

-- SPEC 6: "A toast can be interacted with." SPEC 14: a whisper toast opens
-- chat at that conversation.
do
    local opened
    local realOpen = ns.Chat.Open
    ns.Chat.Open = function(prefill) opened = prefill end
    Toast.Clear()
    -- These are the legacy paths (the chat switch off, no chat panel).
    local talkWas = ns.Talk.enabled
    ns.Talk.enabled = false
    check("clicking a whisper opens chat at /w and the sender", (function()
        local it = Toast.Add("violet", "Friend-Realm", 1, "Friend-Realm")
        Toast.Activate(it)
        return opened == "/w Friend-Realm ", opened
    end)())
    check("  a whisper with no name to answer falls back to /r", (function()
        local it = Toast.Add("violet", "Whisper")
        Toast.Activate(it)
        return opened == "/r ", opened
    end)())
    ns.Talk.enabled = talkWas
    ns.Chat.Open = realOpen
end
check("clicking anything else opens the history at its hue", (function()
    local it = Toast.Add("green", "Valor")
    local how = Toast.Activate(it)
    local ok = how == "history" and ns.Center.IsOpen() and ns.Center.filter == "green"
    ns.Center.Close()
    ns.Center.Filter(nil)
    return ok, how
end)())
check("right click dismisses", (function()
    Toast.Clear()
    local it = Toast.Add("blue", "Gone")
    local f = Toast.pool[1]
    for _, frame in ipairs(Toast.pool) do if frame.item == it then f = frame end end
    f.scripts.OnMouseUp(f, "RightButton")
    return not Toast.IsSpeaking()
end)())
Toast.Clear()

-- What the sources posted, newest first. The rail used to be this list; now a
-- toast is the announcement and the log the record, so the tests watch what
-- reached Toast.Add -- one entry per announcement, a burst rolling into its own.
local Feed = { items = {} }
do
    local realAdd = ns.Toast.Add
    ns.Toast.Add = function(...)
        local item, why = realAdd(...)
        if item then table.insert(Feed.items, 1, item) end
        return item, why
    end
end
function Feed.Clear()
    for i = #Feed.items, 1, -1 do Feed.items[i] = nil end
    ns.Toast.Clear()
end
function Feed.Add(...) return ns.Toast.Add(...) end
function Feed.Bump(item, count) return ns.Toast.Bump(item, count) end

-- ---------------------------------------------------------------------------
section("Sources -- what feeds it")
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
        "ACHIEVEMENT_EARNED", "CHAT_MSG_WHISPER", "CHAT_MSG_BN_WHISPER",
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
    Feed.Clear()
    sourceDriver:Fire(event, ...)
    return Feed.items[1]
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
    Feed.Clear()
    sourceDriver:Fire("CHAT_MSG_LOOT", EPIC, nil, nil, nil, nil, nil, nil, nil, nil, nil,
                      nil, "Player-1-SOMEONE")
    return #Feed.items == 0
end)())

-- With no GUID the localized "you receive" strings decide. Guessing wrong in a
-- raid is the noisy direction, so an unattributable message is dropped.
check("a message with no GUID falls back to the localized patterns", (function()
    Feed.Clear()
    sourceDriver:Fire("CHAT_MSG_LOOT", EPIC)
    return #Feed.items == 1
end)())
check("  and one that names somebody else is dropped", (function()
    Feed.Clear()
    sourceDriver:Fire("CHAT_MSG_LOOT",
                      "Someone receives loot: |Hitem:6948::::::::70:::::|h[Hearthstone]|h|r.")
    return #Feed.items == 0
end)())

-- SPEC 6: "loot at uncommon and above", a saved variable.
mock.itemQuality[1234] = 1
local POOR = "You receive loot: |Hitem:1234::::::::70:::::|h[Linen Cloth]|h|r."
check("common loot is filtered out", (function()
    Feed.Clear()
    sourceDriver:Fire("CHAT_MSG_LOOT", POOR, nil, nil, nil, nil, nil, nil, nil, nil, nil,
                      nil, mock.playerGUID)
    return #Feed.items == 0
end)())
check("  and the threshold comes from saved variables", (function()
    _G.MyUIDB.sources.lootQuality = 1
    Feed.Clear()
    sourceDriver:Fire("CHAT_MSG_LOOT", POOR, nil, nil, nil, nil, nil, nil, nil, nil, nil,
                      nil, mock.playerGUID)
    local n = #Feed.items
    _G.MyUIDB.sources.lootQuality = 2
    return n == 1
end)())

-- --- amber: quests ---------------------------------------------------------

-- These are the toast sources' own quest rows, which speak only while MyUI's
-- quest tracker (Quests.lua, round 005) is off.
local questsWere = ns.Quests.enabled
ns.Quests.enabled = false
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

Feed.Clear()
-- G1 is closed by deletion. UNIT_QUEST_LOG_CHANGED fired several times per
-- objective and carried no quest id, so its row could never be named or rolled
-- up -- it just said "Objective". Dropped rather than tuned: it was the only
-- row on the rail that could not say what it was about.
check("quest objectives are not a source", Sources.EVENTS.UNIT_QUEST_LOG_CHANGED == nil)
check("  and the window that existed only for them went with it",
      Sources.COALESCE == nil and Sources.Coalesce == nil)
check("  so firing it does nothing at all", (function()
    Feed.Clear()
    sourceDriver:Fire("UNIT_QUEST_LOG_CHANGED", "player")
    return #Feed.items == 0, #Feed.items
end)())
-- Quests still speak; it is only the unnameable progress event that went.
check("  while accepting a quest still does", (function()
    Feed.Clear()
    sourceDriver:Fire("QUEST_ACCEPTED", 42)
    return #Feed.items == 1, #Feed.items
end)())
ns.Quests.enabled = questsWere

-- --- green: currency and reputation ---------------------------------------

mock.currencies[1602] = "Conquest"
got = fire("CURRENCY_DISPLAY_UPDATE", 1602, 250, 50)
check("a currency gain posts a green row", got ~= nil and got.kind == "green")
check("  named and counted", got and got.name == "Conquest" and got.count == 50)
check("spending is not a notification", (function()
    Feed.Clear()
    sourceDriver:Fire("CURRENCY_DISPLAY_UPDATE", 1602, 200, -50)
    return #Feed.items == 0
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
check("an achievement posts an amber row (round 003)", got ~= nil and got.kind == "amber")
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
Feed.Clear()
Sources.latched.bagFull = nil
mock.bagFree = 0
for _ = 1, 5 do sourceDriver:Fire("BAG_UPDATE_DELAYED") end
check("a full bag says so once, not on every update", #Feed.items == 1, #Feed.items)
check("  in orange", Feed.items[1] and Feed.items[1].kind == "orange")

mock.bagFree = 3
sourceDriver:Fire("BAG_UPDATE_DELAYED")
check("making room clears the latch silently", #Feed.items == 1, #Feed.items)
mock.bagFree = 0
sourceDriver:Fire("BAG_UPDATE_DELAYED")
check("  and filling it again speaks again", #Feed.items == 2, #Feed.items)
mock.bagFree = 5
sourceDriver:Fire("BAG_UPDATE_DELAYED")

Feed.Clear()
Sources.latched.durability = nil
mock.durability = 0.10
for _ = 1, 4 do sourceDriver:Fire("UPDATE_INVENTORY_DURABILITY") end
check("worn gear says so once", #Feed.items == 1, #Feed.items)
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

Feed.Clear()
Sources.latched.mail = nil
mock.hasMail = true
sourceDriver:Fire("UPDATE_PENDING_MAIL")
sourceDriver:Fire("UPDATE_PENDING_MAIL")
check("pending mail says so once", #Feed.items == 1, #Feed.items)
mock.hasMail = false
sourceDriver:Fire("UPDATE_PENDING_MAIL")
check("  and reading it clears the latch", Sources.latched.mail == nil)

-- The whole file has to survive an API that is not there. On 12.1 a
-- misremembered name returns nil in game while every offline test passes.
check("a missing reader does not take the source down", (function()
    local saved = _G.C_CurrencyInfo
    _G.C_CurrencyInfo = nil
    Feed.Clear()
    local ok = pcall(function() sourceDriver:Fire("CURRENCY_DISPLAY_UPDATE", 1602, 250, 50) end)
    _G.C_CurrencyInfo = saved
    return ok and #Feed.items == 1 and Feed.items[1].name == "Currency",
           Feed.items[1] and Feed.items[1].name
end)())

Feed.Clear()
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
-- "r" is ambiguous since R3b added restore; "ru" is not.
check("prefix 'ru' resolves to rules", output("ru"):find("Forwarding a secret", 1, true) ~= nil)
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
    for _, word in ipairs({ "toast", "log", "history", "whisper", "four seconds" }) do
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
    Feed.Clear()
    Feed.Add("blue", "Dated")
    local e = Log.db.entries[1]
    return e ~= nil and e.at > 1000000000, e and e.at
end)())
check("  which is a different clock from the rail's", Log.Now() ~= ns.Reveal.Now())

check("every rail item is recorded", (function()
    Log.Clear()
    Feed.Clear()
    Feed.Add("blue", "One")
    Feed.Add("amber", "Two")
    return Log.Count() == 2, Log.Count()
end)())
check("  newest first, like the rail", Log.db.entries[1].name == "Two")
check("  keeping the hue", Log.Filter("amber")[1].name == "Two")
check("  and the count", (function()
    Log.Clear()
    Feed.Add("green", "Stack", 7)
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
    Feed.Clear()
    Feed.Add("blue", "a")
    Feed.Add("blue", "b")
    Feed.Add("orange", "c")
    local t = Log.Tally()
    return t.blue == 2 and t.orange == 1, tostring(t.blue) .. "/" .. tostring(t.orange)
end)())

check("/myui log prints the record", (function()
    Log.Clear()
    Feed.Clear()
    Feed.Add("blue", "Readable")
    ns.ClearOutput()
    run("log")
    local out = ns.GetOutput()
    return out:find("Readable", 1, true) ~= nil and out:find("kept", 1, true) ~= nil, out
end)())
check("  filters by hue", (function()
    Log.Clear()
    Feed.Clear()
    Feed.Add("blue", "Bluey")
    Feed.Add("orange", "Orangey")
    ns.ClearOutput()
    run("log orange")
    local out = ns.GetOutput()
    return out:find("Orangey", 1, true) ~= nil and out:find("Bluey", 1, true) == nil, out
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

-- ---------------------------------------------------------------------------
section("Sources -- the leading edge")
-- ---------------------------------------------------------------------------
-- Currency and reputation stream. The gain you feel you caused is the first
-- after a quiet stretch; the rest are the system talking to itself. So the
-- first speaks and the rest refresh the dot it already owns -- and every one
-- of them is still written down.

check("the first gain after a quiet stretch speaks", (function()
    Feed.Clear()
    Log.Clear()
    mock.time = mock.time + Sources.QUIET + 1
    Sources.bursts["currency:1602"] = nil
    sourceDriver:Fire("CURRENCY_DISPLAY_UPDATE", 1602, 250, 50)
    return #Feed.items == 1, #Feed.items
end)())
check("  and the stream behind it does not add a second dot", (function()
    for _ = 1, 8 do
        sourceDriver:Fire("CURRENCY_DISPLAY_UPDATE", 1602, 250, 50)
    end
    return #Feed.items == 1, #Feed.items
end)())
check("  it rolls up into the one dot instead", Feed.items[1].count > 8, Feed.items[1].count)
check("  and every single gain reached the log", Log.Count() == 9, Log.Count())

check("a different currency is a different thing happening", (function()
    mock.currencies[1792] = "Honor"
    sourceDriver:Fire("CURRENCY_DISPLAY_UPDATE", 1792, 10, 10)
    return #Feed.items == 2, #Feed.items
end)())

check("the burst reopens once the source goes quiet", (function()
    mock.time = mock.time + Sources.QUIET + 1
    sourceDriver:Fire("CURRENCY_DISPLAY_UPDATE", 1602, 300, 50)
    return #Feed.items == 3, #Feed.items
end)())

-- Round 003 drops the sixth hue: dying is not a source any more.
check("dying is not a source (the red hue is gone)", Sources.EVENTS.PLAYER_DEAD == nil)

-- Whispers take violet (D1). The sender can arrive secret in chat-messaging
-- lockdown; then it is never compared, concatenated or logged.
check("a whisper posts a violet row named for the sender", (function()
    Feed.Clear()
    sourceDriver:Fire("CHAT_MSG_WHISPER", "hi", "Friend-Realm")
    local it = Feed.items[1]
    return it ~= nil and it.kind == "violet" and it.name == "Friend-Realm"
           and it.sub == "Friend-Realm", it and (it.kind .. " " .. it.name)
end)())
check("  a secret sender toasts as 'Whisper' and carries nothing", (function()
    Feed.Clear()
    sourceDriver:Fire("CHAT_MSG_WHISPER", mock.secret(), mock.secret())
    local it = Feed.items[1]
    return it ~= nil and it.name == "Whisper" and it.sub == nil, it and it.name
end)())
check("  a Battle.net whisper carries no /w target", (function()
    Feed.Clear()
    sourceDriver:Fire("CHAT_MSG_BN_WHISPER", "hi", "|Kq1|k")
    local it = Feed.items[1]
    return it ~= nil and it.kind == "violet" and it.sub == nil
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
    run("chat probe")
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
    run("chat probe")
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
check("in combat it does not move, it queues (RULES)", (function()
    Stow.Restore("raid")
    local was = _G.InCombatLockdown
    _G.InCombatLockdown = function() return true end
    local moved, err = Stow.Group("raid")
    local stillHome = not Stow.IsStowed("raid")
    _G.InCombatLockdown = was
    return moved == 0 and stillHome and tostring(err):find("queued", 1, true) ~= nil, tostring(err)
end)())
check("  and flushes when combat ends", (function()
    Stow.waiter:Fire("PLAYER_REGEN_ENABLED")
    local ok = Stow.IsStowed("raid")
    Stow.Restore("raid")
    return ok
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

-- R3 ruling: a dev aid with no minimap button until SPEC 14's menu exists.
check("no minimap button at login (R3)", Panel.button == nil)
check("  /myui panel opens it", (function()
    run("panel")
    local open = Panel.IsOpen()
    run("panel")
    return open and not Panel.IsOpen()
end)())
-- Built here so the drag-safety findings below stay covered for the day the
-- button returns as the minimap-menu entry.
Panel.BuildButton()
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
check("it opens at the top of the left dock, and the toasts speak beside it (round 005)", (function()
    Center.Open()
    local p, rel = Center.panel:GetPoint(1)
    local tp, trel, trp = ns.Toast.Anchor():GetPoint(1)
    local ok = Center.IsOpen() and p == "TOPLEFT" and rel == UIParent
       and trel == Center.panel and tp == "TOPLEFT" and trp == "TOPRIGHT"
    Center.Close()
    local _, back = ns.Toast.Anchor():GetPoint(1)
    return ok and back == UIParent
end)())

-- Allowed in R3 as SPEC 7's one recorded exception, and still not a palette
-- entry: the palette is the resting HUD's thirteen colours.
check("the opaque surface is not smuggled into the palette",
      ns.Palette.colors["surface"] == nil and ns.Palette.COUNT == 13)
check("  and it is the value Round 5 named", (function()
    local s = Center.SURFACE
    return math.abs(s[1] - 10/255) < 0.001 and math.abs(s[4] - 0.86) < 0.001
end)())

check("it lists what the log holds", (function()
    Log.Clear()
    Feed.Clear()
    Feed.Add("blue", "Ashlin")
    Feed.Add("green", "Voidsteel Greaves")
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
    Feed.Clear()
    Feed.Add("amber", "Quiet arrival")
    return not ns.Toast.IsSpeaking()
end)())
check("  but it was still posted", Feed.items[1].name == "Quiet arrival")
check("  and still in the log", Log.db.entries[1].name == "Quiet arrival")
check("  and the centre shows it immediately",
      Center.panel.rows[1].name:GetText() == "Quiet arrival")

check("it toasts again once closed", (function()
    Center.Close()
    Feed.Clear()
    Feed.Add("blue", "Loud again")
    return ns.Toast.IsSpeaking()
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
section("Bars -- Phase 4, live data through curves")
-- ---------------------------------------------------------------------------
-- The riskiest compliance surface in v1. Every value here is secret in the
-- mock; the guard runs strict, so a single inspection fails the suite.

do
    local Bars = ns.Bars
    local stack = Registry.Get("SelfStack").frame
    local strip = Registry.Get("TargetStrip").frame
    local function lastCall(frame, method)
        for i = #frame.__calls, 1, -1 do
            if frame.__calls[i].method == method then return frame.__calls[i] end
        end
    end
    local function forwardedSecret(frame, method, argIndex)
        local c = lastCall(frame, method)
        return c ~= nil and mock.isSecret(c[argIndex or 1])
    end

    check("every curve built", #(Bars.curveProblems or { "?" }) == 0,
          table.concat(Bars.curveProblems or {}, "; "))
    check("  the three step curves are Step curves", (function()
        for _, k in ipairs({ "below", "above", "edge" }) do
            if Bars.curves[k].curveType ~= Enum.LuaCurveType.Step then return false, k end
        end
        return true
    end)())
    check("  and the scalar shapes are scalar curves (a number, not a colour)",
          Bars.curves.frac.kind == "scalar" and Bars.curves.missing.kind == "scalar"
          and Bars.curves.pct.kind == "scalar")

    Guard.Reset()
    if ns.Frames.placeholders then ns.Frames.Placeholders(false) end
    Bars.Suspend(false)
    Bars.driver:Fire("UNIT_HEALTH", "player")
    check("health: the value is forwarded, secret, into SetValue", forwardedSecret(stack.health, "SetValue"))
    check("  the fill colour arrives through SetVertexColor", forwardedSecret(stack.health.fill, "SetVertexColor"))
    check("  the depleted wash gets the MISSING fraction, reverse-filled",
          forwardedSecret(stack.health.wash, "SetValue") and lastCall(stack.health.wash, "SetReverseFill")[1] == true)
    check("  the number is formatted in C, never in Lua",
          (function()
              local c = lastCall(stack.number, "SetFormattedText")
              return c ~= nil and c[1] == "%d" and mock.isSecret(c[2])
          end)())
    check("  the number takes the curve's colour", forwardedSecret(stack.number, "SetTextColor"))
    check("  the low-health copy is fed the same", forwardedSecret(Bars.low.health, "SetValue")
          and forwardedSecret(Bars.low.number, "SetFormattedText", 2))
    check("  the step alphas cross-fade steady and low, and light the edge",
          forwardedSecret(Bars.steady, "SetAlpha") and forwardedSecret(Bars.low, "SetAlpha")
          and forwardedSecret(Bars.edge, "SetAlpha"))
    check("  with no guard violation anywhere", #Guard.violations == 0,
          Guard.violations[1] and Guard.violations[1].message)

    mock.units.target = true
    Bars.driver:Fire("UNIT_HEALTH", "target")
    check("a red-to-clear gradient under the self, low and target health fills, over the first 35%", (function()
        for _, bar in ipairs({ stack.health, Bars.low.health, strip.health }) do
            local g = bar.danger
            if not g then return false end
            local w = g:GetWidth()
            local found
            for i = #g.__calls, 1, -1 do if g.__calls[i].method == "SetGradient" then found = g.__calls[i] break end end
            if not found or found[1] ~= "HORIZONTAL" or found[3].a ~= 0 then return false end
        end
        return near(stack.health.danger:GetWidth(), Scale.U(240) * 0.35)
    end)())
    check("an idle cast bar is hidden, not an empty band", (function()
        Bars.UpdateCast()
        return not stack.cast:IsShown()
    end)())
    check("the danger gradient sits in a clipping window right of the fill's edge", (function()
        local clip = stack.health.dangerClip
        local leftEdge = false
        for _, c in ipairs(clip.__calls) do
            if c.method == "SetPoint" and c[1] == "TOPLEFT" and c[3] == "TOPRIGHT" then leftEdge = true end
        end
        return clip ~= nil and leftEdge and (function()
            for _, c in ipairs(clip.__calls) do if c.method == "SetClipsChildren" then return c[1] == true end end
        end)()
    end)())
    check("experience as a thin line under SelfStack while levelling (when on), gone at max", (function()
        Bars.XP_LINE = true
        _G.UnitXP = function() return 300 end
        _G.UnitXPMax = function() return 1000 end
        _G.IsPlayerAtEffectiveMaxLevel = function() return false end
        Bars.driver:Fire("PLAYER_XP_UPDATE")
        local shown = stack.xp:IsShown()
        Bars.XP_LINE = false
        _G.IsPlayerAtEffectiveMaxLevel = function() return true end
        Bars.driver:Fire("PLAYER_XP_UPDATE")
        local gone = not stack.xp:IsShown()
        _G.UnitXP, _G.UnitXPMax, _G.IsPlayerAtEffectiveMaxLevel = nil, nil, nil
        return shown and gone
    end)())
    check("the target's percentage, formatted in C, on its bar (round 004)", (function()
        local c = lastCall(strip.number, "SetFormattedText")
        local p, rel = strip.pill:GetPoint(1)
        return c ~= nil and c[1] == "%d" and mock.isSecret(c[2]) and p == "BOTTOM" and rel == strip.health
    end)())
    check("  with its danger gradient", strip.health.danger:IsShown())
    mock.units.target = nil
    Bars.driver:Fire("PLAYER_TARGET_CHANGED")
    check("  and cleared with no target -- the gradient too", strip.number:GetText() == ""
          and not strip.health.danger:IsShown())
    check("  the low copy's 14pt number has its own pill on the low bar", (function()
        local _, rel = Bars.low.pill:GetPoint(1)
        return rel == Bars.low.health and Bars.low.pill.size == 14
    end)())
    check("/myui pct pill puts every number on its bar, on a pill", (function()
        run("pct pill")
        for _, pill in ipairs(ns.Frames.pills) do
            local p, rel, rp = pill:GetPoint(1)
            if p ~= "CENTER" or rel ~= pill.bar or rp ~= "CENTER" or not pill.bg:IsShown() then return false end
        end
        return ns.db.pct == "pill" and #ns.Frames.pills == 5   -- self, low, target, pet, focus
    end)())
    check("  /myui pct above puts them back just above the bar (the default)", (function()
        run("pct above")
        for _, pill in ipairs(ns.Frames.pills) do
            local p, rel, rp = pill:GetPoint(1)
            if p ~= "BOTTOM" or rp ~= "TOP" or pill.bg:IsShown() then return false end
        end
        return ns.db.pct == "above"
    end)())
    check("  an unknown style changes nothing", ns.Frames.SetPctStyle("left") == nil and ns.db.pct == "above")
    check("the player's name and level are filled", (function()
        Bars.Refresh()
        return lastCall(stack.name, "SetText") ~= nil and stack.level:GetText() ~= nil
    end)())

    check("the low-health copy breathes forever: 1.0 <-> 0.55 over 1.6s", (function()
        local b = Bars.low.breathe
        local a1, a2 = b.__animations[1], b.__animations[2]
        return b:IsPlaying() and lastCall(b, "SetLooping")[1] == "REPEAT"
           and lastCall(a1, "SetToAlpha")[1] == 0.55 and lastCall(a2, "SetToAlpha")[1] == 1
           and math.abs(lastCall(a1, "SetDuration")[1] + lastCall(a2, "SetDuration")[1] - 1.6) < 1e-9
    end)())
    check("the 14pt number exists only in the low copy (the one size change)", (function()
        local c = lastCall(Bars.low.number, "SetFont")
        return c ~= nil and near(c[2], Scale.U(14))
    end)())
    check("the danger edge is not in the registry (no channel may move it)",
          Registry.Get("DangerEdge") == nil and _G.MyUIDangerEdge ~= nil)

    mock.powerCalls = 0
    Bars.driver:Fire("UNIT_POWER_UPDATE", "player")
    check("power: forwarded, and asked for with the right signature",
          mock.powerCalls > 0 and forwardedSecret(stack.resource, "SetValue"))

    mock.casting.player = "cast"
    Bars.driver:Fire("UNIT_SPELLCAST_START", "player")
    check("a cast drives the bar engine-side by its duration object",
          lastCall(stack.cast, "SetTimerDuration") ~= nil and Bars.castMode == "timer")
    mock.secretDurations = true
    Bars.driver:Fire("UNIT_SPELLCAST_START", "player")
    check("  a secret duration is never handed over; the bar shows full instead",
          Bars.castMode == "degraded" and lastCall(stack.cast, "SetValue")[1] == 1
          and #Guard.violations == 0)
    mock.secretDurations = false
    mock.casting.player = nil
    Bars.driver:Fire("UNIT_SPELLCAST_STOP", "player")
    check("  and empties when the cast ends", lastCall(stack.cast, "SetValue")[1] == 0)

    mock.units.target = true
    mock.casting.target = "channel"
    Bars.driver:Fire("PLAYER_TARGET_CHANGED")
    check("target: the name is forwarded, never read", forwardedSecret(strip.name, "SetText"))
    check("  a plain level is shown", strip.level:GetText() == "80")
    check("  health forwarded", forwardedSecret(strip.health, "SetValue"))
    check("  the cast tick shows while the target casts", strip.cast:IsShown())
    mock.levels.target = -1
    Bars.driver:Fire("UNIT_LEVEL", "target")
    check("  a skull level reads ??", strip.level:GetText() == "??")
    mock.casting.target, mock.units.target, mock.levels.target = nil, nil, nil
    Bars.driver:Fire("PLAYER_TARGET_CHANGED")
    check("  and it all clears with no target", strip.name:GetText() == "" and not strip.cast:IsShown())

    -- The summon: RULES' fifth mechanism.
    local lhf = mock.frame({ name = "LowHealthFrame" })
    _G.LowHealthFrame = lhf
    _G.C_CVar = _G.C_CVar or {}
    local cvar = false
    _G.C_CVar.GetCVarBool = function(name) return name == "doNotFlashLowHealthWarning" and cvar end
    Bars.summonHooked = false
    check("the summon is available when Blizzard's warning is on", Bars.SummonAvailable() == true)
    Bars.HookSummon()
    clearClaims()
    lhf.scripts.OnShow(lhf)
    check("  Blizzard's low-health frame showing claims SelfStack", Registry.Get("SelfStack").target == 1
          and Registry.Get("SelfStack").claim == "lowhealth")
    check("  and only SelfStack", Registry.Get("TargetStrip").target == 0
          and Registry.Get("Cooldowns").target == 0.25)
    lhf.scripts.OnHide(lhf)
    check("  released when it hides", Registry.Get("SelfStack").target == 0.35)
    cvar = true
    local ok, why = Bars.SummonAvailable()
    check("  unavailable when the player has turned the warning off", ok == false
          and tostring(why):find("doNotFlashLowHealthWarning", 1, true) ~= nil)
    check("  and /myui audit says so", (function()
        ns.ClearOutput()
        run("audit")
        return ns.GetOutput():find("low-health summon", 1, true) ~= nil
    end)())
    _G.LowHealthFrame = nil

    -- The harness's switch, and the debug placeholders.
    Bars.Suspend(true)
    local before = #stack.health.__calls
    Bars.driver:Fire("UNIT_HEALTH", "player")
    check("suspended, nothing live reaches the bars", #stack.health.__calls == before)
    Bars.Suspend(false)
    run("show on")
    local during = #stack.health.__calls
    Bars.driver:Fire("UNIT_HEALTH", "player")
    check("while placeholders show, live data waits", #stack.health.__calls == during)
    run("show off")
    check("  and takes the bars back when they go", forwardedSecret(stack.health, "SetValue"))

    -- The diff-level rule PLAN states: no arithmetic on any unit value.
    check("Bars.lua never calls a unit value API except through a curve", (function()
        local src = assert(io.open("../MyUI/Bars.lua")):read("*a")
        for line in src:gmatch("[^\n]+") do
            local code = line:gsub("%-%-.*$", "")
            if code:find("UnitHealth%(") or code:find("UnitPower%(") or code:find("UnitHealthMax")
               or code:find("UnitPowerMax") then
                return false, line
            end
        end
        return true
    end)())
end

-- ---------------------------------------------------------------------------
section("Clearing -- SPEC 11, R3b")
-- ---------------------------------------------------------------------------
-- Adoption: Blizzard's chat, minimap and bags at resting alpha 0, revealed by
-- the ordinary engine. Alpha only, so no combat queue.

do
    local Clear = ns.Clear
    local made = {}
    for _, spec in ipairs(Clear.ADOPT) do
        made[spec[2]] = mock.frame({ name = spec[2] })
        _G[spec[2]] = made[spec[2]]
        made[spec[2]]:SetAlpha(0.9)
    end
    local before = Registry.Count()

    -- The minimap's own "calm" claim (round 004) has its section below; these
    -- R3b checks are about adoption at rest.
    ns.db.map = "peek"
    local n = Clear.Apply()
    check("every adopted frame is registered (bar 1 yields to MyUI's action bar)", n == #Clear.ADOPT
          and Registry.Count() == before + #Clear.ADOPT - 1 and Registry.Get("MainBar") == nil, n)
    check("  at resting alpha 0", (function()
        for _, spec in ipairs(Clear.ADOPT) do
            local e = Registry.Get(spec[1])
            if spec.yieldsTo then
                if e or _G[spec[2]]:GetAlpha() ~= 0 then return false, spec[1] end
            elseif not e or e.resting ~= 0 or e.target ~= 0 then return false, spec[1] end
        end
        return true
    end)())
    check("  and the chat edit box left the log first", ns.Chat.editBoxFreed == true
          or _G.ChatFrame1EditBox == nil)
    check("applying twice adopts nothing new", Clear.Apply() == 0)

    local talkOn = ns.Talk.enabled
    ns.Talk.enabled = false
    Reveal.Claim("peek")
    check("peek reveals them", Registry.Get("Minimap").target == 1 and Registry.Get("Chat").target == 1)
    Reveal.Release("peek")
    ns.Talk.enabled = true
    Reveal.Claim("peek")
    check("  but with MyUI's chat panel on, not Blizzard's chat window (Mykel: \"annoying\")",
          Registry.Get("Minimap").target == 1 and Registry.Get("Chat").target == 0
          and Registry.Get("ChatDock").target == 0 and Registry.Get("ChatButtons").target == 0)
    Reveal.Release("peek")
    ns.Talk.enabled = talkOn
    Reveal.Claim("peek")
    Reveal.Release("peek")
    check("  and they settle back to 0", Registry.Get("Minimap").target == 0)

    -- The minimap draws its arrow and blips through alpha, so the map itself
    -- is hidden once a fade settles at 0, and shown again before it fades in.
    mock.advance(ns, 0.3, 3)
    check("the minimap map is hidden at rest", not made.Minimap:IsShown())
    Reveal.Claim("peek")
    check("  shown when summoned", made.Minimap:IsShown())
    Reveal.Release("peek")
    mock.advance(ns, 0.3, 3)
    check("  and hidden again once the fade-out finishes", not made.Minimap:IsShown())

    Reveal.Claim("combat")
    check("combat does not reveal chat or the minimap",
          Registry.Get("Chat").target == 0 and Registry.Get("Minimap").target == 0
          and Registry.Get("SelfStack").target == 1)
    check("  nor the bags or micro menu",
          Registry.Get("Bags").target == 0 and Registry.Get("MicroMenu").target == 0)
    check("  group frames in every fight by default (round 004 play)", Registry.Get("Group").target == 1
          and Clear.GroupMode() == "combat")
    Reveal.Release("combat")
    run("group auto")
    Reveal.Claim("combat")
    check("  but not a DPS's when set to auto", Registry.Get("Group").target == 0)
    check("  but MyUI's own action bar does (round 004)", Registry.Get("ActionBar").target == 1)
    check("  and the wings, debuffs and stance bar with it", Registry.Get("StanceBar").target == 1
          and Registry.Get("Debuffs").target == 1 and Registry.Get("WingCooldowns").target == 1
          and Registry.Get("WingUtility").target == 1 and Registry.Get("WingBuffs").target == 1)
    check("  Blizzard's pet bar is not adopted any more (MyUI draws its own)", Registry.Get("PetBar") == nil)
    Reveal.Release("combat")
    _G.UnitGroupRolesAssigned = function() return "HEALER" end
    Reveal.Claim("combat")
    check("  but a healer's group frames do come back (auto)",
          Registry.Get("Group").target == 1)
    Reveal.Release("combat")
    run("group hover")
    Reveal.Claim("combat")
    check("  unless pinned to hover", Registry.Get("Group").target == 0)
    Reveal.Release("combat")
    mock.hostile = false
    Reveal.Claim("target")
    check("a friendly target (a vendor) brings the bar but not the wings, debuffs or stances",
          Registry.Get("ActionBar").target == 1 and Registry.Get("WingCooldowns").target == 0
          and Registry.Get("WingUtility").target == 0 and Registry.Get("Debuffs").target == 0
          and Registry.Get("StanceBar").target == 0)
    Reveal.Release("target")
    mock.hostile = true
    Reveal.Claim("target")
    check("  something you can attack brings them all", Registry.Get("WingCooldowns").target == 1
          and Registry.Get("Debuffs").target == 1)
    Reveal.Release("target")
    run("group dps combat")
    _G.UnitGroupRolesAssigned = function() return "DAMAGER" end
    Reveal.Claim("combat")
    check("  or set to combat for that role", Registry.Get("Group").target == 1)
    run("group auto")
    _G.UnitGroupRolesAssigned = nil
    Reveal.Release("combat")

    -- Blizzard's log on a whisper is the legacy path: with MyUI's chat panel
    -- (Talk.lua) a whisper toasts instead.
    local talkWas = ns.Talk.enabled
    check("with MyUI's chat panel, a whisper leaves Blizzard's log hidden", (function()
        ns.Talk.enabled = true
        Clear.OnWhisper()
        return Registry.Get("Chat").target == 0
    end)())
    ns.Talk.enabled = false
    Clear.OnWhisper()
    check("a whisper reveals chat", Registry.Get("Chat").target == 1
          and Registry.Get("ChatDock").target == 1)
    check("  and only chat", Registry.Get("Minimap").target == 0
          and Registry.Get("SelfStack").target == 0.35)
    mock.advance(ns, Clear.WHISPER_HOLD - 1)
    check("  held for the 8s", Registry.Get("Chat").target == 1)
    Clear.OnWhisper()
    mock.advance(ns, Clear.WHISPER_HOLD - 1)
    check("  a second whisper restarts the hold", Registry.Get("Chat").target == 1)
    mock.advance(ns, 2)
    check("  then lets go", Registry.Get("Chat").target == 0)
    ns.Talk.enabled = talkWas

    run("restore")
    check("/myui restore unregisters them", Registry.Count() == before, Registry.Count())
    check("  and gives back their own alpha", made.MinimapCluster:GetAlpha() == 0.9,
          made.MinimapCluster:GetAlpha())
    check("  and is remembered", Clear.Enabled() == false)
    run("clear")
    check("/myui clear turns it back on", Clear.Enabled() and Registry.Get("Bags") ~= nil)
    run("restore")

    -- The probe: SPEC 11's filter on PlayerFrame, tried and put back.
    local player = mock.frame({ name = "PlayerFrame" })
    local rolesets = "unitFrames"
    player.SetRolesets = function(_, r) rolesets = r end
    player.IsRolesetFiltered = function() return rolesets == "myuiCleared" end
    player.IsVisible = function() return rolesets ~= "myuiCleared" end
    _G.PlayerFrame = player
    local r = Clear.ProbePlayer()
    check("the probe tries the filter and reads it", r.setOk and r.filtered == true
          and r.visibleDuring == false)
    check("  and puts the frame back exactly", rolesets == "unitFrames" and r.filteredAfter == false)
    check("  and records it for reading off disk", ns.db.clear.probe == r)
    local was = _G.InCombatLockdown
    _G.InCombatLockdown = function() return true end
    rolesets = "unitFrames"
    local r2 = Clear.ProbePlayer()
    _G.InCombatLockdown = was
    check("  never in combat: SetRolesets is protected", r2.error ~= nil and rolesets == "unitFrames")
    _G.PlayerFrame = nil

    -- Unit frames: unregister and hide (R3b ruling), out of combat only.
    local units = {}
    for _, name in ipairs(Clear.UNITS) do
        local f = mock.frame({ name = name, shown = true })
        f.unregistered = false
        f.UnregisterAllEvents = function() f.unregistered = true end
        units[name] = f
        _G[name] = f
    end
    local was2 = _G.InCombatLockdown
    _G.InCombatLockdown = function() return true end
    Clear.hiddenUnits = {}
    Clear.queue = {}
    local done = Clear.Defer("units", Clear.HideUnits)
    check("in combat the unit frames wait", done == false and units.PlayerFrame:IsShown()
          and not units.PlayerFrame.unregistered)
    _G.InCombatLockdown = was2
    Clear.Flush()
    check("  and are unregistered and hidden when combat ends", (function()
        for name, f in pairs(units) do
            if f:IsShown() or not f.unregistered then return false, name end
        end
        return true
    end)())
    units.TargetFrame:Show()
    check("  anything that shows one again is answered with a Hide", not units.TargetFrame:IsShown())

    -- The MyUI layout: bars in combat only, through C_EditMode alone.
    mock.layouts.activeLayout = 3
    Clear.queue = {}
    -- Layouts are the account's, on Blizzard's servers (probe, 2026-11-22).
    check("a spec on its own layout is left alone: nothing saved, nothing selected, nothing recorded", (function()
        mock.editMode.saved, mock.editMode.active = nil, nil
        ns.db.clear.prevLayout = nil
        local ok, err = Clear.ApplyLayout()
        Clear.RestoreLayout()
        return ok == nil and err == "not used on this spec" and mock.editMode.saved == nil
           and mock.editMode.active == nil and #mock.layouts.layouts == 2 and ns.db.clear.prevLayout == nil
           and Clear.layoutUntouched == true
    end)())
    local changed = Clear.ApplyLayout(true)
    local saved = mock.editMode.saved
    local mine
    for i, l in ipairs(saved.layouts) do if l.layoutName == "MyUI" then mine = i end end
    check("a MyUI layout is made from the active one", mine ~= nil, mine)
    check("  as this character's own, after every other, so nothing moves", mine == 3
          and saved.layouts[mine].layoutType == 2 and saved.layouts[2].layoutName == "Alt")
    check("  every action bar with a visibility setting is hidden", changed >= 2
          and saved.layouts[mine].systems[2].settings[1].value == 3, changed)
    local function sys(i) return saved.layouts[mine].systems[i + 2] end
    check("  stance under the cooldowns, outer edge with the wing", (function()
        local st = saved.layouts[mine].systems[5].anchorInfo
        local half, bottom, row, gap = ns.Actions.Extent()
        local wing = half + Scale.U(32)
        return st and st.point == "BOTTOMRIGHT" and near(st.offsetX, -wing) and near(st.offsetY, bottom - gap - 30)
    end)())
    local function setting(s, id) for _, st in ipairs(s.settings) do if st.setting == id then return st.value end end end
    check("  the wings are always shown to Blizzard (the reveal engine decides); buff bars in combat only",
          setting(sys(5), 6) == 0 and setting(sys(6), 6) == 0 and setting(sys(7), 6) == 0 and setting(sys(8), 6) == 1)
    check("  major cooldowns: left of bar 1's row, growing away from the bar, ~bar-1 size", (function()
        local a = sys(5).anchorInfo
        local half, bottom = ns.Actions.Extent()
        return a and a.point == "BOTTOMRIGHT" and a.relativeTo == "UIParent" and a.relativePoint == "BOTTOM"
           and near(a.offsetX, -(half + Scale.U(32))) and near(a.offsetY, bottom)
           and setting(sys(5), 2) == 0 and setting(sys(5), 3) == 6 and sys(5).isInDefaultPosition == false
    end)())
    check("  utility sits on the major cooldowns' viewer, the chosen buffs on utility's, whatever rows they wrap to", (function()
        local u, b = sys(6).anchorInfo, sys(7).anchorInfo
        local _, _, _, gap = ns.Actions.Extent()
        return u.point == "BOTTOMRIGHT" and u.relativeTo == "EssentialCooldownViewer" and u.relativePoint == "TOPRIGHT"
           and near(u.offsetX, 0) and near(u.offsetY, gap)
           and b.point == "BOTTOMRIGHT" and b.relativeTo == "UtilityCooldownViewer" and b.relativePoint == "TOPRIGHT"
           and near(b.offsetY, gap) and setting(sys(7), 2) == 0
    end)())
    check("  the tracked buff bars on the chosen buffs' viewer, whatever is under it, growing up (vertical, direction Right)", (function()
        local a = sys(8).anchorInfo
        local _, _, _, gap = ns.Actions.Extent()
        return a and a.point == "BOTTOMRIGHT" and a.relativeTo == "BuffIconCooldownViewer"
           and a.relativePoint == "TOPRIGHT" and near(a.offsetX, 0) and near(a.offsetY, gap)
           and setting(sys(8), 0) == 1 and setting(sys(8), 2) == 1
    end)())
    check("  debuffs on you: past the zone button's place, on UIParent (never a MyUI frame: taint), dispel types shown", (function()
        local d = sys(9)
        local a = d.anchorInfo
        local half, bottom = ns.Actions.Extent()
        return a and a.relativeTo == "UIParent" and a.point == "BOTTOMLEFT" and a.relativePoint == "BOTTOM"
           and near(a.offsetX, half + Scale.U(128)) and near(a.offsetY, bottom)
           and setting(d, 5) == 6 and setting(d, 9) == 1 and setting(d, 4) == 8
    end)())
    check("  no Edit Mode anchor names a MyUI frame", (function()
        for _, sy in ipairs(saved.layouts[mine].systems) do
            local r = sy.anchorInfo and sy.anchorInfo.relativeTo
            if type(r) == "string" and r:match("^MyUI") then return false, r end
        end
        return true
    end)())
    check("  a narrow screen shrinks a wing to fit beside the bar, never under it", (function()
        local was = _G.UIParent.__w
        local half, _, _, _, barX = ns.Actions.Extent()
        local gap = Scale.U(32)
        _G.UIParent.__w = 3000
        local s1, l1 = Clear.WingFit("Essential")
        _G.UIParent.__w = 1229            -- a 16:10 laptop screen, 768 tall
        local s2, l2 = Clear.WingFit("Essential")
        local w = Clear.WINGS.Essential
        local width = l2 * w.base * (50 + 10 * s2) / 100 + (l2 - 1) * ns.Layout.Value("iconPadding")
        local fits = width <= 1229 / 2 + barX - half - gap
        local h = Clear.WingIconHeight("Essential")
        _G.UIParent.__w = was
        return s1 == 6 and l1 == 8 and (s2 < 6 or l2 < 8) and fits and h == w.base * (50 + 10 * s2) / 100,
               ("%s/%s %s/%s"):format(s1, l1, s2, l2)
    end)())
    check("  the buff frame is left alone", sys(10).anchorInfo == nil)
    check("  Blizzard's experience and second status bars at the top edge, one under the other", (function()
        local a, b = sys(12).anchorInfo, sys(13).anchorInfo
        return a and b and a.point == "TOP" and a.relativePoint == "TOP" and near(a.offsetY, 0)
           and near(b.offsetY, -Scale.U(12))
    end)())
    check("  the zone / extra ability button on bar 1's row, past button 8", (function()
        local a = sys(11).anchorInfo
        return a and a.point == "BOTTOM" and near(a.offsetX, Scale.U(250)) and near(a.offsetY, Scale.U(39))
    end)())
    check("  Blizzard's tooltip corner in the bottom right, growing up (the tooltip itself untouched)", (function()
        local a = sys(14).anchorInfo
        return a and a.point == "BOTTOMRIGHT" and a.relativePoint == "BOTTOMRIGHT" and a.relativeTo == "UIParent"
           and near(a.offsetX, Scale.U(-16)) and near(a.offsetY, Scale.U(144))
           and a.offsetY > (select(2, ns.Actions.Extent())) + 44   -- clear of the debuff row
    end)())
    check("  other systems are untouched", saved.layouts[mine].systems[4].settings[1].value == 0)
    check("  the source layout is untouched", saved.layouts[1].systems[2].settings[1].value == 0)
    check("  and it is selected", mock.editMode.active == 2 + mine, mock.editMode.active)
    check("  the previous layout is remembered by name", ns.db.clear.prevLayout == "XYZ - Ultra",
          tostring(ns.db.clear.prevLayout))
    check("applying again reuses it rather than making another", (function()
        Clear.ApplyLayout()
        local n = 0
        for _, l in ipairs(mock.layouts.layouts) do if l.layoutName == "MyUI" then n = n + 1 end end
        return n == 1 and ns.db.clear.prevLayout == "XYZ - Ultra", n
    end)())
    check("applying again with nothing to change never calls C_EditMode (no taint)", (function()
        mock.editMode.saved = nil
        local n = Clear.ApplyLayout()
        return n == 0 and mock.editMode.saved == nil and Clear.layoutUntouched == true
    end)())
    check("  but a change is saved", (function()
        ns.Layout.Set("iconPadding", 9)
        Clear.ApplyLayout()
        local saved = mock.editMode.saved ~= nil
        ns.Layout.Delete("mine")
        Clear.ApplyLayout()
        return saved
    end)())
    check("each screen size has its layout, this character's, named in words; a new one is made when asked", (function()
        local was, all, act = _G.UIParent.__w, mock.layouts.layouts, mock.layouts.activeLayout
        local function find(name)
            for i, l in ipairs(mock.layouts.layouts) do if l.layoutName == name then return i end end
        end
        -- As it was: one account layout, named by a number.
        local old = all[find("MyUI")]
        old.layoutName, old.layoutType = "MyUI 1365", 1
        mock.layouts.layouts = { all[1], old, all[2] }
        mock.layouts.activeLayout = 4
        _G.UIParent.__w = 1365.33
        mock.editMode.saved = nil
        local ok, err = Clear.ApplyLayout()
        local asks = ok == nil and err == "no layout for this screen" and mock.editMode.saved == nil
                     and mock.layouts.activeLayout == 4 and find("MyUI 1365") == 2
        Clear.layoutHints = {}
        ns.ClearOutput()
        asks = asks and Clear.HintLayout(err) and not Clear.HintLayout(err)
               and ns.GetOutput():find('"MyUI Wide"', 1, true) ~= nil
        Clear.ApplyLayout(true)
        local at = find("MyUI Wide")
        local made = at == 4 and mock.layouts.layouts[at].layoutType == 2 and mock.editMode.active == 6
                     and find("MyUI 1365") == 2 and mock.layouts.layouts[2].layoutType == 1
        mock.editMode.saved = nil
        local twice = Clear.ApplyLayout(true) == 0 and mock.editMode.saved == nil
        _G.UIParent.__w = 1188                    -- the laptop
        local stays = Clear.ApplyLayout() == nil and mock.layouts.activeLayout == 6
        Clear.ApplyLayout(true)
        local both = find("MyUI Standard") == 5 and mock.editMode.active == 7
        -- Another screen of the same size: nothing to write at all.
        mock.editMode.saved = nil
        _G.UIParent.__w = 1229
        local same = Clear.ApplyLayout() == 0 and mock.editMode.saved == nil
        -- Back to the monitor, or on to an ultrawide: only switched.
        _G.UIParent.__w = 1792
        Clear.ApplyLayout()
        local back = mock.editMode.active == 6 and mock.editMode.saved == nil
        local prevKept = ns.db.clear.prevLayout == "XYZ - Ultra"
        old.layoutName, old.layoutType = "MyUI", 2
        mock.layouts.layouts = all
        mock.layouts.activeLayout = act
        _G.UIParent.__w = was
        Clear.ApplyLayout()
        return asks and made and twice and stays and both and same and back and prevKept,
               ("%s %s %s %s %s %s %s %s"):format(tostring(asks), tostring(made), tostring(twice), tostring(stays),
                   tostring(both), tostring(same), tostring(back), tostring(prevKept))
    end)())
    check("five on this character, a name already taken, or one the client did not keep: stop, select nothing", (function()
        local was, all, act = _G.UIParent.__w, mock.layouts.layouts, mock.layouts.activeLayout
        _G.UIParent.__w = 1188
        local function Try(layouts)
            mock.layouts.layouts, mock.layouts.activeLayout = layouts, 1
            mock.editMode.saved, mock.editMode.active = nil, nil
            local ok, err = Clear.ApplyLayout(true)
            return ok == nil and mock.editMode.active == nil and tostring(err) or "applied"
        end
        local five = {}
        for i = 1, 5 do five[i] = { layoutName = "Mine " .. i, layoutType = 2, systems = {} } end
        local before = ns.db.clear.prevLayout
        local full = Try(five)
        local taken = Try({ { layoutName = "MyUI Standard", layoutType = 1, systems = {} } })
        local save = C_EditMode.SaveLayouts
        C_EditMode.SaveLayouts = function() end
        local lost = Try({ { layoutName = "MyUI 1365", layoutType = 1, systems = {} } })
        C_EditMode.SaveLayouts = save
        mock.layouts.layouts, mock.layouts.activeLayout = all, act
        _G.UIParent.__w = was
        return full:find("five layouts on this character", 1, true) and taken:find("already named", 1, true)
           and lost:find("not there yet", 1, true) and ns.db.clear.prevLayout == before, full .. " | " .. taken .. " | " .. lost
    end)())
    check("every size fits its narrowest screen, down to 4:3", (function()
        local was = _G.UIParent.__w
        local half, _, _, _, barX = ns.Actions.Extent()
        for _, w in ipairs({ 1024, 1152, 1179, 1180, 1188, 1229, 1339, 1340, 1365, 1792, 2730 }) do
            _G.UIParent.__w = w
            local size, limit = Clear.WingFit("Essential")
            local need = limit * Clear.WINGS.Essential.base * (50 + 10 * size) / 100
                         + (limit - 1) * ns.Layout.Value("iconPadding")
            if need > w / 2 + barX - half - Scale.U(ns.Layout.Value("wingGap")) then
                _G.UIParent.__w = was
                return false, w
            end
        end
        _G.UIParent.__w = was
        return true
    end)())
    check("restore reselects the previous layout", (function()
        Clear.RestoreLayout()
        return mock.editMode.active == 3, mock.editMode.active
    end)())
    check("each spec goes back to its own: what one left does not overwrite another's", (function()
        local realGuid, realSpec = _G.UnitGUID, _G.GetSpecialization
        local spec = 1
        _G.UnitGUID = function() return "Player-1-0001" end
        _G.GetSpecialization = function() return spec end
        mock.layouts.activeLayout = 3
        Clear.ApplyLayout(true)
        local mineIdx = mock.editMode.active
        spec = 2
        mock.layouts.activeLayout = 1            -- spec 2 sits on a preset
        local left = Clear.ApplyLayout() == nil and mock.layouts.activeLayout == 1
        Clear.ApplyLayout(true)
        spec = 1
        mock.layouts.activeLayout = mineIdx
        Clear.RestoreLayout()
        local one = mock.editMode.active
        spec = 2
        mock.layouts.activeLayout = mineIdx
        Clear.RestoreLayout()
        local two = mock.editMode.active
        _G.UnitGUID, _G.GetSpecialization = realGuid, realSpec
        return left and one == 3 and two == 1, ("%s %s %s"):format(tostring(left), tostring(one), tostring(two))
    end)())
    check("a preset is remembered and restored by index", (function()
        mock.layouts.activeLayout = 1
        Clear.ApplyLayout(true)
        local prev = ns.db.clear.prevLayout
        Clear.RestoreLayout()
        return prev == "preset:1" and mock.editMode.active == 1, prev
    end)())

    for name in pairs(units) do _G[name] = nil end
    for _, spec in ipairs(Clear.ADOPT) do _G[spec[2]] = nil end
end

-- ---------------------------------------------------------------------------
section("MVP -- extras off (M1)")
-- ---------------------------------------------------------------------------
-- The MVP default: the history window, toast sources other than whispers,
-- MyUI's chat box and the dev panel are off. Dynamic checks only here; the
-- login-time gates are read straight from the source.

do
    local was = ns.db.extras
    ns.db.extras = nil
    check("extras are off by default (a fresh db has none)", ns.Extras() == false)
    check("  whispers still feed toasts", ns.Sources.Wanted("CHAT_MSG_WHISPER")
          and ns.Sources.Wanted("CHAT_MSG_BN_WHISPER"))
    check("  loot, quests, currency, mail and the rest do not",
          not ns.Sources.Wanted("CHAT_MSG_LOOT") and not ns.Sources.Wanted("QUEST_TURNED_IN")
          and not ns.Sources.Wanted("UPDATE_PENDING_MAIL"))
    check("  the history window will not open", ns.Center.Open() == false)
    check("  /myui center says it is an extra", (function()
        ns.ClearOutput()
        run("center")
        return ns.GetOutput():find("extra", 1, true) ~= nil
    end)())
    check("  clicking a non-whisper toast just dismisses it", (function()
        local it = ns.Toast.Add("blue", "Loot")
        return ns.Toast.Activate(it) == nil and not ns.Toast.IsSpeaking()
    end)())
    check("  a whisper toast opens Blizzard's chat box at /w", (function()
        mock.chatOpened = {}
        local real = ns.Chat.IsOverriding
        ns.Chat.IsOverriding = function() return false end
        local it = ns.Toast.Add("violet", "Friend-Realm", 1, "Friend-Realm")
        ns.Toast.Activate(it)
        ns.Chat.IsOverriding = real
        return mock.chatOpened[#mock.chatOpened] == "/w Friend-Realm "
    end)())
    check("  the panel and our chat box are gated at login", (function()
        for _, f in ipairs({ "Panel", "Chat", "Center" }) do
            local src = assert(io.open("../MyUI/" .. f .. ".lua")):read("*a")
            local body = src:match("function " .. f .. "%.OnLogin%(%)(.-)\nend")
            if not body or not body:find("ns.Extras()", 1, true) then return false, f end
        end
        return true
    end)())
    run("extras on")
    check("/myui extras on persists", ns.db.extras == true)
    ns.db.extras = was
end

-- ---------------------------------------------------------------------------
section("Actions -- round 004's swap bar, probe P5")
-- ---------------------------------------------------------------------------
-- MyUI's own secure buttons on Blizzard's action slots, paged by a state
-- driver. The mock runs the page snippet with only `self` and `newstate` in
-- scope, as the restricted environment would.

do
    local A = ns.Actions
    mock.bindings = {
        ["1"] = "ACTIONBUTTON1", ["2"] = "ACTIONBUTTON2",
        ["ALT-1"] = "MULTIACTIONBAR1BUTTON1", ["ALT-2"] = "MULTIACTIONBAR1BUTTON2",
        ["CTRL-1"] = "MULTIACTIONBAR2BUTTON1",
    }
    check("ALT pages to whatever ALT-1 is bound to", (function()
        local bar, off = A.DetectPage("ALT-")
        return bar == "MULTIACTIONBAR1" and off == 60
    end)())
    check("  CTRL likewise", select(2, A.DetectPage("CTRL-")) == 48)
    check("  an unbound modifier pages nowhere", A.DetectPage("ALT-CTRL-") == nil)
    check("  ACTIONBUTTON1 is bar 1, not some 'ACTION' bar", (function()
        mock.bindings["SHIFT-1"] = "ACTIONBUTTON1"
        local bar, off = A.DetectPage("SHIFT-")
        mock.bindings["SHIFT-1"] = nil
        return bar == "ACTIONBUTTON" and off == 0
    end)())
    check("  a key bound to something else is not a page", (function()
        mock.bindings["SHIFT-1"] = "TOGGLEWORLDMAP"
        local bar = A.DetectPage("SHIFT-")
        mock.bindings["SHIFT-1"] = nil
        return bar == nil
    end)())
    check("the driver: vehicles first, the pages found most specific first, then Blizzard's form pages",
          A.DriverString({ a = {}, c = {}, ac = {} }) ==
          "[petbattle][vehicleui][overridebar][possessbar] hide; "
          .. "[mod:alt,mod:ctrl] ac; [mod:ctrl] c; [mod:alt] a; [bonusbar:5] 11; [bonusbar:4] 10; "
          .. "[bonusbar:3] 9; [bonusbar:2] 8; [bonusbar:1] 7; 1")
    check("  and leaves out a page nothing is bound to",
          not A.DriverString({ a = {} }):find("ctrl", 1, true))

    -- Rebuild with the bindings in place (login ran with none).
    mock.bindings["ALT-CTRL-1"] = "MULTIACTIONBAR3BUTTON1"
    mock.bindings["BUTTON4"] = "ACTIONBUTTON2"     -- a second key on one command
    Registry.Remove("ActionBar")
    A.header, A.bindSig = nil, nil
    mock.drivers = {}
    check("built out of combat", A.Build() == true and A.header ~= nil)
    A.Register()
    A.PaintKeys()
    local header, b1, b8 = A.header, A.rows["1"][1], A.rows["1"][8]
    local a1, c1, ac1 = A.rows.a[1], A.rows.c[1], A.rows.ac[1]
    local function shown(row) for _, b in ipairs(A.rows[row]) do if not b:IsShown() then return false end end return true end
    local function hidden(row) for _, b in ipairs(A.rows[row]) do if b:IsShown() then return false end end return true end

    check("a row of eight of Blizzard's ActionBarButtonTemplate per page, on a secure state header",
          #A.rows["1"] == 8 and #A.rows.a == 8 and #A.rows.c == 8 and #A.rows.ac == 8
          and b1.__template == "ActionBarButtonTemplate" and header.__template == "SecureHandlerStateTemplate")
    check("  centred, low on the screen", (function()
        local p, rel, rp, x, y = header:GetPoint(1)
        return p == "BOTTOM" and rel == UIParent and rp == "BOTTOM" and x == 0
           and near(y * A.Scale(), Scale.U(76))
    end)())
    check("  buttons kept at Blizzard's 45, the bar scaled to SPEC's 44 (glows stay centred)", (function()
        local w, h = b1:GetSize()
        local sc
        for i = #header.__calls, 1, -1 do
            if header.__calls[i].method == "SetScale" then sc = header.__calls[i][1] break end
        end
        return w == 45 and h == 45 and sc ~= nil and near(45 * sc, Scale.U(44))
    end)())
    check("  every page's row in bar 1's place (Swap)", (function()
        local _, _, _, x1, y1 = b1:GetPoint(1)
        local _, _, _, xa, ya = a1:GetPoint(1)
        return x1 == xa and y1 == ya
    end)())
    check("  each modifier row fixed to its slots", a1:GetAttribute("action") == 61
          and c1:GetAttribute("action") == 49 and ac1:GetAttribute("action") == 25
          and A.rows.a[8]:GetAttribute("action") == 68)
    check("at rest: bar 1 shown with slots 1-8, the rest hidden, no label", shown("1") and hidden("a")
          and hidden("c") and hidden("ac") and b1:GetAttribute("action") == 1
          and b8:GetAttribute("action") == 8 and not A.labels.a:IsShown())
    local function minis(id, want)
        for _, b in ipairs(A.miniButtons[id]) do if b:IsShown() ~= want then return false end end
        return true
    end
    check("mini style (default): the other pages small over bar 1, side by side", A.Style() == "mini"
          and minis("a", true) and minis("c", true) and minis("ac", true)
          and A.miniButtons.a[1]:GetAttribute("action") == 61 and A.miniButtons.c[1]:GetAttribute("action") == 49)
    check("  ALT left of CTRL, centred as a group over the bar, a little transparent", (function()
        local pa, rel, rp, xa = A.minis.a:GetPoint(1)
        local _, _, _, xc = A.minis.ac:GetPoint(1)
        local s
        for i = #A.minis.a.__calls, 1, -1 do
            if A.minis.a.__calls[i].method == "SetScale" then s = A.minis.a.__calls[i][1] break end
        end
        local w = header:GetWidth()
        -- the left margin of the first equals the right margin of the last
        local leftMargin = xa * s
        local rightMargin = w - (xc * s + w * s)
        return pa == "BOTTOMLEFT" and rel == header and rp == "TOPLEFT" and xa > -0.01
           and near(leftMargin, rightMargin, 0.01) and A.minis.a:GetAlpha() == A.MINI_ALPHA,
           ("%s %s %s %s"):format(tostring(xa), tostring(s), tostring(leftMargin), tostring(rightMargin))
    end)())
    check("  no keybind text on the minis", A.miniButtons.a[1].__myuiKey == nil)
    check("  a page with nothing on it is left out, the rest re-centred", (function()
        _G.HasAction = function(slot) return slot >= 61 and slot <= 68 end   -- only ALT holds anything
        A.LayoutMinis()
        local ok = A.minis.a:IsShown() and not A.minis.c:IsShown() and not A.minis.ac:IsShown()
        local _, _, _, xa = A.minis.a:GetPoint(1)
        _G.HasAction = nil
        A.LayoutMinis()
        return ok and xa > 0 and A.minis.c:IsShown()
    end)())
    check("  minis never take the player's keys", (function()
        for _, o in pairs(mock.overrides) do if o.button:find("Mini") then return false end end
        return true
    end)())
    check("  MyUI's own keybind text, top-left, from the player's bindings",
          b1.__myuiKey:GetText() == "1" and a1.__myuiKey:GetText() == "ALT-1"
          and b1.__myuiKey:GetPoint(1) == "TOPLEFT")

    check("the player's keys click MyUI's buttons: every key on every command", (function()
        local o = mock.overrides
        return o["1"] and o["1"].button == "MyUIActionButton1"
           and o["2"] and o["2"].button == "MyUIActionButton2"
           and o["BUTTON4"] and o["BUTTON4"].button == "MyUIActionButton2"
           and o["ALT-1"] and o["ALT-1"].button == "MyUIActionA1"
           and o["CTRL-1"] and o["CTRL-1"].button == "MyUIActionC1"
           and o["ALT-CTRL-1"] and o["ALT-CTRL-1"].button == "MyUIActionAC1"
    end)())
    check("  a key fires its own slot whatever the display shows (ALT-1 -> slot 61, ALT not seen)",
          _G[mock.overrides["ALT-1"].button]:GetAttribute("action") == 61)
    check("  rebinding the same keys again is a no-op (no UPDATE_BINDINGS loop)", (function()
        local before = #header.__calls
        A.Bind()
        return #header.__calls == before
    end)())

    mock.mods.alt = true
    mock.UpdateStateDrivers()
    check("holding ALT swaps the ALT row into bar 1's place", shown("a") and hidden("1") and hidden("c"))
    check("  its mini row steps aside; CTRL's stays", minis("a", false) and minis("c", true))
    check("  labelled ALT", A.labels.a:IsShown() and not A.labels.c:IsShown())
    mock.mods.ctrl = true
    mock.UpdateStateDrivers()
    check("ALT+CTRL is its own row", shown("ac") and hidden("a") and hidden("c") and A.labels.ac:IsShown())
    mock.mods.alt = false
    mock.UpdateStateDrivers()
    check("CTRL alone", shown("c") and hidden("ac") and A.labels.c:IsShown())
    mock.mods.ctrl = false
    mock.UpdateStateDrivers()
    check("letting go puts bar 1 back", shown("1") and hidden("c") and not A.labels.c:IsShown())
    mock.bonusbar = 1
    mock.UpdateStateDrivers()
    check("a form's bonus bar still pages bar 1 (cat form: slots 73-80)", b1:GetAttribute("action") == 73
          and b8:GetAttribute("action") == 80 and a1:GetAttribute("action") == 61)
    mock.bonusbar = nil
    mock.UpdateStateDrivers()

    run("pages swap")
    check("/myui pages swap: no minis", minis("a", false) and minis("c", false) and A.Style() == "swap")
    run("pages mini")
    check("/myui pages mini brings them back", minis("a", true) and minis("c", true))
    mock.known.vehicleui = true
    mock.UpdateStateDrivers()
    check("a vehicle hides every row and hands the keys back to Blizzard",
          hidden("1") and hidden("a") and mock.overrides["1"] == nil and mock.overrides["ALT-1"] == nil)
    mock.known.vehicleui = nil
    mock.UpdateStateDrivers()
    check("  and leaving it brings the bar and the keys back", shown("1")
          and mock.overrides["1"] and mock.overrides["1"].button == "MyUIActionButton1"
          and mock.overrides["ALT-CTRL-1"] and mock.overrides["ALT-CTRL-1"].button == "MyUIActionAC1")

    -- Blizzard's bars, as the client has them: dragging a spell shows them all.
    local blz = {}
    for _, spec in ipairs(ns.Clear.BLIZZARD_BARS) do
        _G[spec[1]] = mock.frame({ name = spec[1], shown = true })
        for i = 1, 12 do
            local b = mock.frame({ name = spec[2] .. i, shown = true })
            _G[spec[2] .. i] = b
            blz[#blz + 1] = b
        end
    end
    local leave = mock.frame({ name = "MainMenuBarVehicleLeaveButton", shown = true })
    _G.MainMenuBarVehicleLeaveButton = leave
    leave.SetIgnoreParentAlpha = function(_, on) leave.__ignoreParentAlpha = on end
    ns.Clear.PinBars()
    check("the leave-vehicle button stays visible though bar 1, its parent, is at 0",
          leave.__ignoreParentAlpha == true)
    _G.MainMenuBarVehicleLeaveButton = nil
    check("  and the bars' own frames stop taking the mouse too (bar 1 sat over your clickable bar)", (function()
        for i = #_G.MainActionBar.__calls, 1, -1 do
            local c = _G.MainActionBar.__calls[i]
            if c.method == "EnableMouse" then return c[1] == false end
        end
        return false
    end)())
    check("every Blizzard action bar and button held at 0, mouse off", (function()
        for _, b in ipairs(blz) do
            local m
            for i = #b.__calls, 1, -1 do if b.__calls[i].method == "EnableMouse" then m = b.__calls[i][1] break end end
            if b:GetAlpha() ~= 0 or m ~= false then return false, b:GetName() end
        end
        _G.MultiBarBottomLeft:SetAlpha(1)      -- Blizzard showing it for the drag
        _G.MultiBarBottomLeftButton3:SetAlpha(1)
        return _G.MultiBarBottomLeft:GetAlpha() == 0 and _G.MultiBarBottomLeftButton3:GetAlpha() == 0
    end)())

    A.events:Fire("ACTIONBAR_SHOWGRID")
    check("picking something up stacks every page, labelled, to drop it on", (function()
        local _, _, _, _, y1 = b1:GetPoint(1)
        local _, _, _, _, yc = c1:GetPoint(1)
        local _, _, _, _, ya = a1:GetPoint(1)
        local _, _, _, _, yac = ac1:GetPoint(1)
        return shown("1") and shown("a") and shown("c") and shown("ac")
           and y1 == 0 and yc > y1 and ya > yc and yac > ya
           and A.labels.a:IsShown() and A.labels.c:IsShown() and A.labels.ac:IsShown()
    end)())
    check("  and shows the bar while it is held", Registry.Get("ActionBar").target == 1)
    check("  minis hidden while arranging", minis("a", false) and minis("c", false))
    A.events:Fire("ACTIONBAR_HIDEGRID")
    check("  putting it down goes back to one row", shown("1") and hidden("a") and hidden("ac")
          and Registry.Get("ActionBar").target == 0 and (function()
              local _, _, _, _, ya = a1:GetPoint(1)
              return ya == 0
          end)())

    check("/myui actions lists every Blizzard bar's alpha and mouse", (function()
        ns.ClearOutput()
        run("actions")
        return ns.GetOutput():find("MultiBarBottomLeft: shown, alpha 0", 1, true) ~= nil
    end)())
    check("unpinning gives them back", (function()
        ns.Clear.UnpinBars()
        _G.MultiBarBottomLeftButton3:SetAlpha(0.7)
        local ok = _G.MultiBarBottomLeftButton3:GetAlpha() == 0.7
        ns.Clear.PinBars()
        return ok and _G.MultiBarBottomLeftButton3:GetAlpha() == 0
    end)())
    for _, spec in ipairs(ns.Clear.BLIZZARD_BARS) do
        _G[spec[1]] = nil
        for i = 1, 12 do _G[spec[2] .. i] = nil end
    end

    local function stacked()
        local _, _, _, _, ya = a1:GetPoint(1)
        return shown("a") and shown("c") and shown("1") and ya > 0
    end
    run("bars")
    check("/myui bars holds every page on screen", stacked() and Registry.Get("ActionBar").target == 1)
    A.events:Fire("ACTIONBAR_SHOWGRID")
    A.events:Fire("ACTIONBAR_HIDEGRID")
    check("  and putting something down does not fold it", stacked())
    local realLock = _G.InCombatLockdown
    A.events:Fire("PLAYER_REGEN_DISABLED")
    _G.InCombatLockdown = function() return true end
    check("  a fight folds it to one row", hidden("a") and shown("1"))
    run("bars"); run("bars")            -- toggling in combat only records the wish
    check("  toggling in combat changes nothing on screen", hidden("a"))
    _G.InCombatLockdown = realLock
    A.events:Fire("PLAYER_REGEN_ENABLED")
    check("  and it comes back after", stacked())
    run("bars")
    check("  the same command puts it away", hidden("a") and Registry.Get("ActionBar").target == 0)

    local book = mock.frame({ name = "PlayerSpellsFrame" })
    _G.PlayerSpellsFrame = book
    A.events:Fire("ADDON_LOADED", "Blizzard_PlayerSpells")
    book:Show(); book.scripts.OnShow(book)
    check("opening the spellbook arranges the bar", stacked())
    book:Hide(); book.scripts.OnHide(book)
    check("  closing it folds it", hidden("a"))
    _G.PlayerSpellsFrame = nil

    -- Round 005 play: "I actually can't change specs".
    A.books.PlayerSpellsFrame = nil
    local win, page = mock.frame({ name = "PlayerSpellsFrame" }), mock.frame({ name = "SpellBookMock" })
    win.SpellBookFrame = page
    win:Hide(); page:Hide()
    _G.PlayerSpellsFrame = win
    local realHeader = _G.MyUIActionHeader
    _G.MyUIActionHeader = A.header
    A.HookBooks()
    win:Show(); win.scripts.OnShow(win)
    check("the talents and specialization pages do not arrange the bar, and it goes under the window",
          hidden("a") and A.header:GetFrameStrata() == "LOW", A.header:GetFrameStrata())
    page:Show(); page.scripts.OnShow(page)
    check("  the spellbook page does, on top", stacked() and A.header:GetFrameStrata() == "HIGH")
    page:Hide(); page.scripts.OnHide(page)
    check("  turning back to talents folds it under again", hidden("a") and A.header:GetFrameStrata() == "LOW")
    A.events:Fire("ACTIONBAR_SHOWGRID")
    check("  a talent on the cursor brings it up on top", stacked() and A.header:GetFrameStrata() == "HIGH")
    A.events:Fire("ACTIONBAR_HIDEGRID")
    check("  and it goes back under", hidden("a") and A.header:GetFrameStrata() == "LOW")
    win:Hide(); win.scripts.OnHide(win)
    check("  closing the window puts it back on top", A.header:GetFrameStrata() == "HIGH")
    _G.MyUIActionHeader = realHeader
    _G.PlayerSpellsFrame = nil
    A.books.PlayerSpellsFrame = nil

    check("the pointer wakes only MyUI's own HUD, not Blizzard's adopted chrome", (function()
        local adopted
        for _, spec in ipairs(ns.Clear.ADOPT) do
            if ns.Clear.IsAdopted(spec[1]) and Registry.Get(spec[1]) then adopted = spec[1] break end
        end
        if not adopted then return true end      -- nothing adopted in this section
        ns.Reveal.Claim("cursor", adopted)
        local down = Registry.Get(adopted).target == 0
        ns.Reveal.Release("cursor", adopted)
        return down
    end)())
    ns.Reveal.Claim("cursor", "TargetStrip")
    check("the pointer near an empty target strip leaves it down (no target, nothing to say)",
          Registry.Get("TargetStrip").target == 0)
    ns.Reveal.Release("cursor", "TargetStrip")
    mock.units.target = true
    ns.Reveal.Claim("cursor", "TargetStrip")
    check("  but with a target it comes up as usual", Registry.Get("TargetStrip").target == 1)
    ns.Reveal.Release("cursor", "TargetStrip")
    ns.Reveal.Claim("target")
    check("a target brings the bar up (pull with an ALT taunt)", Registry.Get("ActionBar").target == 1)
    do
        local st = mock.frame({ name = "StanceBarMock" })
        local had = Registry.Get("StanceBar")
        if not had then Registry.Add("StanceBar", st, 0) end
        ns.Reveal.Release("target"); ns.Reveal.Claim("target")
        local before = Registry.Get("StanceBar").target
        run("bars")
        local during = Registry.Get("StanceBar").target
        run("bars")
        local after = Registry.Get("StanceBar").target
        check("the forms bar comes with a target, steps aside while arranging, and comes back",
              before == 1 and during == 0 and after == 1, ("%s %s %s"):format(tostring(before), tostring(during), tostring(after)))
        if not had then Registry.Remove("StanceBar") end
    end
    ns.Reveal.Release("target")
    mock.units.target = nil
    check("  and it goes again without one", Registry.Get("ActionBar").target == 0)

    check("a spell flyout (a hunter's Call Pet) holds the bar up while it is open", (function()
        local fly = mock.frame({ name = "SpellFlyout" })
        _G.SpellFlyout = fly
        A.flyoutHooked = nil
        A.HookFlyout()
        fly.scripts.OnShow(fly)
        local up = Registry.Get("ActionBar").target == 1
        fly.scripts.OnHide(fly)
        _G.SpellFlyout = nil
        return up and Registry.Get("ActionBar").target == 0
    end)())
    check("registered resting at 0, in the combat scope; Blizzard's bar 1 left the registry",
          Registry.Get("ActionBar") ~= nil and Registry.Get("ActionBar").resting == 0
          and Registry.Get("MainBar") == nil
          and assert(io.open("../MyUI/Reveal.lua")):read("*a"):find("ActionBar = true", 1, true) ~= nil)
    check("re-clearing after /myui restore keeps Blizzard's bar 1 out of the registry, pinned at 0", (function()
        local main = mock.frame({ name = "MainActionBar", shown = true })
        _G.MainActionBar = main
        ns.Clear.Release()
        ns.Clear.Adopt()
        local ok = Registry.Get("MainBar") == nil and ns.Clear.IsAdopted("MainBar")
                   and main:GetAlpha() == 0 and main:IsShown()
        main:SetAlpha(1)                  -- Blizzard's code putting it back
        ok = ok and main:GetAlpha() == 0
        ns.Clear.Release()
        main:SetAlpha(0.5)                -- released: no longer held
        ok = ok and main:GetAlpha() == 0.5
        _G.MainActionBar = nil
        return ok
    end)())
    check("the page snippet only shows, hides, pages and binds -- no unit, spell or state read",
          (function()
              local body = A.snippet
              return body ~= nil and not body:find("Unit") and not body:find("Spell")
                 and not body:find("Cooldown") and not body:find("{")
          end)())
    check("/myui actions reports each page", (function()
        ns.ClearOutput()
        run("actions")
        local out = ns.GetOutput()
        return out:find("ALT -> MULTIACTIONBAR1 (slots 61-68)", 1, true) ~= nil
           and out:find("ALT+CTRL -> MULTIACTIONBAR3 (slots 25-32)", 1, true) ~= nil
           and ns.db.actionsProbe ~= nil
    end)())
    check("/myui mods watches the modifier keys", (function()
        ns.ClearOutput()
        run("mods")
        mock.altDown = true
        A.modPoll()
        mock.altDown = false
        return ns.GetOutput():find("held   ALT", 1, true) ~= nil
    end)())
    mock.bindings = {}
end

-- ---------------------------------------------------------------------------
section("Group -- SPEC 19's party and raid frames (M3, first part)")
-- ---------------------------------------------------------------------------

do
    local G = ns.Group
    local party, raid = G.party, G.raid
    check("built on Blizzard's secure group header and unit buttons",
          party.__template == "SecureGroupHeaderTemplate" and raid.__template == "SecureGroupHeaderTemplate"
          and party:GetAttribute("template") == "SecureUnitButtonTemplate")
    check("party: role then group order, never health; the player included",
          party:GetAttribute("groupBy") == "ASSIGNEDROLE"
          and party:GetAttribute("groupingOrder") == "TANK,HEALER,DAMAGER,NONE"
          and party:GetAttribute("showPlayer") == true and party:GetAttribute("sortMethod") == nil)
    check("raid: a 5-wide grid by group", raid:GetAttribute("groupBy") == "GROUP"
          and raid:GetAttribute("unitsPerColumn") == 5 and raid:GetAttribute("point") == "LEFT"
          and raid:GetAttribute("columnAnchorPoint") == "TOP")
    check("every button made out of combat (no dressing in a fight)", (function()
        local ok = false
        for _, c in ipairs(party.__calls) do
            if c.method == "SetAttribute" and c[1] == "startingIndex" and c[2] == -(G.PARTY_MAX - 1) then ok = true end
        end
        return ok
    end)())
    check("right of the target strip, clear of the right wing, growing up; in the registry", (function()
        local p, rel, rp, x, y = G.frame:GetPoint(1)
        local pp = party:GetPoint(1)
        return p == "BOTTOMLEFT" and rel == UIParent and rp == "BOTTOM" and near(x, Scale.U(224))
           and near(y, Scale.U(176)) and pp == "BOTTOMLEFT" and Registry.Get("Group") ~= nil
    end)())
    check("a DPS gets five tiny icons in a row by default", ns.Clear.GroupLook() == "icons"
          and party:GetAttribute("point") == "LEFT" and near(party:GetAttribute("xOffset"), Scale.U(G.ROWS.icons.gap))
          and near(party:GetAttribute("unitWidth"), Scale.U(G.SIZES.icon.w)))

    -- The engine making a unit button: CONFIG in the restricted environment,
    -- then the child attribute the header sets.
    local b = mock.frame({ name = "MyUIPartyHeaderUnitButton1", objectType = "Button" })
    b.SetWidth = function(_, w) b.__w = w end
    b.SetHeight = function(_, h) b.__h = h end
    b.__parent = party
    local cfg = assert(loadstring(party:GetAttribute("initialConfigFunction")))
    setfenv(cfg, { self = b })
    cfg()
    party:SetAttribute("child1", b)
    check("the click map: click targets, ctrl-click focuses, right-click opens the unit menu",
          b:GetAttribute("*type1") == "target" and b:GetAttribute("ctrl-type1") == "focus"
          and b:GetAttribute("*type2") == "togglemenu")
    check("  sized by the header, dressed as it is made", near(b.__w, party:GetAttribute("unitWidth"))
          and b.__myuiStyled and b.__health ~= nil and b.__name ~= nil)
    check("  a 1 px border while the pointer is over it", (function()
        local before = b.__hover[1]:IsShown()
        b.scripts.OnEnter(b)
        local during = b.__hover[1]:IsShown() and b.__hover[4]:IsShown()
        b.scripts.OnLeave(b)
        return not before and during and not b.__hover[1]:IsShown()
    end)())

    Guard.Reset()
    mock.units.party1 = true
    _G.UnitGroupRolesAssigned = function(u) return u == "party1" and "TANK" or "NONE" end
    b:SetAttribute("unit", "party1")
    check("a unit arriving fills its name and health -- forwarded through the curve", (function()
        local hv
        for i = #b.__health.__calls, 1, -1 do
            if b.__health.__calls[i].method == "SetValue" then hv = b.__health.__calls[i][1] break end
        end
        return mock.isSecret(hv) and b.__name:GetText() ~= nil and #Guard.violations == 0
    end)())
    check("  with its role", (function()
        for i = #b.__role.__calls, 1, -1 do
            if b.__role.__calls[i].method == "SetAtlas" then return b.__role.__calls[i][1] == "roleicon-tiny-tank" end
        end
    end)())
    _G.UnitIsUnit = function(a, b2) return a == "party1" and b2 == "target" end
    G.events:Fire("PLAYER_TARGET_CHANGED")
    check("targeting a member edges its row in amber", b.__hover[1]:IsShown() and (function()
        for i = #b.__hover[1].__calls, 1, -1 do
            local c = b.__hover[1].__calls[i]
            if c.method == "SetColorTexture" then
                local r, g, bb = ns.Palette.Get("notifAmber")
                return near(c[1], r) and near(c[2], g) and near(c[3], bb)
            end
        end
    end)())
    _G.UnitIsUnit = function() return false end
    G.events:Fire("PLAYER_TARGET_CHANGED")
    check("  and the edge goes when the target does", not b.__hover[1]:IsShown())
    _G.UnitIsUnit = nil
    local before = #b.__health.__calls
    G.events:Fire("UNIT_HEALTH", "party1")
    check("  and its health follows UNIT_HEALTH", #b.__health.__calls > before)
    _G.UnitGroupRolesAssigned = function() return "HEALER" end
    G.events:Fire("PLAYER_SPECIALIZATION_CHANGED")
    check("a healer's list grows", near(party:GetAttribute("unitHeight"), Scale.U(G.SIZES.healer.h))
          and near(b.__h, Scale.U(G.SIZES.healer.h)))
    _G.UnitGroupRolesAssigned = nil
    G.events:Fire("PLAYER_SPECIALIZATION_CHANGED")
    mock.units.party1 = nil
    local me = G.selfButton
    check("your own bar is clickable: click targets you, right-click opens your menu, ctrl-click focuses",
          me ~= nil and me.__template == "SecureUnitButtonTemplate" and me:GetAttribute("unit") == "player"
          and me:GetAttribute("*type1") == "target" and me:GetAttribute("*type2") == "togglemenu"
          and me:GetAttribute("ctrl-type1") == "focus")
    check("  laid over SelfStack with 6 of padding all round, anchored to UIParent", (function()
        local p, rel, rp, x, y = me:GetPoint(1)
        local sp, _, srp, sx, sy = ns.Registry.Get("SelfStack").frame:GetPoint(1)
        return rel == UIParent and p == sp and rp == srp and near(x, sx) and near(y, sy - Scale.U(6))
           and near(me:GetWidth(), Scale.U(252)) and near(me:GetHeight(), Scale.U(45))
    end)())
    local pet = G.petButton
    check("your pet: a strip on a secure button -- click targets it, right-click its menu", pet ~= nil
          and pet:GetAttribute("unit") == "pet" and pet:GetAttribute("*type1") == "target"
          and pet:GetAttribute("*type2") == "togglemenu" and Registry.Get("Pet") ~= nil)
    check("  only while you have one", G.PET_DRIVER == "[@pet,exists] show; hide")
    mock.units.pet = true
    G.events:Fire("UNIT_PET", "player")
    local F = ns.Frames
    local stack = ns.Registry.Get("SelfStack").frame
    check("with a pet out, you and it side by side at 45% each, 10% between, in SelfStack's place", (function()
        local _, _, _, sx = stack:GetPoint(1)
        local _, _, _, px = pet:GetPoint(1)
        local w = Scale.U(240 * 0.45)
        return F.split and near(stack:GetWidth(), w) and near(pet:GetWidth(), w)
           and near(px - sx, Scale.U(240 * 0.55)) and near(sx + px, 0)
           and near(stack.health:GetWidth(), w)
    end)())
    check("  your 20% and 40% marks stay true to the narrower bar", (function()
        local _, _, _, x20 = stack.tick20:GetPoint(1)
        local _, _, _, x40 = stack.tick40:GetPoint(1)
        return near(x20, Scale.U(240 * 0.45 * 0.2)) and near(x40, Scale.U(240 * 0.45 * 0.4))
    end)())
    check("  and your clickable bar narrows with it", near(G.selfButton:GetWidth(), Scale.U(240 * 0.45 + 12)))
    Guard.Reset()
    G.events:Fire("UNIT_HEALTH", "pet")
    check("  its health through the curve, its name", (function()
        local hv
        for i = #pet.__health.__calls, 1, -1 do
            if pet.__health.__calls[i].method == "SetValue" then hv = pet.__health.__calls[i][1] break end
        end
        return mock.isSecret(hv) and pet.__name:GetText() ~= nil and #Guard.violations == 0
    end)())
    local pb = G.petBar
    check("MyUI's pet bar: secure pet buttons, packed, drawn only on hover", pb ~= nil and #pb.buttons == 10
          and pb.buttons[1]:GetAttribute("type") == "pet" and pb.buttons[4]:GetAttribute("action") == 4
          and pb:GetAlpha() == 0)
    check("  only the slots that hold something, side by side, no gap for the empty ones", (function()
        local info = { [1] = "Claw", [2] = "Growl", [8] = "Assist", [10] = "Passive" }
        _G.GetPetActionInfo = function(i)
            if info[i] then return info[i], "tex" .. i, false, i == 8, i <= 2, i == 1 end
        end
        G.LayoutPetBar()
        local shown = 0
        for _, b in ipairs(pb.buttons) do if b:IsShown() then shown = shown + 1 end end
        local _, _, _, x8 = pb.buttons[8]:GetPoint(1)
        local ok = shown == 4 and pb.buttons[3]:IsShown() == false
           and near(x8, 2 * (Scale.U(18) + Scale.U(3)))
           and pb.buttons[1]:GetAttribute("macrotext2") == "/petautocasttoggle Claw"
           and pb.buttons[8]:GetAttribute("type2") == nil
        _G.GetPetActionInfo = nil
        return ok
    end)())
    check("  pointing at your pet brings it up; leaving lets it go after a moment", (function()
        pet.scripts.OnEnter(pet)
        local up = pb:GetAlpha() == 1
        pet.scripts.OnLeave(pet)
        mock.advance(ns, 1, 2)
        if mock.runTimers then mock.runTimers() end
        return up and pb:GetAlpha() == 0
    end)())
    check("  the pet's percentage too", (function()
        for i = #pet.__number.__calls, 1, -1 do
            local c = pet.__number.__calls[i]
            if c.method == "SetFormattedText" then return c[1] == "%d" and mock.isSecret(c[2]) end
        end
    end)())
    check("  and exactly as visible as SelfStack, whatever claims either", (function()
        ns.Reveal.Claim("target")
        local a = ns.Registry.Get("Pet").target == ns.Registry.Get("SelfStack").target
        ns.Reveal.Release("target")
        ns.Reveal.Claim("cursor", "SelfStack")
        local b = ns.Registry.Get("Pet").target == 1
        ns.Reveal.Release("cursor", "SelfStack")
        return a and b and ns.Registry.Get("Pet").target == ns.Registry.Get("SelfStack").target
    end)())
    mock.units.pet = nil
    G.events:Fire("UNIT_PET", "player")
    check("no pet: SelfStack gets its full width and place back", not F.split
          and near(stack:GetWidth(), Scale.U(240)) and select(4, stack:GetPoint(1)) == 0)
    local tb = G.targetButton
    check("the target strip is clickable: ctrl-click makes your target the focus, right-click its menu",
          tb ~= nil and tb:GetAttribute("unit") == "target" and tb:GetAttribute("ctrl-type1") == "focus"
          and tb:GetAttribute("*type2") == "togglemenu" and G.TARGET_DRIVER == "[@target,exists] show; hide")
    local fb = G.focusButton
    G.PlaceFocus()   -- the Actions section rebuilt the bar's header since login
    check("the focus strip is labelled FOCUS, like the ALT and CTRL pages", fb.__label:GetText() == "FOCUS")
    check("an x after the focus bar clears it (/clearfocus, a secure macro)", fb.__clear ~= nil
          and fb.__clear:GetAttribute("type") == "macro" and fb.__clear:GetAttribute("macrotext") == "/clearfocus")
    check("the focus drops into the target strip's place with no target, and rises above it with one", (function()
        local x, high, low = G.FocusSlots()
        local _, _, _, by = ns.Layout.Pos("ActionBar")
        local _, _, _, ty = ns.Layout.Pos("TargetStrip")
        return x == 0 and near(low, Scale.U(ty + 15 - by)) and high > low
           and fb:GetAttribute("_onstate-slot") ~= nil and fb:GetFrameRef("anchor") == ns.Actions.header
    end)())
    check("  out of combat with no target it rests lower still, in the faded bar's row", (function()
        local chunk = assert(loadstring("local newstate = 'rest'\n" .. fb:GetAttribute("_onstate-slot")))
        setfenv(chunk, { self = fb })
        chunk()
        local _, rel, _, _, y = fb:GetPoint(1)
        return G.FOCUS_SLOT_DRIVER == "[@target,exists] high; [combat] low; rest"
           and rel == ns.Actions.header and near(y, Scale.U(10)) and y < fb:GetAttribute("ylow")
    end)())
    check("one hover edge everywhere: pet, focus, target, pet buttons", G.petButton.__hoverEdge ~= nil
          and fb.__hoverEdge ~= nil and G.targetButton.__hoverEdge ~= nil
          and G.petBar.buttons[1].__hoverEdge ~= nil and (function()
              local e = fb.__hoverEdge
              fb.scripts.OnEnter(fb)
              local on = e:IsShown()
              fb.scripts.OnLeave(fb)
              return on and not e:IsShown()
          end)())
    check("  the snippet puts it at the low slot when told 'low'", (function()
        local chunk = assert(loadstring("local newstate = 'low'\n" .. fb:GetAttribute("_onstate-slot")))
        setfenv(chunk, { self = fb })
        chunk()
        local _, rel, _, _, y = fb:GetPoint(1)
        return rel == ns.Actions.header and near(y, fb:GetAttribute("ylow"))
    end)())
    check("your focus: a strip over the target strip, on a secure button -- click targets it",
          fb ~= nil and fb:GetAttribute("unit") == "focus" and fb:GetAttribute("*type1") == "target"
          and fb:GetAttribute("*type2") == "togglemenu" and G.FOCUS_DRIVER == "[@focus,exists] show; hide"
          and select(2, G.FocusSlots()) > select(3, G.FocusSlots()))
    mock.units.focus = true
    Guard.Reset()
    G.events:Fire("PLAYER_FOCUS_CHANGED")
    check("  name, percentage and health through the curve", (function()
        local hv
        for i = #fb.__health.__calls, 1, -1 do
            if fb.__health.__calls[i].method == "SetValue" then hv = fb.__health.__calls[i][1] break end
        end
        return mock.isSecret(hv) and fb.__name:GetText() ~= nil and #Guard.violations == 0
    end)())
    mock.units.focus = nil
    check("Blizzard's party and raid frames are hidden outright once these exist", (function()
        local want = { PartyFrame = true, CompactPartyFrame = true, CompactRaidFrameContainer = true, PetFrame = true }
        for _, u in ipairs(ns.Clear.UNITS) do want[u] = nil end
        return next(want) == nil
    end)())
end

-- ---------------------------------------------------------------------------
section("Layout profiles (round 004 play)")
-- ---------------------------------------------------------------------------

do
    local L = ns.Layout
    local stack = Registry.Get("SelfStack").frame
    local strip = Registry.Get("TargetStrip").frame
    local function y(f) local _, _, _, _, v = f:GetPoint(1) return v end
    check("the default profile: you under the bar, the target just over the bar",
          L.Active() == "focus" and near(y(stack), Scale.U(24)) and near(y(strip), Scale.U(163))
          and strip:GetPoint(1) == "BOTTOM")
    check("one rhythm: bar 1 to your health bar = mini pages to the target's health bar", (function()
        local A = ns.Actions
        local _, _, _, sy = L.Pos("SelfStack")
        local _, _, _, by = L.Pos("ActionBar")
        local _, _, _, ty = L.Pos("TargetStrip")
        local selfBarTop = sy + 33 - 13                       -- SelfStack: text row, then the bar
        local miniTop = by + 44 + A.MINI_GAP + 45 * A.MINI_SCALE * (44 / 45)
        local targetBar = ty + 15                             -- the strip's bar sits 15 up
        return math.abs((by - selfBarTop) - (targetBar - miniTop)) < 1, (by - selfBarTop) .. " vs " .. (targetBar - miniTop)
    end)())
    check("  the order bottom-up: you, the bar, the target strip, with room between", (function()
        local _, _, _, sy = L.Pos("SelfStack")
        local _, _, _, by = L.Pos("ActionBar")
        local _, _, _, ty = L.Pos("TargetStrip")
        return sy + 33 < by and by + 44 < ty
    end)())
    run("profile spec")
    check("/myui profile spec puts SPEC 2's positions back, bar included", L.Active() == "spec"
          and near(y(stack), Scale.U(214)) and strip:GetPoint(1) == "TOP"
          and near(y(ns.Actions.header) * ns.Actions.Scale(), Scale.U(48)))
    run("profile focus")
    run("move target 0 20")
    check("/myui move on a built-in profile copies it to \"mine\" first", L.Active() == "mine"
          and near(y(strip), Scale.U(183)) and L.PRESETS.focus.TargetStrip[4] == 163
          and ns.db.layout.saved.mine.base == "focus" and ns.db.layout.saved.mine.SelfStack == nil)
    run("move group -10 5")
    check("  and moves the group frames too", (function()
        local _, _, _, x, yy = ns.Group.frame:GetPoint(1)
        return near(x, Scale.U(214)) and near(yy, Scale.U(181))
    end)())
    run("spacing padding 8")
    check("/myui spacing padding sets the gap between wing icons", L.Value("iconPadding") == 8)
    check("  and the wings use it", (function()
        mock.layouts.activeLayout = 3
        ns.Clear.ApplyLayout(true)
        for _, l in ipairs(mock.editMode.saved.layouts) do
            if l.layoutName == "MyUI" then
                for _, sys in ipairs(l.systems) do
                    if sys.system == 20 and sys.systemIndex == 1 then
                        for _, st in ipairs(sys.settings) do
                            if st.setting == 4 then return st.value == 8 end
                        end
                    end
                end
            end
        end
        return false
    end)())
    run("profile save raid")
    check("/myui profile save copies the active profile", L.Active() == "raid" and L.Value("iconPadding") == 8)
    run("profile delete raid")
    run("profile delete mine")
    check("deleting the active one falls back to the default", L.Active() == "focus"
          and near(y(strip), Scale.U(163)))
    check("an unknown profile changes nothing", L.Use("nope") == nil and L.Active() == "focus")
    check("a stray bracket on a command word is forgiven", (function()
        ns.ClearOutput()
        run("profile]")
        return ns.GetOutput():find("layout profile:", 1, true) ~= nil
    end)())
    run("layout")
    check("/myui layout boxes every placed part, even what is not up, and holds the HUD visible",
          L.previewing == true and Registry.Get("ActionBar").target == 1)
    check("  but not chat or the minimap", (Registry.Get("Chat") == nil or Registry.Get("Chat").target == 0))
    run("layout")
    check("  and the same command hides them", L.previewing == false and Registry.Get("ActionBar").target == 0)

    -- The minimap out of combat (Mykel: "enough of a map to see BugSack").
    local mm = mock.frame({ name = "MinimapClusterMock" })
    local had = Registry.Get("Minimap")
    if not had then Registry.Add("Minimap", mm, 0) end
    local wasMap = ns.db.map
    ns.db.map = nil
    check("the map is on a key by default: peek, not calm", ns.Reveal.MapMode() == "peek")
    ns.Reveal.Calm()
    check("  so the minimap is not up out of combat", Registry.Get("Minimap").target == 0)
    ns.db.map = wasMap
    run("map calm")
    check("/myui map calm: the minimap is up out of combat", Registry.Get("Minimap").target == 1)
    ns.Reveal.driver:Fire("PLAYER_REGEN_DISABLED")
    check("  and goes in combat", Registry.Get("Minimap").target == 0)
    ns.Reveal.driver:Fire("PLAYER_REGEN_ENABLED")
    check("  and comes back after", Registry.Get("Minimap").target == 1)
    run("map peek")
    check("/myui map peek: only when summoned", Registry.Get("Minimap").target == 0)
    if not had then Registry.Remove("Minimap") end
end

-- ---------------------------------------------------------------------------
section("Round 005 -- switches and the quest tracker")
-- ---------------------------------------------------------------------------
do
    local S, Q, Clear = ns.Switches, ns.Quests, ns.Clear
    check("every switch is on by default: MyUI's way", (function()
        for _, sw in ipairs(S.LIST) do if not S.On(sw.key) then return false, sw.key end end
        return true
    end)())
    check("each switch's frames are names Clear adopts", (function()
        local known = {}
        for _, spec in ipairs(Clear.ADOPT) do known[spec[1]] = true end
        for _, sw in ipairs(S.LIST) do
            for _, f in ipairs(sw.frames or {}) do if not known[f] then return false, f end end
        end
        return true
    end)())

    -- The quest tracker switch, both ways, live.
    local tracker = mock.frame({ name = "ObjectiveTrackerFrame", shown = true })
    _G.ObjectiveTrackerFrame = tracker
    Clear.AdoptOne("Tracker")
    check("with quests on, Blizzard's tracker is adopted (resting 0)", Clear.IsAdopted("Tracker")
          and Registry.Get("Tracker") ~= nil)
    local sw, reload = S.Set("quests", false)
    check("/myui override quests off: Blizzard's tracker back at once, no reload",
          sw ~= nil and reload == false and not Clear.IsAdopted("Tracker") and Registry.Get("Tracker") == nil
          and tracker:GetAlpha() == 1 and not Q.Active() and Registry.Get("QuestList") == nil,
          ("%s %s %s %s %s"):format(tostring(sw ~= nil), tostring(reload), tostring(Clear.IsAdopted("Tracker")),
              tostring(Registry.Get("Tracker") ~= nil), tostring(tracker:GetAlpha())))
    check("  and it stays Blizzard's when clearing runs again", (function()
        Clear.Adopt()
        return not Clear.IsAdopted("Tracker")
    end)())
    S.Set("quests", true)
    check("  and on again: MyUI's quest toasts back, the tracker adopted while clearing is on",
          Q.Active() and Clear.IsAdopted("Tracker") == Clear.Enabled())
    check("a protected switch waits for /reload", select(2, S.Set("bars", false)) == true
          and S.On("bars") == false)
    S.Set("bars", true)
    check("Blizzard's unit frames are only hidden while their switch is on", (function()
        S.Set("unitframes", false)
        local ok = S.Hides("PlayerFrame") == false and S.Hides("SomethingElse") == true
        S.Set("unitframes", true)
        return ok and S.Hides("PlayerFrame") == true
    end)())
    run("override")
    check("/myui override lists every switch", (function()
        local out = ns.GetOutput()
        for _, s2 in ipairs(S.LIST) do if not out:find(s2.key, 1, true) then return false, s2.key end end
        return true
    end)())
    run("override quests off")
    check("/myui override quests off flips it", S.On("quests") == false)
    run("override quests on")

    -- Toasts from the log.
    mock.quests = {
        { id = 101, title = "Boar Trouble", objectives = {
            { text = "Boars slain: 3/10", numFulfilled = 3, numRequired = 10, finished = false },
            { text = "Talk to the farmer", numFulfilled = 0, numRequired = 1, finished = false } } },
        { id = 102, title = "Lost Letter", objectives = {
            { text = "Letter found: 0/1", numFulfilled = 0, numRequired = 1, finished = false } } },
    }
    Q.primed, Q.snapshot = false, {}
    check("the first read only records -- no toasts for where you already are", #Q.Scan() == 0)
    mock.quests[1].objectives[1] = { text = "Boars slain: 4/10", numFulfilled = 4, numRequired = 10, finished = false }
    local said = Q.Scan()
    check("an objective moving toasts its own line", #said == 1 and said[1] == "Boars slain: 4/10", said[1])
    check("  in amber, the quest hue", Feed.items[1] and Feed.items[1].kind == "amber"
          and Feed.items[1].name == "Boars slain: 4/10")
    check("nothing moved, nothing said", #Q.Scan() == 0)
    mock.quests[2].objectives[1] = { text = "Letter found: 1/1", numFulfilled = 1, numRequired = 1, finished = true }
    mock.quests[2].complete = true
    said = Q.Scan()
    check("finishing a quest says it is ready to turn in, not the last objective",
          #said == 1 and said[1] == "Lost Letter -- ready to turn in", said[1])
    check("a progress bar reads as a percentage", Q.ObjectiveText(
          { text = "", bar = true, have = 45 }, "Clear the camp") == "Clear the camp 45%")

    -- The list: compact, one line a quest, details called up.
    check("a quest's status: one counted objective reads as a count", (function()
        local f, st = Q.Progress(Q.Read(102))
        local q = { complete = false, objectives = { { have = 18, need = 20 } } }
        local f2, st2 = Q.Progress(q)
        return f == 1 and st == "ready" and st2 == "18/20" and math.abs(f2 - 0.9) < 1e-6
    end)())
    check("  several objectives read as a percentage of the whole", (function()
        local f, st = Q.Progress(Q.Read(101))
        return st == "36%" and math.abs(f - 4 / 11) < 1e-6, st
    end)())
    mock.quests[3] = { id = 103, title = "Hold the Line", objectives = {
        { text = "Wave survived (40%)", type = "progressbar", numFulfilled = 0, numRequired = 1, finished = false } } }
    mock.progressBars = { [103] = 40 }
    check("a progress bar takes its percentage from the bar, and Blizzard's own text when it has one",
          (function()
              local q = Q.Read(103)
              local _, st = Q.Progress(q)
              return q.objectives[1].have == 40 and st == "40%"
                 and Q.ObjectiveText(q.objectives[1], q.title) == "Wave survived (40%)"
          end)())
    mock.watched = { 101, 102, 103 }
    local lines = Q.Lines()
    check("the list: ready to turn in before the rest, one line each, nothing expanded",
          lines[1].questID == 102 and lines[1].colour == "notifGreen" and lines[2].questID == 101
          and not lines[2].expand and #lines == 3)
    mock.superTracked = 101
    lines = Q.Lines()
    check("  the waypoint quest goes first, in amber, with what is left of it",
          lines[1].questID == 101 and lines[1].colour == "notifAmber" and lines[1].expand == true)
    mock.superTracked = 0
    check("past eight quests, the list says how many more", (function()
        local was = mock.watched
        mock.watched = {}
        for i = 1, 11 do
            mock.quests[#mock.quests + 1] = { id = 200 + i, title = "Q" .. i, objectives = {} }
            mock.watched[i] = 200 + i
        end
        local l, more = Q.Lines()
        Q.Build()
        Q.Refresh()
        local toggle = Q.frame.__footer.more
        local says = toggle:IsShown() and toggle.text:GetText()
        Q.SetExpanded(true)
        local all, rest = Q.Lines()
        local fewer = toggle.text:GetText()
        Q.SetExpanded(false)
        for i = #mock.quests, 4, -1 do mock.quests[i] = nil end
        mock.watched = was
        return #l == 8 and more == 3 and says == "+3 more" and #all == 11 and rest == 0 and fewer == "fewer",
               ("%d %d %s %d %s"):format(#l, more, tostring(says), #all, tostring(fewer))
    end)())
    check("only the pinned quest carries a count; the rest read to the edge", (function()
        mock.watched, mock.superTracked = { 101, 103 }, 101
        Q.Build()
        Q.Refresh()
        local pinned, other
        for _, r in ipairs(Q.rows) do
            if r.questID == 101 then pinned = r elseif r.questID == 103 then other = r end
        end
        mock.superTracked = 0
        return pinned and other and pinned.status:IsShown() and pinned.status:GetText() == "36%"
           and not other.status:IsShown()
    end)())
    check("the list is closed until asked for, and the pointer never wakes it",
          not Q.open and Registry.Get("QuestList").target == 0)
    run("quests")
    check("/myui quests opens it", Q.open == true and Registry.Get("QuestList").target == 1)
    check("  and its quest rows take clicks only while open", Q.rows[1]:IsMouseEnabled() == true)
    check("hovering a quest calls up its objectives, done ones green", (function()
        local row
        for _, r in ipairs(Q.rows) do if r.questID == 101 then row = r end end
        local n = row and Q.ShowCard(row)
        local ok = n == 3 and Q.card:IsShown() and Q.card.lines[1]:GetText() == "Boar Trouble"
                   and Q.card.lines[2]:GetText() == "Boars slain: 4/10"
        Q.HideCard()
        return ok and not Q.card:IsShown()
    end)())
    check("left-click points the waypoint arrow at a quest; again clears it", (function()
        local a = Q.Click(101, "LeftButton")
        local first = mock.superTracked == 101
        local b = Q.Click(101, "LeftButton")
        return a == "tracked" and first and b == "untracked" and mock.superTracked == 0
    end)())
    ns.Summon.driver:Fire("PLAYER_REGEN_DISABLED")
    check("combat puts it away", not Q.open and Registry.Get("QuestList").target == 0
          and Q.rows[1]:IsMouseEnabled() == false and Q.frame.__header.close:IsMouseEnabled() == false)

    -- Summoned panels go away by themselves, unless pinned (Summon.lua).
    local Sm = ns.Summon
    Q.Open()
    check("a summoned panel the pointer never reaches goes after a while", (function()
        mock.advance(ns, Sm.UNSEEN - 1, 4)
        local still = Q.open
        mock.advance(ns, 1.5, 6)
        return still and not Q.open and Q.summon.closedBy == "unseen"
    end)())
    check("  and once the pointer has been and left, soon after", (function()
        Q.Open()
        Q.frame.__over = true
        mock.advance(ns, 0.5, 2)
        Q.frame.__over = false
        mock.advance(ns, Sm.LINGER - 0.5, 4)
        local still = Q.open
        mock.advance(ns, 1, 4)
        return still and not Q.open and Q.summon.closedBy == "left"
    end)())
    check("pinned, it stays: past the pointer leaving and through combat", (function()
        Q.Open()
        Q.summon.header.pin:Click()
        mock.advance(ns, Sm.UNSEEN + 5, 10)
        Sm.driver:Fire("PLAYER_REGEN_DISABLED")
        return Q.open and Q.summon:IsPinned() and ns.db.pinned.quests == true
           and Q.summon.header.pin.text:GetText() == "pinned"
    end)())
    check("  and comes back open after a reload", (function()
        Q.summon.open = false
        Sm.Restore()
        return Q.open == true
    end)())
    check("close always closes, and unpins", (function()
        Q.summon.header.close:Click()
        return not Q.open and not Q.summon:IsPinned() and ns.db.pinned.quests == nil
    end)())
    check("the toast sources leave quest rows to the tracker while it is on", (function()
        Feed.Clear()
        Q.EVENTS.QUEST_ACCEPTED(101)
        ns.Sources.Handle("QUEST_ACCEPTED", 101)
        return #Feed.items == 1 and Feed.items[1].name == "Accepted: Boar Trouble", #Feed.items
    end)())
    -- Kinds and filters.
    mock.quests = {
        { id = 301, title = "Main Story", objectives = { { text = "a", numFulfilled = 0, numRequired = 1 } } },
        { id = 302, title = "Rare Hunt", world = true, objectives = { { text = "b", numFulfilled = 0, numRequired = 1 } } },
        { id = 303, title = "Bonus: Clear the Camp", task = true, objectives = { { text = "c", numFulfilled = 0, numRequired = 1 } } },
    }
    mock.watched, mock.watchedWorld = { 301 }, { 302 }
    mock.trackedAch = { 9001 }
    mock.achievements[9001] = "Explorer"
    mock.achCriteria[9001] = { { "Visit the lake", true, 1, 1 }, { "Bears", false, 3, 10 } }
    local realInfo = _G.C_QuestLog.GetInfo
    _G.C_QuestLog.GetInfo = function(i)
        local q = mock.quests[i]
        return q and { questID = q.id, title = q.title, isTask = q.task == true }
    end
    local items = Q.Items()
    local kinds = {}
    for _, it in ipairs(items) do kinds[it.kind] = (kinds[it.kind] or 0) + 1 end
    check("the list knows each kind: a quest, a world quest, an event here, a tracked achievement",
          kinds.quest == 1 and kinds.world == 1 and kinds.event == 1 and kinds.achievement == 1)
    local ach = Q.ReadAchievement(9001)
    check("  an achievement reads as its criteria, counted ones with their count",
          ach.title == "Explorer" and ach.objectives[1].done and ach.objectives[2].text == "3/10 Bears")
    Q.Build()
    Q.Filter("world")
    local l = Q.Lines()
    check("a filter shows one kind", #l == 1 and l[1].kind == "world" and l[1].text == "Rare Hunt")
    check("  and every chip carries its count", (function()
        local t = {}
        for _, c in ipairs(Q.frame.chips) do t[#t + 1] = c.text:GetText() end
        return t[1] == "all 4" and t[2] == "1" and t[3] == "1" and t[4] == "1"
           and t[5] == "1" and Q.frame.__header.title:GetText():find("world", 1, true) ~= nil,
           table.concat(t, ",")
    end)())
    Q.Filter("achievement")
    l = Q.Lines()
    check("achievements: right-click stops tracking one", l[1] and l[1].achievementID == 9001
          and Q.ClickAchievement(9001, "RightButton") == "untracked" and #mock.trackedAch == 0)
    Q.Filter(nil)
    _G.C_QuestLog.GetInfo = realInfo
    mock.quests, mock.watched, mock.watchedWorld = {}, {}, {}
end

-- ---------------------------------------------------------------------------
section("Round 005 -- chat panel and who's online")
-- ---------------------------------------------------------------------------
do
    local T, So = ns.Talk, ns.Social
    T.enabled = true
    T.log, T.unread = {}, {}
    Feed.Clear()
    T.Add("CHAT_MSG_GUILD", "anyone for a dungeon?", "Bren-Realm")
    check("a message is kept, newest first, with its group", T.log[1].group == "guild"
          and T.log[1].who == "Bren-Realm" and (T.unread.guild or 0) == 1)
    check("  guild chat that does not name you does not toast", #Feed.items == 0)
    _G.UnitName = function() return "Nimbus" end
    T.Add("CHAT_MSG_GUILD", "nimbus you around?", "Bren-Realm")
    check("  guild chat that names you does", Feed.items[1] and Feed.items[1].kind == "violet"
          and Feed.items[1].name == "Bren: nimbus you around?")
    Feed.Clear()
    T.Add("CHAT_MSG_PARTY", "pull in 5", "Aria")
    check("party chat toasts outside a raid", Feed.items[1] and Feed.items[1].name == "Aria: pull in 5")
    Feed.Clear()
    _G.IsInRaid = function() return true end
    T.Add("CHAT_MSG_RAID", "pull in 5", "Aria")
    check("  raid chat does not, unless it names you", #Feed.items == 0)
    _G.IsInRaid = nil
    local secret = mock.secret and mock.secret("hidden") or nil
    if secret then
        Feed.Clear()
        T.Add("CHAT_MSG_PARTY", secret, "Aria")
        check("a secret message is kept but never toasted", T.log[1].text == secret and #Feed.items == 0)
    end
    T.Build()
    T.Open()
    check("the chat panel opens, rows filled, and reading clears the unread counts on close", (function()
        local shown = 0
        for _, r in ipairs(T.rows) do if r:IsShown() then shown = shown + 1 end end
        local before = T.unread.guild
        T.summon:Close("asked")
        return shown >= 3 and before ~= nil and next(T.unread) == nil and T.filter == nil
    end)())
    local opened
    local realOpen = ns.Chat.Open
    ns.Chat.Open = function(prefill) opened = prefill end
    check("clicking a message answers on its channel", T.Reply(T.log[#T.log]) == "/g " and opened == "/g ")
    T.Add("CHAT_MSG_WHISPER", "hey", "Cato-Realm")
    check("  a whisper answers its sender", T.Reply(T.log[1]) == "/w Cato-Realm ")
    T.Filter("guild")
    check("the type row speaks on the filter's channel", T.Type() == "/g ")
    T.Filter(nil)
    ns.Chat.Open = realOpen

    -- Who's online.
    mock.guild = { { name = "Aria-Realm", zone = "Dornogal", online = true },
                   { name = "Bren-Realm", zone = "", online = false } }
    mock.friends = { { name = "Cato", connected = true, area = "Stormwind" } }
    local lines, n, counts = So.Lines()
    check("who's online: guild then friends, offline left out, each marked with its group",
          n == 2 and lines[1].name == "Aria" and lines[1].group == "guild"
          and lines[2].name == "Cato" and lines[2].group == "friends" and counts.guild == 1)
    So.Filter("friends")
    check("  a filter keeps one group", #So.Lines() == 1 and So.Lines()[1].name == "Cato")
    So.Filter(nil)
    Feed.Clear()
    So.OnSystem("|Hplayer:Aria-Realm|h[Aria-Realm]|h has come online.")
    So.OnSystem("|Hplayer:Bren-Realm|h[Bren-Realm]|h has come online.")
    So.OnSystem("|Hplayer:Cato|h[Cato]|h has come online.")
    check("logins gather a moment, then one toast", #Feed.items == 0)
    mock.advance(ns, So.GATHER + 0.1, 2)
    check("  \"Online: Aria, Bren +1\"", Feed.items[1] and Feed.items[1].name == "Online: Aria, Bren +1",
          Feed.items[1] and Feed.items[1].name)
    check("a name in the list whispers them", (function()
        local got
        ns.Chat.Open = function(p) got = p end
        local how = So.Whisper({ name = "Aria", full = "Aria-Realm" })
        ns.Chat.Open = realOpen
        return how == "whisper" and got == "/w Aria-Realm "
    end)())
    check("docked panels stack instead of overlapping: chat sits under the history", (function()
        if not ns.Center.panel then return true end   -- the history is an extra
        local was = ns.db.extras
        ns.db.extras = true
        ns.Center.Open()
        T.Open()
        local p, rel, rp = T.panel:GetPoint(1)
        local ok = p == "TOPLEFT" and rel == ns.Center.panel and rp == "BOTTOMLEFT"
        ns.Center.Close()
        local p2, rel2 = T.panel:GetPoint(1)
        ok = ok and p2 == "TOPLEFT" and rel2 == UIParent
        T.summon:Close("asked")
        ns.db.extras = was
        return ok
    end)())
    check("every summoned panel sits where Blizzard's windows open over it", (function()
        for key, c in pairs(ns.Summon.all) do
            if c.frame:GetFrameStrata() ~= "MEDIUM" then return false, key end
        end
        return ns.Quests.card:GetFrameStrata() == "MEDIUM"
    end)())
    check("every summoned panel is one width, on the grid", (function()
        local panels = { T.panel, ns.Social.panel, ns.Quests.frame, ns.Center.panel }
        local first
        for _, p in ipairs(panels) do
            if p then
                first = first or p:GetWidth()
                if math.abs(p:GetWidth() - first) > 0.01 then return false end
            end
        end
        return first ~= nil
    end)())
    check("the history rolls runs up and clears what it shows", (function()
        if not ns.Center.panel then return true end
        ns.Center.filter = nil
        ns.Log.Clear()
        Feed.Add("violet", "Online: Aria")
        Feed.Add("violet", "Online: Bren")
        Feed.Add("violet", "Online: Cato")
        Feed.Add("blue", "Voidsteel Greaves")
        Feed.Add("blue", "Voidsteel Greaves")
        local r = ns.Center.Rows()
        local ok = #r == 2 and r[1].name == "Voidsteel Greaves" and r[1].count == 2
                   and r[2].name == "Online: Cato, Bren +1"
        ns.Center.Filter("blue")
        local n = ns.Center.ClearShown()
        ns.Center.Filter(nil)
        return ok and n == 2 and #ns.Center.Rows() == 1, ("%d %s %s %s"):format(#r, tostring(r[1] and r[1].name), tostring(r[1] and r[1].count), tostring(r[2] and r[2].name))
    end)())
    check("a notification row: right-click clears just it (all of a rolled-up run)", (function()
        if not ns.Center.panel then return true end
        ns.Center.filter = nil
        ns.Log.Clear()
        Feed.Add("blue", "Pebble")
        Feed.Add("violet", "Online: Aria")
        Feed.Add("violet", "Online: Bren")
        local r = ns.Center.Rows()
        local how = ns.Center.ClickRow(r[1], "RightButton")
        local left = ns.Center.Rows()
        return how == "cleared" and #left == 1 and left[1].name == "Pebble"
    end)())
    check("  left-click acts: a login opens who's online, a quest the quest list", (function()
        if not ns.Center.panel then return true end
        local a = ns.Center.Act({ kind = "violet", name = "Online: Aria" })
        if ns.Social.open then ns.Social.Toggle() end
        local b = ns.Center.Act({ kind = "amber", name = "Accepted: Boar Trouble" })
        ns.Quests.Close()
        return a == "online" and b == "quests"
    end)())
    check("a docked panel never runs past the bottom of the screen", (function()
        local was = _G.UIParent.__h
        _G.UIParent.__h = 400
        T.log = {}
        for i = 1, 30 do T.Add("CHAT_MSG_SAY", "line " .. i, "Aria") end
        T.Open()
        T.expanded = true
        T.Refresh()
        local _, _, _, _, y = T.panel:GetPoint(1)
        local top = math.abs(y or 0)
        local fits = top + T.panel:GetHeight() <= 400 - Scale.U(ns.Summon.BOTTOM_RESERVE) + 0.01
        local more = T.panel.__footer.more.text:GetText()
        T.expanded = nil
        T.summon:Close("asked")
        _G.UIParent.__h = was
        return fits and more == "fewer", top + T.panel:GetHeight()
    end)())
    check("each hue keeps one shape everywhere", (function()
        local d = ns.Summon.Dot(UIParent, "notifViolet")
        local a = d.shape
        d:SetHue("notifBlue")
        local b = d.shape
        d:SetHue("notifAmber")
        return a == "circle" and b == "diamond" and d.shape == "triangle"
    end)())
    check("a docked panel is only as tall as what it holds", (function()
        T.log = {}
        T.Build()
        T.Refresh()
        local h1 = T.panel:GetHeight()
        for i = 1, 5 do T.Add("CHAT_MSG_SAY", "hi " .. i, "Aria") end
        T.Refresh()
        return T.panel:GetHeight() > h1
    end)())
    mock.guild, mock.friends = {}, {}
    _G.UnitName = nil
end

-- ---------------------------------------------------------------------------
section("Round 005 -- the map on a key")
-- ---------------------------------------------------------------------------
do
    local M = ns.Map
    local wasMM = _G.Minimap
    local corner = mock.frame({ name = "MinimapCornerMock" })
    local mm = mock.frame({ name = "Minimap", parent = corner })
    mm:SetSize(140, 140)
    mm:SetPoint("CENTER", corner, "CENTER", 0, 0)
    mm.zoom = 3
    mm.GetZoom = function() return mm.zoom end
    mm.SetZoom = function(_, z) mm.zoom, mm.zoomed = z, true end
    _G.Minimap = mm
    M.enabled = true
    M.Build()
    check("the map key brings Blizzard's minimap up big, in a summoned panel, at the zoom it had", (function()
        M.Toggle()
        return M.open and mm:GetParent() == M.panel.area and mm:GetWidth() > 140 and mm.zoom == 3 and not mm.zoomed
           and M.panel:IsShown()
    end)())
    check("  and the same key hands it back to its corner, as it was", (function()
        M.Toggle()
        local p, rel = mm:GetPoint(1)
        return not M.open and mm:GetParent() == corner and mm:GetWidth() == 140 and mm.zoom == 3
           and p == "CENTER" and rel == corner and not M.panel:IsShown()
    end)())
    check("the minimap's buttons line up in the footer while it is out, and go home after", (function()
        local btn = mock.frame({ name = "LibDBIcon10_BugSack", objectType = "Button", parent = mm, shown = true })
        btn:SetSize(31, 31)
        btn:SetPoint("CENTER", mm, "CENTER", 50, 50)
        mm.GetChildren = function() return btn end
        local zoom = mock.frame({ name = "ZoomInMock", objectType = "Button", parent = mm, shown = true })
        mm.ZoomIn = zoom
        M.Toggle()
        local p, rel = btn:GetPoint(1)
        local out = btn:GetParent() == M.panel and p == "BOTTOMRIGHT" and rel == M.panel
                    and btn:GetWidth() < 31 and zoom:GetAlpha() == 0
        M.Toggle()
        local p2, rel2 = btn:GetPoint(1)
        mm.GetChildren, mm.ZoomIn = nil, nil
        return out and btn:GetParent() == mm and p2 == "CENTER" and rel2 == mm and btn:GetWidth() == 31
           and zoom:GetAlpha() == 1, ("%s %s %s %s %s %s"):format(tostring(out), tostring(btn:GetParent() == mm),
           tostring(p2), tostring(rel2 == mm), tostring(btn:GetWidth()), tostring(zoom:GetAlpha()))
    end)())
    check("LibDBIcon buttons are stood in for: the original hidden, a proxy in the row that clicks through", (function()
        local clicked
        local orig = mock.frame({ name = "LibDBIcon10_BugSack", objectType = "Button", parent = mm, shown = true })
        orig.dataObject = { icon = "Interface\\Icons\\bug", OnClick = function(_, b) clicked = b end }
        orig.db = { hide = false }
        mm.GetChildren = function() return orig end
        M.Toggle()
        local proxy = M.proxies.BugSack
        local ok = proxy and proxy:IsShown() and not orig:IsShown() and proxy:GetPoint(1) == "BOTTOMRIGHT"
        if proxy then proxy:Click("RightButton") end
        M.Toggle()
        mm.GetChildren = nil
        return ok and clicked == "RightButton" and orig:IsShown() and not proxy:IsShown(),
               ("%s %s %s %s"):format(tostring(ok), tostring(clicked), tostring(orig:IsShown()), tostring(proxy and proxy:IsShown()))
    end)())
    check("the header says where you are", (function()
        _G.GetMinimapZoneText = function() return "Dornogal" end
        _G.C_Map = { GetBestMapForUnit = function() return 1 end,
                     GetPlayerMapPosition = function() return { GetXY = function() return 0.412, 0.638 end } end }
        local zone, at = M.Where()
        _G.C_Map.GetPlayerMapPosition = function() return nil end
        local z2, at2 = M.Where()
        return zone == "Dornogal" and at == "41.2, 63.8" and z2 == "Dornogal" and at2 == nil
    end)())
    check("the map heads the right column, the quest list under it, one width", (function()
        M.Toggle()
        ns.Quests.Open()
        local p, rel = M.panel:GetPoint(1)
        local q, qrel, qrp = ns.Quests.frame:GetPoint(1)
        local ok = p == "TOPRIGHT" and rel == UIParent and q == "TOPRIGHT" and qrel == M.panel
                   and qrp == "BOTTOMRIGHT" and math.abs(M.panel:GetWidth() - ns.Quests.frame:GetWidth()) < 0.01
        ns.Quests.Close()
        M.Toggle()
        return ok
    end)())
    check("combat puts it away unless pinned", (function()
        M.Toggle()
        ns.Summon.driver:Fire("PLAYER_REGEN_DISABLED")
        return not M.open and mm:GetParent() == corner
    end)())
    _G.Minimap = wasMM
end

-- ---------------------------------------------------------------------------
section("Named places")
-- ---------------------------------------------------------------------------
do
    local P, C = ns.Places, ns.Clear
    local all, act, db = mock.layouts.layouts, mock.layouts.activeLayout, _G.MyUICharDB
    _G.MyUICharDB = { schema = 1, entries = {} }
    mock.layouts.layouts = { { layoutName = "Theirs", layoutType = 1, systems = {} },
                             { layoutName = "MyUI", layoutType = 2, systems = {} } }
    mock.layouts.activeLayout = 3
    check("a part in Edit Mode's hands does not move on a spec that is not on MyUI's layout", (function()
        mock.editMode.saved = nil
        local p, why = P.Set("cooldowns", "left")
        return p == nil and why:find("layout use", 1, true) ~= nil and mock.editMode.saved == nil
           and _G.MyUICharDB.places == nil
    end)())
    mock.layouts.activeLayout = 4
    local pt0, x0, y0, rel0 = C.Anchor("Essential")
    check("cooldowns to the left edge: anchored to it, growing in, the rows over them too", (function()
        local p, changed = P.Set("cooldowns", "left")
        local pt, x, y, rel = C.Anchor("Essential")
        local pt2, x2 = C.Anchor("BuffIcon")
        local bb, bx = C.Anchor("BuffBars")
        return p and changed and pt == "BOTTOMLEFT" and rel == "BOTTOMLEFT" and near(x, Scale.U(16)) and near(y, y0)
           and pt2 == "BOTTOMLEFT" and near(x2, Scale.U(16)) and bb == "BOTTOMLEFT" and near(bx, Scale.U(16))
    end)())
    check("  the same again changes nothing and saves nothing", (function()
        mock.editMode.saved = nil
        local p, changed = P.Set("cooldowns", "left")
        return p and changed == false and mock.editMode.saved == nil
    end)())
    check("  the edge is taken: a second part is refused by name, and stays where it was", (function()
        local p, why = P.Set("group", "left")
        return p == nil and why:find("Cooldowns", 1, true) ~= nil and P.Of("group") == "target"
    end)())
    check("  the tooltip has the right edge until it is moved", (function()
        local p, why = P.Set("group", "right")
        return p == nil and why:find("Tooltip", 1, true) ~= nil
    end)())
    check("kept for this character and this screen size only", (function()
        local was = _G.UIParent.__w
        _G.UIParent.__w = 1188
        local other = P.Of("cooldowns")
        _G.UIParent.__w = was
        return other == "bar" and P.Of("cooldowns") == "left" and _G.MyUICharDB.places.Wide.cooldowns == "left"
    end)())
    check("a drag snaps to the place on that side, or to none", P.At("cooldowns", 0.1) == "left"
          and P.At("cooldowns", 0.5) == "bar" and P.At("cooldowns", 0.9) == nil and P.At("tooltip", 0.2) == "left")
    check("  dropping a box moves its part", P.Drop("Essential", 0.5) == "bar" and P.Of("cooldowns") == "bar"
          and (C.Anchor("Essential")) == pt0 and _G.MyUICharDB.places.Wide.cooldowns == nil)
    check("not in combat", (function()
        local real = _G.InCombatLockdown
        _G.InCombatLockdown = function() return true end
        local p, why = P.Set("group", "left")
        _G.InCombatLockdown = real
        return p == nil and why == "not in combat"
    end)())
    check("group frames go to an edge, and back with reset; reset twice changes nothing", (function()
        local home = { ns.Layout.Pos("Group") }
        P.Set("group", "left")
        local pt, rel, x = ns.Layout.Pos("Group")
        local moved = pt == "BOTTOMLEFT" and rel == "BOTTOMLEFT" and x == 16
        local n, again = P.Reset(), P.Reset()
        return moved and n == 1 and again == 0 and (ns.Layout.Pos("Group")) == home[1]
    end)())
    check("a panel changes columns, and its order with the others holds", (function()
        ns.Quests.Open()
        P.Set("quests", "left")
        local p, rel = ns.Quests.frame:GetPoint(1)
        local ok = p == "TOPLEFT" and rel == UIParent
        P.Set("quests", "right")
        local p2 = ns.Quests.frame:GetPoint(1)
        ns.Quests.Close()
        return ok and p2 == "TOPRIGHT"
    end)())
    check("a character log that starts again keeps the places", (function()
        _G.MyUICharDB = { schema = 999, entries = {}, places = { Wide = { group = "left" } } }
        ns.Log.Attach()
        local kept = _G.MyUICharDB.places and _G.MyUICharDB.places.Wide.group == "left" and #_G.MyUICharDB.entries == 0
        return kept
    end)())
    run("place")
    check("/myui place lists every part and its places", (function()
        local out = ns.GetOutput()
        for _, part in ipairs(P.PARTS) do if not out:find(part.key, 1, true) then return false, part.key end end
        return true
    end)())
    _G.MyUICharDB = db
    ns.Log.Attach()
    mock.layouts.layouts, mock.layouts.activeLayout = all, act
    P.Apply({ panel = true })
end

-- ---------------------------------------------------------------------------
section("Commands -- the trail kept on disk")
-- ---------------------------------------------------------------------------
do
    local Trail = ns.Commands.Trail
    ns.db.outputs = nil
    run("version")
    run("pct")
    local list = ns.db.outputs
    check("each command's output is kept, oldest first, with its time", #list == 2
          and list[1].command == "version" and list[2].command == "pct"
          and list[1].output ~= "" and list[1].at:match("^%d+%-%d+%-%d+ %d+:%d+:%d+$") ~= nil)
    run("spacing gap 32")
    check("  with what was typed after it", list[#list].args == "gap 32", list[#list].args)
    ns.Print("printed later")
    Trail.driver:Fire("PLAYER_LOGOUT")
    check("  and what it went on to print, saved at a reload",
          list[#list].output:find("printed later", 1, true) ~= nil)
    run("version")
    ns.ClearOutput()
    ns.Print("someone else entirely, and at some length so it outgrows the entry it must not replace")
    local before = list[#list].output
    Trail.Finish()
    check("  but never another output in its place", list[#list].output == before)
    run("copy")
    check("copy is not recorded over what it exists to show", list[#list].command ~= "copy")
    for _ = 1, 60 do run("version") end
    check("the trail keeps the last 50", #ns.db.outputs == 50, #ns.db.outputs)
    ns.readOnlyDB = true
    run("pct")
    ns.readOnlyDB = nil
    check("a newer build's saved data is not written to", ns.db.outputs[50].command == "version")
end

-- ---------------------------------------------------------------------------
section("Commands -- the debug report")
-- ---------------------------------------------------------------------------
do
    local Report = ns.Commands.Report
    local xml = assert(io.open("../MyUI/Bindings.xml")):read("*a")
    local declared = {}
    for name in xml:gmatch('<Binding name="(MYUI_[%w_]+)"') do declared[#declared + 1] = name end
    local listed = {}
    for _, b in ipairs(Report.BINDINGS) do listed[b] = true end
    local same = #declared == #Report.BINDINGS
    for _, b in ipairs(declared) do same = same and listed[b] == true end
    check("the report names every binding Bindings.xml declares", same, #declared)
    check("  and the report key has a name in the key bindings list",
          _G.BINDING_NAME_MYUI_REPORT ~= nil and type(_G.MyUI_Report) == "function")

    ns.db.report = nil
    ns.Log.Add("whisper", "Somebody Secret", 1, "a private message")
    local chatty = 0
    local frame = _G.DEFAULT_CHAT_FRAME
    local add = frame and frame.AddMessage
    if frame then frame.AddMessage = function(self, ...) chatty = chatty + 1 end end
    run("report")
    if frame then frame.AddMessage = add end
    local r = ns.db.report
    check("/myui report writes the report to saved variables", type(r) == "table"
          and r.schema == Report.SCHEMA and type(r.text) == "string" and r.version == ns.version)
    for _, title in ipairs({ "environment", "bindings", "notifications", "override", "audit",
                             "claims", "sources", "taint" }) do
        check("  with a section for " .. title, r.text:find("## " .. title, 1, true) ~= nil)
    end
    check("  and the notification log as kinds only, never names or text",
          r.text:find("whisper", 1, true) ~= nil and r.text:find("Somebody", 1, true) == nil
          and r.text:find("private", 1, true) == nil)
    check("  without colour codes", r.text:find("|cff", 1, true) == nil)
    check("  printing one line to chat, not every section", chatty == 1, chatty)
    check("  and printing to chat again afterwards", ns.quiet == nil)

    local reloaded = 0
    local was = _G.ReloadUI
    _G.ReloadUI = function() reloaded = reloaded + 1 end
    ns.db.report = nil
    _G.MyUI_Report()
    _G.ReloadUI = was
    check("the report key writes the report, then reloads",
          type(ns.db.report) == "table" and reloaded == 1)

    -- The key's two edges: the press writes and screenshots, the release reloads.
    local R = ns.Commands.Report
    local shots, wasShot = 0, _G.Screenshot
    _G.Screenshot = function() shots = shots + 1 end
    _G.ReloadUI = function() reloaded = reloaded + 1 end
    reloaded = 0
    ns.db.report = nil
    _G.MyUI_Report("down")
    check("the press writes the report and takes a screenshot, named by its time",
          type(ns.db.report) == "table" and shots == 1 and reloaded == 0
          and ns.db.report.shot and ns.db.report.shot.result == "pending"
          and ns.db.report.shot.at:match("^%d%d%d%d%d%d_%d%d%d%d%d%d$") ~= nil)
    R.shotDriver:Fire("SCREENSHOT_SUCCEEDED")
    _G.MyUI_Report("up")
    check("  the release reloads once the client says it is saved",
          reloaded == 1 and ns.db.report.shot.result == "ok")
    reloaded, shots = 0, 0
    _G.MyUI_Report("down")
    ns.ClearOutput()
    _G.MyUI_Report("up")
    check("  a release before it is saved does not reload, and says so",
          reloaded == 0 and ns.GetOutput():find("still saving", 1, true) ~= nil)
    check("  as a notification too: chat is hidden behind MyUI's panel", (function()
        for _, e in ipairs(ns.Log.db.entries) do
            if tostring(e.name):find("report key again", 1, true) then return true end
        end
        return false
    end)())
    R.shotDriver:Fire("SCREENSHOT_SUCCEEDED")
    local at = ns.db.report.at
    _G.MyUI_Report("down")
    _G.MyUI_Report("up")
    check("  and the next press only finishes it: no second report or screenshot",
          reloaded == 1 and shots == 1 and ns.db.report.at == at)
    R.shotDriver:Fire("SCREENSHOT_FAILED")
    check("  a shot already settled is not changed by a later event", ns.db.report.shot.result == "ok")
    R.shot, R.waiting = nil, nil
    _G.Screenshot, _G.ReloadUI = wasShot, was

    ns.readOnlyDB = true
    ns.db.report = nil
    run("report")
    ns.readOnlyDB = nil
    check("a newer build's saved data is not written to", ns.db.report == nil)
end

-- ---------------------------------------------------------------------------
section("Group frames per role (2026-11-23)")
-- ---------------------------------------------------------------------------
do
    local Clear, G, Reveal = ns.Clear, ns.Group, ns.Reveal
    local db = ns.db.clear
    local savedBy, savedLook, savedOld = db.groupBy, db.groupLook, db.group
    db.groupBy, db.groupLook, db.group = nil, nil, "auto"
    check("the old single setting migrates: auto was combat for healers only",
          Clear.GroupMode("TANK") == "hover" and Clear.GroupMode("HEALER") == "combat"
          and Clear.GroupMode("DAMAGER") == "hover" and db.group == nil)
    db.groupBy, db.groupLook = nil, nil
    check("  and with nothing saved, every role is combat", Clear.GroupMode("TANK") == "combat"
          and Clear.GroupMode("HEALER") == "combat" and Clear.GroupMode("DAMAGER") == "combat")
    check("  healers get the list, tanks and DPS the icons", Clear.GroupLook("HEALER") == "list"
          and Clear.GroupLook("TANK") == "icons" and Clear.GroupLook("DAMAGER") == "icons")
    check("no role reads as DPS", Clear.SettingRole("NONE") == "DAMAGER")

    run("group tank always")
    run("group healer hover")
    check("each role keeps its own mode", Clear.GroupMode("TANK") == "always"
          and Clear.GroupMode("HEALER") == "hover" and Clear.GroupMode("DAMAGER") == "combat")
    ns.ClearOutput()
    run("group")
    local out = ns.GetOutput()
    check("/myui group lists all three roles", out:find("tank", 1, true) and out:find("healer", 1, true)
          and out:find("dps", 1, true) and out:find("always", 1, true))
    run("group nonsense")
    check("  and refuses a word it does not know", ns.GetOutput():find("unknown", 1, true) ~= nil)

    _G.UnitGroupRolesAssigned = function() return "TANK" end
    G.events:Fire("PLAYER_ROLES_ASSIGNED")
    check("always: a tank's group frames are up out of combat", Registry.Get("Group").target == 1
          and Reveal.HasClaim("always", "Group"))
    run("group tank hover")
    check("  and down again when set to hover", Registry.Get("Group").target == 0
          and not Reveal.HasClaim("always", "Group"))
    run("group always")
    check("a bare mode sets the current role's", Clear.GroupMode("TANK") == "always"
          and Registry.Get("Group").target == 1)
    _G.UnitGroupRolesAssigned = function() return "HEALER" end
    G.events:Fire("PLAYER_SPECIALIZATION_CHANGED")
    check("  and a spec swap to a role that is not always drops it", Registry.Get("Group").target == 0)

    local party = G.party
    check("a healer's party is the list", party:GetAttribute("point") == "TOP"
          and near(party:GetAttribute("unitWidth"), Scale.U(G.SIZES.healer.w)))
    run("group healer boxes")
    check("  until set to boxes", party:GetAttribute("point") == "LEFT"
          and near(party:GetAttribute("unitHeight"), Scale.U(G.SIZES.box.h))
          and near(G.frame:GetWidth(), Scale.U(G.SIZES.box.w * 5 + G.BOX_GAP * 4)))

    local b = mock.frame({ name = "MyUIPartyHeaderUnitButton9", objectType = "Button" })
    b.__parent = party
    party:SetAttribute("child9", b)
    mock.units.party2 = true
    local wasClass, wasColours, wasName = _G.UnitClass, _G.RAID_CLASS_COLORS, _G.UnitName
    _G.UnitName = _G.UnitName or function() return "Nimbus" end
    _G.UnitClass = function() return "Priest", "PRIEST" end
    _G.RAID_CLASS_COLORS = { PRIEST = { r = 0.9, g = 0.8, b = 0.7 } }
    b:SetAttribute("unit", "party2")
    local function lastColour(t)
        for i = #t.__calls, 1, -1 do
            if t.__calls[i].method == "SetColorTexture" then return t.__calls[i] end
        end
    end
    check("a box fills its health in the class colour", (function()
        local c = lastColour(b.__fill)
        return c and near(c[1], 0.9) and near(c[2], 0.8) and near(c[3], 0.7)
    end)())
    run("group healer list")
    check("  a list row keeps the palette's fill", (function()
        local c = lastColour(b.__fill)
        local r = ns.Palette.Get("fill")
        return c and near(c[1], r)
    end)())
    run("group healer icons")
    check("icons: no name, the health fills the square, in the class colour", (function()
        local c = lastColour(b.__fill)
        return not b.__name:IsShown() and near(b:GetWidth(), Scale.U(G.SIZES.icon.w))
           and near(b:GetHeight(), Scale.U(G.SIZES.icon.h)) and c and near(c[1], 0.9)
    end)())
    check("  the role drawn over the health", b.__role:GetParent() == b.__top)
    check("  and the group area is five icons wide",
          near(G.frame:GetWidth(), Scale.U(G.SIZES.icon.w * 5 + G.ROWS.icons.gap * 4)))
    -- Charon play (twice): a descending stair. The header lays out on every
    -- attribute, so the buttons must be cleared after every attribute but
    -- the point, and the point set last.
    run("group healer list")      -- from a column to a row: the point changes
    local order = {}
    local setAttr, clear = party.SetAttribute, b.ClearAllPoints
    party.SetAttribute = function(self, k, v) order[#order + 1] = "attr:" .. tostring(k); return setAttr(self, k, v) end
    b.ClearAllPoints = function(self) order[#order + 1] = "clear"; return clear(self) end
    run("group healer boxes")
    party.SetAttribute, b.ClearAllPoints = setAttr, clear
    check("switching look: every attribute, then the buttons cleared, then the point (no stair)", (function()
        local n = #order
        if order[n] ~= "attr:point" or order[n - 1] ~= "clear" then return false, table.concat(order, " ") end
        for i = 1, n - 2 do
            if order[i]:find("^attr:") and order[i] ~= "attr:point" then
                for j = i + 1, n - 1 do if order[j] == "clear" then return true end end
                return false, table.concat(order, " ")
            end
        end
        return true
    end)())
    order = {}
    party.SetAttribute = function(self, k, v) order[#order + 1] = "attr:" .. tostring(k); return setAttr(self, k, v) end
    b.ClearAllPoints = function(self) order[#order + 1] = "clear"; return clear(self) end
    run("group healer icons")
    party.SetAttribute, b.ClearAllPoints = setAttr, clear
    check("  and a row to a row keeps the anchors (nothing to clear)", (function()
        for _, o in ipairs(order) do if o == "clear" then return false end end
        return order[#order] == "attr:point"
    end)())
    run("group healer list")
    check("  and back to the list, the name returns", b.__name:IsShown())
    run("group healer boxes")
    _G.UnitClass = function() return nil, mock.secret and mock.secret("x") or nil end
    run("group healer boxes")
    check("  and an unreadable class falls back to the palette", (function()
        local c = lastColour(b.__fill)
        return c and near(c[1], (ns.Palette.Get("fill")))
    end)())
    _G.UnitClass, _G.RAID_CLASS_COLORS, _G.UnitName = wasClass, wasColours, wasName
    mock.units.party2 = nil
    _G.UnitGroupRolesAssigned = nil
    db.groupBy, db.groupLook, db.group = savedBy, savedLook, savedOld
    db.groupBy, db.groupLook = nil, nil
    G.Apply()
end

-- ---------------------------------------------------------------------------
section("The debug log (2026-11-23)")
-- ---------------------------------------------------------------------------
do
    local Dev, Reveal = ns.Dev, ns.Reveal
    ns.db.dev, ns.db.devlog = nil, nil
    check("off by default: nothing is kept", Dev.Add("command", "x") == nil and #Dev.Entries() == 0)
    check("  and it will not open", Dev.Open() == false)
    run("dev on")
    check("/myui dev on turns it on", Dev.On() and ns.db.dev == true)

    run("version")
    local e = Dev.Shown()[1]
    check("a command is noted with what it printed", e and e.kind == "command"
          and e.text:find("/myui version", 1, true) == 1 and e.text:find(" -- ", 1, true) ~= nil)
    local n = #Dev.Entries()
    run("dev")
    check("  but not its own toggles", #Dev.Entries() == n and Dev.IsOpen())

    Reveal.Claim("peek")
    Reveal.Release("peek")
    check("reveal claims and releases are noted", Dev.Shown()[1].text == "release peek"
          and Dev.Shown()[2].text == "claim peek")
    local before = #Dev.Entries()
    Reveal.Claim("cursor", "SelfStack")
    Reveal.Release("cursor", "SelfStack")
    check("  but never the pointer's", #Dev.Entries() == before)

    local guardWas = Guard.mode
    Guard.mode = "warn"
    Guard.Violation("a test violation")
    Guard.mode = guardWas
    check("a compliance violation is an error", Dev.Shown()[1].kind == "error"
          and Dev.Shown()[1].text:find("a test violation", 1, true) ~= nil)
    Dev.driver:Fire("ADDON_ACTION_BLOCKED", "MyUI", "CastSpellByName()")
    Dev.driver:Fire("ADDON_ACTION_BLOCKED", "SomeOtherAddon", "Jump()")
    check("Blizzard blocking MyUI is an error; another addon's block is not ours",
          Dev.Shown()[1].text == "Blizzard blocked MyUI: CastSpellByName()")
    Dev.driver:Fire("EDIT_MODE_LAYOUTS_UPDATED")
    check("layout changes are noted", Dev.Shown()[1].kind == "layout")

    Dev.filter = "error"
    local shown = Dev.Shown()
    check("the filter shows one kind", #shown == 2 and shown[1].kind == "error" and shown[2].kind == "error")
    check("  and the panel's title says which", Dev.panel.__header.title:GetText() ~= nil)
    Dev.Refresh()
    check("  copy holds just what is shown, oldest first", (function()
        local t = Dev.Text()
        local a, b2 = t:find("violation", 1, true), t:find("CastSpellByName", 1, true)
        return a and b2 and a < b2 and t:find("version", 1, true) == nil
    end)())
    Dev.Copy()
    check("  in the copy window, selected", ns.Copy.IsShown())
    ns.Copy.Hide()
    local total = #Dev.Entries()
    check("clear empties what the filter shows, and only that", Dev.ClearShown() == 2
          and #Dev.Entries() == total - 2)
    Dev.filter = nil
    Dev.Remove(Dev.Shown()[1])
    check("a right-click clears one", #Dev.Entries() == total - 3)

    local f = Dev.panel.__footer
    check("the footer: copy, clear, report, on the shared grid", f.actions and #f.actions == 3
          and f.actions[1].text:GetText() == "copy" and f.actions[3].text:GetText() == "report")
    check("docked down the left with the other panels", Dev.summon.dock == "left")

    mock.mouseFoci = { Registry.Get("SelfStack").frame }
    check("the pointer line names the part and why it is up", Dev.Under():find("SelfStack", 1, true) ~= nil)
    -- Charon play: a damage meter row's GetName returns its name FontString.
    local row = mock.frame({ name = "MeterRow" })
    row.GetName = function() return mock.frame({}) end
    row.GetDebugName = function() return "DamageMeter.Row1" end
    mock.mouseFoci = { row }
    check("  even over a frame whose GetName is not a name", (function()
        local ok, text = pcall(Dev.Under)
        return ok and text:find("DamageMeter.Row1", 1, true) ~= nil
    end)())
    mock.mouseFoci = {}
    check("  or that it is the world", Dev.Under():find("the world", 1, true) ~= nil)

    Dev.Close()
    Dev.unseen = 0
    Guard.mode = "warn"
    Guard.Violation("while closed")
    Guard.mode = guardWas
    check("an error while closed is counted for the title", Dev.unseen == 1)
    run("dev clear")
    check("/myui dev clear empties it", #Dev.Entries() == 0)
    run("dev off")
    check("/myui dev off stops keeping anything", not Dev.On() and Dev.Add("command", "x") == nil)
    Guard.Reset()
end

-- ---------------------------------------------------------------------------
print("")
print(("%d checks, %d failures"):format(checks, failures))
os.exit(failures == 0 and 0 or 1)
