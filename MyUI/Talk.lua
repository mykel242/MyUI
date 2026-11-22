-- MyUI :: Talk.lua
-- Round 005 (Mykel: "a version of myui chat that matches the most recent
-- panel UI"). Chat as a summoned panel, like the quest list and the history
-- (Summon.lua): the same surface, pin and close, gone by itself when you are
-- done with it.
--
--   * READING. MyUI keeps the last messages itself, from the CHAT_MSG_
--     events (Blizzard's chat log stays hidden, untouched). Filters in the
--     header: all, whispers, group, guild, say. Each row: who, then what,
--     up to two lines.
--   * ANSWERING. Click a row to reply on its channel (a whisper back, /p,
--     /g ...). Typing goes through Blizzard's own box (Chat.Open), which does
--     the routing -- MyUI never sends for you.
--   * TOASTS. Whispers already toast (Sources.lua). Party and instance
--     chat toast too, outside raids; guild and raid only when your name is
--     in the message. "online N" in the header opens who's online
--     (Social.lua).
--
-- 12.1: a message or a sender can arrive SECRET in restricted content. Those
-- are kept and forwarded to SetText through Guard.Send -- never joined,
-- searched or measured -- and never toasted.

local ADDON, ns = ...

local Scale, Palette = ns.Scale, ns.Palette
local U = function(v) return Scale.U(v) end

local Talk = {}
ns.Talk = Talk

Talk.KEEP   = 200       -- messages kept
Talk.WIDTH  = 400
Talk.ROW    = 32        -- who + up to two lines of what
Talk.ROWS   = 9
Talk.WHO_W  = 92
Talk.FILTER_H = 22
-- Where Blizzard's chat sat: the left edge, above the left wing.
Talk.ANCHOR = { point = "BOTTOMLEFT", x = 16, y = 300 }

-- Each chat event: its group (the filter), its colour, and how a reply
-- starts. A whisper replies to its sender.
Talk.EVENTS = {
    CHAT_MSG_WHISPER         = { group = "whisper", colour = "notifViolet", reply = "whisper" },
    CHAT_MSG_WHISPER_INFORM  = { group = "whisper", colour = "notifViolet", reply = "whisper", mine = true },
    CHAT_MSG_BN_WHISPER      = { group = "whisper", colour = "notifViolet", reply = "/r " },
    CHAT_MSG_BN_WHISPER_INFORM = { group = "whisper", colour = "notifViolet", reply = "/r ", mine = true },
    CHAT_MSG_PARTY           = { group = "group", colour = "notifBlue", reply = "/p " },
    CHAT_MSG_PARTY_LEADER    = { group = "group", colour = "notifBlue", reply = "/p " },
    CHAT_MSG_INSTANCE_CHAT   = { group = "group", colour = "notifOrange", reply = "/i " },
    CHAT_MSG_INSTANCE_CHAT_LEADER = { group = "group", colour = "notifOrange", reply = "/i " },
    CHAT_MSG_RAID            = { group = "group", colour = "notifOrange", reply = "/raid ", raid = true },
    CHAT_MSG_RAID_LEADER     = { group = "group", colour = "notifOrange", reply = "/raid ", raid = true },
    CHAT_MSG_RAID_WARNING    = { group = "group", colour = "notifOrange", reply = "/raid ", raid = true },
    CHAT_MSG_GUILD           = { group = "guild", colour = "notifGreen", reply = "/g " },
    CHAT_MSG_OFFICER         = { group = "guild", colour = "notifGreen", reply = "/o " },
    CHAT_MSG_SAY             = { group = "say", colour = "textPrimary", reply = "/s " },
    CHAT_MSG_YELL            = { group = "say", colour = "textPrimary", reply = "/y " },
    CHAT_MSG_EMOTE           = { group = "say", colour = "textDim", reply = "/e " },
}

Talk.GROUPS = { "whisper", "group", "guild", "say" }
Talk.GROUP_LABEL = { whisper = "whispers", group = "group", guild = "guild", say = "say" }

Talk.log = {}           -- newest first: { event, who, text, at, group, colour }
Talk.filter = nil
Talk.unread = {}        -- group -> count since the panel was last open

local function Secret(v) return ns.Compat.IsSecret(v) end

local function Short(name)
    if type(name) ~= "string" or Secret(name) then return name end
    return (name:gsub("%-.*$", ""))
end

local function MyName()
    local n = _G.UnitName and _G.UnitName("player")
    return type(n) == "string" and not Secret(n) and n or nil
end

-- ---------------------------------------------------------------------------
-- Keeping and toasting
-- ---------------------------------------------------------------------------

--- A message arrived. Returns what was kept.
function Talk.Add(event, text, sender)
    local spec = Talk.EVENTS[event]
    if not spec then return nil end
    local e = { event = event, who = sender, text = text, at = ns.Reveal.Now(),
                group = spec.group, colour = spec.colour, mine = spec.mine }
    table.insert(Talk.log, 1, e)
    if #Talk.log > Talk.KEEP then Talk.log[#Talk.log] = nil end
    if not Talk.open and not spec.mine then
        Talk.unread[spec.group] = (Talk.unread[spec.group] or 0) + 1
    end
    Talk.MaybeToast(e, spec)
    if Talk.open then Talk.Refresh() end
    return e
end

--- Whispers toast from Sources. Party and instance chat toast outside a
-- raid; guild and raid chat only when they name you. Nothing secret toasts.
function Talk.MaybeToast(e, spec)
    if spec.mine or spec.group == "whisper" or spec.group == "say" then return false end
    if Secret(e.text) or Secret(e.who) or type(e.text) ~= "string" then return false end
    local inRaid = _G.IsInRaid and _G.IsInRaid()
    local me = MyName()
    local named = me and e.text:lower():find(me:lower(), 1, true) ~= nil
    local wanted
    if spec.group == "group" and not spec.raid and not inRaid then
        wanted = true
    else
        wanted = named
    end
    if not wanted then return false end
    ns.Toast.Add("violet", ("%s: %s"):format(tostring(Short(e.who) or "?"), e.text))
    return true
end

-- ---------------------------------------------------------------------------
-- The panel
-- ---------------------------------------------------------------------------

local panel, rows = nil, {}

local function Row(i)
    local r = CreateFrame("Button", nil, panel)
    r:SetHeight(U(Talk.ROW))
    local pad = ns.Summon.PAD
    local top = ns.Summon.HEADER_H + Talk.FILTER_H + 4 + (i - 1) * Talk.ROW
    r:SetPoint("TOPLEFT", panel, "TOPLEFT", U(pad), -U(top))
    r:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -U(pad), -U(top))
    r.who = ns.Frames.Text(r, 10, "textPrimary", "LEFT")
    r.who:SetPoint("TOPLEFT", r, "TOPLEFT", 0, -U(2))
    r.who:SetWidth(U(Talk.WHO_W))
    r.who:SetWordWrap(false)
    r.text = ns.Frames.Text(r, 11, "textPrimary", "LEFT")
    r.text:SetPoint("TOPLEFT", r, "TOPLEFT", U(Talk.WHO_W + 8), -U(1))
    r.text:SetPoint("TOPRIGHT", r, "TOPRIGHT", -U(28), -U(1))
    r.text:SetHeight(U(Talk.ROW - 4))
    r.text:SetJustifyV("TOP")
    r.text:SetWordWrap(true)
    if r.text.SetMaxLines then r.text:SetMaxLines(2) end
    r.age = ns.Frames.Text(r, 10, "textDim", "RIGHT")
    r.age:SetPoint("TOPRIGHT", r, "TOPRIGHT", 0, -U(2))
    r:SetScript("OnClick", function(self) if self.entry then Talk.Reply(self.entry) end end)
    ns.Frames.HoverEdge(r, 2)
    r:EnableMouse(false)
    r:Hide()
    return r
end

local function SetMouse(on)
    local h = panel and panel.__header
    if not h then return end
    h.pin:EnableMouse(on)
    h.close:EnableMouse(on)
    panel.online:EnableMouse(on)
    panel.type:EnableMouse(on)
    for _, c in ipairs(panel.chips) do c:EnableMouse(on) end
    for _, r in ipairs(rows) do r:EnableMouse(on and r.entry ~= nil) end
end

function Talk.Build()
    if panel then return panel end
    panel = CreateFrame("Frame", "MyUITalk", UIParent)
    panel:SetFrameStrata("DIALOG")
    local pad = ns.Summon.PAD
    panel:SetSize(U(Talk.WIDTH), U(ns.Summon.HEADER_H + Talk.FILTER_H + 8 + Talk.ROWS * Talk.ROW + 26))
    local a = Talk.ANCHOR
    panel:SetPoint(a.point, UIParent, a.point, U(a.x), U(a.y))
    local header = ns.Summon.Chrome(panel, "Chat")

    -- Who's online, from the header.
    panel.online = CreateFrame("Button", nil, panel)
    panel.online:SetSize(U(80), U(16))
    panel.online:SetPoint("LEFT", header.title, "RIGHT", U(12), 0)
    panel.online.text = ns.Frames.Text(panel.online, 10, "textDim", "LEFT")
    panel.online.text:SetAllPoints()
    panel.online:SetScript("OnClick", function() if ns.Social then ns.Social.Toggle() end end)

    -- Filters: all, then each group with what came in while you were away.
    panel.chips = {}
    local x = pad
    local widths = { 34, 74, 56, 50, 40 }
    for i, group in ipairs({ "all", "whisper", "group", "guild", "say" }) do
        local c = CreateFrame("Button", nil, panel)
        c:SetSize(U(widths[i]), U(Talk.FILTER_H - 4))
        c:SetPoint("TOPLEFT", panel, "TOPLEFT", U(x), -U(ns.Summon.HEADER_H + 3))
        x = x + widths[i] + 6
        c.text = ns.Frames.Text(c, 10, "textPrimary", "LEFT")
        c.text:SetAllPoints()
        c.group = group ~= "all" and group or nil
        c:SetScript("OnClick", function(self) Talk.Filter(self.group) end)
        panel.chips[i] = c
    end
    local under = ns.Summon.Hairline(panel, "trough")
    under:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -U(ns.Summon.HEADER_H + Talk.FILTER_H))
    under:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -U(ns.Summon.HEADER_H + Talk.FILTER_H))

    for i = 1, Talk.ROWS do rows[i] = Row(i) end

    -- The way in to typing: Blizzard's box, already on the filter's channel.
    panel.type = CreateFrame("Button", nil, panel)
    panel.type:SetHeight(U(18))
    panel.type:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", U(pad), U(5))
    panel.type:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -U(pad), U(5))
    panel.type.text = ns.Frames.Text(panel.type, 10, "textDim", "LEFT")
    panel.type.text:SetAllPoints()
    panel.type.text:SetText("type...  (or click a message to answer it)")
    panel.type:SetScript("OnClick", function() Talk.Type() end)
    ns.Frames.HoverEdge(panel.type, 2)

    panel:Hide()
    Talk.panel, Talk.rows = panel, rows
    Talk.summon = ns.Summon.Attach({
        key = "chat", frame = panel, header = header,
        show = function()
            Talk.open = true
            Talk.Refresh()
            panel:Show()
            SetMouse(true)
        end,
        hide = function()
            Talk.open = false
            Talk.unread = {}
            -- A filter is for this look (a whisper toast opens at whispers).
            Talk.filter = nil
            SetMouse(false)
            panel:Hide()
        end,
    })
    panel:HookScript("OnHide", function() if Talk.summon.open then Talk.summon.open = false end end)
    SetMouse(false)
    return panel
