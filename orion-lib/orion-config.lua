-- orion-config.lua
-- Alle anpassbaren Werte an einem Ort. Du kannst diese Datei auch lokal definieren:
-- getgenv()._SorinOrionConfig = require(...)  oder direkt ein Table setzen.

local Config = {

  -- Build-/Kanal-Markierung für Feature-Flags im Code: "DEV" | "BETA" | "STABLE"
  CHANNEL = "DEV",

  -- GUI & Intro
  GuiName     = "SorinUI",
  IntroEnabled = true,
  IntroText    = "SorinHub",
  IntroIcon    = "rbxassetid://8834748103", -- kleines Lade-Icon
  WindowIcon   = "rbxassetid://122633020844347", -- SorinLogo in der TopBar (optional)

  -- Basisthema (dunkel, leicht violett angehaucht)
  Theme = {
    Main    = Color3.fromRGB(22, 20, 26),
    Second  = Color3.fromRGB(30, 28, 36),
    Stroke  = Color3.fromRGB(70, 62, 92),
    Divider = Color3.fromRGB(52, 46, 68),
    Text    = Color3.fromRGB(238, 236, 244),
    TextDark= Color3.fromRGB(176, 168, 196),
  },

  -- Akzentfarben – wird für Slider, Toggles etc. genutzt
  Accent = {
    Primary   = Color3.fromRGB(158, 96, 255),  -- Sorin-Lila
    PrimaryHi = Color3.fromRGB(182, 126, 255), -- Hover/Helligkeit
  },

  -- RbxAsset-IDs: Key = kurzer Name; Value = assetid
  Icons = {
    home    = "rbxassetid://133768243848629",
    info    = "rbxassetid://133768243848629",
    visual  = "rbxassetid://133768243848629",
    bypass  = "rbxassetid://133768243848629",
    utility = "rbxassetid://133768243848629",
    close   = "rbxassetid://7072725342",
    minimize= "rbxassetid://7072719338",
    unmin   = "rbxassetid://7072720870",
    dropdown= "rbxassetid://7072706796",
    check   = "rbxassetid://3944680095",
    avatarFrame = "rbxassetid://4031889928",
  },

  -- Konfiguration/Speicher
  SaveConfig = false,           -- true = automatisch pro Spiel-ID speichern
  ConfigFolder = "SorinHub",    -- Ordnername für writefile/isfile
}

return Config

