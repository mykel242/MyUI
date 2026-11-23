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
    -- 2026-11-23 (Mykel): five small boxes in a row, role icon and class
    -- colour -- the tank and DPS default, as an experiment.
    box    = { w = 64,  h = 40, font = 10, bar = 5 },
}
-- Round 004 play: 4 between rows read as one block ("too tight").
Group.GAP = 8
Group.RAID_GAP = 4
Group.BOX_GAP = 6
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

--- The party's look for the current role: "list" or "boxes" (Clear).
function Group.Look()
    return ns.Clear and ns.Clear.GroupLook and ns.Clear.GroupLook() or "list"
end

--- Which SIZES entry the party uses now.
function Group.PartySize()
    if Group.Look() == "boxes" then return "box" end
    return Group.Kind()
end

--- The party header's layout attributes for a look: a row grows right, a
-- list grows up.
function Group.PartyAttrs(look)
    if look == "boxes" then
        return { point = "LEFT", xOffset = U(Group.BOX_GAP), yOffset = 0 }
    end
    return { point = "TOP", xOffset = 0, yOffset = -U(Group.GAP) }
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
    return Group.SIZES[b.__myuiKind == "raid" and "raid" or Group.PartySize()]
end

local function IsBox(b)
    return b.__myuiKind ~= "raid" and Group.Look() == "boxes"
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
    elseif IsBox(b) then
        -- Role icon in the corner, the name under it, health along the foot.
        b.__role:SetSize(U(sz.font + 2), U(sz.font + 2))
        b.__role:SetPoint("TOPLEFT", b, "TOPLEFT", U(3), -U(3))
        b.__name:SetPoint("TOPLEFT", b.__role, "BOTTOMLEFT", 0, -U(2))
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
    b.__health, b.__fill = health, fill

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
    Group.PaintClass(b)
    b:HookScript("OnAttributeChanged", function(self, name)
        if name == "unit" then
            Remap()
            Group.UpdateButton(self)
        end
    end)
    Group.buttons[#Group.buttons + 1] = b
end

--- The class colour of a unit, or nil when it cannot be read plainly.
function Group.ClassColour(unit)
    if not unit or not _G.UnitClass then return nil end
    local ok, _, class = pcall(_G.UnitClass, unit)
    if not ok or class == nil or ns.Compat.IsSecret(class) then return nil end
    local c = _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[class]
    if type(c) ~= "table" or type(c.r) ~= "number" then return nil end
    return c.r, c.g, c.b
end

--- Boxes fill their health in the member's class colour; lists and raid
-- cells keep the palette's fill (SPEC 7).
function Group.PaintClass(b)
    if not b.__fill then return end
    local r, g, bb
    if IsBox(b) then r, g, bb = Group.ClassColour(b:GetAttribute("unit")) end
    if r then
        b.__fill:SetColorTexture(r, g, bb)
    else
        b.__fill:SetColorTexture(Palette.Get("fill"))
    end
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
    Group.PaintClass(b)
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
    Group.frame = frame
    Group.FrameSize()
    Group.Place()

    local pw, ph = SizeAttrs(Group.SIZES[Group.PartySize()])
    local attrs = {
        showParty = true, showPlayer = true, showRaid = false, showSolo = false,
        groupBy = "ASSIGNEDROLE", groupingOrder = "TANK,HEALER,DAMAGER,NONE",
        unitWidth = pw, unitHeight = ph,
    }
    for k, v in pairs(Group.PartyAttrs(Group.Look())) do attrs[k] = v end
    local party = Header("MyUIPartyHeader", frame, "party", attrs)
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
    -- Round 005: with the "group" switch off, Blizzard's party and raid
    -- frames stay and MyUI's never show.
    if ns.Switches and not ns.Switches.On("group") then
        RegisterStateDriver(party, "visibility", "hide")
        RegisterStateDriver(raid, "visibility", "hide")
    end

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

--- The group area's size: room for five of whatever the party looks like,
-- so hover finds it where the party is.
function Group.FrameSize()
    if not Group.frame then return end
    if Group.Look() == "boxes" then
        local sz = Group.SIZES.box
        Group.frame:SetSize(U(sz.w * 5 + Group.BOX_GAP * 4), U(sz.h))
    else
        local sz = Group.SIZES.healer
        Group.frame:SetSize(U(sz.w), U(sz.h * 5 + Group.GAP * 4))
    end
end

--- A role change (spec swap) or a new look resizes the party -- out of
-- combat only; a change in combat waits for it to end.
function Group.Resize()
    if not Group.party then return false end
    if InCombatLockdown() then Group.resizePending = true return false end
    Group.resizePending = false
    Group.FrameSize()
    local pw, ph = SizeAttrs(Group.SIZES[Group.PartySize()])
    Group.party:SetAttribute("unitWidth", pw)
    Group.party:SetAttribute("unitHeight", ph)
    for k, v in pairs(Group.PartyAttrs(Group.Look())) do Group.party:SetAttribute(k, v) end
    for _, b in ipairs(Group.buttons) do
        if b.__myuiKind == "party" then
            b:SetSize(pw, ph)
            Dress(b)
            Group.PaintClass(b)
        end
    end
    return true
end

--- After a role or setting change: the size and look, and whether the
-- always claim reaches the group frames now.
function Group.Apply()
    local done = Group.Resize()
    Group.Refresh()
    if ns.Reveal and ns.Reveal.Always then ns.Reveal.Always() end
    return done
end

-- ---------------------------------------------------------------------------
-- Your own bar, clickable (round 004 play)
-- ---------------------------------------------------------------------------
-- Mykel, solo: no function keys, clicking the character does not target, no
-- party frames -- "I need access to the right-click menu". An invisible
-- secure unit button over SelfStack with the same click map as a party
-- row: click targets you, ctrl-click focuses, right-click opens your menu.
-- Anchored to UIParent where the profile puts SelfStack, not to SelfStack
-- itself, so SelfStack stays free to move in combat.

local SELF_H = 33   -- SelfStack's height (Frames.lua); its width follows the pet split
-- The button (and its hover edge) reaches this far past SelfStack on every
-- side, so the edge never touches the text (round 004 play).
Group.SELF_PAD = 6

function Group.PlaceSelf()
    local b = Group.selfButton
    if not b or InCombatLockdown() then return false end
    local point, rel, x, y = ns.Layout.Pos("SelfStack")
    local F = ns.Frames
    if F.split then x = x - F.SplitOffset() end
    local pad = Group.SELF_PAD
    b:SetSize(U(F.SelfWidth() + 2 * pad), U(SELF_H + 2 * pad))
    -- Grow the box outward from whichever point SelfStack is anchored by.
    local dx = point:find("LEFT") and -pad or point:find("RIGHT") and pad or 0
    local dy = point:find("BOTTOM") and -pad or point:find("TOP") and pad or 0
    b:ClearAllPoints()
    b:SetPoint(point, UIParent, rel, U(x + dx), U(y + dy))
    return true
end

function Group.BuildSelf()
    if Group.selfButton or InCombatLockdown() then return Group.selfButton ~= nil end
    local b = CreateFrame("Button", "MyUISelfButton", UIParent, "SecureUnitButtonTemplate")
    -- Over anything of Blizzard's left at the bottom of the screen, as the
    -- action bar is (round 004 play: bar 1's frame sat on top of it).
    b:SetFrameStrata("HIGH")
    b:RegisterForClicks("AnyUp")
    b:SetAttribute("unit", "player")
    b:SetAttribute("*type1", "target")
    b:SetAttribute("ctrl-type1", "focus")
    b:SetAttribute("*type2", "togglemenu")
    -- The shared hover edge (the button already reaches SELF_PAD past the
    -- stack, so the edge sits on its own bounds).
    local edge = ns.Frames.HoverEdge(b, 0)
    b.__hover = edge.lines
    Group.selfButton = b
    Group.PlaceSelf()
    return true
end

-- ---------------------------------------------------------------------------
-- Your pet (round 004 play: a hunter's Blizzard pet frame sat in the wing)
-- ---------------------------------------------------------------------------
-- Mykel: with a pet, "two side by side MyUI frames like the character frame
-- but at 45% the width, so altogether they are the same width with a 10%
-- gap". The pet stack -- name, percentage, level, health with its danger
-- gradient, the pet's resource -- on a secure unit button for "pet": click
-- targets it, right-click the pet menu, ctrl-click focuses. Shown by a state
-- driver while a pet exists. SelfStack narrows to the left half beside it;
-- that resize, and the buttons' sizes, wait for combat to end.

Group.PET_DRIVER = "[@pet,exists] show; hide"

function Group.PlacePet()
    local b = Group.petButton
    if not b or InCombatLockdown() then return false end
    local F = ns.Frames
    local w = F.SELF_W * F.SPLIT
    local point, rel, x, y = ns.Layout.Pos("SelfStack")
    b:SetSize(U(w), U(33))
    b:ClearAllPoints()
    b:SetPoint(point, UIParent, rel, U(x + F.SplitOffset()), U(y))
    return true
end

function Group.BuildPet()
    if Group.petButton or InCombatLockdown() then return Group.petButton ~= nil end
    local F = ns.Frames
    local w = F.SELF_W * F.SPLIT
    local b = CreateFrame("Button", "MyUIPetButton", UIParent, "SecureUnitButtonTemplate")
    b:SetFrameStrata("HIGH")
    b:RegisterForClicks("AnyUp")
    b:SetAttribute("unit", "pet")
    b:SetAttribute("*type1", "target")
    b:SetAttribute("ctrl-type1", "focus")
    b:SetAttribute("*type2", "togglemenu")

    -- The same internals as SelfStack, at its height: text row, health,
    -- resource. (No cast bar: the pet's casts are not the player's.)
    local health = F.Bar(b, w, 4)
    health:SetPoint("TOPLEFT", b, "TOPLEFT", 0, -U(13))
    F.DangerGradient(health, w, 4)
    local resource = F.Bar(b, w, 2)
    resource:SetPoint("TOPLEFT", health, "BOTTOMLEFT", 0, -U(4))
    resource.fill:SetColorTexture(Palette.Get("resource"))
    local name, level = F.TextRow(b, health)
    if name.SetWordWrap then name:SetWordWrap(false) end
    local pill, number = F.Pill(b, health, 12)
    b.__health, b.__resource, b.__name, b.__level, b.__number = health, resource, name, level, number
    F.HoverEdge(b, Group.SELF_PAD)

    Group.petButton = b
    Group.PlacePet()
    RegisterStateDriver(b, "visibility", Group.PET_DRIVER)
    -- Always exactly as visible as SelfStack, beside which it sits.
    local entry = ns.Registry.Add("Pet", b, 0.35)
    entry.follows = "SelfStack"
    return true
end

function Group.UpdatePet()
    local b = Group.petButton
    if not b or not (_G.UnitExists and _G.UnitExists("pet")) then return end
    Guard.Send(b.__name, "SetText", _G.UnitName("pet"))
    local curves = ns.Bars and ns.Bars.curves
    if curves then
        local v = Guard.HealthThrough("pet", curves.frac)
        if v ~= nil then Guard.Send(b.__health, "SetValue", v) end
        local pct = Guard.HealthThrough("pet", curves.pct)
        if pct ~= nil then Guard.Send(b.__number, "SetFormattedText", "%d", pct) end
        local pw = Guard.PowerThrough("pet", curves.frac)
        if pw ~= nil then Guard.Send(b.__resource, "SetValue", pw) end
    end
    local level = _G.UnitLevel and _G.UnitLevel("pet")
    if type(level) == "number" and not ns.Compat.IsSecret(level) and level > 0 then
        b.__level:SetText(tostring(level))
    else
        b.__level:SetText("")
    end
end

-- ---------------------------------------------------------------------------
-- MyUI's pet bar (round 004 play: "I really hate this pet bar" -- 2 and 3)
-- ---------------------------------------------------------------------------
-- Blizzard's pet bar is ten fixed slots, so a hunter's three abilities and
-- three stances sit far apart. MyUI's own: only the slots that hold
-- something, packed, at mini-page size, right of the pet stack --
-- and drawn only while the pointer is on the pet stack or on the bar itself
-- (lingering a moment so it can be reached). Secure action buttons of type
-- "pet": click uses the ability or stance; right-click toggles autocast by
-- /petautocasttoggle. Icons and states come from GetPetActionInfo -- plain
-- game data. Blizzard's pet bar is held at alpha 0 (its keybinds still fire).

Group.PETBAR_SIZE = 18
Group.PETBAR_GAP = 3
Group.PETBAR_LINGER = 0.6

local function PetBarShow(on)
    local bar = Group.petBar
    if not bar then return end
    Group.petBarToken = (Group.petBarToken or 0) + 1
    if on then
        bar:SetAlpha(1)
    else
        local token = Group.petBarToken
        C_Timer.After(Group.PETBAR_LINGER, function()
            if Group.petBarToken == token then bar:SetAlpha(0) end
        end)
    end
end
Group.PetBarShow = PetBarShow

function Group.BuildPetBar()
    if Group.petBar or InCombatLockdown() then return Group.petBar ~= nil end
    local bar = CreateFrame("Frame", "MyUIPetBar", UIParent)
    bar:SetFrameStrata("HIGH")
    bar:SetSize(U(Group.PETBAR_SIZE), U(Group.PETBAR_SIZE))
    bar:SetAlpha(0)
    Group.petBar = bar
    bar.buttons = {}
    local size = U(Group.PETBAR_SIZE)
    for i = 1, 10 do
        local b = CreateFrame("Button", "MyUIPetBarButton" .. i, bar, "SecureActionButtonTemplate")
        b:SetSize(size, size)
        b:RegisterForClicks("AnyUp")
        b:SetAttribute("type", "pet")
        b:SetAttribute("action", i)
        local icon = b:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        b.__icon = icon
        -- One thin edge: amber while autocast is on, light while a stance
        -- is active, none otherwise.
        local px = Scale.Hairline()
        b.__edge = {}
        for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
            local t = b:CreateTexture(nil, "OVERLAY")
            if side == "TOP" or side == "BOTTOM" then
                t:SetHeight(px); t:SetPoint(side .. "LEFT"); t:SetPoint(side .. "RIGHT")
            else
                t:SetWidth(px); t:SetPoint("TOP" .. side); t:SetPoint("BOTTOM" .. side)
            end
            t:Hide()
            b.__edge[#b.__edge + 1] = t
        end
        ns.Frames.HoverEdge(b, 2)
        b:HookScript("OnEnter", function() PetBarShow(true) end)
        b:HookScript("OnLeave", function() PetBarShow(false) end)
        b:Hide()
        bar.buttons[i] = b
    end
    RegisterStateDriver(bar, "visibility", Group.PET_DRIVER)
    if Group.petButton then
        Group.petButton:HookScript("OnEnter", function() PetBarShow(true) end)
        Group.petButton:HookScript("OnLeave", function() PetBarShow(false) end)
    end
    Group.LayoutPetBar()
    return true
end

local function PetInfo(i)
    if not _G.GetPetActionInfo then return nil end
    local name, texture, isToken, isActive, autoAllowed, autoOn = _G.GetPetActionInfo(i)
    if not name then return nil end
    if isToken then
        name = _G[name] or name
        texture = _G[texture] or texture
    end
    return name, texture, isActive, autoAllowed, autoOn
end

--- Icons and edges (any time: display only).
function Group.PaintPetBar()
    local bar = Group.petBar
    if not bar then return end
    for i, b in ipairs(bar.buttons) do
        local name, texture, isActive, _, autoOn = PetInfo(i)
        if name then
            b.__icon:SetTexture(texture)
            local colour = autoOn and "notifAmber" or (isActive and "fill") or nil
            for _, t in ipairs(b.__edge) do
                if colour then t:SetColorTexture(Palette.Get(colour)); t:Show() else t:Hide() end
            end
        end
    end
end

--- Which slots show, packed left to right over the pet stack's left edge,
-- and each one's right-click macro. Out of combat (secure buttons).
function Group.LayoutPetBar()
    local bar = Group.petBar
    if not bar then return false end
    if InCombatLockdown() then Group.petBarPending = true return false end
    Group.petBarPending = false
    local size, gap = U(Group.PETBAR_SIZE), U(Group.PETBAR_GAP)
    local n = 0
    for i, b in ipairs(bar.buttons) do
        local name, _, _, autoAllowed = PetInfo(i)
        if name then
            b:ClearAllPoints()
            b:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", n * (size + gap), 0)
            b:SetAttribute("type2", autoAllowed and "macro" or nil)
            b:SetAttribute("macrotext2", autoAllowed and ("/petautocasttoggle " .. name) or nil)
            b:Show()
            n = n + 1
        else
            b:Hide()
        end
    end
    bar:SetWidth(math.max(1, n * (size + gap) - gap))
    -- Right of the pet stack, level with its bars (Mykel).
    local pet = Group.petButton
    bar:ClearAllPoints()
    if pet then
        bar:SetPoint("LEFT", pet.__health or pet, "RIGHT", U(10), -U(3))
    else
        bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, U(60))
    end
    Group.PaintPetBar()
    return true
end

--- Split SelfStack for the pet, or give it its full width back. Out of
-- combat (the your-bar and pet buttons are secure); a change in combat
-- waits for it to end.
function Group.UpdateSplit()
    if InCombatLockdown() then Group.splitPending = true return false end
    Group.splitPending = false
    local has = _G.UnitExists and _G.UnitExists("pet") and true or false
    ns.Frames.SetSplit(has)
    Group.PlaceSelf()
    Group.PlacePet()
    return has
end

-- ---------------------------------------------------------------------------
-- The target strip, clickable (round 004 play)
-- ---------------------------------------------------------------------------
-- Mykel: "no way to make a target mob the focus -- clicking on the mob
-- attacks it". A secure unit button for "target" over the strip, with the
-- click map: ctrl-click focuses it, right-click opens its menu, click is a
-- plain re-target. Only while there is a target.

Group.TARGET_DRIVER = "[@target,exists] show; hide"
local TARGET_W, TARGET_H, TARGET_PAD = 400, 49, 6

function Group.PlaceTarget()
    local b = Group.targetButton
    if not b or InCombatLockdown() then return false end
    local point, rel, x, y = ns.Layout.Pos("TargetStrip")
    local dx = point:find("LEFT") and -TARGET_PAD or point:find("RIGHT") and TARGET_PAD or 0
    local dy = point:find("BOTTOM") and -TARGET_PAD or point:find("TOP") and TARGET_PAD or 0
    b:SetSize(U(TARGET_W + 2 * TARGET_PAD), U(TARGET_H + 2 * TARGET_PAD))
    b:ClearAllPoints()
    b:SetPoint(point, UIParent, rel, U(x + dx), U(y + dy))
    return true
end

function Group.BuildTarget()
    if Group.targetButton or InCombatLockdown() then return Group.targetButton ~= nil end
    local b = CreateFrame("Button", "MyUITargetButton", UIParent, "SecureUnitButtonTemplate")
    b:SetFrameStrata("HIGH")
    b:RegisterForClicks("AnyUp")
    b:SetAttribute("unit", "target")
    b:SetAttribute("*type1", "target")
    b:SetAttribute("ctrl-type1", "focus")
    b:SetAttribute("*type2", "togglemenu")
    ns.Frames.HoverEdge(b, 0)   -- the button already reaches TARGET_PAD past the strip
    Group.targetButton = b
    Group.PlaceTarget()
    RegisterStateDriver(b, "visibility", Group.TARGET_DRIVER)
    return true
end

-- ---------------------------------------------------------------------------
-- Your focus (round 004 play: ctrl-click set a focus that showed nowhere)
-- ---------------------------------------------------------------------------
-- A smaller strip in the target strip's grammar -- name, percentage, level
-- over a thin health bar with the danger gradient -- above the target
-- strip. On a secure unit button for "focus": click targets the focus,
-- right-click opens its menu. Shown by a state driver while a focus exists;
-- a focus is a deliberate choice, so while it exists it is simply up.

Group.FOCUS_DRIVER = "[@focus,exists] show; hide"
local FOCUS_W, FOCUS_H = 240, 16   -- a 3 px bar under an 11pt text row

-- Round 004 play (Mykel: "the focus should move down? ... we could try
-- it"): with no target, the focus drops into the target strip's place --
-- its bar where the target's bar would be; with a target it sits above.
-- A secure state driver moves it, so it follows targets in combat too: the
-- snippet re-anchors it to the action bar's header (protected, fixed) by
-- one of two offsets computed out of combat.
-- Round 004 play (Mykel, option 1): out of combat with no target the action
-- bar is faded, so the focus drops further, into the bar's row just over
-- your own bar ("rest"); combat or a target lifts it again.
Group.FOCUS_SLOT_DRIVER = "[@target,exists] high; [combat] low; rest"
Group.FOCUS_REST = 10   -- SPEC units above the action bar's bottom
local FOCUS_SLOT = [[
    local a = self:GetFrameRef("anchor")
    if not a then return end
    self:ClearAllPoints()
    local y = (newstate == "high") and self:GetAttribute("yhigh")
              or (newstate == "low") and self:GetAttribute("ylow")
              or self:GetAttribute("yrest")
    self:SetPoint("BOTTOM", a, "BOTTOM", self:GetAttribute("xoff") or 0, y or 0)
]]

--- The two slots, as offsets from the action bar's bottom centre, or nil
-- when the profile places the focus or the target strip some other way.
function Group.FocusSlots()
    local fp, frel, fx, fy = ns.Layout.Pos("Focus")
    local tp, trel, _, ty = ns.Layout.Pos("TargetStrip")
    local _, brel, bx, by = ns.Layout.Pos("ActionBar")
    if fp ~= "BOTTOM" or frel ~= "BOTTOM" or tp ~= "BOTTOM" or trel ~= "BOTTOM" or brel ~= "BOTTOM" then
        return nil
    end
    -- The strip's bar sits 15 up from its bottom (Frames.BuildTargetStrip).
    return U(fx - bx), U(fy - by), U(ty + 15 - by)
end

function Group.PlaceFocus()
    local b = Group.focusButton
    if not b or InCombatLockdown() then return false end
    b:SetSize(U(FOCUS_W), U(FOCUS_H))
    local header = ns.Actions and ns.Actions.header
    local x, high, low = Group.FocusSlots()
    if header and x then
        b:SetFrameRef("anchor", header)
        b:SetAttribute("xoff", x)
        b:SetAttribute("yhigh", high)
        b:SetAttribute("ylow", low)
        b:SetAttribute("yrest", U(Group.FOCUS_REST))
        b:SetAttribute("_onstate-slot", FOCUS_SLOT)
        if not Group.focusSlotDriver then
            RegisterStateDriver(b, "slot", Group.FOCUS_SLOT_DRIVER)
            Group.focusSlotDriver = true
        end
        b:Execute("local newstate = self:GetAttribute('state-slot') or 'high'\n" .. FOCUS_SLOT)
        return true
    end
    local point, rel, px, py = ns.Layout.Pos("Focus")
    b:ClearAllPoints()
    b:SetPoint(point, UIParent, rel, U(px), U(py))
    return true
end

function Group.BuildFocus()
    if Group.focusButton or InCombatLockdown() then return Group.focusButton ~= nil end
    local F = ns.Frames
    local b = CreateFrame("Button", "MyUIFocusButton", UIParent, "SecureUnitButtonTemplate, SecureHandlerStateTemplate")
    b:SetFrameStrata("HIGH")
    b:RegisterForClicks("AnyUp")
    b:SetAttribute("unit", "focus")
    b:SetAttribute("*type1", "target")
    b:SetAttribute("*type2", "togglemenu")
    local health = F.Bar(b, FOCUS_W, 3)
    health:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
    F.DangerGradient(health, FOCUS_W, 3)
    local name, level = F.TextRow(b, health)
    if name.SetWordWrap then name:SetWordWrap(false) end
    local pill, number = F.Pill(b, health, 11)
    b.__health, b.__name, b.__level, b.__number = health, name, level, number
    F.HoverEdge(b, Group.SELF_PAD)
    -- Labelled like the ALT and CTRL pages (round 004 play, Mykel).
    local label = b:CreateFontString(nil, "OVERLAY")
    label:SetFont(F.FONT, U(10), "")
    label:SetTextColor(Palette.Get("notifAmber"))
    label:SetJustifyH("RIGHT")
    label:SetText("FOCUS")
    label:SetPoint("RIGHT", b, "LEFT", -U(8), 0)
    b.__label = label

    -- An x after the bar clears the focus (round 004 play). A secure macro
    -- button (/clearfocus is a protected action), drawn as two thin strokes
    -- in the dim text grey, danger red under the pointer.
    local x = CreateFrame("Button", "MyUIFocusClear", b, "SecureActionButtonTemplate")
    x:SetSize(U(14), U(14))
    x:SetPoint("LEFT", b, "RIGHT", U(8), 0)
    x:RegisterForClicks("AnyUp", "AnyDown")
    x:SetAttribute("type", "macro")
    x:SetAttribute("macrotext", "/clearfocus")
    x.__strokes = {}
    for _, angle in ipairs({ 45, -45 }) do
        local t = x:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(Palette.Get("textDim"))
        t:SetSize(U(14), Scale.Hairline() * 2)
        t:SetPoint("CENTER", x, "CENTER", 0, 0)
        if t.SetRotation then t:SetRotation(math.rad(angle)) end
        x.__strokes[#x.__strokes + 1] = t
    end
    x:HookScript("OnEnter", function(self) for _, t in ipairs(self.__strokes) do t:SetColorTexture(Palette.Get("danger")) end end)
    x:HookScript("OnLeave", function(self) for _, t in ipairs(self.__strokes) do t:SetColorTexture(Palette.Get("textDim")) end end)
    b.__clear = x
    Group.focusButton = b
    Group.PlaceFocus()
    RegisterStateDriver(b, "visibility", Group.FOCUS_DRIVER)
    -- Round 004 play: the same opacity as you and your pet.
    local entry = ns.Registry.Add("Focus", b, 0.35)
    entry.follows = "SelfStack"
    return true
end

function Group.UpdateFocus()
    local b = Group.focusButton
    if not b or not (_G.UnitExists and _G.UnitExists("focus")) then return end
    Guard.Send(b.__name, "SetText", _G.UnitName("focus"))
    local curves = ns.Bars and ns.Bars.curves
    if curves then
        local v = Guard.HealthThrough("focus", curves.frac)
        if v ~= nil then Guard.Send(b.__health, "SetValue", v) end
        local pct = Guard.HealthThrough("focus", curves.pct)
        if pct ~= nil then Guard.Send(b.__number, "SetFormattedText", "%d", pct) end
    end
    local level = _G.UnitLevel and _G.UnitLevel("focus")
    if level ~= nil and ns.Compat.IsSecret(level) then
        Guard.Send(b.__level, "SetFormattedText", "%d", level)
    elseif type(level) == "number" and level > 0 then
        b.__level:SetText(tostring(level))
    else
        b.__level:SetText("??")
    end
end

-- ---------------------------------------------------------------------------
-- Events and login
-- ---------------------------------------------------------------------------

local UNIT_EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_NAME_UPDATE", "UNIT_CONNECTION",
                      "UNIT_POWER_UPDATE", "UNIT_LEVEL" }

function Group.Start()
    if not Group.Build() then return false end
    Group.BuildSelf()
    Group.BuildPet()
    Group.BuildPetBar()
    Group.BuildFocus()
    Group.BuildTarget()
    ns.Registry.Add("Group", Group.frame, 0)
    local ev = CreateFrame("Frame")
    Group.events = ev
    for _, e in ipairs(UNIT_EVENTS) do ev:RegisterEvent(e) end
    ev:RegisterEvent("GROUP_ROSTER_UPDATE")
    ev:RegisterEvent("PLAYER_ROLES_ASSIGNED")
    ev:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    ev:RegisterEvent("PLAYER_TARGET_CHANGED")
    ev:RegisterEvent("UNIT_PET")
    ev:RegisterEvent("PET_BAR_UPDATE")
    ev:RegisterEvent("PLAYER_FOCUS_CHANGED")
    ev:SetScript("OnEvent", function(_, event, unit)
        if event == "PLAYER_TARGET_CHANGED" then
            Group.PaintTargets()
            return
        end
        if event == "PLAYER_FOCUS_CHANGED" or unit == "focus" then
            Group.UpdateFocus()
            if event == "PLAYER_FOCUS_CHANGED" then return end
        end
        if event == "PET_BAR_UPDATE" then
            Group.LayoutPetBar()
            Group.PaintPetBar()
            return
        end
        if event == "UNIT_PET" then
            if unit == "player" then Group.UpdateSplit(); Group.LayoutPetBar() end
            Group.UpdatePet()
            return
        end
        if unit == "pet" then
            Group.UpdatePet()
            return
        end
        if event == "UNIT_POWER_UPDATE" or event == "UNIT_LEVEL" then
            return   -- only the pet's matter, handled above
        elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" or event == "UNIT_NAME_UPDATE"
           or event == "UNIT_CONNECTION" then
            Group.UpdateUnit(unit)
        elseif event == "PLAYER_SPECIALIZATION_CHANGED" or event == "PLAYER_REGEN_ENABLED"
            or event == "PLAYER_ROLES_ASSIGNED" then
            Group.Apply()
            if Group.splitPending then Group.UpdateSplit() end
            if Group.petBarPending then Group.LayoutPetBar() end
        else
            Group.Refresh()
        end
    end)
    if ns.Clear and ns.Clear.HideGroupFrames then ns.Clear.HideGroupFrames() end
    Group.UpdateSplit()
    Group.UpdatePet()
    Group.UpdateFocus()
    ns.Reveal.Always()
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
