-- tabs/functions/vehicle/vehicle/carfly.lua
return function(tab, OrionLib, Common)
    ----------------------------------------------------------------
    -- Legacy Car Fly (Velocity/CFrame) – zum Testen des alten Codes
    -- Passt in deine neue Loader/Functions-Struktur.
    ----------------------------------------------------------------

    ---------------- Services ----------------
    local Players     = game:GetService("Players")
    local RunService  = game:GetService("RunService")
    local UserInput   = game:GetService("UserInputService")
    local Workspace   = game:GetService("Workspace")

    local LP     = Players.LocalPlayer
    local Camera = Workspace.CurrentCamera

    -- kleine Helper (ziehen wir aus Common, falls vorhanden)
    local VehiclesFolder = (Common and Common.VehiclesFolder) or function()
        return Workspace:FindFirstChild("Vehicles") or Workspace
    end

    local function myVehicleFolder()
        if Common and Common.myVehicleFolder then return Common.myVehicleFolder() end
        local root = VehiclesFolder(); if not root then return nil end
        local byName = root:FindFirstChild(LP.Name)
        if byName then return byName end
        for _,m in ipairs(root:GetChildren()) do
            if (m:IsA("Model") or m:IsA("Folder")) and (m.GetAttribute and m:GetAttribute("Owner") == LP.Name) then
                return m
            end
        end
        return nil
    end

    local function ensurePrimaryPart(model)
        if not model then return false end
        if model.PrimaryPart then return true end
        for _,d in ipairs(model:GetDescendants()) do
            if d:IsA("BasePart") then
                pcall(function() model.PrimaryPart = d end)
                if model.PrimaryPart then return true end
            end
        end
        return false
    end

    local function isSeated()
        if Common and Common.isSeated then return Common.isSeated() end
        local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
        return hum and hum.SeatPart ~= nil
    end

    local function isSeatedInOwnVehicle()
        if Common and Common.isSeatedInOwnVehicle then return Common.isSeatedInOwnVehicle() end
        local vf = myVehicleFolder(); if not vf then return false, nil, vf end
        local seat
        local s = vf:FindFirstChild("DriveSeat", true)
        if s and s:IsA("Seat") then seat = s end
        if not seat then
            local seats = vf:FindFirstChild("Seats", true)
            if seats then
                for _,d in ipairs(seats:GetDescendants()) do
                    if d:IsA("Seat") then seat = d; break end
                end
            end
        end
        if not seat then
            for _,d in ipairs(vf:GetDescendants()) do
                if d:IsA("Seat") then seat = d; break end
            end
        end
        local hum  = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
        if hum and seat and seat.Occupant == hum then return true, seat, vf end
        return false, seat, vf
    end

    local function notify(title, msg, t)
        OrionLib:MakeNotification({Name = title, Content = msg, Time = t or 3})
    end

    ---------------- State ----------------
    local state = {
        enabled     = false,
        conn        = nil,
        curVel      = Vector3.new(),
        speed       = 256, -- FlightSpeed
        accel       = 4,   -- FlightAcceleration
        turn        = 16,  -- TurnSpeed
        turboMul    = 3,   -- SpeedKeyMultiplier
        toggleKey   = Enum.KeyCode.V,
        speedKey    = Enum.KeyCode.LeftControl, -- Turbo
    }

    -- für UI, um den Toggle visuell zu syncen
    local toggleUI = nil

    ---------------- Core (alter Algorithmus, adaptiert) ----------------
    local function stepFly(dt)
        -- nicht komplett ausknipsen, aber ohne Sitz/Auto nichts machen
        local okSeat, _, vf = isSeatedInOwnVehicle()
        if not okSeat then return end

        local v = myVehicleFolder(); if not v then return end
        if not ensurePrimaryPart(v) then return end
        local pp = v.PrimaryPart ; if not pp then return end

        -- optionales Netzwerk-Owner-Gate (falls vorhanden)
        if typeof(isnetworkowner) == "function" then
            local ok, owns = pcall(isnetworkowner, pp)
            if ok and not owns then return end
        end

        -- Eingabe in kamerabezogener Basis
        local base = Vector3.zero
        if not UserInput:GetFocusedTextBox() then
            if UserInput:IsKeyDown(Enum.KeyCode.W) then
                base += (Camera.CFrame.LookVector * state.speed)
            end
            if UserInput:IsKeyDown(Enum.KeyCode.S) then
                base -= (Camera.CFrame.LookVector * state.speed)
            end
            if UserInput:IsKeyDown(Enum.KeyCode.D) then
                base += (Camera.CFrame.RightVector * state.speed)
            end
            if UserInput:IsKeyDown(Enum.KeyCode.A) then
                base -= (Camera.CFrame.RightVector * state.speed)
            end
            if UserInput:IsKeyDown(Enum.KeyCode.Space) then
                base += (Camera.CFrame.UpVector * state.speed)
            end
            if UserInput:IsKeyDown(state.speedKey) then
                base *= state.turboMul
            end
        end

        -- Lerp auf gewünschte Geschwindigkeit
        state.curVel = state.curVel:Lerp(
            base,
            math.clamp(dt * state.accel, 0, 1)
        )

        -- alte Methode: Velocity setzen + sanft drehen
        -- Hinweis: Das kann Anti-Cheat triggern – erwünscht zum Testen
        -- (du wolltest dieses Verhalten prüfen)
        pp.Velocity = state.curVel + Vector3.new(0, 2, 0)

        -- Ausrichtung zur Bewegungsrichtung + Kamera
        -- (nur wenn PrimaryPart NICHT dein HRP ist – bei echten Fahrzeugteilen ok)
        pcall(function()
            pp.RotVelocity = Vector3.new()
            local look = state.curVel.Magnitude > 0 and state.curVel.Unit or Camera.CFrame.LookVector
            local target = CFrame.lookAt(pp.Position, pp.Position + look)
            pp.CFrame = pp.CFrame:Lerp(target, math.clamp(dt * state.turn, 0, 1))
        end)
    end

    local function setEnabled(on)
        if on == state.enabled then return end
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

    local function toggle()
        setEnabled(not state.enabled)
    end

    ---------------- UI ----------------
    local sec = tab:AddSection({ Name = "Car Fly (Legacy Test)" })

    toggleUI = sec:AddToggle({
        Name = "Enable Legacy Car Fly",
        Default = false,
        Callback = function(v) setEnabled(v) end
    })

    sec:AddBind({
        Name = "Toggle Key",
        Default = state.toggleKey,
        Hold = false,
        Callback = function() toggle() end
    })

    sec:AddSlider({
        Name = "Speed",
        Min = 50, Max = 600, Increment = 5,
        Default = state.speed,
        Callback = function(v) state.speed = math.floor(v) end
    })

    sec:AddSlider({
        Name = "Acceleration",
        Min = 1, Max = 20, Increment = 1,
        Default = state.accel,
        Callback = function(v) state.accel = math.floor(v) end
    })

    sec:AddSlider({
        Name = "Turn Speed",
        Min = 4, Max = 48, Increment = 1,
        Default = state.turn,
        Callback = function(v) state.turn = math.floor(v) end
    })

    sec:AddSlider({
        Name = "Turbo Multiplier (Ctrl)",
        Min = 1, Max = 6, Increment = 0.5,
        Default = state.turboMul,
        Callback = function(v) state.turboMul = tonumber(v) or state.turboMul end
    })

    -- läuft weiter, auch wenn du kurz aussteigst → setzt erst wieder an,
    -- sobald du wieder in deinem Fahrzeug sitzt.
    RunService.Heartbeat:Connect(function()
        if not state.enabled then return end
        -- wenn dein Fenster den Fokus hat (Textbox), macht stepFly nichts;
        -- ansonsten: keine harte Auto-Off-Logik hier.
        -- (bewusst minimal, damit du den Legacy-Weg testen kannst)
    end)
end
