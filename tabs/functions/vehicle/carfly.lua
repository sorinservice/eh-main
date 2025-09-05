-- tabs/functions/vehicle/vehicle/carfly_tp.lua
return function(SV, tab, OrionLib)
print("[carfly_tp v5.0] loaded")

    -- Ziel: W/S = vor/zurück; volle Kamera-Ausrichtung fürs Auto,
    --        ABER keine Höhenänderung, wenn du „geradeaus“ schaust.
    --        Vertikal nur bei deutlichem Pitch (oberhalb Deadzone).
    --        TP-only via Model:PivotTo (serverseitig sichtbar).
    --        SafeFly greift auch im Idle; Re-Seat ohne Welds.

    local RunService = game:GetService("RunService")
    local UserInput  = game:GetService("UserInputService")
    local Players    = game:GetService("Players")
    local LP         = Players.LocalPlayer
    local Camera     = SV.Camera
    local notify     = SV.notify

    -- ===== Tuning =====
    local DEFAULT_SPEED        = 240
    local MAX_STEP_DIST        = 4
    local MAX_SUBSTEPS         = 18

    -- Vertikalsteuerung: KEIN Offset mehr → „geradeaus“ = 0
    local NEUTRAL_DEADZONE     = 0.06   -- |look.Y| ≤ deadzone ⇒ keine Höhenänderung
    local MIN_ASCENT_RATE      = 0      -- 0 = kein erzwungenes Steigen bei leicht positivem Pitch
    local NEUTRAL_CLIMB_RATE   = 0      -- 0 = exakt Höhe halten in Neutral (kein Auto-Climb)

    -- Boden-Clearance (nur gegen Einsacken am Boden)
    local GROUND_CLAMP         = true
    local GROUND_CLEARANCE     = 2.4
    local CLEARANCE_PROBE      = 12

    -- SafeFly
    local SAFE_PERIOD          = 6.0
    local SAFE_HOLD            = 0.5
    local SAFE_BACK            = true
    local SAFE_RAY_DEPTH       = 4000

    local TOGGLE_KEY           = Enum.KeyCode.X

    -- ===== State =====
    local fly = {
        enabled=false, speed=DEFAULT_SPEED, safeOn=true,
        hbConn=nil, safeTask=nil, locking=false,
        uiToggle=nil, hold={F=false,B=false},
        hoverCF=nil, lastAirCF=nil, lastYaw=Vector3.new(1,0,0),
        debounceTS=0,
    }

    -- ===== Helpers =====
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
        return d
    end

    local function groundHitBelow(model, depth)
        local cf = model:GetPivot()
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Blacklist
        params.FilterDescendantsInstances = {model}
        return workspace:Raycast(cf.Position + Vector3.new(0, CLEARANCE_PROBE*0.5, 0), Vector3.new(0, -math.max(depth or CLEARANCE_PROBE,1), 0), params)
    end

    local function enforceClearance(model, pos)
        if not GROUND_CLAMP then return pos end
        local hit = groundHitBelow(model, CLEARANCE_PROBE)
        if hit then
            local minY = hit.Position.Y + GROUND_CLEARANCE
            if pos.Y < minY then
                pos = Vector3.new(pos.X, minY, pos.Z)
            end
        end
        return pos
    end

    -- ===== Core =====
    local function step(dt)
        if not fly.enabled or fly.locking or not seated() then return end

        local v = myVehicle(); if not v then return end
        if not v.PrimaryPart then if not ensurePP(v) then return end end
        setNetOwner(v)

        local curCF  = v:GetPivot()
        local curPos = curCF.Position

        local look = Camera.CFrame.LookVector
        if look.Magnitude < 0.999 then look = look.Unit end

        -- Horizontal = Kamera-Yaw
        local yaw = Vector3.new(look.X, 0, look.Z)
        if yaw.Magnitude < 1e-3 then yaw = fly.lastYaw else yaw = yaw.Unit; fly.lastYaw = yaw end

        -- Idle → Pose halten, volle Kameraausrichtung
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

        local totalDist   = fly.speed * dt
        local substeps    = math.clamp(math.ceil(totalDist / MAX_STEP_DIST), 1, MAX_SUBSTEPS)
        local stepDist    = totalDist / substeps
        local neutralClmb = (NEUTRAL_CLIMB_RATE * dt) / substeps
        local minAscStep  = (MIN_ASCENT_RATE    * dt) / substeps

        for _ = 1, substeps do
            -- horizontal Move
            local horiz  = yaw * (stepDist * (s > 0 and 1 or -1))
            local target = curPos + horiz

            -- vertikal nur bei Pitch außerhalb Deadzone
            local ly = look.Y
            local dY = 0
            if math.abs(ly) <= NEUTRAL_DEADZONE then
                -- neutral: Höhe exakt halten (oder sanft steigen, hier = 0)
                dY = neutralClmb -- 0 mit obigem Tuning
            elseif ly > NEUTRAL_DEADZONE then
                -- positiv: Steigen um (ly - deadzone)
                dY = (ly - NEUTRAL_DEADZONE) * stepDist
                if dY < minAscStep then dY = minAscStep end -- nur wenn >0 gesetzt; bei 0 bleibt 0
            else
                -- negativ: Sinken um (ly + deadzone)  (ly ist negativ)
                dY = (ly + NEUTRAL_DEADZONE) * stepDist
            end

            target = Vector3.new(target.X, curPos.Y + dY, target.Z)
            target = enforceClearance(v, target)

            local newCF = CFrame.new(target, target + look) -- volle Kameraausrichtung
            v:PivotTo(newCF)
            curPos = target
        end

        local finalCF = CFrame.new(curPos, curPos + look)
        fly.hoverCF   = finalCF
        fly.lastAirCF = finalCF
    end

    -- ===== SafeFly =====
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

                            local seat = SV.findDriveSeat(v)
                            local hum  = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")

                            local t0 = os.clock()
                            while os.clock() - t0 < SAFE_HOLD and fly.enabled do
                                v:PivotTo(lockCF)
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

    -- ===== Toggle/UI =====
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

    local sec = tab:AddSection({ Name = "Car Fly v5.0" })
    fly.uiToggle = sec:AddToggle({ Name = "Enable Car Fly (nur im Auto)", Default = false, Callback = function(v) setEnabled(v) end })
    sec:AddBind({ Name = "Car Fly Toggle Key", Default = TOGGLE_KEY, Hold = false, Callback = function() toggle() end })
    sec:AddSlider({ Name = "Speed", Min = 10, Max = 520, Increment = 5, Default = DEFAULT_SPEED, Callback = function(v) fly.speed = math.floor(v) end })
    sec:AddToggle({ Name = "Safe Fly (alle 6s Boden, 0.5s, zurück)", Default = true, Callback = function(v) fly.safeOn = v end })

    RunService.Heartbeat:Connect(function()
        if fly.enabled and not seated() then setEnabled(false) end
    end)
end
