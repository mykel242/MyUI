-- MyUI :: Dev.lua
-- The debug log: a summoned panel on the same grid as the others, for
-- developing MyUI in the game rather than reading chat.
--
-- 2026-11-23 (Mykel: "a log that uses the same panels as our other ui and we
-- can copy to clipboard, or clear"). What it holds, newest first:
--
--   command  every /myui command and the first line it printed
--   error    MyUI's own failures: a command or module that errored, a
--            compliance violation, an action Blizzard blocked for MyUI
--   reveal   reveal claims and releases (not the pointer's: far too many)
--   layout   Edit Mode layout changes, screen size, spec and role
--
-- Off unless asked for (/myui dev on): it is for testers, not players.
-- An addon cannot write the clipboard, so "copy" puts the log in the copy
-- window, selected, for Ctrl+C. The log is kept in MyUIDB.devlog, so it
-- survives a /reload -- and it holds whatever commands printed, names
-- included, so the debug report never carries it.

local ADDON, ns = ...

local Scale, Palette = ns.Scale, ns.Palette
local U = function(v) return Scale.U(v) end

local Dev = {}
ns.Dev = Dev

Dev.KEEP      = 200
Dev.ROWS      = 10
Dev.ROWS_ALL = ns.Summon.ROWS_MAX
Dev.TICK      = 0.5     -- the under-the-pointer line, while open
Dev.TOAST_GAP = 30      -- at most one error toast this often

Dev.KINDS = { "command", "error", "reveal", "layout" }
Dev.HUE = { command = "blue", error = "orange", reveal = "violet", layout = "green" }

Dev.filter = nil
Dev.unseen = 0

local panel

function Dev.On()
    return ns.db ~= nil and ns.db.dev == true
end

function Dev.Entries()
    if not ns.db then return {} end
    if type(ns.db.devlog) ~= "table" then ns.db.devlog = {} end
    return ns.db.devlog
end

function Dev.IsOpen()
    return panel ~= nil and panel:IsShown()
end

local function OneLine(text)
    text = tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    return (text:match("^[^\n]*") or text)
end

--- Add an entry. detail is the full text a click shows; text is one line.
function Dev.Add(kind, text, detail)
    if not Dev.On() or not Dev.HUE[kind] or ns.readOnlyDB then return nil end
    local list = Dev.Entries()
    local e = { kind = kind, text = OneLine(text), when = date("%H:%M:%S") }
    if detail and detail ~= "" and detail ~= e.text then e.detail = tostring(detail) end
    list[#list + 1] = e
    while #list > Dev.KEEP do table.remove(list, 1) end
    if kind == "error" then
        if not Dev.IsOpen() then Dev.unseen = Dev.unseen + 1 end
        Dev.ToastError()
    end
    -- On the next frame, once: an entry can arrive from inside the reveal
    -- engine or a panel's own layout, and a refresh there would re-enter it.
    if Dev.IsOpen() and not Dev.refreshQueued then
        Dev.refreshQueued = true
        C_Timer.After(0, function() Dev.refreshQueued = false; Dev.Refresh() end)
    end
    return e
end

--- An error while the log is closed says so once in a while, as a toast.
function Dev.ToastError()
    if Dev.IsOpen() or not (ns.Toast and ns.Toast.Add and ns.Reveal) then return false end
    local now = ns.Reveal.Now()
    if Dev.lastToast and now - Dev.lastToast < Dev.TOAST_GAP then return false end
    Dev.lastToast = now
    -- Spoken only (Toast.Speak, not Toast.Add): an error is not a
    -- notification worth keeping in the history.
    pcall(ns.Toast.Speak, { kind = "orange", name = "MyUI error: see the debug log", count = 1, at = now })
    return true
end

--- What the filter shows, newest first.
function Dev.Shown()
    local list, out = Dev.Entries(), {}
    for i = #list, 1, -1 do
        local e = list[i]
        if Dev.filter == nil or e.kind == Dev.filter then out[#out + 1] = e end
    end
    return out
end

--- The shown entries as plain text, oldest first, for the copy window.
function Dev.Text()
    local shown, lines = Dev.Shown(), {}
    for i = #shown, 1, -1 do
        local e = shown[i]
        lines[#lines + 1] = ("%s  %-7s %s"):format(e.when or "", e.kind, e.text)
        if e.detail then
            for line in tostring(e.detail):gmatch("[^\n]+") do lines[#lines + 1] = "      " .. line end
        end
    end
    return table.concat(lines, "\n")
end

function Dev.ClearShown()
    local kept, n = {}, 0
    for _, e in ipairs(Dev.Entries()) do
        if Dev.filter ~= nil and e.kind ~= Dev.filter then kept[#kept + 1] = e else n = n + 1 end
    end
    ns.db.devlog = kept
    Dev.Refresh()
    return n
end

function Dev.Remove(e)
    local kept = {}
    for _, x in ipairs(Dev.Entries()) do if x ~= e then kept[#kept + 1] = x end end
    ns.db.devlog = kept
    Dev.Refresh()
end

function Dev.Copy(text)
    if ns.Copy and ns.Copy.Show then ns.Copy.Show(text or Dev.Text()) return true end
    return false
end

-- ---------------------------------------------------------------------------
-- What is under the pointer: name, the MyUI part that owns it, its alpha
-- and what is holding it up.
-- ---------------------------------------------------------------------------

local function Named(region)
    if type(region) ~= "table" then return nil end
    if type(region.IsForbidden) == "function" and region:IsForbidden() then return "<forbidden>" end
    -- Some of Blizzard's frames override GetName with their own meaning (a
    -- damage meter row returns its name FontString), so only a string counts;
    -- otherwise the debug name, which every region has.
    -- Charon play: a party member's GetName can be a secret string, and
    -- comparing one errors -- it is checked before anything looks at it.
    for _, method in ipairs({ "GetName", "GetDebugName" }) do
        local ok, name = pcall(function() return region[method](region) end)
        if ok and ns.Compat.IsSecret(name) then return "<secret>" end
        if ok and type(name) == "string" and name ~= "" then return name end
    end
    return nil
end

function Dev.Under()
    local foci
    if type(_G.GetMouseFoci) == "function" then
        local ok, r = pcall(_G.GetMouseFoci)
        if ok then foci = type(r) == "table" and r or { r } end
    end
    local top = foci and foci[1]
    if type(top) ~= "table" or top == _G.WorldFrame then return "under the pointer: the world" end
    local byFrame = {}
    ns.Registry.Each(function(entry) byFrame[entry.frame] = entry end)
    local owner, cur, depth = nil, top, 0
    while cur and depth < 10 do
        if byFrame[cur] then owner = byFrame[cur] break end
        -- Charon play: some of Blizzard's frames are forbidden to addon
        -- code, and asking one for its parent errors. Stop there.
        local okF, forbidden = pcall(function() return cur:IsForbidden() end)
        if okF and forbidden then break end
        local ok, parent = pcall(function() return cur:GetParent() end)
        if not ok then break end
        cur = parent
        depth = depth + 1
    end
    local name = Named(top) or (owner and "part of " .. owner.name) or "<unnamed>"
    if not owner then return ("under the pointer: %s -- not MyUI's"):format(name) end
    local why = table.concat(ns.Reveal.ClaimsOn(owner.name), "+")
    return ("under the pointer: %s -- %s at %.2f%s"):format(name, owner.name,
        owner.current or owner.target or 0, why ~= "" and (", " .. why) or ", resting")
end

-- ---------------------------------------------------------------------------
-- The panel
-- ---------------------------------------------------------------------------

local function BuildRow(parent, index)
    local S = ns.Summon
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(U(S.ROW_H))
    local top = S.Top(true) + index * U(S.ROW_H)    -- row 0 is the pointer line
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", U(S.PAD), -top)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -U(S.PAD), -top)
    row.dot = S.Dot(row)
    row.dot:SetPoint("LEFT")
    row.when = ns.Frames.Text(row, 10, "textDim", "RIGHT")
    row.when:SetPoint("RIGHT")
    row.when:SetWidth(U(48))
    row.name = ns.Frames.Text(row, 11, "textPrimary", "LEFT")
    row.name:SetPoint("LEFT", row.dot, "RIGHT", U(S.GAP), 0)
    row.name:SetPoint("RIGHT", row.when, "LEFT", -U(S.GAP), 0)
    row.name:SetWordWrap(false)
    -- Left shows the whole entry, ready to copy; right clears it.
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", function(self, button)
        if not self.entry then return end
        if button == "RightButton" then
            Dev.Remove(self.entry)
        else
            local e = self.entry
            Dev.Copy(("%s  %s  %s%s"):format(e.when or "", e.kind, e.text, e.detail and ("\n\n" .. e.detail) or ""))
        end
    end)
    ns.Frames.HoverEdge(row, 2)
    row:EnableMouse(false)
    row:Hide()
    return row
end

function Dev.Build()
    if panel then return panel end
    local S = ns.Summon
    panel = CreateFrame("Frame", "MyUIDevLog", UIParent)
    S.Depth(panel)
    panel:SetSize(U(S.WIDTH), U(200))
    local d = S.DOCK.left
    panel:SetPoint(d.point, UIParent, d.point, U(d.x), U(d.y))

    local header = S.Chrome(panel, "Debug log")
    local items = { { key = nil, label = "all" } }
    for _, kind in ipairs(Dev.KINDS) do
        items[#items + 1] = { key = kind, hue = ns.Toast.HUES[Dev.HUE[kind]], label = kind }
    end
    S.Filters(panel, items, function(kind)
        if Dev.filter == kind then Dev.filter = nil else Dev.filter = kind end
        Dev.Refresh()
    end)

    panel.under = ns.Frames.Text(panel, 10, "textDim", "LEFT")
    panel.under:SetPoint("TOPLEFT", panel, "TOPLEFT", U(S.PAD), -S.Top(true))
    panel.under:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -U(S.PAD), -S.Top(true))
    panel.under:SetHeight(U(S.ROW_H))
    panel.under:SetWordWrap(false)

    panel.rows = {}
    for i = 1, Dev.ROWS_ALL do panel.rows[i] = BuildRow(panel, i) end

    S.Footer(panel, {
        { "copy", function() Dev.Copy() end },
        { "clear", function() Dev.ClearShown() end },
        -- A click is a hardware event, so the reload that saves it is
        -- allowed. Both edges, like the key: down writes and takes the
        -- screenshot, up reloads (wired below).
        { "report", function() end },
    }, nil, function() Dev.expanded = not Dev.expanded; Dev.Refresh() end)
    local report = panel.__footer.actions[3]
    report:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
    report:SetScript("OnClick", function(_, _, down)
        if _G.MyUI_Report then _G.MyUI_Report(down and "down" or "up") end
    end)

    panel:Hide()
    local special = _G.UISpecialFrames
    if type(special) == "table" then special[#special + 1] = "MyUIDevLog" end

    Dev.panel = panel
    Dev.summon = S.Attach({
        key = "dev", frame = panel, header = header, dock = "left", order = 5,
        refresh = function() Dev.Refresh() end,
        rowH = function() return U(S.ROW_H) end,
        -- The pointer line is a row of chrome.
        chrome = function() return S.Height(U(S.ROW_H), true, true) end,
        want = function() return math.min(#Dev.Shown(), Dev.ROWS_ALL) end,
        prefer = function() return Dev.ROWS end,
        expanded = function() return Dev.expanded end,
        show = function()
            Dev.unseen = 0
            panel:Show()
            Dev.Refresh()
            Dev.Tick()
        end,
        hide = function() panel:Hide() end,
    })
    panel:HookScript("OnHide", function() if Dev.summon.open then Dev.summon.open = false end end)
    return panel
end

--- The pointer line, every TICK while open (a timer: OnUpdate is the
-- reveal engine's alone, R5).
function Dev.Tick()
    if not Dev.IsOpen() then Dev.ticking = false return end
    panel.under:SetText(Dev.Under())
    if Dev.ticking then return end
    Dev.ticking = true
    local function again()
        if not Dev.IsOpen() then Dev.ticking = false return end
        panel.under:SetText(Dev.Under())
        C_Timer.After(Dev.TICK, again)
    end
    C_Timer.After(Dev.TICK, again)
end

function Dev.Refresh()
    if not panel then return end
    local S = ns.Summon
    local counts = { all = 0 }
    for _, e in ipairs(Dev.Entries()) do
        counts[e.kind] = (counts[e.kind] or 0) + 1
        counts.all = counts.all + 1
    end
    local chosen = S.PaintFilters(panel, counts, Dev.filter)
    local title = "Debug log"
    if chosen then title = title .. " \194\183 " .. chosen end
    if Dev.unseen > 0 then title = title .. (" \194\183 %d new error%s"):format(Dev.unseen, Dev.unseen == 1 and "" or "s") end
    panel.__header.title:SetText(title)

    -- Its share of the column (Summon.Share; the pointer line is chrome).
    local cap = math.min(S.Rows(Dev.summon, Dev.expanded and Dev.ROWS_ALL or Dev.ROWS), Dev.ROWS_ALL)
    local all = Dev.Shown()
    local open = Dev.summon and Dev.summon.open or false
    local shown = 0
    for i, row in ipairs(panel.rows) do
        local e = i <= cap and all[i] or nil
        row.entry = e
        row:EnableMouse(open and e ~= nil)
        if e then
            shown = i
            row:Show()
            row.dot:SetHue(ns.Toast.HUES[Dev.HUE[e.kind]] or "textDim")
            row.name:SetText(e.text)
            row.name:SetTextColor(Palette.Get(e.kind == "error" and "danger" or "textPrimary"))
            row.when:SetText(e.when or "")
        else
            row:Hide()
        end
    end
    if shown == 0 then
        local row = panel.rows[1]
        row.dot:SetHue("textDim")
        row.name:SetText(Dev.On() and "nothing yet" or "off -- /myui dev on")
        row.name:SetTextColor(Palette.Get("textDim"))
        row.when:SetText("")
        row:Show()
        shown = 1
    end
    S.PaintMore(panel, math.max(0, #all - cap), Dev.expanded)
    S.Mouse(panel, open)
    panel:SetHeight(S.Height((shown + 1) * U(S.ROW_H), true, true))
    if open then S.Layout() end
end

function Dev.Open()
    if not Dev.On() then return false, "the debug log is off -- /myui dev on" end
    Dev.Build()
    return Dev.summon:Open()
end

function Dev.Close()
    if Dev.summon then Dev.summon:Close("asked") end
    return true
end

function Dev.Toggle()
    if Dev.IsOpen() then return Dev.Close() end
    return Dev.Open()
end

function _G.MyUI_DevLog()
    local ok, err = Dev.Toggle()
    if ok == false and err then ns.Print(err) end
end
_G.BINDING_NAME_MYUI_DEVLOG = "Show the debug log"

-- ---------------------------------------------------------------------------
-- What feeds it
-- ---------------------------------------------------------------------------

--- A command ran: what was typed, what it printed, and whether it failed.
function Dev.Command(name, rest, output, err)
    if name == "dev" then return end   -- its own toggles would fill it
    local typed = "/myui " .. name .. ((rest and rest ~= "") and (" " .. rest) or "")
    local first = OneLine(tostring(output or ""):gsub("^MyUI: ", ""))
    Dev.Add("command", first ~= "" and (typed .. " -- " .. first) or typed, output)
    if err then Dev.Add("error", typed .. " failed: " .. tostring(err)) end
end

--- From the reveal engine's own log: inputs only, never the pointer's.
function Dev.Reveal(entry)
    if entry.channel == "cursor" or (entry.kind ~= "claim" and entry.kind ~= "release") then return end
    Dev.Add("reveal", ("%s %s%s"):format(entry.kind, tostring(entry.channel),
        entry.frame and (" on " .. entry.frame) or ""))
end

local BLOCKED = { ADDON_ACTION_BLOCKED = "blocked", ADDON_ACTION_FORBIDDEN = "forbidden" }

function Dev.OnEvent(event, a, b)
    if BLOCKED[event] then
        if a == ADDON then Dev.Add("error", ("Blizzard %s MyUI: %s"):format(BLOCKED[event], tostring(b))) end
    elseif event == "DISPLAY_SIZE_CHANGED" then
        local size = ns.Clear and ns.Clear.ScreenSize and ns.Clear.ScreenSize()
        Dev.Add("layout", ("screen changed: %s"):format(tostring(size)))
    elseif event == "EDIT_MODE_LAYOUTS_UPDATED" then
        local name = ns.Clear and ns.Clear.ActiveLayoutName and ns.Clear.ActiveLayoutName()
        Dev.Add("layout", ("edit mode layout: %s"):format(tostring(name)))
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" and (a == nil or a == "player") then
        Dev.Add("layout", ("spec changed: role %s"):format(tostring(ns.Clear and ns.Clear.Role())))
    end
end

function Dev.OnLogin()
    local d = CreateFrame("Frame", "MyUIDevDriver", UIParent)
    for _, e in ipairs({ "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN", "DISPLAY_SIZE_CHANGED",
                         "EDIT_MODE_LAYOUTS_UPDATED", "PLAYER_SPECIALIZATION_CHANGED" }) do
        pcall(d.RegisterEvent, d, e)
    end
    d:SetScript("OnEvent", function(_, event, a, b) Dev.OnEvent(event, a, b) end)
    Dev.driver = d
    if Dev.On() then Dev.Build() end
end

ns.Dev = Dev
