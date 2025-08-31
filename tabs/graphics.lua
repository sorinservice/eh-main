-- tabs/graphics.lua
-- Graphics (local-only): Fullbright (natural, no flicker), X-Ray, Ghost Player with color

return function(tab, OrionLib)
    ----------------------------------------------------------------
    -- Services
    local Players      = game:GetService("Players")
    local RunService   = game:GetService("RunService")
    local Workspace    = game:GetService("Workspace")
    local Lighting     = game:GetService("Lighting")
    local TweenService = game:GetService("TweenService")

    local LocalPlayer = Players.LocalPlayer

    ----------------------------------------------------------------
    -- State
    local STATE = {
        fb_on       = false,
        fb_strength = 0.6,     -- 0..1

        xray_on     = false,
        xray_amt    = 0.35,    -- 0..0.8

        ghost_on    = false,
        ghost_amt   = 0.55,    -- 0..0.95 (transparency)
        ghost_col   = Color3.fromRGB(160, 210, 255),
    }

    ----------------------------------------------------------------
    -- Fullbright (natural via post-processing; no per-frame edits)
    local cc, bloom

    local function getFullbrightEffects()
        if not cc then
            cc = Instance.new("ColorCorrectionEffect")
            cc.Name = "Sorin_CC"
            cc.Parent = Lighting
        end
        if not bloom then
            bloom = Instance.new("BloomEffect")
            bloom.Name = "Sorin_Bloom"
            bloom.Threshold = 0.9
            bloom.Intensity = 0.15
            bloom.Size = 12
            bloom.Parent = Lighting
        end
        return cc, bloom
    end

    local function applyFullbrightValues(strength) -- 0..1
        local c, b = getFullbrightEffects()
        local target = {
            Brightness = 0.10 + 0.35 * strength, -- 0.10..0.45
            Contrast   = 0.02 + 0.18 * strength, -- 0.02..0.20
            Saturation = 0,                       -- neutral
            Bloom      = 0.10 + 0.35 * strength, -- bloom intensity
        }
        TweenService:Create(c, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Brightness = target.Brightness,
            Contrast   = target.Contrast,
            Saturation = target.Saturation
        }):Play()
        TweenService:Create(b, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Intensity = target.Bloom
        }):Play()
    end

    local function setFullbright(on)
        if on and not STATE.fb_on then
            STATE.fb_on = true
            local c, b = getFullbrightEffects()
            c.Enabled, b.Enabled = true, true
            applyFullbrightValues(STATE.fb_strength)
        elseif (not on) and STATE.fb_on then
            STATE.fb_on = false
            if cc then cc.Enabled = false end
            if bloom then bloom.Enabled = false end
        end
    end

    ----------------------------------------------------------------
    -- X-RAY (make world slightly transparent; excludes your character)
    local xray_prev = setmetatable({}, { __mode = "k" })
    local xray_addedConn

    local function isPart(o) return o and o:IsA("BasePart") end
    local function skip(o)
        return not isPart(o) or (LocalPlayer.Character and o:IsDescendantOf(LocalPlayer.Character))
    end

    local function applyX(part)
        if skip(part) or xray_prev[part] ~= nil then return end
        xray_prev[part] = part.LocalTransparencyModifier
        part.LocalTransparencyModifier = math.max(part.LocalTransparencyModifier, STATE.xray_amt)
    end

    local function restoreX()
        for p, prev in pairs(xray_prev) do
            if p then pcall(function() p.LocalTransparencyModifier = prev end) end
            xray_prev[p] = nil
        end
    end

    local function setXray(on)
        if on and not STATE.xray_on then
            STATE.xray_on = true
            for _, d in ipairs(Workspace:GetDescendants()) do
                if isPart(d) then applyX(d) end
            end
            if xray_addedConn then xray_addedConn:Disconnect() end
            xray_addedConn = Workspace.DescendantAdded:Connect(function(d)
                if STATE.xray_on and isPart(d) then applyX(d) end
            end)
        elseif (not on) and STATE.xray_on then
            STATE.xray_on = false
            if xray_addedConn then xray_addedConn:Disconnect(); xray_addedConn = nil end
            restoreX()
        end
    end

    local function updateXrayIntensity(v) -- 0..1
        STATE.xray_amt = v
        if STATE.xray_on then
            for p, original in pairs(xray_prev) do
                if p then
                    p.LocalTransparencyModifier = math.max(original or 0, STATE.xray_amt)
                end
            end
        end
    end

    ----------------------------------------------------------------
    -- Ghost Player (local: transparency + highlight with chosen color)
    local ghost_prev = setmetatable({}, { __mode = "k" })
    local ghost_descConn, ghost_spawnConn
    local ghostHL

    local function isPart(o) return o and o:IsA("BasePart") end

    local function ensureHighlight(char)
        if ghostHL and ghostHL.Parent ~= char then ghostHL:Destroy(); ghostHL = nil end
        if not ghostHL then
            ghostHL = Instance.new("Highlight")
            ghostHL.Name = "Sorin_GhostHL"
            ghostHL.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            ghostHL.FillTransparency = 0.25
            ghostHL.OutlineTransparency = 1
            ghostHL.FillColor = STATE.ghost_col
            ghostHL.Parent = char
        end
    end

    local function ghostApplyOn(char)
        for _, d in ipairs(char:GetDescendants()) do
            if isPart(d) then
                if ghost_prev[d] == nil then ghost_prev[d] = d.LocalTransparencyModifier end
                d.LocalTransparencyModifier = math.max(d.LocalTransparencyModifier, STATE.ghost_amt)
            end
        end
        ensureHighlight(char)
    end

    local function ghostRestore()
        for p, prev in pairs(ghost_prev) do
            if p then pcall(function() p.LocalTransparencyModifier = prev end) end
            ghost_prev[p] = nil
        end
        if ghostHL then ghostHL:Destroy(); ghostHL = nil end
    end

    local function setGhost(on)
        if on and not STATE.ghost_on then
            STATE.ghost_on = true
            local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
            ghostApplyOn(char)

            if ghost_descConn then ghost_descConn:Disconnect() end
            ghost_descConn = char.DescendantAdded:Connect(function(d)
                if STATE.ghost_on and isPart(d) then
                    if ghost_prev[d] == nil then ghost_prev[d] = d.LocalTransparencyModifier end
                    d.LocalTransparencyModifier = math.max(d.LocalTransparencyModifier, STATE.ghost_amt)
                end
            end)

            if ghost_spawnConn then ghost_spawnConn:Disconnect() end
            ghost_spawnConn = LocalPlayer.CharacterAdded:Connect(function(newChar)
                ghostRestore()
                ghostApplyOn(newChar)
                if ghost_descConn then ghost_descConn:Disconnect() end
                ghost_descConn = newChar.DescendantAdded:Connect(function(d)
                    if STATE.ghost_on and isPart(d) then
                        if ghost_prev[d] == nil then ghost_prev[d] = d.LocalTransparencyModifier end
                        d.LocalTransparencyModifier = math.max(d.LocalTransparencyModifier, STATE.ghost_amt)
                    end
                end)
            end)
        elseif (not on) and STATE.ghost_on then
            STATE.ghost_on = false
            if ghost_descConn then ghost_descConn:Disconnect(); ghost_descConn = nil end
            if ghost_spawnConn then ghost_spawnConn:Disconnect(); ghost_spawnConn = nil end
            ghostRestore()
        end
    end

    local function setGhostColor(c)
        STATE.ghost_col = c
        if ghostHL then ghostHL.FillColor = c end
    end

    local function setGhostAlpha(a) -- 0..1
        STATE.ghost_amt = a
        if STATE.ghost_on and LocalPlayer.Character then
            ghostApplyOn(LocalPlayer.Character) -- re-apply current amount
            if ghostHL then
                ghostHL.FillTransparency = math.clamp(a * 0.7, 0.1, 0.85)
            end
        end
    end

    ----------------------------------------------------------------
    -- UI
    tab:AddSection({ Name = "Graphics" })

    -- Fullbright
    tab:AddToggle({
        Name = "Fullbright (natural, no flicker)",
        Default = false, Save = true, Flag = "gfx_fullbright",
        Callback = setFullbright
    })
    tab:AddSlider({
        Name = "Fullbright Intensity",
        Min = 0, Max = 100, Increment = 5,
        Default = math.floor(STATE.fb_strength * 100),
        Save = true, Flag = "gfx_fb_strength",
        Callback = function(v)
            STATE.fb_strength = v / 100
            if STATE.fb_on then applyFullbrightValues(STATE.fb_strength) end
        end
    })

    -- X-Ray
    tab:AddToggle({
        Name = "X-Ray (make world slightly see-through)",
        Default = false, Save = true, Flag = "gfx_xray",
        Callback = setXray
    })
    tab:AddSlider({
        Name = "X-Ray Intensity",
        Min = 0, Max = 80, Increment = 5,
        Default = math.floor(STATE.xray_amt * 100),
        ValueName = "%", Save = true, Flag = "gfx_xray_amt",
        Callback = function(v) updateXrayIntensity(v / 100) end
    })

    -- Ghost Player
    tab:AddToggle({
        Name = "Ghost Player (local only)",
        Default = false, Save = true, Flag = "gfx_ghost",
        Callback = setGhost
    })
    tab:AddSlider({
        Name = "Ghost Transparency",
        Min = 10, Max = 95, Increment = 5,
        Default = math.floor(STATE.ghost_amt * 100),
        ValueName = "%", Save = true, Flag = "gfx_ghost_amt",
        Callback = function(v) setGhostAlpha(v / 100) end
    })
    tab:AddColorpicker({
        Name = "Ghost Color",
        Default = STATE.ghost_col, Save = true, Flag = "gfx_ghost_col",
        Callback = setGhostColor
    })

    tab:AddParagraph("Note",
        "All effects are **local**. Fullbright uses ColorCorrection/Bloom for a natural look (no flicker). " ..
        "Ghost applies local transparency to your character and an always-on-top highlight."
    )
end
