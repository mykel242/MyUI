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

local CHANNELS = { "debug", "peek", "combat", "target", "cursor" }

-- SPEC.md 2's resting alphas, restated so checks assert against the spec
-- rather than against whatever Frames.lua registered.
local SPEC_RESTING = { SelfStack = 0.35, Cooldowns = 0.25, TargetStrip = 0 }

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
    if ns.Toast then ns.Toast.Clear() end
    if ns.Center and ns.Center.IsOpen() then ns.Center.Close() end
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
    ns.Reveal.Claim(channel)
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
              Claim(api, "combat")
              api.ns().Reveal.Release("combat")
          end,
          check = function(api) return AlphasAre(api, SPEC_RESTING) end },
    },
})

-- ---------------------------------------------------------------------------
-- R3 -- toasts and a history (SPEC 6, round 003)
-- ---------------------------------------------------------------------------
-- Test notifications go through the real log, so the character's record is
-- saved before the suite and put back after it: a test run must not leave
-- "Notice 3" in someone's history.

local savedLog

local function ToastFrames(api)
    local f = api.registryFrames()
    for i = 1, 8 do
        local t = _G["MyUIToast" .. i]
        if t then f["Toast" .. i] = t end
    end
    f.ToastAnchor = _G.MyUIToastAnchor
    return f
end

-- Ages count in whole seconds and a test's waits vary by a second, so every
-- speaking toast is stamped "now" just before the shot: every age reads 0s.
local function FreshAges(api)
    local ns = api.ns()
    local now = ns.Reveal.Now()
    for _, item in ipairs(ns.Toast.live) do item.at = now end
    ns.Toast.Repaint()
end

-- The history shows the log, which is whatever this character has lived
-- through. For a stable shot it is given a fixed, freshly dated record.
local FIXED = {
    { "violet", "Friend-Realm" }, { "blue", "Hearthstone" }, { "amber", "The Missing Diplomat" },
    { "green", "Conquest", 50 }, { "orange", "Mail" }, { "blue", "Satchel of Cooperation" },
}
local function FixedLog(api)
    local Log = api.ns().Log
    local now = Log.Now()
    local entries = {}
    for i, e in ipairs(FIXED) do
        entries[i] = { at = now, kind = e[1], name = e[2], count = e[3] or 1 }
    end
    Log.db.entries = entries
end

T.Suite("myui-toasts", {
    title = "R3 -- toasts and a history",
    requires = NeedMyUI,
    before = function(api)
        Save(api.ns())
        local Log = api.ns().Log
        savedLog = Log.db and Log.db.entries
        if Log.db then
            local copy = {}
            for i, e in ipairs(savedLog or {}) do copy[i] = e end
            Log.db.entries = copy
        end
    end,
    after = function(api)
        Restore(api)
        local Log = api.ns().Log
        if Log.db and savedLog then Log.db.entries = savedLog end
    end,
    tests = {
        { id = "quiet",
          what = "Nothing speaking: nothing at the left edge at all. No column, no hairline.",
          setup = function(api) Baseline(api) end, frames = ToastFrames,
          check = function(api)
              local n = #api.ns().Toast.live
              return n == 0, n .. " speaking"
          end },

        { id = "one",
          what = "One blue toast at the anchor: dot, name, 0s on the right.",
          setup = function(api) Baseline(api); api.myui("notify blue Hearthstone") end,
          wait = 0.8, frames = ToastFrames, beforeShot = FreshAges,
          check = function(api)
              return api.ns().Toast.IsSpeaking(), "speaking"
          end },

        { id = "stack",
          what = "Five sent: three speaking, newest at the anchor, stacked downward.",
          setup = function(api) Baseline(api); api.myui("notify demo") end,
          wait = 0.8, frames = ToastFrames, beforeShot = FreshAges,
          check = function(api)
              local T2 = api.ns().Toast
              return #T2.live == T2.CAP, ("%d speaking, cap %d"):format(#T2.live, T2.CAP)
          end },

        { id = "long-name",
          what = "A long name truncates with an ellipsis; the age never yields (H1).",
          setup = function(api)
              Baseline(api)
              api.myui("notify blue Chunk of Companion Experience and a Great Deal More")
          end,
          wait = 0.8, frames = ToastFrames, beforeShot = FreshAges },


        { id = "stack-normal-contrast", world = true,
          what = "Three toasts with SPEC 6's original grey (contrast normal), over the "
              .. "world -- legibility. For eyes; diffed on geometry.",
          setup = function(api)
              Baseline(api); api.myui("contrast normal"); api.myui("notify demo")
          end,
          wait = 0.8, frames = ToastFrames, beforeShot = FreshAges,
          teardown = function(api)
              local ns = api.ns()
              if saved and ns.db then ns.db.contrast = saved.contrast; ns.Frames.RestyleText() end
          end },
    },
})

