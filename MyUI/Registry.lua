-- MyUI :: Registry.lua
-- Every frame MyUI creates registers here with the resting alpha SPEC.md § 2
-- gives it. Nothing else in the addon is allowed to own that number.
--
-- Phase 0 ships the machinery empty. Phase 1 fills it; Phase 2's arbiter reads
-- it. The registry exists first because /myui audit is the acceptance test for
-- every later phase, and an audit that cannot see a frame cannot clear it.

local ADDON, ns = ...

local Registry = {}
ns.Registry = Registry

local entries = {}   -- ordered
local byName  = {}

--- Register a frame at its permanent anchor with its resting alpha.
-- restingAlpha is the value the frame returns to when every reveal claim
-- releases -- never zero unless the spec says zero (SPEC.md § 4).
function Registry.Add(name, frame, restingAlpha)
    if byName[name] then
        ns.Print(("duplicate frame name %q ignored"):format(name))
        return byName[name]
    end
    local entry = {
        name    = name,
        frame   = frame,
        resting = restingAlpha,
        claim   = nil,     -- which reveal channel currently holds it (Phase 2)
        target  = restingAlpha,
    }
    entries[#entries + 1] = entry
    byName[name] = entry
    return entry
end

function Registry.Get(name)
    return byName[name]
end

function Registry.Count()
    return #entries
end

--- Iterate registered frames in registration order.
function Registry.Each(fn)
    for i = 1, #entries do
        fn(entries[i], i)
    end
end

--- A printable snapshot: name, resting alpha, live alpha, current claim.
-- Live alpha is read through Compat because GetAlpha is guarded by the
-- RequiresScriptObjectAlphaAccess predicate and a frame we have forwarded a
-- secret into carries SecretAspect.Alpha from that moment on. Reading it back
-- is therefore not guaranteed to return a number, and the audit says so rather
-- than inventing one.
function Registry.Snapshot()
    local out = {}
    for i = 1, #entries do
        local e = entries[i]
        out[i] = {
            name    = e.name,
            resting = e.resting,
            target  = e.target,
            claim   = e.claim or "-",
            current = ns.Compat.Get(e.frame, "GetAlpha"),
        }
    end
    return out
end

function Registry.OnLogin()
    -- Phase 1 creates frames here.
end
