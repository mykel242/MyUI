-- MyUI_Test :: Harness.lua
-- One job: run suites -- set a UI state, wait, take a screenshot, and write
-- down what was on screen where. Filing, diffing and approving the shots are
-- separate tools on the Mac (tools/), each with one job of its own.
--
-- Lives in the dev environment only. Never shipped, never a dependency of
-- anything but itself.
--
-- The flow, end to end:
--   1. The run key queues every suite in SavedVariables and reloads.
--   2. On load the queue is picked up, cleared (so a crash cannot loop), and
--      the suites run one test at a time, each ending in Screenshot().
--   3. Every shot's test name, time and frame rectangles go in a manifest.
--   4. When the last shot lands, the harness reloads once more. That reload is
--      what flushes the manifest to disk; tools/watch_shots.py is waiting on it.

local ADDON, T = ...
MyUI_Test = T

T.suites = {}

local MAX_RUNS = 5          -- manifests kept in SavedVariables
local SETTLE = 3.0          -- seconds after load before the first test
local DEFAULT_WAIT = 0.6    -- longer than MyUI's 260ms fade-out, with margin
local SHOT_TIMEOUT = 10
-- Screenshot file names carry the time to the second. Two shots in the same
-- second would collide, so consecutive shots are kept at least this far apart.
local SHOT_GAP = 1.2

-- ---------------------------------------------------------------------------
-- Suites
-- ---------------------------------------------------------------------------

