-- MyUI :: Commands.lua
-- /myui. Any unambiguous prefix of a subcommand works.

local ADDON, ns = ...

local Compat, Guard, Registry, Rules = ns.Compat, ns.Guard, ns.Registry, ns.Rules

local function fmtAlpha(v)
    if type(v) ~= "number" then
        return tostring(v)
    end
    return ("%.2f"):format(v)
end

-- ---------------------------------------------------------------------------
-- audit
-- ---------------------------------------------------------------------------
-- RULES.md: run this at the end of every phase. A phase is not done until it
-- is clean.

local function Audit()
    ns.Print(("audit -- phase %d, guard %s"):format(ns.phase, Guard.mode))

    local count = Registry.Count()
    if count == 0 then
        ns.Raw("  no frames registered (phase 0 draws nothing)")
    else
        ns.Raw(("  %-16s %7s %7s %7s  %s"):format("FRAME", "REST", "TARGET", "LIVE", "CLAIM"))
        for _, e in ipairs(Registry.Snapshot()) do
            ns.Raw(("  %-16s %7s %7s %7s  %s"):format(
                e.name, fmtAlpha(e.resting), fmtAlpha(e.target),
                fmtAlpha(e.current), e.claim))
        end
    end

    ns.Raw(" ")
    local v = Guard.violations
    if #v == 0 then
        ns.Raw(("  |cffa6d98cclean|r -- 0 violations, %d secret forwards"):format(Guard.forwards))
    else
        ns.Raw(("  |cfff26b61%d violation(s)|r -- %d secret forwards"):format(#v, Guard.forwards))
        for i = 1, #v do
            ns.Raw("    " .. v[i])
        end
    end

    if not Compat.hasSecretAPI then
        ns.Raw("  |cffffd159note|r issecretvalue is absent -- secret detection is inert on this client")
    end
end

-- ---------------------------------------------------------------------------
-- conditionals
-- ---------------------------------------------------------------------------
-- Resolves the one question API-NOTES-12.1.md 4 could not answer offline:
-- SecureCmdOptionParse is engine-side, so the conditional vocabulary cannot be
-- read from Blizzard's Lua source. It can be asked directly.
--
-- Measured on a live client: a conditional the parser does not know is
-- IGNORED, so the clause matches. [zzznope] hits. That is the opposite of what
-- this probe first assumed, and it matters, because "unknown" then produces
-- the same signature as "known and true".
--
-- So candidates with a numeric argument are tested as a complementary pair --
-- one clause that must always be false and one that must always be true if the
-- conditional is real. Unknown makes both match; real makes them differ. That
-- holds at any health, which is what makes the answer trustworthy without
-- having to nearly die to get it.
--
-- Baselines are measured, not assumed: a nonsense conditional is run through
-- both shapes so the "parser does not know this" signature comes from this
-- client rather than from a guess.

local CONTROLS = {
    { key = "known",   label = "control: known",     a = "[combat]",     b = "[nocombat]" },
    { key = "negbase", label = "control: unknown",   a = "[zzznope]",    b = "[nozzznope]" },
    { key = "numbase", label = "control: unknown n", a = "[zzznope<0]",  b = "[zzznope<101]" },
}

local CANDIDATES = {
    { label = "hp",             a = "[hp<0]",             b = "[hp<101]",             base = "numbase", certain = true },
    { label = "hp, scoped",     a = "[@player,hp<0]",     b = "[@player,hp<101]",     base = "numbase", certain = true },
    { label = "health",         a = "[health<0]",         b = "[health<101]",         base = "numbase", certain = true },
    { label = "health, scoped", a = "[@player,health<0]", b = "[@player,health<101]", base = "numbase", certain = true },
    { label = "hurt",           a = "[@player,hurt]",     b = "[@player,nohurt]",     base = "negbase", certain = false },
    { label = "lowhealth",      a = "[lowhealth]",        b = "[nolowhealth]",        base = "negbase", certain = false },
}

local function Evaluate(parse, clause)
    local ok, result = pcall(parse, clause .. " hit; miss")
    if not ok then
        return "error"
    end
    if result == nil then
        return "nil"
    end
    return tostring(result)
end

local function Signature(parse, row)
    return Evaluate(parse, row.a) .. "/" .. Evaluate(parse, row.b)
end

local function Row(label, clauses, sig, verdict)
    ns.Raw(("  %-18s %-42s %-10s %s"):format(label, clauses, sig, verdict))
end

local function Conditionals()
    local parse = _G.SecureCmdOptionParse
    if type(parse) ~= "function" then
        ns.Print("SecureCmdOptionParse is unavailable on this client")
        return
    end

    local baseline = {}
    ns.Print("macro conditional probe")
    Row("", "CLAUSES", "RESULT", "VERDICT")

    for _, c in ipairs(CONTROLS) do
        local sig = Signature(parse, c)
        baseline[c.key] = sig
        Row(c.label, c.a .. " / " .. c.b, sig, "|cffadb1b8--|r")
    end

    local recognised = 0
    for _, c in ipairs(CANDIDATES) do
        local sig = Signature(parse, c)
        local verdict
        if sig == baseline[c.base] then
            verdict = "|cfff26b61not recognised|r"
        else
            recognised = recognised + 1
            verdict = "|cffa6d98cRECOGNISED|r"
        end
        if not c.certain then
            verdict = verdict .. " |cffadb1b8(needs full health)|r"
        end
        Row(c.label, c.a .. " / " .. c.b, sig, verdict)
    end

    ns.Raw(" ")
    ns.Raw("  The known control must differ from the unknown one. If it does not, the")
    ns.Raw("  probe is broken rather than the conditionals missing.")
    ns.Raw(" ")
    if recognised == 0 then
        ns.Raw("  Nothing recognised. SPEC.md 3's driver state has no macro conditional")
        ns.Raw("  behind it. The rows marked certain hold at any health; the two marked")
        ns.Raw("  'needs full health' are only conclusive above the threshold.")
        ns.Raw("  Fallback: hook Blizzard's own LowHealthFrame. See API-NOTES-12.1.md 4.")
    else
        ns.Raw(("  %d recognised. SPEC.md 3 ships as written -- use that conditional.")
               :format(recognised))
    end
end

-- ---------------------------------------------------------------------------
-- guard
-- ---------------------------------------------------------------------------

local function SetGuardMode(arg)
    if arg == "strict" or arg == "warn" then
        Guard.mode = arg
        if ns.db and ns.db.guard then
            ns.db.guard.mode = arg
        end
        ns.Print("guard mode: " .. arg)
    elseif arg == "reset" then
        Guard.Reset()
        ns.Print("violation log cleared")
    else
        ns.Print(("guard mode is %s (strict errors, warn logs). "):format(Guard.mode)
                 .. "/myui guard strict|warn|reset")
    end
end

-- ---------------------------------------------------------------------------
-- help
-- ---------------------------------------------------------------------------

local COMMANDS = {
    { "help",         "this list" },
    { "copy",         "the last output in a selectable window" },
    { "rules",        "the 12.1 compliance contract, printed" },
    { "audit",        "every frame, its resting alpha, live alpha and reveal claim" },
    { "guard",        "strict | warn | reset -- how violations are reported" },
    { "conditionals", "probe which macro conditionals the client's parser knows" },
    { "version",      "build and schema" },
}

local function Help()
    ns.Print(("v%s -- phase %d"):format(ns.version, ns.phase))
    for _, c in ipairs(COMMANDS) do
        ns.Raw(("  |cfff0f1f3/myui %-13s|r %s"):format(c[1], c[2]))
    end
    ns.Raw("  any unambiguous prefix works")
end

-- ---------------------------------------------------------------------------
-- Dispatch
-- ---------------------------------------------------------------------------

local HANDLERS = {
    help         = Help,
    copy         = function()
        -- Deliberately shows what was captured BEFORE this command ran --
        -- otherwise /myui copy would only ever show itself.
        ns.Copy.Show(ns.db and ns.db.lastOutput or nil)
    end,
    rules        = function() Rules.Print() end,
    audit        = Audit,
    guard        = SetGuardMode,
    conditionals = Conditionals,
    version      = function()
        ns.Print(("v%s, phase %d, schema %s, guard %s")
                 :format(ns.version, ns.phase, tostring(ns.db and ns.db.schema), Guard.mode))
    end,
}

--- Resolve a prefix to exactly one command name, or nil plus the ambiguity.
local function Resolve(word)
    if HANDLERS[word] then
        return word
    end
    local hits = {}
    for name in pairs(HANDLERS) do
        if name:sub(1, #word) == word then
            hits[#hits + 1] = name
        end
    end
    if #hits == 1 then
        return hits[1]
    end
    table.sort(hits)
    return nil, hits
end

SLASH_MYUI1 = "/myui"
SLASH_MYUI2 = "/mui"

SlashCmdList["MYUI"] = function(input)
    ns.ClearOutput()
    local word, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
    if word == nil or word == "" then
        Help()
        return
    end

    local name, ambiguous = Resolve(word:lower())
    if not name then
        if ambiguous and #ambiguous > 1 then
            ns.Print(("%q is ambiguous: %s"):format(word, table.concat(ambiguous, ", ")))
        else
            ns.Print(("unknown command %q -- /myui help"):format(word))
        end
        return
    end

    local ok, err = pcall(HANDLERS[name], rest ~= "" and rest or nil)
    if not ok then
        ns.Print("|cfff26b61" .. tostring(err) .. "|r")
    end

    -- Persist for the off-disk route. SavedVariables are only flushed on
    -- /reload or logout, so this is readable after one of those, not before.
    -- copy is excluded so it cannot overwrite the output it exists to show.
    if ns.db and not ns.readOnlyDB and name ~= "copy" then
        ns.db.lastCommand = name
        ns.db.lastOutput  = ns.GetOutput()
    end
end
