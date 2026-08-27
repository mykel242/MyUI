-- MyUI :: Testing.lua
-- The in-game acceptance checklist.
--
-- PLAN.md ends every phase with an in-game test, and those tests are the only
-- ones that matter -- the offline suite cannot see a frame in the wrong place
-- or a hairline that renders grey. But reading a test script off a second
-- screen is how steps get skipped.
--
-- So the script lives in the addon. Steps MyUI can verify itself carry a check
-- function and answer on their own; the rest are the ones that genuinely need
-- your eyes, and those get a pass/fail button. The result is written to
-- SavedVariables, so a finished run can be read off disk after a /reload
-- rather than transcribed.

local ADDON, ns = ...

local Testing = {}
ns.Testing = Testing

local Registry, Scale = ns.Registry, ns.Scale

-- ---------------------------------------------------------------------------
-- The scripts
-- ---------------------------------------------------------------------------
-- Each step: what to do, what to expect, and optionally a check that decides
-- for itself. A check returns ok, detail.

-- These compare the registry's own target alpha, not the frame's. From Phase 4
-- a frame carrying a forwarded secret returns a secret from GetAlpha, so an
-- auto-check that reads the frame back would start failing on a UI that is
-- perfectly correct. What the eye is for is the step immediately after each of
-- these, which asks whether the frames actually look right.

local function everyFrameAt(alpha)
    local bad
    Registry.Each(function(entry)
        if type(entry.target) ~= "number" or math.abs(entry.target - alpha) > 0.001 then
            bad = bad or entry.name
        end
    end)
    if bad then
        return false, "first mismatch: " .. bad
    end
    return true, Registry.Count() .. " frames targeted at " .. alpha
end

local function everyFrameResting()
    local bad
    Registry.Each(function(entry)
        if type(entry.target) ~= "number"
           or math.abs(entry.target - entry.resting) > 0.001 then
            bad = bad or entry.name
        end
    end)
    if bad then
        return false, "first mismatch: " .. bad
    end
    return true, "all back to resting"
end

-- SPEC.md 2's table, restated here so the test asserts against the spec rather
-- than against whatever Frames.lua happens to have registered.
local SPEC_RESTING = {
    SelfStack = 0.35, Cooldowns = 0.25, TargetStrip = 0, Rail = 1,
}

