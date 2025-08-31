-- tabs/graphics.lua
-- Graphics Tab for SorinHub (client-only visual helpers)

return function(tab, OrionLib)
    ----------------------------------------------------------------
    -- Services
    local Players      = game:GetService("Players")
    local RunService   = game:GetService("RunService")
    local TweenService = game:GetService("TweenService")
    local Lighting     = game:GetService("Lighting")
    local Workspace    = game:GetService("Workspace")

    local LocalPlayer  = Players.LocalPlayer

    ----------------------------------------------------------------
    -- Helpers
    local function on(sig, fn, bucket)
        local c = sig:Connect(fn)
        if bucket then table.insert(bucket, c) end
        return c
    end
    local function disconnectAll(list)
        for _,c in ipairs(list) do pcall(function() c:Disconnect() end) end
        table.clear(list)
    end
    local function tween(obj, props, t)
        return TweenService:Create(obj, TweenInfo.new(t or 0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), props):Play()
    end

    ----------------------------------------------------------------
    -- FULLBRIGHT (smoother, natural look)
    local FB = {
        enabled = false,
        orig = {},
        cc = nil,
        locks = {}
    }

    local function captureLighting()
        FB.orig.Brightness           = Lighting.Brightness
        FB.orig.Ambient              = Lighting.Ambient
        FB.orig.OutdoorAmbient       = Lighting.OutdoorAmbient
        FB.orig.ExposureCompensation = Lighting.ExposureCompensation
        FB.orig.ClockTime            = Lighting.ClockTime
    end

    local function enableFullbright()
        if FB.enabled then return end
        FB.enabled = true
        captureLighting()

        -- subtle post effect (no ugly blur)
        FB.cc = Instance.new("ColorCorrectionEffect")
        FB.cc.Name = "SorinHubFullbright"
        FB.cc.Brightness = 0
        FB.cc.Contrast  = 0
        FB.cc.Saturation= 0
        FB.cc.Parent = Lighting

        -- target values (daylight-ish, soft)
        tween(Lighting, {ClockTime = 13.5}, 0.6)
        tween(Lighting, {Brightness = 3}, 0.6)
        tween(Lighting, {Ambient = Color3.fromRGB(180,180,180)}, 0.6)
        tween(Lighting, {OutdoorAmbient = Color3.fromRGB(180,180,180)}, 0.6)
        tween(Lighting, {ExposureCompensation = 1.25}, 0.6)

        tween(FB.cc, {Brightness = 0.12}, 0.6)
        tween(FB.cc, {Contrast   = 0.10}, 0.6)

        -- anti-flicker lock (some games fight Lighting every frame)
        FB.locks[1] = on(RunService.Stepped, function()
            if not FB.enabled then return end
            -- only “nudge” when values drift
            if math.abs(Lighting.Brightness - 3) > 0.05 then Lighting.Brightness = 3 end
            if math.abs(Lighting.ExposureCompensation - 1.25) > 0.05 then Lighting.ExposureCompensation = 1.25 end
            if math.abs(Lighting.ClockTime - 13.5) > 0.05 then Lighting.ClockTime = 13.5 end
            if (Lighting.Ambient - Color3.fromRGB(180,180,180)).Magnitude > 0.01 then
                Lighting.Ambient = Color3.fromRGB(180,180,180)
            end
            if (Lighting.OutdoorAmbient - Color3.fromRGB(180,180,180)).Magnitude > 0.01 then
                Lighting.OutdoorAmbient = Color3.fromRGB(180,180,180)
            end
        end, FB.locks)
    end

    local function disableFullbright()
        if not FB.enabled then return end
        FB.enabled = false
        disconnectAll(FB.locks)
        if next(FB.orig) then
            tween(Lighting, {ClockTime = FB.orig.ClockTime}, 0.45)
            tween(Lighting, {Brightness = FB.orig.Brightness}, 0.45)
            tween(Lighting, {Ambient = FB.orig.Ambient}, 0.45)
            tween(Lighting, {OutdoorAmbient = FB.orig.OutdoorAmbient}, 0.45)
            tween(Lighting, {ExposureCompensation = FB.orig.ExposureCompensation}, 0.45)
        end
        if FB.cc then FB.cc:Destroy(); FB.cc=nil end
    end

    ----------------------------------------------------------------
    -- X-RAY (fixed at 50% world transparency)
    local XR = {
        enabled = false,
        tracked = {},
        conns = {}
    }

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
        -- LocalTransparencyModifier does not destroy original Transparency
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

    local function enableXray()
        if XR.enabled then return end
        XR.enabled = true
        -- initial pass
        for _,d in ipairs(Workspace:GetDescendants()) do
            tryXray(d)
        end
        -- keep new parts in sync
        XR.conns[1] = on(Workspace.DescendantAdded, tryXray, XR.conns)
    end

    local function disableXray()
        if not XR.enabled then return end
        XR.enabled = false
        disconnectAll(XR.conns)
        clearXray()
    end

    ----------------------------------------------------------------
    -- GHOST (filled silhouette + local semi-transparent parts)
    local GH = {
        enabled   = false,
        baseColor = Color3.fromRGB(255, 0, 255),
        rainbow   = false,
        parts     = {},
        hi        = nil,
        conns     = {},
        rainbowConn = nil,
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
        -- make body semi transparent (local-only)
        GH.parts = collectParts(char)
        for _,p in ipairs(GH.parts) do
            p.LocalTransparencyModifier = 0.4
            p.CanCollide = false
        end
        -- add filled highlight
        if not GH.hi then
            local h = Instance.new("Highlight")
            h.Name = "SorinGhost"
            h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            h.FillTransparency = 0.35   -- << not just outline
            h.OutlineTransparency = 0.2
            h.FillColor    = GH.baseColor
            h.OutlineColor = GH.baseColor
            h.Parent = char
            GH.hi = h
        else
            GH.hi.Parent = char
        end

        -- safety: re-apply in case seats/vehicles reset LTM
        GH.conns.reapply = on(RunService.Stepped, function()
            if not GH.enabled then return end
            for _,p in ipairs(GH.parts) do
                if p and p.Parent and p.LocalTransparencyModifier < 0.39 then
                    p.LocalTransparencyModifier = 0.4
                end
            end
        end, GH.conns)
    end

    local function removeGhost()
        disconnectAll(GH.conns)
        if GH.hi then GH.hi:Destroy(); GH.hi = nil end
        for _,p in ipairs(GH.parts) do
            if p and p.Parent then
                p.LocalTransparencyModifier = 0
            end
        end
        GH.parts = {}
    end

    local function startGhost()
        if GH.enabled then return end
        GH.enabled = true
        applyGhostTo(LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait())
        GH.conns.char = on(LocalPlayer.CharacterAdded, function(ch) 
            removeGhost()
            applyGhostTo(ch)
        end, GH.conns)
    end

    local function stopGhost()
        if not GH.enabled then return end
        GH.enabled = false
        removeGhost()
    end

    local function startRainbow()
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

    local function stopRainbow()
        if GH.rainbowConn then
            GH.rainbowConn:Disconnect()
            GH.rainbowConn = nil
        end
        if GH.hi then
            GH.hi.FillColor    = GH.baseColor
            GH.hi.OutlineColor = GH.baseColor
        end
    end

    ----------------------------------------------------------------
    -- UI
    tab:AddSection({Name = "Lighting"})
    tab:AddToggle({
        Name = "Fullbright",
        Default = false, Save = true, Flag = "gfx_fullbright",
        Callback = function(v)
            if v then enableFullbright() else disableFullbright() end
        end
    })

    tab:AddSection({Name = "X-Ray"})
    tab:AddToggle({
        Name = "X-Ray (world transparency)",
        Default = false, Save = true, Flag = "gfx_xray",
        Callback = function(v)
            if v then enableXray() else disableXray() end
        end
    })

    tab:AddSection({Name = "Ghost Options"})
    tab:AddToggle({
        Name = "Player Ghost",
        Default = false, Save = true, Flag = "gfx_ghost",
        Callback = function(v)
            if v then startGhost() else stopGhost() end
        end
    })
    tab:AddColorpicker({
        Name = "Ghost Color",
        Default = GH.baseColor, Save = true, Flag = "gfx_ghost_color",
        Callback = function(c)
            GH.baseColor = c
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
            GH.rainbow = v
            if v then startRainbow() else stopRainbow() end
        end
    })

    ----------------------------------------------------------------
    -- Optional: clean up when window closes (if your lib calls this)
    -- You can call these from your global shutdown hook if you have one.
    -- disableFullbright()
    -- disableXray()
    -- stopGhost()
end
