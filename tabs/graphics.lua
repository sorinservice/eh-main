-- tabs/graphics.lua
-- Graphics tab for SorinHub (Orion UI)
-- Features:
--  - Fullbright (natural, no blur; uses ColorCorrection + exposure with tweened enable/disable)
--  - X-Ray (fixed 50% local transparency for world parts, no slider)
--  - Player Ghost (local-only; color picker + optional rainbow color; resilient on respawn/vehicles)

return function(tab, OrionLib)
    -- // Services
    local Players      = game:GetService("Players")
    local RunService   = game:GetService("RunService")
    local TweenService = game:GetService("TweenService")
    local Lighting     = game:GetService("Lighting")
    local LP           = Players.LocalPlayer

    -- // State & bookkeeping
    local STATE = {
        fullbright   = false,
        xray         = false,
        ghost        = false,
        ghostColor   = Color3.fromRGB(255, 0, 255),
        rainbow      = false,
        rainbowSpeed = 0.15, -- hue cycles per second
    }

    local CONN = {
        worldAdded = nil,
        charAdded  = nil,
        rainbow    = nil,
    }

    -- Track parts we touched for X-Ray so we can revert cleanly
    local XRAY_TOUCH = {}
    local GHOST = {
        highlight = nil,
        humConn   = nil,
    }

    -- // Helpers
    local function tween(obj, t, props)
        local ti = TweenInfo.new(t or 0.30, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
        TweenService:Create(obj, ti, props):Play()
    end

    -- =========================================================
    -- Fullbright (natural look; avoids blur)
    -- =========================================================
    local FULLBRIGHT = {
        cc = nil,            -- ColorCorrectionEffect
        prevExposure = nil,  -- Lighting.ExposureCompensation backup
    }

    function FULLBRIGHT.enable()
        if FULLBRIGHT.cc then return end

        -- Color correction for gentle lift without washing out colors too much
        local cc = Instance.new("ColorCorrectionEffect")
        cc.Name = "SorinFullbright"
        cc.Brightness = 0
        cc.Contrast   = 0
        cc.Saturation = 0
        cc.Parent = Lighting
        FULLBRIGHT.cc = cc

        -- Tween to target values so it feels natural (no flicker/pop)
        tween(cc, 0.35, {
            Brightness = 0.25,  -- a little lift
            Contrast   = -0.05, -- keep detail
            Saturation = 0.05,  -- slight color pop back
        })

        -- Small exposure bump on Lighting itself (no Blur)
        FULLBRIGHT.prevExposure = Lighting.ExposureCompensation
        tween(Lighting, 0.35, { ExposureCompensation = 0.6 })
    end

    function FULLBRIGHT.disable()
        if not FULLBRIGHT.cc then return end
        tween(FULLBRIGHT.cc, 0.25, { Brightness = 0, Contrast = 0, Saturation = 0 })
        task.delay(0.28, function()
            if FULLBRIGHT.cc then
                FULLBRIGHT.cc:Destroy()
                FULLBRIGHT.cc = nil
            end
        end)
        if FULLBRIGHT.prevExposure ~= nil then
            tween(Lighting, 0.25, { ExposureCompensation = FULLBRIGHT.prevExposure })
            FULLBRIGHT.prevExposure = nil
        end
    end

    -- =========================================================
    -- X-Ray (world @ 50% local transparency)
    -- =========================================================
    local function tagXRay(part, on)
        if not part:IsA("BasePart") then return end
        if on then
            XRAY_TOUCH[part] = true
            -- Local-only; does not replicate to server
            part.LocalTransparencyModifier = 0.5
        else
            if XRAY_TOUCH[part] then
                XRAY_TOUCH[part] = nil
                part.LocalTransparencyModifier = 0
            end
        end
    end

    local function setXRay(on)
        if on then
            for _, d in ipairs(workspace:GetDescendants()) do
                if not (LP.Character and d:IsDescendantOf(LP.Character)) then
                    pcall(tagXRay, d, true)
                end
            end
            if not CONN.worldAdded then
                CONN.worldAdded = workspace.DescendantAdded:Connect(function(d)
                    if LP.Character and d:IsDescendantOf(LP.Character) then return end
                    pcall(tagXRay, d, true)
                end)
            end
        else
            -- Revert touched parts
            for p, _ in pairs(XRAY_TOUCH) do
                pcall(tagXRay, p, false)
            end
            table.clear(XRAY_TOUCH)
            if CONN.worldAdded then
                CONN.worldAdded:Disconnect()
                CONN.worldAdded = nil
            end
        end
    end

    -- =========================================================
    -- Player Ghost (local only; color + rainbow)
    -- =========================================================
    local rainbowHue = 0

    local function applyGhostColor(c)
        if GHOST.highlight then
            GHOST.highlight.FillColor    = c
            GHOST.highlight.OutlineColor = c
        end
    end

    local function makeGhost(char)
        if not char then return end

        -- Highlight gives that clean neon outline + fill
        if not GHOST.highlight then
            local h = Instance.new("Highlight")
            h.Name = "SorinGhost"
            h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            h.OutlineTransparency = 0.1
            h.FillTransparency    = 0.75
            h.Parent = char
            GHOST.highlight = h
        else
            GHOST.highlight.Parent = char
        end
        applyGhostColor(STATE.ghostColor)

        -- Make local character semi-transparent (local only)
        for _, p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") then
                p.LocalTransparencyModifier = 0.6
            end
        end

        -- Handle vehicle enter/exit & similar by reapplying lightly
        if GHOST.humConn then
            GHOST.humConn:Disconnect()
            GHOST.humConn = nil
        end
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then
            GHOST.humConn = hum.Seated:Connect(function()
                -- short delay to allow Roblox to re-attach parts when seating
                task.wait(0.05)
                if STATE.ghost then
                    for _, p in ipairs(char:GetDescendants()) do
                        if p:IsA("BasePart") then
                            p.LocalTransparencyModifier = 0.6
                        end
                    end
                end
            end)
        end
    end

    local function clearGhost()
        local char = LP.Character
        if char then
            for _, p in ipairs(char:GetDescendants()) do
                if p:IsA("BasePart") then
                    p.LocalTransparencyModifier = 0
                end
            end
        end
        if GHOST.humConn then
            GHOST.humConn:Disconnect()
            GHOST.humConn = nil
        end
        if GHOST.highlight then
            GHOST.highlight:Destroy()
            GHOST.highlight = nil
        end
        if CONN.rainbow then
            CONN.rainbow:Disconnect()
            CONN.rainbow = nil
        end
    end

    local function setGhost(on)
        if on then
            if LP.Character then makeGhost(LP.Character) end
            if not CONN.charAdded then
                CONN.charAdded = LP.CharacterAdded:Connect(function(char)
                    task.wait(0.1)
                    if STATE.ghost then makeGhost(char) end
                end)
            end
            -- Start/stop rainbow loop based on current toggle
            if STATE.rainbow and not CONN.rainbow then
                CONN.rainbow = RunService.RenderStepped:Connect(function(dt)
                    rainbowHue = (rainbowHue + dt * STATE.rainbowSpeed) % 1
                    applyGhostColor(Color3.fromHSV(rainbowHue, 1, 1))
                end)
            end
        else
            clearGhost()
            if CONN.charAdded then
                CONN.charAdded:Disconnect()
                CONN.charAdded = nil
            end
        end
    end

    local function setRainbow(on)
        STATE.rainbow = on
        if not STATE.ghost then
            if CONN.rainbow then CONN.rainbow:Disconnect(); CONN.rainbow = nil end
            return
        end
        if on then
            if CONN.rainbow then CONN.rainbow:Disconnect() end
            CONN.rainbow = RunService.RenderStepped:Connect(function(dt)
                rainbowHue = (rainbowHue + dt * STATE.rainbowSpeed) % 1
                applyGhostColor(Color3.fromHSV(rainbowHue, 1, 1))
            end)
        else
            if CONN.rainbow then CONN.rainbow:Disconnect(); CONN.rainbow = nil end
            applyGhostColor(STATE.ghostColor)
        end
    end

    -- =========================================================
    -- UI
    -- =========================================================
    tab:AddSection({ Name = "Fullbright" })
    tab:AddToggle({
        Name     = "Fullbright (always bright)",
        Default  = false,
        Save     = true,
        Flag     = "gfx_fullbright",
        Callback = function(v)
            STATE.fullbright = v
            if v then FULLBRIGHT.enable() else FULLBRIGHT.disable() end
        end
    })

    tab:AddSection({ Name = "X-Ray" })
    tab:AddToggle({
        Name     = "X-Ray (50% world transparency)",
        Default  = false,
        Save     = true,
        Flag     = "gfx_xray",
        Callback = function(v)
            STATE.xray = v
            setXRay(v)
        end
    })

    tab:AddSection({ Name = "Ghost Options" })
    tab:AddToggle({
        Name     = "Player Ghost",
        Default  = false,
        Save     = true,
        Flag     = "gfx_ghost",
        Callback = function(v)
            STATE.ghost = v
            setGhost(v)
        end
    })

    tab:AddColorpicker({
        Name     = "Ghost Color",
        Default  = STATE.ghostColor,
        Save     = true,
        Flag     = "gfx_ghostColor",
        Callback = function(c)
            STATE.ghostColor = c
            if STATE.ghost and not STATE.rainbow then
                applyGhostColor(c)
            end
        end
    })

    tab:AddToggle({
        Name     = "Rainbow Color",
        Default  = false,
        Save     = true,
        Flag     = "gfx_rainbow",
        Callback = function(v)
            setRainbow(v)
        end
    })
end
