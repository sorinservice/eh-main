-- tabs/vehicle.lua
return function(tab, OrionLib)
    ----------------------------------------------------------------
    -- SorinHub · Vehicle Mod (dev, hardened)
    ----------------------------------------------------------------

    local Players      = game:GetService("Players")
    local RunService   = game:GetService("RunService")
    local HttpService  = game:GetService("HttpService")
    local Workspace    = game:GetService("Workspace")

    local LP = Players.LocalPlayer

    ----------------------------------------------------------------
    -- Persist (only plateText)
    ----------------------------------------------------------------
    local SAVE_FOLDER = OrionLib.Folder or "SorinConfig"
    local SAVE_FILE   = SAVE_FOLDER .. "/vehicle.json"

    local function read_json(path)
        local ok, data = pcall(function()
            if isfile and isfile(path) then
                return HttpService:JSONDecode(readfile(path))
            end
        end)
        return ok and data or nil
    end
    local function write_json(path, tbl)
        pcall(function()
            if makefolder and not isfolder(SAVE_FOLDER) then makefolder(SAVE_FOLDER) end
            if writefile then writefile(path, HttpService:JSONEncode(tbl)) end
        end)
    end

    local CFG = { plateText = "" }
    do
        local saved = read_json(SAVE_FILE)
        if type(saved) == "table" and type(saved.plateText) == "string" then
            CFG.plateText = saved.plateText
        end
    end
    local function save_cfg() write_json(SAVE_FILE, { plateText = CFG.plateText }) end

    ----------------------------------------------------------------
    -- Helpers (safe world position / pivot)
    ----------------------------------------------------------------
    local function instWorldCFrame(inst)
        if not inst or not inst.Parent then return nil end
        if inst:IsA("BasePart") then
            return inst.CFrame
        elseif inst:IsA("Model") and inst.GetPivot then
            local ok, cf = pcall(inst.GetPivot, inst)
            if ok and typeof(cf) == "CFrame" then return cf end
        end
        -- try parent model
        local p = inst.Parent
        if p and p:IsA("Model") and p.GetPivot then
            local ok, cf = pcall(p.GetPivot, p)
            if ok and typeof(cf) == "CFrame" then return cf end
        end
        return nil
    end

    local function instWorldPos(inst)
        local cf = instWorldCFrame(inst)
        return cf and cf.Position or nil
    end

    ----------------------------------------------------------------
    -- Vehicle discovery (strict: only Workspace.Vehicles / .vehicles)
    ----------------------------------------------------------------
    local function VehiclesFolder()
        return Workspace:FindFirstChild("Vehicles") or Workspace:FindFirstChild("vehicles")
    end

    local function myVehicleFolder()
        local root = VehiclesFolder()
        if not root then return nil end
        local mine = root:FindFirstChild(LP.Name)
        if mine then return mine end
        -- fallback: scan by attribute Owner/PlayerName
        for _,m in ipairs(root:GetChildren()) do
            if (m:IsA("Model") or m:IsA("Folder")) then
                local owner = (m.GetAttribute and (m:GetAttribute("Owner") or m:GetAttribute("PlayerName")))
                if owner and tostring(owner) == LP.Name then
                    return m
                end
            end
        end
        return nil
    end

    local function findDriveSeat(vFolder)
        if not vFolder then return nil end
        local ds = vFolder:FindFirstChild("DriveSeat", true)
        if ds and ds:IsA("Seat") then return ds end
        local seats = vFolder:FindFirstChild("Seats", true)
        if seats then
            for _,d in ipairs(seats:GetDescendants()) do
                if d:IsA("Seat") then return d end
            end
        end
        for _,d in ipairs(vFolder:GetDescendants()) do
            if d:IsA("Seat") then return d end
        end
        return nil
    end

    ----------------------------------------------------------------
    -- Enter via driver prompt (robust) or direct Sit fallback
    ----------------------------------------------------------------
    local function findDriverPrompt(vFolder)
        if not vFolder then return nil end
        local ds = findDriveSeat(vFolder)
        local dsPos = ds and ds.Position or (instWorldPos(vFolder) or Vector3.new())
        local nearest, best = nil, math.huge
        for _,pp in ipairs(vFolder:GetDescendants()) do
            if pp:IsA("ProximityPrompt") then
                local a = string.lower(pp.ActionText or "")
                local o = string.lower(pp.ObjectText or "")
                if a:find("fahrer") or o:find("fahrer") or a:find("driver") or o:find("driver") or a:find("seat") or o:find("seat") then
                    local ppos = instWorldPos(pp.Parent) or dsPos
                    local d = (ppos - dsPos).Magnitude
                    if d < best then best, nearest = d, pp end
                end
            end
        end
        return nearest
    end

    local function tpBesidePrompt(pp)
        local char = LP.Character or LP.CharacterAdded:Wait()
        local hrp  = char:WaitForChild("HumanoidRootPart")
        local base = instWorldCFrame(pp.Parent) or CFrame.new(pp.Parent.Position)
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
            if ds and hum and ds.Occupant == hum then return true end
        end
        return false
    end

    local function enterSeat(seat)
        local char = LP.Character or LP.CharacterAdded:Wait()
        local hum  = char:FindFirstChildOfClass("Humanoid")
        if not (seat and hum) then return false end

        local vf = myVehicleFolder()
        local pp = findDriverPrompt(vf)
        if pp then
            tpBesidePrompt(pp)
            task.wait(0.05)
            if pressPromptHard(pp, 12) then return true end
        end

        -- direct sit fallback
        local ok = pcall(function() seat:Sit(hum) end)
        if ok and seat.Occupant == hum then return true end

        -- little nudge
        if hum.RootPart then
            hum:MoveTo(seat.Position + seat.CFrame.LookVector * -0.9)
            local t0 = time()
            while time() - t0 < 1.2 do
                task.wait()
                if seat.Occupant == hum then return true end
            end
        end
        return seat.Occupant == hum
    end

    ----------------------------------------------------------------
    -- Actions
    ----------------------------------------------------------------
    local WARN_DISTANCE = 300
    local BRING_OFFSET  = CFrame.new(0, 0, -3)

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
            OrionLib:MakeNotification({Name="Vehicle", Content=("Achtung: Fahrzeug ist weit entfernt (~%d studs)."):format(dist//1), Time=3})
        end
        hrp.CFrame = ds.CFrame * CFrame.new(-2.0, 1.2, 0.0)
        task.wait(0.05)
        if enterSeat(ds) then
            OrionLib:MakeNotification({Name="Vehicle", Content="Eingestiegen.", Time=2})
        else
            OrionLib:MakeNotification({Name="Vehicle", Content="Einsteigen blockiert.", Time=3})
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

        local target = hrp.CFrame * BRING_OFFSET
        if vf:IsA("Model") and vf.PivotTo then
            pcall(function() vf:PivotTo(CFrame.new(target.Position, (hrp.Position + hrp.CFrame.LookVector))) end)
        else
            local root = (vf:IsA("Model") and vf.PrimaryPart) or ds
            if root and root:IsA("BasePart") then
                root.CFrame = target
            end
        end
        task.wait(0.05)

        if enterSeat(ds) then
            OrionLib:MakeNotification({Name="Vehicle", Content="Fahrzeug gebracht & eingestiegen.", Time=2})
        else
            OrionLib:MakeNotification({Name="Vehicle", Content="Fahrzeug gebracht, Einsteigen blockiert.", Time=3})
        end
    end

    ----------------------------------------------------------------
    -- License plate (local)
    ----------------------------------------------------------------
    local function setPlateOnGui(gui, text)
        if not (gui and text and #text>0) then return false end
        local tl = gui:FindFirstChildOfClass("TextLabel")
        if not tl then
            for _,d in ipairs(gui:GetDescendants()) do
                if d:IsA("TextLabel") then tl=d; break end
            end
        end
        if tl then tl.Text = text return true end
        return false
    end

    local function applyPlateToVehicle(vFolder, text)
        if not (vFolder and text and #text>0) then return false end
        local body = vFolder:FindFirstChild("Body", true)
        local plates = body and (body:FindFirstChild("LicensePlates", true) or body:FindFirstChild("LicencePlates", true))
        local ok = false
        if plates then
            local back  = plates:FindFirstChild("Back", true)
            local front = plates:FindFirstChild("Front", true)
            local function guiOf(node)
                return node and (node:FindFirstChild("Gui") or node:FindFirstChild("SurfaceGui") or node:FindFirstChildWhichIsA("SurfaceGui"))
            end
            ok = setPlateOnGui(guiOf(back), text) or ok
            ok = setPlateOnGui(guiOf(front), text) or ok
        end
        if not ok then
            for _,sg in ipairs(vFolder:GetDescendants()) do
                if sg:IsA("SurfaceGui") and string.lower(sg.Name):find("license") then
                    ok = setPlateOnGui(sg, text) or ok
                end
            end
        end
        return ok
    end

    local function ensurePlateForMyVehicle(timeout)
        timeout = timeout or 6
        if (CFG.plateText or "") == "" then return end
        local t0 = time()
        while time() - t0 < timeout do
            local vf = myVehicleFolder()
            if vf and applyPlateToVehicle(vf, CFG.plateText) then return true end
            task.wait(0.25)
        end
        return false
    end

    -- Reapply plates after your vehicle appears
    task.defer(function()
        pcall(ensurePlateForMyVehicle, 6)
        local root = VehiclesFolder()
        if root then
            root.ChildAdded:Connect(function(ch)
                if ch.Name == LP.Name then task.defer(function() ensurePlateForMyVehicle(6) end) end
            end)
        end
    end)

    ----------------------------------------------------------------
    -- UI
    ----------------------------------------------------------------
    local secVehicle = tab:AddSection({ Name = "Vehicle" })
    secVehicle:AddButton({ Name = "To Vehicle (auf Sitz & einsteigen)", Callback = toVehicle })
    secVehicle:AddButton({ Name = "Bring Vehicle (vor dich & einsteigen)", Callback = bringVehicle })

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
                OrionLib:MakeNotification({Name="Vehicle", Content="Konnte Kennzeichen nicht setzen.", Time=3})
            end
        end
    })

    print(("VehicleMod loaded. Dev build. Warn Distance: %d studs."):format(WARN_DISTANCE))
end
