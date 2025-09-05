-- tabs/functions/vehicle/vehicle/carfly_tp.lua
return function(SV, tab, OrionLib)
print("[carfly v5.0.4] loaded")

    ----------------------------------------------------------------
    -- Services & Locals
    ----------------------------------------------------------------
    local RS           = game:GetService("ReplicatedStorage")
    local RunService   = game:GetService("RunService")
    local UserInput    = game:GetService("UserInputService")
    local Players      = game:GetService("Players")
    local LP           = Players.LocalPlayer

    local Camera       = SV.Camera
    local notify       = SV.notify

    -- Vehicles + Seat Remote
    local VehiclesFolder  = workspace:WaitForChild("Vehicles")
    local Bnl             = RS:WaitForChild("Bnl")
    local SeatRemote      = Bnl:WaitForChild("fdffc7c3-4c83-4693-8a33-380ed2d60083") -- << anpassen falls anders

    ----------------------------------------------------------------
    -- Config (constants, no UI sliders)
    ----------------------------------------------------------------
    local DEFAULT_SPEED  = 130
    local MIN_SPEED      = 10
    local MAX_SPEED      = 190

    local MAX_STEP_DIST  = 4
    local MAX_SUBSTEPS   = 18

    local SAFE_PERIOD    = 6.0
    local SAFE_HOLD      = 0.5
    local SAFE_RAY_DEPTH = 4000

    local TOGGLE_KEY     = Enum.KeyCode.X

    ----------------------------------------------------------------
    -- State
    ----------------------------------------------------------------
    local fly = {
        enabled   = false,
        speed     = DEFAULT_SPEED,
        hbConn    = nil,
        safeTask  = nil,
        locking   = false,
        uiToggle  = nil,
        hoverCF   = nil,
        lastAirCF = nil,
        lastYaw   = Vector3.new(1,0,0),
        debounceTS= 0,
    }

    ----------------------------------------------------------------
    -- Helpers
    ----------------------------------------------------------------
    local function myVehicle()
        return SV.myVehicleFolder()
    end
    local function ensurePP(v)
        SV.ensurePrimaryPart(v)
        return v.PrimaryPart
    end
    local function setNetOwner(v)
        pcall(function()
            if v and v.PrimaryPart then
                v.PrimaryPart:SetNetworkOwner(LP)
            end
        end)
    end
    local function seated()
        return SV.isSeated()
    end
    local function dirScalar()
        local d = 0
        if not UserInput:GetFocusedTextBox() then
            if UserInput:IsKeyDown(Enum.KeyCode.W) then d += 1 end
            if UserInput:IsKeyDown(Enum.KeyCode.S) then d -= 1 end
        end
        return d
    end
    local function reseatServer(vModel, seatIndex)
        pcall(function()
            SeatRemote:FireServer(vModel:FindFirstChild("DriveSeat"), "Oj2", false)
        end)
    end

    ----------------------------------------------------------------
    -- Flight Step
    ----------------------------------------------------------------
    local function step(dt)
        if not fly.enabled or fly.locking or not seated() then return end
        local v = myVehicle(); if not v then return end
        if not v.PrimaryPart then if not ensurePP(v) then return end end
        setNetOwner(v)

        local curCF  = v:GetPivot()
        local curPos = curCF.Position

        local look = Camera.CFrame.LookVector
        if look.Magnitude < 0.999 then look = look.Unit end

        local yaw = Vector3.new(look.X, 0, look.Z)
        if yaw.Magnitude < 1e-3 then yaw = fly.lastYaw else yaw = yaw.Unit; fly.lastYaw = yaw end

        local s = dirScalar()
        if s == 0 then
            local keepPos = (fly.hoverCF and fly.hoverCF.Position) or curPos
            local lockCF  = CFrame.new(keepPos, keepPos + look)
            v:PivotTo(lockCF)
            fly.lastAirCF = lockCF
            return
        end

        local totalDist   = fly.speed * dt
        local substeps    = math.clamp(math.ceil(totalDist / MAX_STEP_DIST), 1, MAX_SUBSTEPS)
        local stepDist    = totalDist / substeps

        for _ = 1, substeps do
            local horiz  = yaw * (stepDist * (s > 0 and 1 or -1))
            local target = curPos + horiz
            local newCF  = CFrame.new(target, target + look)
            v:PivotTo(newCF)
            curPos = target
        end

        local finalCF = CFrame.new(curPos, curPos + look)
        fly.hoverCF   = finalCF
        fly.lastAirCF = finalCF
    end

    ----------------------------------------------------------------
    -- SafeFly (hard reset, server reseat)
    ----------------------------------------------------------------
    local function startSafeFly()
        if fly.safeTask then task.cancel(fly.safeTask) end
        fly.safeTask = task.spawn(function()
            while fly.enabled do
                task.wait(SAFE_PERIOD)
                if not fly.enabled then break end

                local v = myVehicle()
                if v and (v.PrimaryPart or ensurePP(v)) then
                    local before = fly.lastAirCF or v:GetPivot()
                    local probeCF = v:GetPivot()

                    -- Raycast straight down
                    local params = RaycastParams.new()
                    params.FilterType = Enum.RaycastFilterType.Blacklist
                    params.FilterDescendantsInstances = {v}

                    local hit = workspace:Raycast(probeCF.Position, Vector3.new(0, -SAFE_RAY_DEPTH, 0), params)
                    if hit then
                        fly.locking = true

                        local base = Vector3.new(probeCF.Position.X, hit.Position.Y + 2, probeCF.Position.Z)
                        local groundCF = CFrame.new(base, base + fly.lastYaw)

                        local t0 = os.clock()
                        while os.clock() - t0 < SAFE_HOLD and fly.enabled do
                            v:PivotTo(groundCF)
                            v.PrimaryPart.AssemblyLinearVelocity  = Vector3.zero
                            v.PrimaryPart.AssemblyAngularVelocity = Vector3.zero
                            reseatServer(v, 0) -- spam remote
                            RunService.Heartbeat:Wait()
                        end

                        if fly.enabled then
                            v:PivotTo(before)
                            fly.hoverCF   = before
                            fly.lastAirCF = before
                            reseatServer(v, 0)
                        end

                        fly.locking = false
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
            if not v then notify("Car Fly","Kein Fahrzeug."); return end
            if not v.PrimaryPart then if not ensurePP(v) then notify("Car Fly","Kein PrimaryPart."); return end end
            setNetOwner(v)

            local cf = v:GetPivot()
            fly.hoverCF   = cf
            fly.lastAirCF = cf

            local lk = Camera.CFrame.LookVector
            local y  = Vector3.new(lk.X,0,lk.Z)
            if y.Magnitude > 1e-3 then fly.lastYaw = y.Unit end

            if fly.hbConn then fly.hbConn:Disconnect() end
            fly.hbConn = RunService.Heartbeat:Connect(step)

            startSafeFly()
            fly.enabled = true
            if fly.uiToggle then fly.uiToggle:Set(true) end
            notify("Car Fly", ("Aktiviert (Speed %d)"):format(fly.speed), 2)
        else
            fly.enabled = false
            if fly.hbConn   then fly.hbConn:Disconnect();   fly.hbConn  = nil end
            if fly.safeTask then task.cancel(fly.safeTask); fly.safeTask = nil end
            fly.locking = false
            if fly.uiToggle then fly.uiToggle:Set(false) end
            notify("Car Fly","Deaktiviert.", 2)
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
    local sec = tab:AddSection({ Name = "Car Fly v5.0.4" })
    fly.uiToggle = sec:AddToggle({
        Name = "Enable Car Fly",
        Default = false,
        Callback = function(v) setEnabled(v) end
    })
    sec:AddBind({
        Name = "Car Fly Toggle Key",
        Default = TOGGLE_KEY,
        Hold = false,
        Callback = function() toggle() end
    })

    -- Auto-Off beim Aussteigen
    RunService.Heartbeat:Connect(function()
        if fly.enabled and not seated() then setEnabled(false) end
    end)
end
