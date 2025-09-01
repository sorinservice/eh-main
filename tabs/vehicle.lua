----------------------------------------------------------------
-- Car Fly (one source of truth) + SafeFly snap + Mobile hold
----------------------------------------------------------------
local flyEnabled    = false         -- EINZIGE Quelle der Wahrheit
local flySpeed      = 130           -- 10..190
local safeFly       = false
local lastAirCF     = nil           -- letzte echte Flugpose
local flyConn       = nil
local safeTimer     = 0
local savedFlags    = {}            -- [BasePart] = {Anchored, CanCollide}
local uiFlyToggle   = nil           -- Referenz auf Orion-Toggle (für Sync)
local toggleDebounce= 0

-- Mobile-hold States
local mHold = { forward=false, back=false, left=false, right=false, up=false, down=false }

-- kleine Notification-Hilfe
local function notify(title, text, secs)
    pcall(function()
        OrionLib:MakeNotification({ Name=title, Content=text, Time=secs or 3 })
    end)
end

local function forEachPart(vf, fn)
    if not vf then return end
    for _,p in ipairs(vf:GetDescendants()) do
        if p:IsA("BasePart") then fn(p) end
    end
end

local function getVehicleRoot()
    local vf = myVehicleFolder()
    if not vf then return nil end
    ensurePrimaryPart(vf)
    return vf
end

local function setFlightPhysics(vf, on)
    if not vf then return end
    if on then
        savedFlags = {}
        forEachPart(vf, function(bp)
            savedFlags[bp] = {Anchored = bp.Anchored, CanCollide = bp.CanCollide}
            bp.Anchored   = true
            bp.CanCollide = false
        end)
    else
        for bp,flags in pairs(savedFlags) do
            if bp and bp.Parent then
                bp.Anchored   = flags.Anchored
                bp.CanCollide = flags.CanCollide
                -- leicht nach unten “anstupsen”
                local v = bp.AssemblyLinearVelocity
                bp.AssemblyLinearVelocity = Vector3.new(v.X, math.min(v.Y, -3), v.Z)
            end
        end
        savedFlags = {}
    end
end

local function setFlyEnabled(state)
    if state == flyEnabled then
        if uiFlyToggle and uiFlyToggle.Set then pcall(function() uiFlyToggle:Set(flyEnabled) end) end
        return
    end
    flyEnabled = state
    if uiFlyToggle and uiFlyToggle.Set then pcall(function() uiFlyToggle:Set(flyEnabled) end) end

    if flyConn then flyConn:Disconnect(); flyConn=nil end

    local vf = getVehicleRoot()
    if not vf then
        flyEnabled = false
        if uiFlyToggle and uiFlyToggle.Set then pcall(function() uiFlyToggle:Set(false) end) end
        notify("Car Fly", "Kein Fahrzeug gefunden.")
        return
    end

    if not flyEnabled then
        setFlightPhysics(vf, false)
        notify("Car Fly", "Deaktiviert.")
        return
    end

    setFlightPhysics(vf, true)
    lastAirCF = vf:GetPivot()
    safeTimer = 0
    notify("Car Fly", ("Aktiviert (Speed %d)"):format(flySpeed))

    flyConn = RunService.RenderStepped:Connect(function(dt)
        if not flyEnabled then return end
        toggleDebounce = math.max(0, toggleDebounce - dt)

        local vf2 = getVehicleRoot()
        if not vf2 then return end

        local rootCF = vf2:GetPivot()
        lastAirCF = rootCF

        -- Tastatur + Mobile-Hold kombi
        local dir = Vector3.new(0,0,0)
        if UserInput:IsKeyDown(Enum.KeyCode.W) or mHold.forward then dir = dir + Camera.CFrame.LookVector end
        if UserInput:IsKeyDown(Enum.KeyCode.S) or mHold.back    then dir = dir - Camera.CFrame.LookVector end
        if UserInput:IsKeyDown(Enum.KeyCode.D) or mHold.right   then dir = dir + Camera.CFrame.RightVector end
        if UserInput:IsKeyDown(Enum.KeyCode.A) or mHold.left    then dir = dir - Camera.CFrame.RightVector end
        if UserInput:IsKeyDown(Enum.KeyCode.E) or UserInput:IsKeyDown(Enum.KeyCode.Space) or mHold.up then
            dir = dir + Vector3.new(0,1,0)
        end
        if UserInput:IsKeyDown(Enum.KeyCode.Q) or UserInput:IsKeyDown(Enum.KeyCode.LeftControl) or mHold.down then
            dir = dir - Vector3.new(0,1,0)
        end

        if dir.Magnitude > 0 then
            dir = dir.Unit
            local step   = dir * (flySpeed * dt)
            local newPos = rootCF.Position + step
            local lookAt = newPos + Camera.CFrame.LookVector
            local newCF  = CFrame.lookAt(newPos, lookAt)
            pcall(function() vf2:PivotTo(newCF) end)
            lastAirCF = newCF
        end

        -- SafeFly: 0.5s Boden, dann exakt zurück
        if safeFly then
            safeTimer = safeTimer + dt
            if safeTimer >= 6 then
                safeTimer = 0
                local params = RaycastParams.new()
                params.FilterType = Enum.RaycastFilterType.Blacklist
                params.FilterDescendantsInstances = {vf2}
                local from = vf2:GetPivot().Position
                local hit = Workspace:Raycast(from, Vector3.new(0,-1000,0), params)

                setFlightPhysics(vf2, false)
                local groundCF
                if hit then
                    groundCF = CFrame.new(hit.Position + Vector3.new(0, 2, 0),
                                          hit.Position + Camera.CFrame.LookVector)
                else
                    groundCF = CFrame.new(from.X, 4, from.Z)
                end
                pcall(function() vf2:PivotTo(groundCF) end)

                -- falls Spieler nicht sitzt: mitnehmen
                local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
                local hrp = hum and hum.RootPart
                if hrp and (not hum.SeatPart) then
                    pcall(function() hrp.CFrame = groundCF end)
                end

                task.wait(0.5)
                if lastAirCF then pcall(function() vf2:PivotTo(lastAirCF) end) end
                setFlightPhysics(vf2, true)
            end
        end
    end)
