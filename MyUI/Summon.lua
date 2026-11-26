-- MyUI :: Summon.lua
-- Round 005 play (Mykel): the history "seems stuck open", it "needs a way to
-- be pinned open and a way to have it disappear", and the quest list and the
-- history "should match better". This is what both summoned panels share:
--
--   * ONE SURFACE. The history's dark surface (SPEC 7's recorded exception:
--     it exists only while you are looking at it), a hairline top and bottom,
--     a header row with a title on the left and PIN and CLOSE on the right.
--   * ONE BEHAVIOUR. A summoned panel goes away by itself: LINGER seconds
--     after the pointer leaves it, or UNSEEN seconds after it opened if the
--     pointer never came to it, and when combat starts. Pinned, it stays --
--     through combat and across /reload -- until you unpin or close it.
--     Close (or its key, or Escape for the history) always closes.
--
-- Timing runs on C_Timer: RULES reserves OnUpdate for the reveal engine.

local ADDON, ns = ...

local Scale, Palette = ns.Scale, ns.Palette
local U = function(v) return Scale.U(v) end

local Summon = {}
ns.Summon = Summon

Summon.LINGER   = 1.5
Summon.UNSEEN   = 10
Summon.TICK     = 0.25

-- THE GRID (round 005 play: "tighten up the grid and design language so
-- things line up better -- margins are inconsistent and the panels are
-- arbitrary sizes"). Every summoned panel is built from these and nothing
-- else, in SPEC units:
--
--   width     WIDTH, every panel
--   header    HEADER_H: title left, pin and close right
--   filters   FILTER_H: hue squares with counts, equal columns
--   rows      ROW_H a line (a panel may use whole multiples of it)
--   footer    FOOTER_H: the panel's action left, "+N more" / "fewer" right
--   margins   PAD inside, everywhere; DOT squares; GAP between a square
--             and its text
Summon.WIDTH    = 320
Summon.PAD      = 10
Summon.HEADER_H = 26
Summon.FILTER_H = 22
Summon.ROW_H    = 22
Summon.FOOTER_H = 22
Summon.DOT      = 8
Summon.GAP      = 6
-- Round 005 play: "the panels should start near the top of the screen
-- rather than partway down" -- under Blizzard's status bars at the top edge.
Summon.DOCK_TOP = -28
-- What a column leaves free at the bottom of the screen: the HUD lives
-- there (bar, wings, your strip). A panel never grows into it -- it shows
-- fewer rows and says "+N more" instead.
Summon.BOTTOM_RESERVE = 230

-- SPEC 7's one recorded exception, moved here from Center.lua so the two
-- panels cannot drift apart: rgba(10,10,12,0.86).
Summon.SURFACE = { 10 / 255, 10 / 255, 12 / 255, 0.86 }

local function DB()
    if not ns.db then return {} end
    ns.db.pinned = ns.db.pinned or {}
    return ns.db.pinned
end

local function Hairline(parent, colorName)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(Palette.Get(colorName))
    line:SetHeight(Scale.Hairline())
    return line
end
Summon.Hairline = Hairline

-- Round 005 play: a pinned panel covered part of the talents window. Panels
-- share the strata Blizzard's windows open in, and those raise themselves to
-- the top of it when shown, so a window opens over them. The level keeps
-- panels above Blizzard's faded frames, which still take the mouse.
Summon.STRATA = "MEDIUM"
Summon.LEVEL  = 20

--- Put a panel (or something of its own, `above` it) at that depth. Called
-- before its children are made: they take their level from it.
function Summon.Depth(frame, above)
    frame:SetFrameStrata(Summon.STRATA)
    frame:SetFrameLevel(Summon.LEVEL + (above or 0))
end

--- The surface alone: background and the top and bottom hairlines.
function Summon.Surface(frame)
    local s = Summon.SURFACE
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(s[1], s[2], s[3], s[4])
    local top = Hairline(frame, "fillDim")
    top:SetPoint("TOPLEFT")
    top:SetPoint("TOPRIGHT")
    local bottom = Hairline(frame, "fillDim")
    bottom:SetPoint("BOTTOMLEFT")
    bottom:SetPoint("BOTTOMRIGHT")
    frame.__surface = { bg = bg, top = top, bottom = bottom }
    return frame.__surface
end

local function CloseButton(parent)
    local x = CreateFrame("Button", nil, parent)
    x:SetSize(U(14), U(14))
    x.strokes = {}
    for _, angle in ipairs({ 45, -45 }) do
        local t = x:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(Palette.Get("textDim"))
        t:SetSize(U(12), Scale.Hairline() * 2)
        t:SetPoint("CENTER")
        if t.SetRotation then t:SetRotation(math.rad(angle)) end
        x.strokes[#x.strokes + 1] = t
    end
    x:SetScript("OnEnter", function(self)
        for _, t in ipairs(self.strokes) do t:SetColorTexture(Palette.Get("danger")) end
    end)
    x:SetScript("OnLeave", function(self)
        for _, t in ipairs(self.strokes) do t:SetColorTexture(Palette.Get("textDim")) end
    end)
    return x
end

local function PinButton(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(U(44), U(16))
    b.text = ns.Frames.Text(b, 10, "textDim", "RIGHT")
    b.text:SetAllPoints()
    return b
end

--- Surface plus header: a title at the left, pin and close at the right,
-- and the hairline under the header. Returns the header's parts.
function Summon.Chrome(frame, title)
    Summon.Surface(frame)
    local h = {}
    h.title = ns.Frames.Text(frame, 10, "textDim", "LEFT")
    h.title:SetPoint("TOPLEFT", frame, "TOPLEFT", U(Summon.PAD), -U(8))
    h.title:SetText(title or "")
    h.close = CloseButton(frame)
    h.close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -U(Summon.PAD - 2), -U(6))
    h.pin = PinButton(frame)
    h.pin:SetPoint("RIGHT", h.close, "LEFT", -U(10), 0)
    h.under = Hairline(frame, "trough")
    h.under:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -U(Summon.HEADER_H))
    h.under:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -U(Summon.HEADER_H))
    frame.__header = h
    return h
