-- MyUI :: Compat.lua
-- Safe-read layer. Ported from the Rebar project's Compat.lua, trimmed to what
-- a HUD needs: MyUI never walks the frame tree, so the forbidden-aspect
-- decoding half is deliberately absent.
--
-- Two things make naive reads unsafe on 12.1:
--   1. Secret values. A Secret cannot be compared, done arithmetic on,
--      concatenated, or written to SavedVariables.
--   2. Forbidden objects. Indexing or calling a method on one can throw.
--
-- This file answers "can I safely look at this?". Guard.lua answers the more
-- important question, "am I allowed to?".

local ADDON, ns = ...

local Compat = {}
ns.Compat = Compat

-- Sentinels are plain strings, always safe to store and print.
Compat.SECRET = "<secret>"
Compat.ERROR  = "<error>"
Compat.ABSENT = "<absent>"

local issecretvalue = _G.issecretvalue
local hasSecretAPI  = type(issecretvalue) == "function"

Compat.hasSecretAPI = hasSecretAPI

--- True if value is a Secret, or if we could not prove it is not one.
-- Fails closed: an untestable value is treated as secret rather than risking a
-- throw further down the line.
function Compat.IsSecret(value)
    if not hasSecretAPI then
        return false
    end
    local ok, result = pcall(issecretvalue, value)
    if not ok then
        return true
    end
    return result and true or false
end

--- Reduce any value to something safe to store in SavedVariables and print.
function Compat.Plain(value)
    if Compat.IsSecret(value) then
        return Compat.SECRET
    end
    local t = type(value)
    if t == "nil" or t == "number" or t == "string" or t == "boolean" then
        return value
    end
    local ok, text = pcall(tostring, value)
    -- Written long-hand deliberately: the `ok and x or y` idiom silently turns
    -- a falsy x into y, which cost the Rebar project a wrong answer.
    if ok then
        return text
    end
    return Compat.ERROR
end

--- True when v is one of our sentinels rather than real data.
function Compat.IsSentinel(v)
    return v == Compat.SECRET or v == Compat.ERROR or v == Compat.ABSENT
end

--- True when v is a real number we can safely do arithmetic on.
function Compat.IsNumber(v)
    return type(v) == "number"
end

local function PackResults(ok, ...)
    if not ok then
        return false, 1, Compat.ERROR
    end
    return true, select("#", ...), ...
end

--- Call obj:method(...) defensively. Returns ok, count, ...raw results.
-- Results are NOT sanitized; callers that store them must run Plain first.
-- The explicit count matters: several 12.1 getters are MayReturnNothing, and
-- the length operator on a table with a nil hole is undefined in Lua. Never
-- use # on captured varargs.
function Compat.CallN(obj, method, ...)
    local t = type(obj)
    if t ~= "table" and t ~= "userdata" then
        return false, 1, Compat.ABSENT
    end

    -- Even the index can throw on a forbidden object.
    local fn
    local indexed = pcall(function() fn = obj[method] end)
    if not indexed then
        return false, 1, Compat.ERROR
    end
    if type(fn) ~= "function" then
        return false, 1, Compat.ABSENT
    end

    return PackResults(pcall(fn, obj, ...))
end

--- As CallN, but without the count, for single-value reads.
function Compat.Call(obj, method, ...)
    local ok, _, first, second, third, fourth = Compat.CallN(obj, method, ...)
    return ok, first, second, third, fourth
end

--- Single sanitized return. Always safe to store or print.
function Compat.Get(obj, method, ...)
    local ok, first = Compat.Call(obj, method, ...)
    if not ok then
        return first
    end
    return Compat.Plain(first)
end
