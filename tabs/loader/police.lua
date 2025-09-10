-- tabs/police.lua
return function(tab, OrionLib)
    -- Passe BASE an dein Repo an (analog zum Vehicle-Loader):
    -- /tabs/functions/police/*
    local BASE = "https://raw.githubusercontent.com/sorinservice/eh-main/refs/heads/dev/tabs/functions/police/"

    local function httpget(url)
        local ok, res = pcall(function() return game:HttpGet(url .. "?cb=" .. tostring(os.clock())) end)
        if ok and type(res)=="string" and #res>0 then return res end
        local ok2, res2 = pcall(function() return game:HttpGet(url) end)
        if ok2 and type(res2)=="string" and #res2>0 then return res2 end
        return nil
    end

    local function fetch(file)
        local src = httpget(BASE .. file)
        if not src then warn("[PoliceLoader] HttpGet failed: " .. file); return nil end
        local chunk, err = loadstring(src, "@police/"..file)
        if not chunk then warn("[PoliceLoader] loadstring error in "..file..": "..tostring(err)); return nil end
        return chunk
    end

    -- 1) common → liefert SV (shared helpers/state)
    local commonChunk = fetch("common.lua")
    if not commonChunk then return end
    local okCF, commonFactory = pcall(commonChunk)
    if not okCF or type(commonFactory)~="function" then
        warn("[PoliceLoader] common.lua didn't return a function"); return
    end
    local okSV, SV = pcall(commonFactory, tab, OrionLib)
    if not okSV or type(SV)~="table" then
        warn("[PoliceLoader] common.lua factory failed: "..tostring(SV)); return
    end

    -- 2) Funktionen des Police-Tabs laden
    local modules = {
        "radarfalle.lua",
        "anti-taser.lua"
    }

    for _,file in ipairs(modules) do
        local chunk = fetch(file)
        if chunk then
            local okF, factory = pcall(chunk)
            if okF and type(factory)=="function" then
                local okRun, err = pcall(factory, SV, tab, OrionLib)
                if not okRun then
                    warn("[PoliceLoader] run("..file..") error: "..tostring(err))
                end
            else
                warn("[PoliceLoader] "..file.." didn't return a function")
            end
        end
    end
end
