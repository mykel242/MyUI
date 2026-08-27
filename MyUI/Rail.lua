-- MyUI :: Rail.lua
-- SPEC.md 6. The left-edge rail: what happened while you weren't looking.
--
-- PLAN.md puts this ahead of the bars deliberately -- it touches no protected
-- data, so it exercises the reveal engine hard with no taint risk at all.
-- Nothing in this file reads a unit, a spell or a cooldown.
--
-- SPEC.md is complete on the rail's appearance and silent on two things: where
-- a toast sits, and what produces a notification in the first place. Both are
-- flagged in STATUS. Phase 3 ships /myui notify as the source so the lifecycle
-- can be built and accepted without inventing a data binding the spec never
-- asked for.

local ADDON, ns = ...

local Registry, Scale, Palette = ns.Registry, ns.Scale, ns.Palette

local Rail = {}
ns.Rail = Rail

local U = function(v) return Scale.U(v) end

-- ---------------------------------------------------------------------------
-- Constants, all from SPEC.md 6 and 8
-- ---------------------------------------------------------------------------

Rail.CAP         = 8      -- "Cap at 8 dots"
Rail.NAMED       = 2      -- "The two newest items carry name, count and age"
Rail.OLD_ALPHA   = 0.4    -- "Older items are the dot alone at alpha 0.4"
Rail.DOT         = 10     -- "Dots 10 x 10"
Rail.FIRST_DOT   = 40     -- "first at 40 down from the hairline top"
Rail.SPACING     = 26     -- "26 spacing"
Rail.TOAST_DWELL = 4.0    -- SPEC 8: "4s dwell, then 200ms"
Rail.TOAST_IN    = 0.180  -- SPEC 8: "slide + fade, 180ms"
Rail.TOAST_OUT   = 0.200

-- SPEC.md 6's dot hues, which are also SPEC.md 7 palette entries. Naming them
-- by type rather than colour keeps the palette the single source.
Rail.HUES = {
    blue   = "notifBlue",
    amber  = "notifAmber",
    green  = "notifGreen",
    violet = "notifViolet",
    orange = "notifOrange",
}

-- Invented: SPEC gives the dots' vertical positions and nothing horizontal.
-- The rail sits at x = 20, so rightward is the only direction with room.
local TEXT_GAP   = 8      -- name starts this far right of the dot
local ROW_WIDTH  = 160
local TOAST_W    = 200
local TOAST_H    = 20
local TOAST_SLIDE = 12    -- how far the toast travels on entry

-- ---------------------------------------------------------------------------
-- Items
-- ---------------------------------------------------------------------------

Rail.items = {}   -- newest first

--- SPEC.md 6 says "age", not "timestamp". Coarse on purpose: a rail read at a
-- glance does not want three digits of precision.
function Rail.FormatAge(seconds)
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

--- An item's display text: name, plus a count only when there is one to show.
function Rail.Label(item)
    if item.count > 1 then
        return ("%s x%d"):format(item.name, item.count)
    end
    return item.name
end

--- Add a notification. Returns the item, or nil plus a reason.
function Rail.Add(kind, name, count)
    if not Rail.HUES[kind] then
        return nil, ("unknown type %q -- one of blue, amber, green, violet, orange")
                    :format(tostring(kind))
    end
    local item = {
        kind  = kind,
        name  = name or kind,
        count = tonumber(count) or 1,
        at    = ns.Reveal.Now(),
    }
    table.insert(Rail.items, 1, item)
    Rail.Refresh()
    Rail.Toast(item)
    return item
end

function Rail.Clear()
    Rail.items = {}
    Rail.Collapse()
    Rail.Refresh()
end

--- How many items are hidden behind the "+N more" square.
function Rail.Overflow()
    local extra = #Rail.items - Rail.CAP
    if extra < 0 then
        return 0
    end
    return extra
end

-- ---------------------------------------------------------------------------
-- Widgets
-- ---------------------------------------------------------------------------

local slots, overflow, toast

local function SlotY(index)
    return -U(Rail.FIRST_DOT + (index - 1) * Rail.SPACING)
end

