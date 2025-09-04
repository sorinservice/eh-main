-- tabs/functions/vehicle/vehicle/carfly.lua
-- AC-freundlicher Car Fly: nur Kräfte (VectorForce), keine Velocity-Writes, kein AlignOrientation.

return function(SV, tab, OrionLib)
    print("Hure digga. Was bannt ihr mich")
    local RunService  = game:GetService("RunService")
    local UserInput   = game:GetService("UserInputService")
    local Workspace   = game:GetService("Workspace")
    local Camera      = SV.Camera

    -- ====== Tuning ======
    local DEFAULT_SPEED     = 130        -- UI-Standard
    local THRUST_ACCEL      = 120        -- studs/s^2 (planar)
    local CLIMB_ACCEL       = 90         -- studs/s^2 (vertikal)
    local CLIMB_MAX_V       = 38         -- max vertikale Zielgeschwindigkeit
    local DAMPING_PLANAR    = 0.55       -- Luftdämpfung (drift abbauen)
    local INPUT_LERP        = 0.18       -- Zielgeschw.-Glättung 0..1
    local YAW_K             = 1.4        -- Yaw-Impuls-Faktor
    local YAW_CLAMP         = 0.28       -- rad/Tick max
    local CLEARANCE_PROBE   = 6          -- Bodenscan-Tiefe
    local CLEARANCE_UP_BIAS = 0.35       -- Aufwärts-Offset nahe Boden
    local LAND_HEIGHT       = 15         -- weiches Landen (studs)
    local SAFE_PERIOD       = 6          -- alle X Sekunden
    local SAFE_PRESS_TIME   = 0.5        -- 0.5s “auf Boden drücken”
    local SAFE_TELEPORT_BACK = false     -- Teleport zurück (AC-Risiko) -> standard AUS

    -- ====== State ======
    local fly = {
        enabled   = false,
        speed     = DEFAULT_SPEED,
        smoothed  = Vector3.new(),
        conn      = nil,
        safeTh    = nil,
        groundLock= false,
        uiToggle  = nil,
        mobileHold= {F=false,B=false,L=false,R=false,U=false,D=false},

        -- controllers
        att=nil, vfThrust=nil, vfLift=nil, pp=nil,
        safeFly=false
    }

    local function notify(t,m,s) SV.notify(t,m,s or 3) end

    -- ====== Helpers ======
    local function getPP(v)
        SV.ensurePrimaryPart(v)
        return v.PrimaryPart
    end

    local function buildControllers(v)
        local pp = getPP(v); if not pp then return false end
        fly.pp = pp

        fly.att = Instance.new("Attachment")
        fly.att.Name = "SorinFly_Att"
        fly.att.Parent = pp

        -- planar thrust
        fly.vfThrust = Instance.new("VectorForce")
        fly.vfThrust.Name = "SorinFly_Thrust"
        fly.vfThrust.Attachment0 = fly.att
        fly.vfThrust.RelativeTo  = Enum.ActuatorRelativeTo.World
        fly.vfThrust.Force = Vector3.new()
        fly.vfThrust.Parent = pp

        -- vertical lift (Schwerkraftkompensation + Steigen/Sinken)
        fly.vfLift = Instance.new("VectorForce")
        fly.vfLift.Name = "SorinFly_Lift"
        fly.vfLift.Attachment0 = fly.att
        fly.vfLift.RelativeTo  = Enum.ActuatorRelativeTo.World
        fly.vfLift.Force = Vector3.new()
        fly.vfLift.Parent = pp

        return true
    end

    local function destroyControllers()
        for _,x in ipairs({fly.vfThrust, fly.vfLift, fly.att}) do
            if x and x.Parent then x:Destroy() end
        end
        fly.att, fly.vfThrust, fly.vfLift, fly.pp = nil, nil, nil, nil
    end

    local function zeroMotion()
        local v = SV.myVehicleFolder(); if not v then return end
        for _,p in ipairs(v:GetDescendants()) do
            if p:IsA("BasePart") then
                p.AssemblyLinearVelocity  = Vector3.new()
                p.AssemblyAngularVelocity = Vector3.new()
            end
        end
    end

    local function groundRay(v, depth)
        local cf = v:GetPivot()
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Blacklist
        params.FilterDescendantsInstances = { v }
        return Workspace:Raycast(cf.Position, Vector3.new(0,-(depth or 1000),0), params)
    end

    local function settleToGroundSoft(v)
        local hit = groundRay(v, 1000)
        if hit then
            local pos  = hit.Position + Vector3.new(0, LAND_HEIGHT, 0)
            local look = Camera.CFrame.LookVector
            pcall(function() v:PivotTo(CFrame.new(pos, pos + look)) end)
        end
    end

    local function signedYawErr(forward, desired)
        local f = Vector3.new(forward.X,0,forward.Z)
        local d = Vector3.new(desired.X,0,desired.Z)
        if f.Magnitude == 0 or d.Magnitude == 0 then return 0 end
        f=f.Unit; d=d.Unit
        local crossY = f:Cross(d).Y
        local dot    = math.clamp(f:Dot(d), -1, 1)
        local ang    = math.acos(dot)
        return math.clamp(ang * (crossY>=0 and 1 or -1), -YAW_CLAMP, YAW_CLAMP)
    end

    -- ====== Step ======
    local function step(dt)
        if not fly.enabled or fly.groundLock then return end
        if not SV.isSeated() then return end

        local v = SV.myVehicleFolder(); if not v then return end
        if not fly.pp or not fly.pp.Parent then
            if not buildControllers(v) then return end
        end

        local pp   = fly.pp
        local mass = math.max(pp.AssemblyMass, 1)
        local g    = Workspace.Gravity

        -- Eingabe (inkl. Mobile)
        local dir = Vector3.zero
        if not UserInput:GetFocusedTextBox() then
            if UserInput:IsKeyDown(Enum.KeyCode.W) or fly.mobileHold.F then dir += Camera.CFrame.LookVector end
            if UserInput:IsKeyDown(Enum.KeyCode.S) or fly.mobileHold.B then dir -= Camera.CFrame.LookVector end
            if UserInput:IsKeyDown(Enum.KeyCode.D) or fly.mobileHold.R then dir += Camera.CFrame.RightVector end
            if UserInput:IsKeyDown(Enum.KeyCode.A) or fly.mobileHold.L then dir -= Camera.CFrame.RightVector end
            if UserInput:IsKeyDown(Enum.KeyCode.Space) or fly.mobileHold.U then dir += Vector3.new(0,1,0) end
            if UserInput:IsKeyDown(Enum.KeyCode.LeftControl) or fly.mobileHold.D then dir -= Vector3.new(0,1,0) end
        end

        -- Boden-Offset (verhindert “Räder hängen”)
        local near = groundRay(v, CLEARANCE_PROBE)
        if near and not (UserInput:IsKeyDown(Enum.KeyCode.LeftControl) or fly.mobileHold.D) then
            dir += Vector3.new(0, CLEARANCE_UP_BIAS, 0)
        end

        -- Zielgeschwindigkeit
        local target = Vector3.new()
        if dir.Magnitude > 0 then
            target = dir.Unit * fly.speed
            if target.Y >  CLIMB_MAX_V then target = Vector3.new(target.X,  CLIMB_MAX_V, target.Z) end
            if target.Y < -CLIMB_MAX_V then target = Vector3.new(target.X, -CLIMB_MAX_V, target.Z) end
        end
        fly.smoothed = fly.smoothed:Lerp(target, math.clamp(INPUT_LERP, 0, 1))

        -- Aktuelle Geschw.
        local vel = pp.AssemblyLinearVelocity
        local vPlan = Vector3.new(vel.X,0,vel.Z)

        -- Planar Thrust + Dämpfung
        local desiredPlan = Vector3.new(fly.smoothed.X, 0, fly.smoothed.Z)
        local thrust = Vector3.new()
        if desiredPlan.Magnitude > 0 then
            -- Speed Cap in Bewegungsrichtung
            local forwarding = vPlan.Magnitude > fly.speed and (vPlan.Unit:Dot(desiredPlan.Unit) > 0)
            if not forwarding then
                thrust = desiredPlan.Unit * (THRUST_ACCEL * mass)
            end
        end
        local damp = -vPlan * (DAMPING_PLANAR * mass)
        fly.vfThrust.Force = thrust + damp

        -- Vertical Lift (Hover + climb/sink)
        local desiredY = fly.smoothed.Y
        local climbAcc = 0
        if math.abs(desiredY) > 1e-4 then
            climbAcc = math.clamp((desiredY > 0 and 1 or -1) * CLIMB_ACCEL, -CLIMB_ACCEL, CLIMB_ACCEL)
        end
        fly.vfLift.Force = Vector3.new(0, mass*g + climbAcc*mass, 0)

        -- Nase folgt Kamera (nur sanftes Yaw per Impuls)
        local yawErr = signedYawErr(v:GetPivot().LookVector, Camera.CFrame.LookVector)
        if math.abs(yawErr) > 1e-3 then
            pp:ApplyAngularImpulse(Vector3.new(0, yawErr * YAW_K * mass, 0))
        end
    end

    -- ====== Toggle ======
    local function setEnabled(on)
        if on == fly.enabled then return end
        fly.enabled = on

        local v = SV.myVehicleFolder()
        if not v then
            fly.enabled = false
            if fly.uiToggle then fly.uiToggle:Set(false) end
            notify("Car Fly","Kein Fahrzeug.")
            return
        end

        if fly.enabled then
            if not buildControllers(v) then
                fly.enabled = false
                if fly.uiToggle then fly.uiToggle:Set(false) end
                notify("Car Fly","Kein PrimaryPart.")
                return
            end

            -- kleiner Lift-Off
            pcall(function() v:PivotTo(v:GetPivot() + Vector3.new(0,2.5,0)) end)
            fly.smoothed = Vector3.new()

            if fly.conn then fly.conn:Disconnect() end
            fly.conn = RunService.RenderStepped:Connect(step)

            -- SafeFly-Thread
            if fly.safeTh then task.cancel(fly.safeTh) end
            fly.safeTh = task.spawn(function()
                while fly.enabled do
                    if not fly.safeFly then task.wait(0.25)
                    else
                        task.wait(SAFE_PERIOD)
                        if not fly.enabled then break end
                        local vv = SV.myVehicleFolder(); if not vv then break end
                        local before = vv:GetPivot()
                        local pp = fly.pp; if not pp then break end
                        local mass = math.max(pp.AssemblyMass,1)
                        fly.groundLock = true
                        -- “auf Boden drücken” (stärker als g)
                        local t0 = os.clock()
                        while os.clock()-t0 < SAFE_PRESS_TIME and fly.enabled do
                            if fly.vfLift then
                                fly.vfLift.Force = Vector3.new(0, mass*Workspace.Gravity*0.2, 0) -- weniger als g -> sinken
                            end
                            RunService.RenderStepped:Wait()
                        end
                        -- optional exakt zurück (Teleport – potentiell AC-risiko)
                        if SAFE_TELEPORT_BACK and fly.enabled then
                            pcall(function() vv:PivotTo(before) end)
                        end
                        fly.groundLock = false
                    end
                end
            end)

            if fly.uiToggle then fly.uiToggle:Set(true) end
            notify("Car Fly", ("Aktiviert (Speed %d)"):format(fly.speed), 2)
        else
            if fly.conn then fly.conn:Disconnect() fly.conn=nil end
            if fly.safeTh then task.cancel(fly.safeTh) fly.safeTh=nil end

            zeroMotion()
            destroyControllers()
            if v then settleToGroundSoft(v) end

            if fly.uiToggle then fly.uiToggle:Set(false) end
            notify("Car Fly","Deaktiviert.", 2)
        end
    end

    local function toggle() setEnabled(not fly.enabled) end

    -- ====== Mobile UI ======
    local function spawnMobileFly()
        local gui = Instance.new("ScreenGui")
        gui.Name = "Sorin_MobileFly"
        gui.ResetOnSpawn = false
        gui.IgnoreGuiInset = true
        gui.Enabled = false
        gui.Parent = game:GetService("CoreGui")

        local frame = Instance.new("Frame")
        frame.Size = UDim2.fromOffset(230, 160)
        frame.Position = UDim2.fromOffset(40, 300)
        frame.BackgroundColor3 = Color3.fromRGB(25,25,25)
        frame.Parent = gui
        Instance.new("UICorner", frame).CornerRadius = UDim.new(0,12)

        local title = Instance.new("TextLabel")
        title.Size = UDim2.new(1, -10, 0, 22)
        title.Position = UDim2.fromOffset(10, 6)
        title.BackgroundTransparency = 1
        title.Font = Enum.Font.GothamBold
        title.TextSize = 14
        title.TextColor3 = Color3.fromRGB(240,240,240)
        title.TextXAlignment = Enum.TextXAlignment.Left
        title.Text = "Car Fly"
        title.Parent = frame

        local function mkBtn(txt, x, y, w, h, key)
            local b = Instance.new("TextButton")
            b.Size = UDim2.fromOffset(w,h); b.Position = UDim2.fromOffset(x,y)
            b.Text = txt; b.BackgroundColor3 = Color3.fromRGB(40,40,40)
            b.TextColor3 = Color3.fromRGB(230,230,230); b.Font = Enum.Font.GothamSemibold; b.TextSize = 14
            b.Parent = frame; Instance.new("UICorner", b).CornerRadius = UDim.new(0,8)
            b.MouseButton1Down:Connect(function() fly.mobileHold[key] = true end)
            b.MouseButton1Up:Connect(function() fly.mobileHold[key] = false end)
            b.MouseLeave:Connect(function() fly.mobileHold[key] = false end)
            return b
        end

        mkBtn("Toggle", 10, 34, 60, 28, "T").MouseButton1Click:Connect(function() toggle() end)
        mkBtn("^",      85, 34, 60, 28, "F")
        mkBtn("v",      85,100, 60, 28, "B")
        mkBtn("<<",     15, 67, 60, 28, "L")
        mkBtn(">>",     155,67, 60, 28, "R")
        mkBtn("Up",     155,34, 60, 28, "U")
        mkBtn("Down",   155,100,60, 28, "D")

        -- drag header
        local dragging, start, startPos
        frame.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 and input.Position.Y - frame.AbsolutePosition.Y <= 28 then
                dragging = true; start = input.Position; startPos = frame.Position
                input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then dragging = false end
                end)
            end
        end)
        UserInput.InputChanged:Connect(function(input)
            if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
                local d = input.Position - start
                frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
            end
        end)

        return gui
    end
    local MobileFlyGui = spawnMobileFly()

    -- ====== UI minimal (Toggle, SafeFly, Mobile, Speed, Keybind) ======
    local sec = tab:AddSection({ Name = "Car Fly" })

    fly.uiToggle = sec:AddToggle({
        Name = "Enable Car Fly (nur im Auto)",
        Default = false,
        Callback = function(v) setEnabled(v) end
    })

    sec:AddBind({
        Name = "Toggle Key",
        Default = Enum.KeyCode.X,
        Hold = false,
        Callback = function() toggle() end
    })

    sec:AddToggle({
        Name = "Safe Fly (alle 6s 0.5s Boden)",
        Default = false,
        Callback = function(v) fly.safeFly = v end
    })

    sec:AddToggle({
        Name = "Mobile Fly Panel",
        Default = false,
        Callback = function(v) if MobileFlyGui then MobileFlyGui.Enabled = v end end
    })

    sec:AddSlider({
        Name = "Speed",
        Min = 10, Max = 190, Increment = 5,
        Default = DEFAULT_SPEED,
        Callback = function(v) fly.speed = math.floor(v) end
    })

    -- Safety: falls du den Sitz verlässt → aus
    RunService.Heartbeat:Connect(function()
        if fly.enabled and not SV.isSeated() then
            setEnabled(false)
        end
    end)
end
