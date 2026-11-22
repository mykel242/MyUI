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
Quests.WIDTH   = 220
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

Quests.ROW      = 17     -- title + bar
Quests.DETAIL   = 13     -- one objective line
Quests.STATUS_W = 40
Quests.BAR_H    = 2
Quests.MAX_QUESTS = 8
Quests.CARD_W   = 240
Quests.CARD_LINES = 10

local frame, rows, details, card = nil, {}, {}, nil

--- How far along a quest is, 0..1, and its status text.
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
    r:SetSize(U(Quests.WIDTH), U(Quests.ROW))
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r.status = ns.Frames.Text(r, 10, "textDim", "RIGHT")
    r.status:SetPoint("TOPRIGHT", r, "TOPRIGHT", 0, 0)
    r.status:SetWidth(U(Quests.STATUS_W))
    r.text = ns.Frames.Text(r, 11, "textPrimary", "RIGHT")
    r.text:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0)
    r.text:SetPoint("TOPRIGHT", r.status, "TOPLEFT", -U(6), 0)
    r.text:SetWordWrap(false)
    r.trough = r:CreateTexture(nil, "BACKGROUND")
    r.trough:SetColorTexture(Palette.Get("trough"))
    r.trough:SetHeight(U(Quests.BAR_H))
    r.trough:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, U(2))
    r.trough:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 0, U(2))
    r.fill = r:CreateTexture(nil, "ARTWORK")
    r.fill:SetHeight(U(Quests.BAR_H))
    r.fill:SetPoint("BOTTOMRIGHT", r.trough, "BOTTOMRIGHT", 0, 0)
    r:SetScript("OnClick", function(self, button)
        if self.questID then Quests.Click(self.questID, button) end
    end)
    r:SetScript("OnEnter", function(self) if self.questID then Quests.ShowCard(self) end end)
    r:SetScript("OnLeave", function() Quests.HideCard() end)
    ns.Frames.HoverEdge(r, 3):Hide()
    r:EnableMouse(false)
    r:Hide()
    return r
end

local function Detail()
    local d = ns.Frames.Text(frame, 10, "textDim", "RIGHT")
    d:SetWordWrap(false)
    d:Hide()
    return d
end

local function BuildCard()
    card = CreateFrame("Frame", "MyUIQuestCard", UIParent)
    card:SetFrameStrata(ns.Frames.STRATA)
    card:SetWidth(U(Quests.CARD_W))
    card.bg = card:CreateTexture(nil, "BACKGROUND")
    card.bg:SetAllPoints()
    card.bg:SetColorTexture(Palette.Get("tickDark"))
    card.lines = {}
    for i = 1, Quests.CARD_LINES do
        local l = ns.Frames.Text(card, i == 1 and 11 or 10, i == 1 and "textPrimary" or "textDim", "LEFT")
        l:SetPoint("TOPLEFT", card, "TOPLEFT", U(8), -U(6) - (i - 1) * U(Quests.DETAIL))
        l:SetPoint("RIGHT", card, "RIGHT", -U(8), 0)
        l:SetWordWrap(false)
        card.lines[i] = l
    end
    card:Hide()
    Quests.card = card
end

local function Build()
    if frame then
        if not ns.Registry.Get("QuestList") then ns.Registry.Add("QuestList", frame, 0) end
        frame:Show()
        return frame
    end
    frame = CreateFrame("Frame", "MyUIQuestList", UIParent)
    frame:SetFrameStrata(ns.Frames.STRATA)
    frame:SetSize(U(Quests.WIDTH), U(Quests.ROW))
    local a = Quests.ANCHOR
    frame:SetPoint(a.point, UIParent, a.point, U(a.x), U(a.y))
    for i = 1, Quests.MAX_QUESTS + 1 do rows[i] = Row() end
    for i = 1, 8 do details[i] = Detail() end
    BuildCard()
    Quests.frame, Quests.rows, Quests.details = frame, rows, details
    ns.Registry.Add("QuestList", frame, 0)
    return frame
end

