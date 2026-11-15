-- MyUI :: Center.lua
-- The notification centre. Round 5, 5a: "The center is the rail" -- not a
-- window that appears elsewhere, but the rail widening at the same anchor and
-- closing again.
--
-- It exists because the rail became lossy on purpose. Dots age out, the pool
-- has a ceiling, and the chat log is stowed -- so a whisper is a dot and
-- nothing else until something can show you what it said. The log has held
-- every one of them since it was built; this is the first thing that reads it.
--
-- Opened by a key rather than by clicking the rail. The rail gave up its
-- entire mouse surface so the left edge of the screen passes clicks to the
-- world, and a keybinding costs no pixels at all. Clicking a dot to open the
-- centre already filtered is the obvious next gesture and needs the rail to
-- take the mouse back, which is a decision worth making on its own.

local ADDON, ns = ...

local Scale, Palette = ns.Scale, ns.Palette
local U = function(v) return Scale.U(v) end

local Center = {}
ns.Center = Center

Center.WIDTH    = 356    -- "356 wide, same anchor as the rail"
Center.ROW_H    = 22
Center.ROWS     = 12
Center.HEADER_H = 26
Center.FOOTER_H = 20
Center.PAD      = 10

-- Allowed by Mykel in R3 (2026-11-14) as the palette's one recorded
-- exception (SPEC 7). Round 5 made the case: "SPEC 1 forbids fills
-- above 14% -- and twelve rows of 11pt over daylight terrain is unreadable at
-- 14%. So the center is a named exception: rgba(10,10,12,0.86). Defensible
-- because SPEC 1 governs the resting HUD, and the center only exists while
-- you're looking straight at it."
--
-- Deliberately NOT a palette entry. The palette is the resting HUD's thirteen
-- colours and a test asserts a fourteenth is an error; this is one surface
-- that exists only while summoned, and burying it in the palette would make it
-- look like something the HUD may draw at rest.
local SURFACE = { 10 / 255, 10 / 255, 12 / 255, 0.86 }
Center.SURFACE = SURFACE

-- The filter row: SPEC 6's five hues, by what each means. Violet leads
-- because whispers are the reason chat and the history are one view (SPEC 14).
Center.HUES = { "whispers", "loot", "quests", "gains", "attention" }

Center.HUE_OF = {
    whispers  = "violet",
    loot      = "blue",
    quests    = "amber",
    gains     = "green",
    attention = "orange",
}
Center.LABEL_OF = {}
for label, hue in pairs(Center.HUE_OF) do Center.LABEL_OF[hue] = label end

Center.filter = nil     -- nil is unfiltered

local panel

function Center.IsOpen()
    return panel ~= nil and panel:IsShown()
end

-- ---------------------------------------------------------------------------
-- Build
-- ---------------------------------------------------------------------------

local function Hairline(parent, colorName)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(Palette.Get(colorName))
    line:SetHeight(Scale.Hairline())
    return line
end

local function BuildRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(U(Center.ROW_H))
    row:SetPoint("TOPLEFT", parent, "TOPLEFT",
                 U(Center.PAD), -U(Center.HEADER_H + (index - 1) * Center.ROW_H))
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT",
                 -U(Center.PAD), -U(Center.HEADER_H + (index - 1) * Center.ROW_H))

    row.dot = row:CreateTexture(nil, "ARTWORK")
    row.dot:SetSize(U(8), U(8))
    row.dot:SetPoint("LEFT", row, "LEFT", 0, 0)

    row.age = ns.Frames.Text(row, 10, "textDim", "RIGHT")
    row.age:SetPoint("RIGHT", row, "RIGHT", 0, 0)

    row.count = ns.Frames.Text(row, 10, "textDim", "RIGHT")
    row.count:SetPoint("RIGHT", row.age, "LEFT", -U(8), 0)

    row.name = ns.Frames.Text(row, 11, "textPrimary", "LEFT")
    row.name:SetPoint("LEFT", row.dot, "RIGHT", U(8), 0)
    row.name:SetPoint("RIGHT", row.count, "LEFT", -U(8), 0)
    row.name:SetWordWrap(false)

    row:Hide()
    return row
end

local function BuildChip(parent, index, hue)
    local chip = CreateFrame("Button", nil, parent)
    chip:SetSize(U(46), U(16))
    chip:SetPoint("TOPLEFT", parent, "TOPLEFT",
                  U(Center.PAD + (index - 1) * 50), -U(6))

    chip.dot = chip:CreateTexture(nil, "ARTWORK")
    chip.dot:SetSize(U(8), U(8))
    chip.dot:SetPoint("LEFT", chip, "LEFT", 0, 0)
    chip.dot:SetColorTexture(Palette.Get(ns.Toast.HUES[hue]))

    chip.count = ns.Frames.Text(chip, 10, "textDim", "LEFT")
    chip.count:SetPoint("LEFT", chip.dot, "RIGHT", U(5), 0)

    chip.hue = hue
    chip:SetScript("OnClick", function(self)
        -- Spelled out rather than `a and nil or b`: that idiom cannot yield
        -- nil, so the filter could be set and never cleared.
        if Center.filter == self.hue then
            Center.Filter(nil)
        else
            Center.Filter(self.hue)
        end
    end)
    return chip
