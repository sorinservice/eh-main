-- tabs/aimbot.lua
return function(tab, OrionLib)
    print("[SorinHub] Aimbot module (center-FOV, mobile UI, persist) init")

    ----------------------------------------------------------------
    -- Services & basics
    ----------------------------------------------------------------
    local Players      = game:GetService("Players")
    local RunService   = game:GetService("RunService")
    local UserInput    = game:GetService("UserInputService")
    local Workspace    = game:GetService("Workspace")
    local HttpService  = game:GetService("HttpService")
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

    ----------------------------------------------------------------
    -- Persistence (readfile/writefile)
    ----------------------------------------------------------------
    local CFG_DIR  = "SorinConfig"
    local CFG_PATH = CFG_DIR.."/aimbot.json"

    local function file_exists(path)
        return (isfile and isfile(path)) and true or false
    end
    local function save_json(tbl)
        if not makefolder or not writefile then return end
        if not isfolder(CFG_DIR) then pcall(makefolder, CFG_DIR) end
        local ok, data = pcall(HttpService.JSONEncode, HttpService, tbl)
        if ok then pcall(writefile, CFG_PATH, data) end
    end
    local function load_json(defaults)
        if not readfile or not file_exists(CFG_PATH) then return defaults end
        local ok, data = pcall(readfile, CFG_PATH)
        if not ok or not data then return defaults end
        local ok2, decoded = pcall(HttpService.JSONDecode, HttpService, data)
        if ok2 and typeof(decoded)=="table" then
            for k,v in pairs(defaults) do
                if decoded[k] == nil then decoded[k] = v end
            end
            return decoded
        end
        return defaults
    end

    ----------------------------------------------------------------
    -- Config (defaults: alles aus)
    ----------------------------------------------------------------
    local DEFAULT_CFG = {
        Enabled        = false,                       -- Aimbot standardmäßig aus
        KeyActivation  = "MouseButton2",              -- RMB halten
        CloseKey       = "L",                         -- globaler Toggle
        FOVVisible     = false,                       -- FOV standardmäßig aus
        FOV            = 175,
        FOVColor       = {R=0,G=185,B=35},
        TeamCheck      = false,                       -- standard aus
        DistanceCheck  = true,
        MaxDistance    = 500,                         -- Slider 50–1000
        Smoothness     = 0.5,                         -- 0.1 weich, 1.0 aggressiv
        Prediction     = { Enabled = false, Value = 0.185 },
        AimPart        = "HumanoidRootPart",
        MobilePanel    = true                         -- kleines Mobile-Panel ein
    }

    local CFG = load_json(DEFAULT_CFG)

    local function c3_from_tbl(t) return Color3.fromRGB(t.R or 0, t.G or 185, t.B or 35) end
    local function c3_to_tbl(c)   return {R=math.floor(c.R*255), G=math.floor(c.G*255), B=math.floor(c.B*255)} end

    ----------------------------------------------------------------
    -- FOV + TargetBox (centered)
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
                local stroke = Instance.new("UIStroke"); stroke.Thickness=2; stroke.Color = c3_from_tbl(CFG.FOVColor); stroke.Parent = circle
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

    local function setFOVVisible(vis)
        if hasDrawing then
            if FOVCircle then FOVCircle.Visible = vis end
        else
            if FOVGui then FOVGui.Enabled = vis end
            if FOVCircle then FOVCircle.Visible = vis end
        end
    end

    local function updateFOV()
        ensureFOV()
        local cpos = screenCenter()
        local r    = CFG.FOV
        local col  = c3_from_tbl(CFG.FOVColor)

        if hasDrawing then
            FOVCircle.Radius   = r
            FOVCircle.Position = cpos
            FOVCircle.Color    = col
        else
            FOVCircle.Size     = UDim2.fromOffset(r*2, r*2)
            FOVCircle.Position = UDim2.fromOffset(cpos.X - r, cpos.Y - r)
            local stroke = FOVCircle:FindFirstChildOfClass("UIStroke")
            if stroke then stroke.Color = col end
        end

        -- Sichtbarkeit: FOV nur, wenn Aimbot an UND FOVVisible an
        setFOVVisible(CFG.Enabled and CFG.FOVVisible)
    end

    ----------------------------------------------------------------
    -- LOS helper
    ----------------------------------------------------------------
    local function has_clear_los(targetPart)
        if not (Camera and targetPart) then return false end
        -- Try GetPartsObscuringTarget
        local ok, blocked = pcall(function()
            return Camera:GetPartsObscuringTarget({ targetPart.Position }, { Camera, LocalPlayer.Character })
        end)
        if ok then return #blocked == 0 end

        -- Fallback Raycast
        local char = LocalPlayer.Character
        local head = char and char:FindFirstChild("Head")
        if not head then return true end
        local params = RaycastParams.new()
        params.IgnoreWater = true
        local ok2 = pcall(function() params.FilterType = Enum.RaycastFilterType.Exclude end)
        if not ok2 then params.FilterType = Enum.RaycastFilterType.Blacklist end
        params.FilterDescendantsInstances = { char, Camera }
        local res = Workspace:Raycast(head.Position, targetPart.Position - head.Position, params)
        return (not res) or res.Instance:IsDescendantOf(targetPart.Parent)
    end

    local function getRoot(plr)
        local c = plr.Character
        return c and c:FindFirstChild("HumanoidRootPart") or nil
    end

    local function team_name(plr)
        local t = plr.Team
        if t and t.Name then return t.Name end
        -- Fallbacks (falls ein Spiel Teams anders speichert)
        if plr:FindFirstChild("Team") and typeof(plr.Team.Value)=="string" then return plr.Team.Value end
        return ""
    end

    -- Wenn TeamCheck aktiv ist: nur Police <-> Citizen gegenseitig
    local function teams_are_opponents(a, b)
        local A = team_name(a)
        local B = team_name(b)
        if (A == "" or B == "") then return true end -- wenn unbekannt, nicht blocken
        local pair = {
            ["Police|Citizen"]  = true,
            ["Citizen|Police"]  = true,
        }
        return pair[A.."|"..B] or false
    end

    local function is_valid(plr)
        if plr == LocalPlayer then return false end
        local c = plr.Character
        if not c then return false end
        if c:FindFirstChildWhichIsA("ForceField") then return false end
        local hum = c:FindFirstChildWhichIsA("Humanoid")
        if not hum or hum.Health <= 0 then return false end
        if CFG.TeamCheck and (not teams_are_opponents(LocalPlayer, plr)) then return false end
        return true
    end

    -- Prediction
    local function vel_pred(v)
        return Vector3.new(v.X, math.clamp(v.Y * 0.5, -5, 10), v.Z)
    end
    local function predict_cframe(part)
        if not (part and CFG.Prediction.Enabled) then return part.CFrame end
        return part.CFrame + vel_pred(part.Velocity) * CFG.Prediction.Value
    end

    ----------------------------------------------------------------
    -- Zielsuche relativ zum Bildschirmzentrum
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
                    if on then
                        if has_clear_los(tgt) then
                            local screenDist = (center - Vector2.new(sp.X, sp.Y)).Magnitude
                            local charDist   = (myRoot.Position - tgt.Position).Magnitude
                            if screenDist <= CFG.FOV
                               and screenDist < bestScreenDist
                               and (not CFG.DistanceCheck or charDist <= CFG.MaxDistance and charDist < bestCharDist) then
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
    -- Aimen: Smoothness (0.1 langsam -> 1.0 aggressiv)
    ----------------------------------------------------------------
    local currentTarget
    local function aim_step()
        -- FOV an/aus folgt dem Enabled-Status
        setFOVVisible(CFG.Enabled and CFG.FOVVisible)
        if not CFG.Enabled then
            if TargetBox then TargetBox.Visible = false end
            return
        end

        currentTarget = get_nearest_in_fov()
        updateFOV()

        if currentTarget then
            local sp, on = Camera:WorldToViewportPoint(currentTarget.Position)
            if hasDrawing then
                TargetBox.Visible = on
                TargetBox.Position = Vector2.new(sp.X, sp.Y) - (TargetBox.Size/2)
            else
                TargetBox.Visible = on
                TargetBox.Position = UDim2.fromOffset(sp.X - 10, sp.Y - 10)
            end

            -- Nur beim gehaltenen KeyActivation (RMB)
            local keyPressed = false
            if CFG.KeyActivation == "MouseButton2" then
                keyPressed = UserInput:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
            else
                -- falls du später umschaltest
                keyPressed = UserInput:IsMouseButtonPressed(Enum.UserInputType[CFG.KeyActivation])
            end

            if keyPressed then
                local desired = CFrame.lookAt(Camera.CFrame.Position, (predict_cframe(currentTarget)).Position)
                -- Smoothness direkt als Lerp-Alpha (1.0 = aggressiv/schnell)
                local alpha = math.clamp(tonumber(CFG.Smoothness) or 0.5, 0.1, 1)
                Camera.CFrame = Camera.CFrame:Lerp(desired, alpha)
            end
        else
            if TargetBox then TargetBox.Visible = false end
        end
    end

    ----------------------------------------------------------------
    -- Mobile Aimbot-Panel (mini overlay)
    ----------------------------------------------------------------
    local MobileGui, MobileFrame, BtnAimbot, BtnPred
    local function build_mobile_panel()
        if not CFG.MobilePanel then return end
        if MobileGui then return end
        MobileGui = Instance.new("ScreenGui")
        MobileGui.Name = "Sorin_MobileAimbot"
        MobileGui.IgnoreGuiInset = true
        MobileGui.ResetOnSpawn = false
        protect_gui(MobileGui)
        MobileGui.Parent = get_ui_parent()

        MobileFrame = Instance.new("Frame")
        MobileFrame.Name = "Panel"
        MobileFrame.Size = UDim2.fromOffset(220, 64)
        MobileFrame.AnchorPoint = Vector2.new(0.5, 1)
        MobileFrame.Position = UDim2.fromScale(0.5, 0.98)
        MobileFrame.BackgroundColor3 = Color3.fromRGB(25,25,25)
        MobileFrame.Parent = MobileGui
        local uic = Instance.new("UICorner"); uic.CornerRadius = UDim.new(0,10); uic.Parent = MobileFrame
        local stroke = Instance.new("UIStroke"); stroke.Thickness=1; stroke.Color = Color3.fromRGB(90,90,90); stroke.Parent = MobileFrame

        local function makeBtn(txt, x)
            local b = Instance.new("TextButton")
            b.Size = UDim2.fromOffset(100, 40)
            b.Position = UDim2.fromOffset(x, 12)
            b.Text = txt
            b.TextColor3 = Color3.fromRGB(240,240,240)
            b.BackgroundColor3 = Color3.fromRGB(45,45,45)
            b.Font = Enum.Font.GothamBold
            b.TextSize = 14
            b.Parent = MobileFrame
            local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,8); c.Parent = b
            local s = Instance.new("UIStroke"); s.Thickness = 1; s.Color = Color3.fromRGB(80,80,80); s.Parent = b
            return b
        end

        BtnAimbot = makeBtn("Aimbot: OFF", 10)
        BtnPred   = makeBtn("Prediction: OFF", 110)

        local function refresh()
            BtnAimbot.Text = "Aimbot: "..(CFG.Enabled and "ON" or "OFF")
            BtnPred.Text   = "Prediction: "..(CFG.Prediction.Enabled and "ON" or "OFF")
        end
        refresh()

        BtnAimbot.MouseButton1Click:Connect(function()
            CFG.Enabled = not CFG.Enabled
            save_json(CFG)
            refresh()
            updateFOV()
        end)
        BtnPred.MouseButton1Click:Connect(function()
            CFG.Prediction.Enabled = not CFG.Prediction.Enabled
            save_json(CFG)
            refresh()
        end)
    end

    ----------------------------------------------------------------
    -- Orion UI
    ----------------------------------------------------------------
    local sec = tab:AddSection({ Name = "Aimbot" })
    sec:AddToggle({
        Name = "Enable Aimbot",
        Default = CFG.Enabled,
        Callback = function(v) CFG.Enabled=v; save_json(CFG); updateFOV() end
    })
    sec:AddToggle({
        Name = "Show FOV (only when Aimbot ON)",
        Default = CFG.FOVVisible,
        Callback = function(v) CFG.FOVVisible=v; save_json(CFG); updateFOV() end
    })
    sec:AddSlider({
        Name = "FOV Size",
        Min = 40, Max = 400, Increment = 5,
        Default = CFG.FOV,
        Callback = function(v) CFG.FOV = v; save_json(CFG); updateFOV() end
    })
    sec:AddColorpicker({
        Name = "FOV Color",
        Default = c3_from_tbl(CFG.FOVColor),
        Callback = function(col) CFG.FOVColor = c3_to_tbl(col); save_json(CFG); updateFOV() end
    })
    sec:AddDropdown({
        Name = "Aim Part",
        Options = {"HumanoidRootPart","Head","UpperTorso","LowerTorso"},
        Default = CFG.AimPart,
        Callback = function(v) CFG.AimPart = v; save_json(CFG) end
    })

    local sec2 = tab:AddSection({ Name = "Behavior" })
    sec2:AddSlider({
        Name = "Smoothness (0.1 slow  →  1.0 aggressive)",
        Min = 0.1, Max = 1.0, Increment = 0.05,
        Default = CFG.Smoothness,
        Callback = function(v) CFG.Smoothness = v; save_json(CFG) end
    })
    sec2:AddToggle({
        Name = "Prediction",
        Default = CFG.Prediction.Enabled,
        Callback = function(v) CFG.Prediction.Enabled = v; save_json(CFG) end
    })
    sec2:AddSlider({
        Name = "Prediction Value",
        Min = 0.05, Max = 0.35, Increment = 0.005,
        Default = CFG.Prediction.Value,
        Callback = function(v) CFG.Prediction.Value = v; save_json(CFG) end
    })

    local sec3 = tab:AddSection({ Name = "Checks" })
    sec3:AddToggle({
        Name = "Ignore Team (Police ↔ Citizen only)",
        Default = CFG.TeamCheck,
        Callback = function(v) CFG.TeamCheck = v; save_json(CFG) end
    })
    sec3:AddToggle({
        Name = "Use Distance Check",
        Default = CFG.DistanceCheck,
        Callback = function(v) CFG.DistanceCheck = v; save_json(CFG) end
    })
    sec3:AddSlider({
        Name = "Max Distance (Studs)",
        Min = 50, Max = 1000, Increment = 10,
        Default = CFG.MaxDistance,
        ValueName = "Studs",
        Callback = function(v) CFG.MaxDistance = v; save_json(CFG) end
    })

    local sec4 = tab:AddSection({ Name = "Mobile Panel" })
    sec4:AddToggle({
        Name = "Enable Mobile Aimbot Panel",
        Default = CFG.MobilePanel,
        Callback = function(v)
            CFG.MobilePanel = v; save_json(CFG)
            if v then build_mobile_panel() else if MobileGui then MobileGui:Destroy(); MobileGui=nil end end
        end
    })

    local stat = tab:AddSection({ Name = "Status" })
    local lbl = stat:AddLabel(CFG.Enabled and "Status: Active" or "Status: Inactive")

    ----------------------------------------------------------------
    -- Global toggle key (CloseKey)
    ----------------------------------------------------------------
    UserInput.InputBegan:Connect(function(input, gp)
        if gp then return end
        local key = Enum.KeyCode[CFG.CloseKey] or Enum.KeyCode.L
        if input.KeyCode == key then
            CFG.Enabled = not CFG.Enabled
            save_json(CFG)
            updateFOV()
            OrionLib:MakeNotification({
                Name = "Aimbot",
                Content = CFG.Enabled and "Enabled" or "Disabled",
                Time = 2
            })
        end
    end)

    ----------------------------------------------------------------
    -- Loop
    ----------------------------------------------------------------
    ensureFOV()
    build_mobile_panel()
    updateFOV()

    RunService.PreSimulation:Connect(function()
        lbl:Set(CFG.Enabled and "Status: Active" or "Status: Inactive")
        aim_step()
    end)
end
