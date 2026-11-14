-- MyUI_Test :: SuitesMyUI.lua
-- MyUI's in-game acceptance scripts (MyUI/Testing.lua, phases 0-3) as suites
-- that need no hands: every state is set from code, with fake data where the
-- real trigger is a player action (a target, combat, a held key).
--
-- What still needs eyes -- "does it read as calm", "is the hairline crisp" --
-- is answered by looking at the shot afterwards, not by being present.

local ADDON, T = ...


-- ---------------------------------------------------------------------------
-- Shared state handling
-- ---------------------------------------------------------------------------

local CHANNELS = { "debug", "peek", "modifier", "combat", "target", "cursor" }

-- SPEC.md 2's resting alphas, restated so checks assert against the spec
-- rather than against whatever Frames.lua registered.
local SPEC_RESTING = { SelfStack = 0.35, Cooldowns = 0.25, TargetStrip = 0, Rail = 1 }

local saved

local function Save(ns)
    saved = {
        contrast = ns.db and ns.db.contrast,
        textStyle = ns.db and ns.db.textStyle,
    }
end

--- Every test starts from rest: nothing forced, no claims, no outline, no
-- peek, an empty rail. Synthetic claims stand in for the real triggers, so a
-- target you happened to have when the key was pressed does not leak in.
--
-- fill: the debug placeholders (number, names, 30% bar fill) stand in for the
-- live data Phase 4 will bring, so a reveal has something visible to reveal.
-- Off only where the test is about the empty state itself.
local function Baseline(api, fill)
    local ns = api.ns()
    if not ns then return end
    if ns.Registry.forced then ns.Registry.ForceVisible(false) end
    ns.Frames.Placeholders(fill ~= false)
    if ns.Peek and ns.Peek.IsActive() then ns.Peek.Stop() end
    for _, ch in ipairs(CHANNELS) do ns.Reveal.Release(ch) end
    if ns.Outline and ns.Outline.IsShown() then ns.Outline.Toggle(false) end
    if ns.Rail then ns.Rail.Clear() end
    ns.Reveal.Resolve()
    ns.Reveal.Snap()
end

local function Restore(api)
    local ns = api.ns()
    if not ns then return end
    Baseline(api, false)
    api.myui("outline off")
    if saved and ns.db then
        ns.db.contrast = saved.contrast
        ns.db.textStyle = saved.textStyle
        ns.Frames.RestyleText()
    end
end

local function NeedMyUI(api)
    local ns = api.ns()
    if not ns then
        return false, "MyUI did not hand over its namespace (is MyUI loaded?)"
    end
    if not ns.Registry or ns.Registry.Count() == 0 then
        return false, "MyUI has no registered frames"
    end
    return true
end

-- Alphas after a snap. Live alpha when readable, intent otherwise.
local function AlphasAre(api, want)
    local ns = api.ns()
    local bad
    ns.Registry.Each(function(entry)
        local target = want[entry.name]
        if target == nil then return end
        local live = ns.Compat.Get(entry.frame, "GetAlpha")
        local got = type(live) == "number" and live or entry.target
        if type(got) ~= "number" or math.abs(got - target) > 0.01 then
            bad = bad or ("%s at %s, wanted %.2f"):format(entry.name, tostring(got), target)
        end
    end)
    if bad then return false, bad end
    return true, "alphas as expected"
end

local function AllAt(api, alpha)
    local want = {}
    for name in pairs(SPEC_RESTING) do want[name] = alpha end
    return AlphasAre(api, want)
end

local function Claim(api, channel)
    local ns = api.ns()
    ns.Reveal.Claim(channel, nil, "test")
    ns.Reveal.Snap()
end

-- ---------------------------------------------------------------------------
-- Phase 0 -- skeleton and compliance harness
-- ---------------------------------------------------------------------------

