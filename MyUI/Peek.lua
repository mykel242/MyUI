-- MyUI :: Peek.lua
-- SPEC.md 4, tap-to-peek: "Reveals for 3s on a visible drain clock, then fades."
--
-- The clock's appearance is the one thing in Phase 2 the spec does not
-- specify. Every element in SPEC.md 2 is given to the pixel; this is named and
-- then left to the implementation. What is built here is the least invented
-- thing that satisfies "visible drain clock" and stays inside SPEC.md 1's flat
-- geometry: a 1px hairline the width of the SelfStack, draining right to left,
-- in a colour already in the palette.
--
-- Its geometry is a guess and is flagged in STATUS for the designer.

local ADDON, ns = ...

local Registry, Scale, Palette = ns.Registry, ns.Scale, ns.Palette

local Peek = {}
ns.Peek = Peek

Peek.DURATION = 3.0   -- SPEC.md 8

local clock, bar

local function BuildClock()
    local stack = Registry.Get("SelfStack")
    if not stack then
        return nil
    end

    clock = CreateFrame("Frame", "MyUIPeekClock", UIParent)
    clock:SetFrameStrata(ns.Frames.STRATA)
    clock:SetSize(Scale.U(240), Scale.Hairline())
    clock:SetPoint("TOPLEFT", stack.frame, "BOTTOMLEFT", 0, -Scale.U(6))

    bar = clock:CreateTexture(nil, "ARTWORK")
    bar:SetColorTexture(Palette.Get("fillDim"))
    bar:SetPoint("TOPLEFT")
    bar:SetPoint("BOTTOMLEFT")
    bar:SetWidth(Scale.U(240))

    clock:Hide()
    return clock
end

--- Reveal everything for DURATION seconds. Tapping again restarts the clock
-- rather than extending it, so the drain always reads as a full run.
function Peek.Start()
    if not Registry.Get("SelfStack") then
        return false
    end
    if not clock then
        BuildClock()
    end
    Peek.until_ = ns.Reveal.Now() + Peek.DURATION
    ns.Reveal.Claim("peek")
    if clock then
        clock:Show()
        bar:SetWidth(Scale.U(240))
    end
    return true
end

function Peek.Stop()
    Peek.until_ = nil
    ns.Reveal.Release("peek")
    if clock then
        clock:Hide()
    end
end

function Peek.IsActive()
    return Peek.until_ ~= nil
end

--- Driven from Reveal's single OnUpdate. RULES.md permits the peek timer there
-- explicitly, and it touches no game state.
function Peek.Update(now)
    if not Peek.until_ then
        return
    end
    local remaining = Peek.until_ - now
    if remaining <= 0 then
        Peek.Stop()
        return
    end
    if bar then
        bar:SetWidth(Scale.U(240) * (remaining / Peek.DURATION))
    end
end

function Peek.Remaining(now)
    if not Peek.until_ then
        return 0
    end
    local left = Peek.until_ - (now or ns.Reveal.Now())
    if left < 0 then
        return 0
    end
    return left
end

-- The keybinding calls this global. Bindings.xml is loaded by the client by
-- FILENAME and must never be listed in the TOC -- listing it sends the same
-- file through the ordinary XML parser as well, which does not know <Binding>
-- and silently rejects every attribute on it. Confirmed in the Rebar project
-- against four Blizzard addons that ship one, none of which lists it.
function MyUI_Peek()
    Peek.Start()
end

_G.BINDING_HEADER_MYUI = "MyUI"
_G.BINDING_NAME_MYUI_PEEK = "Peek at the HUD"
