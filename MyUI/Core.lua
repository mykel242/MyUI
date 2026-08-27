-- MyUI :: Core.lua
-- Namespace, versioned SavedVariables, migration ladder, output capture.

local ADDON, ns = ...

ns.name    = ADDON
ns.version = C_AddOns and C_AddOns.GetAddOnMetadata
             and C_AddOns.GetAddOnMetadata(ADDON, "Version") or "0.3.0-phase2"
ns.phase   = 2

-- Bump on any change to the stored shape, and add the matching migration.
local SCHEMA_VERSION = 1
ns.SCHEMA_VERSION = SCHEMA_VERSION

-- MIGRATIONS[n] upgrades a database at schema n to schema n+1.
-- Phase 0 ships the first schema, so this is empty by design; the ladder
-- exists now so later phases never have to retrofit one.
local MIGRATIONS = {}
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
        -- Which keys arm the reveal engine's modifier channel. SPEC 4's
        -- default is Alt or Shift; players who bind those to abilities need
        -- to change or disable it.
        modifiers   = { alt = true, shift = true },
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
    db.modifiers = db.modifiers or { alt = true, shift = true }
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

        if ns.Guard and ns.db.guard and ns.db.guard.mode then
            ns.Guard.mode = ns.db.guard.mode
        end

        -- Phase 0 draws nothing. Frames arrive at PLAYER_LOGIN from Phase 1.
        self:RegisterEvent("PLAYER_LOGIN")

    elseif event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")

        for label, module in pairs({
            registry = ns.Registry,
            frames   = ns.Frames,
            reveal   = ns.Reveal,
        }) do
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
