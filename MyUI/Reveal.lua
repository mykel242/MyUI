-- MyUI :: Reveal.lua
-- SPEC.md 4. Four channels, one arbiter.
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
Reveal.CHANNELS = {
    cursor   = 1.0,
    modifier = 1.0,
    combat   = 1.0,
    target   = 1.0,
    peek     = 1.0,
    debug    = 1.0,
}

-- SPEC.md 4 says "highest claim wins" and says nothing about ties -- but every
-- channel claims 1.0, so ties are the NORMAL case, not an edge one.
--
-- Iterating the claim table with pairs() made the credited winner depend on
-- Lua's internal table order, so it flapped between resolves: one Alt press
-- logged three separate handovers at three different timestamps. The alpha was
-- never wrong, only the attribution, but the transition log is a diagnostic and
-- a diagnostic that invents events is worse than none.
--
-- Ordered most deliberate first, so what gets credited is the thing the player
-- actually did. debug leads because it is an override and the audit should say
-- so; cursor trails because it is the one claim you can make by accident.
Reveal.PRECEDENCE = { "debug", "peek", "modifier", "combat", "target", "cursor" }

-- Which frames a channel may claim. SPEC 4 tabulates triggers but never says
-- which frames each one reveals; cursor proximity is per-frame by definition
-- and the rest are inferred. Flagged in STATUS.
-- nil means every registered frame.
local SCOPE = {
    combat = { SelfStack = true, Cooldowns = true },
    target = { TargetStrip = true },
}

-- ---------------------------------------------------------------------------
-- Claims
-- ---------------------------------------------------------------------------

local claims = {}   -- [frameName][channel] = alpha

-- ---------------------------------------------------------------------------
-- Transition log
-- ---------------------------------------------------------------------------
-- Every reveal channel is transient by nature, and the two that are hardest to
-- observe -- a held modifier and a cursor dwell -- cannot be inspected by
-- typing a command, because typing while holding a modifier produces something
-- other than the command. On macOS Option-key combinations insert accented
-- characters and Shift turns "/" into "?", so the command never runs at all.
--
-- So the engine records its own transitions and you read them afterwards. This
-- is also simply a better test than watching: it shows which channel won, on
-- which frame, and when, rather than asking whether a fade felt right.

local MAX_LOG = 40
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

local function InScope(channel, name)
    local scope = SCOPE[channel]
    if scope == nil then
        return true
    end
    return scope[name] == true
end

--- Assert a claim. name omitted claims every frame the channel may reach.
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
    -- Only a real change is logged. A modifier event can repeat while the key
    -- is held, and a log full of "claimed" for a key you pressed once would be
    -- exactly the noise this is meant to remove.
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
        entry.frame:SetAlpha(entry.current)
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
local function UpdateProximity(now)
    local x, y = CursorPosition()
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

-- SPEC.md 4 names "Alt (primary) or Shift" and that is the default. But Alt
-- and Shift are what most players bind their ability modifiers to, and a HUD
-- that flashes on every modified cast during a fight is the opposite of a
-- design whose premise is that at rest the screen is the game. The dwell exists
-- to stop incidental reveals; this is the same problem arriving through a
-- different door.
--
-- So which keys arm the channel is configurable, and turning it off entirely is
-- a supported answer. Slash commands only, per the handoff's scoping decision.
local MODIFIER_KEYS = {
    alt   = "IsAltKeyDown",
    shift = "IsShiftKeyDown",
    ctrl  = "IsControlKeyDown",
}

Reveal.DEFAULT_MODIFIERS = { alt = true, shift = true }

function Reveal.Modifiers()
    if ns.db and ns.db.modifiers then
        return ns.db.modifiers
    end
    return Reveal.DEFAULT_MODIFIERS
end

--- Set which keys arm the modifier channel. An empty list disables it.
-- Returns the accepted set, or nil plus the unknown name.
function Reveal.SetModifiers(names)
    local set = {}
    for _, name in ipairs(names) do
        name = name:lower()
        if name ~= "none" then
            if not MODIFIER_KEYS[name] then
                return nil, name
            end
            set[name] = true
        end
    end
    if ns.db then
        ns.db.modifiers = set
    end
    Reveal.Release("modifier")
    return set
end

local function AnyModifierDown()
    for name in pairs(Reveal.Modifiers()) do
        local fn = _G[MODIFIER_KEYS[name]]
        if type(fn) == "function" then
            local ok, down = pcall(fn)
            if ok and down then
                return true
            end
        end
    end
    return false
end

local function OnModifier()
    if AnyModifierDown() then
        Reveal.Claim("modifier")
    else
        Reveal.Release("modifier")
    end
end

Reveal.AnyModifierDown = AnyModifierDown

local function OnTargetChanged()
    local exists = _G.UnitExists and _G.UnitExists("target")
    if exists then
        Reveal.Claim("target")
    else
        Reveal.Release("target")
    end
end

function Reveal.OnLogin()
    local driver = CreateFrame("Frame", "MyUIRevealDriver", UIParent)
    Reveal.driver = driver

    driver:RegisterEvent("MODIFIER_STATE_CHANGED")
    driver:RegisterEvent("PLAYER_TARGET_CHANGED")
    driver:RegisterEvent("PLAYER_REGEN_DISABLED")
    driver:RegisterEvent("PLAYER_REGEN_ENABLED")

    driver:SetScript("OnEvent", function(_, event)
        if event == "MODIFIER_STATE_CHANGED" then
            OnModifier()
        elseif event == "PLAYER_TARGET_CHANGED" then
            OnTargetChanged()
        elseif event == "PLAYER_REGEN_DISABLED" then
            Reveal.Claim("combat")
        elseif event == "PLAYER_REGEN_ENABLED" then
            Reveal.Release("combat")
        end
    end)

    driver:SetScript("OnUpdate", function()
        Reveal.Tick()
    end)

    Reveal.Resolve()
    Reveal.Snap()
end
