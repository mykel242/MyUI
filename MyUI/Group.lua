-- MyUI :: Group.lua
-- SPEC 19 (round 004), first part: MyUI's own party and raid frames, in one
-- area right of the character. A short list for a party (role, name, thin
-- health), larger for a healer, a 5-wide grid of cells for a raid.
--
-- Built on Blizzard's protected group header (SecureGroupHeaderTemplate) and
-- unit buttons (SecureUnitButtonTemplate), so roster changes are handled
-- securely in combat. Order is fixed -- role, then group order -- never by
-- health (RULES): the header sorts by assigned role or by group, both plain.
--
-- The click map (SPEC 19) is attributes on each unit button, set in the
-- restricted environment as Blizzard creates it: click targets, ctrl-click
-- focuses, right-click opens Blizzard's unit menu. Shift-click pinning, the
-- hover cards and alt-click casting come next (M3, probe P3).
--
-- Health goes through the same curve as TargetStrip -- forwarded, never read.
-- Blizzard's own party and raid frames are hidden (Clear.UNITS) once these
-- exist, so nothing invisible sits under them catching clicks.

local ADDON, ns = ...

local Scale, Palette, Guard = ns.Scale, ns.Palette, ns.Guard

local Group = {}
ns.Group = Group

local U = function(v) return Scale.U(v) end

-- Sizes in SPEC's units. A healer's party list is the action surface, so it
-- grows; a DPS's stays small (SPEC 16).
Group.SIZES = {
    party  = { w = 150, h = 24, font = 11, bar = 3 },
    healer = { w = 200, h = 34, font = 12, bar = 6 },
    raid   = { w = 56,  h = 28, font = 9,  bar = 3 },
}
-- Round 004 play: 4 between rows read as one block ("too tight").
Group.GAP = 8
Group.RAID_GAP = 4
Group.PARTY_MAX = 5
Group.RAID_MAX = 40

-- Where the list sits comes from the layout profile (Layout.lua): right of
-- the HUD's middle, clear of the right wing, growing up.

local ROLE_ATLAS = {
    TANK = "roleicon-tiny-tank",
    HEALER = "roleicon-tiny-healer",
    DAMAGER = "roleicon-tiny-dps",
}

-- Restricted: runs on each unit button as the header creates it. The click
-- map, and the size the header asks for. Numbers and strings only.
local CONFIG = [[
    local h = self:GetParent()
    self:SetWidth(h:GetAttribute("unitWidth") or 150)
    self:SetHeight(h:GetAttribute("unitHeight") or 22)
    self:SetAttribute("*type1", "target")
    self:SetAttribute("ctrl-type1", "focus")
    self:SetAttribute("*type2", "togglemenu")
]]

function Group.Kind()
    local role = ns.Clear and ns.Clear.Role and ns.Clear.Role() or "NONE"
    return role == "HEALER" and "healer" or "party"
end

-- ---------------------------------------------------------------------------
-- Unit buttons: dressing (ordinary code, out of combat, at creation)
-- ---------------------------------------------------------------------------

Group.byUnit = {}     -- unit token -> { button, ... }
Group.buttons = {}

local function Remap()
    local map = {}
    for _, b in ipairs(Group.buttons) do
        local unit = b:GetAttribute("unit")
        if unit then
            map[unit] = map[unit] or {}
            table.insert(map[unit], b)
        end
    end
    Group.byUnit = map
end

local function SizeOf(b)
    return Group.SIZES[b.__myuiKind == "raid" and "raid" or Group.Kind()]
end

--- Lay out the inside of one button for its size.
local function Dress(b)
    local sz = SizeOf(b)
    b.__name:SetFont(ns.Frames.FONT, U(sz.font), "")
    b.__name:ClearAllPoints()
    b.__health:ClearAllPoints()
    b.__health:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
    b.__health:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
    b.__health:SetHeight(U(sz.bar))
    if b.__myuiKind == "raid" then
        b.__role:Hide()
        b.__name:SetPoint("TOPLEFT", b, "TOPLEFT", U(3), -U(3))
        b.__name:SetPoint("RIGHT", b, "RIGHT", -U(2), 0)
    else
        b.__role:SetSize(U(sz.font + 2), U(sz.font + 2))
        b.__role:SetPoint("LEFT", b, "LEFT", U(2), U(sz.bar / 2))
        b.__name:SetPoint("LEFT", b.__role, "RIGHT", U(4), 0)
        b.__name:SetPoint("RIGHT", b, "RIGHT", -U(2), 0)
    end
end

