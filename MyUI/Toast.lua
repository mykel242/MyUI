-- MyUI :: Toast.lua
-- SPEC.md 6 (round 003): toasts and a history. The rail is cut; the toast it
-- carried survives here, at ToastAnchor rather than in a fixed column.
--
-- One toast per event, never a stream. Every notification is written to the
-- character log FIRST (Log.lua), so a toast is the announcement and never the
-- record: one that is dismissed, capped off or suppressed loses nothing.
--
-- Nothing in this file reads a unit, a spell or a cooldown.

local ADDON, ns = ...

local Scale, Palette = ns.Scale, ns.Palette

local Toast = {}
ns.Toast = Toast

local U = function(v) return Scale.U(v) end

-- ---------------------------------------------------------------------------
-- Constants -- SPEC.md 6 and 8
-- ---------------------------------------------------------------------------

Toast.DWELL   = 4.0     -- SPEC 8: "4s dwell, then 200ms fade"
Toast.IN      = 0.180   -- SPEC 8: "slide + fade, 180ms"
Toast.OUT     = 0.200
-- SPEC 6: "Simultaneous toasts stack away from the anchor's snapped corner.
-- Cap: tune in Phase 6." Three is a placeholder; past it the oldest leaves at
-- once rather than queueing, because the log already has it.
Toast.CAP     = 3

Toast.WIDTH   = 220
Toast.HEIGHT  = 20
Toast.GAP     = 6       -- between stacked toasts
Toast.DOT     = 10
Toast.SLIDE   = 12      -- how far a toast travels on entry
local TEXT_GAP = 8
local NAME_GAP = 6

-- Where the anchor sits until the layout layer (R4) lets the player place it:
-- the left edge, upper third -- clear of SelfStack (bottom centre) and
-- TargetStrip (top centre), which a toast must never cover (SPEC 6).
Toast.DEFAULT = { point = "TOPLEFT", x = 20, y = -240 }

-- SPEC 6's hues, by meaning. Five, all palette entries: four mean SOMETHING
-- HAPPENED, orange means SOMETHING WANTS YOU. The Aug 28 sixth hue (red, for
-- deaths) is dropped in round 003.
Toast.HUES = {
    blue   = "notifBlue",
    amber  = "notifAmber",
    green  = "notifGreen",
    violet = "notifViolet",
    orange = "notifOrange",
}

-- ---------------------------------------------------------------------------
-- Text
-- ---------------------------------------------------------------------------

--- Coarse on purpose: read at a glance.
function Toast.FormatAge(seconds)
    if type(seconds) ~= "number" or seconds < 0 then
        return "?"
    end
    if seconds < 60 then
        return ("%ds"):format(math.floor(seconds))
    end
    if seconds < 3600 then
        return ("%dm"):format(math.floor(seconds / 60))
    end
    return ("%dh"):format(math.floor(seconds / 3600))
end

function Toast.Label(item)
    if (item.count or 1) > 1 then
        return ("%s x%d"):format(item.name, item.count)
    end
    return item.name
end

-- ---------------------------------------------------------------------------
-- Widgets
-- ---------------------------------------------------------------------------

local anchor
local pool = {}       -- toast frames, built once; never allocated in combat
Toast.live = {}       -- items on screen, newest first

local function SlotOffset(index)
    return -(index - 1) * U(Toast.HEIGHT + Toast.GAP)
end

