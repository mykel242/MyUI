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

-- SPEC.md 3, the health fill curve, verbatim.
local HEALTH_STOPS = {
    { 100, { 240/255, 241/255, 243/255, 0.92 } },
    {  58, { 242/255, 214/255, 150/255, 0.92 } },
    {  34, { 242/255, 170/255, 120/255, 0.92 } },
    {  17, { 242/255, 120/255, 100/255, 0.94 } },
    {   6, { 242/255,  86/255,  80/255, 1.00 } },
}

local curve, err = Guard.ColorCurve(HEALTH_STOPS)
check("ColorCurve builds from spec stops", curve ~= nil, err)
check("  with all five stops", curve and curve:GetPointCount() == 5)
check("  and no secret flag before use", curve and curve:HasSecretValues() == false)

local colour = Guard.HealthThrough("player", curve)
check("HealthThrough returns a value", colour ~= nil)
check("  which is secret", Compat.IsSecret(colour))
check("  and flags the curve as having seen one", curve:HasSecretValues() == true)

-- The full sanctioned path, end to end, with nothing inspected in between.
local health = mock.frame({ name = "HealthFill" })
Guard.Reset()
check("curve output forwards into SetVertexColor",
      Guard.Send(health, "SetVertexColor", colour))
check("  counted as a forward", Guard.forwards == 1)
check("  frame now carries the alpha aspect", health.__secretAspect == true)

-- ---------------------------------------------------------------------------
section("Registry")
-- ---------------------------------------------------------------------------

Registry.Add("SelfStack", mock.frame({ name = "SelfStack" }), 0.35)
Registry.Add("Rail", mock.frame({ name = "Rail" }), 0.14)
check("frames register", Registry.Count() == 2, Registry.Count())
check("lookup by name works", Registry.Get("Rail").resting == 0.14)

Registry.Add("Rail", mock.frame({}), 0.99)
check("duplicate name is refused", Registry.Count() == 2)
check("  and the original alpha survives", Registry.Get("Rail").resting == 0.14)

local snap = Registry.Snapshot()
check("snapshot covers every frame", #snap == 2)
check("  carries the spec resting alpha", snap[1].resting == 0.35)
check("  and reports no claim at rest", snap[1].claim == "-")

-- A frame that has been forwarded a secret returns a secret alpha; the audit
-- must show a sentinel rather than throw on it.
Registry.Add("Tainted", health, 0.25)
snap = Registry.Snapshot()
check("secret alpha reads back as a sentinel",
      snap[3].current == Compat.SECRET, tostring(snap[3].current))

-- ---------------------------------------------------------------------------
section("Core -- saved variables")
-- ---------------------------------------------------------------------------

check("database was created", type(_G.MyUIDB) == "table")
check("  at the current schema", _G.MyUIDB.schema == ns.SCHEMA_VERSION)
check("  recording the phase", _G.MyUIDB.addon.phase == 0)
check("  with an alpha table for phase 5", type(_G.MyUIDB.alpha) == "table")
check("no migrations needed at schema 1", next(ns.MIGRATIONS) == nil)

ns.ClearOutput()
ns.Print("hello")
check("output is captured", ns.GetOutput():find("hello", 1, true) ~= nil)
check("  with colour codes stripped", ns.GetOutput():find("|cff", 1, true) == nil)

-- ---------------------------------------------------------------------------
section("Commands")
-- ---------------------------------------------------------------------------

local run = _G.SlashCmdList["MYUI"]
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

local probe = output("conditionals")
check("probe runs the control first", probe:find("%[combat%]") ~= nil)
check("  reports the health candidates", probe:find("hp<20", 1, true) ~= nil)
check("  and explains what a miss means", probe:find("cross%-fade") ~= nil)

mock.inCombat = true
probe = output("conditionals")
check("control tracks combat state", probe:find("%[combat%] hit; miss%s*%->%s*hit") ~= nil)
mock.inCombat = false

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
print("")
print(("%d checks, %d failures"):format(checks, failures))
os.exit(failures == 0 and 0 or 1)
