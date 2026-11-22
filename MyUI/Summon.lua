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
-- right. Either may be absent. Returns { action, more }.
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
    if onAction then
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

--- Stack the open panels of each dock column, in order. Called whenever a
-- panel opens, closes or changes height.
--- How tall a docked panel may be: the screen under the dock's top, less
-- the panels above it in its column, less the HUD's reserve. Unknown screen
-- height (0): no limit.
function Summon.Room(c)
    local screen = _G.UIParent and _G.UIParent.GetHeight and _G.UIParent:GetHeight() or 0
    if type(screen) ~= "number" or screen <= 0 or not c or not c.dock then return math.huge end
    local used = U(-Summon.DOCK_TOP) + U(Summon.BOTTOM_RESERVE)
    for _, o in pairs(Summon.all) do
        if o ~= c and o.open and o.dock == c.dock and (o.order or 0) < (c.order or 0) then
            used = used + o.frame:GetHeight() + U(Summon.DOCK_GAP)
        end
    end
    return screen - used
end

--- How many rows of rowHeight fit in a panel's room, at least one.
function Summon.FitRows(c, rowHeight, hasFilters, hasFooter)
    local room = Summon.Room(c)
    if room == math.huge then return math.huge end
    local chrome = Summon.Height(0, hasFilters, hasFooter)
    return math.max(1, math.floor((room - chrome) / rowHeight))
end

function Summon.Layout()
    -- A panel's Refresh asks for a layout, and a layout refreshes panels so
    -- the lower ones fit what the upper ones left them: once at a time.
    if Summon.busy then return end
    Summon.busy = true
    local order = {}
    for _, c in pairs(Summon.all) do
        if c.dock and c.open and c.refresh then order[#order + 1] = c end
    end
    table.sort(order, function(a, b) return (a.order or 0) < (b.order or 0) end)
    for _, c in ipairs(order) do pcall(c.refresh) end
    Summon.busy = false
    local columns = { left = {}, right = {} }
    for _, c in pairs(Summon.all) do
        if c.dock and c.open and columns[c.dock] then
            local col = columns[c.dock]
            col[#col + 1] = c
        end
    end
    local tops = {}
    for side, col in pairs(columns) do
        table.sort(col, function(a, b) return (a.order or 0) < (b.order or 0) end)
        local d = Summon.DOCK[side]
        local prev
        for _, c in ipairs(col) do
            c.frame:ClearAllPoints()
            if prev then
                local edge = side == "left" and "LEFT" or "RIGHT"
                c.frame:SetPoint("TOP" .. edge, prev.frame, "BOTTOM" .. edge, 0, -U(Summon.DOCK_GAP))
            else
                c.frame:SetPoint(d.point, UIParent, d.point, U(d.x), U(d.y))
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
    local d = c.dock and Summon.DOCK[c.dock]
    if not d then return end
    c.frame:ClearAllPoints()
    c.frame:SetPoint(d.point, UIParent, d.point, U(d.x), U(d.y))
end

--- Give a panel the shared behaviour. spec: { key, frame, header (from
-- Chrome), show = function() end, hide = function() end }. show and hide
-- do the panel's own opening and closing; this decides when.
function Summon.Attach(spec)
    local c = { key = spec.key, frame = spec.frame, header = spec.header,
                show = spec.show, hide = spec.hide, open = false,
                dock = spec.dock, order = spec.order, refresh = spec.refresh }
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
    driver:SetScript("OnEvent", function() Summon.OnCombat() end)
    Summon.driver = driver
    -- After everything that attaches a panel has built (Core runs this last).
    C_Timer.After(0, Summon.Restore)
end