Testing.scripts = {
    [0] = {
        title = "Phase 0 — skeleton and compliance harness",
        accept = "/reload clean, zero Lua errors, nothing visible on screen.",
        steps = {
            { act = "Type /reload and wait for the UI to come back.",
              expect = "No Lua error popup. MyUI prints one loaded line." },
            { act = "Look at the screen.",
              expect = "Nothing from MyUI is visible. Phase 0 draws nothing." },
            { act = "Type /myui rules",
              expect = "The principle, six prohibitions, four mechanisms." },
            { act = "Type /myui audit",
              expect = "A clean guard: 0 violations.",
              check = function()
                  local n = #ns.Guard.violations
                  if n == 0 then return true, "0 violations" end
                  return false, n .. " violations"
              end },
            { act = "Type /myui conditionals",
              expect = "The known control differs from the unknown one." },
        },
    },

    [1] = {
        title = "Phase 1 — anchors and frame registry",
        accept = "Debug toggle shows every frame; positions and sizes match the "
              .. "mock; audit lists each frame with its spec resting alpha.",
        steps = {
            { act = "Type /myui show",
              expect = "Four frames appear at full opacity.",
              check = function()
                  if not Registry.forced then
                      return false, "not forced -- run /myui show first"
                  end
                  return everyFrameAt(1)
              end },
            { act = "Look at the bottom centre of the screen.",
              expect = "A narrow horizontal bar group sitting well above the "
                    .. "bottom edge: a wide bar, a thinner one under it, a "
                    .. "third below that, and a number to their left." },
            { act = "Look along the health bar for two vertical ticks.",
              expect = "One dark tick a fifth of the way across, one pale tick "
                    .. "two fifths across. Both exactly one pixel wide." },
            { act = "Look at the top centre of the screen.",
              expect = "A wide thin bar with empty name and level rows above it." },
            { act = "Look at the far left edge, vertically centred.",
              expect = "A single vertical hairline, crisp, not a grey smear." },
            { act = "Type /myui audit",
              expect = "Four frames with resting alphas 0.35, 0.25, 0.00, 1.00.",
              check = function()
                  for name, want in pairs(SPEC_RESTING) do
                      local entry = Registry.Get(name)
                      if not entry then return false, name .. " missing" end
                      if math.abs(entry.resting - want) > 0.001 then
                          return false, ("%s rests at %.2f, spec says %.2f")
                                        :format(name, entry.resting, want)
                      end
                  end
                  return true, "all four match SPEC 2"
              end },
            { act = "Read the px-per-unit line at the bottom of the audit.",
              expect = "Reports pixel-perfect.",
              check = function()
                  local perfect, perUnit = Scale.IsPixelPerfect()
                  if perUnit == nil then return false, "could not measure" end
                  if perfect then
                      return true, ("%.4f px per unit"):format(perUnit)
                  end
                  return false, ("%.4f px per unit -- hairlines will smear")
                                :format(perUnit)
              end },
            { act = "Type /myui show off",
              expect = "The target strip vanishes completely. The others dim "
                    .. "but stay visible. Nothing moves.",
              check = function()
                  if Registry.forced then
                      return false, "still forced -- run /myui show off"
                  end
                  return everyFrameResting()
              end },
            { act = "Type /myui show again, and watch closely.",
              expect = "Frames return in exactly the same positions. Nothing "
                    .. "shifts by a pixel." },
        },
    },
}

-- ---------------------------------------------------------------------------
-- The window
-- ---------------------------------------------------------------------------
-- Deliberately plain: this is a tool, not part of the design. It uses Blizzard
-- font objects and button templates rather than MyUI's palette, so nothing here
-- can be mistaken for the HUD or quietly introduce a fifteenth colour.

local window, rows, tallyText

local ROW_H, TEXT_W = 52, 520

local function BuildRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(TEXT_W + 150, ROW_H)

    row.num = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.num:SetPoint("TOPLEFT", 0, -2)
    row.num:SetText(tostring(index) .. ".")

    row.mark = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.mark:SetPoint("TOPLEFT", 22, -2)
    row.mark:SetWidth(46)
    row.mark:SetJustifyH("LEFT")

    row.act = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.act:SetPoint("TOPLEFT", 72, -2)
    row.act:SetWidth(TEXT_W)
    row.act:SetJustifyH("LEFT")

    row.expect = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.expect:SetPoint("TOPLEFT", row.act, "BOTTOMLEFT", 0, -2)
    row.expect:SetWidth(TEXT_W)
    row.expect:SetJustifyH("LEFT")

    row.pass = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.pass:SetSize(52, 20)
    row.pass:SetPoint("TOPLEFT", row.act, "TOPRIGHT", 8, 2)
    row.pass:SetText("pass")
    row.pass:SetScript("OnClick", function()
        Testing.Set(index, "pass")
        Testing.Refresh()
    end)

    row.fail = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.fail:SetSize(52, 20)
    row.fail:SetPoint("TOPLEFT", row.pass, "BOTTOMLEFT", 0, -2)
    row.fail:SetText("fail")
    row.fail:SetScript("OnClick", function()
        Testing.Set(index, "fail")
        Testing.Refresh()
    end)

    return row
end

