-- tabs/functions/vehicle/vehicle/carfly_tp.lua
return function(SV, tab, OrionLib)
    -- TP Car Fly — hard cam-lock, anti-sag lift, no pre-latched camera

    local RunService = game:GetService("RunService")
    local UserInput  = game:GetService("UserInputService")
    local Players    = game:GetService("Players")
    local LP         = Players.LocalPlayer

    local notify = SV.notify

    -- ===== Tuning =====
    local DEFAULT_SPEED   = 260
    local MAX_STEP_DIST   = 1.0
    local MAX_SUBSTEPS    = 48

    -- slight upward bias to counter chase-cam's natural downward pitch
    local PITCH_LIFT      = 0.06   -- 0.04–0.10 typical
    local NEUTRAL_CLAMP   = -0.02  -- if look.Y is slightly below 0, clamp to 0 (removes tiny sink)

    -- SafeFly
    local SAFE_PERIOD     = 6.0
    local SAFE_HOLD       = 0.5
    local SAFE_BACK       = true
    local SAFE_RAY_DEPTH  = 4000

    local TOGGLE_KEY      = Enum.KeyCode.X

    -- ===== State =====
    local fly = {
        enabled=false, speed=DEFAULT_SPEED, safeOn=true,
        hbConn=nil, safeTask=nil, locking=false,
        uiToggle=nil, hold={F=false,B=false},
        hoverCF=nil, lastAirCF=nil, debounceTS=0,
    }

    -- ===== Helpers =====
    local function myVehicle() return SV.myVehicleFolder() end
    local function ensurePP(v) SV.ensurePrimaryPart(v); return v.PrimaryPart end
    local function setNetOwner(v) pcall(function() if v and v.PrimaryPart then v.PrimaryPart:SetNetworkOwner(LP) end end) end
    local function seated() return SV.isSeated() end

    local function hasInput()
        if UserInput:GetFocusedTextBox() then return false end
        return UserInput:IsKeyDown(Enum.KeyCode.W) or fly.hold.F
            or UserInput:IsKeyDown(Enum.KeyCode.S) or fly.hold.B
    end
    local function dirScalar()
        local d=0
        if not UserInput:GetFocusedTextBox() then
            if UserInput:IsKeyDown(Enum.KeyCode.W) or fly.hold.F then d+=1 end
            if UserInput:IsKeyDown(Enum.KeyCode.S) or fly.hold.B then d-=1 end
        end
        return d
    end

    local function hardPivot(v, cf)
        local pp = v.PrimaryPart
        if pp then
            pp.AssemblyLinearVelocity  = Vector3.zero
            pp.AssemblyAngularVelocity = Vector3.zero
        end
        v:PivotTo(cf)
    end

    -- ===== Core =====
    local function step(dt)
        if not fly.enabled or fly.locking then return end
        if not seated() then return end

        local v = myVehicle(); if not v then return end
        if not v.PrimaryPart then if not ensurePP(v) then return end end
        setNetOwner(v)

        -- read *fresh* camera every frame (no pre-latch)
        local cam   = workspace.CurrentCamera
        local look  = cam.CFrame.LookVector
        if look.Magnitude < 0.999 then look = look.Unit end
        local up    = cam.CFrame.UpVector

        local curCF  = v:GetPivot()
        local curPos = curCF.Position

        if not hasInput() then
            local keep = (fly.hoverCF and fly.hoverCF.Position) or curPos
            hardPivot(v, CFrame.lookAt(keep, keep + look, up))
            fly.lastAirCF = v:GetPivot()
            return
        end

        local s        = dirScalar()
        local total    = (fly.speed * dt) * (s >= 0 and 1 or -1)
        local absDist  = math.abs(total)
        local sub      = math.clamp(math.ceil(absDist / MAX_STEP_DIST), 1, MAX_SUBSTEPS)
        local stepDist = total / sub

        -- movement direction = full cam look + small anti-sag lift (forward gets lift, backward gets inverse)
        local moveLook = look
        if moveLook.Y < NEUTRAL_CLAMP then
            moveLook = Vector3.new(moveLook.X, 0, moveLook.Z).Unit
        end
        moveLook = (moveLook + Vector3.new(0, PITCH_LIFT * (s >= 0 and 1 or -1), 0)).Unit

        for _=1, sub do
            local target = curPos + (moveLook * stepDist)
            local newCF  = CFrame.lookAt(target, target + look, up) -- orientation = exact camera
            hardPivot(v, newCF)
            curPos = target
        end

        local final = CFrame.lookAt(curPos, curPos + look, up)
        hardPivot(v, final)
        fly.hoverCF, fly.lastAirCF = final, final
    end

    -- ===== SafeFly =====
    local function startSafeFly()
        if fly.safeTask then task.cancel(fly.safeTask) end
        fly.safeTask = task.spawn(function()
            while fly.enabled do
                if not fly.safeOn then
                    task.wait(0.25)
                else
                    task.wait(SAFE_PERIOD)
                    if not fly.enabled then break end

                    local v = myVehicle()
                    if v and (v.PrimaryPart or ensurePP(v)) then
                        local before  = fly.lastAirCF or v:GetPivot()
                        local probeCF = v:GetPivot()

                        local params = RaycastParams.new()
                        params.FilterType = Enum.RaycastFilterType.Blacklist
                        params.FilterDescendantsInstances = {v}

                        local hit = workspace:Raycast(probeCF.Position, Vector3.new(0, -SAFE_RAY_DEPTH, 0), params)
                        if hit then
                            fly.locking = true

                            local basePos  = Vector3.new(probeCF.Position.X, hit.Position.Y + 2, probeCF.Position.Z)
                            local cam      = workspace.CurrentCamera
                            local yawFwd   = (cam.CFrame.LookVector * Vector3.new(1,0,1))
                            yawFwd = (yawFwd.Magnitude > 1e-3) and yawFwd.Unit or Vector3.new(0,0,-1)
                            local groundCF = CFrame.lookAt(basePos, basePos + yawFwd, cam.CFrame.UpVector)

                            local seat = SV.findDriveSeat(v)
                            local hum  = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")

                            local t0 = os.clock()
                            while os.clock() - t0 < SAFE_HOLD and fly.enabled do
                                hardPivot(v, groundCF)
                                if seat and hum and seat.Occupant ~= hum then
                                    pcall(function() seat:Sit(hum) end)
                                end
                                RunService.Heartbeat:Wait()
                            end

                            if SAFE_BACK and fly.enabled then
                                hardPivot(v, before)
                                fly.hoverCF, fly.lastAirCF = before, before
                                if seat and hum and seat.Occupant ~= hum then
                                    pcall(function() seat:Sit(hum) end)
                                end
                            end

                            fly.locking = false
                        end
                    end
                end
            end
        end)
    end

    -- ===== Enable/Disable =====
    local function setEnabled(on)
        if on == fly.enabled then return end
        local v = myVehicle()

        if on then
            if not v then notify("Car Fly","No vehicle."); return end
            if not v.PrimaryPart then if not ensurePP(v) then notify("Car Fly","No PrimaryPart."); return end end
            setNetOwner(v)

            local cf = v:GetPivot()
            fly.hoverCF, fly.lastAirCF = cf, cf

            if fly.hbConn then fly.hbConn:Disconnect() end
            fly.hbConn = RunService.Heartbeat:Connect(step)

            startSafeFly()
            fly.enabled = true
            if fly.uiToggle then fly.uiToggle:Set(true) end
            notify("Car Fly", ("Enabled (Speed %d)"):format(fly.speed), 2)
        else
            fly.enabled = false
            if fly.hbConn   then fly.hbConn:Disconnect();   fly.hbConn  = nil end
            if fly.safeTask then task.cancel(fly.safeTask); fly.safeTask = nil end
            fly.locking = false
            if fly.uiToggle then fly.uiToggle:Set(false) end
            notify("Car Fly","Disabled.", 2)
        end
    end

    local function toggle()
        local now = os.clock()
        if now - fly.debounceTS < 0.15 then return end
        fly.debounceTS = now
        setEnabled(not fly.enabled)
    end

    -- ===== UI =====
    local sec = tab:AddSection({ Name = "Car Fly (TP, anti-sag)" })
    fly.uiToggle = sec:AddToggle({
        Name = "Enable Car Fly (vehicle only)",
        Default = false,
        Callback = function(v) setEnabled(v) end
    })
    sec:AddBind({
        Name = "Car Fly Toggle Key",
        Default = TOGGLE_KEY,
        Hold = false,
        Callback = function() toggle() end
    })
    sec:AddSlider({
        Name = "Speed",
        Min = 10, Max = 520, Increment = 5,
        Default = DEFAULT_SPEED,
        Callback = function(v) fly.speed = math.floor(v) end
    })
    sec:AddToggle({
        Name = "Safe Fly (ground every 6s, hold 0.5s, return)",
        Default = true,
        Callback = function(v) fly.safeOn = v end
    })

    -- Auto-Off when leaving seat
    RunService.Heartbeat:Connect(function()
        if fly.enabled and not seated() then setEnabled(false) end
    end)

    print("[carfly v4.9.4] loaded")
end
