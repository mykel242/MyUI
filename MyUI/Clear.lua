-- MyUI :: Clear.lua
-- SPEC.md 11: clearing the screen is MyUI's job. R3b brings it forward from
-- Phase 6b, minus the replacements (PLAN R3b).
--
-- This file does the part that is certain: ADOPTION. Chat, minimap and bags
-- are registered at resting alpha 0 and revealed by the ordinary engine --
-- hidden never means lost, because proximity and peek summon them. Alpha only,
-- so nothing here is protected and nothing here waits for combat to end.
--
-- Then the parts that touch protected frames, all out of combat only:
--   * player, target and focus frames: UnregisterAllEvents + Hide (Mykel's R3b
--     ruling, after the in-game probe showed the roleset filter does not hide
--     anything -- API-NOTES 13). Undone by /myui restore plus a /reload, since
--     Blizzard's event registrations cannot be put back from outside.
--   * a "MyUI" Edit Mode layout with the action bars visible only in combat.
--
-- It also carries the PROBE for the player frame. SPEC 11 filters it by
-- roleset; whether an undefined roleset actually filters with no UI mode
-- active has never been seen in game (API-NOTES 7), and Rebar measured the
-- roleset system inert. So the probe tries it, reads IsRolesetFiltered(),
-- puts the frame back, and records what happened. Building on it waits for
-- that answer.

local ADDON, ns = ...

local Clear = {}
ns.Clear = Clear

-- What is adopted, by registry name. Each resolves at apply time: a frame
-- that does not exist on this client is skipped, not an error.
--
-- Chat is three frames because Blizzard's chat is: the log, the dock that
-- carries the tabs (and fades them itself -- its alpha multiplies under ours),
-- and the button column. All three answer the whisper channel.
Clear.ADOPT = {
    { "Chat",     "ChatFrame1" },
    { "ChatDock", "GeneralDockManager" },
    { "ChatButtons", "ChatFrame1ButtonFrame" },
    { "Minimap",  "MinimapCluster" },
    { "Bags",     "BagsBar" },
    -- R3b ruling: buffs and the cast bar are adopted too -- nothing MyUI draws
    -- replaces them. The cast bar sets its own alpha when a cast starts
    -- (CastingBarMixin:ApplyAlpha), so it shows while casting and rests at 0:
    -- summoned by the cast itself.
    { "Buffs",    "BuffFrame" },
    { "Debuffs",  "DebuffFrame" },
    { "CastBar",  "PlayerCastingBarFrame" },
    -- R3b, second ruling: what the layout could not clear. Bar 1 and the
    -- stance and pet bars have no Edit Mode visibility setting; they are
    -- adopted and, like the other bars, revealed in combat (Reveal's combat
    -- scope). The minimap draws its arrow and blips through its cluster's
    -- alpha, so the map itself is adopted too.
    -- Round 004: MyUI's action bar (Actions.lua) draws bar 1's slots, so
    -- Blizzard's stays adopted at 0 -- shown, keybinds live -- but out of the
    -- registry, where peek or hover would bring it back over MyUI's.
    { "MainBar",    "MainActionBar", yieldsTo = "ActionBar" },
    { "StanceBar",  "StanceBar" },
    { "PetBar",     "PetActionBar" },
    { "MicroMenu",  "MicroMenuContainer" },
    -- The experience / reputation bar (seen in Phase 4 play on a levelling
    -- character).
    { "StatusBars", "StatusTrackingBarManager" },
    -- Phase 4 play (Mykel): the objective tracker and the damage meter.
    -- Alpha on the tracker frame only -- never ObjectiveTrackerManager or
    -- Blizzard's alpha globals, which taint (SPEC 13, ChatQuiet's lesson).
    { "Tracker",    "ObjectiveTrackerFrame" },
    { "DamageMeter", "DamageMeter" },
    { "MinimapMap", "Minimap", hideAtZero = true },
    -- The social button on the chat panel: friends and guild online.
    { "ChatSocial", "QuickJoinToastButton" },
    -- Round 004, SPEC 18: the wings are the Cooldown Manager's own viewers,
    -- placed beside MyUI's bar by the MyUI layout (Clear.PlaceWings) and
    -- revealed with it. Mirroring them is not possible: Cooldown:SetCooldown
    -- is protected on 12.1 (API-NOTES), so MyUI cannot draw a sweep itself.
    { "WingCooldowns", "EssentialCooldownViewer" },
    { "WingUtility",   "UtilityCooldownViewer" },
    { "WingBuffs",     "BuffIconCooldownViewer" },
    -- Party and raid frames: no longer adopted. Round 004 (SPEC 19): MyUI's
    -- own group frames replace them, and Blizzard's are hidden outright
    -- (Clear.HideGroupFrames) -- at alpha 0 they would still catch clicks.
}

