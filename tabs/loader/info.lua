-- tabs/loader/info.lua
-- Lädt nur das Info-Feature aus tabs/functions/info/info.lua

return function(tab, OrionLib)
    local function notify(t, m, s)
        pcall(function() OrionLib:MakeNotification({Name=t, Content=m, Time=s or 3}) end)
    end

    local BASE = "https://raw.githubusercontent.com/sorinservice/eh-main/dev/tabs/functions/info/"

    local function fetch(file)
        local url = BASE .. file .. "?cb=" .. tostring(math.floor(os.clock()*1000)) -- simpler Cache-Buster
        local ok, src = pcall(function() return game:HttpGet(url) end)
        if not ok then
            notify("Info Loader", "HTTP-Fehler bei "..file, 4)
            return nil
        end
        local ok2, chunk = pcall(loadstring, src, "@info/"..file)
        if not ok2 or type(chunk) ~= "function" then
            notify("Info Loader", "loadstring fehlgeschlagen: "..file, 4)
            return nil
        end
        local ok3, ret = pcall(chunk)
        if not ok3 then
            notify("Info Loader", "Ausführung fehlgeschlagen: "..file, 4)
            return nil
        end
        return ret
    end

    local init = fetch("info.lua")
    if type(init) == "function" then
        local ok, err = pcall(init, tab, OrionLib, {}) -- {} = optional Common (nicht benötigt)
        if not ok then notify("Info Loader", "Fehler in info.lua: "..tostring(err), 5) end
    else
        notify("Info Loader", "Konnte info.lua nicht laden.", 4)
    end
end
