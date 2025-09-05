-- tabs/functions/vehicle/vehicle/carfly_tp.lua
return function(SV, tab, OrionLib)
print("[carfly_tp v4.7] loaded")

    -- TP-only, serverseitig sichtbar
    -- W/S = vor/zurück; Fahrzeug-YAW folgt Kamera, PITCH steuert NUR die Höhe (kein Vorwärts-Sinkflug)
    -- Idle-Hard-Lock; SafeFly aktiv (auch im Idle), 0.5s Boden-Lock, exakter Rücksprung, Re-Seat ohne Welds

    local RunService = game:GetService("RunService")
    local UserInput  = game:GetService("UserInputService")
    local Players    = game:GetService("Players")
    local LP         = Players.LocalPlayer

    local Camera = SV.Camera
    local notify = SV.notify

    -- ===== Konstanten (ohne UI-Schieber) =====
    local DEFAULT_SPEED      = 240     -- studs/s
    local MAX_STEP_DIST      = 4       -- max Teleport pro Substep
    local MAX_SUBSTEPS       = 18      -- Substeps je Heartbeat

    -- Vorwärts neutral (kein Sinkflug), leichtes Auto-Climb:
    local NEUTRAL_DOWN_TOL   = 0.08    -- tolerierter negativer Look.Y, der noch als „neutral“ gilt
    local NEUTRAL_CLIMB_RATE = 16      -- studs/s bei Vorwärts + neutral (sanftes Steigen). 0 = exakt Höhe halten
    local MIN_ASCENT_RATE    = 36      -- studs/s Mindest-Steigrate bei leicht positivem Pitch

    -- SafeFly
    local SAFE_PERIOD        = 6.0     -- s
    local SAFE_HOLD          = 0.5     -- s
    local SAFE_BACK          = true
    local SAFE_RAY_DEPTH     = 4000

    local TOGGLE_KEY         = Enum.KeyCode.X

    -- ===== State =====
    local fly = {
        enabled   = false,
        speed     = DEFAULT_SPEED,
        safeOn    = true,

        hbConn    = nil,
        safeTask  = nil,
        locking   = false,

        uiToggle  = nil,
        hold      = {F=false,B=false},

        hoverCF   = nil,   -- Idle-Pose
        lastAirCF = nil,   -- Rücksprung SafeFly
        lastYaw   = Vector3.new(1,0,0), -- letzter gültiger Yaw-Richtungsvektor
        debounceTS= 0,
    }

    -- ===== Helpers =====
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

    -- ===== Core (Heartbeat + Substeps) =====
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
        local camLook = Camera.CFrame.LookVector
        if camLook.Magnitude < 0.999 then camLook = camLook.Unit end
        local camYaw  = Vector3.new(camLook.X, 0, camLook.Z)
        if camYaw.Magnitude < 1e-3 then camYaw = fly.lastYaw else camYaw = camYaw.Unit; fly.lastYaw = camYaw end
        local ly = camLook.Y

        -- Idle: Pose halten, nur YAW zur Kamera
        if not hasInput() then
            local keepPos = (fly.hoverCF and fly.hoverCF.Position) or curPos
            local lockCF  = CFrame.new(keepPos, keepPos + camYaw)
            v:PivotTo(lockCF)
            fly.lastAirCF = lockCF
            return
        end

        local s = dirScalar()
        if s == 0 then
            local keepPos = (fly.hoverCF and fly.hoverCF.Position) or curPos
            local lockCF  = CFrame.new(keepPos, keepPos + camYaw)
            v:PivotTo(lockCF); fly.lastAirCF = lockCF; return
        end

        -- Bewegung: Horizontal entlang camYaw; Vertical separat aus Pitch
        local totalDist = fly.speed * dt
        local substeps  = math.clamp(math.ceil(totalDist / MAX_STEP_DIST), 1, MAX_SUBSTEPS)
        local stepDist  = totalDist / substeps
        local neutralClimbStep = (NEUTRAL_CLIMB_RATE * dt) / substeps
        local minAscStep       = (MIN_ASCENT_RATE     * dt) / substeps

        for _ = 1, substeps do
            -- horizontal
            local horiz = camYaw * (stepDist * (s > 0 and 1 or -1))
            local target = curPos + horiz

            -- vertikal (Pitch-Logik)
            if s > 0 then
                -- Vorwärts
                if ly >= -NEUTRAL_DOWN_TOL and ly <= NEUTRAL_DOWN_TOL then
                    -- Neutral: Höhe halten oder sanft steigen
                    if NEUTRAL_CLIMB_RATE > 0 then
                        target = Vector3.new(target.X, curPos.Y + neutralClimbStep, target.Z)
                    else
                        target = Vector3.new(target.X, curPos.Y,                 target.Z)
                    end
                elseif ly > NEUTRAL_DOWN_TOL then
                    -- leicht positiv: Mindest-Steigrate durchsetzen
                    local dY = (ly * stepDist)  -- natürliche Steigrate aus Pitch
                    if dY < minAscStep then dY = minAscStep end
                    target = Vector3.new(target.X, curPos.Y + dY, target.Z)
                else
                    -- deutlich negativ: bewusstes Sinken erlauben
                    target = Vector3.new(target.X, curPos.Y + (ly * stepDist), target.Z)
                end
            else
                -- Rückwärts
                if math.abs(ly) <= NEUTRAL_DOWN_TOL then
                    -- neutral: Höhe halten
                    target = Vector3.new(target.X, curPos.Y, target.Z)
                else
                    -- sonst Pitch folgen (symmetrisch)
                    target = Vector3.new(target.X, curPos.Y + (-ly * stepDist), target.Z)
                end
            end

            local newCF = CFrame.new(target, target + camYaw) -- YAW-only Ausrichtung
            v:PivotTo(newCF)
            curPos = target
        end

        local finalCF = CFrame.new(curPos, curPos + camYaw)
        fly.hoverCF   = finalCF
        fly.lastAirCF = finalCF
    end

    -- ===== SafeFly (Idle & Bewegung) =====
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

                            local base   = Vector3.new(probeCF.Position.X, hit.Position.Y + 2, probeCF.Position.Z)
                            local lockCF = CFrame.new(base, base + fly.lastYaw)

                            local t0 = os.clock()
                            while os.clock() - t0 < SAFE_HOLD and fly.enabled do
                                v:PivotTo(lockCF)
                                RunService.Heartbeat:Wait()
                            end

                            if SAFE_BACK and fly.enabled then
                                v:PivotTo(before)
                                fly.hoverCF   = before
                                fly.lastAirCF = before
                            end

                            if fly.enabled and not seated() then
                                local seat = SV.findDriveSeat(v)
                                if seat then SV.sitIn(seat) end
                            end

                            fly.locking = false
                        end
                    end
                end
            end
        end)
    end

    -- ===== Toggle =====
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
            -- initiale Yaw merken
            local look = Camera.CFrame.LookVector
            local yaw  = Vector3.new(look.X,0,look.Z); if yaw.Magnitude > 1e-3 then fly.lastYaw = yaw.Unit end

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

    -- ===== UI (minimal) =====
    local sec = tab:AddSection({ Name = "Car Fly v4.7" })
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
