-- Zach-style Car Fly (serverseitig sichtbar sofern Network Ownership vorhanden)
-- - Keybind X (toggle)
-- - SafeFly (alle 6s 0.5s Boden, dann zurück)
-- - Speed 130 default, Accel, Turn, Turbo (Ctrl)
-- - Mobile Panel optional

return function(SV, tab, OrionLib)
    print("Fuck you motherfucking bitch")
    local RunService  = game:GetService("RunService")
    local UserInput   = game:GetService("UserInputService")
    local Workspace   = game:GetService("Workspace")
    local Camera      = SV.Camera

    local function notify(t, m, s) SV.notify(t, m, s or 3) end

    -- ===== Config (Zach-Feeling) =====
    local TOGGLE_KEY          = Enum.KeyCode.X
    local SPEED_KEY           = Enum.KeyCode.LeftControl
    local SPEED_KEY_MULT      = 3

    local FLIGHT_SPEED        = 130  -- default
    local FLIGHT_ACCEL        = 4    -- wie schnell Zielgeschw. erreicht wird
    local TURN_SPEED          = 16   -- Lerpfaktor für Drehung

    local SAFE_PERIOD         = 6.0  -- alle 6s
    local SAFE_HOLD           = 0.5  -- 0.5s am Boden „halten“
    local LAND_HEIGHT         = 15   -- bei Deaktivierung ca. 15 studs über Boden

    -- ===== State =====
    local st = {
        enabled   = false,
        curVel    = Vector3.new(),
        speed     = FLIGHT_SPEED,
        accel     = FLIGHT_ACCEL,
        turn      = TURN_SPEED,
        turboMul  = SPEED_KEY_MULT,
        conn      = nil,
        uiToggle  = nil,
        safeOn    = false,
        safeTask  = nil,
        toggleTS  = 0,
        mobileUI  = nil,
        hold = {F=false,B=false,L=false,R=false,U=false,D=false},
    }

    -- ===== Helpers =====
    local function myVehicle() return SV.myVehicleFolder() end
    local function getPP(v) SV.ensurePrimaryPart(v); return v and v.PrimaryPart or nil end

    local function isOwner(bp)
        if typeof(isnetworkowner) == "function" then
            local ok, owns = pcall(isnetworkowner, bp)
            if ok then return owns end
        end
        return true
    end

    local function rayDownFromModel(v, depth)
        local cf = v:GetPivot()
        local p = RaycastParams.new()
        p.FilterType = Enum.RaycastFilterType.Blacklist
        p.FilterDescendantsInstances = {v}
        return Workspace:Raycast(cf.Position, Vector3.new(0, -math.max(depth or 1000, 1), 0), p)
    end

    local function softLand(v)
        local hit = rayDownFromModel(v, 1000)
        if not hit then return end
        local pos  = hit.Position + Vector3.new(0, LAND_HEIGHT, 0)
        local look = Camera and Camera.CFrame.LookVector or Vector3.new(0,0,-1)
        pcall(function() v:PivotTo(CFrame.new(pos, pos + look)) end)
    end

    -- ===== Kern: pro-Frame Schritt (Zach-Prinzip) =====
    local function step(dt)
        -- nur wenn du im Auto sitzt
        if not SV.isSeated() then return end

        local v = myVehicle(); if not v then return end
        local pp = getPP(v);   if not pp then return end
        if pp.Anchored then return end
        if not isOwner(pp) then return end  -- Ownership-Gate

        -- Eingaben (Cam-basiert)
        local base = Vector3.new()
        if not UserInput:GetFocusedTextBox() then
            if UserInput:IsKeyDown(Enum.KeyCode.W) or st.hold.F then base += (Camera.CFrame.LookVector  * st.speed) end
            if UserInput:IsKeyDown(Enum.KeyCode.S) or st.hold.B then base -= (Camera.CFrame.LookVector  * st.speed) end
            if UserInput:IsKeyDown(Enum.KeyCode.D) or st.hold.R then base += (Camera.CFrame.RightVector * st.speed) end
            if UserInput:IsKeyDown(Enum.KeyCode.A) or st.hold.L then base -= (Camera.CFrame.RightVector * st.speed) end
            if UserInput:IsKeyDown(Enum.KeyCode.Space) or st.hold.U then base += (Camera.CFrame.UpVector * st.speed) end
            if UserInput:IsKeyDown(SPEED_KEY) then base = base * st.turboMul end
        end

        -- sanft auf Zielgeschwindigkeit
        st.curVel = st.curVel:Lerp(base, math.clamp(dt * st.accel, 0, 1))

        -- Zach: Velocity + sanft rotieren
        -- (kein hartes Nullen; minimaler Up-Bias gegen „Absacken“)
        local okv, _ = pcall(function()
            pp.Velocity = st.curVel + Vector3.new(0, 2, 0)
        end)
        if not okv then return end

        -- Drehung zur Bewegungs-/Kamerarichtung (nur wenn PP nicht HRP ist)
        pcall(function()
            pp.RotVelocity = Vector3.new()
            local look = st.curVel.Magnitude > 1 and st.curVel.Unit or Camera.CFrame.LookVector
            local target = CFrame.lookAt(pp.Position, pp.Position + look)
            pp.CFrame = pp.CFrame:Lerp(target, math.clamp(dt * st.turn, 0, 1))
        end)
    end

    -- ===== SafeFly (alle 6s kurz Boden, dann zurück) =====
    local function startSafeFly()
        if st.safeTask then task.cancel(st.safeTask) end
        st.safeTask = task.spawn(function()
            while st.enabled do
                if not st.safeOn then task.wait(0.25)
                else
                    task.wait(SAFE_PERIOD)
                    if not st.enabled then break end
                    local v = myVehicle(); if not v then break end
                    local before = v:GetPivot()

                    local hit = rayDownFromModel(v, 2000)
                    if not hit then continue end

                    local lockCF = CFrame.new(
                        hit.Position + Vector3.new(0, 2, 0),
                        hit.Position + Vector3.new(0, 2, 0) + Camera.CFrame.LookVector
                    )
                    -- einmalig auf Boden
                    pcall(function() v:PivotTo(lockCF) end)

                    -- 0.5s „halten“ (keine harte Nullung)
                    local t0 = os.clock()
                    while os.clock() - t0 < SAFE_HOLD and st.enabled do
                        RunService.Heartbeat:Wait()
                        -- leichtes „Kleben“: Position immer wieder auf lockCF ziehen
                        pcall(function() v:PivotTo(lockCF) end)
                    end

                    -- zurück in die Luft
                    if st.enabled then
                        pcall(function() v:PivotTo(before) end)
                    end
                end
            end
        end)
    end

    -- ===== Toggle =====
    local function setEnabled(on)
        if on == st.enabled then return end

        if on then
            local v = myVehicle(); if not v then notify("Car Fly","Kein Fahrzeug."); return end
            local pp = getPP(v);  if not pp then notify("Car Fly","Kein PrimaryPart."); return end
            if not isOwner(pp) then notify("Car Fly","Kein NetOwner (warte/versuch erneut)."); return end

            st.curVel = pp.Velocity
            if st.conn then st.conn:Disconnect() st.conn = nil end
            st.conn = RunService.Heartbeat:Connect(step)
            startSafeFly()
            st.enabled = true
            if st.uiToggle then st.uiToggle:Set(true) end
            notify("Car Fly", ("Aktiviert (Speed %d)"):format(st.speed), 2)
        else
            st.enabled = false
            if st.conn then st.conn:Disconnect(); st.conn = nil end
            if st.safeTask then task.cancel(st.safeTask); st.safeTask=nil end

            local v = myVehicle()
            if v then softLand(v) end

            if st.uiToggle then st.uiToggle:Set(false) end
            notify("Car Fly","Deaktiviert.", 2)
        end
    end

    local function toggle()
        local now = os.clock()
        if now - st.toggleTS < 0.15 then return end
        st.toggleTS = now
        setEnabled(not st.enabled)
    end

    -- ===== Mobile Panel (optional) =====
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
            b.MouseButton1Down:Connect(function() st.hold[key] = true end)
            b.MouseButton1Up:Connect(function() st.hold[key] = false end)
            b.MouseLeave:Connect(function() st.hold[key] = false end)
            return b
        end

        mkBtn("Toggle", 10, 34, 60, 28, "T").MouseButton1Click:Connect(toggle)
        mkBtn("^",      85, 34, 60, 28, "F")
        mkBtn("v",      85,100, 60, 28, "B")
        mkBtn("<<",     15, 67, 60, 28, "L")
        mkBtn(">>",     155,67, 60, 28, "R")
        mkBtn("Up",     155,34, 60, 28, "U")
        mkBtn("Down",   155,100, 60, 28, "D")

        -- Drag nur über Kopfzeile
        local dragging, start, startPos
        frame.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
               and input.Position.Y - frame.AbsolutePosition.Y <= 26 then
                dragging = true; start = input.Position; startPos = frame.Position
                input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then dragging = false end
                end)
            end
        end)
        UserInput.InputChanged:Connect(function(input)
            if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
                local d = input.Position - start
                frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
            end
        end)

        return gui
    end
    local MobileFlyGui = spawnMobileFly()

    -- ===== UI (nur das, was du wolltest) =====
    local sec = tab:AddSection({ Name = "Car Fly" })

    st.uiToggle = sec:AddToggle({
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

    sec:AddToggle({
        Name = "Safe Fly (alle 6s: 0.5s Boden → zurück)",
        Default = false,
        Callback = function(v) st.safeOn = v end
    })

    sec:AddToggle({
        Name = "Mobile Panel",
        Default = false,
        Callback = function(v) if MobileFlyGui then MobileFlyGui.Enabled = v end end
    })

    sec:AddSlider({
        Name = "Speed",
        Min = 10, Max = 300, Increment = 5,
        Default = FLIGHT_SPEED,
        Callback = function(v) st.speed = math.floor(v) end
    })

    -- Auto-Off wenn aus dem Sitz
    RunService.Heartbeat:Connect(function()
        if st.enabled and not SV.isSeated() then
            setEnabled(false)
        end
    end)
end
