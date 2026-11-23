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
    { "override",     "MyUI's replacements, one switch each: list | <name> on|off (off = Blizzard's)" },
    { "quests",       "the quest list (the tracker's replacement): toggles; bind MyUI -> Show the quest list" },
    { "copy",         "the last output in a selectable window" },
    { "show",         "force every frame to alpha 1, or release back to resting" },
    { "test",         "the acceptance checklist; test report | reset | <phase>" },
    { "outline",      "diagnostic boxes around every frame, above everything" },
    { "claims",       "who is claiming each frame, and every recent transition" },
    { "notify",       "send a toast: <hue> [name] [count] | demo | clear | dismiss" },
    { "sources",      "what feeds the toasts: thresholds, readings, latches" },
    { "log",          "the notification record: <hue> to filter | clear" },
    { "chat",         "the chat panel: toggles | probe | on | off (our edit box) | hide | show" },
    { "social",       "who's online: guild and friends; click a name to whisper" },
    { "center",       "the notification centre: <hue> to open filtered | close" },
    { "what",         "name whatever is under the cursor; bind MyUI -> Name what" },
    { "stow",         "take Blizzard furniture off the screen: raid | show raid" },
    { "extras",       "the non-MVP features: on | off (history, other toasts, our chat box, panel)" },
    { "panel",        "the dev panel: the toggles as switches (an extra)" },
    { "clear",        "clear the screen (SPEC 11): on | probe -- tests the player-frame filter" },
    { "restore",      "put back everything clearing took" },
    { "group",        "group frames per role: [tank|healer|dps] combat (default) | hover | always | list | boxes | icons" },
    { "actions",      "the action bar (probe P5): what each modifier pages to, and the driver" },
    { "pages",        "the pages not in bar 1's place: mini (small, over it; default) | swap (hidden)" },
    { "taint",        "which Blizzard frames MyUI has tainted (Edit Mode, debuffs, cooldown viewers)" },
    { "map",          "the map on a key: toggles | calm (corner minimap up out of combat) | peek (only when summoned)" },
    { "layout",       "preview where everything goes: toggles | use (MyUI's Edit Mode layout, for this character, on this spec)" },
    { "profile",      "layout profiles: list | <name> to switch | save <name> | delete <name>" },
    { "place",        "where a part goes, this character and screen size: list | <part> <place> | reset" },
    { "move",         "nudge a part of the HUD: self | target | focus | bar | group | zone | timers <dx> <dy> (SPEC units)" },
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
    { "report",       "write a debug report to MyUIDB.report; bind MyUI -> Write a debug report, which also reloads" },
    { "dev",          "the debug log: toggles | on | off | copy | clear" },
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
    override     = function(arg)
        local S = ns.Switches
        local key, state = (arg or ""):lower():match("^(%S*)%s*(%S*)$")
        if key ~= "" and S.BY_KEY[key] and (state == "on" or state == "off") then
            local s, reload = S.Set(key, state == "on")
            ns.Print(("%s: %s%s"):format(s.label, state == "on" and "MyUI's" or "Blizzard's",
                     reload and " -- |cffffd159/reload|r to apply" or ""))
            return
        end
        if key ~= "" and not S.BY_KEY[key] then
            ns.Print(("no switch %q"):format(key))
        end
        ns.Print("MyUI's replacements (off gives Blizzard's back):")
        for _, s in ipairs(S.LIST) do
            local on = S.On(s.key)
            ns.Raw(("  %s %-10s|r %s -- %s%s"):format(on and "|cffa6d98con |r" or "|cfff29e73off|r",
                   s.key, s.label, on and s.mine or "Blizzard's", s.reload and " (on /reload)" or ""))
        end
        ns.Raw("  /myui override <name> on|off")
    end,
    social       = function()
        if not ns.Social or not ns.Social.panel then
            ns.Print("who's online is off with the chat switch -- /myui override chat on")
            return
        end
        ns.Print(ns.Social.Toggle() and "online: open" or "online: closed")
    end,
    quests       = function()
        local Q = ns.Quests
        if not (Q and Q.Active()) then
            ns.Print("the quest list is off -- /myui override quests on")
            return
        end
        ns.Print(Q.Toggle() and "quest list: open (left-click a quest: waypoint; right-click: map)"
                            or "quest list: closed")
    end,
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
    pages        = function(arg)
        local A = ns.Actions
        if arg and A.SetStyle(arg) then
            ns.Print(arg == "mini" and "pages: the others small over bar 1" or "pages: one row, swapped on a modifier")
        else
            ns.Print(("pages: %s -- mini | swap"):format(A.Style()))
        end
    end,
    taint        = function()
        local check = _G.issecurevariable
        if not check then ns.Print("no issecurevariable on this client") return end
        ns.Print(("taint check (layout %s this session)"):format(
            ns.Clear.layoutUntouched and "untouched" or "saved by MyUI"))
        local probes = {
            { "EditModeManagerFrame", "layoutInfo" },
            { "DebuffFrame", "showDispelType" },
            { "DebuffFrame", "auraFrames" },
            { "BuffFrame", "auraFrames" },
            { "EssentialCooldownViewer", "iconScale" },
            { "BuffIconCooldownViewer", "iconScale" },
            { "BuffBarCooldownViewer", "iconScale" },
        }
        for _, pr in ipairs(probes) do
            local t = _G[pr[1]]
            if t then
                local ok, secure, by = pcall(check, t, pr[2])
                ns.Raw(("  %s.%s: %s"):format(pr[1], pr[2],
                    not ok and "?" or secure and "secure" or ("TAINTED by " .. tostring(by))))
            end
        end
    end,
    map          = function(arg)
        local R = ns.Reveal
        if arg and R.MAP_MODES[arg] then
            ns.db.map = arg
            R.Calm()
            ns.Print(arg == "calm" and "minimap: up out of combat" or "minimap: only when summoned (peek)")
        elseif not arg and ns.Map and ns.Map.Active() then
            -- Round 005: plain /myui map brings the map up (Map.lua).
            ns.Print(ns.Map.Toggle() and "map: open (wheel zooms; the world map is in its footer)" or "map: closed")
        else
            ns.Print(("minimap: %s -- calm | peek"):format(R.MapMode()))
        end
    end,
    layout       = function(arg)
        arg = (arg or ""):lower():gsub("%s+$", "")
        if arg == "use" then
            ns.Clear.Defer("layout-use", function()
                local ok, err = ns.Clear.ApplyLayout(true)
                if not ok then
                    ns.Print("layout: " .. tostring(err))
                elseif ns.Clear.layoutUntouched then
                    ns.Print(("layout: this spec already uses %q"):format(ns.Clear.LayoutName()))
                else
                    ns.Print(("layout: %q, this character's, on this spec -- |cffffd159/reload|r. "):format(ns.Clear.LayoutName())
                             .. "To leave it, choose another in Edit Mode.")
                end
            end)
            return
        end
        local size = ns.Clear.ScreenSize()
        if size then
            ns.Print(("this screen: %s (%s). Edit Mode layout here: %s"):format(size.name, size.what,
                     tostring((ns.Clear.ActiveLayoutName()))))
        end
        local on = ns.Layout.Preview()
        ns.Print(on and "layout preview: boxes where each part goes; drag one to a side of the screen to move it there, /myui layout to hide"
                    or "layout preview off")
    end,
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
    place        = function(arg)
        local P = ns.Places
        local key, place = (arg or ""):lower():match("^(%S*)%s*(%S*)$")
        if key == "reset" then
            local n, why = P.Reset()
            ns.Print(n and (n == 0 and "places: already as they come" or ("places: %d back"):format(n)) or why)
            return
        end
        if key ~= "" and place ~= "" then
            local p, changed = P.Set(key, place)
            if not p then ns.Print(changed)
            else
                ns.Print(("%s: %s%s"):format(P.BY_KEY[key].label, p.label, changed and "" or " already"))
            end
            return
        end
        local size = ns.Clear.ScreenSize()
        ns.Print(("places, for this character on this screen size (%s):"):format(size and size.name or "Wide"))
        for _, part in ipairs(P.PARTS) do
            local names = {}
            for i, p in ipairs(part.places) do
                names[i] = P.Of(part.key) == p.key and ("|cffffd159%s|r"):format(p.key) or p.key
            end
            ns.Raw(("  %-10s %s"):format(part.key, table.concat(names, " | ")))
        end
        ns.Raw("  /myui place <part> <place>, or drag the boxes in /myui layout; /myui place reset")
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
        local words = {}
        for w in (arg or ""):lower():gmatch("%S+") do words[#words + 1] = w end
        local role = Clear.GROUP_ROLE_WORDS[words[1] or ""]
        if role then table.remove(words, 1) end
        local word = words[1]
        if word then
            if Clear.GROUP_LOOKS[word] then
                Clear.SetGroupLook(word, role)
            elseif not Clear.SetGroupMode(word, role) then
                ns.Print(("unknown %q -- combat, hover, always, or list, boxes, icons"):format(word))
                return
            end
            if ns.Group and ns.Group.Apply and not ns.Group.Apply() and InCombatLockdown() then
                ns.Print("the new look waits for combat to end")
            end
        end
        local LABEL = { TANK = "tank", HEALER = "healer", DAMAGER = "dps" }
        local now = Clear.SettingRole()
        ns.Print(("group frames, per role (you are %s):"):format(LABEL[now]))
        for _, r in ipairs(Clear.GROUP_ROLES) do
            ns.Raw(("  %s %-7s %-7s %s"):format(r == now and ">" or " ", LABEL[r],
                Clear.GroupMode(r), Clear.GroupLook(r)))
        end
        ns.Raw("  /myui group [tank|healer|dps] combat|hover|always|list|boxes|icons")
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

        -- Round 005: plain /myui chat opens MyUI's chat panel (Talk.lua);
        -- /myui chat probe is the old override report.
        if arg == "" and ns.Talk and ns.Talk.Active() then
            ns.Print(ns.Talk.Toggle() and "chat: open (click a message to answer it)" or "chat: closed")
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
    dev          = function(arg)
        local Dev = ns.Dev
        arg = (arg or ""):lower():gsub("%s+$", "")
        if arg == "on" or arg == "off" then
            ns.db.dev = arg == "on" or nil
            if arg == "on" then Dev.Build() elseif Dev.IsOpen() then Dev.Close() end
            ns.Print(("debug log %s"):format(arg))
            if arg == "on" then ns.Raw("  bind MyUI -> Show the debug log, or /myui dev to open it") end
            return
        elseif arg == "copy" then
            Dev.Copy()
            return
        elseif arg == "clear" then
            local was = Dev.filter
            Dev.filter = nil
            local n = Dev.ClearShown()
            Dev.filter = was
            ns.Print(("debug log cleared: %d entries"):format(n))
            return
        elseif arg ~= "" then
            ns.Print(("unknown %q -- on, off, copy or clear"):format(arg))
            return
        end
        local ok, err = Dev.Toggle()
        if ok == false and err then ns.Print(err) end
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

-- ---------------------------------------------------------------------------
-- report: one key, everything a reader on another machine needs
-- ---------------------------------------------------------------------------
-- Round 005, on Windows: typing five commands and carrying their output to
-- another machine does not work. One key writes everything to MyUIDB.report
-- and reloads, because a reload is what puts saved variables on disk.
--
-- Built to leave the machine: it holds no chat, no names and no log text, only
-- what MyUI itself is doing. Every section but the first three is a report
-- MyUI already prints, run quietly.

local Report = { SCHEMA = 1, MAX_TEXT = 60000, RECENT = 15 }
ns.Commands = ns.Commands or {}
ns.Commands.Report = Report

Report.SECTIONS = { "version", "override", "audit", "claims", "sources", "taint" }

-- Every binding in Bindings.xml; a test keeps the two in step.
Report.BINDINGS = { "MYUI_PEEK", "MYUI_REPLY", "MYUI_CENTER", "MYUI_WHAT", "MYUI_ARRANGE",
                    "MYUI_QUESTS", "MYUI_TALK", "MYUI_SOCIAL", "MYUI_MAP", "MYUI_REPORT",
                    "MYUI_DEVLOG" }

local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d = pcall(fn, ...)
    if not ok then return nil end
    return a, b, c, d
end

local function Environment()
    local version, build, date_, toc = Call(_G.GetBuildInfo)
    ns.Raw(("client %s (%s, %s), interface %s"):format(tostring(version), tostring(build),
           tostring(date_), tostring(toc)))
    local pw, ph = Call(_G.GetPhysicalScreenSize)
    local ui = _G.UIParent
    ns.Raw(("screen %sx%s physical, UI %sx%s at scale %s"):format(tostring(pw), tostring(ph),
           tostring(Call(_G.GetScreenWidth)), tostring(Call(_G.GetScreenHeight)),
           tostring(ui and Call(ui.GetEffectiveScale, ui))))
    local layout = ns.Clear and Call(ns.Clear.ActiveLayoutName)
    ns.Raw(("edit mode layout %s, group frames %s %s, role %s"):format(tostring(layout),
           tostring(ns.Clear and Call(ns.Clear.GroupMode)), tostring(ns.Clear and Call(ns.Clear.GroupLook)),
           tostring(ns.Clear and Call(ns.Clear.Role))))
    ns.Raw(("extras %s -- off means no history window and toasts for whispers only")
           :format(ns.Extras() and "on" or "off"))
    ns.Raw(("debug log %s, map %s"):format(ns.Dev and ns.Dev.On() and "on" or "off",
           tostring(ns.Reveal and Call(ns.Reveal.MapMode))))
    local inInstance, kind = Call(_G.IsInInstance)
    ns.Raw(("in group %s, raid %s, instance %s (%s), combat %s"):format(
        tostring(Call(_G.IsInGroup)), tostring(Call(_G.IsInRaid)), tostring(inInstance),
        tostring(kind), tostring(Call(_G.InCombatLockdown))))
end

local function Bindings()
    for _, cmd in ipairs(Report.BINDINGS) do
        local keys = { Call(_G.GetBindingKey, cmd) }
        ns.Raw(("%-14s %s"):format(cmd, #keys > 0 and table.concat(keys, ", ") or "unbound"))
    end
end

-- Kinds, counts and ages only: a name in the log is a person.
local function Notifications()
    local db = ns.Log and ns.Log.db
    local entries = db and db.entries or {}
    local now, byKind, hour = ns.Log.Now(), {}, 0
    for _, e in ipairs(entries) do
        if now - (e.at or 0) <= 3600 then
            hour = hour + 1
            byKind[e.kind or "?"] = (byKind[e.kind or "?"] or 0) + 1
        end
    end
    local kinds = {}
    for k, n in pairs(byKind) do kinds[#kinds + 1] = ("%s %d"):format(k, n) end
    table.sort(kinds)
    ns.Raw(("%d in the log, %d in the last hour%s"):format(#entries, hour,
           #kinds > 0 and (": " .. table.concat(kinds, ", ")) or ""))
    for i = 1, math.min(Report.RECENT, #entries) do
        local e = entries[i]
        ns.Raw(("  -%ds  %s x%s"):format(now - (e.at or now), tostring(e.kind), tostring(e.count)))
    end
end

function Report.Write(handlers)
    local parts = {}
    local function take(title, fn)
        ns.ClearOutput()
        local ok, err = pcall(fn)
        local text = ns.GetOutput()
        if not ok then text = text .. "\nerror: " .. tostring(err) end
        parts[#parts + 1] = "## " .. title .. "\n" .. text
    end
    ns.quiet = true
    take("environment", Environment)
    take("bindings", Bindings)
    take("notifications", Notifications)
    for _, name in ipairs(Report.SECTIONS) do
        take(name, function() handlers[name]() end)
    end
    ns.quiet = nil
    local text = table.concat(parts, "\n\n")
    if #text > Report.MAX_TEXT then
        text = text:sub(1, Report.MAX_TEXT) .. "\n... (cut)"
    end
    if ns.db and not ns.readOnlyDB then
        ns.db.report = { schema = Report.SCHEMA, at = date("%Y-%m-%d %H:%M:%S"),
                         version = ns.version, text = text }
    end
    ns.ClearOutput()
    ns.Print(("debug report written: %d sections -- a /reload saves it to disk"):format(#parts))
    return text
end

HANDLERS.report = function() Report.Write(HANDLERS) end

-- The key: write, then reload, which is the only way to flush it. A key press
-- is a hardware event, so the reload is allowed where a timer's is not.
function MyUI_Report()
    ns.Commands.Run("report")
    if type(_G.ReloadUI) == "function" then _G.ReloadUI() end
end

_G.BINDING_NAME_MYUI_REPORT = "Write a debug report (reloads)"

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

-- The last commands and what they printed, each with its time, so a session
-- can be read off disk after a /reload or logout with nothing copied out of
-- chat. lastOutput alone lost every command but the last.
--
-- This holds whatever was typed and printed, names included. It stays in the
-- player's own saved variables; anything that shares it must filter it first.
local Trail = { KEEP = 50, MAX_TEXT = 8000 }
ns.Commands.Trail = Trail

local function Clip(text)
    if #text <= Trail.MAX_TEXT then return text end
    return text:sub(1, Trail.MAX_TEXT) .. "\n... (cut)"
end

function Trail.Add(name, rest)
    if not ns.db or ns.readOnlyDB then return nil end
    ns.db.outputs = type(ns.db.outputs) == "table" and ns.db.outputs or {}
    local list = ns.db.outputs
    local e = { at = date("%Y-%m-%d %H:%M:%S"), command = name, output = Clip(ns.GetOutput()) }
    if rest ~= nil and rest ~= "" then e.args = rest end
    list[#list + 1] = e
    while #list > Trail.KEEP do table.remove(list, 1) end
    Trail.open = e
    return e
end

--- Some commands go on printing (/myui mods, for 10 s). Before the buffer is
-- cleared for the next command, and at logout, the entry takes what came
-- after -- only if the buffer still continues it.
function Trail.Finish()
    local e = Trail.open
    Trail.open = nil
    if not e then return false end
    local now = Clip(ns.GetOutput())
    if #now > #e.output and now:sub(1, #e.output) == e.output then
        e.output = now
        return true
    end
    return false
end

local trailDriver = CreateFrame("Frame", "MyUITrailDriver")
trailDriver:RegisterEvent("PLAYER_LOGOUT")   -- fires on /reload too, before the save
trailDriver:SetScript("OnEvent", function() Trail.Finish() end)
Trail.driver = trailDriver

local function Run(input)
    Trail.Finish()
    ns.ClearOutput()
    local word, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
    if word == nil or word == "" then
        Help()
        return
    end

    -- A stray bracket or full stop on the command word (round 004 play:
    -- "/myui what]") should not make a known command unknown.
    local name, ambiguous = Resolve((word:lower():gsub("[^%w]+$", "")))
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
    if ns.Dev and ns.Dev.Command then
        pcall(ns.Dev.Command, name, rest, ns.GetOutput(), not ok and err or nil)
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
        Trail.Add(name, rest)
    end
end

ns.Commands.Run = Run
SlashCmdList["MYUI"] = Run