Clear.WHISPER_HOLD = 8.0   -- SPEC 11: "holds for 8s"

Clear.adopted = {}          -- name -> { frame, alpha }

local function DB()
    if not ns.db then return {} end
    ns.db.clear = ns.db.clear or {}
    return ns.db.clear
end

--- Is clearing on? On by default: SPEC 11, "MyUI ships a clean screen".
function Clear.Enabled()
    return DB().off ~= true
end

-- ---------------------------------------------------------------------------
-- Adoption
-- ---------------------------------------------------------------------------

function Clear.Adopt()
    local n = 0
    for _, spec in ipairs(Clear.ADOPT) do
        local name, global = spec[1], spec[2]
        local frame = _G[global]
        if frame and not Clear.adopted[name] and not ns.Registry.Get(name)
           and type(frame.SetAlpha) == "function" then
            local alpha = ns.Compat.Get(frame, "GetAlpha")
            Clear.adopted[name] = { frame = frame, alpha = type(alpha) == "number" and alpha or 1,
                                    shown = frame:IsShown() }
            local entry = ns.Registry.Add(name, frame, 0)
            entry.hideAtZero = spec.hideAtZero
            if spec.yieldsTo and ns.Registry.Get(spec.yieldsTo) then
                ns.Registry.Remove(name)
                Clear.Pin(frame)
            end
            n = n + 1
        end
    end
    -- Typing must never happen inside an invisible frame: the edit box leaves
    -- the chat log before the log goes to alpha 0.
    if Clear.adopted.Chat and ns.Chat and ns.Chat.FreeEditBox then
        ns.Chat.FreeEditBox()
    end
    if ns.Reveal.Calm then ns.Reveal.Calm() end
    ns.Reveal.Resolve()
    ns.Reveal.Snap()
    return n
end

