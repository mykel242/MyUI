-------------------------------------------------------------------------------
-- Namespaces
-------------------------------------------------------------------------------
local _, core = ...; -- // Addon name, Namespace
core.Config = {};

local Config = core.Config;
local myConfigFrame;

-------------------------------------------------------------------------------
-- Datastores
-------------------------------------------------------------------------------
local defaults = {
  theme = {
    r = 0, g = 0, b = 0, hex="000000"
  }
}


-------------------------------------------------------------------------------
-- Configuration UI Elements
-------------------------------------------------------------------------------
function createMyConfigWidget()
  myConfigFrame = CreateFrame("Frame", "MYUI_Frame",
    UIParent, "BasicFrameTemplateWithInset")
  myConfigFrame:SetSize(200,320)
  myConfigFrame:SetPoint("CENTER", UIParent, "CENTER")
  --

  -- myConfigFrame.Title:ClearAllPoints()
  -- myConfigFrame.Title:SetFontObject("GameFontHighlight")
  -- myConfigFrame.Title:SetPoint("LEFT", myConfigFrame.TitleBG, "LEFT", 6, 1)
  -- myConfigFrame.Title:SetText("MyUI Config")

  myConfigFrame.button1 = CreateFrame("Button", nil,
    myConfigFrame, "GameMenuButtonTemplate")
  myConfigFrame.button1:SetPoint("CENTER", myConfigFrame,
    "TOP", 0, -70)
  myConfigFrame.button1:SetSize(140,40)
  myConfigFrame.button1:SetText("Boom")
  myConfigFrame.button1:SetNormalFontObject("GameFontNormalLarge")
  myConfigFrame.button1:SetHighlightFontObject("GameFontHighlightLarge")
  --
  myConfigFrame.button2 = CreateFrame("Button", nil,
    myConfigFrame, "GameMenuButtonTemplate")
  myConfigFrame.button2:SetPoint("CENTER", myConfigFrame.button1,
    "BOTTOM", 0, -20)
  myConfigFrame.button2:SetSize(140,40)
  myConfigFrame.button2:SetText("Shaka")
  myConfigFrame.button2:SetNormalFontObject("GameFontNormalLarge")
  myConfigFrame.button2:SetHighlightFontObject("GameFontHighlightLarge")
  --
  myConfigFrame.button3 = CreateFrame("Button", nil,
    myConfigFrame, "GameMenuButtonTemplate")
  myConfigFrame.button3:SetPoint("CENTER", myConfigFrame.button2,
    "BOTTOM", 0, -20)
  myConfigFrame.button3:SetSize(140,40)
  myConfigFrame.button3:SetText("Laka")
  myConfigFrame.button3:SetNormalFontObject("GameFontNormalLarge")
  myConfigFrame.button3:SetHighlightFontObject("GameFontHighlightLarge")
  --
  myConfigFrame.slider1 = CreateFrame("Slider", nil,
    myConfigFrame, "OptionsSliderTemplate")
  myConfigFrame.slider1:SetPoint("TOP", myConfigFrame.button3,
    "BOTTOM", 0, -10)
  myConfigFrame.slider1:SetMinMaxValues(1,100)
  myConfigFrame.slider1:SetValue(50)
  myConfigFrame.slider1:SetValueStep(10)
  myConfigFrame.slider1:SetObeyStepOnDrag(true)
  --
  myConfigFrame.checkbtn1 = CreateFrame("CheckButton", nil,
    myConfigFrame, "UICheckButtonTemplate")
  myConfigFrame.checkbtn1:SetPoint("TOPLEFT", myConfigFrame.slider1,
    "BOTTOMLEFT", 0, -20)
  myConfigFrame.checkbtn1.text:SetText("Check Please!")
  myConfigFrame.checkbtn1:SetChecked(false)
end
