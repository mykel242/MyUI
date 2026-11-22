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

-- Round 005: on the summoned panels' grid (Summon.lua). Eight rows until
-- "+N more" opens the rest.
Center.ROW_H    = ns.Summon.ROW_H
Center.ROWS     = 8
Center.ROWS_ALL = 24
Center.ROLLUP   = true   -- runs of the same thing read as one row

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
-- (Round 005: the surface lives in Summon.lua now, shared with the quest
-- list, so the two summoned panels cannot drift apart.)
Center.SURFACE = ns.Summon.SURFACE

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

local function BuildRow(parent, index)
    local S = ns.Summon
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(U(Center.ROW_H))
    local top = S.Top(true) + (index - 1) * U(Center.ROW_H)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", U(S.PAD), -top)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -U(S.PAD), -top)
    row.dot = S.Dot(row)
    row.dot:SetPoint("LEFT")
    row.age = ns.Frames.Text(row, 10, "textDim", "RIGHT")
    row.age:SetPoint("RIGHT")
    row.age:SetWidth(U(28))
    row.count = ns.Frames.Text(row, 10, "textDim", "RIGHT")
    row.count:SetPoint("RIGHT", row.age, "LEFT", -U(S.GAP), 0)
    row.name = ns.Frames.Text(row, 11, "textPrimary", "LEFT")
    row.name:SetPoint("LEFT", row.dot, "RIGHT", U(S.GAP), 0)
    row.name:SetPoint("RIGHT", row.count, "LEFT", -U(S.GAP), 0)
    row.name:SetWordWrap(false)
    -- Round 005 play: "clicking on notifications does not seem to do much",
    -- and "a way to clear a single entry". Left acts on it; right clears it.
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", function(self, button)
        if self.entry then Center.ClickRow(self.entry, button) end
    end)
    ns.Frames.HoverEdge(row, 2)
    row:EnableMouse(false)
    row:Hide()
    return row
end

