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

-- Check the registry's intent AND the frame's actual alpha.
--
-- The first version compared only entry.target, so it reported "4 frames
-- targeted at 1" while the screen was still showing a barely-visible UI. An
-- auto-check that can pass when nothing happened is worse than no check.
--
-- The live read is still guarded: from Phase 4 a frame carrying a forwarded
-- secret returns a secret from GetAlpha, and that is not a failure. When the
-- alpha is unreadable the check falls back to intent and says so, rather than
-- pretending it verified something it could not see.

local function compareAlphas(want)
    local bad, unreadable = nil, false
    Registry.Each(function(entry)
        local target = want
        if want == nil then
            target = entry.resting
        end
        if type(entry.target) ~= "number" or math.abs(entry.target - target) > 0.001 then
            bad = bad or (entry.name .. " target")
            return
        end
        local live = ns.Compat.Get(entry.frame, "GetAlpha")
        if type(live) ~= "number" then
            unreadable = true
        elseif math.abs(live - target) > 0.001 then
            bad = bad or (entry.name .. (" live %.2f, wanted %.2f"):format(live, target))
        end
    end)
    if bad then
        return false, "mismatch: " .. bad
    end
    local how = "verified on screen"
    if unreadable then
        how = "intent only -- some alphas are secret"
    end
    return true, ("%d frames, %s"):format(Registry.Count(), how)
end

local function everyFrameAt(alpha)
    return compareAlphas(alpha)
end

