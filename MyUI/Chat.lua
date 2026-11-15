-- MyUI :: Chat.lua
-- Step one of replacing the chat log: our own edit box, focused through
-- Blizzard's own supported override. Nothing is hidden yet and nothing is
-- intercepted -- this is purely additive, and clearing the override puts the
-- game back exactly as it was.
--
-- Why this is not what chat addons do. They replace the message pipeline:
-- hook ChatFrame_MessageEventHandler, re-implement filtering and routing, and
-- inherit every patch-day break. We do neither half. Reading is our own frames
-- fed by CHAT_MSG_ events like any addon, and SENDING is handed straight back
-- to Blizzard's edit box -- ChatFrameEditBoxBaseMixin:SendText does the
-- parsing, the chat type, the whisper target and the history. We own the
-- presentation and none of the routing.
--
-- Verified in Blizzard_ChatFrameBase at 12.1.0.69497:
--
--   ChatFrameUtil.SetChatFocusOverride(editBox)   ChatFrameUtil.lua:104
--   OpenChat consults CHAT_FOCUS_OVERRIDE FIRST   ChatFrameUtil.lua:367
--   ChooseBoxForSend never returns the override   ChatFrameUtil.lua:490
--
-- Blizzard_Communities already uses this mechanism for its own chat, which is
-- what makes it an extension point rather than a trick.

local ADDON, ns = ...

local Scale, Palette = ns.Scale, ns.Palette
local U = function(v) return Scale.U(v) end

local Chat = {}
ns.Chat = Chat

-- Aligned with the rail at x = 20, because it is the same left edge and
-- position is the one thing SPEC 1 says never moves.
Chat.X       = 20
Chat.Y       = 140
Chat.WIDTH   = 420
Chat.HEIGHT  = 22

-- The override carries this flag, and Blizzard reads it in OpenChat: when it
-- is false, anything beginning with "/" falls through to the real chat box
-- instead of coming to us.
--
-- False on purpose, and it is the reason the chat frame gets HIDDEN and never
-- removed. Setting it true would mean owning slash-command routing -- parsing
-- every /command in the game -- which is exactly the pipeline replacement that
-- makes other chat addons fragile. Blizzard_Communities makes the same call.
Chat.SUPPORTS_SLASH = false

local function API(path, ...)
    local fn = _G
    for part in tostring(path):gmatch("[^%.]+") do
        if type(fn) ~= "table" then return nil end
        fn = fn[part]
    end
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if not ok then return nil end
    return a, b
end
Chat.API = API

--- Blizzard's real edit box -- the one that knows how to send.
function Chat.SendBox()
    local box = API("ChatFrameUtil.ChooseBoxForSend")
    if type(box) == "table" then
        return box
    end
    -- ChooseBoxForSend reads CVars and the dock, either of which can be
    -- unavailable this early. The default frame's box is the same object in
    -- every case the chooser has to pick between.
    local default = _G.DEFAULT_CHAT_FRAME
    return type(default) == "table" and default.editBox or nil
end

--- Hand the text to Blizzard and let it do the routing.
function Chat.Send(text)
    if type(text) ~= "string" or text:match("^%s*$") then
        return false, "empty"
    end
    local box = Chat.SendBox()
    if not box or type(box.SendText) ~= "function" then
        return false, "no send box"
    end
    box:SetText(text)
    local ok, err = pcall(box.SendText, box, 1)
    box:SetText("")
    if not ok then
        return false, tostring(err)
    end
    return true
end

--- What we are about to talk into, for the label.
function Chat.Label()
    local box = Chat.SendBox()
    local kind = box and type(box.GetChatType) == "function" and box:GetChatType()
    if kind == "WHISPER" or kind == "BN_WHISPER" then
        local target = type(box.GetTellTarget) == "function" and box:GetTellTarget()
        if target and target ~= "" then
            return ("whisper %s"):format(tostring(target))
        end
        return "whisper"
    end
    return type(kind) == "string" and kind:lower() or "say"
end

-- ---------------------------------------------------------------------------
-- The box
-- ---------------------------------------------------------------------------

