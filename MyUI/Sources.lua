-- MyUI :: Sources.lua
-- SPEC.md 6, "What feeds the rail". Seven sources, five hues.
--
-- Phase 3 shipped /myui notify as the source and flagged the real ones as an
-- open design question (C1). The amendment answers it with an event table, and
-- this is that table wired up. /myui notify stays -- the acceptance test needs
-- eight notifications on demand and no real source can be made to fire eight
-- times in a row.
--
-- NOTHING IN THIS FILE IS PROTECTED, AND THAT IS WORTH SAYING OUT LOUD.
-- RULES.md governs unit and cooldown values. Item quality, free bag slots,
-- durability percentages and mail flags are ordinary Lua, and the amended
-- RULES says so explicitly because over-applying the rules produces worse code
-- rather than safer code. So this file compares and filters freely. The one
-- standing constraint is the last line of SPEC 6's table: no source may be
-- added that reads a unit value. If one ever needs to, it does not belong here.
--
-- The hues are not one-per-source. Four of them mean SOMETHING HAPPENED; orange
-- means SOMETHING WANTS YOU.

local ADDON, ns = ...

local Sources = {}
ns.Sources = Sources

-- ---------------------------------------------------------------------------
-- Defensive API access
-- ---------------------------------------------------------------------------
-- Every reader below goes through this, and the reason is on the record: on
-- 12.1 a misremembered API name returns nil in the game while every offline
-- test passes, because the mock encodes the same wrong assumption. That has
-- happened three times on this project, C_CurveUtil being the last.
--
-- The events SPEC 6 names are stable and cheap to trust. The readers that turn
-- an event into a NAME are not all APIs this project has run. So a source whose
-- API is missing goes quiet -- it still posts the row, with a fallback name --
-- instead of erroring on login and taking the rest of the addon with it.

--- Call a global or namespaced function if it exists. Returns nil if it does
-- not, or if it throws.
local function API(path, ...)
    local fn = _G
    for part in path:gmatch("[^.]+") do
        if type(fn) ~= "table" then
            return nil
        end
        fn = fn[part]
    end
    if type(fn) ~= "function" then
        return nil
    end
    local ok, a, b, c = pcall(fn, ...)
    if not ok then
        return nil
    end
    return a, b, c
end

Sources.API = API

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------
-- SPEC 6: "Defaults -- loot at uncommon and above; durability at 20%; bag
-- notice at zero free slots. All three are saved variables."

Sources.DEFAULTS = {
    lootQuality = 2,      -- Enum.ItemQuality.Uncommon
    durability  = 0.20,
    bagFree     = 0,
}

function Sources.Setting(name)
    local db = ns.db and ns.db.sources
    if db and type(db[name]) == "number" then
        return db[name]
    end
    return Sources.DEFAULTS[name]
end

-- ---------------------------------------------------------------------------
-- The stream rule
-- ---------------------------------------------------------------------------
-- SPEC 6: "one row per event, never a stream (a full bag says so once, not on
-- every BAG_UPDATE)".
--
-- Two different mechanisms, because there are two different shapes of noise:
--
--   LATCH -- for a CONDITION. Bag full, low durability and pending mail are
--   states, not events, and their events fire whenever anything in the bag,
--   the gear or the mailbox changes. A latch speaks on the way in and stays
--   quiet until the condition clears, so a full bag says so once.
--
--   BURST -- for an EVENT that arrives in streams. Currency and reputation
--   fire over and over for one action, so the first after a quiet stretch
--   speaks and the rest refresh the dot it already owns. Every one is logged.
--
-- There used to be a third, a plain COALESCE window, and it existed for one
-- source: quest objectives. UNIT_QUEST_LOG_CHANGED fires several times for one
-- objective advancing and carries no quest id, so the row could never be named
-- or rolled up -- it just said "Objective". That source is dropped rather than
-- tuned, and the window went with it. It was the only row on the rail that
-- could not say what it was about.

Sources.latched = {}

--- Report a condition. Posts a row only on the transition into it.
local function Latch(key, active, kind, name)
    if active then
        if not Sources.latched[key] then
            Sources.latched[key] = true
            ns.Rail.Add(kind, name)
            return true
        end
    else
        Sources.latched[key] = nil
    end
    return false
end

Sources.Latch = Latch

