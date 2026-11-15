-- MyUI :: Bars.lua
-- Phase 4: SPEC.md 2's bar internals and 3's low health. The riskiest
-- compliance surface in v1 -- every value here is, or may be, secret.
--
-- THE RULE THIS FILE IS BUILT AROUND: forwarding a secret is legal,
-- inspecting one is not. Nothing below reads health, power or a cast time
-- into a variable it compares, measures or does arithmetic on. Every shape a
-- value needs -- a 0..1 fraction, the missing fraction, a 0..100 percentage,
-- a colour, a threshold alpha -- is made ENGINE-SIDE by a curve handed to
-- UnitHealthPercent / UnitPowerPercent, and the result goes straight to a
-- sanctioned setter through Guard.Send.
--
-- What is plain and may be branched on: unit tokens, event names, UnitExists,
-- the cast bar ID (NeverSecret, UnitDocumentation), LowHealthFrame's shown
-- state (a plain boolean -- RULES' fifth mechanism), a CVar.

local ADDON, ns = ...

local Guard, Scale, Palette, Registry, Compat = ns.Guard, ns.Scale, ns.Palette, ns.Registry, ns.Compat

local Bars = {}
ns.Bars = Bars

local U = function(v) return Scale.U(v) end

-- One boundary, one moment (SPEC 3). Set at Blizzard's 35% so the step-curve
-- escalation and the LowHealthFrame summon arrive together rather than at two
-- different healths. SPEC gives no number for the step; this is the choice.
Bars.CUTOFF = 0.35

-- SPEC 3's fill curve, percentages as the fractions the curve wants.
Bars.FILL_STOPS = {
    { 0.06, { 242 / 255,  86 / 255,  80 / 255, 1.00 } },
    { 0.17, { 242 / 255, 120 / 255, 100 / 255, 0.94 } },
    { 0.34, { 242 / 255, 170 / 255, 120 / 255, 0.92 } },
    { 0.58, { 242 / 255, 214 / 255, 150 / 255, 0.92 } },
    { 1.00, { 240 / 255, 241 / 255, 243 / 255, 0.92 } },
}

Bars.BREATHE = 1.60      -- SPEC 3/8: 1.0 <-> 0.55 at 1.60s
Bars.BREATHE_LOW = 0.55
Bars.EDGE_ALPHA = 0.35   -- SPEC 3: the danger hairline

local curves = {}
Bars.curves = curves

-- ---------------------------------------------------------------------------
-- Curves, built once at login before any secret touches them (API-NOTES 1)
-- ---------------------------------------------------------------------------

local function NumberStops(stops)
    local out = {}
    for i, s in ipairs(stops) do
        out[i] = { s[1], { s[2][1], s[2][2], s[2][3], 1 } }
    end
    return out
end

function Bars.BuildCurves()
    local problems = {}
    local function need(name, curve, err)
        curves[name] = curve
        if not curve then problems[#problems + 1] = name .. ": " .. tostring(err) end
    end
    need("frac",    Guard.Curve({ { 0, 0 }, { 1, 1 } }))
    need("missing", Guard.Curve({ { 0, 1 }, { 1, 0 } }))
    need("pct",     Guard.Curve({ { 0, 0 }, { 1, 100 } }))
    need("fill",    Guard.ColorCurve(Bars.FILL_STOPS))
    need("number",  Guard.ColorCurve(NumberStops(Bars.FILL_STOPS)))
    -- The depleted wash: danger red, alpha 0 at full health rising to 0.22
    -- across the same range as the fill curve.
    local r, g, b = 242 / 255, 107 / 255, 97 / 255
    need("wash",    Guard.ColorCurve({ { 0.06, { r, g, b, 0.22 } }, { 1.00, { r, g, b, 0 } } }))
    -- The discrete layer: one boundary, three step curves.
    need("below",   Guard.StepCurve(Bars.CUTOFF, 1, 0))
    need("above",   Guard.StepCurve(Bars.CUTOFF, 0, 1))
    need("edge",    Guard.StepCurve(Bars.CUTOFF, Bars.EDGE_ALPHA, 0))
    Bars.curveProblems = problems
    return #problems == 0
end

-- ---------------------------------------------------------------------------
-- Forwarding helpers -- results go straight to Guard.Send, never into a test
-- ---------------------------------------------------------------------------

local function Scalar(unit, curve)
    if not curve then return nil end
    return Guard.HealthThrough(unit, curve)
end

local function Colour(unit, curve)
    local c = curve and Guard.HealthThrough(unit, curve)
    if not c then return nil end
    local ok, r, g, b, a = pcall(c.GetRGBA, c)
    if not ok then return nil end
    return r, g, b, a
end

local function AlphaThrough(unit, curve)
    return curve and Guard.AlphaAt(unit, curve)
end

local INTERP = _G.Enum and _G.Enum.StatusBarInterpolation
               and _G.Enum.StatusBarInterpolation.ExponentialEaseOut

local function Value(bar, v)
    if v == nil then return end
    if INTERP then
        Guard.Send(bar, "SetValue", v, INTERP)
    else
        Guard.Send(bar, "SetValue", v)
    end
end

-- ---------------------------------------------------------------------------
-- Widgets
-- ---------------------------------------------------------------------------
-- SelfStack's health "group" exists twice: the steady copy Frames built, and
-- a low-health copy that breathes. The step alphas cross-fade them, so the
-- moment health crosses the cutoff the 12pt number becomes 14pt and the group
-- starts breathing -- with no comparison and no event (SPEC 3, API-NOTES 6).

local function Wash(bar)
    local wash = CreateFrame("StatusBar", nil, bar)
    wash:SetAllPoints(bar)
    wash:SetMinMaxValues(0, 1)
    wash:SetReverseFill(true)
    local t = wash:CreateTexture(nil, "ARTWORK")
    t:SetColorTexture(1, 1, 1, 1)
    wash:SetStatusBarTexture(t)
    wash.fill = t
    t:SetVertexColor(1, 1, 1, 0)
    wash:SetValue(0)
    return wash
end

-- Fill textures go white so the curve's colour arrives unmultiplied:
-- SetVertexColor multiplies the texture's own colour.
local function Whiten(bar, colourName)
    bar.fill:SetColorTexture(1, 1, 1, 1)
    bar.fill:SetVertexColor(Palette.Get(colourName))
end

local function BuildLowLayer(stack)
    local Frames = ns.Frames
    -- low: alpha from the "below" step. inner: the permanent breathe. Two
    -- frames because an Alpha animation owns its region's alpha; the step has
    -- to act on a parent, where alpha multiplies.
    local low = CreateFrame("Frame", nil, stack)
    low:SetAllPoints(stack)
    local inner = CreateFrame("Frame", nil, low)
    inner:SetAllPoints(low)

    local health = Frames.Bar(inner, 240, 4)
    Frames.DangerGradient(health, 240, 4)
    health:SetPoint("TOPLEFT", stack.health, "TOPLEFT", 0, 0)
    local tick20 = Frames.Fill(health, "tickDark", "OVERLAY")
    tick20:SetSize(Scale.Hairline(), U(4))
    tick20:SetPoint("TOPLEFT", health, "TOPLEFT", U(48), 0)
    local tick40 = Frames.Fill(health, "fillDim", "OVERLAY")
    tick40:SetSize(Scale.Hairline(), U(4))
    tick40:SetPoint("TOPLEFT", health, "TOPLEFT", U(96), 0)

    -- SPEC 3: 12pt -> 14pt, the only type-size change in the addon. On its
    -- own pill, over the low bar, so it breathes with it.
    local pill, number = Frames.Pill(inner, health, 14)

    local breathe = inner:CreateAnimationGroup()
    breathe:SetLooping("REPEAT")
    local down = breathe:CreateAnimation("Alpha")
    down:SetFromAlpha(1)
    down:SetToAlpha(Bars.BREATHE_LOW)
    down:SetDuration(Bars.BREATHE / 2)
    down:SetOrder(1)
    local up = breathe:CreateAnimation("Alpha")
    up:SetFromAlpha(Bars.BREATHE_LOW)
    up:SetToAlpha(1)
    up:SetDuration(Bars.BREATHE / 2)
    up:SetOrder(2)
    breathe:Play()

    low.health, low.number, low.pill, low.inner, low.breathe = health, number, pill, inner, breathe
    low.tick20, low.tick40 = tick20, tick40
    low:SetAlpha(0)
    return low
end

-- The steady layer: Frames' own health bar and 12pt number, gathered under
-- one frame so the "above" step can fade them together. Reparenting our own
-- frames; their anchors are to the stack and do not move.
local function BuildSteadyLayer(stack)
    local steady = CreateFrame("Frame", nil, stack)
    steady:SetAllPoints(stack)
    stack.health:SetParent(steady)
    stack.pill:SetParent(steady)
    ns.Frames.PlacePill(stack.pill)
    return steady
end

-- SPEC 3: a 1px danger hairline at the full screen edge, inset 0, alpha 0.35
-- below the cutoff. Not in the registry: no channel may reveal or dim it; its
-- alpha belongs to the step curve alone.
local function BuildEdge()
    local edge = CreateFrame("Frame", "MyUIDangerEdge", UIParent)
    edge:SetFrameStrata("HIGH")
    edge:SetAllPoints(UIParent)
    local px = Scale.Hairline()
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local t = edge:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(Palette.Get("danger"))
        if side == "TOP" or side == "BOTTOM" then
            t:SetHeight(px)
            t:SetPoint(side .. "LEFT")
            t:SetPoint(side .. "RIGHT")
        else
            t:SetWidth(px)
            t:SetPoint("TOP" .. side)
            t:SetPoint("BOTTOM" .. side)
        end
    end
    edge:SetAlpha(0)
    return edge
end

-- ---------------------------------------------------------------------------
-- Painting
-- ---------------------------------------------------------------------------

local stack, strip, low, steady, edge

--- Placeholder-free, data-free state: what the harness shoots and what show
-- on draws over. Palette colours, no tells.
function Bars.Neutral()
    if not stack then return end
    for _, bar in ipairs({ stack.health, low.health }) do
        bar.fill:SetVertexColor(Palette.Get("fill"))
        bar.wash.fill:SetVertexColor(1, 1, 1, 0)
        bar.wash:SetValue(0)
    end
    stack.number:SetTextColor(Palette.Get("textPrimary"))
    steady:SetAlpha(1)
    low:SetAlpha(0)
    edge:SetAlpha(0)
end

function Bars.Live()
    return stack ~= nil and not Bars.suspended
           and not (ns.Frames and ns.Frames.placeholders)
end

function Bars.UpdateHealth()
    if not Bars.Live() then return end
    local u = "player"
    local v, missing = Scalar(u, curves.frac), Scalar(u, curves.missing)
    for _, bar in ipairs({ stack.health, low.health }) do
        Value(bar, v)
        local r, g, b, a = Colour(u, curves.fill)
        if r ~= nil then Guard.Send(bar.fill, "SetVertexColor", r, g, b, a) end
        Value(bar.wash, missing)
        local wr, wg, wb, wa = Colour(u, curves.wash)
        if wr ~= nil then Guard.Send(bar.wash.fill, "SetVertexColor", wr, wg, wb, wa) end
    end
    local pct = Scalar(u, curves.pct)
    local nr, ng, nb, na = Colour(u, curves.number)
    for _, fs in ipairs({ stack.number, low.number }) do
        if pct ~= nil then Guard.Send(fs, "SetFormattedText", "%d", pct) end
        if nr ~= nil then Guard.Send(fs, "SetTextColor", nr, ng, nb, na) end
    end
    local below, above, e = AlphaThrough(u, curves.below), AlphaThrough(u, curves.above),
                            AlphaThrough(u, curves.edge)
    if above ~= nil then Guard.Send(steady, "SetAlpha", above) end
    if below ~= nil then Guard.Send(low, "SetAlpha", below) end
    if e ~= nil then Guard.Send(edge, "SetAlpha", e) end
end

function Bars.UpdatePower()
    if not Bars.Live() then return end
    local result = Guard.PowerThrough("player", curves.frac)
    Value(stack.resource, result)
end

-- Casting. The duration object drives the bar engine-side (SetTimerDuration).
-- It is AllowedWhenUntainted, so a duration that arrives secret (restricted
-- content) cannot drive it from addon code: then the bar shows full for the
-- length of the cast instead -- it says "casting" without saying how long.
local function CastBarID(unit)
    local id = select(10, _G.UnitCastingInfo(unit))   -- lint:allow R6 castBarID is NeverSecret (UnitDocumentation); nothing else kept
    if id ~= nil then return id, "cast" end
    local isEmpowered
    isEmpowered, _, id = select(9, _G.UnitChannelInfo(unit))
    if id ~= nil then return id, isEmpowered and "empower" or "channel" end
    return nil
end

function Bars.UpdateCast()
    if not Bars.Live() then return end
    local bar = stack.cast
    local id, kind = CastBarID("player")
    if not id then
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(0)
        return
    end
    local duration
    if kind == "cast" then
        duration = _G.UnitCastingDuration and _G.UnitCastingDuration("player")
    elseif kind == "empower" and _G.UnitEmpoweredChannelDuration then
        duration = _G.UnitEmpoweredChannelDuration("player")
    else
        duration = _G.UnitChannelDuration and _G.UnitChannelDuration("player")
    end
    local dir = _G.Enum and _G.Enum.StatusBarTimerDirection
    if duration ~= nil and not Compat.IsSecret(duration) and bar.SetTimerDuration then
        bar:SetTimerDuration(duration, nil,
            dir and (kind == "channel" and dir.RemainingTime or dir.ElapsedTime) or nil)
        Bars.castMode = "timer"
    else
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(1)
        Bars.castMode = "degraded"
    end
end

-- Experience (round 004 play): a thin line under SelfStack while levelling.
-- XP is not combat data; if a client ever hands it back secret, the line
-- hides (SetMinMaxValues is not sanctioned for a secret) rather than guess.
function Bars.UpdateXP()
    if not stack or not stack.xp then return end
    local atMax = _G.IsPlayerAtEffectiveMaxLevel and _G.IsPlayerAtEffectiveMaxLevel()
    local cur, max = _G.UnitXP and _G.UnitXP("player"), _G.UnitXPMax and _G.UnitXPMax("player")
    if atMax or cur == nil or max == nil then
        stack.xp:Hide()
        return
    end
    if Compat.IsSecret(max) or Compat.IsSecret(cur) or max <= 0 then
        stack.xp:Hide()
        return
    end
    stack.xp:SetMinMaxValues(0, max)
    stack.xp:SetValue(cur)
    stack.xp:Show()
end

-- SelfStack's name and level (round 004). Plain for the player; forwarded
-- anyway, the same way as the target's.
function Bars.UpdateIdentity()
    if not Bars.Live() then return end
    Guard.Send(stack.name, "SetText", _G.UnitName("player"))
    local level = _G.UnitLevel("player")
    if level ~= nil and Compat.IsSecret(level) then
        Guard.Send(stack.level, "SetFormattedText", "%d", level)
    elseif type(level) == "number" and level > 0 then
        stack.level:SetText(tostring(level))
    else
        stack.level:SetText("")
    end
end

-- TargetStrip: name, level, health, cast tick. The strip rests at 0 and the
-- target channel reveals it; this only fills it.
function Bars.UpdateTarget()
    if not Bars.Live() then return end
    if not (_G.UnitExists and _G.UnitExists("target")) then
        strip.name:SetText("")
        strip.level:SetText("")
        strip.number:SetText("")
        strip.health:SetValue(0)
        strip.cast:Hide()
        return
    end
    Guard.Send(strip.name, "SetText", _G.UnitName("target"))
    local level = _G.UnitLevel("target")
    if level ~= nil and Compat.IsSecret(level) then
        Guard.Send(strip.level, "SetFormattedText", "%d", level)
    elseif type(level) == "number" and level > 0 then
        strip.level:SetText(tostring(level))
    else
        strip.level:SetText("??")
    end
    Value(strip.health, Scalar("target", curves.frac))
    local pct = Scalar("target", curves.pct)
    if pct ~= nil then Guard.Send(strip.number, "SetFormattedText", "%d", pct) end
    if CastBarID("target") then strip.cast:Show() else strip.cast:Hide() end
end

function Bars.Refresh()
    if not Bars.Live() then return end
    Bars.UpdateHealth()
    Bars.UpdatePower()
    Bars.UpdateCast()
    Bars.UpdateTarget()
    Bars.UpdateIdentity()
    Bars.UpdateXP()
end

--- The harness's switch: while suspended nothing live reaches the bars, so a
-- shot does not depend on the health you happened to have.
function Bars.Suspend(on)
    Bars.suspended = on and true or false
    if on then Bars.Neutral() else Bars.Refresh() end
end

-- ---------------------------------------------------------------------------
-- The summon: RULES' fifth mechanism, narrowly licensed (SPEC 3)
-- ---------------------------------------------------------------------------
-- LowHealthFrame is Blizzard's own low-health flash. Its show/hide is a
-- plain boolean computed inside Blizzard's access; we watch it and claim
-- SelfStack. Threshold is Blizzard's 35%. If the player has turned the
-- warning off, the channel is unavailable and the escalation layers still
-- work; /myui audit says which.

function Bars.SummonAvailable()
    local frame = _G.LowHealthFrame
    if not frame then return false, "no LowHealthFrame on this client" end
    local get = _G.C_CVar and _G.C_CVar.GetCVarBool
    if get and get("doNotFlashLowHealthWarning") then
        return false, "the low-health warning is switched off (doNotFlashLowHealthWarning)"
    end
    return true
end

function Bars.HookSummon()
    local frame = _G.LowHealthFrame
    if not frame or Bars.summonHooked then return end
    frame:HookScript("OnShow", function() ns.Reveal.Claim("lowhealth", "SelfStack") end)
    frame:HookScript("OnHide", function() ns.Reveal.Release("lowhealth", "SelfStack") end)
    Bars.summonHooked = true
    if frame:IsShown() then ns.Reveal.Claim("lowhealth", "SelfStack") end
end

-- ---------------------------------------------------------------------------
-- Build and events
-- ---------------------------------------------------------------------------

local PLAYER_EVENTS = {
    "UNIT_HEALTH", "UNIT_MAXHEALTH",
    "UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER",
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_DELAYED",
    "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_CHANNEL_UPDATE",
    "UNIT_SPELLCAST_EMPOWER_START", "UNIT_SPELLCAST_EMPOWER_STOP", "UNIT_SPELLCAST_EMPOWER_UPDATE",
    "UNIT_NAME_UPDATE", "UNIT_LEVEL",
}

local function OnEvent(_, event, unit)
    if event == "PLAYER_XP_UPDATE" then
        Bars.UpdateXP()
        return
    end
    if event == "PLAYER_LEVEL_UP" or ((event == "UNIT_NAME_UPDATE" or event == "UNIT_LEVEL") and unit == "player") then
        Bars.UpdateIdentity()
        Bars.UpdateXP()
        return
    end
    if event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
        Bars.Refresh()
        return
    end
    if unit == "target" then
        Bars.UpdateTarget()
    elseif event:find("^UNIT_SPELLCAST") then
        Bars.UpdateCast()
    elseif event:find("^UNIT_.*POWER") then
        Bars.UpdatePower()
    else
        Bars.UpdateHealth()
    end
end

function Bars.OnLogin()
    local s = Registry.Get("SelfStack")
    local t = Registry.Get("TargetStrip")
    if not s or not t or stack then return end
    stack, strip = s.frame, t.frame
    Bars.BuildCurves()

    Whiten(stack.health, "fill")
    stack.health.wash = Wash(stack.health)
    steady = BuildSteadyLayer(stack)
    low = BuildLowLayer(stack)
    Whiten(low.health, "fill")
    low.health.wash = Wash(low.health)
    edge = BuildEdge()
    Bars.stack, Bars.low, Bars.steady, Bars.edge = stack, low, steady, edge

    local driver = CreateFrame("Frame", "MyUIBarsDriver", UIParent)
    Bars.driver = driver
    for _, event in ipairs(PLAYER_EVENTS) do
        if driver.RegisterUnitEvent then
            driver:RegisterUnitEvent(event, "player", "target")
        else
            driver:RegisterEvent(event)
        end
    end
    driver:RegisterEvent("PLAYER_TARGET_CHANGED")
    driver:RegisterEvent("PLAYER_LEVEL_UP")
    driver:RegisterEvent("PLAYER_XP_UPDATE")
    driver:RegisterEvent("PLAYER_ENTERING_WORLD")
    driver:SetScript("OnEvent", OnEvent)

    if Bars.SummonAvailable() then Bars.HookSummon() end
    Bars.Neutral()
    Bars.Refresh()
end
