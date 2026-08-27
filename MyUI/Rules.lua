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
        yes = "A curve for continuous colour; RegisterStateDriver for a discrete state.",
    },
    {
        no  = "Compare, rank or sort anything derived from combat state.",
        yes = "Fixed, user-configured order only. Cell order is never computed.",
    },
    {
        no  = "Treat HasSecretValues() as a signal.",
        yes = "It is a crash guard, not a low-health tell. RegisterStateDriver is the "
           .. "only legal event source.",
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

Rules.mechanisms = {
    { name = "Curve through UnitHealthPercent", owns = "continuous colour from a secret",
      cannot = "size, alpha timing, geometry" },
    { name = "Reverse-fill StatusBar",          owns = "anything tied to the fill boundary",
      cannot = "anything not spatially tied to a bar" },
    { name = "RegisterStateDriver",             owns = "discrete state arrival",
      cannot = "anything graded or continuous" },
    { name = "CDM at alpha 0 + mirror frames",  owns = "cooldown and charge tracking",
      cannot = "nothing you inspect" },
}

-- Consequence worth keeping in front of you: size changes, pulses and breathing
-- need an event. SetScale is AllowedWhenUntainted, so it will not take a
-- forwarded secret. If the spec asks for a pulse, there is a driver state
-- behind it; if there is no driver state, there is no pulse.
Rules.consequence =
    "Size changes and pulses require an event -- SetScale refuses a forwarded secret."

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
    ns.Print("the four sanctioned mechanisms")
    for _, m in ipairs(Rules.mechanisms) do
        P(("  |cfff0f1f3%s|r"):format(m.name))
        P(("     owns:   %s"):format(m.owns))
        P(("     cannot: %s"):format(m.cannot))
    end
    P(" ")
    P("  |cffffd159" .. Rules.consequence .. "|r")
end
