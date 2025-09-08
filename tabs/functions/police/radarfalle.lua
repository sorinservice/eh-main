-- tabs/functions/police/radarfalle.lua
return function(SV, tab, OrionLib)
    -- Version: 1.0.0 (Auto-Radar)

    local RunService = game:GetService("RunService")
    local Players    = game:GetService("Players")
    local LP         = Players.LocalPlayer

    local REMOTE = SV.radarRemote()
    if not REMOTE then
        SV.notify("Radar", "Remote nicht gefunden (Bnl/"..tostring(SV.RADAR_REMOTE_ID)..")", 4)
        return
    end

    local cfg = {
        enabled       = false,
        requireTool   = false,      -- wenn true: prüfe, ob RadarGun ausgerüstet; sonst Dummy-Tool
        useLOS        = true,       -- Line-of-sight prüfen
        maxDistance   = 450,        -- Reichweite
        maxFOVDeg     = 70,         -- Sichtkegel
        minSpeed      = 60,         -- Mindestgeschwindigkeit in Studs/s
        fireInterval  = 0.60,       -- Mindestabstand zwischen Schüssen
        targetCooldown= 2.50,       -- pro Ziel Cooldown
    }

    local lastFireAt = 0
    local cooldownPerTarget = {} -- [model] = tUntil

    local function now() return os.clock() end

    local function haveRadarTool()
        local ch = LP.Character
        if not ch then return false end
        local hum = ch:FindFirstChildOfClass("Humanoid")
        if not hum then return false end
        local tool = hum:FindFirstChildWhichIsA("Tool")
        if not tool then return false end
        -- optional: tool.Name prüfen (z.B. "RadarGun")
        return true
    end

    local function closestSpeedingVehicle()
        local vf = SV.vehiclesFolder()
        if not vf then return nil end
        local hrp = SV.hrp()
        if not hrp then return nil end

        local best, bestDist = nil, 1e9
        for _,v in ipairs(vf:GetChildren()) do
            -- eigenes Auto optional ausklammern (falls gewünscht)
            -- if v.Name == LP.Name then continue end
            local pp = v.PrimaryPart or SV.ensurePrimaryPart(v)
            if not pp then continue end

            -- Speed-Filter
            local spd = SV.getSpeed(v)
            if spd < cfg.minSpeed then continue end

            -- Dist/FOV
            local pos = pp.Position
            if not SV.inFOVAndRange(pos, cfg.maxDistance, cfg.maxFOVDeg) then continue end

            -- LOS
            if cfg.useLOS and not SV.hasLineOfSight(workspace.CurrentCamera.CFrame.Position, pos, {v, LP.Character}) then
                continue
            end

            -- eigener Ziel-Cooldown
            local freeAt = cooldownPerTarget[v]
            if freeAt and freeAt > now() then
                continue
            end

            local d = (pos - hrp.Position).Magnitude
            if d < bestDist then
                best, bestDist = v, d
            end
        end
        return best
    end

    local function fireRadarAtVehicle(v)
        if not v then return end
        local pp = v.PrimaryPart or SV.ensurePrimaryPart(v)
        if not pp then return end

        -- Tool-Arg:
        local toolArg
        if cfg.requireTool then
            -- echte Ausrüstung (wenn vorhanden), sonst Abbruch
            if not haveRadarTool() then return end
            -- Server erwartet erfahrungsgemäß irgendein Tool-Objekt; hier NOP:
            toolArg = Instance.new("Tool")
        else
            -- Dummy genügt in deinem Protokoll
            toolArg = Instance.new("Tool")
        end

        local targetPos = pp.Position
        local dir       = SV.dirFromPlayer(targetPos)

        -- throttle global
        if (now() - lastFireAt) < cfg.fireInterval then return end
        lastFireAt = now()

        -- fire
        local ok, err = pcall(function()
            REMOTE:FireServer(toolArg, targetPos, dir)
        end)
        if not ok then
            SV.notify("Radar", "FireServer-Fehler: "..tostring(err), 2)
            return
        end

        -- Ziel-Cooldown setzen
        cooldownPerTarget[v] = now() + cfg.targetCooldown
    end

    -- Scanner-Loop
    local loopConn = nil
    local function setEnabled(on)
        if on == cfg.enabled then return end
        cfg.enabled = on
        if on then
            if loopConn then loopConn:Disconnect() end
            local acc = 0
            loopConn = RunService.Heartbeat:Connect(function(dt)
                acc += dt
                -- leichte Sampling-Rate (z. B. alle 0.10s wählen wir Ziel, Fire selbst durch fireInterval gedrosselt)
                if acc >= 0.10 then
                    acc = 0
                    local target = closestSpeedingVehicle()
                    if target then fireRadarAtVehicle(target) end
                end
            end)
            SV.notify("Radar", "Auto-Radar aktiviert.", 1.2)
        else
            if loopConn then loopConn:Disconnect(); loopConn=nil end
            SV.notify("Radar", "Auto-Radar deaktiviert.", 1.2)
        end
    end

    -- ==== UI ====
    local sec = tab:AddSection({ Name = "Radarfalle" })
    local toggle = sec:AddToggle({
        Name = "Auto-Radar aktivieren",
        Default = false,
        Callback = function(v) setEnabled(v) end
    })
    sec:AddBind({
        Name = "Toggle Key",
        Default = Enum.KeyCode.R,
        Hold = false,
        Callback = function() toggle:Set(not cfg.enabled) setEnabled(not cfg.enabled) end
    })

    sec:AddSlider({
        Name = "Mindestgeschwindigkeit (Studs/s)",
        Min = 20, Max = 300, Increment = 5, Default = cfg.minSpeed,
        Callback = function(v) cfg.minSpeed = math.floor(v) end
    })
    sec:AddSlider({
        Name = "Max Distanz",
        Min = 100, Max = 800, Increment = 10, Default = cfg.maxDistance,
        Callback = function(v) cfg.maxDistance = math.floor(v) end
    })
    sec:AddSlider({
        Name = "FOV (Grad)",
        Min = 20, Max = 120, Increment = 1, Default = cfg.maxFOVDeg,
        Callback = function(v) cfg.maxFOVDeg = math.floor(v) end
    })
    sec:AddSlider({
        Name = "Feuer-Intervall (s)",
        Min = 0.2, Max = 2.0, Increment = 0.05, Default = cfg.fireInterval,
        Callback = function(v) cfg.fireInterval = tonumber(string.format("%.2f", v)) end
    })
    sec:AddSlider({
        Name = "Ziel-Cooldown (s)",
        Min = 0.5, Max = 5.0, Increment = 0.1, Default = cfg.targetCooldown,
        Callback = function(v) cfg.targetCooldown = tonumber(string.format("%.1f", v)) end
    })
    sec:AddToggle({
        Name = "Line of Sight prüfen",
        Default = cfg.useLOS,
        Callback = function(v) cfg.useLOS = v end
    })
    sec:AddToggle({
        Name = "Radar-Tool benötigt",
        Default = cfg.requireTool,
        Callback = function(v) cfg.requireTool = v end
    })
    sec:AddButton({
        Name = "Test: nächstes schnelles Fahrzeug blitzen",
        Callback = function()
            local t = closestSpeedingVehicle()
            if t then fireRadarAtVehicle(t) else SV.notify("Radar","Kein schnelles Fahrzeug im Kegel.",1.5) end
        end
    })

    print("[police/radarfalle v1.0.0] loaded (remote="..tostring(SV.RADAR_REMOTE_ID)..")")
end
