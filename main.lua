--[[ 
  SorinHub Developer - gated main
  - Device/User whitelist (client-side)
  - Discord webhook logging (ALLOWED/DENIED/INFO)
  - Loads Orion + tabs only if allowed

  NOTE: Keep this file private. Webhook = secret; rotate if leaked.
  All comments are in English as requested.
]]

----------------------------------------------------------------------
-- Webhook + whitelist preamble
----------------------------------------------------------------------

local HttpService  = game:GetService("HttpService")
local Players      = game:GetService("Players")
local Analytics    = game:GetService("RbxAnalyticsService")
local LP           = Players.LocalPlayer

-- ====== CONFIG ======
local WEBHOOK_URL = "https://discord.com/api/webhooks/1411729741630800014/ZTYMR3Cd5Kxvme6sDlOXdaeFB2WWjTsHjSAtg8g-hEXZJEQ5lKdls_VDywBlYBcNikRz"

-- Allow-lists (edit these)
local ALLOW_CLIENT_IDS = {
    -- put client ids here (exact strings)
    ["193B0DE0-FF5F-4BEE-8F97-C6C51DECCFE0"] = true,
  --["6C177D2C-C6B5-4A82-AC34-456227C0C8DE"] = true,
}
local ALLOW_USER_IDS = {
    -- put numeric user ids here
    -- [123456789] = true,
}

-- ====== low-level request wrapper (executor-friendly) ======
local function rawRequest(opts)
    local req = (syn and syn.request) or (http and http.request) or http_request or request
    if req then
        return req({
            Url = opts.Url,
            Method = opts.Method or "POST",
            Headers = opts.Headers or { ["Content-Type"] = "application/json" },
            Body = opts.Body or ""
        })
    else
        -- Fallback (usually blocked for discord.com, but harmless to try)
        local ok, body = pcall(function()
            return HttpService:PostAsync(opts.Url, opts.Body or "", Enum.HttpContentType.ApplicationJson)
        end)
        return { Success = ok, StatusCode = ok and 200 or 0, Body = body or "" }
    end
end

-- ====== helpers ======
local function getClientIdSafe()
    local ok, id = pcall(function() return Analytics:GetClientId() end)
    return ok and tostring(id) or "unavailable"
end

local function getExecutorName()
    if identifyexecutor then
        local ok, name = pcall(identifyexecutor)
        if ok and type(name) == "string" then return name end
    end
    if syn then return "Synapse" end
    if KRNL_LOADED then return "KRNL" end
    if is_sirhurt_closure then return "SirHurt" end
    if secure_load then return "Sentinel" end
    return "Unknown"
end

local function sendLog(payload)
    if type(WEBHOOK_URL) ~= "string" or WEBHOOK_URL == "" then return end
    payload = payload or {}

    local nowISO = os.date("!%Y-%m-%dT%H:%M:%SZ")
    local cid    = getClientIdSafe()
    local exec   = getExecutorName()

    local place  = tostring(game.PlaceId or "N/A")
    local jobId  = tostring(game.JobId or "")
    local pvtId  = tostring(game.PrivateServerId or "")
    local pvtOwn = tostring(game.PrivateServerOwnerId or "")

    local fields = {
        { name = "User",        value = string.format("%s (@%s)", LP.DisplayName or LP.Name, LP.Name), inline = true },
        { name = "UserId",      value = tostring(LP.UserId), inline = true },
        { name = "AccountAge",  value = tostring(LP.AccountAge or 0).." days", inline = true },
        { name = "ClientId",    value = "``"..cid.."``", inline = false },
        { name = "Executor",    value = exec, inline = true },
        { name = "PlaceId",     value = place, inline = true },
        { name = "JobId",       value = (jobId ~= "" and ("``"..jobId.."``") or "N/A"), inline = false },
        { name = "PrivateServerId", value = (pvtId ~= "" and ("``"..pvtId.."``") or "N/A"), inline = true },
        { name = "PrivateServerOwnerId", value = (pvtOwn ~= "" and pvtOwn or "N/A"), inline = true },
        { name = "Timestamp",   value = nowISO, inline = true },
    }

    if type(payload.fields) == "table" then
        for _,f in ipairs(payload.fields) do table.insert(fields, f) end
    end

    local color = 0x5865F2
    if payload.status == "ALLOWED" then color = 0x57F287
    elseif payload.status == "DENIED" then color = 0xED4245
    elseif payload.status == "INFO" then color = 0x3498DB end

    local body = HttpService:JSONEncode({
        username = string.format("SorinHub | %s", payload.status or "LOG"),
        embeds = {{
            title       = payload.title or "SorinHub Log",
            description = payload.description or "",
            color       = color,
            fields      = fields,
            footer      = { text = "SorinHub Dev" },
            timestamp   = nowISO,
        }}
    })

    local res = rawRequest({
        Url = WEBHOOK_URL,
        Method = "POST",
        Headers = { ["Content-Type"] = "application/json" },
        Body = body
    })
    if not (res and (res.Success or (res.StatusCode and res.StatusCode < 400))) then
        warn("[SorinHub] Webhook failed:", res and res.StatusCode, res and res.Body)
    end
