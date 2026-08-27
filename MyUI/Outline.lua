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
