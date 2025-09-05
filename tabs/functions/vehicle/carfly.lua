-- tabs/functions/vehicle/vehicle/carfly_tp.lua
return function(SV, tab, OrionLib)

    ----------------------------------------------------------------
    -- Car Fly (TP, precise cam-follow) + SafeFly (reliable reseat)
    -- Version: 5.0.3
    ----------------------------------------------------------------

    -- Services
    local RunService = game:GetService("RunService")
    local UserInput  = game:GetService("UserInputService")
    local Players    = game:GetService("Players")
    local RS         = game:GetService("ReplicatedStorage")
    local LP         = Players.LocalPlayer
    local Camera     = workspace.CurrentCamera

    -- Game folders (per spec)
    local VehiclesFolder = workspace:WaitForChild("Vehicles")
    local BnlFolder      = RS:WaitForChild("Bnl")

    -- SV shortcuts
    local notify       = SV.notify
    local function myVehicle() return SV.myVehicleFolder() end
    local function ensurePP(v) SV.ensurePrimaryPart(v); return v.PrimaryPart end
    local function findSeat(v) return SV.findDriveSeat(v) end
    local function isSeated()  return SV.isSeated() end

    ----------------------------------------------------------------
    -- Tunables (script-only)
    ----------------------------------------------------------------
    local MIN_SPEED     = 10
    local MAX_SPEED     = 190
    local DEFAULT_SPEED = 130

    local STEP_DIST     = 1.0     -- max TP per substep
    local SUBSTEPS_MAX  = 48

    local SAFE_PERIOD   = 6.0     -- seconds between locks
    local SAFE_HOLD     = 0.5     -- hold on ground
    local SAFE_BACK     = true    -- return to air pos
    local SAFE_RAY_DEPTH= 4000
    local GROUND_PAD_Y  = 2

    local TOGGLE_KEY    = Enum.KeyCode.X

    ----------------------------------------------------------------
    -- Dynamic Remote handling
    --  - Vehicle path: workspace.Vehicles:<ownerName>:DriveSeat
    --  - Remotes live in RS.Bnl and have UUID-like names
    --  - Call pattern seen in-game: FireServer(DriveSeat, "Oj2", false)
    ----------------------------------------------------------------
    local function allSeatRemotes()
        local list = {}
        for _, ch in ipairs(BnlFolder:GetChildren()) do
            if ch:IsA("RemoteEvent") then
                list[#list+1] = ch
            end
        end
        return list
    end

    local cachedSeatRemotes = allSeatRemotes()

    local function reseatServerBySeat(seat)
        if not seat then return end
        -- fire on all Bnl remotes to be robust (server ignores wrong ones)
        for _, re in ipairs(cachedSeatRemotes) do
            pcall(function()
                re:FireServer(seat, "Oj2", false)
            end)
        end
    end

    local function vehicleModelForLocal()
        -- Vehicle is named like the owner username (without @)
        local model = VehiclesFolder:FindFirstChild(LP.Name)
        if model and model:IsA("Model") then return model end
        -- fallback: try character display name or any model with DriveSeat owned by LP
        for _, m in ipairs(VehiclesFolder:GetChildren()) do
            if m:IsA("Model") and m:FindFirstChild("DriveSeat") then
                return m
            end
        end
        return nil
    end

    ----------------------------------------------------------------
    -- State
    ----------------------------------------------------------------
    local fly = {
        enabled    = false,
        safeOn     = true,
        speed      = DEFAULT_SPEED,

        hbConn     = nil,
        locking    = false,

        uiToggle   = nil,
        hoverCF    = nil,
        lastAirCF  = nil,

        debounce   = 0,
        nextSafeAt = nil,  -- absolute time for next SafeFly
    }

    ----------------------------------------------------------------
    -- Helpers
    ----------------------------------------------------------------
    local function setNetOwner(v)
        pcall(function()
            local pp = v and v.PrimaryPart
            if pp then pp:SetNetworkOwner(LP) end
        end)
    end

    local function hardPivot(v, cf)
        local pp = v.PrimaryPart
        if pp then
            pp.AssemblyLinearVelocity  = Vector3.zero
            pp.AssemblyAngularVelocity = Vector3.zero
        end
        v:PivotTo(cf)
    end

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

    local function rayDown(pos, depth, ignore)
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Blacklist
        params.FilterDescendantsInstances = ignore or {}
        return workspace:Raycast(pos, Vector3.new(0, -(depth or SAFE_RAY_DEPTH), 0), params)
    end

    ----------------------------------------------------------------
    -- SafeFly (ground lock with anti-eject measures)
    ----------------------------------------------------------------
    local function doSafeFly()
        if fly.locking then return end

        local v = myVehicle() or vehicleModelForLocal(); if not v then return end
        if not v.PrimaryPart then if not ensurePP(v) then return end end

        local beforeCF = fly.lastAirCF or v:GetPivot()
        local probeCF  = v:GetPivot()
        local hit      = rayDown(probeCF.Position, SAFE_RAY_DEPTH, {v})
        if not hit then return end

        fly.locking = true

        local basePos  = Vector3.new(probeCF.Position.X, hit.Position.Y + GROUND_PAD_Y, probeCF.Position.Z)
        local camCF    = Camera.CFrame
        local yawFwd   = (camCF.LookVector * Vector3.new(1,0,1))
        yawFwd         = (yawFwd.Magnitude > 1e-3) and yawFwd.Unit or Vector3.new(0,0,-1)
        local groundCF = CFrame.lookAt(basePos, basePos + yawFwd, camCF.UpVector)

        local seat = findSeat(v) or v:FindFirstChild("DriveSeat")
        local hum  = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")

        -- PRE-PREPARE: force seated state and server reseat BEFORE first pivot
        if hum then
            pcall(function() hum.Sit = true end)
            pcall(function() hum:ChangeState(Enum.HumanoidStateType.Seated) end)
        end
        reseatServerBySeat(seat)
        if seat and hum and seat.Occupant ~= hum then pcall(function() seat:Sit(hum) end) end

        -- MICRO-DESCENT: soften the snap (reduces seat break)
        local microSteps = 10
        for i = 1, microSteps do
            local alpha  = i / microSteps
            local lerpCF = beforeCF:Lerp(groundCF, alpha)
            hardPivot(v, lerpCF)
            if hum then
                reseatServerBySeat(seat)
                if seat and seat.Occupant ~= hum then pcall(function() seat:Sit(hum) end) end
            end
            RunService.Heartbeat:Wait()
        end

        -- HARD LOCK ON GROUND for SAFE_HOLD
        local tEnd = os.clock() + SAFE_HOLD
        while fly.enabled and os.clock() < tEnd do
            hardPivot(v, groundCF)
            if hum then
                reseatServerBySeat(seat)
                if seat and seat.Occupant ~= hum then pcall(function() seat:Sit(hum) end) end
            end
            RunService.Heartbeat:Wait()
        end

        -- RETURN TO AIR
        if SAFE_BACK and fly.enabled then
            hardPivot(v, beforeCF)
            fly.hoverCF, fly.lastAirCF = beforeCF, beforeCF
            if hum then
                reseatServerBySeat(seat)
                if seat and seat.Occupant ~= hum then pcall(function() seat:Sit(hum) end) end
            end
        end

        fly.locking = false
    end

    ----------------------------------------------------------------
    -- Flight step + SafeFly scheduler (strict every SAFE_PERIOD)
    ----------------------------------------------------------------
    local function step(dt)
        if not fly.enabled then return end

        -- strict schedule; never skip long gaps
        local now = os.clock()
        if not fly.nextSafeAt then
            fly.nextSafeAt = now + SAFE_PERIOD
        elseif fly.safeOn and now >= fly.nextSafeAt and not fly.locking then
            -- update next tick first to avoid re-entrancy issues
            fly.nextSafeAt = now + SAFE_PERIOD
            doSafeFly()
            return
        end

        if fly.locking then return end
        if not isSeated() then return end

        local v = myVehicle() or vehicleModelForLocal(); if not v then return end
        if not v.PrimaryPart then if not ensurePP(v) then return end end
        setNetOwner(v)

        local look = Camera.CFrame.LookVector
        if look.Magnitude < 0.999 then look = look.Unit end
        local up   = Camera.CFrame.UpVector

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
        local sub      = math.clamp(math.ceil(absDist / STEP_DIST), 1, SUBSTEPS_MAX)
        local stepDist = total / sub

        for _ = 1, sub do
            local target = curPos + (look * stepDist)
            local newCF  = CFrame.lookAt(target, target + look, up)
            hardPivot(v, newCF)
            curPos = target
        end

        local final = CFrame.lookAt(curPos, curPos + look, up)
        hardPivot(v, final)
        fly.hoverCF, fly.lastAirCF = final, final
    end

    ----------------------------------------------------------------
    -- Enable/Disable
    ----------------------------------------------------------------
    local function setEnabled(on)
        if on == fly.enabled then return end

        if on then
            local v = myVehicle() or vehicleModelForLocal()
            if not v then notify("Car Fly","No vehicle."); return end
            if not v.PrimaryPart then if not ensurePP(v) then notify("Car Fly","No PrimaryPart."); return end end
            setNetOwner(v)

            local cf = v:GetPivot()
            fly.hoverCF, fly.lastAirCF = cf, cf
            fly.nextSafeAt = os.clock() + SAFE_PERIOD

            if fly.hbConn then fly.hbConn:Disconnect() end
            fly.hbConn = RunService.Heartbeat:Connect(step)

            fly.enabled = true
            if fly.uiToggle then fly.uiToggle:Set(true) end
            notify("Car Fly", ("Enabled (Speed %d)"):format(fly.speed), 2)
        else
            fly.enabled = false
            if fly.hbConn then fly.hbConn:Disconnect(); fly.hbConn = nil end
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
    -- Minimal UI (limits applied)
    ----------------------------------------------------------------
    local sec = tab:AddSection({ Name = "Car Fly" })
    fly.uiToggle = sec:AddToggle({
        Name = "Enable",
        Default = false,
        Callback = function(v) setEnabled(v) end
    })
    sec:AddBind({
        Name = "Toggle Key",
        Default = TOGGLE_KEY,
        Hold = false,
        Callback = function() toggle() end
    })
    sec:AddSlider({
        Name = "Speed",
        Min = MIN_SPEED, Max = MAX_SPEED, Increment = 5,
        Default = DEFAULT_SPEED,
        Callback = function(v) fly.speed = math.clamp(math.floor(v), MIN_SPEED, MAX_SPEED) end
    })
    sec:AddToggle({
        Name = "Safe Fly",
        Default = true,
        Callback = function(v) fly.safeOn = v end
    })

    -- safety: disable when leaving seat
    RunService.Heartbeat:Connect(function()
        if fly.enabled and not isSeated() then setEnabled(false) end
    end)

    print("[carfly v5.0.3] loaded")
end
