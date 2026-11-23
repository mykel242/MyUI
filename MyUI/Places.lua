-- MyUI :: Places.lua
-- Mykel, 2026-11-22: "get away from people dragging stuff around and ending
-- up with wildly diverse layouts -- I'd rather this be more constraint
-- oriented ... drag some things out to an edge for THAT character".
--
-- The core of the HUD does not move: your strip, the bar, target, focus, pet,
-- stances. Everything else has a short list of named places. What a character
-- chose is kept for that character and screen size, and only where it differs
-- from the first place in the list.
--
-- Each edge of the screen holds one part: a second is refused, by name.
-- /myui layout shows the boxes; drag one and it snaps to the place for that
-- side of the screen. /myui place does the same in words.

local ADDON, ns = ...

local Places = {}
ns.Places = Places

Places.EDGE = 16        -- SPEC units from the screen's edge
Places.LOW  = 250       -- up from the bottom: over the cooldowns' three rows, which on a
                        -- 16:9 screen reach nearly to the left edge themselves

-- side: the third of the screen a drag must end in. edge: the edge it takes.
local LEFT  = { key = "left",  label = "left edge",  side = "left",  edge = "left" }
local RIGHT = { key = "right", label = "right edge", side = "right", edge = "right" }

-- `layout`: placed through MyUI's Edit Mode layout. `panel`: a summoned panel.
Places.PARTS = {
    { key = "cooldowns", label = "Cooldowns", layout = true,
      places = { { key = "bar", label = "beside the bar", side = "middle" }, LEFT } },
    { key = "debuffs", label = "Debuffs", layout = true,
      places = { { key = "bar", label = "beside the bar", side = "middle" }, RIGHT } },
    { key = "timers", label = "Buff bars", layout = true,
      places = { { key = "cooldowns", label = "above the cooldowns", side = "middle" }, LEFT, RIGHT } },
    { key = "group", label = "Group frames",
      places = { { key = "target", label = "beside the target", side = "middle" }, LEFT, RIGHT } },
    { key = "zone", label = "Zone button", layout = true,
      places = { { key = "bar", label = "on the bar row", side = "middle" }, RIGHT } },
    { key = "tooltip", label = "Tooltip", layout = true, places = { RIGHT, LEFT } },
}
for _, p in ipairs({ { "map", "Map", "right" }, { "quests", "Quests", "right" }, { "social", "Who's online", "right" },
                     { "history", "Notifications", "left" }, { "chat", "Chat", "left" },
                     { "dev", "Debug log", "left" } }) do
    local l = { key = "left", label = "left column", side = "left" }
    local r = { key = "right", label = "right column", side = "right" }
    Places.PARTS[#Places.PARTS + 1] = { key = p[1], label = p[2], panel = true,
                                        places = p[3] == "left" and { l, r } or { r, l } }
end

Places.BY_KEY = {}
for _, part in ipairs(Places.PARTS) do Places.BY_KEY[part.key] = part end

-- The preview's boxes (Layout.PREVIEW), by the part each belongs to.
Places.BOXES = { Essential = "cooldowns", Utility = "cooldowns", BuffIcon = "cooldowns", Debuffs = "debuffs",
                 BuffBars = "timers", Group = "group", ZoneAbility = "zone", Tooltip = "tooltip" }

local function Store(make)
    local db = _G.MyUICharDB
    if type(db) ~= "table" then return nil end
    local size = ns.Clear and ns.Clear.ScreenSize and ns.Clear.ScreenSize()
    local name = size and size.name or "Wide"
    if make then
        db.places = db.places or {}
        db.places[name] = db.places[name] or {}
    end
    return db.places and db.places[name]
end

local function Find(part, place)
    for _, p in ipairs(part.places) do if p.key == place then return p end end
end

--- Where a part is: the place this character chose here, or the first.
function Places.Of(key)
    local part = Places.BY_KEY[key]
    if not part then return nil end
    local s = Store()
    local chosen = s and s[key] and Find(part, s[key])
    return (chosen or part.places[1]).key
end