--- Hold a frame at alpha 0 against Blizzard's own code setting it back
-- (round 004 play: bar 1 showed through under MyUI's). Alpha is never
-- protected, so this is legal in combat too.
Clear.pinned = {}
local pinning = false
function Clear.Pin(frame)
    if Clear.pinned[frame] == nil then
        hooksecurefunc(frame, "SetAlpha", function(f, a)
            if Clear.pinned[f] and not pinning and a ~= 0 then
                pinning = true
                f:SetAlpha(0)
                pinning = false
            end
        end)
    end
    Clear.pinned[frame] = true
    frame:SetAlpha(0)
end

-- Round 004 play: picking up a spell shows EVERY Blizzard action bar --
-- Edit Mode's Hidden included -- raised to TOOLTIP strata
-- (ActionBarMixin:SetShowGrid), over MyUI's bar, catching the drop at its
-- own misaligned positions. With MyUI's bar built, all of them are held at
-- alpha 0 and their buttons stop taking the mouse. Keybinds still fire them:
-- a binding clicks a button, it does not need the pointer.
Clear.BLIZZARD_BARS = {
    { "MainActionBar",       "ActionButton" },
    { "MultiBarBottomLeft",  "MultiBarBottomLeftButton" },
    { "MultiBarBottomRight", "MultiBarBottomRightButton" },
    { "MultiBarRight",       "MultiBarRightButton" },
    { "MultiBarLeft",        "MultiBarLeftButton" },
    { "MultiBar5",           "MultiBar5Button" },
    { "MultiBar6",           "MultiBar6Button" },
    { "MultiBar7",           "MultiBar7Button" },
}

--- Pin every Blizzard action bar and button at 0, mouse off. Mouse is
-- protected in combat; then only the alpha is pinned and the mouse waits.
function Clear.PinBars()
    local mouse = not InCombatLockdown()
    Clear.barsPinned = true
    -- Round 004 play: "there is no vehicle exit button... I am stuck".
    -- Blizzard's leave-vehicle / leave-taxi button is a child of bar 1
    -- (VehicleLeaveButton.xml, parent="MainActionBar"), so bar 1's alpha
    -- of 0 hid it. It draws at its own alpha, whatever its parent's.
    local leave = _G.MainMenuBarVehicleLeaveButton
    if leave and leave.SetIgnoreParentAlpha then leave:SetIgnoreParentAlpha(true) end
    for _, spec in ipairs(Clear.BLIZZARD_BARS) do
        local bar = _G[spec[1]]
        if bar then
            Clear.Pin(bar)
            -- Round 004 play: bar 1's own frame (561 x 45, bottom centre)
            -- took the mouse, invisibly, over MyUI's clickable SelfStack.
            if mouse and bar.EnableMouse then bar:EnableMouse(false) end
        end
        for i = 1, 12 do
            local b = _G[spec[2] .. i]
            if b then
                Clear.Pin(b)
                if mouse and b.EnableMouse then b:EnableMouse(false) end
            end
        end
    end
    return mouse
end

function Clear.UnpinBars()
    if not Clear.barsPinned or InCombatLockdown() then return false end
    Clear.barsPinned = false
    for _, spec in ipairs(Clear.BLIZZARD_BARS) do
        local bar = _G[spec[1]]
        if bar and Clear.pinned[bar] then
            Clear.pinned[bar] = false
            bar:SetAlpha(Clear.IsAdopted("MainBar") and 0 or 1)
            if bar.EnableMouse then bar:EnableMouse(true) end
        end
        for i = 1, 12 do
            local b = _G[spec[2] .. i]
            if b and Clear.pinned[b] then
                Clear.pinned[b] = false
                b:SetAlpha(1)
                if b.EnableMouse then b:EnableMouse(true) end
            end
        end
    end
    return true
end

function Clear.Release()
    local n = 0
    for _, a in pairs(Clear.adopted) do Clear.pinned[a.frame] = Clear.pinned[a.frame] and false end
    for name, a in pairs(Clear.adopted) do
        ns.Reveal.Release("whisper", name)
        ns.Registry.Remove(name)
        a.frame:SetAlpha(a.alpha or 1)
        if a.shown and not a.frame:IsShown() then a.frame:Show() end
        n = n + 1
    end
    Clear.adopted = {}
    return n
end

function Clear.IsAdopted(name)
    return Clear.adopted[name] ~= nil
end

-- ---------------------------------------------------------------------------
-- Whispers reveal chat, held 8s
-- ---------------------------------------------------------------------------

local whisperToken = 0

function Clear.OnWhisper()
    if not Clear.adopted.Chat then return end
    ns.Reveal.Claim("whisper")
    whisperToken = whisperToken + 1
    local mine = whisperToken
    C_Timer.After(Clear.WHISPER_HOLD, function()
        if whisperToken == mine then ns.Reveal.Release("whisper") end
    end)
end

-- ---------------------------------------------------------------------------
-- The player-frame probe
-- ---------------------------------------------------------------------------
-- Tries SPEC 11's filter on PlayerFrame, reads the result, and puts the frame
-- back exactly (its XML roleset is "unitFrames"). Out of combat only:
-- SetRolesets is a protected function and PlayerFrame a protected frame.

Clear.PROBE_ROLESET = "myuiCleared"
Clear.PLAYER_ROLESET = "unitFrames"   -- PlayerFrame.xml

function Clear.ProbePlayer()
    local frame = _G.PlayerFrame
    local result = { at = date and date("%Y-%m-%d %H:%M:%S") or "?" }
    if not frame or type(frame.SetRolesets) ~= "function" then
        result.error = "no PlayerFrame or no SetRolesets"
    elseif InCombatLockdown() then
        result.error = "in combat -- try again out of combat"
    else
        local active = _G.C_Roleset and _G.C_Roleset.GetActiveBlockedRolesets
        result.blockedBefore = active and table.concat(active() or {}, ",") or "?"
        result.visibleBefore = frame:IsVisible() and true or false
        local ok, err = pcall(frame.SetRolesets, frame, Clear.PROBE_ROLESET)
        result.setOk = ok
        result.setError = (not ok) and tostring(err) or nil
        if ok then
            result.filtered = frame:IsRolesetFiltered() and true or false
            result.visibleDuring = frame:IsVisible() and true or false
        end
        local back = pcall(frame.SetRolesets, frame, Clear.PLAYER_ROLESET)
        result.restored = back
        result.filteredAfter = frame:IsRolesetFiltered() and true or false
        result.visibleAfter = frame:IsVisible() and true or false
    end
    DB().probe = result
    return result
end

-- ---------------------------------------------------------------------------
-- Combat: queue, flush on PLAYER_REGEN_ENABLED (RULES)
-- ---------------------------------------------------------------------------

Clear.queue = {}

function Clear.Defer(key, fn)
    if not InCombatLockdown() then
        fn()
        return true
    end
    Clear.queue[key] = fn
    if Clear.driver then Clear.driver:RegisterEvent("PLAYER_REGEN_ENABLED") end
    return false
end

function Clear.Flush()
    local todo = Clear.queue
    Clear.queue = {}
    for _, fn in pairs(todo) do fn() end
end

-- ---------------------------------------------------------------------------
-- Unit frames: unregister and hide
-- ---------------------------------------------------------------------------

Clear.UNITS = { "PlayerFrame", "TargetFrame", "FocusFrame" }
Clear.hiddenUnits = {}

-- Blizzard's party and raid frames, once MyUI's group frames exist (Group.lua).
Clear.GROUP_FRAMES = { "PartyFrame", "CompactPartyFrame", "CompactRaidFrameContainer",
                       -- Round 004 play: MyUI's pet strip replaces the pet frame.
                       "PetFrame" }

function Clear.HideGroupFrames()
    for _, name in ipairs(Clear.GROUP_FRAMES) do
        local present = false
        for _, u in ipairs(Clear.UNITS) do if u == name then present = true end end
        if not present then Clear.UNITS[#Clear.UNITS + 1] = name end
    end
    if Clear.Enabled and not Clear.Enabled() then return end
    Clear.Defer("units", Clear.HideUnits)
end

function Clear.HideUnits()
    local n = 0
    for _, name in ipairs(Clear.UNITS) do
        local frame = _G[name]
        if frame and not Clear.hiddenUnits[name] then
            frame:UnregisterAllEvents()
            frame:Hide()
            -- Belt and braces: anything that still calls Show() is answered
            -- with a Hide, out of combat now or as soon as combat ends. A
            -- post-hook, so Blizzard's own call runs untouched.
            if not frame.__myuiHooked then
                hooksecurefunc(frame, "Show", function(self)
                    if Clear.hiddenUnits[name] then
                        Clear.Defer("hide:" .. name, function() self:Hide() end)
                    end
                end)
                frame.__myuiHooked = true
            end
            Clear.hiddenUnits[name] = true
            n = n + 1
        end
    end
    return n
end

-- ---------------------------------------------------------------------------
-- The MyUI Edit Mode layout: action bars in combat only
-- ---------------------------------------------------------------------------
-- Through C_EditMode only, never EditModeManagerFrame's methods (that is how
-- Edit Mode gets tainted, and action bars with it). SaveLayouts then
-- SetActiveLayout; the client answers with EDIT_MODE_LAYOUTS_UPDATED, which
-- Blizzard's own handler applies in its own context.

Clear.LAYOUT = "MyUI"

local function DeepCopy(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = DeepCopy(v) end
    return out
end

local function DeepEqual(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then
        if type(a) == "number" then return math.abs(a - b) < 0.01 end
        return a == b
    end
    for k, v in pairs(a) do if not DeepEqual(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
Clear.DeepEqual = DeepEqual

local function Presets()
    local meta = _G.Enum and _G.Enum.EditModePresetLayoutsMeta
    return meta and meta.NumValues or 2
end

--- The active layout's name (presets by their Blizzard name).
function Clear.ActiveLayoutName()
    local info = C_EditMode.GetLayouts()
    local idx, presets = info.activeLayout, Presets()
    if idx <= presets then
        return "preset:" .. idx, idx
    end
    local l = info.layouts[idx - presets]
    return l and l.layoutName, idx
end

-- ---------------------------------------------------------------------------
-- Group frames in combat: by role or by preference
-- ---------------------------------------------------------------------------
-- "auto" (default): a healer's group frames come back in combat; everyone
-- else summons them by hover or peek. "combat" and "hover" pin it.

Clear.GROUP_MODES = { auto = true, combat = true, hover = true }

function Clear.IsHunter()
    if not _G.UnitClass then return false end
    local _, class = _G.UnitClass("player")   -- not "a and f()": that keeps one value
    return class == "HUNTER"
end

function Clear.Role()
    local role = _G.UnitGroupRolesAssigned and _G.UnitGroupRolesAssigned("player")
    if (role == nil or role == "NONE") and _G.GetSpecialization and _G.GetSpecializationRole then
        local spec = _G.GetSpecialization()
        role = spec and _G.GetSpecializationRole(spec) or role
    end
    return role or "NONE"
end

function Clear.GroupMode()
    local m = DB().group
    -- Round 004 play (Mykel): group frames in every fight, not only a
    -- healer's. "auto" stays available.
    return Clear.GROUP_MODES[m] and m or "combat"
end

function Clear.GroupInCombat()
    local m = Clear.GroupMode()
    if m == "combat" then return true end
    if m == "hover" then return false end
    return Clear.Role() == "HEALER"
end

function Clear.SetGroupMode(m)
    if not Clear.GROUP_MODES[m] then return nil end
    DB().group = m
    return m
end

--- Hide every action bar that has a visibility setting, and
-- stop bars drawing their empty slots (Phase 4 play: a grid of empty boxes
-- came up with the bars in combat). The Cooldown Manager's viewers go
-- in-combat only too: cooldown information belongs to the fight, and the
-- rhythm line that replaces them is v2. Returns how many settings changed.
function Clear.BarsInCombat(layout)
    local E = _G.Enum
    local bar, cdm = E.EditModeActionBarSetting, E.EditModeCooldownViewerSetting
    local n = 0
    for _, sys in ipairs(layout.systems or {}) do
        if sys.system == E.EditModeSystem.ActionBar then
            for _, st in ipairs(sys.settings or {}) do
                if st.setting == bar.VisibleSetting then
                    -- Phase 4 play (Mykel): hidden always. The Cooldown
                    -- Manager carries cooldowns in combat; keybinds work.
                    st.value = E.ActionBarVisibleSetting.Hidden
                    n = n + 1
                elseif bar.AlwaysShowButtons and st.setting == bar.AlwaysShowButtons then
                    st.value = 0
                    n = n + 1
                end
            end
        elseif cdm and E.EditModeSystem.CooldownViewer and sys.system == E.EditModeSystem.CooldownViewer then
            for _, st in ipairs(sys.settings or {}) do
                if st.setting == cdm.VisibleSetting then
                    -- Round 004: the wings are always "shown" to Blizzard;
                    -- adopted at alpha 0, they come back with the bar (combat,
                    -- a target, arranging) -- the reveal engine decides. The
                    -- buff bars are not a wing and stay in-combat only.
                    local idx = E.EditModeCooldownViewerSystemIndices
                    local wing = not idx or sys.systemIndex ~= idx.BuffBar
                    st.value = wing and E.CooldownViewerVisibleSetting.Always
                               or E.CooldownViewerVisibleSetting.InCombat
                    n = n + 1
                end
            end
        end
    end
    return n
end

-- SPEC 18: where each Cooldown Manager viewer goes, beside MyUI's bar.
-- `side` -1 is the left wing, 1 the right; `row` 0 is bar 1's row, 1 the
-- row above. Icon sizes are Edit Mode's slider steps ((percent - 50) / 10):
-- essential 50 px at 90% ~ bar 1's 44; utility 30 px at 100%; buffs 40 at 80%.
Clear.WINGS = {
    -- Round 004 play: at bar-1 size and 12 away they read as more bar. Bigger
    -- (SPEC's button grammar: cooldown > bar 1 > a page) and further off.
    Essential = { side = -1, row = 0, size = 6, limit = 8, base = 50 },   -- major cooldowns, 55 px
    -- Above the major cooldowns, not above bar 1's row: they are taller than
    -- the bar, and at bar height the two overlapped (round 004 play).
    Utility   = { side = -1, row = 1, size = 5, limit = 8, base = 30, over = "Essential" },
    -- Round 004 play (Mykel): the chosen buffs go on the left too (where
    -- exactly is undecided) -- above the utility row for now.
    BuffIcon  = { side = -1, row = 2, size = 3, limit = 8, base = 40, over = "Utility" },
}

-- SPEC 18, right wing, bar 1's row: debuffs on you. Blizzard's own debuff
-- frame (adopted as "Debuffs"), which already edges each debuff by dispel
-- type (ShowDispelType) and draws whatever arrives secret itself -- so probe
-- P1 does not gate it. One row, growing away from the bar. Round 004 play:
-- 150% drew ~59 units, bigger than bar 1; 110% is ~43, bar-1 size.
Clear.AURA_WINGS = {
    DebuffFrame = { side = 1, row = 0, size = 6, limit = 8 },
}

--- A viewer's icon height in UI units: its template's size times the Edit
-- Mode step's percentage. Blizzard's own units, not SPEC's (no U()).
function Clear.WingIconHeight(key)
    local w = Clear.WINGS[key]
    return w.base * (50 + 10 * w.size) / 100
end
-- The gap between the bar and each wing, and between icons, come from the
-- layout profile (Layout.lua: wingGap, iconPadding).

-- Round 004 play: the stance (forms) and pet bars were adopted and never came
-- back. First they sat on the row above bar 1; then (Mykel) "stances belong
-- below the CDs": under each wing, outer edge aligned with the bar's, at
-- their own 30 px -- stance under the cooldowns, pet under the debuffs.
Clear.OVER_BAR = {
    StanceBar    = { side = -1 },
    PetActionBar = { side =  1 },
}
Clear.UNDER_WING_HEIGHT = 30

-- Blizzard's zone / extra ability button has an ornate frame (Mykel: "I
-- really dislike that giant zone button"): the frame art is hidden. A scale
-- of 0.7 was tried and did not take in game (Edit Mode keeps the system's
-- scale); without its frame the button already reads as bar-1 size, which
-- Mykel liked -- so no scale.

local function SetSetting(sys, setting, value)
    for _, st in ipairs(sys.settings) do
        if st.setting == setting then st.value = value; return end
    end
    sys.settings[#sys.settings + 1] = { setting = setting, value = value }
end

--- Place the wings in the layout: each viewer anchored to UIParent's bottom
-- centre at the bar's edge, growing away from it, so its first icon sits
-- next to the bar. Returns how many viewers were placed.
--- Where each placed element goes, in UIParent units from its bottom centre:
-- point, x, y. One source for the Edit Mode layout (PlaceWings) and the
-- layout preview (Layout.Preview), so they cannot disagree.
function Clear.Anchor(key)
    local half, bottom, row, rowGap, barX = ns.Actions.Extent()
    local gap = ns.Scale.U(ns.Layout.Value("wingGap"))
    local w = Clear.WINGS[key]
    if w then
        -- A row stacked over another sits on top of it, whatever its height.
        local y
        if w.over then
            local _, _, under = Clear.Anchor(w.over)
            y = under + Clear.WingIconHeight(w.over) + rowGap
        else
            y = bottom + w.row * (row + rowGap)
        end
        return w.side < 0 and "BOTTOMRIGHT" or "BOTTOMLEFT", barX + w.side * (half + gap), y
    end
    local o = Clear.OVER_BAR[key]
    if o then
        return o.side < 0 and "BOTTOMRIGHT" or "BOTTOMLEFT", barX + o.side * (half + gap),
               bottom - rowGap - Clear.UNDER_WING_HEIGHT
    end
    if key == "Debuffs" then
        -- Past the zone button while it is up, otherwise in its place.
        local g = Clear.ZoneShown() and (ns.Layout.Value("debuffGap") or ns.Layout.Value("wingGap"))
                  or ns.Layout.Value("wingGap")
        return "BOTTOMLEFT", barX + half + ns.Scale.U(g), bottom
    end
    if key == "BuffBars" then
        -- Over the chosen buffs' row, whatever its height; the profile's y
        -- is an extra lift.
        local point, rel, x, lift = ns.Layout.Pos(key)
        local _, _, under = Clear.Anchor("BuffIcon")
        return point, ns.Scale.U(x), under + Clear.WingIconHeight("BuffIcon") + rowGap + ns.Scale.U(lift or 0), rel
    end
    local point, rel, x, y = ns.Layout.Pos(key)
    return point, ns.Scale.U(x), ns.Scale.U(y), rel
end

--- Is Blizzard's zone / extra ability button up right now?
function Clear.ZoneShown()
    local c = _G.ExtraAbilityContainer
    return c ~= nil and c:IsShown() == true
end

-- The debuffs are anchored in the Edit Mode layout to this MyUI frame rather
-- than to UIParent, so MyUI can slide them (Mykel: into the zone button's
-- place when it is not up) without touching Blizzard's frame. Created when
-- this file loads: Edit Mode applies the saved layout (EDIT_MODE_LAYOUTS_
-- UPDATED) before PLAYER_LOGIN, and an anchor made at login was not there
-- yet ("Couldn't find region named 'MyUIDebuffAnchor'", round 004 play).
function Clear.DebuffAnchor()
    if not Clear.debuffAnchor then
        Clear.debuffAnchor = CreateFrame("Frame", "MyUIDebuffAnchor", UIParent)
        Clear.debuffAnchor:SetSize(1, 1)
        -- Somewhere sane until login places it (Clear.OnLogin).
        Clear.debuffAnchor:SetPoint("BOTTOMLEFT", UIParent, "BOTTOM", 240, 80)
    end
    return Clear.debuffAnchor
end

Clear.DebuffAnchor()

function Clear.PlaceDebuffAnchor()
    Clear.DebuffAnchor()
    local point, x, y = Clear.Anchor("Debuffs")
    Clear.debuffAnchor:ClearAllPoints()
    Clear.debuffAnchor:SetPoint(point, UIParent, "BOTTOM", x, y)
end

function Clear.HookZone()
    local c = _G.ExtraAbilityContainer
    if not c or Clear.zoneHooked then return end
    c:HookScript("OnShow", Clear.PlaceDebuffAnchor)
    c:HookScript("OnHide", Clear.PlaceDebuffAnchor)
    Clear.zoneHooked = true
end

function Clear.PlaceWings(layout)
    local E = _G.Enum
    local A = ns.Actions
    local idx, cdm = E.EditModeCooldownViewerSystemIndices, E.EditModeCooldownViewerSetting
    if not (A and A.Extent and idx and cdm and E.EditModeSystem.CooldownViewer) then return 0 end
    local pad = ns.Layout.Value("iconPadding")
    local n = 0
    local bars = E.EditModeActionBarSystemIndices
    local function At(sys, key, relativeTo)
        local point, x, y, rel = Clear.Anchor(key)
        sys.isInDefaultPosition = false
        sys.anchorInfo = { point = point, relativeTo = relativeTo or "UIParent",
                           relativePoint = rel or "BOTTOM", offsetX = x, offsetY = y }
        n = n + 1
    end
    for _, sys in ipairs(layout.systems or {}) do
        if bars and sys.system == E.EditModeSystem.ActionBar then
            for key in pairs(Clear.OVER_BAR) do
                if bars[key] == sys.systemIndex then At(sys, key) end
            end
        elseif E.EditModeSystem.ExtraAbilities and sys.system == E.EditModeSystem.ExtraAbilities then
            -- Blizzard's zone / extra ability button (round 004 play: it sat
            -- mid-screen over the character). Placed by the profile.
            At(sys, "ZoneAbility")
        elseif E.EditModeSystem.AuraFrame and sys.system == E.EditModeSystem.AuraFrame then
            local aidx, aset = E.EditModeAuraFrameSystemIndices, E.EditModeAuraFrameSetting
            for key, w in pairs(Clear.AURA_WINGS) do
                if aidx and aset and aidx[key] == sys.systemIndex then
                    sys.isInDefaultPosition = false
                    -- Anchored to MyUI's debuff anchor, which slides.
                    sys.anchorInfo = { point = "BOTTOMLEFT", relativeTo = "MyUIDebuffAnchor",
                                       relativePoint = "BOTTOMLEFT", offsetX = 0, offsetY = 0 }
                    n = n + 1
                    sys.settings = sys.settings or {}
                    SetSetting(sys, aset.Orientation, E.AuraFrameOrientation.Horizontal)
                    SetSetting(sys, aset.IconDirection, E.AuraFrameIconDirection.Right)
                    SetSetting(sys, aset.IconWrap, E.AuraFrameIconWrap.Up)
                    SetSetting(sys, aset.IconLimitDebuffFrame, w.limit)
                    SetSetting(sys, aset.IconSize, w.size)
                    if aset.ShowDispelType then SetSetting(sys, aset.ShowDispelType, 1) end
                    if aset.IconPadding then SetSetting(sys, aset.IconPadding, pad) end
                end
            end
        elseif sys.system == E.EditModeSystem.CooldownViewer and idx.BuffBar == sys.systemIndex then
            -- The tracked buff bars: not a wing, placed by the profile. A
            -- vertical viewer grows up only with direction Right
            -- (CooldownViewer.lua: layoutFramesGoingUp) -- round 004 play:
            -- they grew down over the other trackers.
            At(sys, "BuffBars")
            sys.settings = sys.settings or {}
            SetSetting(sys, cdm.Orientation, E.CooldownViewerOrientation.Vertical)
            SetSetting(sys, cdm.IconDirection, E.CooldownViewerIconDirection.Right)
        elseif sys.system == E.EditModeSystem.CooldownViewer then
            for key, w in pairs(Clear.WINGS) do
                if idx[key] == sys.systemIndex then
                    At(sys, key)
                    sys.settings = sys.settings or {}
                    SetSetting(sys, cdm.Orientation, E.CooldownViewerOrientation.Horizontal)
                    SetSetting(sys, cdm.IconDirection,
                               w.side < 0 and E.CooldownViewerIconDirection.Left or E.CooldownViewerIconDirection.Right)
                    SetSetting(sys, cdm.IconSize, w.size)
                    SetSetting(sys, cdm.IconLimit, w.limit)
                    -- Round 004 play: "at the least the icons should have
                    -- some margin between them".
                    SetSetting(sys, cdm.IconPadding, pad)
                end
            end
        end
    end
    Clear.PlaceDebuffAnchor()
    Clear.HookZone()
    return n
end

--- Drop the frame art from Blizzard's zone / extra ability button.
-- Out of combat (the container holds secure buttons). Undone by restore.
function Clear.StyleExtra(on)
    if InCombatLockdown() then return false end
    local art = {
        _G.ZoneAbilityFrame and _G.ZoneAbilityFrame.Style,
        _G.ExtraActionButton1 and _G.ExtraActionButton1.style,
    }
    for _, t in pairs(art) do
        if t and t.SetAlpha then t:SetAlpha(on == false and 1 or 0) end
    end
    return true
end

function Clear.ApplyLayout()
    if not _G.C_EditMode or not _G.C_EditMode.GetLayouts then return nil, "no C_EditMode" end
    local E = _G.Enum
    local info = C_EditMode.GetLayouts()
    local presets = Presets()
    local current, activeIdx = Clear.ActiveLayoutName()
    if current ~= Clear.LAYOUT then
        DB().prevLayout = current
    end

    -- Find or make the layout.
    local mine
    for i, l in ipairs(info.layouts) do
        if l.layoutName == Clear.LAYOUT then mine = i end
    end
    if not mine then
        local source
        if activeIdx > presets then
            source = info.layouts[activeIdx - presets]
        elseif _G.EditModePresetLayoutManager then
            -- Reading a copy of Blizzard's preset table; nothing is written back.
            local copies = _G.EditModePresetLayoutManager:GetCopyOfPresetLayouts()
            source = copies and copies[activeIdx]
        end
        if not source then return nil, "could not read the active layout" end
        local accounts = 0
        for _, l in ipairs(info.layouts) do
            if l.layoutType == E.EditModeLayoutType.Account then accounts = accounts + 1 end
        end
        if accounts >= 5 then return nil, "five account layouts already -- delete one in Edit Mode" end
        local new = DeepCopy(source)
        new.layoutName = Clear.LAYOUT
        new.layoutType = E.EditModeLayoutType.Account
        -- Account layouts sort before character ones.
        mine = accounts + 1
        table.insert(info.layouts, mine, new)
        if info.activeLayout > presets + accounts then
            info.activeLayout = info.activeLayout + 1
        end
    end

    local before = DeepCopy(info.layouts[mine])
    local changed = Clear.BarsInCombat(info.layouts[mine])
    changed = changed + Clear.PlaceWings(info.layouts[mine])
    -- Round 004 play: Blizzard's aura code hit secret values from a tainted
    -- call ("attempted to index a table that cannot be indexed with secret
    -- keys", AuraUtil.lua). C_EditMode called from addon code fires Edit
    -- Mode's update inside MyUI's call, so whatever it sets is tainted.
    -- When the MyUI layout is already active and already right, touch
    -- nothing: then a normal login never calls C_EditMode at all.
    local isActive = info.activeLayout == presets + mine
    if isActive and DeepEqual(before, info.layouts[mine]) then
        Clear.layoutUntouched = true
        return 0
    end
    Clear.layoutUntouched = false
    info.activeLayout = presets + mine
    C_EditMode.SaveLayouts(info)
    C_EditMode.SetActiveLayout(presets + mine)
    return changed
end

function Clear.RestoreLayout()
    if not _G.C_EditMode or not _G.C_EditMode.GetLayouts then return nil, "no C_EditMode" end
    local prev = DB().prevLayout
    if not prev then return nil, "no previous layout recorded" end
    local presets = Presets()
    local preset = prev:match("^preset:(%d+)$")
    if preset then
        C_EditMode.SetActiveLayout(tonumber(preset))
        return true
    end
    local info = C_EditMode.GetLayouts()
    for i, l in ipairs(info.layouts) do
        if l.layoutName == prev then
            C_EditMode.SetActiveLayout(presets + i)
            return true
        end
    end
    return nil, ("layout %q no longer exists"):format(prev)
end

-- ---------------------------------------------------------------------------
-- On and off
-- ---------------------------------------------------------------------------

--- Everything R3b clears. Adoption is alpha and happens now; the unit frames
-- and the layout wait for combat to end.
function Clear.Apply()
    DB().off = nil
    local adopted = Clear.Adopt()
    Clear.Defer("units", Clear.HideUnits)
    Clear.Defer("layout", function()
        local ok, err = Clear.ApplyLayout()
        DB().layoutResult = ok and ("bars changed: " .. tostring(ok)) or tostring(err)
        Clear.StyleExtra(true)
        -- Applying a layout sets each viewer's Edit Mode opacity (SetAlpha);
        -- put the adopted ones back where the reveal engine has them.
        ns.Reveal.Snap()
        C_Timer.After(1, function() ns.Reveal.Snap() end)
    end)
    return adopted
end

--- /myui restore: put back everything R3b took. The layout switches back
-- and adoption releases now (or when combat ends); the unit frames need a
-- /reload, because their event registrations are Blizzard's to make.
function Clear.Restore()
    DB().off = true
    Clear.UnpinBars()
    local n = Clear.Release()
    local needsReload = next(Clear.hiddenUnits) ~= nil
    Clear.Defer("layout", function() Clear.RestoreLayout(); Clear.StyleExtra(false) end)
    return n, needsReload
end

function Clear.OnLogin()
    Clear.PlaceDebuffAnchor()
    local driver = CreateFrame("Frame", "MyUIClearDriver", UIParent)
    Clear.driver = driver
    driver:RegisterEvent("PLAYER_ENTERING_WORLD")
    driver:RegisterEvent("CHAT_MSG_WHISPER")
    driver:RegisterEvent("CHAT_MSG_BN_WHISPER")
    driver:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_ENTERING_WORLD" then
            if Clear.Enabled() then Clear.Apply() end
        elseif event == "PLAYER_REGEN_ENABLED" then
            self:UnregisterEvent("PLAYER_REGEN_ENABLED")
            Clear.Flush()
        else
            Clear.OnWhisper()
        end
    end)
end
