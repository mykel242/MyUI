-- MyUI :: Switches.lua
-- Round 005 (Mykel): "myui should probably allow people to turn on and off
-- the myui overrides". Every place MyUI replaces or hides a piece of
-- Blizzard's chrome is one switch here. On (the default) is MyUI's way; off
-- gives that piece back to Blizzard.
--
-- A switch names the adopted frames it covers (Clear.ADOPT names) and, where
-- MyUI draws a replacement, the module that draws it. Alpha-only switches
-- apply at once; the ones that touch protected frames (the action bar, the
-- unit and group frames) apply on /reload.
--
-- /myui override lists them; /myui override <name> on|off flips one.

local ADDON, ns = ...

local Switches = {}
ns.Switches = Switches

-- In the order /myui override lists them. Your pet peeves first.
Switches.LIST = {
    { key = "quests", label = "Quest tracker", mine = "progress as toasts; the list on a key, by kind",
      frames = { "Tracker" } },
    { key = "chat", label = "Chat", mine = "MyUI's chat panel and who's online; toasts for people",
      frames = { "Chat", "ChatDock", "ChatButtons", "ChatSocial" }, reload = true },
    { key = "minimap", label = "Minimap", mine = "hidden; /myui map sets when it shows",
      frames = { "Minimap", "MinimapMap" } },
    { key = "buffs", label = "Buffs and debuffs", mine = "buffs on peek; debuffs beside the bar",
      frames = { "Buffs", "Debuffs" } },
    { key = "castbar", label = "Cast bar", mine = "shown only while casting",
      frames = { "CastBar" } },
    { key = "cooldowns", label = "Cooldown Manager", mine = "beside the bar, with it",
      frames = { "WingCooldowns", "WingUtility", "WingBuffs" } },
    { key = "menu", label = "Menu and bags", mine = "on peek",
      frames = { "MicroMenu", "Bags" } },
    { key = "meter", label = "Damage meter", mine = "on peek",
      frames = { "DamageMeter" } },
    { key = "bars", label = "Action bars", mine = "MyUI's bar: one row, pages on modifiers",
      frames = { "MainBar", "StanceBar" }, reload = true },
    { key = "unitframes", label = "Player, target, focus frames", mine = "MyUI's strips instead",
      units = { "PlayerFrame", "TargetFrame", "FocusFrame" }, reload = true },
    { key = "group", label = "Party and raid frames", mine = "MyUI's group frames",
      units = { "PartyFrame", "CompactPartyFrame", "CompactRaidFrameContainer", "PetFrame" },
      reload = true },
}

Switches.BY_KEY = {}
local byFrame, byUnit = {}, {}
for _, s in ipairs(Switches.LIST) do
    Switches.BY_KEY[s.key] = s
    for _, f in ipairs(s.frames or {}) do byFrame[f] = s.key end
    for _, u in ipairs(s.units or {}) do byUnit[u] = s.key end
end

local function DB()
    if not ns.db then return {} end
    ns.db.switches = ns.db.switches or {}
    return ns.db.switches
end

--- Is this switch on (MyUI's way)? Unknown keys are on.
function Switches.On(key)
    return DB()[key] ~= false
end

--- May Clear adopt this frame (by its Clear.ADOPT name)?
function Switches.Adopts(name)
    local key = byFrame[name]
    return key == nil or Switches.On(key)
end

--- May Clear hide this Blizzard unit or group frame (by global name)?
function Switches.Hides(global)
    local key = byUnit[global]
    return key == nil or Switches.On(key)
end

--- Flip one. Returns the switch and whether it needs a /reload, or nil and
-- a reason.
function Switches.Set(key, on)
    local s = Switches.BY_KEY[key]
    if not s then return nil, ("no switch %q"):format(tostring(key)) end
    on = on and true or false
    if Switches.On(key) == on then return s, false end
    -- Stored only when off ("x and false or nil" is always nil in Lua).
    if on then DB()[key] = nil else DB()[key] = false end
    if s.reload then return s, true end
    -- Giving a frame back always works; taking it again only while
    -- clearing is on (/myui restore turns it all off).
    local C = ns.Clear
    for _, name in ipairs(s.frames or {}) do
        if not on then
            C.ReleaseOne(name)
        elseif C.Enabled() then
            C.AdoptOne(name)
        end
    end
    if key == "quests" and ns.Quests then
        if on then ns.Quests.Enable() else ns.Quests.Disable() end
    end
    return s, false
end