--- Which part holds an edge, other than `but`.
function Places.Holder(edge, but)
    for _, part in ipairs(Places.PARTS) do
        if part.key ~= but then
            local p = Find(part, Places.Of(part.key))
            if p.edge == edge then return part end
        end
    end
end

--- Put a part in one of its places. Returns the place, and whether anything
-- changed; or nil and why not. Asking twice changes nothing.
function Places.Set(key, place)
    local part = Places.BY_KEY[key]
    if not part then return nil, ("no part %q"):format(tostring(key)) end
    local p = Find(part, place)
    if not p then return nil, ("%s has no place %q"):format(part.label, tostring(place)) end
    if Places.Of(key) == place then return p, false end
    if InCombatLockdown() then return nil, "not in combat" end
    if part.layout and not ns.Clear.IsMyLayout((ns.Clear.ActiveLayoutName())) then
        return nil, "this spec is not on MyUI's layout -- /myui layout use"
    end
    local holder = p.edge and Places.Holder(p.edge, key)
    if holder then
        return nil, ("the %s holds %s -- move that first"):format(p.label, holder.label)
    end
    local s = Store(true)
    if not s then return nil, "no saved data" end
    if place == part.places[1].key then s[key] = nil else s[key] = place end
    Places.Apply(part)
    return p, true
end

--- Everything back to its first place. Returns how many moved.
function Places.Reset()
    if InCombatLockdown() then return nil, "not in combat" end
    local s, n, layout = Store(), 0, false
    for key in pairs(s or {}) do
        local part = Places.BY_KEY[key]
        layout = layout or (part and part.layout) or false
        n = n + 1
    end
    if n == 0 then return 0 end
    if layout and not ns.Clear.IsMyLayout((ns.Clear.ActiveLayoutName())) then
        return nil, "this spec is not on MyUI's layout -- /myui layout use"
    end
    for key in pairs(s) do s[key] = nil end
    Places.Apply({ panel = true })
    Places.Apply({})
    return n
end

function Places.Apply(part)
    if part.panel then
        for key, c in pairs(ns.Summon.all) do
            if Places.BY_KEY[key] then
                c.dock = Places.Of(key)
                if not c.open then ns.Summon.Home(c) end
            end
        end
        ns.Summon.Layout()
        return
    end
    ns.Layout.Apply()
end

--- A placed frame's anchor when it is not in its first place: point,
-- relativePoint, x, y in SPEC units (Layout.Pos asks first). nil otherwise.
Places.KEYS = { Group = "group", ZoneAbility = "zone", Tooltip = "tooltip" }
function Places.Pos(key)
    local part = Places.KEYS[key]
    if not part then return nil end
    local place = Places.Of(part)
    if place == Places.BY_KEY[part].places[1].key then return nil end
    local corner = place == "left" and "BOTTOMLEFT" or "BOTTOMRIGHT"
    return corner, corner, place == "left" and Places.EDGE or -Places.EDGE, Places.LOW
end

--- The place a drag ending at x (0 left, 1 right) means; nil for none there.
function Places.At(key, x)
    local part = Places.BY_KEY[key]
    if not part then return nil end
    local middle
    for _, p in ipairs(part.places) do if p.side == "middle" then middle = p end end
    local side
    if middle then
        side = x < 1 / 3 and "left" or x > 2 / 3 and "right" or "middle"
    else
        side = x < 1 / 2 and "left" or "right"
    end
    for _, p in ipairs(part.places) do if p.side == side then return p.key end end
    return nil
end

--- A preview box was dropped at x. Says what happened; the boxes are put
-- where their parts now are either way.
function Places.Drop(box, x)
    local key = Places.BOXES[box]
    local place = key and Places.At(key, x)
    local ok, why
    if place then
        ok, why = Places.Set(key, place)
        if not ok then ns.Print(why)
        elseif why then ns.Print(("%s: %s"):format(Places.BY_KEY[key].label, ok.label)) end
    elseif key then
        ns.Print(("%s has no place on that side"):format(Places.BY_KEY[key].label))
    end
    ns.Layout.PlaceBoxes()
    return ok and place or nil
end