-- ---------------------------------------------------------------------------
-- Bursts -- leading edge only
-- ---------------------------------------------------------------------------
-- Currency and reputation are the noisy ones, and the reason to show them in
-- real time is narrow: you clicked something and you want to see that it
-- worked. The gain you feel you caused is the FIRST one after a quiet stretch.
-- The eight behind it are the system talking to itself.
--
-- So a source that has been quiet announces, and a source already streaming
-- refreshes the dot it already owns. Every single gain still reaches the log,
-- including the ones nothing was said about -- the aggregate stays exact even
-- though the rail only ever showed one row.
Sources.QUIET = 20.0

local bursts = {}
Sources.bursts = bursts

--- Announce on the leading edge, roll up on the trailing one.
-- Returns true when it spoke.
local function Burst(key, kind, name, count)
    local now = ns.Reveal.Now()
    local b = bursts[key]

    if b and b.item and (now - b.at) < Sources.QUIET then
        b.at = now
        ns.Rail.Bump(b.item, count)
        return false
    end

    local item = ns.Rail.Add(kind, name, count)
    bursts[key] = { at = now, item = item }
    return true
end

Sources.Burst = Burst

-- ---------------------------------------------------------------------------
-- Blue -- loot received
-- ---------------------------------------------------------------------------

--- Pull an item out of a chat message. Returns id, name, count.
-- The count is matched AFTER the link's closing tag, because item names
-- themselves contain things like "x2" and matching anywhere finds those first.
function Sources.ParseLoot(text)
    if type(text) ~= "string" then
        return nil
    end
    local id = tonumber(text:match("|Hitem:(%d+)"))
    local name = text:match("|h%[(.-)%]|h")
    if not name then
        return nil
    end
    local count = tonumber(text:match("|h|r%s*[xX](%d+)")) or 1
    return id, name, count
end

-- CHAT_MSG_LOOT fires for the whole group, so a raid would otherwise fill the
-- rail with other people's drops. arg12 is the looter's GUID -- an identifier,
-- not a unit value, and nothing in RULES governs it -- which makes the filter
-- one comparison instead of a set of localized message patterns.
--
-- The fallback matters more than it looks: if the GUID is ever absent we cannot
-- tell whose loot it is, and guessing wrong in a raid is the noisy direction.
-- So no GUID means the localized "you receive" patterns decide, and if those
-- are missing too the message is dropped rather than posted.
local SELF_PATTERNS

