-- MyUI :: Core.lua
-- Namespace, versioned SavedVariables, migration ladder, output capture.

local ADDON, ns = ...

ns.name    = ADDON
ns.version = C_AddOns and C_AddOns.GetAddOnMetadata
             and C_AddOns.GetAddOnMetadata(ADDON, "Version") or "0.4.0-phase3"
ns.phase   = 3

-- Bump on any change to the stored shape, and add the matching migration.
local SCHEMA_VERSION = 2
ns.SCHEMA_VERSION = SCHEMA_VERSION

-- MIGRATIONS[n] upgrades a database at schema n to schema n+1.
-- Phase 0 shipped the first schema and an empty ladder, so that no later phase
-- would have to retrofit one. This is the first rung.
local MIGRATIONS = {
    -- 1 -> 2: the amended SPEC 4 cut the modifier reveal channel, so the keys
    -- that armed it stopped being a setting. Cleared rather than left in place:
    -- a stored value nothing reads is a question for whoever opens the file
    -- next, and this is exactly what the ladder is for.
    [1] = function(db)
        db.modifiers = nil
    end,
}
ns.MIGRATIONS = MIGRATIONS

local function FreshDB()
    return {
        schema = SCHEMA_VERSION,
        addon  = { version = ns.version, phase = ns.phase },
        -- Per-frame alpha overrides land here in Phase 5.
        alpha  = {},
        -- Every command's output, persisted so it can be read off disk after a
        -- /reload rather than copied out of the chat frame by hand.
        lastCommand = nil,
        lastOutput  = nil,
        -- How the small type survives a bright backdrop. SPEC's palette is
        -- light-on-dark and washes out over sand or firelight.
        textStyle   = "shadow",
        -- lift is the amended SPEC 7 value; normal is the grey it replaced,
        -- kept as a diagnostic. See Frames.Contrast.
        contrast    = "lift",
        -- SPEC 6's three rail thresholds, which it says are saved variables.
        sources     = { lootQuality = 2, durability = 0.20, bagFree = 0 },
        -- Step one of replacing the chat log. Off by one flag, because it
        -- touches a Blizzard extension point and needs a way back that does
        -- not involve deleting the addon.
        chat        = { override = true, hideLog = false },
        -- Blizzard furniture we take off the screen, by group.
        stow        = { raid = false },
        guard  = { mode = "strict" },
    }
end

local function Migrate(db)
    local from = tonumber(db.schema) or 0

    if from > SCHEMA_VERSION then
        -- Written by a newer MyUI. Do not touch it.
        ns.Print(("saved data is schema %d but this build understands %d. "):format(from, SCHEMA_VERSION)
                 .. "Running without persistence to avoid damaging it.")
        ns.readOnlyDB = true
        return db
    end

    while from < SCHEMA_VERSION do
        local step = MIGRATIONS[from]
        if not step then
            ns.Print(("no migration from schema %d; resetting saved data."):format(from))
            return FreshDB()
        end
        local ok, err = pcall(step, db)
        if not ok then
            ns.Print(("migration %d -> %d failed (%s); resetting saved data."):format(from, from + 1, tostring(err)))
            return FreshDB()
        end
        from = from + 1
        db.schema = from
    end

    db.addon = db.addon or {}
    db.addon.version = ns.version
    db.addon.phase   = ns.phase
    db.alpha = db.alpha or {}
    db.guard = db.guard or { mode = "strict" }
    db.textStyle = db.textStyle or "shadow"
    db.contrast  = db.contrast or "lift"
    -- Backfilled rather than migrated, and the distinction is the rule this
    -- ladder runs on: an ADDED key has a default, so a backfill expresses it
    -- completely and a migration rung would be dead code beside it. A REMOVED
    -- key cannot be backfilled away, which is why cutting db.modifiers needed
    -- rung 1 and adding db.sources does not.
    db.sources   = db.sources or { lootQuality = 2, durability = 0.20, bagFree = 0 }
    db.chat      = db.chat or { override = true, hideLog = false }
    -- Nested keys are backfilled individually: `db.chat or {...}` only fills
    -- the table when it is missing entirely, so a database written before
    -- hideLog existed keeps a chat table with no hideLog in it.
    if db.chat.override == nil then db.chat.override = true end
    if db.chat.hideLog  == nil then db.chat.hideLog  = false end
    db.stow = db.stow or { raid = false }
    if db.stow.raid == nil then db.stow.raid = false end
    return db
