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
Summon.HEADER_H = 26
Summon.PAD      = 10
Summon.ROW_H    = 22

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

-- ---------------------------------------------------------------------------
-- Behaviour
-- ---------------------------------------------------------------------------

Summon.all = {}

--- Give a panel the shared behaviour. spec: { key, frame, header (from
-- Chrome), show = function() end, hide = function() end }. show and hide
-- do the panel's own opening and closing; this decides when.
function Summon.Attach(spec)
    local c = { key = spec.key, frame = spec.frame, header = spec.header,
                show = spec.show, hide = spec.hide, open = false }
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
        return true
    end

    function c:Close(why)
        if not self.open then return false end
        self.open = false
        self.closedBy = why
        self.hide()
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
