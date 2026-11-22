-- MyUI :: Social.lua
-- Round 005 play (Mykel): "I can hear my guild mates logging in but I don't
-- have any way to check who without calling up the default UI."
--
--   * A TOAST when someone comes online -- a guild mate or a friend --
--     violet, the people hue. Several at once (a raid night) roll into one:
--     "Online: Aria, Bren +3".
--   * WHO'S ONLINE, summoned like the quest list (Summon.lua): guild and
--     friends, name and where they are; click a name to whisper.
--     Opened from the chat panel's header, its key, or /myui social.
--
-- Roster data is plain Lua; names arriving in chat events can be secret in
-- restricted content, and those are forwarded to SetText, never read.

local ADDON, ns = ...

local Scale, Palette = ns.Scale, ns.Palette
local U = function(v) return Scale.U(v) end

local Social = {}
ns.Social = Social

Social.WIDTH  = 280
Social.ROW    = 20
Social.ROWS   = 14
Social.GATHER = 2.0     -- seconds online notices gather before one toast
Social.NAMES  = 2       -- names spelled out in that toast

local function API(path, ...) return ns.Sources.API(path, ...) end

-- Sources.API keeps three returns; these readers need all of them
-- (GetGuildRosterInfo, GetAchievementCriteriaInfo).
local function APIN(name, ...)
    local fn = _G[name]
    if type(fn) ~= "function" then return nil end
    local r = { pcall(fn, ...) }
    if not r[1] then return nil end
    return unpack(r, 2, table.maxn(r))
end

-- ---------------------------------------------------------------------------
-- Who is online
-- ---------------------------------------------------------------------------

local function Short(name)
    if type(name) ~= "string" or ns.Compat.IsSecret(name) then return name end
    return (name:gsub("%-.*$", ""))
end

