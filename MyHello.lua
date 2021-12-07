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

local myTileInfo = {
  bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
  tile = true,
  tileEdge = true,
  tileSize = 8,
  -- edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  -- edgeSize = 8,
  -- insets = { left = 1, right = 1, top = 1, bottom = 1 },
};

local tiles_wide = 5;
local tiles_height = 10;
local gap = 0;
local tWidth;
local tHeight;
local tiles;

-------------------------------------------------------------------------------
-- Misc Demo functions
-------------------------------------------------------------------------------
local function showMessage(msg)
  message(msg);
end

local function MyGreetingsHandler(name)
  -- Kinda like Hello World!
  local nameProvided = string.len(name) > 0;
  local greetingMessage = "Hello ";
  if (nameProvided) then
    greetingMessage = greetingMessage .. name .. "!?!";
  else
    greetingMessage = greetingMessage .. UnitName("player") .. "!";
  end
  showMessage(greetingMessage);
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

-------------------------------------------------------------------------------
-- Create Tiles and Backdrops
-------------------------------------------------------------------------------
local function calcTileSizes()
    tWidth  = UIParent:GetWidth()  / tiles_wide;
    tHeight = UIParent:GetHeight() / tiles_height;
end

local function AddBaseFrame()
  -- https://wowpedia.fandom.com/wiki/API_CreateFrame
  if baseFrame == nil then
    baseFrame = CreateFrame("Frame", "MyBaseFrame",
        UIParent, "BackdropTemplate");
    baseFrame:SetWidth(0);    -- // placeholder
    baseFrame:SetHeight(6);  -- // placeholder
    baseFrame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT");
    baseFrame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT");
    baseFrame:SetBackdrop(myBackdropInfo);
    baseFrame:SetFrameStrata("BACKGROUND");
    baseFrame:SetBackdropColor(0.25, 0.0, 0.25, 0.75);
  else
    print("already exists!");
  end
end

local function createTile(col, row, cspan, rspan, alpha)
  local tile = CreateFrame("Frame", "Tile", UIParent, "BackdropTemplate");
  tile:SetWidth((tWidth * cspan) - gap);
  tile:SetHeight((tHeight * rspan) - gap);
  local px = floor(col * tWidth);
  local py = floor(row * tHeight);
  -- y coordinate relative to top left has to be negative
  tile:SetPoint("TOPLEFT", UIParent, "TOPLEFT", px, -py);
  tile:SetBackdrop(myTileInfo);
  tile:SetFrameStrata("BACKGROUND");
  tile:SetBackdropColor(0.0, 0.0, 0.0, alpha);
  print("[", col, ",", row, "] ", px, ", ", py);
end

local function makeTiles()
-- Col 0
createTile(0, 0, 1, 8, 0.2);

-- Col 4
createTile(4, 0,  1, 8, 0.2);

-- Tray
createTile(0, 8,  5, 2, 0.5);
-- createTile(1.825, 7.35,  1.4, 0.645, 0.7);
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
calcTileSizes();
makeTiles();
AddBaseFrame();
-- createMyConfigWidget();
