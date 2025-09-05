-- tabs/functions/vehicle/vehicle/carfly_tp.lua
return function(SV, tab, OrionLib)
print("[carfly_tp] v3.1 loaded")

    local RunService   = game:GetService("RunService")
    local UserInput    = game:GetService("UserInputService")
    local Workspace    = game:GetService("Workspace")
    local Camera       = SV.Camera
    local notify       = SV.notify

    -- ================== Tuning ==================
    local DEFAULT_SPEED       = 130
    local POS_LERP            = 0.35
    local START_UP_NUDGE      = 2.0
    local MIN_CLEARANCE       = 2.25
    local CLEARANCE_PROBE     = 6

    local SAFE_PERIOD         = 6.0
    local SAFE_HOLD           = 0.5
    local SAFE_BACK           = true

    local TOGGLE_KEY          = Enum.KeyCode.X

    -- ================== State ==================
    local fly = {
        enabled    = false,
        speed      = DEFAULT_SPEED,
        conn       = nil,
        safeTask   = nil,
        safeOn     = false,
        uiToggle   = nil,
        mobileUI   = nil,
        debounceTS = 0,
        lastCF     = nil,
    }

    -- ================== Helpers ==================
    local function myVehicle() return SV.myVehicleFolder() end
    local function ensurePP(v) SV.ensurePrimaryPart(v); return v.PrimaryPart end

    local function dirInput()
        local dir = Vector3.zero
        if not UserInput:GetFocusedTextBox() then
            if UserInput:IsKeyDown(Enum.KeyCode.W) then
                dir += Camera.CFrame.LookVector
            end
            if UserInput:IsKeyDown(Enum.KeyCode.S) then
                dir -= Camera.CFrame.LookVector
            end
        end
        return dir
    end

    local function groundHitBelow(model, depth)
        local cf = model:GetPivot()
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Blacklist
        params.FilterDescendantsInstances = {model}
        return Workspace:Raycast(cf.Position, Vector3.new(0, -math.max(depth or 1000,1), 0), params)
    end

    local function withClearance(model, targetPos)
        local hit = groundHitBelow(model, CLEARANCE_PROBE)
        if hit then
            local cf      = model:GetPivot()
            local current = cf.Position
            local dist    = (current - hit.Position).Y
            if dist < MIN_CLEARANCE then
                targetPos = Vector3.new(
                    targetPos.X,
                    math.max(targetPos.Y, hit.Position.Y + MIN_CLEARANCE),
                    targetPos.Z
                )
            end
        end
        return targetPos
    end

    local function softLiftOff(model)
        local cf = model:GetPivot()
        model:PivotTo(cf + Vector3.new(0, START_UP_NUDGE, 0))
        fly.lastCF = model:GetPivot()
    end

    -- ================== Core Step ==================
    local function step(dt)
        if not fly.enabled then return end
        if not SV.isSeated() then return end

        local v = myVehicle(); if not v then return end
        if not v.PrimaryPart then if not ensurePP(v) then return end end

        local curCF  = v:GetPivot()
        local camCF  = Camera.CFrame

        local dir = dirInput()
        local stepVec = Vector3.zero
        if dir.Magnitude > 0 then
            dir = dir.Unit
            stepVec = dir * (fly.speed * dt)
        end

        local targetPos = curCF.Position + stepVec
        targetPos = withClearance(v, targetPos)

        local newCF = CFrame.new(targetPos, targetPos + camCF.LookVector)

        v:PivotTo(newCF)
        fly.lastCF = newCF
    end

    -- ================== Safe Fly ==================
    local function startSafeFly()
        if fly.safeTask then task.cancel(fly.safeTask) end
        fly.safeTask = task.spawn(function()
            while fly.enabled do
                if not fly.safeOn then task.wait(0.25)
                else
                    task.wait(SAFE_PERIOD)
                    if not fly.enabled then break end
                    local v = myVehicle(); if not v then break end
                    local before = fly.lastCF or v:GetPivot()

                    local hit = groundHitBelow(v, 1500)
                    if hit then
                        local lockCF = CFrame.new(
                            hit.Position + Vector3.new(0, 2, 0),
                            hit.Position + Vector3.new(0, 2, 0) + Camera.CFrame.LookVector
                        )

                        local t0 = os.clock()
                        while os.clock() - t0 < SAFE_HOLD and fly.enabled do
                            v:PivotTo(lockCF)
                            RunService.Heartbeat:Wait()
                        end

                        if SAFE_BACK and fly.enabled then
                            v:PivotTo(before)
                            fly.lastCF = before
                        end
                    end
                end
            end
        end)
    end

    -- ================== Toggle ==================
    local function setEnabled(on)
        if on == fly.enabled then return end
        local v = myVehicle()

        if on then
            if not v then notify("Car Fly","Kein Fahrzeug."); return end
            if not v.PrimaryPart then if not ensurePP(v) then notify("Car Fly","Kein PrimaryPart."); return end end
            softLiftOff(v)
            if fly.conn then fly.conn:Disconnect() end
            fly.conn = RunService.RenderStepped:Connect(step)
            startSafeFly()
            fly.enabled = true
            if fly.uiToggle then fly.uiToggle:Set(true) end
            notify("Car Fly", ("Aktiviert (Speed %d)"):format(fly.speed), 2)
        else
            fly.enabled = false
            if fly.conn then fly.conn:Disconnect(); fly.conn = nil end
            if fly.safeTask then task.cancel(fly.safeTask); fly.safeTask = nil end
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

    -- ================== UI ==================
    local sec = tab:AddSection({ Name = "Car Fly" })
    fly.uiToggle = sec:AddToggle({
        Name = "Enable Car Fly (nur im Auto)",
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
        Min = 10, Max = 300, Increment = 5,
        Default = DEFAULT_SPEED,
        Callback = function(v) fly.speed = math.floor(v) end
    })
    sec:AddToggle({
        Name = "Safe Fly (alle 6s Boden, 0.5s, zurück)",
        Default = false,
        Callback = function(v) fly.safeOn = v end
    })

    -- Auto-Off wenn Sitz verlassen
    RunService.Heartbeat:Connect(function()
        if fly.enabled and not SV.isSeated() then
            setEnabled(false)
        end
    end)
end
