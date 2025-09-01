-- tabs/aimbot.lua
return function(tab, OrionLib)
    -- sanity print to confirm correct version loaded
    print("[SorinHub] aimbot_tab v1.0 loaded")

    --// Services
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local UserInputService = game:GetService("UserInputService")
    local LocalPlayer = Players.LocalPlayer

    --// Optional executor features (guarded)
    local hasDrawing = (typeof(Drawing) == "table" or typeof(Drawing) == "userdata") and typeof(Drawing.new) == "function"
    local canMouseClick = (typeof(mouse1click) == "function") or (typeof(mouse1press) == "function" and typeof(mouse1release) == "function")

    --// Settings
    local aimbotSettings = {
        Enabled       = false,
        Keybind       = Enum.KeyCode.Q,

        Prediction    = true,
        AimPart       = "Head",
        IgnoreTeam    = true,

        FOVVisible    = true,
        FOVRadius     = 100,                 -- pixels
        FOVColor      = Color3.fromRGB(255, 0, 0),

        MaxDistance   = 1000,                -- studs (world distance)
        Smoothness    = 0.5,                 -- 0.1 fast / 1.0 very slow

        WallCheck     = false,
        VisibleCheck  = true,                -- require target point to be on-screen

        Triggerbot    = false,
        TriggerbotKey = Enum.KeyCode.E
    }

    --// FOV circle (only if executor Drawing API exists)
    local FOVCircle = nil
    if hasDrawing then
        FOVCircle = Drawing.new("Circle")
        FOVCircle.Visible = aimbotSettings.FOVVisible
        FOVCircle.Radius = aimbotSettings.FOVRadius
        FOVCircle.Color = aimbotSettings.FOVColor
        FOVCircle.Thickness = 2
        FOVCircle.Filled = false
        FOVCircle.Transparency = 1
    end

    --// State
    local aimbotConn, infoConn
    local targetPlayer = nil
    local isAiming = false

    --// Helpers
    local function updateFOV()
        if not FOVCircle then return end
        local mp = UserInputService:GetMouseLocation()
        FOVCircle.Visible  = aimbotSettings.FOVVisible
        FOVCircle.Color    = aimbotSettings.FOVColor
        FOVCircle.Radius   = aimbotSettings.FOVRadius
        FOVCircle.Position = Vector2.new(mp.X, mp.Y)
    end

    local function isPartVisible(part)
        local cam = workspace.CurrentCamera
        local char = LocalPlayer.Character
        if not (part and cam and char) then return false end
        local head = char:FindFirstChild("Head")
        if not head then return false end

        local origin = head.Position
        local direction = part.Position - origin

        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = { char }
        params.IgnoreWater = true

        local result = workspace:Raycast(origin, direction, params)
        if result then
            -- visible only if the first hit lies within the target character
            return result.Instance:IsDescendantOf(part.Parent)
        end
        -- no obstruction hit; assume clear LOS
        return true
    end

    local function predictPosition(targetPart)
        if not aimbotSettings.Prediction or not targetPart then
            return targetPart and targetPart.Position or nil
        end
        local cam = workspace.CurrentCamera
        if not cam then return targetPart.Position end
        -- adjust projectileSpeed for your weapon if you have one
        local projectileSpeed = 2000
        local distance = (targetPart.Position - cam.CFrame.Position).Magnitude
        local travelTime = distance / projectileSpeed
        return targetPart.Position + (targetPart.Velocity * travelTime)
    end

    local function getClosestPlayer()
        local cam = workspace.CurrentCamera
        local myChar = LocalPlayer.Character
        local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
        if not (cam and myRoot) then return nil end

        local mp = UserInputService:GetMouseLocation()
        local bestPlayer, bestScreenDist = nil, math.huge

        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer then
                local char = plr.Character
                local hum  = char and char:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 then
                    -- team filter
                    if aimbotSettings.IgnoreTeam and plr.Team and LocalPlayer.Team and plr.Team == LocalPlayer.Team then
                        goto continue
                    end

                    -- choose aim part
                    local part = char:FindFirstChild(aimbotSettings.AimPart) or char:FindFirstChild("HumanoidRootPart")
                    if not part then goto continue end

                    -- world distance (studs)
                    local studs = (part.Position - myRoot.Position).Magnitude
                    if studs > aimbotSettings.MaxDistance then
                        goto continue
                    end

                    -- wall/LOS
                    if aimbotSettings.WallCheck and not isPartVisible(part) then
                        goto continue
                    end

                    local sp, onScreen = cam:WorldToViewportPoint(part.Position)
                    if aimbotSettings.VisibleCheck and not onScreen then
                        goto continue
                    end

                    local screenDist = (Vector2.new(mp.X, mp.Y) - Vector2.new(sp.X, sp.Y)).Magnitude
                    if screenDist <= aimbotSettings.FOVRadius and screenDist < bestScreenDist then
                        bestScreenDist = screenDist
                        bestPlayer = plr
                    end
                end
            end
            ::continue::
        end

        return bestPlayer
    end

    local function aimAt(target)
        if not target or not target.Character then return end
        local cam = workspace.CurrentCamera
        if not cam then return end

        local part = target.Character:FindFirstChild(aimbotSettings.AimPart) or target.Character:FindFirstChild("HumanoidRootPart")
        if not part then return end

        local predicted = predictPosition(part) or part.Position
        local from = cam.CFrame.Position
        local desired = (predicted - from).Unit

        local alpha = math.clamp(1 - aimbotSettings.Smoothness, 0, 1) -- 0.1 fast / 1.0 slow
        local newLook = cam.CFrame.LookVector:Lerp(desired, alpha)

        cam.CFrame = CFrame.new(from, from + newLook)
    end

    local function triggerbotTick()
        if not aimbotSettings.Triggerbot then return end
        if not UserInputService:IsKeyDown(aimbotSettings.TriggerbotKey) then return end
        local tgt = getClosestPlayer()
        if not tgt then return end
        if canMouseClick then
            if typeof(mouse1click) == "function" then
                mouse1click()
            elseif typeof(mouse1press) == "function" and typeof(mouse1release) == "function" then
                mouse1press(); task.wait(); mouse1release()
            end
        end
    end

    local function stopLoop()
        if aimbotConn then aimbotConn:Disconnect(); aimbotConn = nil end
        isAiming, targetPlayer = false, nil
    end

    local function startLoop()
        stopLoop()
        if not aimbotSettings.Enabled then return end
        aimbotConn = RunService.RenderStepped:Connect(function()
            updateFOV()

            local cam = workspace.CurrentCamera
            if not cam then return end

            local closest = getClosestPlayer()
            if closest then
                targetPlayer = closest
                aimAt(closest)
                isAiming = true
                triggerbotTick()
            else
                isAiming, targetPlayer = false, nil
            end
        end)
    end

    ----------------------------------------------------------------
    -- UI (Orion: AddToggle / AddBind / AddDropdown / AddSlider / AddColorpicker)
    ----------------------------------------------------------------

    local MainSection = tab:AddSection({ Name = "Aimbot" })

    MainSection:AddToggle({
        Name = "Enable Aimbot",
        Default = aimbotSettings.Enabled,
        Callback = function(v)
            aimbotSettings.Enabled = v
            if v then
                startLoop()
                OrionLib:MakeNotification({ Name = "Aimbot", Content = "Aimbot enabled", Time = 3 })
            else
                stopLoop()
                OrionLib:MakeNotification({ Name = "Aimbot", Content = "Aimbot disabled", Time = 3 })
            end
        end
    })

    MainSection:AddBind({
        Name = "Aimbot Keybind",
        Default = aimbotSettings.Keybind,
        Hold = false,
        Callback = function()
            aimbotSettings.Enabled = not aimbotSettings.Enabled
            if aimbotSettings.Enabled then
                startLoop()
                OrionLib:MakeNotification({ Name = "Aimbot", Content = "Aimbot enabled (keybind)", Time = 3 })
            else
                stopLoop()
                OrionLib:MakeNotification({ Name = "Aimbot", Content = "Aimbot disabled (keybind)", Time = 3 })
            end
        end
    })

    MainSection:AddToggle({
        Name = "Hit Prediction",
        Default = aimbotSettings.Prediction,
        Callback = function(v) aimbotSettings.Prediction = v end
    })

    MainSection:AddDropdown({
        Name = "Aim Part",
        Default = aimbotSettings.AimPart,
        Options = { "Head", "HumanoidRootPart", "UpperTorso", "LowerTorso" },
        Callback = function(v) aimbotSettings.AimPart = v end
    })

    MainSection:AddToggle({
        Name = "Ignore Team",
        Default = aimbotSettings.IgnoreTeam,
        Callback = function(v) aimbotSettings.IgnoreTeam = v end
    })

    local FOVSection = tab:AddSection({ Name = "FOV Settings" })

    FOVSection:AddToggle({
        Name = "Show FOV",
        Default = aimbotSettings.FOVVisible,
        Callback = function(v)
            aimbotSettings.FOVVisible = v
            if FOVCircle then FOVCircle.Visible = v end
        end
    })

    FOVSection:AddColorpicker({
        Name = "FOV Color",
        Default = aimbotSettings.FOVColor,
        Callback = function(v)
            aimbotSettings.FOVColor = v
            if FOVCircle then FOVCircle.Color = v end
        end
    })

    FOVSection:AddSlider({
        Name = "FOV Size",
        Min = 10, Max = 300, Increment = 5,
        Default = aimbotSettings.FOVRadius,
        Callback = function(v)
            aimbotSettings.FOVRadius = v
            if FOVCircle then FOVCircle.Radius = v end
        end
    })

    FOVSection:AddSlider({
        Name = "Smoothness",
        Min = 0.1, Max = 1, Increment = 0.05,
        Default = aimbotSettings.Smoothness,
        Callback = function(v) aimbotSettings.Smoothness = v end
    })

    local DistSection = tab:AddSection({ Name = "Distance / Checks" })

    DistSection:AddSlider({
        Name = "Max Distance",
        Min = 100, Max = 5000, Increment = 50,
        Default = aimbotSettings.MaxDistance,
        ValueName = "Studs",
        Callback = function(v) aimbotSettings.MaxDistance = v end
    })

    DistSection:AddToggle({
        Name = "Wall Check (raycast)",
        Default = aimbotSettings.WallCheck,
        Callback = function(v) aimbotSettings.WallCheck = v end
    })

    DistSection:AddToggle({
        Name = "Require On-Screen",
        Default = aimbotSettings.VisibleCheck,
        Callback = function(v) aimbotSettings.VisibleCheck = v end
    })

    local TrigSection = tab:AddSection({ Name = "Triggerbot" })

    TrigSection:AddToggle({
        Name = "Enable Triggerbot (hold key)",
        Default = aimbotSettings.Triggerbot,
        Callback = function(v) aimbotSettings.Triggerbot = v end
    })

    TrigSection:AddBind({
        Name = "Triggerbot Key",
        Default = aimbotSettings.TriggerbotKey,
        Hold = true,
        Callback = function(_) end -- we poll IsKeyDown each frame
    })

    -- Status UI
    local InfoSection = tab:AddSection({ Name = "Status" })
    local StatusLabel   = InfoSection:AddLabel("Status: Inactive")
    local TargetLabel   = InfoSection:AddLabel("Target: None")
    local DistanceLabel = InfoSection:AddLabel("Distance: -")

    if infoConn then infoConn:Disconnect() end
    infoConn = RunService.Heartbeat:Connect(function()
        if aimbotSettings.Enabled and isAiming and targetPlayer then
            StatusLabel:Set("Status: Active (Target Locked)")
            TargetLabel:Set("Target: " .. targetPlayer.Name)

            local myChar = LocalPlayer.Character
            local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
            local tRoot  = targetPlayer.Character and targetPlayer.Character:FindFirstChild("HumanoidRootPart")
            if myRoot and tRoot then
                local d = (tRoot.Position - myRoot.Position).Magnitude
                DistanceLabel:Set(("Distance: %d Studs"):format(math.floor(d)))
            end
        else
            StatusLabel:Set(aimbotSettings.Enabled and "Status: Active (No Target)" or "Status: Inactive")
            TargetLabel:Set("Target: None")
            DistanceLabel:Set("Distance: -")
        end
    end)

    -- Maintenance
    local CleanupSection = tab:AddSection({ Name = "Maintenance" })
    CleanupSection:AddButton({
        Name = "Stop Aimbot & Cleanup",
        Callback = function()
            stopLoop()
            if infoConn then infoConn:Disconnect(); infoConn = nil end
            if FOVCircle and FOVCircle.Remove then FOVCircle:Remove(); FOVCircle = nil end
            OrionLib:MakeNotification({ Name = "Aimbot", Content = "Stopped & cleaned up.", Time = 3 })
        end
    })
end