end

function Center.Build()
    if panel then
        return panel
    end
    -- Reattached from the rail to the toasts (SPEC 6): the history opens
    -- where notifications speak.
    local anchor = ns.Toast and ns.Toast.Anchor()
    if not anchor then
        return nil
    end

    local height = Center.HEADER_H + Center.ROWS * Center.ROW_H + Center.FOOTER_H
    panel = CreateFrame("Frame", "MyUICenter", UIParent)
    panel:SetFrameStrata("DIALOG")
    panel:SetSize(U(Center.WIDTH), U(height))

    panel:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)

    local bg = panel:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(SURFACE[1], SURFACE[2], SURFACE[3], SURFACE[4])

    local top = Hairline(panel, "fillDim")
    top:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0)

    local under = Hairline(panel, "trough")
    under:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -U(Center.HEADER_H) + Scale.Hairline())
    under:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -U(Center.HEADER_H) + Scale.Hairline())

    local bottom = Hairline(panel, "fillDim")
    bottom:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)

    panel.chips = {}
    for i, name in ipairs(Center.HUES) do
        panel.chips[i] = BuildChip(panel, i, Center.HUE_OF[name])
    end

    panel.rows = {}
    for i = 1, Center.ROWS do
        panel.rows[i] = BuildRow(panel, i)
    end

    panel.footer = ns.Frames.Text(panel, 10, "textDim", "LEFT")
    panel.footer:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", U(Center.PAD), U(6))

    panel.hint = ns.Frames.Text(panel, 10, "textDim", "RIGHT")
    panel.hint:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -U(Center.PAD), U(6))

    panel:Hide()

    -- Escape closes it, through Blizzard's own list rather than by grabbing
    -- the keyboard: taking keyboard focus for a read-only panel is how you
    -- swallow a keystroke someone needed.
    local special = _G.UISpecialFrames
    if type(special) == "table" then
        special[#special + 1] = "MyUICenter"
    end

    Center.panel = panel
    return panel
end

-- ---------------------------------------------------------------------------
-- Contents
-- ---------------------------------------------------------------------------

function Center.Refresh()
    if not panel then
        return
    end
    local Log = ns.Log
    local tally = (Log and Log.Tally and Log.Tally()) or {}

    for _, chip in ipairs(panel.chips) do
        local n = tally[chip.hue] or 0
        chip.count:SetText(tostring(n))
        -- The selected filter is the only lit one. Alpha carries the state,
        -- which is the design's whole vocabulary; nothing grows a border.
        local dim = (Center.filter ~= nil and Center.filter ~= chip.hue)
        chip:SetAlpha(dim and 0.35 or 1)
    end

    local rows = (Log and Log.Filter and Log.Filter(Center.filter, Center.ROWS)) or {}
    local now = (Log and Log.Now and Log.Now()) or 0

    for i, row in ipairs(panel.rows) do
        local e = rows[i]
        if not e then
            row:Hide()
        else
            row:Show()
            row.dot:SetColorTexture(Palette.Get(ns.Toast.HUES[e.kind] or "textDim"))
            row.name:SetText(tostring(e.name or ""))
            row.count:SetText((e.count or 1) > 1 and ("x" .. e.count) or "")
            row.age:SetText(ns.Toast.FormatAge(now - (tonumber(e.at) or now)))
        end
    end

    local total = (Log and Log.Count and Log.Count(Center.filter)) or 0
    panel.footer:SetText(("%d kept%s"):format(
        total, Center.filter and (" \194\183 " .. (Center.LABEL_OF[Center.filter] or Center.filter)) or ""))
    panel.hint:SetText(#rows < total and ("showing %d"):format(#rows) or "")
end

function Center.Filter(hue)
    Center.filter = hue
    Center.Refresh()
    return Center.filter
end

-- ---------------------------------------------------------------------------
-- Open and close
-- ---------------------------------------------------------------------------

function Center.Open(hue)
    if not ns.Extras() then
        return false, "the history window is an extra -- /myui extras on, then /reload"
    end
    local p = Center.Build()
    if not p then
        return false
    end
    if hue ~= nil then
        Center.filter = hue
    end
    Center.Refresh()
    p:Show()
    return true
end

function Center.Close()
    if panel then
        panel:Hide()
    end
    return true
end

function Center.Toggle(hue)
    if Center.IsOpen() then
        return Center.Close()
    end
    return Center.Open(hue)
end

function MyUI_Center()
    if not ns.Extras() then
        ns.Print("the history window is an extra -- /myui extras on, then /reload")
        return
    end
    Center.Toggle()
end

_G.BINDING_NAME_MYUI_CENTER = "Open the notification centre"

function Center.OnLogin()
    if not ns.Extras() then return end
    Center.Build()
end

ns.Center = Center
