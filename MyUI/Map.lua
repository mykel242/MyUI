-- MyUI :: Map.lua
-- Round 005 (Mykel: "we need the map"; SPEC 22, "the map on a key"). The
-- corner minimap stays out of the way (the "minimap" switch); a key brings a
-- big map up over the world, top centre, and puts it away again.
--
-- It is Blizzard's own minimap render -- the terrain, your arrow, the quest
-- blips, the gathering nodes, the addon buttons on its edge -- moved into a
-- summoned panel (Summon.lua: pin, close, gone by itself when you are done)
-- and zoomed out, then handed back to its corner when it closes. Nothing is
-- drawn by MyUI but the panel: the zone and where you are in the header, the
-- world map one click away in the footer. The mouse wheel zooms, a click
-- pings, as on the minimap.
--
-- Minimap is not a protected frame; moving it is ordinary addon work. Your
-- position can be restricted in instances: then the header says the zone
-- alone.

local ADDON, ns = ...

local Scale, Palette = ns.Scale, ns.Palette
local U = function(v) return Scale.U(v) end

local Map = {}
ns.Map = Map

Map.WIDTH = 420         -- wider than the docked panels: it is a map
Map.TOP   = -28         -- with the dock columns, under the status bars
Map.ALPHA = 0.85        -- the world shows through a little
Map.TICK  = 0.5

local function API(path, ...) return ns.Sources.API(path, ...) end

local panel

--- Where you are, as "Zone  41.2, 63.8"; the zone alone when the client
-- will not say (instances).
function Map.Where()
    local zone = API("GetMinimapZoneText")
    zone = type(zone) == "string" and not ns.Compat.IsSecret(zone) and zone or ""
    local id = API("C_Map.GetBestMapForUnit", "player")
    local pos = id and API("C_Map.GetPlayerMapPosition", id, "player")
    if type(pos) == "table" and pos.GetXY then
        local ok, x, y = pcall(pos.GetXY, pos)
        if ok and type(x) == "number" and type(y) == "number"
           and not ns.Compat.IsSecret(x) and not ns.Compat.IsSecret(y) then
            return zone, ("%.1f, %.1f"):format(x * 100, y * 100)
        end
    end
    return zone, nil
end

local function Size()
    return U(Map.WIDTH - 2 * ns.Summon.PAD)
end

function Map.Build()
    if panel then return panel end
    local S = ns.Summon
    panel = CreateFrame("Frame", "MyUIMap", UIParent)
    panel:SetFrameStrata("DIALOG")
    panel:SetSize(U(Map.WIDTH), S.Top(false) + Size() + U(4) + U(S.FOOTER_H) + U(4))
    panel:SetPoint("TOP", UIParent, "TOP", 0, U(Map.TOP))
    local header = S.Chrome(panel, "Map")
    -- The world through the map's square, not a dark board.
    panel.__surface.bg:SetAlpha(0.45)
    panel.where = ns.Frames.Text(panel, 10, "textDim", "RIGHT")
    panel.where:SetPoint("RIGHT", header.pin, "LEFT", -U(12), 0)
    panel.area = CreateFrame("Frame", nil, panel)
    panel.area:SetSize(Size(), Size())
    panel.area:SetPoint("TOP", panel, "TOP", 0, -S.Top(false))
    S.Footer(panel, "world map", function() Map.WorldMap() end, nil)
    panel:Hide()
    Map.panel = panel
    Map.summon = S.Attach({
        key = "map", frame = panel, header = header,
        show = function() return Map.Show() end,
        hide = function() Map.Hide() end,
    })
    panel:HookScript("OnHide", function() if Map.summon.open then Map.summon.open = false end end)
    S.Mouse(panel, false)
    return panel
end

function Map.Paint()
    if not panel then return end
    local zone, coords = Map.Where()
    panel.__header.title:SetText(zone ~= "" and zone or "Map")
    panel.where:SetText(coords or "")
end

--- Take Blizzard's minimap into the panel, big and zoomed out.
function Map.Show()
    local mm = _G.Minimap
    if type(mm) ~= "table" then return false end
    if not Map.home then
        Map.home = { parent = mm:GetParent(), points = {}, w = mm:GetWidth(), h = mm:GetHeight(),
                     zoom = mm.GetZoom and mm:GetZoom() or 0 }
        for i = 1, (mm.GetNumPoints and mm:GetNumPoints() or 0) do
            Map.home.points[i] = { mm:GetPoint(i) }
        end
    end
    panel:Show()
    mm:SetParent(panel.area)
    mm:ClearAllPoints()
    mm:SetPoint("CENTER", panel.area, "CENTER", 0, 0)
    mm:SetSize(Size(), Size())
    if mm.SetZoom then mm:SetZoom(0) end
    Map.open = true
    -- The minimap is adopted at rest (Clear: hidden, hideAtZero); this
    -- channel holds it up while the map is out.
    if ns.Registry.Get("MinimapMap") then ns.Reveal.Claim("map") end
    if mm.SetAlpha and not ns.Registry.Get("MinimapMap") then mm:SetAlpha(Map.ALPHA) end
    ns.Summon.Mouse(panel, true)
    Map.Paint()
    local function tick()
        if not Map.open then return end
        Map.Paint()
        C_Timer.After(Map.TICK, tick)
    end
    C_Timer.After(Map.TICK, tick)
    return true
end

--- Hand it back to its corner, as it was.
function Map.Hide()
    Map.open = false
    ns.Reveal.Release("map")
    local mm, home = _G.Minimap, Map.home
    if type(mm) == "table" and home then
        mm:SetParent(home.parent)
        mm:ClearAllPoints()
        for _, p in ipairs(home.points) do mm:SetPoint(p[1], p[2], p[3], p[4], p[5]) end
        mm:SetSize(home.w, home.h)
        if mm.SetZoom then mm:SetZoom(home.zoom or 0) end
    end
    Map.home = nil
    ns.Summon.Mouse(panel, false)
    panel:Hide()
end

--- Blizzard's world map, out of combat.
function Map.WorldMap()
    if InCombatLockdown() then return "combat" end
    if type(_G.ToggleWorldMap) == "function" then
        pcall(_G.ToggleWorldMap)
        return "world"
    end
    return nil
end

function Map.Toggle()
    Map.Build()
    if Map.open then Map.summon:Close("asked") return false end
    return Map.summon:Open()
end

function Map.Active()
    return Map.enabled == true
end

function Map.OnLogin()
    if ns.Switches and not ns.Switches.On("minimap") then return end
    Map.enabled = true
    Map.Build()
end

function _G.MyUI_Map()
    if not Map.Active() then
        ns.Print("the map is off with the minimap switch -- /myui override minimap on")
        return
    end
    Map.Toggle()
end
_G.BINDING_NAME_MYUI_MAP = "Show the map"