-- The history window is an extra (MVP M1): its suite runs only with extras on.
T.Suite("myui-history", {
    title = "Extra -- the history window",
    requires = function(api)
        local ok, why = NeedMyUI(api)
        if not ok then return ok, why end
        if not api.ns().Extras() then return false, "extras are off (MVP)" end
        return true
    end,
    before = function(api)
        Save(api.ns())
        local Log = api.ns().Log
        savedLog = Log.db and Log.db.entries
        if Log.db then
            local copy = {}
            for i, e in ipairs(savedLog or {}) do copy[i] = e end
            Log.db.entries = copy
        end
    end,
    after = function(api)
        Restore(api)
        local Log = api.ns().Log
        if Log.db and savedLog then Log.db.entries = savedLog end
    end,
    tests = {
        { id = "open",
          what = "The history at the toast anchor: five hue chips, six rows, newest first.",
          setup = function(api) Baseline(api); FixedLog(api); api.ns().Center.Open() end,
          frames = function(api)
              local f = ToastFrames(api)
              f.Center = _G.MyUICenter
              return f
          end,
          check = function(api)
              return api.ns().Center.IsOpen(), "open"
          end,
          teardown = function(api) api.ns().Center.Close() end },
    },
})

-- ---------------------------------------------------------------------------
-- R3b -- clearing the screen (SPEC 11)
-- ---------------------------------------------------------------------------
-- Checks, not shots: adopted frames are Blizzard's chat, minimap and bags, and
-- a crop of chat is other people's names and words.

local function Target(api, name)
    local e = api.ns().Registry.Get(name)
    return e and e.target
end

