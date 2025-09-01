-- tabs/aimbot.lua
return function(tab, OrionLib)
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
        FOVRadius = 80
    }
    
    -- Services
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local UserInputService = game:GetService("UserInputService")
    local LocalPlayer = Players.LocalPlayer
    
    -- FOV Circle
    local FOVCircle = Drawing.new("Circle")
    FOVCircle.Visible = aimbotSettings.FOVVisible
    FOVCircle.Radius = aimbotSettings.FOVRadius
    FOVCircle.Color = aimbotSettings.FOVColor
    FOVCircle.Thickness = 2
    FOVCircle.Filled = false
    
    -- Hilfsfunktionen
    local function UpdateFOV()
        FOVCircle.Visible = aimbotSettings.FOVVisible
        FOVCircle.Color = aimbotSettings.FOVColor
        FOVCircle.Radius = aimbotSettings.FOVRadius
        FOVCircle.Position = Vector2.new(UserInputService:GetMouseLocation().X, UserInputService:GetMouseLocation().Y)
    end
    
    local function GetClosestPlayer()
        local closestPlayer = nil
        local closestDistance = aimbotSettings.MaxDistance
        
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
                end
                
                if aimPart then
                    local screenPoint, visible = workspace.CurrentCamera:WorldToViewportPoint(aimPart.Position)
                    local distance = (LocalPlayer.Character.Head.Position - aimPart.Position).Magnitude
                    
                    if visible and distance <= closestDistance then
                        closestPlayer = player
                        closestDistance = distance
                    end
                end
            end
        end
        
        return closestPlayer
    end
    
    local function PredictPosition(targetPart)
        if not aimbotSettings.Prediction then
            return targetPart.Position
        end
        
        -- Einfache Vorhersage
        local targetVelocity = targetPart.Velocity
        local distance = (targetPart.Position - LocalPlayer.Character.Head.Position).Magnitude
        local travelTime = distance / 1000
        
        return targetPart.Position + (targetVelocity * travelTime)
    end
    
    local function AimAt(target)
        if not target or not target.Character then return end
        
        local targetPart = target.Character:FindFirstChild(aimbotSettings.AimPart)
        if not targetPart then
            targetPart = target.Character:FindFirstChild("HumanoidRootPart")
            if not targetPart then return end
        end
        
        local predictedPosition = PredictPosition(targetPart)
        local camera = workspace.CurrentCamera
        
        if camera and camera.CFrame then
            local currentLook = camera.CFrame.LookVector
            local targetLook = (predictedPosition - camera.CFrame.Position).Unit
            
            -- Smoothing anwenden
            local smoothedLook = currentLook:Lerp(targetLook, 1 - aimbotSettings.Smoothness)
            camera.CFrame = CFrame.new(camera.CFrame.Position, camera.CFrame.Position + smoothedLook)
        end
    end
    
    -- Aimbot Loop
    local AimbotConnection
    local function ToggleAimbot()
        if AimbotConnection then
            AimbotConnection:Disconnect()
            AimbotConnection = nil
        end
        
        if aimbotSettings.Enabled then
            AimbotConnection = RunService.RenderStepped:Connect(function()
                UpdateFOV()
                
                if aimbotSettings.Enabled then
                    local closestPlayer = GetClosestPlayer()
                    if closestPlayer then
                        AimAt(closestPlayer)
                    end
                end
            end)
        end
    end
    
    -- Keybind Handler
    local KeybindConnection
    local function SetupKeybind()
        if KeybindConnection then
            KeybindConnection:Disconnect()
        end
        
        KeybindConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
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
    tab:AddToggle({
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
    
    tab:AddToggle({
        Name = "Aimbot aktivieren",
        Default = aimbotSettings.Enabled,
        Callback = function(value)
            aimbotSettings.Enabled = value
            ToggleAimbot()
            OrionLib:MakeNotification({
                Name = "Aimbot",
                Content = "Aimbot " .. (value and "aktiviert" or "deaktiviert"),
                Time = 3
            })
        end
    })
    
    tab:AddKeybind({
        Name = "Aimbot Keybind",
        Default = aimbotSettings.Keybind,
        Callback = function(key)
            aimbotSettings.Keybind = key
            SetupKeybind()
        end
    })
    
    tab:AddToggle({
        Name = "Hit Prediction",
        Default = aimbotSettings.Prediction,
        Callback = function(value)
            aimbotSettings.Prediction = value
        end
    })
    
    tab:AddDropdown({
        Name = "Aim Part",
        Default = aimbotSettings.AimPart,
        Options = {"Head", "HumanoidRootPart", "UpperTorso"},
        Callback = function(value)
            aimbotSettings.AimPart = value
        end
    })
    
    tab:AddToggle({
        Name = "Ignore Team",
        Default = aimbotSettings.IgnoreTeam,
        Callback = function(value)
            aimbotSettings.IgnoreTeam = value
        end
    })
    
    tab:AddColorpicker({
        Name = "FOV Color",
        Default = aimbotSettings.FOVColor,
        Callback = function(value)
            aimbotSettings.FOVColor = value
        end
    })
    
    tab:AddSlider({
        Name = "Max Distance",
        Min = 10,
        Max = 1000,
        Default = aimbotSettings.MaxDistance,
        Color = Color3.fromRGB(255, 0, 0),
        Increment = 10,
        Callback = function(value)
            aimbotSettings.MaxDistance = value
        end
    })
    
    tab:AddSlider({
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
    
    tab:AddSlider({
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
    
    tab:AddToggle({
        Name = "FOV Sichtbar",
        Default = aimbotSettings.FOVVisible,
        Callback = function(value)
            aimbotSettings.FOVVisible = value
        end
    })
    
    -- Initialisierung
    SetupKeybind()
    UpdateFOV()
    
    -- Cleanup
    tab:OnClose(function()
        if AimbotConnection then
            AimbotConnection:Disconnect()
        end
        if KeybindConnection then
            KeybindConnection:Disconnect()
        end
        if FOVCircle then
            FOVCircle:Remove()
        end
    end)
end
