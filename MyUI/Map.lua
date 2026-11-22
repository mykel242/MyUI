-- MyUI :: Map.lua
-- Round 005 (Mykel: "we need the map"; SPEC 22, "the map on a key"). The
-- corner minimap stays out of the way (the "minimap" switch); a key brings a
-- big map up over the world, top centre, and puts it away again.
--
-- It is Blizzard's own minimap render -- the terrain, your arrow, the quest
-- blips, the gathering nodes, the addon buttons on its edge -- moved into a
-- summoned panel (Summon.lua: pin, close, gone by itself when you are done)
-- at the zoom you left it, then handed back to its corner when it closes. Nothing is
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

-- Round 005 play: "put the map at the top of the right stack and match the
-- width" -- docked first on the right, the panels' one width.
Map.WIDTH = ns.Summon.WIDTH
Map.ALPHA = 0.85        -- the world shows through a little
Map.TICK  = 0.5

local function API(path, ...) return ns.Sources.API(path, ...) end

local panel

-- Round 005 play: "let's do something better with the addon markers". In
-- the map the minimap's furniture -- its ring and compass, the zoom
-- buttons, the landing-page orb, every addon's button round the edge --
-- stayed at corner size, scattered over the big map. While the map is out:
-- the map is square (the panel's grid), the ring and zoom buttons go (the
-- wheel zooms), and the buttons line up in a row in the footer, small, on
-- the right. All of it goes back when the map closes.
Map.BUTTON  = 18        -- a gathered button, square
Map.SQUARE_MASK = "Interface\\Buttons\\WHITE8X8"
Map.ROUND_MASK  = "Interface\\Masks\\CircleMaskScalable"

--- The buttons to gather: every addon button on the minimap's edge, and
-- Blizzard's landing-page orb. Not the zoom buttons (hidden instead).
--- Addon buttons made by LibDBIcon (BugSack and most others): name ->
-- button. These are not moved -- the library keeps putting them back round
-- the minimap -- but stood in for (Map.Proxy). Found by what they are (a
-- minimap child carrying its broker object), not through the library:
-- MyUI depends on nothing but Blizzard (RULES).
function Map.LibButtons()
    local mm = _G.Minimap
    local out = {}
    if not (mm and mm.GetChildren) then return out end
    for _, kid in ipairs({ mm:GetChildren() }) do
        local name = kid.GetName and kid:GetName()
        local hidden = type(kid.db) == "table" and kid.db.hide
        if type(kid.dataObject) == "table" and type(name) == "string" and not hidden then
            out[(name:gsub("^LibDBIcon%d*_", ""))] = kid
        end
    end
    return out
end

