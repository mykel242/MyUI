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
            { cmd = "/reload", act = "Type /reload and wait for the UI to come back.",
              expect = "No Lua error popup. MyUI prints one loaded line." },
            { act = "Look at the screen.",
              expect = "Nothing from MyUI is visible. Phase 0 draws nothing." },
            { cmd = "/myui rules", act = "Type /myui rules",
              expect = "The principle, six prohibitions, four mechanisms." },
            { awaits = "audit", cmd = "/myui audit", act = "Type /myui audit",
              expect = "A clean guard: 0 violations.",
              check = function()
                  local n = #ns.Guard.violations
                  if n == 0 then return true, "0 violations" end
                  return false, n .. " violations"
              end },
            { cmd = "/myui conditionals", act = "Type /myui conditionals",
              expect = "The known control differs from the unknown one." },
        },
    },

    [1] = {
        title = "Phase 1 — anchors and frame registry",
        accept = "Debug toggle shows every frame; positions and sizes match the "
              .. "mock; audit lists each frame with its spec resting alpha.",
        steps = {
            { id = "show", awaits = "show on", cmd = "/myui show on", act = "Type /myui show on",
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

            { awaits = "audit", cmd = "/myui audit", act = "Type /myui audit",
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

            { cmd = "/myui outline on", act = "Type /myui outline on -- a green box around each group?",
              expect = "Four boxes, each snug around its frame with the name above "
                    .. "it. A box with nothing inside means the frame is placed "
                    .. "right but hidden." },
            { cmd = "/myui outline off", act = "Type /myui outline off",
              expect = "Boxes gone, frames unchanged." },

            { id = "showoff", awaits = "show off", cmd = "/myui show off", act = "Type /myui show off",
              expect = "Placeholders clear and the bars empty.",
              check = function()
                  if Registry.forced then
                      return false, "still forced -- run /myui show off"
                  end
                  return everyFrameResting()
              end },
            { act = "After /myui show off: has the top-centre strip vanished entirely?",
              expect = "TargetStrip rests at alpha 0. The others dim but remain." },
            { cmd = "/myui show on", act = "Type /myui show on again. Did anything move?",
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
              cmd = "/myui show off", act = "Type /myui show off to start from rest.",
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

            -- A transient channel has to be recorded and read afterwards rather
            -- than caught in the act. That began as a workaround: the step
            -- above this one used to ask you to type a command while holding
            -- Alt, which cannot be done -- on macOS an Option-combination
            -- inserts an accented character and Shift turns "/" into "?", so
            -- the command never ran at all. The modifier channel is gone now
            -- and the constraint went with it, but the technique is better
            -- anyway and the cursor dwell still needs it: the cursor has to
            -- leave the frame to reach the chat box.
            { awaits = "claims",
              act = "Rest the cursor on the bottom bars for a second, move away, "
                 .. "then type /myui claims.",
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
              cmd = "/myui claims",
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
        accept = "Notifications arrive without a cap and age out; a toast "
              .. "speaks once and collapses after 4s; the log survives a "
              .. "reload; Enter opens our edit box; the rail at rest reads "
              .. "as calm.",
        steps = {
            { awaits = "notify clear", cmd = "/myui notify clear", act = "Type /myui notify clear",
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

            { cmd = "/myui notify blue Whisper", act = "Type /myui notify blue Whisper",
              expect = "A toast slides in near the top of the rail and speaks "
                    .. "once." },
            { act = "Watch that toast without touching anything.",
              expect = "It collapses on its own after about four seconds." },
            { act = "Look at the top of the rail now.",
              expect = "One coloured dot, with the name beside it and an age to "
                    .. "the right." },
            { act = "Wait a few seconds and look at that age again.",
              expect = "It has counted up on its own." },

            { cmd = "/myui notify amber Loot", act = "Type /myui notify amber Loot",
              expect = "The new one takes the top row; the first drops to the "
                    .. "second row and keeps its text." },

            { awaits = "notify demo", cmd = "/myui notify demo", act = "Type /myui notify demo",
              expect = "Twelve arrive at once and all twelve are drawn -- no square, no count.",
              check = function()
                  local Rail = ns.Rail
                  local shown = 0
                  for i = 1, Rail.SLOTS do
                      if Rail.slots and Rail.slots[i]:IsShown() then
                          shown = shown + 1
                      end
                  end
                  if shown < 12 then
                      return false, shown .. " dots shown, sent 12"
                  end
                  return true, ("%d dots at pitch %d"):format(shown, Rail.Pitch())
              end },
            { act = "Count the dots on the rail.",
              expect = "All twelve, and nothing hidden behind a +N square. The "
                    .. "cap was arbitrary and is gone; dots leave by ageing "
                    .. "out, and the log behind the rail keeps them either way." },
            { act = "Look at how tightly the dots are spaced.",
              expect = "Closer together than they were with two or three on "
                    .. "screen. The pitch tightens as the rail fills, so a "
                    .. "busy minute looks busy." },
            { act = "Look at rows three and below.",
              expect = "Bare dots with no text. Only the newest two are named." },
            { act = "Compare the lower dots with the top two.",
              expect = "The lower ones are visibly dimmer." },

            -- The amendment's answer to the dots-over-bright-ground finding.
            -- Two steps, because "is there an edge" and "is it on the right
            -- dots" are different questions and a compound one cannot be
            -- answered.
            { act = "Look closely at one of the dim lower dots, over bright "
                 .. "ground if you can find some.",
              expect = "A thin dark outline around it, which is what keeps a "
                    .. "0.4 dot readable over sand or firelight." },
            { act = "Now look at the top two dots.",
              expect = "No outline -- they are solid. SPEC 6 puts the edge on "
                    .. "the older items only, so the rail should read as a "
                    .. "progression: solid, then outlined and fading. If that "
                    .. "reads as inconsistent rather than "
                    .. "deliberate, it is a finding." },

            -- The palette is light-on-dark and the dim grey loses to mid-tone
            -- terrain in both directions. A shadow cannot fix a contrast
            -- problem, only an edge problem.
            --
            -- This step is what produced the finding: it failed here on the
            -- grey SPEC 6 originally named, the addon shipped a lift as a
            -- deviation, and the amended SPEC 7 adopted it. So the default now
            -- IS the spec, and the step reads as an ordinary check again.
            { act = "Read the age on the top row and the count beside the square.",
              expect = "Both legible against the ground you are standing on. "
                    .. "/myui contrast normal shows the grey this replaced, if "
                    .. "you want to see what the finding was about." },

            { cmd = { "/myui notify green Urgent", "/myui notify dismiss" },
              act = "Send the first, then dismiss it before four seconds pass.",
              expect = "The toast collapses immediately rather than waiting." },
            { cmd = "/myui notify dismiss", act = "Send another, then type /myui notify dismiss",
              expect = "It collapses early rather than waiting out the four "
                    .. "seconds. Nothing on the rail takes a click -- the whole "
                    .. "left edge passes clicks through to the world." },

            -- SPEC 6's real sources, in place of /myui notify. Everything above
            -- this line is driven by a test command; everything below it has to
            -- be provoked by playing, which is the only way to find out whether
            -- the filters are set anywhere near right.
            { awaits = "sources", cmd = { "/myui notify clear", "/myui sources" },
              act = "Clear the rail, then run the second command.",
              expect = "The thresholds, a live reading of your free bag slots "
                    .. "and worst durability, and which conditions have already "
                    .. "spoken.",
              check = function()
                  local out = ns.db and ns.db.lastOutput
                  if not out or not out:find("free slots", 1, true) then
                      return false, "waiting for /myui sources"
                  end
                  if out:find("unreadable", 1, true) then
                      return false, "a reader came back unreadable -- see the output"
                  end
                  return true, "readings available"
              end },
            { act = "Compare the free-slot number it printed with your actual bags.",
              expect = "They match. If they do not, the bag source is counting "
                    .. "the wrong containers and the full-bag notice will be "
                    .. "wrong with it." },

            { awaits = "notify clear",
              cmd = "/myui notify clear",
              act = "Clear the rail, then kill something and loot an item of "
                 .. "uncommon quality or better.",
              expect = "One blue row, named for the item, with its count.",
              check = function()
                  local Rail = ns.Rail
                  for _, item in ipairs(Rail.items) do
                      if item.kind == "blue" then
                          return true, "blue row: " .. tostring(item.name)
                      end
                  end
                  return false, "no loot recorded yet"
              end },
            { act = "Keep looting greys and whites for a moment.",
              expect = "Nothing new on the rail. SPEC 6 filters loot at uncommon "
                    .. "and above, so common drops are deliberately silent." },

            -- Both found in game on the first run of these steps, and both are
            -- the kind of thing the offline suite cannot see: one needs a real
            -- item name, the other a real client string.
            { act = "Look at a row whose item name is long -- "
                 .. "\"Chunk of Companion Experience\" was the one that found this.",
              expect = "The name stops short and ends in an ellipsis. It must "
                    .. "not run across the age; the first build drew the two on "
                    .. "top of each other and neither could be read." },
            { act = "Gain reputation with any faction.",
              expect = "A green row naming THE FACTION. If it says just "
                    .. "\"Reputation\", that is the fallback and the client "
                    .. "sent a message form the reader still does not know.",
              check = function()
                  for _, item in ipairs(ns.Rail.items) do
                      if item.kind == "green" and item.name == "Reputation" then
                          return false, "fallback name -- an unhandled message form"
                      end
                  end
                  for _, item in ipairs(ns.Rail.items) do
                      if item.kind == "green" then
                          return true, "named: " .. tostring(item.name)
                      end
                  end
                  return false, "no reputation or currency recorded yet"
              end },

            { act = "Accept a quest, or hand one in.",
              expect = "One amber row, named for the quest rather than saying "
                    .. "\"Quest accepted\" -- the fallback name means the quest "
                    .. "log reader did not answer.",
              check = function()
                  for _, item in ipairs(ns.Rail.items) do
                      if item.kind == "amber" then
                          return true, "amber row: " .. tostring(item.name)
                      end
                  end
                  return false, "no quest event recorded yet"
              end },

            { act = "Stand back and look at the whole screen with the rail full.",
              expect = "It still reads as calm. If the rail draws your eye at "
                    .. "rest, that is the finding this phase exists to catch." },

            -- The log. Everything the rail is now allowed to forget depends on
            -- this, so it is checked before anything that relies on it.
            { cmd = "/myui log", act = "Type /myui log",
              expect = "A list of what has happened, newest first, with clock "
                    .. "times and a count per hue.",
              check = function()
                  local Log = ns.Log
                  if not Log or not Log.db then
                      return false, "no log"
                  end
                  if Log.Count() == 0 then
                      return false, "nothing recorded yet -- loot something first"
                  end
                  return true, ("%d entries kept"):format(Log.Count())
              end },
            { cmd = "/myui log green", act = "Type /myui log green",
              expect = "Only the green rows -- currency and reputation." },
            { cmd = "/reload", act = "Type /reload and wait for the addon to load.",
              expect = "The UI comes back." },
            { cmd = "/myui log", act = "Type /myui log again.",
              expect = "The same entries are still there with the same times. "
                    .. "This is the thing that makes dots ageing out safe: if "
                    .. "the log is empty after a reload, nothing else in this "
                    .. "phase is trustworthy." },

            -- Step one of replacing the chat log. Additive, and reversible in
            -- one command.
            { cmd = "/myui chat", act = "Type /myui chat",
              expect = "It reports the override installed and finds Blizzard's "
                    .. "send box.",
              check = function()
                  local Chat = ns.Chat
                  if not Chat then return false, "no chat module" end
                  if not Chat.IsOverriding() then
                      return false, "override not installed"
                  end
                  if not Chat.SendBox() then
                      return false, "Blizzard's send box not found -- sending would fail"
                  end
                  return true, "override installed, send box found"
              end },
            { act = "Press Enter.",
              expect = "A thin input appears at the bottom left, above the "
                    .. "rail's line, labelled with what you are talking into. "
                    .. "Blizzard's chat box does NOT open." },
            { act = "Type something and press Enter.",
              expect = "It sends, and the input disappears. Blizzard's edit box "
                    .. "did the routing -- if this works, the chat frame can be "
                    .. "hidden later without losing the ability to reply." },
            { act = "Press Enter, type something, then press Escape.",
              expect = "The input disappears and nothing was sent." },
            { act = "Press the / key.",
              expect = "BLIZZARD's chat box opens, not ours, already holding a "
                    .. "slash. That fall-through is deliberate: it is why the "
                    .. "chat frame gets hidden and never removed." },
            { act = "Bind a key to MyUI -> Reply in the game's Key Bindings, "
                 .. "then press it.",
              expect = "Our box opens already holding \"/r \". Type and send "
                    .. "and it whispers whoever last messaged you -- Blizzard's "
                    .. "own parser resolves the target, we never look it up." },

            -- The house without furniture.
            { cmd = "/myui chat hide", act = "Type /myui chat hide",
              expect = "The chat log, its tabs, the dock and the buttons all "
                    .. "leave the screen. It reports how many frames it stowed.",
              check = function()
                  local Chat = ns.Chat
                  if not Chat then return false, "no chat module" end
                  if not Chat.logHidden then return false, "not hidden" end
                  if Chat.StowedCount() < 1 then
                      return false, "hidden but nothing was stowed -- the frame "
                                 .. "names did not match this client"
                  end
                  if not Chat.editBoxFreed then
                      return false, "the edit box is still inside the chat frame"
                  end
                  if not Chat.SendBox() then
                      return false, "Blizzard's send box went with it -- sending would fail"
                  end
                  return true, ("%d frames stowed, send box still reachable")
                               :format(Chat.StowedCount())
              end },
            { act = "Look at the bottom left of the screen.",
              expect = "Nothing. No tabs, no chat backdrop, no buttons." },
            { act = "Press Enter, type something, and send it.",
              expect = "It still sends. This is the check that matters: the "
                    .. "frames are stowed under a hidden parent rather than "
                    .. "hidden, precisely so Blizzard still believes they are "
                    .. "there and sending keeps working." },
            { act = "Press / and send something.",
              expect = "Blizzard's edit box still appears and still works, "
                    .. "because it was moved out of the chat frame before the "
                    .. "frame was stowed." },
            { act = "Have someone whisper you, or whisper yourself from an alt.",
              expect = "A blue dot on the rail. The message is not on screen "
                    .. "anywhere else, which is the point and also the risk -- "
                    .. "if you cannot get back to it, say so." },
            -- The centre. It exists because the rail was made lossy on
            -- purpose, and until now nothing could read the record back.
            { cmd = "/myui center", act = "Type /myui center",
              expect = "A dark panel opens along the rail's own line, growing "
                    .. "rightward. The dots do not move.",
              check = function()
                  local C = ns.Center
                  if not C then return false, "no centre module" end
                  if not C.IsOpen() then return false, "did not open" end
                  if ns.Log.Count() == 0 then
                      return false, "open but the log is empty -- nothing to read"
                  end
                  return true, ("open over %d entries"):format(ns.Log.Count())
              end },
            { act = "Read the top row against the newest dot on the rail.",
              expect = "The same thing, with its name, count and age. This is "
                    .. "the answer to a whisper being a dot and nothing else." },
            { act = "Click one of the coloured dots along the top.",
              expect = "The list narrows to that hue and the others dim. Click "
                    .. "it again to clear the filter." },
            { act = "With the centre open, make something happen -- loot "
                 .. "something, or type /myui notify blue Test in another window.",
              expect = "It appears at the top of the list WITHOUT a toast "
                    .. "speaking. While you are looking at the record, nothing "
                    .. "needs to announce itself." },
            { act = "Press Escape.",
              expect = "The centre closes. Nothing is left on screen and the "
                    .. "left edge passes clicks to the world again." },
            { act = "Bind a key to MyUI -> Open the notification centre, then "
                 .. "press it twice.",
              expect = "It opens and closes. A key rather than a click on the "
                    .. "rail, because the rail deliberately takes no mouse." },

            { cmd = "/myui chat show", act = "Type /myui chat show",
              expect = "The chat frame and all its furniture come back. A "
                    .. "/reload restores Blizzard's exact layout." },
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

local ROW_H, TEXT_W = 90, 520
local MAX_CMDS = 2

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

    -- One button per command the step names. Clicking drops it into the chat
    -- box ready to send, because a step like "type this, then type that inside
    -- four seconds" is otherwise a typing test rather than a test of the addon.
    row.cmds = {}
    for c = 1, MAX_CMDS do
        local button = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        button:SetSize(250, 18)
        if c == 1 then
            button:SetPoint("TOPLEFT", row.detail, "BOTTOMLEFT", 0, -2)
        else
            button:SetPoint("TOPLEFT", row.cmds[c - 1], "TOPRIGHT", 6, 0)
        end
        button:SetScript("OnClick", function(self)
            Testing.SendToChat(self.command)
        end)
        button:Hide()
        row.cmds[c] = button
    end

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

--- Put a command in the chat box, focused, so it can be sent with Enter.
--
-- ChatFrame_OpenChat is deprecated on 12.1 and aliased to ChatFrameUtil.
-- OpenChat; both are tried so this works either way rather than depending on
-- which one a future build keeps.
function Testing.SendToChat(command)
    if not command then
        return false
    end
    local util = _G.ChatFrameUtil
    if util and type(util.OpenChat) == "function" then
        util.OpenChat(command)
        return true
    end
    if type(_G.ChatFrame_OpenChat) == "function" then
        _G.ChatFrame_OpenChat(command)
        return true
    end
    -- No chat box to fill: fall back to the copy window so the text is at
    -- least selectable rather than needing to be retyped from the panel.
    ns.Copy.Show(command)
    return false
end

--- A step's commands, always as a list.
function Testing.CommandsFor(step)
    if step.cmd == nil then
        return {}
    end
    if type(step.cmd) == "string" then
        return { step.cmd }
    end
    return step.cmd
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

--- The command buttons actually shown on a row, in order. Like RowMark, this
-- reports what is on screen rather than what should be.
function Testing.RowCommands(index)
    local row = rows and rows[index]
    if not row then
        return nil
    end
    local out = {}
    for _, button in ipairs(row.cmds) do
        if button:IsShown() then
            out[#out + 1] = button.command
        end
    end
    return out
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

        local commands = Testing.CommandsFor(step)
        for c = 1, MAX_CMDS do
            local button = row.cmds[c]
            if commands[c] then
                button.command = commands[c]
                button:SetText(commands[c])
                button:Show()
            else
                button:Hide()
            end
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
