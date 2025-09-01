-- tabs/aimbot.lua  (Stage 2: FOV only)
return function(tab, OrionLib)
    print("[SorinHub] Stage2 FOV-only init")

    local UserInputService = game:GetService("UserInputService")
    local CoreGui = game:GetService("CoreGui")

    -- Executor helpers
    local function get_ui_parent()
        local p; pcall(function() if gethui then p = gethui() end end)
        return p or CoreGui
    end
    local function protect_gui(gui)
        pcall(function() if syn and syn.protect_gui then syn.protect_gui(gui) end end)
    end

    local aimbotSettings = {
        FOVVisible = true,
        FOVRadius  = 100,
        FOVColor   = Color3.fromRGB(255,0,0),
    }

    local hasDrawing = (typeof(Drawing)=="table" or typeof(Drawing)=="userdata") and typeof(Drawing.new)=="function"

    local FOVGui, FOVCircle
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

                local frame = Instance.new("Frame")
                frame.Name = "FOV"
                frame.BackgroundTransparency = 1
                frame.Parent = FOVGui
                local uic = Instance.new("UICorner"); uic.CornerRadius = UDim.new(1,0); uic.Parent = frame
                local stroke = Instance.new("UIStroke"); stroke.Thickness = 2; stroke.Parent = frame
                FOVCircle = frame
            end
        end
    end

    local function updateFOV()
        if not FOVCircle then return end
        local m = UserInputService:GetMouseLocation()
        local r = aimbotSettings.FOVRadius
        local c = aimbotSettings.FOVColor
        if hasDrawing then
            FOVCircle.Visible   = aimbotSettings.FOVVisible
            FOVCircle.Radius    = r
            FOVCircle.Color     = c
            FOVCircle.Position  = Vector2.new(m.X, m.Y)
        else
            if FOVGui then FOVGui.Enabled = aimbotSettings.FOVVisible end
            FOVCircle.Visible   = aimbotSettings.FOVVisible
            FOVCircle.Size      = UDim2.fromOffset(r*2, r*2)
            FOVCircle.Position  = UDim2.fromOffset(m.X - r, m.Y - r)
            local stroke = FOVCircle:FindFirstChildOfClass("UIStroke")
            if stroke then stroke.Color = c end
        end
    end

    -- UI
    local fov = tab:AddSection({ Name = "FOV" })
    fov:AddToggle({ Name="Show FOV", Default=aimbotSettings.FOVVisible, Callback=function(v) aimbotSettings.FOVVisible=v; ensureFOV(); updateFOV() end })
    fov:AddColorpicker({ Name="FOV Color", Default=aimbotSettings.FOVColor, Callback=function(col) aimbotSettings.FOVColor=col; updateFOV() end })
    fov:AddSlider({ Name="FOV Size", Min=10, Max=300, Default=aimbotSettings.FOVRadius, Increment=5, Callback=function(v) aimbotSettings.FOVRadius=v; updateFOV() end })

    -- Loop
    ensureFOV()
    game:GetService("RunService").RenderStepped:Connect(function()
        ensureFOV()
        updateFOV()
    end)
end
