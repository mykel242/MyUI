-- MyUI :: Reveal.lua
-- SPEC.md 4. Four channels, one arbiter -- three of them built here, since the
-- fourth is the low-health summon that arrives with Phase 4.
--
-- "All four resolve through a single arbiter that computes one target alpha per
-- frame per tick. Do not let frames manage their own visibility; that is the
-- architectural mistake this design is most vulnerable to."
--
-- So nothing outside this file calls SetAlpha on a registered frame. Channels
-- assert and release claims; the arbiter takes the highest and fades toward it.
--
-- THE CONSTRAINT THAT SHAPES EVERYTHING HERE: the arbiter compares claims, and
-- comparison requires plain numbers. From Phase 4 the low-health alpha comes
-- out of a step curve and is SECRET -- comparing it would be an inspection.
-- So the arbiter owns plain-number alpha on the registered container frames,
-- and anything curve-driven lives on their CHILDREN, where alpha multiplies
-- down the hierarchy on its own. A secret never enters this file.

local ADDON, ns = ...

local Compat, Registry, Scale = ns.Compat, ns.Registry, ns.Scale

local Reveal = {}
ns.Reveal = Reveal

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------

-- SPEC.md 4 says "within 32 units". Every other number in the spec is a
-- mock-canvas pixel, and this one is converted the same way for consistency --
-- but it is the single place the spec says "units" rather than leaving the
-- number bare, so it may not be. Flagged in STATUS; one edit if wrong.
Reveal.PROXIMITY = Scale.U(32)

Reveal.DWELL    = 0.140   -- SPEC 4: held 140ms before the cursor claims
Reveal.FADE_IN  = 0.120   -- SPEC 8
Reveal.FADE_OUT = 0.260   -- SPEC 8, slower so release settles rather than snaps

