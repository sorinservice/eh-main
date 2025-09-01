-- tabs/aimbot.lua
return function(tab, OrionLib)
    print("[SorinHub] Aimbot module (v1) init")
    -- Services
    local Players     = game:GetService("Players")
    local RunService  = game:GetService("RunService")
    local UserInput   = game:GetService("UserInputService")
    local Workspace   = game:GetService("Workspace")
    local CoreGui     = game:GetService("CoreGui")
    local HttpService = game:GetService("HttpService")

    local LocalPlayer = Players.LocalPlayer
    local Camera      = Workspace.CurrentCamera

    -- Executor helpers
    local function ui_parent()
        local p; pcall(function() if gethui then p = gethui() end end)
        return p or CoreGui
    end
    local function protect_gui(gui)
        pcall(function() if syn and syn.protect_gui then syn.protect_gui(gui) end end)
    end
    local HAS_DRAWING = (typeof(Drawing)=="table" or typeof(Drawing)=="userdata") and typeof(Drawing.new)=="function"

    ----------------------------------------------------------------
    -- Persistenz
    ----------------------------------------------------------------
    local CFG_DIR  = "SorinConfig"
    local CFG_PATH = CFG_DIR.."/aimbot.json"

    local DEFAULTS = {
        Enabled        = false,                              -- alles aus
        AimbotKey      = "Q",                                -- Toggle-Key
        KeyActivation  = "MouseButton2",                     -- RMB halten
        FOVVisible     = false,
        FOV            = 100,                                -- 50..300
        FOVColor       = {R=0,G=185,B=35},

        TeamCheck      = false,                              -- Police <-> Citizen
        DistanceCheck  = false,
        MaxDistance    = 500,                                -- 50..1000

        Smoothness     = 0.5,                                -- 0.1 smooth -> 1.0 aggressiv
        Prediction     = { Enabled=false, Value=0.185 },
        AimPart        = "HumanoidRootPart",

        MobilePanel    = true
    }

    local function C3_from_tbl(t) return Color3.fromRGB(t.R or 255, t.G or 0, t.B or 0) end
    local function C3_to_tbl(c)   return {R=math.floor(c.R*255), G=math.floor(c.G*255), B=math.floor(c.B*255)} end
    local function ensure_folder()
        if makefolder and isfolder and not isfolder(CFG_DIR) then pcall(makefolder, CFG_DIR) end
    end
    local function load_cfg()
        if not (readfile and isfile and isfile(CFG_PATH)) then return table.clone(DEFAULTS) end
        local ok, data = pcall(readfile, CFG_PATH); if not ok or not data then return table.clone(DEFAULTS) end
        local ok2, dec = pcall(HttpService.JSONDecode, HttpService, data); if not ok2 or type(dec)~="table" then return table.clone(DEFAULTS) end
        for k,v in pairs(DEFAULTS) do if dec[k]==nil then dec[k]=v end end
        return dec
    end
    local function save_cfg()
        if not (writefile and HttpService) then return end
        ensure_folder()
        local ok, enc = pcall(HttpService.JSONEncode, HttpService, CFG)
        if ok then pcall(writefile, CFG_PATH, enc) end
    end

    local CFG = load_cfg()

    ----------------------------------------------------------------
    -- JALON-Logik (center-FOV, LOS, Distance, RMB-Hold)
    ----------------------------------------------------------------
    local function screen_center()
        Camera = Workspace.CurrentCamera
        local vs = Camera and Camera.ViewportSize or Vector2.new(800,600)
        return Vector2.new(vs.X/2, vs.Y/2)
    end

    local function team_name(plr)
        local t = plr.Team
        return (t and t.Name) or ""
    end
    local function opponents(a, b)
        local A, B = team_name(a), team_name(b)
        if (A=="" or B=="") then return true end
        return (A=="Police" and B=="Citizen") or (A=="Citizen" and B=="Police")
    end

    local function root_of(plr)
        local c = plr.Character
        return c and c:FindFirstChild("HumanoidRootPart") or nil
    end

    local function is_valid_enemy(plr)
        if plr == LocalPlayer then return false end
        local ch  = plr.Character
        if not ch then return false end
        if ch:FindFirstChildWhichIsA("ForceField") then return false end
        local hum = ch:FindFirstChildWhichIsA("Humanoid")
        if not hum or hum.Health <= 0 then return false end
        if CFG.TeamCheck and not opponents(LocalPlayer, plr) then return false end
        return true
    end

    local function has_clear_los(target_pos)
        -- bevorzugt GetPartsObscuringTarget; fallback Raycast
        local ignore = { Camera, LocalPlayer.Character }
        local ok, blocked = pcall(function()
            return Camera:GetPartsObscuringTarget({ target_pos }, ignore)
        end)
        if ok then return #blocked == 0 end

        local head   = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Head")
        local origin = (head and head.Position) or Camera.CFrame.Position
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = ignore
        params.IgnoreWater = true
        local res = workspace:Raycast(origin, target_pos - origin, params)
        return (not res)
    end

    local function vel_pred(v) return Vector3.new(v.X, math.clamp(v.Y*0.5, -5, 10), v.Z) end
    local function predict_cframe(part)
        if not CFG.Prediction.Enabled then return part.CFrame end
        return part.CFrame + vel_pred(part.Velocity) * (CFG.Prediction.Value or 0.185)
    end

    local function nearest_target_center()
        Camera = Workspace.CurrentCamera
        local myRoot = root_of(LocalPlayer)
        if not (Camera and myRoot) then return nil end

        local center = screen_center()
        local bestPart, bestDist = nil, math.huge
        local FOVR = math.clamp(CFG.FOV or 100, 50, 300)

        for _, plr in ipairs(Players:GetPlayers()) do
            if is_valid_enemy(plr) then
                local ch = plr.Character
                local part = ch and (ch:FindFirstChild(CFG.AimPart) or ch:FindFirstChild("HumanoidRootPart"))
                if part then
                    local sp, on = Camera:WorldToViewportPoint(part.Position)
                    if on then
                        -- Distance gate
                        if not CFG.DistanceCheck or ((myRoot.Position - part.Position).Magnitude <= math.clamp(CFG.MaxDistance or 500, 50, 1000)) then
                            if has_clear_los(part.Position) then
                                local d = (center - Vector2.new(sp.X, sp.Y)).Magnitude
                                if d <= FOVR and d < bestDist then
                                    bestDist = d
                                    bestPart = part
                                end
                            end
                        end
                    end
                end
            end
        end
        return bestPart
    end

    ----------------------------------------------------------------
    -- FOV/TargetBox (Drawing bevorzugt, GUI Fallback)
    ----------------------------------------------------------------
    local FOVCircle, TargetBox, FOVGui

    local function ensure_fov()
        if HAS_DRAWING then
            if not FOVCircle then
                FOVCircle = Drawing.new("Circle")
                FOVCircle.Thickness = 2
                FOVCircle.Filled = false
                FOVCircle.Transparency = 0.7
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
                FOVGui.IgnoreGuiInset = true
                FOVGui.ResetOnSpawn = false
                protect_gui(FOVGui); FOVGui.Parent = ui_parent()

                local circle = Instance.new("Frame")
                circle.Name = "FOV"
                circle.BackgroundTransparency = 1
                circle.Parent = FOVGui
                local uic = Instance.new("UICorner"); uic.CornerRadius = UDim.new(1,0); uic.Parent = circle
                local stroke = Instance.new("UIStroke"); stroke.Thickness=2; stroke.Parent=circle
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

    local function set_fov_visible(vis)
        if HAS_DRAWING then
            if FOVCircle then FOVCircle.Visible = vis end
        else
            if FOVGui then FOVGui.Enabled = vis end
            if FOVCircle then FOVCircle.Visible = vis end
        end
    end

    local function update_fov()
        ensure_fov()
        local c  = screen_center()
        local R  = math.clamp(CFG.FOV or 100, 50, 300)
        local col= C3_from_tbl(CFG.FOVColor)

        if HAS_DRAWING then
            FOVCircle.Position = c
            FOVCircle.Radius   = R
            FOVCircle.Color    = col
        else
            FOVCircle.Size     = UDim2.fromOffset(R*2, R*2)
            FOVCircle.Position = UDim2.fromOffset(c.X - R, c.Y - R)
            local stroke = FOVCircle:FindFirstChildOfClass("UIStroke")
            if stroke then stroke.Color = col end
        end

        -- nur sichtbar, wenn Aimbot an UND FOVVisible true
        set_fov_visible(CFG.Enabled and CFG.FOVVisible)
    end

    ----------------------------------------------------------------
    -- Mobile Panel (draggable)
    ----------------------------------------------------------------
    local MobileGui, MobileFrame, BtnAimbot, BtnPred
    local dragging, dragStart, startPos
    local function make_mobile_panel()
        if not CFG.MobilePanel then return end
        if MobileGui then return end

        MobileGui = Instance.new("ScreenGui")
        MobileGui.Name = "Sorin_MobileAimbot"
        MobileGui.IgnoreGuiInset = true
        MobileGui.ResetOnSpawn = false
        protect_gui(MobileGui); MobileGui.Parent = ui_parent()

        MobileFrame = Instance.new("Frame")
        MobileFrame.Name = "Panel"
        MobileFrame.Size = UDim2.fromOffset(220, 64)
        MobileFrame.AnchorPoint = Vector2.new(0.5, 1)
        MobileFrame.Position = UDim2.fromScale(0.5, 0.98)
        MobileFrame.BackgroundColor3 = Color3.fromRGB(25,25,25)
        MobileFrame.Parent = MobileGui
        local uic = Instance.new("UICorner"); uic.CornerRadius = UDim.new(0,10); uic.Parent = MobileFrame
        local s   = Instance.new("UIStroke");  s.Thickness=1; s.Color = Color3.fromRGB(90,90,90); s.Parent = MobileFrame

        MobileFrame.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging  = true
                dragStart = input.Position
                startPos  = MobileFrame.Position
                input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then dragging=false end
                end)
            end
        end)
        MobileFrame.InputChanged:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
                if dragging then
                    local delta = input.Position - dragStart
                    MobileFrame.Position = UDim2.new(
                        startPos.X.Scale, startPos.X.Offset + delta.X,
                        startPos.Y.Scale, startPos.Y.Offset + delta.Y
                    )
                end
            end
        end)

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
            local s2 = Instance.new("UIStroke");  s2.Thickness=1; s2.Color = Color3.fromRGB(80,80,80); s2.Parent = b
            return b
        end

        BtnAimbot = makeBtn("Aimbot: OFF", 10)
        BtnPred   = makeBtn("Prediction: OFF", 110)

        local function refresh()
            BtnAimbot.Text = "Aimbot: " .. (CFG.Enabled and "ON" or "OFF")
            BtnPred.Text   = "Prediction: " .. (CFG.Prediction.Enabled and "ON" or "OFF")
        end
        refresh()

        BtnAimbot.MouseButton1Click:Connect(function()
            CFG.Enabled = not CFG.Enabled; save_cfg(); update_fov(); refresh()
        end)
        BtnPred.MouseButton1Click:Connect(function()
            CFG.Prediction.Enabled = not CFG.Prediction.Enabled; save_cfg(); refresh()
        end)
    end

    ----------------------------------------------------------------
    -- Orion UI (dein Style)
    ----------------------------------------------------------------
    local sec = tab:AddSection({ Name = "Aimbot" })
    sec:AddToggle({
        Name = "Enable Aimbot",
        Default = CFG.Enabled,
        Callback = function(v) CFG.Enabled=v; save_cfg(); update_fov() end
    })
    sec:AddBind({
        Name = "Aimbot Keybind (toggle)",
        Default = Enum.KeyCode[CFG.AimbotKey] or Enum.KeyCode.Q,
        Hold = false,
        Callback = function()
            CFG.Enabled = not CFG.Enabled
            save_cfg(); update_fov()
            OrionLib:MakeNotification({ Name="Aimbot", Content = CFG.Enabled and "Enabled" or "Disabled", Time=2 })
        end
    })
    sec:AddToggle({
        Name = "Show FOV (only when Aimbot ON)",
        Default = CFG.FOVVisible,
        Callback = function(v) CFG.FOVVisible=v; save_cfg(); update_fov() end
    })
    sec:AddSlider({
        Name = "FOV Size",
        Min = 50, Max = 300, Increment = 5,
        Default = CFG.FOV,
        Callback = function(v) CFG.FOV=v; save_cfg(); update_fov() end
    })
    sec:AddColorpicker({
        Name = "FOV Color",
        Default = C3_from_tbl(CFG.FOVColor),
        Callback = function(c) CFG.FOVColor=C3_to_tbl(c); save_cfg(); update_fov() end
    })
    sec:AddDropdown({
        Name = "Aim Part",
        Options = {"HumanoidRootPart","Head","UpperTorso","LowerTorso"},
        Default = CFG.AimPart,
        Callback = function(v) CFG.AimPart=v; save_cfg() end
    })

    local secB = tab:AddSection({ Name = "Behavior" })
    secB:AddSlider({
        Name = "Smoothness (0.1 smooth → 1.0 aggressive)",
        Min = 0.1, Max = 1.0, Increment = 0.05,
        Default = CFG.Smoothness,
        Callback = function(v) CFG.Smoothness=v; save_cfg() end
    })
    secB:AddToggle({
        Name = "Prediction",
        Default = CFG.Prediction.Enabled,
        Callback = function(v) CFG.Prediction.Enabled=v; save_cfg() end
    })
    secB:AddSlider({
        Name = "Prediction Value",
        Min = 0.05, Max = 0.35, Increment = 0.005,
        Default = CFG.Prediction.Value,
        Callback = function(v) CFG.Prediction.Value=v; save_cfg() end
    })

    local secC = tab:AddSection({ Name = "Checks" })
    secC:AddToggle({
        Name = "Ignore Team (Police ↔ Citizen only)",
        Default = CFG.TeamCheck,
        Callback = function(v) CFG.TeamCheck=v; save_cfg() end
    })
    secC:AddToggle({
        Name = "Use Distance Check",
        Default = CFG.DistanceCheck,
        Callback = function(v) CFG.DistanceCheck=v; save_cfg() end
    })
    secC:AddSlider({
        Name = "Max Distance (Studs)",
        Min = 50, Max = 1000, Increment = 10,
        Default = CFG.MaxDistance,
        ValueName = "Studs",
        Callback = function(v) CFG.MaxDistance=v; save_cfg() end
    })

    local secM = tab:AddSection({ Name = "Mobile Panel" })
    secM:AddToggle({
        Name = "Enable Mobile Aimbot Panel (draggable)",
        Default = CFG.MobilePanel,
        Callback = function(v)
            CFG.MobilePanel = v; save_cfg()
            if v then if not MobileGui then make_mobile_panel() end
            else if MobileGui then MobileGui:Destroy(); MobileGui=nil; MobileFrame=nil end end
        end
    })

    local stat = tab:AddSection({ Name = "Status" })
    local lbl = stat:AddLabel(CFG.Enabled and "Status: Active" or "Status: Inactive")

    ----------------------------------------------------------------
    -- Direkter Hotkey (falls außerhalb des Orion-Binds)
    ----------------------------------------------------------------
    UserInput.InputBegan:Connect(function(input, gp)
        if gp then return end
        local want = Enum.KeyCode[CFG.AimbotKey] or Enum.KeyCode.Q
        if input.KeyCode == want then
            CFG.Enabled = not CFG.Enabled
            save_cfg(); update_fov()
            OrionLib:MakeNotification({ Name="Aimbot", Content = CFG.Enabled and "Enabled" or "Disabled", Time=2 })
        end
    end)

    ----------------------------------------------------------------
    -- Loop (JALON-Style)
    ----------------------------------------------------------------
    ensure_fov()
    make_mobile_panel()
    update_fov()

    local function activation_pressed()
        local key = CFG.KeyActivation or "MouseButton2"
        local enumInp = Enum.UserInputType[key]
        if enumInp then return UserInput:IsMouseButtonPressed(enumInp) end
        return false
    end

    RunService.PreSimulation:Connect(function()
        lbl:Set(CFG.Enabled and "Status: Active" or "Status: Inactive")
        update_fov()

        if not (CFG.Enabled) then
            if HAS_DRAWING then
                if FOVCircle then FOVCircle.Visible = false end
            else
                if FOVGui then FOVGui.Enabled = false end
            end
            if TargetBox then TargetBox.Visible = false end
            return
        end

        local tgtPart = nearest_target_center()
        if not tgtPart then
            if TargetBox then TargetBox.Visible = false end
            return
        end

        local sp, on = Camera:WorldToViewportPoint(tgtPart.Position)
        if HAS_DRAWING then
            TargetBox.Visible  = on
            TargetBox.Position = Vector2.new(sp.X, sp.Y) - (TargetBox.Size/2)
        else
            TargetBox.Visible  = on
            TargetBox.Position = UDim2.fromOffset(sp.X - 10, sp.Y - 10)
        end

        -- aktives Zielen nur mit Halte-Taste (RMB)
        if activation_pressed() then
            local lookTo = (predict_cframe(tgtPart)).Position
            local goal   = CFrame.lookAt(Camera.CFrame.Position, lookTo)
            local alpha  = math.clamp(CFG.Smoothness or 0.5, 0.1, 1.0)
            Camera.CFrame = Camera.CFrame:Lerp(goal, alpha)
        end
    end)
end
