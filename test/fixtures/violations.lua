-- Fixture: every rule in rules_lint.py, violated once, deliberately.
-- Not loaded by the addon. test_lint.py asserts each line below is caught --
-- a lint nobody has proven catches anything is decoration.
--
-- Prose mentioning UnitHealth() / 100 or SetScale( must NOT trip the lint,
-- because comments are stripped before matching. This line is that test.

local ns = {}

-- R1: arithmetic on a secret
local function r1(bar)
    bar:SetValue(UnitHealth("player") / UnitHealthMax("player"))
end

-- R2: a threshold branch
local function r2()
    if UnitHealthPercent("player") < 20 then
        return "low"
    end
end

-- R3: a sink that refuses forwarded secrets
local function r3(frame)
    frame:SetScale(1.35)
end

-- R4: HasSecretValues used as a signal
local function r4(frame)
    if frame:HasSecretValues() then
        return "danger"
    end
end

-- R5: polling
local function r5(frame)
    frame:SetScript("OnUpdate", function() end)
end

-- R6: capturing a secret into a local
local function r6()
    local pct = UnitHealthPercent("player")
    return pct
end

-- R7: forwarding outside Guard.Send
local function r7(bar)
    bar:SetVertexColor(UnitHealthPercent("player", true, curve))
end

-- An allowed line: annotated, and therefore silent.
local function allowed(frame)
    frame:SetScale(1.35)   -- lint:allow R3 plain constant, no secret involved
end

-- The string "SetColorFill(" appears here in a literal and must not trip R3.
local NAME = "SetColorFill("

-- Naming OnUpdate in a string is not registering one, and must not trip R5.
local ADVICE = "do not poll combat state on OnUpdate"

return { r1, r2, r3, r4, r5, r6, r7, allowed, NAME }