T.Suite("myui-p0", {
    title = "Phase 0 -- skeleton and compliance",
    requires = NeedMyUI,
    tests = {
        { id = "guard-clean", shot = false,
          what = "The compliance guard has logged no violations this session.",
          check = function(api)
              local n = #api.ns().Guard.violations
              return n == 0, n .. " violations"
          end },
    },
})

-- ---------------------------------------------------------------------------
-- Phase 1 -- anchors and frame registry
-- ---------------------------------------------------------------------------

T.Suite("myui-p1", {
    title = "Phase 1 -- anchors and registry",
    requires = NeedMyUI,
    before = function(api) Save(api.ns()) end,
    after = Restore,
    tests = {
        { id = "rest",
          what = "Every frame at its SPEC 2 resting alpha, bars empty, no placeholder "
              .. "text; TargetStrip invisible.",
          setup = function(api) Baseline(api, false) end,
          check = function(api) return AlphasAre(api, SPEC_RESTING) end },

        { id = "show-on",
          what = "Every frame forced to full with placeholders: three bars and a number "
              .. "bottom centre, target bar with name and value top centre, rail hairline left.",
          setup = function(api) Baseline(api); api.myui("show on") end,
          check = function(api) return AllAt(api, 1) end },

        { id = "outline",
          what = "As show-on, with a box snug around each of the four frames.",
          setup = function(api) Baseline(api); api.myui("show on"); api.myui("outline on") end,
          teardown = function(api) api.myui("outline off") end },

        { id = "registry", shot = false,
          what = "Four frames registered, resting alphas match SPEC 2.",
          check = function(api)
              local ns = api.ns()
              for name, want in pairs(SPEC_RESTING) do
                  local e = ns.Registry.Get(name)
                  if not e then return false, name .. " missing" end
                  if math.abs(e.resting - want) > 0.001 then
                      return false, ("%s rests at %.2f, spec says %.2f"):format(name, e.resting, want)
                  end
              end
              return true, "all four match SPEC 2"
          end },

        { id = "pixel-perfect", shot = false,
          what = "One UI unit is a whole number of physical pixels.",
          check = function(api)
              local perfect, perUnit = api.ns().Scale.IsPixelPerfect()
              if perUnit == nil then return false, "could not measure" end
              return perfect and true or false, ("%.4f px per unit"):format(perUnit)
          end },
    },
})

-- ---------------------------------------------------------------------------
-- Phase 2 -- the reveal engine
-- ---------------------------------------------------------------------------

T.Suite("myui-p2", {
    title = "Phase 2 -- reveal engine",
    requires = NeedMyUI,
    before = function(api) Save(api.ns()) end,
    after = Restore,
    tests = {
        { id = "timings", shot = false,
          what = "Zone 32 units, dwell 140ms, fade in 120ms, out 260ms, peek 3s.",
          check = function(api)
              local ns = api.ns()
              local R, P = ns.Reveal, ns.Peek
              for _, w in ipairs({
                  { "zone", R.PROXIMITY, ns.Scale.U(32) }, { "dwell", R.DWELL, 0.140 },
                  { "in", R.FADE_IN, 0.120 }, { "out", R.FADE_OUT, 0.260 },
                  { "peek", P.DURATION, 3.0 },
              }) do
                  if math.abs(w[2] - w[3]) > 0.0001 then
                      return false, ("%s is %s, spec says %s"):format(w[1], tostring(w[2]), tostring(w[3]))
                  end
              end
              return true, "all five match"
          end },

        { id = "modifier",
          what = "Held modifier: every frame at full, no dwell.",
          setup = function(api) Baseline(api); Claim(api, "modifier") end,
          check = function(api) return AllAt(api, 1) end },

        { id = "target",
          what = "A target: the top strip appears; the bottom group stays faint.",
          setup = function(api) Baseline(api); Claim(api, "target") end,
          check = function(api)
              return AlphasAre(api, { TargetStrip = 1, SelfStack = 0.35, Cooldowns = 0.25 })
          end },

        { id = "combat",
          what = "Combat: the bottom group up; the target strip unaffected.",
          setup = function(api) Baseline(api); Claim(api, "combat") end,
          check = function(api)
              return AlphasAre(api, { SelfStack = 1, Cooldowns = 1, TargetStrip = 0 })
          end },

        { id = "peek",
          what = "Peek, halfway: everything up, the drain line about half empty.",
          setup = function(api) Baseline(api); api.ns().Peek.Start() end,
          wait = 1.5,
          frames = function(api)
              local f = api.registryFrames()
              f.PeekClock = _G.MyUIPeekClock
              return f
          end,
          check = function(api)
              local left = api.ns().Peek.Remaining()
              return left > 0.5 and left < 2.5, ("%.1fs left"):format(left)
          end,
          teardown = function(api) api.ns().Peek.Stop() end },

        { id = "released",
          what = "All claims dropped: back to resting, not to zero.",
          setup = function(api)
              Baseline(api)
              Claim(api, "modifier")
              api.ns().Reveal.Release("modifier", nil, "test")
          end,
          check = function(api) return AlphasAre(api, SPEC_RESTING) end },
    },
})