end

--- The inner width: WIDTH less PAD each side.
function Summon.Inner()
    return U(Summon.WIDTH - 2 * Summon.PAD)
end

--- Where the rows start: under the header, and under the filters if any.
function Summon.Top(hasFilters)
    return U(Summon.HEADER_H + (hasFilters and Summon.FILTER_H or 0) + 4)
end

--- A panel's height for rowsHeight of rows (UI units).
function Summon.Height(rowsHeight, hasFilters, hasFooter)
    return Summon.Top(hasFilters) + rowsHeight + U(4) + (hasFooter and U(Summon.FOOTER_H) or 0) + U(4)
end

-- Round 005 play: "the color squares could also be shapes (diamond,
-- square, circle, triangle ...)". Each hue keeps one shape everywhere --
-- toasts, the history, chat, quests, who's online -- so the mark reads
-- without the colour too.
Summon.SHAPE = {
    notifViolet = "circle",     -- people: whispers, chat, logins, achievements
    notifBlue   = "diamond",    -- loot, world quests, group chat, friends
    notifAmber  = "triangle",   -- quests
    notifGreen  = "square",     -- gains, events, guild
    notifOrange = "bar",        -- something wants you
    textDim     = "bar",
}
Summon.CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

--- A hue mark: a small frame holding one shape per hue (Summon.SHAPE).
-- mark:SetHue(paletteName) picks the shape and colours it.
function Summon.Dot(parent, hue)
    local s = U(Summon.DOT)
    local d = CreateFrame("Frame", nil, parent)
    d:SetSize(s, s)
    d.shapes = {}
    local square = d:CreateTexture(nil, "ARTWORK")
    square:SetAllPoints()
    d.shapes.square = square
    local diamond = d:CreateTexture(nil, "ARTWORK")
    diamond:SetSize(s * 0.74, s * 0.74)
    diamond:SetPoint("CENTER")
    if diamond.SetRotation then diamond:SetRotation(math.rad(45)) end
    d.shapes.diamond = diamond
    local circle = d:CreateTexture(nil, "ARTWORK")
    circle:SetAllPoints()
    if d.CreateMaskTexture and circle.AddMaskTexture then
        local mask = d:CreateMaskTexture()
        mask:SetAllPoints(circle)
        mask:SetTexture(Summon.CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        circle:AddMaskTexture(mask)
    end
    d.shapes.circle = circle
    -- A triangle is the top half of a diamond, the bottom half clipped off.
    local clip = CreateFrame("Frame", nil, d)
    clip:SetSize(s * 1.2, s * 0.6)
    clip:SetPoint("CENTER", d, "CENTER", 0, 0)
    if clip.SetClipsChildren then clip:SetClipsChildren(true) end
    local tri = clip:CreateTexture(nil, "ARTWORK")
    tri:SetSize(s * 0.85, s * 0.85)
    tri:SetPoint("CENTER", clip, "BOTTOM", 0, 0)
    if tri.SetRotation then tri:SetRotation(math.rad(45)) end
    clip.tex = tri
    d.shapes.triangle = clip
    local bar = d:CreateTexture(nil, "ARTWORK")
    bar:SetSize(s, s * 0.36)
    bar:SetPoint("CENTER")
    d.shapes.bar = bar

    function d:SetHue(name)
        local shape = Summon.SHAPE[name] or "square"
        local r, g, b, a = Palette.Get(name)
        for key, t in pairs(self.shapes) do
            if key == shape then
                local tex = t.tex or t
                tex:SetColorTexture(r, g, b, a)
                tex:Show()
                t:Show()
            else
                t:Hide()
            end
        end
        self.shape = shape
    end
    d:SetHue(hue or "textDim")
    return d
end

--- The filter row: "all" then one square-and-count per hue, in equal
-- columns across the inner width. items: { { key = nil, label = "all" },
-- { key = "world", hue = "notifBlue", label = "world" }, ... }. onPick(key).
function Summon.Filters(frame, items, onPick)
    local chips = {}
    local w = (Summon.WIDTH - 2 * Summon.PAD) / #items
    for i, item in ipairs(items) do
        local c = CreateFrame("Button", nil, frame)
        c:SetSize(U(w), U(Summon.FILTER_H - 4))
        c:SetPoint("TOPLEFT", frame, "TOPLEFT", U(Summon.PAD + (i - 1) * w), -U(Summon.HEADER_H + 2))
        c.key, c.label, c.hue = item.key, item.label, item.hue
        c.text = ns.Frames.Text(c, 10, "textPrimary", "LEFT")
        if item.hue then
            c.dot = Summon.Dot(c, item.hue)
            c.dot:SetPoint("LEFT")
            c.text:SetPoint("LEFT", c.dot, "RIGHT", U(Summon.GAP), 0)
            c.text:SetPoint("RIGHT")
        else
            c.text:SetAllPoints()
        end
        c:SetScript("OnClick", function(self) onPick(self.key) end)
        chips[i] = c
    end
    local under = Hairline(frame, "trough")
    under:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -U(Summon.HEADER_H + Summon.FILTER_H))
    under:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -U(Summon.HEADER_H + Summon.FILTER_H))
    frame.__chips = chips
    return chips
