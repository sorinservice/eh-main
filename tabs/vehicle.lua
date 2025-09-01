-- tabs/vehicle.lua
return function(tab, Orion)
    print(
    "VehicleMod loaded. | Not safe to use, dev version 1.1\n" ..
    "Warn Distance: 300 Studs."
)

    ----------------------------------------------------------------
    -- SorinHub | Vehicle Mod (DEV)
    -- - To Vehicle (Teleport auf Sitz & einsteigen)
    -- - Bring Vehicle (Auto zu dir & einsteigen)
    -- - Lokales Kennzeichen (Front+Back) mit Persistenz
    ----------------------------------------------------------------

    local Players      = game:GetService("Players")
    local RunService   = game:GetService("RunService")
    local HttpService  = game:GetService("HttpService")
    local Workspace    = game:GetService("Workspace")

    local LP           = Players.LocalPlayer
    local Vehicles     = Workspace:FindFirstChild("Vehicles")
    local Camera       = Workspace.CurrentCamera

    -- ===== Settings im Code (keine UI) =====
    local WARN_DISTANCE_STUDS = 300    -- ab hier wird nur gewarnt (kein Teleport)
    local BRING_OFFSET = CFrame.new(0, 2.75, -5) -- wohin das Auto vor dich gestellt wird

    -- ===== Persistenz =====
    local SAVE_FOLDER = Orion.Folder or "SorinConfig"
    local SAVE_FILE   = SAVE_FOLDER .. "/vehicle.json"

    local function safeRead()
        if isfile and isfile(SAVE_FILE) then
            local ok, tbl = pcall(function()
                return HttpService:JSONDecode(readfile(SAVE_FILE))
            end)
            if ok and type(tbl) == "table" then return tbl end
        end
        return { plateText = "" }
    end

    local function safeWrite(tbl)
        pcall(function()
            if makefolder and not isfolder(SAVE_FOLDER) then makefolder(SAVE_FOLDER) end
            if writefile then writefile(SAVE_FILE, HttpService:JSONEncode(tbl)) end
        end)
    end

    local CFG = safeRead()

    -- ===== Utils =====
    local function getMyVehicle()
        if not Vehicles then return nil end
        return Vehicles:FindFirstChild(LP.Name)
    end

    local function getDriveSeat(model)
        if not model then return nil end
        -- häufig liegt er direkt unter dem Model als VehicleSeat/Seat "DriveSeat"
        local seat = model:FindFirstChild("DriveSeat", true)
        if seat and seat:IsA("BasePart") then return seat end
        -- Fallback: irgendein VehicleSeat
        for _,d in ipairs(model:GetDescendants()) do
            if d:IsA("VehicleSeat") or d:IsA("Seat") then
                return d
            end
        end
        return nil
    end

    local function dist(a, b)
        return (a - b).Magnitude
    end

    local function notify(t)
        Orion:MakeNotification({Name="Vehicle", Content=t, Time=3})
    end

    local function firePromptIfAny(seat)
        -- manche Spiele haben direkt am Sitz einen ProximityPrompt
        for _,d in ipairs(seat:GetDescendants()) do
            if d:IsA("ProximityPrompt") then
                pcall(function() fireproximityprompt(d) end)
                return true
            end
        end
        return false
    end

    local function seatHumanoid(hum, seat)
        if not (hum and seat) then return false end

        -- 1) freundlicher Weg: ProximityPrompt (falls vorhanden)
        if firePromptIfAny(seat) then return true end

        -- 2) Roblox-API: Seat:Sit(humanoid) (funktioniert nur, wenn Humanoid den Sitz berührt)
        -- wir teleportieren knapp über den Sitz und "touchen" ihn für den Weld
        local root = hum.RootPart or (hum.Parent and hum.Parent:FindFirstChild("HumanoidRootPart"))
        if not root then return false end

        -- knapp über den Sitz
        root.CFrame = seat.CFrame * CFrame.new(0, 2, 0)
        task.wait()

        -- Touch-Hack (Client): erzeugt den SeatWeld
        if firetouchinterest then
            pcall(function()
                firetouchinterest(root, seat, 0) -- touch begin
                task.wait(0.05)
                firetouchinterest(root, seat, 1) -- touch end (Seat weld bleibt)
            end)
        end

        -- versuchen zu sitzen
        pcall(function() seat:Sit(hum) end)
        hum.Sit = true

        -- kurzer Check
        task.wait(0.10)
        return hum.Sit == true
    end

    local function applyPlateTextTo(model, text)
        if not (model and text and text ~= "") then return false end
        local ok = false
        local body = model:FindFirstChild("Body")
        local plates = body and body:FindFirstChild("LicensePlates") or body and body:FindFirstChild("LicencePlates")
        if not plates then
            -- manchmal liegen Front/Back direkt unter Body
            plates = body
        end
        if not plates then return false end

        local function applyToNode(node)
            if not node then return end
            local gui = node:FindFirstChild("Gui", true)
            local label = gui and gui:FindFirstChildWhichIsA("TextLabel", true)
            if label and label:IsA("TextLabel") then
                pcall(function()
                    label.Text = text
                end)
                ok = true
            end
        end

        applyToNode(plates:FindFirstChild("Front"))
        applyToNode(plates:FindFirstChild("Back"))
        -- Fallback: falls die Struktur anders ist, versuche beide Label im Body zu finden
        if not ok then
            for _,d in ipairs(body:GetDescendants()) do
                if d:IsA("TextLabel") then
                    pcall(function() d.Text = text end)
                    ok = true
                end
            end
        end
        return ok
    end

    local function ensurePlateWatcher()
        if not Vehicles then return end
        -- bei neuen Autos sofort Label setzen
        Vehicles.ChildAdded:Connect(function(m)
            task.wait(0.2) -- kurz warten bis Bau fertig
            if m.Name == LP.Name and CFG.plateText ~= "" then
                applyPlateTextTo(m, CFG.plateText)
            end
        end)
    end
    ensurePlateWatcher()

    -- ===== Aktionen =====
    local function toVehicle()
        local car = getMyVehicle()
        if not car then return notify("Kein Fahrzeug gefunden.") end

        local seat = getDriveSeat(car)
        if not seat then return notify("DriveSeat nicht gefunden.") end

        local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
        if not (hrp and hum) then return notify("Spieler nicht bereit.") end

        local d = dist(hrp.Position, seat.Position)
        if d > WARN_DISTANCE_STUDS then
            return notify(("Zu weit entfernt (%.0f studs)."):format(d))
        end

        -- teleport knapp neben den Sitz (nicht exakt drauf – AntiSeat mag sonst blocken)
        hrp.CFrame = seat.CFrame * CFrame.new(-1.25, 2, -1.25)
        task.wait(0.05)

        if seatHumanoid(hum, seat) then
            notify("Eingestiegen.")
        else
            notify("Konnte nicht einsteigen (Anti-TP/Anti-Seat?).")
        end
    end

    local function bringVehicle()
        local car = getMyVehicle()
        if not car then return notify("Kein Fahrzeug gefunden.") end

        local seat = getDriveSeat(car)
        if not seat then return notify("DriveSeat nicht gefunden.") end

        local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
        if not (hrp and hum) then return notify("Spieler nicht bereit.") end

        -- Auto vor dich setzen (Pivot nutzt Model:PivotTo, Roblox erstellt nötige Welds)
        local targetCF = hrp.CFrame * BRING_OFFSET
        pcall(function() car:PivotTo(targetCF) end)
        task.wait(0.05)

        if seatHumanoid(hum, seat) then
            notify("Fahrzeug gebracht & eingestiegen.")
        else
            notify("Fahrzeug gebracht – Einsteigen fehlgeschlagen.")
        end
    end

    local function applyPlateCurrent()
        local car = getMyVehicle()
        if not car then return notify("Kein Fahrzeug gefunden.") end
        if CFG.plateText == "" then return notify("Kennzeichen-Text ist leer.") end
        if applyPlateTextTo(car, CFG.plateText) then
            notify("Kennzeichen angewandt (lokal).")
        else
            notify("Konnte Kennzeichen nicht anwenden.")
        end
    end

    -- ===== ORION UI =====
    local sec = tab:AddSection({ Name = "Vehicle" })
    sec:AddButton({ Name = "To Vehicle (auf Sitz & einsteigen)", Callback = toVehicle })
    sec:AddButton({ Name = "Bring Vehicle (vor dich & einsteigen)", Callback = bringVehicle })

    local secPlate = tab:AddSection({ Name = "License Plate (lokal)" })
    local plateBox
    plateBox = secPlate:AddTextbox({
        Name = "Kennzeichen-Text",
        Default = (CFG.plateText or ""),
        TextDisappear = false,
        Callback = function(txt)
            CFG.plateText = tostring(txt or "")
            safeWrite(CFG)
        end
    })
    secPlate:AddButton({
        Name = "Kennzeichen auf aktuelles Fahrzeug anwenden",
        Callback = applyPlateCurrent
    })

    -- ===== Auto-Apply beim Join, falls Auto schon da ist
    task.spawn(function()
        task.wait(0.5)
        local car = getMyVehicle()
        if car and CFG.plateText ~= "" then
            applyPlateTextTo(car, CFG.plateText)
        end
    end)
end