end

function Talk.Lines()
    local out = {}
    for _, e in ipairs(Talk.log) do
        if Talk.filter == nil or Talk.filter == e.group then
            out[#out + 1] = e
            if #out >= Talk.ROWS then break end
        end
    end
    return out
end

function Talk.Refresh()
    if not panel then return end
    local counts = { all = 0 }
    for _, e in ipairs(Talk.log) do
        counts[e.group] = (counts[e.group] or 0) + 1
        counts.all = counts.all + 1
    end
    for _, c in ipairs(panel.chips) do
        local label = c.group and Talk.GROUP_LABEL[c.group] or "all"
        local new = c.group and (Talk.unread[c.group] or 0) or 0
        c.text:SetText(new > 0 and ("%s %d"):format(label, new) or label)
        local lit = Talk.filter == c.group
        c.text:SetTextColor(Palette.Get(lit and "textPrimary" or (new > 0 and "notifAmber" or "textDim")))
    end
    local online = ns.Social and (select(2, ns.Social.Lines())) or 0
    panel.online.text:SetText(("online %d"):format(online))

    local lines = Talk.Lines()
    local now = ns.Reveal.Now()
    for i, r in ipairs(rows) do
        local e = lines[#lines - i + 1]   -- oldest at the top, newest by the box
        if e then
            if e.mine then
                r.who:SetText("you")
                r.who:SetTextColor(Palette.Get("textDim"))
            else
                ns.Guard.Send(r.who, "SetText", Short(e.who) or "")
                r.who:SetTextColor(Palette.Get(e.colour))
            end
            ns.Guard.Send(r.text, "SetText", e.text or "")
            r.age:SetText(ns.Toast.FormatAge(now - e.at))
            r.entry = e
            r:Show()
        else
            r.entry = nil
            r:Hide()
        end
    end
    SetMouse(Talk.open == true)
end

function Talk.Filter(group)
    Talk.filter = group
    if group then Talk.unread[group] = nil end
    Talk.Refresh()
    return Talk.filter
end

--- Answer a message on its channel: a whisper back to its sender, or the
-- channel's own slash. A secret sender cannot be named; /r answers them.
function Talk.Reply(e)
    local spec = Talk.EVENTS[e.event] or {}
    local prefill = spec.reply or ""
    if prefill == "whisper" then
        if Secret(e.who) or type(e.who) ~= "string" then
            prefill = "/r "
        else
            prefill = ("/w %s "):format(e.who)
        end
    end
    ns.Chat.Open(prefill)
    return prefill
end

--- The type row: Blizzard's box, on the channel the filter shows.
Talk.TYPE_PREFIX = { whisper = "/r ", group = nil, guild = "/g ", say = "/s " }
function Talk.Type()
    local prefix = Talk.filter and Talk.TYPE_PREFIX[Talk.filter]
    if Talk.filter == "group" then
        prefix = (_G.IsInRaid and _G.IsInRaid()) and "/raid " or "/p "
    end
    ns.Chat.Open(prefix or "")
    return prefix or ""
end

function Talk.Open(group)
    Talk.Build()
    if group ~= nil then Talk.filter = group; Talk.unread[group] = nil end
    return Talk.summon:Open()
end

function Talk.Toggle()
    Talk.Build()
    if Talk.open then Talk.summon:Close("asked") return false end
    return Talk.summon:Open()
end

function Talk.Active()
    return Talk.enabled == true
end

function Talk.OnLogin()
    if ns.Switches and not ns.Switches.On("chat") then return end
    Talk.enabled = true
    local d = CreateFrame("Frame", "MyUITalkDriver", UIParent)
    for event in pairs(Talk.EVENTS) do pcall(d.RegisterEvent, d, event) end
    d:SetScript("OnEvent", function(_, event, text, sender) Talk.Add(event, text, sender) end)
    Talk.driver = d
    Talk.Build()
    -- Ages tick while it is open.
    local function tick()
        if Talk.open then Talk.Refresh() end
        C_Timer.After(5, tick)
    end
    C_Timer.After(5, tick)
end

function _G.MyUI_Talk() Talk.Toggle() end
_G.BINDING_NAME_MYUI_TALK = "Show chat"