function Center.Build()
    if panel then
        return panel
    end
    local S = ns.Summon
    panel = CreateFrame("Frame", "MyUICenter", UIParent)
    ns.Summon.Depth(panel)
    panel:SetSize(U(S.WIDTH), U(200))
    -- Docked down the left with the chat panel (Summon.Layout).
    local d = S.DOCK.left
    panel:SetPoint(d.point, UIParent, d.point, U(d.x), U(d.y))

    local header = S.Chrome(panel, "Notifications")
    local items = { { key = nil, label = "all" } }
    for _, name in ipairs(Center.HUES) do
        local hue = Center.HUE_OF[name]
        items[#items + 1] = { key = hue, hue = ns.Toast.HUES[hue], label = name }
    end
    panel.chips = S.Filters(panel, items, function(hue)
        -- Picking the lit one again clears it (spelled out: `a and nil or
        -- b` cannot yield nil).
        if Center.filter == hue then Center.Filter(nil) else Center.Filter(hue) end
    end)
    for _, chip in ipairs(panel.chips) do chip.hue, chip.count = chip.key, chip.text end

    panel.rows = {}
    for i = 1, Center.ROWS_ALL do
        panel.rows[i] = BuildRow(panel, i)
    end

    -- Round 005 play: "the notification items need a way to be rolled up
    -- and cleared". Clear empties what the filter shows (all of it, or one
    -- hue); runs of the same thing are rolled into one row.
    S.Footer(panel, "clear", function() Center.ClearShown() end,
             function() Center.expanded = not Center.expanded; Center.Refresh() end)

    panel:Hide()

    -- Escape closes it, through Blizzard's own list rather than by grabbing
    -- the keyboard: taking keyboard focus for a read-only panel is how you
    -- swallow a keystroke someone needed.
    local special = _G.UISpecialFrames
    if type(special) == "table" then
        special[#special + 1] = "MyUICenter"
    end

    Center.panel = panel
    -- Round 005 play ("it seems stuck open"): it goes away by itself once
    -- you are done with it, unless pinned (Summon.lua).
    Center.summon = S.Attach({
        key = "history", frame = panel, header = header, dock = "left", order = 3,
        refresh = function() Center.Refresh() end,
        show = function() panel:Show(); Center.Refresh() end,
        hide = function() panel:Hide() end,
    })
    -- Escape hides the frame directly; keep the behaviour in step.
    panel:HookScript("OnHide", function()
        if Center.summon.open then Center.summon.open = false end
    end)
    return panel
end

-- ---------------------------------------------------------------------------
-- Contents
-- ---------------------------------------------------------------------------

--- What a row says about a run: "Online: Aria, Bren +3" for a run of the
-- same kind of notice, "Voidsteel Greaves" x3 for the same thing again.
local function RollKey(e)
    local name = tostring(e.name or "")
    local prefix, rest = name:match("^(.-):%s*(.+)$")
    if prefix then return e.kind .. "|" .. prefix, prefix, rest end
    return e.kind .. "|=" .. name, nil, name
end

--- The log, newest first, with runs rolled up (Center.ROLLUP).
function Center.Rows(limit)
    local Log = ns.Log
    local entries = (Log and Log.Filter and Log.Filter(Center.filter)) or {}
    local out = {}
    for _, e in ipairs(entries) do
        local key, prefix, rest = RollKey(e)
        local last = out[#out]
        if Center.ROLLUP and last and last.key == key then
            last.count = last.count + (e.count or 1)
            last.n = last.n + 1
            last.entries[#last.entries + 1] = e
            if prefix then last.parts[#last.parts + 1] = rest end
        else
            if limit and #out >= limit then break end
            out[#out + 1] = { key = key, kind = e.kind, at = e.at, name = e.name, sub = e.sub,
                              prefix = prefix, parts = { rest }, count = e.count or 1, n = 1,
                              entries = { e } }
        end
    end
    for _, r in ipairs(out) do
        if r.prefix and r.n > 1 then
            local shown = { r.parts[1], r.parts[2] }
            r.name = ("%s: %s"):format(r.prefix, table.concat(shown, ", "))
            if r.n > 2 then r.name = r.name .. (" +%d"):format(r.n - 2) end
            r.count = 1
        end
    end
    return out
end

function Center.Refresh()
    if not panel then
        return
    end
    local S = ns.Summon
    local Log = ns.Log
    local tally = (Log and Log.Tally and Log.Tally()) or {}
    local counts = { all = 0 }
    for hue, n in pairs(tally) do counts[hue] = n; counts.all = counts.all + n end
    local chosen = S.PaintFilters(panel, counts, Center.filter)
    panel.__header.title:SetText(chosen and ("Notifications \194\183 " .. chosen) or "Notifications")

    local cap = Center.expanded and Center.ROWS_ALL or Center.ROWS
    -- Never past the bottom of the screen: as many as fit, then "+N more".
    cap = math.min(cap, ns.Summon.FitRows(Center.summon, U(Center.ROW_H), true, true))
    local all = Center.Rows(Center.ROWS_ALL + 1)
    local now = (Log and Log.Now and Log.Now()) or 0
    local shown = 0
    local open = Center.summon and Center.summon.open or false
    for i, row in ipairs(panel.rows) do
        local e = i <= cap and all[i]
        row.entry = e or nil
        row:EnableMouse(open and e ~= nil and e ~= false)
        if not e then
            row:Hide()
        else
            shown = i
            row:Show()
            row.dot:SetHue(ns.Toast.HUES[e.kind] or "textDim")
            row.name:SetText(tostring(e.name or ""))
            row.count:SetText((e.count or 1) > 1 and ("x" .. e.count) or "")
            row.age:SetText(ns.Toast.FormatAge(now - (tonumber(e.at) or now)))
        end
    end
    if shown == 0 then
        local row = panel.rows[1]
        row.dot:SetHue("textDim")
        row.name:SetText("nothing yet")
        row.count:SetText("")
        row.age:SetText("")
        row:Show()
        shown = 1
    end
    S.PaintMore(panel, math.max(0, #all - cap), Center.expanded)
    S.Mouse(panel, Center.IsOpen() or (Center.summon and Center.summon.open) or false)

    -- Only as tall as what it holds.
    panel:SetHeight(S.Height(shown * U(Center.ROW_H), true, true))
    if Center.summon and Center.summon.open then S.Layout() end
end

--- Clear one row: the notification, or every one a rolled-up row holds.
function Center.Remove(row)
    local Log = ns.Log
    if not (Log and Log.db and row and row.entries) then return 0 end
    local gone = {}
    for _, e in ipairs(row.entries) do gone[e] = true end
    local kept, n = {}, 0
    for _, e in ipairs(Log.db.entries) do
        if gone[e] then n = n + 1 else kept[#kept + 1] = e end
    end
    Log.db.entries = kept
    Center.Refresh()
    return n
end

--- What a notification leads to: a whisper opens the reply, a login who's
-- online, a chat line the chat panel, a quest the quest list, loot or full
-- bags your bags. Anything else has nowhere to go and says so.
function Center.Act(row)
    local name = tostring(row.name or "")
    if row.kind == "violet" then
        if row.sub and ns.Chat then
            if ns.Talk and ns.Talk.Active() then ns.Talk.Open("whisper") end
            ns.Chat.Open(("/w %s "):format(row.sub))
            return "reply"
        elseif name:find("^Online:") and ns.Social and ns.Social.panel then
            ns.Social.Toggle()
            return "online"
        elseif ns.Talk and ns.Talk.Active() then
            ns.Talk.Open()
            return "chat"
        end
    elseif row.kind == "amber" and ns.Quests and ns.Quests.Active() then
        ns.Quests.Open()
        return "quests"
    elseif (row.kind == "blue" or (row.kind == "orange" and name:lower():find("bag"))) then
        if not InCombatLockdown() and type(_G.OpenAllBags) == "function" then
            pcall(_G.OpenAllBags)
            return "bags"
        end
    end
    return nil
end

function Center.ClickRow(row, button)
    if button == "RightButton" then
        Center.Remove(row)
        return "cleared"
    end
    return Center.Act(row)
end

--- Empty what the filter shows: one hue, or everything.
function Center.ClearShown()
    local Log = ns.Log
    if not (Log and Log.db) then return 0 end
    local kept, n = {}, 0
    for _, e in ipairs(Log.db.entries) do
        if Center.filter ~= nil and e.kind ~= Center.filter then
            kept[#kept + 1] = e
        else
            n = n + 1
        end
    end
    Log.db.entries = kept
    Center.Refresh()
    return n
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
    return Center.summon:Open()
end

function Center.Close()
    if Center.summon then
        Center.summon:Close("asked")
    elseif panel then
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
