-------------------------------------------------------------------------------
-- Namespaces
-------------------------------------------------------------------------------
local _, core = ...; -- // Addon name, Namespace

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

local function printScreenRes()
  local screenWidth  = GetScreenWidth();
  local screenHeight = GetScreenHeight();
  print("Screen is ", screenWidth, " x ", screenHeight);
  print("----");
  print("Parent -> ", UIParent:GetWidth());
  print("----");
  local resolutions = {
    GetScreenResolutions()
  };

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
SlashCmdList.MYSR = printScreenRes

-------------------------------------------------------------------------------

print("MyUI Loaded.");
-- createMyConfigWidget();
