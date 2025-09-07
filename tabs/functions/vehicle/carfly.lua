-- tabs/functions/vehicle/vehicle/carfly_tp.lua
return function(SV, tab, OrionLib)

    ----------------------------------------------------------------
    -- Car Fly (TP, precise) + SafeFly (ground-touch 0.5s, restore)
    -- Version: 5.1.0 (UI trimmed: only Fly toggle, Keybind, SafeFly)
    ----------------------------------------------------------------

    ----------------------------------------------------------------
    -- TUNABLES (code-only; no sliders)
    ----------------------------------------------------------------
    local TUNE = {
        SPEED_DEFAULT   = 130,   -- studs/s
        STEP_DIST       = 1.0,   -- max TP per substep
        SUBSTEPS_MAX    = 48,

        -- Camera vertical shaping
        VERT_GAIN       = 1.00,
        Y_BIAS          = 0.00,

        -- Raycast
        RAY_DEPTH       = 4000,

        -- SafeFly
        SAFE_PERIOD     = 6.0,   -- every 6s
        SAFE_HOLD       = 0.5,   -- hold on ground for 0.5s
        SAFE_BACK       = true,  -- return to exact pre-lock CFrame

        -- Server ReSeat (no local Sit/ChangeState)
        RESEAT_ENABLED  = true,
        REMOTE_FOLDER   = "Bnl",
        VEHICLES_FOLDER = "Vehicles",
    }

    ----------------------------------------------------------------
    -- Services / Shortcuts
    ----------------------------------------------------------------
    local RunService = game:GetService("RunService")
    local UserInput  = game:GetService("UserInputService")
    local Players    = game:GetService("Players")
    local RS         = game:GetService("ReplicatedStorage")
    local LP         = Players.LocalPlayer
    local notify     = SV.notify

    ----------------------------------------------------------------
    -- State
    ----------------------------------------------------------------
    local fly = {
        enabled   = false,
        speed     = TUNE.SPEED_DEFAULT,
        safeOn    = true,

        hbConn    = nil,
        safeTask  = nil,
        locking   = false,

        uiToggle  = nil,
        hoverCF   = nil,
        lastAirCF = nil,
        debounce  = 0,
    }

    ----------------------------------------------------------------
    -- Helpers
    ----------------------------------------------------------------
    local function myVehicle() return SV.myVehicleFolder() end
    local function ensurePP(v) SV.ensurePrimaryPart(v); return v.PrimaryPart end
    local function setNetOwner(v) pcall(function() if v and v.PrimaryPart then v.PrimaryPart:SetNetworkOwner(LP) end end) end
    local function seated() return SV.isSeated() end

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

    -- DriveSeat lookup
    local function findSeat(v)
        return SV.findDriveSeat(v) or v:FindFirstChild("DriveSeat")
    end

    -- Dynamic RemoteEvents in RS.Bnl (UUIDs change; fire all)
    local BnlFolder = RS:FindFirstChild(TUNE.REMOTE_FOLDER)
    local function seatRemotes()
        local out = {}
        local folder = BnlFolder or RS:FindFirstChild(TUNE.REMOTE_FOLDER)
        if not folder then return out end
        for _,ch in ipairs(folder:GetChildren()) do
            if ch:IsA("RemoteEvent") then
                table.insert(out, ch)
            end
        end
        return out
    end
    local cachedSeatRemotes = seatRemotes()

    -- FireServer signature observed: (DriveSeat, "Oj2", false)
    local function reseatServerBySeat(seat)
        if not (TUNE.RESEAT_ENABLED and seat) then return end
        for _,re in ipairs(cachedSeatRemotes) do
            pcall(function()
                re:FireServer(seat, "Oj2", false)
            end)
        end
    end

    ----------------------------------------------------------------
    -- Core Flight Step
    ----------------------------------------------------------------
    local function step(dt)
        if not fly.enabled or fly.locking then return end
        if not seated() then return end

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
            local keep = (fly.hoverCF and fly.hoverCF.Position) or curPos
            local lock = CFrame.lookAt(keep, keep + look, up)
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
            local newCF  = CFrame.lookAt(target, target + look, up)
            hardPivot(v, newCF)
            curPos = target
        end

        local final = CFrame.lookAt(curPos, curPos + look, up)
        hardPivot(v, final)
        fly.hoverCF, fly.lastAirCF = final, final
    end

    ----------------------------------------------------------------
    -- SafeFly: every SAFE_PERIOD -> ground-lock for SAFE_HOLD, then restore
    ----------------------------------------------------------------
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
                    if v and (v.PrimaryPart or ensurePP(v)) then
                        local beforeCF = fly.lastAirCF or v:GetPivot()

                        -- Find ground directly below current position
                        local probe = v:GetPivot()
                        local hit = groundHit(probe.Position, TUNE.RAY_DEPTH, {v})
                        if hit then
                            fly.locking = true

                            -- Build ground CF (keep yaw from camera, set Y to ground + small pad)
                            local cam    = workspace.CurrentCamera
                            local yawFwd = (cam.CFrame.LookVector * Vector3.new(1,0,1))
                            yawFwd = (yawFwd.Magnitude > 1e-3) and yawFwd.Unit or Vector3.new(0,0,-1)
                            local base   = Vector3.new(probe.Position.X, hit.Position.Y + 0.2, probe.Position.Z)
                            local groundCF = CFrame.lookAt(base, base + yawFwd, cam.CFrame.UpVector)

                            local seat = findSeat(v)

                            -- Ensure server-side reseat, then hold the ground lock for SAFE_HOLD seconds
                            reseatServerBySeat(seat)
                            local t0 = os.clock()
                            while os.clock() - t0 < TUNE.SAFE_HOLD and fly.enabled do
                                hardPivot(v, groundCF)
                                reseatServerBySeat(seat)
                                RunService.Heartbeat:Wait()
                            end

                            -- Return to exact previous CFrame
                            if TUNE.SAFE_BACK and fly.enabled then
                                hardPivot(v, beforeCF)
                                fly.hoverCF, fly.lastAirCF = beforeCF, beforeCF
                                reseatServerBySeat(seat)
                            end

                            fly.locking = false
                        end
                    end
                end
            end
        end)
    end

    ----------------------------------------------------------------
    -- Enable/Disable
    ----------------------------------------------------------------
    local function setEnabled(on)
        if on == fly.enabled then return end
        local v = myVehicle()

        if on then
            if not v then notify("Car Fly","No vehicle."); return end
            if not v.PrimaryPart then if not ensurePP(v) then notify("Car Fly","No PrimaryPart."); return end end
            setNetOwner(v)

            local cf = v:GetPivot()
            fly.hoverCF, fly.lastAirCF = cf, cf

            if fly.hbConn then fly.hbConn:Disconnect() end
            fly.hbConn = RunService.Heartbeat:Connect(step)

            startSafeFly()
            fly.enabled = true
            if fly.uiToggle then fly.uiToggle:Set(true) end
            notify("Car Fly", ("Enabled (Speed %d)"):format(fly.speed), 2)
        else
            fly.enabled = false
            if fly.hbConn   then fly.hbConn:Disconnect();   fly.hbConn  = nil end
            if fly.safeTask then task.cancel(fly.safeTask); fly.safeTask = nil end
            fly.locking = false
            if fly.uiToggle then fly.uiToggle:Set(false) end
            notify("Car Fly","Disabled.", 2)
        end
    end

    local function toggle()
        local now = os.clock()
        if now - fly.debounce < 0.15 then return end
        fly.debounce = now
        setEnabled(not fly.enabled)
    end

    ----------------------------------------------------------------
    -- UI (minimal)
    ----------------------------------------------------------------
    local sec = tab:AddSection({ Name = "Car Fly" })

    fly.uiToggle = sec:AddToggle({
        Name = "Enable Car Fly",
        Default = false,
        Callback = function(v) setEnabled(v) end
    })

    sec:AddBind({
        Name = "Toggle Key",
        Default = Enum.KeyCode.X,
        Hold = false,
        Callback = function() toggle() end
    })

    sec:AddToggle({
        Name = "Safe Fly",
        Default = true,
        Callback = function(v) fly.safeOn = v end
    })

    -- Auto-Off when leaving seat
    RunService.Heartbeat:Connect(function()
        if fly.enabled and not seated() then setEnabled(false) end
    end)

    print("[carfly v5.1.0] loaded (minimal UI, SafeFly active)")
end