function Group.Style(b, kind)
    if b.__myuiStyled then return end
    b.__myuiStyled, b.__myuiKind = true, kind
    b:RegisterForClicks("AnyUp")

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(Palette.Get("tickDark"))
    b.__bg = bg

    local health = CreateFrame("StatusBar", nil, b)
    health:SetMinMaxValues(0, 1)
    local trough = health:CreateTexture(nil, "BACKGROUND")
    trough:SetAllPoints()
    trough:SetColorTexture(Palette.Get("trough"))
    local fill = health:CreateTexture(nil, "ARTWORK")
    fill:SetColorTexture(Palette.Get("fill"))
    health:SetStatusBarTexture(fill)
    health:SetValue(1)
    b.__health = health

    -- Round 004 play (Mykel): a 1 px border while the pointer is over a
    -- member. Display only, hooked -- the button's secure click is untouched.
    local px = Scale.Hairline()
    b.__hover = {}
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local t = b:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(Palette.Get("fill"))
        if side == "TOP" or side == "BOTTOM" then
            t:SetHeight(px); t:SetPoint(side .. "LEFT"); t:SetPoint(side .. "RIGHT")
        else
            t:SetWidth(px); t:SetPoint("TOP" .. side); t:SetPoint("BOTTOM" .. side)
        end
        t:Hide()
        b.__hover[#b.__hover + 1] = t
    end
    b:HookScript("OnEnter", function(self) self.__hovered = true; Group.PaintBorder(self) end)
    b:HookScript("OnLeave", function(self) self.__hovered = false; Group.PaintBorder(self) end)

    b.__role = b:CreateTexture(nil, "ARTWORK")
    b.__name = ns.Frames.Text(b, 11, "textPrimary", "LEFT")
    if b.__name.SetWordWrap then b.__name:SetWordWrap(false) end

    Dress(b)
    b:HookScript("OnAttributeChanged", function(self, name)
        if name == "unit" then
            Remap()
            Group.UpdateButton(self)
        end
    end)
    Group.buttons[#Group.buttons + 1] = b
end

--- The border: amber while this member is your target (round 004's "gold
-- for selected", in the palette's amber), light while the pointer is over
-- it, hidden otherwise. Hover wins while it lasts.
function Group.PaintBorder(b)
    local colour = b.__hovered and "fill" or (b.__targeted and "notifAmber") or nil
    for _, t in ipairs(b.__hover or {}) do
        if colour then
            t:SetColorTexture(Palette.Get(colour))
            t:Show()
        else
            t:Hide()
        end
    end
end

--- Is this button's unit the target? UnitIsUnit is a plain answer about
-- identity; if a client ever hands it back secret, no border rather than a
-- guess.
local function IsTarget(unit)
    if not unit or not _G.UnitIsUnit then return false end
    local ok, same = pcall(_G.UnitIsUnit, unit, "target")
    if not ok or ns.Compat.IsSecret(same) then return false end
    return same == true
end

function Group.PaintTargets()
    for _, b in ipairs(Group.buttons) do
        b.__targeted = IsTarget(b:GetAttribute("unit"))
        Group.PaintBorder(b)
    end
end

-- ---------------------------------------------------------------------------
-- Painting (live data: through curves and Guard only)
-- ---------------------------------------------------------------------------

function Group.UpdateButton(b)
    local unit = b:GetAttribute("unit")
    if not unit or not (_G.UnitExists and _G.UnitExists(unit)) then return end
    Guard.Send(b.__name, "SetText", _G.UnitName(unit))
    local curves = ns.Bars and ns.Bars.curves
    local v = curves and Guard.HealthThrough(unit, curves.frac)
    if v ~= nil then Guard.Send(b.__health, "SetValue", v) end
    if b.__myuiKind ~= "raid" then
        local role = _G.UnitGroupRolesAssigned and _G.UnitGroupRolesAssigned(unit)
        local atlas = ROLE_ATLAS[role]
        if atlas then
            b.__role:SetAtlas(atlas)
            b.__role:Show()
        else
            b.__role:Hide()
        end
    end
end

function Group.UpdateUnit(unit)
    for _, b in ipairs(Group.byUnit[unit] or {}) do Group.UpdateButton(b) end
end

function Group.Refresh()
    Remap()
    for _, b in ipairs(Group.buttons) do Group.UpdateButton(b) end
    Group.PaintTargets()
end

-- ---------------------------------------------------------------------------
-- Build (out of combat only: protected headers and buttons)
-- ---------------------------------------------------------------------------

local function Header(name, parent, kind, attrs)
    local h = CreateFrame("Frame", name, parent, "SecureGroupHeaderTemplate")
    h.__myuiKind = kind
    h:SetAttribute("template", "SecureUnitButtonTemplate")
    h:SetAttribute("initialConfigFunction", CONFIG)
    for k, v in pairs(attrs) do h:SetAttribute(k, v) end
    -- Dress each unit button as the header makes it.
    h:HookScript("OnAttributeChanged", function(self, name, value)
        if type(name) == "string" and name:match("^child%d+$") and type(value) == "table" then
            Group.Style(value, self.__myuiKind)
        end
    end)
    return h
end

--- Have the header make all its buttons now, out of combat, so none is
-- created (and dressed) during a fight. The negative starting index makes
-- it count that many phantom units (the oUF pattern).
local function Precreate(h, n)
    h:SetAttribute("startingIndex", -(n - 1))
    h:Show()
    h:SetAttribute("startingIndex", 1)
end

local function SizeAttrs(sz)
    return U(sz.w), U(sz.h)
end

function Group.Build()
    if Group.frame then return true end
    if InCombatLockdown() then return false end

    local frame = CreateFrame("Frame", "MyUIGroup", UIParent)
    frame:SetFrameStrata(ns.Frames.STRATA or "MEDIUM")
    frame:SetSize(U(Group.SIZES.healer.w), U(Group.SIZES.healer.h * 5 + Group.GAP * 4))
    Group.frame = frame
    Group.Place()

    local pw, ph = SizeAttrs(Group.SIZES[Group.Kind()])
    local party = Header("MyUIPartyHeader", frame, "party", {
        showParty = true, showPlayer = true, showRaid = false, showSolo = false,
        point = "TOP", yOffset = -U(Group.GAP),
        groupBy = "ASSIGNEDROLE", groupingOrder = "TANK,HEALER,DAMAGER,NONE",
        unitWidth = pw, unitHeight = ph,
    })
    -- The header sizes itself to its rows; anchored by the bottom, it grows up.
    party:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)

    local rw, rh = SizeAttrs(Group.SIZES.raid)
    local raid = Header("MyUIRaidHeader", frame, "raid", {
        showRaid = true, showParty = false, showPlayer = true, showSolo = false,
        point = "LEFT", xOffset = U(Group.RAID_GAP),
        groupBy = "GROUP", groupingOrder = "1,2,3,4,5,6,7,8",
        unitsPerColumn = 5, maxColumns = 8,
        columnSpacing = U(Group.RAID_GAP), columnAnchorPoint = "TOP",
        unitWidth = rw, unitHeight = rh,
    })
    raid:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    Group.party, Group.raid = party, raid

    Precreate(party, Group.PARTY_MAX)
    Precreate(raid, Group.RAID_MAX)
    RegisterStateDriver(party, "visibility", "[group:raid] hide; [group:party] show; hide")
    RegisterStateDriver(raid, "visibility", "[group:raid] show; hide")

    Group.Refresh()
    return true
end

--- Anchor the group area where the profile says. Its children are protected
-- headers, so it moves out of combat only.
function Group.Place()
    if not Group.frame or InCombatLockdown() then return false end
    local point, rel, x, y = ns.Layout.Pos("Group")
    Group.frame:ClearAllPoints()
    Group.frame:SetPoint(point, UIParent, rel, U(x), U(y))
    return true
end

--- A role change (spec swap) resizes the party list -- out of combat only.
function Group.Resize()
    if not Group.party or InCombatLockdown() then return false end
    local pw, ph = SizeAttrs(Group.SIZES[Group.Kind()])
    Group.party:SetAttribute("unitWidth", pw)
    Group.party:SetAttribute("unitHeight", ph)
    for _, b in ipairs(Group.buttons) do
        if b.__myuiKind == "party" then
            b:SetSize(pw, ph)
            Dress(b)
        end
    end
    return true
end

-- ---------------------------------------------------------------------------
-- Events and login
-- ---------------------------------------------------------------------------

local UNIT_EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_NAME_UPDATE", "UNIT_CONNECTION" }

function Group.Start()
    if not Group.Build() then return false end
    ns.Registry.Add("Group", Group.frame, 0)
    local ev = CreateFrame("Frame")
    Group.events = ev
    for _, e in ipairs(UNIT_EVENTS) do ev:RegisterEvent(e) end
    ev:RegisterEvent("GROUP_ROSTER_UPDATE")
    ev:RegisterEvent("PLAYER_ROLES_ASSIGNED")
    ev:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    ev:RegisterEvent("PLAYER_TARGET_CHANGED")
    ev:SetScript("OnEvent", function(_, event, unit)
        if event == "PLAYER_TARGET_CHANGED" then
            Group.PaintTargets()
            return
        end
        if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" or event == "UNIT_NAME_UPDATE"
           or event == "UNIT_CONNECTION" then
            Group.UpdateUnit(unit)
        elseif event == "PLAYER_SPECIALIZATION_CHANGED" or event == "PLAYER_REGEN_ENABLED" then
            Group.Resize()
            Group.Refresh()
        else
            Group.Refresh()
        end
    end)
    if ns.Clear and ns.Clear.HideGroupFrames then ns.Clear.HideGroupFrames() end
    ns.Reveal.Resolve()
    ns.Reveal.Snap()
    return true
end

function Group.OnLogin()
    if Group.Start() then return end
    local wait = CreateFrame("Frame")
    wait:RegisterEvent("PLAYER_REGEN_ENABLED")
    wait:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        Group.Start()
    end)
end