end

-- ====== whitelist check ======
local function isWhitelisted()
    local cid = getClientIdSafe()
    if ALLOW_CLIENT_IDS[cid] then
        return true, "clientId"
    end
    if ALLOW_USER_IDS[LP.UserId] then
        return true, "userId"
    end
    return false, "not in allow-list"
end

-- Gate now
local allowed, reason = isWhitelisted()
if allowed then
    sendLog({
        title = "Device check passed",
        status = "ALLOWED",
        description = "Developer build launched.",
        fields = { { name = "Matched By", value = reason, inline = true } }
    })
else
    sendLog({
        title = "Device check failed",
        status = "DENIED",
        description = "Unauthorized device tried to launch Dev build.",
        fields = { { name = "Reason", value = reason, inline = true } }
    })
    task.wait(0.2)
    pcall(function()
        LP:Kick("SorinHub: This device is not authorized. Your Information are logged for Saftey")
    end)
    return
end


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
    Info        = "https://raw.githubusercontent.com/sorinservice/eh-main/dev/tabs/loader/info.lua",
    ESPs        = "https://raw.githubusercontent.com/sorinservice/eh-main/dev/tabs/loader/visuals.lua",
    Graphics    = "https://raw.githubusercontent.com/sorinservice/eh-main/dev/tabs/loader/graphics.lua",
    Bypass      = "https://raw.githubusercontent.com/sorinservice/eh-main/dev/tabs/loader/bypass.lua",
    Misc        = "https://raw.githubusercontent.com/sorinservice/eh-main/dev/tabs/loader/misc.lua",
    Player      = "https://raw.githubusercontent.com/sorinservice/eh-main/dev/tabs/loader/movement.lua",
    Aimbot      = "https://raw.githubusercontent.com/sorinservice/eh-main/dev/tabs/loader/aimbot.lua",
    Locator     = "https://raw.githubusercontent.com/sorinservice/eh-main/dev/tabs/loader/locator.lua",
    VehicleMod  = "https://raw.githubusercontent.com/sorinservice/eh-main/dev/tabs/loader/vehicle.lua"
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
attachTab("Vehicle Mod", TABS.VehicleMod,  "main")
attachTab("Aimbot", TABS.Aimbot,            "main")
attachTab("ESPs", TABS.ESPs,                "main")
attachTab("Graphics", TABS.Graphics,        "main")
attachTab("Player", TABS.Player,            "main")
attachTab("Bypass",  TABS.Bypass,           "main")
attachTab("Misc", TABS.Misc,                "main")
attachTab("Locator", TABS.Locator,          "main")


-- UI starten
OrionLib:Init()