function Chat.Build()
    if Chat.box then
        return Chat.box
    end

    local box = CreateFrame("EditBox", "MyUIChatBox", UIParent)
    box:SetFrameStrata("DIALOG")
    box:SetSize(U(Chat.WIDTH), U(Chat.HEIGHT))
    box:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", U(Chat.X), U(Chat.Y))

    -- SPEC 1: flat, no radius, no gradient, no fill above 14%. `trough` is
    -- exactly 14%, and the hairline underneath is what says "type here".
    local bg = box:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(Palette.Get("trough"))
    box.bg = bg

    local rule = box:CreateTexture(nil, "ARTWORK")
    rule:SetHeight(Scale.Hairline())
    rule:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 0, 0)
    rule:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 0, 0)
    rule:SetColorTexture(Palette.Get("fillDim"))
    box.rule = rule

    box.label = ns.Frames.Text(box, 10, "textDim", "LEFT")
    box.label:SetPoint("BOTTOMLEFT", box, "TOPLEFT", 0, U(4))

    box:SetFont(ns.Frames.FONT, U(12), "")
    box:SetTextColor(ns.Frames.TextColor("textPrimary"))
    box:SetTextInsets(U(8), U(8), 0, 0)
    box:SetAutoFocus(false)
    box:SetMaxLetters(255)

    -- No mouse. The rail gave its click surface up and this does too: the box
    -- arrives focused, so there is nothing to click on, and the bottom-left of
    -- the screen keeps passing clicks to the world.
    box:EnableMouse(false)

    -- Shown but transparent rather than hidden, because Blizzard's OpenChat
    -- calls SetFocus on us directly and a hidden EditBox cannot take focus.
    -- Alpha does the hiding; focus does the showing.
    box:SetAlpha(0)

    box:SetScript("OnEditFocusGained", function(self)
        self.label:SetText(Chat.Label())
        self:SetAlpha(1)
    end)
    box:SetScript("OnEditFocusLost", function(self)
        self:SetText("")
        self:SetAlpha(0)
    end)
    box:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    box:SetScript("OnEnterPressed", function(self)
        local text = self:GetText()
        self:ClearFocus()
        if text and not text:match("^%s*$") then
            local ok, err = Chat.Send(text)
            if not ok and err ~= "empty" then
                ns.Print("could not send: " .. tostring(err))
            end
        end
    end)

    Chat.box = box
    return box
end

-- ---------------------------------------------------------------------------
-- The override
-- ---------------------------------------------------------------------------

--- What this client actually offers. FOUND IN GAME: the override did not
-- install and the status could only say "not installed", which is a symptom
-- rather than a cause. The reference dump is 12.1.0.69497 and the live build
-- can differ, so this reports what is really there instead of assuming.
function Chat.Probe()
    local util = _G.ChatFrameUtil
    return {
        util        = type(util) == "table",
        set         = type(util) == "table" and type(util.SetChatFocusOverride) == "function",
        get         = type(util) == "table" and type(util.GetChatFocusOverride) == "function",
        clear       = type(util) == "table" and type(util.ClearChatFocusOverride) == "function",
        open        = type(util) == "table" and type(util.OpenChat) == "function",
        -- Blizzard_DeprecatedChatInfo aliases the same functions under the old
        -- names, and that addon may not be loaded.
        legacySet   = type(_G.ChatFrame_SetChatFocusOverride) == "function",
        -- OpenChat reads this global directly, so it is the floor: if the
        -- setter is missing, writing the global does the same job.
        globalHeld  = _G.CHAT_FOCUS_OVERRIDE,
    }
end

function Chat.Enable()
    local box = Chat.Build()
    box.supportsSlashCommands = Chat.SUPPORTS_SLASH

    local p = Chat.Probe()
    local route

    if p.set then
        local ok, err = pcall(_G.ChatFrameUtil.SetChatFocusOverride, box)
        if not ok then
            Chat.lastError = tostring(err)
            return false, Chat.lastError
        end
        route = "ChatFrameUtil.SetChatFocusOverride"
    elseif p.legacySet then
        local ok, err = pcall(_G.ChatFrame_SetChatFocusOverride, box)
        if not ok then
            Chat.lastError = tostring(err)
            return false, Chat.lastError
        end
        route = "ChatFrame_SetChatFocusOverride"
    else
        -- The setter is a one-line assignment to a global that OpenChat reads
        -- on every press of Enter. If the wrapper is not exported on this
        -- build, the global still is, and it is not protected.
        _G.CHAT_FOCUS_OVERRIDE = box
        route = "CHAT_FOCUS_OVERRIDE directly"
    end

    Chat.route = route
    Chat.enabled = true
    Chat.lastError = nil

    -- Assert rather than assume. Setting it and finding it did not take is the
    -- exact failure this had in game, and it said nothing about it.
    if not Chat.IsOverriding() then
        Chat.lastError = "set via " .. route .. " but it did not hold"
        return false, Chat.lastError
    end
    return true, route
