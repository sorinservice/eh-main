-- tabs/functions/vehicle/vehicle/carfly.lua
return function(SV, tab, OrionLib)
    ----------------------------------------------------------------
    -- Legacy Car Fly (Velocity/CFrame) – Testbuild
    ----------------------------------------------------------------
    local RunService  = game:GetService("RunService")
    local UserInput   = game:GetService("UserInputService")
    local Camera      = SV.Camera

    local function notify(t,m,s) SV.notify(t,m,s) end

    local state = {
        enabled   = false, conn=nil,
        curVel    = Vector3.new(),
        speed     = 256,
        accel     = 4,
        turn      = 16,
        turboMul  = 3,
        toggleKey = Enum.KeyCode.V,
        speedKey  = Enum.KeyCode.LeftControl,
    }

    local toggleUI = nil

    local function stepFly(dt)
        -- nur arbeiten, wenn du im EIGENEN Fahrzeug sitzt
        local v = SV.myVehicleFolder(); if not v then return end
        if not SV.isSeated() then return end
        SV.ensurePrimaryPart(v)
        local pp = v.PrimaryPart; if not pp then return end

        -- falls Executor isnetworkowner hat, respektieren
        if typeof(isnetworkowner)=="function" then
            local ok, owns = pcall(isnetworkowner, pp)
            if ok and not owns then return end
        end

        local base = Vector3.zero
        if not UserInput:GetFocusedTextBox() then
            if UserInput:IsKeyDown(Enum.KeyCode.W) then base +=  Camera.CFrame.LookVector  * state.speed end
            if UserInput:IsKeyDown(Enum.KeyCode.S) then base -=  Camera.CFrame.LookVector  * state.speed end
            if UserInput:IsKeyDown(Enum.KeyCode.D) then base +=  Camera.CFrame.RightVector * state.speed end
            if UserInput:IsKeyDown(Enum.KeyCode.A) then base -=  Camera.CFrame.RightVector * state.speed end
            if UserInput:IsKeyDown(Enum.KeyCode.Space) then base += Camera.CFrame.UpVector * state.speed end
            if UserInput:IsKeyDown(state.speedKey) then base *= state.turboMul end
        end

        state.curVel = state.curVel:Lerp(base, math.clamp(dt*state.accel, 0, 1))

        -- ACHTUNG: Velocity/CFrame-Write → evtl. Anti-Cheat
        pp.Velocity = state.curVel + Vector3.new(0,2,0)

        pcall(function()
            pp.RotVelocity = Vector3.new()
            local look   = state.curVel.Magnitude>0 and state.curVel.Unit or Camera.CFrame.LookVector
            local target = CFrame.lookAt(pp.Position, pp.Position+look)
            pp.CFrame = pp.CFrame:Lerp(target, math.clamp(dt*state.turn, 0, 1))
        end)
    end

    local function setEnabled(on)
        if on==state.enabled then return end
        state.enabled = on
        if state.enabled then
            if toggleUI then toggleUI:Set(true) end
            notify("Car Fly (legacy)", "Aktiviert – TESTBUILD", 2)
            state.curVel = Vector3.new()
            if state.conn then state.conn:Disconnect() state.conn=nil end
            state.conn = RunService.Heartbeat:Connect(stepFly)
        else
            if toggleUI then toggleUI:Set(false) end
            if state.conn then state.conn:Disconnect() state.conn=nil end
            notify("Car Fly (legacy)", "Deaktiviert", 2)
        end
    end

    local function toggle() setEnabled(not state.enabled) end

    -- UI (jetzt sicher: tab ist wirklich der Orion-Tab)
    local sec = tab:AddSection({ Name = "Car Fly (Legacy Test)" })

    toggleUI = sec:AddToggle({
        Name = "Enable Legacy Car Fly",
        Default = false,
        Callback = function(v) setEnabled(v) end
    })
    sec:AddBind({
        Name = "Toggle Key",
        Default = state.toggleKey,
        Hold   = false,
        Callback = function() toggle() end
    })
    sec:AddSlider({
        Name="Speed", Min=50, Max=600, Increment=5, Default=state.speed,
        Callback=function(v) state.speed = math.floor(v) end
    })
    sec:AddSlider({
        Name="Acceleration", Min=1, Max=20, Increment=1, Default=state.accel,
        Callback=function(v) state.accel = math.floor(v) end
    })
    sec:AddSlider({
        Name="Turn Speed", Min=4, Max=48, Increment=1, Default=state.turn,
        Callback=function(v) state.turn = math.floor(v) end
    })
    sec:AddSlider({
        Name="Turbo Multiplier (Ctrl)", Min=1, Max=6, Increment=0.5, Default=state.turboMul,
        Callback=function(v) state.turboMul = tonumber(v) or state.turboMul end
    })
end
