-- MyUI :: Panel.lua
-- A minimap button and a checklist, so the toggles stop being slash commands.
--
-- Everything here already existed as a command. This is the same state read
-- and written through a switch, which matters for the ones you flip often --
-- Blizzard's chat log especially, which you need back several times an hour.

local ADDON, ns = ...

local Scale, Palette = ns.Scale, ns.Palette
local U = function(v) return Scale.U(v) end

local Panel = {}
ns.Panel = Panel

Panel.ROW_H  = 22
Panel.WIDTH  = 240
Panel.PAD    = 10
Panel.BOX    = 12
Panel.RADIUS = 80      -- how far off the minimap's centre the button sits

local SURFACE = ns.Center and ns.Center.SURFACE or { 10 / 255, 10 / 255, 12 / 255, 0.86 }

-- Each row reads live state rather than a remembered flag, so the panel can
-- never disagree with the game: flip something with a slash command and the
-- switch is already right the next time you open it.
Panel.TOGGLES = {
    {
        key   = "chatlog",
        label = "Blizzard chat log",
        get   = function() return ns.Chat and ns.Chat.logHidden ~= true end,
        set   = function(on) ns.Commands.Run("chat " .. (on and "show" or "hide")) end,
    },
    {
        key   = "override",
        label = "Our chat input on Enter",
        get   = function() return ns.Chat and ns.Chat.IsOverriding() end,
        set   = function(on) ns.Commands.Run("chat " .. (on and "on" or "off")) end,
    },
    {
        key   = "raid",
        label = "Raid frame tab",
        get   = function() return not (ns.Stow and ns.Stow.IsStowed("raid")) end,
        set   = function(on) ns.Commands.Run(on and "stow show raid" or "stow raid") end,
    },
    {
        key   = "center",
        label = "Notification centre",
        get   = function() return ns.Center and ns.Center.IsOpen() end,
        set   = function(on) ns.Commands.Run(on and "center" or "center close") end,
    },
    {
        key   = "outline",
        label = "Frame outlines",
        get   = function() return ns.Outline and ns.Outline.IsShown() end,
        set   = function(on) ns.Commands.Run("outline " .. (on and "on" or "off")) end,
    },
    {
        key   = "show",
        label = "Force every frame visible",
        get   = function() return ns.Registry.forced == true end,
        set   = function(on) ns.Commands.Run("show " .. (on and "on" or "off")) end,
    },
}

local function Border(frame, colorName)
    local t = Scale.Hairline()
    local edges = {}
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local edge = frame:CreateTexture(nil, "OVERLAY")
        edge:SetColorTexture(Palette.Get(colorName))
        if side == "TOP" or side == "BOTTOM" then
            edge:SetHeight(t)
            edge:SetPoint(side .. "LEFT", frame, side .. "LEFT", 0, 0)
            edge:SetPoint(side .. "RIGHT", frame, side .. "RIGHT", 0, 0)
        else
            edge:SetWidth(t)
            edge:SetPoint("TOP" .. side, frame, "TOP" .. side, 0, 0)
            edge:SetPoint("BOTTOM" .. side, frame, "BOTTOM" .. side, 0, 0)
        end
        edges[side] = edge
    end
    return edges
end

-- ---------------------------------------------------------------------------
-- The panel
-- ---------------------------------------------------------------------------

local panel

local function BuildRow(parent, index, spec)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(U(Panel.ROW_H))
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", U(Panel.PAD), -U(Panel.PAD + (index - 1) * Panel.ROW_H))
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -U(Panel.PAD), -U(Panel.PAD + (index - 1) * Panel.ROW_H))

    row.box = CreateFrame("Frame", nil, row)
    row.box:SetSize(U(Panel.BOX), U(Panel.BOX))
    row.box:SetPoint("LEFT", row, "LEFT", 0, 0)
    Border(row.box, "fillDim")

    row.tick = row.box:CreateTexture(nil, "ARTWORK")
    row.tick:SetPoint("TOPLEFT", row.box, "TOPLEFT", U(3), -U(3))
    row.tick:SetPoint("BOTTOMRIGHT", row.box, "BOTTOMRIGHT", -U(3), U(3))
    row.tick:SetColorTexture(Palette.Get("fill"))

    row.label = ns.Frames.Text(row, 11, "textPrimary", "LEFT")
    row.label:SetPoint("LEFT", row.box, "RIGHT", U(9), 0)
    row.label:SetText(spec.label)

    row.spec = spec
    row:SetScript("OnClick", function(self)
        local ok = pcall(self.spec.set, not self.spec.get())
        if not ok then
            ns.Print("could not toggle " .. tostring(self.spec.label))
        end
        Panel.Refresh()
    end)
    return row