end

function Chat.Disable()
    local clear = _G.ChatFrameUtil and _G.ChatFrameUtil.ClearChatFocusOverride
    if type(clear) == "function" then
        pcall(clear)
    else
        _G.CHAT_FOCUS_OVERRIDE = nil
    end
    if Chat.box then
        Chat.box:ClearFocus()
        Chat.box:SetAlpha(0)
    end
    Chat.enabled = false
    return true
end

--- Is our box the one Blizzard will focus?
--- Is our box the one Blizzard will focus? Read through the API when it is
-- there and off the global when it is not, because the global is what OpenChat
-- actually consults.
function Chat.IsOverriding()
    local get = _G.ChatFrameUtil and _G.ChatFrameUtil.GetChatFocusOverride
    if type(get) == "function" then
        local ok, current = pcall(get)
        if ok then
            return current == Chat.box
        end
    end
    return _G.CHAT_FOCUS_OVERRIDE == Chat.box
end

-- ---------------------------------------------------------------------------
-- Who took it back
-- ---------------------------------------------------------------------------
-- FOUND IN GAME, then named by this hook: the override installs at login,
-- verifies, and is nil by the time you ask.
--
--   ChatFrameUtil.ActivateChat clears it as its FIRST line, :454
--   reached from OpenChat, :407, reached from [OPENCHATSLASH]
--
-- So pressing "/" does it. That fall-through is the behaviour we asked for --
-- supportsSlashCommands is false so slash commands stay Blizzard's -- and
-- their handoff drops the override on purpose: whoever was just activated
-- owns focus. Not a conflict, and not something re-asserting once at login
-- can fix. It has to be re-asserted after every activation, forever.
--
-- Nothing else in Blizzard's Interface writes that global, which is why two
-- rounds of reading the source got this wrong and one hook got it right.
--
-- Re-asserting happens on the next frame rather than inside the hook: the
-- clear may be one step of a teardown, and setting it again mid-teardown is
-- how you end up fighting a frame that has not finished putting itself away.

Chat.clears = 0

function Chat.Watch()
    if Chat.watching then
        return true
    end
    local util = _G.ChatFrameUtil
    local hook = _G.hooksecurefunc
    if type(util) ~= "table" or type(hook) ~= "function"
       or type(util.ClearChatFocusOverride) ~= "function" then
        return false
    end

    hook(util, "ClearChatFocusOverride", function()
        Chat.clears = Chat.clears + 1
        -- Three frames is enough to name the caller now that we know who it
        -- is; the full trace was for finding it.
        if type(_G.debugstack) == "function" then
            local ok, stack = pcall(_G.debugstack, 2, 3, 0)
            if ok then Chat.clearedBy = stack end
        end
        if not Chat.enabled then
            return
        end
        -- Next frame, out of whatever call stack cleared it.
        local after = _G.C_Timer and _G.C_Timer.After
        if type(after) == "function" then
            after(0, function()
                -- Asking IsOverriding rather than reading the global: it is
                -- the same question through whichever route this client
                -- actually has, and it does not re-claim from someone who
                -- legitimately took the focus for their own box.
                if Chat.enabled and not Chat.IsOverriding()
                   and _G.CHAT_FOCUS_OVERRIDE == nil then
                    Chat.reasserts = (Chat.reasserts or 0) + 1
                    Chat.Enable()
                end
            end)
        end
    end)

    hook(util, "SetChatFocusOverride", function(box)
        if Chat.box and box ~= Chat.box then
            Chat.displacedBy = tostring(box and box.GetName and box:GetName() or box)
        end
    end)

    Chat.watching = true
    return true
end

-- ---------------------------------------------------------------------------
-- Opening it deliberately
-- ---------------------------------------------------------------------------