--- Online guild members: { name, full, zone, level, guild = true }.
function Social.Guild()
    local out = {}
    local total, online = API("GetNumGuildMembers")
    total = total or 0
    for i = 1, total do
        local name, _, _, level, _, zone, _, _, isOnline = APIN("GetGuildRosterInfo", i)
        if isOnline and name then
            out[#out + 1] = { name = Short(name), full = name, zone = zone, level = level, guild = true }
        end
        if online and #out >= online then break end
    end
    return out
end

--- Online friends, character and Battle.net: { name, full, zone, bnet }.
function Social.Friends()
    local out = {}
    for i = 1, API("C_FriendList.GetNumFriends") or 0 do
        local f = API("C_FriendList.GetFriendInfoByIndex", i)
        if type(f) == "table" and f.connected and f.name then
            out[#out + 1] = { name = Short(f.name), full = f.name, zone = f.area, level = f.level }
        end
    end
    for i = 1, API("BNGetNumFriends") or 0 do
        local a = API("C_BattleNet.GetFriendAccountInfo", i)
        local g = type(a) == "table" and a.gameAccountInfo
        if type(g) == "table" and g.isOnline then
            out[#out + 1] = { name = a.accountName, bnet = a.accountName,
                              zone = g.clientProgram == "WoW" and g.areaName or g.richPresence }
        end
    end
    return out
end

-- ---------------------------------------------------------------------------
-- Toasts: "Online: Aria, Bren +3"
-- ---------------------------------------------------------------------------

Social.pending = {}

function Social.Flush()
    local names = Social.pending
    Social.pending = {}
    Social.gathering = false
    if #names == 0 then return nil end
    local shown = {}
    for i = 1, math.min(#names, Social.NAMES) do shown[i] = names[i] end
    local text = "Online: " .. table.concat(shown, ", ")
    if #names > Social.NAMES then text = text .. (" +%d"):format(#names - Social.NAMES) end
    ns.Toast.Add("violet", text)
    return text
end

--- Someone came online. Secret names are not spelled (they cannot be
-- joined into a string); they still count.
function Social.CameOnline(name)
    if ns.Compat.IsSecret(name) or type(name) ~= "string" then name = "someone" end
    Social.pending[#Social.pending + 1] = Short(name)
    if not Social.gathering then
        Social.gathering = true
        C_Timer.After(Social.GATHER, Social.Flush)
    end
    if Social.open then Social.Refresh() end
end

local onlinePattern
local function OnlinePattern()
    if onlinePattern == nil then
        local fmt = _G.ERR_FRIEND_ONLINE_SS
        onlinePattern = type(fmt) == "string" and ns.Sources.ToPattern(fmt) or false
    end
    return onlinePattern
end

--- "|Hplayer:Aria|h[Aria]|h has come online." -- guild mates and friends.
function Social.OnSystem(text)
    if type(text) ~= "string" or ns.Compat.IsSecret(text) then return nil end
    local pat = OnlinePattern()
    if not pat then return nil end
    local a, b = text:match(pat)
    local name = b or a
    if name then Social.CameOnline(name) end
    return name
end

-- ---------------------------------------------------------------------------
-- The panel
-- ---------------------------------------------------------------------------

local panel, rows = nil, {}

local function Row(i)
    local r = CreateFrame("Button", nil, panel)
    r:SetHeight(U(Social.ROW))
    local pad = ns.Summon.PAD
    r:SetPoint("TOPLEFT", panel, "TOPLEFT", U(pad), -U(ns.Summon.HEADER_H + 4 + (i - 1) * Social.ROW))
    r:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -U(pad), -U(ns.Summon.HEADER_H + 4 + (i - 1) * Social.ROW))
    r.zone = ns.Frames.Text(r, 10, "textDim", "RIGHT")
    r.zone:SetPoint("RIGHT")
    r.zone:SetWidth(U(120))
    r.zone:SetWordWrap(false)
    r.name = ns.Frames.Text(r, 11, "textPrimary", "LEFT")
    r.name:SetPoint("LEFT")
    r.name:SetPoint("RIGHT", r.zone, "LEFT", -U(8), 0)
    r.name:SetWordWrap(false)
    r:SetScript("OnClick", function(self) if self.who then Social.Whisper(self.who) end end)
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
    for _, r in ipairs(rows) do r:EnableMouse(on and r.who ~= nil) end
end

function Social.Build()
    if panel then return panel end
    panel = CreateFrame("Frame", "MyUISocial", UIParent)
    panel:SetFrameStrata("DIALOG")
    panel:SetWidth(U(Social.WIDTH))
    -- Beside the chat panel, where talking to someone starts.
    local chat = ns.Talk and ns.Talk.Build and ns.Talk.Build()
    if chat then
        panel:SetPoint("BOTTOMLEFT", chat, "BOTTOMRIGHT", U(8), 0)
    else
        panel:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", U(320), U(260))
    end
    local header = ns.Summon.Chrome(panel, "Online")
    for i = 1, Social.ROWS do rows[i] = Row(i) end
    panel:Hide()
    Social.panel, Social.rows = panel, rows
    Social.summon = ns.Summon.Attach({
        key = "social", frame = panel, header = header,
        show = function()
            Social.open = true
            -- Ask the server for a fresh roster; GUILD_ROSTER_UPDATE repaints.
            API("C_GuildInfo.GuildRoster")
            Social.Refresh()
            panel:Show()
            SetMouse(true)
        end,
        hide = function()
            Social.open = false
            SetMouse(false)
            panel:Hide()
        end,
    })
    panel:HookScript("OnHide", function() if Social.summon.open then Social.summon.open = false end end)
    return panel
end

--- Guild first, then friends; a heading line for each that has anyone.
function Social.Lines()
    local lines = {}
    local guild, friends = Social.Guild(), Social.Friends()
    if #guild > 0 then
        lines[#lines + 1] = { heading = ("guild %d"):format(#guild) }
        for _, g in ipairs(guild) do lines[#lines + 1] = g end
    end
    if #friends > 0 then
        lines[#lines + 1] = { heading = ("friends %d"):format(#friends) }
        for _, f in ipairs(friends) do lines[#lines + 1] = f end
    end
    return lines, #guild + #friends
end

function Social.Refresh()
    if not panel then return end
    local lines, n = Social.Lines()
    panel.__header.title:SetText(("Online  %d"):format(n))
    local shown = math.min(#lines, Social.ROWS)
    for i, r in ipairs(rows) do
        local l = lines[i]
        if l and i <= shown then
            if l.heading then
                r.name:SetText(l.heading)
                r.name:SetTextColor(Palette.Get("textDim"))
                r.zone:SetText("")
                r.who = nil
            else
                ns.Guard.Send(r.name, "SetText", l.name)
                r.name:SetTextColor(Palette.Get(l.bnet and "notifBlue" or "textPrimary"))
                ns.Guard.Send(r.zone, "SetText", l.zone or "")
                r.who = l
            end
            r:Show()
        else
            r.who = nil
            r:Hide()
        end
    end
    if n == 0 then
        rows[1].name:SetText("nobody online")
        rows[1].name:SetTextColor(Palette.Get("textDim"))
        rows[1].zone:SetText("")
        rows[1]:Show()
        shown = 1
    end
    SetMouse(Social.open == true)
    panel:SetHeight(U(ns.Summon.HEADER_H + 4 + shown * Social.ROW + ns.Summon.PAD))
end

--- Whisper them: a character by name, a Battle.net friend through
-- Blizzard's own Battle.net tell.
function Social.Whisper(who)
    if who.bnet then
        local tell = _G.ChatFrameUtil and _G.ChatFrameUtil.SendBNetTell or _G.ChatFrame_SendBNetTell
        if type(tell) == "function" then pcall(tell, who.bnet) end
        return "bnet"
    end
    ns.Chat.Open(("/w %s "):format(tostring(who.full or who.name)))
    return "whisper"
end

function Social.Toggle()
    Social.Build()
    if Social.open then Social.summon:Close("asked") return false end
    return Social.summon:Open()
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

Social.EVENTS = {
    CHAT_MSG_SYSTEM = function(text) Social.OnSystem(text) end,
    BN_FRIEND_ACCOUNT_ONLINE = function(id)
        local a = API("C_BattleNet.GetAccountInfoByID", id)
        Social.CameOnline(type(a) == "table" and a.accountName or nil)
    end,
    GUILD_ROSTER_UPDATE = function() if Social.open then Social.Refresh() end end,
    FRIENDLIST_UPDATE = function() if Social.open then Social.Refresh() end end,
    BN_FRIEND_INFO_CHANGED = function() if Social.open then Social.Refresh() end end,
}

function Social.OnLogin()
    if ns.Switches and not ns.Switches.On("chat") then return end
    local d = CreateFrame("Frame", "MyUISocialDriver", UIParent)
    for event in pairs(Social.EVENTS) do pcall(d.RegisterEvent, d, event) end
    d:SetScript("OnEvent", function(_, event, ...)
        local fn = Social.EVENTS[event]
        if fn then fn(...) end
    end)
    Social.driver = d
    Social.Build()
end

function _G.MyUI_Social() Social.Toggle() end
_G.BINDING_NAME_MYUI_SOCIAL = "Show who's online"
