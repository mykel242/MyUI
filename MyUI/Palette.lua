-- MyUI :: Palette.lua
-- SPEC.md 7, complete and closed.
--
-- "Thirteen colours, all RGBA float. Nothing outside this list." The handoff is
-- explicit that the addon must not introduce a fourteenth, so this table is the
-- whole vocabulary and a test asserts its size. Curve intermediates from
-- SPEC.md 3 are interpolation stops, not palette entries, and live in Frames.
--
-- THIRTEEN, NOT FOURTEEN, since the amended SPEC 7. Text secondary and text
-- tertiary were rgba(173,177,184,1) and rgba(115,119,126,1); the tertiary value
-- tested unreadable over ordinary terrain and the amendment lifts it to the
-- secondary one -- at which point the two entries are the same colour, so they
-- collapse into a single textDim. They never appeared in the same row, so the
-- two-tier hierarchy was notional and nothing is lost.
--
-- rgba(115,119,126,1) is no longer a palette entry at all. It survives only as
-- the /myui contrast normal debug affordance in Frames.lua, which is the one
-- place in the addon that draws a colour this table does not hold.

local ADDON, ns = ...

local Palette = {}
ns.Palette = Palette

--- SPEC.md writes colours as 0-255 RGB with float alpha; WoW wants 0-1 floats.
local function rgba(r, g, b, a)
    return { r / 255, g / 255, b / 255, a }
end

Palette.colors = {
    fill           = rgba(240, 241, 243, 0.92),   -- Fill / primary
    textPrimary    = rgba(240, 241, 243, 1),
    textDim        = rgba(173, 177, 184, 1),
    trough         = rgba(255, 255, 255, 0.14),
    fillDim        = rgba(255, 255, 255, 0.25),
    tickDark       = rgba(0, 0, 0, 0.55),
    danger         = rgba(242, 107, 97, 1),
    resource       = rgba(140, 211, 255, 1),      -- Resource accent
    notifBlue      = rgba(140, 200, 255, 1),
    notifAmber     = rgba(255, 209, 89, 1),
    notifGreen     = rgba(166, 217, 140, 1),
    notifViolet    = rgba(209, 179, 255, 1),
    notifOrange    = rgba(242, 158, 115, 1),
}

Palette.COUNT = 13

--- Unpack a palette entry for a SetColorTexture or SetVertexColor call.
function Palette.Get(name)
    local c = Palette.colors[name]
    if not c then
        error(("no palette colour %q -- SPEC.md 7 is closed at %d")
              :format(tostring(name), Palette.COUNT), 2)
    end
    return c[1], c[2], c[3], c[4]
end
