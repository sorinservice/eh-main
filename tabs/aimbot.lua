-- tabs/aimbot.lua
return function(tab, OrionLib)
    ----------------------------------------------------------------
    -- SorinHub Aimbot (Executor-freundlich)
    -- - FOV-Kreis als GUI (kein Drawing-Zwang)
    -- - BindToRenderStep nach der Kamera (funktioniert auch bei Track/Follow)
    -- - Hold-Aim (RMB) mit Aggressions-Regler (0.1..1.0  =>  höher = aggressiver)
    -- - Team-Filter (Police <-> Citizen), optional
    -- - Mobile-Panel (verschiebbar) mit Aimbot/Prediction Toggle
    -- - Persistenz über writefile/readfile  (SorinConfig/aimbot.json)
    ----------------------------------------------------------------

    -----------------------------
    -- Services & singletons
    -----------------------------
    local Players           = game:GetService("Players")
    local RunService        = game:GetService("RunService")
    local UserInputService  = game:GetService("UserInputService")
    local HttpService       = game:GetService("HttpService")
    local Camera            = workspace.CurrentCamera
    local LocalPlayer       = Players.LocalPlayer

    -----------------------------
    -- Persistenz
    -----------------------------
    local SAVE_FOLDER = OrionLib.Folder or "SorinConfig"
    local SAVE_FILE   = SAVE_FOLDER .. "/aimbot.json"

    local function safe_read_json(path)
        local ok, data = pcall(function()
            if isfile and isfile(path) then
                return HttpService:JSONDecode(readfile(path))
            end
            return nil
        end)
        return ok and data or nil
    end

    local function safe_write_json(path, tbl)
        pcall(function()
            if makefolder and not isfolder(SAVE_FOLDER) then
                makefolder(SAVE_FOLDER)
            end
            if writefile then
                writefile(path, HttpService:JSONEncode(tbl))
            end
        end)
    end

    -----------------------------
    -- Konfiguration (Defaults AUS)
    -----------------------------
    local CFG = {
        Enabled         = false,                        -- Haupt-Toggle
        KeyActivation   = "MouseButton2",               -- RMB halten
        FOVVisible      = false,                        -- FOV standardmäßig AUS
        FOVRadius       = 100,                          -- 50..300
        FOVColor        = { r = 0, g = 185, b = 35 },   -- RGB ints
        MaxDistance     = 250,                          -- 50..1000
        Aggression      = 0.25,                         -- 0.1..1.0  (höher = aggressiver)
        Prediction      = { Enabled = false, Value = 0.18 }, -- linear prediction
        TeamFilter      = { Enabled = false },          -- Police <-> Citizen
        MobilePanel     = { Enabled = false, Prediction = false }
    }

    -- Lade ggf. gespeicherte Werte
    do
        local saved = safe_read_json(SAVE_FILE)
        if type(saved) == "table" then
            for k,v in pairs(saved) do
                if type(CFG[k]) == "table" and type(v) == "table" then
                    for kk,vv in pairs(v) do CFG[k][kk] = vv end
                else
                    CFG[k] = v
                end
            end
        end
    end

    local function save_cfg()
        -- serialize Color3 table sauber
        safe_write_json(SAVE_FILE, CFG)
    end

    local function color3_from_tbl(t)
        return Color3.fromRGB(t.r or 0, t.g or 255, t.b or 0)
    end

    local function tbl_from_color3(c)
        return { r = math.floor(c.R * 255), g = math.floor(c.G * 255), b = math.floor(c.B * 255) }
    end

    -----------------------------
    -- FOV GUI (zentriert)
    -----------------------------
    local FOVGui, FOVCircle
    local function ensure_fov_gui()
        if FOVGui then return end
        FOVGui = Instance.new("ScreenGui")
        FOVGui.Name = "Sorin_FOV"
        FOVGui.IgnoreGuiInset = true
        FOVGui.ResetOnSpawn = false
        FOVGui.Parent = game:GetService("CoreGui")

        local frame = Instance.new("Frame")
        frame.Name = "Circle"
        frame.BackgroundTransparency = 1
        frame.BorderSizePixel = 0
        frame.AnchorPoint = Vector2.new(0.5, 0.5)
        frame.Parent = FOVGui

        local uic = Instance.new("UICorner")
        uic.CornerRadius = UDim.new(1, 0)
        uic.Parent = frame

        local stroke = Instance.new("UIStroke")
        stroke.Thickness = 2
        stroke.Transparency = 0.2
        stroke.Parent = frame

        FOVCircle = frame
    end

    local function update_fov_gui()
        if not (CFG.Enabled and CFG.FOVVisible) then
            if FOVGui then FOVGui.Enabled = false end
            return
        end
        ensure_fov_gui()
        FOVGui.Enabled = true

        local vp = Camera.ViewportSize
        FOVCircle.Position = UDim2.fromOffset(vp.X * 0.5, vp.Y * 0.5)
        FOVCircle.Size     = UDim2.fromOffset(CFG.FOVRadius * 2, CFG.FOVRadius * 2)
        local stroke = FOVCircle:FindFirstChildOfClass("UIStroke")
        if stroke then stroke.Color = color3_from_tbl(CFG.FOVColor) end
    end

    -----------------------------
    -- Zielauswahl & Utilities
    -----------------------------
    local function my_team_name(plr)
        local t = plr.Team
        return t and t.Name or nil
    end

    local function team_allows_target(myName, otherName)
        -- Optionaler Filter: Nur Police<->Citizen
        if not CFG.TeamFilter.Enabled then return true end
        if not myName or not otherName then return false end
        if myName == otherName then return false end
        local pair = {
            Police   = "Citizen",
            Citizen  = "Police"
        }
        return pair[myName] == otherName
    end

    local function predict_position(part)
        if not (CFG.Prediction.Enabled and part) then
            return part and part.Position or nil
        end
        local speed = math.max(0.05, CFG.Prediction.Value) -- Sekunden Vorhaltezeit-Äquivalent
        return part.Position + (part.Velocity * speed)
    end

    local function nearest_target_center()
        local me = LocalPlayer.Character
        if not me then return nil end
        local myRoot = me:FindFirstChild("HumanoidRootPart")
        if not myRoot then return nil end

        local vpCenter = Vector2.new(Camera.ViewportSize.X * 0.5, Camera.ViewportSize.Y * 0.5)
        local best, bestDist = nil, math.huge

        local myTeam = my_team_name(LocalPlayer)

        for _,plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer then
                local ch = plr.Character
                local hum = ch and ch:FindFirstChildOfClass("Humanoid")
                local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
                if hum and hum.Health > 0 and hrp then
                    -- Distanz
                    local studs = (hrp.Position - myRoot.Position).Magnitude
                    if studs <= CFG.MaxDistance then
                        -- Team-Regel, wenn eingeschaltet (Police<->Citizen)
                        if team_allows_target(myTeam, my_team_name(plr)) then
                            local sp, onScreen = Camera:WorldToViewportPoint(hrp.Position)
                            if onScreen then
                                local d = (vpCenter - Vector2.new(sp.X, sp.Y)).Magnitude
                                if d <= CFG.FOVRadius and d < bestDist then
                                    bestDist = d
                                    best = hrp
                                end
                            end
                        end
                    end
                end
            end
        end
        return best
    end

    -----------------------------
    -- Aim-Loop (nach Kamera)
    -----------------------------
    local STEP_NAME = "SorinAimStep"
    local TargetBoxGui
    local function ensure_target_box()
        if TargetBoxGui then return end
        local g = Instance.new("ScreenGui")
        g.Name = "Sorin_TargetBox"
        g.ResetOnSpawn = false
        g.IgnoreGuiInset = true
        g.Parent = game:GetService("CoreGui")

        local b = Instance.new("Frame")
        b.Name = "Box"
        b.AnchorPoint = Vector2.new(0.5, 0.5)
        b.Size = UDim2.fromOffset(20, 20)
        b.BackgroundColor3 = color3_from_tbl({r=0,g=185,b=35})
        b.BackgroundTransparency = 0.4
        b.Parent = g

        local uic = Instance.new("UICorner")
        uic.CornerRadius = UDim.new(0,4)
        uic.Parent = b

        TargetBoxGui = g
    end

    local function set_targetbox(sp, visible)
        ensure_target_box()
        TargetBoxGui.Enabled = visible or false
        if visible then
            local box = TargetBoxGui:FindFirstChild("Box")
            if box then
                box.Position = UDim2.fromOffset(sp.X, sp.Y)
            end
        end
    end

    local function start_aim_loop()
        pcall(function() RunService:UnbindFromRenderStep(STEP_NAME) end)
        local priority = Enum.RenderPriority.Camera.Value + 1

        RunService:BindToRenderStep(STEP_NAME, priority, function()
            update_fov_gui()
            if not CFG.Enabled then
                set_targetbox(Vector2.new(), false)
                return
            end

            -- Kamera ggf. in Custom versuchen (nicht kritisch)
            pcall(function()
                if Camera.CameraType ~= Enum.CameraType.Custom then
                    Camera.CameraType = Enum.CameraType.Custom
                end
            end)

            local tgt = nearest_target_center()
            if not tgt then
                set_targetbox(Vector2.new(), false)
                return
            end

            local sp, onScreen = Camera:WorldToViewportPoint(tgt.Position)
            set_targetbox(Vector2.new(sp.X, sp.Y), onScreen)

            -- Aktivieren per RMB halten
            local activationType = Enum.UserInputType[CFG.KeyActivation or "MouseButton2"]
            if activationType and UserInputService:IsMouseButtonPressed(activationType) then
                local lookTo = predict_position(tgt) or tgt.Position
                local goal   = CFrame.lookAt(Camera.CFrame.Position, lookTo)

                -- Aggression direkt als Lerp-Faktor (0.1..1.0) => höher = aggressiver
                local factor = math.clamp(CFG.Aggression or 0.25, 0.1, 1.0)

                Camera.CFrame = Camera.CFrame:Lerp(goal, factor)
                -- „Nachdruck“ falls Game zurückzieht (optional)
                -- Camera.CFrame = Camera.CFrame:Lerp(goal, factor)
            end
        end)
    end

    local function stop_aim_loop()
        pcall(function() RunService:UnbindFromRenderStep(STEP_NAME) end)
        set_targetbox(Vector2.new(), false)
        update_fov_gui()
    end

    -----------------------------
    -- Mobile-Panel (verschiebbar)
    -----------------------------
    local function spawn_mobile_panel()
        local gui = Instance.new("ScreenGui")
        gui.Name = "Sorin_MobileAim"
        gui.IgnoreGuiInset = true
        gui.ResetOnSpawn = false
        gui.Enabled = CFG.MobilePanel.Enabled
        gui.Parent = game:GetService("CoreGui")

        local frame = Instance.new("Frame")
        frame.Name = "Panel"
        frame.Size = UDim2.fromOffset(180, 120)
        frame.Position = UDim2.fromOffset(30, 300)
        frame.BackgroundColor3 = Color3.fromRGB(25,25,25)
        frame.Parent = gui

        local stroke = Instance.new("UIStroke")
        stroke.Color = Color3.fromRGB(90,90,90)
        stroke.Parent = frame

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0,12)
        corner.Parent = frame

        local title = Instance.new("TextLabel")
        title.Size = UDim2.new(1, -10, 0, 22)
        title.Position = UDim2.fromOffset(10, 6)
        title.BackgroundTransparency = 1
        title.Font = Enum.Font.GothamBold
        title.TextSize = 14
        title.Text = "Mobile Aimbot"
        title.TextColor3 = Color3.fromRGB(240,240,240)
        title.TextXAlignment = Enum.TextXAlignment.Left
        title.Parent = frame

        -- Dragging
        local dragging, dragStart, startPos
        frame.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = true
                dragStart = input.Position
                startPos = frame.Position
                input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then dragging = false end
                end)
            end
        end)
        UserInputService.InputChanged:Connect(function(input)
            if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
                local delta = input.Position - dragStart
                frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
            end
        end)

        -- Toggle Aimbot
        local ab = Instance.new("TextButton")
        ab.Size = UDim2.fromOffset(160, 28)
        ab.Position = UDim2.fromOffset(10, 40)
        ab.BackgroundColor3 = Color3.fromRGB(40,40,40)
        ab.TextColor3 = Color3.fromRGB(230,230,230)
        ab.TextSize = 14
        ab.Font = Enum.Font.GothamSemibold
        ab.Text = "Aimbot: OFF"
        ab.Parent = frame
        Instance.new("UICorner", ab).CornerRadius = UDim.new(0,8)

        local pb = Instance.new("TextButton")
        pb.Size = UDim2.fromOffset(160, 28)
        pb.Position = UDim2.fromOffset(10, 74)
        pb.BackgroundColor3 = Color3.fromRGB(40,40,40)
        pb.TextColor3 = Color3.fromRGB(230,230,230)
        pb.TextSize = 14
        pb.Font = Enum.Font.GothamSemibold
        pb.Text = "Prediction: OFF"
        pb.Parent = frame
        Instance.new("UICorner", pb).CornerRadius = UDim.new(0,8)

        local function refresh_labels()
            ab.Text = "Aimbot: " .. (CFG.Enabled and "ON" or "OFF")
            pb.Text = "Prediction: " .. ((CFG.Prediction.Enabled or CFG.MobilePanel.Prediction) and "ON" or "OFF")
        end

        ab.MouseButton1Click:Connect(function()
            CFG.Enabled = not CFG.Enabled
            if CFG.Enabled then start_aim_loop() else stop_aim_loop() end
            save_cfg(); refresh_labels()
        end)

        pb.MouseButton1Click:Connect(function()
            CFG.Prediction.Enabled = not (CFG.Prediction.Enabled)
            CFG.MobilePanel.Prediction = CFG.Prediction.Enabled
            save_cfg(); refresh_labels()
        end)

        refresh_labels()

        return gui
    end

    local MobileGui = spawn_mobile_panel()

    -----------------------------
    -- ORION UI
    -----------------------------
    local secMain   = tab:AddSection({ Name = "Aimbot" })
    local secFov    = tab:AddSection({ Name = "FOV" })
    local secFilt   = tab:AddSection({ Name = "Filter / Distance" })
    local secMob    = tab:AddSection({ Name = "Mobile Panel" })

    -- Haupt-Toggle
    secMain:AddToggle({
        Name = "Enable Aimbot",
        Default = CFG.Enabled,
        Callback = function(v)
            CFG.Enabled = v
            if v then start_aim_loop() else stop_aim_loop() end
            save_cfg()
        end
    })

    -- Aggression (0.1..1.0) – höher = aggressiver
    secMain:AddSlider({
        Name = "Aim Aggression",
        Min = 0.1, Max = 1.0, Increment = 0.05,
        Default = CFG.Aggression,
        Callback = function(v)
            CFG.Aggression = v
            save_cfg()
        end
    })

    -- Prediction Toggle + Wert
    secMain:AddToggle({
        Name = "Hit Prediction",
        Default = CFG.Prediction.Enabled,
        Callback = function(v)
            CFG.Prediction.Enabled = v
            CFG.MobilePanel.Prediction = v
            save_cfg()
        end
    })

    secMain:AddSlider({
        Name = "Prediction Value",
        Min = 0.05, Max = 0.35, Increment = 0.005,
        Default = CFG.Prediction.Value,
        Callback = function(v)
            CFG.Prediction.Value = v
            save_cfg()
        end
    })

    -- FOV
    secFov:AddToggle({
        Name = "Show FOV",
        Default = CFG.FOVVisible,
        Callback = function(v)
            CFG.FOVVisible = v
            save_cfg()
            update_fov_gui()
        end
    })

    secFov:AddSlider({
        Name = "FOV Size",
        Min = 50, Max = 300, Increment = 5,
        Default = CFG.FOVRadius,
        Callback = function(v)
            CFG.FOVRadius = math.floor(v)
            save_cfg()
        end
    })

    secFov:AddColorpicker({
        Name = "FOV Color",
        Default = color3_from_tbl(CFG.FOVColor),
        Callback = function(col)
            CFG.FOVColor = tbl_from_color3(col)
            save_cfg()
        end
    })

    -- Filter
    secFilt:AddToggle({
        Name = "Team Filter (Police <-> Citizen)",
        Default = CFG.TeamFilter.Enabled,
        Callback = function(v)
            CFG.TeamFilter.Enabled = v
            save_cfg()
        end
    })

    secFilt:AddSlider({
        Name = "Max Distance",
        Min = 50, Max = 1000, Increment = 25,
        Default = CFG.MaxDistance,
        ValueName = "Studs",
        Callback = function(v)
            CFG.MaxDistance = math.floor(v)
            save_cfg()
        end
    })

    -- Mobile Panel
    secMob:AddToggle({
        Name = "Enable Mobile Panel",
        Default = CFG.MobilePanel.Enabled,
        Callback = function(v)
            CFG.MobilePanel.Enabled = v
            if MobileGui then MobileGui.Enabled = v end
            save_cfg()
        end
    })

    -- initialer Loop-Zustand
    if CFG.Enabled then start_aim_loop() else stop_aim_loop() end
    update_fov_gui()
end
