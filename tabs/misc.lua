-- tabs/misc.lua
-- Misc features for SorinHub

return function(tab, OrionLib)
    ----------------------------------------------------------------
    -- Services
    ----------------------------------------------------------------
    local Players     = game:GetService("Players")
    local RunService  = game:GetService("RunService")
    local Workspace   = game:GetService("Workspace")
    local LP          = Players.LocalPlayer

    ----------------------------------------------------------------
    -- State
    ----------------------------------------------------------------
    local state = {
        -- Anti Fall
        antiFallEnabled   = false,
        fall_probeDist    = 12,   -- ab dieser Bodennähe eingreifen (Studs)
        fall_maxStep      = 2.5,  -- maximale Abwärtsbewegung je Frame
        fall_safeOffset   = 2.5,  -- über Boden "auflanden"

        -- Anti Arrest
        antiArrestEnabled = false,
        arrest_radius     = 12,   -- Distanz Polizist -> Spieler
        arrest_teleport   = 15,   -- Teleport-Offset (Studs)

        -- Anti Taser
        antiTaserEnabled  = false,
    }

    ----------------------------------------------------------------
    -- Helpers
    ----------------------------------------------------------------
    local function getHumanoid(char)
        return char and char:FindFirstChildOfClass("Humanoid")
    end
    local function getHRP(char)
        return char and char:FindFirstChild("HumanoidRootPart")
    end

    local function rayDown(origin, dist, ignore)
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = ignore or {}
        local result = Workspace:Raycast(origin, Vector3.new(0, -dist, 0), params)
        if result then
            return result.Position, result.Instance, result.Normal, (origin.Y - result.Position.Y)
        end
        return nil
    end

    ----------------------------------------------------------------
    -- Respawn Button
    ----------------------------------------------------------------
    tab:AddButton({
        Name = "Respawn (lose all weapons/tools)",
        Callback = function()
            local function nukeTools(container)
                if not container then return end
                for _, inst in ipairs(container:GetChildren()) do
                    if inst:IsA("Tool") then
                        pcall(function() inst:Destroy() end)
                    end
                end
            end
            nukeTools(LP:FindFirstChild("Backpack"))
            nukeTools(LP.Character)

            local hum = getHumanoid(LP.Character)
            if hum then
                hum.Health = 0
                OrionLib:MakeNotification({
                    Name = "Utility",
                    Content = "Respawn requested (inventory cleared).",
                    Time = 3
                })
            else
                OrionLib:MakeNotification({
                    Name = "Utility",
                    Content = "No humanoid found; try rejoining if respawn fails.",
                    Time = 4
                })
            end
        end
    })
    tab:AddParagraph("Note", "This forces a respawn and deletes all Tools from your Backpack.")

    ----------------------------------------------------------------
    -- Anti-FallDamage (CFrame Ladder)
    ----------------------------------------------------------------
    local secFall = tab:AddSection({ Name = "Anti Fall Damage" })
    secFall:AddToggle({
        Name = "Enable Anti-FallDamage",
        Default = false,
        Callback = function(v) state.antiFallEnabled = v end
    })
    secFall:AddSlider({
        Name = "Trigger Distance (to ground)",
        Min = 6, Max = 30, Increment = 1, Default = state.fall_probeDist,
        ValueName = "studs",
        Callback = function(v) state.fall_probeDist = math.floor(v) end
    })
    secFall:AddSlider({
        Name = "Max Drop/Frame",
        Min = 1.0, Max = 5.0, Increment = 0.25, Default = state.fall_maxStep,
        ValueName = "studs",
        Callback = function(v) state.fall_maxStep = tonumber(string.format("%.2f", v)) end
    })
    secFall:AddSlider({
        Name = "Safe Offset above ground",
        Min = 1.5, Max = 4.0, Increment = 0.25, Default = state.fall_safeOffset,
        ValueName = "studs",
        Callback = function(v) state.fall_safeOffset = tonumber(string.format("%.2f", v)) end
    })

    local function fallTick(dt)
        if not state.antiFallEnabled then return end
        local char = LP.Character
        local hum  = getHumanoid(char)
        local hrp  = getHRP(char)
        if not (hum and hrp) then return end

        local st = hum:GetState()
        if st ~= Enum.HumanoidStateType.Freefall and st ~= Enum.HumanoidStateType.FallingDown then
            return
        end

        local hitPos, _, _, dist = rayDown(hrp.Position, math.max(6, state.fall_probeDist + 8), {char})
        if not hitPos then return end

        local gap = (hrp.Position.Y - hitPos.Y)
        if gap <= state.fall_probeDist then
            local targetY = hitPos.Y + state.fall_safeOffset
            if hrp.Position.Y - targetY > 0 then
                local step = math.min(state.fall_maxStep, hrp.Position.Y - targetY)
                local pos = hrp.Position
                hrp.CFrame = CFrame.new(pos.X, pos.Y - step, pos.Z, hrp.CFrame:components())
                if (hrp.Position.Y - targetY) <= 0.6 then
                    pcall(function() hum:ChangeState(Enum.HumanoidStateType.Landed) end)
                end
            end
        end
    end

    ----------------------------------------------------------------
    -- Anti-Arrest
    ----------------------------------------------------------------
    local secArrest = tab:AddSection({ Name = "Anti Arrest" })
    secArrest:AddToggle({
        Name = "Enable Anti-Arrest",
        Default = false,
        Callback = function(v) state.antiArrestEnabled = v end
    })
    secArrest:AddSlider({
        Name = "Detect Radius",
        Min = 6, Max = 25, Increment = 1, Default = state.arrest_radius,
        ValueName = "studs",
        Callback = function(v) state.arrest_radius = math.floor(v) end
    })
    secArrest:AddSlider({
        Name = "Teleport Offset",
        Min = 10, Max = 30, Increment = 1, Default = state.arrest_teleport,
        ValueName = "studs",
        Callback = function(v) state.arrest_teleport = math.floor(v) end
    })

    local function arrestTick(dt)
        if not state.antiArrestEnabled then return end
        local char = LP.Character
        local hrp  = getHRP(char)
        if not hrp then return end

        for _,plr in ipairs(Players:GetPlayers()) do
            if plr ~= LP and plr.Team and plr.Team.Name == "Police" then
                local phrp = getHRP(plr.Character)
                if phrp then
                    local dist = (phrp.Position - hrp.Position).Magnitude
                    if dist <= state.arrest_radius then
                        local offset = Vector3.new(
                            (math.random() > 0.5 and 1 or -1) * state.arrest_teleport,
                            0,
                            (math.random() > 0.5 and 1 or -1) * state.arrest_teleport
                        )
                        hrp.CFrame = hrp.CFrame + offset
                        OrionLib:MakeNotification({
                            Name = "Anti-Arrest",
                            Content = "Teleported away from nearby Police.",
                            Time = 2
                        })
                        break
                    end
                end
            end
        end
    end

    ----------------------------------------------------------------
    -- Anti-Taser
    ----------------------------------------------------------------
    local secTaser = tab:AddSection({ Name = "Anti Taser" })
    secTaser:AddToggle({
        Name = "Enable Anti-Taser",
        Default = false,
        Callback = function(v) state.antiTaserEnabled = v end
    })

    local function taserTick(dt)
        if not state.antiTaserEnabled then return end
        local hum = getHumanoid(LP.Character)
        if hum then
            if hum.PlatformStand then
                hum.PlatformStand = false
            end
            if hum.Sit then
                hum.Sit = false
            end
        end
    end

    ----------------------------------------------------------------
    -- Heartbeat Loop
    ----------------------------------------------------------------
    RunService.Heartbeat:Connect(function(dt)
        fallTick(dt)
        arrestTick(dt)
        taserTick(dt)
    end)
end
