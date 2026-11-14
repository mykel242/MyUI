-- MyUI :: Stow.lua
-- Taking Blizzard's furniture off the screen, by group.
--
-- Reparented into a hidden frame rather than hidden, and the difference is the
-- whole design. Blizzard's code keeps calling Show and SetShown on these
-- frames -- CompactRaidFrameManager_UpdateShown does it every time your group
-- changes, and ChooseBoxForSend branches on ChatFrame1:IsShown() -- so a frame
-- we HIDE is a frame we have to keep re-hiding, and a frame whose IsShown()
-- answer we have changed underneath logic that reads it.
--
-- Stowed under a hidden parent, every one of those calls still succeeds and
-- still reports the truth. We are not fighting anything; the frame simply has
-- nowhere to draw. Nothing here polls, hooks, or re-hides on a timer.

local ADDON, ns = ...

local Stow = {}
ns.Stow = Stow

-- Groups rather than one list, because these are different systems with
-- different reasons to come back. Chat is furniture around something we
-- replaced; the raid manager is a feature we have not replaced at all.
Stow.GROUPS = {
    chat = {
        label = "Blizzard's chat log and its furniture",
        frames = {
            "GeneralDockManager", "ChatFrameMenuButton", "QuickJoinToastButton",
            "ChatFrameChannelButton", "ChatFrameToggleVoiceDeafenButton",
            "ChatFrameToggleVoiceMuteButton",
        },
        -- Chat frames are numbered, so the list is built at stow time.
        numbered = { "ChatFrame%d", "ChatFrame%dTab", "ChatFrame%dButtonFrame" },
        count = function() return tonumber(_G.NUM_CHAT_WINDOWS) or 10 end,
    },
    raid = {
        label = "the raid frame manager tab",
        -- FOUND IN GAME: a 221x361 frame at the left edge, exactly where the
        -- rail lives. It appears whenever you are in a group, or whenever Edit
        -- Mode is force-showing party or raid frames
        -- (Blizzard_CompactRaidFrameManager.lua:294), which is easy to leave
        -- switched on by accident.
        frames = { "CompactRaidFrameManager" },
        -- Unit frames are protected. The MANAGER is a plain frame with no
        -- protected attribute, but it is the visible edge of a protected
        -- system, so this group never moves during combat.
        combatUnsafe = true,
    },
}

Stow.stash = {}

function Stow.Attic()
    if not Stow.attic then
        local attic = CreateFrame("Frame", "MyUIAttic", UIParent)
        attic:Hide()
        Stow.attic = attic
    end
    return Stow.attic
end

local function InCombat()
    local fn = _G.InCombatLockdown
    if type(fn) ~= "function" then
        return false
    end
    local ok, locked = pcall(fn)
    return ok and locked == true
end

--- Put one frame in the attic. Returns true if it moved.
function Stow.Add(frame, group)
    if type(frame) ~= "table" or Stow.stash[frame] then
        return false
    end
    if type(frame.SetParent) ~= "function" or type(frame.GetParent) ~= "function" then
        return false
    end
    Stow.stash[frame] = { parent = frame:GetParent() or _G.UIParent, group = group }
    pcall(frame.SetParent, frame, Stow.Attic())
    return true
end

local function Resolve(name)
    local spec = Stow.GROUPS[name]
    if not spec then
        return nil
    end
    local out = {}
    for _, frameName in ipairs(spec.frames or {}) do
        out[#out + 1] = _G[frameName]
    end
    if spec.numbered then
        local n = spec.count and spec.count() or 0
        for i = 1, n do
            for _, pattern in ipairs(spec.numbered) do
                out[#out + 1] = _G[pattern:format(i)]
            end
        end
    end
    return out
end
Stow.Resolve = Resolve

--- Stow a whole group. Returns how many moved, or nil plus a reason.
function Stow.Group(name)
    local spec = Stow.GROUPS[name]
    if not spec then
        return nil, ("no such group %q"):format(tostring(name))
    end
    if spec.combatUnsafe and InCombat() then
        return nil, "not during combat -- " .. spec.label
                 .. " belongs to a protected system"
    end
    local moved = 0
    for _, frame in ipairs(Resolve(name)) do
        if Stow.Add(frame, name) then
            moved = moved + 1
        end
    end
    return moved
end

--- Put a group back where it came from.
function Stow.Restore(name)
    local spec = name and Stow.GROUPS[name]
    if name and not spec then
        return nil, ("no such group %q"):format(tostring(name))
    end
    if spec and spec.combatUnsafe and InCombat() then
        return nil, "not during combat"
    end
    local back = 0
    for frame, entry in pairs(Stow.stash) do
        if name == nil or entry.group == name then
            pcall(frame.SetParent, frame, entry.parent)
            Stow.stash[frame] = nil
            back = back + 1
        end
    end
    return back
end

--- How many frames are stowed, optionally for one group.
function Stow.Count(name)
    local n = 0
    for _, entry in pairs(Stow.stash) do
        if name == nil or entry.group == name then
            n = n + 1
        end
    end
    return n
end

function Stow.IsStowed(name)
    return Stow.Count(name) > 0
end

ns.Stow = Stow