end

--- Paint the filters: "all N", then each square's count; while one is
-- chosen the others dim. Returns the chosen one's label, for the title.
function Summon.PaintFilters(frame, counts, chosen)
    local label
    for _, c in ipairs(frame.__chips or {}) do
        local n = counts[c.key or "all"] or 0
        c.text:SetText(c.key and tostring(n) or ("all " .. n))
        local lit = chosen == c.key
        c.text:SetTextColor(Palette.Get(lit and "textPrimary" or "textDim"))
        c:SetAlpha((chosen == nil or lit) and 1 or 0.4)
        if lit and c.key then label = c.label end
    end
    return label
end

--- The footer: the panel's action at the left, "+N more" / "fewer" at the
-- right. Either may be absent. actionText may instead be a list of
-- { text, onClick } for several actions in a row (the debug log's copy,
-- clear, report). Returns { action, actions, more }.
function Summon.Footer(frame, actionText, onAction, onMore)
    local f = {}
    local function Button(justify)
        local b = CreateFrame("Button", nil, frame)
        b:SetHeight(U(Summon.FOOTER_H - 4))
        b.text = ns.Frames.Text(b, 10, "textDim", justify)
        b.text:SetAllPoints()
        ns.Frames.HoverEdge(b, 2)
        return b
    end
    f.line = Hairline(frame, "trough")
    f.line:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, U(Summon.FOOTER_H + 4))
    f.line:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, U(Summon.FOOTER_H + 4))
    if type(actionText) == "table" then
        f.actions = {}
        local x = Summon.PAD
        for _, a in ipairs(actionText) do
            local b = Button("LEFT")
            b:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", U(x), U(6))
            b:SetWidth(U(48))
            b.text:SetText(a[1])
            local fn = a[2]
            b:SetScript("OnClick", function() fn() end)
            f.actions[#f.actions + 1] = b
            x = x + 48 + Summon.GAP
        end
        f.action = f.actions[1]
    elseif onAction then
        f.action = Button("LEFT")
        f.action:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", U(Summon.PAD), U(6))
        f.action:SetWidth(U(Summon.WIDTH * 0.6))
        f.action.text:SetText(actionText or "")
        f.action:SetScript("OnClick", function() onAction() end)
    end
    if onMore then
        f.more = Button("RIGHT")
        f.more:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -U(Summon.PAD), U(6))
        f.more:SetWidth(U(Summon.WIDTH * 0.3))
        f.more:SetScript("OnClick", function() onMore() end)
    end
    frame.__footer = f
    return f
