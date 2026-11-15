-- MyUI :: Actions.lua
-- SPEC 17 (round 004): the action bars as the player plays them -- bar 1 plus
-- pages reached by holding ALT, CTRL and ALT+CTRL -- centred low, with only
-- ONE row drawn ("Swap"): holding a modifier puts that page in bar 1's place.
--
-- MyUI's own secure action buttons on Blizzard's action slots. Blizzard's
-- bars stay hidden (the MyUI layout) and keep the player's keybinds: ALT+1
-- still fires what it always fired. These buttons show the same slots and
-- click them.
--
-- Paging is a SECURE STATE DRIVER on MyUI's header -- the one way a display
-- may change on a modifier during combat. The page snippet runs in Blizzard's
-- restricted environment and only reassigns each button's "action" attribute.
-- Nothing here reads health, power or a cooldown: icons, cooldown sweeps,
-- counts and range come from Blizzard's own ActionBarButtonTemplate code.
--
-- Paging moves by Blizzard's 12-slot pages; only the first 8 of each are drawn.
--
-- Probe P5 (PLAN, round 004) is /myui actions: it reports what was detected
-- and built, so the first in-game run says whether this approach holds.

local ADDON, ns = ...

local Scale = ns.Scale

local Actions = {}
ns.Actions = Actions

local U = function(v) return Scale.U(v) end

Actions.BUTTONS = 8       -- SPEC 17: 8 shown
Actions.SIZE = 44        -- SPEC 17: bar 1 at 44
Actions.GAP = 6
Actions.BOTTOM = 48      -- SPEC 17: low on the screen

-- Blizzard's binding command for each bar, and its first action slot minus one
-- (Blizzard_ActionBar/Shared/MultiActionBars.lua: the *_ACTIONBAR_PAGE values).
Actions.BAR_OFFSET = {
    ACTIONBUTTON      = 0,     -- bar 1 (page 1)
    MULTIACTIONBAR1   = 60,    -- bottom left,  page 6
    MULTIACTIONBAR2   = 48,    -- bottom right, page 5
    MULTIACTIONBAR3   = 24,    -- right,        page 3
    MULTIACTIONBAR4   = 36,    -- left,         page 4
    MULTIACTIONBAR5   = 144,   -- page 13
    MULTIACTIONBAR6   = 156,   -- page 14
    MULTIACTIONBAR7   = 168,   -- page 15
}

-- The modifier pages, in the order the driver tests them (most specific first).
Actions.PAGES = {
    { id = "ac", label = "ALT+CTRL", prefix = "ALT-CTRL-", cond = "[mod:alt,mod:ctrl]" },
    { id = "c",  label = "CTRL",     prefix = "CTRL-",     cond = "[mod:ctrl]" },
    { id = "a",  label = "ALT",      prefix = "ALT-",      cond = "[mod:alt]" },
}

--- Which bar a modifier pages to, read from the player's own keybinds:
-- whatever MODIFIER-1 is bound to names the bar. Plain API, nothing secret.
-- Returns command prefix (e.g. "MULTIACTIONBAR1") and slot offset, or nil.
function Actions.DetectPage(prefix)
    local get = _G.GetBindingAction
    if type(get) ~= "function" then return nil end
    local cmd = get(prefix .. "1")
    if (cmd == nil or cmd == "") and prefix == "ALT-CTRL-" then
        cmd = get("CTRL-ALT-1")
    end
    if type(cmd) ~= "string" then return nil end
    local bar = cmd == "ACTIONBUTTON1" and "ACTIONBUTTON" or cmd:match("^(MULTIACTIONBAR%d)BUTTON1$")
    if bar and Actions.BAR_OFFSET[bar] then
        return bar, Actions.BAR_OFFSET[bar]
    end
    return nil
end

