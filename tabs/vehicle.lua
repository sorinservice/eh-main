-- tabs/vehicle.lua
return function(tab, OrionLib)
    print("Version 3.3, keine Schwebekraft mehr zum Fliegen")
    ------------------------------ services ------------------------------
    local Players     = game:GetService("Players")
    local RunService  = game:GetService("RunService")
    local UserInput   = game:GetService("UserInputService")
    local HttpService = game:GetService("HttpService")
    local Workspace   = game:GetService("Workspace")

    local LP     = Players.LocalPlayer
    local Camera = Workspace.CurrentCamera

    local function notify(t, m, s)
        OrionLib:MakeNotification({Name=t, Content=m, Time=s or 3})
    end

    ------------------------------ persist (plate) ------------------------------
    local SAVE_FOLDER = OrionLib.Folder or "SorinConfig"
    local SAVE_FILE   = SAVE_FOLDER .. "/vehicle.json"

    local function read_json(p)
        local ok, res = pcall(function()
            if isfile and isfile(p) then return HttpService:JSONDecode(readfile(p)) end
        end)
        return ok and res or nil
    end
    local function write_json(p, tbl)
        pcall(function()
            if makefolder and not isfolder(SAVE_FOLDER) then makefolder(SAVE_FOLDER) end
            if writefile then writefile(p, HttpService:JSONEncode(tbl)) end
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

    ------------------------------ helpers ------------------------------
    local function VehiclesFolder()
        return Workspace:FindFirstChild("Vehicles") or Workspace
    end

    local function myVehicleFolder()
        local vRoot = VehiclesFolder(); if not vRoot then return nil end
        local byName = vRoot:FindFirstChild(LP.Name)
        if byName then return byName end
        for _,m in ipairs(vRoot:GetChildren()) do
            if (m:IsA("Model") or m:IsA("Folder")) and (m.GetAttribute and m:GetAttribute("Owner") == LP.Name) then
                return m
            end
        end
        return nil
    end

    local function ensurePrimaryPart(model)
        if not model then return false end
        if model.PrimaryPart then return true end
        for _,d in ipairs(model:GetDescendants()) do
            if d:IsA("BasePart") then
                pcall(function() model.PrimaryPart = d end)
                if model.PrimaryPart then return true end
            end
        end
        return false
    end

    local function findDriveSeat(vf)
        if not vf then return nil end
        local s = vf:FindFirstChild("DriveSeat", true)
        if s and s:IsA("Seat") then return s end
        local seats = vf:FindFirstChild("Seats", true)
        if seats then
            for _,d in ipairs(seats:GetDescendants()) do
                if d:IsA("Seat") then return d end
            end
        end
        for _,d in ipairs(vf:GetDescendants()) do
            if d:IsA("Seat") then return d end
        end
        return nil
    end

    local function findDriverPrompt(vf)
        if not vf then return nil end
        for _,pp in ipairs(vf:GetDescendants()) do
            if pp:IsA("ProximityPrompt") then
                local a = string.lower(pp.ActionText or "")
                local o = string.lower(pp.ObjectText or "")
                if a:find("driver") or a:find("seat") or a:find("fahrer")
                or o:find("driver") or o:find("seat") or o:find("fahrer") then
                    return pp
                end
            end
        end
        return nil
    end

    local function isSeated()
        local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
        return hum and hum.SeatPart ~= nil
    end

    local function isSeatedInOwnVehicle()
        local vf = myVehicleFolder(); if not vf then return false, nil, vf end
        local seat = findDriveSeat(vf); if not seat then return false, nil, vf end
        local hum  = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
        if hum and seat.Occupant == hum then return true, seat, vf end
        return false, seat, vf
    end

    local function pressPrompt(pp, tries)
        tries = tries or 12
        if not pp then return false end
        for _=1,tries do
            if typeof(fireproximityprompt) == "function" then
                pcall(function() fireproximityprompt(pp, math.max(pp.HoldDuration or 0.15, 0.1)) end)
            else
                pp:InputHoldBegin(); task.wait(math.max(pp.HoldDuration or 0.15, 0.1)); pp:InputHoldEnd()
            end
            task.wait(0.08)
            local ok = isSeatedInOwnVehicle()
            if ok then return true end
        end
        return false
    end

    local function sitIn(seat)
        local char = LP.Character or LP.CharacterAdded:Wait()
        local hum  = char:FindFirstChildOfClass("Humanoid")
        if not (seat and hum) then return false end

        local vf = myVehicleFolder()
        local pp = vf and findDriverPrompt(vf) or nil
        if pp then
            local baseCF = CFrame.new()
            if pp.Parent then
                if pp.Parent.GetPivot then
                    baseCF = pp.Parent:GetPivot()
                elseif pp.Parent:IsA("BasePart") then
                    baseCF = CFrame.new(pp.Parent.Position)
                end
            end
            char:WaitForChild("HumanoidRootPart").CFrame = baseCF * CFrame.new(-1.2, 1.4, 0.2)
            task.wait(0.05)
            if pressPrompt(pp, 12) then return true end
        end

        local ok = pcall(function() seat:Sit(hum) end)
        if ok and seat.Occupant == hum then return true end

        if hum.RootPart then
            hum:MoveTo(seat.Position + seat.CFrame.LookVector * 1)
            local t0 = time()
            while time() - t0 < 1.2 do
                task.wait()
                if seat.Occupant == hum then return true end
            end
        end
        return seat.Occupant == hum
    end

    ------------------------------ license plate ------------------------------
    local function applyPlateTextTo(vf, txt)
        if not (vf and txt and txt ~= "") then return end
        local lpRoot = vf:FindFirstChild("LicensePlates", true) or vf:FindFirstChild("LicencePlates", true)
        local function setLabel(container)
            if not container then return end
            local gui = container:FindFirstChild("Gui", true)
            if gui and gui:FindFirstChild("TextLabel") then
                pcall(function() gui.TextLabel.Text = txt end)
            end
        end
        if lpRoot then
            setLabel(lpRoot:FindFirstChild("Back", true))
            setLabel(lpRoot:FindFirstChild("Front", true))
        else
            for _,d in ipairs(vf:GetDescendants()) do
                if d:IsA("TextLabel") then pcall(function() d.Text = txt end) end
            end
        end
    end

    local function applyPlateToCurrent()
        local vf = myVehicleFolder()
        if vf and CFG.plateText ~= "" then
            applyPlateTextTo(vf, CFG.plateText)
        end
    end

    task.spawn(function()
        local vroot = VehiclesFolder(); if not vroot then return end
        vroot.ChildAdded:Connect(function(ch)
            task.wait(0.7)
            if ch and (ch.Name == LP.Name or (ch.GetAttribute and ch:GetAttribute("Owner") == LP.Name)) and CFG.plateText ~= "" then
                applyPlateTextTo(ch, CFG.plateText)
            end
        end)
    end)

    ------------------------------ to/bring ------------------------------
    local WARN_DISTANCE = 300
    local TO_OFFSET     = CFrame.new(-2.0, 0.5, 0)
    local BRING_AHEAD   = 10
    local BRING_UP      = 2

    local function toVehicle()
        if isSeatedInOwnVehicle() then notify("Vehicle","Du sitzt bereits im Fahrzeug."); return end
        local vf = myVehicleFolder(); if not vf then notify("Vehicle","Kein eigenes Fahrzeug gefunden."); return end
        local seat = findDriveSeat(vf); if not seat then notify("Vehicle","Kein Fahrersitz gefunden."); return end
        local hrp = (LP.Character or LP.CharacterAdded:Wait()):WaitForChild("HumanoidRootPart")
        local dist = (hrp.Position - seat.Position).Magnitude
        if dist > WARN_DISTANCE then
            notify("Vehicle", ("Achtung: weit entfernt (~%d studs)."):format(math.floor(dist)), 3)
        end
        hrp.CFrame = seat.CFrame * TO_OFFSET
        task.wait(0.06)
        sitIn(seat)
    end

    local function bringVehicle()
        if isSeatedInOwnVehicle() then notify("Vehicle","Schon im Fahrzeug – Bring gesperrt."); return end
        local vf = myVehicleFolder(); if not vf then notify("Vehicle","Kein Fahrzeug gefunden."); return end
        ensurePrimaryPart(vf)
        local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        if not hrp then notify("Vehicle","Kein HRP."); return end
        local look = hrp.CFrame.LookVector
        local pos  = hrp.Position + look * BRING_AHEAD + Vector3.new(0, BRING_UP, 0)
        local cf   = CFrame.lookAt(pos, pos + look)
        pcall(function() vf:PivotTo(cf) end)
        task.wait(0.05)
        local seat = findDriveSeat(vf)
        if seat then sitIn(seat) end
    end

    ----------------------------------------------------------------------
    -- POWERDRIVE (boden-only Schub; keine Velocity-Writes; keine Hover)
    ----------------------------------------------------------------------
    local PD = {
        enabled=false, conn=nil,
        pp=nil, att=nil, vf=nil,
        accel=55,           -- studs/s^2  (per Slider)
        speedCap=85,        -- studs/s    (per Slider)
        traction=0.12       -- leichter Querdrag
    }

    local function pd_destroy()
        if PD.conn then PD.conn:Disconnect() PD.conn=nil end
        if PD.vf then PD.vf.Force = Vector3.new() end
        for _,x in ipairs({PD.vf, PD.att}) do if x and x.Parent then x:Destroy() end end
        PD.pp, PD.vf, PD.att = nil,nil,nil
        PD.enabled=false
    end

    local function pd_build(v)
        ensurePrimaryPart(v)
        local pp = v.PrimaryPart or v:FindFirstChildWhichIsA("BasePart", true)
        if not pp then return false end
        PD.pp = pp
        PD.att = Instance.new("Attachment"); PD.att.Name="Sorin_PD_Att"; PD.att.Parent=pp
        PD.vf  = Instance.new("VectorForce"); PD.vf.Name="Sorin_PD_VF"
        PD.vf.Attachment0 = PD.att
        PD.vf.RelativeTo  = Enum.ActuatorRelativeTo.World
        PD.vf.Force = Vector3.new()
        PD.vf.Parent = pp
        return true
    end

    local function projOnPlane(v, n)
        if n.Magnitude == 0 then return v end
        local u = n.Unit
        return v - u * v:Dot(u)
    end

    local function pd_toggle(state)
        if state == nil then state = not PD.enabled end
        if state == PD.enabled then return end
        if state and not isSeated() then notify("PowerDrive","Nur im Auto."); return end

        if not state then
            pd_destroy()
            notify("PowerDrive","Off")
            return
        end

        local vf = myVehicleFolder(); if not vf then notify("PowerDrive","Kein Fahrzeug."); return end
        if not pd_build(vf) then notify("PowerDrive","Kein PrimaryPart."); return end
        PD.enabled = true
        notify("PowerDrive","On")

        PD.conn = RunService.RenderStepped:Connect(function(dt)
            if not PD.enabled then return end
            if not isSeated() then pd_toggle(false) return end
            local v = myVehicleFolder(); if not v then pd_toggle(false) return end
            if not (PD.pp and PD.pp.Parent) then pd_toggle(false) return end

            -- Bodencheck
            local pivot = v:GetPivot()
            local params = RaycastParams.new()
            params.FilterType = Enum.RaycastFilterType.Blacklist
            params.FilterDescendantsInstances = {v}
            local hit = Workspace:Raycast(pivot.Position, Vector3.new(0,-8,0), params)
            if not hit then
                PD.vf.Force = Vector3.new()
                return
            end

            -- Input (nur XZ)
            local t = 0
            if UserInput:IsKeyDown(Enum.KeyCode.W) then t = t + 1 end
            if UserInput:IsKeyDown(Enum.KeyCode.S) then t = t - 1 end

            local fwd = PD.pp.CFrame.LookVector
            fwd = projOnPlane(fwd, hit.Normal)
            if fwd.Magnitude > 0 then fwd = fwd.Unit end

            local desired_a = fwd * (t * PD.accel)  -- studs/s^2
            local mass      = math.max(PD.pp.AssemblyMass, 1)

            -- Speed-Cap in Fahr­ebene
            local vel   = PD.pp.AssemblyLinearVelocity
            local vPlan = projOnPlane(vel, hit.Normal)
            if vPlan.Magnitude > PD.speedCap and (t * vPlan:Dot(fwd)) > 0 then
                desired_a = Vector3.new() -- über Cap: kein extra Schub in Fahrtrichtung
            end

            -- leichter Querdrag (sanftere Kontrolle, wirkt nur in Ebene)
            local lateral = vPlan - fwd * vPlan:Dot(fwd)
            local dragF   = -lateral * (PD.traction * mass)

            -- finale Kraft
            PD.vf.Force = desired_a * mass + dragF
        end)
    end

    ------------------------------ UI ------------------------------
    local secV  = tab:AddSection({ Name = "Vehicle" })
    secV:AddButton({ Name = "To Vehicle (auf Sitz & einsteigen)", Callback = toVehicle })
    secV:AddButton({ Name = "Bring Vehicle (vor dich & einsteigen)", Callback = bringVehicle })
    secV:AddTextbox({
        Name = "Kennzeichen-Text",
        Default = CFG.plateText,
        TextDisappear = false,
        Callback = function(txt) CFG.plateText = tostring(txt or ""); save_cfg() end
    })
    secV:AddButton({ Name = "Kennzeichen anwenden (aktuelles Fahrzeug)", Callback = applyPlateToCurrent })

    local secPD = tab:AddSection({ Name = "PowerDrive (Boden-Boost)" })
    secPD:AddToggle({
        Name = "PowerDrive aktivieren",
        Default = false,
        Callback = function(v) pd_toggle(v) end
    })
    secPD:AddSlider({
        Name = "Beschleunigung (stud/s^2)",
        Min = 20, Max = 150, Increment = 5,
        Default = PD.accel,
        Callback = function(val) PD.accel = math.floor(val) end
    })
    secPD:AddSlider({
        Name = "Speed-Cap (stud/s)",
        Min = 30, Max = 200, Increment = 5,
        Default = PD.speedCap,
        Callback = function(val) PD.speedCap = math.floor(val) end
    })
    secPD:AddSlider({
        Name = "Traction (Quer-Dämpfung)",
        Min = 0, Max = 0.5, Increment = 0.01,
        Default = PD.traction,
        Callback = function(val) PD.traction = tonumber(val) or PD.traction end
    })

    -- Safety: disable PD when you leave the seat
    RunService.Heartbeat:Connect(function()
        if PD.enabled and not isSeated() then pd_toggle(false) end
    end)
end
