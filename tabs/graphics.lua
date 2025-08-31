-- tabs/graphics.lua
-- Graphics tab for SorinHub (local-only visuals)
-- Features: Fullbright, X-Ray (world), Ghost Player (self only)

return function(tab, OrionLib)
    ----------------------------------------------------------------
    -- Services
    local Players    = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local Workspace  = game:GetService("Workspace")
    local Lighting   = game:GetService("Lighting")

    local LocalPlayer = Players.LocalPlayer

    ----------------------------------------------------------------
    -- State
    local STATE = {
        fullbright = false,
        xray       = false,
        ghost      = false,
        xrayAmount = 0.4,  -- wie „ein wenig transparent“
        ghostAmt   = 0.55, -- Ghost Player Transparenz
    }

    ----------------------------------------------------------------
    -- Helpers
    local function isPart(o) return o and o:IsA("BasePart") end

    ----------------------------------------------------------------
    -- FULLBRIGHT
    local fb_conn
    local origLight -- speichern originale Lighting-Werte

    local function applyFullbright()
        -- Wird pro Frame erzwungen, solange aktiv
        if not STATE.fullbright then return end
        pcall(function()
            Lighting.Brightness = 2
            Lighting.ClockTime  = 12 -- „mittags“
            Lighting.FogEnd     = 1e6
            Lighting.Ambient    = Color3.fromRGB(255,255,255)
            Lighting.ExposureCompensation = 0.5
        end)
    end

    local function setFullbright(on)
        if on and not STATE.fullbright then
            STATE.fullbright = true
            -- Originale einmal sichern
            origLight = origLight or {
                Brightness = Lighting.Brightness,
                ClockTime  = Lighting.ClockTime,
                FogEnd     = Lighting.FogEnd,
                Ambient    = Lighting.Ambient,
                Exposure   = Lighting.ExposureCompensation,
            }
            applyFullbright()
            if fb_conn then fb_conn:Disconnect() end
            fb_conn = RunService.Stepped:Connect(applyFullbright)
        elseif (not on) and STATE.fullbright then
            STATE.fullbright = false
            if fb_conn then fb_conn:Disconnect(); fb_conn = nil end
            if origLight then
                pcall(function()
                    Lighting.Brightness = origLight.Brightness
                    Lighting.ClockTime  = origLight.ClockTime
                    Lighting.FogEnd     = origLight.FogEnd
                    Lighting.Ambient    = origLight.Ambient
                    Lighting.ExposureCompensation = origLight.Exposure
                end)
            end
        end
    end

    ----------------------------------------------------------------
    -- X-RAY (map leicht transparent, Spielercharakter ausgenommen)
    local xray_prev = setmetatable({}, {__mode = "k"}) -- part -> prev LTM
    local xray_addedConn

    local function skipForXray(obj)
        if not isPart(obj) then return true end
        -- eigenen Character bewusst auslassen, damit „Ghost“ nicht kollidiert
        if LocalPlayer and LocalPlayer.Character and obj:IsDescendantOf(LocalPlayer.Character) then
            return true
        end
        return false
    end

    local function applyXrayTo(part)
        if skipForXray(part) or xray_prev[part] ~= nil then return end
        xray_prev[part] = part.LocalTransparencyModifier
        part.LocalTransparencyModifier = math.max(part.LocalTransparencyModifier, STATE.xrayAmount)
    end

    local function restoreXray()
        for part, prev in pairs(xray_prev) do
            if part then
                pcall(function()
                    part.LocalTransparencyModifier = prev
                end)
            end
            xray_prev[part] = nil
        end
    end

    local function setXray(on)
        if on and not STATE.xray then
            STATE.xray = true
            -- gesamte Map einmalig anwenden
            for _,d in ipairs(Workspace:GetDescendants()) do
                if isPart(d) then applyXrayTo(d) end
            end
            -- neue Parts live nachziehen
            if xray_addedConn then xray_addedConn:Disconnect() end
            xray_addedConn = Workspace.DescendantAdded:Connect(function(d)
                if STATE.xray and isPart(d) then
                    applyXrayTo(d)
                end
            end)
        elseif (not on) and STATE.xray then
            STATE.xray = false
            if xray_addedConn then xray_addedConn:Disconnect(); xray_addedConn = nil end
            restoreXray()
        end
    end

    ----------------------------------------------------------------
    -- GHOST PLAYER (nur lokal für dich)
    local ghost_prev  = setmetatable({}, {__mode = "k"}) -- part -> prev LTM
    local ghost_connDesc, ghost_connSpawn

    local function ghostApplyOn(char)
        for _,d in ipairs(char:GetDescendants()) do
            if isPart(d) then
                if ghost_prev[d] == nil then
                    ghost_prev[d] = d.LocalTransparencyModifier
                end
                d.LocalTransparencyModifier = math.max(d.LocalTransparencyModifier, STATE.ghostAmt)
            end
        end
    end

    local function ghostRestore()
        for part, prev in pairs(ghost_prev) do
            if part then
                pcall(function()
                    part.LocalTransparencyModifier = prev
                end)
            end
            ghost_prev[part] = nil
        end
    end

    local function setGhost(on)
        if on and not STATE.ghost then
            STATE.ghost = true
            local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
            ghostApplyOn(char)

            if ghost_connDesc then ghost_connDesc:Disconnect() end
            ghost_connDesc = char.DescendantAdded:Connect(function(d)
                if STATE.ghost and isPart(d) then
                    if not d:IsDescendantOf(LocalPlayer.Character) then return end
                    if ghost_prev[d] == nil then ghost_prev[d] = d.LocalTransparencyModifier end
                    d.LocalTransparencyModifier = math.max(d.LocalTransparencyModifier, STATE.ghostAmt)
                end
            end)

            if ghost_connSpawn then ghost_connSpawn:Disconnect() end
            ghost_connSpawn = LocalPlayer.CharacterAdded:Connect(function(newChar)
                ghost_prev = setmetatable({}, {__mode="k"})
                ghostApplyOn(newChar)
                if ghost_connDesc then ghost_connDesc:Disconnect() end
                ghost_connDesc = newChar.DescendantAdded:Connect(function(d)
                    if STATE.ghost and isPart(d) then
                        if ghost_prev[d] == nil then ghost_prev[d] = d.LocalTransparencyModifier end
                        d.LocalTransparencyModifier = math.max(d.LocalTransparencyModifier, STATE.ghostAmt)
                    end
                end)
            end)
        elseif (not on) and STATE.ghost then
            STATE.ghost = false
            if ghost_connDesc  then ghost_connDesc:Disconnect();  ghost_connDesc  = nil end
            if ghost_connSpawn then ghost_connSpawn:Disconnect(); ghost_connSpawn = nil end
            ghostRestore()
        end
    end

    ----------------------------------------------------------------
    -- UI
    tab:AddSection({ Name = "Graphics" })

    tab:AddToggle({
        Name = "Brightness (Always Bright)",
        Default = false, Save = true, Flag = "gfx_fullbright",
        Callback = setFullbright
    })

    tab:AddToggle({
        Name = "X-Ray (make world slightly transparent)",
        Default = false, Save = true, Flag = "gfx_xray",
        Callback = setXray
    })

    tab:AddToggle({
        Name = "Ghost Player (local only)",
        Default = false, Save = true, Flag = "gfx_ghost",
        Callback = setGhost
    })

    -- (Optional) kurzer Hinweis
    tab:AddParagraph("Hinweis",
        "Alle Effekte sind **lokal** und sollten serverseitig nichts beeinflussen. " ..
        "X-Ray wirkt nicht auf deinen eigenen Charakter, damit es sich nicht mit Ghost überschneidet."
    )
end
