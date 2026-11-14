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

-- Round 5 killed the cap: "you were right, the cap was arbitrary". Dots age
-- out instead, so the rail is a decay curve rather than a queue with a length.
--
-- SLOTS is not that cap coming back. WoW cannot destroy a frame -- only hide
-- and reuse one -- so a rail with no ceiling is a pool that only ever grows.
-- This is an allocation bound, set past the densest state Round 5 draws
-- (thirty-four live at pitch 8), and the log behind the rail is what makes
-- dropping the overflow honest rather than lossy.
Rail.SLOTS       = 40
Rail.DECAY       = 300    -- "decays to zero over 5 minutes"
Rail.NAMED       = 2      -- "The two newest items carry name, count and age"
Rail.OLD_ALPHA   = 0.4    -- "Older items are the dot alone at alpha 0.4"
Rail.DOT         = 10     -- "Dots 10 x 10"
Rail.FIRST_DOT   = 40     -- "first at 40 down from the hairline top"
Rail.SPACING     = 26     -- "26 spacing"
-- "Pitch drops 26 -> 20 -> 8 as the live count rises, so a raid pull looks
-- like a raid pull." Read off Round 5's own age strips: six live at 26, twelve
-- at 20, thirty-four at 8.
Rail.PITCH       = { { 8, 26 }, { 16, 20 } }
Rail.PITCH_MIN   = 8
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
    -- Round 5's sixth hue. It cost nothing: rgba(242,107,97,1) is byte for
    -- byte the `danger` already in the palette for the low-health bar, so the
    -- rail borrows it rather than adding a fourteenth colour.
    red    = "danger",
}

-- Invented: SPEC gives the dots' vertical positions and nothing horizontal.
-- The rail sits at x = 20, so rightward is the only direction with room.
local TEXT_GAP   = 8      -- name starts this far right of the dot
local NAME_GAP   = 6      -- clear space the name must leave before the age
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
function Rail.Add(kind, name, count, sub)
    if not Rail.HUES[kind] then
        return nil, ("unknown type %q -- one of blue, amber, green, violet, orange, red")
                    :format(tostring(kind))
    end
    local item = {
        kind  = kind,
        name  = name or kind,
        count = tonumber(count) or 1,
        sub   = sub,
        at    = ns.Reveal.Now(),
    }

    -- The record is written FIRST, and unconditionally. Everything the rail is
    -- now allowed to do -- decay a dot, drop the oldest, stay silent in combat
    -- -- is only honest because the log already has it. If this ever moves
    -- below the display, the rail starts losing things again.
    if ns.Log and ns.Log.Add then
        ns.Log.Add(kind, item.name, item.count, sub)
    end

    table.insert(Rail.items, 1, item)
    Rail.Refresh()
    Rail.Toast(item)
    return item
end

--- Refresh an existing item instead of adding another beside it.
--
-- Round 5: "A noisy source owns one dot and refreshes its own timer rather
-- than adding another, so 62 experience ticks are one violet dot that keeps
-- resetting. Without this, decay alone wouldn't have saved the rail."
--
-- It moves to the front because the rail is ordered newest first and a
-- refreshed item IS the newest. It does not toast: the burst already spoke.
function Rail.Bump(item, count)
    if not item then
        return nil
    end
    item.at    = ns.Reveal.Now()
    item.count = item.count + (tonumber(count) or 1)

    if ns.Log and ns.Log.Add then
        ns.Log.Add(item.kind, item.name, tonumber(count) or 1, item.sub)
    end

    for i, other in ipairs(Rail.items) do
        if other == item then
            table.remove(Rail.items, i)
            break
        end
    end
    table.insert(Rail.items, 1, item)
    Rail.Refresh()
    return item
end

function Rail.Clear()
    Rail.items = {}
    Rail.Collapse()
    Rail.Refresh()
end

--- Drop what has aged out, then anything past the pool ceiling.
-- Returns how many left. Nothing is lost: the log has all of it.
function Rail.Expire(now)
    now = now or ns.Reveal.Now()
    local gone = 0
    for i = #Rail.items, 1, -1 do
        if (now - Rail.items[i].at) >= Rail.DECAY then
            table.remove(Rail.items, i)
            gone = gone + 1
        end
    end
    while #Rail.items > Rail.SLOTS do
        table.remove(Rail.items)
        gone = gone + 1
    end
    return gone
