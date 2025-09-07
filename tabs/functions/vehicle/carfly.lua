-- tabs/functions/vehicle/vehicle/carfly_tp.lua
return function(SV, tab, OrionLib)
    print("M")

    -- ===== Tunables (code-only) =====
    local TUNE = {
        SPEED_DEFAULT = 130,   -- studs/s
        STEP_DIST     = 1.0,   -- max TP per substep
        SUBSTEPS_MAX  = 48,
        VERT_GAIN     = 1.00,
        Y_BIAS        = 0.00,
        SAFE_PERIOD   = 6.0,   -- every 6s
        SAFE_HOLD     = 0.5,   -- hold 0.5s
        RAY_DEPTH     = 8000,  -- downward ray
        GROUND_PAD    = 0.05,  -- tiny pad to avoid z-fight
    }

    local RunService = game:GetService("RunService")
    local UserInput  = game:GetService("UserInputService")
    local Players    = game:GetService("Players")
    local LP         = Players.LocalPlayer

    local function myVehicle() return SV.myVehicleFolder() end
    local function ensurePP(v) SV.ensurePrimaryPart(v); return v.PrimaryPart end
    local function setNetOwner(v) pcall(function() if v and v.PrimaryPart then v.PrimaryPart:SetNetworkOwner(LP) end end) end

    local function dirScalar()
        if UserInput:GetFocusedTextBox() then return 0 end
        local d = 0
        if UserInput:IsKeyDown(Enum.KeyCode.W) then d += 1 end
        if UserInput:IsKeyDown(Enum.KeyCode.S) then d -= 1 end
        return d
    end

    local function hardPivot(v, cf)
        local pp = v.PrimaryPart
        if pp then
            pp.AssemblyLinearVelocity  = Vector3.zero
            pp.AssemblyAngularVelocity = Vector3.zero
        end
        v:PivotTo(cf)
    end

    local function groundHit(origin, depth, ignore)
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Blacklist
        params.FilterDescendantsInstances = ignore or {}
        return workspace:Raycast(origin, Vector3.new(0, -(depth or TUNE.RAY_DEPTH), 0), params)
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

    -- === Flight step (no idle-grounding) ===
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
            local lock = CFrame.lookAt(curPos, curPos + look, up)
            hardPivot(v, lock)
            fly.lastAirCF = lock
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

    -- === SafeFly: touch ground for 0.5s, then restore EXACTLY ===
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
                    if not v or not (v.PrimaryPart or ensurePP(v)) then goto continue end

                    local beforeCF = fly.lastAirCF or v:GetPivot()
                    local probeCF  = v:GetPivot()

                    -- cast from current position straight down
                    local hit = groundHit(probeCF.Position, TUNE.RAY_DEPTH, {v})
                    if not hit then goto continue end

                    -- compute half-height so BOTTOM touches ground
                    local halfY = (v:GetExtentsSize().Y * 0.5)
                    local cam   = workspace.CurrentCamera
                    local yawF  = (cam.CFrame.LookVector * Vector3.new(1,0,1))
                    yawF = (yawF.Magnitude > 1e-3) and yawF.Unit or Vector3.new(0,0,-1)

                    local baseY    = hit.Position.Y + halfY + TUNE.GROUND_PAD
                    local basePos  = Vector3.new(probeCF.Position.X, baseY, probeCF.Position.Z)
                    local groundCF = CFrame.lookAt(basePos, basePos + yawF, cam.CFrame.UpVector)

                    -- lock: freeze for SAFE_HOLD, then restore
                    fly.locking = true
                    local t0 = os.clock()
                    while os.clock() - t0 < TUNE.SAFE_HOLD and fly.enabled do
                        hardPivot(v, groundCF)
                        RunService.Heartbeat:Wait()
                    end

                    if fly.enabled then
                        hardPivot(v, beforeCF)
                        fly.lastAirCF = beforeCF
                    end

                    fly.locking = false
                    ::continue::
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

end
