-- tabs/functions/vehicle/vehicle/carfly.lua
-- "Echtes" Car Fly (clientseitig, Velocity + Blicksteuerung), mit SafeFly, Mobile-Panel,
-- Boden-Clearance, sanftem Ausstieg und minimaler UI.
-- Signatur passt zu deinem Loader: return function(SV, tab, OrionLib)

return function(SV, tab, OrionLib)
    print("La le lu, nur der Mann im Mond schaut zu...")
    local RunService  = game:GetService("RunService")
    local UserInput   = game:GetService("UserInputService")
    local Workspace   = game:GetService("Workspace")
    local Camera      = SV.Camera

    -- ================== Tuning / Defaults ==================
    local DEFAULT_SPEED       = 130   -- UI-Default
    local ACCEL               = 4     -- wie schnell wir Zielgeschwindigkeit anfahren (lerp factor)
    local TURN_SPEED          = 16    -- wie schnell Nase zur Kamera rotiert (lerp factor)
    local SPEED_KEY           = Enum.KeyCode.LeftControl
    local SPEED_KEY_MULTI     = 3

    local CLEARANCE_PROBE     = 5     -- Bodenscan-Tiefe (studs)
    local CLEARANCE_UP        = 2.0   -- Nudge beim Start / nahe Boden (studs)
    local LAND_SOFT_HEIGHT    = 15    -- bei Disable ~15 studs über Boden parken

    local SAFE_PERIOD         = 6.0   -- alle 6s
    local SAFE_HOLD           = 0.5   -- 0.5s am Boden "kleben"
    local SAFE_TP_BACK        = true  -- EXPLIZIT gewünscht: zurück zur alten Luft-Position teleportieren

    -- ================== State ==================
    local fly = {
        enabled   = false,
        speed     = DEFAULT_SPEED,
        curVel    = Vector3.new(),
        conn      = nil,
        safeTask  = nil,
        safeOn    = false,
        mobileUI  = nil,
        mobileHold= {F=false,B=false,L=false,R=false,U=false,D=false},
        uiToggle  = nil,
        toggleDeb = 0,
    }

    local function notify(t,m,s) SV.notify(t,m,s or 3) end

    -- ================== Helpers ==================
    local function myVehicle()
        return SV.myVehicleFolder()
    end

    local function getPP(v)
        SV.ensurePrimaryPart(v)
        return v and v.PrimaryPart or nil
    end

    local function isNetworkOwner(bp)
        if typeof(isnetworkowner) == "function" then
            local ok, owns = pcall(isnetworkowner, bp)
            if ok then return owns end
        end
        -- Fallback: versuchen trotzdem; wenn nicht Owner, Effekte bleiben i.d.R. lokal ohne Server-Repl.
        return true
    end

    local function groundRay(v, depth)
        if not v then return nil end
        local cf = v:GetPivot()
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Blacklist
        params.FilterDescendantsInstances = { v }
        return Workspace:Raycast(cf.Position, Vector3.new(0, -math.max(depth or 1000, 1), 0), params)
    end

    local function nudgeUp(v, studs)
        if not v then return end
        local cf = v:GetPivot()
        pcall(function() v:PivotTo(cf + Vector3.new(0, studs or CLEARANCE_UP, 0)) end)
    end

    local function settleToGroundSoft(v)
        local hit = groundRay(v, 1000)
        if hit then
            local pos  = hit.Position + Vector3.new(0, LAND_SOFT_HEIGHT, 0)
            local look = Camera.CFrame.LookVector
            pcall(function() v:PivotTo(CFrame.new(pos, pos + look)) end)
        end
    end

    local function zeroMotion(v)
        if not v then return end
        for _,p in ipairs(v:GetDescendants()) do
            if p:IsA("BasePart") then
                p.AssemblyLinearVelocity  = Vector3.new()
                p.AssemblyAngularVelocity = Vector3.new()
            end
        end
    end

    -- ================== Core Step ==================
    local function step(delta)
        if not fly.enabled then return end
        if not SV.isSeated() then return end

        local v  = myVehicle(); if not v then return end
        local pp = getPP(v);    if not pp or pp.Anchored then return end
        if not isNetworkOwner(pp) then return end

        -- Eingabe (Keyboard + Mobile)
        local base = Vector3.new()
        if not UserInput:GetFocusedTextBox() then
            if UserInput:IsKeyDown(Enum.KeyCode.W) or fly.mobileHold.F then
                base += Camera.CFrame.LookVector * fly.speed
            end
            if UserInput:IsKeyDown(Enum.KeyCode.S) or fly.mobileHold.B then
                base -= Camera.CFrame.LookVector * fly.speed
            end
            if UserInput:IsKeyDown(Enum.KeyCode.D) or fly.mobileHold.R then
                base += Camera.CFrame.RightVector * fly.speed
            end
            if UserInput:IsKeyDown(Enum.KeyCode.A) or fly.mobileHold.L then
                base -= Camera.CFrame.RightVector * fly.speed
            end
            if UserInput:IsKeyDown(Enum.KeyCode.Space) or fly.mobileHold.U then
                base += Camera.CFrame.UpVector * fly.speed
            end
            if UserInput:IsKeyDown(SPEED_KEY) then
                base *= SPEED_KEY_MULTI
            end
        end

        -- leichte Boden-Clearance (Reifen hängen nicht)
        do
            local near = groundRay(v, CLEARANCE_PROBE)
            if near and not (UserInput:IsKeyDown(Enum.KeyCode.LeftControl) or fly.mobileHold.D) then
                base = base + Vector3.new(0, fly.speed * 0.15, 0) -- minimaler vertikaler Bias
            end
        end

        -- Zielgeschwindigkeit glätten
        fly.curVel = fly.curVel:Lerp(base, math.clamp(delta * ACCEL, 0, 1))

        -- Bewegungs-Apply (Velocity) + sanftes Ausrichten zur Blickrichtung/Bewegung
        -- (Das ist dein bewährter Ansatz, erweitert mit "soft turn")
        pp.Velocity = fly.curVel + Vector3.new(0, 2, 0)

        -- Sanftes Drehen (nur wenn PP nicht der HRP des Spielers ist)
        local lookDir = (fly.curVel.Magnitude > 0) and fly.curVel.Unit or Camera.CFrame.LookVector
        pcall(function()
            pp.RotVelocity = Vector3.new()
            local tgt = CFrame.lookAt(pp.Position, pp.Position + lookDir)
            pp.CFrame = pp.CFrame:Lerp(tgt, math.clamp(delta * TURN_SPEED, 0, 1))
        end)
    end

    -- ================== SafeFly ==================
    local function startSafeFlyLoop()
        if fly.safeTask then task.cancel(fly.safeTask) end
        fly.safeTask = task.spawn(function()
            while fly.enabled do
                if not fly.safeOn then task.wait(0.25)
                else
                    task.wait(SAFE_PERIOD)
                    if not fly.enabled then break end
                    local v = myVehicle(); if not v then break end

                    -- Alte Luft-Position merken
                    local before = v:GetPivot()

                    -- Boden finden & kurz "festhalten"
                    local hit = groundRay(v, 1500)
                    if hit then
                        local groundCF = CFrame.new(hit.Position + Vector3.new(0, 2, 0),
                                                    hit.Position + Vector3.new(0, 2, 0) + Camera.CFrame.LookVector)
                        local t0 = os.clock()
                        while os.clock() - t0 < SAFE_HOLD and fly.enabled do
                            pcall(function() v:PivotTo(groundCF) end)
                            zeroMotion(v)
                            RunService.Heartbeat:Wait()
                        end
                        -- zurück an exakt dieselbe Luft-Position
                        if SAFE_TP_BACK and fly.enabled then
                            pcall(function() v:PivotTo(before) end)
                        end
                    end
                end
            end
        end)
    end

    -- ================== Toggle ==================
    local function setEnabled(on)
        if on == fly.enabled then return end
        fly.enabled = on

        local v = myVehicle()
        if not v then
            fly.enabled = false
            if fly.uiToggle then fly.uiToggle:Set(false) end
            notify("Car Fly","Kein Fahrzeug.")
            return
        end

        if fly.enabled then
            -- kleiner Lift-Off gegen Bodenklemmen
            nudgeUp(v, CLEARANCE_UP)
            fly.curVel = Vector3.new()
            if fly.conn then fly.conn:Disconnect() end
            fly.conn = RunService.Heartbeat:Connect(step)
            startSafeFlyLoop()
            if fly.uiToggle then fly.uiToggle:Set(true) end
            notify("Car Fly", ("Aktiviert (Speed %d)"):format(fly.speed), 2)
        else
            if fly.conn then fly.conn:Disconnect() fly.conn=nil end
            if fly.safeTask then task.cancel(fly.safeTask) fly.safeTask=nil end

            -- sanfter Exit: oben über Boden parken + Bewegung rausnehmen
            settleToGroundSoft(v)
            zeroMotion(v)

            if fly.uiToggle then fly.uiToggle:Set(false) end
            notify("Car Fly","Deaktiviert.", 2)
        end
    end

    local function toggle()
        local now = os.clock()
        if now - fly.toggleDeb < 0.15 then return end
        fly.toggleDeb = now
        setEnabled(not fly.enabled)
    end

    -- ================== Mobile Panel ==================
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
            b.MouseButton1Down:Connect(function() fly.mobileHold[key] = true end)
            b.MouseButton1Up:Connect(function() fly.mobileHold[key] = false end)
            b.MouseLeave:Connect(function() fly.mobileHold[key] = false end)
            return b
        end

        mkBtn("Toggle", 10, 34, 60, 28, "T").MouseButton1Click:Connect(toggle)
        mkBtn("^",      85, 34, 60, 28, "F")
        mkBtn("v",      85,100, 60, 28, "B")
        mkBtn("<<",     15, 67, 60, 28, "L")
        mkBtn(">>",     155,67, 60, 28, "R")
        mkBtn("Up",     155,34, 60, 28, "U")
        mkBtn("Down",   155,100,60, 28, "D")

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

    -- ================== UI (minimal) ==================
    local sec = tab:AddSection({ Name = "Car Fly" })

    fly.uiToggle = sec:AddToggle({
        Name = "Enable Car Fly (nur im Auto)",
        Default = false,
        Callback = function(v) setEnabled(v) end
    })

    sec:AddBind({
        Name = "Toggle Key",
        Default = Enum.KeyCode.X,   -- dein Wunsch: Keybind wieder drin
        Hold = false,
        Callback = function() toggle() end
    })

    sec:AddToggle({
        Name = "Safe Fly (alle 6s → 0.5s Boden, dann zurück)",
        Default = false,
        Callback = function(v) fly.safeOn = v end
    })

    sec:AddToggle({
        Name = "Mobile Fly Panel",
        Default = false,
        Callback = function(v) if MobileFlyGui then MobileFlyGui.Enabled = v end end
    })

    sec:AddSlider({
        Name = "Speed",
        Min = 10, Max = 300, Increment = 5,
        Default = DEFAULT_SPEED,
        Callback = function(v) fly.speed = math.floor(v) end
    })

    -- Safety: wenn du den Sitz verlässt → Fly aus
    RunService.Heartbeat:Connect(function()
        if fly.enabled and not SV.isSeated() then
            setEnabled(false)
        end
    end)
end