function Map.Buttons()
    local mm = _G.Minimap
    local out, seen = {}, {}
    local skip = {}
    if mm then skip[mm.ZoomIn or 0] = true; skip[mm.ZoomOut or 0] = true end
    for _, b in pairs(Map.LibButtons()) do skip[b] = true end
    local function add(b)
        if b and not seen[b] and not skip[b] and b.IsShown and b:IsShown() then
            seen[b] = true
            out[#out + 1] = b
        end
    end
    for _, kid in ipairs({ mm and mm.GetChildren and mm:GetChildren() }) do
        if kid.GetObjectType and kid:GetObjectType() == "Button" then add(kid) end
    end
    add(_G.ExpansionLandingPageMinimapButton)
    return out
end

local function Keep(f)
    local k = { frame = f, parent = f:GetParent(), w = f:GetWidth(), h = f:GetHeight(), points = {},
                alpha = f.GetAlpha and f:GetAlpha() or 1, mouse = f.IsMouseEnabled and f:IsMouseEnabled(),
                strata = f.GetFrameStrata and f:GetFrameStrata(), level = f.GetFrameLevel and f:GetFrameLevel(),
                shown = f.IsShown and f:IsShown() }
    if f.GetHitRectInsets then k.insets = { f:GetHitRectInsets() } end
    for i = 1, (f.GetNumPoints and f:GetNumPoints() or 0) do k.points[i] = { f:GetPoint(i) } end
    return k
end

local function Put(k)
    local f = k.frame
    f:SetParent(k.parent)
    f:ClearAllPoints()
    for _, p in ipairs(k.points) do f:SetPoint(p[1], p[2], p[3], p[4], p[5]) end
    f:SetSize(k.w, k.h)
    if f.SetAlpha then f:SetAlpha(k.alpha or 1) end
    if k.mouse ~= nil and f.EnableMouse then f:EnableMouse(k.mouse) end
    if k.strata and f.SetFrameStrata then f:SetFrameStrata(k.strata) end
    if k.level and f.SetFrameLevel then f:SetFrameLevel(k.level) end
    if k.insets and f.SetHitRectInsets and #k.insets == 4 then f:SetHitRectInsets(unpack(k.insets)) end
    if k.shown and f.Show and not f:IsShown() then f:Show() end
end

-- A stand-in for a LibDBIcon button: its broker object's icon, click and
-- tooltip, on a small button of MyUI's own.
Map.proxies = {}
function Map.Proxy(name, original)
    local p = Map.proxies[name]
    local data = original.dataObject
    if not p then
        p = CreateFrame("Button", nil, panel)
        p:RegisterForClicks("AnyUp")
        p.icon = p:CreateTexture(nil, "ARTWORK")
        p.icon:SetAllPoints()
        ns.Frames.HoverEdge(p, 2)
        p:SetScript("OnClick", function(self, button)
            local d = self.dataObject
            if d and type(d.OnClick) == "function" then pcall(d.OnClick, self, button) end
        end)
        p:SetScript("OnEnter", function(self)
            local d, tip = self.dataObject, _G.GameTooltip
            if not d then return end
            if type(d.OnTooltipShow) == "function" and tip then
                tip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
                pcall(d.OnTooltipShow, tip)
                tip:Show()
            elseif type(d.OnEnter) == "function" then
                pcall(d.OnEnter, self)
            end
        end)
        p:SetScript("OnLeave", function(self)
            local d, tip = self.dataObject, _G.GameTooltip
            if d and type(d.OnLeave) == "function" then pcall(d.OnLeave, self) end
            if tip and tip.IsOwned and tip:IsOwned(self) then tip:Hide() end
        end)
        Map.proxies[name] = p
    end
    p.dataObject = data
    p.icon:SetTexture(data.icon)
    if data.iconCoords and p.icon.SetTexCoord then p.icon:SetTexCoord(unpack(data.iconCoords)) end
    ns.Summon.Depth(p, 10)
    return p
end

--- Line the buttons up in the footer, right to left; remember where each was.
function Map.Gather()
    Map.kept = {}
    local x = 0
    local function Place(b)
        b:ClearAllPoints()
        b:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -U(ns.Summon.PAD) - x, U(6))
        b:SetSize(U(Map.BUTTON), U(Map.BUTTON))
        b:Show()
        x = x + U(Map.BUTTON + 4)
    end
    -- LibDBIcon's: hidden where they are, stood in for in the row.
    local names = {}
    for name in pairs(Map.LibButtons()) do names[#names + 1] = name end
    table.sort(names)
    local lib = Map.LibButtons()
    for _, name in ipairs(names) do
        local b = lib[name]
        Map.kept[#Map.kept + 1] = Keep(b)
        b:Hide()
        Place(Map.Proxy(name, b))
    end
    -- Everything else (Blizzard's landing-page orb, other addons'): moved
    -- into the row. Round 005 play: they were behind the panel (their own
    -- strata) and the orb's hit area was its 53 px one, inset to nothing at
    -- this size -- so strata, level and hit area come too.
    for _, b in ipairs(Map.Buttons()) do
        Map.kept[#Map.kept + 1] = Keep(b)
        b:SetParent(panel)
        if b.SetFrameStrata and b.SetFrameLevel then ns.Summon.Depth(b, 10) end
        if b.SetHitRectInsets then b:SetHitRectInsets(0, 0, 0, 0) end
        Place(b)
    end
    -- The furniture that only fits the corner.
    local mm = _G.Minimap
    local furniture = { _G.MinimapBackdrop, mm and mm.ZoomIn, mm and mm.ZoomOut, mm and mm.ZoomHitArea }
    for i = 1, 4 do   -- not ipairs: any of them may be missing
        local f = furniture[i]
        if f then
            Map.kept[#Map.kept + 1] = Keep(f)
            f:SetAlpha(0)
            if f.EnableMouse then f:EnableMouse(false) end
        end
    end
    if mm and mm.SetMaskTexture then mm:SetMaskTexture(Map.SQUARE_MASK) end
    return #Map.kept
end

function Map.Scatter()
    for _, p in pairs(Map.proxies) do p:Hide() end
    for i = #(Map.kept or {}), 1, -1 do Put(Map.kept[i]) end
    Map.kept = nil
    local mm = _G.Minimap
    if mm and mm.SetMaskTexture then mm:SetMaskTexture(Map.ROUND_MASK) end
end

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
    ns.Summon.Depth(panel)
    panel:SetSize(U(Map.WIDTH), S.Top(false) + Size() + U(4) + U(S.FOOTER_H) + U(4))
    local d = S.DOCK.right
    panel:SetPoint(d.point, UIParent, d.point, U(d.x), U(d.y))
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
        key = "map", frame = panel, header = header, dock = "right", order = 0,
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

--- Take Blizzard's minimap into the panel, big. Its zoom is the player's:
-- the client saves it (minimapZoom), and a pinned map opened at every login.
function Map.Show()
    local mm = _G.Minimap
    if type(mm) ~= "table" then return false end
    if not Map.home then
        Map.home = { parent = mm:GetParent(), points = {}, w = mm:GetWidth(), h = mm:GetHeight() }
        for i = 1, (mm.GetNumPoints and mm:GetNumPoints() or 0) do
            Map.home.points[i] = { mm:GetPoint(i) }
        end
    end
    panel:Show()
    mm:SetParent(panel.area)
    mm:ClearAllPoints()
    mm:SetPoint("CENTER", panel.area, "CENTER", 0, 0)
    mm:SetSize(Size(), Size())
    Map.Gather()
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
    Map.Scatter()
    local mm, home = _G.Minimap, Map.home
    if type(mm) == "table" and home then
        mm:SetParent(home.parent)
        mm:ClearAllPoints()
        for _, p in ipairs(home.points) do mm:SetPoint(p[1], p[2], p[3], p[4], p[5]) end
        mm:SetSize(home.w, home.h)
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
