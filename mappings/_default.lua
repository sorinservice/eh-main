local function loadMappingFor(placeId)
    -- 1) try exact place
    local urlPlace = BASE_MAP_URL .. tostring(placeId) .. ".lua"
    local ok1, src1 = pcall(httpLoad, urlPlace)
    if ok1 and type(src1)=="string" and #src1>0 then
        local f = loadstring(src1)
        local okf, tbl = pcall(f)
        if okf and type(tbl)=="table" then
            tbl.__isDefault = false
            return tbl
        end
    end
    -- 2) fallback default
    local urlDef = BASE_MAP_URL .. DEFAULT_MAP
    local ok2, src2 = pcall(httpLoad, urlDef)
    if ok2 and type(src2)=="string" and #src2>0 then
        local f = loadstring(src2)
        local okf, tbl = pcall(f)
        if okf and type(tbl)=="table" then
            tbl.__isDefault = true
            return tbl
        end
    end
    -- 3) ultimate fallback
    return { byId={}, byName={}, defaultUnknown="Unknown Item", __isDefault = true }
end