--- What the list shows now, in order: the waypoint quest first, then the
-- ones ready to turn in, then the rest. Each: { q, frac, status, colour,
-- expand (the waypoint quest's remaining objectives) }, plus how many more
-- there were than fit.
function Quests.Lines()
    local tracked = API("C_SuperTrack.GetSuperTrackedQuestID")
    local first, ready, rest = {}, {}, {}
    for _, id in ipairs(Quests.Shown()) do
        local q = Quests.Read(id)
        local frac, status = Quests.Progress(q)
        local line = { q = q, questID = id, text = q.title, frac = frac, status = status }
        if id == tracked then
            line.colour, line.expand = "notifAmber", not q.complete
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
    local more = math.max(0, #lines - Quests.MAX_QUESTS)
    for i = #lines, Quests.MAX_QUESTS + 1, -1 do lines[i] = nil end
    return lines, more
end

function Quests.Refresh()
    if not frame then return end
    local lines, more = Quests.Lines()
    local y, d = 0, 0
    for i, r in ipairs(rows) do
        local l = lines[i]
        r:ClearAllPoints()
        if l then
            r:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -y)
            r.text:SetText(l.text)
            r.text:SetTextColor(Palette.Get(l.colour))
            r.status:SetText(l.status)
            r.status:SetTextColor(Palette.Get(l.q.complete and "notifGreen" or "textDim"))
            r.fill:SetColorTexture(Palette.Get(l.q.complete and "notifGreen" or "fill"))
            -- Fills from the screen edge inward, like the list reads.
            r.fill:SetWidth(math.max(U(Quests.WIDTH) * l.frac, 0.01))
            r.questID, r.line = l.questID, l
            r:EnableMouse(Quests.open == true)
            r:Show()
            y = y + U(Quests.ROW)
            if l.expand then
                for _, o in ipairs(l.q.objectives) do
                    if not o.done and d < #details then
                        d = d + 1
                        local t = details[d]
                        t:ClearAllPoints()
                        t:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -U(Quests.STATUS_W + 6), -y)
                        t:SetWidth(U(Quests.WIDTH - Quests.STATUS_W - 6))
                        t:SetText(Quests.ObjectiveText(o, l.q.title))
                        t:Show()
                        y = y + U(Quests.DETAIL)
                    end
                end
                y = y + U(3)
            end
        elseif i == #lines + 1 and more > 0 then
            r:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -y)
            r.text:SetText(("+%d more"):format(more))
            r.text:SetTextColor(Palette.Get("textDim"))
            r.status:SetText("")
            r.fill:SetWidth(0.01)
            r.trough:Hide()
            r.questID, r.line = nil, nil
            r:EnableMouse(false)
            r:Show()
            y = y + U(Quests.ROW)
        else
            r.questID, r.line = nil, nil
            r:EnableMouse(false)
            r:Hide()
        end
        if l then r.trough:Show() end
    end
    for i = d + 1, #details do details[i]:Hide() end
    if #lines == 0 then
        rows[1]:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        rows[1].text:SetText("no quests")
        rows[1].text:SetTextColor(Palette.Get("textDim"))
        rows[1].status:SetText("")
        rows[1].trough:Hide()
        rows[1].fill:SetWidth(0.01)
        rows[1]:Show()
        y = U(Quests.ROW)
    end
    frame:SetHeight(math.max(y, U(Quests.ROW)))
end

--- The details, called up: every objective of the quest under the pointer,
-- done ones in green, in a card to the list's left.
function Quests.ShowCard(row)
    local l = row.line
    if not (card and l) then return end
    local n = 1
    card.lines[1]:SetText(l.q.title)
    for _, o in ipairs(l.q.objectives) do
        if n >= Quests.CARD_LINES then break end
        n = n + 1
        local t = card.lines[n]
        t:SetText(Quests.ObjectiveText(o, l.q.title))
        t:SetTextColor(Palette.Get(o.done and "notifGreen" or "textDim"))
        t:Show()
    end
    if l.q.complete and n < Quests.CARD_LINES then
        n = n + 1
        card.lines[n]:SetText("ready to turn in")
        card.lines[n]:SetTextColor(Palette.Get("notifGreen"))
        card.lines[n]:Show()
    end
    for i = n + 1, Quests.CARD_LINES do card.lines[i]:Hide() end
    card.lines[1]:Show()
    card:SetHeight(U(12) + n * U(Quests.DETAIL))
    card:ClearAllPoints()
    card:SetPoint("TOPRIGHT", row, "TOPLEFT", -U(12), U(4))
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
            Quests.Close()
            return "map"
        end
        return nil
    end
    local now = API("C_SuperTrack.GetSuperTrackedQuestID")
    API("C_SuperTrack.SetSuperTrackedQuestID", now == questID and 0 or questID)
    Quests.Refresh()
    return now == questID and "untracked" or "tracked"
end

function Quests.Open()
    if not Quests.Active() then return false end
    Build()
    Quests.open = true
    Quests.Refresh()
    ns.Reveal.Claim("quests")
    return true
end

function Quests.Close()
    if not Quests.open then return false end
    Quests.open = false
    Quests.HideCard()
    for _, r in ipairs(rows) do r:EnableMouse(false) end
    ns.Reveal.Release("quests")
    return true
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
    -- The list is for between pulls.
    PLAYER_REGEN_DISABLED = function() Quests.Close() end,
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
