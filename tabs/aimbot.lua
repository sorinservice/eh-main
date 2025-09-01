-- tabs/aimbot.lua
return function(tab, OrionLib)
    print("[SorinHub] Aimbot tab initialized")

    ----------------------------------------------------------------
    -- Services & State
    ----------------------------------------------------------------
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local UserInputService = game:GetService("UserInputService")
    local CoreGui = game:GetService("CoreGui")
    local LocalPlayer = Players.LocalPlayer

    -- Settings (ein einziges Objekt – UI steuert diese Werte)
    local aimbotSettings = {
        Enabled       = false,
        Keybind       = Enum.KeyCode.Q,

        Prediction    = true,
        AimPart       = "Head",
        IgnoreTeam    = true,

        FOVVisible    = true,
        FOVRadius     = 100,                 -- Pixel
        FOVColor      = Color3.fromRGB(255, 0, 0),

        MaxDistance   = 1000,                -- Studs
        Smoothness    = 0.25,                -- 0.1 schnell, 1.0 sehr weich

        WallCheck     = false,
        VisibleCheck  = true                 -- Zielteil muss on-screen sein
    }

    -- Laufzeit-Variablen
    local aimbotConn, infoConn
    local targetPlayer, isAiming = nil, false

    ----------------------------------------------------------------
    -- FOV Overlay (GUI, executor-frei)
    ----------------------------------------------------------------
    local FOVGui, FOVCircle
    local function ensureFOVGui()
        if FOVGui then return end
        FOVGui = Instance.new("ScreenGui")
        FOVGui.Name = "Sorin_FOV"
        FOVGui.ResetOnSpawn = false
        FOVGui.IgnoreGuiInset = true
        FOVGui.Parent = CoreGui

        local circle = Instance.new("Frame")
        circle.Name = "FOV"
        circle.Size = UDim2.fromOffset(aimbotSettings.FOVRadius * 2, aimbotSettings.FOVRadius * 2)
        circle.BackgroundTransparency = 1
        circle.BorderSizePixel = 0
        circle.Parent = FOVGui

        local uic = Instance.new("UICorner")
        uic.CornerRadius = UDim.new(1, 0)
        uic.Parent = circle

        local stroke = Instance.new("UIStroke")
        stroke.Thickness = 2
        stroke.Color = aimbotSettings.FOVColor
        stroke.Parent = circle

        FOVCircle = circle
    end

    local function updateFOVGui()
        if not aimbotSettings.FOVVisible then
            if FOVGui then FOVGui.Enabled = false end
            return
        end
        ensureFOVGui()
        FOVGui.Enabled = true

        local mouse = UserInputService:GetMouseLocation()
        FOVCircle.Position = UDim2.fromOffset(mouse.X - aimbotSettings.FOVRadius, mouse.Y - aimbotSettings.FOVRadius)
        FOVCircle.Size = UDim2.fromOffset(aimbotSettings.FOVRadius * 2, aimbotSettings.FOVRadius * 2)

        local stroke = FOVCircle:FindFirstChildOfClass("UIStroke")
        if stroke then stroke.Color = aimbotSettings.FOVColor end
    end

    ----------------------------------------------------------------
    -- Core-Logik
    ----------------------------------------------------------------
    local function isPartVisible(part)
        local cam = workspace.CurrentCamera
        local char = LocalPlayer.Character
        if not (part and cam and char) then return false end
        local head = char:FindFirstChild("Head")
        if not head then return false end

        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = { char }
        params.IgnoreWater = true

        local dir = part.Position - head.Position
        local res = workspace:Raycast(head.Position, dir, params)
        if res then
            return res.Instance:IsDescendantOf(part.Parent)
        end
        return true
    end

    local function predictPosition(part)
        if not aimbotSettings.Prediction or not part then
            return part and part.Position or nil
        end
        local cam = workspace.CurrentCamera
        if not cam then return part.Position end

        local projectileSpeed = 2000 -- ggf. an deine Waffe anpassen
        local distance = (part.Position - cam.CFrame.Position).Magnitude
        local travelTime = distance / projectileSpeed
        return part.Position + part.Velocity * travelTime
    end

    local function getClosestPlayer()
        local cam = workspace.CurrentCamera
        local me = LocalPlayer.Character
        local myRoot = me and me:FindFirstChild("HumanoidRootPart")
        if not (cam and myRoot) then return nil end

        local mouse = UserInputService:GetMouseLocation()
        local bestPlr, bestScreen = nil, math.huge

        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer then
                local ch = plr.Character
                local hum = ch and ch:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 then
                    if aimbotSettings.IgnoreTeam and plr.Team and LocalPlayer.Team and plr.Team == LocalPlayer.Team then
                        goto continue
                    end

                    local part = ch:FindFirstChild(aimbotSettings.AimPart) or ch:FindFirstChild("HumanoidRootPart")
                    if not part then goto continue end

                    local studs = (part.Position - myRoot.Position).Magnitude
                    if studs > aimbotSettings.MaxDistance then goto continue end

                    if aimbotSettings.WallCheck and not isPartVisible(part) then
                        goto continue
                    end

                    local sp, onScreen = cam:WorldToViewportPoint(part.Position)
                    if aimbotSettings.VisibleCheck and not onScreen then
                        goto continue
                    end

                    local d = (Vector2.new(mouse.X, mouse.Y) - Vector2.new(sp.X, sp.Y)).Magnitude
                    if d <= aimbotSettings.FOVRadius and d < bestScreen then
                        bestScreen = d
                        bestPlr = plr
                    end
                end
            end
            ::continue::
        end

        return bestPlr
    end

    local function aimAt(plr)
        local cam = workspace.CurrentCamera
        if not (plr and cam) then return end

        local ch = plr.Character
        local part = ch and (ch:FindFirstChild(aimbotSettings.AimPart) or ch:FindFirstChild("HumanoidRootPart"))
        if not part then return end

        local from = cam.CFrame.Position
        local target = predictPosition(part) or part.Position
        local desired = (target - from).Unit

        local alpha = math.clamp(1 - aimbotSettings.Smoothness, 0, 1) -- 0.1 schneller / 1.0 weicher
        local newLook = cam.CFrame.LookVector:Lerp(desired, alpha)
        cam.CFrame = CFrame.new(from, from + newLook)
    end

    local function startAimbot()
        if aimbotConn then aimbotConn:Disconnect() end
        aimbotConn = RunService.RenderStepped:Connect(function()
            updateFOVGui()

            local cam = workspace.CurrentCamera
            if not cam then return end

            local closest = getClosestPlayer()
            if closest then
                targetPlayer = closest
                isAiming = true
                aimAt(closest)
            else
                targetPlayer = nil
                isAiming = false
            end
        end)
    end

    local function stopAimbot()
        if aimbotConn then aimbotConn:Disconnect(); aimbotConn = nil end
        isAiming, targetPlayer = false, nil
        if FOVGui then FOVGui.Enabled = false end
    end

    ----------------------------------------------------------------
    -- UI (Orion)
    ----------------------------------------------------------------
    local main = tab:AddSection({ Name = "Aimbot" })

    main:AddToggle({
        Name = "Enable Aimbot",
        Default = aimbotSettings.Enabled,
        Callback = function(v)
            aimbotSettings.Enabled = v
            if v then
                startAimbot()
                OrionLib:MakeNotification({ Name = "Aimbot", Content = "Enabled", Time = 2 })
            else
                stopAimbot()
                OrionLib:MakeNotification({ Name = "Aimbot", Content = "Disabled", Time = 2 })
            end
        end
    })

    main:AddBind({
        Name = "Aimbot Keybind",
        Default = aimbotSettings.Keybind,
        Hold = false,
        Callback = function()
            aimbotSettings.Enabled = not aimbotSettings.Enabled
            if aimbotSettings.Enabled then
                startAimbot()
                OrionLib:MakeNotification({ Name = "Aimbot", Content = "Enabled (keybind)", Time = 2 })
            else
                stopAimbot()
                OrionLib:MakeNotification({ Name = "Aimbot", Content = "Disabled (keybind)", Time = 2 })
            end
        end
    })

    main:AddToggle({
        Name = "Hit Prediction",
        Default = aimbotSettings.Prediction,
        Callback = function(v) aimbotSettings.Prediction = v end
    })

    main:AddDropdown({
        Name = "Aim Part",
        Default = aimbotSettings.AimPart,
        Options = { "Head", "HumanoidRootPart", "UpperTorso", "LowerTorso" },
        Callback = function(v) aimbotSettings.AimPart = v end
    })

    main:AddToggle({
        Name = "Ignore Team",
        Default = aimbotSettings.IgnoreTeam,
        Callback = function(v) aimbotSettings.IgnoreTeam = v end
    })

    local fov = tab:AddSection({ Name = "FOV" })

    fov:AddToggle({
        Name = "Show FOV",
        Default = aimbotSettings.FOVVisible,
        Callback = function(v) aimbotSettings.FOVVisible = v; updateFOVGui() end
    })

    fov:AddColorpicker({
        Name = "FOV Color",
        Default = aimbotSettings.FOVColor,
        Callback = function(c) aimbotSettings.FOVColor = c; updateFOVGui() end
    })

    fov:AddSlider({
        Name = "FOV Size",
        Min = 10, Max = 300, Increment = 5,
        Default = aimbotSettings.FOVRadius,
        Callback = function(v) aimbotSettings.FOVRadius = v; updateFOVGui() end
    })

    local dist = tab:AddSection({ Name = "Distance / Checks" })

    dist:AddSlider({
        Name = "Max Distance",
        Min = 100, Max = 5000, Increment = 50,
        Default = aimbotSettings.MaxDistance,
        ValueName = "Studs",
        Callback = function(v) aimbotSettings.MaxDistance = v end
    })

    dist:AddSlider({
        Name = "Smoothness",
        Min = 0.1, Max = 1, Increment = 0.05,
        Default = aimbotSettings.Smoothness,
        Callback = function(v) aimbotSettings.Smoothness = v end
    })

    dist:AddToggle({
        Name = "Wall Check (raycast)",
        Default = aimbotSettings.WallCheck,
        Callback = function(v) aimbotSettings.WallCheck = v end
    })

    dist:AddToggle({
        Name = "Require On-Screen",
        Default = aimbotSettings.VisibleCheck,
        Callback = function(v) aimbotSettings.VisibleCheck = v end
    })

    -- Status
    local status = tab:AddSection({ Name = "Status" })
    local lblStatus   = status:AddLabel("Status: Inactive")
    local lblTarget   = status:AddLabel("Target: None")
    local lblDistance = status:AddLabel("Distance: -")

    if infoConn then infoConn:Disconnect() end
    infoConn = RunService.Heartbeat:Connect(function()
        if aimbotSettings.Enabled and isAiming and targetPlayer then
            lblStatus:Set("Status: Active (Target Locked)")
            lblTarget:Set("Target: " .. targetPlayer.Name)

            local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            local tRoot  = targetPlayer.Character and targetPlayer.Character:FindFirstChild("HumanoidRootPart")
            if myRoot and tRoot then
                local d = (tRoot.Position - myRoot.Position).Magnitude
                lblDistance:Set(("Distance: %d Studs"):format(math.floor(d)))
            end
        else
            lblStatus:Set(aimbotSettings.Enabled and "Status: Active (No Target)" or "Status: Inactive")
            lblTarget:Set("Target: None")
            lblDistance:Set("Distance: -")
        end
    end)

    -- Maintenance
    local maintenance = tab:AddSection({ Name = "Maintenance" })
    maintenance:AddButton({
        Name = "Stop & Cleanup",
        Callback = function()
            stopAimbot()
            if infoConn then infoConn:Disconnect(); infoConn = nil end
            if FOVGui then FOVGui:Destroy(); FOVGui = nil; FOVCircle = nil end
            OrionLib:MakeNotification({ Name = "Aimbot", Content = "Stopped & cleaned up.", Time = 2 })
        end
    })
end