-- ---------------------------------------------------------------------------
-- Phase 3 -- the rail
-- ---------------------------------------------------------------------------

local function RailFrames(api)
    local f = api.registryFrames()
    f.RailToast = _G.MyUIRailToast
    return f
end

T.Suite("myui-p3", {
    title = "Phase 3 -- the rail",
    requires = NeedMyUI,
    before = function(api) Save(api.ns()) end,
    after = Restore,
    tests = {
        { id = "empty",
          what = "The rail at rest: one vertical hairline, nothing else. Calm.",
          setup = function(api) Baseline(api) end, frames = RailFrames,
          check = function(api)
              local n = #api.ns().Rail.items
              return n == 0, n .. " items"
          end },

        { id = "toast",
          what = "A blue Whisper toast slid in near the top of the rail.",
          setup = function(api) Baseline(api); api.myui("notify blue Whisper") end,
          wait = 0.8, frames = RailFrames,
          check = function(api)
              local on = api.ns().Rail.IsToasting()
              return on and true or false, on and "toasting" or "no toast"
          end },

        { id = "two",
          what = "Two items, toasts dismissed: amber Loot on top, blue Whisper below, "
              .. "both named, ages on the right.",
          setup = function(api)
              Baseline(api)
              api.myui("notify blue Whisper"); api.myui("notify dismiss")
              api.myui("notify amber Loot"); api.myui("notify dismiss")
          end,
          frames = RailFrames,
          check = function(api)
              local items = api.ns().Rail.items
              return #items == 2 and items[1].name == "Loot",
                     ("%d items, top %s"):format(#items, items[1] and items[1].name or "-")
          end },

        { id = "full",
          what = "Ten sent: eight dots, the newest two named, lower ones dimmer, a hollow "
              .. "square with +2 beside it.",
          setup = function(api)
              Baseline(api); api.myui("notify demo"); api.myui("notify dismiss")
          end,
          frames = RailFrames,
          check = function(api)
              local Rail = api.ns().Rail
              local shown = 0
              for i = 1, Rail.CAP do
                  if Rail.slots and Rail.slots[i] and Rail.slots[i]:IsShown() then shown = shown + 1 end
              end
              return shown == Rail.CAP and Rail.Overflow() >= 1,
                     ("%d dots, +%d behind the square"):format(shown, Rail.Overflow())
          end },

        { id = "full-normal-contrast",
          what = "As full, with SPEC 6's exact greys (contrast normal) -- the legibility "
              .. "question in Phase 3 step 13.",
          setup = function(api)
              Baseline(api); api.myui("contrast normal")
              api.myui("notify demo"); api.myui("notify dismiss")
          end,
          frames = RailFrames,
          teardown = function(api)
              local ns = api.ns()
              if saved and ns.db then ns.db.contrast = saved.contrast; ns.Frames.RestyleText() end
          end },
    },
})
