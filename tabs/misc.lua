-- tabs/misc.lua
-- Misc utilities for SorinHub (Orion UI)
-- Features: Anti FallDamage (air-cushion), Anti Arrest (blink-away), Anti Taser (anti-ragdoll)

return function(tab, OrionLib)
    ------------------------------------------------------------
    -- Services / Singletons
    ------------------------------------------------------------
    local Players          = game:GetService("Players")
    local RunService       = game:GetService("RunService")
    local UserInputService = game:GetService("UserInputService")
    local Workspace        = game:GetService("Workspace")

    local LP        = Players.LocalPlayer
    local Camera    = Workspace.CurrentCamera

    ------------------------------------------------------------
    -- Hardcoded Settings (no sliders, user sees only toggles)
    ------------------------------------------------------------
    local SETTINGS = {
        -- Anti FallDamage (air-cushion)
        FALL = {
            ENABLED_DEFAULT     = false,
            SEGMENT_DROP        = 12,     -- alle ~12 Studs einen kurzen "Zwischenboden"
            CUSHION_LIFETIME    = 0.12,   -- Sekunden bis das Cushion-Part wieder verschwindet
            PART_SIZE           = Vector3.new(8, 1, 8),
            PART_TRANSPARENCY   = 1,      -- 1 = komplett unsichtbar
            ONLY_WHEN_FAST_DOWN = -14,    -- nur platzieren, wenn Y-Velocity < -14
            START_AFTER_HEIGHT  = 18      -- erst ab ~18 Studs freiem Fall aktiv werden
        },

        -- Anti Arrest (blink away when Police close)
        ARREST = {
            ENABLED_DEFAULT     = false,
            POLICE_TEAM_NAME    = "Police",
            TRIGGER_RADIUS      = 20,     -- Studs: wie nahe darf Police kommen
            BLINK_DISTANCE      = 18,     -- Distanz pro Teleport
            BLINK_JITTER        = 6,      -- +/- Zufall
            COOLDOWN            = 1.25,   -- Sekunden zwischen Blinks
            MAX_ATTEMPTS        = 4       -- Versuche pro Blink, einen freien Platz zu finden
        },

        -- Anti Taser (cancel ragdoll/ko)
        TASER = {
            ENABLED_DEFAULT     = false,
            RESTORE_WALKSPEED   = 16,     -- falls Game WS hart setzt, wir geben Base zurück
            RESTORE_JUMPPOWER   = 50,     -- ggf. an dein Spiel anpassen
            COOLDOWN            = 0.35    -- minimale Zeit zwischen Restores
        }
    }

    ------------------------------------------------------------
    -- Small helpers
    ------------------------------------------------------------
    local function hum()
        local ch = LP.Character
        return ch and ch:FindFirstChildOfClass("Humanoid") or nil
    end
    local function hrp()
        local ch = LP.Character
        return ch and ch:FindFirstChild("HumanoidRootPart") or nil
    end
    local function isSeated(humanoid)
        if not humanoid then return false end
        return humanoid.SeatPart ~= nil
    end
    local function notify(msg, t)
        OrionLib:MakeNotification({ Name = "Misc", Content = msg, Time = t or 3 })
    end

    ------------------------------------------------------------
    -- Anti FallDamage (Air Cushion / “Luftleiter”)
    ------------------------------------------------------------
    local fallConn
    local lastCushionY   = nil
    local accumulatedDrop = 0

    local function makeCushion(atCFrame)
        local p = Instance.new("Part")
        p.Size = SETTINGS.FALL.PART_SIZE
        p.CFrame = atCFrame
        p.Anchored = true
        p.CanCollide = true
        p.CanTouch = false
        p.CanQuery = false
        p.Transparency = SETTINGS.FALL.PART_TRANSPARENCY
        p.Name = "Sorin_AirCushion"
        p.Parent = Workspace
        game:GetService("Debris"):AddItem(p, SETTINGS.FALL.CUSHION_LIFETIME)
    end

    local function startAntiFall()
        if fallConn then fallConn:Disconnect() end
        lastCushionY = nil
        accumulatedDrop = 0

        fallConn = RunService.Heartbeat:Connect(function(dt)
            local H = hum()
            local R = hrp()
            if not (H and R) then return end

            -- echte Fallsituation?
            local vy = R.AssemblyLinearVelocity.Y
            local inFreefall = H:GetState() == Enum.HumanoidStateType.Freefall
            local airborne   = (H.FloorMaterial == Enum.Material.Air)

            if not (inFreefall and airborne and vy < SETTINGS.FALL.ONLY_WHEN_FAST_DOWN) then
                -- Reset, wenn wir wieder stehen/gleiten/springen etc.
                lastCushionY = nil
                accumulatedDrop = 0
                return
            end

            -- ab bestimmter Höhe erst aktiv werden (gegen Jump/kleine Hüpfer)
            if not lastCushionY then
                -- Prüfe, ob unter uns genug "leerer Raum" ist; wenn ja, initiiere Kaskade
                local rayParams = RaycastParams.new()
                rayParams.FilterType = Enum.RaycastFilterType.Exclude
                rayParams.FilterDescendantsInstances = { LP.Character }

                local ray = Workspace:Raycast(R.Position, Vector3.new(0, -SETTINGS.FALL.START_AFTER_HEIGHT - 2, 0), rayParams)
                if ray == nil then
                    -- Unter uns ist locker mehr als START_AFTER_HEIGHT Luft → initialisieren
                    lastCushionY = R.Position.Y
                    accumulatedDrop = 0
                else
                    -- Boden ist näher als START_AFTER_HEIGHT -> nix tun
                    return
                end
            end

            -- wie weit sind wir seit dem letzten Punkt gefallen?
            local dropNow = math.max(0, (lastCushionY - R.Position.Y))
            accumulatedDrop = accumulatedDrop + dropNow
            lastCushionY = R.Position.Y

            if accumulatedDrop >= SETTINGS.FALL.SEGMENT_DROP then
                -- Cushion knapp unter der Hüfte setzen: so "landen" wir taktisch
                local targetY = R.Position.Y - (H.HipHeight + 1.5)
                local placeCF = CFrame.new(R.Position.X, targetY, R.Position.Z)
                makeCushion(placeCF)
                accumulatedDrop = 0
            end
        end)
    end
    local function stopAntiFall()
        if fallConn then fallConn:Disconnect(); fallConn = nil end
        lastCushionY = nil
        accumulatedDrop = 0
    end

    ------------------------------------------------------------
    -- Anti Arrest (blink away from Police)
    ------------------------------------------------------------
    local arrestConn
    local lastBlink = 0

    local function isPolice(plr)
        return plr and plr.Team and plr.Team.Name == SETTINGS.ARREST.POLICE_TEAM_NAME
    end

    local function blinkAway()
        local R = hrp()
        local H = hum()
        if not (R and H) then return end
        if isSeated(H) then return end

        -- Finde horizontale Richtung "weg von nahestem Police"
        local myPos = R.Position
        local closest, closestDist, closestDir = nil, math.huge, nil

        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LP and isPolice(p) and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
                local pos = p.Character.HumanoidRootPart.Position
                local d = (pos - myPos)
                local dist = d.Magnitude
                if dist < closestDist then
                    closestDist = dist
                    closest = p
                    closestDir = (myPos - pos) * Vector3.new(1,0,1)  -- horizontal weg
                end
            end
        end

        if not closest or closestDist == math.huge then return end

        -- kleine Zufallsvariante, um nicht immer exakt gleich zu blinken
        local base = SETTINGS.ARREST.BLINK_DISTANCE
        local jitter = SETTINGS.ARREST.BLINK_JITTER
        local step = base + (math.random(-jitter, jitter))

        local dir = (closestDir.Magnitude > 0.1) and closestDir.Unit or Vector3.new(1,0,0)
        local success = false
        for _ = 1, SETTINGS.ARREST.MAX_ATTEMPTS do
            local offset = dir * step
            local newPos = myPos + offset + Vector3.new(0, 2.5, 0) -- leicht anheben
            -- simple ground check (ray nach unten, um “Boden” zu finden)
            local params = RaycastParams.new()
            params.FilterType = Enum.RaycastFilterType.Exclude
            params.FilterDescendantsInstances = { LP.Character }

            local probe = Workspace:Raycast(newPos, Vector3.new(0, -30, 0), params)
            if probe then
                local land = probe.Position + Vector3.new(0, H.HipHeight + 1.0, 0)
                LP.Character:PivotTo(CFrame.new(land, land + Camera.CFrame.LookVector))
                success = true
                break
            else
                -- leicht drehen und nochmal probieren
                dir = CFrame.fromAxisAngle(Vector3.new(0,1,0), math.rad(45)) * dir
                dir = Vector3.new(dir.X, 0, dir.Z).Unit
            end
        end

        if success then
            lastBlink = tick()
        end
    end

    local function startAntiArrest()
        if arrestConn then arrestConn:Disconnect() end
        lastBlink = 0
        arrestConn = RunService.Heartbeat:Connect(function()
            local R = hrp()
            local H = hum()
            if not (R and H) then return end
            if isSeated(H) then return end

            -- Ist Police innerhalb Trigger-Radius?
            local myPos = R.Position
            local danger = false
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= LP and isPolice(p) and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
                    local dist = (p.Character.HumanoidRootPart.Position - myPos).Magnitude
                    if dist <= SETTINGS.ARREST.TRIGGER_RADIUS then
                        danger = true
                        break
                    end
                end
            end

            if danger and (tick() - lastBlink) >= SETTINGS.ARREST.COOLDOWN then
                blinkAway()
            end
        end)
    end
    local function stopAntiArrest()
        if arrestConn then arrestConn:Disconnect(); arrestConn = nil end
    end

    ------------------------------------------------------------
    -- Anti Taser (cancel ragdoll/ko/platformstand)
    ------------------------------------------------------------
    local taserConnA, taserConnB
    local lastRestore = 0

    local function restoreHum()
        local H = hum()
        if not H then return end
        if (tick() - lastRestore) < SETTINGS.TASER.COOLDOWN then return end
        lastRestore = tick()
        -- Harte Resets – je nach Spiel ggf. anpassen
        pcall(function() H.PlatformStand = false end)
        pcall(function() H.Sit = false end)
        pcall(function() H:ChangeState(Enum.HumanoidStateType.GettingUp) end)
        pcall(function() H:ChangeState(Enum.HumanoidStateType.Running) end)
        pcall(function()
            if H.WalkSpeed < 1 then H.WalkSpeed = SETTINGS.TASER.RESTORE_WALKSPEED end
            if H.JumpPower < 5 then H.JumpPower = SETTINGS.TASER.RESTORE_JUMPPOWER end
        end)
    end

    local function startAntiTaser()
        -- StateChanged + PlatformStand listener
        local H = hum()
        if not H then
            -- warte bis Charakter spawnt
            local spawned
            spawned = LP.CharacterAdded:Connect(function()
                spawned:Disconnect()
                startAntiTaser()
            end)
            return
        end
        -- redundante Listener (robuster gegen Game-spezifische KO-Zustände)
        taserConnA = H.StateChanged:Connect(function(old, new)
            if new == Enum.HumanoidStateType.Ragdoll
            or new == Enum.HumanoidStateType.FallingDown
            or new == Enum.HumanoidStateType.Physics
            or new == Enum.HumanoidStateType.StrafingNoPhysics
            or new == Enum.HumanoidStateType.Seated -- einige Spiele "setzen" kurz
            then
                restoreHum()
            end
        end)
        taserConnB = H:GetPropertyChangedSignal("PlatformStand"):Connect(function()
            if H.PlatformStand then
                restoreHum()
            end
        end)
    end
    local function stopAntiTaser()
        if taserConnA then taserConnA:Disconnect(); taserConnA = nil end
        if taserConnB then taserConnB:Disconnect(); taserConnB = nil end
    end

    ------------------------------------------------------------
    -- UI (Orion) – simple toggles
    ------------------------------------------------------------
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

            local H = hum()
            if H then
                H.Health = 0
                notify("Respawn requested (inventory cleared).", 3)
            else
                notify("No humanoid found; try rejoining if respawn fails.", 4)
            end
        end
    })

    tab:AddSection({ Name = "Protections" })

    tab:AddToggle({
        Name = "Anti FallDamage (Air Cushion)",
        Default = SETTINGS.FALL.ENABLED_DEFAULT,
        Callback = function(on)
            if on then startAntiFall() else stopAntiFall() end
        end
    })

    tab:AddToggle({
        Name = "Anti Arrest (Police proximity blink)",
        Default = SETTINGS.ARREST.ENABLED_DEFAULT,
        Callback = function(on)
            if on then startAntiArrest() else stopAntiArrest() end
        end
    })

    tab:AddToggle({
        Name = "Anti Taser (cancel ragdoll/ko)",
        Default = SETTINGS.TASER.ENABLED_DEFAULT,
        Callback = function(on)
            if on then startAntiTaser() else stopAntiTaser() end
        end
    })

    ------------------------------------------------------------
    -- Cleanup on character respawn (auto re-arm toggles)
    ------------------------------------------------------------
    local function rearmActive()
        -- Diese Toggles sind nur zur Laufzeit; falls du persistieren willst,
        -- kannst du Flags speichern. Hier: falls Toggle aktiv, erneut starten.
        -- (Orion speichert Default nicht automatisch → bewusst einfach gehalten)
    end

    LP.CharacterRemoving:Connect(function()
        stopAntiFall()
        stopAntiArrest()
        stopAntiTaser()
    end)

    LP.CharacterAdded:Connect(function()
        -- kurze Verzögerung bis Humanoid/HRP sicher existieren
        task.wait(0.25)
        rearmActive()
    end)
end
