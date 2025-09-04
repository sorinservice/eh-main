-- tabs/functions/vehicle/carfly.lua
-- Car Fly – 3 Methoden zum Umschalten (A: LV+Hover, B: Δv-Impulse, C: Legacy Body*).
-- Kein Teleport beim Start. Vor/zurück + hoch/runter; Nase folgt Kamera.
return function(SV, tab, OrionLib)
    print("Tests. NICHT BENUTZEN!!! BANN IST SEHR WARSCHEINLICH!!!")
    local RunService   = game:GetService("RunService")
    local UserInput    = game:GetService("UserInputService")
    local Workspace    = game:GetService("Workspace")
    local Camera       = SV.Camera
    local notify       = SV.notify

    --------------------------------------------------------------------
    -- Einstellungen
    --------------------------------------------------------------------
    local DEFAULT_SPEED   = 130     -- Startwert (im UI änderbar)
    local ACCEL_LERP      = 0.14    -- Glättung Zielgeschw. [0..1]
    local AO_RESP         = 35      -- AlignOrientation.Responsiveness
    local SPEED_KEY       = Enum.KeyCode.LeftControl
    local SPEED_MULTI     = 3
    local UP_KEY          = Enum.KeyCode.Space
    local DOWN_KEYS       = {Enum.KeyCode.Q, Enum.KeyCode.LeftControl}

    --------------------------------------------------------------------
    -- State
    --------------------------------------------------------------------
    local fly = {
        enabled = false,
        mode    = "A",    -- "A" | "B" | "C"
        speed   = DEFAULT_SPEED,
        curVel  = Vector3.new(),
        conn    = nil,

        -- A: LV/VectorForce/AO
        pp=nil, att=nil, lv=nil, vf=nil, ao=nil,

        -- C: Body*
        bv=nil, bg=nil,
    }

    local function isDown(k)
        return UserInput:IsKeyDown(k)
    end
    local function isAnyDown(list)
        for _,k in ipairs(list) do if isDown(k) then return true end end
        return false
    end

    local function vehicle()
        return SV.myVehicleFolder()
    end
    local function primaryPart(v)
        SV.ensurePrimaryPart(v)
        return v and v.PrimaryPart or nil
    end

    --------------------------------------------------------------------
    -- Helfer: Eingabe → gewünschte Zielgeschwindigkeit (kein Strafen)
    --------------------------------------------------------------------
    local function desiredVelocity(baseSpeed)
        local v = Vector3.new()
        if not UserInput:GetFocusedTextBox() then
            -- Nur Blickrichtung vor/zurück
            if isDown(Enum.KeyCode.W) then v = v + Camera.CFrame.LookVector end
            if isDown(Enum.KeyCode.S) then v = v - Camera.CFrame.LookVector end
            -- Hoch/Runter
            if isDown(UP_KEY) then v = v + Vector3.new(0,1,0) end
            if isAnyDown(DOWN_KEYS) then v = v - Vector3.new(0,1,0) end
            -- Turbo
            if isDown(SPEED_KEY) then baseSpeed = baseSpeed * SPEED_MULTI end
        end
        if v.Magnitude > 0 then v = v.Unit * baseSpeed end
        return v
    end

    --------------------------------------------------------------------
    -- MODE A: Serverseitig, LinearVelocity + VectorForce + AlignOrientation
    --------------------------------------------------------------------
    local function a_build(pp)
        fly.att = Instance.new("Attachment")
        fly.att.Name = "CF_Att"; fly.att.Parent = pp

        fly.lv = Instance.new("LinearVelocity")
        fly.lv.Name = "CF_LV"; fly.lv.RelativeTo = Enum.ActuatorRelativeTo.World
        fly.lv.Attachment0 = fly.att; fly.lv.MaxForce = math.huge
        fly.lv.VectorVelocity = Vector3.new()
        fly.lv.Parent = pp

        fly.vf = Instance.new("VectorForce")
        fly.vf.Name = "CF_VF"; fly.vf.RelativeTo = Enum.ActuatorRelativeTo.World
        fly.vf.Attachment0 = fly.att; fly.vf.Force = Vector3.new()
        fly.vf.Parent = pp

        fly.ao = Instance.new("AlignOrientation")
        fly.ao.Name = "CF_AO"; fly.ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
        fly.ao.Attachment0 = fly.att; fly.ao.Responsiveness = AO_RESP
        fly.ao.MaxTorque = math.huge; fly.ao.RigidityEnabled = false
        fly.ao.Parent = pp
    end
    local function a_step(pp, dt)
        -- Grav kompensieren (nur halten; steigen/sinken über desired Y)
        local mass = math.max(pp.AssemblyMass, 1)
        fly.vf.Force = Vector3.new(0, mass * Workspace.Gravity, 0)

        -- Ziel-Vel
        local target = desiredVelocity(fly.speed)
        fly.curVel = fly.curVel:Lerp(target, ACCEL_LERP)
        fly.lv.VectorVelocity = fly.curVel

        -- Nase zur Kamera
        fly.ao.CFrame = Camera.CFrame.Rotation
    end
    local function a_destroy()
        if fly.lv then pcall(function() fly.lv.VectorVelocity = Vector3.new() end) end
        if fly.vf then pcall(function() fly.vf.Force = Vector3.new() end) end
        for _,o in ipairs({fly.ao, fly.vf, fly.lv, fly.att}) do
            if o and o.Parent then o:Destroy() end
        end
        fly.att, fly.lv, fly.vf, fly.ao = nil,nil,nil,nil
    end

    --------------------------------------------------------------------
    -- MODE B: Impuls-Δv (ApplyImpulse) + weiche Kamera-Ausrichtung
    --------------------------------------------------------------------
    local DV_CAP = 60 -- studs/s^2 cap pro Sekunde (wird mit dt skaliert)
    local AO_TORQUE = 2.0
    local function b_step(pp, dt)
        local target = desiredVelocity(fly.speed)
        fly.curVel = fly.curVel:Lerp(target, ACCEL_LERP)

        local cur = pp.AssemblyLinearVelocity
        local dv  = fly.curVel - cur
        local maxDv = DV_CAP * math.max(dt, 1/240)
        if dv.Magnitude > maxDv then dv = dv.Unit * maxDv end
        if dv.Magnitude > 1e-5 then
            pp:ApplyImpulse(dv * math.max(pp.AssemblyMass,1))
        end

        -- Yaw sanft zur Kamera (nur horizontal)
        local fwd = pp.CFrame.LookVector
        local des = Camera.CFrame.LookVector
        local f = Vector3.new(fwd.X,0,fwd.Z); local d = Vector3.new(des.X,0,des.Z)
        if f.Magnitude>0 and d.Magnitude>0 then
            f=f.Unit; d=d.Unit
            local crossY = (f:Cross(d)).Y
            local dot = math.clamp(f:Dot(d), -1, 1)
            local ang = math.acos(dot) * (crossY>=0 and 1 or -1)
            if math.abs(ang) > 1e-3 then
                pp:ApplyAngularImpulse(Vector3.new(0, ang * AO_TORQUE * math.max(pp.AssemblyMass,1), 0))
            end
        end
    end

    --------------------------------------------------------------------
    -- MODE C: Legacy BodyVelocity/BodyGyro (risikoreicher)
    --------------------------------------------------------------------
    local function c_build(pp)
        fly.bv = Instance.new("BodyVelocity")
        fly.bv.Name = "CF_BV"; fly.bv.MaxForce = Vector3.new(1e9,1e9,1e9)
        fly.bv.Velocity = Vector3.new(); fly.bv.Parent = pp

        fly.bg = Instance.new("BodyGyro")
        fly.bg.Name = "CF_BG"; fly.bg.MaxTorque = Vector3.new(1e9,1e9,1e9)
        fly.bg.D = 600; fly.bg.P = 5000; fly.bg.Parent = pp
    end
    local function c_step(pp, dt)
        local target = desiredVelocity(fly.speed)
        fly.curVel = fly.curVel:Lerp(target, ACCEL_LERP)
        fly.bv.Velocity = fly.curVel
        fly.bg.CFrame = CFrame.lookAt(pp.Position, pp.Position + Camera.CFrame.LookVector)
    end
    local function c_destroy()
        for _,o in ipairs({fly.bv, fly.bg}) do
            if o and o.Parent then o:Destroy() end
        end
        fly.bv, fly.bg = nil,nil
    end

    --------------------------------------------------------------------
    -- Start/Stop (kein Teleport!)
    --------------------------------------------------------------------
    local function setEnabled(on)
        if on == fly.enabled then return end
        local v = vehicle()
        if on then
            if not v then notify("Car Fly","Kein Fahrzeug."); return end
            fly.pp = primaryPart(v)
            if not fly.pp or fly.pp.Anchored then notify("Car Fly","Kein PrimaryPart oder anchored."); return end

            -- Mode-spezifisch bauen
            if fly.mode == "A" then a_build(fly.pp)
            elseif fly.mode == "C" then c_build(fly.pp)
            end

            -- Ticker
            if fly.conn then fly.conn:Disconnect() end
            fly.conn = RunService.Heartbeat:Connect(function(dt)
                if not SV.isSeated() then return end
                if not fly.pp or not fly.pp.Parent then return end
                if fly.pp.Anchored then return end
                -- Optional: Ownership gate (meist safe)
                if typeof(isnetworkowner) == "function" then
                    local ok, owns = pcall(isnetworkowner, fly.pp)
                    if ok and not owns then return end
                end

                if fly.mode == "A" then
                    a_step(fly.pp, dt)
                elseif fly.mode == "B" then
                    b_step(fly.pp, dt)
                elseif fly.mode == "C" then
                    c_step(fly.pp, dt)
                end
            end)

            fly.enabled = true
            notify("Car Fly", ("ON (Mode %s, Speed %d)"):format(fly.mode, fly.speed), 2)
        else
            fly.enabled = false
            if fly.conn then fly.conn:Disconnect() fly.conn=nil end
            -- Mode cleanup (nichts teleportieren!)
            if fly.mode == "A" then a_destroy()
            elseif fly.mode == "C" then c_destroy()
            end
            fly.curVel = Vector3.new()
            notify("Car Fly","OFF", 2)
        end
    end

    local function toggle() setEnabled(not fly.enabled) end
    local function switchMode(newMode)
        if newMode == fly.mode then return end
        local wasOn = fly.enabled
        if wasOn then setEnabled(false) end
        fly.mode = newMode
        notify("Car Fly", "Mode "..newMode.." gewählt", 2)
        if wasOn then setEnabled(true) end
    end

    --------------------------------------------------------------------
    -- UI
    --------------------------------------------------------------------
    local sec = tab:AddSection({ Name = "Car Fly (Multi-Mode)" })

    sec:AddButton({ Name = "Mode A – LV + Hover (empfohlen)", Callback = function() switchMode("A") end })
    sec:AddButton({ Name = "Mode B – Δv Impulse (ApplyImpulse)", Callback = function() switchMode("B") end })
    sec:AddButton({ Name = "Mode C – Legacy Body* (riskant)", Callback = function() switchMode("C") end })

    sec:AddToggle({
        Name = "Fly Toggle",
        Default = false,
        Callback = function(v) setEnabled(v) end
    })

    sec:AddBind({
        Name = "Toggle Key (X)",
        Default = Enum.KeyCode.X,
        Hold = false,
        Callback = function() toggle() end
    })

    sec:AddSlider({
        Name = "Speed",
        Min = 10, Max = 300, Increment = 5,
        Default = DEFAULT_SPEED,
        Callback = function(v) fly.speed = math.floor(v) end
    })

    -- Sicherheitsnetz: aus wenn du den Sitz verlässt (ohne TP)
    RunService.Heartbeat:Connect(function()
        if fly.enabled and not SV.isSeated() then
            setEnabled(false)
        end
    end)
end