end

--- "+N more" while some are hidden, "fewer" while the whole list is out,
-- nothing when everything fits.
function Summon.PaintMore(frame, hidden, expanded)
    local m = frame.__footer and frame.__footer.more
    if not m then return frame.__footer ~= nil end
    -- Opened, it offers "fewer" even if the screen still could not take
    -- them all: a panel never grows past the bottom (Summon.FitRows).
    if expanded then m.text:SetText("fewer") m:Show()
    elseif hidden > 0 then m.text:SetText(("+%d more"):format(hidden)) m:Show()
    else m.text:SetText("") m:Hide() end
    -- A footer with nothing in it is not drawn (round 005 play: an empty
    -- band under the quest list).
    local f = frame.__footer
    local used = f.action ~= nil or m:IsShown()
    if used then f.line:Show() else f.line:Hide() end
    return used
end

--- Mouse for the shared parts (header buttons, filters, footer) with the
-- panel open or closed.
function Summon.Mouse(frame, on)
    local h = frame.__header
    if h then h.pin:EnableMouse(on); h.close:EnableMouse(on) end
    for _, c in ipairs(frame.__chips or {}) do c:EnableMouse(on) end
    local f = frame.__footer
    if f then
        if f.action then f.action:EnableMouse(on) end
        for _, b in ipairs(f.actions or {}) do b:EnableMouse(on) end
        if f.more then f.more:EnableMouse(on) end
    end
end

-- ---------------------------------------------------------------------------
-- Behaviour
-- ---------------------------------------------------------------------------

Summon.all = {}

-- Round 005 play: the history and the chat panel opened on top of each
-- other. Summoned panels DOCK instead: a column down each side, each open
-- panel under the one before it, every panel only as tall as what it holds.
-- Left: the history, then chat. Right: the quest list, then who's online.
Summon.DOCK = {
    left  = { point = "TOPLEFT",  x = 16,  y = Summon.DOCK_TOP },
    right = { point = "TOPRIGHT", x = -16, y = Summon.DOCK_TOP },
}
Summon.DOCK_GAP = 8

-- 2026-11-26 (Charon, the features panel): "several myui panels were
-- disabled correctly but we will need to account for where the default
-- blizz components expect space". A Blizzard frame given back by a switch
-- (Switches.lua) keeps its own place; a dock column that would cover it
-- moves. A tall one (the quest tracker) is stepped aside; a short one (the
-- minimap, the buffs) is gone under. Only frames up in the column's reach:
-- the top half of the screen, across the column's width.

