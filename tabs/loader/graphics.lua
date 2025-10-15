-- tabs/graphics.lua
-- Graphics Tab
-- Fullbright (dynamic), X-Ray 50%
-- Startup-safe: no effect is applied until flags are loaded (bootstrap sync).

return function(tab, OrionLib)
    ----------------------------------------------------------------
    -- Services
    local Players      = game:GetService("Players")
    local RunService   = game:GetService("RunService")
    local Lighting     = game:GetService("Lighting")
    local Workspace    = game:GetService("Workspace")

    local LocalPlayer  = Players.LocalPlayer

    -- Bootstrap gate: block callbacks until we’ve synced once with saved flags
    local BOOT = { ready = false }

    local function approach(current, target, alpha)
        return current + (target - current) * math.clamp(alpha or 0.15, 0, 1)
    end
    local function lerpColor(a, b, t)
        return Color3.new(
            approach(a.R, b.R, t),
            approach(a.G, b.G, t),
            approach(a.B, b.B, t)
        )
    end

    ----------------------------------------------------------------
    -- FULLBRIGHT (dynamic, no ClockTime change)
    local FB = {
        enabled = false,
        cc = nil,
        loop = nil,
        saved = nil,
        targets = {
            minBrightness = 2.4,            -- minimum comfortable brightness
            minExposure   = 0.8,            -- minimum exposure add
            targetAmbient = Color3.fromRGB(180,180,180)
        }
    }

    local function fb_enable()
        if FB.enabled then return end
        FB.enabled = true

        -- Save current Lighting values
        FB.saved = {
            Brightness = Lighting.Brightness,
            Exposure = Lighting.ExposureCompensation,
            Ambient = Lighting.Ambient,
            OutdoorAmbient = Lighting.OutdoorAmbient,
            EnvironmentDiffuseScale = Lighting.EnvironmentDiffuseScale,
            EnvironmentSpecularScale = Lighting.EnvironmentSpecularScale
        }

        FB.cc = Instance.new("ColorCorrectionEffect")
        FB.cc.Name = "Fullbright"
        FB.cc.Brightness = 0
        FB.cc.Contrast   = 0
        FB.cc.Saturation = 0
        FB.cc.Parent = Lighting

        FB.loop = RunService.RenderStepped:Connect(function()
            if not FB.enabled then return end

            -- Lift only if the game is darker than our minimums
            if Lighting.Brightness < FB.targets.minBrightness then
                Lighting.Brightness = approach(Lighting.Brightness, FB.targets.minBrightness, 0.18)
            end
            if Lighting.ExposureCompensation < FB.targets.minExposure then
                Lighting.ExposureCompensation = approach(Lighting.ExposureCompensation, FB.targets.minExposure, 0.18)
            end

            -- Gently lift ambient if very dark
            local amb = Lighting.Ambient
            if (amb.R + amb.G + amb.B)/3 < 0.55 then
                Lighting.Ambient = lerpColor(amb, FB.targets.targetAmbient, 0.12)
            end
            local oamb = Lighting.OutdoorAmbient
            if (oamb.R + oamb.G + oamb.B)/3 < 0.55 then
                Lighting.OutdoorAmbient = lerpColor(oamb, FB.targets.targetAmbient, 0.12)
            end

            -- Useful for PBR scenes; nudge toward 1 smoothly
            if Lighting.EnvironmentDiffuseScale and Lighting.EnvironmentDiffuseScale < 1 then
                Lighting.EnvironmentDiffuseScale = approach(Lighting.EnvironmentDiffuseScale, 1, 0.25)
            end
            if Lighting.EnvironmentSpecularScale and Lighting.EnvironmentSpecularScale < 1 then
                Lighting.EnvironmentSpecularScale = approach(Lighting.EnvironmentSpecularScale, 1, 0.25)
            end

            -- Subtle post lift
            FB.cc.Brightness = approach(FB.cc.Brightness, 0.09, 0.10)
            FB.cc.Contrast   = approach(FB.cc.Contrast,   0.06, 0.10)
        end)
    end

    local function fb_disable()
        if not FB.enabled then return end
        FB.enabled = false
        if FB.loop then FB.loop:Disconnect(); FB.loop=nil end
        if FB.cc then FB.cc:Destroy(); FB.cc=nil end

        -- Restore previous Lighting values
        if FB.saved then
            Lighting.Brightness = FB.saved.Brightness
            Lighting.ExposureCompensation = FB.saved.Exposure
            Lighting.Ambient = FB.saved.Ambient
            Lighting.OutdoorAmbient = FB.saved.OutdoorAmbient
            if FB.saved.EnvironmentDiffuseScale then
                Lighting.EnvironmentDiffuseScale = FB.saved.EnvironmentDiffuseScale
            end
            if FB.saved.EnvironmentSpecularScale then
                Lighting.EnvironmentSpecularScale = FB.saved.EnvironmentSpecularScale
            end
            FB.saved = nil
        end
    end
    local function fb_set(v)
        if v then fb_enable() else fb_disable() end
    end

    ----------------------------------------------------------------
    -- X-RAY (fixed at 50% world transparency, excludes characters)
    local XR = { enabled=false, tracked={}, conns={} }

    local function isCharacterPart(inst)
        local p = inst
        while p do
            if p:FindFirstChildOfClass("Humanoid") then return true end
            p = p.Parent
        end
        return false
    end
    local function tryXray(obj)
        if not (obj and obj:IsA("BasePart")) then return end
        if isCharacterPart(obj) then return end
        XR.tracked[obj] = true
        pcall(function() obj.LocalTransparencyModifier = 0.5 end)
    end
    local function clearXray()
        for part in pairs(XR.tracked) do
            if part and part.Parent then
                pcall(function() part.LocalTransparencyModifier = 0 end)
            end
        end
        table.clear(XR.tracked)
    end
    local function xr_enable()
        if XR.enabled then return end
        XR.enabled = true
        for _,d in ipairs(Workspace:GetDescendants()) do tryXray(d) end
        XR.conns[#XR.conns + 1] = Workspace.DescendantAdded:Connect(tryXray)
    end
    local function xr_disable()
        if not XR.enabled then return end
        XR.enabled=false
        for _,c in ipairs(XR.conns) do pcall(function() c:Disconnect() end) end
        table.clear(XR.conns)
        clearXray()
    end
    local function xr_set(v)
        if v then xr_enable() else xr_disable() end
    end

    ----------------------------------------------------------------
    -- Camera zoom (persist + guarded)
    local ZOOM = {
        target = (LocalPlayer and LocalPlayer.CameraMaxZoomDistance) or 128,
        guardConn = nil,
    }
    local function applyZoom(v)
        ZOOM.target = math.clamp(v or ZOOM.target, 6, 2000)
        if not LocalPlayer then return end
        if LocalPlayer.CameraMode == Enum.CameraMode.LockFirstPerson then
            LocalPlayer.CameraMode = Enum.CameraMode.Classic
        end
        LocalPlayer.CameraMaxZoomDistance = ZOOM.target
    end
    if not ZOOM.guardConn then
        ZOOM.guardConn = RunService.Stepped:Connect(function()
            if LocalPlayer and LocalPlayer.CameraMaxZoomDistance ~= ZOOM.target then
                LocalPlayer.CameraMaxZoomDistance = ZOOM.target
            end
        end)
    end
    LocalPlayer.CharacterAdded:Connect(function()
        task.defer(applyZoom, ZOOM.target)
    end)

    ----------------------------------------------------------------
    -- UI
    tab:AddSection({Name = "Lighting"})
    tab:AddToggle({
        Name = "Fullbright",
        Default = false, Save = true, Flag = "gfx_fullbright",
        Callback = function(v)
            if not BOOT.ready then return end
            fb_set(v)
        end
    })

    tab:AddSection({Name = "X-Ray"})
    tab:AddToggle({
        Name = "X-Ray (world transparency)",
        Default = false, Save = true, Flag = "gfx_xray",
        Callback = function(v)
            if not BOOT.ready then return end
            xr_set(v)
        end
    })

    tab:AddSection({Name = "Camera"})
    tab:AddSlider({
        Name = "Max Zoom Distance",
        Min = 6, Max = 2000, Increment = 10,
        Default = ZOOM.target, ValueName = "studs",
        Save = true, Flag = "gfx_zoom_max",
        Callback = function(v)
            if not BOOT.ready then return end
            applyZoom(v)
        end
    })

    ----------------------------------------------------------------
    -- One-time bootstrap sync (after Orion loads flags)
    task.spawn(function()
        task.wait(0.05)
        task.wait() -- next frame

        local f_fb   = OrionLib.Flags["gfx_fullbright" ] and OrionLib.Flags["gfx_fullbright" ].Value or false
        local f_xr   = OrionLib.Flags["gfx_xray"       ] and OrionLib.Flags["gfx_xray"       ].Value or false
        local f_zoom = OrionLib.Flags["gfx_zoom_max"   ] and OrionLib.Flags["gfx_zoom_max"   ].Value or ZOOM.target

        applyZoom(f_zoom)
        if f_fb then fb_enable() else fb_disable() end
        if f_xr then xr_enable() else xr_disable() end

        BOOT.ready = true
    end)
end
