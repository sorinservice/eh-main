-- tabs/aimbot.lua  — executor-safe, FOV centered, integrates JALON flow
return function(tab, OrionLib)
    print("[SorinHub] Aimbot (center-FOV) init")

    ----------------------------------------------------------------
    -- Services & basics
    ----------------------------------------------------------------
    local Players      = game:GetService("Players")
    local RunService   = game:GetService("RunService")
    local UserInput    = game:GetService("UserInputService")
    local Workspace    = game:GetService("Workspace")
    local CoreGui      = game:GetService("CoreGui")

    local LocalPlayer  = Players.LocalPlayer
    local Camera       = Workspace.CurrentCamera

    -- executor helpers
    local function get_ui_parent()
        local p; pcall(function() if gethui then p = gethui() end end)
        return p or CoreGui
    end
    local function protect_gui(gui)
        pcall(function() if syn and syn.protect_gui then syn.protect_gui(gui) end end)
    end

    local hasDrawing = (typeof(Drawing)=="table" or typeof(Drawing)=="userdata") and typeof(Drawing.new)=="function"
    local canMouseClick = (typeof(mouse1click)=="function") or (typeof(mouse1press)=="function" and typeof(mouse1release)=="function")

    ----------------------------------------------------------------
    -- Config (dein JALON-Style + UI-Overrides)
    ----------------------------------------------------------------
    local CFG = _G.JALON_AIMCONFIG or {
        Enabled        = true,
        KeyActivation  = Enum.UserInputType.MouseButton2, -- RMB halten
        CloseKey       = Enum.KeyCode.L,                  -- Toggle global on/off
        FOV            = 175,
        TeamCheck      = false,       -- team check aus
        DistanceCheck  = true,
        VisibleCheck   = true,
        Smoothness     = 0.975,       -- 0.975 = sehr smooth
        Prediction     = { Enabled = false, Value = 0.185 },
        AimPart        = "HumanoidRootPart",
    }
    _G.JALON_AIMCONFIG = CFG

    -- interne Schalter
    local scriptEnabled = true   -- globaler Kill-Switch via CloseKey
    local aimbotEnabled = CFG.Enabled

    ----------------------------------------------------------------
    -- FOV: center screen (Drawing bevorzugt, GUI-Fallback)
    ----------------------------------------------------------------
    local FOVGui, FOVCircle, TargetBox

    local function screenCenter()
        Camera = Workspace.CurrentCamera
        local vp = Camera and Camera.ViewportSize or Vector2.new(800,600)
        return Vector2.new(vp.X/2, vp.Y/2)
    end

    local function ensureFOV()
        if hasDrawing then
            if not FOVCircle then
                FOVCircle = Drawing.new("Circle")
                FOVCircle.Thickness = 2
                FOVCircle.Filled = false
                FOVCircle.Transparency = 0.6
                FOVCircle.Color = Color3.fromRGB(0,185,35)
            end
            if not TargetBox then
                TargetBox = Drawing.new("Square")
                TargetBox.Color = Color3.fromRGB(0,185,35)
                TargetBox.Filled = true
                TargetBox.Size = Vector2.new(20,20)
                TargetBox.Thickness = 20
                TargetBox.Transparency = 0.6
                TargetBox.Visible = false
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
                circle.BackgroundTransparency = 1
                circle.Parent = FOVGui
                local uic = Instance.new("UICorner"); uic.CornerRadius = UDim.new(1,0); uic.Parent = circle
                local stroke = Instance.new("UIStroke"); stroke.Thickness=2; stroke.Color = Color3.fromRGB(0,185,35); stroke.Parent = circle
                FOVCircle = circle

                local box = Instance.new("Frame")
                box.Name = "TargetBox"
                box.BackgroundColor3 = Color3.fromRGB(0,185,35)
                box.BackgroundTransparency = 0.4
                box.Size = UDim2.fromOffset(20,20)
                box.Visible = false
                box.Parent = FOVGui
                TargetBox = box
            end
        end
    end

    local function updateFOV()
        ensureFOV()
        local cpos = screenCenter()
        local r    = CFG.FOV

        if hasDrawing then
            FOVCircle.Visible  = aimbotEnabled and scriptEnabled
            FOVCircle.Radius   = r
            FOVCircle.Position = cpos
        else
            if FOVGui then FOVGui.Enabled = aimbotEnabled and scriptEnabled end
            FOVCircle.Visible  = aimbotEnabled and scriptEnabled
            FOVCircle.Size     = UDim2.fromOffset(r*2, r*2)
            FOVCircle.Position = UDim2.fromOffset(cpos.X - r, cpos.Y - r)
        end
    end

    ----------------------------------------------------------------
    -- Helper: LOS (zwei Wege: GetPartsObscuringTarget oder Raycast)
    ----------------------------------------------------------------
    local function has_clear_los(targetPart)
        if not (Camera and targetPart) then return false end
        -- Versuch 1: GetPartsObscuringTarget
        local ok, blocked = pcall(function()
            return Camera:GetPartsObscuringTarget({ targetPart.Position }, { Camera, LocalPlayer.Character })
        end)
        if ok then return #blocked == 0 end

        -- Fallback: Raycast vom Kopf zur Ziel-Position
        local char = LocalPlayer.Character
        local head = char and char:FindFirstChild("Head")
        if not head then return true end
        local params = RaycastParams.new()
        params.IgnoreWater = true
        local exclOk = pcall(function() params.FilterType = Enum.RaycastFilterType.Exclude end)
        if not exclOk then params.FilterType = Enum.RaycastFilterType.Blacklist end
        params.FilterDescendantsInstances = { char, Camera }
        local res = Workspace:Raycast(head.Position, targetPart.Position - head.Position, params)
        return (not res) or res.Instance:IsDescendantOf(targetPart.Parent)
    end

    local function getRoot(plr)
        local c = plr.Character
        return c and c:FindFirstChild("HumanoidRootPart") or nil
    end

    local function is_valid(plr)
        if plr == LocalPlayer then return false end
        local c = plr.Character
        if not c then return false end
        if c:FindFirstChildWhichIsA("ForceField") then return false end
        local hum = c:FindFirstChildWhichIsA("Humanoid")
        if not hum or hum.Health <= 0 then return false end
        if CFG.TeamCheck and LocalPlayer.Team and plr.Team and LocalPlayer.Team == plr.Team then return false end
        return true
    end

    -- Prediction wie in deinem Snippet (leicht sanfter an Y)
    local function vel_pred(v)
        return Vector3.new(v.X, math.clamp(v.Y * 0.5, -5, 10), v.Z)
    end
    local function predict_cframe(part)
        if not (part and CFG.Prediction.Enabled) then return part.CFrame end
        return part.CFrame + vel_pred(part.Velocity) * CFG.Prediction.Value
    end

    ----------------------------------------------------------------
    -- Zielsuche relativ zur BILDSCHIRMMITTE (nicht Maus)
    ----------------------------------------------------------------
    local function get_nearest_in_fov()
        Camera = Workspace.CurrentCamera
        local myRoot = getRoot(LocalPlayer)
        if not (Camera and myRoot) then return nil end

        local center = screenCenter()
        local best, bestScreenDist, bestCharDist = nil, math.huge, math.huge

        for _,plr in ipairs(Players:GetPlayers()) do
            if is_valid(plr) then
                local tgt = getRoot(plr) or (plr.Character and plr.Character:FindFirstChild(CFG.AimPart))
                if tgt then
                    local sp, on = Camera:WorldToViewportPoint(tgt.Position)
                    if not CFG.VisibleCheck or on then
                        if not CFG.VisibleCheck or has_clear_los(tgt) then
                            local screenDist = (center - Vector2.new(sp.X, sp.Y)).Magnitude
                            local charDist   = (myRoot.Position - tgt.Position).Magnitude
                            if screenDist <= CFG.FOV
                               and screenDist < bestScreenDist
                               and (not CFG.DistanceCheck or charDist < bestCharDist) then
                                best, bestScreenDist, bestCharDist = tgt, screenDist, charDist
                            end
                        end
                    end
                end
            end
        end

        return best
    end

    ----------------------------------------------------------------
    -- Aimen (RMB halten)
    ----------------------------------------------------------------
    local currentTarget -- BasePart (HRP)
    local function aim_step()
        if not (aimbotEnabled and scriptEnabled) then
            if TargetBox then TargetBox.Visible = false end
            return
        end

        currentTarget = get_nearest_in_fov()
        updateFOV()

        -- Zielmarker setzen
        if currentTarget then
            local sp, on = Camera:WorldToViewportPoint(currentTarget.Position)
            if hasDrawing then
                TargetBox.Visible = on
                TargetBox.Position = Vector2.new(sp.X, sp.Y) - (TargetBox.Size/2)
            else
                TargetBox.Visible = on
                TargetBox.Position = UDim2.fromOffset(sp.X - 10, sp.Y - 10)
            end

            -- Nur wenn RMB gehalten
            if UserInput:IsMouseButtonPressed(CFG.KeyActivation) then
                local targetCF = predict_cframe(currentTarget)
                local desired  = CFrame.lookAt(Camera.CFrame.Position, targetCF.Position)
                Camera.CFrame  = Camera.CFrame:Lerp(desired, CFG.Smoothness)
            end
        else
            if TargetBox then TargetBox.Visible = false end
        end
    end

    ----------------------------------------------------------------
    -- UI (Orion)
    ----------------------------------------------------------------
    local sec = tab:AddSection({ Name = "Aimbot" })
    sec:AddToggle({
        Name = "Enable Aimbot",
        Default = aimbotEnabled,
        Callback = function(v) aimbotEnabled = v end
    })
    sec:AddBind({
        Name = "Toggle Key (global)",
        Default = CFG.CloseKey,
        Hold = false,
        Callback = function() scriptEnabled = not scriptEnabled end
    })
    sec:AddSlider({
        Name = "FOV",
        Min = 40, Max = 400, Increment = 5,
        Default = CFG.FOV,
        Callback = function(v) CFG.FOV = v; updateFOV() end
    })
    sec:AddToggle({
        Name = "Visible Check",
        Default = CFG.VisibleCheck,
        Callback = function(v) CFG.VisibleCheck = v end
    })
    sec:AddToggle({
        Name = "Distance Check",
        Default = CFG.DistanceCheck,
        Callback = function(v) CFG.DistanceCheck = v end
    })
    sec:AddDropdown({
        Name = "Aim Part",
        Options = {"HumanoidRootPart","Head","UpperTorso","LowerTorso"},
        Default = CFG.AimPart,
        Callback = function(v) CFG.AimPart = v end
    })
    sec:AddSlider({
        Name = "Smoothness",
        Min = 0.85, Max = 0.995, Increment = 0.001,
        Default = CFG.Smoothness,
        Callback = function(v) CFG.Smoothness = v end
    })
    local pred = tab:AddSection({ Name = "Prediction" })
    pred:AddToggle({
        Name = "Enable Prediction",
        Default = CFG.Prediction.Enabled,
        Callback = function(v) CFG.Prediction.Enabled = v end
    })
    pred:AddSlider({
        Name = "Prediction Value",
        Min = 0.05, Max = 0.35, Increment = 0.005,
        Default = CFG.Prediction.Value,
        Callback = function(v) CFG.Prediction.Value = v end
    })

    -- Status
    local stat = tab:AddSection({ Name = "Status" })
    local lbl = stat:AddLabel("Status: Inactive")

    ----------------------------------------------------------------
    -- Input: global close key (L) wie im Snippet
    ----------------------------------------------------------------
    UserInput.InputBegan:Connect(function(input, gp)
        if gp then return end
        if input.KeyCode == CFG.CloseKey then
            scriptEnabled = not scriptEnabled
            OrionLib:MakeNotification({
                Name = "Aimbot",
                Content = scriptEnabled and "Enabled (global)" or "Disabled (global)",
                Time = 2
            })
        end
    end)

    ----------------------------------------------------------------
    -- Loop
    ----------------------------------------------------------------
    RunService.PreSimulation:Connect(function()
        -- Status
        if not scriptEnabled then
            lbl:Set("Status: Disabled (global)")
        elseif not aimbotEnabled then
            lbl:Set("Status: Disabled")
        else
            lbl:Set("Status: Active")
        end

        aim_step()
    end)

    -- initial draw
    ensureFOV()
    updateFOV()
end