--- Register a suite.
-- spec = {
--   title    = "...",
--   requires = function() return ok, why end,   -- optional; skip if not ok
--   before   = function(api) end,               -- optional, once
--   after    = function(api) end,               -- optional, once, always runs
--   tests    = { {
--       id      = "show-on",                    -- stable; names the file
--       what    = "what the shot should show",
--       setup   = function(api) end,
--       wait    = seconds,                      -- default DEFAULT_WAIT
--       frames  = { "GlobalName", ... } or function(api) return {name=frame,...} end,
--       check   = function(api) return ok, detail end,  -- optional
--       shot    = false,                        -- check-only test
--       teardown= function(api) end,
--   }, ... },
-- }
function T.Suite(name, spec)
    spec.name = name
    T.suites[#T.suites + 1] = spec
    return spec
end

-- ---------------------------------------------------------------------------
-- Saved state
-- ---------------------------------------------------------------------------

local function DB()
    if type(_G.MyUITestDB) ~= "table" then
        _G.MyUITestDB = {}
    end
    local db = _G.MyUITestDB
    db.runs = db.runs or {}
    return db
end

local function Print(msg)
    local frame = _G.DEFAULT_CHAT_FRAME
    if frame then
        frame:AddMessage("|cff8cc4ffMyUI_Test|r " .. tostring(msg))
    end
end
T.Print = Print

-- ---------------------------------------------------------------------------
-- Geometry
-- ---------------------------------------------------------------------------
-- Rectangles are stored normalised to the screen, origin top-left, so the Mac
-- side can crop any screenshot size without knowing the UI scale. The raw
-- numbers go in too, for debugging.

local function Number(v)
    if type(v) ~= "number" then return nil end
    if _G.issecretvalue and _G.issecretvalue(v) then return nil end
    return v
end

local function Call(frame, method)
    local fn = frame and frame[method]
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d = pcall(fn, frame)
    if not ok then return nil end
    return a, b, c, d
end

function T.Rect(frame)
    local l, b, w, h = Call(frame, "GetRect")
    l, b, w, h = Number(l), Number(b), Number(w), Number(h)
    local s = Number((Call(frame, "GetEffectiveScale")))
    local ui = _G.UIParent
    local us = Number((Call(ui, "GetEffectiveScale")))
    local sw, sh = Number(_G.GetScreenWidth and _G.GetScreenWidth()),
                   Number(_G.GetScreenHeight and _G.GetScreenHeight())
    if not (l and b and w and h and s and us and sw and sh) or sw <= 0 or sh <= 0 then
        return nil
    end
    local W, H = sw * us, sh * us
    local x0, y0 = l * s / W, b * s / H
    local nw, nh = w * s / W, h * s / H
    return {
        x = x0, y = 1 - (y0 + nh), w = nw, h = nh,   -- normalised, top-left origin
        raw = { l = l, b = b, w = w, h = h, scale = s },
    }
end

local function Describe(name, frame)
    local rec = { name = name }
    local rect = T.Rect(frame)
    if rect then
        rec.x, rec.y, rec.w, rec.h, rec.raw = rect.x, rect.y, rect.w, rect.h, rect.raw
    end
    rec.visible = (Call(frame, "IsVisible")) == true
    -- From Phase 4 an alpha can be secret; record nothing rather than guess.
    rec.alpha = Number((Call(frame, "GetEffectiveAlpha")))
    return rec
end

-- ---------------------------------------------------------------------------
-- The API a suite sees
-- ---------------------------------------------------------------------------

local api = {}
T.api = api

--- MyUI's namespace, handed over by MyUI when this addon loads.
function api.ns()
    return _G.MyUI_TestAPI
end

--- Run a /myui command exactly as typed.
function api.myui(text)
    local fn = _G.SlashCmdList and _G.SlashCmdList["MYUI"]
    if fn then fn(text) end
end

--- Run a /rebar command exactly as typed.
function api.rebar(text)
    local fn = _G.SlashCmdList and _G.SlashCmdList["REBAR"]
    if fn then fn(text) end
end

function api.loaded(addon)
    return _G.C_AddOns and _G.C_AddOns.IsAddOnLoaded
           and _G.C_AddOns.IsAddOnLoaded(addon) or false
end

--- Every frame in MyUI's registry, by registry name.
function api.registryFrames()
    local out = {}
    local ns = api.ns()
    if ns and ns.Registry then
        ns.Registry.Each(function(entry) out[entry.name] = entry.frame end)
    end
    return out
end

-- ---------------------------------------------------------------------------
-- The runner
-- ---------------------------------------------------------------------------
-- A coroutine. Wait() and WaitShot() yield; a timer or the screenshot event
-- resumes it. No OnUpdate: RULES reserves that for two named uses, and a
-- harness has no business adding a third even in a dev-only addon.

local driver = CreateFrame("Frame", "MyUITestDriver", UIParent)
local co, token, waitingShot, shotResult
local run           -- the manifest being written

local function Resume()
    if not co then return end
    local ok, err = coroutine.resume(co)
    if not ok then
        Print("|cfff26b61harness error:|r " .. tostring(err))
        if run then
            run.errors[#run.errors + 1] = "harness: " .. tostring(err)
        end
        co = nil
    elseif coroutine.status(co) == "dead" then
        co = nil
    end
end

-- Each wait gets a token, so a stale timer (a shot that answered before its
-- timeout) cannot resume a later wait.
local function After(seconds)
    token = (token or 0) + 1
    local mine = token
    C_Timer.After(seconds, function()
        if token == mine then Resume() end
    end)
end

local function Wait(seconds)
    After(seconds)
    coroutine.yield()
end

local function WaitShot()
    waitingShot, shotResult = true, nil
    After(SHOT_TIMEOUT)
    coroutine.yield()
    waitingShot = false
    return shotResult
end

driver:RegisterEvent("SCREENSHOT_SUCCEEDED")
driver:RegisterEvent("SCREENSHOT_FAILED")
driver:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_REGEN_ENABLED" then
        -- A run asked for in combat starts when combat ends.
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        if T.pending then
            local selected = T.pending
            T.pending = nil
            T.Start(selected)
        end
        return
    end
    if waitingShot then
        shotResult = event == "SCREENSHOT_SUCCEEDED" and "ok" or "failed"
        token = (token or 0) + 1      -- cancel the timeout
        -- Resume on the next frame rather than inside the event handler.
        C_Timer.After(0, Resume)
    end
end)

local function Protected(label, fn, ...)
    if not fn then return true end
    local ok, a, b = pcall(fn, ...)
    if not ok then
        run.errors[#run.errors + 1] = label .. ": " .. tostring(a)
        return false, tostring(a)
    end
    return true, a, b
end

local function FramesFor(test)
    local list = {}
    local spec = test.frames
    if type(spec) == "function" then
        local ok, got = pcall(spec, api)
        if ok and type(got) == "table" then
            for name, frame in pairs(got) do list[#list + 1] = { name, frame } end
        end
    elseif type(spec) == "table" then
        for _, name in ipairs(spec) do
            local frame = _G[name]
            if frame then list[#list + 1] = { name, frame } end
        end
    else
        for name, frame in pairs(api.registryFrames()) do
            list[#list + 1] = { name, frame }
        end
    end
    table.sort(list, function(a, b) return a[1] < b[1] end)
    local out = {}
    for _, pair in ipairs(list) do out[#out + 1] = Describe(pair[1], pair[2]) end
    return out
end

-- Things on screen that are not the HUD and would otherwise land in every
-- shot: Blizzard's "Screen captured" notice, a quest NPC's talking head (it
-- covered TargetStrip in the first in-game run), Rebar's grid (persisted
-- user state; the Rebar suite raises it for its own tests), and our own
-- windows. Alpha only, restored afterwards -- none of these is protected.
local QUIET = { "ActionStatus", "TalkingHeadFrame", "RebarGrid", "MyUITestWindow", "MyUICopy" }
local quieted = {}

local function Quiet(on)
    for _, name in ipairs(QUIET) do
        local f = _G[name]
        if f and f.SetAlpha then
            if on then
                quieted[name] = f:GetAlpha()
                f:SetAlpha(0)
            elseif quieted[name] then
                f:SetAlpha(quieted[name])
            end
        end
    end
    if not on then quieted = {} end
end

local function Stamp()
    return date("%Y-%m-%d %H:%M:%S")
end

local function NewRun(selected)
    local pw, ph = GetPhysicalScreenSize()
    local version, build = GetBuildInfo()
    local ns = api.ns()
    local uiScale = _G.C_CVar and _G.C_CVar.GetCVar and _G.C_CVar.GetCVar("uiScale")
    return {
        id = date("%Y%m%d-%H%M%S"),
        started = time(), startedText = Stamp(),
        build = tostring(version) .. "." .. tostring(build),
        myui = ns and ns.version or "?",
        phase = ns and ns.phase or nil,
        screen = {
            physical = { w = pw, h = ph },
            units = { w = GetScreenWidth(), h = GetScreenHeight() },
            uiScale = tonumber(uiScale),
            effectiveScale = UIParent:GetEffectiveScale(),
        },
        format = _G.C_CVar and _G.C_CVar.GetCVar and _G.C_CVar.GetCVar("screenshotFormat") or "?",
        suites = selected,
        shots = {}, checks = {}, skipped = {}, errors = {},
        finished = false,
    }
end

local lastShotAt = 0

local function RunTest(suite, test)
    local key = suite.name .. "/" .. test.id
    Protected(key .. " setup", test.setup, api)
    Wait(test.wait or DEFAULT_WAIT)

    local check
    if test.check then
        local ok, passed, detail = pcall(test.check, api)
        if not ok then
            check = { ok = false, detail = "check errored: " .. tostring(passed) }
        else
            check = { ok = passed and true or false, detail = detail and tostring(detail) or nil }
        end
        run.checks[#run.checks + 1] = { suite = suite.name, test = test.id, ok = check.ok, detail = check.detail }
    end

    if test.shot ~= false then
        local gap = SHOT_GAP - (GetTime() - lastShotAt)
        if gap > 0 then Wait(gap) end
        local frames = FramesFor(test)
        local before = time()
        Screenshot()
        local result = WaitShot()
        lastShotAt = GetTime()
        run.shots[#run.shots + 1] = {
            n = #run.shots + 1,
            suite = suite.name, test = test.id, what = test.what,
            before = before, after = time(),
            result = result or "timeout",
            frames = frames,
            check = check,
        }
    end

    Protected(key .. " teardown", test.teardown, api)
end

local function RunSuites(selected)
    local db = DB()
    run = NewRun(selected)
    table.insert(db.runs, 1, run)
    while #db.runs > MAX_RUNS do table.remove(db.runs) end

    Print(("run %s: %d suite(s)"):format(run.id, #selected))
    Quiet(true)
    local ns = api.ns()
    if ns and ns.Reveal then ns.Reveal.cursorSuspended = true end

    for _, name in ipairs(selected) do
        local suite
        for _, s in ipairs(T.suites) do
            if s.name == name then suite = s end
        end
        if not suite then
            run.skipped[#run.skipped + 1] = { suite = name, why = "no such suite" }
        else
            local ok, why = true, nil
            if suite.requires then
                local pok, a, b = pcall(suite.requires, api)
                ok, why = pok and a, pok and b or tostring(a)
            end
            if not ok then
                run.skipped[#run.skipped + 1] = { suite = name, why = why or "requirement not met" }
                Print(("skip %s: %s"):format(name, why or "requirement not met"))
            else
                Print(("suite %s (%d tests)"):format(name, #suite.tests))
                Protected(name .. " before", suite.before, api)
                for _, test in ipairs(suite.tests) do
                    RunTest(suite, test)
                end
                Protected(name .. " after", suite.after, api)
            end
        end
    end

    if ns and ns.Reveal then ns.Reveal.cursorSuspended = false end
    Quiet(false)

    run.finished = true
    run.finishedAt = time()
    local failed = 0
    for _, c in ipairs(run.checks) do if not c.ok then failed = failed + 1 end end
    Print(("done: %d shots, %d checks (%d failed), %d errors -- reloading to save"):format(
        #run.shots, #run.checks, failed, #run.errors))

    -- The reload is what writes the manifest to disk.
    Wait(1.5)
    ReloadUI()
end

function T.SuiteNames()
    local out = {}
    for _, s in ipairs(T.suites) do out[#out + 1] = s.name end
    return out
end

--- Start a run now, in this session.
function T.Start(selected)
    if co then
        Print("a run is already in progress")
        return
    end
    if InCombatLockdown() then
        Print("in combat -- the run will start when combat ends")
        driver:RegisterEvent("PLAYER_REGEN_ENABLED")
        T.pending = selected
        return
    end
    co = coroutine.create(function()
        Wait(SETTLE)
        RunSuites(selected)
    end)
    Resume()
end

--- Queue a run and reload: the run key. A clean UI is the baseline, so every
-- run starts from a fresh load rather than from whatever state was on screen.
function T.Queue(selected)
    local db = DB()
    db.queued = { suites = selected or T.SuiteNames(), at = time() }
    ReloadUI()
end

function MyUI_Test_Run()
    T.Queue(nil)
end

_G.BINDING_HEADER_MYUITEST = "MyUI Test"
_G.BINDING_NAME_MYUI_TEST_RUN = "Run every suite (reloads)"

-- ---------------------------------------------------------------------------
-- Load
-- ---------------------------------------------------------------------------

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_ENTERING_WORLD")
loader:SetScript("OnEvent", function(self, event)
    self:UnregisterEvent(event)
    local db = DB()
    local queued = db.queued
    if queued then
        -- Cleared before anything runs: if a test crashes the client, the next
        -- load must not start the same run again.
        db.queued = nil
        T.Start(queued.suites)
    end
end)

-- ---------------------------------------------------------------------------
-- Slash: /myuitest [run [suite ...] | list | last]
-- ---------------------------------------------------------------------------

SLASH_MYUITEST1 = "/myuitest"
SlashCmdList["MYUITEST"] = function(input)
    local words = {}
    for w in (input or ""):gmatch("%S+") do words[#words + 1] = w end
    local cmd = table.remove(words, 1) or "help"
    if cmd == "run" then
        T.Queue(#words > 0 and words or nil)
    elseif cmd == "list" then
        for _, s in ipairs(T.suites) do
            Print(("%s -- %s (%d tests)"):format(s.name, s.title or "", #s.tests))
        end
    elseif cmd == "last" then
        local r = DB().runs[1]
        if not r then Print("no runs yet") return end
        Print(("%s: %d shots, %d checks, %d errors, finished %s"):format(
            r.id, #r.shots, #r.checks, #r.errors, tostring(r.finished)))
    else
        Print("/myuitest run [suite ...] | list | last -- or bind MyUI Test > Run every suite")
    end
end
