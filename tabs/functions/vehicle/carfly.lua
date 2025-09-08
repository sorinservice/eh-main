-- tabs/functions/vehicle/vehicle/carfly_tp.lua
return function(SV, tab, OrionLib)

    -- Version: 5.3.2
    local RunService = game:GetService("RunService")
    local UserInput  = game:GetService("UserInputService")
    local Players    = game:GetService("Players")
    local LP         = Players.LocalPlayer

    local TUNE = {
        SPEED_DEFAULT = 130,
        STEP_DIST     = 1.0,
        SUBSTEPS_MAX  = 48,
        VERT_GAIN     = 1.00,
        Y_BIAS        = 0.00,

        SAFE_PERIOD   = 6.0,
        SAFE_HOLD     = 1.0,          -- 1 Sekunde
        RAY_DEPTH     = 12000,
        GROUND_PAD    = 0.02,         -- Ziel: Unterkante = hitY + pad
        CORRECT_ITERS = 5,            -- Korrekturschleifen zum "Anpressen"
    }

    local function myVehicle() return SV.myVehicleFolder() end
    local function ensurePP(v) SV.ensurePrimaryPart(v); return v.PrimaryPart end
    local function setNetOwner(v) pcall(function() if v and v.PrimaryPart then v.PrimaryPart:SetNetworkOwner(LP) end end) end

    local function zeroVel(v)
        for _,p in ipairs(v:GetDescendants()) do
            if p:IsA("BasePart") then
                p.AssemblyLinearVelocity  = Vector3.zero
                p.AssemblyAngularVelocity = Vector3.zero
            end
        end
    end
    local function hardPivot(v, cf) zeroVel(v); v:PivotTo(cf) end

    local function rayDown(origin, depth, blacklist)
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Blacklist
        params.FilterDescendantsInstances = blacklist or {}
        return workspace:Raycast(origin, Vector3.new(0, -(depth or TUNE.RAY_DEPTH), 0), params)
    end

    local function groundYBelow(pos, ignoreModel)
        local origin = pos + Vector3.new(0, TUNE.RAY_DEPTH*0.5, 0)
        local hit = rayDown(origin, TUNE.RAY_DEPTH, ignoreModel and {ignoreModel} or {})
        if hit then return hit.Position.Y end
        -- Terrain-Whitelist-Fallback
        local params2 = RaycastParams.new()
        params2.FilterType = Enum.RaycastFilterType.Whitelist
        params2.FilterDescendantsInstances = {workspace.Terrain}
        local hit2 = workspace:Raycast(origin, Vector3.new(0, -TUNE.RAY_DEPTH, 0), params2)
        if hit2 then return hit2.Position.Y end
        return 0
    end

    local function bboxBottomY(v)
        local cf, size = v:GetBoundingBox()
        return cf.Position.Y - size.Y * 0.5, cf, size
    end

    local function dirScalar()
        if UserInput:GetFocusedTextBox() then return 0 end
        local d = 0
        if UserInput:IsKeyDown(Enum.KeyCode.W) then d += 1 end
        if UserInput:IsKeyDown(Enum.KeyCode.S) then d -= 1 end
        return d
    end

    local fly = {
        enabled=false, speed=TUNE.SPEED_DEFAULT, safeOn=true,
        hbConn=nil, locking=false, uiToggle=nil, lastAirCF=nil, debounce=0, timer=0,
    }

    local function step(dt)
        if not fly.enabled or fly.locking then return end
        local v = myVehicle(); if not v then return end
        if not v.PrimaryPart then if not ensurePP(v) then return end end
        setNetOwner(v)

        local cam  = workspace.CurrentCamera
        local look = cam.CFrame.LookVector
        local up   = cam.CFrame.UpVector
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
        moveLook = (moveLook.Magnitude < 1e-3) and look or moveLook.Unit

        for _ = 1, sub do
            local target = curPos + (moveLook * stepDist)
            hardPivot(v, CFrame.lookAt(target, target + look, up))
            curPos = target
        end

        local final = CFrame.lookAt(curPos, curPos + look, up)
        hardPivot(v, final)
        fly.lastAirCF = final
    end

    -- Boden-Anpressung: korrigiert die Höhe über BoundingBox-Unterkante
    local function computeGroundLockCF(v)
        local _, curBboxCF = bboxBottomY(v)
        local pos = curBboxCF.Position
        local targetHitY = groundYBelow(pos, v)
        local cam = workspace.CurrentCamera
        local yawFwd = (cam.CFrame.LookVector * Vector3.new(1,0,1))
        yawFwd = (yawFwd.Magnitude > 1e-3) and yawFwd.Unit or Vector3.new(0,0,-1)

        -- Ausgangsorientierung: Kamera-Yaw + Up
        local targetCF = CFrame.lookAt(pos, pos + yawFwd, cam.CFrame.UpVector)

        -- Iterative Korrektur: Unterkante exakt = hitY + pad
        for _ = 1, TUNE.CORRECT_ITERS do
            hardPivot(v, targetCF)
            RunService.Heartbeat:Wait() -- Physik einmal laufen lassen
            local bottomY, curCF, size = bboxBottomY(v)
            local hitY = groundYBelow(curCF.Position, v) -- nach Pivot neu messen
            local wantBottom = hitY + TUNE.GROUND_PAD
            local dy = wantBottom - bottomY
            if math.abs(dy) < 0.005 then
                -- ausreichend exakt
                targetCF = CFrame.lookAt(Vector3.new(curCF.Position.X, curCF.Position.Y + dy, curCF.Position.Z), Vector3.new(curCF.Position.X, curCF.Position.Y + dy, curCF.Position.Z) + yawFwd, cam.CFrame.UpVector)
                break
            end
            targetCF = CFrame.lookAt(Vector3.new(curCF.Position.X, curCF.Position.Y + dy, curCF.Position.Z), Vector3.new(curCF.Position.X, curCF.Position.Y + dy, curCF.Position.Z) + yawFwd, cam.CFrame.UpVector)
        end

        return v:GetPivot() -- nach letzter Korrektur ist Pivot bereits passend
    end

    local function safeLockOnce()
        local v = myVehicle(); if not v then return end
        if not v.PrimaryPart then if not ensurePP(v) then return end end

        local beforeCF = fly.lastAirCF or v:GetPivot()

        fly.locking = true

        -- Ankern zum harten Anpressen
        for _,p in ipairs(v:GetDescendants()) do
            if p:IsA("BasePart") then p.Anchored = true end
        end

        -- Korrigiertes Boden-CF ermitteln (Unterkante = hitY + pad)
        local groundCF = computeGroundLockCF(v)

        -- Hold-Phase bei exakt angepresster Position
        local t = 0
        while t < TUNE.SAFE_HOLD and fly.enabled do
            hardPivot(v, groundCF)
            t += RunService.Heartbeat:Wait() or 0
        end

        -- Zurück + deankern
        for _,p in ipairs(v:GetDescendants()) do
            if p:IsA("BasePart") then p.Anchored = false end
        end
        if fly.enabled then
            hardPivot(v, beforeCF)
            fly.lastAirCF = beforeCF
        end
        fly.locking = false
    end

    local function setEnabled(on)
        if on == fly.enabled then return end
        local v = myVehicle()
        if on then
            if not v then return end
            if not v.PrimaryPart then if not ensurePP(v) then return end end
            setNetOwner(v)
            fly.lastAirCF = v:GetPivot()
            fly.timer = 0
            if fly.hbConn then fly.hbConn:Disconnect() end
            fly.hbConn = RunService.Heartbeat:Connect(function(dt)
                step(dt)
                if fly.safeOn and not fly.locking then
                    fly.timer += dt
                    if fly.timer >= TUNE.SAFE_PERIOD then
                        fly.timer = 0
                        safeLockOnce()
                    end
                end
            end)
            fly.enabled = true
            if fly.uiToggle then fly.uiToggle:Set(true) end
        else
            fly.enabled = false
            if fly.hbConn then fly.hbConn:Disconnect(); fly.hbConn=nil end
            fly.locking = false
        end
    end

    local function toggle()
        local now=os.clock()
        if now - (fly.debounce or 0) < 0.15 then return end
        fly.debounce = now
        setEnabled(not fly.enabled)
    end

    -- UI: nur Car Fly / Keybind / Safe Fly
    local sec = tab:AddSection({ Name = "Car Fly" })
    fly.uiToggle = sec:AddToggle({ Name = "Enable Car Fly", Default=false, Callback=function(v) setEnabled(v) end })
    sec:AddBind({ Name="Toggle Key", Default=Enum.KeyCode.X, Hold=false, Callback=function() toggle() end })
    sec:AddToggle({ Name="Safe Fly", Default=true, Callback=function(v) fly.safeOn=v; fly.timer=0 end })

    print("[carfly_tp] v5.3.2 loaded (SafeFly presses car to ground)")
end
