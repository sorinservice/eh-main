-- tabs/misc.lua
-- SorinHub - Misc Utilities
-- - Anti Fall Damage (federnd, near-ground soft landing)
-- - Anti Arrest (Police proximity warp, if not seated)
-- - Anti Taser (cancel ragdoll/platform stand quickly)
-- UI: nur EIN/AUS-Toggles. Feintuning in CONFIG unten.

return function(tab, OrionLib)
    ----------------------------------------------------------------
    -- Services
    ----------------------------------------------------------------
    local Players        = game:GetService("Players")
    local RunService     = game:GetService("RunService")
    local Workspace      = game:GetService("Workspace")
    local UserInput      = game:GetService("UserInputService")

    local LP             = Players.LocalPlayer
    local Camera         = Workspace.CurrentCamera

    ----------------------------------------------------------------
    -- CONFIG (nur hier im Code verändern; UI hat nur EIN/AUS)
    ----------------------------------------------------------------
    local CONFIG = {
        AntiFall = {
            RayLengthDown    = 20,   -- wie weit nach unten schauen (Studs)
            TriggerGap       = 8,    -- “nah am Boden” Schwellwert (Studs)
            StepPerFrame     = 2,    -- maximaler Abstiegsschritt je Frame beim Federn
            KillYVelocity    = true, -- Y-Geschwindigkeit kurz vorm Boden nullen
            ForceLandedBelow = 1.5,  -- unterhalb dieses Gaps “Landed” setzen
        },
        AntiArrest = {
            EnabledTeamsOnly   = true,    -- Police vs Citizen Logik nutzen
            PoliceTeamName     = "Police",
            CitizenTeamName    = "Citizen",
            TriggerRadius      = 18,      -- Distanz zu Police, ab der reagiert wird
            TeleportStep       = 12,      -- wie weit wegspringen (horizontal)
            TryAnglesDeg       = {0, 45, -45, 90, -90, 135, -135, 180}, -- Ausweichrichtungen
            GroundCheckDown    = 30,      -- Rays nach unten, um einen sicheren Boden zu finden
            CooldownSeconds    = 2.0,     -- Anti-Spam
        },
        AntiTaser = {
            CooldownSeconds  = 1.25, -- debounce zwischen un-stuns
            ClearConstraints = true, -- versuche Ragdoll-Constraints zu löschen
            ForceGettingUp   = true, -- kurz “GettingUp” state pushen
            ClearPlatform    = true, -- Humanoid.PlatformStand = false
            ClearSit         = true, -- Humanoid.Sit = false
        },
    }

    ----------------------------------------------------------------
    -- interne State/Utils
    ----------------------------------------------------------------
    local antiFallEnabled   = false
    local antiArrestEnabled = false
    local antiTaserEnabled  = false

    local lastArrestWarpAt  = 0
    local lastTaserClearAt  = 0

    local function now()
        return tick()
    end

    local function getCharHumHRP(plr)
        local ch  = plr and plr.Character
        local hum = ch and ch:FindFirstChildOfClass("Humanoid")
        local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
        return ch, hum, hrp
    end

    local function isSeated(hum)
        if not hum then return false end
        if hum.SeatPart then return true end
        -- Fallback: SeatWeld in Character?
        local ch = hum.Parent
        if ch and ch:FindFirstChildWhichIsA("SeatWeld", true) then
            return true
        end
        return false
    end

    local function myTeamName(plr)
        local t = plr and plr.Team
        return t and t.Name or nil
    end

    local function isPolice(plr)
        return myTeamName(plr) == CONFIG.AntiArrest.PoliceTeamName
    end

    local function allowedMatch(me, other)
        if not CONFIG.AntiArrest.EnabledTeamsOnly then return true end
        local mt = myTeamName(me)
        local ot = myTeamName(other)
        if not mt or not ot then return false end
        if mt == ot then return false end
        -- Nur Police <-> Citizen
        local A, B = CONFIG.AntiArrest.PoliceTeamName, CONFIG.AntiArrest.CitizenTeamName
        return (mt == A and ot == B) or (mt == B and ot == A)
    end

    local function safeRay(origin, dir, ignore)
        local rp = RaycastParams.new()
        rp.FilterType = Enum.RaycastFilterType.Exclude
        rp.FilterDescendantsInstances = ignore
        rp.IgnoreWater = true
        return Workspace:Raycast(origin, dir, rp)
    end

    ----------------------------------------------------------------
    -- Anti FallDamage (sanftes “Federn” am Ende)
    ----------------------------------------------------------------
    local function AntiFallTick(dt)
        if not antiFallEnabled then return end
        local ch, hum, hrp = getCharHumHRP(LP)
        if not (ch and hum and hrp) then return end

        if hum:GetState() ~= Enum.HumanoidStateType.Freefall then return end

        -- Boden checken unter HRP
        local res = safeRay(hrp.Position, Vector3.new(0, -CONFIG.AntiFall.RayLengthDown, 0), {ch})
        if not res then return end

        local gap = hrp.Position.Y - res.Position.Y
        if gap <= CONFIG.AntiFall.TriggerGap then
            -- kleine Schritte nach unten -> “federn”
            local step = math.min(CONFIG.AntiFall.StepPerFrame, math.max(0, gap))
            hrp.CFrame = hrp.CFrame - Vector3.new(0, step, 0)

            -- Y-Velocity abklemmen (optional)
            if CONFIG.AntiFall.KillYVelocity then
                pcall(function()
                    hrp.Velocity = Vector3.new(hrp.Velocity.X, 0, hrp.Velocity.Z)
                end)
            end

            -- landed state kurz unterhalb
            if gap <= CONFIG.AntiFall.ForceLandedBelow then
                pcall(function()
                    hum:ChangeState(Enum.HumanoidStateType.Landed)
                end)
            end
        end
    end

    ----------------------------------------------------------------
    -- Anti Arrest (wegsteppen, wenn Police nahe & nicht seated)
    ----------------------------------------------------------------
    local function findNearestPolice(meHRP, maxDist)
        local bestPlr, bestD = nil, math.huge
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LP and isPolice(plr) and allowedMatch(LP, plr) then
                local _, hum, hrp = getCharHumHRP(plr)
                if hum and hrp and hum.Health > 0 then
                    local d = (hrp.Position - meHRP.Position).Magnitude
                    if d < maxDist and d < bestD then
                        bestD = d
                        bestPlr = plr
                    end
                end
            end
        end
        return bestPlr, bestD
    end

    local function tryWarpFrom(originPos, awayDirXZ, step, tries, chToIgnore)
        -- mehrere versetzte Richtungen testen, Boden finden und dort platzieren
        local dirs = CONFIG.AntiArrest.TryAnglesDeg
        for _, ang in ipairs(dirs) do
            local rad = math.rad(ang)
            local dir = CFrame.fromAxisAngle(Vector3.new(0,1,0), rad):VectorToWorldSpace(awayDirXZ)
            dir = Vector3.new(dir.X, 0, dir.Z).Unit

            local tryPos = originPos + dir * step + Vector3.new(0, 1.5, 0)
            -- sicheren Boden suchen
            local hit = safeRay(tryPos, Vector3.new(0, -CONFIG.AntiArrest.GroundCheckDown, 0), {chToIgnore})
            if hit then
                local landPos = hit.Position + Vector3.new(0, 3, 0) -- bisschen Luft
                return landPos
            end
        end
        return nil
    end

    local function AntiArrestTick(dt)
        if not antiArrestEnabled then return end
        local ch, hum, hrp = getCharHumHRP(LP)
        if not (ch and hum and hrp) then return end
        if isSeated(hum) then return end

        -- cooldown
        if now() - lastArrestWarpAt < CONFIG.AntiArrest.CooldownSeconds then return end

        local police, dist = findNearestPolice(hrp, CONFIG.AntiArrest.TriggerRadius)
        if not police then return end

        -- Richtung weg von Police
        local _, phum, phrp = getCharHumHRP(police)
        if not (phum and phrp) then return end

        local away = (hrp.Position - phrp.Position)
        away = Vector3.new(away.X, 0, away.Z)
        if away.Magnitude < 1 then
            -- fallback: nutze Blickrichtung
            away = Camera.CFrame.LookVector
        end
        away = away.Unit

        local targetPos = tryWarpFrom(hrp.Position, away, CONFIG.AntiArrest.TeleportStep, 8, ch)
        if targetPos then
            -- kurzer, kleiner, legitimer Warp
            hrp.CFrame = CFrame.new(targetPos, targetPos + Camera.CFrame.LookVector)
            lastArrestWarpAt = now()
        end
    end

    ----------------------------------------------------------------
    -- Anti Taser (cancel ragdoll/platform stand schnell & vorsichtig)
    ----------------------------------------------------------------
    local badStates = {
        [Enum.HumanoidStateType.Ragdoll]         = true,
        [Enum.HumanoidStateType.FallingDown]     = true,
        [Enum.HumanoidStateType.StrafingNoPhysics]= true,
        [Enum.HumanoidStateType.Physics]         = true,
        [Enum.HumanoidStateType.PlatformStanding]= true,
        -- manche Spiele togglen auch Seated → wir lassen Seated in Ruhe
    }

    local function clearRagdollBits(ch, hum)
        if CONFIG.AntiTaser.ClearConstraints and ch then
            for _, d in ipairs(ch:GetDescendants()) do
                if d:IsA("BallSocketConstraint") or d:IsA("HingeConstraint") or d.Name:lower():find("ragdoll") then
                    pcall(function() d.Enabled = false end)
                end
            end
        end
        if CONFIG.AntiTaser.ClearSit and hum then
            pcall(function() hum.Sit = false end)
        end
        if CONFIG.AntiTaser.ClearPlatform and hum then
            pcall(function() hum.PlatformStand = false end)
        end
        if CONFIG.AntiTaser.ForceGettingUp and hum then
            pcall(function()
                hum:ChangeState(Enum.HumanoidStateType.GettingUp)
            end)
        end
    end

    local function AntiTaserTick(dt)
        if not antiTaserEnabled then return end
        local ch, hum, hrp = getCharHumHRP(LP)
        if not (ch and hum and hrp) then return end

        -- debounce
        if now() - lastTaserClearAt < CONFIG.AntiTaser.CooldownSeconds then return end

        local st = hum:GetState()
        if badStates[st] or hum.PlatformStand then
            lastTaserClearAt = now()
            clearRagdollBits(ch, hum)
            -- leicht “stabilisieren”
            pcall(function()
                hrp.RotVelocity = Vector3.new()
                if math.abs(hrp.Velocity.Y) > 50 then
                    hrp.Velocity = Vector3.new(hrp.Velocity.X, 0, hrp.Velocity.Z)
                end
            end)
        end
    end

    ----------------------------------------------------------------
    -- Heartbeat loop (server-freundlich; keine hohen Prioritäten)
    ----------------------------------------------------------------
    RunService.Heartbeat:Connect(function(dt)
        -- Reihenfolge: erst Taser, dann Arrest, dann Fall – ist egal, aber so logisch.
        AntiTaserTick(dt)
        AntiArrestTick(dt)
        AntiFallTick(dt)
    end)

    ----------------------------------------------------------------
    -- UI (nur Toggles, speichert über Orion Flags automatisch)
    ----------------------------------------------------------------
    tab:AddToggle({
        Name = "Anti Fall Damage",
        Default = false,
        Save = true,
        Flag = "misc_antifall",
        Callback = function(v)
            antiFallEnabled = v
            OrionLib:MakeNotification({
                Name = "Misc",
                Content = "Anti Fall Damage: " .. (v and "ON" or "OFF"),
                Time = 3
            })
        end
    })

    tab:AddToggle({
        Name = "Anti Arrest",
        Default = false,
        Save = true,
        Flag = "misc_antiarrest",
        Callback = function(v)
            antiArrestEnabled = v
            OrionLib:MakeNotification({
                Name = "Misc",
                Content = "Anti Arrest: " .. (v and "ON" or "OFF"),
                Time = 3
            })
        end
    })

    tab:AddToggle({
        Name = "Anti Taser",
        Default = false,
        Save = true,
        Flag = "misc_antitaser",
        Callback = function(v)
            antiTaserEnabled = v
            OrionLib:MakeNotification({
                Name = "Misc",
                Content = "Anti Taser: " .. (v and "ON" or "OFF"),
                Time = 3
            })
        end
    })


    

    tab:AddParagraph("Notes", [[
• Anti FallDamage: federt kurz vor dem Boden mit kleinen CFrame-Schritten; optional killt es Y-Velocity.
• Anti Arrest: warpt dich in kleinen, kollisionsgeprüften Steps weg, wenn Police in Reichweite und du nicht sitzt.
• Anti Taser: bricht Ragdoll/PlatformStand schnell ab (GettingUp, PlatformStand=false, Sit=false).
]])
end
