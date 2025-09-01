-- tabs/aimbot.lua  (executor-friendly)
return function(tab, OrionLib)
    print("[SorinHub] Aimbot (exec) init")

    ----------------------------------------------------------------
    -- Executor-sichere UI-Parent-Ermittlung
    ----------------------------------------------------------------
    local function get_ui_parent()
        local parent = nil
        pcall(function()
            if gethui then parent = gethui() end
        end)
        if not parent then
            parent = (game:FindFirstChild("CoreGui") or game:GetService("CoreGui"))
        end
        return parent
    end

    local function protect_gui(gui)
        pcall(function() if syn and syn.protect_gui then syn.protect_gui(gui) end end)
    end

    ----------------------------------------------------------------
    -- Services & State
    ----------------------------------------------------------------
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local UserInputService = game:GetService("UserInputService")
    local Workspace = game:GetService("Workspace")
    local LocalPlayer = Players.LocalPlayer
    local Camera = Workspace.CurrentCamera

    -- Executor-Features erkennen
    local hasDrawing = (typeof(Drawing) == "table" or typeof(Drawing) == "userdata") and typeof(Drawing.new) == "function"
    local canMouseClick = (typeof(mouse1click) == "function")
                        or (typeof(mouse1press) == "function" and typeof(mouse1release) == "function")

    -- Settings (ein Objekt!)
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
        Smoothness    = 0.25,                -- 0.1=snappy, 1.0=weich

        WallCheck     = false,
        VisibleCheck  = true,                -- Zielteil muss on-screen sein

        Triggerbot    = false,
        TriggerKey    = Enum.KeyCode.E
    }

    -- Laufzeit
    local aimbotConn, infoConn
    local targetPlayer, isAiming = nil, false

    ----------------------------------------------------------------
    -- FOV Overlay (Drawing bevorzugt; GUI-Fallback)
    ----------------------------------------------------------------
    local FOVCircle -- either Drawing circle or GUI frame
    local FOVGui -- only if GUI mode

    local function ensureFOV()
        if not aimbotSettings.FOVVisible then return end
        if hasDrawing then
            if not FOVCircle then
                FOVCircle = Drawing.new("Circle")
                FOVCircle.Thickness = 2
                FOVCircle.Filled = false
                FOVCircle.Transparency = 1
            end
        else
            if not FOVGui then
                FOVGui = Instance.new("ScreenGui")
                FOVGui.Name = "Sorin_FOV"
                FOVGui.ResetOnSpawn = false
                FOVGui.IgnoreGuiInset = true
                protect_gui(FOVGui)
                FOVGui.Parent = get_ui_parent()

                local circle = Instance.new("Frame")
                circle.Name = "FOV"
                circle.Size = UDim2.fromOffset(aimbotSettings.FOVRadius*2, aimbotSettings.FOVRadius*2)
                circle.BackgroundTransparency = 1
                circle.BorderSizePixel = 0
                circle.Parent = FOVGui

                local uic = Instance.new("UICorner"); uic.CornerRadius = UDim.new(1,0); uic.Parent = circle
                local stroke = Instance.new("UIStroke"); stroke.Thickness = 2; stroke.Parent = circle

                FOVCircle = circle
            end
        end
    end

    local function updateFOV()
        if not FOVCircle then return end
        local m = UserInputService:GetMouseLocation()
        local r = aimbotSettings.FOVRadius
        local c = aimbotSettings.FOVColor
        local vis = aimbotSettings.FOVVisible

        if hasDrawing then
            FOVCircle.Visible = vis
            FOVCircle.Radius = r
            FOVCircle.Color = c
            FOVCircle.Position = Vector2.new(m.X, m.Y)
        else
            if FOVGui then FOVGui.Enabled = vis end
            FOVCircle.Visible = vis
            FOVCircle.Size = UDim2.fromOffset(r*2, r*2)
            FOVCircle.Position = UDim2.fromOffset(m.X - r, m.Y - r)
            local stroke = FOVCircle:FindFirstChildOfClass("UIStroke")
            if stroke then stroke.Color = c end
        end
    end

    ----------------------------------------------------------------
    -- Core-Logik
    ----------------------------------------------------------------
    local function mkRaycastParams(excludeList)
        local params = RaycastParams.new()
        params.IgnoreWater = true
        -- Fallback für alte Enums:
        local ok = pcall(function() params.FilterType = Enum.RaycastFilterType.Exclude end)
        if not ok then
            params.FilterType = Enum.RaycastFilterType.Blacklist
        end
        params.FilterDescendantsInstances = excludeList
        return params
    end

    local function isPartVisible(part)
        local char = LocalPlayer.Character
        if not (Camera and part and char) then return false end
        local head = char:FindFirstChild("Head"); if not head then return false end

        local dir = part.Position - head.Position
        local res = Workspace:Raycast(head.Position, dir, mkRaycastParams({char, Camera}))
        if res then
            return res.Instance:IsDescendantOf(part.Parent)
        end
        return true
    end

    local function predictPosition(part)
        if not aimbotSettings.Prediction or not part then
            return part and part.Position or nil
        end
        if not Camera then return part.Position end
        local speed = 2000
        local t = (part.Position - Camera.CFrame.Position).Magnitude / speed
        return part.Position + part.Velocity * t
    end

    local function getClosestPlayer()
        local myChar = LocalPlayer.Character
        local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
        if not (Camera and myRoot) then return nil end

        local mouse = UserInputService:GetMouseLocation()
        local bestPlr, bestDist = nil, math.huge

        for _,plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer then
                local ch = plr.Character
                local hum = ch and ch:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 then
                    if aimbotSettings.IgnoreTeam and plr.Team and LocalPlayer.Team and (plr.Team == LocalPlayer.Team) then
                        goto continue
                    end

                    local part = ch:FindFirstChild(aimbotSettings.AimPart) or ch:FindFirstChild("HumanoidRootPart")
                    if not part then goto continue end

                    local studs = (part.Position - myRoot.Position).Magnitude
                    if studs > aimbotSettings.MaxDistance then goto continue end

                    if aimbotSettings.WallCheck and not isPartVisible(part) then
                        goto continue
                    end

                    local sp, onScreen = Camera:WorldToViewportPoint(part.Position)
                    if aimbotSettings.VisibleCheck and not onScreen then
                        goto continue
                    end

                    local screenDist = (Vector2.new(mouse.X, mouse.Y) - Vector2.new(sp.X, sp.Y)).Magnitude
                    if screenDist <= aimbotSettings.FOVRadius and screenDist < bestDist then
                        bestDist = screenDist
                        bestPlr = plr
                    end
                end
            end
            ::continue::
        end

        return bestPlr
    end

    local function aimAt(plr)
        if not (plr and Camera) then return end
        local ch = plr.Character
        local part = ch and (ch:FindFirstChild(aimbotSettings.AimPart) or ch:FindFirstChild("HumanoidRootPart"))
        if not part then return end

        local from = Camera.CFrame.Position
        local target = predictPosition(part) or part.Position
        local desired = (target - from).Unit

        local alpha = math.clamp(1 - aimbotSettings.Smoothness, 0, 1)
        local newLook = Camera.CFrame.LookVector:Lerp(desired, alpha)
        Camera.CFrame = CFrame.new(from, from + newLook)
    end

    local function triggerTick()
        if not aimbotSettings.Triggerbot then return end
        if not UserInputService:IsKeyDown(aimbotSettings.TriggerKey) then return end
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

    local function startLoop()
        if aimbotConn then aimbotConn:Disconnect() end
        ensureFOV()
        aimbotConn = RunService.RenderStepped:Connect(function()
            Camera = Workspace.CurrentCamera
            updateFOV()
            if not Camera then return end

            local p = getClosestPlayer()
            if p then
                targetPlayer = p
                isAiming = true
                aimAt(p)
                triggerTick()
            else
                targetPlayer = nil
                isAiming = false
            end
        end)
    end

    local function stopLoop()
        if aimbotConn then aimbotConn:Disconnect(); aimbotConn = nil end
        targetPlayer, isAiming = nil, false
        if hasDrawing and FOVCircle then
            FOVCircle.Visible = false
        elseif FOVGui then
            FOVGui.Enabled = false
        end
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
                startLoop()
                OrionLib:MakeNotification({ Name="Aimbot", Content="Enabled", Time=2 })
            else
                stopLoop()
                OrionLib:MakeNotification({ Name="Aimbot", Content="Disabled", Time=2 })
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
                startLoop()
                OrionLib:MakeNotification({ Name="Aimbot", Content="Enabled (keybind)", Time=2 })
            else
                stopLoop()
                OrionLib:MakeNotification({ Name="Aimbot", Content="Disabled (keybind)", Time=2 })
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
        Options = { "Head", "HumanoidRootPart", "UpperTorso", "LowerTorso" },
        Default = aimbotSettings.AimPart,
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
        Callback = function(v)
            aimbotSettings.FOVVisible = v
            ensureFOV(); updateFOV()
        end
    })
    fov:AddColorpicker({
        Name = "FOV Color",
        Default = aimbotSettings.FOVColor,
        Callback = function(c)
            aimbotSettings.FOVColor = c
            updateFOV()
        end
    })
    fov:AddSlider({
        Name = "FOV Size",
        Min = 10, Max = 300, Increment = 5,
        Default = aimbotSettings.FOVRadius,
        Callback = function(v)
            aimbotSettings.FOVRadius = v
            updateFOV()
        end
    })

    local checks = tab:AddSection({ Name = "Distance / Checks" })
    checks:AddSlider({
        Name = "Max Distance",
        Min = 100, Max = 5000, Increment = 50,
        Default = aimbotSettings.MaxDistance, ValueName = "Studs",
        Callback = function(v) aimbotSettings.MaxDistance = v end
    })
    checks:AddSlider({
        Name = "Smoothness",
        Min = 0.1, Max = 1, Increment = 0.05,
        Default = aimbotSettings.Smoothness,
        Callback = function(v) aimbotSettings.Smoothness = v end
    })
    checks:AddToggle({
        Name = "Wall Check (raycast)",
        Default = aimbotSettings.WallCheck,
        Callback = function(v) aimbotSettings.WallCheck = v end
    })
    checks:AddToggle({
        Name = "Require On-Screen",
        Default = aimbotSettings.VisibleCheck,
        Callback = function(v) aimbotSettings.VisibleCheck = v end
    })

    local trig = tab:AddSection({ Name = "Triggerbot" })
    trig:AddToggle({
        Name = "Enable Triggerbot (hold key)",
        Default = aimbotSettings.Triggerbot,
        Callback = function(v) aimbotSettings.Triggerbot = v end
    })
    trig:AddBind({
        Name = "Trigger Key (hold)",
        Default = aimbotSettings.TriggerKey,
        Hold = true,
        Callback = function() end -- wir pollen IsKeyDown pro Frame
    })

    local status = tab:AddSection({ Name = "Status" })
    local lblStatus = status:AddLabel("Status: Inactive")
    local lblTarget = status:AddLabel("Target: None")

    if infoConn then infoConn:Disconnect() end
    infoConn = RunService.Heartbeat:Connect(function()
        if aimbotSettings.Enabled and isAiming and targetPlayer then
            lblStatus:Set("Status: Active (Target Locked)")
            lblTarget:Set("Target: " .. targetPlayer.Name)
        else
            lblStatus:Set(aimbotSettings.Enabled and "Status: Active (No Target)" or "Status: Inactive")
            lblTarget:Set("Target: None")
        end
    end)

    local maintenance = tab:AddSection({ Name = "Maintenance" })
    maintenance:AddButton({
        Name = "Stop & Cleanup",
        Callback = function()
            stopLoop()
            if infoConn then infoConn:Disconnect(); infoConn = nil end
            if hasDrawing and FOVCircle then pcall(function() FOVCircle:Remove() end); FOVCircle=nil end
            if FOVGui then pcall(function() FOVGui:Destroy() end); FOVGui=nil end
            OrionLib:MakeNotification({ Name="Aimbot", Content="Stopped & cleaned up.", Time=2 })
        end
    })
end
