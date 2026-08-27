-- MyUI :: Copy.lua
-- A selectable window holding the last command's output.
--
-- WoW's chat frame is close to impossible to copy out of, and every report
-- this addon produces exists to be read somewhere else. Two routes out:
--
--   /myui copy    this window -- select, cmd-C, paste
--   MyUIDB        every command's output is persisted, so after a /reload the
--                 text can be read straight off disk with no copying at all
--
-- Ported from the Rebar project's Copy.lua.

local ADDON, ns = ...

local Copy = {}
ns.Copy = Copy

local frame, editBox

local function Build()
    frame = CreateFrame("Frame", "MyUICopy", UIParent)
    frame:SetSize(760, 460)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)

    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.92)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText("|cff8cd3ffMyUI|r output")

    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPRIGHT", -12, -12)
    hint:SetText("cmd-C to copy  |  escape to close")

    local close = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    close:SetSize(70, 22)
    close:SetPoint("BOTTOMRIGHT", -10, 10)
    close:SetText("close")
    close:SetScript("OnClick", function() frame:Hide() end)

    local scroll = CreateFrame("ScrollFrame", "MyUICopyScroll", frame,
                               "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -34)
    scroll:SetPoint("BOTTOMRIGHT", -32, 40)

    editBox = CreateFrame("EditBox", nil, scroll)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject("ChatFontNormal")
    editBox:SetWidth(700)
    editBox:SetScript("OnEscapePressed", function() frame:Hide() end)
    -- Read-only in effect: any edit is reverted, so the text stays selectable
    -- but cannot be mangled before copying.
    editBox:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            self:SetText(self.myuiText or "")
            self:HighlightText()
        end
    end)
    scroll:SetScrollChild(editBox)

    frame:Hide()
end

local function Ensure()
    if not frame then Build() end
    return frame
end

--- Show text in the copy window, selected and ready to copy.
function Copy.Show(text)
    Ensure()
    if not text or text == "" then
        text = "(nothing captured yet -- run a command first)"
    end
    editBox.myuiText = text
    editBox:SetText(text)
    editBox:SetCursorPosition(0)
    frame:Show()
    editBox:SetFocus()
    editBox:HighlightText()
end

function Copy.Hide()
    if frame then frame:Hide() end
end

function Copy.IsShown()
    return frame ~= nil and frame:IsShown()
end