end

--- How far apart the dots sit, given how many are live.
function Rail.Pitch(count)
    count = count or #Rail.items
    for _, step in ipairs(Rail.PITCH) do
        if count <= step[1] then
            return step[2]
        end
    end
    return Rail.PITCH_MIN
end

--- How lit a dot is, by age. Enters at OLD_ALPHA, reaches zero at DECAY.
function Rail.Fade(age)
    local left = 1 - ((tonumber(age) or 0) / Rail.DECAY)
    if left < 0 then return 0 end
    if left > 1 then return 1 end
    return Rail.OLD_ALPHA * left
end

-- ---------------------------------------------------------------------------
-- Widgets
-- ---------------------------------------------------------------------------

local slots, toast, railFrame

local function SlotY(index, pitch)
    return -U(Rail.FIRST_DOT + (index - 1) * (pitch or Rail.SPACING))
end

--- A hollow 1px box, DOT x DOT, at the parent's top-left. Four textures rather
-- than a backdrop, because SPEC 1 allows only solid fills and 1px lines and a
-- backdrop brings a border texture with it.
--
-- Built once and used twice, which is the point: SPEC 6 asks for the dot edge
-- to match the "+N more" square, and two separate implementations of "a 1px
-- box" is how they stop matching.
local function HairlineBox(parent, colorName, layer)
    local thickness = Scale.Hairline()
    local edges = {}
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local edge = parent:CreateTexture(nil, layer or "ARTWORK")
        edge:SetColorTexture(Palette.Get(colorName))
        if side == "TOP" or side == "BOTTOM" then
            edge:SetSize(U(Rail.DOT), thickness)
            edge:SetPoint(side .. "LEFT", parent, "TOPLEFT", 0,
                          side == "TOP" and 0 or -U(Rail.DOT))
        else
            edge:SetSize(thickness, U(Rail.DOT))
            edge:SetPoint("TOP" .. side, parent, "TOPLEFT",
                          side == "LEFT" and 0 or U(Rail.DOT), 0)
        end
        edges[side] = edge
    end
    return edges
end

--- Show or hide a box built by HairlineBox.
local function ShowBox(edges, shown)
    for _, edge in pairs(edges) do
        if shown then
            edge:Show()
        else
            edge:Hide()
        end
    end
end

