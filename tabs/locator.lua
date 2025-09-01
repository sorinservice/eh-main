-- tabs/locator.lua
-- SorinHub: Spawn Inspector + Bookmarks + Dynamic Highlight (optimiert)

return function(tab, OrionLib)
    local HttpService = game:GetService("HttpService")
    local Workspace   = game:GetService("Workspace")
    local Players     = game:GetService("Players")
    local RunService  = game:GetService("RunService")

    local LP          = Players.LocalPlayer
    local SAVE_FOLDER = OrionLib.Folder or "SorinConfig"
    local SAVE_FILE   = SAVE_FOLDER .. "/spawn_inspector.json"

    -- ---------- utils ----------
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
    local function notify(t, m, secs) OrionLib:MakeNotification({Name=t, Content=m, Time=secs or 3}) end

    -- ---------- state ----------
    local STATE = {
        Scan = { items={}, names={}, byName={}, selected=nil, idx=1 },
        Bookmarks = { items={}, names={}, selected=nil },
        HL = {
            Enabled=false, MaxDistance=500,
            GuiFolder=nil, Pool={}, Conn=nil,
            Ticker=0, Interval=0.15, -- 6x pro Sekunde
        }
    }

    -- bookmarks laden
    do
        local saved = read_json(SAVE_FILE) or {}
        STATE.Bookmarks.items = saved.bookmarks or {}
        for alias,_ in pairs(STATE.Bookmarks.items) do table.insert(STATE.Bookmarks.names, alias) end
        table.sort(STATE.Bookmarks.names)

        if saved.lastScan and saved.lastScan.items then
            -- Achtung: gespeicherte Items haben keine Instanz-Refs mehr (anderer Join),
            -- wir scannen sowieso sofort neu; load nur für Anzeige, falls nötig.
            STATE.Scan.items = {}
        end
    end
    local function save_all()
        write_json(SAVE_FILE, {
            bookmarks = STATE.Bookmarks.items,
            lastScan  = { items = {} } -- Instanz-Refs nicht serialisieren
        })
    end

    -- ---------- scanning ----------
    local function scan_spawns()
        local list, names, map = {}, {}, {}
        local n = 0
        for _, inst in ipairs(Workspace:GetDescendants()) do
            if inst:IsA("SpawnLocation") then
                n = n + 1
                local cfstr, v3str = cf_to_strings(inst.CFrame)
                local label = string.format("#%02d %s", n, inst.Name)
                local item = {
                    id = n,
                    name = label,
                    inst = inst,      -- <- echte Instanz (für Highlight / Distanz)
                    cfstr = cfstr,
                    v3str = v3str,
                }
                list[#list+1] = item
                names[#names+1] = label
                map[label] = item
            end
        end
        STATE.Scan.items, STATE.Scan.names, STATE.Scan.byName = list, names, map
        STATE.Scan.selected = names[1]
        STATE.Scan.idx = (#names >= 1) and 1 or 0
        return n
    end

    -- ---------- highlighter ----------
    local function ensure_gui_folder()
        if STATE.HL.GuiFolder then return end
        local g = Instance.new("ScreenGui")
        g.Name = "Sorin_SpawnHighlighter"
        g.ResetOnSpawn = false
        g.IgnoreGuiInset = true
        g.Parent = game:GetService("CoreGui")
        STATE.HL.GuiFolder = g
    end
    local function alloc_bb(forPart, text)
        ensure_gui_folder()
        local bb = Instance.new("BillboardGui")
        bb.Name = "SpawnHint"
        bb.Adornee = forPart
        bb.Size = UDim2.fromOffset(220, 46)
        bb.AlwaysOnTop = true
        bb.MaxDistance = 999999
        bb.StudsOffset = Vector3.new(0, 3.5, 0)
        bb.Parent = STATE.HL.GuiFolder

        local bg = Instance.new("Frame")
        bg.Size = UDim2.fromScale(1,1)
        bg.BackgroundColor3 = Color3.fromRGB(10,10,10)
        bg.BackgroundTransparency = 0.35
        bg.Parent = bb
        local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0,10); corner.Parent = bg
        local stroke = Instance.new("UIStroke"); stroke.Color=Color3.fromRGB(70,70,70); stroke.Parent=bg

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
    local function free_bb(inst)
        local bb = STATE.HL.Pool[inst]
        if bb then
            STATE.HL.Pool[inst] = nil
            pcall(function() bb:Destroy() end)
        end
    end
    local function clear_all_bb()
        for inst,_ in pairs(STATE.HL.Pool) do free_bb(inst) end
    end

    local function start_highlight()
        if STATE.HL.Conn then return end
        ensure_gui_folder()
        STATE.HL.Ticker = 0
        STATE.HL.Conn = RunService.Heartbeat:Connect(function(dt)
            STATE.HL.Ticker += dt
            if STATE.HL.Ticker < STATE.HL.Interval then return end
            STATE.HL.Ticker = 0

            if not STATE.HL.Enabled then
                clear_all_bb(); return
            end

            local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
            if not hrp then clear_all_bb(); return end
            local myPos = hrp.Position

            -- nur über gescannte Items iterieren (deutlich leichter)
            for _,it in ipairs(STATE.Scan.items) do
                local inst = it.inst
                if inst and inst.Parent then
                    local dist = (inst.Position - myPos).Magnitude
                    local bb = STATE.HL.Pool[inst]
                    local shouldShow = (dist <= STATE.HL.MaxDistance)

                    if shouldShow and not bb then
                        bb = alloc_bb(inst, string.format("%s\n(%s)", it.name, inst.Name))
                        STATE.HL.Pool[inst] = bb
                    end

                    if bb then bb.Enabled = shouldShow end
                else
                    -- Instanz existiert nicht mehr → säubern
                    free_bb(inst)
                end
            end
        end)
    end
    local function stop_highlight()
        if STATE.HL.Conn then STATE.HL.Conn:Disconnect(); STATE.HL.Conn = nil end
        clear_all_bb()
    end

    -- ---------- UI ----------
    local secScan  = tab:AddSection({ Name = "Workspace Spawns" })
    local secBook  = tab:AddSection({ Name = "Bookmarks" })
    local secHi    = tab:AddSection({ Name = "Highlight Nearby" })
    local secTools = tab:AddSection({ Name = "Tools" })

    -- sofort scannen
    local count = scan_spawns()
    local lblCount = secScan:AddLabel(("Gefunden: %d"):format(count))

    local ddScan
    ddScan = secScan:AddDropdown({
        Name = "Spawn auswählen",
        Default = STATE.Scan.selected,
        Options = STATE.Scan.names,
        Callback = function(v)
            STATE.Scan.selected = v
            -- index updaten, falls Slider benutzt wird
            for i,name in ipairs(STATE.Scan.names) do
                if name == v then STATE.Scan.idx = i; break end
            end
        end
    })

    secScan:AddButton({
        Name = "Rescan SpawnLocation",
        Callback = function()
            local n = scan_spawns()
            lblCount:Set(("Gefunden: %d"):format(n))
            if ddScan then ddScan:Refresh(STATE.Scan.names, true) end
            notify("Inspector","Rescan fertig.")
        end
    })

    -- Fallback/Komfort: Index-Slider (falls Dropdown mal leer wirkt)
    secScan:AddSlider({
        Name = "Spawn Index",
        Min = (#STATE.Scan.names > 0) and 1 or 0,
        Max = #STATE.Scan.names,
        Default = STATE.Scan.idx,
        Increment = 1,
        Callback = function(i)
            i = math.clamp(math.floor(i), 1, math.max(1, #STATE.Scan.names))
            STATE.Scan.idx = i
            local name = STATE.Scan.names[i]
            if name then
                STATE.Scan.selected = name
                if ddScan then ddScan:Set(name) end
            end
        end
    })

    secScan:AddButton({
        Name = "Copy CFrame",
        Callback = function()
            local it = STATE.Scan.byName[STATE.Scan.selected or ""]
            if not it then notify("Inspector","Bitte Auswahl treffen."); return end
            if set_clip(it.cfstr) then notify("Copied","CFrame in Clipboard.")
            else print("[Spawn CFrame]", it.name, it.cfstr); notify("Copied","In Konsole gedruckt.") end
        end
    })
    secScan:AddButton({
        Name = "Copy Position (Vector3)",
        Callback = function()
            local it = STATE.Scan.byName[STATE.Scan.selected or ""]
            if not it then notify("Inspector","Bitte Auswahl treffen."); return end
            if set_clip(it.v3str) then notify("Copied","Vector3 in Clipboard.")
            else print("[Spawn Position]", it.name, it.v3str); notify("Copied","In Konsole gedruckt.") end
        end
    })

    -- Bookmarks
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
            if not it then notify("Bookmarks","Keine Auswahl."); return end
            local x,y,z = it.cfstr:match("CFrame%.new%(([-%d%.]+), ([-%d%.]+), ([-%d%.]+)%)")
            if not x then notify("Bookmarks","Position lesen fehlgeschlagen."); return end
            STATE.Bookmarks.items[lastAlias] = {x=tonumber(x),y=tonumber(y),z=tonumber(z)}
            STATE.Bookmarks.names = {}
            for k,_ in pairs(STATE.Bookmarks.items) do table.insert(STATE.Bookmarks.names, k) end
            table.sort(STATE.Bookmarks.names)
            ddBookmarks:Refresh(STATE.Bookmarks.names, true)
            STATE.Bookmarks.selected = lastAlias
            save_all(); notify("Bookmarks",'Gespeichert als "'..lastAlias..'".')
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
            STATE.Bookmarks.names = {}
            for k,_ in pairs(STATE.Bookmarks.items) do table.insert(STATE.Bookmarks.names, k) end
            table.sort(STATE.Bookmarks.names)
            ddBookmarks:Refresh(STATE.Bookmarks.names, true)
            STATE.Bookmarks.selected = lastAlias
            save_all(); notify("Bookmarks","Gespeichert aus Spielerposition.")
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

    -- Highlight
    secHi:AddToggle({
        Name = "Spawns in der Nähe highlighten",
        Default = false,
        Callback = function(v)
            STATE.HL.Enabled = v
            if v then start_highlight() else stop_highlight() end
        end
    })
    secHi:AddSlider({
        Name = "Highlight Distanz",
        Min = 100, Max = 2000, Increment = 50,
        Default = STATE.HL.MaxDistance,
        ValueName = "studs",
        Callback = function(v) STATE.HL.MaxDistance = math.floor(v) end
    })

    -- Tools
    secTools:AddButton({
        Name = "Aktuelle Auswahl im Output anzeigen",
        Callback = function()
            local it = STATE.Scan.byName[STATE.Scan.selected or ""]
            if not it then notify("Inspector","Kein Eintrag ausgewählt."); return end
            print(("[SorinHub Locator]\nName: %s\nCFrame: %s\nPosition: %s"):format(it.name, it.cfstr, it.v3str))
            notify("Inspector","In Konsole ausgegeben.")
        end
    })
end
