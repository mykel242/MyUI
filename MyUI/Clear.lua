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
    -- Party and raid frames: adopted, revealed in combat.
    { "Party",      "PartyFrame" },
    { "CompactParty", "CompactPartyFrame" },
    { "Raid",       "CompactRaidFrameContainer" },
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
                frame:SetAlpha(0)
            end
            n = n + 1
        end
    end
    -- Typing must never happen inside an invisible frame: the edit box leaves
    -- the chat log before the log goes to alpha 0.
    if Clear.adopted.Chat and ns.Chat and ns.Chat.FreeEditBox then
        ns.Chat.FreeEditBox()
    end
    ns.Reveal.Resolve()
    ns.Reveal.Snap()
    return n
end

function Clear.Release()
    local n = 0
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
    return Clear.GROUP_MODES[m] and m or "auto"
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
                    st.value = E.CooldownViewerVisibleSetting.InCombat
                    n = n + 1
                end
            end
        end
    end
    return n
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

    local changed = Clear.BarsInCombat(info.layouts[mine])
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
    end)
    return adopted
end

--- /myui restore: put back everything R3b took. The layout switches back
-- and adoption releases now (or when combat ends); the unit frames need a
-- /reload, because their event registrations are Blizzard's to make.
function Clear.Restore()
    DB().off = true
    local n = Clear.Release()
    local needsReload = next(Clear.hiddenUnits) ~= nil
    Clear.Defer("layout", function() Clear.RestoreLayout() end)
    return n, needsReload
end

function Clear.OnLogin()
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
