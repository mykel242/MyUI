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
-- The naive probe does not work. At full health a conditional that exists and
-- evaluates false is indistinguishable from one the parser never heard of --
-- both miss. So each candidate is tested in both its plain and negated forms,
-- and measured against two controls:
--
--   known    [combat] / [nocombat]   -- one hits, one misses. Proves the probe.
--   unknown  a deliberate nonsense conditional. Establishes what "the parser
--            does not know this" looks like on THIS client, rather than
--            assuming it.
--
-- A candidate whose signature differs from the unknown control is real. That
-- holds at any health, so this can be run standing in a city.

local CANDIDATES = {
    { label = "control: known",   yes = "[combat]",              no = "[nocombat]" },
    { label = "control: unknown", yes = "[zzznotaconditional]",  no = "[nozzznotaconditional]" },
    { label = "hp",               yes = "[hp<20]",               no = "[nohp<20]" },
    { label = "hp, unit-scoped",  yes = "[@player,hp<20]",       no = "[@player,nohp<20]" },
    { label = "health",           yes = "[health<20]",           no = "[nohealth<20]" },
    { label = "health, scoped",   yes = "[@player,health<20]",   no = "[@player,nohealth<20]" },
    { label = "hurt",             yes = "[@player,hurt]",        no = "[@player,nohurt]" },
    { label = "lowhealth",        yes = "[lowhealth]",           no = "[nolowhealth]" },
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

local function Conditionals()
    local parse = _G.SecureCmdOptionParse
    if type(parse) ~= "function" then
        ns.Print("SecureCmdOptionParse is unavailable on this client")
        return
    end

    local rows, unknown = {}, nil
    for i, c in ipairs(CANDIDATES) do
        local row = { label = c.label, yes = c.yes,
                      a = Evaluate(parse, c.yes), b = Evaluate(parse, c.no) }
        rows[i] = row
        if c.label == "control: unknown" then
            unknown = row.a .. "/" .. row.b
        end
    end

    ns.Print("macro conditional probe")
    ns.Raw(("  %-17s %-24s %-6s %-6s  %s"):format("", "CLAUSE", "PLAIN", "NEG", "VERDICT"))
    for _, row in ipairs(rows) do
        local verdict
        if row.label:find("control", 1, true) then
            verdict = "|cffadb1b8--|r"
        elseif (row.a .. "/" .. row.b) == unknown then
            verdict = "|cfff26b61not recognised|r"
        else
            verdict = "|cffa6d98cRECOGNISED|r"
        end
        ns.Raw(("  %-17s %-24s %-6s %-6s  %s"):format(row.label, row.yes, row.a, row.b, verdict))
    end

    ns.Raw(" ")
    ns.Raw("  The known control must show one hit and one miss. If it does not, the")
    ns.Raw("  probe is broken rather than the conditionals missing.")
    ns.Raw(" ")
    ns.Raw("  Every candidate 'not recognised': SPEC.md 3's driver state has no event")
    ns.Raw("  source. The breathe and the screen hairline still work on curve-driven")
    ns.Raw("  alpha; only the 12pt->14pt change needs the two-FontString cross-fade.")
    ns.Raw("  Any candidate RECOGNISED: SPEC.md 3 ships as written. Confirm it by")
    ns.Raw("  running this again below the threshold -- it should flip to a hit.")
    ns.Raw("  See API-NOTES-12.1.md 4.")
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
end