local function Build()
    window = CreateFrame("Frame", "MyUITestWindow", UIParent)
    window:SetSize(760, 540)
    window:SetPoint("CENTER")
    window:SetFrameStrata("DIALOG")
    window:EnableMouse(true)
    window:SetMovable(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    window:SetClampedToScreen(true)

    local bg = window:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.94)

    window.title = window:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    window.title:SetPoint("TOPLEFT", 14, -12)

    window.accept = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    window.accept:SetPoint("TOPLEFT", 14, -36)
    window.accept:SetWidth(720)
    window.accept:SetJustifyH("LEFT")

    local scroll = CreateFrame("ScrollFrame", "MyUITestScroll", window,
                               "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 14, -66)
    scroll:SetPoint("BOTTOMRIGHT", -32, 44)

    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(700, 10)
    scroll:SetScrollChild(child)
    window.child = child

    tallyText = window:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tallyText:SetPoint("BOTTOMLEFT", 14, 16)

    local close = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    close:SetSize(70, 22)
    close:SetPoint("BOTTOMRIGHT", -12, 12)
    close:SetText("close")
    close:SetScript("OnClick", function() window:Hide() end)

    local report = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    report:SetSize(90, 22)
    report:SetPoint("RIGHT", close, "LEFT", -6, 0)
    report:SetText("report")
    report:SetScript("OnClick", function() Testing.Report() end)

    local recheck = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    recheck:SetSize(90, 22)
    recheck:SetPoint("RIGHT", report, "LEFT", -6, 0)
    recheck:SetText("re-check")
    recheck:SetScript("OnClick", function()
        Testing.Recheck()
        Testing.Refresh()
    end)

    local reset = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    reset:SetSize(70, 22)
    reset:SetPoint("RIGHT", recheck, "LEFT", -6, 0)
    reset:SetText("reset")
    reset:SetScript("OnClick", function()
        Testing.Reset()
        Testing.Refresh()
    end)

    window:SetScript("OnShow", function() Testing.Refresh() end)
    window:Hide()
    rows = {}
end

--- Repaint every row from the current results.
function Testing.Refresh()
    if not window then return end
    local script = Testing.scripts[Testing.phase]
    if not script then return end

    window.title:SetText(script.title)
    window.accept:SetText("Acceptance: " .. script.accept)

    local y = 0
    for i, step in ipairs(script.steps) do
        local row = rows[i]
        if not row then
            row = BuildRow(window.child, i)
            rows[i] = row
        end
        row:SetPoint("TOPLEFT", window.child, "TOPLEFT", 0, -y)
        row:Show()
        y = y + ROW_H

        row.act:SetText(step.act)
        row.expect:SetText(step.expect)

        local r = Testing.results[i]
        if r == nil then
            row.mark:SetText("|cffadb1b8...|r")
        elseif r.verdict == "pass" then
            row.mark:SetText("|cffa6d98cpass|r")
        else
            row.mark:SetText("|cfff26b61FAIL|r")
        end

        -- A step MyUI can decide for itself does not get buttons. Offering one
        -- would invite overriding a measurement with an opinion.
        if step.check then
            row.pass:Hide()
            row.fail:Hide()
            if r and r.detail then
                row.mark:SetText(row.mark:GetText() .. "\n|cff73777e auto|r")
            end
        else
            row.pass:Show()
            row.fail:Show()
        end
    end
    window.child:SetHeight(math.max(y, 10))

    local pass, fail, pending = Testing.Tally()
    tallyText:SetText(("%d passed   %d failed   %d not run")
                      :format(pass, fail, pending))
end

--- Open the checklist, optionally for a phase other than the current one.
function Testing.Show(phase)
    if phase ~= nil then
        Testing.phase = phase
        Testing.results = {}
    end
    if not Testing.scripts[Testing.phase] then
        ns.Print("no acceptance script for phase " .. tostring(Testing.phase))
        return
    end
    if not window then Build() end
    Testing.Recheck()
    window:Show()
    Testing.Refresh()
end

function Testing.IsShown()
    return window ~= nil and window:IsShown()
end

-- ---------------------------------------------------------------------------
-- Results
-- ---------------------------------------------------------------------------

Testing.phase = ns.phase
Testing.results = {}

function Testing.Steps()
    local script = Testing.scripts[Testing.phase]
    if not script then
        return nil
    end
    return script.steps
end

--- Fill in auto-checks that have not passed yet, leaving manual verdicts alone.
--
-- A pass LATCHES. The steps are a sequence, and several of them test states
-- that are mutually exclusive by design -- step 1 wants the frames forced
-- visible, step 8 wants them released. Re-evaluating everything at report time
-- meant completing the run always failed the step you did first. A step that
-- passed, passed.
--
-- force re-evaluates everything, for when you want to start the sequence over
-- without losing the manual verdicts.
function Testing.Recheck(force)
    local steps = Testing.Steps()
    if not steps then return end
    for i, step in ipairs(steps) do
        local existing = Testing.results[i]
        local settled = existing ~= nil and existing.verdict == "pass"
        if step.check and (force or not settled) then
            -- One protected call. Running the check twice would both waste the
            -- work and leave the second call unguarded.
            local ok, passed, why = pcall(step.check)
            if not ok then
                Testing.results[i] =
                    { verdict = "fail", detail = "check errored: " .. tostring(passed), auto = true }
            elseif passed then
                Testing.results[i] = { verdict = "pass", detail = why, auto = true }
            else
                Testing.results[i] = { verdict = "fail", detail = why, auto = true }
            end
        end
    end
end

function Testing.Set(index, verdict)
    Testing.results[index] = { verdict = verdict, auto = false }
end

--- Start the run over. Manual verdicts go too -- a fresh run means fresh eyes.
function Testing.Reset()
    Testing.results = {}
    Testing.Recheck(true)
end

function Testing.Tally()
    local steps = Testing.Steps()
    local pass, fail, pending = 0, 0, 0
    if not steps then return 0, 0, 0 end
    for i = 1, #steps do
        local r = Testing.results[i]
        if not r then
            pending = pending + 1
        elseif r.verdict == "pass" then
            pass = pass + 1
        else
            fail = fail + 1
        end
    end
    return pass, fail, pending
end

--- A plain-text report, printed and persisted for reading off disk.
function Testing.Report()
    local script = Testing.scripts[Testing.phase]
    if not script then
        ns.Print("no acceptance script for phase " .. tostring(Testing.phase))
        return
    end
    Testing.Recheck()

    local when = "unknown time"
    if type(_G.date) == "function" then
        local ok, stamp = pcall(_G.date, "%Y-%m-%d %H:%M")
        if ok then when = stamp end
    end

    local pass, fail, pending = Testing.Tally()
    ns.Print(script.title)
    ns.Raw("  " .. when .. " -- MyUI v" .. ns.version)
    ns.Raw(" ")
    for i, step in ipairs(script.steps) do
        local r = Testing.results[i]
        local mark, detail = "|cffadb1b8 -- |r", ""
        if r then
            if r.verdict == "pass" then
                mark = "|cffa6d98cpass|r"
            else
                mark = "|cfff26b61FAIL|r"
            end
            if r.auto then
                detail = "  (auto: " .. tostring(r.detail) .. ")"
            end
        end
        ns.Raw(("  %d. %s  %s%s"):format(i, mark, step.act, detail))
        if not r or r.verdict ~= "pass" then
            ns.Raw("        expected: " .. step.expect)
        end
    end
    ns.Raw(" ")
    ns.Raw(("  %d passed, %d failed, %d not run"):format(pass, fail, pending))
    if fail == 0 and pending == 0 then
        ns.Raw("  |cffa6d98cphase accepted|r -- /reload, then the report is in "
               .. "MyUIDB.lastOutput")
    end

    if ns.db and not ns.readOnlyDB then
        ns.db.testRuns = ns.db.testRuns or {}
        ns.db.testRuns[Testing.phase] = {
            when = when, pass = pass, fail = fail, pending = pending,
            version = ns.version, text = ns.GetOutput(),
        }
    end
end