--- Focus our box, optionally holding something already.
function Chat.Open(prefill)
    -- MVP: without our box, open Blizzard's, already holding the text.
    if not Chat.IsOverriding() then
        local util = _G.ChatFrameUtil
        if util and type(util.OpenChat) == "function" then
            util.OpenChat(prefill or "")
            return nil
        elseif type(_G.ChatFrame_OpenChat) == "function" then
            _G.ChatFrame_OpenChat(prefill or "")
            return nil
        end
    end
    local box = Chat.Build()
    prefill = type(prefill) == "string" and prefill or ""
    box:SetText(prefill)
    box:SetFocus()
    if type(box.SetCursorPosition) == "function" then
        box:SetCursorPosition(#prefill)
    end
    return box
end

-- Bound in Bindings.xml. "/r " is Blizzard's own reply command, so their
-- parser resolves the target -- we never look up who last whispered you.
function MyUI_Reply()
    Chat.Open("/r ")
end

_G.BINDING_NAME_MYUI_REPLY = "Reply to the last whisper"

-- ---------------------------------------------------------------------------
-- The furniture
-- ---------------------------------------------------------------------------
-- Reparented into a hidden frame rather than hidden outright, and the
-- difference matters. A hidden ChatFrame1 reports IsShown() false, and
-- ChooseBoxForSend branches on exactly that (ChatFrameUtil.lua:490) -- so
-- hiding it properly is how you lose the ability to send. Stowed under a
-- hidden parent it still says it is shown, Blizzard's bookkeeping stays true,
-- Edit Mode can reposition it all it likes, and nothing reaches the screen.
--
-- Nothing here is protected: chat frames are ordinary UI, unlike action bars.

--- Take the edit box out of the chat frame BEFORE the chat frame is stowed.
-- ChatFrame1EditBox is declared inside FloatingChatFrameTemplate
-- (FloatingChatFrame.xml:496), so it travels with its parent -- and it is the
-- box "/" falls through to. Stow the frame with the box still inside it and
-- slash commands stop working, which is the one thing this whole design says
-- must keep working.
function Chat.FreeEditBox()
    local box = _G.ChatFrame1EditBox
    if type(box) ~= "table" or Chat.editBoxFreed then
        return false
    end
    Chat.editBoxHome = box:GetParent()
    Chat.editBoxPoints = {}
    if type(box.GetNumPoints) == "function" and type(box.GetPoint) == "function" then
        for i = 1, (box:GetNumPoints() or 0) do
            local ok, a, b, c, d, e = pcall(box.GetPoint, box, i)
            if ok then
                Chat.editBoxPoints[#Chat.editBoxPoints + 1] = { a, b, c, d, e }
            end
        end
    end

    box:SetParent(_G.UIParent)
    box:ClearAllPoints()
    box:SetPoint("BOTTOMLEFT", _G.UIParent, "BOTTOMLEFT",
                 U(Chat.X), U(Chat.Y + Chat.HEIGHT + 14))
    box:SetSize(U(Chat.WIDTH), U(Chat.HEIGHT))
    Chat.editBoxFreed = true
    return true
end

function Chat.HideLog()
    -- Always first: the edit box is declared inside the chat frame, so stowing
    -- the frame with the box still in it is what kills slash commands.
    Chat.FreeEditBox()
    local moved, err = ns.Stow.Group("chat")
    if not moved then
        return false, err
    end
    Chat.logHidden = true
    return true
end

function Chat.ShowLog()
    ns.Stow.Restore("chat")

    local box = _G.ChatFrame1EditBox
    if Chat.editBoxFreed and type(box) == "table" then
        pcall(box.SetParent, box, Chat.editBoxHome)
        if #(Chat.editBoxPoints or {}) > 0 then
            box:ClearAllPoints()
            for _, pt in ipairs(Chat.editBoxPoints) do
                pcall(box.SetPoint, box, pt[1], pt[2], pt[3], pt[4], pt[5])
            end
        end
        Chat.editBoxFreed = false
    end
    Chat.logHidden = false
    return true
end

--- How much is currently stowed. Zero with logHidden true means the frames
-- were not found, which is a different problem from not having tried.
function Chat.StowedCount()
    return ns.Stow.Count("chat")
end

function Chat.OnLogin()
    if ns.db and ns.db.stow and ns.db.stow.raid then
        ns.Stow.Group("raid")
    end
    -- MyUI's own chat box is an extra (MVP M1): Blizzard's box stays in charge.
    if not ns.Extras() then return end
    Chat.Build()
    Chat.Watch()
    if ns.db and ns.db.chat and ns.db.chat.override == false then
        return
    end
    local ok, err = Chat.Enable()
    if not ok and err then
        ns.Print("chat override not installed: " .. tostring(err))
    end

    -- Only once the override is actually in: hiding the log without a way to
    -- type is how you lock yourself out of your own chat.
    if ok and ns.db and ns.db.chat and ns.db.chat.hideLog then
        Chat.HideLog()
    end
end

ns.Chat = Chat
