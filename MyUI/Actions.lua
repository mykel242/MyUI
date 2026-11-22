-- MyUI :: Actions.lua
-- SPEC 17 (round 004): the action bars as the player plays them -- bar 1 plus
-- pages reached by holding ALT, CTRL and ALT+CTRL -- centred low, with only
-- ONE row drawn ("Swap"): holding a modifier puts that page in bar 1's place.
--
-- MyUI's own secure action buttons on Blizzard's action slots, one row of
-- buttons per page, each modifier row FIXED to its slots. A secure state
-- driver on MyUI's header shows the row for the modifier held -- the one way
-- a display may change on a modifier during combat. Only bar 1's row pages
-- (stance, stealth and skyriding bonus bars), exactly as Blizzard's bar 1 does.
--
-- The player's keybinds move onto these buttons as override bindings: every
-- key bound to ACTIONBUTTON3 clicks MyUI's bar-1 button 3, every key bound to
-- MULTIACTIONBAR1BUTTON3 clicks MyUI's button 3 of that page. Each row is
-- fixed to its slots, so a key always fires the slot it always fired -- also
-- when the display has not seen the modifier (round 004 play: mouse buttons
-- mapped to ALT and CTRL). The press, the cast flash and the proc glow are
-- drawn on MyUI's button, not on Blizzard's hidden one. A vehicle, possession,
-- override bar or pet battle hides the bar and drops the overrides in the
-- restricted environment, so Blizzard's own bars take those keys back.
--
-- Arranging: every page stacked with its label, held still, so there is
-- somewhere to drop things -- while a spell, item or macro is on the cursor,
-- while the spellbook or macro window is open, or while the player has
-- turned it on (/myui bars, or a key). Out of combat only; a fight folds it
-- and it comes back after.
--
-- Nothing here reads health, power or a cooldown: icons, sweeps, counts and
-- range come from Blizzard's own ActionBarButtonTemplate code.
--
-- Probe P5 (PLAN, round 004) is /myui actions, and /myui mods for what the
-- client sees of the modifier keys.

local ADDON, ns = ...

local Scale = ns.Scale

local Actions = {}
ns.Actions = Actions

local U = function(v) return Scale.U(v) end

Actions.BUTTONS = 8       -- SPEC 17: 8 shown
Actions.SIZE = 44         -- SPEC 17: bar 1 at 44
Actions.GAP = 6
Actions.ROW_GAP = 10      -- between stacked rows while assigning

-- Round 004 play (Mykel): the pages not in bar 1's place drawn small, side
-- by side over it, "so cooldowns are visible but not noisy" -- the "mini"
-- style (default); "swap" draws one row only. A page's mini row hides while
-- its own page is up in bar 1's place, and while arranging.
Actions.MINI_SCALE = 0.45
Actions.MINI_GAP = 6      -- SPEC units between bar 1 and the mini rows
Actions.MINI_SPACE = 24   -- SPEC units between two mini rows
Actions.MINI_ALPHA = 0.6  -- round 004 play: "a little more transparency"
Actions.STYLES = { mini = true, swap = true }

function Actions.Style()
    local s = ns.db and ns.db.pages
    return Actions.STYLES[s] and s or "mini"
end
-- Where the bar sits comes from the layout profile (Layout.lua).

-- Blizzard's action button is built at 45 x 45, and some of its art -- the
-- drop and new-action highlights -- is pinned TOPLEFT at its atlas size, so
-- a button resized with SetSize draws those glows off-centre (round 004
-- play). Buttons stay 45 and the whole bar is SCALED to SPEC's 44, as
-- Blizzard scales its own bars. Positions below are in the bar's units.
Actions.NATIVE = 45

function Actions.Scale()
    return U(Actions.SIZE) / Actions.NATIVE
end

-- Blizzard's binding command prefix for each bar, and its first action slot
-- minus one (Blizzard_ActionBar/Shared/MultiActionBars.lua, *_ACTIONBAR_PAGE).
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

