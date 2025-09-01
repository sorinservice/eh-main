-- tabs/aimbot.lua
return function(tab, OrionLib)
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
        Keybind = Enum.KeyCode.Q,
        Prediction = true,
        AimPart = "Head",
        IgnoreTeam = true,
        FOVColor = Color3.fromRGB(255, 0, 0),
        MaxDistance = 1000,
        Smoothness = 0.5,
        FOVVisible = true,
        FOVRadius = 100,
        WallCheck = false,
        VisibleCheck = true,
        Triggerbot = false,
        TriggerbotKey = Enum.KeyCode.E
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
    local triggerbotConnection
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
    
    local function IsPartVisible(part)
        if not part then return false end
        
        local character = LocalPlayer.Character
        if not character then return false end
        
        local head = character:FindFirstChild("Head")
        if not head then return false end
        
        local origin = head.Position
        local direction = (part.Position - origin).Unit * (origin - part.Position).Magnitude
        
        local raycastParams = RaycastParams.new()
        raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
        raycastParams.FilterDescendantsInstances = {LocalPlayer.Character, Camera}
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
                    end
                end
            end
        end
        
        return closestPlayer
    end
    
    local function PredictPosition(targetPart)
        if not aimbotSettings.Prediction or not targetPart then
            return targetPart and targetPart.Position or Vector3.new(0, 0, 0)
        end
        
        -- Vorhersage basierend auf Geschwindigkeit
        local targetVelocity = targetPart.Velocity
        local distance = (targetPart.Position - Camera.CFrame.Position).Magnitude
        local travelTime = distance / 2000 -- Angepasste Vorhersage
        
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
    
    local function Triggerbot()
        if aimbotSettings.Triggerbot and UserInputService:IsKeyDown(aimbotSettings.TriggerbotKey) then
            local target = GetClosestPlayer()
            if target then
                -- Simuliere Mausklick für automatisches Schießen
                mouse1click()
            end
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
                    local closestPlayer = GetClosestPlayer()
                    if closestPlayer then
                        targetPlayer = closestPlayer
                        AimAt(targetPlayer)
                        isAiming = true
                        Triggerbot()
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
    local function SetupKeybinds()
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
    
    -- UI Elements (Vortex Style)
    local MainSection = tab:AddSection({
        Name = "Aimbot"
    })
    
    local AimbotToggle = MainSection:AddToggle({
        Name = "Enable Aimbot",
        Default = aimbotSettings.Enabled,
        Callback = function(value)
            aimbotSettings.Enabled = value
            ToggleAimbot()
        end
    })
    
    local Keybind = MainSection:AddKeybind({
        Name = "Aimbot Keybind",
        Default = aimbotSettings.Keybind,
        Callback = function(key)
            aimbotSettings.Keybind = key
            SetupKeybinds()
        end
    })
    
    local PredictionToggle = MainSection:AddToggle({
        Name = "Hit Prediction",
        Default = aimbotSettings.Prediction,
        Callback = function(value)
            aimbotSettings.Prediction = value
        end
    })
    
    local AimPartDropdown = MainSection:AddDropdown({
        Name = "Aim Part",
        Default = aimbotSettings.AimPart,
        Options = {"Head", "HumanoidRootPart", "UpperTorso", "LowerTorso"},
        Callback = function(value)
            aimbotSettings.AimPart = value
        end
    })
    
    local IgnoreTeamToggle = MainSection:AddToggle({
        Name = "Ignore Team",
        Default = aimbotSettings.IgnoreTeam,
        Callback = function(value)
            aimbotSettings.IgnoreTeam = value
        end
    })
    
    local FOVSection = tab:AddSection({
        Name = "FOV Settings"
    })
    
    local FOVToggle = FOVSection:AddToggle({
        Name = "Show FOV",
        Default = aimbotSettings.FOVVisible,
        Callback = function(value)
            aimbotSettings.FOVVisible = value
        end
    })
    
    local FOVColor = FOVSection:AddColorpicker({
        Name = "FOV Color",
        Default = aimbotSettings.FOVColor,
        Callback = function(value)
            aimbotSettings.FOVColor = value
        end
    })
    
    local FOVRadiusSlider = FOVSection:AddSlider({
        Name = "FOV Size",
        Min = 10,
        Max = 300,
        Default = aimbotSettings.FOVRadius,
        Color = Color3.fromRGB(0, 255, 0),
        Increment = 5,
        Callback = function(value)
            aimbotSettings.FOVRadius = value
        end
    })
    
    local SmoothnessSlider = FOVSection:AddSlider({
        Name = "Smoothness",
        Min = 0.1,
        Max = 1,
        Default = aimbotSettings.Smoothness,
        Color = Color3.fromRGB(0, 0, 255),
        Increment = 0.05,
        Callback = function(value)
            aimbotSettings.Smoothness = value
        end
    })
    
    local DistanceSection = tab:AddSection({
        Name = "Distance Settings"
    })
    
    local MaxDistanceSlider = DistanceSection:AddSlider({
        Name = "Max Distance",
        Min = 100,
        Max = 5000,
        Default = aimbotSettings.MaxDistance,
        Color = Color3.fromRGB(255, 0, 0),
        Increment = 50,
        ValueName = "Studs",
        Callback = function(value)
            aimbotSettings.MaxDistance = value
        end
    })
    
    local WallCheckToggle = DistanceSection:AddToggle({
        Name = "Wall Check",
        Default = aimbotSettings.WallCheck,
        Callback = function(value)
            aimbotSettings.WallCheck = value
        end
    })
    
    local TriggerbotSection = tab:AddSection({
        Name = "Triggerbot"
    })
    
    local TriggerbotToggle = TriggerbotSection:AddToggle({
        Name = "Enable Triggerbot",
        Default = aimbotSettings.Triggerbot,
        Callback = function(value)
            aimbotSettings.Triggerbot = value
        end
    })
    
    local TriggerbotKeybind = TriggerbotSection:AddKeybind({
        Name = "Triggerbot Key",
        Default = aimbotSettings.TriggerbotKey,
        Callback = function(key)
            aimbotSettings.TriggerbotKey = key
        end
    })
    
    -- Info Section
    local InfoSection = tab:AddSection({
        Name = "Status"
    })
    
    local StatusLabel = InfoSection:AddLabel("Status: Inactive")
    local TargetLabel = InfoSection:AddLabel("Target: None")
    local DistanceLabel = InfoSection:AddLabel("Distance: -")
    
    -- Update Info Labels
    local infoConnection
    infoConnection = RunService.Heartbeat:Connect(function()
        if aimbotSettings.Enabled and isAiming and targetPlayer then
            StatusLabel:Set("Status: Active (Target Locked)")
            TargetLabel:Set("Target: " .. targetPlayer.Name)
            
            if targetPlayer.Character and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
                local rootPart = targetPlayer.Character:FindFirstChild("HumanoidRootPart")
                local localRoot = LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                
                if rootPart and localRoot then
                    local distance = (rootPart.Position - localRoot.Position).Magnitude
                    DistanceLabel:Set("Distance: " .. math.floor(distance) .. " Studs")
                end
            end
        else
            StatusLabel:Set("Status: " .. (aimbotSettings.Enabled and "Active (No Target)" or "Inactive"))
            TargetLabel:Set("Target: None")
            DistanceLabel:Set("Distance: -")
        end
    end)
    
    -- Initialisierung
    SetupKeybinds()
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
