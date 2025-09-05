-- tabs/functions/vehicle/vehicle/carfly_tp.lua
return function(SV, tab, OrionLib)

    ----------------------------------------------------------------
    -- Car Fly (TP, precise) + SafeFly with server-side reseat only
    -- Version: 5.0.3
    ----------------------------------------------------------------

    ----------------------------------------------------------------
    -- TUNABLES
    ----------------------------------------------------------------
    local TUNE = {
        -- Flight core
        SPEED_DEFAULT   = 130,  -- studs/s
        STEP_DIST       = 1.0,
        SUBSTEPS_MAX    = 48,

        -- Camera->vertical response
        VERT_GAIN       = 1.00,
        Y_BIAS          = 0.00,

        -- Idle autoground
        AUTOGROUND      = true,
        AUTOGROUND_PAD  = 2.0,
        RAY_DEPTH       = 4000,

        -- SafeFly
        SAFE_PERIOD     = 6.0,
        SAFE_HOLD       = 0.5,
        SAFE_BACK       = true,

        -- Server ReSeat (no local Sit/ChangeState)
        RESEAT_ENABLED  = true,
        REMOTE_FOLDER   = "Bnl",
        VEHICLES_FOLDER = "Vehicles",
    }

    ----------------------------------------------------------------
    -- Services / Shortcuts
    ----------------------------------------------------------------
    local RunService = game:GetService("RunService")
    local UserInput  = game:GetService("UserInputService")
    local Players    = game:GetService("Players")
    local RS         = game:GetService("ReplicatedStorage")
    local LP         = Players.LocalPlayer
    local notify     = SV.notify

    ----------------------------------------------------------------
    -- State
    ----------------------------------------------------------------
    local fly = {
        enabled   = false,
        speed     = TUNE.SPEED_DEFAULT,
        safeOn    = true,

        hbConn    = nil,
        safeTask  = nil,
        locking   = false,

        uiToggle  = nil,
        hoverCF   = nil,
        lastAirCF = nil,
        debounce  = 0,
    }

    ----------------------------------------------------------------
    -- Helpers
    ----------------------------------------------------------------
    local function myVehicle() return SV.myVehicleFolder() end
    local function ensurePP(v) SV.ensurePrimaryPart(v); return v.PrimaryPart end
    local function setNetOwner(v) pcall(function() if v and v.PrimaryPart then v.PrimaryPart:SetNetworkOwner(LP) end end) end
    local function seated() return SV.isSeated() end

    local function hasInput()
        if UserInput:GetFocusedTextBox() then return false end
        return UserInput:IsKeyDown(Enum.KeyCode.W) or UserInput:IsKeyDown(Enum.KeyCode.S)
    end
    local function dirScalar()
        local d = 0
        if not UserInput:GetFocusedTextBox() then
            if UserInput:IsKeyDown(Enum.KeyCode.W) then d += 1 end
            if UserInput:IsKeyDown(Enum.KeyCode.S) then d -= 1 end
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

    local function groundHit(origin, depth, ignore)
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Blacklist
        params.FilterDescendantsInstances = ignore or {}
        return workspace:Raycast(origin, Vector3.new(0, -(depth or TUNE.RAY_DEPTH), 0), params)
    end

    -- DriveSeat lookup
    local function findSeat(v)
        return SV.findDriveSeat(v) or v:FindFirstChild("DriveSeat")
    end

    -- Dynamic RemoteEvents in RS.Bnl (UUIDs change; fire all)
    local VehiclesFolder = workspace:FindFirstChild(TUNE.VEHICLES_FOLDER)
    local BnlFolder      = RS:FindFirstChild(TUNE.REMOTE_FOLDER)
    local function seatRemotes()
        local out = {}
        local folder = BnlFolder or RS:FindFirstChild(TUNE.REMOTE_FOLDER)
        if not folder then return out end
        for _,ch in ipairs(folder:GetChildren()) do
            if ch:IsA("RemoteEvent") then
                table.insert(out, ch)
            end
        end
        return out
    end
    local cachedSeatRemotes = seatRemotes()

    -- FireServer signature observed in live traffic: (DriveSeat, "Oj2", false)
    local function reseatServerBySeat(seat)
        if not (TUNE.RESEAT_ENABLED and seat) then return end
        for _,re in ipairs(cachedSeatRemotes) do
            pcall(function()
                re:FireServer(seat, "Oj2", false)
            end)
        end
    end

    ----------------------------------------------------------------
    -- Core Flight Step
    ----------------------------------------------------------------
    local function step(dt)
        if not fly.enabled or fly.locking then return end
        if not seated() then return end

        local v = myVehicle(); if not v then return end
        if not v.PrimaryPart then if not ensurePP(v) then return end end
        setNetOwner(v)

        local cam   = workspace.CurrentCamera
        local look  = cam.CFrame.LookVector
        if look.Magnitude < 0.999 then look = look.Unit end
        local up    = cam.CFrame.UpVector

        local curCF  = v:GetPivot()
        local curPos = curCF.Position

        local s = dirScalar()
        if s == 0 then
            if TUNE.AUTOGROUND then
                local hit = groundHit(curPos, TUNE.RAY_DEPTH, {v})
                if hit then
                    local basePos = Vector3.new(curPos.X, hit.Position.Y + TUNE.AUTOGROUND_PAD, curPos.Z)
                    local yawFwd  = (look * Vector3.new(1,0,1))
                    yawFwd = (yawFwd.Magnitude > 1e-3) and yawFwd.Unit or Vector3.new(0,0,-1)

                    local seat = findSeat(v)
                    reseatServerBySeat(seat) -- server-ack before lock

                    local groundCF = CFrame.lookAt(basePos, basePos + yawFwd, up)
                    hardPivot(v, groundCF)
                    fly.hoverCF, fly.lastAirCF = groundCF, groundCF
                    return
                end
            end

            local keep = (fly.hoverCF and fly.hoverCF.Position) or curPos
            local lock = CFrame.lookAt(keep, keep + look, up)
            hardPivot(v, lock)
            fly.lastAirCF = lock
            return
        end

        local total    = (fly.speed * dt) * (s >= 0 and 1 or -1)
        local absDist  = math.abs(total)
        local sub      = math.clamp(math.ceil(absDist / TUNE.STEP_DIST), 1, TUNE.SUBSTEPS_MAX)
        local stepDist = total / sub

        local moveLook = Vector3.new(look.X, look.Y * TUNE.VERT_GAIN + TUNE.Y_BIAS, look.Z)
        if moveLook.Magnitude < 1e-3 then moveLook = look else moveLook = moveLook.Unit end

        for _ = 1, sub do
            local target = curPos + (moveLook * stepDist)
            local newCF  = CFrame.lookAt(target, target + look, up)
            hardPivot(v, newCF)
            curPos = target
        end

        local final = CFrame.lookAt(curPos, curPos + look, up)
        hardPivot(v, final)
        fly.hoverCF, fly.lastAirCF = final, final
    end

    ----------------------------------------------------------------
    -- SafeFly
    ----------------------------------------------------------------
    local function startSafeFly()
        if fly.safeTask then task.cancel(fly.safeTask) end
        fly.safeTask = task.spawn(function()
            while fly.enabled do
                if not fly.safeOn then
                    task.wait(0.25)
                else
                    task.wait(TUNE.SAFE_PERIOD)
                    if not fly.enabled then break end

                    local v = myVehicle()
                    if v and (v.PrimaryPart or ensurePP(v)) then
                        local before  = fly.lastAirCF or v:GetPivot()
                        local probeCF = v:GetPivot()

                        local hit = groundHit(probeCF.Position, TUNE.RAY_DEPTH, {v})
                        if hit then
                            fly.locking = true

                            local base   = Vector3.new(probeCF.Position.X, hit.Position.Y + TUNE.AUTOGROUND_PAD, probeCF.Position.Z)
                            local cam    = workspace.CurrentCamera
                            local yawFwd = (cam.CFrame.LookVector * Vector3.new(1,0,1))
                            yawFwd = (yawFwd.Magnitude > 1e-3) and yawFwd.Unit or Vector3.new(0,0,-1)
                            local groundCF = CFrame.lookAt(base, base + yawFwd, cam.CFrame.UpVector)

                            local seat = findSeat(v)

                            -- Server reseat BEFORE first lock, then each frame during lock
                            reseatServerBySeat(seat)

                            local t0 = os.clock()
                            while os.clock() - t0 < TUNE.SAFE_HOLD and fly.enabled do
                                hardPivot(v, groundCF)
                                reseatServerBySeat(seat)
                                RunService.Heartbeat:Wait()
                            end

                            if TUNE.SAFE_BACK and fly.enabled then
                                hardPivot(v, before)
                                fly.hoverCF, fly.lastAirCF = before, before
                                reseatServerBySeat(seat)
                            end

                            fly.locking = false
                        end
                    end
                end
            end
        end)
    end

    ----------------------------------------------------------------
    -- Enable/Disable
    ----------------------------------------------------------------
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
        if now - fly.debounce < 0.15 then return end
        fly.debounce = now
        setEnabled(not fly.enabled)
    end

    ----------------------------------------------------------------
    -- UI
    ----------------------------------------------------------------
    local sec = tab:AddSection({ Name = "Car Fly (TP, tunables)" })
    fly.uiToggle = sec:AddToggle({
        Name = "Enable Car Fly (vehicle only)",
        Default = false,
        Callback = function(v) setEnabled(v) end
    })
    sec:AddBind({
        Name = "Toggle Key",
        Default = Enum.KeyCode.X,
        Hold = false,
        Callback = function() toggle() end
    })
    -- constrain to 10..190 as requested
    sec:AddSlider({
        Name = "Speed",
        Min = 10, Max = 190, Increment = 5,
        Default = TUNE.SPEED_DEFAULT,
        Callback = function(v) fly.speed = math.clamp(math.floor(v), 10, 190) end
    })
    sec:AddSlider({
        Name = "Vertical Gain (Y * gain)",
        Min = 0.50, Max = 1.60, Increment = 0.05,
        Default = TUNE.VERT_GAIN,
        Callback = function(v) TUNE.VERT_GAIN = v end
    })
    sec:AddSlider({
        Name = "Y Bias (+/-)",
        Min = -0.20, Max = 0.20, Increment = 0.01,
        Default = TUNE.Y_BIAS,
        Callback = function(v) TUNE.Y_BIAS = v end
    })
    sec:AddSlider({
        Name = "Step Distance",
        Min = 0.50, Max = 4.00, Increment = 0.05,
        Default = TUNE.STEP_DIST,
        Callback = function(v) TUNE.STEP_DIST = v end
    })
    sec:AddSlider({
        Name = "Max Substeps",
        Min = 8, Max = 64, Increment = 1,
        Default = TUNE.SUBSTEPS_MAX,
        Callback = function(v) TUNE.SUBSTEPS_MAX = math.floor(v) end
    })
    sec:AddToggle({
        Name = "Idle Autoground",
        Default = TUNE.AUTOGROUND,
        Callback = function(v) TUNE.AUTOGROUND = v end
    })
    sec:AddToggle({
        Name = "Safe Fly",
        Default = true,
        Callback = function(v) fly.safeOn = v end
    })
    sec:AddToggle({
        Name = "Server ReSeat during locks",
        Default = TUNE.RESEAT_ENABLED,
        Callback = function(v) TUNE.RESEAT_ENABLED = v end
    })

    -- Auto-Off when leaving seat
    RunService.Heartbeat:Connect(function()
        if fly.enabled and not seated() then setEnabled(false) end
    end)

    print("[carfly v5.0.4] loaded Safe? IDK")
end
