-- MyUI_Test :: SuitesRebar.lua
-- Rebar's TESTING-PHASE0-3.md as suites, for the parts that need no hands.
--
-- Rebar is folded into MyUI in R4; until then it is a separate addon and this
-- suite skips itself when Rebar is not loaded. It is never a dependency.
--
-- Not automated, and why: hovering frames for the inspector (Phase 2) and
-- dragging to snap (Phase 3) need a real cursor, and nothing here moves one.
-- Phase 0's report is text: its commands run and must not error, and the
-- output is read from RebarDB rather than from a screenshot.

local ADDON, T = ...

local saved

local function Grid()
    return _G.RebarGrid
end

local function GridShown()
    local g = Grid()
    return g ~= nil and g:IsShown()
end

local function GridOff(api)
    if GridShown() then api.rebar("grid") end
end

-- Runs a command and reports whether it raised. Rebar's own dispatcher prints
-- errors rather than raising, so a clean pcall is necessary, not sufficient;
-- the shot or the saved output carries the rest.
local function Runs(api, text)
    local ok, err = pcall(api.rebar, text)
    if not ok then return false, tostring(err) end
    return true, "/rebar " .. text .. " ran"
end

T.Suite("rebar", {
    title = "Rebar -- grid and read-only reports",
    requires = function(api)
        if not api.loaded("Rebar") then return false, "Rebar is not loaded" end
        return true
    end,
    before = function(api)
        local db = _G.RebarDB
        local g = db and db.grid or {}
        saved = { shown = GridShown(), divisions = g.divisions, border = g.borderPixels }
        GridOff(api)
        -- The harness quiets the grid for every other suite; raise it here.
        if Grid() then Grid():SetAlpha(1) end
    end,
    after = function(api)
        GridOff(api)
        if Grid() then Grid():SetAlpha(0) end   -- the harness restores it at the end
        if not saved then return end
        -- Put the live grid back (Rebar's defaults are 16 divisions and a 3px
        -- border when nothing was saved)...
        api.rebar("grid border " .. (saved.border or 3))
        api.rebar("grid " .. (saved.divisions or 16))   -- shows it
        if not saved.shown then GridOff(api) end
        -- ...and the saved settings exactly as found, including "never set".
        -- The first in-game run left borderPixels = 1 behind; this is why.
        local g = _G.RebarDB and _G.RebarDB.grid
        if g then
            g.borderPixels, g.divisions, g.shown = saved.border, saved.divisions, saved.shown
        end
    end,
    tests = {
        { id = "grid-16",
          what = "16 divisions: single-pixel interior lines, 3px gold border flush with "
              .. "the usable rect, readout at the top saying pixel-perfect in green.",
          setup = function(api) GridOff(api); api.rebar("grid border 3"); api.rebar("grid 16") end,
          frames = { "RebarGrid" },
          check = function()
              return GridShown(), GridShown() and "grid shown" or "grid not shown"
          end },

        { id = "grid-12",
          what = "12 divisions: the cell readout shows the width in amber and suggests "
              .. "a better count.",
          setup = function(api) api.rebar("grid 12") end,
          frames = { "RebarGrid" } },

        { id = "grid-border-1",
          what = "16 divisions with a one-pixel border.",
          setup = function(api) api.rebar("grid 16"); api.rebar("grid border 1") end,
          frames = { "RebarGrid" } },

        { id = "grid-off",
          what = "Grid toggled off: no lines, no readout, no dimming left behind.",
          setup = function(api) GridOff(api) end,
          frames = { "RebarGrid" },
          check = function()
              return not GridShown(), GridShown() and "still shown" or "hidden"
          end },

        { id = "viewport", shot = false,
          what = "/rebar viewport prints without error.",
          check = function(api) return Runs(api, "viewport") end },

        { id = "find-minimap", shot = false,
          what = "/rebar find MinimapCluster prints without error.",
          check = function(api) return Runs(api, "find MinimapCluster") end },

        { id = "blocked", shot = false,
          what = "/rebar blocked lists refusals with reasons, without error.",
          check = function(api) return Runs(api, "blocked") end },
    },
})