local function Build(index)
    local f = CreateFrame("Frame", "MyUIToast" .. index, anchor)
    f:SetFrameStrata(ns.Frames.STRATA)
    f:SetSize(U(Toast.WIDTH), U(Toast.HEIGHT))

    f.dot = f:CreateTexture(nil, "ARTWORK")
    f.dot:SetSize(U(Toast.DOT), U(Toast.DOT))
    f.dot:SetPoint("LEFT")

    -- The age never yields; the name truncates against it (SPEC 6, H1). Two
    -- anchors give the name a real width, the right one tied to the AGE so the
    -- name gives way to however wide the age is.
    f.age = ns.Frames.Text(f, 10, "textDim", "RIGHT")
    f.age:SetPoint("RIGHT")
    f.name = ns.Frames.Text(f, 11, "textPrimary", "LEFT")
    f.name:SetPoint("LEFT", f.dot, "RIGHT", U(TEXT_GAP), 0)
    f.name:SetPoint("RIGHT", f.age, "LEFT", -U(NAME_GAP), 0)
    f.name:SetWordWrap(false)

    -- SPEC 8: slide + fade in. A Translation snaps back to the anchor when it
    -- ends, so the frame is anchored short of its place, slides the gap, and
    -- is re-anchored at its place when the animation finishes.
    local entrance = f:CreateAnimationGroup()
    local fadeIn = entrance:CreateAnimation("Alpha")
    fadeIn:SetDuration(Toast.IN)
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(1)
    local slide = entrance:CreateAnimation("Translation")
    slide:SetDuration(Toast.IN)
    slide:SetOffset(U(Toast.SLIDE), 0)
    entrance:SetScript("OnFinished", function() Toast.Layout() end)
    f.entrance = entrance

    local leave = f:CreateAnimationGroup()
    local fadeOut = leave:CreateAnimation("Alpha")
    fadeOut:SetDuration(Toast.OUT)
    fadeOut:SetFromAlpha(1)
    fadeOut:SetToAlpha(0)
    leave:SetScript("OnFinished", function()
        f:Hide()
        f:SetAlpha(1)
        f.item = nil
        Toast.Layout()
    end)
    f.leave = leave

    -- SPEC 6: "A toast can be interacted with." Left click acts on it (a
    -- whisper opens chat at that conversation; anything else opens the
    -- history at its hue); right click dismisses. A hidden toast takes no
    -- mouse, so the screen edge only eats clicks while something is speaking.
    f:EnableMouse(true)
    f:SetScript("OnMouseUp", function(self, button)
        local item = self.item
        if not item then return end
        if button == "RightButton" then
            Toast.Dismiss(item)
        else
            Toast.Activate(item)
        end
    end)

    f:Hide()
    return f
end

local function FrameFor(item)
    for _, f in ipairs(pool) do
        if f.item == item then return f end
    end
    return nil
end

local function FreeFrame()
    for _, f in ipairs(pool) do
        if not f.item then return f end
    end
    return nil
end

local function Paint(f, now)
    local item = f.item
    f.dot:SetColorTexture(Palette.Get(Toast.HUES[item.kind]))
    f.name:SetText(Toast.Label(item))
    f.age:SetText(Toast.FormatAge((now or ns.Reveal.Now()) - item.at))
end

--- Repaint every live toast's text and age now, rather than on the next tick.
function Toast.Repaint()
    local now = ns.Reveal.Now()
    for _, f in ipairs(pool) do
        if f.item then Paint(f, now) end
    end
end

--- Re-anchor every live toast: newest at the anchor, older ones stacked away
-- from it.
function Toast.Layout()
    for i, item in ipairs(Toast.live) do
        local f = FrameFor(item)
        if f and not f.entrance:IsPlaying() then
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, SlotOffset(i))
        end
    end
end

-- ---------------------------------------------------------------------------
-- Items
-- ---------------------------------------------------------------------------

local function Remove(item)
    for i, other in ipairs(Toast.live) do
        if other == item then
            table.remove(Toast.live, i)
            return true
        end
    end
    return false
end

--- Notify: log it, then speak it. Returns the item, or nil plus a reason.
function Toast.Add(kind, name, count, sub)
    if not Toast.HUES[kind] then
        return nil, ("unknown type %q -- one of blue, amber, green, violet, orange")
                    :format(tostring(kind))
    end
    local item = {
        kind = kind, name = name or kind, count = tonumber(count) or 1,
        sub = sub, at = ns.Reveal.Now(),
    }
    -- The record first, unconditionally.
    if ns.Log and ns.Log.Add then
        ns.Log.Add(kind, item.name, item.count, sub)
    end
    Toast.Speak(item)
    return item
end

