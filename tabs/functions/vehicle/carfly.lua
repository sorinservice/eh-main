-- tabs/functions/vehicle/vehicle/carfly_tp.lua
return function(SV, tab, OrionLib)
    -- TP Car Fly — precise cam-follow + RELIABLE SafeFly + dynamic ReSeat

    -- === Services ===
    local RunService = game:GetService("RunService")
    local UserInput  = game:GetService("UserInputService")
    local Players    = game:GetService("Players")
    local RS         = game:GetService("ReplicatedStorage")
    local LP         = Players.LocalPlayer
    local Camera     = workspace.CurrentCamera

    -- === Shortcuts from SV ===
    local notify = SV.notify
    local function myVehicle() return SV.myVehicleFolder() end
    local function ensurePP(v) SV.ensurePrimaryPart(v); return v.PrimaryPart end
    local function findSeat(v) return SV.findDriveSeat(v) end
    local function isSeated() return SV.isSeated() end

    -- === Tunables (script-only) ===
    local SPEED_DEFAULT   = 260
    local STEP_DIST       = 1.0
    local SUBSTEPS_MAX    = 48

    local SAFE_PERIOD     = 6.0      -- every 6s while fly is enabled
    local SAFE_HOLD       = 0.5      -- lock time on ground
    local SAFE_BACK       = true
    local SAFE_RAY_DEPTH  = 4000
    local GROUND_PAD_Y    = 2

    local TOGGLE_KEY      = Enum.KeyCode.X

    -- === Dynamic Remote discovery (Bnl / UUID RemoteEvent) ===
    local VehiclesFolder  = workspace:FindFirstChild("Vehicles")
    local BnlFolder       = RS:FindFirstChild("Bnl")

    local function isUuidName(s)
        return typeof(s)=="string" and s:match("^[%x]+%-%x+%-%x+%-%x+%-%x+$") ~= nil
    end

    local function guessSeatRemote()
        if not BnlFolder then return nil end
        -- prefer UUID-looking RemoteEvents
        for _,child in ipairs(BnlFolder:GetChildren()) do
            if child:IsA("RemoteEvent") and isUuidName(child.Name) then
                return child
            end
        end
        -- fallback: first RemoteEvent
        for _,child in ipairs(BnlFolder:GetChildren()) do
            if child:IsA("RemoteEvent") then
                return child
            end
        end
        return nil
    end

    local SeatRemote = guessSeatRemote()

    local function reseatServerBySeat(seat)
        if not SeatRemote or not seat then return end
        -- matches your observed call signature: (DriveSeat, "Oj2", false)
        pcall(function()
            SeatRemote:FireServer(seat, "Oj2", false)
        end)
    end

    -- === State ===
    local fly = {
        enabled=false, safeOn=true, speed=SPEED_DEFAULT,
        hbConn=nil, locking=false,
        uiToggle=nil,
        hoverCF=nil, lastAirCF=nil,
        debounce=0,
        lastSafeClock=nil,   -- os.clock() timestamp for SAFE_PERIOD
    }

    -- === Helpers ===
    local function setNetOwner(v)
        pcall(function()
            local pp=v and v.PrimaryPart
            if pp then pp:SetNetworkOwner(LP) end
        end)
    end

    local function hardPivot(v, cf)
        local pp=v.PrimaryPart
        if pp then
            pp.AssemblyLinearVelocity  = Vector3.zero
            pp.AssemblyAngularVelocity = Vector3.zero
        end
        v:PivotTo(cf)
    end

    local function hasInput()
        if UserInput:GetFocusedTextBox() then return false end
        return UserInput:IsKeyDown(Enum.KeyCode.W) or UserInput:IsKeyDown(Enum.KeyCode.S)
    end

    local function dirScalar()
        local d=0
        if not UserInput:GetFocusedTextBox() then
            if UserInput:IsKeyDown(Enum.KeyCode.W) then d+=1 end
            if UserInput:IsKeyDown(Enum.KeyCode.S) then d-=1 end
        end
        return d
    end

    local function rayDown(pos, depth, ignore)
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Blacklist
        params.FilterDescendantsInstances = ignore or {}
        return workspace:Raycast(pos, Vector3.new(0, -(depth or SAFE_RAY_DEPTH), 0), params)
    end

    -- === SafeFly routine (non-blocking trigger, but blocking during lock) ===
    local function doSafeFly()
        if fly.locking then return end
        local v = myVehicle(); if not v then return end
        if not v.PrimaryPart then if not ensurePP(v) then return end end

        local before  = fly.lastAirCF or v:GetPivot()
        local probeCF = v:GetPivot()

        local hit = rayDown(probeCF.Position, SAFE_RAY_DEPTH, {v})
        if not hit then return end

        fly.locking = true

        local basePos = Vector3.new(probeCF.Position.X, hit.Position.Y + GROUND_PAD_Y, probeCF.Position.Z)
        local camCF   = Camera.CFrame
        local yawFwd  = (camCF.LookVector * Vector3.new(1,0,1))
        yawFwd = (yawFwd.Magnitude > 1e-3) and yawFwd.Unit or Vector3.new(0,0,-1)
        local groundCF = CFrame.lookAt(basePos, basePos + yawFwd, camCF.UpVector)

        local seat  = findSeat(v)
        local hum   = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")

        -- reseat BEFORE first ground pivot (prevents pop-out)
        if hum then
            reseatServerBySeat(seat)
            if seat and seat.Occupant ~= hum then pcall(function() seat:Sit(hum) end) end
        end

        local tEnd = os.clock() + SAFE_HOLD
        while fly.enabled and os.clock() < tEnd do
            hardPivot(v, groundCF)
            -- reseat EVERY frame during lock
            if hum then
                if not seat or seat.Occupant ~= hum then
                    reseatServerBySeat(seat)
                    if seat then pcall(function() seat:Sit(hum) end) end
                end
            end
            RunService.Heartbeat:Wait()
        end

        if SAFE_BACK and fly.enabled then
            hardPivot(v, before)
            fly.hoverCF, fly.lastAirCF = before, before
            if hum then
                if not seat or seat.Occupant ~= hum then
                    reseatServerBySeat(seat)
                    if seat then pcall(function() seat:Sit(hum) end) end
                end
            end
        end

        fly.locking = false
    end

    -- === Flight step (also drives the SafeFly scheduler reliably) ===
    local function step(dt)
        if not fly.enabled then return end

        -- schedule SafeFly strictly every SAFE_PERIOD (no drift)
        local now = os.clock()
        if not fly.lastSafeClock then
            fly.lastSafeClock = now
        elseif (now - fly.lastSafeClock) >= SAFE_PERIOD and fly.safeOn and not fly.locking then
            fly.lastSafeClock = now
            doSafeFly()
            return -- during lock the movement is handled; after lock we resume
        end

        if fly.locking then return end
        if not isSeated() then return end

        local v = myVehicle(); if not v then return end
        if not v.PrimaryPart then if not ensurePP(v) then return end end
        setNetOwner(v)

        local look = Camera.CFrame.LookVector
        if look.Magnitude < 0.999 then look = look.Unit end
        local up   = Camera.CFrame.UpVector

        local curCF  = v:GetPivot()
        local curPos = curCF.Position

        if not hasInput() then
            local keep = (fly.hoverCF and fly.hoverCF.Position) or curPos
            hardPivot(v, CFrame.lookAt(keep, keep + look, up))
            fly.lastAirCF = v:GetPivot()
            return
        end

        local s        = dirScalar()
        local total    = (fly.speed * dt) * (s >= 0 and 1 or -1)
        local absDist  = math.abs(total)
        local sub      = math.clamp(math.ceil(absDist / STEP_DIST), 1, SUBSTEPS_MAX)
        local stepDist = total / sub

        for _=1, sub do
            local target = curPos + (look * stepDist)
            local newCF  = CFrame.lookAt(target, target + look, up)
            hardPivot(v, newCF)
            curPos = target
        end

        local final = CFrame.lookAt(curPos, curPos + look, up)
        hardPivot(v, final)
        fly.hoverCF, fly.lastAirCF = final, final
    end

    -- === Enable/Disable ===
    local function setEnabled(on)
        if on == fly.enabled then return end
        local v = myVehicle()

        if on then
            if not v then notify("Car Fly","No vehicle."); return end
            if not v.PrimaryPart then if not ensurePP(v) then notify("Car Fly","No PrimaryPart."); return end end
            setNetOwner(v)

            local cf = v:GetPivot()
            fly.hoverCF, fly.lastAirCF = cf, cf
            fly.lastSafeClock = os.clock()   -- start SafeFly timer NOW

            if fly.hbConn then fly.hbConn:Disconnect() end
            fly.hbConn = RunService.Heartbeat:Connect(step)

            fly.enabled = true
            if fly.uiToggle then fly.uiToggle:Set(true) end
            notify("Car Fly", ("Enabled (Speed %d)"):format(fly.speed), 2)
        else
            fly.enabled = false
            if fly.hbConn then fly.hbConn:Disconnect(); fly.hbConn = nil end
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

    -- === Minimal UI ===
    local sec = tab:AddSection({ Name = "Car Fly" })
    fly.uiToggle = sec:AddToggle({
        Name = "Enable",
        Default = false,
        Callback = function(v) setEnabled(v) end
    })
    sec:AddBind({
        Name = "Toggle Key",
        Default = TOGGLE_KEY,
        Hold = false,
        Callback = function() toggle() end
    })
    sec:AddSlider({
        Name = "Speed",
        Min = 10, Max = 800, Increment = 5,
        Default = SPEED_DEFAULT,
        Callback = function(v) fly.speed = math.floor(v) end
    })
    sec:AddToggle({
        Name = "Safe Fly",
        Default = true,
        Callback = function(v) fly.safeOn = v end
    })

    -- safety: auto-off when leaving seat
    RunService.Heartbeat:Connect(function()
        if fly.enabled and not isSeated() then setEnabled(false) end
    end)

    print("[carfly v5.0.2] loaded")
end
