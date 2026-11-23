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
    -- 2026-11-23 (Mykel): "All the unit frames above the action bars which
    -- move down." Bottom up: the bar at the foot, the row above it (utility,
    -- stance, chosen buffs), then the unit frames in one stack that never
    -- overlaps -- you, your target, your focus -- each the target's width,
    -- each labelled. The group list sits right of the target strip.
    -- Mykel: "the frames need to move down to avoid leaving gaps (focus w/o
    -- target)": with no target the focus drops into the target's place
    -- (Group.FOCUS_SLOT_DRIVER), in combat too.
    -- The zone / extra ability button, shrunk, sits right of the bar's end
    -- (Mykel's own height from round 004, when it sat under button 8).
    focus = {
        ActionBar   = { "BOTTOM", "BOTTOM", 0, 24 },
        -- The bar's rows reach ~94: you 16 over them, then 14 between each
        -- frame (SelfStack 33 tall, the target strip 49).
        SelfStack   = { "BOTTOM", "BOTTOM", 0, 110 },
        TargetStrip = { "BOTTOM", "BOTTOM", 0, 157 },
        Focus       = { "BOTTOM", "BOTTOM", 0, 220 },
        -- Charon play: at 224 the party icons sat 2 past the focus's clear
        -- x (focus edge 200, the x 208-222). 26 clear of it now.
        Group       = { "BOTTOMLEFT", "BOTTOM", 248, 170 },
        -- Blizzard's experience and second status bars, out of the way at
        -- the top edge (round 004 play).
        StatusBars  = { "TOP", "TOP", 0, 0 },
        -- Left of the strip, mirroring the group list: the Cooldown
        -- Manager's tracked buff bars, over the left wing's rows, growing up.
        -- Only x is a position: y is how far above the chosen buffs' row
        -- (the preview showed a fixed height overlapping it).
        -- Mirrors the party (Mykel: "I do like the grid to be tidy").
        BuffBars    = { "BOTTOMRIGHT", "BOTTOM", -248, 0 },
        -- On bar 1's row, past button 8 (Mykel: "line it up with the action
        -- bars"). Its container lays the button out off-centre (~39 right of
        -- this anchor); the height is Mykel's own, set in game with
        -- /myui move zone and baked in here.
        ZoneAbility = { "BOTTOM", "BOTTOM", 250, 39 },
        -- Round 005 play: Blizzard's tooltip out of the middle of the fight,
        -- into the bottom-right corner, growing up -- from over the debuff
        -- row, which on the laptop reaches under it.
        Tooltip     = { "BOTTOMRIGHT", "BOTTOMRIGHT", -16, 144 },
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
        Focus       = { "TOP", "TOP", 0, -90 },
        StatusBars  = { "TOP", "TOP", 0, 0 },
        BuffBars    = { "BOTTOMRIGHT", "BOTTOM", -240, 0 },
        ZoneAbility = { "BOTTOM", "BOTTOM", 0, 280 },
        Tooltip     = { "BOTTOMRIGHT", "BOTTOMRIGHT", -16, 144 },
        debuffGap   = 32,
        wingGap     = 32,
        iconPadding = 2,
    },
}
Layout.DEFAULT = "focus"

