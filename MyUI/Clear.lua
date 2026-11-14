-- MyUI :: Clear.lua
-- SPEC.md 11: clearing the screen is MyUI's job. R3b brings it forward from
-- Phase 6b, minus the replacements (PLAN R3b).
--
-- This file does the part that is certain: ADOPTION. Chat, minimap and bags
-- are registered at resting alpha 0 and revealed by the ordinary engine --
-- hidden never means lost, because proximity and peek summon them. Alpha only,
-- so nothing here is protected and nothing here waits for combat to end.
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
            Clear.adopted[name] = { frame = frame, alpha = type(alpha) == "number" and alpha or 1 }
            ns.Registry.Add(name, frame, 0)
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
-- On and off
-- ---------------------------------------------------------------------------

function Clear.Apply()
    DB().off = nil
    return Clear.Adopt()
end

--- /myui restore: put back everything R3b took. Alpha only so far, so no
-- combat queue is needed; the filter and the layout will need one.
function Clear.Restore()
    DB().off = true
    return Clear.Release()
end

function Clear.OnLogin()
    local driver = CreateFrame("Frame", "MyUIClearDriver", UIParent)
    Clear.driver = driver
    driver:RegisterEvent("PLAYER_ENTERING_WORLD")
    driver:RegisterEvent("CHAT_MSG_WHISPER")
    driver:RegisterEvent("CHAT_MSG_BN_WHISPER")
    driver:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_ENTERING_WORLD" then
            if Clear.Enabled() then Clear.Adopt() end
        else
            Clear.OnWhisper()
        end
    end)
end
