-- MyUI :: Frames.lua
-- SPEC.md 2, built once at its permanent anchor.
--
-- Phase 1 only. No behaviour, no reveal logic, no data -- every bar is an empty
-- trough and every string is blank. Position is fixed forever in this design,
-- because muscle memory is the whole argument for letting things be invisible,
-- so it has to be right before anything animates.
--
-- Every number below is the number printed in SPEC.md, wrapped in U(). If the
-- mock-canvas reading is wrong, Scale.MOCK_TO_UNIT is the single edit.

local ADDON, ns = ...

local Scale, Palette, Registry = ns.Scale, ns.Palette, ns.Registry

local Frames = {}
ns.Frames = Frames

local U = function(v) return Scale.U(v) end

-- SPEC.md specifies anchors, sizes, alphas and colours in detail and never
-- mentions frame strata. MEDIUM is the default and it works on this machine's
-- layout -- the bars are visible where the spec puts them. It is set explicitly
-- anyway, because "whatever the default happens to be" is not a decision, and a
-- HUD that shares a layer with the action bars is one Edit Mode change away
-- from disappearing behind them. Raise to HIGH if that ever happens.
Frames.STRATA = "MEDIUM"

-- SPEC.md gives type sizes in mock pixels like every other measurement, so they
-- go through the same conversion. 12pt reads as 9.6 units.
Frames.FONT = _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local FONT = Frames.FONT

local function Fill(parent, colorName, layer)
    local t = parent:CreateTexture(nil, layer or "ARTWORK")
    t:SetColorTexture(Palette.Get(colorName))
    return t
end

-- SPEC.md 7's palette is light-on-dark: near-white text, faint white troughs.
-- Over bright scenery -- desert sand, firelight, anything golden -- the whole
-- HUD washes out and the small type becomes unreadable. Found in game, and it
-- applies to every string the addon draws, not just the rail's.
--
-- A shadow costs nothing and introduces no fifteenth colour: tickDark is
-- already rgba(0,0,0,0.55), which is what a shadow wants anyway. OUTLINE is
-- stronger but thickens the type, which the design's restraint argues against,
-- so it is offered rather than imposed.
Frames.TEXT_STYLES = { shadow = true, outline = true, none = true }

function Frames.TextStyle()
    if ns.db and ns.db.textStyle and Frames.TEXT_STYLES[ns.db.textStyle] then
        return ns.db.textStyle
    end
    return "shadow"
end

-- A shadow rescues light text on a light backdrop. It does nothing for the dim
-- greys: textTertiary is rgba(115,119,126,1), a mid-grey, and mid-grey on the
-- mid-brown of a cave floor has almost no contrast in either direction. SPEC 6
-- names that exact value for the age, so this is a spec conflict rather than an
-- implementation bug -- but the age and the "+N more" count are unreadable in
-- ordinary terrain, so there is a way to lift them.
--
-- Lifting moves dim text one step UP the palette. No fifteenth colour, and
-- nothing outside SPEC 7.
Frames.CONTRAST_LEVELS = { normal = true, lift = true }

local LIFT = {
    textTertiary  = "textSecondary",
    textSecondary = "textPrimary",
}

function Frames.Contrast()
    if ns.db and ns.db.contrast and Frames.CONTRAST_LEVELS[ns.db.contrast] then
        return ns.db.contrast
    end
    return "normal"
end

local function ResolveColor(name)
    if Frames.Contrast() == "lift" and LIFT[name] then
        return LIFT[name]
    end
    return name
end

--- Apply the current legibility treatment to one string.
local function Legible(fs, size)
    local style = Frames.TextStyle()
    if style == "outline" then
        fs:SetFont(FONT, U(size), "OUTLINE")
        fs:SetShadowOffset(0, 0)
    else
        fs:SetFont(FONT, U(size), "")
        if style == "shadow" then
            local px = Scale.Hairline()
            fs:SetShadowColor(Palette.Get("tickDark"))
            fs:SetShadowOffset(px, -px)
        else
            fs:SetShadowOffset(0, 0)
        end
    end
end

