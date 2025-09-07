-- tabs/functions/vehicle/vehicle/carfly_tp.lua
return function(SV, tab, OrionLib)

    ----------------------------------------------------------------
    -- Car Fly (TP) + SafeFly hard-lock (ground-touch 0.5s, restore)
    -- Version: 5.2.0
    ----------------------------------------------------------------

    -- === Tunables (keine UI-Slider) ===
    local TUNE = {
        SPEED_DEFAULT = 130,     -- studs/s vorwärts
        STEP_DIST     = 1.0,     -- max TP pro Substep
        SUBSTEPS_MAX  = 48,

        VERT_GAIN     = 1.00,    -- Kamera-Y-Verhalten
        Y_BIAS        = 0.00,

        SAFE_PERIOD   = 6.0,     -- alle 6 Sekunden
        SAFE_HOLD     = 0.5,     -- 0.5s Boden-Kontakt
        RAY_DEPTH     = 12000,   -- tief genug für jede Map
        GROUND_PAD    = 0.02,    -- Anti-Z-Fight

        FREEZE_FPS    = 60,      -- wie "hart" wir während des Locks halten
    }

    local RunService = game:GetService("RunService")
    local UserInput  = game:GetService("UserInputService")
    local Players    = game:GetService("Players")
    local LP         = Players.LocalPlayer

    -- === Helfer vom SV ===
    local function myVehicle() return SV.myVehicleFolder() end
    local function ensurePP(v) SV.ensurePrimaryPart(v); return v.PrimaryPart end

    -- === Nützliche Helfer ===
    local function setNetOwner(v)
        pcall(function() if v and v.PrimaryPart then v.PrimaryPart:SetNetworkOwner(LP) end end)
    end

    local function zeroVel(v)
        for _,p in ipairs(v:GetDescendants()) do
            if p:IsA("BasePart") then
                p.AssemblyLinearVelocity  = Vector3.zero
                p.AssemblyAngularVelocity = Vector3.zero
            end
        end
    end

    local function hardPivot(v, cf)
        zeroVel(v)
        v:PivotTo(cf)
    end

    local function groundHit(origin, depth, ignore)
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Blacklist
        params.FilterDescendantsInstances = ignore or {}
        return workspace:Raycast(origin, Vector3.new(0, -(depth or TUNE.RAY_DEPTH), 0), params)
    end

    local function modelHalfHeight(v)
        -- stabile Unterkanten-Berechnung
        local size = v:GetExtentsSize()
        return size.Y * 0.5
    end

    -- Freeze/Unfreeze: ANKER alle Teile; Merke Zustand und stelle zurück
    local frozenState = nil
    local function freezeModel(v, on)
        if on then
            frozenState = {}
            for _,p in ipairs(v:GetDescendants()) do
                if p:IsA("BasePart") then
                    frozenState[p] = p.Anchored
                    p.Anchored = true
                    p.AssemblyLinearVelocity  = Vector3.zero
                    p.AssemblyAngularVelocity = Vector3.zero
                end
            end
        else
            if frozenState then
                for p,prev in pairs(frozenState) do
                    if p and p.Parent then
                        p.Anchored = prev
                    end
                end
            end
            frozenState = nil
        end
    end

    local function dirScalar()
        if UserInput:GetFocusedTextBox() then return 0 end
        local d = 0
        if UserInput:IsKeyDown(Enum.KeyCode.W) then d += 1 end
        if UserInput:IsKeyDown(Enum.KeyCode.S) then d -= 1 end
        return d
    end

    -- === State ===
    local fly = {
        enabled   = false,
        speed     = TUNE.SPEED_DEFAULT,
        safeOn    = true,

        hbConn    = nil,
        safeTask  = nil,
        locking   = false,

        uiToggle  = nil,
        lastAirCF = nil,
        debounce  = 0,
    }

    -- === Flugstep (kein Sitz-Check, kein Idle-Grounding) ===
    local function step(dt)
        if not fly.enabled or fly.locking then return end

        local v = myVehicle(); if not v then return end
        if not v.PrimaryPart then if not ensurePP(v) then return end end
        setNetOwner(v)

        local cam   = workspace.CurrentCamera
        local look  = cam.CFrame.LookVector
        local up    = cam.CFrame.UpVector
        if look.Magnitude < 0.999 then look = look.Unit end

        local curCF  = v:GetPivot()
        local curPos = curCF.Position

        local s = dirScalar()
        if s == 0 then
            hardPivot(v, CFrame.lookAt(curPos, curPos + look, up))
            fly.lastAirCF = v:GetPivot()
            return
        end

        local total    = (fly.speed * dt) * (s >= 0 and 1 or -1)
        local absDist  = math.abs(total)
        local sub      = math.clamp(math.ceil(absDist / TUNE.STEP_DIST), 1, TUNE.SUBSTEPS_MAX)
        local stepDist = total / sub

        local moveLook = Vector3.new(look.X, look.Y * TUNE.VERT_GAIN + TUNE.Y_BIAS, look.Z)
        if moveLook.Magnitude < 1e-3 then moveLook = look else moveLook = moveLook.Unit end

        for _ = 1, sub do
            local target = curPos + (moveLook * stepDist)
            hardPivot(v, CFrame.lookAt(target, target + look, up))
            curPos = target
        end

        local final = CFrame.lookAt(curPos, curPos + look, up)
        hardPivot(v, final)
        fly.lastAirCF = final
    end

    -- === SafeFly: immer alle 6s, egal wo ===
    local function startSafeFly()
        if fly.safeTask then task.cancel(fly.safeTask) end
        fly.safeTask = task.spawn(function()
            while fly.enabled do
                if not fly.safeOn then
                    task.wait(0.25)
                else
                    task.wait(TUNE.SAFE_PERIOD)
                    if not fly.enabled then break end

                    local v = myVehicle()
                    if not v or not (v.PrimaryPart or ensurePP(v)) then
                        continue
                    end

                    -- Vorherige Luft-Position sichern
                    local beforeCF = fly.lastAirCF or v:GetPivot()

                    -- Boden direkt unter der aktuellen Position suchen
                    local pos   = v:GetPivot().Position
                    local hit   = groundHit(pos, TUNE.RAY_DEPTH, {v})
                    if not hit then
                        -- Falls nichts getroffen wurde, setze auf Y=0 als Fallback
                        hit = { Position = Vector3.new(pos.X, 0, pos.Z) }
                    end

                    fly.locking = true
                    local halfY   = modelHalfHeight(v)
                    local cam     = workspace.CurrentCamera
                    local yawFwd  = (cam.CFrame.LookVector * Vector3.new(1,0,1))
                    yawFwd        = (yawFwd.Magnitude > 1e-3) and yawFwd.Unit or Vector3.new(0,0,-1)

                    local baseY    = hit.Position.Y + halfY + TUNE.GROUND_PAD
                    local basePos  = Vector3.new(pos.X, baseY, pos.Z)
                    local groundCF = CFrame.lookAt(basePos, basePos + yawFwd, cam.CFrame.UpVector)

                    -- Hard Freeze: ankern + pro Frame halten
                    freezeModel(v, true)
                    zeroVel(v)
                    local t0   = os.clock()
                    local tick = 1 / math.max(30, TUNE.FREEZE_FPS)

                    while os.clock() - t0 < TUNE.SAFE_HOLD and fly.enabled do
                        hardPivot(v, groundCF)
                        task.wait(tick)
                    end

                    -- Restore
                    freezeModel(v, false)
                    if fly.enabled then
                        hardPivot(v, beforeCF)
                        fly.lastAirCF = beforeCF
                    end
                    fly.locking = false
                end
            end
        end)
    end

    -- === Enable/Disable ===
    local function setEnabled(on)
        if on == fly.enabled then return end
        local v = myVehicle()

        if on then
            if not v then return end
            if not v.PrimaryPart then if not ensurePP(v) then return end end
            setNetOwner(v)

            local cf = v:GetPivot()
            fly.lastAirCF = cf

            if fly.hbConn then fly.hbConn:Disconnect() end
            fly.hbConn = RunService.Heartbeat:Connect(step)

            startSafeFly()
            fly.enabled = true
            if fly.uiToggle then fly.uiToggle:Set(true) end
        else
            fly.enabled = false
            if fly.hbConn   then fly.hbConn:Disconnect();   fly.hbConn  = nil end
            if fly.safeTask then task.cancel(fly.safeTask); fly.safeTask = nil end
            fly.locking = false
            if fly.uiToggle then fly.uiToggle:Set(false) end
        end
    end

    local function toggle()
        local now = os.clock()
        if now - fly.debounce < 0.15 then return end
        fly.debounce = now
        setEnabled(not fly.enabled)
    end

    -- === Minimal UI ===
    local sec = tab:AddSection({ Name = "Car Fly" })
    fly.uiToggle = sec:AddToggle({ Name = "Enable Car Fly", Default = false, Callback = function(v) setEnabled(v) end })
    sec:AddBind({ Name = "Toggle Key", Default = Enum.KeyCode.X, Hold = false, Callback = function() toggle() end })
    sec:AddToggle({ Name = "Safe Fly", Default = true, Callback = function(v) fly.safeOn = v end })

    print("[carfly_tp] v5.2.0 loaded (SafeFly hard-lock enabled)")
end
