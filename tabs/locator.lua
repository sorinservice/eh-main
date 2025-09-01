-- tabs/locator.lua
-- SorinHub: Spawn/Destination Inspector & Bookmarks
-- - Scannt workspace nach SpawnLocation-Instanzen
-- - Listet sie in Dropdowns
-- - Kopiert CFrame / Position in die Zwischenablage (oder print, falls nicht möglich)
-- - Bookmarks: eigene Ziele speichern/löschen (persistiert)

return function(tab, OrionLib)
    ----------------------------------------------------------------
    -- Services
    ----------------------------------------------------------------
    local HttpService = game:GetService("HttpService")
    local Workspace   = game:GetService("Workspace")
    local Players     = game:GetService("Players")

    local SAVE_FOLDER = OrionLib.Folder or "SorinConfig"
    local SAVE_FILE   = SAVE_FOLDER .. "/spawn_inspector.json"

    ----------------------------------------------------------------
    -- Persistence helpers
    ----------------------------------------------------------------
    local function read_json(path)
        local ok, res = pcall(function()
            if isfile and isfile(path) then
                return HttpService:JSONDecode(readfile(path))
            end
        end)
        return ok and res or nil
    end
    local function write_json(path, tbl)
        pcall(function()
            if makefolder and not isfolder(SAVE_FOLDER) then makefolder(SAVE_FOLDER) end
            if writefile then writefile(path, HttpService:JSONEncode(tbl)) end
        end)
    end

    ----------------------------------------------------------------
    -- State
    ----------------------------------------------------------------
    local STATE = {
        Scan = {               -- aus workspace gefunden
            items = {},        -- { {id=1,name="SpawnLocation", path="workspace.Model.SpawnLocation", cfstr="CFrame.new(...)", v3str="Vector3.new(...)"}, ... }
            names = {},        -- reiner Namen-Array fürs Dropdown
            byName = {},       -- map name->item
            selected = nil,    -- aktuell im Dropdown gewählt (Name)
        },
        Bookmarks = {          -- eigene Ziele
            items = {},        -- map alias -> { x=, y=, z= }  (optional rx/ry/rz später)
            names = {},        -- alias-Liste fürs Dropdown
            selected = nil     -- aktuell im Dropdown gewählt (Alias)
        }
    }

    -- Lade gespeicherte Bookmarks & evtl. letzte Scan-Ergebnisse
    do
        local saved = read_json(SAVE_FILE) or {}
        STATE.Bookmarks.items = saved.bookmarks or {}
        -- Namenliste initialisieren
        STATE.Bookmarks.names = {}
        for alias,_ in pairs(STATE.Bookmarks.items) do table.insert(STATE.Bookmarks.names, alias) end
        table.sort(STATE.Bookmarks.names)
        -- (Optional) letzten Scan wiederherstellen
        if saved.lastScan and saved.lastScan.items then
            STATE.Scan.items = saved.lastScan.items
            STATE.Scan.names = {}
            STATE.Scan.byName = {}
            for _,it in ipairs(STATE.Scan.items) do
                table.insert(STATE.Scan.names, it.name)
                STATE.Scan.byName[it.name] = it
            end
        end
    end

    local function save_all()
        write_json(SAVE_FILE, {
            bookmarks = STATE.Bookmarks.items,
            lastScan  = { items = STATE.Scan.items }
        })
    end

    ----------------------------------------------------------------
    -- Utils
    ----------------------------------------------------------------
    local function cf_to_strings(cf)
        local p = cf.Position
        -- kurze, saubere Kopiervarianten
        local v3 = string.format("Vector3.new(%.2f, %.2f, %.2f)", p.X, p.Y, p.Z)
        local c3 = string.format("CFrame.new(%.2f, %.2f, %.2f)", p.X, p.Y, p.Z)
        return c3, v3
    end

    local function full_path(inst)
        local path = {}
        local cur = inst
        while cur and cur ~= game do
            table.insert(path, 1, cur.Name)
            cur = cur.Parent
        end
        return table.concat(path, ".")
    end

    local function set_clipboard(text)
        if setclipboard then
            setclipboard(text)
            return true
        end
        return false
    end

    local function notify(title, msg, t)
        OrionLib:MakeNotification({ Name = title, Content = msg, Time = t or 3 })
    end

    ----------------------------------------------------------------
    -- Scanner
    ----------------------------------------------------------------
    local function scan_spawns()
        local list, names, map = {}, {}, {}
        local count = 0
        for _, inst in ipairs(Workspace:GetDescendants()) do
            if inst:IsA("SpawnLocation") then
                count += 1
                local cf = inst.CFrame
                local cfstr, v3str = cf_to_strings(cf)
                local name = string.format("#%02d %s", count, inst.Name)
                local item = {
                    id    = count,
                    name  = name,
                    path  = full_path(inst),
                    cfstr = cfstr,
                    v3str = v3str,
                }
                table.insert(list, item)
                table.insert(names, name)
                map[name] = item
            end
        end

        STATE.Scan.items  = list
        STATE.Scan.names  = names
        STATE.Scan.byName = map
        STATE.Scan.selected = names[1]

        save_all()
        return count
    end

    ----------------------------------------------------------------
    -- UI
    ----------------------------------------------------------------
    local secScan  = tab:AddSection({ Name = "Workspace Spawns" })
    local secBook  = tab:AddSection({ Name = "Bookmarks" })
    local secTools = tab:AddSection({ Name = "Tools" })

    -- Scan Button + Counter
    secScan:AddButton({
        Name = "Scan SpawnLocation",
        Callback = function()
            local n = scan_spawns()
            notify("Inspector", ("Gefunden: %d SpawnLocation(s)."):format(n))
        end
    })

    local lblCount = secScan:AddLabel(("Gefunden: %d"):format(#STATE.Scan.items))

    -- Dropdown der Scan-Ergebnisse
    local ddScan = secScan:AddDropdown({
        Name = "Spawn auswählen",
        Default = STATE.Scan.selected,
        Options = STATE.Scan.names,
        Callback = function(v) STATE.Scan.selected = v end
    })

    -- Copy Buttons
    secScan:AddButton({
        Name = "Copy CFrame (CFrame.new(x,y,z))",
        Callback = function()
            local it = STATE.Scan.byName[STATE.Scan.selected or ""]
            if not it then notify("Inspector","Bitte erst scannen / auswählen."); return end
            if set_clipboard(it.cfstr) then
                notify("Copied", "CFrame in Clipboard.")
            else
                print("[Spawn CFrame]", it.name, it.cfstr)
                notify("Copied", "Clipboard nicht verfügbar – in Konsole gedruckt.")
            end
        end
    })
    secScan:AddButton({
        Name = "Copy Position (Vector3.new(x,y,z))",
        Callback = function()
            local it = STATE.Scan.byName[STATE.Scan.selected or ""]
            if not it then notify("Inspector","Bitte erst scannen / auswählen."); return end
            if set_clipboard(it.v3str) then
                notify("Copied", "Vector3 in Clipboard.")
            else
                print("[Spawn Position]", it.name, it.v3str)
                notify("Copied", "Clipboard nicht verfügbar – in Konsole gedruckt.")
            end
        end
    })

    -- Bookmark: hinzufügen (Alias via TextBox + Quelle wählbar: Auswahl/CurrentPos)
    local lastAlias = ""
    local tbAlias = secBook:AddTextbox({
        Name = "Neuer Bookmark-Name",
        Default = "",
        TextDisappear = false,
        Callback = function(txt) lastAlias = txt end
    })

    secBook:AddButton({
        Name = "Bookmark aus Auswahl hinzufügen",
        Callback = function()
            if (lastAlias or "") == "" then notify("Bookmarks","Bitte einen Namen eingeben."); return end
            local it = STATE.Scan.byName[STATE.Scan.selected or ""]
            if not it then notify("Bookmarks","Keine Auswahl vorhanden."); return end

            -- Parse aus v3str (einfachster Weg)
            local x,y,z = it.v3str:match("Vector3%.new%(([-%d%.]+), ([-%d%.]+), ([-%d%.]+)%)")
            if not x then notify("Bookmarks","Konnte Position nicht lesen."); return end
            STATE.Bookmarks.items[lastAlias] = { x = tonumber(x), y = tonumber(y), z = tonumber(z) }
            -- UI Namen aktualisieren
            table.insert(STATE.Bookmarks.names, lastAlias)
            table.sort(STATE.Bookmarks.names)
            ddBookmarks:Refresh(STATE.Bookmarks.names, true)
            STATE.Bookmarks.selected = lastAlias
            save_all()
            notify("Bookmarks", "Gespeichert als \""..lastAlias.."\".")
        end
    })

    secBook:AddButton({
        Name = "Bookmark aus aktueller Spielerposition",
        Callback = function()
            if (lastAlias or "") == "" then notify("Bookmarks","Bitte einen Namen eingeben."); return end
            local hrp = Players.LocalPlayer.Character and Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if not hrp then notify("Bookmarks","Keine Spielerposition verfügbar."); return end
            local p = hrp.Position
            STATE.Bookmarks.items[lastAlias] = { x = p.X, y = p.Y, z = p.Z }
            table.insert(STATE.Bookmarks.names, lastAlias)
            table.sort(STATE.Bookmarks.names)
            ddBookmarks:Refresh(STATE.Bookmarks.names, true)
            STATE.Bookmarks.selected = lastAlias
            save_all()
            notify("Bookmarks", "Gespeichert aus Spielerposition.")
        end
    })

    -- Dropdown + Copy/Remove
    local ddBookmarks = secBook:AddDropdown({
        Name = "Bookmark auswählen",
        Default = STATE.Bookmarks.selected,
        Options = STATE.Bookmarks.names,
        Callback = function(v) STATE.Bookmarks.selected = v end
    })

    secBook:AddButton({
        Name = "Copy Bookmark (CFrame)",
        Callback = function()
            local alias = STATE.Bookmarks.selected
            local data  = alias and STATE.Bookmarks.items[alias]
            if not data then notify("Bookmarks","Bitte Bookmark wählen."); return end
            local cfstr = string.format("CFrame.new(%.2f, %.2f, %.2f)", data.x, data.y, data.z)
            if set_clipboard(cfstr) then
                notify("Copied", "Bookmark-CFrame kopiert.")
            else
                print("[Bookmark CFrame]", alias, cfstr)
                notify("Copied", "Clipboard nicht verfügbar – in Konsole gedruckt.")
            end
        end
    })

    secBook:AddButton({
        Name = "Bookmark löschen",
        Callback = function()
            local alias = STATE.Bookmarks.selected
            if not alias then notify("Bookmarks","Kein Bookmark ausgewählt."); return end
            STATE.Bookmarks.items[alias] = nil
            -- Namenliste neu bauen
            STATE.Bookmarks.names = {}
            for k,_ in pairs(STATE.Bookmarks.items) do table.insert(STATE.Bookmarks.names, k) end
            table.sort(STATE.Bookmarks.names)
            ddBookmarks:Refresh(STATE.Bookmarks.names, true)
            STATE.Bookmarks.selected = STATE.Bookmarks.names[1]
            save_all()
            notify("Bookmarks","Gelöscht.")
        end
    })

    -- Hilfstools
    secTools:AddButton({
        Name = "Rescan & UI aktualisieren",
        Callback = function()
            local n = scan_spawns()
            lblCount:Set(("Gefunden: %d"):format(n))
            ddScan:Refresh(STATE.Scan.names, true)
            notify("Inspector", "Rescan fertig.")
        end
    })

    -- Initiale UI-Werte setzen
    lblCount:Set(("Gefunden: %d"):format(#STATE.Scan.items))
    ddScan:Refresh(STATE.Scan.names, true)
    ddBookmarks:Refresh(STATE.Bookmarks.names, true)
end
