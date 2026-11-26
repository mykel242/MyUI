-- MyUI :: Features.lua
-- The features panel: every switch (Switches.lua) as a row you click, on the
-- same grid as the other summoned panels.
--
-- 2026-11-26 (Mykel): "an in game panel (styled like the others) with on/off
-- switches for each feature so i can just click through many combinations
-- without typing a lot of slash commands".
--
-- A row is one switch: its name, and on (MyUI's) or off (Blizzard's). A
-- click flips it. Switches that touch protected frames apply on /reload;
-- those say "reload" until then, and the footer's reload button does it
-- (a click is a hardware event, so ReloadUI is allowed from it).

local ADDON, ns = ...

local Scale, Palette = ns.Scale, ns.Palette
local U = function(v) return Scale.U(v) end

local Features = {}
ns.Features = Features

local panel

--- What each switch was when this session started: a reload switch is
-- waiting while it differs.
Features.atLogin = {}

function Features.Snapshot()
    for _, s in ipairs(ns.Switches.LIST) do
        Features.atLogin[s.key] = ns.Switches.On(s.key)
    end
end

--- Is this switch's change waiting for a /reload?
function Features.Waiting(key)
    local s = ns.Switches.BY_KEY[key]
    if not (s and s.reload) then return false end
    local was = Features.atLogin[key]
    return was ~= nil and was ~= ns.Switches.On(key)
end

--- How many changes wait for a /reload.
function Features.WaitingCount()
    local n = 0
    for _, s in ipairs(ns.Switches.LIST) do
        if Features.Waiting(s.key) then n = n + 1 end
    end
    return n
end

--- Flip one switch, or set it. Returns the switch's new state.
function Features.Flip(key, on)
    if on == nil then on = not ns.Switches.On(key) end
    ns.Switches.Set(key, on)
    -- A frame given back keeps its place; the dock columns move off it.
    if ns.Summon then ns.Summon.Layout() end
    if ns.Dev then
        ns.Dev.Add("command", ("feature %s %s"):format(key, on and "on" or "off"))
    end
    Features.Refresh()
    return ns.Switches.On(key)
end

--- Every switch at once.
function Features.All(on)
    for _, s in ipairs(ns.Switches.LIST) do ns.Switches.Set(s.key, on) end
    if ns.Summon then ns.Summon.Layout() end
    if ns.Dev then ns.Dev.Add("command", "features all " .. (on and "on" or "off")) end
    Features.Refresh()
end

function Features.IsOpen()
    return panel ~= nil and panel:IsShown()
end

-- ---------------------------------------------------------------------------
-- The panel
-- ---------------------------------------------------------------------------

local function BuildRow(parent, index)
    local S = ns.Summon
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(U(S.ROW_H))
    local top = S.Top(false) + (index - 1) * U(S.ROW_H)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", U(S.PAD), -top)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -U(S.PAD), -top)
    row.dot = S.Dot(row)
    row.dot:SetPoint("LEFT")
    row.state = ns.Frames.Text(row, 10, "textDim", "RIGHT")
    row.state:SetPoint("RIGHT")
    row.state:SetWidth(U(80))
    row.name = ns.Frames.Text(row, 11, "textPrimary", "LEFT")
    row.name:SetPoint("LEFT", row.dot, "RIGHT", U(S.GAP), 0)
    row.name:SetPoint("RIGHT", row.state, "LEFT", -U(S.GAP), 0)
    row.name:SetWordWrap(false)
    row:RegisterForClicks("LeftButtonUp")
    row:SetScript("OnClick", function(self)
        if self.switch then Features.Flip(self.switch.key) end
    end)
    -- What the switch does, on the line under the rows, while pointed at.
    row:SetScript("OnEnter", function(self)
        if self.switch and panel then
            local on = ns.Switches.On(self.switch.key)
            panel.note:SetText(on and ("MyUI: " .. self.switch.mine) or "Blizzard's own")
        end
    end)
    row:SetScript("OnLeave", function()
        if panel then panel.note:SetText(Features.Hint()) end
    end)
    ns.Frames.HoverEdge(row, 2)
    row:EnableMouse(false)
    return row
end

