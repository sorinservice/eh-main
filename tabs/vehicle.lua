-- tabs/vehicle.lua
return function(tab, OrionLib)
    ----------------------------------------------------------------
    -- SorinHub · Vehicle Mod (dev)
    -- - To Vehicle (auf Sitz teleportieren & einsteigen)
    -- - Bring Vehicle (Fahrzeug zu dir & einsteigen)
    -- - License Plate (lokal, persistiert & auto-reapply)
    ----------------------------------------------------------------

    -----------------------------
    -- Services & singletons
    -----------------------------
    local Players      = game:GetService("Players")
    local RunService   = game:GetService("RunService")
    local HttpService  = game:GetService("HttpService")
    local TweenService = game:GetService("TweenService")
    local Workspace    = game:GetService("Workspace")

    local LP           = Players.LocalPlayer

    -----------------------------
    -- Persistenz
    -----------------------------
    local SAVE_FOLDER = OrionLib.Folder or "SorinConfig"
    local SAVE_FILE   = SAVE_FOLDER .. "/vehicle.json"

    local function safe_read_json(path)
        local ok, data = pcall(function()
            if isfile and isfile(path) then
                return HttpService:JSONDecode(readfile(path))
            end
            return nil
        end)
        return ok and data or nil
    end

    local function safe_write_json(path, tbl)
        pcall(function()
            if makefolder and not isfolder(SAVE_FOLDER) then
                makefolder(SAVE_FOLDER)
            end
            if writefile then
                writefile(path, HttpService:JSONEncode(tbl))
            end
        end)
    end

    -----------------------------
    -- Config (nur was der User ändert)
    -----------------------------
    local CFG = {
        plateText   = "",    -- wird in UI geändert
    }

    do
        local saved = safe_read_json(SAVE_FILE)
        if type(saved) == "table" then
            for k,v in pairs(saved) do CFG[k] = v end
        end
    end

    local function save_cfg()
        safe_write_json(SAVE_FILE, {
            plateText = CFG.plateText,
        })
    end

    -----------------------------
    -- Game helpers
    -----------------------------
    local function VehiclesFolder()
        return Workspace:FindFirstChild("Vehicles") or Workspace:FindFirstChild("vehicles") or Workspace
    end

    local function myVehicleFolder()
        local vRoot = VehiclesFolder()
        if not vRoot then return nil end
        local mf = vRoot:FindFirstChild(LP.Name)
        if mf then return mf end
        -- fallback: nach Besitzer-Attribut o.ä. suchen
        for _,m in ipairs(vRoot:GetChildren()) do
            if m:IsA("Model") or m:IsA("Folder") then
                local owner = (m:GetAttribute and m:GetAttribute("Owner")) or m:FindFirstChild("Owner")
                if owner == LP.Name then return m end
            end
        end
        return nil
    end

    local function findDriveSeat(vFolder)
        if not vFolder then return nil end
        -- 1) klassisch: DriveSeat
        local ds = vFolder:FindFirstChild("DriveSeat", true)
        if ds and ds:IsA("Seat") then return ds end
        -- 2) Seats/… suchen
        local seats = vFolder:FindFirstChild("Seats", true)
        if seats then
            for _,ch in ipairs(seats:GetDescendants()) do
                if ch:IsA("Seat") then return ch end
            end
        end
        -- 3) irgendein Seat als Fallback
        for _,d in ipairs(vFolder:GetDescendants()) do
            if d:IsA("Seat") then return d end
        end
        return nil
    end

    -----------------------------
    -- Einsteigen via Prompt
    -----------------------------
    local function findDriverPrompt(vFolder)
        if not vFolder then return nil end
        local nearest, bestDist = nil, math.huge
        local ds = findDriveSeat(vFolder)
        local dsPos = (ds and ds.Position) or (vFolder:GetPivot and vFolder:GetPivot().Position) or vFolder.Position

        for _,pp in ipairs(vFolder:GetDescendants()) do
            if pp:IsA("ProximityPrompt") then
                local a = string.lower(pp.ActionText or "")
                local o = string.lower(pp.ObjectText or "")
                if a:find("fahrer") or o:find("fahrer") or a:find("driver") or o:find("driver") or a:find("seat") or o:find("seat") then
                    -- nimm das Prompt, das dem DriveSeat am nächsten ist
                    local base = (pp.Parent.GetPivot and pp.Parent:GetPivot().Position) or (pp.Parent.Position or dsPos)
                    local d = (base - dsPos).Magnitude
                    if d < bestDist then
                        bestDist, nearest = d, pp
                    end
                end
            end
        end
        return nearest
    end

    local function tpBesidePrompt(pp)
        local char = LP.Character or LP.CharacterAdded:Wait()
        local hrp  = char:WaitForChild("HumanoidRootPart")
        local base = (pp.Parent.GetPivot and pp.Parent:GetPivot()) or CFrame.new(pp.Parent.Position)
        -- seitlich/leicht erhöht an die Tür
        hrp.CFrame = base * CFrame.new(-1.1, 1.4, 0.2)
    end

    local function pressPromptHard(pp, tries)
        tries = tries or 8
        if not pp then return false end
        for _=1, tries do
            if typeof(fireproximityprompt) == "function" then
                pcall(function() fireproximityprompt(pp, pp.HoldDuration and math.max(pp.HoldDuration,0.1) or 0.2) end)
            else
                pp:InputHoldBegin()
                task.wait(pp.HoldDuration and math.max(pp.HoldDuration,0.1) or 0.2)
                pp:InputHoldEnd()
            end
            task.wait(0.08)
            local ds = findDriveSeat(myVehicleFolder())
            local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
            if ds and hum and ds.Occupant == hum then
                return true
            end
        end
        return false
    end

    local function enterSeat(seat)
        local char = LP.Character or LP.CharacterAdded:Wait()
        local hum  = char:FindFirstChildOfClass("Humanoid")
        if not (seat and hum) then return false end

        -- 1) bevorzugt via Prompt
        local vf = myVehicleFolder()
        local pp = findDriverPrompt(vf)
        if pp then
            tpBesidePrompt(pp)
            task.wait(0.05)
            if pressPromptHard(pp, 10) then return true end
        end

        -- 2) direkter Sitzversuch
        if pcall(function() seat:Sit(hum) end) and seat.Occupant == hum then
            return true
        end

        -- 3) kleiner Stupser
        if hum.RootPart then
            hum:MoveTo(seat.Position + seat.CFrame.LookVector * -0.9)
            local t0 = time()
            while time() - t0 < 1.2 do
                task.wait()
                if seat.Occupant == hum then return true end
            end
            hum.RootPart.CFrame = seat.CFrame * CFrame.new(0, 0.1, -0.2)
            task.wait(0.05)
        end
        return seat.Occupant == hum
    end

    -----------------------------
    -- Bewegungen
    -----------------------------
    local WARN_DISTANCE = 300      -- nur Hinweis; kein UI nötig
    local BRING_OFFSET  = CFrame.new(0, 0, -3) -- 3 studs vor dir erscheinen

    local function toVehicle()
        local vf = myVehicleFolder()
        local ds = findDriveSeat(vf)
        if not (vf and ds) then
            OrionLib:MakeNotification({Name="Vehicle", Content="Kein eigenes Fahrzeug gefunden.", Time=3})
            return
        end

        local char = LP.Character or LP.CharacterAdded:Wait()
        local hrp  = char:WaitForChild("HumanoidRootPart")
        local dist = (hrp.Position - ds.Position).Magnitude
        if dist > WARN_DISTANCE then
            OrionLib:MakeNotification({Name="Vehicle", Content=("Achtung: Fahrzeug ist weit entfernt (~%d studs)."):format(math.floor(dist)), Time=3})
        end

        -- nahe an die Tür setzen
        hrp.CFrame = ds.CFrame * CFrame.new(-2.0, 1.2, 0.0)
        task.wait(0.05)
        if enterSeat(ds) then
            OrionLib:MakeNotification({Name="Vehicle", Content="Eingestiegen.", Time=2})
        else
            OrionLib:MakeNotification({Name="Vehicle", Content="Konnte nicht einsteigen (Anti-TP/Anti-Seat?).", Time=3})
        end
    end

    local function bringVehicle()
        local vf = myVehicleFolder()
        local ds = findDriveSeat(vf)
        if not (vf and ds) then
            OrionLib:MakeNotification({Name="Vehicle", Content="Kein eigenes Fahrzeug gefunden.", Time=3})
            return
        end

        local char = LP.Character or LP.CharacterAdded:Wait()
        local hrp  = char:WaitForChild("HumanoidRootPart")

        -- neben dich holen (PivotTo ist am saubersten)
        local target = hrp.CFrame * BRING_OFFSET
        if vf.PivotTo then
            vf:PivotTo(CFrame.new(target.Position, (hrp.Position + hrp.CFrame.LookVector)))
        else
            -- Fallback, falls altes API
            local root = vf.PrimaryPart or ds
            if root then
                root.CFrame = target
            end
        end
        task.wait(0.05)

        if enterSeat(ds) then
            OrionLib:MakeNotification({Name="Vehicle", Content="Fahrzeug gebracht & eingestiegen.", Time=2})
        else
            OrionLib:MakeNotification({Name="Vehicle", Content="Fahrzeug gebracht, aber Einsteigen blockiert.", Time=3})
        end
    end

    -----------------------------
    -- License Plate (lokal)
    -----------------------------
    local function applyPlateToVehicle(vFolder, text)
        if not (vFolder and text and #text > 0) then return false end

        local function setOne(gui)
            if not gui then return false end
            local tl = gui:FindFirstChildOfClass("TextLabel")
            if not tl then
                for _,d in ipairs(gui:GetDescendants()) do
                    if d:IsA("TextLabel") then tl = d; break end
                end
            end
            if tl then
                tl.Text = text
                return true
            end
            return false
        end

        -- Erwarteter Pfad
        local body = vFolder:FindFirstChild("Body", true)
        local plates = body and body:FindFirstChild("LicensePlates", true)
        if not plates then plates = body and body:FindFirstChild("LicencePlates", true) end -- Schreibweise absichern

        local ok = false
        if plates then
            local back = plates:FindFirstChild("Back", true)
            local front = plates:FindFirstChild("Front", true)

            local function guiOf(node)
                return node and (node:FindFirstChild("Gui") or node:FindFirstChild("SurfaceGui") or node:FindFirstChildWhichIsA("SurfaceGui"))
            end

            ok = setOne(guiOf(back)) or ok
            ok = setOne(guiOf(front)) or ok
        end

        -- Fallback: irgendein SurfaceGui namens License… durchsuchen
        if not ok then
            for _,sg in ipairs(vFolder:GetDescendants()) do
                if sg:IsA("SurfaceGui") and string.lower(sg.Name):find("license") then
                    ok = setOne(sg) or ok
                end
            end
        end

        return ok
    end

    local function applyPlateIfPossible(vf, text)
        if not (vf and text and #text>0) then return false end
        return applyPlateToVehicle(vf, text)
    end

    local function ensurePlateForMyVehicle(timeout)
        timeout = timeout or 6.0
        if (CFG.plateText or "") == "" then return end
        local t0 = time()
        while time() - t0 < timeout do
            local vf = myVehicleFolder()
            if vf and applyPlateIfPossible(vf, CFG.plateText) then
                return true
            end
            task.wait(0.25)
        end
        return false
    end

    -- Bei Start & bei Neuspawns erneut anwenden
    task.defer(function() ensurePlateForMyVehicle(6) end)
    local vConn
    do
        local root = VehiclesFolder()
        if root then
            if vConn then vConn:Disconnect() end
            vConn = root.ChildAdded:Connect(function(ch)
                if ch.Name == LP.Name then
                    task.defer(function() ensurePlateForMyVehicle(6) end)
                end
            end)
        end
    end

    -----------------------------
    -- ORION UI
    -----------------------------
    local secVehicle = tab:AddSection({ Name = "Vehicle" })

    secVehicle:AddButton({
        Name = "To Vehicle (auf Sitz & einsteigen)",
        Callback = toVehicle
    })

    secVehicle:AddButton({
        Name = "Bring Vehicle (vor dich & einsteigen)",
        Callback = bringVehicle
    })

    local secPlate = tab:AddSection({ Name = "License Plate (lokal)" })

    secPlate:AddTextbox({
        Name = "Kennzeichen-Text",
        Default = CFG.plateText,
        TextDisappear = false,
        Callback = function(txt)
            CFG.plateText = tostring(txt or "")
            save_cfg()
        end
    })

    secPlate:AddButton({
        Name = "Kennzeichen auf aktuelles Fahrzeug anwenden",
        Callback = function()
            local vf = myVehicleFolder()
            if not vf then
                OrionLib:MakeNotification({Name="Vehicle", Content="Kein eigenes Fahrzeug gefunden.", Time=3})
                return
            end
            if (CFG.plateText or "") == "" then
                OrionLib:MakeNotification({Name="Vehicle", Content="Bitte Text eingeben.", Time=2})
                return
            end
            if applyPlateToVehicle(vf, CFG.plateText) then
                OrionLib:MakeNotification({Name="Vehicle", Content="Kennzeichen gesetzt (lokal).", Time=2})
            else
                OrionLib:MakeNotification({Name="Vehicle", Content="Konnte Kennzeichen nicht finden/setzen.", Time=3})
            end
        end
    })

    -- kleine Konsole
    print(("VehicleMod loaded. Dev build.\nWarn Distance: %d studs."):format(WARN_DISTANCE))
end
