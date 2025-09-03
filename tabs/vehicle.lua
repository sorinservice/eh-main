-- tabs/vehicle.lua
return function(tab, OrionLib)
    print("Version 3.4 — PowerDrive persists + AirFly (forces, no anchors/vel writes)")

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

    -- zusätzlich: beim Join nach kurzer Zeit auf aktuelles Fahrzeug anwenden
    task.defer(function()
        if CFG.plateText ~= "" then
            task.wait(1.0)
            pcall(applyPlateToCurrent)
        end
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
    -- POWERDRIVE (boden-only Schub; persistiert über Sitzwechsel)
    ----------------------------------------------------------------------
    local PD = {
        wanted=false, enabled=false, conn=nil, vf=nil, att=nil, pp=nil,
        accel=55,           -- studs/s^2 (UI)
        speedCap=120        -- feste Obergrenze, kein Slider (sicherer)
    }

    local function pd_teardown()
        if PD.conn then PD.conn:Disconnect() PD.conn=nil end
        if PD.vf then PD.vf.Force = Vector3.new() end
        for _,x in ipairs({PD.vf, PD.att}) do if x and x.Parent then x:Destroy() end end
        PD.vf, PD.att, PD.pp = nil, nil, nil
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
        PD.enabled = true
        return true
    end

    local function projOnPlane(v, n)
        if n.Magnitude == 0 then return v end
        local u = n.Unit
        return v - u * v:Dot(u)
    end

    local function pd_setWanted(on)
        PD.wanted = on and true or false
        if not PD.wanted then
            pd_teardown()
            notify("PowerDrive","Off")
            return
        end
        -- exklusiv zu AirFly
        _G.__Sorin_AirFlyWanted = false
        if AirFly and AirFly.setWanted then AirFly.setWanted(false) end

        if isSeated() then
            local v = myVehicleFolder(); if not v then notify("PowerDrive","Kein Fahrzeug."); return end
            if pd_build(v) then notify("PowerDrive","On") end
        else
            notify("PowerDrive","Armed (aktiviert bei Einstieg)")
        end
    end

    -- Lauf-Update
    local function pd_step(dt)
        if not PD.enabled then return end
        if not isSeated() then pd_teardown(); return end
        local v = myVehicleFolder(); if not v then pd_teardown(); return end
        if not (PD.pp and PD.pp.Parent) then pd_teardown(); return end

        -- Bodenkontakt prüfen
        local pivot = v:GetPivot()
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Blacklist
        params.FilterDescendantsInstances = {v}
        local hit = Workspace:Raycast(pivot.Position, Vector3.new(0,-8,0), params)
        if not hit then
            PD.vf.Force = Vector3.new()
            return
        end

        -- Input (nur vor/zurück)
        local t = 0
        if UserInput:IsKeyDown(Enum.KeyCode.W) then t = t + 1 end
        if UserInput:IsKeyDown(Enum.KeyCode.S) then t = t - 1 end

        local fwd = PD.pp.CFrame.LookVector
        fwd = projOnPlane(fwd, hit.Normal)
        if fwd.Magnitude > 0 then fwd = fwd.Unit end

        local mass = math.max(PD.pp.AssemblyMass, 1)
        local desired_a = fwd * (t * PD.accel)  -- studs/s^2

        -- Speed-Cap in Ebene
        local vel   = PD.pp.AssemblyLinearVelocity
        local vPlan = projOnPlane(vel, hit.Normal)
        if vPlan.Magnitude > PD.speedCap and (t * vPlan:Dot(fwd)) > 0 then
            desired_a = Vector3.new()
        end

        PD.vf.Force = desired_a * mass
    end

    -- Sitz-/Heartbeat-Logik für Persistenz
    RunService.Heartbeat:Connect(function()
        -- Reattach wenn gewünscht & im Sitz & noch nicht aktiv
        if PD.wanted and (not PD.enabled) and isSeated() then
            local v = myVehicleFolder()
            if v then pd_build(v) end
        end
    end)
    RunService.RenderStepped:Connect(pd_step)

    ----------------------------------------------------------------------
    -- AIRFLY (echtes Fliegen; forces + orientation; persistiert)
    ----------------------------------------------------------------------
    AirFly = AirFly or {} -- für exklusives Ausschalten mit PD
    do
        local AF = {
            wanted=false, enabled=false, conn=nil,
            pp=nil, att=nil, ao=nil, thrust=nil, lift=nil, drag=nil,

            thrustAccel = 60,     -- Schub (UI)
            liftK       = 1.0,    -- Auftrieb ~ v^2 * k  (intern fix)
            dragK       = 0.02,   -- Luftwiderstand ~ v^2  (intern fix)
            maxPitchDeg = 25,     -- Pitch-Grenze
            aoResp      = 22,     -- Ausrichtung
            speedCap    = 180,    -- harte Kappe
            aCap        = 80      -- Beschl.-Kappe (Sicherheitsnetz)
        }

        local function af_teardown()
            if AF.conn then AF.conn:Disconnect() AF.conn=nil end
            for _,x in ipairs({AF.thrust, AF.lift, AF.drag}) do
                if x then pcall(function() x.Force = Vector3.new() end) end
            end
            for _,inst in ipairs({AF.ao, AF.thrust, AF.lift, AF.drag, AF.att}) do
                if inst and inst.Parent then inst:Destroy() end
            end
            AF.pp, AF.att, AF.ao, AF.thrust, AF.lift, AF.drag = nil,nil,nil,nil,nil,nil
            AF.enabled=false
        end

        local function af_build(v)
            ensurePrimaryPart(v)
            local pp = v.PrimaryPart or v:FindFirstChildWhichIsA("BasePart", true)
            if not pp then return false end
            AF.pp = pp

            AF.att = Instance.new("Attachment"); AF.att.Name="Sorin_AF_Att"; AF.att.Parent=pp

            AF.ao = Instance.new("AlignOrientation")
            AF.ao.Name="Sorin_AF_AO"
            AF.ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
            AF.ao.Attachment0 = AF.att
            AF.ao.Responsiveness = AF.aoResp
            AF.ao.MaxTorque = math.huge
            AF.ao.RigidityEnabled = false
            AF.ao.Parent = pp

            AF.thrust = Instance.new("VectorForce")
            AF.thrust.Name="Sorin_AF_Thrust"
            AF.thrust.Attachment0 = AF.att
            AF.thrust.RelativeTo  = Enum.ActuatorRelativeTo.World
            AF.thrust.Force = Vector3.new()
            AF.thrust.Parent = pp

            AF.lift = Instance.new("VectorForce")
            AF.lift.Name="Sorin_AF_Lift"
            AF.lift.Attachment0 = AF.att
            AF.lift.RelativeTo  = Enum.ActuatorRelativeTo.World
            AF.lift.Force = Vector3.new()
            AF.lift.Parent = pp

            AF.drag = Instance.new("VectorForce")
            AF.drag.Name="Sorin_AF_Drag"
            AF.drag.Attachment0 = AF.att
            AF.drag.RelativeTo  = Enum.ActuatorRelativeTo.World
            AF.drag.Force = Vector3.new()
            AF.drag.Parent = pp

            AF.enabled=true
            return true
        end

        local function af_setWanted(on)
            AF.wanted = on and true or false
            if not AF.wanted then
                af_teardown()
                _G.__Sorin_AirFlyWanted = false
                notify("AirFly","Off")
                return
            end
            -- exklusiv zu PowerDrive
            PD.wanted = false
            pd_teardown()

            _G.__Sorin_AirFlyWanted = true
            if isSeated() then
                local v = myVehicleFolder(); if not v then notify("AirFly","Kein Fahrzeug."); return end
                if af_build(v) then notify("AirFly","On") end
            else
                notify("AirFly","Armed (aktiviert bei Einstieg)")
            end
        end

        AirFly.setWanted = af_setWanted

        local function af_step(dt)
            if not AF.enabled then return end
            if not isSeated() then af_teardown(); return end
            local v = myVehicleFolder(); if not v then af_teardown(); return end
            local pp = AF.pp; if not (pp and pp.Parent) then af_teardown(); return end

            -- Eingaben
            local throttle = (UserInput:IsKeyDown(Enum.KeyCode.W) and 1 or 0)
                            - (UserInput:IsKeyDown(Enum.KeyCode.S) and 1 or 0)
            local pitchIn  = (UserInput:IsKeyDown(Enum.KeyCode.E) or UserInput:IsKeyDown(Enum.KeyCode.Space)) and -1 or 0
            pitchIn        = pitchIn + ((UserInput:IsKeyDown(Enum.KeyCode.Q) or UserInput:IsKeyDown(Enum.KeyCode.LeftControl)) and 1 or 0)

            -- Ausrichtung (Yaw zu Kamera, Pitch über Tasten)
            local camLV = Camera.CFrame.LookVector
            local yaw   = math.atan2(camLV.X, camLV.Z)
            local yawCF   = CFrame.fromAxisAngle(Vector3.new(0,1,0), yaw)
            local pitchCF = CFrame.Angles(math.rad(math.clamp(pitchIn*AF.maxPitchDeg, -AF.maxPitchDeg, AF.maxPitchDeg)), 0, 0)
            AF.ao.CFrame = yawCF * pitchCF

            -- Basisgrößen
            local mass   = math.max(pp.AssemblyMass, 1)
            local g      = Workspace.Gravity
            local fwd    = pp.CFrame.LookVector
            local up     = pp.CFrame.UpVector
            local vel    = pp.AssemblyLinearVelocity
            local speed  = vel.Magnitude

            if speed > AF.speedCap then
                AF.dragK = math.max(AF.dragK, 0.03)
            end

            -- Kräfte
            local thrustF = (throttle ~= 0) and (fwd * (AF.thrustAccel * throttle * mass)) or Vector3.new()

            -- Lift nur mit Fahrt – kein Hover
            local liftMag = (speed > 8) and (AF.liftK * speed * speed) or 0
            local liftCap = mass * g * 1.15
            if liftMag > liftCap then liftMag = liftCap end
            local liftF = up * liftMag

            local dragF = Vector3.new()
            if speed > 1e-3 then dragF = -vel.Unit * (AF.dragK * speed * speed) end

            -- Gesamtbeschl.-Kappe
            local acc = (thrustF + liftF + dragF) / mass
            if acc.Magnitude > AF.aCap then
                local s = AF.aCap / acc.Magnitude
                thrustF = thrustF * s; liftF = liftF * s; dragF = dragF * s
            end

            AF.thrust.Force = thrustF
            AF.lift.Force   = liftF
            AF.drag.Force   = dragF
        end

        -- Persistenz/Attach bei Einstieg
        RunService.Heartbeat:Connect(function()
            if AF.wanted and (not AF.enabled) and isSeated() then
                local v = myVehicleFolder()
                if v then af_build(v) end
            end
        end)
        RunService.RenderStepped:Connect(af_step)

        -- === UI ===
        local secF = tab:AddSection({ Name = "AirFly (Fliegen)" })
        local flyToggle
        flyToggle = secF:AddToggle({
            Name = "AirFly aktivieren (nur im Auto)",
            Default = false,
            Callback = function(on)
                af_setWanted(on)
                if flyToggle then flyToggle:Set(AF.wanted) end
            end
        })
        secF:AddBind({
            Name = "AirFly Toggle Key",
            Default = Enum.KeyCode.X,
            Hold = false,
            Callback = function()
                af_setWanted(not AF.wanted)
                if flyToggle then flyToggle:Set(AF.wanted) end
            end
        })
        secF:AddSlider({
            Name = "Schub (Beschleunigung)",
            Min = 20, Max = 140, Increment = 5,
            Default = 60,
            Callback = function(v) AF.thrustAccel = math.floor(v) end
        })
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
    local pdToggle
    pdToggle = secPD:AddToggle({
        Name = "PowerDrive aktivieren",
        Default = false,
        Callback = function(v)
            -- exklusiv zu AirFly
            if v then
                if AirFly and AirFly.setWanted then AirFly.setWanted(false) end
            end
            pd_setWanted(v)
            if pdToggle then pdToggle:Set(PD.wanted) end
        end
    })
    secPD:AddSlider({
        Name = "Beschleunigung (stud/s^2)",
        Min = 20, Max = 150, Increment = 5,
        Default = PD.accel,
        Callback = function(val) PD.accel = math.floor(val) end
    })

end