--- A string in the addon's type. Every FontString goes through here so the
-- legibility treatment is one decision rather than a dozen.
function Frames.Text(parent, size, colorName, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs.__size = size
    fs.__color = colorName
    Legible(fs, size)
    fs:SetTextColor(Palette.Get(ResolveColor(colorName)))
    fs:SetJustifyH(justify)
    Frames.strings = Frames.strings or {}
    Frames.strings[#Frames.strings + 1] = fs
    return fs
end

local Text = Frames.Text

--- Re-apply the treatment to every string already created.
function Frames.RestyleText()
    for _, fs in ipairs(Frames.strings or {}) do
        Legible(fs, fs.__size)
        fs:SetTextColor(Palette.Get(ResolveColor(fs.__color)))
    end
end

--- An empty bar: a trough with a fill that carries no value yet.
-- A StatusBar rather than a plain texture, because Phase 4 forwards a secret
-- into SetValue and changing the frame type later would move the anchors this
-- phase exists to settle.
local function Bar(parent, w, h)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetSize(U(w), U(h))
    bar:SetMinMaxValues(0, 1)

    local trough = bar:CreateTexture(nil, "BACKGROUND")
    trough:SetAllPoints()
    trough:SetColorTexture(Palette.Get("trough"))
    bar.trough = trough

    local fill = bar:CreateTexture(nil, "ARTWORK")
    fill:SetColorTexture(Palette.Get("fill"))
    bar:SetStatusBarTexture(fill)
    bar.fill = fill

    -- Phase 1 has no data, so the value stays at the minimum and the fill draws
    -- nothing. Only the trough is visible, at 14% white -- which is what SPEC 2
    -- asks for and is meant to be quiet.
    bar:SetValue(0)

    return bar
end

-- ---------------------------------------------------------------------------
-- SelfStack -- BOTTOM, centred, 214 up. 240 wide, resting 0.35.
-- ---------------------------------------------------------------------------
-- Height is the sum of the internals: 4 health + 4 gap + 2 resource + 6 gap +
-- 4 cast = 20.

local function BuildSelfStack()
    local group = CreateFrame("Frame", "MyUISelfStack", UIParent)
    group:SetFrameStrata(Frames.STRATA)
    group:SetSize(U(240), U(20))
    group:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, U(214))

    local health = Bar(group, 240, 4)
    health:SetPoint("TOPLEFT", group, "TOPLEFT", 0, 0)

    local resource = Bar(group, 240, 2)
    resource:SetPoint("TOPLEFT", health, "BOTTOMLEFT", 0, -U(4))
    resource.fill:SetColorTexture(Palette.Get("resource"))

    local cast = Bar(group, 240, 4)
    cast:SetPoint("TOPLEFT", resource, "BOTTOMLEFT", 0, -U(6))

    -- 40 wide, right-aligned, 8 left of the bar group, 12pt.
    local number = Text(group, 12, "textPrimary", "RIGHT")
    number:SetSize(U(40), U(12))
    number:SetPoint("RIGHT", group, "LEFT", -U(8), 0)

    -- The compliance keystone. Static geometry, always present: the bar
    -- crossing them is the event and the player's eye does the comparison.
    -- Never computed from a value -- x = 48 and x = 96 on a 240-wide bar are
    -- the 20% and 40% marks by construction.
    local tick20 = Fill(health, "tickDark", "OVERLAY")
    tick20:SetSize(Scale.Hairline(), U(4))
    tick20:SetPoint("TOPLEFT", health, "TOPLEFT", U(48), 0)

    local tick40 = Fill(health, "fillDim", "OVERLAY")
    tick40:SetSize(Scale.Hairline(), U(4))
    tick40:SetPoint("TOPLEFT", health, "TOPLEFT", U(96), 0)

    group.health, group.resource, group.cast = health, resource, cast
    group.number, group.tick20, group.tick40 = number, tick20, tick40
    return group
end

-- ---------------------------------------------------------------------------
-- Cooldowns -- 18 below the resource bar, centred. 240 x 4, resting 0.25.
-- ---------------------------------------------------------------------------
-- The rhythm line is v2 (PLAN.md Phase 7). Only the container is built here,
-- because SPEC.md 2's anchor table lists it and this phase is what fixes
-- anchors forever. It holds no cells and does nothing.

local function BuildCooldowns(selfStack)
    local line = CreateFrame("Frame", "MyUICooldowns", UIParent)
    line:SetFrameStrata(Frames.STRATA)
    line:SetSize(U(240), U(4))
    line:SetPoint("TOP", selfStack.resource, "BOTTOM", 0, -U(18))
    return line
end

-- ---------------------------------------------------------------------------
-- TargetStrip -- TOP, centred, 20 down. 400 wide, resting 0.
-- ---------------------------------------------------------------------------
-- Height covers the internals: an 11pt name row, then 20 to the bar, 3 of bar,
-- 9 to the cast tick, 6 of tick = 49.

local function BuildTargetStrip()
    local group = CreateFrame("Frame", "MyUITargetStrip", UIParent)
    group:SetFrameStrata(Frames.STRATA)
    group:SetSize(U(400), U(49))
    group:SetPoint("TOP", UIParent, "TOP", 0, -U(20))

    local name = Text(group, 11, "textPrimary", "LEFT")
    name:SetPoint("TOPLEFT", group, "TOPLEFT", 0, 0)

    local level = Text(group, 11, "textSecondary", "RIGHT")
    level:SetPoint("TOPRIGHT", group, "TOPRIGHT", 0, 0)

    local health = Bar(group, 400, 3)
    health:SetPoint("TOPLEFT", group, "TOPLEFT", 0, -U(31))

    local cast = Fill(group, "fill", "OVERLAY")
    cast:SetSize(U(3), U(6))
    cast:SetPoint("TOP", health, "BOTTOM", 0, -U(9))

    group.name, group.level, group.health, group.cast = name, level, health, cast
    return group
end

-- ---------------------------------------------------------------------------
-- Rail -- LEFT, x = 20, vertically centred. 440 tall.
-- ---------------------------------------------------------------------------
-- SPEC.md 2 gives the rail's resting alpha as "hairline 0.14, dots per 6",
-- which is a per-element alpha rather than a frame one. 0.14 is exactly the
-- trough colour from SPEC.md 7, so the hairline takes that colour and carries
-- its alpha in the palette entry, leaving the container to rest at 1 for the
-- reveal engine to claim.
--
-- Dots are SPEC.md 6 and arrive in Phase 3 with the notification lifecycle
-- that produces them. Container width is a dot wide so they have somewhere to
-- go; SPEC does not say which side of the hairline they sit on, and at x = 20
-- rightward is the only direction with room.

local function BuildRail()
    local rail = CreateFrame("Frame", "MyUIRail", UIParent)
    rail:SetFrameStrata(Frames.STRATA)
    rail:SetSize(U(10), U(440))
    rail:SetPoint("LEFT", UIParent, "LEFT", U(20), 0)

    local hairline = Fill(rail, "trough", "ARTWORK")
    hairline:SetSize(Scale.Hairline(), U(440))
    hairline:SetPoint("TOPLEFT", rail, "TOPLEFT", 0, 0)

    rail.hairline = hairline
    return rail
end

-- ---------------------------------------------------------------------------
-- Build
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Debug
-- ---------------------------------------------------------------------------
-- Phase 1 has no data, so every FontString is empty and every bar sits at zero.
-- That is correct, and it also means the number, the name row and the 20% tick
-- cannot be judged by looking -- the dark tick is specified to read against the
-- fill, and at value 0 there is no fill for it to read against.
--
-- So the debug toggle does more than raise alpha: it puts placeholder text in
-- the strings and a nominal value in the bars, purely so their geometry can be
-- checked. Plain constants, no unit data, cleared the moment the toggle
-- releases. Phase 4 replaces the placeholders with forwarded values.

local PLACEHOLDER = { number = "100", name = "Target Name", level = "73" }
-- Between the two ticks, and that is the whole reason for the value. SPEC 2
-- says the 20% tick "reads against the fill" and the 40% tick "reads against
-- the empty trough" -- so the only fill that makes BOTH visible at once is one
-- above 0.20 and below 0.40. The first debug fill was 0.65, which buried the
-- 40% tick under a 92%-white fill and failed its own acceptance step.
Frames.DEBUG_FILL = 0.30

function Frames.Placeholders(on)
    if not Frames.built then
        return
    end
    local stack = Registry.Get("SelfStack").frame
    local strip = Registry.Get("TargetStrip").frame

    if on then
        stack.number:SetText(PLACEHOLDER.number)
        strip.name:SetText(PLACEHOLDER.name)
        strip.level:SetText(PLACEHOLDER.level)
        stack.health:SetValue(Frames.DEBUG_FILL)
        stack.resource:SetValue(Frames.DEBUG_FILL)
        stack.cast:SetValue(Frames.DEBUG_FILL)
        strip.health:SetValue(Frames.DEBUG_FILL)
    else
        stack.number:SetText("")
        strip.name:SetText("")
        strip.level:SetText("")
        stack.health:SetValue(0)
        stack.resource:SetValue(0)
        stack.cast:SetValue(0)
        strip.health:SetValue(0)
    end
    Frames.placeholders = on and true or false
end

function Frames.OnLogin()
    if Frames.built then
        return
    end

    local selfStack = BuildSelfStack()
    Registry.Add("SelfStack", selfStack, 0.35)
    Registry.Add("Cooldowns", BuildCooldowns(selfStack), 0.25)
    Registry.Add("TargetStrip", BuildTargetStrip(), 0)
    Registry.Add("Rail", BuildRail(), 1)

    Registry.Each(function(entry)
        entry.frame:SetAlpha(entry.resting)
    end)

    Frames.built = true
end