local function everyFrameResting()
    return compareAlphas(nil)
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
            { awaits = "audit", act = "Type /myui audit",
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
            { id = "show", awaits = "show on", act = "Type /myui show on",
              expect = "Frames go opaque, with placeholder text and a nominal fill.",
              check = function()
                  if not Registry.forced then
                      return false, "not forced -- run /myui show first"
                  end
                  return everyFrameAt(1)
              end },

            { act = "Bottom centre: are there three stacked horizontal bars?",
              expect = "A wide one, a thinner one below it, a third below that." },
            { act = "Bottom centre: is there a number to the LEFT of the bars?",
              expect = "The placeholder 100, right-aligned, clear of the bar group." },
            { act = "On the widest bar: a DARK tick about one fifth across?",
              expect = "The 20% mark, inside the filled part. Debug fills the "
                    .. "bar to 30% precisely so this tick has fill to read against." },
            { act = "On the widest bar: a PALE tick about two fifths across?",
              expect = "The 40% mark, just past where the fill ends, against the "
                    .. "empty trough. One pixel wide." },

            { act = "Top centre: is there a wide thin bar?",
              expect = "The target health bar, wider than the bottom group." },
            { act = "Top centre: text above that bar, left AND right?",
              expect = "Target Name on the left, 73 on the right, same row." },

            { act = "Far left, vertically centred: a vertical hairline?",
              expect = "One crisp pixel-wide line. Not a soft grey smear." },

            { awaits = "audit", act = "Type /myui audit",
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
            { awaits = "audit",
              act = "Read the px-per-unit line at the bottom of the audit.",
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

            { act = "Type /myui outline on -- a green box around each group?",
              expect = "Four boxes, each snug around its frame with the name above "
                    .. "it. A box with nothing inside means the frame is placed "
                    .. "right but hidden." },
            { act = "Type /myui outline off",
              expect = "Boxes gone, frames unchanged." },

            { id = "showoff", awaits = "show off", act = "Type /myui show off",
              expect = "Placeholders clear and the bars empty.",
              check = function()
                  if Registry.forced then
                      return false, "still forced -- run /myui show off"
                  end
                  return everyFrameResting()
              end },
            { act = "After /myui show off: has the top-centre strip vanished entirely?",
              expect = "TargetStrip rests at alpha 0. The others dim but remain." },
            { act = "Type /myui show on again. Did anything move?",
              expect = "Nothing shifts by a pixel. Position is fixed forever." },
        },
    },

    [2] = {
        title = "Phase 2 — the reveal engine",
        accept = "Each channel drives a frame in isolation; overlapping claims "
              .. "resolve highest-wins; releasing all claims returns a frame to "
              .. "its resting alpha, not to zero; the 32-unit zone and 140ms "
              .. "dwell both verified by brushing past.",
        steps = {
            { id = "showoff", awaits = "show off",
              act = "Type /myui show off to start from rest.",
              expect = "Everything back to its resting alpha.",
              check = function()
                  if Registry.forced then
                      return false, "still forced -- run /myui show off"
                  end
                  return everyFrameResting()
              end },

            { act = "Are the engine's timings the ones the spec gives?",
              expect = "Checked automatically: 32-unit zone, 140ms dwell, "
                    .. "120ms in, 260ms out, 3s peek.",
              check = function()
                  local R, P = ns.Reveal, ns.Peek
                  local want = {
                      { "zone",  R.PROXIMITY, ns.Scale.U(32) },
                      { "dwell", R.DWELL,     0.140 },
                      { "in",    R.FADE_IN,   0.120 },
                      { "out",   R.FADE_OUT,  0.260 },
                      { "peek",  P.DURATION,  3.0 },
                  }
                  for _, w in ipairs(want) do
                      if math.abs(w[2] - w[3]) > 0.0001 then
                          return false, ("%s is %s, spec says %s")
                                        :format(w[1], tostring(w[2]), tostring(w[3]))
                      end
                  end
                  return true, "all five match"
              end },

            { act = "Rest the cursor on the bottom-centre bars and hold still.",
              expect = "After a short pause they brighten to full. Not instantly "
                    .. "-- the pause is the 140ms dwell." },
            { act = "Now sweep the cursor quickly across them without stopping.",
              expect = "They stay faint. This is the whole reason the dwell "
                    .. "exists: brushing past while looting must not flash the HUD." },
            { act = "Rest on them again, then move the cursor away.",
              expect = "They fade back to faint over about a quarter second — "
                    .. "and stop there. They must NOT vanish." },

            { act = "Hold Alt.",
              expect = "Everything appears at once, with no pause. The modifier "
                    .. "channel has no dwell." },
            { act = "Release Alt.",
              expect = "Everything settles back to resting. The top-centre strip "
                    .. "disappears completely; the others stay faint." },

            { act = "Target something.",
              expect = "The top-centre strip appears on its own. The bottom "
                    .. "group stays faint." },
            { act = "Clear your target.",
              expect = "The strip goes completely invisible again." },

            { act = "Enter combat.",
              expect = "The bottom group brightens and stays up. The target strip "
                    .. "is unaffected by combat alone." },
            { act = "Leave combat.",
              expect = "The bottom group settles back to faint." },

            { act = "Bind a key to MyUI -> Peek in the game's Key Bindings, then press it.",
              expect = "Everything appears, with a thin line draining right to "
                    .. "left under the bottom group." },
            { act = "Watch the drain line run out.",
              expect = "It empties over about three seconds, then everything "
                    .. "fades back to resting." },

            -- These used to ask you to type a command while holding Alt, which
            -- cannot be done: on macOS Option-combinations insert accented
            -- characters, and Shift turns "/" into "?", so the command never
            -- runs at all. A transient channel has to be recorded and read
            -- afterwards, not caught in the act.
            { awaits = "claims",
              act = "Hold Alt for a second, release it, then type /myui claims.",
              expect = "The log shows modifier claiming three frames, then "
                    .. "releasing them.",
              check = function()
                  -- Reads the input entries, not the outcomes: whether you
                  -- pressed the key is a different question from what the
                  -- arbiter did about it.
                  local claimed, released = 0, 0
                  for _, e in ipairs(ns.Reveal.log) do
                      if e.channel == "modifier" then
                          if e.kind == "claim" then claimed = claimed + 1 end
                          if e.kind == "release" then released = released + 1 end
                      end
                  end
                  if claimed == 0 then
                      return false, "no modifier press recorded yet"
                  end
                  if released == 0 then
                      return false, "pressed but never released"
                  end
                  return true, ("%d press%s recorded"):format(
                      claimed, claimed == 1 and "" or "es")
              end },

            { awaits = "claims",
              act = "Rest the cursor on the bottom bars for a second, move away, "
                 .. "then run /myui claims again.",
              expect = "A cursor claim on SelfStack, and none on the target strip.",
              check = function()
                  local onStack, onStrip = false, false
                  for _, e in ipairs(ns.Reveal.log) do
                      if e.kind == "change" and e.winner == "cursor" then
                          if e.frame == "SelfStack" then onStack = true end
                          if e.frame == "TargetStrip" then onStrip = true end
                      end
                  end
                  if onStrip then
                      return false, "cursor claimed the target strip too"
                  end
                  if not onStack then
                      return false, "no cursor claim on SelfStack yet"
                  end
                  return true, "cursor claimed SelfStack only"
              end },

            { awaits = "claims",
              act = "Hold Alt, rest the cursor on the bottom bars, then release "
                 .. "Alt while leaving the cursor there. Then /myui claims.",
              expect = "A line reading SelfStack 1.00 -> 1.00 with the winner "
                    .. "becoming cursor: two claims overlapped, the higher held, "
                    .. "and dropping one did not dim the frame." ,
              check = function()
                  for _, e in ipairs(ns.Reveal.log) do
                      if e.kind == "change" and e.frame == "SelfStack"
                         and e.winner == "cursor" and e.from == e.to then
                          return true, "handover recorded with no alpha change"
                      end
                  end
                  return false, "no overlapping-claim handover recorded yet"
              end },
        },
    },

    [3] = {
        title = "Phase 3 — the rail",
        accept = "Eight simultaneous notifications cap correctly and show "
              .. "\"+N more\"; a toast speaks once and collapses after 4s; "
              .. "the rail at rest reads as calm.",
        steps = {
            { awaits = "notify clear", act = "Type /myui notify clear",
              expect = "The rail empties.",
              check = function()
                  if #ns.Rail.items > 0 then
                      return false, #ns.Rail.items .. " still on the rail"
                  end
                  return true, "empty"
              end },
            { act = "Look at the left edge of the screen.",
              expect = "One vertical hairline and nothing else. This is the "
                    .. "rail at rest, and it should read as calm." },

            { act = "Type /myui notify blue Whisper",
              expect = "A toast slides in near the top of the rail and speaks "
                    .. "once." },
            { act = "Watch that toast without touching anything.",
              expect = "It collapses on its own after about four seconds." },
            { act = "Look at the top of the rail now.",
              expect = "One coloured dot, with the name beside it and an age to "
                    .. "the right." },
            { act = "Wait a few seconds and look at that age again.",
              expect = "It has counted up on its own." },

            { act = "Type /myui notify amber Loot",
              expect = "The new one takes the top row; the first drops to the "
                    .. "second row and keeps its text." },

            { awaits = "notify demo", act = "Type /myui notify demo",
              expect = "Ten arrive at once. Eight dots, two behind the square.",
              check = function()
                  local Rail = ns.Rail
                  local shown = 0
                  for i = 1, Rail.CAP do
                      if Rail.slots and Rail.slots[i]:IsShown() then
                          shown = shown + 1
                      end
                  end
                  if shown ~= Rail.CAP then
                      return false, shown .. " dots shown, cap is " .. Rail.CAP
                  end
                  if Rail.Overflow() < 1 then
                      return false, "nothing overflowed"
                  end
                  return true, ("%d dots, +%d behind the square")
                               :format(shown, Rail.Overflow())
              end },
            { act = "Count the dots on the rail.",
              expect = "Exactly eight, however many were sent." },
            { act = "Look below the eighth dot.",
              expect = "A hollow square with a count beside it, not a ninth dot. "
                    .. "Hollow because a solid one would read as another item." },
            { act = "Look at rows three and below.",
              expect = "Bare dots with no text. Only the newest two are named." },
            { act = "Compare the lower dots with the top two.",
              expect = "The lower ones are visibly dimmer." },

            { act = "Type /myui notify green Urgent, then /myui notify dismiss "
                 .. "before four seconds pass.",
              expect = "The toast collapses immediately rather than waiting." },
            { act = "Send another, and click the toast itself.",
              expect = "It collapses on the click too." },

            -- Folded in from Phase 2: the hold binding shipped after that
            -- phase was accepted, so it has never been verified in game.
            { awaits = "claims",
              act = "Bind MyUI -> Hold to reveal to a free key, run /myui "
                 .. "modifier none, hold that key, release, then /myui claims.",
              expect = "The log shows the channel arming via binding, not via "
                    .. "keys -- so the HUD no longer fights your ability rows.",
              check = function()
                  for _, e in ipairs(ns.Reveal.log) do
                      if e.kind == "claim" and e.channel == "modifier"
                         and e.via == "binding" then
                          return true, "armed via binding"
                      end
                  end
                  return false, "no binding-armed claim recorded yet"
              end },

            { act = "Stand back and look at the whole screen with the rail full.",
              expect = "It still reads as calm. If the rail draws your eye at "
                    .. "rest, that is the finding this phase exists to catch." },
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

local ROW_H, TEXT_W = 68, 520

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

    -- What the auto-check actually measured. Without this a FAIL is a verdict
    -- with no evidence, and the only way to find out why is the report.
    row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.detail:SetPoint("TOPLEFT", row.expect, "BOTTOMLEFT", 0, -2)
    row.detail:SetWidth(TEXT_W)
    row.detail:SetJustifyH("LEFT")

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

--- What a row should read: "waiting", "pending", "pass" or "fail".
--
-- Separate from the drawing on purpose. The window painted a stale "waiting"
-- for a step that had already passed, and no test caught it because every test
-- read Testing.results directly and never looked at what was on screen.
function Testing.MarkFor(index)
    local steps = Testing.Steps()
    local step = steps and steps[index]
    if not step then
        return nil
    end
    if step.check and not Testing.Ready(step) then
        return "waiting"
    end
    local r = Testing.results[index]
    if r == nil then
        return "pending"
    end
    if r.verdict == "pass" then
        return "pass"
    end
    return "fail"
end

--- What a row is actually painted with right now. Lets a test assert on the
-- window rather than on the state behind it.
function Testing.RowMark(index)
    if not rows or not rows[index] then
        return nil
    end
    local text = rows[index].mark:GetText()
    if not text then
        return nil
    end
    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("%s+", " "))
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
        local mark = Testing.MarkFor(i)

        if mark == "waiting" then
            -- Not done is not a failure. The row is asking you to do something;
            -- marking it FAIL before you have is both wrong and discouraging.
            row.mark:SetText("|cff73777ewaiting|r")
            row.detail:SetText("|cff73777echecks itself once you run it|r")
        elseif mark == "pending" then
            row.mark:SetText("|cffadb1b8...|r")
            row.detail:SetText("")
        elseif mark == "pass" then
            row.mark:SetText("|cffa6d98cpass|r")
            row.detail:SetText("")
        else
            row.mark:SetText("|cfff26b61FAIL|r")
            row.detail:SetText("")
        end

        if r and r.auto and r.detail then
            row.mark:SetText(row.mark:GetText() .. "\n|cff73777eauto|r")
            row.detail:SetText("|cff73777e" .. tostring(r.detail) .. "|r")
        end

        -- A step MyUI can decide for itself does not get buttons. Offering one
        -- would invite overriding a measurement with an opinion.
        if step.check then
            row.pass:Hide()
            row.fail:Hide()
        else
            row.pass:Show()
            row.fail:Show()
        end
    end
    window.child:SetHeight(math.max(y, 10))

    local pass, fail, pending = Testing.Tally()
    tallyText:SetText(("%d passed   %d failed   %d to go"):format(pass, fail, pending))
end

--- Open the checklist, optionally for a phase other than the current one.
function Testing.Show(phase)
    if phase ~= nil then
        -- Switching scripts starts a fresh run: commands performed for the
        -- previous phase must not count as having been done for this one.
        -- Reopening the current phase (no argument) keeps your progress.
        Testing.phase = phase
        Testing.results = {}
        Testing.performed = {}
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

-- Commands run so far in this acceptance run, as "name arg" -- "show on",
-- "outline off", "audit". A step that awaits one stays pending until it fires.
--
-- Without this an auto step reads FAIL before you have had a chance to do it,
-- which is both wrong and demoralising: the row is telling you to type
-- something and marking you down for not having typed it yet. "Not done" and
-- "done and broken" are different states and only the second is a failure.
Testing.performed = {}

--- Record that a command ran. Called from the slash dispatcher for every
-- command, so steps do not need individual wiring.
function Testing.Note(name, rest)
    if rest and rest ~= "" then
        Testing.performed[name .. " " .. rest] = true
    end
    Testing.performed[name] = true
end

--- Index of a step by its stable id, so tests and tools do not depend on the
-- position of a step in a list that gets reordered as scripts are refined.
function Testing.IndexOf(id)
    local steps = Testing.Steps()
    if not steps then return nil end
    for i, step in ipairs(steps) do
        if step.id == id then return i end
    end
    return nil
end

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
--- True when a step's prerequisite command has been run this session.
function Testing.Ready(step)
    if not step.awaits then
        return true
    end
    return Testing.performed[step.awaits] == true
end

function Testing.Recheck(force)
    local steps = Testing.Steps()
    if not steps then return end
    for i, step in ipairs(steps) do
        local existing = Testing.results[i]
        local settled = existing ~= nil and existing.verdict == "pass"
        if step.check and not Testing.Ready(step) then
            -- Waiting on you, not failing. Leave it unset.
            Testing.results[i] = nil
        elseif step.check and (force or not settled) then
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

--- Re-evaluate, then repaint. Anything that changes state calls this; calling
-- only Recheck updates the verdicts and leaves the window showing the old ones.
function Testing.Sync()
    Testing.Recheck()
    Testing.Refresh()
end

function Testing.Set(index, verdict)
    Testing.results[index] = { verdict = verdict, auto = false }
end

--- Start the run over. Manual verdicts go too -- a fresh run means fresh eyes.
function Testing.Reset()
    Testing.results = {}
    Testing.performed = {}
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