local function BuildSlot(rail, index)
    local slot = CreateFrame("Frame", nil, rail)
    slot:SetSize(U(Rail.DOT) + U(TEXT_GAP) + U(ROW_WIDTH), U(Rail.DOT))
    slot:SetPoint("TOPLEFT", rail, "TOPLEFT", 0, SlotY(index))

    slot.dot = slot:CreateTexture(nil, "ARTWORK")
    slot.dot:SetSize(U(Rail.DOT), U(Rail.DOT))
    slot.dot:SetPoint("TOPLEFT")

    -- Only the two newest use these, but every slot owns them: creating widgets
    -- when a notification arrives would mean allocating in combat.
    slot.name = ns.Frames.Text(slot, 11, "textPrimary", "LEFT")
    slot.name:SetPoint("LEFT", slot.dot, "RIGHT", U(TEXT_GAP), 0)

    slot.age = ns.Frames.Text(slot, 10, "textTertiary", "RIGHT")
    slot.age:SetPoint("RIGHT", slot, "RIGHT", 0, 0)

    slot:Hide()
    return slot
end

--- The overflow marker: a hollow square, per SPEC.md 6. Hollow because a solid
-- one would read as a ninth notification rather than as a count of them.
local function BuildOverflow(rail)
    local frame = CreateFrame("Frame", nil, rail)
    frame:SetSize(U(Rail.DOT) + U(TEXT_GAP) + U(ROW_WIDTH), U(Rail.DOT))
    frame:SetPoint("TOPLEFT", rail, "TOPLEFT", 0, SlotY(Rail.CAP + 1))

    local thickness = Scale.Hairline()
    frame.edges = {}
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local edge = frame:CreateTexture(nil, "ARTWORK")
        edge:SetColorTexture(Palette.Get("textTertiary"))
        if side == "TOP" or side == "BOTTOM" then
            edge:SetSize(U(Rail.DOT), thickness)
            edge:SetPoint(side .. "LEFT", frame, "TOPLEFT", 0,
                          side == "TOP" and 0 or -U(Rail.DOT))
        else
            edge:SetSize(thickness, U(Rail.DOT))
            edge:SetPoint("TOP" .. side, frame, "TOPLEFT",
                          side == "LEFT" and 0 or U(Rail.DOT), 0)
        end
        frame.edges[side] = edge
    end

    frame.label = ns.Frames.Text(frame, 10, "textTertiary", "LEFT")
    frame.label:SetPoint("LEFT", frame, "LEFT", U(Rail.DOT) + U(TEXT_GAP), 0)

    frame:Hide()
    return frame
end

-- SPEC.md 6: a toast "speaks once, then collapses into its dot". Read
-- literally, that says what the toast IS: the newest item's row, expanded,
-- shrinking back into the dot it belongs to.
--
-- The first attempt gave the toast its own dot and its own copy of the text,
-- anchored over the first row -- so while it was up you saw the same
-- notification twice, overlapping itself. It has no dot of its own now; it
-- borrows the first slot's, and that slot's text stays hidden until the toast
-- has collapsed into it.
local function BuildToast(rail)
    local frame = CreateFrame("Frame", "MyUIRailToast", rail)
    frame:SetFrameStrata(ns.Frames.STRATA)
    frame:SetSize(U(TOAST_W), U(TOAST_H))

    frame.label = ns.Frames.Text(frame, 11, "textPrimary", "LEFT")
    frame.label:SetPoint("LEFT")

    -- SPEC.md 8: slide + fade, 180ms in; 200ms to collapse.
    --
    -- A Translation moves the frame and then snaps back to its anchor, so
    -- sliding IN means anchoring short of the destination, translating the
    -- gap, and moving the anchor to the destination as the animation ends.
    -- Animating toward the anchor and stopping is the wrong way round: the
    -- frame would slide right and then jump back left.
    local entrance = frame:CreateAnimationGroup()
    local fadeIn = entrance:CreateAnimation("Alpha")
    fadeIn:SetDuration(Rail.TOAST_IN)
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(1)
    local slide = entrance:CreateAnimation("Translation")
    slide:SetDuration(Rail.TOAST_IN)
    slide:SetOffset(U(TOAST_SLIDE), 0)
    entrance:SetScript("OnFinished", function()
        Rail.AnchorToast(0)
    end)
    frame.entrance = entrance

    local collapse = frame:CreateAnimationGroup()
    local fadeOut = collapse:CreateAnimation("Alpha")
    fadeOut:SetDuration(Rail.TOAST_OUT)
    fadeOut:SetFromAlpha(1)
    fadeOut:SetToAlpha(0)
    collapse:SetScript("OnFinished", function()
        frame:Hide()
        Rail.toasting = nil
        -- The row underneath takes over the moment the toast is gone.
        Rail.Refresh()
    end)
    frame.collapse = collapse

    frame:EnableMouse(true)
    frame:SetScript("OnMouseDown", function() Rail.Collapse() end)

    frame:Hide()
    return frame
