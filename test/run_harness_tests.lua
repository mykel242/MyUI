-- MyUI_Test harness, offline. Run: cd test && luajit run_harness_tests.lua
--
-- Drives a whole queued run through the mock: load, settle, every suite, every
-- screenshot, the closing reload. What it cannot test is the client itself --
-- whether Screenshot() and ReloadUI() behave as documented -- and that is what
-- the first in-game run is for.
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

-- ---------------------------------------------------------------------------
-- The client surface the harness uses, beyond what MyUI's tests need
-- ---------------------------------------------------------------------------

local shots, reloads = {}, 0
_G.time = function() return math.floor(mock.time) end
_G.GetScreenWidth = function() return 5120 / 3 end     -- 3 px per unit
_G.GetScreenHeight = function() return 2880 / 3 end
_G.C_CVar = { GetCVar = function(name)
    return ({ uiScale = "0.8", screenshotFormat = "png" })[name]
end }
_G.ReloadUI = function() reloads = reloads + 1 end
local loaded = { MyUI = true, MyUI_Test = true }
_G.C_AddOns.IsAddOnLoaded = function(name) return loaded[name] == true end

local driver
_G.Screenshot = function()
    shots[#shots + 1] = mock.time
    -- The client confirms asynchronously; a tenth of a second is plenty.
    _G.C_Timer.After(0.1, function() driver:Fire("SCREENSHOT_SUCCEEDED") end)
end

-- ---------------------------------------------------------------------------
-- Load MyUI, then the harness, the way the client would
-- ---------------------------------------------------------------------------

local ns = mock.loadAddon("../MyUI")
local myuiFrames = #mock.created
for i = 1, myuiFrames do
    mock.created[i]:Fire("ADDON_LOADED", "MyUI")
end
for i = 1, myuiFrames do
    mock.created[i]:Fire("PLAYER_LOGIN")
end

-- Give the registry frames real rects, in UI units, so geometry is recorded.
local placed = 0
ns.Registry.Each(function(entry)
    placed = placed + 1
    mock.place(entry.frame, 100 * placed, 100, 100 * placed + 80, 140)
    entry.frame:Show()
end)

-- Blizzard's frames that R3b adopts, and a PlayerFrame for the probe.
for _, spec in ipairs(ns.Clear.ADOPT) do
    _G[spec[2]] = mock.frame({ name = spec[2] })
end
do
    local rolesets = "unitFrames"
    local player = mock.frame({ name = "PlayerFrame" })
    player.SetRolesets = function(_, r) rolesets = r end
    player.IsRolesetFiltered = function() return rolesets == "myuiCleared" end
    player.IsVisible = function() return rolesets ~= "myuiCleared" end
    _G.PlayerFrame = player
end
for _, name in ipairs({ "TargetFrame", "FocusFrame" }) do
    _G[name] = mock.frame({ name = name, shown = true })
end
_G.MyUIClearDriver:Fire("PLAYER_ENTERING_WORLD")

local T = mock.loadAddon("../MyUI_Test", "MyUI_Test")
for i = 1, #mock.created do
    mock.created[i]:Fire("ADDON_LOADED", "MyUI_Test")
end
driver = _G.MyUITestDriver

print("== Seam")
check("MyUI hands its namespace to MyUI_Test", _G.MyUI_TestAPI == ns)
check("the harness sees it", T.api.ns() == ns)
check("suites registered", #T.suites >= 5, #T.suites)

-- ---------------------------------------------------------------------------
-- A queued run, start to finish
-- ---------------------------------------------------------------------------

print("== A run, start to finish")
_G.MyUITestDB = {}
_G.MyUI_Test_Run()            -- the key

local guard = 0
local function current() return _G.MyUITestDB.runs and _G.MyUITestDB.runs[1] end
while not (current() and current().finished) and guard < 4000 do
    mock.advance(ns, 0.05)
    guard = guard + 1
end
check("the run does not try to reload itself (blocked on 12.1.5)", reloads == 0, reloads)
check("it asks for the saving press instead", _G.MyUITestPrompt and _G.MyUITestPrompt:IsShown())
_G.MyUI_Test_Run()            -- the key again
check("the second press reloads, which saves", reloads == 1, reloads)

local run = _G.MyUITestDB.runs and _G.MyUITestDB.runs[1]
check("a run was recorded", run ~= nil)
check("it finished", run and run.finished)
check("no harness errors", run and #run.errors == 0, run and table.concat(run.errors, " | "))

local skippedNames = {}
for _, sk in ipairs(run and run.skipped or {}) do skippedNames[sk.suite] = true end
local expected = 0
for _, s in ipairs(T.suites) do
    if not skippedNames[s.name] then
        for _, t in ipairs(s.tests) do
            if t.shot ~= false then expected = expected + 1 end
        end
    end
end
check("one screenshot per shot test", run and #run.shots == expected and #shots == expected,
      run and ("%d recorded, %d taken, %d expected"):format(#run.shots, #shots, expected))

local ok = true
for _, s in ipairs(run and run.shots or {}) do
    if s.result ~= "ok" then ok = false end
end
check("every screenshot confirmed", ok)

local apart = true
for i = 2, #shots do
    if shots[i] - shots[i - 1] < 1.0 then apart = false end
end
check("shots at least a second apart (file names are per second)", apart)

local distinct = {}
for _, s in ipairs(run and run.shots or {}) do distinct[s.before] = true end
local n = 0
for _ in pairs(distinct) do n = n + 1 end
check("every shot has its own timestamp window", run and n == #run.shots, n)

check("Rebar suite skipped when Rebar is not loaded", skippedNames.rebar == true)
check("the history suite skipped with extras off (MVP)", skippedNames["myui-history"] == true)
check("  and nothing else skipped", (function()
    local n = 0
    for _ in pairs(skippedNames) do n = n + 1 end
    return n == 2, n
end)())

-- Geometry: SelfStack placed at x=100..180, y=100..140 units on a 1706.67 x 960
-- unit screen (in mock terms the scale cancels out).
local first = run and run.shots[1]
local rec
for _, f in ipairs(first and first.frames or {}) do
    if f.x then rec = rec or f end
end
check("frames carry normalised rects", rec ~= nil and rec.x > 0 and rec.x < 1
      and rec.y > 0 and rec.y < 1 and rec.w > 0 and rec.h > 0)
check("screen recorded for the shape", run and run.screen.physical.w == 5120
      and run.screen.physical.h == 2880)

local failedChecks = {}
for _, c in ipairs(run and run.checks or {}) do
    if not c.ok then failedChecks[#failedChecks + 1] = c.suite .. "/" .. c.test .. ": " .. tostring(c.detail) end
end
check("every in-run check passes against the mock", #failedChecks == 0, table.concat(failedChecks, " | "))

local worldShots, backdropShots = 0, 0
for _, s in ipairs(run and run.shots or {}) do
    if s.world then worldShots = worldShots + 1 else backdropShots = backdropShots + 1 end
end
check("shots over the backdrop by default, the world only where asked",
      worldShots == 1 and backdropShots == #run.shots - 1, ("%d world, %d backdrop"):format(worldShots, backdropShots))
check("backdrop hidden after the run", _G.MyUITestBackdrop and not _G.MyUITestBackdrop:IsShown())

check("cursor proximity handed back after the run", ns.Reveal.cursorSuspended == false)
check("nothing left forced", not ns.Registry.forced)

-- ---------------------------------------------------------------------------

print("")
print(("%d checks, %d failures"):format(checks, failures))
os.exit(failures == 0 and 0 or 1)
