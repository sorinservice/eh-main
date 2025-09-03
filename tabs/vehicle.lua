-- tabs/vehicle.lua
return function(tab, OrionLib)
    print("Version 3.3 DEV (Fly+PowerDrive, impulse-only)")

    -- Services / locals
    local Players     = game:GetService("Players")
    local RunService  = game:GetService("RunService")
    local UserInput   = game:GetService("UserInputService")
    local HttpService = game:GetService("HttpService")
    local Workspace   = game:GetService("Workspace")

    local LP     = Players.LocalPlayer
    local Camera = Workspace.CurrentCamera
    local function notify(title, msg, t) OrionLib:MakeNotification({Name=title,Content=msg,Time=t or 3}) end

    -- Persistenz (Kennzeichen)
    local SAVE_FOLDER = OrionLib.Folder or "SorinConfig"
    local SAVE_FILE   = SAVE_FOLDER .. "/vehicle.json"
    local function read_json(path)
        local ok, res = pcall(function()
            if isfile and isfile(path) then return HttpService:JSONDecode(readfile(path)) end
        end)
        return ok and res or nil
    end
    local function write_json(path, tbl)
        pcall(function()
            if makefolder and not isfolder(SAVE_FOLDER) then makefolder(SAVE_FOLDER) end
            if writefile then writefile(path, HttpService:JSONEncode(tbl)) end
        end)
    end
    local CFG = { plateText = "" }
    do local saved = read_json(SAVE_FILE); if type(saved)=="table" and type(saved.plateText)=="string" then CFG.plateText=saved.plateText end end
    local function save_cfg() write_json(SAVE_FILE, { plateText = CFG.plateText }) end

    -- Vehicle helpers
    local function VehiclesFolder() return Workspace:FindFirstChild("Vehicles") or Workspace end
    local function myVehicleFolder()
        local vRoot = VehiclesFolder() ; if not vRoot then return nil end
        local byName = vRoot:FindFirstChild(LP.Name) ; if byName then return byName end
        for _,m in ipairs(vRoot:GetChildren()) do
            if (m:IsA("Model") or m:IsA("Folder")) and (m.GetAttribute and m:GetAttribute("Owner")==LP.Name) then return m end
        end
        return nil
    end
    local function ensurePrimaryPart(model)
        if not model then return false end
        if model.PrimaryPart then return true end
        for _,d in ipairs(model:GetDescendants()) do
            if d:IsA("BasePart") then pcall(function() model.PrimaryPart=d end) ; if model.PrimaryPart then return true end end
        end
        return false
    end
    local function findDriveSeat(vf)
        if not vf then return nil end
        local s = vf:FindFirstChild("DriveSeat", true) ; if s and s:IsA("Seat") then return s end
        local seats = vf:FindFirstChild("Seats", true)
        if seats then for _,d in ipairs(seats:GetDescendants()) do if d:IsA("Seat") then return d end end end
        for _,d in ipairs(vf:GetDescendants()) do if d:IsA("Seat") then return d end end
        return nil
    end
    local function findDriverPrompt(vf)
        if not vf then return nil end
        for _,pp in ipairs(vf:GetDescendants()) do
            if pp:IsA("ProximityPrompt") then
                local a = string.lower(pp.ActionText or ""); local o = string.lower(pp.ObjectText or "")
                if a:find("driver") or a:find("seat") or a:find("fahrer") or o:find("driver") or o:find("seat") or o:find("fahrer") then return pp end
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
            if typeof(fireproximityprompt)=="function" then
                pcall(function() fireproximityprompt(pp, math.max(pp.HoldDuration or 0.15, 0.1)) end)
            else
                pp:InputHoldBegin(); task.wait(math.max(pp.HoldDuration or 0.15, 0.1)); pp:InputHoldEnd()
            end
            task.wait(0.08)
            if isSeatedInOwnVehicle() then return true end
        end
        return false
    end
    local function sitIn(seat)
        local char = LP.Character or LP.CharacterAdded:Wait()
        local hum  = char:FindFirstChildOfClass("Humanoid"); if not (seat and hum) then return false end
        local vf = myVehicleFolder(); local pp = vf and findDriverPrompt(vf) or nil
        if pp then
            local baseCF = CFrame.new()
            if pp.Parent then
                if pp.Parent.GetPivot then baseCF = pp.Parent:GetPivot()
                elseif pp.Parent:IsA("BasePart") then baseCF = CFrame.new(pp.Parent.Position) end
            end
            char:WaitForChild("HumanoidRootPart").CFrame = baseCF * CFrame.new(-1.2, 1.4, 0.2)
            task.wait(0.05); if pressPrompt(pp, 12) then return true end
        end
        local ok = pcall(function() seat:Sit(hum) end)
        if ok and seat.Occupant==hum then return true end
        if hum.RootPart then
            hum:MoveTo(seat.Position + seat.CFrame.LookVector * 1)
            local t0 = time()
            while time()-t0<1.2 do task.wait(); if seat.Occupant==hum then return true end end
        end
        return seat.Occupant==hum
    end

    -- License Plate
    local function applyPlateTextTo(vf, txt)
        if not (vf and txt and txt~="") then return end
        local lpRoot = vf:FindFirstChild("LicensePlates", true) or vf:FindFirstChild("LicencePlates", true)
        local function setLabel(container)
            if not container then return end
            local gui = container:FindFirstChild("Gui", true)
            if gui and gui:FindFirstChild("TextLabel") then pcall(function() gui.TextLabel.Text = txt end) end
        end
        if lpRoot then setLabel(lpRoot:FindFirstChild("Back", true)); setLabel(lpRoot:FindFirstChild("Front", true))
        else for _,d in ipairs(vf:GetDescendants()) do if d:IsA("TextLabel") then pcall(function() d.Text=txt end) end end end
    end
    local function applyPlateToCurrent()
        local vf = myVehicleFolder()
        if vf and CFG.plateText~="" then applyPlateTextTo(vf, CFG.plateText) end
    end
    task.spawn(function()
        local vroot = VehiclesFolder(); if not vroot then return end
        vroot.ChildAdded:Connect(function(ch)
            task.wait(0.7)
            if ch and (ch.Name==LP.Name or (ch.GetAttribute and ch:GetAttribute("Owner")==LP.Name)) and CFG.plateText~="" then
                applyPlateTextTo(ch, CFG.plateText)
            end
        end)
    end)

    -- To / Bring Vehicle
    local WARN_DISTANCE=300; local TO_OFFSET=CFrame.new(-2.0,0.5,0); local BRING_AHEAD=10; local BRING_UP=2
    local function toVehicle()
        if isSeatedInOwnVehicle() then notify("Vehicle","Schon im Fahrzeug."); return end
        if _G.__Sorin_FlyActive then notify("Vehicle","Car Fly aktiv – zuerst deaktivieren."); return end
        local vf = myVehicleFolder(); if not vf then notify("Vehicle","Kein eigenes Fahrzeug."); return end
        local seat = findDriveSeat(vf); if not seat then notify("Vehicle","Kein Fahrersitz."); return end
        local hrp = (LP.Character or LP.CharacterAdded:Wait()):WaitForChild("HumanoidRootPart")
        local dist = (hrp.Position - seat.Position).Magnitude
        if dist > WARN_DISTANCE then notify("Vehicle",("weit entfernt (~%d studs)"):format(math.floor(dist)),3) end
        hrp.CFrame = seat.CFrame * TO_OFFSET; task.wait(0.06); sitIn(seat)
    end
    local function bringVehicle()
        if isSeatedInOwnVehicle() then notify("Vehicle","Schon im Fahrzeug – Bring gesperrt."); return end
        if _G.__Sorin_FlyActive then notify("Vehicle","Car Fly aktiv – zuerst deaktivieren."); return end
        local vf = myVehicleFolder(); if not vf then notify("Vehicle","Kein Fahrzeug."); return end
        ensurePrimaryPart(vf)
        local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart"); if not hrp then notify("Vehicle","Kein HRP."); return end
        local look = hrp.CFrame.LookVector; local pos = hrp.Position + look*BRING_AHEAD + Vector3.new(0,BRING_UP,0)
        local cf = CFrame.lookAt(pos, pos + look); pcall(function() vf:PivotTo(cf) end)
        task.wait(0.05); local seat = findDriveSeat(vf); if seat then sitIn(seat) end
    end

    ------------------------------------------------------------------------
    -- Car Fly (impulse-based; Hover + vertikal)
    ------------------------------------------------------------------------
    local flyEnabled=false, flySpeed=130, safeFly=false, flyConn=nil, flyToggleUI=nil
    local savedFlags={}, lastAirCF=nil, toggleLockTS=0, fullNoClip=false, groundLock=false, exitBlockUntil=0
    local A_MAX=60; local CLIMB_MAX=40; local JERK_SMOOTH=0.15; local GROUND_PROBE=5; local LIFTOFF_NUDGE=2.5
    local Y_BIAS_NEAR_GND=0.35; local YAW_K=2.0; local YAW_CLAMP=0.25

    local function forEachPart(vf, fn) if not vf then return end for _,p in ipairs(vf:GetDescendants()) do if p:IsA("BasePart") then fn(p) end end end
    local function zeroMotion(vf) forEachPart(vf, function(bp) bp.AssemblyLinearVelocity=Vector3.new(); bp.AssemblyAngularVelocity=Vector3.new() end) end
    local function applyFlyCollision(vf) -- keeps UI toggle compatible; only effective while physics saved
        if not vf then return end
        forEachPart(vf, function(bp) if savedFlags[bp] then bp.CanCollide = not fullNoClip end end)
    end
    local function setFlightPhysics(vf, on)
        if not vf then return end
        if on then
            savedFlags = {}
            forEachPart(vf, function(bp)
                savedFlags[bp] = {Anchored=bp.Anchored, CanCollide=bp.CanCollide}
                bp.Anchored=false; bp.AssemblyLinearVelocity=Vector3.new(); bp.AssemblyAngularVelocity=Vector3.new()
            end)
        else
            for bp,fl in pairs(savedFlags) do
                if bp and bp.Parent then
                    bp.Anchored=fl.Anchored; bp.CanCollide=fl.CanCollide
                    bp.AssemblyLinearVelocity=Vector3.new(0,-10,0); bp.AssemblyAngularVelocity=Vector3.new()
                end
            end
            savedFlags={}
        end
    end
    local function settleToGround(v)
        if not v then return end
        local cf=v:GetPivot(); local params=RaycastParams.new(); params.FilterType=Enum.RaycastFilterType.Blacklist; params.FilterDescendantsInstances={v}
        local hit=Workspace:Raycast(cf.Position, Vector3.new(0,-1000,0), params)
        if hit then pcall(function() v:PivotTo(CFrame.new(hit.Position+Vector3.new(0,3,0), hit.Position+Vector3.new(0,3,0)+Camera.CFrame.LookVector)) end)
        else pcall(function() v:PivotTo(cf + Vector3.new(0,-2,0)) end) end
        pcall(function() v:PivotTo(v:GetPivot()+Vector3.new(0,1.5,0)) end)
    end
    RunService.Heartbeat:Connect(function()
        local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
        if not hum then return end
        if hum.SeatPart==nil and os.clock()<exitBlockUntil then local _,seat=isSeatedInOwnVehicle(); if seat then sitIn(seat) end end
    end)
    local function signedYawError(forward, desired)
        local f=Vector3.new(forward.X,0,forward.Z); if f.Magnitude==0 then return 0 end
        local d=Vector3.new(desired.X,0,desired.Z); if d.Magnitude==0 then return 0 end
        f=f.Unit; d=d.Unit; local ang=math.acos(math.clamp(f:Dot(d),-1,1)); local s=((f:Cross(d)).Y>=0) and 1 or -1
        return math.clamp(ang*s, -YAW_CLAMP, YAW_CLAMP)
    end
    local function clampVecLength(v, maxLen) local m=v.Magnitude; if m<=maxLen then return v end; return v*(maxLen/math.max(m,1e-9)) end

    -- Mobile hold flags (used by loops; set in pads)
    local mobileFlyHold = {F=false,B=false,L=false,R=false,U=false,D=false}
    local mobileDriveHold = {F=false,B=false,L=false,R=false}

    local function toggleFly(state)
        local now=os.clock(); if now-toggleLockTS<0.08 then return end; toggleLockTS=now
        if state==nil then state=not flyEnabled end
        if state and not isSeated() then notify("Car Fly","Nur im Auto nutzbar."); if flyToggleUI then flyToggleUI:Set(false) end; return end
        if state==flyEnabled then return end
        flyEnabled=state; _G.__Sorin_FlyActive=flyEnabled; if flyToggleUI then flyToggleUI:Set(flyEnabled) end
        if flyConn then flyConn:Disconnect(); flyConn=nil end

        local vf=myVehicleFolder(); if not vf then flyEnabled=false; _G.__Sorin_FlyActive=false; if flyToggleUI then flyToggleUI:Set(false) end; notify("Car Fly","Kein Fahrzeug."); return end
        ensurePrimaryPart(vf); local pp=vf.PrimaryPart or vf:FindFirstChildWhichIsA("BasePart", true)
        if not pp then flyEnabled=false; _G.__Sorin_FlyActive=false; if flyToggleUI then flyToggleUI:Set(false) end; notify("Car Fly","Kein PrimaryPart."); return end

        if not flyEnabled then setFlightPhysics(vf,false); settleToGround(vf); exitBlockUntil=os.clock()+2; notify("Car Fly","Deaktiviert."); return end
        setFlightPhysics(vf,true)
        do local cf=vf:GetPivot(); pcall(function() vf:PivotTo(cf+Vector3.new(0,LIFTOFF_NUDGE,0)) end) end
        lastAirCF=vf:GetPivot(); exitBlockUntil=os.clock()+2; notify("Car Fly",("Aktiviert (Speed %d)"):format(flySpeed))

        local smoothed=Vector3.new()
        flyConn=RunService.RenderStepped:Connect(function(dt)
            if not flyEnabled or groundLock then return end
            if not isSeated() then toggleFly(false); return end
            local v=myVehicleFolder(); if not v then return end
            local rootCF=v:GetPivot(); local ppNow=v.PrimaryPart or pp; if not ppNow then return end
            local upKey   = UserInput:IsKeyDown(Enum.KeyCode.E) or UserInput:IsKeyDown(Enum.KeyCode.Space) or mobileFlyHold.U
            local downKey = UserInput:IsKeyDown(Enum.KeyCode.Q) or UserInput:IsKeyDown(Enum.KeyCode.LeftControl) or mobileFlyHold.D

            local dir=Vector3.zero
            if UserInput:IsKeyDown(Enum.KeyCode.W) or mobileFlyHold.F then dir += Camera.CFrame.LookVector end
            if UserInput:IsKeyDown(Enum.KeyCode.S) or mobileFlyHold.B then dir -= Camera.CFrame.LookVector end
            if UserInput:IsKeyDown(Enum.KeyCode.D) or mobileFlyHold.R then dir += Camera.CFrame.RightVector end
            if UserInput:IsKeyDown(Enum.KeyCode.A) or mobileFlyHold.L then dir -= Camera.CFrame.RightVector end
            if upKey   then dir += Vector3.new(0,1,0) end
            if downKey then dir -= Vector3.new(0,1,0) end

            do -- Bodenbias
                local params=RaycastParams.new(); params.FilterType=Enum.RaycastFilterType.Blacklist; params.FilterDescendantsInstances={v}
                local hit=Workspace:Raycast(rootCF.Position, Vector3.new(0,-GROUND_PROBE,0), params)
                if hit and not downKey then dir += Vector3.new(0,Y_BIAS_NEAR_GND,0) end
            end

            local target=(dir.Magnitude>0) and (dir.Unit*flySpeed) or Vector3.new()
            if target.Y> CLIMB_MAX then target=Vector3.new(target.X, CLIMB_MAX, target.Z) end
            if target.Y<-CLIMB_MAX then target=Vector3.new(target.X,-CLIMB_MAX, target.Z) end
            smoothed = smoothed:Lerp(target, JERK_SMOOTH)

            do -- Hover
                local mass=math.max(ppNow.AssemblyMass,1); local g=Workspace.Gravity; local support=downKey and 0.35 or 1.0
                ppNow:ApplyImpulse(Vector3.new(0, mass*g*dt*support, 0))
            end
            do -- Δv Budget
                local curVel=ppNow.AssemblyLinearVelocity; local dv=smoothed-curVel
                local dvCap=clampVecLength(dv, A_MAX*math.max(dt,1/240))
                if dvCap.Magnitude>1e-5 then ppNow:ApplyImpulse(dvCap*math.max(ppNow.AssemblyMass,1)) end
            end
            do -- Yaw zur Kamera
                local yawErr=signedYawError(rootCF.LookVector, Camera.CFrame.LookVector)
                if math.abs(yawErr)>1e-3 then ppNow:ApplyAngularImpulse(Vector3.new(0, yawErr*YAW_K*math.max(ppNow.AssemblyMass,1), 0)) end
            end
            lastAirCF=v:GetPivot()
        end)

        -- SafeFly
        task.spawn(function()
            while flyEnabled do
                if not safeFly then task.wait(0.25) else
                    task.wait(6); if not flyEnabled then break end
                    local v=myVehicleFolder(); if not v then break end
                    ensurePrimaryPart(v); local ppNow=v.PrimaryPart or pp; if not ppNow then break end
                    groundLock=true
                    ppNow:ApplyImpulse(-ppNow.AssemblyLinearVelocity*math.max(ppNow.AssemblyMass,1))
                    zeroMotion(v); setFlightPhysics(v,false); settleToGround(v); task.wait(0.5)
                    if not flyEnabled then return end
                    setFlightPhysics(v,true); lastAirCF=v:GetPivot(); groundLock=false; exitBlockUntil=os.clock()+2
                end
            end
        end)
    end
    RunService.Heartbeat:Connect(function() if flyEnabled and not isSeated() then toggleFly(false) end end)

    ------------------------------------------------------------------------
    -- Power Drive (Impuls-Fahren bei Motor aus, am Boden)
    ------------------------------------------------------------------------
    local driveEnabled=false, driveConn=nil
    local driveSpeed=65                -- Ziel-Top-Speed (horiz.)
    local DRIVE_A_MAX=50              -- max Beschl. [stud/s^2]
    local STEER_K=2.2                 -- Lenkstärke (Yaw-Impulse)
    local STEER_CLAMP=0.35            -- Max yaw pro Tick (rad)
    local ROLLING_DAMP=0.25           -- Passiv-Bremse wenn kein Gas
    local steerAssistCamera=true      -- optional Kamera-orientiert drehen

    local function clamp(v, lo, hi) return (v<lo) and lo or ((v>hi) and hi or v) end

    local function toggleDrive(state)
        if state==nil then state=not driveEnabled end
        if state and not isSeated() then notify("Power Drive","Nur im Auto."); return end
        if state==driveEnabled then return end
        driveEnabled=state
        if driveConn then driveConn:Disconnect(); driveConn=nil end
        if not driveEnabled then notify("Power Drive","Aus."); return end

        notify("Power Drive","An (Impuls-Fahren).")
        local smoothVel = Vector3.new()

        driveConn = RunService.RenderStepped:Connect(function(dt)
            if not driveEnabled then return end
            if flyEnabled then return end  -- nicht doppeln
            if not isSeated() then driveEnabled=false; return end

            local v=myVehicleFolder(); if not v then return end
            local pp=v.PrimaryPart; if not pp then return end
            local mass=math.max(pp.AssemblyMass,1)
            local rootCF=v:GetPivot()

            -- Inputs
            local forward=0
            if UserInput:IsKeyDown(Enum.KeyCode.W) or mobileDriveHold.F then forward = forward + 1 end
            if UserInput:IsKeyDown(Enum.KeyCode.S) or mobileDriveHold.B then forward = forward - 1 end
            local steer=0
            if UserInput:IsKeyDown(Enum.KeyCode.D) or mobileDriveHold.R then steer = steer + 1 end
            if UserInput:IsKeyDown(Enum.KeyCode.A) or mobileDriveHold.L then steer = steer - 1 end

            -- Forward-Richtung (Fahrzeug-Look auf XZ)
            local fwd = Vector3.new(rootCF.LookVector.X, 0, rootCF.LookVector.Z)
            if fwd.Magnitude < 1e-3 then
                local camF = Camera.CFrame.LookVector
                fwd = Vector3.new(camF.X,0,camF.Z)
            end
            fwd = fwd.Unit

            -- Zielgeschwindigkeit horizontal
            local targetH = (forward ~= 0) and (fwd * (driveSpeed * forward)) or Vector3.new()
            smoothVel = smoothVel:Lerp(targetH, 0.18)

            -- Δv Budget -> Impuls
            local vel = pp.AssemblyLinearVelocity
            local curH = Vector3.new(vel.X,0,vel.Z)
            local dvH  = smoothVel - curH
            local dvCap= dvH
            local aMax = DRIVE_A_MAX * math.max(dt, 1/240)
            local m = dvCap.Magnitude
            if m > aMax then dvCap = dvCap * (aMax / m) end
            if dvCap.Magnitude > 1e-5 then pp:ApplyImpulse(dvCap * mass) end

            -- Passive Dämpfung wenn kein Gas
            if forward == 0 and curH.Magnitude > 0.1 then
                local damp = clamp(curH.Magnitude * ROLLING_DAMP, 0, DRIVE_A_MAX) * math.max(dt,1/240)
                pp:ApplyImpulse(-curH.Unit * damp * mass)
            end

            -- Lenken → Yaw-Impulse (optional zur Kamera ausrichten)
            local desiredYawErr = 0
            if steerAssistCamera then
                local desiredF = Camera.CFrame.LookVector
                desiredYawErr = signedYawError(rootCF.LookVector, desiredF)
            end
            -- aktives Lenken
            local steerErr = clamp(steer * STEER_CLAMP + desiredYawErr*0.35, -STEER_CLAMP, STEER_CLAMP)
            if math.abs(steerErr) > 1e-3 then
                pp:ApplyAngularImpulse(Vector3.new(0, steerErr * STEER_K * mass, 0))
            end
        end)
    end

    ------------------------------------------------------------------------
    -- Mobile Pads (setzen nur Hold-Flags)
    ------------------------------------------------------------------------
    local function spawnMobileFly()
        local gui = Instance.new("ScreenGui")
        gui.Name = "Sorin_MobileFly"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true
        gui.Enabled = false; gui.Parent = game:GetService("CoreGui")

        local frame = Instance.new("Frame"); frame.Size=UDim2.fromOffset(230,160); frame.Position=UDim2.fromOffset(40,300)
        frame.BackgroundColor3=Color3.fromRGB(25,25,25); frame.Parent=gui; Instance.new("UICorner",frame).CornerRadius=UDim.new(0,12)
        local title=Instance.new("TextLabel"); title.Size=UDim2.new(1,-10,0,22); title.Position=UDim2.fromOffset(10,6)
        title.BackgroundTransparency=1; title.Font=Enum.Font.GothamBold; title.TextSize=14; title.TextColor3=Color3.fromRGB(240,240,240)
        title.TextXAlignment=Enum.TextXAlignment.Left; title.Text="Car Fly"; title.Parent=frame

        local function mkBtn(txt,x,y,w,h,key)
            local b=Instance.new("TextButton"); b.Size=UDim2.fromOffset(w,h); b.Position=UDim2.fromOffset(x,y); b.Text=txt
            b.BackgroundColor3=Color3.fromRGB(40,40,40); b.TextColor3=Color3.fromRGB(230,230,230); b.Font=Enum.Font.GothamSemibold; b.TextSize=14; b.Parent=frame
            Instance.new("UICorner",b).CornerRadius=UDim.new(0,8)
            b.MouseButton1Down:Connect(function() if not isSeated() then notify("Car Fly","Nur im Auto."); return end; mobileFlyHold[key]=true end)
            b.MouseButton1Up:Connect(function() mobileFlyHold[key]=false end)
            b.MouseLeave:Connect(function() mobileFlyHold[key]=false end)
            b.TouchLongPress:Connect(function(_,state) mobileFlyHold[key]=(state==Enum.UserInputState.Begin) end)
            return b
        end
        mkBtn("Toggle",10,34,60,28,"T").MouseButton1Click:Connect(function() if not isSeated() then notify("Car Fly","Nur im Auto."); return end; toggleFly() end)
        mkBtn("^",85,34,60,28,"F"); mkBtn("v",85,100,60,28,"B"); mkBtn("<<",15,67,60,28,"L"); mkBtn(">>",155,67,60,28,"R")
        mkBtn("Up",155,34,60,28,"U"); mkBtn("Down",155,100,60,28,"D")

        -- Drag
        local dragging,start,startPos
        frame.InputBegan:Connect(function(input)
            if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
                dragging=true; start=input.Position; startPos=frame.Position
                input.Changed:Connect(function() if input.UserInputState==Enum.UserInputState.End then dragging=false end end)
            end
        end)
        UserInput.InputChanged:Connect(function(input)
            if dragging and (input.UserInputType==Enum.UserInputType.MouseMovement or input.UserInputType==Enum.UserInputType.Touch) then
                local d=input.Position-start; frame.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,startPos.Y.Scale,startPos.Y.Offset+d.Y)
            end
        end)
        return gui
    end

    local function spawnMobileDrive()
        local gui = Instance.new("ScreenGui")
        gui.Name="Sorin_MobileDrive"; gui.ResetOnSpawn=false; gui.IgnoreGuiInset=true
        gui.Enabled=false; gui.Parent=game:GetService("CoreGui")

        local frame=Instance.new("Frame"); frame.Size=UDim2.fromOffset(230,140); frame.Position=UDim2.fromOffset(290,300)
        frame.BackgroundColor3=Color3.fromRGB(25,25,25); frame.Parent=gui; Instance.new("UICorner",frame).CornerRadius=UDim.new(0,12)
        local title=Instance.new("TextLabel"); title.Size=UDim2.new(1,-10,0,22); title.Position=UDim2.fromOffset(10,6)
        title.BackgroundTransparency=1; title.Font=Enum.Font.GothamBold; title.TextSize=14; title.TextColor3=Color3.fromRGB(240,240,240)
        title.TextXAlignment=Enum.TextXAlignment.Left; title.Text="Power Drive"; title.Parent=frame

        local function mkBtn(txt,x,y,w,h,flag,pressOnly)
            local b=Instance.new("TextButton"); b.Size=UDim2.fromOffset(w,h); b.Position=UDim2.fromOffset(x,y); b.Text=txt
            b.BackgroundColor3=Color3.fromRGB(40,40,40); b.TextColor3=Color3.fromRGB(230,230,230); b.Font=Enum.Font.GothamSemibold; b.TextSize=14; b.Parent=frame
            Instance.new("UICorner",b).CornerRadius=UDim.new(0,8)
            if pressOnly then b.MouseButton1Click:Connect(function() toggleDrive() end)
            else
                b.MouseButton1Down:Connect(function() if not isSeated() then notify("Drive","Nur im Auto."); return end; mobileDriveHold[flag]=true end)
                b.MouseButton1Up:Connect(function() mobileDriveHold[flag]=false end)
                b.MouseLeave:Connect(function() mobileDriveHold[flag]=false end)
                b.TouchLongPress:Connect(function(_,state) mobileDriveHold[flag]=(state==Enum.UserInputState.Begin) end)
            end
            return b
        end

        mkBtn("Toggle",10,34,60,28,"",true)
        mkBtn("^",85,34,60,28,"F"); mkBtn("v",85,90,60,28,"B")
        mkBtn("<<",15,62,60,28,"L"); mkBtn(">>",155,62,60,28,"R")

        -- Drag
        local dragging,start,startPos
        frame.InputBegan:Connect(function(input)
            if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
                dragging=true; start=input.Position; startPos=frame.Position
                input.Changed:Connect(function() if input.UserInputState==Enum.UserInputState.End then dragging=false end end)
            end
        end)
        UserInput.InputChanged:Connect(function(input)
            if dragging and (input.UserInputType==Enum.UserInputType.MouseMovement or input.UserInputType==Enum.UserInputType.Touch) then
                local d=input.Position-start; frame.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,startPos.Y.Scale,startPos.Y.Offset+d.Y)
            end
        end)
        return gui
    end

    local MobileFlyGui  = spawnMobileFly()
    local MobileDriveGui= spawnMobileDrive()

    ------------------------------------------------------------------------
    -- UI (Orion)
    ------------------------------------------------------------------------
    local secV = tab:AddSection({ Name = "Vehicle" })
    secV:AddButton({ Name="To Vehicle (auf Sitz & einsteigen)", Callback=toVehicle })
    secV:AddButton({ Name="Bring Vehicle (vor dich & einsteigen)", Callback=bringVehicle })
    secV:AddTextbox({ Name="Kennzeichen-Text", Default=CFG.plateText, TextDisappear=false, Callback=function(txt) CFG.plateText=tostring(txt or ""); save_cfg() end })
    secV:AddButton({ Name="Kennzeichen anwenden (aktuelles Fahrzeug)", Callback=applyPlateToCurrent })

    local secF = tab:AddSection({ Name = "Car Fly" })
    flyToggleUI = secF:AddToggle({ Name="Enable Car Fly (nur im Auto)", Default=false, Callback=function(v) toggleFly(v) end })
    secF:AddBind({ Name="Car Fly Toggle Key", Default=Enum.KeyCode.X, Hold=false, Callback=function() toggleFly() end })
    secF:AddSlider({ Name="Fly Speed", Min=10, Max=190, Increment=5, Default=130, Callback=function(v) flySpeed=math.floor(v) end })
    secF:AddToggle({ Name="Safe Fly (alle 6s Boden-Lock, 0.5s)", Default=false, Callback=function(v) safeFly=v end })
    secF:AddToggle({
        Name="Full Vehicle NoClip (riskant)", Default=false,
        Callback=function(v) fullNoClip=v; if flyEnabled then local vf=myVehicleFolder(); applyFlyCollision(vf) end end
    })
    secF:AddToggle({ Name="Mobile Fly Panel anzeigen", Default=false, Callback=function(v) if MobileFlyGui then MobileFlyGui.Enabled=v end end })

    local secD = tab:AddSection({ Name = "Power Drive (Motor aus)" })
    secD:AddToggle({ Name="Enable Power Drive", Default=false, Callback=function(v) toggleDrive(v) end })
    secD:AddBind({ Name="Power Drive Toggle Key", Default=Enum.KeyCode.Z, Hold=false, Callback=function() toggleDrive() end })
    secD:AddSlider({ Name="Drive Speed", Min=10, Max=140, Increment=5, Default=65, Callback=function(v) driveSpeed=math.floor(v) end })
    secD:AddSlider({ Name="Drive Accel", Min=10, Max=120, Increment=5, Default=50, Callback=function(v) DRIVE_A_MAX=math.floor(v) end })
    secD:AddSlider({ Name="Steer Strength", Min=10, Max=500, Increment=10, Default=220, Callback=function(v) STEER_K = v/100 end })
    secD:AddToggle({ Name="Lenkung an Kamera ausrichten", Default=true, Callback=function(v) steerAssistCamera=v end })
    secD:AddToggle({ Name="Mobile Drive Pad anzeigen", Default=false, Callback=function(v) if MobileDriveGui then MobileDriveGui.Enabled=v end end })

    task.defer(function() if CFG.plateText~="" then task.wait(1.0); pcall(applyPlateToCurrent) end end)
end
