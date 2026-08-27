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

--- The alpha the registry last set on a frame.
--
-- Read this, never GetAlpha. From Phase 4 a frame that has been forwarded a
-- secret carries SecretAspect.Alpha, and reading its alpha back returns a
-- secret rather than a number -- so anything that checks state against what we
-- intended has to hold that intent itself. The audit still shows the live value
-- for information, as a sentinel when it is unreadable.
function Registry.Target(name)
    local entry = byName[name]
    if not entry then
        return nil
    end
    return entry.target
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

--- Debug toggle: force every registered frame to full alpha, or release it
-- back to the resting alpha SPEC.md 2 gives it.
--
-- PLAN.md Phase 1 asks for this, and the reason is worth stating: a design
-- where the correct state is invisible cannot be checked by looking at it. The
-- toggle is the only way to see whether a frame is where the spec says before
-- the reveal engine exists to summon it.
function Registry.ForceVisible(on)
    if on then
        Registry.forced = true
    else
        Registry.forced = false
    end
    -- Routed through the arbiter rather than setting alpha directly, so there
    -- is exactly one owner of a frame's alpha (SPEC.md 4). Snapped rather than
    -- faded: the toggle is a diagnostic, not a reveal.
    if ns.Reveal then
        if Registry.forced then
            ns.Reveal.Claim("debug")
        else
            ns.Reveal.Release("debug")
        end
        ns.Reveal.Snap()
    else
        Registry.Each(function(entry)
            if Registry.forced then
                entry.target = 1
            else
                entry.target = entry.resting
            end
            entry.frame:SetAlpha(entry.target)
        end)
    end
    return Registry.forced
end

--- Size and anchor of a registered frame, sanitised for printing.
-- Read through Compat: geometry getters carry SecretWhenAnchoringSecret in the
-- 12.1 docs, so a number is not guaranteed and the audit says so rather than
-- inventing one.
function Registry.Geometry(entry)
    local w = ns.Compat.Get(entry.frame, "GetWidth")
    local h = ns.Compat.Get(entry.frame, "GetHeight")
    -- GetPoint is MayReturnNothing and returns five values. Read through CallN
    -- with its explicit count rather than trusting the arity of an assignment.
    local res = { ns.Compat.CallN(entry.frame, "GetPoint", 1) }
    local ok, count = res[1], res[2]
    if not ok or count < 5 then
        return w, h, nil
    end
    return w, h, {
        point    = ns.Compat.Plain(res[3]),
        relPoint = ns.Compat.Plain(res[5]),
        x        = ns.Compat.Plain(res[6]),
        y        = ns.Compat.Plain(res[7]),
    }
end

function Registry.OnLogin()
    -- Frames.OnLogin does the building; this runs first and has nothing to do.
end
