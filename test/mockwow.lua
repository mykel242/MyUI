-- Minimal WoW 12.1 mock for MyUI's offline tests.
--
-- Two things it models that a naive mock would not, and both matter:
--
--   1. Secrets THROW on arithmetic, concat, compare and tostring, so an
--      accidental inspection shows up as a real failure rather than passing
--      silently.
--   2. Setters enforce the AllowedWhenTainted / AllowedWhenUntainted split
--      from API-NOTES-12.1.md 2. SetScale and SetColorFill refuse a secret
--      exactly as the live client does. Without this the guard's refusals
--      would be untested opinions.
--
-- A mock's defaults are assertions about the real system. Every behaviour here
-- is traceable to a citation in API-NOTES-12.1.md.

local M = {}

local unpk = table.unpack or unpack

local secretSet = setmetatable({}, { __mode = "k" })

local function boom(op)
    return function()
        error("attempt to " .. op .. " a secret value", 2)
    end
end

local secretMT = {
    __add = boom("add"), __sub = boom("subtract"), __mul = boom("multiply"),
    __div = boom("divide"), __mod = boom("mod"), __pow = boom("pow"),
    __unm = boom("negate"), __concat = boom("concatenate"),
    __lt = boom("compare"), __le = boom("compare"),
    __tostring = boom("tostring"),
    __index = boom("index"),
}

function M.secret()
    local s = setmetatable({}, secretMT)
    secretSet[s] = true
    return s
end

function M.isSecret(v)
    return secretSet[v] == true
end

-- ---------------------------------------------------------------------------
-- Setter secrecy rules -- API-NOTES-12.1.md 2
-- ---------------------------------------------------------------------------

-- SecretArguments = "AllowedWhenTainted": an addon may pass a secret.
local ACCEPTS_SECRET = {
    SetAlpha = true, SetVertexColor = true, SetValue = true,
    -- Phase 4: SimpleFontStringAPIDocumentation.lua 539 / 664 / 675.
    SetText = true, SetFormattedText = true, SetTextColor = true,
}

-- SecretArguments = "AllowedWhenUntainted": passing a secret from an addon is
-- a blocked action. The live client errors; so does this.
local REFUSES_SECRET = {
    SetScale = true, SetColorFill = true, SetTimerDuration = true,
}

local function anySecret(...)
    for i = 1, select("#", ...) do
        if secretSet[(select(i, ...))] then
            return true
        end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Frames
-- ---------------------------------------------------------------------------