end

function Panel.Build()
    if panel then
        return panel
    end
    local height = Panel.PAD * 2 + #Panel.TOGGLES * Panel.ROW_H
    panel = CreateFrame("Frame", "MyUIPanel", UIParent)
    panel:SetFrameStrata("DIALOG")
    panel:SetSize(U(Panel.WIDTH), U(height))
    panel:SetPoint("TOPRIGHT", _G.Minimap or UIParent, "TOPLEFT", -U(8), 0)

    local bg = panel:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(SURFACE[1], SURFACE[2], SURFACE[3], SURFACE[4])
    Border(panel, "fillDim")

    panel.rows = {}
    for i, spec in ipairs(Panel.TOGGLES) do
        panel.rows[i] = BuildRow(panel, i, spec)
    end

    panel:Hide()
    local special = _G.UISpecialFrames
    if type(special) == "table" then
        special[#special + 1] = "MyUIPanel"
    end

    Panel.panel = panel
    return panel
end

function Panel.Refresh()
    if not panel then
        return
    end
    for _, row in ipairs(panel.rows) do
        local on = false
        local ok, value = pcall(row.spec.get)
        if ok then on = value == true end
        row.tick:SetAlpha(on and 1 or 0)
        row.label:SetAlpha(on and 1 or 0.55)
    end
end

function Panel.IsOpen()
    return panel ~= nil and panel:IsShown()
end

function Panel.Toggle()
    local p = Panel.Build()
    if not p then
        return false
    end
    if p:IsShown() then
        p:Hide()
        return false
    end
    Panel.Refresh()
    p:Show()
    return true
end

-- ---------------------------------------------------------------------------
-- The minimap button
-- ---------------------------------------------------------------------------

function Panel.Place(angle)
    if not Panel.button then
        return
    end
    angle = tonumber(angle) or 210
    Panel.angle = angle
    if ns.db then
        ns.db.panel = ns.db.panel or {}
        ns.db.panel.angle = angle
    end
    local rad = math.rad(angle)
    Panel.button:ClearAllPoints()
    Panel.button:SetPoint("CENTER", _G.Minimap or UIParent, "CENTER",
                          math.cos(rad) * Panel.RADIUS, math.sin(rad) * Panel.RADIUS)
end

function Panel.BuildButton()
    if Panel.button then
        return Panel.button
    end
    local parent = _G.Minimap or UIParent
    local btn = CreateFrame("Button", "MyUIMinimapButton", parent)
    btn:SetSize(U(20), U(20))
    btn:SetFrameStrata("MEDIUM")

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(SURFACE[1], SURFACE[2], SURFACE[3], SURFACE[4])
    Border(btn, "fillDim")

    -- No icon file. The design owns one texture and this is not it, so the
    -- button is the rail's own vocabulary: a dot.
    btn.dot = btn:CreateTexture(nil, "ARTWORK")
    btn.dot:SetSize(U(8), U(8))
    btn.dot:SetPoint("CENTER")
    btn.dot:SetColorTexture(Palette.Get("notifBlue"))

    btn:RegisterForDrag("LeftButton")
    btn:SetScript("OnClick", function() Panel.Toggle() end)
    -- Placed where you let go, rather than following the cursor. Following
    -- would need a second OnUpdate and RULES allows exactly one, for cursor
    -- proximity and the peek clock. A minimap button is not worth spending it.
    btn:SetScript("OnDragStop", function()
        -- Not `_G.Minimap and _G.Minimap:GetCenter()`: an `and` expression
        -- keeps only the FIRST return value, so my was always nil and the
        -- second coordinate arrived missing. Guard, then call.
        local map = _G.Minimap
        if not map or type(map.GetCenter) ~= "function" then
            return
        end
        local mx, my = map:GetCenter()
        local cx, cy = GetCursorPosition()
        local scale = _G.UIParent:GetEffectiveScale()
        if not mx or not my or not cx or not cy or not scale or scale == 0 then
            return
        end
        Panel.Place(math.deg(math.atan2(cy / scale - my, cx / scale - mx)))
    end)

    Panel.button = btn
    return btn
end

function Panel.OnLogin()
    Panel.BuildButton()
    Panel.Build()
    Panel.Place(ns.db and ns.db.panel and ns.db.panel.angle or 210)
end

ns.Panel = Panel