T.Suite("myui-clear", {
    title = "R3b -- clearing the screen",
    requires = function(api)
        local ok, why = NeedMyUI(api)
        if not ok then return ok, why end
        if not api.ns().Clear then return false, "no Clear module" end
        return true
    end,
    before = function(api) Baseline(api) end,
    after = function(api)
        local ns = api.ns()
        ns.Reveal.Release("peek")
        ns.Reveal.Release("whisper")
        ns.Reveal.Snap()
    end,
    tests = {
        { id = "adopted", shot = false,
          what = "Chat, minimap and bags adopted at resting alpha 0.",
          check = function(api)
              local Clear = api.ns().Clear
              if not Clear.Enabled() then return false, "clearing is off (/myui restore)" end
              local missing = {}
              for _, spec in ipairs(Clear.ADOPT) do
                  -- Round 004: bar 1 yields to MyUI's action bar -- adopted at 0,
                  -- out of the registry.
                  local ok
                  local calm = api.ns().Reveal.MapMode and api.ns().Reveal.MapMode() == "calm"
                  if calm and (spec[1] == "Minimap" or spec[1] == "MinimapMap") then
                      ok = true      -- round 004: up out of combat by design (/myui map)
                  elseif spec.yieldsTo and api.ns().Registry.Get(spec.yieldsTo) then
                      local f = _G[spec[2]]
                      ok = Target(api, spec[1]) == nil and (not f or f:GetAlpha() == 0)
                  else
                      ok = Target(api, spec[1]) == 0
                  end
                  if not ok then missing[#missing + 1] = spec[1] end
              end
              return #missing == 0, #missing == 0 and "all at 0" or ("not at 0: " .. table.concat(missing, ", "))
          end },
        { id = "peek-reveals", shot = false,
          what = "Peek summons them.",
          setup = function(api) api.ns().Reveal.Claim("peek") end,
          check = function(api)
              return Target(api, "Chat") == 1 and Target(api, "Minimap") == 1,
                     ("chat %s, minimap %s"):format(tostring(Target(api, "Chat")), tostring(Target(api, "Minimap")))
          end,
          teardown = function(api) api.ns().Reveal.Release("peek") end },
        { id = "whisper-reveals-chat", shot = false,
          what = "A whisper summons chat, and only chat.",
          setup = function(api) api.ns().Clear.OnWhisper() end,
          check = function(api)
              local calm = api.ns().Reveal.MapMode and api.ns().Reveal.MapMode() == "calm"
              return Target(api, "Chat") == 1 and (calm or Target(api, "Minimap") == 0),
                     ("chat %s, minimap %s"):format(tostring(Target(api, "Chat")), tostring(Target(api, "Minimap")))
          end,
          teardown = function(api) api.ns().Reveal.Release("whisper") end },
        { id = "combat-reveals", shot = false,
          what = "Combat brings back SelfStack, MyUI's action bar and wings, and group frames only by "
              .. "role or preference; never the bags, chat or the minimap.",
          setup = function(api) api.ns().Reveal.Claim("combat") end,
          check = function(api)
              local Clear = api.ns().Clear
              local main, chat, party = Target(api, "Bags"), Target(api, "Chat"), Target(api, "Party")
              local ours = Target(api, "ActionBar")
              local wantParty = Clear.GroupInCombat() and 1 or 0
              return (main == nil or main == 0) and chat == 0 and (ours == nil or ours == 1)
                     and (party == nil or party == wantParty),
                     ("bags %s, our bar %s, chat %s, party %s (mode %s, role %s)"):format(tostring(main), tostring(ours),
                         tostring(chat), tostring(party), Clear.GroupMode(), Clear.Role())
          end,
          teardown = function(api) api.ns().Reveal.Release("combat") end },
        { id = "leftovers", shot = false,
          what = "Lists every top-level frame still drawn at rest, so nothing is left unnamed. "
              .. "Informational: always passes; the detail is the list.",
          setup = function(api) Baseline(api) end,
          check = function(api)
              local ns = api.ns()
              local mine = {}
              ns.Registry.Each(function(e) mine[e.frame] = true end)
              local out = {}
              for _, f in ipairs({ UIParent:GetChildren() }) do
                  -- Forbidden frames (Blizzard's secure store and the like)
                  -- refuse every method from addon code; skip them.
                  local forbidden = f.IsForbidden and f:IsForbidden()
                  local ok, vis, alpha = false, nil, nil
                  local name
                  if not forbidden then
                      ok, vis, alpha = pcall(function() return f:IsVisible(), f:GetEffectiveAlpha() end)
                      local okName, n = pcall(f.GetName, f)
                      name = okName and n or nil
                  end
                  if ok and vis and type(alpha) == "number" and alpha > 0.01 and not mine[f]
                     and not (name and (name:find("^MyUI") or name == "MyUITestBackdrop")) then
                      local l, b, w, h = f:GetRect()
                      if l and w and h and w > 1 and h > 1 then
                          out[#out + 1] = ("%s@%d,%d %dx%d"):format(name or tostring(f):sub(-8),
                              math.floor(l), math.floor(b), math.floor(w), math.floor(h))
                      end
                  end
              end
              table.sort(out)
              return true, #out .. ": " .. table.concat(out, "; ")
          end },
        { id = "units-hidden", shot = false,
          what = "Player, target and focus frames unregistered and hidden (R3b ruling).",
          check = function(api)
              local shown = {}
              for _, name in ipairs(api.ns().Clear.UNITS) do
                  local f = _G[name]
                  if f and f:IsShown() then shown[#shown + 1] = name end
              end
              return #shown == 0, #shown == 0 and "all hidden" or ("shown: " .. table.concat(shown, ", "))
          end },
        { id = "layout-active", shot = false,
          what = "The MyUI Edit Mode layout is active: action bars hidden, Cooldown Manager in combat.",
          check = function(api)
              local Clear = api.ns().Clear
              local name = Clear.ActiveLayoutName()
              local db = api.ns().db.clear or {}
              return name == Clear.LAYOUT, ("active %s; previous %s; %s"):format(
                  tostring(name), tostring(db.prevLayout), tostring(db.layoutResult))
          end },
        { id = "player-frame-probe", shot = false,
          what = "SPEC 11's roleset filter on PlayerFrame: does it actually filter? (records, restores)",
          check = function(api)
              -- Informational since R3b's ruling: the filter is known not to
              -- hide (API-NOTES 13). Kept so a patch that changes that shows up.
              local r = api.ns().Clear.ProbePlayer()
              if r.error then return false, r.error end
              return r.restored and not r.filteredAfter,
                     ("set %s, filtered %s, visible %s->%s, restored %s, blocked before [%s]"):format(
                         tostring(r.setOk), tostring(r.filtered), tostring(r.visibleBefore),
                         tostring(r.visibleDuring), tostring(r.restored), tostring(r.blockedBefore))
          end },
    },
})

-- ---------------------------------------------------------------------------
-- Phase 4 -- bars and low health
-- ---------------------------------------------------------------------------
-- Checks, not shots: live health is whatever you have when you press the key.
-- The low-health tells need you actually hurt, so they are verified by eye
-- (fall damage is the easy way) and by /myui audit.

T.Suite("myui-actions", {
    title = "Round 004 -- the swap bar (probe P5)",
    requires = function(api)
        local ok, why = NeedMyUI(api)
        if not ok then return ok, why end
        local A = api.ns().Actions
        if not (A and A.header) then return false, "no action bar built (/myui actions)" end
        return true
    end,
    tests = {
        { id = "secure", shot = false,
          what = "A secure state header holding eight of Blizzard's action buttons.",
          check = function(api)
              local A = api.ns().Actions
              local prot = A.header.IsProtected and A.header:IsProtected()
              return #A.buttons == A.BUTTONS and prot ~= false,
                     ("%d buttons, header protected: %s"):format(#A.buttons, tostring(prot))
          end },
        { id = "pages", shot = false,
          what = "ALT and CTRL page to the bars the player's own keybinds name.",
          check = function(api)
              local A = api.ns().Actions
              local r = A.Probe()
              return A.found.a ~= nil and A.found.c ~= nil, table.concat(r.pages, "; ")
          end },
        { id = "driver", shot = false,
          what = "The page driver parses on this client to the page the header holds.",
          check = function(api)
              local A = api.ns().Actions
              local parsed = _G.SecureCmdOptionParse and _G.SecureCmdOptionParse(A.driver)
              local state = A.header:GetAttribute("state-page")
              return parsed ~= nil and tostring(parsed) == tostring(state),
                     ("parse %s, header %s"):format(tostring(parsed), tostring(state))
          end },
        { id = "slots", shot = false,
          what = "Every button shows its slot on the current page.",
          check = function(api)
              local A = api.ns().Actions
              local state = A.header:GetAttribute("state-page") or "1"
              if state == "hide" then return true, "hidden (vehicle or the like)" end
              local f = A.found[state]
              local offset = f and f.offset or ((tonumber(state) or 1) - 1) * 12
              for i, b in ipairs(A.rows[f and state or "1"]) do
                  if not b:IsShown() then return false, ("button %d of the page showing is hidden"):format(i) end
                  if b:GetAttribute("action") ~= offset + i then
                      return false, ("button %d -> %s, want %d"):format(i, tostring(b:GetAttribute("action")), offset + i)
                  end
              end
              return true, ("page %s, slots %d-%d"):format(tostring(state), offset + 1, offset + #A.buttons)
          end },
        { id = "keys", shot = false,
          what = "The player's keys for these slots click MyUI's buttons.",
          check = function(api)
              local A = api.ns().Actions
              local key = _G.GetBindingKey("ACTIONBUTTON1")
              local now = key and _G.GetBindingAction(key, true)
              return (A.nbinds or 0) > 0 and (not key or (now or ""):find("MyUIActionButton1", 1, true) ~= nil),
                     ("%s keys moved; %s -> %s"):format(tostring(A.nbinds), tostring(key), tostring(now))
          end },
        { id = "blizzard-bar-1", shot = false,
          what = "Blizzard's bar 1 stays shown at alpha 0 (its keybinds live), out of the registry.",
          check = function(api)
              local main = _G.MainActionBar
              if not main then return true, "no MainActionBar on this client" end
              local inReg = api.ns().Registry.Get("MainBar") ~= nil
              return main:GetAlpha() == 0 and not inReg,
                     ("shown %s, alpha %s, registered %s"):format(tostring(main:IsShown()),
                         tostring(main:GetAlpha()), tostring(inReg))
          end },
    },
})

T.Suite("myui-group", {
    title = "Round 004 -- group frames (SPEC 19, first part)",
    requires = function(api)
        local ok, why = NeedMyUI(api)
        if not ok then return ok, why end
        if not (api.ns().Group and api.ns().Group.frame) then return false, "no group frames built" end
        return true
    end,
    tests = {
        { id = "built", shot = false,
          what = "Party and raid headers built, every button made and dressed out of combat.",
          check = function(api)
              local G = api.ns().Group
              return #G.buttons >= G.PARTY_MAX, ("%d buttons dressed"):format(#G.buttons)
          end },
        { id = "blizzard-hidden", shot = false,
          what = "Blizzard's party and raid frames are hidden (nothing invisible catching clicks).",
          check = function(api)
              local shown = {}
              for _, name in ipairs(api.ns().Clear.GROUP_FRAMES) do
                  local f = _G[name]
                  if f and f:IsShown() then shown[#shown + 1] = name end
              end
              return #shown == 0, #shown == 0 and "all hidden" or ("shown: " .. table.concat(shown, ", "))
          end },
    },
})

T.Suite("myui-p4", {
    title = "Phase 4 -- bars and low health",
    requires = function(api)
        local ok, why = NeedMyUI(api)
        if not ok then return ok, why end
        if not api.ns().Bars then return false, "no Bars module" end
        return true
    end,
    tests = {
        { id = "curves", shot = false,
          what = "Every curve built on the live client (C_CurveUtil, Step type).",
          check = function(api)
              local p = api.ns().Bars.curveProblems or { "never built" }
              return #p == 0, #p == 0 and "all built" or table.concat(p, "; ")
          end },
        { id = "live-forwarding", shot = false,
          what = "Live health, power, cast and target forward with zero guard violations.",
          setup = function(api)
              local ns = api.ns()
              ns.Guard.Reset()
              ns.Bars.Suspend(false)
              ns.Bars.Refresh()
          end,
          check = function(api)
              local ns = api.ns()
              local v = ns.Guard.violations
              return #v == 0, #v == 0 and ("%d secret forwards"):format(ns.Guard.forwards)
                                       or tostring(v[1] and v[1].message)
          end,
          teardown = function(api) api.ns().Bars.Suspend(true) end },
        { id = "summon", shot = false,
          what = "The low-health summon: available, and hooked (informational if the warning is off).",
          check = function(api)
              local Bars = api.ns().Bars
              local ok, why = Bars.SummonAvailable()
              if not ok then return true, "unavailable: " .. tostring(why) end
              return Bars.summonHooked == true, Bars.summonHooked and "hooked" or "available but not hooked"
          end },
    },
})
