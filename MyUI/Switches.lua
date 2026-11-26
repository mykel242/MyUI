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
    { key = "quests", yields = { "!KalielsTracker", "ElvUI" }, label = "Quest tracker", mine = "progress as toasts; the list on a key, by kind",
      frames = { "Tracker" } },
    { key = "chat", yields = { "Prat-3.0", "Chattynator", "ElvUI" }, label = "Chat", mine = "MyUI's chat panel in place of Blizzard's",
      frames = { "Chat", "ChatDock", "ChatButtons", "ChatSocial" }, reload = true },
    -- 2026-11-26 (Mykel, Charon): "chat and social should be separated -
    -- chat is a bigger lift to get right but social is very useful already".
    { key = "social", label = "Who's online", mine = "friends and guild online, on a key; a toast as they come on" },
    { key = "minimap", yields = { "SexyMap", "BasicMinimap", "ElvUI" }, label = "Minimap", mine = "out of the corner; the map on a key",
      frames = { "Minimap", "MinimapMap" } },
    { key = "buffs", yields = { "ElvUI" }, label = "Buffs and debuffs", mine = "buffs on peek; debuffs beside the bar",
      frames = { "Buffs", "Debuffs" } },
    { key = "castbar", yields = { "Quartz", "ElvUI" }, label = "Cast bar", mine = "shown only while casting",
      frames = { "CastBar" } },
    { key = "cooldowns", label = "Cooldown Manager", mine = "beside the bar, with it",
      frames = { "WingCooldowns", "WingUtility", "WingBuffs" } },
    { key = "menu", yields = { "Bagnon", "AdiBags", "Baganator", "ElvUI" }, label = "Menu and bags", mine = "on peek",
      frames = { "MicroMenu", "Bags" } },
    { key = "meter", yields = { "Details", "Skada", "Recount" }, label = "Damage meter", mine = "on peek",
      frames = { "DamageMeter" } },
    { key = "bars", yields = { "Bartender4", "Dominos", "ElvUI" }, label = "Action bars", mine = "MyUI's bar: one row, pages on modifiers",
      frames = { "MainBar", "StanceBar" }, reload = true },
    { key = "unitframes", yields = { "ShadowedUnitFrames", "UnhaltedUnitFrames", "PitBull4", "MidnightSimpleUnitFrames", "ElvUI" }, label = "Player, target, focus frames", mine = "MyUI's strips instead",
      units = { "PlayerFrame", "TargetFrame", "FocusFrame" }, reload = true },
    { key = "group", yields = { "Cell", "Grid2", "VuhDo", "ElvUI" }, label = "Party and raid frames", mine = "MyUI's group frames",
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

-- 2026-11-26 (Mykel, Charon): "our chat panel work is too pre-alpha and we
-- should leave blizz chat enabled until later". Off unless turned on.
Switches.DEFAULT_OFF = { chat = true }

-- 2026-11-26 (Mykel: "ensure that MyUI is modular enough that users can
-- disable some or all of it to work with whatever addon build out they
-- feel they require"). A switch lists the addons that already do its job
-- (yields). With one of them loaded, the switch starts off -- MyUI stands
-- down -- unless the player has set it; a notification says so once.
-- Decided once a session (Switches.Standing), so an addon loaded on demand
-- later cannot flip a switch mid-session.

local function Loaded(name)
    local f = _G.C_AddOns and _G.C_AddOns.IsAddOnLoaded or _G.IsAddOnLoaded
    if type(f) ~= "function" then return false end
    local ok, loaded = pcall(f, name)
    return ok and loaded == true
end

--- Which switches stand down this session, and for which addon:
-- { key = addonName }. Worked out on first ask.
function Switches.Standing()
    if Switches.standing then return Switches.standing end
    local out = {}
    for _, s in ipairs(Switches.LIST) do
        for _, name in ipairs(s.yields or {}) do
            if Loaded(name) then out[s.key] = name break end
        end
    end
    -- Kept only once the game says every addon has loaded: asked earlier,
    -- an addon loading after MyUI would be missed for the session.
    local ready = _G.IsLoggedIn
    if type(ready) ~= "function" or ready() then Switches.standing = out end
    return out
end

--- What a switch is when the player has not set it.
function Switches.Default(key)
    if Switches.Standing()[key] then return false end
    return not Switches.DEFAULT_OFF[key]
end

--- Is this switch on (MyUI's way)? Unknown keys are on.
function Switches.On(key)
    local v = DB()[key]
    if v == nil then return Switches.Default(key) end
    return v == true
end

--- Say once, per addon and switch, that MyUI stood down.
function Switches.Announce()
    if not ns.db then return {} end
    ns.db.stoodDown = ns.db.stoodDown or {}
    local said = {}
    for key, addon in pairs(Switches.Standing()) do
        local s = Switches.BY_KEY[key]
        if DB()[key] == nil and ns.db.stoodDown[key] ~= addon then
            ns.db.stoodDown[key] = addon
            said[#said + 1] = key
            if ns.Toast and ns.Toast.Add then
                pcall(ns.Toast.Add, "blue", ("%s is loaded: MyUI's %s is off"):format(addon, s.label:lower()))
            end
        end
    end
    return said
end

function Switches.OnLogin()
    -- After the toasts exist, and a moment in, so it is seen.
    C_Timer.After(3, Switches.Announce)
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
    -- Stored only when it differs from the default (standing down included).
    if on == Switches.Default(key) then DB()[key] = nil else DB()[key] = on end
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
    if key == "social" and not on and ns.Social and ns.Social.open then
        ns.Social.summon:Close("asked")
    end
    if key == "quests" and ns.Quests then
        if on then ns.Quests.Enable() else ns.Quests.Disable() end
    end
    return s, false
end
