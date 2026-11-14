-- MyUI :: Rules.lua
-- The forbidden list, printable in game. RULES.md asks for this so the
-- prohibitions stay visible during development rather than living in a file
-- nobody has open.

local ADDON, ns = ...

local Rules = {}
ns.Rules = Rules

Rules.principle = "Forwarding a secret value is legal. Inspecting one is not."

Rules.forbidden = {
    {
        no  = "Read health, resource or cooldown values to drive appearance.",
        yes = "Forward the value to the widget, or map it with a curve: "
           .. "UnitHealthPercent(unit, true, curve) returns the evaluated result.",
    },
    {
        no  = "Write threshold branches (if pct < 0.2 then).",
        yes = "A curve for continuous colour; a STEP curve evaluated to alpha for a "
           .. "hard boundary. There is no health macro conditional, of any spelling.",
    },
    {
        no  = "Assume this file governs every value in the addon.",
        yes = "It governs unit and cooldown values. The rail's sources -- item "
           .. "quality, bag slots, durability, mail -- are ordinary Lua. Compare "
           .. "them normally; over-applying the rules produces worse code, not safer.",
    },
    {
        no  = "Compare, rank or sort anything derived from combat state.",
        yes = "Fixed, user-configured order only. Cell order is never computed.",
    },
    {
        no  = "Treat HasSecretValues() as a signal.",
        yes = "It is a crash guard, not a low-health tell. C_Secrets is introspection "
           .. "about whether a value is secret -- no comparison, no predicate.",
    },
    {
        no  = "Hide or show a protected frame in combat.",
        yes = "Queue on InCombatLockdown() and flush on PLAYER_REGEN_ENABLED. Where a "
           .. "frame only needs to be quiet, set alpha instead -- alpha is not "
           .. "protected, which is why minimap, chat and bags are adopted, not hidden.",
    },
    {
        no  = "Poll combat state on OnUpdate.",
        yes = "Event-driven only. OnUpdate is legal solely for cursor proximity and "
           .. "the peek timer, neither of which touches game state.",
    },
    {
        no  = "Reparent Cooldown Manager's widgets into your layout.",
        yes = "Keep CDM alive at alpha 0 as the tracking source and mirror it.",
    },
}

-- Five since the handoff amendment: two of the original four were wrong on 12.1
-- and the low-health hook was added, narrowly licensed.
Rules.mechanisms = {
    { name = "Curve objects",                   owns = "continuous colour from a secret, "
                                                    .. "and a hard threshold as a step curve",
      cannot = "size or geometry -- a step curve gives an alpha, not an event" },
    { name = "Reverse-fill StatusBar",          owns = "anything tied to the fill boundary",
      cannot = "mask inversion -- the API has none" },
    { name = "RegisterStateDriver",             owns = "discrete states the macro parser knows",
      cannot = "low health -- there is no health conditional" },
    { name = "CDM at alpha 0 + mirror frames",  owns = "cooldown and charge tracking",
      cannot = "nothing you inspect" },
    { name = "Hook on LowHealthFrame",          owns = "the one low-health event, as a "
                                                    .. "plain non-secret boolean",
      cannot = "any threshold but Blizzard's 35%, and the player can switch it off" },
}

-- The fifth is licensed for ONE purpose: letting low health summon SelfStack.
-- Hooking further Blizzard frames to recover other events is out of bounds.
Rules.licence =
    "The low-health hook exists so low health can summon SelfStack, and for nothing "
 .. "else. Do not hook another Blizzard frame to recover an event -- raise it."

-- WE DEVIATE FROM RULES.md HERE, DELIBERATELY.
--
-- The handoff's amended RULES.md still carries, unedited beneath its new
-- mechanism table: "size changes, pulses, and breathing animations require an
-- event. They are only legal inside a driver state. A curve cannot drive them.
-- If the spec asks for a pulse, there is a driver state behind it; if there is
-- no driver state, there is no pulse."
--
-- The first half is true and verified: SetScale and SetColorFill are
-- AllowedWhenUntainted and refuse a forwarded secret, so no secret will ever
-- resize anything. The conclusion no longer follows. The same amendment's
-- SPEC 3 builds both the 12pt -> 14pt number and the 1.60s breathe with NO
-- event and NO driver state -- duplicated frames cross-faded by a step curve's
-- alpha, with the animation permanently running on one copy. That is the
-- mechanism the amendment itself specifies two sections earlier.
--
-- So the paragraph is a leftover from before RegisterStateDriver was refuted,
-- and printing it would send the next reader looking for a driver state that
-- cannot exist. Raised with the designer; printing the accurate version.
Rules.consequence =
    "A forwarded secret cannot resize anything -- SetScale is AllowedWhenUntainted. "
 .. "Cross-fade two frames with a step curve instead; that needs no event."

function Rules.Print()
    local P = ns.Raw
    ns.Print("the one principle")
    P("  |cfff2d696" .. Rules.principle .. "|r")
    P(" ")
    ns.Print("forbidden, with the legal alternative")
    for _, rule in ipairs(Rules.forbidden) do
        P("  |cfff26b61x|r " .. rule.no)
        P("    |cffa6d98c->|r " .. rule.yes)
    end
    P(" ")
    ns.Print("the five sanctioned mechanisms")
    for _, m in ipairs(Rules.mechanisms) do
        P(("  |cfff0f1f3%s|r"):format(m.name))
        P(("     owns:   %s"):format(m.owns))
        P(("     cannot: %s"):format(m.cannot))
    end
    P("  |cffadb1b8" .. Rules.licence .. "|r")
    P(" ")
    P("  |cffffd159" .. Rules.consequence .. "|r")
end