local function BuildSlot(rail, index)
    local slot = CreateFrame("Frame", nil, rail)
    slot:SetSize(U(Rail.DOT) + U(TEXT_GAP) + U(ROW_WIDTH), U(Rail.DOT))
    slot:SetPoint("TOPLEFT", rail, "TOPLEFT", 0, SlotY(index))

    slot.dot = slot:CreateTexture(nil, "ARTWORK")
    slot.dot:SetSize(U(Rail.DOT), U(Rail.DOT))
    slot.dot:SetPoint("TOPLEFT")

    -- SPEC 6 (amended): "Older items are the dot alone at alpha 0.4, each with
    -- a 1px dark edge ... The edge is what keeps a 0.4 dot legible over sand
    -- and firelight." Same rect as the dot, on the layer above it, so the dot
    -- stays the specified 10 x 10 and reads as a bordered square rather than
    -- growing by two pixels.
    --
    -- A SIBLING OF THE DOT, NEVER A CHILD. The amendment is explicit and it is
    -- the whole trick: a child inherits the dot's 0.4 and the edge fades out at
    -- exactly the alpha it was added to rescue. Being a child of the SLOT means
    -- its alpha is its own, and a test asserts the dot's alpha never reaches it.
    slot.edge = HairlineBox(slot, "tickDark", "OVERLAY")

    -- Name and age live in a child frame so their alpha can be animated as a
    -- unit: the row has to fade IN as the toast fades out, or the changeover at
    -- four seconds reads as a blink.
    slot.text = CreateFrame("Frame", nil, slot)
    slot.text:SetAllPoints()

    -- Only the two newest use these, but every slot owns them: creating widgets
    -- when a notification arrives would mean allocating in combat.
    slot.age = ns.Frames.Text(slot.text, 10, "textDim", "RIGHT")
    slot.age:SetPoint("RIGHT", slot.text, "RIGHT", 0, 0)

    -- FOUND IN GAME: "Chunk of Companion Experience" ran straight through the
    -- age and drew on top of it, so the row said neither thing clearly.
    --
    -- SPEC 6 gives the name and the age their fonts and alignment and never
    -- says what happens when one is longer than the row -- the 160-wide row is
    -- our own number (C11). Raised with the designer; truncating is the answer
    -- that changes no position, which SPEC 1 asks for above everything: "Position
    -- is fixed forever -- muscle memory survives because nothing ever moves."
    --
    -- Two anchors give the string a real width, and the RIGHT one is tied to the
    -- AGE rather than to the row, so the name yields to however wide the age
    -- happens to be -- "9s" and "23h" are not the same width. Word wrap off
    -- makes an over-long name end in an ellipsis instead of wrapping into a
    -- second line the 10-unit row has no space for.
    slot.name = ns.Frames.Text(slot.text, 11, "textPrimary", "LEFT")
    slot.name:SetPoint("LEFT", slot.dot, "RIGHT", U(TEXT_GAP), 0)
    slot.name:SetPoint("RIGHT", slot.age, "LEFT", -U(NAME_GAP), 0)
    slot.name:SetWordWrap(false)

    local fade = slot.text:CreateAnimationGroup()
    local alpha = fade:CreateAnimation("Alpha")
    alpha:SetDuration(Rail.TOAST_OUT)
    alpha:SetFromAlpha(0)
    alpha:SetToAlpha(1)
    fade:SetScript("OnFinished", function() slot.text:SetAlpha(1) end)
    slot.fade = fade

    slot:Hide()
    return slot
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
    -- Nothing to collide with here, so the toast gets the whole 200 rather than
    -- the row's 160 -- it is the announcement, and it should say as much of the
    -- name as it can. It still stops at the toast's edge rather than running
    -- across the screen.
    frame.label:SetPoint("RIGHT")
    frame.label:SetWordWrap(false)

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
        frame:SetAlpha(1)
        Rail.toasting = nil
        -- The row has already faded in alongside; this only tidies up.
        Rail.Refresh()
    end)
    frame.collapse = collapse

    -- No mouse. SPEC 8 says a toast ends "after 4s or on dismissal" and never
    -- says the dismissal is a click, so Rail.Collapse still satisfies it --
    -- /myui notify dismiss drives it, and the next notification collapses it
    -- anyway. Dropping the handler leaves the whole rail click-through, which
    -- is worth more than the gesture was: the left edge of the screen stops
    -- eating world clicks entirely, and the click is free for the one thing
    -- that will actually want it, which is opening the notification centre.
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

    -- Age out first, so the pitch below is computed from what will actually be
    -- drawn rather than from what was there a moment ago.
    Rail.Expire(now)
    local pitch = Rail.Pitch()

    for i = 1, Rail.SLOTS do
        local slot, item = slots[i], Rail.items[i]
        if not item then
            slot:Hide()
        else
            slot:Show()
            -- Re-anchored every refresh: the pitch is a function of how many
            -- dots are live, so a slot's position is not fixed at build time.
            slot:ClearAllPoints()
            slot:SetPoint("TOPLEFT", railFrame, "TOPLEFT", 0, SlotY(i, pitch))
            slot.dot:SetColorTexture(Palette.Get(Rail.HUES[item.kind]))

            if i <= Rail.NAMED then
                -- "The two newest items carry name, count and age at rest --
                -- no hover required."
                slot.dot:SetAlpha(1)
                -- No edge. SPEC 6 attaches it to the "older items" line
                -- specifically, and the reason it gives is legibility at 0.4 --
                -- which does not apply to a dot at full alpha. It also leaves
                -- the rail reading as a progression: solid dots for the
                -- newest, outlined ones fading out behind them.
                ShowBox(slot.edge, false)
                slot.name:SetText(Rail.Label(item))
                slot.age:SetText(Rail.FormatAge(now - item.at))

                -- Except while this item is still speaking: the toast is this
                -- row expanded, and drawing both gives you the notification
                -- twice, overlapping itself.
                if i == 1 and Rail.toasting == item then
                    slot.text:Hide()
                else
                    slot.text:Show()
                end
            else
                -- "Older items are the dot alone at alpha 0.4" -- now the
                -- START of a decay rather than a fixed value. Round 5: "Alpha
                -- is the clock. A dot enters at 0.40 and decays to zero over 5
                -- minutes, then leaves."
                --
                -- The two newest keep full alpha rather than joining the
                -- curve: they carry text, and a name fading out is unreadable
                -- long before it is gone. SPEC 6 is unchanged for those.
                slot.dot:SetAlpha(Rail.Fade(now - item.at))
                ShowBox(slot.edge, true)
                slot.name:SetText("")
                slot.age:SetText("")
                slot.text:Hide()
            end
        end
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
    -- Round 5: "A toast is the rail's first row, and the rail is currently a
    -- panel -- so incoming events insert silently at the top instead of
    -- announcing." The item is already added and already logged; only the
    -- announcement is withheld, and only while you are looking at the record.
    if ns.Center and ns.Center.IsOpen and ns.Center.IsOpen() then
        ns.Center.Refresh()
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

    -- Cross-fade, not a swap. The toast and the row it collapses into hold the
    -- same text in the same place, so revealing the row only after the toast
    -- has finished fading leaves a gap where neither is drawn -- which reads as
    -- the text blinking once, four seconds after the notification.
    Rail.Refresh()
    if slots[1] and slots[1]:IsShown() then
        slots[1].text:SetAlpha(0)
        slots[1].fade:Play()
    end
    toast.collapse:Play()
    return true