end

--- Place the toast where the first row's text goes, offset by `slide` units to
-- the left of it. Zero is its resting position.
function Rail.AnchorToast(slide)
    if not toast or not slots then
        return
    end
    toast:ClearAllPoints()
    toast:SetPoint("LEFT", slots[1].dot, "RIGHT", U(TEXT_GAP) - (slide or 0), 0)
end

-- ---------------------------------------------------------------------------
-- Painting
-- ---------------------------------------------------------------------------

--- Repaint the rail from Rail.items. Cheap, and called on every change: the
-- rail holds at most nine widgets and none of them animate.
function Rail.Refresh()
    if not slots then
        return
    end
    local now = ns.Reveal.Now()

    for i = 1, Rail.CAP do
        local slot, item = slots[i], Rail.items[i]
        if not item then
            slot:Hide()
        else
            slot:Show()
            slot.dot:SetColorTexture(Palette.Get(Rail.HUES[item.kind]))

            if i <= Rail.NAMED then
                -- "The two newest items carry name, count and age at rest --
                -- no hover required."
                slot.dot:SetAlpha(1)
                slot.name:SetText(Rail.Label(item))
                slot.age:SetText(Rail.FormatAge(now - item.at))

                -- Except while this item is still speaking: the toast is this
                -- row expanded, and drawing both gives you the notification
                -- twice, overlapping itself.
                if i == 1 and Rail.toasting == item then
                    slot.name:Hide()
                    slot.age:Hide()
                else
                    slot.name:Show()
                    slot.age:Show()
                end
            else
                -- "Older items are the dot alone at alpha 0.4."
                slot.dot:SetAlpha(Rail.OLD_ALPHA)
                slot.name:SetText("")
                slot.age:SetText("")
                slot.name:Hide()
                slot.age:Hide()
            end
        end
    end

    local extra = Rail.Overflow()
    if extra > 0 then
        overflow.label:SetText(("+%d more"):format(extra))
        overflow:Show()
    else
        overflow:Hide()
    end
end

-- ---------------------------------------------------------------------------
-- Toast
-- ---------------------------------------------------------------------------

--- Speak once, then collapse into the dot. A second notification arriving
-- while one is up collapses it immediately rather than queueing: the rail
-- already holds everything, so the toast is the announcement, not the record.
function Rail.Toast(item)
    if not toast then
        return
    end
    toast.collapse:Stop()
    toast.entrance:Stop()

    toast.label:SetText(Rail.Label(item))

    Rail.toasting = item
    Rail.toastUntil = ns.Reveal.Now() + Rail.TOAST_DWELL
    toast:SetAlpha(1)
    toast:Show()
    -- Start short of the destination so the slide has somewhere to come from.
    Rail.AnchorToast(TOAST_SLIDE)
    toast.entrance:Play()

    -- Hide the row this toast is standing in for.
    Rail.Refresh()

    C_Timer.After(Rail.TOAST_DWELL, function()
        -- Only collapse if this toast is still the one on screen; a newer
        -- arrival owns the slot and its own timer.
        if Rail.toasting == item then
            Rail.Collapse()
        end
    end)
end

--- Collapse the toast now, whether the dwell has run out or you dismissed it.
function Rail.Collapse()
    if not toast or not Rail.toasting then
        return false
    end
    Rail.toasting = nil
    Rail.toastUntil = nil
    toast.entrance:Stop()
    Rail.AnchorToast(0)
    toast.collapse:Play()
    return true
end

function Rail.IsToasting()
    return Rail.toasting ~= nil
end

-- ---------------------------------------------------------------------------
-- Build
-- ---------------------------------------------------------------------------

function Rail.OnLogin()
    local entry = Registry.Get("Rail")
    if not entry or slots then
        return
    end
    local rail = entry.frame

    slots = {}
    for i = 1, Rail.CAP do
        slots[i] = BuildSlot(rail, i)
    end
    overflow = BuildOverflow(rail)
    toast = BuildToast(rail)
    Rail.AnchorToast(0)

    Rail.slots, Rail.overflow, Rail.toastFrame = slots, overflow, toast
    Rail.Refresh()

    -- Ages tick over on a timer rather than in the reveal engine's OnUpdate.
    -- RULES.md permits that OnUpdate solely for cursor proximity and the peek
    -- clock, and an age that changes once a second has no business there.
    local function tick()
        Rail.Refresh()
        C_Timer.After(1, tick)
    end
    C_Timer.After(1, tick)
end
