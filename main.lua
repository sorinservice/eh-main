-- ==== SorinHub Dev: Device Lock (ClientId whitelist) ===================
local Players = game:GetService("Players")
local Analytics = game:GetService("RbxAnalyticsService")

-- 1) Deine freigegebenen Geräte-IDs hier eintragen:
local ALLOWED = {
    ["6C177D2C-C6B5-4A82-AC34-456227C0C8DE"] = true,
    -- weitere ...
}

-- Optional: Dev-Bypass, z.B. für dich bei Tests (per getgenv() setzen)
local DEV_BYPASS = (getgenv and getgenv().SorinDevBypass) == true

local function getClientIdSafe()
    local ok, id = pcall(function() return Analytics:GetClientId() end)
    return ok and tostring(id) or nil
end

local function isWhitelisted()
    if DEV_BYPASS then return true, "dev-bypass" end
    local id = getClientIdSafe()
    if not id then return false, "no-id" end
    return ALLOWED[id] == true, id
end

local ok, detail = isWhitelisted()
if not ok then
    warn(("[SorinHub] Access denied: %s"):format(tostring(detail)))
    -- Harte Reaktion: Kicken und sofort beenden
    pcall(function()
        Players.LocalPlayer:Kick("SorinHub Developer: This device is not authorized.")
    end)
    return
end

-- (Optional) Light Anti-Tamper: später nochmal prüfen und beenden, falls „entsichert“
task.delay(5, function()
    local ok2 = select(1, isWhitelisted())
    if not ok2 then
        pcall(function()
            Players.LocalPlayer:Kick("SorinHub Developer: Device check failed.")
        end)
    end
end)
-- ======================================================================


-- Orion laden
local OrionLib = loadstring(game:HttpGet("https://raw.githubusercontent.com/sorinservice/orion-lib/refs/heads/main/orion.lua"))()

-- Fenster erstellen
local Window = OrionLib:MakeWindow({
    Name         = "SorinHub Developer",
    IntroText    = "SorinHub | Developer Script",
    SaveConfig   = true,
    ConfigFolder = "SorinConfig"
})

-- Tabs-Mapping (DEV-Branch)
local TABS = {
    Info    = "https://raw.githubusercontent.com/sorinservice/eh-main/dev/tabs/info.lua",
    ESPs = "https://raw.githubusercontent.com/sorinservice/eh-main/dev/tabs/visuals.lua",
    Graphics = "https://raw.githubusercontent.com/sorinservice/eh-main/heads/dev/tabs/graphics.lua",
    Bypass  = "https://raw.githubusercontent.com/sorinservice/eh-main/dev/tabs/bypass.lua",
    Misc = "https://raw.githubusercontent.com/sorinservice/eh-main/dev/tabs/misc.lua"
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
attachTab("Info",    TABS.Info,      "info")
attachTab("ESPs", TABS.ESPs,         "main")
attachTab("Graphics", TABS.Graphics, "main")
attachTab("Bypass",  TABS.Bypass,    "main")
attachTab("Misc", TABS.Misc,         "main")

-- UI starten
OrionLib:Init()