local function BuildSelfPatterns()
    if SELF_PATTERNS then
        return SELF_PATTERNS
    end
    SELF_PATTERNS = {}
    for _, key in ipairs({ "LOOT_ITEM_SELF", "LOOT_ITEM_SELF_MULTIPLE",
                           "LOOT_ITEM_PUSHED_SELF", "LOOT_ITEM_PUSHED_SELF_MULTIPLE" }) do
        local fmt = _G[key]
        if type(fmt) == "string" then
            -- "You receive loot: %s." -> a pattern anchored at the start.
            local pattern = fmt:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
                               :gsub("%%%%s", ".-")
                               :gsub("%%%%d", "%%d+")
            SELF_PATTERNS[#SELF_PATTERNS + 1] = "^" .. pattern
        end
    end
    return SELF_PATTERNS
end

function Sources.IsSelfLoot(text, guid)
    local mine = API("UnitGUID", "player")
    if guid and mine then
        return guid == mine
    end
    for _, pattern in ipairs(BuildSelfPatterns()) do
        if type(text) == "string" and text:match(pattern) then
            return true
        end
    end
    return false
end

--- Is this item good enough to speak about? SPEC 6 defaults to uncommon.
function Sources.LootPasses(id)
    if not id then
        -- Unknown quality. Post it: a missed drop is worse than a dull row,
        -- and this only happens when the item API is unavailable.
        return true
    end
    local quality = API("C_Item.GetItemQualityByID", id)
    if type(quality) ~= "number" then
        return true
    end
    return quality >= Sources.Setting("lootQuality")
end

local function OnLoot(text, guid)
    if not Sources.IsSelfLoot(text, guid) then
        return
    end
    local id, name, count = Sources.ParseLoot(text)
    if not name then
        return
    end
    if not Sources.LootPasses(id) then
        return
    end
    ns.Rail.Add("blue", name, count)
end

local function OnRollWon(link, quantity)
    local id, name, count = Sources.ParseLoot(link)
    if not name then
        return
    end
    ns.Rail.Add("blue", name, tonumber(quantity) or count)
end

-- ---------------------------------------------------------------------------
-- Amber -- quests
-- ---------------------------------------------------------------------------

local function QuestName(questID, fallback)
    local title = API("C_QuestLog.GetTitleForQuestID", questID)
    if type(title) == "string" and title ~= "" then
        return title
    end
    return fallback
end

-- ---------------------------------------------------------------------------
-- Green -- currency and reputation
-- ---------------------------------------------------------------------------

local function OnCurrency(currencyID, quantity, quantityChange)
    -- Only gains. CURRENCY_DISPLAY_UPDATE also fires on spending, and a rail
    -- that announces what you just paid is a different feature.
    if type(quantityChange) ~= "number" or quantityChange <= 0 then
        return
    end
    local info = API("C_CurrencyInfo.GetCurrencyInfo", currencyID)
    local name = type(info) == "table" and info.name or "Currency"
    -- Keyed per currency: earning two different ones is two things happening,
    -- and only a repeat of the SAME one is a stream.
    Burst("currency:" .. tostring(currencyID), "green", name, quantityChange)
end

--- Turn a client format string into a Lua pattern whose one capture is the
-- first %s. Any later specifier -- %d for the amount, %.1f for an achievement
-- bonus -- becomes a plain wildcard, because only the faction is wanted.
--
-- Specifiers are swapped for control-character sentinels BEFORE escaping, so
-- the escaper cannot mangle the % that starts them. Doing it the other way
-- round is the obvious version and it does not survive "%.1f".
function Sources.ToPattern(fmt)
    if type(fmt) ~= "string" then
        return nil
    end
    local captured = false
    local marked = fmt:gsub("%%[%-%+ #0]*%d*%.?%d*([diouxXeEfgGqscaA])", function(kind)
        if kind == "s" and not captured then
            captured = true
            return "\1"
        end
        return "\2"
    end)
    if not captured then
        return nil
    end
    local escaped = marked:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
    return (escaped:gsub("\1", "(.-)"):gsub("\2", ".-"))
end

-- Every FACTION_STANDING_INCREASED* format string the client ships, as
-- patterns.
--
-- FOUND IN GAME: the first version named exactly one global,
-- FACTION_STANDING_INCREASED, and the rail drew "Reputation" -- the fallback --
-- instead of the faction. The client ships several forms (bonus, account-wide,
-- generic, and whatever a future patch adds), GlobalStrings.lua is not in the
-- reference dump, and the addon is not localized. So the variants are found
-- rather than listed: scanning is the only version that is right without being
-- able to check.
local FACTION_PATTERNS

function Sources.FactionPatterns()
    if FACTION_PATTERNS then
        return FACTION_PATTERNS
    end
    FACTION_PATTERNS = {}
    -- pcall'd whole: this walks every global the client has, and one forbidden
    -- object in there must not take the rail down with it.
    pcall(function()
        for key, value in pairs(_G) do
            if type(key) == "string" and type(value) == "string"
               and key:find("^FACTION_STANDING_INCREASED") then
                local pattern = Sources.ToPattern(value)
                if pattern then
                    FACTION_PATTERNS[#FACTION_PATTERNS + 1] = pattern
                end
            end
        end
    end)
    -- Longest first. Several forms match the same message and the longer one is
    -- the more specific; without an order the winner comes out of pairs().
    table.sort(FACTION_PATTERNS, function(a, b) return #a > #b end)
    return FACTION_PATTERNS
end

--- Faction name out of whichever "reputation increased" line the client sent.
-- Falls back to nil rather than the whole sentence, which is 11pt in a
-- 160-wide row and would simply not fit.
function Sources.ParseFaction(text)
    if type(text) ~= "string" then
        return nil
    end
    for _, pattern in ipairs(Sources.FactionPatterns()) do
        local name = text:match(pattern)
        if name and name ~= "" then
            return name
        end
    end
    return nil
end

local function OnReputation(text)
    local faction = Sources.ParseFaction(text) or "Reputation"
    Burst("reputation:" .. faction, "green", faction)
end

-- ---------------------------------------------------------------------------
-- Orange -- something wants you
-- ---------------------------------------------------------------------------

--- Free slots across the carried bags. Ordinary arithmetic on ordinary values.
function Sources.FreeBagSlots()
    local first = _G.BACKPACK_CONTAINER or 0
    local last  = _G.NUM_TOTAL_EQUIPPED_BAG_SLOTS or 4
    local free, sawAny = 0, false
    for bag = first, last do
        local n = API("C_Container.GetContainerNumFreeSlots", bag)
        if type(n) == "number" then
            sawAny = true
            free = free + n
        end
    end
    if not sawAny then
        return nil
    end
    return free
end

-- Equipped slots that can carry durability. 1..18 is head through off-hand;
-- the readers return nil for the ones that cannot wear out, so the loop does
-- not need to know which those are.
local DURABILITY_SLOTS = 18

--- The worst durability fraction among equipped items, or nil if nothing is
-- readable. Nil is deliberately different from 1.0: "no data" must not latch
-- the warning off.
function Sources.WorstDurability()
    local worst
    for slot = 1, DURABILITY_SLOTS do
        local current, maximum = API("GetInventoryItemDurability", slot)
        if type(current) == "number" and type(maximum) == "number" and maximum > 0 then
            local fraction = current / maximum
            if worst == nil or fraction < worst then
                worst = fraction
            end
        end
    end
    return worst
end

local function OnBagUpdate()
    local free = Sources.FreeBagSlots()
    if free == nil then
        return
    end
    Latch("bagFull", free <= Sources.Setting("bagFree"), "orange", "Bags full")
end

local function OnDurability()
    local worst = Sources.WorstDurability()
    if worst == nil then
        return
    end
    Latch("durability", worst <= Sources.Setting("durability"), "orange", "Gear worn")
end

local function OnMail()
    local has = API("HasNewMail")
    if has == nil then
        -- The event itself is the signal when the reader is unavailable. It
        -- only fires on a change, so this is still one row, not a stream.
        ns.Rail.Add("orange", "Mail")
        return
    end
    Latch("mail", has and true or false, "orange", "Mail")
end

-- ---------------------------------------------------------------------------
-- Wiring
-- ---------------------------------------------------------------------------
-- SPEC 6's event table, verbatim. Kept as data rather than a chain of
-- elseifs so a test can assert every event in the spec is registered and no
-- event outside it is.

Sources.EVENTS = {
    -- blue
    CHAT_MSG_LOOT = function(text, _, _, _, _, _, _, _, _, _, _, guid)
        OnLoot(text, guid)
    end,
    LOOT_ITEM_ROLL_WON = OnRollWon,

    -- amber
    QUEST_ACCEPTED = function(questID)
        ns.Rail.Add("amber", QuestName(questID, "Quest accepted"))
    end,
    QUEST_TURNED_IN = function(questID)
        ns.Rail.Add("amber", QuestName(questID, "Quest complete"))
    end,
    -- green
    CURRENCY_DISPLAY_UPDATE = OnCurrency,
    CHAT_MSG_COMBAT_FACTION_CHANGE = OnReputation,

    -- violet
    ACHIEVEMENT_EARNED = function(achievementID)
        local _, name = API("GetAchievementInfo", achievementID)
        ns.Rail.Add("violet", type(name) == "string" and name or "Achievement")
    end,

    -- red
    PLAYER_DEAD = function()
        Burst("death", "red", "You died")
    end,

    -- orange
    UPDATE_PENDING_MAIL          = OnMail,
    BAG_UPDATE_DELAYED           = OnBagUpdate,
    UPDATE_INVENTORY_DURABILITY  = OnDurability,
    PARTY_INVITE_REQUEST = function(name)
        ns.Rail.Add("orange", ("Party: %s"):format(tostring(name or "?")))
    end,
    GUILD_INVITE_REQUEST = function(inviter, guildName)
        ns.Rail.Add("orange", ("Guild: %s"):format(tostring(guildName or inviter or "?")))
    end,
}

function Sources.Handle(event, ...)
    local fn = Sources.EVENTS[event]
    if fn then
        fn(...)
    end
end

function Sources.OnLogin()
    local driver = CreateFrame("Frame", "MyUISourcesDriver", UIParent)
    Sources.driver = driver

    for event in pairs(Sources.EVENTS) do
        driver:RegisterEvent(event)
    end

    driver:SetScript("OnEvent", function(_, event, ...)
        Sources.Handle(event, ...)
    end)

    -- The three latches are conditions rather than events, and a condition can
    -- already be true at login. Evaluating them here means a bag that was
    -- already full says so once, now, instead of staying silent until the next
    -- time anything moves in it. The latch then keeps it to that one row.
    --
    -- Readers can legitimately return nil this early, before the client has
    -- the container and inventory data. Each one bails on nil, and its own
    -- event fires shortly afterwards and catches it.
    OnBagUpdate()
    OnDurability()
    OnMail()

    -- Built here rather than on the first reputation message: the scan walks
    -- every global the client has, and login is where a few milliseconds do not
    -- matter. Mid-fight is not.
    Sources.FactionPatterns()
end
