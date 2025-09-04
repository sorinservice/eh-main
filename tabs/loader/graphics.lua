-- tabs/graphics.lua
-- Graphics Tab for SorinHub (client-only visual helpers)
-- Fullbright (dynamic), X-Ray 50%, Ghost with animated "shine wave" + optional rainbow.
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

    local function on(sig, fn, bucket)
        local c = sig:Connect(fn)
        if bucket then table.insert(bucket, c) end
        return c
    end
    local function disconnectAll(list)
        for _,c in ipairs(list) do pcall(function() c:Disconnect() end) end
        table.clear(list)
    end
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
        targets = {
            minBrightness = 2.4,            -- minimum comfortable brightness
            minExposure   = 0.8,            -- minimum exposure add
            targetAmbient = Color3.fromRGB(180,180,180)
        }
    }

    local function fb_enable()
        if FB.enabled then return end
        FB.enabled = true

        FB.cc = Instance.new("ColorCorrectionEffect")
        FB.cc.Name = "SorinFullbright"
        FB.cc.Brightness = 0
        FB.cc.Contrast   = 0
        FB.cc.Saturation = 0
        FB.cc.Parent = Lighting

        FB.loop = on(RunService.RenderStepped, function()
            if not FB.enabled then return end

            -- Lift only if the game is darker than our minimums (prevents daylight blowout)
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

            -- Subtle post lift (no blur)
            FB.cc.Brightness = approach(FB.cc.Brightness, 0.09, 0.10)
            FB.cc.Contrast   = approach(FB.cc.Contrast,   0.06, 0.10)
        end)
    end
    local function fb_disable()
        if not FB.enabled then return end
        FB.enabled = false
        if FB.loop then FB.loop:Disconnect(); FB.loop=nil end
        if FB.cc then FB.cc:Destroy(); FB.cc=nil end
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
        obj.LocalTransparencyModifier = 0.5
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
        XR.conns.add = on(Workspace.DescendantAdded, tryXray, XR.conns)
    end
    local function xr_disable()
        if not XR.enabled then return end
        XR.enabled=false
        disconnectAll(XR.conns)
        clearXray()
    end
    local function xr_set(v)
        if v then xr_enable() else xr_disable() end
    end

    ----------------------------------------------------------------
    -- GHOST (filled silhouette + animated "shine wave")
    local GH = {
        enabled     = false,
        wave        = true,
        baseColor   = Color3.fromRGB(255, 0, 255),
        rainbow     = false,
        parts       = {},
        hi          = nil,
        conns       = {},
        rainbowConn = nil,
        waveConn    = nil,
        waveSpeed   = 1.5,   -- studs/sec vertical
        waveWidth   = 2.8,   -- band width (studs)
        baseLTM     = 0.45,  -- default transparency (higher = more transparent)
        waveDepth   = 0.20,  -- band “shine” depth
    }

    local function collectParts(char)
        local t = {}
        for _,d in ipairs(char:GetDescendants()) do
            if d:IsA("BasePart") then table.insert(t, d) end
        end
        return t
    end

    local function applyGhostTo(char)
        if not char then return end

        GH.parts = collectParts(char)
        for _,p in ipairs(GH.parts) do
            p.LocalTransparencyModifier = GH.baseLTM
            p.CanCollide = false
        end

        if not GH.hi then
            local h = Instance.new("Highlight")
            h.Name = "SorinGhost"
            h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            h.FillTransparency    = 0.32
            h.OutlineTransparency = 0.18
            h.FillColor    = GH.baseColor
            h.OutlineColor = GH.baseColor
            h.Parent = char
            GH.hi = h
        else
            GH.hi.Parent = char
        end

        -- Subtle “breathing” outline
        GH.conns.breathe = on(RunService.Heartbeat, function()
            if not (GH.enabled and GH.hi) then return end
            local t = tick()
            local k = (math.sin(t*2.0)*0.5 + 0.5) * 0.06
            GH.hi.OutlineTransparency = 0.18 + k
        end, GH.conns)

        -- Vertical shine band
        if GH.wave then
            local pos = 0
            GH.waveConn = on(RunService.Heartbeat, function(dt)
                if not GH.enabled then return end
                local charNow = GH.hi and GH.hi.Parent
                if not charNow then return end
                local hrp = charNow:FindFirstChild("HumanoidRootPart")
                local originY = hrp and hrp.Position.Y or (charNow:GetPivot().Position.Y)
                pos = (pos + dt * GH.waveSpeed) % 8

                for _,p in ipairs(GH.parts) do
                    if p and p.Parent then
                        local y = p.Position.Y - originY
                        local d = math.abs(y - pos)
                        local band = math.clamp(1 - (d / GH.waveWidth), 0, 1)
                        p.LocalTransparencyModifier = GH.baseLTM - (band * GH.waveDepth)
                    end
                end
            end)
        end

        -- Safety: re-apply after seats/vehicles mess with LTM
        GH.conns.reapply = on(RunService.Stepped, function()
            if not GH.enabled then return end
            for _,p in ipairs(GH.parts) do
                if p and p.Parent and p.LocalTransparencyModifier > GH.baseLTM + 0.01 then
                    p.LocalTransparencyModifier = GH.baseLTM
                end
            end
        end, GH.conns)
    end

    local function ghost_remove()
        if GH.waveConn then GH.waveConn:Disconnect(); GH.waveConn=nil end
        disconnectAll(GH.conns)
        if GH.hi then GH.hi:Destroy(); GH.hi=nil end
        for _,p in ipairs(GH.parts) do
            if p and p.Parent then
                p.LocalTransparencyModifier = 0
            end
        end
        GH.parts = {}
    end
    local function ghost_start()
        if GH.enabled then return end
        GH.enabled = true
        applyGhostTo(LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait())
        GH.conns.char = on(LocalPlayer.CharacterAdded, function(ch)
            ghost_remove()
            applyGhostTo(ch)
        end, GH.conns)
    end
    local function ghost_stop()
        if not GH.enabled then return end
        GH.enabled = false
        ghost_remove()
    end
    local function ghost_set(v)
        if v then ghost_start() else ghost_stop() end
    end

    local function rainbow_start()
        if GH.rainbowConn then return end
        local hue = 0
        GH.rainbowConn = on(RunService.Heartbeat, function(dt)
            hue = (hue + dt * 0.15) % 1
            local c = Color3.fromHSV(hue, 1, 1)
            if GH.hi then
                GH.hi.FillColor    = c
                GH.hi.OutlineColor = c
            end
        end)
    end
    local function rainbow_stop()
        if GH.rainbowConn then GH.rainbowConn:Disconnect(); GH.rainbowConn=nil end
        if GH.hi then
            GH.hi.FillColor    = GH.baseColor
            GH.hi.OutlineColor = GH.baseColor
        end
    end

    ----------------------------------------------------------------
    -- Camera zoom (persist + guarded)
    local ZOOM = {
        target = (Players.LocalPlayer and Players.LocalPlayer.CameraMaxZoomDistance) or 128,
        guardConn = nil,
    }
    local function applyZoom(v)
        ZOOM.target = math.clamp(v or ZOOM.target, 6, 2000)
        local plr = Players.LocalPlayer
        if not plr then return end
        if plr.CameraMode == Enum.CameraMode.LockFirstPerson then
            plr.CameraMode = Enum.CameraMode.Classic
        end
        plr.CameraMaxZoomDistance = ZOOM.target
    end
    if not ZOOM.guardConn then
        ZOOM.guardConn = RunService.Stepped:Connect(function()
            local plr = Players.LocalPlayer
            if plr and plr.CameraMaxZoomDistance ~= ZOOM.target then
                plr.CameraMaxZoomDistance = ZOOM.target
            end
        end)
    end
    Players.LocalPlayer.CharacterAdded:Connect(function()
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

    tab:AddSection({Name = "Ghost Options"})
    tab:AddToggle({
        Name = "Player Ghost",
        Default = false, Save = true, Flag = "gfx_ghost",
        Callback = function(v)
            if not BOOT.ready then return end
            ghost_set(v)
        end
    })
    tab:AddToggle({
        Name = "Shine Wave",
        Default = true, Save = true, Flag = "gfx_ghost_wave",
        Callback = function(v)
            GH.wave = v
            if not BOOT.ready then return end
            if GH.enabled then
                -- restart to apply wave toggle cleanly
                ghost_stop(); ghost_start()
            end
        end
    })
    tab:AddColorpicker({
        Name = "Ghost Color",
        Default = GH.baseColor, Save = true, Flag = "gfx_ghost_color",
        Callback = function(c)
            GH.baseColor = c
            if not BOOT.ready then return end
            if GH.hi and not GH.rainbow then
                GH.hi.FillColor    = c
                GH.hi.OutlineColor = c
            end
        end
    })
    tab:AddToggle({
        Name = "Rainbow Color",
        Default = false, Save = true, Flag = "gfx_ghost_rainbow",
        Callback = function(v)
            if not BOOT.ready then return end
            GH.rainbow = v
            if v then rainbow_start() else rainbow_stop() end
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
    -- We yield 2 short frames to let OrionLib:Init load config and call :Set on flags.
    task.spawn(function()
        task.wait(0.05)
        task.wait() -- next frame

        -- Read current saved values (no callbacks yet)
        local f_fb   = OrionLib.Flags["gfx_fullbright" ] and OrionLib.Flags["gfx_fullbright" ].Value or false
        local f_xr   = OrionLib.Flags["gfx_xray"       ] and OrionLib.Flags["gfx_xray"       ].Value or false
        local f_gh   = OrionLib.Flags["gfx_ghost"      ] and OrionLib.Flags["gfx_ghost"      ].Value or false
        local f_wave = OrionLib.Flags["gfx_ghost_wave" ] and OrionLib.Flags["gfx_ghost_wave" ].Value or true
        local f_col  = OrionLib.Flags["gfx_ghost_color"] and OrionLib.Flags["gfx_ghost_color"].Value or GH.baseColor
        local f_rnb  = OrionLib.Flags["gfx_ghost_rainbow"] and OrionLib.Flags["gfx_ghost_rainbow"].Value or false
        local f_zoom = OrionLib.Flags["gfx_zoom_max"   ] and OrionLib.Flags["gfx_zoom_max"   ].Value or ZOOM.target

        -- Apply once, now that flags are stable
        GH.wave      = f_wave
        GH.baseColor = f_col
        applyZoom(f_zoom)

        if f_fb   then fb_enable()   else fb_disable()   end
        if f_xr   then xr_enable()   else xr_disable()   end
        if f_gh   then ghost_start() else ghost_stop()   end
        if f_rnb  then rainbow_start() else rainbow_stop() end

        BOOT.ready = true
    end)
end
