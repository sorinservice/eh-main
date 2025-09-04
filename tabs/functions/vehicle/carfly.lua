-- Zach-style Car Fly (serverweit, kein Anchor/Teleport/Attachments)
-- + Camera-Facing, Soft-Disable, Lift-off-Bias, SafeFly (ohne TP)

return function(SV, tab, OrionLib)
    print("Fuck yourself")
    local RunService   = game:GetService("RunService")
    local UserInput    = game:GetService("UserInputService")
    local Workspace    = game:GetService("Workspace")
    local Camera       = SV.Camera

    -- ===== Tuning =====
    local DEFAULT_SPEED     = 130
    local ACCEL_LERP        = 0.18      -- wie schnell Zielgeschw. erreicht wird
    local TURN_LERP         = 0.12      -- wie schnell zur Kamera gedreht wird
    local SIDE_SCALE        = 0.75      -- A/D etwas entschärfen (Anti-Cheat)
    local MAX_CLIMB         = 55        -- max. vertikale Zielgeschw. |Y|
    local LIFTOFF_NEAR      = 4         -- Bodennähe-Probe (Studs)
    local LIFTOFF_UP        = 12        -- zusätzl. Up-Bias nahe Boden (Stud/s)
    local SAFE_PERIOD       = 6.0       -- alle 6s
    local SAFE_HOLD         = 0.5       -- 0.5s „bremsen + leicht sinken“
    local SAFE_SLOW_FACTOR  = 0.25      -- auf 25% Zieltempo drosseln
    local SAFE_SINK_Y       = -16       -- leichtes Absinken während SafeHold
    local SOFT_OFF_TIME     = 0.6       -- Ausrollzeit beim Ausschalten (s)
    local SPEED_KEY         = Enum.KeyCode.LeftControl
    local SPEED_MULTI       = 3

    -- ===== State =====
    local fly = {
        enabled   = false,
        speed     = DEFAULT_SPEED,
        curVel    = Vector3.new(),
        conn      = nil,
        safeTask  = nil,
        safeOn    = false,
        uiToggle  = nil,
        mobileUI  = nil,
        mobile    = {F=false,B=false,L=false,R=false,U=false,D=false},
        toggleTS  = 0,
        smoothing = 0, -- 0..1 Dämpfung im Frame (für SafeFly/SoftOff)
    }

    local function notify(t,m,s) SV.notify(t,m,s or 3) end

    -- ===== Helpers =====
    local function myVehicle() return SV.myVehicleFolder() end

    local function getPP(v)
        SV.ensurePrimaryPart(v)
        return v and v.PrimaryPart or nil
    end

    local function isOwner(bp)
        if typeof(isnetworkowner) == "function" then
            local ok, owns = pcall(isnetworkowner, bp)
            if ok then return owns end
        end
        return true
    end

    local function groundNear(v, depth)
        local cf = v:GetPivot()
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Blacklist
        params.FilterDescendantsInstances = { v }
        local hit = Workspace:Raycast(cf.Position, Vector3.new(0, -depth, 0), params)
        return hit ~= nil
    end

    -- ===== Core Step (Heartbeat) =====
    local function step(dt)
        if not fly.enabled then return end
        if not SV.isSeated() then return end

        local v  = myVehicle(); if not v then return end
        local pp = getPP(v);    if not pp or not pp.Parent then return end
        if pp.Anchored then return end
        if not isOwner(pp) then return end

        -- Eingabe (W/A/S/D + Space + Mobile Buttons)
        local wish = Vector3.zero
        if not UserInput:GetFocusedTextBox() then
            local look = Camera.CFrame.LookVector
            local right= Camera.CFrame.RightVector
            local up   = Vector3.new(0,1,0)

            if UserInput:IsKeyDown(Enum.KeyCode.W) or fly.mobile.F then wish += look end
            if UserInput:IsKeyDown(Enum.KeyCode.S) or fly.mobile.B then wish -= look end
            if UserInput:IsKeyDown(Enum.KeyCode.D) or fly.mobile.R then wish += right * SIDE_SCALE end
            if UserInput:IsKeyDown(Enum.KeyCode.A) or fly.mobile.L then wish -= right * SIDE_SCALE end
            if UserInput:IsKeyDown(Enum.KeyCode.Space) or fly.mobile.U then wish += up end
            if UserInput:IsKeyDown(SPEED_KEY) then wish = wish * SPEED_MULTI end
        end

        -- Zielgeschwindigkeit
        local target = Vector3.zero
        if wish.Magnitude > 0 then
            wish = wish.Unit
            target = wish * fly.speed
        end

        -- Lift-off nahe Boden: leichter Up-Bias (nur wenn nicht aktiv abwärts)
        local nearG = groundNear(v, LIFTOFF_NEAR)
        if nearG and not (UserInput:IsKeyDown(Enum.KeyCode.LeftControl) or fly.mobile.D) then
            target = target + Vector3.new(0, LIFTOFF_UP, 0)
        end

        -- vertikal deckeln (sanfter)
        if target.Y >  MAX_CLIMB then target = Vector3.new(target.X,  MAX_CLIMB, target.Z) end
        if target.Y < -MAX_CLIMB then target = Vector3.new(target.X, -MAX_CLIMB, target.Z) end

        -- SafeFly-Bremse aktiv?
        if fly.smoothing > 0 then
            -- zieh Zieltempo etwas runter und gib sanft Y-Sink hinzu
            target = target * (1 - fly.smoothing*(1 - SAFE_SLOW_FACTOR))
            target = target + Vector3.new(0, SAFE_SINK_Y * fly.smoothing, 0)
        end

        -- sanft zur Zielgeschwindigkeit
        local lerpA = math.clamp(ACCEL_LERP, 0, 1)
        fly.curVel = fly.curVel:Lerp(target, lerpA)

        -- direkt Velocity schreiben (Zach-Stil)
        -- kein hartes Nullstellen, kein Teleport
        pp.Velocity = fly.curVel

        -- Kamera-Facing: nur Rotation weich lerpen (wenn PP nicht HRP ist)
        if pp ~= (SV.LP.Character and SV.LP.Character:FindFirstChild("HumanoidRootPart")) then
            local dir = fly.curVel.Magnitude > 1 and fly.curVel.Unit or Camera.CFrame.LookVector
            local tgt = CFrame.lookAt(pp.Position, pp.Position + dir)
            pp.CFrame = pp.CFrame:Lerp(tgt, math.clamp(TURN_LERP, 0, 1))
        end
    end

    -- ===== SafeFly (ohne Teleport) =====
    local function startSafeFly()
        if fly.safeTask then task.cancel(fly.safeTask) end
        fly.safeTask = task.spawn(function()
            while fly.enabled do
                if not fly.safeOn then task.wait(0.25)
                else
                    task.wait(SAFE_PERIOD)
                    if not fly.enabled then break end
                    -- 0.5s „bremsen + leicht sinken“ durch smoothing-Blend
                    local t0 = os.clock()
                    while os.clock() - t0 < SAFE_HOLD and fly.enabled do
                        fly.smoothing = 1 -- volle Bremswirkung
                        RunService.Heartbeat:Wait()
                    end
                    fly.smoothing = 0
                end
            end
        end)
    end

    -- ===== Soft Disable (Ausrollen statt Voll-Stop) =====
    local function softDisable(pp)
        -- Ausrollen über SOFT_OFF_TIME; kein Teleport/Zero-Motion
        local start = tick()
        local dur   = SOFT_OFF_TIME
        local v0    = pp.Velocity
        while tick() - start < dur do
            local a = (tick() - start) / dur
            -- Exponentielles Decay
            local factor = math.exp(-3*a)
            pp.Velocity = v0 * factor + Vector3.new(0, SAFE_SINK_Y * 0.25 * (1 - factor), 0)
            RunService.Heartbeat:Wait()
        end
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
            b.MouseButton1Down:Connect(function() fly.mobile[key] = true end)
            b.MouseButton1Up:Connect(function() fly.mobile[key] = false end)
            b.MouseLeave:Connect(function() fly.mobile[key] = false end)
            return b
        end

        mkBtn("Toggle", 10, 34, 60, 28, "T").MouseButton1Click:Connect(function()
            local now = os.clock(); if now - fly.toggleTS < 0.15 then return end
            fly.toggleTS = now
            fly.enabled = not fly.enabled
            if fly.uiToggle then fly.uiToggle:Set(fly.enabled) end
            if fly.enabled then
                fly.curVel = Vector3.new()
                if fly.conn then fly.conn:Disconnect() end
                fly.conn = RunService.Heartbeat:Connect(step)
                startSafeFly()
                notify("Car Fly", ("Aktiviert (Speed %d)"):format(fly.speed), 2)
            else
                if fly.conn then fly.conn:Disconnect() fly.conn=nil end
                if fly.safeTask then task.cancel(fly.safeTask) fly.safeTask=nil end
                local v = myVehicle(); local pp = v and getPP(v)
                if pp then softDisable(pp) end
                notify("Car Fly","Deaktiviert.", 2)
            end
        end)
        mkBtn("^",      85, 34, 60, 28, "F")
        mkBtn("v",      85,100, 60, 28, "B")
        mkBtn("<<",     15, 67, 60, 28, "L")
        mkBtn(">>",     155,67, 60, 28, "R")
        mkBtn("Up",     155,34, 60, 28, "U")
        mkBtn("Down",   155,100, 60, 28, "D")

        -- Drag nur über Kopfzeile
        local dragging, startPos, startInput
        frame.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
               and input.Position.Y - frame.AbsolutePosition.Y <= 26 then
                dragging = true; startInput = input.Position; startPos = frame.Position
                input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then dragging = false end
                end)
            end
        end)
        UserInput.InputChanged:Connect(function(input)
            if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
                local d = input.Position - startInput
                frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
            end
        end)

        return gui
    end
    local MobileFlyGui = spawnMobileFly()

    -- ===== Toggle / UI =====
    local function setEnabled(on)
        if on == fly.enabled then return end
        fly.enabled = on

        if fly.enabled then
            fly.curVel = Vector3.new()
            if fly.conn then fly.conn:Disconnect() end
            fly.conn = RunService.Heartbeat:Connect(step)
            startSafeFly()
            if fly.uiToggle then fly.uiToggle:Set(true) end
            notify("Car Fly", ("Aktiviert (Speed %d)"):format(fly.speed), 2)
        else
            if fly.conn then fly.conn:Disconnect() fly.conn=nil end
            if fly.safeTask then task.cancel(fly.safeTask) fly.safeTask=nil end
            local v = myVehicle(); local pp = v and getPP(v)
            if pp then softDisable(pp) end
            if fly.uiToggle then fly.uiToggle:Set(false) end
            notify("Car Fly","Deaktiviert.", 2)
        end
    end

    local function toggle()
        local now = os.clock()
        if now - fly.toggleTS < 0.15 then return end
        fly.toggleTS = now
        setEnabled(not fly.enabled)
    end

    local sec = tab:AddSection({ Name = "Car Fly" })
    fly.uiToggle = sec:AddToggle({
        Name = "Enable Car Fly (nur im Auto)",
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
        Name = "Safe Fly (0.5s bremsen/sinken alle 6s)",
        Default = false,
        Callback = function(v) fly.safeOn = v end
    })
    sec:AddToggle({
        Name = "Mobile Panel",
        Default = false,
        Callback = function(v) if MobileFlyGui then MobileFlyGui.Enabled = v end end
    })
    sec:AddSlider({
        Name = "Speed",
        Min = 10, Max = 300, Increment = 5,
        Default = DEFAULT_SPEED,
        Callback = function(v) fly.speed = math.floor(v) end
    })

    -- Safety: Auto-off, wenn du nicht mehr sitzt
    RunService.Heartbeat:Connect(function()
        if fly.enabled and not SV.isSeated() then setEnabled(false) end
    end)
end