end

-- ---------------------------------------------------------------------------
-- Output
-- ---------------------------------------------------------------------------

local PREFIX = "|cff8cd3ffMyUI|r: "

-- Everything printed is also captured, stripped of colour codes. WoW's chat
-- frame is close to impossible to copy out of, and audit output exists to be
-- acted on elsewhere.
local MAX_CAPTURED = 500
ns.output = {}

local function Capture(line)
    local plain = tostring(line):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    local buffer = ns.output
    buffer[#buffer + 1] = plain
    if #buffer > MAX_CAPTURED then
        table.remove(buffer, 1)
    end
end

function ns.ClearOutput()
    ns.output = {}
end

function ns.GetOutput()
    return table.concat(ns.output, "\n")
end

function ns.Print(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[i] = tostring((select(i, ...)))
    end
    local line = PREFIX .. table.concat(parts, " ")
    Capture(line)
    local frame = _G.DEFAULT_CHAT_FRAME
    if frame then
        frame:AddMessage(line)
    else
        print(line)
    end
end

--- Print without the prefix, for indented report bodies.
function ns.Raw(text)
    Capture(text)
    local frame = _G.DEFAULT_CHAT_FRAME
    if frame then
        frame:AddMessage(text)
    else
        print(text)
    end
end

-- ---------------------------------------------------------------------------
-- Load
-- ---------------------------------------------------------------------------

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, addon)
    if event == "ADDON_LOADED" then
        if addon ~= ADDON then
            return
        end
        self:UnregisterEvent("ADDON_LOADED")

        if type(_G.MyUIDB) ~= "table" then
            _G.MyUIDB = FreshDB()
        else
            _G.MyUIDB = Migrate(_G.MyUIDB)
        end
        ns.db = _G.MyUIDB

        -- The character's record, in its own file. Attached here rather than
        -- at PLAYER_LOGIN because a source can fire before the frames exist
        -- and the log must never be the reason something is lost.
        if ns.Log and ns.Log.Attach then
            local ok, err = pcall(ns.Log.Attach)
            if not ok then
                ns.Print("character log failed to load: " .. tostring(err))
            end
        end

        if ns.Guard and ns.db.guard and ns.db.guard.mode then
            ns.Guard.mode = ns.db.guard.mode
        end

        -- Phase 0 draws nothing. Frames arrive at PLAYER_LOGIN from Phase 1.
        self:RegisterEvent("PLAYER_LOGIN")

    elseif event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")

        -- ORDERED, not a pairs() over a table. Login order is a real
        -- dependency: Frames creates what Registry hands out, and Rail cannot
        -- find its container until Frames has built it. With pairs() that
        -- worked or failed depending on Lua's internal table layout, which is
        -- the worst kind of bug -- it passes until it doesn't.
        for _, step in ipairs({
            { "registry",     ns.Registry },
            { "frames",       ns.Frames   },
            { "reveal engine", ns.Reveal  },
            { "rail",         ns.Rail     },
            -- Last: every source posts to the rail, so the rail has to exist
            -- before one can fire. Login primes three latched conditions.
            { "rail sources", ns.Sources  },
            -- The centre reads the log and borrows the rail's hues, so both
            -- have to exist first.
            { "centre",       ns.Center   },
            { "panel",        ns.Panel    },
            -- After the rail: the box borrows Frames' font and the palette,
            -- and nothing else depends on it existing.
            { "chat override", ns.Chat   },
        }) do
            local label, module = step[1], step[2]
            if module and module.OnLogin then
                local ok, err = pcall(module.OnLogin)
                if not ok then
                    ns.Print(label .. " failed to start: " .. tostring(err))
                end
            end
        end

        ns.Print(("v%s loaded (phase %d, schema %d). |cffadb1b8/myui|r for commands.")
                 :format(ns.version, ns.phase, ns.db.schema))
    end
end)
