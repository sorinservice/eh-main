-- Orion laden
local OrionLib = loadstring(game:HttpGet("https://raw.githubusercontent.com/sorinservice/script-libary/main/OrionLibary.lua"))()

-- Fenster erstellen
local Window = OrionLib:MakeWindow({
    Name         = "SorinHub Developer",
    IntroText    = "SorinHub | Developer Script",
    SaveConfig   = true,
    ConfigFolder = "SorinConfig"
})

-- Tabs-Mapping (DEV-Branch)
local TABS = {
    Info        = "https://raw.githubusercontent.com/sorinservice/eh-main/dev/tabs/loader/info.lua",
    ESPs        = "https://raw.githubusercontent.com/sorinservice/eh-main/dev/tabs/loader/visuals.lua",
    Graphics    = "https://raw.githubusercontent.com/sorinservice/eh-main/dev/tabs/loader/graphics.lua",
    Bypass      = "https://raw.githubusercontent.com/sorinservice/eh-main/dev/tabs/loader/bypass.lua",
    Misc        = "https://raw.githubusercontent.com/sorinservice/eh-main/dev/tabs/loader/misc.lua",
    Player      = "https://raw.githubusercontent.com/sorinservice/eh-main/dev/tabs/loader/movement.lua",
    Aimbot      = "https://raw.githubusercontent.com/sorinservice/eh-main/dev/tabs/loader/aimbot.lua",
    Locator     = "https://raw.githubusercontent.com/sorinservice/eh-main/dev/tabs/loader/locator.lua",
    VehicleMod  = "https://raw.githubusercontent.com/sorinservice/eh-main/dev/tabs/loader/vehicle.lua",
    Police      ="https://raw.githubusercontent.com/sorinservice/eh-main/dev/tabs/loader/police.lua"
}

-- Loader-Helfer
local function safeRequire(url)
    -- cache-bust
    local sep = string.find(url, "?", 1, true) and "&" or "?"
    local finalUrl = url .. sep .. "cb=" .. os.time() .. tostring(math.random(1000,9999))

    -- fetch
    local okFetch, body = pcall(function()
        return game:HttpGet(finalUrl)
    end)
    if not okFetch then
        return nil, ("HTTP error on %s\n%s"):format(finalUrl, tostring(body))
    end

    -- sanitize (BOM, zero-width, CRLF, control chars)
    body = body
        :gsub("^\239\187\191", "")        -- UTF-8 BOM am Anfang
        :gsub("\226\128\139", "")         -- ZERO WIDTH NO-BREAK SPACE im Text
        :gsub("[\0-\8\11\12\14-\31]", "") -- sonstige Steuerzeichen
        :gsub("\r\n", "\n")

    -- compile  ➜ WICHTIG: NICHT per pcall(loadstring,...)
    local fn, lerr = loadstring(body)
    if not fn then
        local preview = body:sub(1, 220)
        return nil, ("loadstring failed for %s\n%s\n\nPreview:\n%s")
            :format(finalUrl, tostring(lerr), preview)
    end

    -- run
    local okRun, modOrErr = pcall(fn)
    if not okRun then
        return nil, ("module execution error for %s\n%s"):format(finalUrl, tostring(modOrErr))
    end
    if type(modOrErr) ~= "function" then
        return nil, ("module did not return a function: %s"):format(finalUrl)
    end
    return modOrErr, nil
end



-- WICHTIG: iconKey wird jetzt angenommen und an MakeTab übergeben
local function attachTab(name, url, iconKey)
    local Tab = Window:MakeTab({ Name = name, Icon = iconKey })
    local mod, err = safeRequire(url)
    if not mod then
        Tab:AddParagraph("Fehler", "Loader:\n" .. tostring(err))
        return
    end
    local ok, msg = pcall(mod, Tab, OrionLib)
    if not ok then
        Tab:AddParagraph("Fehler", "Tab-Init fehlgeschlagen:\n" .. tostring(msg))
    end
end


-- Tabs laden (mit Icon-Keys, die in deiner Icon-Map der orion.lua gemappt werden)
attachTab("Info",    TABS.Info,             "info")
attachTab("Vehicle Mod", TABS.VehicleMod,   "main")
attachTab("Aimbot", TABS.Aimbot,            "main")
attachTab("ESPs", TABS.ESPs,                "main")
attachTab("Graphics", TABS.Graphics,        "main")
attachTab("Player", TABS.Player,            "main")
attachTab("Police", TABS.Player,            "main")
attachTab("Bypass",  TABS.Bypass,           "main")
attachTab("Misc", TABS.Misc,                "main")
attachTab("Locator", TABS.Locator,          "main")


-- UI starten
OrionLib:Init()
