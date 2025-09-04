-- tabs/vehicle/powerdrive.lua
-- Boden-Boost: nutzt VectorForce nur wenn Bodenkontakt + Taste W/S.
return function(SV, tab, OrionLib)
    local RS, UIS, WS = SV.Services.RunService, SV.Services.UserInput, SV.Services.Workspace
    local notify = SV.notify

    local PD = {
        enabled = false, conn = nil,
        pp=nil, att=nil, vf=nil,
        accel=55, speedCap=85, traction=0.10
    }

    local function projOnPlane(v, n)
        if n.Magnitude == 0 then return v end
        local u = n.Unit
        return v - u * v:Dot(u)
    end

    local function destroy()
        if PD.conn then PD.conn:Disconnect() PD.conn=nil end
        if PD.vf then PD.vf.Force = Vector3.new() end
        for _,x in ipairs({PD.vf, PD.att}) do if x and x.Parent then x:Destroy() end end
        PD.pp, PD.vf, PD.att = nil,nil,nil
    end

    local function build(v)
        SV.ensurePrimaryPart(v)
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

    local function ensureBuilt()
        if PD.pp and PD.pp.Parent then return true end
        local v = SV.myVehicleFolder(); if not v then return false end
        return build(v)
    end

    local function step(dt)
        if not PD.enabled then return end
        if not ensureBuilt() then if PD.vf then PD.vf.Force = Vector3.new() end return end

        -- Bodenkontakt?
        local vModel = PD.pp:FindFirstAncestorOfClass("Model")
        local pivot = (vModel and vModel:GetPivot()) or PD.pp.CFrame
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Blacklist
        params.FilterDescendantsInstances = {vModel}
        local hit = WS:Raycast(pivot.Position, Vector3.new(0,-8,0), params)

        if not hit then PD.vf.Force = Vector3.new(); return end

        -- Input nur W/S -> keine Eigenbeschleunigung
        local t = 0
        if UIS:IsKeyDown(Enum.KeyCode.W) then t =  1 end
        if UIS:IsKeyDown(Enum.KeyCode.S) then t = -1 end

        local fwd = PD.pp.CFrame.LookVector
        fwd = projOnPlane(fwd, hit.Normal)
        if fwd.Magnitude > 0 then fwd = fwd.Unit end

        local desired_a = Vector3.zero
        if t ~= 0 then
            desired_a = fwd * (t * PD.accel)
            -- Speed-Cap in Ebene
            local vel   = PD.pp.AssemblyLinearVelocity
            local vPlan = projOnPlane(vel, hit.Normal)
            if vPlan.Magnitude > PD.speedCap and (t * vPlan:Dot(fwd)) > 0 then
                desired_a = Vector3.new()
            end
        end

        -- Quer-Dämpfung etwas reduzieren, aber nie beschleunigen ohne Input
        local velPlan = projOnPlane(PD.pp.AssemblyLinearVelocity, hit.Normal)
        local lateral = velPlan - fwd * velPlan:Dot(fwd)
        local dragF   = -lateral * (PD.traction * math.max(PD.pp.AssemblyMass,1))

        PD.vf.Force = desired_a * math.max(PD.pp.AssemblyMass,1) + dragF
    end

    local function toggle(state)
        if state == nil then state = not PD.enabled end
        if state == PD.enabled then return end

        if not state then
            PD.enabled = false
            destroy()
            notify("PowerDrive","Off")
            return
        end

        local v = SV.myVehicleFolder(); if not v then notify("PowerDrive","Kein Fahrzeug."); return end
        if not build(v) then notify("PowerDrive","Kein PrimaryPart."); return end

        PD.enabled = true
        notify("PowerDrive","On")
        if PD.conn then PD.conn:Disconnect() PD.conn=nil end
        PD.conn = RS.RenderStepped:Connect(step)
    end

    -- UI
    local sec = tab:AddSection({ Name = "PowerDrive (Boden-Boost)" })
    sec:AddToggle({ Name = "PowerDrive aktivieren", Default = false, Callback = toggle })
    sec:AddSlider({
        Name = "Beschleunigung (stud/s^2)",
        Min=20, Max=150, Increment=5, Default=PD.accel,
        Callback = function(v) PD.accel = math.floor(v) end
    })
    sec:AddSlider({
        Name = "Speed-Cap (stud/s)",
        Min=30, Max=200, Increment=5, Default=PD.speedCap,
        Callback = function(v) PD.speedCap = math.floor(v) end
    })
end
