-- tabs/functions/vehicle/vehicle/carfly.lua
-- Server-weites, weiches Car Fly mit Actuators (LV/VF/AO)
-- - Keybind X
-- - SafeFly (alle 6s: 0.5s Boden-Hold, danach zurück)
-- - Mobile-Panel
-- - Speed Slider (default 130)
-- - Sanfte Dämpfung statt harte Velocity-Resets
-- - Anti-Stuck: leichte Boden-/Kollisions-Clearance („schwaches Noclip“)

return function(SV, tab, OrionLib)
    local RunService  = game:GetService("RunService")
    local UserInput   = game:GetService("UserInputService")
    local Workspace   = game:GetService("Workspace")
    local Camera      = SV.Camera

    -- ===== Tuning =====
    local DEFAULT_SPEED    = 130
    local ACCEL_LERP       = 0.14     -- wie schnell Zielgeschw. erreicht wird (0..1)
    local TURN_RESP        = 35       -- AlignOrientation.Responsiveness
    local SPEED_KEY        = Enum.KeyCode.LeftControl
    local SPEED_MULTI      = 3

    local CLEARANCE_PROBE  = 5        -- Bodennähe-Check (Studs)
    local CLEARANCE_UP     = 2.25     -- Start-/Anti-Stuck-Nudge nach oben (Studs)
    local LAND_SOFT_HEIGHT = 15       -- Fly-Off: Höhe über Boden (Studs)

    local SAFE_PERIOD      = 6.0
    local SAFE_HOLD        = 0.5
    local SAFE_TP_BACK     = true

    -- sanfte Dämpfung (Impuls-basiert, cap Δv pro Tick)
    local function softDampLinear(pp, duration, a_max)
        local mass = math.max(pp.AssemblyMass or 1, 1)
        local t0 = os.clock()
        local conn; conn = RunService.Heartbeat:Connect(function(dt)
            if not pp or not pp.Parent then conn:Disconnect(); return end
            local v  = pp.AssemblyLinearVelocity
            local dv = -v
            local cap = (a_max or 120) * dt
            if dv.Magnitude > cap then dv = dv.Unit * cap end
            if dv.Magnitude > 1e-4 then
                pp:ApplyImpulse(dv * mass)
            end
            if os.clock() - t0 > duration or v.Magnitude < 1.25 then
                conn:Disconnect()
            end
        end)
    end
    local function softDampAngular(pp, duration, alpha)
        local mass = math.max(pp.AssemblyMass or 1, 1)
        local t0 = os.clock()
        local conn; conn = RunService.Heartbeat:Connect(function(dt)
            if not pp or not pp.Parent then conn:Disconnect(); return end
            local w = pp.AssemblyAngularVelocity
            local desired = -w * math.clamp(alpha or 0.6, 0, 1)
            local cap = 10 * dt
            if desired.Magnitude > cap then desired = desired.Unit * cap end
            if desired.Magnitude > 1e-4 then
                pp:ApplyAngularImpulse(desired * mass)
            end
            if os.clock() - t0 > duration or w.Magnitude < 0.5 then
                conn:Disconnect()
            end
        end)
    end

    local function notify(t,m,s) SV.notify(t,m,s or 3) end
    local function myVehicle() return SV.myVehicleFolder() end
    local function getPP(v) SV.ensurePrimaryPart(v); return v and v.PrimaryPart or nil end
    local function isOwner(bp)
        if typeof(isnetworkowner) == "function" then
            local ok, owns = pcall(isnetworkowner, bp)
            if ok then return owns end
        end
        return true
    end
    local function rayGround(v, depth)
        local cf = v:GetPivot()
        local p = RaycastParams.new()
        p.FilterType = Enum.RaycastFilterType.Blacklist
        p.FilterDescendantsInstances = { v }
        return Workspace:Raycast(cf.Position, Vector3.new(0, -math.max(depth or 1000,1), 0), p)
    end
    local function nudgeUp(v, studs)
        local cf = v:GetPivot()
        pcall(function() v:PivotTo(cf + Vector3.new(0, studs or CLEARANCE_UP, 0)) end)
    end
    local function settleToGroundSoft(v)
        local hit = rayGround(v, 1000)
        if hit then
            local pos  = hit.Position + Vector3.new(0, LAND_SOFT_HEIGHT, 0)
            local look = Camera.CFrame.LookVector
            pcall(function() v:PivotTo(CFrame.new(pos, pos + look)) end)
        end
    end

    -- ===== Fly-Controllers (Attachment + LV + VF + AO) =====
    local fly = {
        enabled=false, speed=DEFAULT_SPEED, curVel=Vector3.new(),
        conn=nil, safeTask=nil, safeOn=false, uiToggle=nil, toggleTS=0,
        mobileUI=nil, mobileHold={F=false,B=false,L=false,R=false,U=false,D=false},
        pp=nil, att=nil, lv=nil, vf=nil, ao=nil
    }

    local function buildControllers(v)
        fly.pp = getPP(v); if not fly.pp then return false end
        -- Attachment
        fly.att = Instance.new("Attachment")
        fly.att.Name = "Sorin_CF_Att"
        fly.att.Parent = fly.pp
        -- LinearVelocity (Bewegung)
        fly.lv = Instance.new("LinearVelocity")
        fly.lv.Name = "Sorin_CF_LV"
        fly.lv.RelativeTo = Enum.ActuatorRelativeTo.World
        fly.lv.Attachment0 = fly.att
        -- MaxForce moderat (anti-flag): ~ m * 6000
        fly.lv.MaxForce = math.max(1, fly.pp.AssemblyMass) * 6000
        fly.lv.VectorVelocity = Vector3.new()
        fly.lv.Parent = fly.pp
        -- VectorForce (Hover: neutralisiert g)
        fly.vf = Instance.new("VectorForce")
        fly.vf.Name = "Sorin_CF_Hover"
        fly.vf.Attachment0 = fly.att
        fly.vf.RelativeTo  = Enum.ActuatorRelativeTo.World
        fly.vf.Force = Vector3.new()
        fly.vf.Parent = fly.pp
        -- AlignOrientation (Nase zu Kamera)
        fly.ao = Instance.new("AlignOrientation")
        fly.ao.Name = "Sorin_CF_AO"
        fly.ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
        fly.ao.Attachment0 = fly.att
        fly.ao.Responsiveness = TURN_RESP
        fly.ao.MaxTorque = math.max(1, fly.pp.AssemblyMass) * 6000
        fly.ao.RigidityEnabled = false
        fly.ao.Parent = fly.pp
        return true
    end
    local function destroyControllers()
        -- actuator-Ausblendung (kein harter Cut)
        if fly.lv then pcall(function() fly.lv.VectorVelocity = Vector3.new() end) end
        if fly.vf then pcall(function() fly.vf.Force = Vector3.new() end) end
        for _,o in ipairs({fly.ao, fly.vf, fly.lv, fly.att}) do
            if o and o.Parent then o:Destroy() end
        end
        fly.pp, fly.att, fly.lv, fly.vf, fly.ao = nil,nil,nil,nil,nil
    end

    -- ===== Anti-Stuck: kurzer Vorwärts-Check, ggf. Up-Nudge =====
    local function forwardNudgeIfNeeded(v)
        if fly.curVel.Magnitude < 2 then return end
        local dir = fly.curVel.Unit
        local p = RaycastParams.new()
        p.FilterType = Enum.RaycastFilterType.Blacklist
        p.FilterDescendantsInstances = { v }
        local len = math.clamp(2 + fly.curVel.Magnitude/60, 2, 6)
        local hit = Workspace:Raycast(fly.pp.Position, dir * len, p)
        if hit then
            nudgeUp(v, 1.25) -- „schwaches Noclip“: minimal hochheben
        end
    end

    -- ===== Haupt-Loop =====
    local function step(dt)
        if not fly.enabled then return end
        if not SV.isSeated() then return end

        local v = myVehicle(); if not v then return end
        if not fly.pp or not fly.pp.Parent then return end
        if fly.pp.Anchored then return end
        if not isOwner(fly.pp) then return end

        -- Eingabe (Keyboard + Mobile)
        local desired = Vector3.new()
        if not UserInput:GetFocusedTextBox() then
            if UserInput:IsKeyDown(Enum.KeyCode.W) or fly.mobileHold.F then desired += Camera.CFrame.LookVector end
            if UserInput:IsKeyDown(Enum.KeyCode.S) or fly.mobileHold.B then desired -= Camera.CFrame.LookVector end
            if UserInput:IsKeyDown(Enum.KeyCode.D) or fly.mobileHold.R then desired += Camera.CFrame.RightVector end
            if UserInput:IsKeyDown(Enum.KeyCode.A) or fly.mobileHold.L then desired -= Camera.CFrame.RightVector end
            if UserInput:IsKeyDown(Enum.KeyCode.Space) or fly.mobileHold.U then desired += Vector3.new(0,1,0) end
            if UserInput:IsKeyDown(SPEED_KEY) then desired = desired * SPEED_MULTI end
        end
        if desired.Magnitude > 0 then desired = desired.Unit * fly.speed end

        -- Boden-/Clearance-Bias (verhindert festklemmen)
        local near = rayGround(v, CLEARANCE_PROBE)
        if near and not UserInput:IsKeyDown(Enum.KeyCode.LeftControl) then
            desired = desired + Vector3.new(0, fly.speed * 0.12, 0)
        end

        -- Zielgeschwindigkeit glätten
        fly.curVel = fly.curVel:Lerp(desired, math.clamp(ACCEL_LERP, 0, 1))

        -- Hover neutralisiert Gewicht (kein Schweben „nach oben“)
        local m = math.max(fly.pp.AssemblyMass, 1)
        fly.vf.Force = Vector3.new(0, m * Workspace.Gravity, 0)

        -- Bewegung anwenden
        fly.lv.VectorVelocity = fly.curVel

        -- Nase zur Kamera (horizontal + leicht vertikal)
        fly.ao.CFrame = CFrame.lookAt(Vector3.new(), Camera.CFrame.LookVector).Rotation

        -- „Schwaches Noclip“: vorn prüfen, ggf. Up-Nudge
        forwardNudgeIfNeeded(v)
    end

    -- ===== SafeFly =====
    local function startSafeFly()
        if fly.safeTask then task.cancel(fly.safeTask) end
        fly.safeTask = task.spawn(function()
            while fly.enabled do
                if not fly.safeOn then task.wait(0.25)
                else
                    task.wait(SAFE_PERIOD)
                    if not fly.enabled then break end
                    local v = myVehicle(); if not v then break end
                    local before = v:GetPivot()
                    local hit = rayGround(v, 1500)
                    if not hit then continue end

                    -- 1) einmalig an Boden setzen (nicht jedes Frame!)
                    local lockCF = CFrame.new(
                        hit.Position + Vector3.new(0, 2, 0),
                        hit.Position + Vector3.new(0, 2, 0) + Camera.CFrame.LookVector
                    )
                    pcall(function() v:PivotTo(lockCF) end)

                    -- 2) 0.5s halten: LV → 0 blenden, VF leicht nach unten drücken
                    local t0 = os.clock()
                    while os.clock() - t0 < SAFE_HOLD and fly.enabled do
                        if fly.lv then fly.lv.VectorVelocity = fly.lv.VectorVelocity:Lerp(Vector3.new(), 0.5) end
                        if fly.vf and fly.pp then
                            local m = math.max(fly.pp.AssemblyMass, 1)
                            fly.vf.Force = Vector3.new(0, -m * Workspace.Gravity * 0.35, 0) -- „press down“
                        end
                        RunService.Heartbeat:Wait()
                    end

                    -- 3) zurück zur Luftposition
                    if SAFE_TP_BACK and fly.enabled then
                        pcall(function() v:PivotTo(before) end)
                    end

                    -- 4) Hover neutral wiederherstellen
                    if fly.vf and fly.pp then
                        local m2 = math.max(fly.pp.AssemblyMass, 1)
                        fly.vf.Force = Vector3.new(0, m2 * Workspace.Gravity, 0)
                    end
                end
            end
        end)
    end

    -- ===== Toggle =====
    local function setEnabled(on)
        if on == fly.enabled then return end
        local v = myVehicle()

        if on then
            if not v then notify("Car Fly","Kein Fahrzeug."); return end
            if not buildControllers(v) then notify("Car Fly","Kein PrimaryPart."); return end
            nudgeUp(v, CLEARANCE_UP)
            fly.curVel = Vector3.new()
            if fly.conn then fly.conn:Disconnect() end
            fly.conn = RunService.Heartbeat:Connect(step)
            startSafeFly()
            fly.enabled = true
            if fly.uiToggle then fly.uiToggle:Set(true) end
            notify("Car Fly", ("Aktiviert (Speed %d)"):format(fly.speed), 2)
        else
            fly.enabled = false
            if fly.conn then fly.conn:Disconnect() fly.conn=nil end
            if fly.safeTask then task.cancel(fly.safeTask) fly.safeTask=nil end
            if v and fly.pp then
                -- Erst sanft dämpfen, dann weich landen, dann Controller weg
                softDampLinear(fly.pp, 0.35, 120)
                softDampAngular(fly.pp, 0.35, 0.6)
                settleToGroundSoft(v)
            end
            destroyControllers()
            if fly.uiToggle then fly.uiToggle:Set(false) end
            notify("Car Fly","Deaktiviert.", 2)
        end
    end

    local function toggle()
        local now = os.clock()
        if now - fly.toggleTS < 0.15 then return end
        fly.toggleTS = now
        setEnabled(not fly.enabled)
    end

    -- ===== Mobile Panel =====
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

        mkBtn("Toggle", 10, 34, 60, 28, "T").MouseButton1Click:Connect(toggle)
        mkBtn("^",      85, 34, 60, 28, "F")
        mkBtn("v",      85,100, 60, 28, "B")
        mkBtn("<<",     15, 67, 60, 28, "L")
        mkBtn(">>",     155,67, 60, 28, "R")
        mkBtn("Up",     155,34, 60, 28, "U")
        mkBtn("Down",   155,100, 60, 28, "D")

        -- Drag nur über Kopfzeile
        local dragging, start, startPos
        frame.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
               and input.Position.Y - frame.AbsolutePosition.Y <= 26 then
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

    -- ===== UI (minimal wie gewünscht) =====
    local sec = tab:AddSection({ Name = "Car Fly" })
    fly.uiToggle = sec:AddToggle({
        Name = "Enable Car Fly (nur im Auto)",
        Default = false,
        Callback = function(v) setEnabled(v) end
    })
    sec:AddBind({
        Name = "Car Fly Toggle Key",
        Default = Enum.KeyCode.X,
        Hold = false,
        Callback = function() toggle() end
    })
    sec:AddToggle({
        Name = "Safe Fly (alle 6s: 0.5s Boden → zurück)",
        Default = false,
        Callback = function(v) fly.safeOn = v end
    })
    sec:AddToggle({
        Name = "Mobile Panel",
        Default = false,
        Callback = function(v) if MobileFlyGui then MobileFlyGui.Enabled = v end end
    })
    sec:AddSlider({
        Name = "Speed",
        Min = 10, Max = 300, Increment = 5,
        Default = DEFAULT_SPEED,
        Callback = function(v) fly.speed = math.floor(v) end
    })

    -- Auto-Off, wenn du den Sitz verlässt
    RunService.Heartbeat:Connect(function()
        if fly.enabled and not SV.isSeated() then
            setEnabled(false)
        end
    end)
end