-- The modifier pages, in the order the driver tests them (most specific
-- first). `stack` is the row's place above bar 1 while assigning.
Actions.PAGES = {
    { id = "ac", label = "ALT+CTRL", prefix = "ALT-CTRL-", cond = "[mod:alt,mod:ctrl]", stack = 3, name = "AC" },
    { id = "c",  label = "CTRL",     prefix = "CTRL-",     cond = "[mod:ctrl]",         stack = 1, name = "C" },
    { id = "a",  label = "ALT",      prefix = "ALT-",      cond = "[mod:alt]",          stack = 2, name = "A" },
}

local HIDE_WHEN = "[petbattle][vehicleui][overridebar][possessbar]"

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

--- The state-driver string for the pages that exist. A vehicle (and the
-- like) first; then the modifiers; bar 1 keeps Blizzard's form pages.
function Actions.DriverString(found)
    local parts = { HIDE_WHEN .. " hide" }
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

--- The binding command for button i of a bar: ACTIONBUTTON3, MULTIACTIONBAR1BUTTON3.
function Actions.Command(bar, i)
    if bar == "ACTIONBUTTON" then return "ACTIONBUTTON" .. i end
    return bar .. "BUTTON" .. i
end

-- ---------------------------------------------------------------------------
-- The restricted snippet
-- ---------------------------------------------------------------------------
-- Runs on every state change, in combat too. Generated (unrolled per row)
-- because restricted code may not build tables. Numbers, strings and frame
-- handles only: it shows one row, pages bar 1, and drops or restores the
-- override bindings around a vehicle.

