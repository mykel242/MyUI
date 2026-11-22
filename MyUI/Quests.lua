-- MyUI :: Quests.lua
-- Round 005 (Mykel: "the quest tracker, map, and chat frames are my biggest
-- pet peeves"). Blizzard's objective tracker is replaced by two things:
--
--   * TOASTS. Progress arrives as it happens -- "Boars slain: 4/10", then
--     "<quest> -- ready to turn in" -- in amber, the quest hue, and goes away
--     on its own. Accepting and turning in a quest toast too.
--   * THE LIST, on demand. A key (MyUI -> Show the quest list), /myui
--     quests, or peek: one compact line per quest with its status and a
--     hairline progress bar; hover one for its objectives. Left-click points
--     the waypoint arrow at it (that quest also shows what is left of it);
--     right-click opens it on the map. Combat puts it away.
--
-- Behind the "quests" switch (Switches.lua): off gives Blizzard's tracker
-- back and stops all of this.
--
-- Nothing here is a unit or cooldown value: quest progress is plain Lua, and
-- RULES.md leaves it alone. Every API goes through Sources.API, so a renamed
-- one goes quiet instead of erroring.

local ADDON, ns = ...

local Scale, Palette = ns.Scale, ns.Palette
local U = function(v) return Scale.U(v) end

local Quests = {}
ns.Quests = Quests

Quests.SETTLE  = 0.25    -- QUEST_LOG_UPDATE comes in bursts; read once after
Quests.WIDTH   = 300
Quests.MAX_ALL = 12       -- with nothing tracked, the first quests in the log
-- Where Blizzard's tracker sat: the right edge, below the minimap's place.
Quests.ANCHOR  = { point = "TOPRIGHT", x = -24, y = -200 }

local function API(path, ...)
    return ns.Sources.API(path, ...)
end

-- ---------------------------------------------------------------------------
-- Reading the quest log
-- ---------------------------------------------------------------------------

--- One quest's state: title, complete, and its objectives (text, done, have, need).
function Quests.Read(questID)
    local q = { id = questID, objectives = {} }
    q.title = API("C_QuestLog.GetTitleForQuestID", questID) or ("Quest " .. tostring(questID))
    q.complete = (API("C_QuestLog.ReadyForTurnIn", questID) or API("C_QuestLog.IsComplete", questID)) == true
    local objs = API("C_QuestLog.GetQuestObjectives", questID)
    if type(objs) == "table" then
        for i, o in ipairs(objs) do
            local bar = o.type == "progressbar"
            q.objectives[i] = {
                text = type(o.text) == "string" and o.text or "",
                done = o.finished == true,
                -- A progress bar's numbers are not its percentage (round
                -- 005 play: "Twilight's Blade disrupted (7%) 0%").
                have = bar and tonumber(API("GetQuestProgressBarPercent", questID))
                       or tonumber(o.numFulfilled) or 0,
                need = bar and 100 or tonumber(o.numRequired) or 0,
                bar  = bar,
            }
        end
    end
    return q
end

