-- tabs/functions/vehicle/vehicle/carfly.lua
-- Fly per Physics (Attachment + LinearVelocity + AlignOrientation)
-- Serverweit replizierend, Anti-Cheat-freundlich, mit SafeFly & Mobile-UI

return function(SV, tab, OrionLib)
    local RunService  = game:GetService("RunService")
    local UserInput   = game:GetService("UserInputService")
    local Workspace   = game:GetService("Workspace")
    local Camera      = SV.Camera

    local function notify(title, msg, t) SV.notify(title, msg, t or 3) end

    -- =================== Tuning / State ===================
    local fly = {
        enabled        = false,
        speed          = 130,   -- Standard
        accelLerp      = 0.18,  -- Glättung 0..1 (je größer, desto direkter)
        climbMax       = 38,    -- max vertikale Zielgeschw.
        rotResponse    = 35,    -- AlignOrientation.Responsiveness
        weakNoClip     = true,  -- "soft noclip" bei Kollisionen
        safeFly        = false, -- 6s → 0.5s Boden, danach exakt zurück
        mobileEnabled  = false,

        -- intern
        att = nil, lv = nil, ao = nil, pp = nil,
        conn = nil, safeThread = nil,
        smoothed = Vector3.new(),
        savedFlags = {},               -- CanCollide-Flags
        weakNoclipUntil = 0,           -- Zeitstempel für temporäres NoClip
        groundLock = false,
        uiToggle = nil,
    }

    -- =================== Helpers ===================
    local function getPP(v)
        SV.ensurePrimaryPart(v)
        return v.PrimaryPart
    end

    local function forEachPart(vf, fn)
        if not vf then return end
        for _,p in ipairs(vf:GetDescendants()) do
            if p:IsA("BasePart") then fn(p) end
        end
    end

    local function zeroMotion(vf)
        forEachPart(vf, function(bp)
            bp.AssemblyLinearVelocity  = Vector3.new()
            bp.AssemblyAngularVelocity = Vector3.new()
        end)
    end

    local function buildControllers(v)
        local pp = getPP(v); if not pp then return false end
        fly.pp = pp

        fly.att = Instance.new("Attachment")
        fly.att.Name = "SorinFly_Att"
        fly.att.Parent = pp

        local lv = Instance.new("LinearVelocity")
        lv.Name = "SorinFly_LV"
        lv.Attachment0 = fly.att
        lv.RelativeTo  = Enum.ActuatorRelativeTo.World
        lv.MaxForce    = math.huge
        lv.VectorVelocity = Vector3.new()
        lv.Parent = pp
        fly.lv = lv

        local ao = Instance.new("AlignOrientation")
        ao.Name = "SorinFly_AO"
        ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
        ao.Attachment0 = fly.att
        ao.MaxTorque = math.huge
        ao.Responsiveness = fly.rotResponse
        ao.RigidityEnabled = false
        ao.Parent = pp
        fly.ao = ao

        -- Originale Kollision merken
        fly.savedFlags = {}
        forEachPart(v, function(bp)
            fly.savedFlags[bp] = { CanCollide = bp.CanCollide }
        end)

        return true
    end

    local function destroyControllers()
        if fly.lv then pcall(function() fly.lv.VectorVelocity = Vector3.new() end) end
        for _,inst in ipairs({fly.ao, fly.lv, fly.att}) do
            if inst and inst.Parent then inst:Destroy() end
        end
        fly.att, fly.lv, fly.ao, fly.pp = nil, nil, nil, nil
    end

    local function restoreCollision(v)
        for bp,fl in pairs(fly.savedFlags) do
            if bp and bp.Parent then
                bp.CanCollide = fl.CanCollide
            end
        end
        fly.savedFlags = {}
    end

    local function aheadRay(v, dist)
        local cf = v:GetPivot()
        local dir = Camera.CFrame.LookVector * (dist or 5)
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Blacklist
        params.FilterDescendantsInstances = { v }
        return Workspace:Raycast(cf.Position, dir, params)
    end

    local function groundRay(v, depth)
        local cf = v:GetPivot()
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Blacklist
        params.FilterDescendantsInstances = { v }
        return Workspace:Raycast(cf.Position, Vector3.new(0,-(depth or 1000),0), params)
    end

    local function settleToGroundSoft(v)
        local hit = groundRay(v, 1000)
        if hit then
            local up = 15
            local pos = hit.Position + Vector3.new(0, up, 0)
            local look = Camera.CFrame.LookVector
            pcall(function()
                v:PivotTo(CFrame.new(pos, pos + look))
            end)
        end
    end

    -- =================== Weak NoClip ===================
    local function applyWeakNoClip(v)
        local now = os.clock()
        if now < fly.weakNoclipUntil then
            -- während des Fensters: Kollision aus
            forEachPart(v, function(bp)
                if fly.savedFlags[bp] then bp.CanCollide = false end
            end)
            return
        end

        -- Fenster abgelaufen → Standard herstellen
        forEachPart(v, function(bp)
            local saved = fly.savedFlags[bp]
            if saved then bp.CanCollide = saved.CanCollide end
        end)

        -- Engstelle direkt vor uns?
        local hit = aheadRay(v, 5)
        if hit then
            -- kurz & leicht durchlässig machen
            fly.weakNoclipUntil = now + 0.25
            forEachPart(v, function(bp)
                if fly.savedFlags[bp] then bp.CanCollide = false end
            end)
        end
    end

    -- =================== Core Step ===================
    local mobileHold = {F=false,B=false,L=false,R=false,U=false,D=false}

    local function step(dt)
        if not fly.enabled or fly.groundLock then return end
        if not SV.isSeated() then return end

        local v = SV.myVehicleFolder(); if not v then return end
        if not fly.pp or not fly.pp.Parent then
            if not buildControllers(v) then return end
        end

        -- Nase → Kamera
        if fly.ao then
            fly.ao.CFrame = Camera.CFrame.Rotation
            fly.ao.Responsiveness = fly.rotResponse
        end

        -- Eingabe (Key + Mobile)
        local dir = Vector3.zero
        if not UserInput:GetFocusedTextBox() then
            if UserInput:IsKeyDown(Enum.KeyCode.W) or mobileHold.F then dir += Camera.CFrame.LookVector end
            if UserInput:IsKeyDown(Enum.KeyCode.S) or mobileHold.B then dir -= Camera.CFrame.LookVector end
            if UserInput:IsKeyDown(Enum.KeyCode.D) or mobileHold.R then dir += Camera.CFrame.RightVector end
            if UserInput:IsKeyDown(Enum.KeyCode.A) or mobileHold.L then dir -= Camera.CFrame.RightVector end
            if UserInput:IsKeyDown(Enum.KeyCode.Space) or mobileHold.U then dir += Vector3.new(0,1,0) end
            if UserInput:IsKeyDown(Enum.KeyCode.LeftControl) or mobileHold.D then dir -= Vector3.new(0,1,0) end
        end

        -- leichter Boden-Bias, um Räder-Klemmen zu vermeiden
        do
            local hit = groundRay(v, 6)
            if hit and not (UserInput:IsKeyDown(Enum.KeyCode.LeftControl) or mobileHold.D) then
                dir = dir + Vector3.new(0, 0.35, 0)
            end
        end

        -- Zielgeschwindigkeit (klammere extremes Steigen/Fallen)
        local target = Vector3.new()
        if dir.Magnitude > 0 then
            target = dir.Unit * fly.speed
            if target.Y >  fly.climbMax then target = Vector3.new(target.X,  fly.climbMax, target.Z) end
            if target.Y < -fly.climbMax then target = Vector3.new(target.X, -fly.climbMax, target.Z) end
        end

        -- Glättung
        fly.smoothed = fly.smoothed:Lerp(target, math.clamp(fly.accelLerp, 0, 1))

        -- Setzen
        if fly.lv then
            fly.lv.VectorVelocity = fly.smoothed
        end

        -- schwaches NoClip bei Bedarf
        if fly.weakNoClip then applyWeakNoClip(v) end
    end

    -- =================== Toggle ===================
    local function setEnabled(on)
        if on == fly.enabled then return end
        fly.enabled = on

        local v = SV.myVehicleFolder()
        if not v then
            fly.enabled = false
            if fly.uiToggle then fly.uiToggle:Set(false) end
            notify("Car Fly","Kein Fahrzeug.")
            return
        end

        if fly.enabled then
            if not buildControllers(v) then
                fly.enabled = false
                if fly.uiToggle then fly.uiToggle:Set(false) end
                notify("Car Fly","Kein PrimaryPart.")
                return
            end

            -- mini Lift-Off, um Boden-Reibung zu lösen
            pcall(function() v:PivotTo(v:GetPivot() + Vector3.new(0, 2.5, 0)) end)
            fly.smoothed = Vector3.new()

            -- loop starten
            if fly.conn then fly.conn:Disconnect() end
            fly.conn = RunService.RenderStepped:Connect(step)

            -- SafeFly-Thread
            if fly.safeThread then task.cancel(fly.safeThread) end
            fly.safeThread = task.spawn(function()
                while fly.enabled do
                    if not fly.safeFly then task.wait(0.25)
                    else
                        task.wait(6)
                        if not fly.enabled then break end
                        local vv = SV.myVehicleFolder(); if not vv then break end
                        local before = vv:GetPivot()

                        fly.groundLock = true
                        -- kurz „auf Boden drücken“
                        local hit = groundRay(vv, 1000)
                        if hit then
                            pcall(function()
                                vv:PivotTo(CFrame.new(hit.Position + Vector3.new(0, 2.0, 0),
                                                      hit.Position + Vector3.new(0, 2.0, 0) + Camera.CFrame.LookVector))
                            end)
                        end
                        task.wait(0.5)
                        -- exakt zurück
                        pcall(function() vv:PivotTo(before) end)
                        fly.groundLock = false
                    end
                end
            end)

            if fly.uiToggle then fly.uiToggle:Set(true) end
            notify("Car Fly", ("Aktiviert (Speed %d)"):format(fly.speed), 2)
        else
            -- aus: Momentum raus, Controller weg, sanft auf ~15 studs über Boden
            if fly.conn then fly.conn:Disconnect() fly.conn=nil end
            if fly.safeThread then task.cancel(fly.safeThread) fly.safeThread=nil end

            local v2 = SV.myVehicleFolder()
            if v2 then
                -- Fahrt stoppen
                zeroMotion(v2)
                if fly.lv then pcall(function() fly.lv.VectorVelocity = Vector3.new() end) end
                destroyControllers()
                restoreCollision(v2)
                settleToGroundSoft(v2)
            else
                destroyControllers()
            end
            if fly.uiToggle then fly.uiToggle:Set(false) end
            notify("Car Fly","Deaktiviert.", 2)
        end
    end

    local function toggle() setEnabled(not fly.enabled) end

    -- =================== Mobile Panel ===================
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
            b.MouseButton1Down:Connect(function() mobileHold[key] = true end)
            b.MouseButton1Up:Connect(function() mobileHold[key] = false end)
            b.MouseLeave:Connect(function() mobileHold[key] = false end)
            return b
        end

        mkBtn("Toggle", 10, 34, 60, 28, "T").MouseButton1Click:Connect(function() toggle() end)
        mkBtn("^",      85, 34, 60, 28, "F")
        mkBtn("v",      85,100, 60, 28, "B")
        mkBtn("<<",     15, 67, 60, 28, "L")
        mkBtn(">>",     155,67, 60, 28, "R")
        mkBtn("Up",     155,34, 60, 28, "U")
        mkBtn("Down",   155,100,60, 28, "D")

        -- drag
        local dragging, start, startPos
        frame.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 and input.Position.Y - frame.AbsolutePosition.Y <= 28 then
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

    -- =================== UI (nur die gewünschten Controls) ===================
    local sec = tab:AddSection({ Name = "Car Fly" })

    fly.uiToggle = sec:AddToggle({
        Name = "Enable Car Fly (nur im Auto)",
        Default = false,
        Callback = function(v) setEnabled(v) end
    })

    sec:AddToggle({
        Name = "Safe Fly (alle 6s Boden, 0.5s)",
        Default = false,
        Callback = function(v) fly.safeFly = v end
    })

    sec:AddToggle({
        Name = "Mobile Fly Panel",
        Default = false,
        Callback = function(v)
            fly.mobileEnabled = v
            if MobileFlyGui then MobileFlyGui.Enabled = v end
        end
    })

    sec:AddSlider({
        Name = "Speed",
        Min = 10, Max = 190, Increment = 5,
        Default = fly.speed,
        Callback = function(v) fly.speed = math.floor(v) end
    })

    -- Auto-Off wenn aus Sitz -> und beim Rejoin Momentum killen
    RunService.Heartbeat:Connect(function()
        if fly.enabled and not SV.isSeated() then
            setEnabled(false)
        end
    end)
end