end

-- X-Key toggelt EINMAL den gemeinsamen State
UserInput.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.X then
        if toggleDebounce <= 0 then
            toggleDebounce = 0.25
            setFlyEnabled(not flyEnabled)
        end
    end
end)

----------------------------------------------------------------
-- Mobile Fly Panel (Buttons mit Hold)
----------------------------------------------------------------
local function spawnMobileFly()
    local gui = Instance.new("ScreenGui")
    gui.Name = "Sorin_MobileFly"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.Enabled = false
    gui.Parent = game:GetService("CoreGui")

    local frame = Instance.new("Frame")
    frame.Size = UDim2.fromOffset(220, 160)
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

    local function mkBtn(txt, x, y, w, h, onDown, onUp)
        local b = Instance.new("TextButton")
        b.Size = UDim2.fromOffset(w,h)
        b.Position = UDim2.fromOffset(x,y)
        b.Text = txt
        b.BackgroundColor3 = Color3.fromRGB(40,40,40)
        b.TextColor3 = Color3.fromRGB(230,230,230)
        b.Font = Enum.Font.GothamSemibold
        b.TextSize = 14
        b.Parent = frame
        Instance.new("UICorner", b).CornerRadius = UDim.new(0,8)
        b.MouseButton1Down:Connect(function() if onDown then onDown() end end)
        b.MouseButton1Up:Connect(function() if onUp   then onUp()   end end)
        b.MouseLeave:Connect(function() if onUp   then onUp()   end end)
        return b
    end

    mkBtn("Toggle", 10, 34, 60, 28, function() setFlyEnabled(not flyEnabled) end, nil)
    mkBtn("^",   80, 34, 60, 28, function() mHold.forward = true end, function() mHold.forward = false end)
    mkBtn("v",   80, 68, 60, 28, function() mHold.back    = true end, function() mHold.back    = false end)
    mkBtn("<<",  10, 68, 60, 28, function() mHold.left    = true end, function() mHold.left    = false end)
    mkBtn(">>", 150, 68, 60, 28, function() mHold.right   = true end, function() mHold.right   = false end)
    mkBtn("Up",  10, 102,60, 28, function() mHold.up      = true end, function() mHold.up      = false end)
    mkBtn("Down",150,102,60,28, function() mHold.down     = true end, function() mHold.down    = false end)

    -- drag
    local dragging, start, startPos
    frame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            start = input.Position
            startPos = frame.Position
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

----------------------------------------------------------------
-- Orion UI: Toggle/Bind/Speed/SafeFly + Mobile-Panel
----------------------------------------------------------------
local secF  = tab:AddSection({ Name = "Car Fly" })
local secM  = tab:AddSection({ Name = "Mobile Fly" })

uiFlyToggle = secF:AddToggle({
    Name = "Enable Car Fly",
    Default = false,
    Callback = function(v) setFlyEnabled(v) end
})

secF:AddBind({
    Name = "Car Fly Toggle Key",
    Default = Enum.KeyCode.X,
    Hold = false,
    Callback = function()
        setFlyEnabled(not flyEnabled)
    end
})

secF:AddSlider({
    Name = "Fly Speed",
    Min = 10, Max = 190, Increment = 5,
    Default = flySpeed,
    Callback = function(v) flySpeed = math.floor(v) end
})

secF:AddToggle({
    Name = "Safe Fly (alle 6s Boden-Touch & Snapback)",
    Default = false,
    Callback = function(v) safeFly = v end
})

secM:AddToggle({
    Name = "Mobile Fly Panel einblenden",
    Default = false,
    Callback = function(v) if MobileFlyGui then MobileFlyGui.Enabled = v end end
})