--- The note line when nothing is pointed at.
function Features.Hint()
    local n = Features.WaitingCount()
    if n > 0 then
        return ("%d change%s wait%s for a reload"):format(n, n == 1 and "" or "s", n == 1 and "s" or "")
    end
    return "click a feature: on is MyUI's, off is Blizzard's"
end

function Features.Build()
    if panel then return panel end
    local S = ns.Summon
    panel = CreateFrame("Frame", "MyUIFeatures", UIParent)
    S.Depth(panel)
    panel:SetSize(U(S.WIDTH), U(200))
    local d = S.DOCK.left
    panel:SetPoint(d.point, UIParent, d.point, U(d.x), U(d.y))

    local header = S.Chrome(panel, "Features")

    panel.rows = {}
    for i, s in ipairs(ns.Switches.LIST) do
        local row = BuildRow(panel, i)
        row.switch = s
        panel.rows[i] = row
    end

    panel.note = ns.Frames.Text(panel, 10, "textDim", "LEFT")
    local below = S.Top(false) + #panel.rows * U(S.ROW_H)
    panel.note:SetPoint("TOPLEFT", panel, "TOPLEFT", U(S.PAD), -below)
    panel.note:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -U(S.PAD), -below)
    panel.note:SetHeight(U(S.ROW_H))
    panel.note:SetWordWrap(false)

    S.Footer(panel, {
        { "all on", function() Features.All(true) end },
        { "all off", function() Features.All(false) end },
        -- A click is a hardware event: ReloadUI is allowed from it.
        { "reload", function() if _G.ReloadUI then _G.ReloadUI() end end },
    })

    panel:Hide()
    local special = _G.UISpecialFrames
    if type(special) == "table" then special[#special + 1] = "MyUIFeatures" end

    Features.panel = panel
    Features.summon = S.Attach({
        key = "features", frame = panel, header = header, dock = "left", order = 6,
        refresh = function() Features.Refresh() end,
        show = function()
            panel:Show()
            Features.Refresh()
        end,
        hide = function() panel:Hide() end,
    })
    panel:HookScript("OnHide", function()
        if Features.summon.open then Features.summon.open = false end
    end)
    return panel
end

function Features.Refresh()
    if not panel then return end
    local S = ns.Summon
    local open = Features.summon and Features.summon.open or false
    for _, row in ipairs(panel.rows) do
        local s = row.switch
        local on = ns.Switches.On(s.key)
        local waiting = Features.Waiting(s.key)
        row.dot:SetHue(on and "notifGreen" or "textDim")
        row.name:SetText(s.label)
        row.name:SetTextColor(Palette.Get(on and "textPrimary" or "textDim"))
        row.state:SetText((on and "on" or "off") .. (waiting and " \194\183 reload" or ""))
        row.state:SetTextColor(Palette.Get(waiting and "notifAmber" or (on and "textPrimary" or "textDim")))
        row:EnableMouse(open)
        row:Show()
    end
    local waiting = Features.WaitingCount()
    local title = "Features"
    if waiting > 0 then title = title .. (" \194\183 %d to reload"):format(waiting) end
    panel.__header.title:SetText(title)
    panel.note:SetText(Features.Hint())
    local reload = panel.__footer.actions[3]
    reload.text:SetTextColor(Palette.Get(waiting > 0 and "notifAmber" or "textDim"))
    S.Mouse(panel, open)
    panel:SetHeight(S.Height((#panel.rows + 1) * U(S.ROW_H), false, true))
    if open then S.Layout() end
end

function Features.Open()
    Features.Build()
    return Features.summon:Open()
end

function Features.Close()
    if Features.summon then Features.summon:Close("asked") end
    return true
end

function Features.Toggle()
    if Features.IsOpen() then return Features.Close() end
    return Features.Open()
end

function _G.MyUI_Features()
    Features.Toggle()
end
_G.BINDING_NAME_MYUI_FEATURES = "Show MyUI's features (on/off)"

function Features.OnLogin()
    Features.Snapshot()
    -- Built now, not on first open: a panel left pinned comes back at login
    -- only if it is attached by then (Summon.Restore). Charon play: "the
    -- features panel did not stay after the reload despite being pinned".
    Features.Build()
end

ns.Features = Features