function M.frame(spec)
    spec = spec or {}
    local f = {}
    f.__spec  = spec
    f.__calls = {}      -- ordered log of every setter that landed
    f.__alpha = spec.alpha or 1

    local function log(method, ...)
        f.__calls[#f.__calls + 1] = { method = method, n = select("#", ...), ... }
    end

    local function setter(method)
        return function(_, ...)
            if method == "SetSize" then
                f.__w, f.__h = ...
            elseif method == "SetWidth" then
                f.__w = ...
            elseif method == "SetHeight" then
                f.__h = ...
            elseif method == "SetPoint" then
                -- Points by anchor, as the client keeps them: setting one
                -- again replaces it, a different one adds a second.
                local pt = { ... }
                f.__points = f.__points or {}
                local at = #f.__points + 1
                for i, q in ipairs(f.__points) do if q[1] == pt[1] then at = i end end
                f.__points[at] = pt
                f.__point = f.__points[1]
            elseif method == "ClearAllPoints" then
                f.__points, f.__point = nil, nil
            elseif method == "EnableMouse" then
                f.__mouse = (...) and true or false
            elseif method == "SetFrameStrata" then
                f.__strata = ...
            end
            if anySecret(...) then
                if REFUSES_SECRET[method] then
                    error(("blocked action: %s does not accept a secret from an addon"):format(method), 2)
                end
                if not ACCEPTS_SECRET[method] then
                    error(("blocked action: %s is not documented to accept a secret"):format(method), 2)
                end
                f.__secretAspect = true
            end
            log(method, ...)
            return true
        end
    end

    for _, method in ipairs({
        "SetAlpha", "SetVertexColor", "SetValue", "SetScale", "SetColorFill",
        "SetPoint", "SetSize", "SetWidth", "SetHeight", "SetReverseFill",
        "Show", "Hide", "SetStatusBarTexture",
    }) do
        f[method] = setter(method)
    end

    f.GetAlpha = function()
        -- A frame we have forwarded a secret into carries SecretAspect.Alpha,
        -- so reading the alpha back returns a secret from then on.
        if f.__secretAspect then return M.secret() end
        local calls = f.__calls
        for i = #calls, 1, -1 do
            if calls[i].method == "SetAlpha" then return calls[i][1] end
        end
        return f.__alpha
    end

    -- Widget surface used by Copy.lua's window. These are no-ops that record
    -- the call, not stubs that pretend success -- a test asserting on them
    -- fails honestly if the real method is spelled differently.
    for _, method in ipairs({
        "SetFrameStrata", "SetFrameLevel", "EnableMouse", "SetMovable", "RegisterForDrag",
        "SetClampedToScreen", "SetMultiLine", "SetAutoFocus", "SetFontObject",
        "SetCursorPosition", "SetFocus", "HighlightText", "SetScrollChild",
        "SetAllPoints", "SetColorTexture", "SetText", "StartMoving",
        "StopMovingOrSizing", "SetJustifyH", "SetJustifyV", "AddMaskTexture", "SetRotation", "SetMinMaxValues", "SetFont",
        "SetTextColor", "SetStatusBarTexture", "SetDrawLayer",
        "SetDuration", "SetFromAlpha", "SetToAlpha", "SetOffset", "SetOrder",
        "SetShadowColor", "SetShadowOffset",
        "SetSmoothing", "ClearAllPoints", "SetWordWrap",
        -- Chat.lua's edit box.
        "SetTextInsets", "SetMaxLetters", "ClearFocus",
        -- Phase 4.
        "SetFormattedText", "SetTimerDuration", "SetLooping", "SetReverseFill",
        -- Round 004.
        "SetAtlas", "RegisterForClicks", "SetScale", "SetGradient", "SetClipsChildren", "SetTexture",
    }) do
        f[method] = setter(method)
    end

    f.__shown = spec.shown or false
    f.Show    = function() f.__shown = true;  log("Show") end
    f.Hide    = function() f.__shown = false; log("Hide") end
    f.IsShown = function() return f.__shown end

    f.GetText = function()
        local calls = f.__calls
        for i = #calls, 1, -1 do
            if calls[i].method == "SetText" then return calls[i][1] end
        end
        return nil
    end

    f.CreateAnimationGroup = function()
        local group = M.frame({ objectType = "AnimationGroup" })
        group.__animations = {}
        group.__playing = false
        group.CreateAnimation = function(_, kind)
            local anim = M.frame({ objectType = kind })
            anim.__kind = kind
            group.__animations[#group.__animations + 1] = anim
            return anim
        end
        group.Play = function() group.__playing = true end
        group.Stop = function() group.__playing = false end
        group.IsPlaying = function() return group.__playing end
        group.SetScript = function(_, name, fn) group.scripts[name] = fn end
        group.Finish = function()
            group.__playing = false
            if group.scripts.OnFinished then group.scripts.OnFinished(group) end
        end
        return group
    end

    f.CreateTexture    = function(...) return M.frame({ objectType = "Texture" }) end
    f.CreateMaskTexture = function(...) return M.frame({ objectType = "MaskTexture" }) end
    f.CreateFontString = function(...) return M.frame({ objectType = "FontString" }) end

    -- Geometry. SetSize/SetPoint are recorded like any other setter; these read
    -- the last one back so tests can assert against SPEC.md rather than against
    -- the order the calls happened to be made in.
    f.GetWidth  = function() return f.__w or 0 end
    f.GetHeight = function() return f.__h or 0 end
    f.GetSize   = function() return f.__w or 0, f.__h or 0 end
    f.IsMouseEnabled = function() return f.__mouse == true end
    -- Set by a test: is the pointer over this frame?
    f.IsMouseOver = function() return f.__over == true end
    f.GetNumPoints = function() return f.__points and #f.__points or 0 end
    f.GetPoint = function(_, i)
        local p = f.__points and f.__points[i or 1]
        if not p then return end
        return p[1], p[2], p[3], p[4], p[5]
    end

    f.GetStatusBarTexture = function() return f.__texture end
    f.GetLeft   = function() return f.__rect and f.__rect[1] end
    f.GetBottom = function() return f.__rect and f.__rect[2] end
    f.GetRight  = function() return f.__rect and f.__rect[3] end
    f.GetTop    = function() return f.__rect and f.__rect[4] end
    -- What the screenshot harness reads: a rect, the effective scale and
    -- visibility. GetRect is nil until a test places the frame, as the
    -- client's is until layout has run.
    f.GetRect = function()
        local r = f.__rect
        if not r then return nil end
        return r[1], r[2], r[3] - r[1], r[4] - r[2]
    end
    f.GetEffectiveScale = function() return M.uiScale or 0.8 end
    f.IsVisible = function() return f.__shown end
    f.GetEffectiveAlpha = function() return f.GetAlpha() end
    f.GetFrameStrata = function() return f.__strata or "MEDIUM" end
    f.GetFrameLevel  = function() return f.__level or 1 end
    f.GetObjectType = function() return spec.objectType or "Frame" end

    -- Parentage. Chat.lua stows Blizzard's chat frames under a hidden parent
    -- rather than hiding them, because a hidden ChatFrame1 reports IsShown()
    -- false and ChooseBoxForSend branches on that.
    f.__parent = spec.parent
    f.SetParent = function(_, parent) f.__parent = parent; log("SetParent", parent) end
    f.GetParent = function() return f.__parent end

    f.GetName = function() return spec.name end

    f.scripts = {}
    f.RegisterEvent   = function(...) end
    f.UnregisterEvent = function() end
    f.UnregisterAllEvents = function() f.__unregisteredAll = true end
    f.GetChildren = function() return end
    f.SetScript = function(_, name, fn) f.scripts[name] = fn end
    -- A button's click, as the client runs it: its OnClick with the button.
    f.Click = function(self, button)
        if f.scripts.OnClick then f.scripts.OnClick(self, button or "LeftButton") end
    end
    f.HookScript = function(_, name, fn)
        local prev = f.scripts[name]
        f.scripts[name] = function(...)
            if prev then prev(...) end
            fn(...)
        end
    end
    -- Secure attributes (Actions.lua). SetAttribute fires OnAttributeChanged
    -- as the client does; frame refs are just a table on the header.
    f.__attrs, f.__refs = {}, {}
    f.SetAttribute = function(_, name, value)
        f.__attrs[name] = value
        log("SetAttribute", name, value)
        local fn = f.scripts.OnAttributeChanged
        if fn then fn(f, name, value) end
    end
    f.GetAttribute = function(_, name) return f.__attrs[name] end
    f.SetFrameRef = function(_, name, ref) f.__refs[name] = ref end
    f.GetFrameRef = function(_, name) return f.__refs[name] end
    -- SecureHandler templates: Execute runs a body as `self`, and the
    -- restricted handle's binding methods land in M.overrides.
    f.Execute = function(_, body)
        local chunk = assert((loadstring or load)(body, "=Execute"))
        setfenv(chunk, setmetatable({ self = f }, { __index = { tonumber = tonumber } }))
        chunk()
    end
    f.ClearBindings = function() _G.ClearOverrideBindings(f) end
    f.SetBindingClick = function(_, priority, key, name) _G.SetOverrideBindingClick(f, priority, key, name) end
    f.Fire = function(_, event, ...)
        local fn = f.scripts.OnEvent
        if fn then return fn(f, event, ...) end
    end

    return f
end

--- Advance the clock and run one reveal tick, the way the client's OnUpdate
-- would. Tests call this instead of sleeping.
function M.advance(ns, seconds, steps)
    steps = steps or 1
    for _ = 1, steps do
        M.time = M.time + (seconds / steps)
        M.runTimers()
        ns.Reveal.Tick()
    end
end

--- Put a frame at an explicit rectangle, in UI units.
-- The mock does not implement WoW's layout engine and should not pretend to:
-- proximity tests need exact rects, so they state them.
function M.place(frame, l, b, r, t)
    frame.__rect = { l, b, r, t }
end

--- Count how many times a setter landed on a frame.
function M.countCalls(frame, method)
    local n = 0
    for _, c in ipairs(frame.__calls) do
        if c.method == method then n = n + 1 end
    end
    return n
end

-- ---------------------------------------------------------------------------
-- Globals
-- ---------------------------------------------------------------------------

function M.install()
    _G.issecretvalue = function(v) return secretSet[v] == true end

    _G.Enum = {
        SecretAspect = { ObjectSecurity = 1, Alpha = 2, VertexColor = 3, Scale = 4, BarValue = 5 },
        -- LuaCurveObjectConstantsDocumentation.lua
        LuaCurveType = { Linear = 0, Step = 1, Cosine = 2, Cubic = 3 },
        AddOnRestrictionType  = { Combat = 0, Encounter = 1, ChallengeMode = 2, PvPMatch = 3 },
        AddOnRestrictionState = { Inactive = 0, Activating = 1, Active = 2 },
    }

    -- Edit Mode, as far as R3b uses it: a saved-layout list (presets are not
    -- in it), an active index that counts the two presets first, and the
    -- enums. M.editMode records what was saved and selected.
    M.editMode = { saved = nil, active = nil }
    _G.Enum.EditModeSystem = { ActionBar = 0, UnitFrame = 3, AuraFrame = 5, HudTooltip = 11,
        ExtraAbilities = 12, StatusTrackingBar = 15, CooldownViewer = 20 }
    _G.Enum.EditModeStatusTrackingBarSystemIndices = { StatusTrackingBar1 = 1, StatusTrackingBar2 = 2 }
    _G.Enum.EditModeAuraFrameSystemIndices = { BuffFrame = 1, DebuffFrame = 2 }
    _G.Enum.EditModeAuraFrameSetting = { Orientation = 0, IconWrap = 1, IconDirection = 2,
        IconLimitBuffFrame = 3, IconLimitDebuffFrame = 4, IconSize = 5, IconPadding = 6, ShowDispelType = 9 }
    _G.Enum.AuraFrameOrientation = { Horizontal = 0, Vertical = 1 }
    _G.Enum.AuraFrameIconDirection = { Down = 0, Left = 0, Right = 1, Up = 1 }
    _G.Enum.AuraFrameIconWrap = { Down = 0, Left = 0, Right = 1, Up = 1 }
    _G.Enum.EditModeCooldownViewerSetting = { Orientation = 0, IconLimit = 1, IconDirection = 2,
        IconSize = 3, IconPadding = 4, Opacity = 5, VisibleSetting = 6 }
    _G.Enum.EditModeCooldownViewerSystemIndices = { Essential = 1, Utility = 2, BuffIcon = 3, BuffBar = 4 }
    _G.Enum.CooldownViewerVisibleSetting = { Always = 0, InCombat = 1, Hidden = 2 }
    _G.Enum.CooldownViewerOrientation = { Horizontal = 0, Vertical = 1 }
    _G.Enum.CooldownViewerIconDirection = { Left = 0, Right = 1 }
    _G.Enum.EditModeActionBarSetting = { Orientation = 0, VisibleSetting = 6 }
    _G.Enum.EditModeActionBarSystemIndices = { MainBar = 1, Bar2 = 2, Bar3 = 3, StanceBar = 11, PetActionBar = 12 }
    _G.Enum.ActionBarVisibleSetting = { Always = 0, InCombat = 1, OutOfCombat = 2, Hidden = 3 }
    _G.Enum.EditModeLayoutType = { Preset = 0, Account = 1, Character = 2, Server = 3 }
    _G.Enum.EditModePresetLayoutsMeta = { NumValues = 2 }
    M.layouts = {
        layouts = {
            { layoutName = "XYZ - Ultra", layoutType = 1, systems = {
                { system = 0, systemIndex = 1, settings = { { setting = 0, value = 0 } } },
                { system = 0, systemIndex = 2, settings = { { setting = 6, value = 0 } } },
                { system = 0, systemIndex = 3, settings = { { setting = 6, value = 0 } } },
                { system = 3, systemIndex = 1, settings = { { setting = 6, value = 0 } } },
                { system = 0, systemIndex = 11, settings = {} },
                { system = 0, systemIndex = 12, settings = {} },
                { system = 20, systemIndex = 1, settings = { { setting = 6, value = 1 } } },
                { system = 20, systemIndex = 2, settings = { { setting = 6, value = 1 } } },
                { system = 20, systemIndex = 3, settings = { { setting = 6, value = 1 } } },
                { system = 20, systemIndex = 4, settings = { { setting = 6, value = 0 } } },
                { system = 5, systemIndex = 2, settings = {} },
                { system = 5, systemIndex = 1, settings = {} },
                { system = 12, settings = {} },
                { system = 15, systemIndex = 1, settings = {} },
                { system = 15, systemIndex = 2, settings = {} },
                { system = 11, settings = {} },
            } },
            { layoutName = "Alt", layoutType = 2, systems = {} },
        },
        activeLayout = 3,
    }
    local function copy(t)
        if type(t) ~= "table" then return t end
        local o = {}
        for k, v in pairs(t) do o[k] = copy(v) end
        return o
    end
    _G.C_EditMode = {
        GetLayouts = function() return copy(M.layouts) end,
        SaveLayouts = function(info) M.layouts = copy(info); M.editMode.saved = copy(info) end,
        SetActiveLayout = function(i) M.layouts.activeLayout = i; M.editMode.active = i end,
    }
    _G.hooksecurefunc = function(obj, method, fn)
        if type(obj) == "string" then obj, method, fn = _G, obj, method end
        local orig = obj[method]
        obj[method] = function(...)
            local r = { orig(...) }
            fn(...)
            return unpack(r)
        end
    end

    _G.GetBuildInfo = function() return "12.1.5", "70783", "Nov 2026", 120105 end
    _G.InCombatLockdown = function() return false end
    -- Reads the real TOC once loadAddon has parsed it. Hardcoding a version
    -- here meant the acceptance report printed the previous phase's number.
    _G.C_AddOns = {
        GetAddOnMetadata = function(_, key)
            if key == "Version" then return M.tocVersion end
            return M.toc and M.toc[key]
        end,
    }
    _G.SlashCmdList = {}
    _G.C_Timer = { After = function(_, fn) fn() end }
    -- A controllable clock. Nothing in Phase 2 -- the 140ms dwell, the 120/260ms
    -- fades, the 3s peek -- can be tested against a real one.
    M.time = 1000
    _G.GetTime = function() return M.time end

    -- Epoch seconds, for the log. GetTime() is seconds since the client
    -- started and resets on reload, so it cannot date a record that outlives
    -- the session. Anchored to a real timestamp and moved by M.time, so a test
    -- that steps the session clock steps this one too.
    M.epoch = 1787000000
    _G.time = function() return math.floor(M.epoch + M.time) end

    -- Post-hooks. The addon uses this to find out who takes the chat focus
    -- override back, which is a question the reference source cannot answer:
    -- nothing in Blizzard's Interface clears it except the function itself.
    _G.hooksecurefunc = function(a, b, c)
        local tbl, key, fn
        if type(a) == "table" then tbl, key, fn = a, b, c else tbl, key, fn = _G, a, b end
        local orig = tbl[key]
        if type(orig) ~= "function" then error("hooksecurefunc: no such function") end
        tbl[key] = function(...)
            local r = { orig(...) }
            fn(...)
            return unpk(r)
        end
    end
    -- 12.1 replaced GetMouseFocus with GetMouseFoci, which returns a LIST:
    -- several regions can sit under one pixel.
    M.mouseFoci = {}
    _G.GetMouseFoci = function() return M.mouseFoci end

    _G.debugstack = function() return "mock stack\n  Blizzard_Something.lua:12\n" end

    -- A real scheduler, not a fire-immediately stub. Running every timer the
    -- instant it is scheduled would make the toast's 4s dwell untestable and,
    -- worse, would pass -- the lifecycle would look correct while collapsing
    -- the moment it opened.
    M.timers = {}
    _G.C_Timer = {
        After = function(delay, fn)
            M.timers[#M.timers + 1] = { at = M.time + delay, fn = fn }
        end,
    }

    function M.runTimers()
        local due = {}
        for i = #M.timers, 1, -1 do
            if M.timers[i].at <= M.time then
                due[#due + 1] = M.timers[i]
                table.remove(M.timers, i)
            end
        end
        -- Oldest first, so a timer that schedules another keeps its order.
        table.sort(due, function(a, b) return a.at < b.at end)
        for _, t in ipairs(due) do
            t.fn()
        end
    end

    -- Cursor is stored in UI units; GetCursorPosition reports the scaled value
    -- the client would, so the addon's division by effective scale is exercised
    -- rather than bypassed.
    M.cursorX, M.cursorY = -10000, -10000
    _G.GetCursorPosition = function()
        local scale = M.uiScale or 0.8
        return M.cursorX * scale, M.cursorY * scale
    end

    M.altDown, M.shiftDown = false, false
    _G.IsAltKeyDown   = function() return M.altDown end
    _G.IsShiftKeyDown = function() return M.shiftDown end
    _G.IsControlKeyDown = function() return M.ctrlDown end

    M.units = {}
    _G.UnitExists = function(unit) return M.units[unit] == true end
    M.hostile = true
    _G.UnitCanAttack = function() return M.hostile == true end

    M.chat = {}
    _G.DEFAULT_CHAT_FRAME = {
        AddMessage = function(_, msg) M.chat[#M.chat + 1] = msg end,
    }

    -- Colours are plain tables; CreateColor is a struct constructor, not an API.
    _G.CreateColor = function(r, g, b, a)
        return { r = r, g = g, b = b, a = a or 1 }
    end

    -- C_CurveUtil.CreateColorCurve -- CurveUtilDocumentation.lua declares
    -- Namespace = "C_CurveUtil". The mock spelled this "CurveUtil" for two
    -- commits and the addon spelled it the same wrong way, so every test
    -- passed while the live client would have returned nil. Found by reading
    -- how oUF and Plater actually call it.
    M.curves = {}
    local function makeCurve(kind)
        local curve = { points = {}, secretFlag = false, curveType = 0, kind = kind or "color" }
        function curve:AddPoint(x, color)
            if secretSet[x] then error("attempt to add a secret point", 2) end
            self.points[#self.points + 1] = { x = x, y = color }
        end
        function curve:SetType(t) self.curveType = t end
        function curve:GetType() return self.curveType end
        function curve:GetPointCount() return #self.points end
        function curve:HasSecretValues() return self.secretFlag end
        function curve:SetToDefaults()
            self.points, self.secretFlag, self.curveType = {}, false, 0
        end
        M.curves[#M.curves + 1] = curve
        return curve
    end

    _G.C_CurveUtil = {
        CreateColorCurve = function() return makeCurve("color") end,
        CreateCurve      = function() return makeCurve("scalar") end,
    }

    -- UnitHealthPercent(unit, usePredicted, curve) -- UnitDocumentation.lua:1431.
    -- With a curve it returns the evaluated colour. The colour object itself is
    -- ordinary -- Plater indexes it directly -- but every channel it yields is
    -- secret, which is what makes the alpha forwardable and unreadable.
    local function evaluated()
        return {
            GetRGBA = function()
                return M.secret(), M.secret(), M.secret(), M.secret()
            end,
        }
    end

    -- A scalar curve evaluates to a (secret) number, a colour curve to a
    -- colour object whose channels are secret.
    local function through(curve)
        curve.secretFlag = true
        if curve.kind == "scalar" then return M.secret() end
        return evaluated()
    end
    _G.UnitHealthPercent = function(unit, usePredicted, curve)
        M.healthCalls = (M.healthCalls or 0) + 1
        if curve then return through(curve) end
        return M.secret()
    end
    -- UnitDocumentation.lua:2749: (unit, powerType, unmodified, curve).
    _G.UnitPowerPercent = function(unit, powerType, unmodified, curve)
        M.powerCalls = (M.powerCalls or 0) + 1
        if type(powerType) == "boolean" then error("UnitPowerPercent: powerType is not a boolean", 2) end
        if curve then return through(curve) end
        return M.secret()
    end
    -- Phase 4. M.casting[unit] = "cast" | "channel" | nil. castBarID is
    -- NeverSecret in the docs and plain here; names are secret, like a
    -- restricted target's. M.secretDurations makes the duration object
    -- arrive secret, as it can in restricted content.
    M.casting = {}
    M.secretDurations = false
    local function duration()
        if M.secretDurations then return M.secret() end
        return { kind = "duration" }
    end
    _G.UnitCastingInfo = function(unit)
        if M.casting[unit] ~= "cast" then return nil end
        return M.secret(), M.secret(), 1, M.secret(), M.secret(), false, "cast-guid",
               false, M.secret(), 7, 0
    end
    _G.UnitChannelInfo = function(unit)
        if M.casting[unit] ~= "channel" then return nil end
        return M.secret(), M.secret(), 1, M.secret(), M.secret(), false, false,
               M.secret(), false, 0, 9
    end
    _G.UnitCastingDuration = function() return duration() end
    _G.UnitChannelDuration = function() return duration() end
    _G.UnitName  = function() return M.secret() end
    M.levels = {}
    _G.UnitLevel = function(unit) return M.levels[unit] or 80 end
    _G.UnitHealth    = function() return M.secret() end
    _G.UnitHealthMax = function() return M.secret() end

    -- SecureCmdOptionParse is engine-side. This models what a live 12.1 client
    -- was measured to do, which is NOT what this mock first assumed:
    --
    --   A conditional the parser does not know is IGNORED, so the clause
    --   matches. [zzznope] hits; [nozzznope] misses.
    --
    -- The first version had that backwards and every test still passed, which
    -- is the standing lesson from the Rebar project: a mock's defaults are
    -- assertions about the real system, and a wrong one buys false confidence.
    --
    -- M.known teaches it a term, so the probe's discriminator can be proven to
    -- report RECOGNISED when a conditional really does exist. Without that a
    -- probe hardwired to answer "no" would pass everything.
    M.known = {}
    M.inCombat = false

    local function term(name)
        -- @unit selectors are not conditionals; the parser accepts them.
        if name:sub(1, 1) == "@" then return true end

        local negated = false
        if name:sub(1, 2) == "no" then
            negated, name = true, name:sub(3)
        end

        local value = M.known[name]
        if value == nil then
            if name == "combat" then
                value = M.inCombat
            else
                value = true   -- unrecognised: ignored, so the clause matches
            end
        end

        if negated then return not value end
        return value
    end

    _G.SecureCmdOptionParse = function(macro)
        local cond, hit, miss = macro:match("^%[(.-)%]%s*(%S+);%s*(%S+)$")
        if not cond then return macro end
        for part in cond:gmatch("[^,]+") do
            if not term(part) then return miss end
        end
        return hit
    end

    -- Secure state drivers. The client evaluates the conditional string on
    -- every modifier or bar change and runs the header's _onstate-<name>
    -- snippet in the restricted environment; this evaluates it on demand
    -- (M.UpdateStateDrivers) against M.mods and M.bonusbar, and runs the
    -- snippet as plain Lua with only `self` and `newstate` -- if the snippet
    -- reached for anything else it would fail here as it would there.
    M.mods, M.bonusbar, M.drivers = { alt = false, ctrl = false, shift = false }, nil, {}

    local function driverTerm(t)
        local mod = t:match("^mod:(%a+)$")
        if mod then return M.mods[mod] and true or false end
        local bb = t:match("^bonusbar:(%d+)$")
        if bb then return M.bonusbar == tonumber(bb) end
        return M.known[t] or false
    end

    function M.EvalDriver(text)
        for raw in text:gmatch("[^;]+") do
            local clause = raw:match("^%s*(.-)%s*$")
            local conds, value = clause:match("^(%[.*%])%s*(.-)$")
            if not conds then return clause end
            for group in conds:gmatch("%[(.-)%]") do
                local all = true
                for t in group:gmatch("[^,]+") do
                    if not driverTerm(t) then all = false end
                end
                if all then return value end
            end
        end
        return nil
    end

    local SNIPPET_ENV = { tonumber = tonumber }
    local function RunDriver(d)
        local value = M.EvalDriver(d.text)
        if d.state == "visibility" then
            if value == "hide" then d.frame:Hide() else d.frame:Show() end
            return
        end
        if d.frame.__attrs["state-" .. d.state] == value then return end
        d.frame:SetAttribute("state-" .. d.state, value)
        local body = d.frame.__attrs["_onstate-" .. d.state]
        if body then
            local env = setmetatable({ self = d.frame, newstate = value }, { __index = SNIPPET_ENV })
            local chunk = assert((loadstring or load)(body, "=_onstate-" .. d.state))
            setfenv(chunk, env)
            chunk()
        end
    end

    _G.RegisterStateDriver = function(frame, state, text)
        local d = { frame = frame, state = state, text = text }
        M.drivers[#M.drivers + 1] = d
        RunDriver(d)
    end
    function M.UpdateStateDrivers()
        for _, d in ipairs(M.drivers) do RunDriver(d) end
    end

    -- Key bindings: M.bindings[key] = command. GetBindingKey is the reverse.
    M.bindings = {}
    _G.GetBindingAction = function(key, checkOverride)
        local o = checkOverride and M.overrides and M.overrides[key]
        if o then return "CLICK " .. o.button .. ":LeftButton" end
        return M.bindings[key] or ""
    end
    _G.GetBindingKey = function(cmd)
        local keys = {}
        for key, c in pairs(M.bindings) do
            if c == cmd then keys[#keys + 1] = key end
        end
        table.sort(keys)
        return (unpack or table.unpack)(keys)
    end
    -- Override bindings: M.overrides[key] = button name, per owner.
    M.overrides = {}
    _G.ClearOverrideBindings = function(owner)
        for key, o in pairs(M.overrides) do
            if o.owner == owner then M.overrides[key] = nil end
        end
    end
    _G.SetOverrideBindingClick = function(owner, _, key, name)
        M.overrides[key] = { owner = owner, button = name }
    end
    _G.GetBindingText = function(key) return key end

    M.created = {}
    _G.CreateFrame = function(frameType, name, parent, template)
        local f = M.frame({ name = name, objectType = frameType or "Frame" })
        f.__template = template
        M.created[#M.created + 1] = f
        M.lastFrame = f
        if type(name) == "string" then _G[name] = f end
        return f
    end

    _G.UIParent = M.frame({ name = "UIParent" })
    _G.UIParent.GetEffectiveScale = function() return M.uiScale or 0.8 end

    -- 5120x2880 at uiScale 0.8 gives exactly 3 physical pixels per UI unit,
    -- which is this machine's measured configuration (Rebar API-NOTES).
    _G.GetPhysicalScreenSize = function() return M.physW or 5120, M.physH or 2880 end
    _G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
    -- Fixed, so a report's text is deterministic across runs.
    _G.date = function() return "2026-08-27 12:00" end

    -- -----------------------------------------------------------------------
    -- What feeds the rail (SPEC 6, Sources.lua)
    -- -----------------------------------------------------------------------
    -- None of this is protected -- item quality, bag slots, durability and mail
    -- are ordinary values, and the amended RULES says so. Modelled here because
    -- the interesting part of Sources.lua is the FILTERING, and a filter with
    -- nothing to filter is untested.
    M.playerGUID   = "Player-1-DEADBEEF"
    M.itemQuality  = {}      -- [itemID] = quality
    M.bagFree      = 5       -- free slots across all bags
    M.durability   = 1.0     -- worst fraction; nil means unreadable
    M.hasMail      = false
    M.currencies   = {}      -- [id] = name
    M.questTitles  = {}      -- [id] = title
    M.achievements = {}      -- [id] = name

    _G.UnitGUID = function(unit)
        if unit == "player" then return M.playerGUID end
        return "Player-1-OTHER"
    end

    _G.C_Item = {
        GetItemQualityByID = function(id) return M.itemQuality[id] end,
    }

    -- One backpack, so the total is whatever the test set. The addon sums over
    -- BACKPACK_CONTAINER..NUM_TOTAL_EQUIPPED_BAG_SLOTS and does not care where
    -- the slots came from.
    _G.BACKPACK_CONTAINER = 0
    _G.NUM_TOTAL_EQUIPPED_BAG_SLOTS = 4
    _G.C_Container = {
        GetContainerNumFreeSlots = function(bag)
            if bag == 0 then return M.bagFree end
            return 0
        end,
    }

    -- Slot 1 carries the worst value and the rest read nil, which also exercises
    -- the loop skipping slots that cannot wear out.
    _G.GetInventoryItemDurability = function(slot)
        if slot ~= 1 or type(M.durability) ~= "number" then return nil end
        return M.durability * 100, 100
    end

    _G.HasNewMail = function() return M.hasMail end

    _G.C_CurrencyInfo = {
        GetCurrencyInfo = function(id)
            local name = M.currencies[id]
            if not name then return nil end
            return { name = name }
        end,
    }

    -- Round 005's quest tracker reads the log. M.quests is the log, in
    -- order: { id, title, complete, objectives = { {text, finished,
    -- numFulfilled, numRequired, type} } }; M.watched lists tracked ids.
    M.quests, M.watched, M.superTracked = {}, {}, 0
    local function quest(id)
        for _, q in ipairs(M.quests) do if q.id == id then return q end end
    end
    _G.C_QuestLog = {
        GetTitleForQuestID = function(id)
            local q = quest(id)
            return q and q.title or M.questTitles[id]
        end,
        GetNumQuestLogEntries = function() return #M.quests end,
        GetInfo = function(i)
            local q = M.quests[i]
            return q and { questID = q.id, title = q.title, isHeader = q.header == true }
        end,
        GetQuestObjectives = function(id) local q = quest(id); return q and q.objectives or {} end,
        IsComplete = function(id) local q = quest(id); return q ~= nil and q.complete == true end,
        ReadyForTurnIn = function(id) local q = quest(id); return q ~= nil and q.complete == true end,
        GetNumQuestWatches = function() return #M.watched end,
        GetQuestIDForQuestWatchIndex = function(i) return M.watched[i] end,
        IsWorldQuest = function(id) local q = quest(id); return q ~= nil and q.world == true end,
        GetNumWorldQuestWatches = function() return #M.watchedWorld end,
        GetQuestIDForWorldQuestWatchIndex = function(i) return M.watchedWorld[i] end,
    }
    M.watchedWorld = {}
    -- Tracked achievements: M.trackedAch = { id, ... }; M.achCriteria[id] =
    -- { { text, done, have, need } }.
    M.trackedAch, M.achCriteria = {}, {}
    _G.Enum.ContentTrackingType = { Appearance = 0, Mount = 1, Achievement = 2 }
    _G.Enum.ContentTrackingStopType = { Invalidated = 0, Collected = 1, Manual = 2 }
    _G.C_ContentTracking = {
        GetTrackedIDs = function(t) if t == 2 then return M.trackedAch end return {} end,
        StopTracking = function(t, id)
            for i, a in ipairs(M.trackedAch) do if a == id then table.remove(M.trackedAch, i) end end
        end,
    }
    _G.GetAchievementNumCriteria = function(id) return #(M.achCriteria[id] or {}) end
    _G.GetAchievementCriteriaInfo = function(id, i)
        local c = (M.achCriteria[id] or {})[i]
        if c then return c[1], 0, c[2], c[3], c[4] end
    end
    -- The guild roster and friends: M.guild = { { name, zone, level, online } }.
    M.guild, M.friends = {}, {}
    _G.GetNumGuildMembers = function()
        local on = 0
        for _, g in ipairs(M.guild) do if g.online then on = on + 1 end end
        return #M.guild, on
    end
    _G.GetGuildRosterInfo = function(i)
        local g = M.guild[i]
        if g then return g.name, "Member", 1, g.level or 90, "Hunter", g.zone, "", "", g.online end
    end
    _G.C_GuildInfo = { GuildRoster = function() end }
    _G.C_FriendList = {
        GetNumFriends = function() return #M.friends end,
        GetFriendInfoByIndex = function(i) return M.friends[i] end,
    }
    _G.ERR_FRIEND_ONLINE_SS = "|Hplayer:%s|h[%s]|h has come online."
    M.progressBars = {}
    _G.GetQuestProgressBarPercent = function(id) return M.progressBars[id] or 0 end
    _G.C_SuperTrack = {
        GetSuperTrackedQuestID = function() return M.superTracked end,
        SetSuperTrackedQuestID = function(id) M.superTracked = id end,
    }

    _G.GetAchievementInfo = function(id) return id, M.achievements[id] end

    -- The localized format strings the loot filter falls back to when a message
    -- arrives with no GUID. Real values from enUS.
    _G.LOOT_ITEM_SELF          = "You receive loot: %s."
    _G.LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."
    _G.LOOT_ITEM_PUSHED_SELF   = "You receive item: %s."
    -- Several forms, because the first version of the reader knew only the
    -- plain one and drew the fallback "Reputation" in game. The bonus form is
    -- here specifically because its trailing %.1f broke the naive escaper.
    _G.FACTION_STANDING_INCREASED = "Your reputation with %s has increased by %d."
    _G.FACTION_STANDING_INCREASED_ACH_BONUS =
        "Your reputation with %s has increased by %d.  (+%.1f bonus from achievement)"
    _G.FACTION_STANDING_INCREASED_ACCOUNT_WIDE =
        "Your account-wide reputation with %s has increased by %d."
    _G.FACTION_STANDING_INCREASED_GENERIC = "Reputation with %s increased."

    -- The edit box Blizzard actually sends through. SendText is the mixin
    -- method that parses the text, resolves the chat type and routes it; the
    -- whole point of the override is that we never reimplement any of that.
    M.sent = {}
    M.chatType = "SAY"
    M.tellTarget = nil
    local sendBox = M.frame({ name = "ChatFrame1EditBox" })
    sendBox.SendText = function(self, addHistory)
        local calls = self.__calls
        for i = #calls, 1, -1 do
            if calls[i].method == "SetText" and calls[i][1] ~= "" then
                M.sent[#M.sent + 1] = { text = calls[i][1], history = addHistory }
                return
            end
        end
    end
    sendBox.GetChatType   = function() return M.chatType end
    sendBox.GetTellTarget = function() return M.tellTarget end
    M.sendBox = sendBox
    _G.DEFAULT_CHAT_FRAME.editBox = sendBox

    -- The chat frames and their furniture, by the names Chat.lua stows.
    _G.NUM_CHAT_WINDOWS = 2
    for i = 1, 2 do
        _G["ChatFrame" .. i]             = M.frame({ name = "ChatFrame" .. i, parent = _G.UIParent, shown = true })
        _G["ChatFrame" .. i .. "Tab"]    = M.frame({ name = "ChatFrame" .. i .. "Tab", parent = _G.UIParent })
        _G["ChatFrame" .. i .. "ButtonFrame"] = M.frame({ name = "ChatFrame" .. i .. "ButtonFrame", parent = _G.UIParent })
    end
    -- FOUND IN GAME: 221x361 at the left edge, exactly where the rail lives.
    _G.Minimap = M.frame({ name = "Minimap", parent = _G.UIParent, shown = true })
    _G.Minimap.GetCenter = function() return 1400, 800 end

    _G.CompactRaidFrameManager = M.frame({ name = "CompactRaidFrameManager",
                                           parent = _G.UIParent, shown = true })
    for _, name in ipairs({ "GeneralDockManager", "ChatFrameMenuButton",
                            "QuickJoinToastButton", "ChatFrameChannelButton" }) do
        _G[name] = M.frame({ name = name, parent = _G.UIParent })
    end
    -- Declared inside FloatingChatFrameTemplate, so it starts life as a child
    -- of the chat frame. That parentage is the whole trap.
    sendBox.__parent = _G.ChatFrame1
    _G.ChatFrame1EditBox = sendBox
    _G.ChatFrame1.editBox = sendBox

    -- ChatFrame_OpenChat is deprecated on 12.1 and aliased to this.
    M.chatOpened = {}
    _G.ChatFrameUtil = {
        OpenChat = function(text) M.chatOpened[#M.chatOpened + 1] = text end,
        ChooseBoxForSend = function() return sendBox end,
        -- ChatFrameUtil.lua:104-114. The override is a real extension point,
        -- and OpenChat consults it before anything else.
        SetChatFocusOverride   = function(box) M.chatFocusOverride = box end,
        GetChatFocusOverride   = function() return M.chatFocusOverride end,
        ClearChatFocusOverride = function() M.chatFocusOverride = nil end,
    }
end

--- Load the addon exactly as the client would, in the order the TOC lists.
--
-- The file list is read from MyUI.toc rather than duplicated here. A hardcoded
-- list silently stops covering a new file the moment one is added, which is
-- how Copy.lua first went untested.
function M.loadAddon(dir, name)
    name = name or "MyUI"
    local toc = assert(io.open(dir .. "/" .. name .. ".toc", "r"),
                       "cannot open " .. dir .. "/" .. name .. ".toc")
    local files, meta = {}, {}
    for line in toc:lines() do
        local name = line:match("^%s*([%w_%-]+%.lua)%s*$")
        if name then
            files[#files + 1] = name
        else
            local key, value = line:match("^##%s*([%w%-]+)%s*:%s*(.-)%s*$")
            if key then meta[key] = value end
        end
    end
    toc:close()
    assert(#files > 0, "no Lua files listed in " .. name .. ".toc")

    -- Before loading: Core.lua reads the version at file scope. Only MyUI's
    -- TOC answers GetAddOnMetadata; loading the test addon must not change it.
    if name == "MyUI" then
        M.toc = meta
        M.tocVersion = meta.Version
    end

    local ns = {}
    for _, file in ipairs(files) do
        local chunk, err = loadfile(dir .. "/" .. file)
        if not chunk then error("could not load " .. file .. ": " .. tostring(err)) end
        chunk(name, ns)
    end
    ns.__loadedFiles = files
    ns.__toc = meta
    return ns
end

return M
