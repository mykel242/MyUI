-- MyUI :: Outline.lua
-- A diagnostic, not a feature.
--
-- Phase 1's acceptance asks whether frames are where SPEC.md says, and the
-- offline suite cannot answer that -- it only knows what we asked for, not what
-- the client drew. When a frame does not appear there are two very different
-- causes and they look identical: it is in the wrong place, or it is in the
-- right place behind something else.
--
-- This draws a bright, opaque box at TOOLTIP strata around every registered
-- frame, with its name. If the box is where the spec says and the frame is not
-- visible inside it, the geometry is right and the problem is z-order or
-- contrast. That is the whole job.
--
-- SPEC.md 9's edit mode is a real feature with a grid, sliders and preview-at-
-- rest, and it is Phase 5. This is deliberately none of those.

local ADDON, ns = ...

local Registry, Scale = ns.Registry, ns.Scale

local Outline = {}
ns.Outline = Outline

local boxes = {}

-- Not from SPEC.md 7. The palette is the HUD's vocabulary and this is a tool
-- that must be unmistakably not the HUD, so it uses a colour the design does
-- not contain and could never be confused with.
local EDGE = { 0.2, 1.0, 0.4, 0.9 }

local function BuildBox(entry)
    local box = CreateFrame("Frame", nil, UIParent)
    box:SetFrameStrata("TOOLTIP")
    box:SetAllPoints(entry.frame)

    local thickness = Scale.Hairline()
    box.edges = {}
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local edge = box:CreateTexture(nil, "OVERLAY")
        edge:SetColorTexture(EDGE[1], EDGE[2], EDGE[3], EDGE[4])
        if side == "TOP" or side == "BOTTOM" then
            edge:SetHeight(thickness)
            edge:SetPoint(side .. "LEFT")
            edge:SetPoint(side .. "RIGHT")
        else
            edge:SetWidth(thickness)
            edge:SetPoint("TOP" .. side)
            edge:SetPoint("BOTTOM" .. side)
        end
        box.edges[side] = edge
    end

    box.label = box:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    box.label:SetPoint("BOTTOMLEFT", box, "TOPLEFT", 0, 2)
    box.label:SetText(("%s  rest %.2f"):format(entry.name, entry.resting))

    return box
end

--- Show or hide the diagnostic boxes. Returns the new state.
function Outline.Toggle(on)
    if on == nil then
        on = not Outline.shown
    end
    Outline.shown = on

    Registry.Each(function(entry)
        -- MyUI's own frames only. Adopted Blizzard frames (R3b) are not
        -- MyUI's geometry, and their labels landed inside MyUI's boxes.
        if ns.Clear and ns.Clear.IsAdopted(entry.name) then
            if boxes[entry.name] then boxes[entry.name]:Hide() end
            return
        end
        local box = boxes[entry.name]
        if not box then
            box = BuildBox(entry)
            boxes[entry.name] = box
        end
        if on then
            box:Show()
        else
            box:Hide()
        end
    end)

    return Outline.shown
end

function Outline.IsShown()
    return Outline.shown == true
end

-- ---------------------------------------------------------------------------
-- What is that thing
-- ---------------------------------------------------------------------------
-- Same reason as the boxes above: the offline suite knows what WE drew and
-- nothing about what the client put next to it. Something appeared along the
-- left edge that the design never accounted for, and naming it from a
-- screenshot is guesswork -- this asks the client.
--
-- A binding rather than a command, because you cannot hover a thing and type
-- at the same time.

local function Describe(region)
    if type(region) ~= "table" then
        return nil
    end
    local name = (type(region.GetName) == "function" and region:GetName()) or "<unnamed>"
    local kind = (type(region.GetObjectType) == "function" and region:GetObjectType()) or "?"
    local w, h = 0, 0
    if type(region.GetSize) == "function" then
        local ok, a, b = pcall(region.GetSize, region)
        if ok then w, h = a or 0, b or 0 end
    end
    local strata = (type(region.GetFrameStrata) == "function" and region:GetFrameStrata()) or "-"
    return ("%s  (%s, %dx%d, %s)"):format(name, kind, math.floor(w), math.floor(h), tostring(strata))
end

local function Ancestry(region, depth)
    local out, seen = {}, 0
    local cur = region
    while cur and seen < (depth or 4) do
        if type(cur.GetParent) ~= "function" then break end
        cur = cur:GetParent()
        if not cur then break end
        out[#out + 1] = (type(cur.GetName) == "function" and cur:GetName()) or "<unnamed>"
        seen = seen + 1
    end
    return out
end

--- Name whatever is under the cursor.
function Outline.Under()
    -- 12.1 replaced GetMouseFocus with GetMouseFoci, which returns a list:
    -- several regions can be under one pixel, and the top one is not always
    -- the interesting one.
    local foci
    if type(_G.GetMouseFoci) == "function" then
        local ok, result = pcall(_G.GetMouseFoci)
        if ok then
            foci = type(result) == "table" and result or { result }
        end
    end
    if not foci and type(_G.GetMouseFocus) == "function" then
        local ok, result = pcall(_G.GetMouseFocus)
        if ok and result then foci = { result } end
    end

    if not foci or #foci == 0 then
        ns.Print("nothing under the cursor takes the mouse.")
        ns.Raw("  Which is itself an answer: a frame that ignores the mouse is "
               .. "not clickable, so it is decoration or it belongs to the world.")
        return {}
    end

    ns.Print(("%d thing(s) under the cursor, nearest first"):format(#foci))
    local named = {}
    for i, region in ipairs(foci) do
        local line = Describe(region)
        if line then
            named[#named + 1] = line
            ns.Raw("  " .. line)
            local up = Ancestry(region, 3)
            if #up > 0 then
                ns.Raw("      inside " .. table.concat(up, " < "))
            end
        end
    end
    return named
end

function MyUI_What()
    Outline.Under()
end

_G.BINDING_NAME_MYUI_WHAT = "Name what is under the cursor"

