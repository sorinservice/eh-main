-- tabs/aimbot.lua
return function(tab, OrionLib)
    print("Aimbot v0.2")
    -- Services
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local UserInputService = game:GetService("UserInputService")
    local TweenService = game:GetService("TweenService")
    local LocalPlayer = Players.LocalPlayer
    local Camera = workspace.CurrentCamera
    
    -- Aimbot Einstellungen
    local aimbotSettings = {
        Enabled = false,
        MobileEnabled = false,
        Keybind = Enum.KeyCode.Q,
        Prediction = true,
        AimPart = "Head",
        IgnoreTeam = true,
        FOVColor = Color3.fromRGB(255, 0, 0),
        MaxDistance = 500,
        Smoothness = 0.5,
        FOVVisible = true,
        FOVRadius = 80,
        WallCheck = false,
        VisibleCheck = true
    }
    
    -- FOV Circle
    local FOVCircle = Drawing.new("Circle")
    FOVCircle.Visible = aimbotSettings.FOVVisible
    FOVCircle.Radius = aimbotSettings.FOVRadius
    FOVCircle.Color = aimbotSettings.FOVColor
    FOVCircle.Thickness = 2
    FOVCircle.Filled = false
    FOVCircle.Transparency = 1
    
    -- Variablen
    local aimbotConnection
    local keybindConnection
    local targetPlayer = nil
    local isAiming = false
    
    -- Hilfsfunktionen
    local function UpdateFOV()
        local mousePos = UserInputService:GetMouseLocation()
        FOVCircle.Visible = aimbotSettings.FOVVisible
        FOVCircle.Color = aimbotSettings.FOVColor
        FOVCircle.Radius = aimbotSettings.FOVRadius
        FOVCircle.Position = Vector2.new(mousePos.X, mousePos.Y)
    end
    
    local function IsPartVisible(part, ignoreList)
        if not part then return false end
        
        local character = LocalPlayer.Character
        if not character then return false end
        
        local head = character:FindFirstChild("Head")
        if not head then return false end
        
        local origin = head.Position
        local direction = (part.Position - origin).Unit * (origin - part.Position).Magnitude
        
        local raycastParams = RaycastParams.new()
        raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
        raycastParams.FilterDescendantsInstances = ignoreList or {LocalPlayer.Character, Camera}
        raycastParams.IgnoreWater = true
        
        local raycastResult = workspace:Raycast(origin, direction, raycastParams)
        
        if raycastResult then
            return raycastResult.Instance:IsDescendantOf(part.Parent)
        end
        
        return true
    end
    
    local function GetClosestPlayer()
        local closestPlayer = nil
        local closestDistance = aimbotSettings.MaxDistance
        local closestScreenPosition = nil
        local mousePos = UserInputService:GetMouseLocation()
        
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and player.Character and player.Character:FindFirstChild("Humanoid") and player.Character.Humanoid.Health > 0 then
                -- Team Check
                if aimbotSettings.IgnoreTeam and player.Team and LocalPlayer.Team and player.Team == LocalPlayer.Team then
                    continue
                end
                
                local character = player.Character
                local aimPart = character:FindFirstChild(aimbotSettings.AimPart)
                if not aimPart then
                    aimPart = character:FindFirstChild("HumanoidRootPart")
                    if not aimPart then
                        continue
                    end
                end
                
                -- Wall Check
                if aimbotSettings.WallCheck and not IsPartVisible(aimPart) then
                    continue
                end
                
                -- FOV Check
                local screenPoint, visible = Camera:WorldToViewportPoint(aimPart.Position)
                if visible then
                    local distance = (Vector2.new(mousePos.X, mousePos.Y) - Vector2.new(screenPoint.X, screenPoint.Y)).Magnitude
                    
                    if distance <= aimbotSettings.FOVRadius and distance <= closestDistance then
                        closestPlayer = player
                        closestDistance = distance
                        closestScreenPosition = screenPoint
                    end
                end
            end
        end
        
        return closestPlayer, closestScreenPosition
    end
    
    local function PredictPosition(targetPart)
        if not aimbotSettings.Prediction or not targetPart then
            return targetPart and targetPart.Position or Vector3.new(0, 0, 0)
        end
        
        -- Einfache Vorhersage basierend auf Geschwindigkeit
        local targetVelocity = targetPart.Velocity
        local distance = (targetPart.Position - Camera.CFrame.Position).Magnitude
        local travelTime = distance / 1000 -- Vereinfachte Annahme
        
        return targetPart.Position + (targetVelocity * travelTime)
    end
    
    local function AimAt(target)
        if not target or not target.Character or not Camera then return end
        
        local targetPart = target.Character:FindFirstChild(aimbotSettings.AimPart)
        if not targetPart then
            targetPart = target.Character:FindFirstChild("HumanoidRootPart")
            if not targetPart then return end
        end
        
        local predictedPosition = PredictPosition(targetPart)
        local currentCFrame = Camera.CFrame
        
        if currentCFrame then
            local currentLook = currentCFrame.LookVector
            local targetLook = (predictedPosition - currentCFrame.Position).Unit
            
            -- Smoothing anwenden
            local smoothedLook = currentLook:Lerp(targetLook, 1 - aimbotSettings.Smoothness)
            Camera.CFrame = CFrame.new(currentCFrame.Position, currentCFrame.Position + smoothedLook)
        end
    end
    
    -- Aimbot Loop
    local function ToggleAimbot()
        if aimbotConnection then
            aimbotConnection:Disconnect()
            aimbotConnection = nil
        end
        
        if aimbotSettings.Enabled then
            aimbotConnection = RunService.RenderStepped:Connect(function()
                UpdateFOV()
                
                if aimbotSettings.Enabled then
                    local closestPlayer, screenPosition = GetClosestPlayer()
                    if closestPlayer then
                        targetPlayer = closestPlayer
                        AimAt(targetPlayer)
                        isAiming = true
                    else
                        isAiming = false
                        targetPlayer = nil
                    end
                else
                    isAiming = false
                    targetPlayer = nil
                end
            end)
        end
    end
    
    -- Keybind Handler
    local function SetupKeybind()
        if keybindConnection then
            keybindConnection:Disconnect()
        end
        
        keybindConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
            if gameProcessed then return end
            
            if input.KeyCode == aimbotSettings.Keybind then
                aimbotSettings.Enabled = not aimbotSettings.Enabled
                ToggleAimbot()
                
                OrionLib:MakeNotification({
                    Name = "Aimbot",
                    Content = "Aimbot " .. (aimbotSettings.Enabled and "aktiviert" or "deaktiviert"),
                    Time = 3
                })
            end
        end)
    end
    
    -- UI Elements
    local AimbotSection = tab:AddSection({
        Name = "Aimbot Einstellungen"
    })
    
    local MobileToggle = AimbotSection:AddToggle({
        Name = "Mobile Aimbot",
        Default = aimbotSettings.MobileEnabled,
        Callback = function(value)
            aimbotSettings.MobileEnabled = value
            OrionLib:MakeNotification({
                Name = "Aimbot",
                Content = "Mobile Aimbot " .. (value and "aktiviert" or "deaktiviert"),
                Time = 3
            })
        end
    })
    
    local AimbotToggle = AimbotSection:AddToggle({
        Name = "Aimbot aktivieren",
        Default = aimbotSettings.Enabled,
        Callback = function(value)
            aimbotSettings.Enabled = value
            ToggleAimbot()
            OrionLib:MakeNotification({
                Name = "Aimbot",
                Content = "Aimbot " .. (value and "aktiviert" oder "deaktiviert"),
                Time = 3
            })
        end
    })
    
    local Keybind = AimbotSection:AddKeybind({
        Name = "Aimbot Keybind",
        Default = aimbotSettings.Keybind,
        Callback = function(key)
            aimbotSettings.Keybind = key
            SetupKeybind()
        end
    })
    
    local PredictionToggle = AimbotSection:AddToggle({
        Name = "Hit Prediction",
        Default = aimbotSettings.Prediction,
        Callback = function(value)
            aimbotSettings.Prediction = value
        end
    })
    
    local AimPartDropdown = AimbotSection:AddDropdown({
        Name = "Aim Part",
        Default = aimbotSettings.AimPart,
        Options = {"Head", "HumanoidRootPart", "UpperTorso", "LowerTorso"},
        Callback = function(value)
            aimbotSettings.AimPart = value
        end
    })
    
    local IgnoreTeamToggle = AimbotSection:AddToggle({
        Name = "Ignore Team",
        Default = aimbotSettings.IgnoreTeam,
        Callback = function(value)
            aimbotSettings.IgnoreTeam = value
        end
    })
    
    local WallCheckToggle = AimbotSection:AddToggle({
        Name = "Wall Check",
        Default = aimbotSettings.WallCheck,
        Callback = function(value)
            aimbotSettings.WallCheck = value
        end
    })
    
    local VisibleCheckToggle = AimbotSection:AddToggle({
        Name = "Visible Check",
        Default = aimbotSettings.VisibleCheck,
        Callback = function(value)
            aimbotSettings.VisibleCheck = value
        end
    })
    
    local FOVSection = tab:AddSection({
        Name = "FOV Einstellungen"
    })
    
    local FOVColor = FOVSection:AddColorpicker({
        Name = "FOV Color",
        Default = aimbotSettings.FOVColor,
        Callback = function(value)
            aimbotSettings.FOVColor = value
        end
    })
    
    local MaxDistanceSlider = FOVSection:AddSlider({
        Name = "Max Distance",
        Min = 10,
        Max = 1000,
        Default = aimbotSettings.MaxDistance,
        Color = Color3.fromRGB(255, 0, 0),
        Increment = 10,
        ValueName = "Studs",
        Callback = function(value)
            aimbotSettings.MaxDistance = value
        end
    })
    
    local SmoothnessSlider = FOVSection:AddSlider({
        Name = "Smoothness",
        Min = 0.1,
        Max = 1,
        Default = aimbotSettings.Smoothness,
        Color = Color3.fromRGB(0, 255, 0),
        Increment = 0.05,
        Callback = function(value)
            aimbotSettings.Smoothness = value
        end
    })
    
    local FOVRadiusSlider = FOVSection:AddSlider({
        Name = "FOV Radius",
        Min = 10,
        Max = 200,
        Default = aimbotSettings.FOVRadius,
        Color = Color3.fromRGB(0, 0, 255),
        Increment = 5,
        Callback = function(value)
            aimbotSettings.FOVRadius = value
        end
    })
    
    local FOVVisibleToggle = FOVSection:AddToggle({
        Name = "FOV Sichtbar",
        Default = aimbotSettings.FOVVisible,
        Callback = function(value)
            aimbotSettings.FOVVisible = value
        end
    })
    
    -- Info Section
    local InfoSection = tab:AddSection({
        Name = "Aimbot Info"
    })
    
    local StatusLabel = InfoSection:AddLabel("Status: Deaktiviert")
    local TargetLabel = InfoSection:AddLabel("Ziel: Kein Ziel")
    local DistanceLabel = InfoSection:AddLabel("Distanz: -")
    
    -- Update Info Labels
    local function UpdateInfoLabels()
        if aimbotSettings.Enabled and isAiming and targetPlayer then
            StatusLabel:Set("Status: Aktiviert (Ziel erkannt)")
            TargetLabel:Set("Ziel: " .. targetPlayer.Name)
            
            if targetPlayer.Character and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
                local rootPart = targetPlayer.Character:FindFirstChild("HumanoidRootPart")
                local localRoot = LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                
                if rootPart and localRoot then
                    local distance = (rootPart.Position - localRoot.Position).Magnitude
                    DistanceLabel:Set("Distanz: " .. math.floor(distance) .. " Studs")
                end
            end
        else
            StatusLabel:Set("Status: " .. (aimbotSettings.Enabled and "Aktiviert (Kein Ziel)" or "Deaktiviert"))
            TargetLabel:Set("Ziel: Kein Ziel")
            DistanceLabel:Set("Distanz: -")
        end
    end
    
    -- Info Update Loop
    local infoConnection
    infoConnection = RunService.Heartbeat:Connect(function()
        UpdateInfoLabels()
    end)
    
    -- Initialisierung
    SetupKeybind()
    UpdateFOV()
    
    -- Cleanup
    tab:OnClose(function()
        if aimbotConnection then
            aimbotConnection:Disconnect()
        end
        if keybindConnection then
            keybindConnection:Disconnect()
        end
        if infoConnection then
            infoConnection:Disconnect()
        end
        if FOVCircle then
            FOVCircle:Remove()
        end
    end)
end
