-- tabs/functions/vehicle/vehicle/carfly_tp.lua
return function(SV, tab, OrionLib)
print("[carfly_tp v4.2] loaded")

    -- Teleport-only (Heartbeat + Substeps), server-seitig sichtbar
    -- W/S exakt entlang Camera.LookVector (inkl. Pitch), KEIN Strafe
    -- Idle-Hard-Lock (steht exakt, kein Absinken/Drift)
    -- Anti-Drift auch während Bewegung: Position wird nur entlang LookVector verändert
    -- Garantierte Steigrate (ohne Lift-Off): min. Aufwärtsdelta wenn LookVector.Y > Deadzone
    -- Down-only-Clearance (nur beim Sinkflug)
    -- SafeFly: alle 6s Boden-Lock 0.5s, dann EXAKT zurück

    local RunService = game:GetService("RunService")
    local UserInput  = game:GetService("UserInputService")
    local Players    = game:GetService("Players")
    local LP         = Players.LocalPlayer

    local Camera     = SV.Camera
    local notify     = SV.notify

    -- ===== Tuning =====
    local DEFAULT_SPEED     = 220          -- Grundspeed
    local POS_LERP          = 0.28         -- Glättung NUR bei Input (0..1)
    local MAX_STEP_DIST     = 4            -- max Distanz pro Substep (Studs)
    local MAX_SUBSTEPS      = 14           -- max Substeps pro Frame

    local PITCH_DEADZONE    = 0.02         -- kleine LookVector.Y werden ignoriert (Jitter weg)
    local MIN_ASCENT_RATE   = 32           -- min. Aufwärtsrate (Studs/s), wenn Pitch über Deadzone

    local MIN_CLEARANCE     = 2.0          -- Bodensicherheit (nur beim Abwärts-TP)
    local CLEARANCE_PROBE   = 8            -- Tiefe des Boden-Raycasts

    local SAFE_PERIOD       = 6.0
    local SAFE_HOLD         = 0.5
    local SAFE_BACK         = true

    local TOGGLE_KEY        = Enum.KeyCode.X

    -- ===== State =====
    local fly = {
        enabled    = false,
        speed      = DEFAULT_SPEED,
        safeOn     = false,

        hbConn     = nil,
        safeTask   = nil,

        uiToggle   = nil,
        hold       = {F=false,B=false},

        hoverCF    = nil,   -- Idle-Hard-Lock-Pose
        lastAirCF  = nil,   -- Rücksprung für SafeFly
        debounceTS = 0,
    }

    -- ===== Helpers =====
    local function myVehicle() return SV.myVehicleFolder() end
    local function ensurePP(v) SV.ensurePrimaryPart(v); return v.PrimaryPart end
    local function setNetOwner(v)
        pcall(function() if v and v.PrimaryPart then v.PrimaryPart:SetNetworkOwner(LP) end end)
    end

    local function hasInput()
        if UserInput:GetFocusedTextBox() then return false end
        return UserInput:IsKeyDown(Enum.KeyCode.W) or fly.hold.F
            or UserInput:IsKeyDown(Enum.KeyCode.S) or fly.hold.B
    end

    local function dirInput()
        local dir = 0    -- +1 vorwärts, -1 rückwärts, 0 nichts
        if not UserInput:GetFocusedTextBox() then
            if UserInput:IsKeyDown(Enum.KeyCode.W) or fly.hold.F then dir = dir + 1 end
            if UserInput:IsKeyDown(Enum.KeyCode.S) or fly.hold.B then dir = dir - 1 end
        end
        return dir
    end

    local function groundHitBelow(model, depth)
        local cf = model:GetPivot()
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Blacklist
        params.FilterDescendantsInstances = {model}
        return workspace:Raycast(cf.Position, Vector3.new(0, -math.max(depth or 1000,1), 0), params)
    end

    -- nur beim Abwärts-TP clampen; Aufwärts nie begrenzen
    local function applyClearanceDownOnly(model, currentPos, targetPos)
        if targetPos.Y >= currentPos.Y then return targetPos end
        local hit = groundHitBelow(model, CLEARANCE_PROBE)
        if not hit then return targetPos end
        local floorY = hit.Position.Y + MIN_CLEARANCE
        if targetPos.Y < floorY then
            targetPos = Vector3.new(targetPos.X, floorY, targetPos.Z)
        end
        return targetPos
    end

    -- ===== Core (Heartbeat + Substeps) =====
    local function step(dt)
        if not fly.enabled then return end
        if not SV.isSeated()   then return end

        local v = myVehicle(); if not v then return end
        if not v.PrimaryPart then if not ensurePP(v) then return end end
        setNetOwner(v)

        local curCF  = v:GetPivot()
        local curPos = curCF.Position

        -- Idle: harte Pose (kein Absinken/Drift), Blick folgt Kamera
        if not hasInput() then
            local keep   = fly.hoverCF or curCF
            local lockCF = CFrame.new(keep.Position, keep.Position + Camera.CFrame.LookVector)
            v:PivotTo(lockCF)
            fly.lastAirCF = lockCF
            return
        end

        local dir = dirInput()       -- -1, 0, +1
        if dir == 0 then
            local keep   = fly.hoverCF or curCF
            local lockCF = CFrame.new(keep.Position, keep.Position + Camera.CFrame.LookVector)
            v:PivotTo(lockCF)
            fly.lastAirCF = lockCF
            return
        end

        -- reiner Bewegungsvektor = ±LookVector, seitliche Komponenten ausgeschlossen
        local look = Camera.CFrame.LookVector
        -- numerisch stabilisieren: normalisieren, falls nötig
        if look.Magnitude < 0.999 then
            look = look.Unit
        end
        local moveDir = (dir > 0) and look or (-look)

        -- Deadzone/Min-Ascent: Y-Anteil erzwingen, wenn nach oben (bzw. bei rückwärts + Blick nach unten)
        -- pro Frame geplante Gesamtdistanz:
        local totalDist = fly.speed * dt
        local substeps  = math.clamp(math.ceil(totalDist / MAX_STEP_DIST), 1, MAX_SUBSTEPS)
        local stepDist  = totalDist / substeps
        local minAscPerStep = (MIN_ASCENT_RATE * dt) / substeps

        for i = 1, substeps do
            -- Ziel nur entlang moveDir (Anti-Drift)
            local targetPos = curPos + moveDir * stepDist

            -- garantierte Aufwärtsbewegung, wenn Y-Komponente „nach oben“ zeigt, aber zu klein wäre:
            local plannedDY = targetPos.Y - curPos.Y
            if plannedDY > 0 then
                -- nur wenn Blick wirklich „spürbar“ nach oben: Deadzone
                if math.abs(look.Y) > PITCH_DEADZONE and plannedDY < minAscPerStep then
                    targetPos = Vector3.new(targetPos.X, curPos.Y + minAscPerStep, targetPos.Z)
                end
            end

            -- Down-only-Clearance
            targetPos = applyClearanceDownOnly(v, curPos, targetPos)

            -- leichte Glättung
            local lerped = curPos:Lerp(targetPos, POS_LERP)

            -- Orientierung exakt an Kamera
            local newCF = CFrame.new(lerped, lerped + Camera.CFrame.LookVector)

            v:PivotTo(newCF)
            curPos = lerped
        end

        local finalCF = CFrame.new(curPos, curPos + Camera.CFrame.LookVector)
        fly.hoverCF   = finalCF
        fly.lastAirCF = finalCF
    end

    -- ===== Safe Fly =====
    local function startSafeFly()
        if fly.safeTask then task.cancel(fly.safeTask) end
        fly.safeTask = task.spawn(function()
            while fly.enabled do
                if not fly.safeOn then
                    task.wait(0.25)
                else
                    task.wait(SAFE_PERIOD)
                    if not fly.enabled then break end

                    local v = myVehicle(); if not v then break end
                    local before = fly.lastAirCF or v:GetPivot()

                    local hit = groundHitBelow(v, 1500)
                    if hit then
                        local base = hit.Position + Vector3.new(0, 2, 0)
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
            fly.hoverCF   = cf     -- Start: keine künstliche Y-Änderung
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

    -- ===== Mobile Panel =====
    local function spawnMobileFly()
        local gui = Instance.new("ScreenGui")
        gui.Name = "Sorin_MobileFly"
        gui.ResetOnSpawn = false
        gui.IgnoreGuiInset = true
        gui.Enabled = false
        gui.Parent = game:GetService("CoreGui")

        local frame = Instance.new("Frame")
        frame.Size = UDim2.fromOffset(230, 160)
        frame.Position = UDim2.fromOffset(40, 300)
        frame.BackgroundColor3 = Color3.fromRGB(25,25,25)
        frame.Parent = gui
        Instance.new("UICorner", frame).CornerRadius = UDim.new(0,12)

        local title = Instance.new("TextLabel")
        title.Size = UDim2.new(1, -10, 0, 22)
        title.Position = UDim2.fromOffset(10, 6)
        title.BackgroundTransparency = 1
        title.Font = Enum.Font.GothamBold
        title.TextSize = 14
        title.TextColor3 = Color3.fromRGB(240,240,240)
        title.TextXAlignment = Enum.TextXAlignment.Left
        title.Text = "Car Fly"
        title.Parent = frame

        local function mkBtn(txt, x, y, w, h, key)
            local b = Instance.new("TextButton")
            b.Size = UDim2.fromOffset(w,h); b.Position = UDim2.fromOffset(x,y)
            b.Text = txt; b.BackgroundColor3 = Color3.fromRGB(40,40,40)
            b.TextColor3 = Color3.fromRGB(230,230,230); b.Font = Enum.Font.GothamSemibold; b.TextSize = 14
            b.Parent = frame; Instance.new("UICorner", b).CornerRadius = UDim.new(0,8)
            b.MouseButton1Down:Connect(function() fly.hold[key] = true end)
            b.MouseButton1Up:Connect(function() fly.hold[key] = false end)
            b.MouseLeave:Connect(function() fly.hold[key] = false end)
            return b
        end

        mkBtn("Toggle", 10, 34, 60, 28, "T").MouseButton1Click:Connect(toggle)
        mkBtn("^",      85, 34, 60, 28, "F")
        mkBtn("v",      85,100, 60, 28, "B")

        return gui
    end
    local MobileFlyGui = spawnMobileFly()

    -- ===== UI =====
    local sec = tab:AddSection({ Name = "Car Fly v4.2" })
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
        Min = 10, Max = 500, Increment = 5,
        Default = DEFAULT_SPEED,
        Callback = function(v) fly.speed = math.floor(v) end
    })
    sec:AddToggle({
        Name = "Safe Fly (alle 6s Boden, 0.5s, zurück)",
        Default = false,
        Callback = function(v) fly.safeOn = v end
    })

    local secM = tab:AddSection({ Name = "Mobile Fly" })
    secM:AddToggle({
        Name = "Mobile Fly Panel",
        Default = false,
        Callback = function(v) if MobileFlyGui then MobileFlyGui.Enabled = v end end
    })

    -- Auto-Off beim Aussteigen
    RunService.Heartbeat:Connect(function()
        if fly.enabled and not SV.isSeated() then
            setEnabled(false)
        end
    end)
end
