-- Orion laden
local OrionLib = loadstring(game:HttpGet("https://raw.githubusercontent.com/sorinservice/orion-lib/main/orion.lua"))()

-- Fenster erstellen
local Window = OrionLib:MakeWindow({
    Name        = "SorinHub | Developer Beta Script",
    IntroText   = "SorinHub Developer Beta",
    IntroIcon   = "rbxassetid://132160391368316",
    SaveConfig  = false,              -- auf true stellen, wenn du Flags speichern willst
    ConfigFolder= "SorinConfig"
})

-- Tabs-Mapping
local TABS = {
    Info    = "https://raw.githubusercontent.com/sorinservice/eh-main/main/tabs/info.lua",
    Visuals = "https://raw.githubusercontent.com/sorinservice/eh-main/main/tabs/visuals.lua",
}

-- Loader-Helfer
local function safeRequire(url)
    local ok, chunk = pcall(function()
        local src = game:HttpGet(url)
        return loadstring(src)
    end)
    if not ok or type(chunk) ~= "function" then
        return nil, "Konnte Modul nicht laden: "..tostring(url)
    end
    local ok2, mod = pcall(chunk)
    if not ok2 then
        return nil, "Fehler beim Ausführen: "..tostring(ok2)
    end
    return mod, nil
end

local function attachTab(name, url)
    local Tab = Window:MakeTab({ Name = name })
    local mod, err = safeRequire(url)
    if not mod then
        Tab:AddParagraph("Fehler", err or "Unbekannter Fehler")
        return
    end
    -- Konvention: jedes Tab-Modul exportiert `function(tab, OrionLib) end`
    local ok, msg = pcall(mod, Tab, OrionLib)
    if not ok then
        Tab:AddParagraph("Fehler", "Tab-Init fehlgeschlagen:\n"..tostring(msg))
    end
end

-- Tabs laden (Reihenfolge = Anzeige-Reihenfolge)
attachTab("Info",    TABS.Info)
-- attachTab("Visuals", TABS.Visuals) -- erst aktivieren, wenn visuals.lua liegt

-- UI starten
OrionLib:Init()