--- A burst that is already speaking rolls into the toast it already owns
-- instead of adding another. Logged either way.
function Toast.Bump(item, count)
    if not item then return nil end
    count = tonumber(count) or 1
    item.count = (item.count or 1) + count
    if ns.Log and ns.Log.Add then
        ns.Log.Add(item.kind, item.name, count, item.sub)
    end
    local f = FrameFor(item)
    if f then Paint(f) end
    return item
end

--- Put an item on screen. While the history is open nothing speaks: you are
-- already looking at the record, which refreshes instead.
function Toast.Speak(item)
    if not anchor then return end
    if ns.Center and ns.Center.IsOpen and ns.Center.IsOpen() then
        ns.Center.Refresh()
        return
    end
    -- Past the cap, the oldest leaves now.
    while #Toast.live >= Toast.CAP do
        Toast.Dismiss(Toast.live[#Toast.live], true)
    end
    local f = FreeFrame()
    if not f then return end

    table.insert(Toast.live, 1, item)
    f.item = item
    f.leave:Stop()
    f.entrance:Stop()
    Paint(f)
    f:SetAlpha(1)
    f:Show()
    Toast.Layout()
    -- Start short of the place so the slide has somewhere to come from.
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", anchor, "TOPLEFT", -U(Toast.SLIDE), SlotOffset(1))
    f.entrance:Play()

    C_Timer.After(Toast.DWELL, function()
        if f.item == item then Toast.Dismiss(item) end
    end)
end

--- Leave now: the dwell ran out, it was dismissed, or the cap pushed it off.
function Toast.Dismiss(item, instant)
    item = item or Toast.live[1]
    if not item or not Remove(item) then return false end
    local f = FrameFor(item)
    if f then
        f.entrance:Stop()
        if instant then
            f:Hide()
            f.item = nil
        else
            f.leave:Play()
        end
    end
    Toast.Layout()
    return true
end

function Toast.Clear()
    while Toast.live[1] do Toast.Dismiss(Toast.live[1], true) end
end

function Toast.IsSpeaking()
    return Toast.live[1] ~= nil
end

--- What a click on a toast does. A whisper opens chat at that conversation,
-- the main way into chat (SPEC 14); anything else opens the history at its
-- hue.
function Toast.Activate(item)
    Toast.Dismiss(item, true)
    if item.kind == "violet" and ns.Chat and ns.Chat.Open then
        -- A character name answers with /w; a Battle.net or secret sender
        -- carries none, and /r answers whoever spoke last.
        ns.Chat.Open(item.sub and ("/w %s "):format(item.sub) or "/r ")
        return "chat"
    end
    if ns.Center and ns.Center.Open then
        ns.Center.Open(item.kind)
        return "history"
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Build
-- ---------------------------------------------------------------------------

--- The anchor. Not in the reveal registry: SPEC 2 gives it resting alpha 0
-- with toasts shown only while speaking, which is what a plain frame holding
-- hidden-until-speaking toasts already is -- and registering it would let peek
-- and proximity "reveal" an empty rectangle. The layout layer (R4) moves it.
function Toast.Anchor()
    return anchor
end

function Toast.OnLogin()
    if anchor then return end
    anchor = CreateFrame("Frame", "MyUIToastAnchor", UIParent)
    anchor:SetSize(U(Toast.WIDTH), U(Toast.HEIGHT))
    local d = Toast.DEFAULT
    anchor:SetPoint(d.point, UIParent, d.point, U(d.x), U(d.y))
    -- Two spare: a toast that is fading out still holds its frame for 200ms.
    for i = 1, Toast.CAP + 2 do
        pool[i] = Build(i)
    end
    Toast.pool = pool

    -- Ages tick on a timer: RULES reserves the one OnUpdate for cursor
    -- proximity and the peek clock.
    local function tick()
        local now = ns.Reveal.Now()
        for _, f in ipairs(pool) do
            if f.item then Paint(f, now) end
        end
        C_Timer.After(1, tick)
    end
    C_Timer.After(1, tick)
end