-- The names /myui move takes.
Layout.ALIASES = {
    self = "SelfStack", me = "SelfStack", health = "SelfStack",
    target = "TargetStrip", bar = "ActionBar", bars = "ActionBar", focus = "Focus",
    group = "Group", party = "Group", raid = "Group",
    zone = "ZoneAbility", extra = "ZoneAbility", ability = "ZoneAbility",
    timers = "BuffBars", buffbars = "BuffBars",
    tooltip = "Tooltip", tip = "Tooltip",
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

--- The active profile, every key filled. A saved profile holds only what
-- the player changed, over the built-in it came from (`base`), so a later
-- change to that built-in still reaches it (round 004 play: a full copy
-- kept an old target-strip height).
function Layout.Get()
    local name = Layout.Active()
    local saved = DB().saved[name]
    local p = saved or Layout.PRESETS[name]
    local base = Layout.PRESETS[saved and saved.base or Layout.DEFAULT] or Layout.PRESETS[Layout.DEFAULT]
    return setmetatable({}, { __index = function(_, k)
        if p[k] ~= nil then return p[k] end
        return base[k]
    end })
end

--- The saved profile to change: the active one, or a new "mine" over the
-- active built-in.
local function Editable()
    local active = Layout.Active()
    if Layout.IsPreset(active) then
        DB().saved.mine = { base = active }
        DB().active = "mine"
    end
    return DB().saved[Layout.Active()]
end

--- A frame's anchor: point, relativePoint, x, y in SPEC units.
function Layout.Pos(key)
    -- A part this character moved to one of its places (Places.lua).
    if ns.Places then
        local p, rel, x, y = ns.Places.Pos(key)
        if p then return p, rel, x, y end
    end
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
    local active = Layout.Active()
    DB().saved[name] = DB().saved[active] and Copy(DB().saved[active]) or { base = active }
    DB().active = name
    return name
end

--- Nudge one frame. A built-in profile is copied to "mine" first.
function Layout.Move(key, dx, dy)
    key = Layout.ALIASES[key] or key
    if not Layout.PRESETS[Layout.DEFAULT][key] or type(Layout.PRESETS[Layout.DEFAULT][key]) ~= "table" then
        return nil
    end
    local current = Copy(Layout.Get()[key])
    local p = Editable()
    p[key] = current
    p[key][3] = p[key][3] + (dx or 0)
    p[key][4] = p[key][4] + (dy or 0)
    Layout.Apply()
    return key, p[key][3], p[key][4]
end

--- Set a spacing value (wingGap, iconPadding) on the active profile.
function Layout.Set(key, value)
    if type(Layout.PRESETS[Layout.DEFAULT][key]) ~= "number" or type(value) ~= "number" then return nil end
    Editable()[key] = value
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
        if ns.Group and ns.Group.PlaceSelf then ns.Group.PlaceSelf() end
        if ns.Group and ns.Group.PlacePet then ns.Group.PlacePet() end
        if ns.Group and ns.Group.PlaceFocus then ns.Group.PlaceFocus() end
        if ns.Group and ns.Group.PlaceTarget then ns.Group.PlaceTarget() end
        if ns.Clear and ns.Clear.Enabled and ns.Clear.Enabled() and ns.Clear.ApplyLayout then
            local _, err = ns.Clear.ApplyLayout()
            ns.Clear.HintLayout(err)
            if ns.Reveal then ns.Reveal.Snap() end
            -- Saving an Edit Mode layout from addon code taints what Edit
            -- Mode touches; a reload starts Blizzard's frames clean.
            if ns.Clear.layoutUntouched == false and not Layout.reloadHinted then
                Layout.reloadHinted = true
                ns.Print("|cffadb1b8/reload when you're done moving things, so Blizzard's frames start clean|r")
            end
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
    { key = "Debuffs",      label = "Debuffs",       w = 4 * 49, h = 43 },
    { key = "BuffBars",     label = "Buff bars",     w = 220,    h = 64 },
    -- The zone button's centre lands ~27 right of and ~71 above its anchor
    -- (measured from the preview in game).
    { key = "ZoneAbility",  label = "Zone",          w = 50,     h = 50, dx = 27, dy = 71, centre = true },
    { key = "Group",        label = "Group",         w = 150,    h = 5 * 32, group = true, spec = true },
    { key = "Tooltip",      label = "Tooltip",       w = 250,    h = 90 },
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
    -- Top-left, small, amber: clear of whatever is drawn in the box.
    local label = ns.Frames.Text(b, 9, "textPrimary", "LEFT")
    label:SetTextColor(ns.Palette.Get("notifAmber"))
    label:SetPoint("BOTTOMLEFT", b, "TOPLEFT", 2, 2)
    label:SetText(spec.label)
    b.label = label
    -- Drag a box to the side it should go to: it snaps to that part's place
    -- there (Places.lua). Boxes of parts that do not move take no mouse.
    if ns.Places and ns.Places.BOXES[spec.key] then
        b:EnableMouse(true)
        b:SetMovable(true)
        b:RegisterForDrag("LeftButton")
        b:SetScript("OnDragStart", function(self)
            if not InCombatLockdown() then self:StartMoving() end
        end)
        b:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            local x = _G.GetCursorPosition()
            local width = UIParent:GetWidth() * UIParent:GetEffectiveScale()
            ns.Places.Drop(spec.key, width > 0 and x / width or 0.5)
        end)
    end
    boxes[spec.key] = b
    return b
end

function Layout.PlaceBoxes()
    local Clear = ns.Clear
    for _, spec in ipairs(Layout.PREVIEW) do
        local b = Box(spec)
        local point, x, y, rel = Clear.Anchor(spec.key)
        -- MyUI's own frames are sized in SPEC units; Blizzard's in its own.
        if spec.spec then
            b:SetSize(ns.Scale.U(spec.w), ns.Scale.U(spec.h))
        else
            b:SetSize(spec.w, spec.h)
        end
        b:ClearAllPoints()
        if spec.centre and (rel or "BOTTOM") == "BOTTOM" then
            b:SetPoint("CENTER", UIParent, rel or "BOTTOM", x + ns.Scale.U(spec.dx or 0), y + ns.Scale.U(spec.dy or 0))
        else
            b:SetPoint(point, UIParent, rel or "BOTTOM", x, y)
        end
    end
end

-- The HUD's frames, held visible while previewing -- not chat, the
-- minimap or the tracker, which the whole-screen debug claim also lit.
Layout.HUD = { "SelfStack", "Pet", "TargetStrip", "Focus", "ActionBar", "Group", "Debuffs", "StanceBar",
               "WingCooldowns", "WingUtility", "WingBuffs" }

function Layout.Preview(on)
    if on == nil then on = not Layout.previewing end
    Layout.previewing = on and true or false
    for _, name in ipairs(Layout.HUD) do
        if ns.Reveal and ns.Registry.Get(name) then
            if on then ns.Reveal.Claim("debug", name) else ns.Reveal.Release("debug", name) end
        end
    end
    if on then
        Layout.PlaceBoxes()
        for _, b in pairs(boxes) do b:Show() end
    else
        for _, b in pairs(boxes) do b:Hide() end
    end
    return Layout.previewing
end