function Actions.Snippet(rows, n)
    local L = {
        "local hidden = newstate == 'hide'",
        "local assign = self:GetAttribute('assign')",
        "local mini = self:GetAttribute('mini')",
        "local show = '1'",
    }
    for _, id in ipairs(rows) do
        if id ~= "1" then L[#L + 1] = ("if newstate == '%s' then show = '%s' end"):format(id, id) end
    end
    L[#L + 1] = "if not hidden and show == '1' then"
    L[#L + 1] = "  local offset = ((tonumber(newstate) or 1) - 1) * 12"
    L[#L + 1] = ("  for i = 1, %d do self:GetFrameRef('1-' .. i):SetAttribute('action', offset + i) end"):format(n)
    L[#L + 1] = "end"
    for _, id in ipairs(rows) do
        L[#L + 1] = ("for i = 1, %d do"):format(n)
        L[#L + 1] = ("  local b = self:GetFrameRef('%s-' .. i)"):format(id)
        L[#L + 1] = ("  if not hidden and (assign or show == '%s') then b:Show() else b:Hide() end"):format(id)
        L[#L + 1] = "end"
    end
    for _, id in ipairs(rows) do
        if id ~= "1" then
            L[#L + 1] = ("for i = 1, %d do"):format(n)
            L[#L + 1] = ("  local b = self:GetFrameRef('m%s-' .. i)"):format(id)
            L[#L + 1] = ("  if not hidden and not assign and mini and show ~= '%s' then b:Show() else b:Hide() end"):format(id)
            L[#L + 1] = "end"
        end
    end
    L[#L + 1] = "if hidden then"
    L[#L + 1] = "  if not self:GetAttribute('unbound') then self:ClearBindings(); self:SetAttribute('unbound', true) end"
    L[#L + 1] = "elseif self:GetAttribute('unbound') then"
    L[#L + 1] = "  for k = 1, self:GetAttribute('nbinds') or 0 do"
    L[#L + 1] = "    self:SetBindingClick(false, self:GetAttribute('bk' .. k), self:GetAttribute('bb' .. k))"
    L[#L + 1] = "  end"
    L[#L + 1] = "  self:SetAttribute('unbound', nil)"
    L[#L + 1] = "end"
    return table.concat(L, "\n")
end

-- ---------------------------------------------------------------------------
-- Display: labels and keybind text (ordinary code; text is never protected)
-- ---------------------------------------------------------------------------

local function KeyText(cmd)
    local key = _G.GetBindingKey and _G.GetBindingKey(cmd)
    if not key then return "" end
    local text = _G.GetBindingText and _G.GetBindingText(key, 1) or key
    return text or ""
end

-- MyUI's own keybind text, top-left (button grammar, round 004). Blizzard's
-- HotKey reads ACTIONBUTTON..GetID() -- these buttons have no ID -- and
-- re-anchors itself top-right on its own events, so it is muted for good.
local function PaintKey(b)
    local key = b.__myuiKey
    if not key then return end
    local text = KeyText(Actions.Command(b.__myuiBar, b.__myuiIndex))
    key:SetText(text)
    if text ~= "" then key:Show() else key:Hide() end
end

--- Labels for the page now showing. `state` is the driver's value: "hide",
-- "a", "c", "ac", or a page number.
function Actions.Paint(state)
    if not Actions.header then return end
    state = state or Actions.header:GetAttribute("state-page") or "1"
    local assign = Actions.header:GetAttribute("assign")
    for id, label in pairs(Actions.labels) do
        if assign or id == state then label:Show() else label:Hide() end
    end
    Actions.state = state
end

function Actions.PaintKeys()
    for _, row in pairs(Actions.rows or {}) do
        for _, b in ipairs(row) do PaintKey(b) end
    end
end

-- ---------------------------------------------------------------------------
-- Layout: Swap (every row in bar 1's place) or stacked (assigning)
-- ---------------------------------------------------------------------------

function Actions.Layout(stacked)
    local sc = Actions.Scale()
    local size, gap = Actions.NATIVE, U(Actions.GAP) / sc
    for id, row in pairs(Actions.rows) do
        local k = stacked and Actions.stackOf[id] or 0
        local y = k * (size + U(Actions.ROW_GAP) / sc)
        for i, b in ipairs(row) do
            b:ClearAllPoints()
            b:SetPoint("BOTTOMLEFT", Actions.header, "BOTTOMLEFT", (i - 1) * (size + gap), y)
        end
        local label = Actions.labels[id]
        if label then
            label:ClearAllPoints()
            label:SetPoint("RIGHT", Actions.header, "BOTTOMLEFT", -U(8) / sc, y + size / 2)
        end
    end
    Actions.LayoutMinis()
end

--- The mini rows: side by side in equal slots over bar 1, left to right in
-- the order ALT, CTRL, ALT+CTRL. A scaled frame's offsets are in its own
-- units, hence the divisions.
--- Does a page hold anything in the slots MyUI draws? Plain API.
function Actions.PageUsed(id)
    local f = Actions.found and Actions.found[id]
    if not f then return false end
    local has = (_G.C_ActionBar and _G.C_ActionBar.HasAction) or _G.HasAction
    if not has then return true end
    for i = 1, Actions.BUTTONS do
        local ok, yes = pcall(has, f.offset + i)
        if ok and yes then return true end
    end
    return false
end

function Actions.LayoutMinis()
    if InCombatLockdown() then Actions.minisPending = true return end
    Actions.minisPending = false
    local frames = {}
    for _, page in ipairs({ "a", "c", "ac" }) do
        local f = Actions.minis and Actions.minis[page]
        if f then
            -- Round 004 play: a page with nothing on it is left out, and the
            -- rest centre without it.
            if Actions.PageUsed(page) then
                frames[#frames + 1] = f
                f:Show()
            else
                f:Hide()
            end
        end
    end
    local k = #frames
    if k == 0 then return end
    local sc = Actions.Scale()
    local width = Actions.header:GetWidth()
    local space = U(Actions.MINI_SPACE) / sc
    local s = math.min(Actions.MINI_SCALE, (width - (k - 1) * space) / (k * width))
    -- Centred as a group over bar 1 (round 004 play: they sat left of
    -- centre), in the bar's units; a scaled frame's offsets are in its own.
    local miniW = width * s
    local left = (width - (k * miniW + (k - 1) * space)) / 2
    for i, f in ipairs(frames) do
        f:SetScale(s)   -- lint:allow R3 a constant from SPEC sizes, never a unit value
        f:SetAlpha(Actions.MINI_ALPHA)
        f:ClearAllPoints()
        f:SetPoint("BOTTOMLEFT", Actions.header, "TOPLEFT", (left + (i - 1) * (miniW + space)) / s,
                   (U(Actions.MINI_GAP) / sc) / s)
    end
end

--- /myui pages: mini (the other pages small over bar 1) or swap (one row).
function Actions.SetStyle(style)
    if not Actions.STYLES[style] then return nil end
    if ns.db then ns.db.pages = style end
    if Actions.header and not InCombatLockdown() then
        Actions.header:SetAttribute("mini", style == "mini" or nil)
        Actions.header:Execute("local newstate = self:GetAttribute('state-page') or '1'\n" .. Actions.snippet)
    end
    return style
end

--- Where the bar sits on screen, in UIParent units: half its width, its
-- bottom, and one row's height -- what the wings line up against (SPEC 18).
function Actions.Extent()
    local width = Actions.BUTTONS * U(Actions.SIZE) + (Actions.BUTTONS - 1) * U(Actions.GAP)
    local _, _, x, y = ns.Layout.Pos("ActionBar")
    return width / 2, U(y), U(Actions.SIZE), U(Actions.ROW_GAP), U(x)
end

--- Anchor the bar where the profile says (secure: out of combat only).
function Actions.Place()
    if not Actions.header or InCombatLockdown() then return false end
    local sc = Actions.Scale()
    local point, rel, x, y = ns.Layout.Pos("ActionBar")
    Actions.header:ClearAllPoints()
    -- A scaled frame's offsets are in its own units.
    Actions.header:SetPoint(point, UIParent, rel, U(x) / sc, U(y) / sc)
    return true
end

--- Re-run the page snippet now, against the current state (out of combat).
local function Reapply()
    Actions.header:Execute("local newstate = self:GetAttribute('state-page') or '1'\n" .. Actions.snippet)
    Actions.Paint()
end

--- Assigning: something placeable is on the cursor. Out of combat only --
-- moving and showing secure buttons is protected in combat.
function Actions.SetAssign(on)
    if not Actions.header or InCombatLockdown() then return false end
    on = on and true or nil
    if Actions.header:GetAttribute("assign") == on then return true end
    Actions.header:SetAttribute("assign", on)
    Actions.Layout(on)
    Reapply()
    if on then ns.Reveal.Claim("assign") else ns.Reveal.Release("assign") end
    -- The target's claim decides the stance and pet bars by whether the
    -- pages are stacked: claim it again so that is asked now.
    if _G.UnitExists and _G.UnitExists("target") then
        ns.Reveal.Release("target")
        ns.Reveal.Claim("target")
    end
    return true
end

--- True while every page is drawn stacked (arranging).
function Actions.IsStacked()
    return Actions.header ~= nil and Actions.header:GetAttribute("assign") == true
end

--- Why the bar is arranged: any reason keeps it stacked. "cursor" (something
-- picked up), "book" (spellbook or macros open), "arrange" (the player's
-- toggle). Applied now, or when combat ends.
Actions.reasons = {}

function Actions.Want(reason, on)
    Actions.reasons[reason] = on and true or nil
    return Actions.Apply()
end

function Actions.Apply()
    if InCombatLockdown() then return false end
    local ok = Actions.SetAssign(next(Actions.reasons) ~= nil)
    Actions.Strata()
    return ok
end

-- What of MyUI's takes clicks at the bottom of the screen, above Blizzard's.
Actions.CLICKABLE = { "MyUIActionHeader", "MyUISelfButton", "MyUIPetButton", "MyUIPetBar",
                      "MyUITargetButton", "MyUIFocusButton" }

--- Round 005 play ("I actually can't change specs"): the bar and the target
-- strip sat over the talents window's Apply button and the middle spec's
-- Activate, taking their clicks. While that window is on its talents or
-- specialization page they go under it -- unless something is being placed,
-- which needs the bar on top.
function Actions.Strata()
    if InCombatLockdown() then return false end
    local under = Actions.covered and next(Actions.reasons) == nil
    for _, name in ipairs(Actions.CLICKABLE) do
        local f = _G[name]
        if f and f.SetFrameStrata then f:SetFrameStrata(under and "LOW" or "HIGH") end
    end
    return true
end

function Actions.Arranging()
    return Actions.reasons.arrange == true
end

--- /myui bars and the key: hold every page on screen until asked again.
function Actions.ToggleArrange()
    Actions.Want("arrange", not Actions.reasons.arrange)
    return Actions.reasons.arrange == true
end

_G.MyUI_ArrangeBars = function()
    local on = Actions.ToggleArrange()
    if InCombatLockdown() then
        ns.Print("bars: arranging after combat")
    else
        ns.Print(on and "bars: every page on screen -- drag to rearrange; the same key puts them away"
                    or "bars: back to one row")
    end
end
_G.BINDING_NAME_MYUI_ARRANGE = "Arrange the action bars"

-- The spellbook (Blizzard_PlayerSpells) and macro window (Blizzard_MacroUI)
-- load on demand: hooked when they load, or now if they already have.
local BOOKS = { Blizzard_PlayerSpells = "PlayerSpellsFrame", Blizzard_MacroUI = "MacroFrame" }
Actions.books = {}

-- The spellbook is one page of PlayerSpellsFrame; talents and specialization
-- are the others, and there is nothing to arrange on those. (A talent dragged
-- to the bar is on the cursor, which arranges it anyway.)
local function Arranges(f)
    local page = f.SpellBookFrame
    if not f:IsShown() then return false end
    return page == nil or page:IsShown() == true
end

local function BookChanged()
    local open, covered = false, false
    for _, f in pairs(Actions.books) do
        if Arranges(f) then open = true
        elseif f:IsShown() then covered = true end
    end
    Actions.covered = covered
    Actions.Want("book", open)
end

function Actions.HookBooks()
    for _, name in pairs(BOOKS) do
        local f = _G[name]
        if f and not Actions.books[name] then
            Actions.books[name] = f
            f:HookScript("OnShow", BookChanged)
            f:HookScript("OnHide", BookChanged)
            if f.SpellBookFrame then
                f.SpellBookFrame:HookScript("OnShow", BookChanged)
                f.SpellBookFrame:HookScript("OnHide", BookChanged)
            end
            if f:IsShown() then BookChanged() end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Bindings: the player's keys, onto MyUI's buttons (out of combat only)
-- ---------------------------------------------------------------------------

function Actions.Bind()
    local header = Actions.header
    if not header or InCombatLockdown() then return false end
    local list = {}
    for _, id in ipairs(Actions.order) do
        for i, b in ipairs(Actions.rows[id]) do
            for _, key in ipairs({ _G.GetBindingKey(Actions.Command(b.__myuiBar, i)) }) do
                list[#list + 1] = { key, b:GetName() }
            end
        end
    end
    -- Override bindings may themselves raise UPDATE_BINDINGS: rebinding the
    -- same keys again would never end.
    local parts = {}
    for k, kb in ipairs(list) do parts[k] = kb[1] .. "=" .. kb[2] end
    local sig = table.concat(parts, ",")
    if sig == Actions.bindSig then return true end
    Actions.bindSig = sig

    _G.ClearOverrideBindings(header)
    for k, kb in ipairs(list) do
        header:SetAttribute("bk" .. k, kb[1])
        header:SetAttribute("bb" .. k, kb[2])
    end
    header:SetAttribute("nbinds", #list)
    Actions.nbinds = #list
    -- Bind through the snippet's own path, so a vehicle at this moment
    -- keeps Blizzard's keys.
    header:SetAttribute("unbound", true)
    Reapply()
    return true
end

-- ---------------------------------------------------------------------------
-- Build (out of combat only: creating secure frames is protected in combat)
-- ---------------------------------------------------------------------------

local function MakeButton(header, name, bar, i, action)
    local b = CreateFrame("CheckButton", name, header, "ActionBarButtonTemplate")
    b:SetSize(Actions.NATIVE, Actions.NATIVE)
    b:SetAttribute("action", action)
    b.__myuiIndex, b.__myuiBar = i, bar
    -- Quieter than Blizzard's frame art: the icon, the sweep, the count.
    if b.NormalTexture then b.NormalTexture:SetAlpha(0) end
    if b.HotKey then b.HotKey:SetAlpha(0) end
    local key = ns.Frames.Text(b, 10, "textPrimary", "LEFT")
    key:SetPoint("TOPLEFT", b, "TOPLEFT", U(3), -U(3))
    b.__myuiKey = key
    return b
end

local function MakeLabel(header, text)
    local label = header:CreateFontString(nil, "OVERLAY")
    label:SetFont(ns.Frames.FONT, U(10), "")
    label:SetTextColor(ns.Palette.Get("notifAmber"))
    label:SetJustifyH("RIGHT")
    label:SetText(text)
    label:Hide()
    return label
end

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
    local sc = Actions.Scale()
    local n, size, gap = Actions.BUTTONS, Actions.NATIVE, U(Actions.GAP) / sc
    header:SetScale(sc)   -- lint:allow R3 a constant from SPEC sizes, never a unit value
    header:SetSize(n * size + (n - 1) * gap, size)
    Actions.header = header
    Actions.Place()

    Actions.rows, Actions.labels, Actions.stackOf = {}, {}, { ["1"] = 0 }
    local order = { "1" }
    Actions.rows["1"] = {}
    for i = 1, n do
        local b = MakeButton(header, "MyUIActionButton" .. i, "ACTIONBUTTON", i, i)
        header:SetFrameRef("1-" .. i, b)
        Actions.rows["1"][i] = b
    end
    for _, page in ipairs(Actions.PAGES) do
        local f = found[page.id]
        if f then
            order[#order + 1] = page.id
            Actions.stackOf[page.id] = page.stack
            Actions.rows[page.id] = {}
            for i = 1, n do
                local b = MakeButton(header, "MyUIAction" .. page.name .. i, f.bar, i, f.offset + i)
                header:SetFrameRef(page.id .. "-" .. i, b)
                b:Hide()
                Actions.rows[page.id][i] = b
            end
            Actions.labels[page.id] = MakeLabel(header, page.label)

            -- The page's mini row: same slots, small, display first (a click
            -- still works), no keybind text -- the full row carries the keys.
            local mf = CreateFrame("Frame", nil, header)
            mf:SetSize(n * Actions.NATIVE + (n - 1) * (U(Actions.GAP) / Actions.Scale()), Actions.NATIVE)
            Actions.minis = Actions.minis or {}
            Actions.minis[page.id] = mf
            Actions.miniButtons = Actions.miniButtons or {}
            Actions.miniButtons[page.id] = {}
            for i = 1, n do
                local b = MakeButton(mf, "MyUIActionMini" .. page.name .. i, f.bar, i, f.offset + i)
                b:SetPoint("BOTTOMLEFT", mf, "BOTTOMLEFT", (i - 1) * (Actions.NATIVE + U(Actions.GAP) / Actions.Scale()), 0)
                if b.__myuiKey then b.__myuiKey:Hide(); b.__myuiKey = nil end
                -- An empty slot draws nothing in a mini row (round 004 play:
                -- an empty CTRL page was a row of dark boxes).
                if b.SlotBackground then b.SlotBackground:SetAlpha(0) end
                if b.SlotArt then b.SlotArt:SetAlpha(0) end
                header:SetFrameRef("m" .. page.id .. "-" .. i, b)
                b:Hide()
                Actions.miniButtons[page.id][i] = b
            end
        end
    end
    header:SetAttribute("mini", Actions.Style() == "mini" or nil)
    Actions.buttons = Actions.rows["1"]
    Actions.order = order
    Actions.Layout(false)

    Actions.snippet = Actions.Snippet(order, n)
    header:SetAttribute("_onstate-page", Actions.snippet)
    header:HookScript("OnAttributeChanged", function(_, name, value)
        if name == "state-page" then Actions.Paint(value) end
    end)
    Actions.driver = Actions.DriverString(found)
    RegisterStateDriver(header, "page", Actions.driver)

    Actions.Bind()
    Actions.PaintKeys()
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
        nbinds = Actions.nbinds,
        unbound = Actions.header and Actions.header:GetAttribute("unbound") or false,
        pages = {},
    }
    for _, page in ipairs(Actions.PAGES) do
        local f = Actions.found and Actions.found[page.id]
        r.pages[#r.pages + 1] = ("%s -> %s"):format(page.label, f and (f.bar .. " (slots " .. (f.offset + 1) .. "-" .. (f.offset + Actions.BUTTONS) .. ")") or "not bound")
    end
    if Actions.driver and _G.SecureCmdOptionParse then
        r.parsed = _G.SecureCmdOptionParse(Actions.driver)
    end
    -- Blizzard's bar 1 must stay shown at alpha 0 under MyUI's.
    local main, blz = _G.MainActionBar, _G.ActionButton1
    r.mainShown = main and main:IsShown() or false
    r.mainAlpha = main and main:GetAlpha()
    r.button1Alpha = blz and blz.GetEffectiveAlpha and blz:GetEffectiveAlpha()
    r.combat = InCombatLockdown()
    -- Every Blizzard bar: shown, alpha, strata, and its button 1's drawn alpha.
    r.blizzard = {}
    for _, spec in ipairs(ns.Clear and ns.Clear.BLIZZARD_BARS or {}) do
        local bar, b = _G[spec[1]], _G[spec[2] .. "1"]
        if bar then
            r.blizzard[#r.blizzard + 1] = ("%s: %s, alpha %s, %s; button 1 drawn at %s, mouse %s"):format(
                spec[1], bar:IsShown() and "shown" or "hidden", tostring(bar:GetAlpha()),
                tostring(bar.GetFrameStrata and bar:GetFrameStrata()),
                tostring(b and b.GetEffectiveAlpha and b:GetEffectiveAlpha()),
                tostring(b and b.IsMouseEnabled and b:IsMouseEnabled()))
        end
    end
    if ns.db then ns.db.actionsProbe = r end
    return r
end

-- /myui mods: for a few seconds, every change the client reports in the
-- modifier keys -- by event and by polling, which is what the state driver
-- does -- so a mouse button mapped to ALT can be checked against the keyboard.
function Actions.WatchMods(seconds)
    local w = Actions.modWatch or CreateFrame("Frame")
    Actions.modWatch = w
    local last, t0 = nil, GetTime()
    local function now()
        return (_G.IsAltKeyDown() and "ALT " or "") .. (_G.IsControlKeyDown() and "CTRL " or "")
               .. (_G.IsShiftKeyDown() and "SHIFT " or "")
    end
    w:RegisterEvent("MODIFIER_STATE_CHANGED")
    w:SetScript("OnEvent", function(_, _, key, down)
        ns.Raw(("  %.2fs event  %s %s"):format(GetTime() - t0, tostring(key), down == 1 and "down" or "up"))
    end)
    -- Polled on a 0.05s timer (RULES R5 keeps OnUpdate for the reveal engine);
    -- the state driver itself polls every 0.2s.
    local function poll()
        local s = now()
        if s ~= last then
            ns.Raw(("  %.2fs held   %s  (bar page: %s)"):format(GetTime() - t0, s == "" and "none" or s,
                   tostring(Actions.header and Actions.header:GetAttribute("state-page"))))
            last = s
        end
        if GetTime() - t0 > (seconds or 10) then
            w:UnregisterAllEvents()
            ns.Raw("  done")
            return
        end
        C_Timer.After(0.05, poll)
    end
    Actions.modPoll = poll
    poll()
end

-- ---------------------------------------------------------------------------
-- Login
-- ---------------------------------------------------------------------------

--- Blizzard's spell flyout (Call Pet, portals, ...) opens over the bar; the
-- bar is held up while it is open.
function Actions.HookFlyout()
    local fly = _G.SpellFlyout
    if not fly or Actions.flyoutHooked then return end
    fly:HookScript("OnShow", function() ns.Reveal.Claim("hold", "ActionBar") end)
    fly:HookScript("OnHide", function() ns.Reveal.Release("hold", "ActionBar") end)
    Actions.flyoutHooked = true
end

function Actions.Start()
    if not Actions.Build() then return false end
    Actions.Register()
    Actions.HookFlyout()
    local ev = Actions.events or CreateFrame("Frame")
    Actions.events = ev
    ev:RegisterEvent("UPDATE_BINDINGS")
    ev:RegisterEvent("ACTIONBAR_SHOWGRID")
    ev:RegisterEvent("ACTIONBAR_HIDEGRID")
    ev:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    ev:RegisterEvent("PLAYER_REGEN_DISABLED")
    ev:RegisterEvent("ADDON_LOADED")
    ev:SetScript("OnEvent", function(_, event)
        if event == "UPDATE_BINDINGS" then
            Actions.rebind = not Actions.Bind()
            Actions.PaintKeys()
        elseif event == "PLAYER_REGEN_ENABLED" then
            if Actions.rebind then
                Actions.rebind = not Actions.Bind()
                Actions.PaintKeys()
            end
            Actions.Apply()
            if Actions.minisPending then Actions.LayoutMinis() end
        elseif event == "PLAYER_REGEN_DISABLED" then
            -- Fires just before the lockdown: the last moment to fold.
            Actions.SetAssign(false)
        elseif event == "ADDON_LOADED" then
            Actions.HookBooks()
        elseif event == "ACTIONBAR_SHOWGRID" then
            if ns.Clear and ns.Clear.barsPinned then ns.Clear.PinBars() end
            Actions.Want("cursor", true)
        elseif event == "ACTIONBAR_HIDEGRID" then
            Actions.Want("cursor", false)
        elseif event == "ACTIONBAR_SLOT_CHANGED" then
            -- A page may have filled or emptied: which minis show.
            Actions.LayoutMinis()
        end
    end)
    Actions.HookBooks()
    return true
end

function Actions.OnLogin()
    -- Round 005: with the "bars" switch off, Blizzard keeps its action bars.
    if ns.Switches and not ns.Switches.On("bars") then return end
    if Actions.Start() then return end
    local wait = CreateFrame("Frame")
    wait:RegisterEvent("PLAYER_REGEN_ENABLED")
    wait:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        Actions.Start()
    end)
end

--- Join the reveal engine: resting 0, back in combat and on peek or hover,
-- like the rest of the combat set. Blizzard's bar 1 (adopted by Clear) steps
-- out of the registry so it never comes back on top of these, pinned at 0.
function Actions.Register()
    if not Actions.header or ns.Registry.Get("ActionBar") then return end
    ns.Registry.Add("ActionBar", Actions.header, 0)
    if ns.Registry.Get("MainBar") then ns.Registry.Remove("MainBar") end
    if ns.Clear and ns.Clear.PinBars then ns.Clear.PinBars() end
    ns.Reveal.Resolve()
    ns.Reveal.Snap()
end