--- Every quest in the log (headers and hidden ones skipped), by id.
function Quests.All()
    local out, order = {}, {}
    local n = API("C_QuestLog.GetNumQuestLogEntries") or 0
    for i = 1, n do
        local info = API("C_QuestLog.GetInfo", i)
        if type(info) == "table" and not info.isHeader and not info.isHidden and info.questID then
            out[info.questID] = true
            order[#order + 1] = info.questID
        end
    end
    return out, order
end

--- What the list shows: the tracked quests, or the first few in the log.
function Quests.Shown()
    local ids = {}
    local n = API("C_QuestLog.GetNumQuestWatches") or 0
    for i = 1, n do
        local id = API("C_QuestLog.GetQuestIDForQuestWatchIndex", i)
        if id then ids[#ids + 1] = id end
    end
    if #ids == 0 then
        local _, order = Quests.All()
        for i = 1, math.min(#order, Quests.MAX_ALL) do ids[i] = order[i] end
    end
    return ids
end

--- An objective as one line. Progress bars carry a percentage and often no
-- text of their own.
function Quests.ObjectiveText(o, title)
    if o.bar then
        -- Blizzard's text often carries the percentage already.
        if o.text:find("%", 1, true) then return o.text end
        local text = o.text ~= "" and o.text or title
        return ("%s %d%%"):format(text, o.have)
    end
    if o.text ~= "" then return o.text end
    return ("%d/%d"):format(o.have, o.need)
end

-- ---------------------------------------------------------------------------
-- Toasts: what changed since the last read
-- ---------------------------------------------------------------------------

Quests.snapshot = {}     -- questID -> { complete, have = { [i] = n }, done = { [i] = bool } }
Quests.primed = false

local function Snap(q)
    local s = { complete = q.complete, have = {}, done = {} }
    for i, o in ipairs(q.objectives) do s.have[i], s.done[i] = o.have, o.done end
    return s
end

local function Say(text)
    if ns.Toast and ns.Toast.Add then ns.Toast.Add("amber", text) end
end

--- Read the whole log and toast what moved. The first read only records.
-- Returns the lines it toasted (for tests and /myui quests).
function Quests.Scan()
    local said = {}
    local present = Quests.All()
    local snap = Quests.snapshot
    for id in pairs(present) do
        local q = Quests.Read(id)
        local old = snap[id]
        if old and Quests.primed then
            for i, o in ipairs(q.objectives) do
                local moved = o.have > (old.have[i] or 0) or (o.done and not old.done[i])
                if moved and not q.complete then
                    said[#said + 1] = Quests.ObjectiveText(o, q.title)
                end
            end
            if q.complete and not old.complete then
                said[#said + 1] = ("%s -- ready to turn in"):format(q.title)
            end
        end
        snap[id] = Snap(q)
    end
    for id in pairs(snap) do
        if not present[id] then snap[id] = nil end
    end
    Quests.primed = true
    for _, line in ipairs(said) do Say(line) end
    -- Kept current even when closed: peek shows it without opening it.
    Quests.Refresh()
    return said
end

local pending = false
local function Soon()
    if pending then return end
    pending = true
    C_Timer.After(Quests.SETTLE, function()
        pending = false
        if Quests.Active() then Quests.Scan() end
    end)
end

-- ---------------------------------------------------------------------------
-- The list
-- ---------------------------------------------------------------------------

-- Round 005 play (Mykel: "something more compact but with an easy to see
-- status -- details called up rather than all listed"). One line per quest:
-- its title, a status at the right edge (18/20, 35%, ready) and a hairline
-- progress bar under it, the bars' own grammar. Only the waypoint quest
-- shows what is left of it; any other quest's objectives come up on hover,
-- in a card to the left.

-- Second pass (round 005 play): more air between lines; counts only on the
-- waypoint quest ("the numbers are noise unless we have pinned something");
-- "+N more" opens the whole list and "fewer" closes it again.
-- Third pass: the history's surface and header (Summon.lua) so the two
-- summoned panels match -- left-aligned rows, pin and close -- and the same
-- going-away: by itself once you are done with it, unless pinned.
Quests.ROW      = 24     -- title, a gap, the bar, a gap
Quests.DETAIL   = 15     -- one objective line
Quests.STATUS_W = 44
Quests.BAR_H    = 2
Quests.MAX_QUESTS = 8
Quests.MAX_ALL_ROWS = 30 -- the whole list, opened
Quests.CARD_W   = 300
Quests.CARD_LINES = 10

local frame, rows, details, card = nil, {}, {}, nil

local function Inner()
    return U(Quests.WIDTH - 2 * ns.Summon.PAD)
end

--- How far along a quest is, 0..1, and its count for when it is pinned.
function Quests.Progress(q)
    if q.complete then return 1, "ready" end
    local have, need, n = 0, 0, 0
    for _, o in ipairs(q.objectives) do
        local want = o.bar and 100 or math.max(o.need, 1)
        have = have + math.min(o.done and want or o.have, want)
        need = need + want
        n = n + 1
    end
    if need == 0 then return 0, "" end
    local frac = have / need
    local only = n == 1 and q.objectives[1]
    if only and not only.bar and only.need > 1 then
        return frac, ("%d/%d"):format(only.have, only.need)
    end
    return frac, ("%d%%"):format(math.floor(frac * 100 + 0.5))
end

local function Row()
    local r = CreateFrame("Button", nil, frame)
    r:SetSize(Inner(), U(Quests.ROW))
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r.status = ns.Frames.Text(r, 10, "textDim", "RIGHT")
    r.status:SetPoint("TOPRIGHT", r, "TOPRIGHT", 0, -U(3))
    r.status:SetWidth(U(Quests.STATUS_W))
    r.text = ns.Frames.Text(r, 11, "textPrimary", "LEFT")
    r.text:SetWordWrap(false)
    r.trough = r:CreateTexture(nil, "BACKGROUND", nil, 1)
    r.trough:SetColorTexture(Palette.Get("trough"))
    r.trough:SetHeight(U(Quests.BAR_H))
    r.trough:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, U(4))
    r.trough:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 0, U(4))
    r.fill = r:CreateTexture(nil, "ARTWORK")
    r.fill:SetHeight(U(Quests.BAR_H))
    r.fill:SetPoint("BOTTOMLEFT", r.trough, "BOTTOMLEFT", 0, 0)
    r:SetScript("OnClick", function(self, button)
        if self.more then Quests.SetExpanded(not Quests.expanded)
        elseif self.questID then Quests.Click(self.questID, button) end
    end)
    r:SetScript("OnEnter", function(self) if self.questID then Quests.ShowCard(self) end end)
    r:SetScript("OnLeave", function() Quests.HideCard() end)
    ns.Frames.HoverEdge(r, 3)
    r:EnableMouse(false)
    r:Hide()
    return r
end

local function RowAt(i)
    if not rows[i] then rows[i] = Row() end
    return rows[i]
end

local function Detail()
    local d = ns.Frames.Text(frame, 10, "textDim", "LEFT")
    d:SetWordWrap(false)
    d:Hide()
    return d
end

local function BuildCard()
    card = CreateFrame("Frame", "MyUIQuestCard", UIParent)
    card:SetFrameStrata("DIALOG")
    card:SetWidth(U(Quests.CARD_W))
    ns.Summon.Surface(card)
    card.lines = {}
    local pad = ns.Summon.PAD
    for i = 1, Quests.CARD_LINES do
        local l = ns.Frames.Text(card, i == 1 and 11 or 10, i == 1 and "textPrimary" or "textDim", "LEFT")
        l:SetWidth(U(Quests.CARD_W - 2 * pad))
        -- The title may take two lines rather than lose its end.
        l:SetWordWrap(i == 1)
        if i == 1 and l.SetMaxLines then l:SetMaxLines(2) end
        card.lines[i] = l
    end
    card:Hide()
    Quests.card = card
end

local function SetMouse(on)
    local h = frame and frame.__header
    if h then
        h.pin:EnableMouse(on)
        h.close:EnableMouse(on)
    end
    for _, r in ipairs(rows) do r:EnableMouse(on and (r.questID ~= nil or r.more == true)) end
end

local function Build()
    if frame then
        if not ns.Registry.Get("QuestList") then ns.Registry.Add("QuestList", frame, 0) end
        frame:Show()
        return frame
    end
    frame = CreateFrame("Frame", "MyUIQuestList", UIParent)
    frame:SetFrameStrata("DIALOG")
    frame:SetSize(U(Quests.WIDTH), U(ns.Summon.HEADER_H + Quests.ROW))
    local a = Quests.ANCHOR
    frame:SetPoint(a.point, UIParent, a.point, U(a.x), U(a.y))
    local header = ns.Summon.Chrome(frame, "Quests")
    for i = 1, Quests.MAX_QUESTS + 1 do RowAt(i) end
    for i = 1, 8 do details[i] = Detail() end
    BuildCard()
    Quests.frame, Quests.rows, Quests.details = frame, rows, details
    ns.Registry.Add("QuestList", frame, 0)
    Quests.summon = ns.Summon.Attach({
        key = "quests", frame = frame, header = header,
        show = function()
            Quests.open = true
            Quests.Refresh()
            SetMouse(true)
            ns.Reveal.Claim("quests")
        end,
        hide = function()
            Quests.open = false
            Quests.HideCard()
            SetMouse(false)
            ns.Reveal.Release("quests")
        end,
    })
    SetMouse(false)
    return frame
end

--- What the list shows now, in order: the waypoint quest first (pinned: its
-- count and what is left of it), then the ones ready to turn in, then the
-- rest. Returns the lines, how many more there are than show, and the total.
function Quests.Lines()
    local tracked = API("C_SuperTrack.GetSuperTrackedQuestID")
    local first, ready, rest = {}, {}, {}
    for _, id in ipairs(Quests.Shown()) do
        local q = Quests.Read(id)
        local frac, status = Quests.Progress(q)
        local line = { q = q, questID = id, text = q.title, frac = frac, status = status }
        if id == tracked then
            line.colour, line.pinned, line.expand = "notifAmber", true, not q.complete
            first[#first + 1] = line
        elseif q.complete then
            line.colour = "notifGreen"
            ready[#ready + 1] = line
        else
            line.colour = "textPrimary"
            rest[#rest + 1] = line
        end
    end
    local lines = {}
    for _, group in ipairs({ first, ready, rest }) do
        for _, l in ipairs(group) do lines[#lines + 1] = l end
    end
    local total = #lines
    local cap = Quests.expanded and Quests.MAX_ALL_ROWS or Quests.MAX_QUESTS
    local more = math.max(0, #lines - cap)
    for i = #lines, cap + 1, -1 do lines[i] = nil end
    return lines, more, total
end

--- "+N more" opens the whole list; "fewer" closes it.
function Quests.SetExpanded(on)
    Quests.expanded = on and true or nil
    Quests.HideCard()
    Quests.Refresh()
    return Quests.expanded == true
end

local function Paint(r, l)
    r.text:ClearAllPoints()
    r.text:SetPoint("TOPLEFT", r, "TOPLEFT", 0, -U(3))
    -- Only a pinned quest carries a count; the rest read across.
    if l.pinned or (l.q and l.q.complete) then
        r.text:SetPoint("TOPRIGHT", r.status, "TOPLEFT", -U(8), 0)
        r.status:SetText(l.q.complete and "ready" or l.status)
        r.status:SetTextColor(Palette.Get(l.q.complete and "notifGreen" or "textDim"))
        r.status:Show()
    else
        r.text:SetPoint("TOPRIGHT", r, "TOPRIGHT", 0, -U(3))
        r.status:Hide()
    end
    r.text:SetText(l.text)
    r.text:SetTextColor(Palette.Get(l.colour))
end

function Quests.Refresh()
    if not frame then return end
    local lines, more, total = Quests.Lines()
    local pad = ns.Summon.PAD
    frame.__header.title:SetText(total > 0 and ("Quests  %d"):format(total) or "Quests")
    local y, d = U(ns.Summon.HEADER_H + 4), 0
    local function Place(r)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", frame, "TOPLEFT", U(pad), -y)
        r:Show()
        y = y + U(Quests.ROW)
    end
    local used = 0
    for i, l in ipairs(lines) do
        local r = RowAt(i)
        used = i
        Paint(r, l)
        r.fill:SetColorTexture(Palette.Get(l.q.complete and "notifGreen" or (l.pinned and "notifAmber" or "fill")))
        r.fill:SetWidth(math.max(Inner() * l.frac, 0.01))
        r.fill:Show()
        r.trough:Show()
        r.questID, r.line, r.more = l.questID, l, nil
        Place(r)
        if l.expand then
            for _, o in ipairs(l.q.objectives) do
                if not o.done and d < #details then
                    d = d + 1
                    local t = details[d]
                    t:ClearAllPoints()
                    t:SetPoint("TOPLEFT", frame, "TOPLEFT", U(pad + 10), -y)
                    t:SetWidth(Inner() - U(10))
                    t:SetText(Quests.ObjectiveText(o, l.q.title))
                    t:Show()
                    y = y + U(Quests.DETAIL)
                end
            end
            y = y + U(6)
        end
    end
    -- The toggle: "+N more" while closed, "fewer" while the whole list is out.
    if more > 0 or Quests.expanded then
        used = used + 1
        local r = RowAt(used)
        Paint(r, { text = more > 0 and ("+%d more"):format(more) or "fewer", colour = "textDim" })
        r.trough:Hide()
        r.fill:Hide()
        r.questID, r.line, r.more = nil, nil, true
        Place(r)
    end
    if #lines == 0 then
        used = 1
        local r = RowAt(1)
        Paint(r, { text = "no quests", colour = "textDim" })
        r.trough:Hide()
        r.fill:Hide()
        r.questID, r.line, r.more = nil, nil, nil
        Place(r)
    end
    for i = used + 1, #rows do
        rows[i].questID, rows[i].line, rows[i].more = nil, nil, nil
        rows[i]:Hide()
    end
    for i = d + 1, #details do details[i]:Hide() end
    SetMouse(Quests.open == true)
    frame:SetHeight(y + U(pad - 4))
end

--- The details, called up: the whole title, every objective (done ones in
-- green), in a card to the list's left.
function Quests.ShowCard(row)
    local l = row.line
    if not (card and l) then return end
    local pad = U(ns.Summon.PAD)
    local n = 1
    local title = card.lines[1]
    title:SetText(l.q.title)
    local function Line(text, colour)
        if n >= Quests.CARD_LINES then return end
        n = n + 1
        local t = card.lines[n]
        t:SetText(text)
        t:SetTextColor(Palette.Get(colour))
        t:Show()
    end
    for _, o in ipairs(l.q.objectives) do
        Line(Quests.ObjectiveText(o, l.q.title), o.done and "notifGreen" or "textDim")
    end
    if l.q.complete then Line("ready to turn in", "notifGreen") end
    for i = n + 1, Quests.CARD_LINES do card.lines[i]:Hide() end
    local th = (title.GetStringHeight and title:GetStringHeight()) or U(Quests.DETAIL)
    if type(th) ~= "number" or th <= 0 then th = U(Quests.DETAIL) end
    title:ClearAllPoints()
    title:SetPoint("TOPLEFT", card, "TOPLEFT", pad, -pad)
    title:Show()
    local y = pad + th + U(4)
    for i = 2, n do
        local t = card.lines[i]
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", card, "TOPLEFT", pad, -y)
        y = y + U(Quests.DETAIL)
    end
    card:SetHeight(y + pad - U(2))
    card:ClearAllPoints()
    card:SetPoint("TOPRIGHT", frame, "TOPLEFT", -U(8), 0)
    card:SetPoint("TOP", row, "TOP", 0, U(4))
    card:Show()
    return n
end

function Quests.HideCard()
    if card then card:Hide() end
end

--- Left: point the waypoint arrow at it (again: clear it). Right: open it on
-- the map, out of combat.
function Quests.Click(questID, button)
    if button == "RightButton" then
        if InCombatLockdown() then return "combat" end
        if type(_G.QuestMapFrame_OpenToQuestDetails) == "function" then
            pcall(_G.QuestMapFrame_OpenToQuestDetails, questID)
            if not (Quests.summon and Quests.summon:IsPinned()) then Quests.Close() end
            return "map"
        end
        return nil
    end
    local now = API("C_SuperTrack.GetSuperTrackedQuestID")
    API("C_SuperTrack.SetSuperTrackedQuestID", now == questID and 0 or questID)
    Quests.Refresh()
    return now == questID and "untracked" or "tracked"
end

Quests.Build = Build

function Quests.Open()
    if not Quests.Active() then return false end
    Build()
    return Quests.summon:Open()
end

function Quests.Close()
    if not Quests.summon then return false end
    return Quests.summon:Close("asked")
end

function Quests.Toggle()
    if Quests.open then Quests.Close() return false end
    return Quests.Open()
end

-- ---------------------------------------------------------------------------
-- On and off
-- ---------------------------------------------------------------------------

function Quests.Active()
    return Quests.enabled == true
end

Quests.EVENTS = {
    QUEST_LOG_UPDATE = function() Soon() end,
    QUEST_WATCH_LIST_CHANGED = function() if Quests.open then Quests.Refresh() end end,
    SUPER_TRACKING_CHANGED = function() if Quests.open then Quests.Refresh() end end,
    QUEST_ACCEPTED = function(questID)
        local title = API("C_QuestLog.GetTitleForQuestID", questID)
        Say(("Accepted: %s"):format(title or "a quest"))
        Soon()
    end,
    QUEST_TURNED_IN = function(questID)
        local title = API("C_QuestLog.GetTitleForQuestID", questID)
        Say(("Turned in: %s"):format(title or "a quest"))
        Quests.snapshot[questID] = nil
    end,
    PLAYER_ENTERING_WORLD = function() Soon() end,
}

function Quests.Enable()
    if Quests.enabled then return end
    Quests.enabled = true
    Build()
    if not Quests.driver then
        Quests.driver = CreateFrame("Frame", "MyUIQuestsDriver", UIParent)
        Quests.driver:SetScript("OnEvent", function(_, event, ...)
            local fn = Quests.EVENTS[event]
            if fn and Quests.enabled then fn(...) end
        end)
    end
    for event in pairs(Quests.EVENTS) do Quests.driver:RegisterEvent(event) end
    -- Record where everything stands, quietly, so the first toast is real.
    Quests.primed = false
    Quests.snapshot = {}
    Quests.Scan()
end

function Quests.Disable()
    Quests.Close()
    Quests.enabled = false
    if Quests.driver then Quests.driver:UnregisterAllEvents() end
    -- Off means off: peek no longer shows a list nobody keeps current.
    if frame then
        ns.Registry.Remove("QuestList")
        frame:Hide()
    end
end

function Quests.OnLogin()
    if ns.Switches and not ns.Switches.On("quests") then return end
    Quests.Enable()
end

function _G.MyUI_Quests()
    if not Quests.Active() then
        ns.Print("the quest list is off -- /myui override quests on")
        return
    end
    Quests.Toggle()
end
_G.BINDING_NAME_MYUI_QUESTS = "Show the quest list"