end

function Rail.IsToasting()
    return Rail.toasting ~= nil
end

--- Is a row's text currently drawn? The dot is separate and always drawn.
function Rail.RowVisible(index)
    local slot = slots and slots[index]
    return slot ~= nil and slot:IsShown() and slot.text:IsShown()
end

--- Put back what is still recent, after a reload.
--
-- The rail lives in memory and the log lives on disk, so before this a reload
-- emptied the rail while the log kept everything -- the display forgot and the
-- record did not. That was survivable when dots sat there forever; with decay
-- it means an idle rail is blank and looks broken.
--
-- The two clocks are different on purpose: the log is dated in epoch seconds
-- so it outlives the session, the rail in GetTime() seconds so it can measure
-- a fade. Ages are carried across rather than timestamps -- how long ago a
-- thing happened is the part that survives a restart.
function Rail.Rehydrate()
    local Log = ns.Log
    if not Log or not Log.db then
        return 0
    end
    local nowEpoch, nowSession = Log.Now(), ns.Reveal.Now()
    local restored = 0

    -- Oldest first, so inserting at the front leaves newest at the top.
    local entries = Log.db.entries
    for i = math.min(#entries, Rail.SLOTS), 1, -1 do
        local e = entries[i]
        local age = nowEpoch - (tonumber(e.at) or 0)
        if age >= 0 and age < Rail.DECAY and Rail.HUES[e.kind] then
            table.insert(Rail.items, 1, {
                kind  = e.kind,
                name  = e.name,
                count = tonumber(e.count) or 1,
                sub   = e.sub,
                at    = nowSession - age,
            })
            restored = restored + 1
        end
    end

    if restored > 0 then
        Rail.Refresh()
    end
    return restored
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
    railFrame = rail

    slots = {}
    for i = 1, Rail.SLOTS do
        slots[i] = BuildSlot(rail, i)
    end
    toast = BuildToast(rail)
    Rail.AnchorToast(0)

    Rail.slots, Rail.toastFrame = slots, toast

    -- Before the first Refresh, and deliberately without toasting: these
    -- already spoke, in a previous session. Putting them back is restoring the
    -- record, not announcing it again.
    Rail.Rehydrate()
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
