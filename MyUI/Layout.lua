-- MyUI :: Layout.lua
-- Round 004 play (Mykel): "significant positioning changes ... we should
-- allow for profiles, because these are certainly personal preference."
--
-- A layout profile says where the HUD's movable parts sit: SelfStack, the
-- target strip, the action bar (and so the wings, the stance and pet bars,
-- which are placed against it), and the group frames -- plus the wings'
-- spacing. Positions are in SPEC's units, the same U() every frame uses, so
-- a profile means the same thing at every readable scale.
--
-- Two built-in profiles: "focus" (the default -- the target where your
-- health used to be, you under the bar) and "spec" (SPEC 2's positions).
-- /myui move nudges the active profile; nudging a built-in one copies it to
-- "mine" first, so the built-ins never change. Profiles are account-wide;
-- which one is active is too (one player, several characters, one taste).
--
-- Moving secure frames (the bar, the group headers' parent) and saving the
-- Edit Mode layout are protected in combat: Apply waits for it to end.

local ADDON, ns = ...

local Layout = {}
ns.Layout = Layout

-- Each frame: { point, relativePoint, x, y } against UIParent.
Layout.PRESETS = {
    -- Bottom up: you (SelfStack) under the bar, the bar, the row above it
    -- (utility, stance, chosen buffs), then the target strip where your
    -- health used to sit, with room left between each so it reads open.
    -- The group list sits right of the target strip, above the right wing.
    -- Round 004 play: the target strip brought down to sit just over the
    -- row above the bar (stance, pet); the group list and Blizzard's zone /
    -- extra ability button either side of it, both clear of the wings.
    focus = {
        SelfStack   = { "BOTTOM", "BOTTOM", 0, 24 },
        ActionBar   = { "BOTTOM", "BOTTOM", 0, 76 },
        TargetStrip = { "BOTTOM", "BOTTOM", 0, 162 },
        Group       = { "BOTTOMLEFT", "BOTTOM", 224, 176 },
        -- Left of the strip, mirroring the group list: the Cooldown
        -- Manager's tracked buff bars (round 004 play: they sat on top of
        -- the zone button), and the zone / extra ability button beyond them.
        BuffBars    = { "BOTTOMRIGHT", "BOTTOM", -224, 176 },
        ZoneAbility = { "BOTTOMRIGHT", "BOTTOM", -460, 176 },
        wingGap     = 32,
        iconPadding = 6,
    },
    -- SPEC 2 as handed off, with round 004's bar and group placement.
    spec = {
        SelfStack   = { "BOTTOM", "BOTTOM", 0, 214 },
        ActionBar   = { "BOTTOM", "BOTTOM", 0, 48 },
        TargetStrip = { "TOP", "TOP", 0, -20 },
        Group       = { "BOTTOMLEFT", "BOTTOM", 140, 150 },
        BuffBars    = { "BOTTOMRIGHT", "BOTTOM", -240, 150 },
        ZoneAbility = { "BOTTOM", "BOTTOM", 0, 280 },
        wingGap     = 32,
        iconPadding = 2,
    },
}
Layout.DEFAULT = "focus"

-- The names /myui move takes.
Layout.ALIASES = {
    self = "SelfStack", me = "SelfStack", health = "SelfStack",
    target = "TargetStrip", bar = "ActionBar", bars = "ActionBar",
    group = "Group", party = "Group", raid = "Group",
    zone = "ZoneAbility", extra = "ZoneAbility", ability = "ZoneAbility",
    timers = "BuffBars", buffbars = "BuffBars",
}

local function DB()
    local db = ns.db
    if not db then return {} end
    db.layout = db.layout or {}
    db.layout.saved = db.layout.saved or {}
    return db.layout
end

local function Copy(t)
    if type(t) ~= "table" then return t end
    local o = {}
    for k, v in pairs(t) do o[k] = Copy(v) end
    return o
end

function Layout.Active()
    local name = DB().active
    if name and (Layout.PRESETS[name] or DB().saved[name]) then return name end
    return Layout.DEFAULT
end

function Layout.IsPreset(name)
    return Layout.PRESETS[name] ~= nil and DB().saved[name] == nil
end

--- The active profile, every key filled (a saved profile missing a key --
-- an older one -- falls back to the default's).
function Layout.Get()
    local name = Layout.Active()
    local p = DB().saved[name] or Layout.PRESETS[name]
    local base = Layout.PRESETS[Layout.DEFAULT]
    return setmetatable({}, { __index = function(_, k)
        if p[k] ~= nil then return p[k] end
        return base[k]
    end })
end

--- A frame's anchor: point, relativePoint, x, y in SPEC units.
function Layout.Pos(key)
    local a = Layout.Get()[key]
    return a[1], a[2], a[3], a[4]
end

function Layout.Value(key)
    return Layout.Get()[key]
end

function Layout.Names()
    local names = {}
    for name in pairs(Layout.PRESETS) do names[#names + 1] = name end
    for name in pairs(DB().saved) do
        if not Layout.PRESETS[name] then names[#names + 1] = name end
    end
    table.sort(names)
    return names
end

-- ---------------------------------------------------------------------------
-- Changing it
-- ---------------------------------------------------------------------------

function Layout.Use(name)
    if not (Layout.PRESETS[name] or DB().saved[name]) then return nil end
    DB().active = name
    Layout.Apply()
    return name
end

--- Save the active profile under a new name and switch to it.
function Layout.Save(name)
    if type(name) ~= "string" or name == "" then return nil end
    local src = DB().saved[Layout.Active()] or Layout.PRESETS[Layout.Active()]
    DB().saved[name] = Copy(src)
    DB().active = name
    return name
end

--- Nudge one frame. A built-in profile is copied to "mine" first.
function Layout.Move(key, dx, dy)
    key = Layout.ALIASES[key] or key
    if not Layout.PRESETS[Layout.DEFAULT][key] or type(Layout.PRESETS[Layout.DEFAULT][key]) ~= "table" then
        return nil
    end
    if Layout.IsPreset(Layout.Active()) then
        local from = Layout.Active()
        DB().saved.mine = Copy(Layout.PRESETS[from])
        DB().active = "mine"
    end
    local p = DB().saved[Layout.Active()]
    p[key] = p[key] or Copy(Layout.PRESETS[Layout.DEFAULT][key])
    p[key][3] = p[key][3] + (dx or 0)
    p[key][4] = p[key][4] + (dy or 0)
    Layout.Apply()
    return key, p[key][3], p[key][4]
end

--- Set a spacing value (wingGap, iconPadding) on the active profile.
function Layout.Set(key, value)
    if type(Layout.PRESETS[Layout.DEFAULT][key]) ~= "number" or type(value) ~= "number" then return nil end
    if Layout.IsPreset(Layout.Active()) then
        DB().saved.mine = Copy(Layout.PRESETS[Layout.Active()])
        DB().active = "mine"
    end
    DB().saved[Layout.Active()][key] = value
    Layout.Apply()
    return value
end

function Layout.Delete(name)
    if not DB().saved[name] then return nil end
    DB().saved[name] = nil
    if DB().active == name then DB().active = nil end
    Layout.Apply()
    return name
end

-- ---------------------------------------------------------------------------
-- Applying it
-- ---------------------------------------------------------------------------

--- Put everything where the active profile says. MyUI's own plain frames
-- move now; the bar, the group frames and the Edit Mode layout (the wings,
-- the stance and pet bars) wait for combat to end.
function Layout.Apply()
    if ns.Frames and ns.Frames.Place then ns.Frames.Place() end
    local function secure()
        if ns.Actions and ns.Actions.Place then ns.Actions.Place() end
        if ns.Group and ns.Group.Place then ns.Group.Place() end
        if ns.Clear and ns.Clear.Enabled and ns.Clear.Enabled() and ns.Clear.ApplyLayout then
            ns.Clear.ApplyLayout()
            if ns.Reveal then ns.Reveal.Snap() end
        end
    end
    if ns.Clear and ns.Clear.Defer then
        ns.Clear.Defer("layout-profile", secure)
    elseif not InCombatLockdown() then
        secure()
    end
end
