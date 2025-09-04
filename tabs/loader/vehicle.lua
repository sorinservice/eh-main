-- tabs/vehicle.lua
return function(tab, OrionLib)
    local BASE = "https://raw.githubusercontent.com/sorinservice/eh-main/dev/tabs/vehicle/"

    local function httpget(url)
        -- robust: erst mit ,true (manche Umgebungen), sonst ohne
        local ok, res = pcall(function() return game:HttpGet(url, true) end)
        if ok and type(res) == "string" and #res > 0 then return res end
        local ok2, res2 = pcall(function() return game:HttpGet(url) end)
        if ok2 and type(res2) == "string" and #res2 > 0 then return res2 end
        return nil
    end

    local function fetch(fn)
        local src = httpget(BASE .. fn)
        if not src then
            warn("[VehicleLoader] HttpGet failed: " .. fn)
            return nil
        end
        local chunk, err = loadstring(src)
        if not chunk then
            warn("[VehicleLoader] loadstring error in " .. fn .. ": " .. tostring(err))
            return nil
        end
        return chunk
    end

    -- 1) common laden → liefert SV (shared values / helpers)
    local commonChunk = fetch("common.lua")
    if not commonChunk then return end
    local okCF, commonFactory = pcall(commonChunk)
    if not okCF or type(commonFactory) ~= "function" then
        warn("[VehicleLoader] common.lua didn't return a function")
        return
    end
    local okSV, SV = pcall(commonFactory, tab, OrionLib)
    if not okSV or type(SV) ~= "table" then
        warn("[VehicleLoader] common.lua factory failed: " .. tostring(SV))
        return
    end

    -- 2) Module-Liste
    local modules = {
        "to_vehicle.lua",
        "bring_to_vehicle.lua",
        "plates.lua",
        "powerdrive.lua",
        "boost.lua",
        "jump.lua",
        "carfly.lua", -- aktuell nur Label/Stub
    }

    for _,file in ipairs(modules) do
        local chunk = fetch(file)
        if chunk then
            local okF, factory = pcall(chunk)
            if okF and type(factory) == "function" then
                local okR, errR = pcall(factory, SV, tab, OrionLib)
                if not okR then
                    warn("[VehicleLoader] run("..file..") error: " .. tostring(errR))
                end
            else
                warn("[VehicleLoader] " .. file .. " didn't return a function")
            end
        end
    end
end