--- The state-driver string for the pages that exist. Bar 1 keeps Blizzard's
-- own form pages (stance / stealth / skyriding bonus bars) underneath.
function Actions.DriverString(found)
    local parts = {}
    for _, page in ipairs(Actions.PAGES) do
        if found[page.id] then
            parts[#parts + 1] = page.cond .. " " .. page.id
        end
    end
    for n = 5, 1, -1 do
        parts[#parts + 1] = ("[bonusbar:%d] %d"):format(n, 6 + n)
    end
    parts[#parts + 1] = "1"
    return table.concat(parts, "; ")
end

-- Runs in the restricted environment on every page change, in combat too.
-- Only reassigns "action"; numbers in, numbers out.
local PAGE_SNIPPET = [[
    local offset
    if newstate == "ac" or newstate == "c" or newstate == "a" then
        offset = self:GetAttribute("offset-" .. newstate) or 0
    else
        offset = ((tonumber(newstate) or 1) - 1) * 12
    end
    local n = self:GetAttribute("numbuttons") or 8
    for i = 1, n do
        local b = self:GetFrameRef("b" .. i)
        if b then b:SetAttribute("action", offset + i) end
    end
]]

-- ---------------------------------------------------------------------------
-- Display: label and keybind text (ordinary code; text is never protected)
-- ---------------------------------------------------------------------------

--- The binding command for button i of a bar: ACTIONBUTTON3, MULTIACTIONBAR1BUTTON3.
function Actions.Command(bar, i)
    if bar == "ACTIONBUTTON" then return "ACTIONBUTTON" .. i end
    return bar .. "BUTTON" .. i
end

local function KeyText(cmd)
    local key = _G.GetBindingKey and _G.GetBindingKey(cmd)
    if not key then return "" end
    local text = _G.GetBindingText and _G.GetBindingText(key, 1) or key
    return text or ""
end

-- Blizzard's UpdateHotkeys reads ACTIONBUTTON..GetID(), and these buttons
-- have no ID; it runs on its own events, so the right text goes on after it.
local function PaintKey(b)
    local hk = b.HotKey
    if not hk then return end
    local text = KeyText(Actions.Command(Actions.bar or "ACTIONBUTTON", b.__myuiIndex))
    hk:SetText(text)
    if text ~= "" then hk:Show() else hk:Hide() end
    -- Button grammar (round 004): the keybind top-left.
    hk:ClearAllPoints()
    hk:SetPoint("TOPLEFT", b, "TOPLEFT", U(3), -U(3))
    hk:SetJustifyH("LEFT")
end

--- Label and keybinds for the page now showing. `state` is the driver's
-- value: "a", "c", "ac", or a page number.
function Actions.Paint(state)
    if not Actions.header then return end
    state = state or Actions.header:GetAttribute("state-page") or "1"
    local label, bar = "", "ACTIONBUTTON"
    for _, page in ipairs(Actions.PAGES) do
        if page.id == state and Actions.found[page.id] then
            label, bar = page.label, Actions.found[page.id].bar
        end
    end
    Actions.label:SetText(label)
    Actions.bar, Actions.state = bar, state
    for _, b in ipairs(Actions.buttons) do PaintKey(b) end
end

-- ---------------------------------------------------------------------------
-- Build (out of combat only: creating secure frames is protected in combat)
-- ---------------------------------------------------------------------------

function Actions.Build()
    if Actions.header then return true end
    if InCombatLockdown() then return false, "in combat" end

    local found = {}
    for _, page in ipairs(Actions.PAGES) do
        local bar, offset = Actions.DetectPage(page.prefix)
        if bar then found[page.id] = { bar = bar, offset = offset } end
    end
    Actions.found = found

    local header = CreateFrame("Frame", "MyUIActionHeader", UIParent, "SecureHandlerStateTemplate")
    header:SetFrameStrata("HIGH")
    local n, size, gap = Actions.BUTTONS, U(Actions.SIZE), U(Actions.GAP)
    header:SetSize(n * size + (n - 1) * gap, size)
    header:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, U(Actions.BOTTOM))
    header:SetAttribute("numbuttons", n)
    for id, f in pairs(found) do
        header:SetAttribute("offset-" .. id, f.offset)
    end

    Actions.buttons = {}
    for i = 1, n do
        local b = CreateFrame("CheckButton", "MyUIActionButton" .. i, header, "ActionBarButtonTemplate")
        b:SetSize(size, size)
        b:SetPoint("LEFT", header, "LEFT", (i - 1) * (size + gap), 0)
        b:SetAttribute("action", i)
        b.__myuiIndex = i
        -- Quieter than Blizzard's frame art: the icon, the sweep, the count.
        if b.NormalTexture then b.NormalTexture:SetAlpha(0) end
        if type(b.UpdateHotkeys) == "function" then
            hooksecurefunc(b, "UpdateHotkeys", PaintKey)
        end
        header:SetFrameRef("b" .. i, b)
        Actions.buttons[i] = b
    end

    local label = header:CreateFontString(nil, "OVERLAY")
    label:SetFont(ns.Frames.FONT, U(10), "")
    label:SetTextColor(ns.Palette.Get("notifAmber"))
    label:SetPoint("RIGHT", header, "LEFT", -U(8), 0)
    Actions.label = label

    header:SetAttribute("_onstate-page", PAGE_SNIPPET)
    header:HookScript("OnAttributeChanged", function(_, name, value)
        if name == "state-page" then Actions.Paint(value) end
    end)
    Actions.driver = Actions.DriverString(found)
    RegisterStateDriver(header, "page", Actions.driver)
    -- Vehicles, possession and pet battles bring Blizzard's own bars.
    RegisterStateDriver(header, "visibility", "[petbattle][vehicleui][overridebar][possessbar] hide; show")

    Actions.header = header
    Actions.Paint()
    return true
end

-- ---------------------------------------------------------------------------
-- Probe P5 -- what was detected and built, for /myui actions and the harness
-- ---------------------------------------------------------------------------

function Actions.Probe()
    local r = {
        built = Actions.header ~= nil,
        driver = Actions.driver,
        state = Actions.header and Actions.header:GetAttribute("state-page"),
        action1 = Actions.buttons and Actions.buttons[1] and Actions.buttons[1]:GetAttribute("action"),
        pages = {},
    }
    for _, page in ipairs(Actions.PAGES) do
        local f = Actions.found and Actions.found[page.id]
        r.pages[#r.pages + 1] = ("%s -> %s"):format(page.label, f and (f.bar .. " (slots " .. (f.offset + 1) .. "-" .. (f.offset + Actions.BUTTONS) .. ")") or "not bound")
    end
    -- Does the driver's string parse on this client, and to what right now?
    if Actions.driver and _G.SecureCmdOptionParse then
        r.parsed = _G.SecureCmdOptionParse(Actions.driver)
    end
    -- Blizzard's bar 1 must stay shown (alpha 0) for its keybinds.
    local main = _G.MainActionBar
    r.mainShown = main and main:IsShown() or false
    r.mainAlpha = main and main:GetAlpha()
    r.combat = InCombatLockdown()
    if ns.db then ns.db.actionsProbe = r end
    return r
end

-- ---------------------------------------------------------------------------
-- Login
-- ---------------------------------------------------------------------------

function Actions.OnLogin()
    local ok = Actions.Build()
    if not ok then
        local wait = CreateFrame("Frame")
        wait:RegisterEvent("PLAYER_REGEN_ENABLED")
        wait:SetScript("OnEvent", function(self)
            self:UnregisterAllEvents()
            Actions.Build()
            Actions.Register()
        end)
        return
    end
    Actions.Register()
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("UPDATE_BINDINGS")
    ev:SetScript("OnEvent", function() Actions.Paint() end)
end

--- Join the reveal engine: resting 0, back in combat and on peek or hover,
-- like the rest of the combat set. Blizzard's bar 1 (adopted by Clear) steps
-- out of the registry so it never comes back on top of these.
function Actions.Register()
    if not Actions.header or ns.Registry.Get("ActionBar") then return end
    ns.Registry.Add("ActionBar", Actions.header, 0)
    if ns.Registry.Get("MainBar") then
        ns.Registry.Remove("MainBar")
        if _G.MainActionBar then _G.MainActionBar:SetAlpha(0) end
    end
    ns.Reveal.Resolve()
    ns.Reveal.Snap()
end