local function Rect(f)
    local ui = _G.UIParent
    local ok, l, b, w, h = pcall(f.GetRect, f)
    if not ok or type(l) ~= "number" or type(w) ~= "number" then return nil end
    local s1, s2 = f:GetEffectiveScale(), ui:GetEffectiveScale()
    local s = (type(s1) == "number" and type(s2) == "number" and s2 > 0) and s1 / s2 or 1
    return l * s, (l + w) * s, (b + h) * s, b * s
end

--- The Blizzard frames a switch has given back, shown now.
function Summon.GivenBack()
    local out = {}
    local S, C = ns.Switches, ns.Clear
    if not (S and C and C.ADOPT) then return out end
    local global = {}
    for _, a in ipairs(C.ADOPT) do global[a[1]] = a[2] end
    for _, s in ipairs(S.LIST) do
        if not S.On(s.key) then
            for _, name in ipairs(s.frames or {}) do
                local f = global[name] and _G[global[name]]
                if f and f.IsShown and f:IsShown() and f.GetRect then out[#out + 1] = f end
            end
            -- Blizzard's unit and party frames, back (Charon: "some blizz UI
            -- is occluded (party frames)").
            for _, g in ipairs(s.units or {}) do
                local f = _G[g]
                if f and f.IsShown and f:IsShown() and f.GetRect then out[#out + 1] = f end
            end
        end
    end
    return out
end

-- 2026-11-26 (Mykel): "the panel that shows up for tanks to add markers --
-- that is blizzards and collides". Blizzard's raid manager (markers, ready
-- check, role filters) lives at the left edge in any group: collapsed, a tab
-- just in from the edge; expanded, 200 wide. Whatever is shown of it, the
-- left column starts to its right.
Summon.EDGE_FRAMES = { left = { "CompactRaidFrameManager" } }

local function EdgeRight(f)
    local right
    for _, part in ipairs({ f, f.toggleButtonForward, f.toggleButtonBack }) do
        if part and part.IsShown and part:IsShown() and part.GetRect then
            local _, r = Rect(part)
            if r and (not right or r > right) then right = r end
        end
    end
    return right
end

--- Where a dock column starts: point, x, y in UI units against UIParent.
function Summon.Origin(side)
    local d = Summon.DOCK[side]
    local x, y = U(d.x), U(d.y)
    local ui = _G.UIParent
    local W = ui and ui.GetWidth and ui:GetWidth() or 0
    local H = ui and ui.GetHeight and ui:GetHeight() or 0
    if type(W) ~= "number" or type(H) ~= "number" or W <= 0 or H <= 0 then return d.point, x, y end
    local gap, colW = U(Summon.DOCK_GAP), U(Summon.WIDTH)
    if side == "left" then
        for _, name in ipairs(Summon.EDGE_FRAMES.left) do
            local f = _G[name]
            local r = f and f.IsShown and f:IsShown() and EdgeRight(f)
            if r and r > 0 then x = math.max(x, r + gap) end
        end
    end
    for _, f in ipairs(Summon.GivenBack()) do
        local l, r, t, b = Rect(f)
        if l then
            local cl, cr
            if side == "left" then cl, cr = x, x + colW else cr = W + x; cl = cr - colW end
            if r > cl and l < cr and t > H / 2 then
                if t - b > H / 2 then
                    if side == "right" then x = math.min(x, l - W - gap) else x = math.max(x, r + gap) end
                else
                    y = math.min(y, b - H - gap)
                end
            end
        end
    end
    return d.point, x, y
end

-- ---------------------------------------------------------------------------
-- The column: ceiling, floor, margins -- and how its panels share it
-- ---------------------------------------------------------------------------
-- 2026-11-26 (Mykel): "we have dynamic ceiling floor and leading and
-- trailing margin constraints. the panels should 'adjust' and not
-- arbitrarily end -- perhaps a set of default sizes -- what i am reacting to
-- is a panel that says +1 more; that has space below it -- or a long panel
-- that says +10 more that has a lot of space."
--
-- A column runs from its ceiling (Summon.Origin: the dock's top, under or
-- beside whatever Blizzard frame is in the way) to its floor (Summon.Floor:
-- the HUD's reserve, or the top of a Blizzard frame given back down there,
-- such as Blizzard's chat). Its leading margin is Origin's x; its trailing
-- edge is the panel width.
--
-- The panels in it share that height (Summon.Share). Each says how tall its
-- rows are, how many it has (want), how many it shows when space is short
-- (prefer: its default size) and the fewest it can show (min). In turn:
-- every panel its min; every panel up to its default; a panel opened with
-- "+N more" all it has; then whatever is left, one row at a time to the
-- panels that still have more. So "+N more" only ever shows when the
-- column is full. A panel whose min does not fit moves to the other
-- column, if there is room there.

--- The column's floor, in UI units up from the screen's bottom.
function Summon.Floor(side)
    local floor = U(Summon.BOTTOM_RESERVE)
    local ui = _G.UIParent
    local W = ui and ui.GetWidth and ui:GetWidth() or 0
    local H = ui and ui.GetHeight and ui:GetHeight() or 0
    if type(W) ~= "number" or type(H) ~= "number" or W <= 0 or H <= 0 then return floor end
    local _, x = Summon.Origin(side)
    local colW = U(Summon.WIDTH)
    local cl, cr
    if side == "left" then cl, cr = x, x + colW else cr = W + x; cl = cr - colW end
    for _, f in ipairs(Summon.GivenBack()) do
        local l, r, t, b = Rect(f)
        if l and r > cl and l < cr and t <= H / 2 + 1 and t > floor then
            floor = t + U(Summon.DOCK_GAP)
        end
    end
    return floor
end

--- The height a column has for its panels; math.huge while the screen is
-- unknown.
function Summon.Span(side)
    local ui = _G.UIParent
    local H = ui and ui.GetHeight and ui:GetHeight() or 0
    if type(H) ~= "number" or H <= 0 then return math.huge end
    local _, _, top = Summon.Origin(side)
    return H + top - Summon.Floor(side)
end

-- What a panel needs: its chrome, its row height, its counts.
local function Measure(c)
    local m = { fixed = c.want == nil }
    if m.fixed then
        m.chrome = c.frame:GetHeight() or 0
        m.rowH, m.want, m.prefer, m.min = 1, 0, 0, 0
        return m
    end
    m.rowH = c.rowH and c.rowH() or U(Summon.ROW_H)
    m.want = math.max(1, c.want() or 1)       -- an empty panel still says so
    -- After want: a panel may learn its chrome while counting (the quest
    -- list's waypoint objectives).
    m.chrome = c.chrome and c.chrome() or Summon.Height(0, true, true)
    m.min = math.min(m.want, c.min and c.min() or 3)
    m.prefer = math.max(m.min, math.min(m.want, c.prefer and c.prefer() or m.want))
    return m
end

--- Share a column's height among its panels; sets c.alloc on each.
function Summon.Share(col, span)
    local gap = U(Summon.DOCK_GAP)
    local budget = span - math.max(0, #col - 1) * gap
    local ms = {}
    for i, c in ipairs(col) do
        ms[i] = Measure(c)
        c.alloc = ms[i].min
        budget = budget - ms[i].chrome - ms[i].min * ms[i].rowH
    end
    local function give(limit)
        local more = true
        while more do
            more = false
            for i, c in ipairs(col) do
                local m = ms[i]
                local cap = limit(c, m)
                if not m.fixed and c.alloc < cap and budget >= m.rowH then
                    c.alloc = c.alloc + 1
                    budget = budget - m.rowH
                    more = true
                end
            end
        end
    end
    give(function(_, m) return m.prefer end)
    give(function(c, m) return c.expanded and c.expanded() and m.want or 0 end)
    give(function(_, m) return m.want end)
    return budget
end

--- What a column's panels need at the least.
local function Least(col)
    local need = math.max(0, #col - 1) * U(Summon.DOCK_GAP)
    for _, c in ipairs(col) do
        local m = Measure(c)
        need = need + m.chrome + m.min * m.rowH
    end
    return need
end

--- How tall a docked panel may be (kept for callers that ask): its share.
function Summon.Room(c)
    if not (c and c.dock) then return math.huge end
    return Summon.Span(c.column or c.dock)
end

--- How many rows a panel shows: its share once the column has been laid
-- out, otherwise as many as fit in the room.
function Summon.FitRows(c, rowHeight, hasFilters, hasFooter)
    if c and c.alloc then return c.alloc end
    local room = Summon.Room(c)
    if room == math.huge then return math.huge end
    local chrome = Summon.Height(0, hasFilters, hasFooter)
    return math.max(1, math.floor((room - chrome) / rowHeight))
end

--- The rows a panel shows: its share, or its default before the first
-- layout.
function Summon.Rows(c, default)
    if c and c.alloc then return c.alloc end
    return default
end

function Summon.Layout()
    -- A panel's Refresh asks for a layout, and a layout refreshes panels so
    -- they draw what they were given: once at a time.
    if Summon.busy then return end
    Summon.busy = true
    local columns = { left = {}, right = {} }
    for _, c in pairs(Summon.all) do
        c.column = nil
        if c.dock and c.open and columns[c.dock] then
            local col = columns[c.dock]
            col[#col + 1] = c
        end
    end
    local function byOrder(a, b) return (a.order or 0) < (b.order or 0) end
    for _, col in pairs(columns) do table.sort(col, byOrder) end
    -- A panel whose least does not fit moves to the other column, last
    -- first, while the other has room for it.
    for _, side in ipairs({ "left", "right" }) do
        local other = side == "left" and "right" or "left"
        local col, span = columns[side], Summon.Span(side)
        while #col > 1 and Least(col) > span do
            local c = col[#col]
            local there = columns[other]
            there[#there + 1] = c
            if Least(there) > Summon.Span(other) then
                there[#there] = nil
                break
            end
            col[#col] = nil
        end
    end
    for side, col in pairs(columns) do
        for _, c in ipairs(col) do c.column = side end
        if Summon.Span(side) ~= math.huge then Summon.Share(col, Summon.Span(side)) end
    end
    local order = {}
    for _, col in pairs(columns) do
        for _, c in ipairs(col) do if c.refresh then order[#order + 1] = c end end
    end
    table.sort(order, byOrder)
    for _, c in ipairs(order) do pcall(c.refresh) end
    Summon.busy = false
    local tops = {}
    for side, col in pairs(columns) do
        local point, ox, oy = Summon.Origin(side)
        local prev
        for _, c in ipairs(col) do
            c.frame:ClearAllPoints()
            if prev then
                local edge = side == "left" and "LEFT" or "RIGHT"
                c.frame:SetPoint("TOP" .. edge, prev.frame, "BOTTOM" .. edge, 0, -U(Summon.DOCK_GAP))
            else
                c.frame:SetPoint(point, UIParent, point, ox, oy)
            end
            prev = c
        end
        tops[side] = col[1] and col[1].frame or nil
    end
    -- Toasts speak beside the left column while it is out, never under it.
    if ns.Toast and ns.Toast.Beside then ns.Toast.Beside(tops.left) end
    return columns
end

--- A docked panel's resting place while closed (peek can still show the
-- quest list): the top of its column.
function Summon.Home(c)
    if not (c.dock and Summon.DOCK[c.dock]) then return end
    local point, x, y = Summon.Origin(c.dock)
    c.frame:ClearAllPoints()
    c.frame:SetPoint(point, UIParent, point, x, y)
end

--- Give a panel the shared behaviour. spec: { key, frame, header (from
-- Chrome), show = function() end, hide = function() end }. show and hide
-- do the panel's own opening and closing; this decides when.
function Summon.Attach(spec)
    local c = { key = spec.key, frame = spec.frame, header = spec.header,
                show = spec.show, hide = spec.hide, open = false,
                dock = spec.dock and ns.Places and ns.Places.Of(spec.key) or spec.dock,
                order = spec.order, refresh = spec.refresh,
                -- How it shares its column (Summon.Share); none: a fixed size.
                rowH = spec.rowH, want = spec.want, prefer = spec.prefer, min = spec.min,
                chrome = spec.chrome, expanded = spec.expanded }
    Summon.all[spec.key] = c

    function c:IsPinned() return DB()[self.key] == true end

    function c:PaintPin()
        local pin = self.header and self.header.pin
        if not pin then return end
        local on = self:IsPinned()
        pin.text:SetText(on and "pinned" or "pin")
        pin.text:SetTextColor(Palette.Get(on and "notifAmber" or "textDim"))
    end

    function c:Watch()
        if self.watching then return end
        self.watching = true
        local function tick()
            if not self.open or self:IsPinned() then
                self.watching = false
                return
            end
            local now = ns.Reveal.Now()
            local over = self.frame.IsMouseOver and self.frame:IsMouseOver()
            if over then
                self.seen, self.lastOver = true, now
            elseif self.seen and now - (self.lastOver or now) >= Summon.LINGER then
                self:Close("left")
            elseif not self.seen and now - self.openedAt >= Summon.UNSEEN then
                self:Close("unseen")
            end
            if self.open then
                C_Timer.After(Summon.TICK, tick)
            else
                self.watching = false
            end
        end
        C_Timer.After(Summon.TICK, tick)
    end

    function c:Open()
        if self.open then
            self.openedAt = ns.Reveal.Now()
            return true
        end
        if self.show() == false then return false end
        self.open, self.seen, self.openedAt = true, false, ns.Reveal.Now()
        self:PaintPin()
        if not self:IsPinned() then self:Watch() end
        Summon.Layout()
        return true
    end

    function c:Close(why)
        if not self.open then return false end
        self.open = false
        self.closedBy = why
        self.hide()
        Summon.Home(self)
        Summon.Layout()
        return true
    end

    function c:SetPinned(on)
        DB()[self.key] = on and true or nil
        self:PaintPin()
        if not on and self.open then
            self.seen, self.openedAt = true, ns.Reveal.Now()
            self.lastOver = self.openedAt
            self:Watch()
        end
        return self:IsPinned()
    end

    if c.header then
        c.header.pin:SetScript("OnClick", function() c:SetPinned(not c:IsPinned()) end)
        c.header.close:SetScript("OnClick", function()
            c:SetPinned(false)
            c:Close("button")
        end)
    end
    c:PaintPin()
    return c
end

--- Combat puts away every summoned panel that is not pinned.
function Summon.OnCombat()
    for _, c in pairs(Summon.all) do
        if c.open and not c:IsPinned() then c:Close("combat") end
    end
end

--- At login, a panel left pinned comes back open.
function Summon.Restore()
    for key, c in pairs(Summon.all) do
        if DB()[key] == true and not c.open then c:Open() end
    end
end

function Summon.OnLogin()
    local driver = CreateFrame("Frame", "MyUISummonDriver", UIParent)
    driver:RegisterEvent("PLAYER_REGEN_DISABLED")
    -- Blizzard's party frames, given back, appear with a group: the columns
    -- move off them once they have (Summon.Origin).
    driver:RegisterEvent("GROUP_ROSTER_UPDATE")
    -- The raid manager opening or closing moves the left column with it.
    for _, fn in ipairs({ "CompactRaidFrameManager_Expand", "CompactRaidFrameManager_Collapse" }) do
        if type(_G[fn]) == "function" then
            hooksecurefunc(fn, function() C_Timer.After(0, Summon.Layout) end)
        end
    end
    driver:SetScript("OnEvent", function(_, event)
        if event == "GROUP_ROSTER_UPDATE" then
            if not Summon.relayoutQueued then
                Summon.relayoutQueued = true
                C_Timer.After(0.5, function() Summon.relayoutQueued = false; Summon.Layout() end)
            end
            return
        end
        Summon.OnCombat()
    end)
    Summon.driver = driver
    -- After everything that attaches a panel has built (Core runs this last).
    C_Timer.After(0, Summon.Restore)
end
