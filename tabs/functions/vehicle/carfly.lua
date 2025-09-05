-- tabs/functions/vehicle/vehicle/carfly_tp.lua
return function(SV, tab, OrionLib)
print("[carfly_tp v4.8.1] loaded")

    -- TP-only (PivotTo), serverseitig sichtbar
    -- Steuerung:
    --   - W/S = vor/zurück
    --   - Fahrzeug-Ausrichtung folgt der KAMERA inkl. Pitch (voller LookVector)
    --   - Horizontalbewegung entlang Kamera-Yaw, Vertikal separat aus Pitch (mit Kompensation)
    --   - Kein Vorwärts-Sinkflug mehr, aber „gefühlt“ gleiche Kameralogik wie zuvor
    -- SafeFly:
    --   - Alle 6s Boden-Lock 0.5s, dann exakt zurück
    --   - Während Lock Movement pausiert, Re-Seat wenn nötig (ohne Welds/Constraints)

    local RunService = game:GetService("RunService")
    local UserInput  = game:GetService("UserInputService")
    local Players    = game:GetService("Players")
    local LP         = Players.LocalPlayer

    local Camera = SV.Camera
    local notify = SV.notify

    ----------------------------------------------------------------
    -- Tuning (hard-coded, keine UI-Slider – justier hier)
    ----------------------------------------------------------------
    local DEFAULT_SPEED       = 240      -- studs/s
    local MAX_STEP_DIST       = 4        -- max TP je Substep
    local MAX_SUBSTEPS        = 18       -- Substeps pro Heartbeat (mehr = glatter)

    -- Pitch→Höhe (gegen „Chasecam schaut leicht nach unten“)
    local CAM_PITCH_OFFSET    = 0.08     -- additiv zu Look.Y für die Höhenberechnung (0.04–0.10)
    local NEUTRAL_DEADZONE    = 0.05     -- |Look.Y + Offset| <= deadzone ⇒ „neutral“ (kein Sinken)
    local NEUTRAL_CLIMB_RATE  = 16       -- studs/s bei W + neutral (0 = exakt Höhe halten)
    local MIN_ASCENT_RATE     = 42       -- studs/s Mindest-Steigrate bei leicht positivem Pitch

    -- SafeFly
    local SAFE_PERIOD         = 6.0      -- s
    local SAFE_HOLD           = 0.5      -- s
    local SAFE_BACK           = true
    local SAFE_RAY_DEPTH      = 4000     -- studs

    local TOGGLE_KEY          = Enum.KeyCode.X

    ----------------------------------------------------------------
    -- State
    ----------------------------------------------------------------
    local fly = {
        enabled   = false,
        speed     = DEFAULT_SPEED,
        safeOn    = true,

        hbConn    = nil,
        safeTask  = nil,
        locking   = false,

        uiToggle  = nil,
        hold      = {F=false,B=false},

        hoverCF   = nil,        -- Idle-Pose
        lastAirCF = nil,        -- Rücksprung SafeFly
        lastYaw   = Vector3.new(1,0,0),
        debounceTS= 0,
    }

    ----------------------------------------------------------------
    -- Helpers
    ----------------------------------------------------------------
    local function myVehicle() return SV.myVehicleFolder() end
    local function ensurePP(v) SV.ensurePrimaryPart(v); return v.PrimaryPart end
    local function setNetOwner(v)
        pcall(function() if v and v.PrimaryPart then v.PrimaryPart:SetNetworkOwner(LP) end end)
    end
    local function seated() return SV.isSeated() end

    local function hasInput()
        if UserInput:GetFocusedTextBox() then return false end
        return UserInput:IsKeyDown(Enum.KeyCode.W) or fly.hold.F
            or UserInput:IsKeyDown(Enum.KeyCode.S) or fly.hold.B
    end
    local function dirScalar()
        local d = 0
        if not UserInput:GetFocusedTextBox() then
            if UserInput:IsKeyDown(Enum.KeyCode.W) or fly.hold.F then d = d + 1 end
            if UserInput:IsKeyDown(Enum.KeyCode.S) or fly.hold.B then d = d - 1 end
        end
        return d -- -1,0,+1
    end

    ----------------------------------------------------------------
    -- Core (Heartbeat + Substeps)
    ----------------------------------------------------------------
    local function step(dt)
        if not fly.enabled then return end
        if fly.locking then return end
        if not seated() then return end

        local v = myVehicle(); if not v then return end
        if not v.PrimaryPart then if not ensurePP(v) then return end end
        setNetOwner(v)

        local curCF  = v:GetPivot()
        local curPos = curCF.Position

        -- Kamera-Vektoren
        local look    = Camera.CFrame.LookVector
        if look.Magnitude < 0.999 then look = look.Unit end

        -- Yaw für horizontale Bewegung (falls Kamera extrem nach oben/unten schaut)
        local yaw = Vector3.new(look.X, 0, look.Z)
        if yaw.Magnitude < 1e-3 then yaw = fly.lastYaw else yaw = yaw.Unit; fly.lastYaw = yaw end

        -- Effektiver Pitch (mit Offset), nur für Vertikalberechnung
        local effY = look.Y + CAM_PITCH_OFFSET

        -- Idle: Position halten, AUSRICHTUNG = volle Kamera (Pitch inklusive)
        if not hasInput() then
            local keepPos = (fly.hoverCF and fly.hoverCF.Position) or curPos
            local lockCF  = CFrame.new(keepPos, keepPos + look)
            v:PivotTo(lockCF)
            fly.lastAirCF = lockCF
            return
        end

        local s = dirScalar()
        if s == 0 then
            local keepPos = (fly.hoverCF and fly.hoverCF.Position) or curPos
            local lockCF  = CFrame.new(keepPos, keepPos + look)
            v:PivotTo(lockCF); fly.lastAirCF = lockCF; return
        end

        -- Bewegung: Horizontal entlang yaw, Vertikal separat aus effY
        local totalDist   = fly.speed * dt
        local substeps    = math.clamp(math.ceil(totalDist / MAX_STEP_DIST), 1, MAX_SUBSTEPS)
        local stepDist    = totalDist / substeps
        local neutralClmb = (NEUTRAL_CLIMB_RATE * dt) / substeps
        local minAscStep  = (MIN_ASCENT_RATE    * dt) / substeps

        for _ = 1, substeps do
            -- Horizontal
            local horiz  = yaw * (stepDist * (s > 0 and 1 or -1))
            local target = curPos + horiz

            -- Vertikal
            if s > 0 then
                -- Vorwärts
                if math.abs(effY) <= NEUTRAL_DEADZONE then
                    -- neutral: leicht steigen oder Höhe halten
                    if NEUTRAL_CLIMB_RATE > 0 then
                        target = Vector3.new(target.X, curPos.Y + neutralClmb, target.Z)
                    else
                        target = Vector3.new(target.X, curPos.Y,                target.Z)
                    end
                elseif effY > NEUTRAL_DEADZONE then
                    -- positiv: Mindest-Steigrate erzwingen
                    local dY = effY * stepDist
                    if dY < minAscStep then dY = minAscStep end
                    target = Vector3.new(target.X, curPos.Y + dY, target.Z)
                else
                    -- deutlich negativ: bewusstes Sinken
                    target = Vector3.new(target.X, curPos.Y + (effY * stepDist), target.Z)
                end
            else
                -- Rückwärts: neutral Höhe halten; sonst Pitch spiegeln (so ist S + runter = hoch)
                if math.abs(effY) <= NEUTRAL_DEADZONE then
                    target = Vector3.new(target.X, curPos.Y, target.Z)
                else
                    target = Vector3.new(target.X, curPos.Y + (-effY * stepDist), target.Z)
                end
            end

            -- Ausrichtung = volle Kamera (Pitch behalten)
            local newCF = CFrame.new(target, target + look)
            v:PivotTo(newCF)
            curPos = target
        end

        local finalCF = CFrame.new(curPos, curPos + look)
        fly.hoverCF   = finalCF
        fly.lastAirCF = finalCF
    end

    ----------------------------------------------------------------
    -- SafeFly (Idle & Bewegung)
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

                        -- Raycast nach unten (Fahrzeug selbst ausblenden)
                        local params = RaycastParams.new()
                        params.FilterType = Enum.RaycastFilterType.Blacklist
                        params.FilterDescendantsInstances = {v}

                        local hit = workspace:Raycast(probeCF.Position, Vector3.new(0, -SAFE_RAY_DEPTH, 0), params)
                        if hit then
                            fly.locking = true

                            local base   = Vector3.new(probeCF.Position.X, hit.Position.Y + 2, probeCF.Position.Z)
                            -- yaw beibehalten, Pitch egal auf Boden
                            local groundCF = CFrame.new(base, base + fly.lastYaw)

                            -- Sitz/Humanoid merken
                            local seat = SV.findDriveSeat(v)
                            local hum  = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")

                            -- 0.5s Boden-Lock; währenddessen Re-Seat, falls nötig
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
                                -- nach Rücksprung erneut Sitz sichern
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
    -- Toggle
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

            -- initialen yaw speichern
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
    -- UI (nur das Nötige)
    ----------------------------------------------------------------
    local sec = tab:AddSection({ Name = "Car Fly v4.8" })
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
        Min = 10, Max = 520, Increment = 5,
        Default = DEFAULT_SPEED,
        Callback = function(v) fly.speed = math.floor(v) end
    })
    sec:AddToggle({
        Name = "Safe Fly (alle 6s Boden, 0.5s, zurück)",
        Default = true,
        Callback = function(v) fly.safeOn = v end
    })

    -- Auto-Off beim Aussteigen
    RunService.Heartbeat:Connect(function()
        if fly.enabled and not seated() then setEnabled(false) end
    end)
end