-- SPEC.md 4 says "highest claim wins" but never gives a per-channel alpha. All
-- of them claim a full reveal until told otherwise, which makes the maximum
-- trivially 1.0 today -- the arbitration is written for real values so that
-- changing any one of these is a one-line edit rather than a redesign.
--
-- SPEC's "state change" row is two channels here, combat and target, because
-- they claim different frames and collapsing them would make the audit's CLAIM
-- column useless. debug is not a SPEC channel; it is the Phase 1 toggle,
-- routed through the arbiter so there is exactly one owner of alpha.
--
-- THE MODIFIER CHANNEL IS GONE. Phase 2 built it as SPEC 4 named it, Alt or
-- Shift, and then found the problem: a conventional three-row bind layout
-- (bare 1-n, Ctrl+1-6, Alt+1-6) leaves no modifier free, so the HUD revealed
-- itself on every modified cast in a fight. That is the incidental-reveal
-- problem the 140ms dwell exists to prevent, arriving through a different door.
-- Phase 2 worked around it with a bindable hold key; the amended SPEC 4 cut the
-- channel outright instead, and the hold binding with it. Proximity covers
-- reveal-while-doing-something and peek covers reveal-because-I-want-to, and
-- one fewer channel is worth more than the option.
--
-- lowhealth joins this table in Phase 4, as the only channel that can claim
-- without the player having done anything -- which is why SPEC 4 ranks it top.
Reveal.CHANNELS = {
    -- SPEC 3/4: low health summons SelfStack, through RULES' fifth mechanism
    -- (Bars.lua hooks LowHealthFrame). Claim 1.0, held while it is shown.
    lowhealth = 1.0,
    cursor  = 1.0,
    combat  = 1.0,
    target  = 1.0,
    -- SPEC 11: adopted chat "additionally reveals on an incoming whisper and
    -- holds for 8s". A state change, event-driven, scoped to the chat frames.
    whisper = 1.0,
    peek    = 1.0,
    debug   = 1.0,
    -- Round 004 play (Mykel: "I need enough of a map to see BugSack"): out
    -- of combat the minimap stays up. /myui map peek turns it off.
    calm    = 1.0,
    -- Round 004 play (a hunter's pet flyout): while a popup that belongs to
    -- the bar is open, the bar stays up -- the pointer travelling up the
    -- flyout left the bar's proximity and it faded.
    hold    = 1.0,
    -- Round 004: something placeable is on the cursor (a spell, item or
    -- macro picked up) -- the action bar shows every page to drop it on.
    assign  = 1.0,
    quests  = 1.0,
    -- Round 005: the map on a key (Map.lua) -- the world shows through.
    map     = 0.85,
    -- 2026-11-23: group frames set to "always" for the current role.
    always  = 1.0,
}

-- SPEC.md 4 says "highest claim wins" and says nothing about ties -- but every
-- channel claims 1.0, so ties are the NORMAL case, not an edge one.
--
-- Iterating the claim table with pairs() made the credited winner depend on
-- Lua's internal table order, so it flapped between resolves: one keypress
-- logged three separate handovers at three different timestamps. The alpha was
-- never wrong, only the attribution, but the transition log is a diagnostic and
-- a diagnostic that invents events is worse than none.
--
-- Phase 2 chose its own order and raised the gap; the amended SPEC 4 now states
-- one, and THIS IS THAT ORDER rather than ours: "low health, state change,
-- peek, proximity", highest first. State change is our combat and target. It
-- differs from what Phase 2 shipped, which put peek above both -- so a peek
-- during combat is now credited to combat. The alpha is identical either way;
-- this decides only what /myui claims reports.
--
-- debug leads because it is not a SPEC channel at all but a diagnostic
-- override, and an audit that hid it would be lying about why a frame is lit.
-- lowhealth slots in directly after it in Phase 4.
Reveal.PRECEDENCE = { "debug", "lowhealth", "combat", "target", "whisper", "hold", "assign", "quests", "map", "peek", "always", "calm", "cursor" }

-- Which frames a channel may claim. SPEC 4 tabulates triggers but never says
-- which frames each one reveals; cursor proximity is per-frame by definition
-- and the rest are inferred. Flagged in STATUS.
-- nil means every registered frame.
local SCOPE = {
    -- R3b: the adopted bars come back in combat like the Edit Mode bars do,
    -- and the group frames with them.
    -- Phase 4 play: the bars no longer come back in combat (the Cooldown
    -- Manager carries cooldowns; keybinds still work). Group frames come back
    -- by role or preference -- Clear.GroupInCombat().
    -- Round 004: MyUI's own action bar (Actions.lua) comes back in combat.
    combat = { SelfStack = true, Cooldowns = true, ActionBar = true,
               WingCooldowns = true, WingUtility = true, WingBuffs = true,
               StanceBar = true, Debuffs = true,
               -- MyUI's group frames (SPEC 19), by role or preference.
               Group = function() return ns.Clear and ns.Clear.GroupInCombat() end },
    -- Round 004 play (Mykel): target something, hold ALT, tap a taunt to pull --
    -- the bar comes up with a target.
    -- The stance and pet bars sit where the stacked pages go while arranging
    -- (Mykel: hide them then); evaluated at claim time, so Actions re-claims
    -- the target when arranging starts or stops.
    -- The target strip itself follows SelfStack now (Frames.lua), so a
    -- target alone does not hold it at full.
    -- Round 005 play: a friendly NPC targeted (a vendor, a quest giver)
    -- brought up the whole Cooldown Manager -- "a lot of screen". The bar
    -- still comes for any target (healing, buffing); the wings, debuffs and
    -- stances only for something you can attack.
    target = { ActionBar = true,
               Debuffs = function() return Reveal.TargetHostile() end,
               WingCooldowns = function() return Reveal.TargetHostile() end,
               WingUtility = function() return Reveal.TargetHostile() end,
               WingBuffs = function() return Reveal.TargetHostile() end,
               StanceBar = function()
                   return Reveal.TargetHostile() and not (ns.Actions and ns.Actions.IsStacked())
               end },
    lowhealth = { SelfStack = true },
    calm = { Minimap = true, MinimapMap = true },
    -- Charon play (a druid): "missing the druid forms buttons ... showed up
    -- once I targeted an enemy. not a good UX." Holding the modifier brings
    -- the stances with the bar, and a shapeshifter keeps them up (always).
    hold = { ActionBar = true,
             StanceBar = function() return not (ns.Actions and ns.Actions.IsStacked()) end },
    assign = { ActionBar = true, WingCooldowns = true, WingUtility = true, WingBuffs = true },
    whisper = { Chat = true, ChatDock = true, ChatButtons = true, ChatSocial = true },
    -- Round 005: the quest list, opened by its key (Quests.lua).
    quests = { QuestList = true },
    map = { MinimapMap = true },
    always = { Group = function() return ns.Clear and ns.Clear.GroupAlways() end,
               StanceBar = function() return Reveal.StancesAlways() end },
}

-- ---------------------------------------------------------------------------
-- Claims
-- ---------------------------------------------------------------------------

local claims = {}   -- [frameName][channel] = alpha

-- ---------------------------------------------------------------------------
-- Transition log
-- ---------------------------------------------------------------------------
-- Every reveal channel is transient by nature, and the hardest to observe --
-- a cursor dwell -- cannot be inspected by typing a command, because the cursor
-- has to leave the frame to reach the chat box. The same was true of the
-- modifier channel before it was cut, and worse: on macOS an Option-key
-- combination inserts an accented character and Shift turns "/" into "?", so
-- the command never ran at all.
--
-- So the engine records its own transitions and you read them afterwards. This
-- is also simply a better test than watching: it shows which channel won, on
-- which frame, and when, rather than asking whether a fade felt right.

local MAX_LOG = 60
Reveal.log = {}

-- Two kinds of entry, and the distinction matters more than it looks.
--
--   "claim" / "release"  an INPUT: a channel was asserted or dropped
--   "change"             an OUTCOME: a frame's target or winner moved
--
-- The first version logged outcomes only, which made two very different things
-- produce identical lines: pressing Alt three times, and pressing it once while
-- the winner got re-attributed twice. A log that cannot tell an input from an
-- outcome cannot answer "did I do that, or did you?" -- which is the first
-- question anyone asks of it.
local function Record(entry)
    local log = Reveal.log
    entry.at = Reveal.Now()
    log[#log + 1] = entry
    if ns.Dev and ns.Dev.On() then ns.Dev.Reveal(entry) end
    if #log > MAX_LOG then
        table.remove(log, 1)
    end
end

function Reveal.ClearLog()
    Reveal.log = {}
end

--- The channels currently claiming a frame, as a sorted list of names.
function Reveal.ClaimsOn(name)
    local out = {}
    for channel in pairs(claims[name] or {}) do
        out[#out + 1] = channel
    end
    table.sort(out)
    return out
end

-- Channels that reach every frame (scope nil), less these, while the rule
-- says no. Round 004 play (/myui claims): the pointer resting above the bar
-- lit an empty target strip -- a strip with no target says nothing.
Reveal.UNLESS = {
    cursor = {
        TargetStrip = function() return not (_G.UnitExists and _G.UnitExists("target")) end,
        -- The quest list comes on its key or peek, never by passing near it.
        QuestList = function() return true end,
    },
    -- 2026-11-23 (Mykel: "peeking to the blizz chat window is annoying"):
    -- with MyUI's chat panel on, peek leaves Blizzard's chat window alone.
    peek = {
        Chat = function() return Reveal.TalkActive() end,
        ChatDock = function() return Reveal.TalkActive() end,
        ChatButtons = function() return Reveal.TalkActive() end,
        ChatSocial = function() return Reveal.TalkActive() end,
    },
}

function Reveal.TalkActive()
    return ns.Talk ~= nil and ns.Talk.Active() == true
end

local function InScope(channel, name)
    local scope = SCOPE[channel]
    if scope == nil then
        local unless = Reveal.UNLESS[channel] and Reveal.UNLESS[channel][name]
        if unless and unless() then return false end
        -- Round 004 (Mykel: "I don't want any of the Blizzard chrome except
        -- for rarely used things ... UI when you need it"): the pointer
        -- wakes only MyUI's own HUD. Blizzard's adopted frames -- cast bar,
        -- quest tracker, buffs, bags, chat -- come back on peek, or by
        -- their own events (a whisper, the calm minimap).
        if channel == "cursor" and ns.Clear and ns.Clear.IsAdopted and ns.Clear.IsAdopted(name) then
            return false
        end
        return true
    end
    local rule = scope[name]
    -- A function decides at claim time (R3b: group frames in combat depend
    -- on role or preference).
    if type(rule) == "function" then
        return rule() == true
    end
    return rule == true
end

--- Assert a claim. name omitted claims every frame the channel may reach.
--
-- This used to take a third argument naming what armed the channel, because the
-- modifier channel had two arms -- a modifier key and the hold binding -- and a
-- log that cannot tell them apart invites the guessing it exists to end. With
-- that channel cut, every remaining channel has exactly one arm, so the
-- argument is gone. Phase 4's low-health hook may want it back; it is four
-- lines here and one in the claims renderer.
function Reveal.Claim(channel, name)
    local alpha = Reveal.CHANNELS[channel]
    if alpha == nil then
        error("no reveal channel " .. tostring(channel), 2)
    end
    local changed = false
    if name then
        if not InScope(channel, name) then
            return false
        end
        claims[name] = claims[name] or {}
        changed = claims[name][channel] ~= alpha
        claims[name][channel] = alpha
    else
        Registry.Each(function(entry)
            if InScope(channel, entry.name) then
                claims[entry.name] = claims[entry.name] or {}
                if claims[entry.name][channel] ~= alpha then
                    changed = true
                end
                claims[entry.name][channel] = alpha
            end
        end)
    end
    -- Only a real change is logged. A channel can re-assert an existing claim --
    -- the proximity check runs every tick and re-claims while the cursor sits
    -- still -- and a log full of "claimed" for one dwell would be exactly the
    -- noise this is meant to remove.
    if changed then
        Record({ kind = "claim", channel = channel, frame = name })
    end
    Reveal.Resolve()
    return true
end

--- Drop a claim. name omitted releases the channel everywhere.
function Reveal.Release(channel, name)
    local changed = false
    if name then
        if claims[name] and claims[name][channel] ~= nil then
            claims[name][channel] = nil
            changed = true
        end
    else
        for _, byChannel in pairs(claims) do
            if byChannel[channel] ~= nil then
                byChannel[channel] = nil
                changed = true
            end
        end
    end
    if changed then
        Record({ kind = "release", channel = channel, frame = name })
    end
    Reveal.Resolve()
end

function Reveal.HasClaim(channel, name)
    return claims[name] ~= nil and claims[name][channel] ~= nil
end

-- ---------------------------------------------------------------------------
-- The arbiter
-- ---------------------------------------------------------------------------

--- Highest claim wins; with none, the frame returns to its resting alpha --
-- never to zero unless its resting alpha is zero (SPEC.md 4).
local function Arbitrate(entry)
    local best, winner = entry.resting, nil
    local byChannel = claims[entry.name]
    if byChannel then
        -- Fixed order plus a strict >, so the first channel in PRECEDENCE to
        -- beat the running best keeps it. A later equal claim cannot displace
        -- it, which is what makes ties deterministic.
        for _, channel in ipairs(Reveal.PRECEDENCE) do
            local alpha = byChannel[channel]
            if alpha and alpha > best then
                best, winner = alpha, channel
            end
        end
    end
    return best, winner
end

--- Recompute every frame's target. Starts a fade where the target moved.
function Reveal.Resolve()
    local now = Reveal.Now()
    Registry.Each(function(entry)
        local target, winner = Arbitrate(entry)
        -- A follower takes its leader's alpha and claim (round 004 play: the
        -- pet stack at full alpha beside a faded SelfStack). The leader is
        -- registered first, so it is already resolved in this pass.
        -- Round 004 play (Mykel: "focus and target opacity should work the
        -- same way as player and pet"): followers come up with their leader
        -- (never below it), and still answer their own claims -- a hover on
        -- one lights that one. followWhen can suspend it (no target).
        local leader = entry.follows and Registry.Get(entry.follows)
        if leader and (not entry.followWhen or entry.followWhen()) and leader.target > target then
            target, winner = leader.target, leader.claim
        end
        local previous = entry.claim
        entry.claim = winner

        -- A handover records even though the alpha does not move. When two
        -- channels overlap, the moment one releases and the other keeps the
        -- frame up is precisely what "highest claim wins" looks like, and
        -- logging only alpha changes would hide the one case worth seeing.
        if entry.target ~= target or previous ~= winner then
            Record({ kind = "change", frame = entry.name,
                     from = entry.target, to = target, winner = winner })
        end

        if entry.target ~= target then
            -- A frame that draws through alpha (the minimap's arrow and
            -- blips) is shown again before it fades in.
            if entry.hideAtZero and target > 0 and not entry.frame:IsShown() then
                entry.frame:Show()
            end
            entry.fadeFrom  = entry.current or entry.resting
            entry.fadeStart = now
            if target > (entry.current or entry.resting) then
                entry.fadeDuration = Reveal.FADE_IN
            else
                entry.fadeDuration = Reveal.FADE_OUT
            end
            entry.target = target
        end
    end)
end

--- Jump every frame to its target with no fade. For the debug toggle, which is
-- a diagnostic rather than a reveal, and for tests.
function Reveal.Snap()
    Registry.Each(function(entry)
        entry.current = entry.target
        entry.fadeStart = nil
        if entry.hideAtZero and entry.target > 0 and not entry.frame:IsShown() then
            entry.frame:Show()
        end
        entry.frame:SetAlpha(entry.current)
        Reveal.HideIfSettled(entry)
    end)
end

-- ---------------------------------------------------------------------------
-- Cursor proximity
-- ---------------------------------------------------------------------------

local function CursorPosition()
    local get = _G.GetCursorPosition
    if type(get) ~= "function" then
        return nil
    end
    local ok, x, y = pcall(get)
    if not ok or type(x) ~= "number" or type(y) ~= "number" then
        return nil
    end
    local scale = Compat.Get(_G.UIParent, "GetEffectiveScale")
    if type(scale) ~= "number" or scale <= 0 then
        return nil
    end
    return x / scale, y / scale
end

--- Distance from a point to a frame's rectangle, zero when inside it.
local function EdgeDistance(entry, x, y)
    local l = Compat.Get(entry.frame, "GetLeft")
    local r = Compat.Get(entry.frame, "GetRight")
    local b = Compat.Get(entry.frame, "GetBottom")
    local t = Compat.Get(entry.frame, "GetTop")
    if type(l) ~= "number" or type(r) ~= "number"
       or type(b) ~= "number" or type(t) ~= "number" then
        return nil
    end

    local dx = 0
    if x < l then
        dx = l - x
    elseif x > r then
        dx = x - r
    end

    local dy = 0
    if y < b then
        dy = b - y
    elseif y > t then
        dy = y - t
    end

    if dx == 0 and dy == 0 then
        return 0
    end
    return math.sqrt(dx * dx + dy * dy)
end

Reveal.EdgeDistance = EdgeDistance

--- The dwell is the whole point of this channel: it stops brushing past while
-- looting from flashing the HUD (SPEC.md 4). Entering the zone starts a clock;
-- only staying in it for DWELL asserts the claim.
-- Set by MyUI_Test while it captures screenshots: wherever the cursor happened
-- to be when the run key was pressed must not decide what the shots show.
Reveal.cursorSuspended = false

local function UpdateProximity(now)
    local x, y
    if not Reveal.cursorSuspended then
        x, y = CursorPosition()
    end
    Registry.Each(function(entry)
        local near = false
        if x then
            local d = EdgeDistance(entry, x, y)
            near = d ~= nil and d <= Reveal.PROXIMITY
        end

        if near then
            if entry.dwellSince == nil then
                entry.dwellSince = now
            end
            if now - entry.dwellSince >= Reveal.DWELL then
                if not Reveal.HasClaim("cursor", entry.name) then
                    Reveal.Claim("cursor", entry.name)
                end
            end
        else
            entry.dwellSince = nil
            if Reveal.HasClaim("cursor", entry.name) then
                Reveal.Release("cursor", entry.name)
            end
        end
    end)
end

-- ---------------------------------------------------------------------------
-- The tick
-- ---------------------------------------------------------------------------
-- One OnUpdate for the whole addon. RULES.md permits it solely for the
-- cursor-proximity check and the peek timer, and neither touches game state.

function Reveal.Now()
    local get = _G.GetTime
    if type(get) ~= "function" then
        return 0
    end
    local ok, t = pcall(get)
    if not ok or type(t) ~= "number" then
        return 0
    end
    return t
end

local function StepFade(entry, now)
    if entry.current == nil then
        entry.current = entry.resting
    end
    if entry.current == entry.target then
        Reveal.HideIfSettled(entry)
        return
    end
    if not entry.fadeStart or not entry.fadeDuration or entry.fadeDuration <= 0 then
        entry.current = entry.target
    else
        local progress = (now - entry.fadeStart) / entry.fadeDuration
        if progress >= 1 then
            entry.current = entry.target
            entry.fadeStart = nil
        else
            entry.current = entry.fadeFrom + (entry.target - entry.fadeFrom) * progress
        end
    end
    entry.frame:SetAlpha(entry.current)
    Reveal.HideIfSettled(entry)
end

--- R3b: some adopted frames draw parts of themselves regardless of alpha --
-- the minimap's player arrow and blips. Those are flagged hideAtZero, and
-- once a fade has fully settled at 0 they are hidden as well. Never a
-- protected frame: only Clear flags them, and only unprotected ones.
function Reveal.HideIfSettled(entry)
    if entry.hideAtZero and entry.current == 0 and entry.target == 0 and entry.frame:IsShown() then
        entry.frame:Hide()
    end
end

function Reveal.Tick()
    local now = Reveal.Now()
    UpdateProximity(now)
    if ns.Peek and ns.Peek.Update then
        ns.Peek.Update(now)
    end
    Registry.Each(function(entry)
        StepFade(entry, now)
    end)
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------
-- Everything except cursor proximity and the peek clock is event-driven, which
-- RULES.md requires and which is also simply cheaper.

--- Can you attack your target? Not a unit VALUE (RULES): a relation the
-- client answers plainly -- but read defensively, and anything unreadable
-- counts as friendly (less on screen).
function Reveal.TargetHostile()
    local can = _G.UnitCanAttack
    if type(can) ~= "function" then return false end
    local ok, v = pcall(can, "player", "target")
    if not ok or Compat.IsSecret(v) then return false end
    return v == true
end

local function OnTargetChanged()
    local exists = _G.UnitExists and _G.UnitExists("target")
    -- Released first: the scope depends on WHAT is targeted, so switching
    -- from a mob to a vendor must drop the wings the mob brought.
    Reveal.Release("target")
    if exists then
        Reveal.Claim("target")
    end
end

--- The calm claim: the minimap, out of combat, when the player asked for it
-- (/myui map calm). The default is peek: the map is on a key. Asked again
-- whenever combat or the setting changes, and after clearing adopts the
-- minimap.
Reveal.MAP_MODES = { calm = true, peek = true }

function Reveal.MapMode()
    local m = ns.db and ns.db.map
    return Reveal.MAP_MODES[m] and m or "peek"
end

function Reveal.Calm()
    local fighting = Reveal.inCombat or (InCombatLockdown and InCombatLockdown())
    if Reveal.MapMode() == "calm" and not fighting then
        Reveal.Claim("calm")
    else
        Reveal.Release("calm")
    end
end

--- The always claim: group frames up all the time for a role set to
-- "always". Scope is decided at claim time, so it is asked again whenever
-- the role or the setting changes.
-- Classes whose forms are travel as much as fighting: a druid shifts to
-- travel, cat (prowl) and bear out of combat, so the forms stay up.
Reveal.STANCE_CLASSES = { DRUID = true }

function Reveal.StancesAlways()
    if ns.Actions and ns.Actions.IsStacked() then return false end
    if not _G.UnitClass then return false end
    local ok, _, class = pcall(_G.UnitClass, "player")
    if not ok or type(class) ~= "string" or (ns.Compat and ns.Compat.IsSecret(class)) then
        return false
    end
    return Reveal.STANCE_CLASSES[class] == true
end

local ALWAYS = {
    Group = function() return ns.Clear ~= nil and ns.Clear.GroupAlways() == true end,
    StanceBar = function() return Reveal.StancesAlways() end,
}

function Reveal.Always()
    -- Only a real change: the debug log showed a release and a claim for
    -- every /myui group that changed nothing.
    for name, want in pairs(ALWAYS) do
        local on = want()
        if on ~= Reveal.HasClaim("always", name) then
            if on then Reveal.Claim("always", name) else Reveal.Release("always", name) end
        end
    end
end

function Reveal.OnLogin()
    local driver = CreateFrame("Frame", "MyUIRevealDriver", UIParent)
    Reveal.driver = driver

    driver:RegisterEvent("PLAYER_TARGET_CHANGED")
    driver:RegisterEvent("PLAYER_REGEN_DISABLED")
    driver:RegisterEvent("PLAYER_REGEN_ENABLED")

    driver:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_TARGET_CHANGED" then
            OnTargetChanged()
        elseif event == "PLAYER_REGEN_DISABLED" then
            Reveal.inCombat = true
            Reveal.Claim("combat")
            Reveal.Calm()
        elseif event == "PLAYER_REGEN_ENABLED" then
            Reveal.inCombat = false
            Reveal.Release("combat")
            Reveal.Calm()
        end
    end)

    driver:SetScript("OnUpdate", function()
        Reveal.Tick()
    end)

    Reveal.Resolve()
    Reveal.Snap()
end
