-------------------------------------------------------------------------------
-- Namespaces
-------------------------------------------------------------------------------
local _, core = ...; -- // Addon name, Namespace
-------------------------------------------------------------------------------
local baseFrame;
local myBackdropInfo = {
  bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
  tile = true,
  tileEdge = true,
  tileSize = 8,
  -- edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  -- edgeSize = 8,
  -- insets = { left = 1, right = 1, top = 1, bottom = 1 },
};

-------------------------------------------------------------------------------
-- Misc Demo functions
-------------------------------------------------------------------------------
local function showMessage(msg)
  message(msg);
end

local function MyGreetingsHandler(name)

  local nameProvided = string.len(name) > 0
  local greetingMessage = "Hello "

  if (nameProvided) then
    greetingMessage = greetingMessage .. name .. "!?!"
  else
    greetingMessage = greetingMessage .. UnitName("player") .. "!"
  end
  showMessage(greetingMessage)
end

local function printDebugInfo()
  local screenWidth  = GetScreenWidth();
  local screenHeight = GetScreenHeight();
  print("Screen is ", screenWidth, " x ", screenHeight);
  print("----");
  print("Parent -> ", UIParent:GetWidth());
  print("----");
  print("Base -> ", MyBaseFrame:GetWidth());
  print("----");
end

local function AddBaseFrame()
  -- https://wowpedia.fandom.com/wiki/API_CreateFrame

  baseFrame = CreateFrame("Frame", "MyBaseFrame", UIParent, "BackdropTemplate");
  baseFrame:SetWidth(0); -- // placeholder
  baseFrame:SetHeight(8);  -- // placeholder
  baseFrame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT");
  baseFrame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT");
  baseFrame:SetBackdrop(myBackdropInfo);
  baseFrame:SetFrameStrata("BACKGROUND");
  baseFrame:SetBackdropColor(0.25, 0.0, 0.25, 0.75);
end

-------------------------------------------------------------------------------
-- Custom Slash Commands
-------------------------------------------------------------------------------
SLASH_MYGR1 = "/myui_greet"
SLASH_MYGR2 = "/gr"
SLASH_MYRL1 = "/rl"
SLASH_MYSR1 = "/sr"

SlashCmdList.MYGR = MyGreetingsHandler
SlashCmdList.MYRL = ReloadUI
SlashCmdList.MYSR = printDebugInfo

-------------------------------------------------------------------------------

print("MyUI Loaded.");
AddBaseFrame();
-- createMyConfigWidget();
