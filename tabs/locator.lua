-- tabs/locator.lua
-- SorinHub: Spawn Inspector + Bookmarks + Dynamic Highlight

return function(tab, OrionLib)
    print("Locator | Dev Only succsess")
    local HttpService = game:GetService("HttpService")
    local Workspace   = game:GetService("Workspace")
    local Players     = game:GetService("Players")
    local RunService  = game:GetService("RunService")

    local LP          = Players.LocalPlayer
    local SAVE_FOLDER = OrionLib.Folder or "SorinConfig"
    local SAVE_FILE   = SAVE_FOLDER .. "/spawn_inspector.json"

    -- ---------------------- persistence ----------------------
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
    local function set_clip(text)
        if setclipboard then setclipboard(text); return true end
        return false
    end
    local function cf_to_strings(cf)
        local p = cf.Position
        return string.format("CFrame.new(%.2f, %.2f, %.2f)", p.X, p.Y, p.Z),
               string.format("Vector3.new(%.2f, %.2f, %.2f)", p.X, p.Y, p.Z)
    end
    local function path_of(inst)
        local t, cur = {}, inst
        while cur and cur ~= game do table.insert(t, 1, cur.Name); cur = cur.Parent end
        return table.concat(t, ".")
    end
    local function notify(t, m, secs) OrionLib:MakeNotification({Name=t, Content=m, Time=secs or 3}) end

    -- ---------------------- state ----------------------
    local STATE = {
        Scan = { items={}, names={}, byName={}, selected=nil },
        Bookmarks = { items={}, names={}, selected=nil },
        Highlighter = {
            Enabled = false,
            MaxDistance = 500,
            -- runtime:
            GuiFolder = nil,  -- ScreenGui container
            Pool = {},        -- key = Instance, value = BillboardGui
            Conn = nil,
        }
    }

    -- load bookmarks & last scan
    do
        local saved = read_json(SAVE_FILE) or {}
        STATE.Bookmarks.items = saved.bookmarks or {}
        for alias,_ in pairs(STATE.Bookmarks.items) do table.insert(STATE.Bookmarks.names, alias) end
        table.sort(STATE.Bookmarks.names)

        if saved.lastScan and saved.lastScan.items then
            STATE.Scan.items = saved.lastScan.items
            for _,it in ipairs(STATE.Scan.items) do
                STATE.Scan.names[#STATE.Scan.names+1] = it.name
                STATE.Scan.byName[it.name] = it
            end
            STATE.Scan.selected = STATE.Scan.names[1]
        end
    end
    local function save_all()
        write_json(SAVE_FILE, {
            bookmarks = STATE.Bookmarks.items,
            lastScan  = { items = STATE.Scan.items }
        })
    end

    -- ---------------------- scanning ----------------------
    local function scan_spawns()
        local list, names, map = {}, {}, {}
        local n = 0
        for _, inst in ipairs(Workspace:GetDescendants()) do
            if inst:IsA("SpawnLocation") then
                n += 1
                local cfstr, v3str = cf_to_strings(inst.CFrame)
                local name = string.format("#%02d %s", n, inst.Name)
                local item = {
                    id=n, name=name, path=path_of(inst), cfstr=cfstr, v3str=v3str,
                }
                list[#list+1] = item
                names[#names+1] = name
                map[name] = item
            end
        end
        STATE.Scan.items, STATE.Scan.names, STATE.Scan.byName = list, names, map
        STATE.Scan.selected = names[1]
        save_all()
        return n
    end

    -- ---------------------- highlighter ----------------------
    local function ensure_gui_folder()
        if STATE.Highlighter.GuiFolder then return end
        local g = Instance.new("ScreenGui")
        g.Name = "Sorin_SpawnHighlighter"
        g.ResetOnSpawn = false
        g.IgnoreGuiInset = true
        g.Parent = game:GetService("CoreGui")
        STATE.Highlighter.GuiFolder = g
    end
    local function alloc_billboard(forPart, text)
        ensure_gui_folder()
        local bb = Instance.new("BillboardGui")
        bb.Name = "SpawnHint"
        bb.Adornee = forPart
        bb.Size = UDim2.fromOffset(220, 46)
        bb.AlwaysOnTop = true
        bb.MaxDistance = 999999
        bb.StudsOffset = Vector3.new(0, 3.5, 0)
        bb.Parent = STATE.Highlighter.GuiFolder

        local bg = Instance.new("Frame")
        bg.Size = UDim2.fromScale(1,1)
        bg.BackgroundColor3 = Color3.fromRGB(10,10,10)
        bg.BackgroundTransparency = 0.35
        bg.Parent = bb
        local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0,10); corner.Parent = bg
        local stroke = Instance.new("UIStroke"); stroke.ApplyStrokeMode="Border"; stroke.Color=Color3.fromRGB(70,70,70); stroke.Parent=bg

        local lbl = Instance.new("TextLabel")
        lbl.BackgroundTransparency = 1
        lbl.TextWrapped = true
        lbl.TextScaled = true
        lbl.Font = Enum.Font.GothamSemibold
        lbl.TextColor3 = Color3.fromRGB(235,235,235)
        lbl.Size = UDim2.fromScale(1,1)
        lbl.Text = text
        lbl.Parent = bg

        return bb
    end
    local function free_billboard(inst)
        local bb = STATE.Highlighter.Pool[inst]
        if bb then
            STATE.Highlighter.Pool[inst] = nil
            pcall(function() bb:Destroy() end)
        end
    end
    local function clear_all_billboards()
        for inst,_ in pairs(STATE.Highlighter.Pool) do free_billboard(inst) end
    end

    local function start_highlight_loop()
        if STATE.Highlighter.Conn then return end
        ensure_gui_folder()
        STATE.Highlighter.Conn = RunService.Heartbeat:Connect(function()
            local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
            if not hrp then clear_all_billboards(); return end
            local myPos = hrp.Position

            -- fast membership set für vorhandene spawns
            local exists = {}
            for _,it in ipairs(STATE.Scan.items) do
                exists[it.path] = true
            end

            -- live gehen wir über echte Instanzen (falls rescan nötig)
            -- leichte Optimierung: nur direkte children, dann descendants fallback
            for _,inst in ipairs(Workspace:GetDescendants()) do
                if inst:IsA("SpawnLocation") then
                    local dist = (inst.Position - myPos).Magnitude
                    local bb = STATE.Highlighter.Pool[inst]
                    if dist <= STATE.Highlighter.MaxDistance and STATE.Highlighter.Enabled then
                        if not bb then
                            local labelText = inst.Name
                            -- optional index aus Scan übernehmen:
                            -- suche in STATE.Scan.items nach path match
                            for _,it in ipairs(STATE.Scan.items) do
                                if it.path == path_of(inst) then
                                    labelText = string.format("%s  (%s)", it.name, inst.Name)
                                    break
                                end
                            end
                            bb = alloc_billboard(inst, labelText)
                            STATE.Highlighter.Pool[inst] = bb
                        end
                        bb.Enabled = true
                    else
                        if bb then bb.Enabled = false end
                    end
                end
            end
            -- toter Eintrag bereinigen
            for inst,bb in pairs(STATE.Highlighter.Pool) do
                if not inst or not inst.Parent then
                    free_billboard(inst)
                end
            end
        end)
    end
    local function stop_highlight_loop()
        if STATE.Highlighter.Conn then
            STATE.Highlighter.Conn:Disconnect()
            STATE.Highlighter.Conn = nil
        end
        clear_all_billboards()
    end

    -- ---------------------- UI ----------------------
    local secScan  = tab:AddSection({ Name = "Workspace Spawns" })
    local secBook  = tab:AddSection({ Name = "Bookmarks" })
    local secHi    = tab:AddSection({ Name = "Highlight Nearby" })
    local secTools = tab:AddSection({ Name = "Tools" })

    -- Scan on open (sofort gefüllt)
    local initialCount = scan_spawns()

    local lblCount = secScan:AddLabel(("Gefunden: %d"):format(initialCount))
    local ddScan   -- forward decl

    secScan:AddButton({
        Name = "Rescan SpawnLocation",
        Callback = function()
            local n = scan_spawns()
            lblCount:Set(("Gefunden: %d"):format(n))
            if ddScan then ddScan:Refresh(STATE.Scan.names, true) end
            notify("Inspector", "Rescan fertig.")
        end
    })

    ddScan = secScan:AddDropdown({
        Name = "Spawn auswählen",
        Default = STATE.Scan.selected,
        Options = STATE.Scan.names,
        Callback = function(v) STATE.Scan.selected = v end
    })

    secScan:AddButton({
        Name = "Copy CFrame",
        Callback = function()
            local it = STATE.Scan.byName[STATE.Scan.selected or ""]
            if not it then notify("Inspector","Bitte erst scannen / auswählen."); return end
            if set_clip(it.cfstr) then notify("Copied","CFrame in Clipboard.")
            else print("[Spawn CFrame]", it.name, it.cfstr); notify("Copied","In Konsole gedruckt.") end
        end
    })
    secScan:AddButton({
        Name = "Copy Position (Vector3)",
        Callback = function()
            local it = STATE.Scan.byName[STATE.Scan.selected or ""]
            if not it then notify("Inspector","Bitte erst scannen / auswählen."); return end
            if set_clip(it.v3str) then notify("Copied","Vector3 in Clipboard.")
            else print("[Spawn Position]", it.name, it.v3str); notify("Copied","In Konsole gedruckt.") end
        end
    })

    -- Bookmarks: simpel – Alias -> Position
    local lastAlias = ""
    secBook:AddTextbox({
        Name = "Neuer Bookmark-Name",
        Default = "",
        TextDisappear = false,
        Callback = function(txt) lastAlias = txt end
    })

    local ddBookmarks = secBook:AddDropdown({
        Name = "Bookmark auswählen",
        Default = STATE.Bookmarks.selected,
        Options = STATE.Bookmarks.names,
        Callback = function(v) STATE.Bookmarks.selected = v end
    })

    secBook:AddButton({
        Name = "Bookmark aus Auswahl hinzufügen",
        Callback = function()
            if (lastAlias or "") == "" then notify("Bookmarks","Bitte Namen eingeben."); return end
            local it = STATE.Scan.byName[STATE.Scan.selected or ""]
            if not it then notify("Bookmarks","Keine Auswahl vorhanden."); return end
            local x,y,z = it.cfstr:match("CFrame%.new%(([-%d%.]+), ([-%d%.]+), ([-%d%.]+)%)")
            if not x then notify("Bookmarks","Konnte Position nicht lesen."); return end
            STATE.Bookmarks.items[lastAlias] = {x=tonumber(x),y=tonumber(y),z=tonumber(z)}
            table.insert(STATE.Bookmarks.names, lastAlias); table.sort(STATE.Bookmarks.names)
            ddBookmarks:Refresh(STATE.Bookmarks.names, true); STATE.Bookmarks.selected = lastAlias
            save_all(); notify("Bookmarks", "Gespeichert als \""..lastAlias.."\".")
        end
    })
    secBook:AddButton({
        Name = "Bookmark aus Spielerposition",
        Callback = function()
            if (lastAlias or "") == "" then notify("Bookmarks","Bitte Namen eingeben."); return end
            local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
            if not hrp then notify("Bookmarks","Keine Spielerposition."); return end
            local p = hrp.Position
            STATE.Bookmarks.items[lastAlias] = {x=p.X,y=p.Y,z=p.Z}
            table.insert(STATE.Bookmarks.names, lastAlias); table.sort(STATE.Bookmarks.names)
            ddBookmarks:Refresh(STATE.Bookmarks.names, true); STATE.Bookmarks.selected = lastAlias
            save_all(); notify("Bookmarks", "Gespeichert aus Spielerposition.")
        end
    })
    secBook:AddButton({
        Name = "Copy Bookmark (CFrame)",
        Callback = function()
            local alias = STATE.Bookmarks.selected
            local d = alias and STATE.Bookmarks.items[alias]
            if not d then notify("Bookmarks","Bitte Bookmark wählen."); return end
            local s = string.format("CFrame.new(%.2f, %.2f, %.2f)", d.x, d.y, d.z)
            if set_clip(s) then notify("Copied","Bookmark CFrame kopiert.")
            else print("[Bookmark CFrame]", alias, s); notify("Copied","In Konsole gedruckt.") end
        end
    })
    secBook:AddButton({
        Name = "Bookmark löschen",
        Callback = function()
            local alias = STATE.Bookmarks.selected
            if not alias then notify("Bookmarks","Kein Bookmark ausgewählt."); return end
            STATE.Bookmarks.items[alias] = nil
            STATE.Bookmarks.names = {}
            for k,_ in pairs(STATE.Bookmarks.items) do table.insert(STATE.Bookmarks.names, k) end
            table.sort(STATE.Bookmarks.names)
            ddBookmarks:Refresh(STATE.Bookmarks.names, true)
            STATE.Bookmarks.selected = STATE.Bookmarks.names[1]
            save_all(); notify("Bookmarks","Gelöscht.")
        end
    })

    -- Highlight controls
    secHi:AddToggle({
        Name = "Spawns in der Nähe highlighten",
        Default = false,
        Callback = function(v)
            STATE.Highlighter.Enabled = v
            if v then start_highlight_loop() else stop_highlight_loop() end
        end
    })
    secHi:AddSlider({
        Name = "Highlight Distanz",
        Min = 100, Max = 2000, Increment = 50,
        Default = STATE.Highlighter.MaxDistance,
        ValueName = "studs",
        Callback = function(v) STATE.Highlighter.MaxDistance = math.floor(v) end
    })

    -- Tools
    secTools:AddButton({
        Name = "Aktuelle Auswahl im Output anzeigen",
        Callback = function()
            local it = STATE.Scan.byName[STATE.Scan.selected or ""]
            if not it then notify("Inspector","Kein Eintrag ausgewählt."); return end
            print(("[SorinHub Locator]\nName: %s\nPath: %s\n%s\n%s"):format(it.name, it.path, it.cfstr, it.v3str))
            notify("Inspector", "In Konsole ausgegeben.")
        end
    })

    -- final init refresh (falls der erste Scan oben lief)
    if ddScan then ddScan:Refresh(STATE.Scan.names, true) end
    if ddBookmarks then ddBookmarks:Refresh(STATE.Bookmarks.names, true) end
end
