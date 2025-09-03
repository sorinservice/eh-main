-- tabs/vehicle.lua
return function(tab, OrionLib)
    -- Minimaler Loader: lädt Module aus /tabs/vehicle/* via loadstring
    local BASE = "https://raw.githubusercontent.com/sorinservice/eh-main/dev/tabs/vehicle/"

    local function fetch(fn)
        local ok, src = pcall(function() return game:HttpGet(BASE .. fn, true) end)
        if not ok then warn("[VehicleLoader] HttpGet fail for " .. fn .. ": " .. tostring(src)) return nil end
        local chunk, err = loadstring(src)
        if not chunk then warn("[VehicleLoader] loadstring fail for " .. fn .. ": " .. tostring(err)) return nil end
        return chunk
    end

    -- 1) common zuerst laden -> liefert das gemeinsame SV (Shared Values / Helpers)
    local commonChunk = fetch("common.lua"); if not commonChunk then return end
    local SV = commonChunk(tab, OrionLib)  -- common.lua gibt ein Table zurück

    -- 2) Feature-Module (Reihenfolge egal, außer plates evtl. vor Actions)
    local modules = {
        "plates.lua",            -- Kennzeichen + Auto-Apply + UI
        "to_vehicle.lua",        -- Teleport & einsteigen
        "bring_to_vehicle.lua",  -- Spawn vor dir & einsteigen
        "powerdrive.lua",        -- Boden-Boost (keine Velocity-Writes)
        "boost.lua",             -- kurzer Boost-Impuls
        "jump.lua",              -- vertikaler Sprung
        -- "carfly.lua",         -- experimentell (optional; derzeit aus)
    }

    for _,file in ipairs(modules) do
        local chunk = fetch(file)
        if chunk then
            local ok, err = pcall(function() chunk(SV, tab, OrionLib) end)
            if not ok then
                warn("[VehicleLoader] module error " .. file .. ": " .. tostring(err))
            end
        end
    end
end
