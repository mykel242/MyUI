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

local function fmtSize(v)
    if type(v) ~= "number" then
        return "?"
    end
    return ("%.1f"):format(v)
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
        ns.Raw("  no frames registered")
    else
        if Registry.forced then
            ns.Raw("  |cffffd159debug: all frames forced to alpha 1|r")
        end
        ns.Raw(("  %-14s %6s %6s %6s %-7s %-14s %-18s %s")
               :format("FRAME", "REST", "TARG", "LIVE", "CLAIM", "SIZE",
                       "ANCHOR", "STRATA:LVL"))
        Registry.Each(function(entry)
            local w, h, p = Registry.Geometry(entry)
            local anchor = "-"
            if p then
                anchor = ("%s %+.1f %+.1f"):format(p.point or "?", p.x or 0, p.y or 0)
            end
            -- Strata and level are here because "the frame is missing" and "the
            -- frame is behind your action bars" look identical on screen.
            local strata = ns.Compat.Get(entry.frame, "GetFrameStrata")
            local level  = ns.Compat.Get(entry.frame, "GetFrameLevel")
            ns.Raw(("  %-14s %6s %6s %6s %-7s %-14s %-18s %s:%s"):format(
                entry.name, fmtAlpha(entry.resting), fmtAlpha(entry.target),
                fmtAlpha(ns.Compat.Get(entry.frame, "GetAlpha")),
                entry.claim or "-",
                ("%s x %s"):format(fmtSize(w), fmtSize(h)),
                anchor, tostring(strata), tostring(level)))
        end)

        local perfect, perUnit = ns.Scale.IsPixelPerfect()
        if perUnit then
            local note = "|cffa6d98cpixel-perfect|r"
            if not perfect then
                note = "|cffffd159not pixel-perfect -- hairlines will not render crisply|r"
            end
            ns.Raw(("  %.4f physical px per unit, %s"):format(perUnit, note))
        end
    end

    -- RULES: the audit reports whether the low-health summon can work.
    if ns.Bars then
        local ok, why = ns.Bars.SummonAvailable()
        ns.Raw(ok and "  low-health summon: |cffa6d98cavailable|r (Blizzard's 35%)"
                  or ("  low-health summon: |cffffd159unavailable|r -- " .. tostring(why)))
        if ns.Bars.curveProblems and #ns.Bars.curveProblems > 0 then
            ns.Raw("  |cfff26b61curves failed:|r " .. table.concat(ns.Bars.curveProblems, "; "))
        end
        if ns.Bars.castMode then
            ns.Raw("  last cast drove the bar by: " .. ns.Bars.castMode)
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
    { "show",         "force every frame to alpha 1, or release back to resting" },
    { "test",         "the acceptance checklist; test report | reset | <phase>" },
    { "outline",      "diagnostic boxes around every frame, above everything" },
    { "claims",       "who is claiming each frame, and every recent transition" },
    { "notify",       "send a toast: <hue> [name] [count] | demo | clear | dismiss" },
    { "sources",      "what feeds the toasts: thresholds, readings, latches" },
    { "log",          "the notification record: <hue> to filter | clear" },
    { "chat",         "our edit box instead of Blizzard's: on | off | hide | show" },
    { "center",       "the notification centre: <hue> to open filtered | close" },
    { "what",         "name whatever is under the cursor; bind MyUI -> Name what" },
    { "stow",         "take Blizzard furniture off the screen: raid | show raid" },
    { "extras",       "the non-MVP features: on | off (history, other toasts, our chat box, panel)" },
    { "panel",        "the dev panel: the toggles as switches (an extra)" },
    { "clear",        "clear the screen (SPEC 11): on | probe -- tests the player-frame filter" },
    { "restore",      "put back everything clearing took" },
    { "group",        "group frames in combat: combat (default) | auto (healers only) | hover" },
    { "actions",      "the action bar (probe P5): what each modifier pages to, and the driver" },
    { "profile",      "layout profiles: list | <name> to switch | save <name> | delete <name>" },
    { "move",         "nudge a part of the HUD: self | target | bar | group | zone | timers <dx> <dy> (SPEC units)" },
    { "spacing",      "wing spacing: gap <n> (bar to wing) | padding <n> (between icons) | debuffs <n> (bar to debuffs)" },
    { "bars",         "arrange the action bars: every page on screen, held, until you run it again" },
    { "mods",         "for 10s, what the client sees of ALT / CTRL / SHIFT (mouse-mapped modifiers)" },
    { "pct",          "where the health % sits: above (over the bar) | pill (on it)" },
    { "text",         "legibility over bright scenery: shadow | outline | none" },
    { "contrast",     "the dim grey: lift is SPEC 7; normal is the value it replaced" },
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
    actions      = function()
        local A = ns.Actions
        if not A then return end
        local r = A.Probe()
        ns.Print(("action bar (P5): %s"):format(r.built and "built" or "not built"))
        for _, line in ipairs(r.pages) do ns.Raw("  " .. line) end
        ns.Raw(("  driver: %s"):format(tostring(r.driver)))
        ns.Raw(("  page now: %s (parse: %s), bar-1 button 1 -> slot %s")
               :format(tostring(r.state), tostring(r.parsed), tostring(r.action1)))
        ns.Raw(("  %s keys moved onto MyUI's buttons%s"):format(tostring(r.nbinds),
               r.unbound and " -- handed back to Blizzard right now (vehicle?)" or ""))
        ns.Raw("  Blizzard's bars (want alpha 0, drawn at 0, mouse false):")
        for _, line in ipairs(r.blizzard or {}) do ns.Raw("    " .. line) end
        ns.Raw("  saved to MyUIDB.actionsProbe. /myui mods checks the modifier keys.")
    end,
    bars         = function() _G.MyUI_ArrangeBars() end,
    profile      = function(arg)
        local L = ns.Layout
        local verb, name = (arg or ""):match("^(%S*)%s*(.-)$")
        if verb == "" then
            ns.Print(("layout profile: %s"):format(L.Active()))
            for _, n in ipairs(L.Names()) do
                ns.Raw(("  %s%s%s"):format(n == L.Active() and "> " or "  ", n,
                       L.PRESETS[n] and " (built in)" or ""))
            end
            ns.Raw("  |cffadb1b8/myui profile <name>|r switches; /myui move nudges (makes \"mine\")")
        elseif verb == "save" and name ~= "" then
            L.Save(name)
            ns.Print(("saved the layout as %q and switched to it"):format(name))
        elseif verb == "delete" and name ~= "" then
            ns.Print(L.Delete(name) and ("deleted %q"):format(name) or ("no saved profile %q"):format(name))
        elseif L.Use(verb) then
            ns.Print(("layout profile: %s%s"):format(verb, InCombatLockdown() and " (the bar and group frames move after combat)" or ""))
        else
            ns.Print(("no profile %q -- /myui profile lists them"):format(verb))
        end
    end,
    move         = function(arg)
        local key, dx, dy = (arg or ""):match("^(%S+)%s+(%-?%d+)%s+(%-?%d+)$")
        if not key then
            ns.Print("/myui move <self | target | bar | group | zone | timers> <dx> <dy> -- e.g. /myui move target 0 20")
            return
        end
        local which, x, y = ns.Layout.Move(key, tonumber(dx), tonumber(dy))
        if not which then
            ns.Print(("can't move %q -- self, target, bar, group, zone or timers"):format(key))
        else
            ns.Print(("%s now at %d, %d (profile %s)"):format(which, x, y, ns.Layout.Active()))
        end
    end,
    spacing      = function(arg)
        local what, n = (arg or ""):match("^(%a+)%s+(%d+)$")
        local key = what == "gap" and "wingGap" or what == "padding" and "iconPadding"
                    or what == "debuffs" and "debuffGap" or nil
        if not key then
            ns.Print(("wing gap %d, icon padding %d -- /myui spacing gap <n> | padding <n>")
                     :format(ns.Layout.Value("wingGap"), ns.Layout.Value("iconPadding")))
            return
        end
        ns.Layout.Set(key, tonumber(n))
        ns.Print(("%s %s (profile %s)"):format(what, n, ns.Layout.Active()))
    end,
    mods         = function()
        if not ns.Actions then return end
        ns.Print("watching the modifier keys for 10s -- hold each key, then each mouse button")
        ns.Actions.WatchMods(10)
    end,
    pct          = function(arg)
        local Frames = ns.Frames
        if arg and Frames.SetPctStyle(arg) then
            ns.Print(("health %% %s"):format(arg == "pill" and "on its bar, on a pill" or "just above its bar"))
        elseif arg then
            ns.Print(("unknown style %q -- pill or above"):format(arg))
        else
            ns.Print(("health %% style: %s -- pill | above"):format(Frames.PctStyle()))
        end
    end,
    show         = function(arg)
        local on
        if arg == "off" then
            on = false
        elseif arg == "on" then
            on = true
        else
            on = not Registry.forced
        end
        Registry.ForceVisible(on)
        ns.Frames.Placeholders(on)
        if on then
            ns.Print("all frames at alpha 1, with placeholder text and a nominal "
                     .. "bar fill so geometry can be judged. "
                     .. "|cffadb1b8/myui show off|r to release.")
        else
            ns.Print("frames released to their resting alphas, placeholders cleared.")
        end
    end,
    -- SPEC.md 6 specifies the rail completely and never says what produces a
    -- notification. Rather than invent a data binding the design did not ask
    -- for, Phase 3 ships this as the source, which is also what the acceptance
    -- test needs: eight at once, on demand.
    contrast     = function(arg)
        local Frames = ns.Frames
        if arg and Frames.CONTRAST_LEVELS[arg] then
            if ns.db then
                ns.db.contrast = arg
            end
            Frames.RestyleText()
        elseif arg and arg ~= "" then
            ns.Print(("unknown level %q -- normal or lift"):format(arg))
            return
        end
        ns.Print("contrast: |cfff0f1f3" .. Frames.Contrast() .. "|r")
        ns.Raw("  A shadow rescues light text on a light backdrop and does nothing "
               .. "for the dim grey.")
        ns.Raw("  |cffadb1b8lift|r is rgba(173,177,184,1) -- textDim, and since the "
               .. "SPEC 7 amendment simply the spec.")
        ns.Raw("  |cffadb1b8normal|r is rgba(115,119,126,1), the value it replaced: "
               .. "unreadable over ordinary terrain,")
        ns.Raw("  no longer a palette entry, and kept only so the original intent "
               .. "can still be looked at.")
    end,
    text         = function(arg)
        local Frames = ns.Frames
        if arg and Frames.TEXT_STYLES[arg] then
            if ns.db then
                ns.db.textStyle = arg
            end
            Frames.RestyleText()
        elseif arg and arg ~= "" then
            ns.Print(("unknown style %q -- shadow, outline or none"):format(arg))
            return
        end
        ns.Print("text: |cfff0f1f3" .. Frames.TextStyle() .. "|r")
        ns.Raw("  SPEC's palette is light-on-dark and washes out over bright "
               .. "scenery. shadow uses the palette's existing")
        ns.Raw("  tick colour, so no fifteenth colour is introduced. outline is "
               .. "stronger but thickens the type.")
    end,
    notify       = function(arg)
        local Toast = ns.Toast
        arg = arg or ""

        if arg == "clear" then
            Toast.Clear()
            ns.Print("toasts cleared (the log keeps everything)")
            return
        end
        if arg == "dismiss" then
            if Toast.Dismiss() then
                ns.Print("toast dismissed")
            else
                ns.Print("nothing to dismiss")
            end
            return
        end
        if arg == "demo" then
            -- One of each hue: more than the stack's cap, so the oldest is
            -- seen to leave, and every hue lands in the log.
            local kinds = { "blue", "amber", "green", "violet", "orange" }
            for i, kind in ipairs(kinds) do
                Toast.Add(kind, "Notice " .. i, i % 3 + 1)
            end
            ns.Print(("sent %d -- %d speaking (cap %d), all %d in the log")
                     :format(#kinds, #Toast.live, Toast.CAP, #kinds))
            return
        end

        local kind, name, count = arg:match("^(%a+)%s*(.-)%s*(%d*)$")
        if not kind or kind == "" then
            ns.Print("usage: /myui notify <blue|amber|green|violet|orange> "
                     .. "[name] [count], or demo | clear | dismiss")
            return
        end
        local item, why = Toast.Add(kind, name ~= "" and name or nil, count)
        if not item then
            ns.Print(why)
            return
        end
        ns.Print(("%s: %s x%d -- %d speaking")
                 :format(item.kind, item.name, item.count, #Toast.live))
    end,
    -- SPEC 6's sources are conditions as much as events, and a condition that
    -- has already latched looks exactly like one that never fired. This prints
    -- the readings beside the latches so the two can be told apart -- which is
    -- the only way to check the stream rule in game without filling your bags
    -- twice.
    -- Toasts forget on purpose; the log is the record, so it needs to be
    -- readable without opening the SavedVariables file.
    log          = function(arg)
        local Log = ns.Log
        if not Log or not Log.db then
            ns.Print("no log")
            return
        end
        arg = (arg or ""):lower():gsub("%s+$", "")

        if arg == "clear" then
            local n = Log.Count()
            Log.Clear()
            ns.Print(("cleared %d entries."):format(n))
            return
        end

        local kind = arg ~= "" and arg or nil
        if kind and not ns.Toast.HUES[kind] then
            ns.Print(("unknown hue %q -- blue, amber, green, violet, orange"):format(kind))
            return
        end

        local tally = Log.Tally()
        ns.Print(("%d kept, per character, ceiling %d"):format(Log.Count(), Log.MAX))
        local counts = {}
        for hue in pairs(ns.Toast.HUES) do
            counts[#counts + 1] = ("%s %d"):format(hue, tally[hue] or 0)
        end
        table.sort(counts)
        ns.Raw("  " .. table.concat(counts, "   "))

        local rows = Log.Filter(kind, 15)
        if #rows == 0 then
            ns.Raw("  nothing recorded" .. (kind and (" for " .. kind) or ""))
            return
        end
        for _, e in ipairs(rows) do
            local when = date and date("%H:%M:%S", e.at) or tostring(e.at)
            ns.Raw(("  %s  %-7s %s%s"):format(
                tostring(when), e.kind, tostring(e.name),
                (e.count or 1) > 1 and (" x" .. e.count) or ""))
        end
        if Log.Count(kind) > #rows then
            ns.Raw(("  ... %d more"):format(Log.Count(kind) - #rows))
        end
    end,

    -- FOUND IN GAME: CompactRaidFrameManager is 221x361 at the left edge,
    -- exactly where the rail lives, and appears whenever you are in a group or
    -- Edit Mode is force-showing party frames.
    stow         = function(arg)
        local Stow = ns.Stow
        if not Stow then
            ns.Print("no stow module")
            return
        end
        arg = (arg or ""):lower():gsub("%s+$", "")
        local show, group = arg:match("^(show)%s+(%a+)$")
        group = group or arg

        if group == "" then
            ns.Print("what is off the screen")
            for name, spec in pairs(Stow.GROUPS) do
                ns.Raw(("  %-6s %-8s %s"):format(
                    name, Stow.IsStowed(name) and "stowed" or "visible", spec.label))
            end
            ns.Raw("  |cffadb1b8/myui stow raid|r to hide one, "
                   .. "|cffadb1b8/myui stow show raid|r to bring it back")
            return
        end
        if not Stow.GROUPS[group] then
            ns.Print(("no such group %q"):format(group))
            return
        end

        if show then
            local back, err = Stow.Restore(group)
            if ns.db and group == "raid" then ns.db.stow.raid = false end
            ns.Print(back and ("%d frame(s) back."):format(back) or tostring(err))
            return
        end

        local moved, err = Stow.Group(group)
        if not moved then
            ns.Print(tostring(err))
            return
        end
        if ns.db and group == "raid" then ns.db.stow.raid = true end
        ns.Print(("%d frame(s) stowed -- %s"):format(moved, Stow.GROUPS[group].label))
    end,

    what         = function()
        if ns.Outline and ns.Outline.Under then
            ns.Outline.Under()
        else
            ns.Print("no diagnostics module")
        end
    end,

    center       = function(arg)
        local Center = ns.Center
        if not Center then
            ns.Print("no centre module")
            return
        end
        if not ns.Extras() then
            ns.Print("the history window is an extra -- /myui extras on, then /reload")
            return
        end
        arg = (arg or ""):lower():gsub("%s+$", "")
        if arg == "close" then
            Center.Close()
            ns.Print("centre closed.")
            return
        end
        if arg ~= "" and not ns.Toast.HUES[arg] then
            ns.Print(("unknown hue %q -- blue, amber, green, violet, orange"):format(arg))
            return
        end
        Center.Open(arg ~= "" and arg or nil)
        ns.Print(("centre open%s. Escape or the binding closes it.")
                 :format(arg ~= "" and (", filtered to " .. arg) or ""))
    end,

    clear        = function(arg)
        local Clear = ns.Clear
        arg = (arg or ""):lower():gsub("%s+$", "")
        if arg == "probe" then
            local r = Clear.ProbePlayer()
            if r.error then
                ns.Print("probe: " .. r.error)
                return
            end
            ns.Print(("player-frame filter: SetRolesets %s, filtered %s, visible %s -> %s; restored %s")
                     :format(r.setOk and "ok" or ("failed: " .. tostring(r.setError)),
                             tostring(r.filtered), tostring(r.visibleBefore),
                             tostring(r.visibleDuring), tostring(r.restored)))
            return
        end
        local n = Clear.Apply()
        ns.Print(("clearing on -- %d Blizzard frame(s) adopted at alpha 0; "):format(n)
                 .. "peek or hover summons them. |cffadb1b8/myui restore|r undoes it.")
    end,
    group        = function(arg)
        local Clear = ns.Clear
        arg = (arg or ""):lower():gsub("%s+$", "")
        if arg ~= "" and not Clear.SetGroupMode(arg) then
            ns.Print(("unknown mode %q -- auto, combat or hover"):format(arg))
            return
        end
        ns.Print(("group frames: %s -- %s in combat (role %s)"):format(Clear.GroupMode(),
            Clear.GroupInCombat() and "shown" or "not shown", Clear.Role()))
    end,
    restore      = function()
        local n, needsReload = ns.Clear.Restore()
        ns.Print(("restored -- %d adopted frame(s) back at their own alpha, "):format(n)
                 .. "your previous Edit Mode layout reselected.")
        if needsReload then
            ns.Raw("  |cffffd159/reload|r to bring back the player, target and focus frames.")
        end
        ns.Raw("  |cffadb1b8/myui clear|r clears again.")
    end,
    extras       = function(arg)
        arg = (arg or ""):lower():gsub("%s+$", "")
        if arg == "on" or arg == "off" then
            if ns.db then ns.db.extras = (arg == "on") end
            ns.Print(("extras %s -- |cffffd159/reload|r to apply."):format(arg))
            return
        end
        ns.Print(("extras: %s. MVP leaves them off: the history window, toast sources "
                  .. "other than whispers, MyUI's chat box, the dev panel."):format(
                  ns.Extras() and "on" or "off"))
    end,
    panel        = function()
        if not ns.Panel or not ns.Panel.panel then
            ns.Print("the dev panel is an extra -- /myui extras on, then /reload")
            return
        end
        ns.Panel.Toggle()
        ns.Print(ns.Panel.IsOpen() and "panel open." or "panel closed.")
    end,
    chat         = function(arg)
        local Chat = ns.Chat
        if not Chat then
            ns.Print("no chat module")
            return
        end
        arg = (arg or ""):lower():gsub("%s+$", "")

        if arg == "hide" then
            if not Chat.IsOverriding() then
                ns.Print("not while the override is off -- you would have no way to type.")
                return
            end
            Chat.HideLog()
            if ns.db then ns.db.chat = ns.db.chat or {}; ns.db.chat.hideLog = true end
            ns.Print(("chat log stowed -- %d frame(s) out of sight."):format(Chat.StowedCount()))
            ns.Raw("  Enter still opens ours, / still opens Blizzard's.")
            ns.Raw("  |cffadb1b8/myui chat show|r brings the furniture back")
            return
        elseif arg == "show" then
            Chat.ShowLog()
            if ns.db then ns.db.chat = ns.db.chat or {}; ns.db.chat.hideLog = false end
            ns.Print("chat log back. A /reload restores Blizzard's exact layout.")
            return
        elseif arg == "off" then
            Chat.Disable()
            if ns.db then ns.db.chat = ns.db.chat or {}; ns.db.chat.override = false end
            ns.Print("override cleared -- Enter opens Blizzard's chat box again.")
            return
        elseif arg == "on" then
            local ok, err = Chat.Enable()
            if ns.db then ns.db.chat = ns.db.chat or {}; ns.db.chat.override = true end
            ns.Print(ok and "override installed -- Enter opens ours."
                        or ("could not install: " .. tostring(err)))
            return
        end

        local p = Chat.Probe()
        ns.Print(("chat override %s"):format(Chat.IsOverriding() and "installed" or "NOT installed"))
        if Chat.lastError then
            ns.Raw("  |cfff26b61why|r        " .. tostring(Chat.lastError))
        end
        if Chat.route then
            ns.Raw("  via        " .. tostring(Chat.route))
        end
        -- What this client really offers. The reference dump is 12.1.0.69497
        -- and the live build can differ; guessing is what cost the first try.
        ns.Raw(("  client     ChatFrameUtil %s, Set %s, Get %s, Clear %s, OpenChat %s")
               :format(p.util and "yes" or "NO", p.set and "yes" or "NO",
                       p.get and "yes" or "NO", p.clear and "yes" or "NO",
                       p.open and "yes" or "NO"))
        ns.Raw("  legacy     ChatFrame_SetChatFocusOverride "
               .. (p.legacySet and "yes" or "NO"))
        ns.Raw("  global     CHAT_FOCUS_OVERRIDE is "
               .. (p.globalHeld == nil and "nil"
                   or (p.globalHeld == Chat.box and "ours" or "someone else's")))
        -- The question the reference source cannot answer, so we watch for it.
        -- Expected, not a fault: ChatFrameUtil.ActivateChat drops the
        -- override as its first line, and pressing "/" goes through it.
        ns.Raw(("  taken back %d time(s) by ActivateChat, put back %d -- expected")
               :format(Chat.clears or 0, Chat.reasserts or 0))
        if Chat.displacedBy then
            ns.Raw("  displaced by " .. tostring(Chat.displacedBy))
        end
        if Chat.clearedBy then
            for line in tostring(Chat.clearedBy):gmatch("[^\n]+") do
                if line:find("%S") then ns.Raw("    " .. line) end
            end
        end
        ns.Raw("  our box    " .. (Chat.box and Chat.box:GetName() or "not built"))
        ns.Raw("  Blizzard's " .. (function()
            local b = Chat.SendBox()
            return b and (b.GetName and b:GetName() or "found") or "NOT FOUND -- sending would fail"
        end)())
        ns.Raw("  talking to " .. Chat.Label())
        ns.Raw(("  log        %s (%d frame(s) stowed)")
               :format(Chat.logHidden and "hidden" or "visible", Chat.StowedCount()))
        ns.Raw("  edit box   " .. (Chat.editBoxFreed
               and "moved out of the chat frame, so / still works"
               or "still inside Blizzard's chat frame"))
        -- The flag is the reason the chat frame gets hidden and never removed.
        ns.Raw("  slash commands " .. (Chat.SUPPORTS_SLASH and "come here"
               or "fall through to Blizzard, which is why its frame has to stay"))
        ns.Raw("  |cffadb1b8/myui chat off|r puts the game back exactly as it was")
    end,

    sources      = function()
        local Sources = ns.Sources
        if not Sources then
            ns.Print("no sources module")
            return
        end
        ns.Print("what feeds the toasts -- SPEC 6, five hues")
        ns.Raw("  |cff8cc8ffblue|r   loot     |cffffd159amber|r  quests    "
               .. "|cffa6d98cgreen|r  currency, reputation")
        ns.Raw("  |cffd1b3ffviolet|r achievements        "
               .. "|cfff29e73orange|r mail, bags, durability, invites")
        ns.Raw(" ")
        ns.Raw(("  loot at quality |cfff0f1f3%d|r and above")
               :format(Sources.Setting("lootQuality")))
        ns.Raw(("  durability warns at |cfff0f1f3%d%%|r")
               :format(Sources.Setting("durability") * 100))
        ns.Raw(("  bags warn at |cfff0f1f3%d|r free slots or fewer")
               :format(Sources.Setting("bagFree")))
        ns.Raw(" ")

        local free = Sources.FreeBagSlots()
        local worn = Sources.WorstDurability()
        ns.Raw(("  reading now: %s free slots, worst durability %s"):format(
            free and tostring(free) or "|cffadb1b8unreadable|r",
            worn and ("%d%%"):format(worn * 100) or "|cffadb1b8unreadable|r"))

        local held = {}
        for key in pairs(Sources.latched) do
            held[#held + 1] = key
        end
        table.sort(held)
        if #held == 0 then
            ns.Raw("  nothing latched -- every condition would speak if it became true")
        else
            ns.Raw("  latched (already spoken, will not repeat): |cfff26b61"
                   .. table.concat(held, ", ") .. "|r")
        end
    end,
    claims       = function(arg)
        local Reveal = ns.Reveal
        if arg == "clear" then
            Reveal.ClearLog()
            ns.Print("transition log cleared")
            return
        end

        ns.Print("claims now")
        Registry.Each(function(entry)
            local holding = Reveal.ClaimsOn(entry.name)
            local who = "|cffadb1b8none|r"
            if #holding > 0 then
                who = table.concat(holding, ", ")
            end
            ns.Raw(("  %-14s %6s  %s"):format(
                entry.name, fmtAlpha(entry.target), who))
        end)

        local log = Reveal.log
        ns.Raw(" ")
        if #log == 0 then
            ns.Raw("  no transitions recorded. |cffadb1b8/myui claims clear|r resets this.")
            return
        end

        -- Relative times, because the absolute ones mean nothing to a reader
        -- and the whole question is how long ago something happened.
        local now = Reveal.Now()
        ns.Print(("recent transitions (%d)"):format(#log))
        for _, e in ipairs(log) do
            local when = ("-%.1fs"):format(now - e.at)
            if e.kind == "change" then
                ns.Raw(("  %7s     %-14s %s -> %s   %s"):format(
                    when, e.frame, fmtAlpha(e.from), fmtAlpha(e.to),
                    e.winner or "|cffadb1b8released|r"))
            else
                -- Inputs are indented left of outcomes, so a glance separates
                -- what you did from what the arbiter decided about it.
                local mark = "|cffa6d98c+|r"
                if e.kind == "release" then
                    mark = "|cfff26b61-|r"
                end
                ns.Raw(("  %7s  %s %s %s"):format(
                    when, mark, e.channel, e.frame or "|cffadb1b8(all)|r"))
            end
        end
    end,
    outline      = function(arg)
        local on
        if arg == "off" then
            on = false
        elseif arg == "on" then
            on = true
        else
            on = nil
        end
        local shown = ns.Outline.Toggle(on)
        if shown then
            ns.Print("outlines on. A box with nothing visible inside it means the "
                     .. "frame is placed correctly but hidden behind something.")
        else
            ns.Print("outlines off.")
        end
    end,
    test         = function(arg)
        if arg == "report" then
            ns.Testing.Report()
            return
        end
        if arg == "reset" then
            ns.Testing.Reset()
            ns.Print("acceptance run reset for phase " .. tostring(ns.Testing.phase))
            return
        end
        ns.Testing.Show(tonumber(arg))
    end,
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

-- Exposed so the panel's switches run the same path a typed command does.
-- A second way to change state is a second thing to keep in agreement; there
-- is only one.
ns.Commands = ns.Commands or {}

local function Run(input)
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

    -- Every command is noted, so acceptance steps can wait on the one that
    -- performs them rather than reading FAIL before you have run it.
    ns.Testing.Note(name, rest)

    -- Latch the checklist against the state as it is NOW. Without this the
    -- auto-checks are only evaluated when the report is run, by which point the
    -- sequence has moved on and they describe the wrong moment.
    if name ~= "test" then
        pcall(ns.Testing.Sync)
    end

    -- Persist for the off-disk route. SavedVariables are only flushed on
    -- /reload or logout, so this is readable after one of those, not before.
    -- copy is excluded so it cannot overwrite the output it exists to show.
    if ns.db and not ns.readOnlyDB and name ~= "copy" then
        ns.db.lastCommand = name
        ns.db.lastOutput  = ns.GetOutput()
    end
end

ns.Commands.Run = Run
SlashCmdList["MYUI"] = Run
