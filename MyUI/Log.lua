-- MyUI :: Log.lua
-- The persistent record behind the rail. Per character, timestamped, bounded.
--
-- Round 5 killed the 8-dot cap and the "+N more" square, and made truncation
-- safe by putting an archive behind the rail: it is a signal, not storage.
-- This is the storage, and it has to exist before the rail is allowed to
-- forget anything.
--
-- Per character, not account-wide. MyUIDB holds settings, which every alt
-- should share -- the same HUD wherever you log in. A record of what happened
-- is the opposite: a whisper was addressed to who you were playing, and a bag
-- filling up is not a fact about your account. Two files, two natures.

local ADDON, ns = ...

local Log = {}
ns.Log = Log

local SCHEMA = 1
Log.SCHEMA = SCHEMA

-- A ceiling, not a garbage collector -- the distinction the log lives or dies
-- on. SavedVariables is Lua source that the client parses on every login, so a
-- log that grows without bound is a login cost that grows without bound. Five
-- thousand entries is far past anything anyone scrolls and still parses in
-- nothing. Nothing here expires by age; entries leave only when the ceiling
-- pushes them off the end.
Log.MAX = 5000

-- ---------------------------------------------------------------------------
-- Time
-- ---------------------------------------------------------------------------
-- Reveal.Now() is GetTime(), which is seconds since the client started and
-- resets on every reload. It dates the rail correctly and cannot date a record
-- that outlives the session, so the log keeps its own clock in epoch seconds.
-- This is also what makes "filter by time" possible later without a migration.

function Log.Now()
    local fn = _G.time
    if type(fn) ~= "function" then
        return 0
    end
    local ok, t = pcall(fn)
    if not ok or type(t) ~= "number" then
        return 0
    end
    return t
end

-- ---------------------------------------------------------------------------
-- Storage
-- ---------------------------------------------------------------------------

local function Fresh()
    return { schema = SCHEMA, entries = {} }
end
Log.Fresh = Fresh

--- Bind the log to its saved variable. Called from Core at ADDON_LOADED.
function Log.Attach()
    local db = _G.MyUICharDB
    -- The same file holds where this character put things (Places.lua): a
    -- log that starts again does not take that with it.
    local places = type(db) == "table" and db.places or nil
    if type(db) ~= "table" or type(db.entries) ~= "table" then
        db = Fresh()
    elseif tonumber(db.schema) ~= SCHEMA then
        -- One schema so far, so there is no ladder to climb yet. A log is a
        -- record rather than a setting: if a future shape cannot be read, the
        -- honest move is to say so and start again, not to guess.
        ns.Print(("character log is schema %s but this build understands %d; starting a new one.")
                 :format(tostring(db.schema), SCHEMA))
        db = Fresh()
    end
    db.places = db.places or places
    _G.MyUICharDB = db
    Log.db = db
    Log.Trim()
    return db
end

--- Drop anything past the ceiling. Entries are newest first, so this takes
-- from the tail.
function Log.Trim()
    local db = Log.db
    if not db then
        return 0
    end
    local dropped = 0
    while #db.entries > Log.MAX do
        table.remove(db.entries)
        dropped = dropped + 1
    end
    return dropped
end

-- ---------------------------------------------------------------------------
-- Writing
-- ---------------------------------------------------------------------------

--- Record one notification. Every rail item lands here, including the ones the
-- rail declines to announce and the ones it later drops.
function Log.Add(kind, name, count, sub)
    local db = Log.db
    if not db then
        return nil
    end
    local entry = {
        at    = Log.Now(),
        kind  = kind,
        name  = name,
        count = tonumber(count) or 1,
        sub   = sub,
    }
    table.insert(db.entries, 1, entry)
    Log.Trim()
    return entry
end

function Log.Clear()
    if Log.db then
        Log.db.entries = {}
    end
end

-- ---------------------------------------------------------------------------
-- Reading
-- ---------------------------------------------------------------------------

function Log.Count(kind)
    local db = Log.db
    if not db then
        return 0
    end
    if kind == nil then
        return #db.entries
    end
    local n = 0
    for _, e in ipairs(db.entries) do
        if e.kind == kind then
            n = n + 1
        end
    end
    return n
end

--- Newest first. `kind` filters by hue; `limit` caps the result.
function Log.Filter(kind, limit)
    local db = Log.db
    local out = {}
    if not db then
        return out
    end
    for _, e in ipairs(db.entries) do
        if kind == nil or e.kind == kind then
            out[#out + 1] = e
            if limit and #out >= limit then
                break
            end
        end
    end
    return out
end

--- Counts per hue, for the filter row Round 5 puts at the top of the centre.
function Log.Tally()
    local tally = {}
    local db = Log.db
    if not db then
        return tally
    end
    for _, e in ipairs(db.entries) do
        tally[e.kind] = (tally[e.kind] or 0) + 1
    end
    return tally
end

ns.Log = Log
