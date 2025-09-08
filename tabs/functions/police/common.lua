-- tabs/functions/police/common.lua
return function(tab, OrionLib)
    local Players = game:GetService("Players")
    local RS      = game:GetService("ReplicatedStorage")
    local Run     = game:GetService("RunService")

    local LP      = Players.LocalPlayer
    local Bnl     = RS:WaitForChild("Bnl")

    local SV = {}

    -- ===== UI Notify Wrapper (nutzt ggf. dein OrionLib.Notify)
    function SV.notify(title, text, time)
        if OrionLib and OrionLib.MakeNotification then
            OrionLib:MakeNotification({ Name = title or "Info", Content = text or "", Time = time or 2 })
        else
            print(("[Police] %s: %s"):format(title or "Info", text or ""))
        end
    end

    -- ===== Player/Char/HRP
    SV.LP = LP
    function SV.hrp()
        local ch = LP.Character or LP.CharacterAdded:Wait()
        return ch:FindFirstChild("HumanoidRootPart")
    end

    -- ===== Radar-Remote (UUID bei Bedarf anpassbar / konfigurierbar)
    SV.RADAR_REMOTE_ID = "bbb7c252-304d-4582-b2a0-89eb9d3a0855"
    function SV.radarRemote()
        return Bnl:FindFirstChild(SV.RADAR_REMOTE_ID)
    end

    -- ===== Vehicles-Liste
    function SV.vehiclesFolder()
        return workspace:FindFirstChild("Vehicles")
    end

    -- ===== PrimaryPart-Absicherung
    function SV.ensurePrimaryPart(model)
        if not model or model.PrimaryPart then return model and model.PrimaryPart end
        -- Versuch: DriveSeat oder erstes BasePart nehmen
        local seat = model:FindFirstChildWhichIsA("BasePart", true)
        if seat then model.PrimaryPart = seat return seat end
        return nil
    end

    -- ===== Geschwindigkeit (Studs/s)
    function SV.getSpeed(model)
        local pp = model and (model.PrimaryPart or SV.ensurePrimaryPart(model))
        if not pp then return 0 end
        return pp.AssemblyLinearVelocity.Magnitude
    end

    -- ===== Richtung vom Spieler zu einem Punkt
    function SV.dirFromPlayer(targetPos)
        local hrp = SV.hrp(); if not hrp then return Vector3.new(0,0,1) end
        local dir = (targetPos - hrp.Position)
        if dir.Magnitude < 1e-6 then return Vector3.new(0,0,1) end
        return dir.Unit
    end

    -- ===== einfache FOV/Dist-Prüfung
    function SV.inFOVAndRange(targetPos, maxDist, maxFOVDeg)
        local hrp = SV.hrp(); if not hrp then return false end
        local cam = workspace.CurrentCamera
        local toT = (targetPos - cam.CFrame.Position)
        local dist = toT.Magnitude
        if dist > (maxDist or 500) then return false end
        local angle = math.deg(math.acos(math.clamp(cam.CFrame.LookVector:Dot(toT.Unit), -1, 1)))
        return angle <= (maxFOVDeg or 60)
    end

    -- ===== LOS (Raycast) optional
    function SV.hasLineOfSight(fromPos, toPos, blacklist)
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Blacklist
        params.FilterDescendantsInstances = blacklist or {}
        local hit = workspace:Raycast(fromPos, (toPos-fromPos), params)
        if not hit then return true end
        -- LOS zählt als frei, wenn der erste Treffer sehr nahe am Ziel ist
        return (toPos - hit.Position).Magnitude < 5
    end

    -- ===== Ticker
    function SV.every(dt, fn)
        local acc = 0
        return Run.Heartbeat:Connect(function(step)
            acc += step
            if acc >= dt then
                acc = 0
                pcall(fn)
            end
        end)
    end

    return SV
end
