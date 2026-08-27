-- MyUI :: Scale.lua
-- The single place SPEC.md's numbers become WoW coordinates.
--
-- SPEC.md gives every coordinate against a mock canvas of 1707 x 960. WoW's
-- virtual screen is 768 units tall at any resolution, and 960 / 768 = 1.25
-- exactly -- the mock is 1.25x the virtual screen in both axes, which is why
-- the conversion is a single clean factor rather than a fit.
--
--     240 mock px  ->  192 units
--     214 mock px  ->  171.2 units
--
-- Every number typed into Frames.lua is the number printed in SPEC.md, wrapped
-- in U(). If this reading of the spec turns out to be wrong, MOCK_TO_UNIT is
-- the one edit.
--
-- "1px" in SPEC.md means one PHYSICAL pixel, not one mock pixel. A hairline
-- scaled by 0.8 would land on 2.4 physical pixels at this machine's 3 px/unit
-- and render as a soft grey smear, which is the opposite of what a flat
-- 1px-geometry design asks for. Hairline() answers that separately.

local ADDON, ns = ...

local Scale = {}
ns.Scale = Scale

local VIRTUAL_HEIGHT = 768
local MOCK_HEIGHT    = 960

Scale.MOCK_TO_UNIT = VIRTUAL_HEIGHT / MOCK_HEIGHT   -- 0.8

--- A SPEC.md coordinate, in UI units.
function Scale.U(mockPx)
    return mockPx * Scale.MOCK_TO_UNIT
end

--- How many physical pixels one UI unit covers, in UIParent's space.
-- Derived from the 768-unit virtual screen invariant. Ported from the Rebar
-- project's Grid.lua, where it was verified by decoding a native 5120x2880
-- screenshot rather than by inspection.
function Scale.PixelsPerUnit()
    local getSize = _G.GetPhysicalScreenSize
    if type(getSize) ~= "function" then
        return nil
    end
    local ok, _, physHeight = pcall(getSize)
    if not ok or type(physHeight) ~= "number" or physHeight <= 0 then
        return nil
    end
    local scale = ns.Compat.Get(_G.UIParent, "GetEffectiveScale")
    if type(scale) ~= "number" or scale <= 0 then
        return nil
    end
    return scale * physHeight / VIRTUAL_HEIGHT
end

--- The thickness, in UI units, of a line exactly one physical pixel wide.
-- Falls back to one unit if the client cannot tell us, which is visible but
-- never zero -- a hairline that rounds to nothing is worse than a thick one.
function Scale.Hairline()
    local perUnit = Scale.PixelsPerUnit()
    if not perUnit then
        return 1
    end
    return 1 / perUnit
end

--- Snap a UI coordinate to the nearest physical pixel boundary.
function Scale.Snap(value)
    local perUnit = Scale.PixelsPerUnit()
    if not perUnit then
        return value
    end
    return math.floor(value * perUnit + 0.5) / perUnit
end

--- True when one UI unit is a whole number of physical pixels, which is the
-- condition for any integer-positioned frame to render crisply. Reported by
-- /myui audit so a blurry UI has an explanation rather than a mystery.
function Scale.IsPixelPerfect()
    local perUnit = Scale.PixelsPerUnit()
    if not perUnit then
        return nil, nil
    end
    return math.abs(perUnit - math.floor(perUnit + 0.5)) < 1e-6, perUnit
end
