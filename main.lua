-- Orion laden
local OrionLib = loadstring(game:HttpGet("https://raw.githubusercontent.com/sorinservice/orion-lib/refs/heads/main/orion.lua"))()

-- Fenster erstellen
local Window = OrionLib:MakeWindow({
    SaveConfig   = true,
    ConfigFolder = "SorinConfig"
})

-- Tabs-Mapping (DEV-Branch)
local TABS = {
    Info     = "https://raw.githubusercontent.com/sorinservice/eh-main/main/tabs/info.lua",
    Aimbot   = "https://raw.githubusercontent.com/sorinservice/eh-main/main/tabs/aimbot.lua",
    ESPs     = "https://raw.githubusercontent.com/sorinservice/eh-main/main/tabs/visuals.lua",
    Bypass   = "https://raw.githubusercontent.com/sorinservice/eh-main/main/tabs/bypass.lua",
    Graphics = "https://raw.githubusercontent.com/sorinservice/eh-main/main/tabs/graphics.lua",
    Misc     = "https://raw.githubusercontent.com/sorinservice/eh-main/main/tabs/misc.lua",
}

-- Loader-Helfer
local function safeRequire(url)
    local ok, loaderOrErr = pcall(function()
        local src = game:HttpGet(url)
        return loadstring(src)
    end)
    if not ok or type(loaderOrErr) ~= "function" then
        return nil, "Konnte Modul nicht laden: " .. tostring(url)
    end
    local ok2, modOrErr = pcall(loaderOrErr)
    if not ok2 then
        return nil, "Fehler beim Ausführen: " .. tostring(modOrErr)
    end
    return modOrErr, nil
end

-- WICHTIG: iconKey wird jetzt angenommen und an MakeTab übergeben
local function attachTab(name, url, iconKey)
    local Tab = Window:MakeTab({ Name = name, Icon = iconKey })
    local mod, err = safeRequire(url)
    if not mod then
        Tab:AddParagraph("Fehler", err or "Unbekannter Fehler")
        return
    end
    local ok, msg = pcall(mod, Tab, OrionLib)
    if not ok then
        Tab:AddParagraph("Fehler", "Tab-Init fehlgeschlagen:\n" .. tostring(msg))
    end
end

-- Tabs laden (mit Icon-Keys, die in deiner Icon-Map der orion.lua gemappt werden)
attachTab("Info",      TABS.Info,     "info")
attachTab("Aimbot",    TABS.Aimbot,   "main")
attachTab("ESPs",      TABS.ESPs,     "main")
attachTab("Graphics",  TABS.Graphics, "main")
attachTab("Bypass",    TABS.Bypass,   "main")
attachTab("Misc",      TABS.Misc,     "main")

-- UI starten
OrionLib:Init()
