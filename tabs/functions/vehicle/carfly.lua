-- tabs/functions/vehicle/vehicle/carfly_tp.lua
return function(SV, tab, OrionLib)

    -- Version: 5.4.5
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
        RAY_DEPTH     = 20000,
        PRESS_EXTRA   = 1.5,          -- wie stark nach unten pressen
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

    local function buildIgnoreList(v)
        local ignore = {v}
        for _,d in ipairs(v:GetDescendants()) do
            if d:IsA("BasePart") then table.insert(ignore, d) end
        end
        return ignore
    end

    local function groundYBelowXZ(x, z, ignoreList)
        local originY = 1e5
        local origin  = Vector3.new(x, originY, z)
        local dir     = Vector3.new(0, -2e5, 0)

        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Blacklist
        params.FilterDescendantsInstances = ignoreList or {}

        local hit = workspace:Raycast(origin, dir, params)
        if hit then return hit.Position.Y end

        local p2 = RaycastParams.new()
        p2.FilterType = Enum.RaycastFilterType.Whitelist
        p2.FilterDescendantsInstances = {workspace.Terrain}
        local hit2 = workspace:Raycast(origin, dir, p2)
        if hit2 then return hit2.Position.Y end

        return 0
    end

    local function getHalfHeight(v)
        local ok, cf, size = pcall(v.GetBoundingBox, v)
        if ok and size then return size.Y * 0.5 end
        local pp = v.PrimaryPart
        return pp and (pp.Size.Y * 0.5) or 3
    end

    local function keepOrientationAtY(v, y)
        local cur = v:GetPivot()
        return CFrame.new(Vector3.new(cur.X, y, cur.Z)) * (cur - cur.Position)
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

    -- === Flug ===
    local function step(dt)
        if not fly.enabled or fly.locking then return end
        if not SV.isSeated() then setEnabled(false); return end

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

    -- === Safe-Lock (ohne Anchorn, knallig pressen) ===
    local function safeLockOnce()
        local v = myVehicle(); if not v then return end
        if not v.PrimaryPart then if not ensurePP(v) then return end end

        local beforeCF = fly.lastAirCF or v:GetPivot()
        local ignore   = buildIgnoreList(v)
        local cur      = v:GetPivot()

        local hitY     = groundYBelowXZ(cur.X, cur.Z, ignore)
        local halfY    = getHalfHeight(v)
        local targetY  = hitY + halfY - TUNE.PRESS_EXTRA
        local groundCF = keepOrientationAtY(v, targetY)

        fly.locking = true

        local t = 0
        while t < TUNE.SAFE_HOLD and fly.enabled do
            hardPivot(v, groundCF)
            t += RunService.Heartbeat:Wait() or 0
        end

        if fly.enabled then
            hardPivot(v, beforeCF)
            fly.lastAirCF = beforeCF
        end
        fly.locking = false
    end

    -- === Enable/Disable ===
    function setEnabled(on)
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

    -- === UI ===
    local sec = tab:AddSection({ Name = "Car Fly" })
    fly.uiToggle = sec:AddToggle({ Name = "Enable Car Fly", Default=false, Callback=function(v) setEnabled(v) end })
    sec:AddBind({ Name="Toggle Key", Default=Enum.KeyCode.X, Hold=false, Callback=function() toggle() end })
    sec:AddToggle({ Name="Safe Fly", Default=true, Callback=function(v) fly.safeOn=v; fly.timer=0 end })

    -- globaler Auto-Off (Failsafe)
    RunService.Heartbeat:Connect(function()
        if fly.enabled and not SV.isSeated() then
            setEnabled(false)
        end
    end)

    print("[carfly_tp v5.4.5] loaded")
end
