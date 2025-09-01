-- tabs/aimbot.lua
return function(tab, OrionLib)
    -- Aimbot Variablen
    local aimbot = {
        enabled = false,
        mobileEnabled = false,
        keybind = Enum.KeyCode.Q,
        hitPrediction = true,
        aimPart = "Head",
        ignoreTeam = true,
        fovColor = Color3.fromRGB(255, 0, 0),
        maxDistance = 500,
        smoothness = 0.5,
        fovVisible = true,
        fovRadius = 80
    }
    
    -- Services
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local UserInputService = game:GetService("UserInputService")
    local LocalPlayer = Players.LocalPlayer
    
    -- Hilfsfunktionen
    local function getClosestPlayer()
        local closestPlayer = nil
        local closestDistance = aimbot.maxDistance
        
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and player.Character and player.Character:FindFirstChild("Humanoid") and player.Character.Humanoid.Health > 0 then
                -- Team-Check
                if aimbot.ignoreTeam and player.Team and LocalPlayer.Team and player.Team == LocalPlayer.Team then
                    continue
                end
                
                local character = player.Character
                local aimPart = character:FindFirstChild(aimbot.aimPart)
                if not aimPart then
                    aimPart = character:FindFirstChild("HumanoidRootPart")
                end
                
                if aimPart then
                    local distance = (LocalPlayer.Character.Head.Position - aimPart.Position).Magnitude
                    if distance <= closestDistance then
                        closestPlayer = player
                        closestDistance = distance
                    end
                end
            end
        end
        
        return closestPlayer
    end
    
    local function predictPosition(targetPart)
        if not aimbot.hitPrediction then
            return targetPart.Position
        end
        
        -- Einfache Vorhersage basierend auf Geschwindigkeit
        local targetVelocity = targetPart.Velocity
        local distance = (targetPart.Position - LocalPlayer.Character.Head.Position).Magnitude
        local travelTime = distance / 1000 -- Vereinfachte Annahme
        
        return targetPart.Position + (targetVelocity * travelTime)
    end
    
    local function aimAt(target)
        if not target or not target.Character then return end
        
        local targetPart = target.Character:FindFirstChild(aimbot.aimPart)
        if not targetPart then
            targetPart = target.Character:FindFirstChild("HumanoidRootPart")
            if not targetPart then return end
        end
        
        local predictedPosition = predictPosition(targetPart)
        local camera = workspace.CurrentCamera
        
        if camera and camera.CFrame then
            local currentLook = camera.CFrame.LookVector
            local targetLook = (predictedPosition - camera.CFrame.Position).Unit
            
            -- Smoothing anwenden
            local smoothedLook = currentLook:Lerp(targetLook, 1 - aimbot.smoothness)
            camera.CFrame = CFrame.new(camera.CFrame.Position, camera.CFrame.Position + smoothedLook)
        end
    end
    
    -- FOV Circle Zeichnen
    local fovCircle = Drawing.new("Circle")
    fovCircle.Visible = aimbot.fovVisible
    fovCircle.Radius = aimbot.fovRadius
    fovCircle.Color = aimbot.fovColor
    fovCircle.Thickness = 2
    fovCircle.Filled = false
    fovCircle.Position = Vector2.new(UserInputService:GetMouseLocation().X, UserInputService:GetMouseLocation().Y)
    
    local function updateFOV()
        fovCircle.Visible = aimbot.fovVisible
        fovCircle.Color = aimbot.fovColor
        fovCircle.Radius = aimbot.fovRadius
        fovCircle.Position = Vector2.new(UserInputService:GetMouseLocation().X, UserInputService:GetMouseLocation().Y)
    end
    
    -- Haupt-Aimbot Loop
    local aimbotConnection
    local function startAimbot()
        if aimbotConnection then
            aimbotConnection:Disconnect()
        end
        
        aimbotConnection = RunService.RenderStepped:Connect(function()
            updateFOV()
            
            if aimbot.enabled then
                local closestPlayer = getClosestPlayer()
                if closestPlayer then
                    aimAt(closestPlayer)
                end
            end
        end)
    end
    
    -- Keybind Handler
    local keybindConnection
    local function setupKeybind()
        if keybindConnection then
            keybindConnection:Disconnect()
        end
        
        keybindConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
            if gameProcessed then return end
            
            if input.KeyCode == aimbot.keybind then
                aimbot.enabled = not aimbot.enabled
                
                OrionLib:MakeNotification({
                    Name = "Aimbot",
                    Content = "Aimbot " .. (aimbot.enabled and "aktiviert" or "deaktiviert"),
                    Time = 3
                })
            end
        end)
    end
    
    -- UI Elemente
    tab:AddToggle({
        Name = "Mobile Aimbot",
        Default = false,
        Callback = function(value)
            aimbot.mobileEnabled = value
            OrionLib:MakeNotification({
                Name = "Aimbot",
                Content = "Mobile Aimbot " .. (value and "aktiviert" or "deaktiviert"),
                Time = 3
            })
        end
    })
    
    tab:AddToggle({
        Name = "Aimbot aktivieren",
        Default = false,
        Callback = function(value)
            aimbot.enabled = value
            OrionLib:MakeNotification({
                Name = "Aimbot",
                Content = "Aimbot " .. (value and "aktiviert" or "deaktiviert"),
                Time = 3
            })
        end
    })
    
    tab:AddKeybind({
        Name = "Aimbot Keybind",
        Default = aimbot.keybind,
        Callback = function(key)
            aimbot.keybind = key
            setupKeybind()
        end
    })
    
    tab:AddToggle({
        Name = "Hit Prediction",
        Default = aimbot.hitPrediction,
        Callback = function(value)
            aimbot.hitPrediction = value
        end
    })
    
    tab:AddDropdown({
        Name = "Aim Part",
        Default = aimbot.aimPart,
        Options = {"Head", "HumanoidRootPart", "UpperTorso"},
        Callback = function(value)
            aimbot.aimPart = value
        end
    })
    
    tab:AddToggle({
        Name = "Ignore Team",
        Default = aimbot.ignoreTeam,
        Callback = function(value)
            aimbot.ignoreTeam = value
        end
    })
    
    tab:AddColorpicker({
        Name = "FOV Color",
        Default = aimbot.fovColor,
        Callback = function(value)
            aimbot.fovColor = value
        end
    })
    
    tab:AddSlider({
        Name = "Max Distance",
        Min = 10,
        Max = 1000,
        Default = aimbot.maxDistance,
        Color = Color3.fromRGB(255, 0, 0),
        Increment = 10,
        Callback = function(value)
            aimbot.maxDistance = value
        end
    })
    
    tab:AddSlider({
        Name = "Smoothness",
        Min = 0.1,
        Max = 1,
        Default = aimbot.smoothness,
        Color = Color3.fromRGB(0, 255, 0),
        Increment = 0.05,
        Callback = function(value)
            aimbot.smoothness = value
        end
    })
    
    tab:AddSlider({
        Name = "FOV Radius",
        Min = 10,
        Max = 200,
        Default = aimbot.fovRadius,
        Color = Color3.fromRGB(0, 0, 255),
        Increment = 5,
        Callback = function(value)
            aimbot.fovRadius = value
        end
    })
    
    tab:AddToggle({
        Name = "FOV Sichtbar",
        Default = aimbot.fovVisible,
        Callback = function(value)
            aimbot.fovVisible = value
        end
    })
    
    -- Initialisiere den Aimbot
    startAimbot()
    setupKeybind()
    
    -- Cleanup wenn der Tab geschlossen wird
    tab:OnClose(function()
        if aimbotConnection then
            aimbotConnection:Disconnect()
        end
        if keybindConnection then
            keybindConnection:Disconnect()
        end
        if fovCircle then
            fovCircle:Remove()
        end
    end)
end
