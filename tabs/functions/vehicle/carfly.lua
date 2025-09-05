-- tabs/functions/vehicle/vehicle/carfly_tp.lua
return function(SV, tab, OrionLib)
print("[carfly_tp v3.2] loaded")

    ----------------------------------------------------------------
    -- Car Fly TP v3.2
    -- - Serverwide, anti-cheat friendly (PivotTo steps only)
    -- - Direction: W/S forward/back, mouse controls yaw & pitch
    -- - Gravity compensation each frame (hover effect)
    -- - Smooth interpolation (POS_LERP)
    -- - Configurable speed, toggle key, SafeFly optional
    ----------------------------------------------------------------

    local RunService = game:GetService("RunService")
    local UserInput  = game:GetService("UserInputService")
    local Workspace  = game:GetService("Workspace")
    local Camera     = SV.Camera
    local notify     = SV.notify

    -- ================== Settings ==================
    local DEFAULT_SPEED   = 130
    local POS_LERP        = 0.35     -- smoothness factor (0..1 per frame)
    local START_UP_NUDGE  = 2.0      -- small lift-off when enabling
    local GRAVITY_COMP    = Workspace.Gravity -- compensate each frame
    local TOGGLE_KEY      = Enum.KeyCode.X

    -- ================== State ==================
    local fly = {
        enabled    = false,
        speed      = DEFAULT_SPEED,
        conn       = nil,
        safeTask   = nil,
        uiToggle   = nil,
        debounceTS = 0,
        lastCF     = nil,
    }

    -- ================== Helpers ==================
    local function myVehicle() return SV.myVehicleFolder() end
    local function ensurePP(v)  SV.ensurePrimaryPart(v); return v.PrimaryPart end

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

    local function softLiftOff(model)
        local cf = model:GetPivot()
        model:PivotTo(cf + Vector3.new(0, START_UP_NUDGE, 0))
        fly.lastCF = model:GetPivot()
    end

    -- ================== Core Step ==================
    local function step(dt)
        if not fly.enabled or not SV.isSeated() then return end
        local v = myVehicle(); if not v then return end
        if not v.PrimaryPart then if not ensurePP(v) then return end end

        local curCF = v:GetPivot()
        local dir   = dirInput()
        local stepVec = Vector3.zero

        if dir.Magnitude > 0 then
            stepVec = dir.Unit * (fly.speed * dt)
        end

        -- Gravity compensation (hover effect)
        stepVec += Vector3.new(0, GRAVITY_COMP * dt, 0)

        local targetPos = curCF.Position + stepVec
        local newPos    = curCF.Position:Lerp(targetPos, POS_LERP)
        local newCF     = CFrame.new(newPos, newPos + Camera.CFrame.LookVector)

        v:PivotTo(newCF)
        fly.lastCF = newCF
    end

    -- ================== Toggle ==================
    local function setEnabled(on)
        if on == fly.enabled then return end
        local v = myVehicle()

        if on then
            if not v then notify("Car Fly","No vehicle found."); return end
            if not v.PrimaryPart then if not ensurePP(v) then notify("Car Fly","No PrimaryPart."); return end end
            softLiftOff(v)
            if fly.conn then fly.conn:Disconnect() end
            fly.conn = RunService.RenderStepped:Connect(step)
            fly.enabled = true
            if fly.uiToggle then fly.uiToggle:Set(true) end
            notify("Car Fly", ("Enabled (Speed %d)"):format(fly.speed), 2)
        else
            fly.enabled = false
            if fly.conn then fly.conn:Disconnect(); fly.conn = nil end
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

    -- ================== UI ==================
    local sec = tab:AddSection({ Name = "Car Fly v3.2" })

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

    sec:AddSlider({
        Name = "Speed",
        Min = 10, Max = 300, Increment = 5,
        Default = DEFAULT_SPEED,
        Callback = function(v) fly.speed = math.floor(v) end
    })

    -- Auto-Off if you leave the seat
    RunService.Heartbeat:Connect(function()
        if fly.enabled and not SV.isSeated() then
            setEnabled(false)
        end
    end)
end
