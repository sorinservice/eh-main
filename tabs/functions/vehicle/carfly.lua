-- CarFly (serverweit) – Velocity-Steuerung (Zach-Stil) + feste Kameraausrichtung,
-- Clean Enable/Disable, echtes SafeFly (Bodenpress + zurück), schwacher NoClip.
-- UI: Toggle, SafeFly, Mobile, Speed (Default 130). Keybind: X.

return function(SV, tab, OrionLib)
    local RunService   = game:GetService("RunService")
    local UserInput    = game:GetService("UserInputService")
    local Workspace    = game:GetService("Workspace")
    local Camera       = SV.Camera

    -- ===== Tuning =====
    local DEFAULT_SPEED     = 130
    local ACCEL_LERP        = 0.22     -- schnelleres Ansprechen (festeres Gefühl)
    local TURN_LERP         = 0.38     -- harte Ausrichtung zur Kamera (0..1)
    local SIDE_SCALE        = 0.75     -- A/D etwas schwächer (unauffälliger)
    local MAX_CLIMB         = 55       -- |Y| Deckel
    local SAFE_PERIOD       = 6.0      -- alle 6s
    local SAFE_HOLD         = 0.5      -- 0.5s am Boden “gepresst”
    local SAFE_DOWN_V       = -160     -- Down-Tempo während Hold
    local SOFT_OFF_TIME     = 0.35     -- Ausrollzeit beim Ausschalten
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
        savedColl = {},   -- CanCollide restore
        lastAirCF = nil,  -- für SafeFly zurück-TP
    }

    local function notify(t,m,s) SV.notify(t,m,s or 3) end
    local function veh() return SV.myVehicleFolder() end
    local function pp(v) SV.ensurePrimaryPart(v); return (v and v.PrimaryPart) or nil end
    local function isOwner(bp)
        if typeof(isnetworkowner) == "function" then local ok,owns=pcall(isnetworkowner,bp); if ok then return owns end end
        return true
    end

    local function setWeakNoClip(v, on)
        if not v then return end
        if on then
            fly.savedColl = {}
            for _,d in ipairs(v:GetDescendants()) do
                if d:IsA("BasePart") then
                    fly.savedColl[d] = d.CanCollide
                    d.CanCollide = false
                end
            end
        else
            for part,was in pairs(fly.savedColl) do
                if part and part.Parent then
                    part.CanCollide = was
                end
            end
            fly.savedColl = {}
        end
    end

    -- Clean disable: kurzes Ausrollen + leichter Down-Bias
    local function softDisable(primary)
        if not primary then return end
        local t0, dur = tick(), SOFT_OFF_TIME
        local v0 = primary.Velocity
        while tick() - t0 < dur do
            local a = (tick() - t0)/dur
            local k = math.exp(-4*a) -- schnelleres Abbremsen
            primary.Velocity = v0 * k + Vector3.new(0, -20*(1-k), 0)
            RunService.Heartbeat:Wait()
        end
        -- final kleiner Stop
        primary.Velocity = Vector3.new(0, -6, 0)
    end

    -- === SafeFly: Bodenpress + zurück ===
    local function startSafeFly()
        if fly.safeTask then task.cancel(fly.safeTask) end
        fly.safeTask = task.spawn(function()
            while fly.enabled do
                if not fly.safeOn then task.wait(0.25)
                else
                    task.wait(SAFE_PERIOD)
                    if not fly.enabled then break end
                    local v = veh(); if not v then break end
                    local primary = pp(v); if not primary or not isOwner(primary) then break end

                    -- Luftposition merken
                    local before = v:GetPivot()
                    fly.lastAirCF = before

                    -- Raycast nach unten
                    local params = RaycastParams.new()
                    params.FilterType = Enum.RaycastFilterType.Blacklist
                    params.FilterDescendantsInstances = { v }
                    local hit = Workspace:Raycast(before.Position, Vector3.new(0,-2000,0), params)

                    if hit then
                        -- 0.5s “an Boden pressen”: horizontale Bewegung quasi nullen,
                        -- starke Down-Velocity. Kein Teleport hier.
                        local t0 = os.clock()
                        while os.clock() - t0 < SAFE_HOLD and fly.enabled do
                            -- horizontal abbauen
                            local vel = primary.Velocity
                            local h   = Vector3.new(vel.X, 0, vel.Z) * 0.1
                            primary.Velocity = Vector3.new(h.X, SAFE_DOWN_V, h.Z)
                            RunService.Heartbeat:Wait()
                        end
                        -- einmalig zurück zur Luftposition (dein gewünschtes Verhalten)
                        if fly.enabled and fly.lastAirCF then
                            pcall(function() v:PivotTo(fly.lastAirCF) end)
                        end
                    end
                end
            end
        end)
    end

    -- === Schritt: Eingabe → Zielgeschwindigkeit → Velocity + Facing ===
    local function step(dt)
        if not fly.enabled then return end
        if not SV.isSeated() then return end

        local v = veh(); if not v then return end
        local primary = pp(v); if not primary or primary.Anchored then return end
        if not isOwner(primary) then return end

        -- Eingabe (Keyboard + Mobile)
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
            target = wish.Unit * fly.speed
        end
        -- vertikal deckeln (festeres Gefühl)
        if target.Y >  MAX_CLIMB then target = Vector3.new(target.X,  MAX_CLIMB, target.Z) end
        if target.Y < -MAX_CLIMB then target = Vector3.new(target.X, -MAX_CLIMB, target.Z) end

        -- glätten
        fly.curVel = fly.curVel:Lerp(target, math.clamp(ACCEL_LERP,0,1))

        -- direkt Velocity schreiben (leise, ohne Zero-Spam)
        primary.Velocity = fly.curVel

        -- **feste** kameraorientierte Nase (schnelleres Lerp)
        local dir = (fly.curVel.Magnitude > 1) and fly.curVel.Unit or Camera.CFrame.LookVector
        local tgt = CFrame.lookAt(primary.Position, primary.Position + dir)
        primary.CFrame = primary.CFrame:Lerp(tgt, math.clamp(TURN_LERP, 0, 1))
    end

    -- === Mobile Panel (klein & simpel) ===
    local function spawnMobileFly()
        local gui = Instance.new("ScreenGui")
        gui.Name = "Sorin_MobileFly"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true
        gui.Enabled = false; gui.Parent = game:GetService("CoreGui")

        local frame = Instance.new("Frame")
        frame.Size = UDim2.fromOffset(230, 160)
        frame.Position = UDim2.fromOffset(40, 300)
        frame.BackgroundColor3 = Color3.fromRGB(25,25,25); frame.Parent = gui
        Instance.new("UICorner", frame).CornerRadius = UDim.new(0,12)

        local title = Instance.new("TextLabel")
        title.Size = UDim2.new(1, -10, 0, 22); title.Position = UDim2.fromOffset(10, 6)
        title.BackgroundTransparency = 1; title.Font = Enum.Font.GothamBold
        title.TextSize = 14; title.TextColor3 = Color3.fromRGB(240,240,240)
        title.TextXAlignment = Enum.TextXAlignment.Left; title.Text = "Car Fly"; title.Parent = frame

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
            local now=os.clock(); if now-fly.toggleTS<0.15 then return end
            fly.toggleTS=now; if fly.uiToggle then fly.uiToggle:Set(not fly.enabled) end
            if fly.enabled then fly.enabled=false else fly.enabled=true end
        end)
        mkBtn("^",    85, 34, 60, 28, "F")
        mkBtn("v",    85,100, 60, 28, "B")
        mkBtn("<<",   15, 67, 60, 28, "L")
        mkBtn(">>",   155,67,60, 28, "R")
        mkBtn("Up",   155,34,60, 28, "U")
        mkBtn("Down", 155,100,60, 28, "D")

        -- Drag Area = Kopfzeile
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

    -- === Toggle/Enable ===
    local function setEnabled(on)
        if on == fly.enabled then return end

        local v = veh(); local primary = v and pp(v)
        if on then
            if not v or not primary then notify("Car Fly","Kein Fahrzeug/PrimaryPart."); return end
            if not isOwner(primary) then notify("Car Fly","Kein NetOwner."); return end

            -- Start: keine Sprünge → beginne mit aktueller Velocity
            fly.curVel = primary.Velocity
            setWeakNoClip(v, true)

            if fly.conn then fly.conn:Disconnect() end
            fly.conn = RunService.Heartbeat:Connect(step)
            startSafeFly()
            fly.enabled = true
            if fly.uiToggle then fly.uiToggle:Set(true) end
            notify("Car Fly", ("Aktiviert (Speed %d)"):format(fly.speed), 2)
        else
            if fly.conn then fly.conn:Disconnect() fly.conn=nil end
            if fly.safeTask then task.cancel(fly.safeTask) fly.safeTask=nil end
            fly.enabled = false
            if v and primary then softDisable(primary) end
            setWeakNoClip(v, false)
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

    -- === UI (minimal wie gewünscht) ===
    local sec = tab:AddSection({ Name = "Car Fly" })
    fly.uiToggle = sec:AddToggle({
        Name = "Enable Car Fly (nur im Auto)",
        Default = false,
        Callback = function(v) setEnabled(v) end
    })
    sec:AddBind({
        Name = "Car Fly Toggle Key",
        Default = Enum.KeyCode.X,
        Hold = false,
        Callback = function() toggle() end
    })
    sec:AddToggle({
        Name = "Safe Fly (alle 6s Bodenpress + zurück)",
        Default = false,
        Callback = function(v) fly.safeOn = v end
    })
    sec:AddToggle({
        Name = "Mobile Panel anzeigen",
        Default = false,
        Callback = function(v) if MobileFlyGui then MobileFlyGui.Enabled = v end end
    })
    sec:AddSlider({
        Name = "Fly Speed",
        Min = 10, Max = 300, Increment = 5,
        Default = DEFAULT_SPEED,
        Callback = function(v) fly.speed = math.floor(v) end
    })

    -- Safety: aus, wenn du den Sitz verlässt
    RunService.Heartbeat:Connect(function()
        if fly.enabled and not SV.isSeated() then setEnabled(false) end
    end)
end
