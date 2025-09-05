-- tabs/functions/vehicle/vehicle/carfly_tp.lua
return function(SV, tab, OrionLib)
print("[carfly_tp v4.6] loaded")

    -- TP-only, serverseitig sichtbar; W/S = ±Camera.LookVector (inkl. Pitch), kein Strafe
    -- Idle-Hard-Lock; kein Down-Clamp (durch Wände fliegbar)
    -- Forward-No-Sink + Neutral-Mode: verhindert Sinkflug bei „nach vorn schauen“
    -- SafeFly triggert auch im Idle/Flug, lockt 0.5s am Boden, springt exakt zurück, re-seated ohne Welds

    local RunService = game:GetService("RunService")
    local UserInput  = game:GetService("UserInputService")
    local Players    = game:GetService("Players")
    local LP         = Players.LocalPlayer

    local Camera = SV.Camera
    local notify = SV.notify

    -- ===== Tuning =====
    local DEFAULT_SPEED        = 240    -- Grundspeed
    local MAX_STEP_DIST        = 4      -- max TP-Distanz pro Substep
    local MAX_SUBSTEPS         = 16     -- max Substeps je Heartbeat

    -- „Nach vorn schauen“ Verhalten:
    local HOLD_DEADZONE        = 0.04   -- |look.Y| <= Deadzone => „neutraler“ Pitch
    local FORWARD_NOSINK_MARGIN= 0.02   -- asymmetrisch nach unten: ly >= - (Deadzone + Margin) gilt als neutral (kein Sinkflug)
    local NEUTRAL_MODE_CLIMB   = true   -- neutraler Pitch + vorwärts: true = leicht steigen, false = exakt Höhe halten
    local CLIMB_BIAS_RATE      = 14     -- studs/s für neutralen Vorwärtsflug (nur wenn NEUTRAL_MODE_CLIMB=true)
    local MIN_ASCENT_RATE      = 32     -- studs/s Mindeststeigrate bei leicht positivem Pitch (ly > Deadzone)

    -- SafeFly
    local SAFE_PERIOD          = 6.0
    local SAFE_HOLD            = 0.5
    local SAFE_BACK            = true
    local SAFE_RAY_DEPTH       = 4000

    local TOGGLE_KEY           = Enum.KeyCode.X

    -- ===== State =====
    local fly = {
        enabled    = false,
        speed      = DEFAULT_SPEED,
        safeOn     = true,

        hbConn     = nil,
        safeTask   = nil,

        uiToggle   = nil,
        hold       = {F=false,B=false},

        hoverCF    = nil,   -- Idle-Pose
        lastAirCF  = nil,   -- Rücksprung SafeFly
        locking    = false, -- SafeFly-Lock aktiv → Movement pausiert
        debounceTS = 0,
    }

    -- ===== Helpers =====
    local function myVehicle() return SV.myVehicleFolder() end
    local function ensurePP(v) SV.ensurePrimaryPart(v); return v.PrimaryPart end
    local function setNetOwner(v) pcall(function() if v and v.PrimaryPart then v.PrimaryPart:SetNetworkOwner(LP) end end) end

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

    -- ===== Core =====
    local function step(dt)
        if not fly.enabled then return end
        if fly.locking then return end
        if not SV.isSeated() then return end

        local v = myVehicle(); if not v then return end
        if not v.PrimaryPart then if not ensurePP(v) then return end end
        setNetOwner(v)

        local curCF  = v:GetPivot()
        local curPos = curCF.Position

        -- Idle: Pose halten, Blick folgt Kamera
        if not hasInput() then
            local keep   = fly.hoverCF or curCF
            local lockCF = CFrame.new(keep.Position, keep.Position + Camera.CFrame.LookVector)
            v:PivotTo(lockCF)
            fly.lastAirCF = lockCF
            return
        end

        local s = dirScalar()
        if s == 0 then
            local keep   = fly.hoverCF or curCF
            local lockCF = CFrame.new(keep.Position, keep.Position + Camera.CFrame.LookVector)
            v:PivotTo(lockCF); fly.lastAirCF = lockCF; return
        end

        local look = Camera.CFrame.LookVector
        if look.Magnitude < 0.999 then look = look.Unit end
        local ly = look.Y
        local moveDir = (s > 0) and look or -look

        local totalDist = fly.speed * dt
        local substeps  = math.clamp(math.ceil(totalDist / MAX_STEP_DIST), 1, MAX_SUBSTEPS)
        local stepDist  = totalDist / substeps
        local biasPerStep   = (CLIMB_BIAS_RATE * dt) / substeps
        local minAscPerStep = (MIN_ASCENT_RATE * dt) / substeps

        for _ = 1, substeps do
            local target = curPos + moveDir * stepDist

            -- Forward-No-Sink + Neutral-Mode
            if s > 0 then
                -- asymmetrisch: leichter negativer Pitch wird toleriert, um Sinkflug zu verhindern
                if ly >= -(HOLD_DEADZONE + FORWARD_NOSINK_MARGIN) and ly <= HOLD_DEADZONE then
                    if NEUTRAL_MODE_CLIMB then
                        target = Vector3.new(target.X, curPos.Y + biasPerStep, target.Z)
                    else
                        target = Vector3.new(target.X, curPos.Y, target.Z)
                    end
                elseif ly > HOLD_DEADZONE then
                    -- leicht positiv: Mindeststeigrate
                    local dY = target.Y - curPos.Y
                    if dY < minAscPerStep then
                        target = Vector3.new(target.X, curPos.Y + minAscPerStep, target.Z)
                    end
                else
                    -- deutlich nach unten schauen → bewusstes Sinken erlaubt
                end
            else
                -- Rückwärts: in neutraler Zone Höhe halten; bei starkem Down-Pitch sinken erlaubt
                if math.abs(ly) <= HOLD_DEADZONE then
                    target = Vector3.new(target.X, curPos.Y, target.Z)
                end
            end

            local newCF = CFrame.new(target, target + Camera.CFrame.LookVector)
            v:PivotTo(newCF)
            curPos = target
        end

        local finalCF = CFrame.new(curPos, curPos + Camera.CFrame.LookVector)
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
                    if not v then goto continue end
                    if not v.PrimaryPart then if not ensurePP(v) then goto continue end end

                    local before = fly.lastAirCF or v:GetPivot()

                    local probeCF = v:GetPivot()
                    local params = RaycastParams.new()
                    params.FilterType = Enum.RaycastFilterType.Blacklist
                    params.FilterDescendantsInstances = {v}
                    local hit = workspace:Raycast(probeCF.Position, Vector3.new(0, -SAFE_RAY_DEPTH, 0), params)

                    if hit then
                        fly.locking = true

                        local base = Vector3.new(probeCF.Position.X, hit.Position.Y + 2, probeCF.Position.Z)
                        local lockCF = CFrame.new(base, base + Camera.CFrame.LookVector)

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

                        if fly.enabled and not SV.isSeated() then
                            local seat = SV.findDriveSeat(v)
                            if seat then SV.sitIn(seat) end
                        end

                        fly.locking = false
                    end
                    ::continue::
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

    -- ===== UI =====
    local sec = tab:AddSection({ Name = "Car Fly v4.6" })
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

    local secT = tab:AddSection({ Name = "Flight Tuning" })
    secT:AddSlider({
        Name = "Level Deadzone (×1000)",
        Min = 0, Max = 120, Increment = 1,
        Default = math.floor(HOLD_DEADZONE * 1000),
        Callback = function(v) HOLD_DEADZONE = v/1000 end
    })
    secT:AddSlider({
        Name = "Forward No-Sink Margin (×1000)",
        Min = 0, Max = 100, Increment = 1,
        Default = math.floor(FORWARD_NOSINK_MARGIN * 1000),
        Callback = function(v) FORWARD_NOSINK_MARGIN = v/1000 end
    })
    secT:AddDropdown({
        Name = "Neutral Mode",
        Options = {"Hold","Climb"},
        Default = NEUTRAL_MODE_CLIMB and "Climb" or "Hold",
        Callback = function(opt) NEUTRAL_MODE_CLIMB = (opt == "Climb") end
    })
    secT:AddSlider({
        Name = "Climb Bias Rate (studs/s)",
        Min = 0, Max = 60, Increment = 1,
        Default = CLIMB_BIAS_RATE,
        Callback = function(v) CLIMB_BIAS_RATE = v end
    })

    RunService.Heartbeat:Connect(function()
        if fly.enabled and not SV.isSeated() then setEnabled(false) end
    end)

    -- ===== Optional: lokales Ausblenden von Reifenrauch (nur lokal sichtbar; serverweit NICHT möglich) =====
    local function localHideTireSmoke(enable)
        local v = myVehicle(); if not v then return end
        for _,d in ipairs(v:GetDescendants()) do
            if d:IsA("ParticleEmitter") or d:IsA("Trail") then
                pcall(function() d.Enabled = not enable end)
            end
        end
    end
    -- Beispiel: bei Aktivierung lokal Rauch aus
    -- secT:AddToggle({ Name="Hide Tire Smoke (local)", Default=false, Callback=function(v) localHideTireSmoke(v) end })
end
