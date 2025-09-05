-- tabs/functions/vehicle/vehicle/carfly_tp.lua
return function(SV, tab, OrionLib)
    -- Car Fly (TP-based, precise cam-follow)
    -- - Strictly moves along camera forward; orientation = camera Look+Up
    -- - One-time model-forward alignment (fixes side-entry / weird forward axes)
    -- - Substep teleport for smoothness; SafeFly ground lock with optional return

    local RunService = game:GetService("RunService")
    local UserInput  = game:GetService("UserInputService")
    local Players    = game:GetService("Players")
    local LP         = Players.LocalPlayer

    local Camera  = SV.Camera
    local notify  = SV.notify

    ----------------------------------------------------------------
    -- Tuning
    ----------------------------------------------------------------
    local DEFAULT_SPEED   = 260       -- studs/s
    local MAX_STEP_DIST   = 1.25      -- smaller = smoother
    local MAX_SUBSTEPS    = 48

    -- SafeFly
    local SAFE_PERIOD     = 6.0
    local SAFE_HOLD       = 0.5
    local SAFE_BACK       = true
    local SAFE_RAY_DEPTH  = 4000

    local TOGGLE_KEY      = Enum.KeyCode.X
    local REALIGN_KEY     = Enum.KeyCode.R

    ----------------------------------------------------------------
    -- State
    ----------------------------------------------------------------
    local fly = {
        enabled    = false,
        speed      = DEFAULT_SPEED,
        safeOn     = true,

        hbConn     = nil,
        safeTask   = nil,
        locking    = false,

        uiToggle   = nil,
        hold       = {F=false, B=false},

        hoverCF    = nil,  -- last stable CF
        lastAirCF  = nil,  -- for SafeFly return
        alignRot   = nil,  -- model-forward alignment (rotation-only)
        debounceTS = 0,

        _didRecal  = false,
    }

    -- Camera samples captured on RenderStepped
    local lastLook, lastUp

    ----------------------------------------------------------------
    -- Helpers
    ----------------------------------------------------------------
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
        local d = 0
        if not UserInput:GetFocusedTextBox() then
            if UserInput:IsKeyDown(Enum.KeyCode.W) or fly.hold.F then d += 1 end
            if UserInput:IsKeyDown(Enum.KeyCode.S) or fly.hold.B then d -= 1 end
        end
        return d -- -1,0,+1
    end

    -- Build a pure-rotation CFrame from an object-space delta (removes translation)
    local function rotationOnly(ofs)
        return CFrame.fromMatrix(Vector3.new(), ofs.XVector, ofs.YVector, ofs.ZVector)
    end

    local function calibrateAlign(v)
        -- wait 1 frame to let the seat/camera settle
        RunService.RenderStepped:Wait()
        local cf   = v:GetPivot()
        local cam  = workspace.CurrentCamera.CFrame
        local want = CFrame.lookAt(cf.Position, cf.Position + cam.LookVector, cam.UpVector)
        local rel  = cf:ToObjectSpace(want)
        fly.alignRot = rotationOnly(rel)
    end

    ----------------------------------------------------------------
    -- Core (Heartbeat + TP substeps)
    ----------------------------------------------------------------
    -- Read camera on RenderStepped for stable values
    RunService.RenderStepped:Connect(function()
        local c = workspace.CurrentCamera.CFrame
        lastLook, lastUp = c.LookVector, c.UpVector
    end)

    local function step(dt)
        if not fly.enabled or fly.locking then return end
        if not seated() then return end

        local v = myVehicle(); if not v then return end
        if not v.PrimaryPart then if not ensurePP(v) then return end end
        setNetOwner(v)

        local curCF  = v:GetPivot()
        local curPos = curCF.Position

        local look = lastLook or Camera.CFrame.LookVector
        if look.Magnitude < 0.999 then look = look.Unit end
        local up   = lastUp   or Camera.CFrame.UpVector

        -- Idle: freeze position but match camera orientation exactly
        if not hasInput() then
            local keepPos = (fly.hoverCF and fly.hoverCF.Position) or curPos
            local lockCF  = CFrame.lookAt(keepPos, keepPos + look, up)
            if fly.alignRot then lockCF = lockCF * fly.alignRot end
            v:PivotTo(lockCF)
            fly.lastAirCF = lockCF
            return
        end

        -- Move strictly along the full camera forward vector
        local s         = dirScalar()
        local total     = (fly.speed * dt) * (s >= 0 and 1 or -1)
        local absDist   = math.abs(total)
        local substeps  = math.clamp(math.ceil(absDist / MAX_STEP_DIST), 1, MAX_SUBSTEPS)
        local stepDist  = total / substeps

        for _ = 1, substeps do
            local target = curPos + (look * stepDist)
            local newCF  = CFrame.lookAt(target, target + look, up)
            if fly.alignRot then newCF = newCF * fly.alignRot end
            v:PivotTo(newCF)
            curPos = target
        end

        local final = CFrame.lookAt(curPos, curPos + look, up)
        if fly.alignRot then final = final * fly.alignRot end
        fly.hoverCF, fly.lastAirCF = final, final
    end

    ----------------------------------------------------------------
    -- SafeFly (periodic ground lock + optional return)
    ----------------------------------------------------------------
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

                            local basePos = Vector3.new(probeCF.Position.X, hit.Position.Y + 2, probeCF.Position.Z)
                            -- keep yaw from camera, use camera Up for stability
                            local yawFwd = (workspace.CurrentCamera.CFrame.LookVector * Vector3.new(1,0,1)).Unit
                            if yawFwd.Magnitude < 1e-3 then yawFwd = Vector3.new(0,0,-1) end
                            local groundCF = CFrame.lookAt(basePos, basePos + yawFwd, workspace.CurrentCamera.CFrame.UpVector)
                            if fly.alignRot then groundCF = groundCF * fly.alignRot end

                            local seat = SV.findDriveSeat(v)
                            local hum  = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")

                            local t0 = os.clock()
                            while os.clock() - t0 < SAFE_HOLD and fly.enabled do
                                v:PivotTo(groundCF)
                                if seat and hum and seat.Occupant ~= hum then
                                    pcall(function() seat:Sit(hum) end)
                                end
                                RunService.Heartbeat:Wait()
                            end

                            if SAFE_BACK and fly.enabled then
                                v:PivotTo(before)
                                fly.hoverCF   = before
                                fly.lastAirCF = before
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

    ----------------------------------------------------------------
    -- Enable/Disable + alignment calibration
    ----------------------------------------------------------------
    local function setEnabled(on)
        if on == fly.enabled then return end
        local v = myVehicle()

        if on then
            if not v then notify("Car Fly","No vehicle."); return end
            if not v.PrimaryPart then if not ensurePP(v) then notify("Car Fly","No PrimaryPart."); return end end
            setNetOwner(v)

            local cf = v:GetPivot()
            fly.hoverCF   = cf
            fly.lastAirCF = cf

            calibrateAlign(v)              -- initial align
            fly._didRecal = false          -- allow one re-calibration after first seated()

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
            fly.locking  = false
            fly.alignRot = nil
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

    ----------------------------------------------------------------
    -- UI
    ----------------------------------------------------------------
    local sec = tab:AddSection({ Name = "Car Fly (TP, precise cam-follow)" })
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
    sec:AddBind({
        Name = "Recalibrate Align",
        Default = REALIGN_KEY,
        Hold = false,
        Callback = function()
            local v = myVehicle()
            if v and ensurePP(v) then calibrateAlign(v); notify("Car Fly","Re-aligned.", 2) end
        end
    })

    -- Auto-Off when leaving seat + first-seat re-alignment
    RunService.Heartbeat:Connect(function()
        if fly.enabled then
            if not seated() then
                if fly._didRecal then fly._didRecal = false end
                setEnabled(false)
            elseif not fly._didRecal then
                fly._didRecal = true
                local v = myVehicle(); if v and ensurePP(v) then calibrateAlign(v) end
            end
        end
    end)

    print("[carfly v4.9.3] loaded")
end
