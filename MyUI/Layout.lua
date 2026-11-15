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
    -- Round 004 play: stances moved under the cooldowns, so the target
    -- strip comes down to just over the bar (its cast tick clear of it).
    -- The zone / extra ability button, shrunk, sits right of SelfStack,
    -- under bar 1's last buttons (Mykel: "under the [8] button").
    focus = {
        SelfStack   = { "BOTTOM", "BOTTOM", 0, 24 },
        ActionBar   = { "BOTTOM", "BOTTOM", 0, 76 },
        TargetStrip = { "BOTTOM", "BOTTOM", 0, 132 },
        Group       = { "BOTTOMLEFT", "BOTTOM", 224, 176 },
        -- Left of the strip, mirroring the group list: the Cooldown
        -- Manager's tracked buff bars.
        BuffBars    = { "BOTTOMRIGHT", "BOTTOM", -224, 176 },
        -- On bar 1's row, past button 8 (Mykel: "line it up with the action
        -- bars"). Its container lays the button out off-centre (~39 right of
        -- this anchor); the height is Mykel's own, set in game with
        -- /myui move zone and baked in here.
        ZoneAbility = { "BOTTOM", "BOTTOM", 250, 39 },
        -- The debuffs on bar 1's row start past the zone button.
        debuffGap   = 128,
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
        debuffGap   = 32,
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
    if Layout.previewing then Layout.PlaceBoxes() end
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

-- ---------------------------------------------------------------------------
-- Preview: where everything goes, including what is not up right now
-- ---------------------------------------------------------------------------
-- Mykel: "a way to peek at where the frames are for elements that are
-- currently missing (like the debuffs)". /myui layout draws a labelled box
-- for each placed element at the size it will roughly take -- Blizzard's
-- debuffs, zone button, cooldown viewers, stance and pet bars, buff bars, and
-- MyUI's group list -- and holds every MyUI frame visible (the debug claim).
-- MyUI's own frames; nothing of Blizzard's is touched.

-- Rough sizes in UI units: what a few of each would take.
Layout.PREVIEW = {
    { key = "Essential",    label = "Cooldowns",     w = 3 * 61, h = 55 },
    { key = "Utility",      label = "Utility",       w = 5 * 36, h = 30 },
    { key = "BuffIcon",     label = "Chosen buffs",  w = 4 * 38, h = 32 },
    { key = "StanceBar",    label = "Stances",       w = 3 * 36, h = 30 },
    { key = "PetActionBar", label = "Pet bar",       w = 5 * 36, h = 30 },
    { key = "Debuffs",      label = "Debuffs",       w = 4 * 49, h = 43 },
    { key = "BuffBars",     label = "Buff bars",     w = 220,    h = 64 },
    -- The zone button lands ~39 right of and ~43 above its anchor.
    { key = "ZoneAbility",  label = "Zone",          w = 50,     h = 50, dx = 39, dy = 43 - 25, centre = true },
    { key = "Group",        label = "Group",         w = 150,    h = 5 * 32, group = true },
}

local boxes = {}

local function Box(spec)
    local b = boxes[spec.key]
    if b then return b end
    b = CreateFrame("Frame", nil, UIParent)
    b:SetFrameStrata("TOOLTIP")
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(ns.Palette.Get("tickDark"))
    local px = ns.Scale.Hairline and ns.Scale.Hairline() or 1
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local t = b:CreateTexture(nil, "BORDER")
        t:SetColorTexture(ns.Palette.Get("notifAmber"))
        if side == "TOP" or side == "BOTTOM" then
            t:SetHeight(px); t:SetPoint(side .. "LEFT"); t:SetPoint(side .. "RIGHT")
        else
            t:SetWidth(px); t:SetPoint("TOP" .. side); t:SetPoint("BOTTOM" .. side)
        end
    end
    local label = ns.Frames.Text(b, 10, "textPrimary", "CENTER")
    label:SetPoint("CENTER")
    label:SetText(spec.label)
    b.label = label
    boxes[spec.key] = b
    return b
end

function Layout.PlaceBoxes()
    local Clear = ns.Clear
    for _, spec in ipairs(Layout.PREVIEW) do
        local b = Box(spec)
        local point, x, y, rel = Clear.Anchor(spec.key)
        b:SetSize(spec.w, spec.h)
        b:ClearAllPoints()
        if spec.centre then
            b:SetPoint("CENTER", UIParent, rel or "BOTTOM", x + ns.Scale.U(spec.dx or 0), y + ns.Scale.U(spec.dy or 0))
        else
            b:SetPoint(point, UIParent, rel or "BOTTOM", x, y)
        end
    end
end

function Layout.Preview(on)
    if on == nil then on = not Layout.previewing end
    Layout.previewing = on and true or false
    if on then
        Layout.PlaceBoxes()
        for _, b in pairs(boxes) do b:Show() end
        if ns.Reveal then ns.Reveal.Claim("debug") end
    else
        for _, b in pairs(boxes) do b:Hide() end
        if ns.Reveal then ns.Reveal.Release("debug") end
    end
    return Layout.previewing
end
