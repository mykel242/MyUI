-- MyUI :: Quests.lua
-- Round 005 (Mykel: "the quest tracker, map, and chat frames are my biggest
-- pet peeves"). Blizzard's objective tracker is replaced by two things:
--
--   * TOASTS. Progress arrives as it happens -- "Boars slain: 4/10", then
--     "<quest> -- ready to turn in" -- in amber, the quest hue, and goes away
--     on its own. Accepting and turning in a quest toast too.
--   * THE LIST, on demand. A key (MyUI -> Quest list), /myui quests, or peek
--     shows your tracked quests and what is left of each. Left-click a quest
--     to point the waypoint arrow at it; right-click opens it on the map.
--     Combat puts it away.
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
Quests.MAX_ROWS = 36
Quests.WIDTH   = 260
Quests.ROW     = 15
Quests.INDENT  = 10
Quests.MAX_ALL = 8       -- with nothing tracked, the first quests in the log
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
            q.objectives[i] = {
                text = type(o.text) == "string" and o.text or "",
                done = o.finished == true,
                have = tonumber(o.numFulfilled) or 0,
                need = tonumber(o.numRequired) or 0,
                bar  = o.type == "progressbar",
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

local frame, rows = nil, {}

local function Row()
    local r = CreateFrame("Button", nil, frame)
    r:SetHeight(U(Quests.ROW))
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r.text = ns.Frames.Text(r, 11, "textPrimary", "RIGHT")
    r.text:SetWordWrap(false)
    r:SetScript("OnClick", function(self, button)
        if self.questID then Quests.Click(self.questID, button) end
    end)
    r:EnableMouse(false)
    r:Hide()
    return r
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
    for i = 1, Quests.MAX_ROWS do
        rows[i] = Row()
        rows[i]:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -(i - 1) * U(Quests.ROW))
        rows[i]:SetWidth(U(Quests.WIDTH))
    end
    Quests.frame, Quests.rows = frame, rows
    ns.Registry.Add("QuestList", frame, 0)
    return frame
end

--- The lines the list shows now: { text, colour, questID, indent }.
function Quests.Lines()
    local lines = {}
    local tracked = API("C_SuperTrack.GetSuperTrackedQuestID")
    for _, id in ipairs(Quests.Shown()) do
        local q = Quests.Read(id)
        local colour = q.complete and "notifGreen" or (id == tracked and "notifAmber" or "textPrimary")
        lines[#lines + 1] = { text = q.title, colour = colour, questID = id }
        if q.complete then
            lines[#lines + 1] = { text = "ready to turn in", colour = "textDim", indent = true }
        else
            for _, o in ipairs(q.objectives) do
                if not o.done then
                    lines[#lines + 1] = { text = Quests.ObjectiveText(o, q.title), colour = "textDim", indent = true }
                end
            end
        end
    end
    if #lines == 0 then lines[1] = { text = "no quests", colour = "textDim" } end
    return lines
end

function Quests.Refresh()
    if not frame then return end
    local lines = Quests.Lines()
    local n = math.min(#lines, Quests.MAX_ROWS)
    for i, r in ipairs(rows) do
        local l = lines[i]
        if l and i <= n then
            r.text:SetText(l.text)
            r.text:SetTextColor(Palette.Get(l.colour))
            -- Right-aligned against the screen edge; what is left of a
            -- quest sits a step in from its title.
            r.text:ClearAllPoints()
            r.text:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0)
            r.text:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", l.indent and -U(Quests.INDENT) or 0, 0)
            r.questID = l.questID
            r:EnableMouse(Quests.open == true and l.questID ~= nil)
            r:Show()
        else
            r.questID = nil
            r:EnableMouse(false)
            r:Hide()
        end
    end
    frame:SetHeight(U(Quests.ROW) * math.max(n, 1))
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
