-- tabs/functions/police/radarfalle.lua
return function(SV, tab, OrionLib)
    -- radar v1.4.0 (first vec = vehicle pos, second vec = look dir, range=1500)

    local RunService = game:GetService("RunService")
    local Players    = game:GetService("Players")
    local LP         = Players.LocalPlayer

    local REMOTE = (function()
        local bnl = game:GetService("ReplicatedStorage"):WaitForChild("Bnl")
        return bnl:WaitForChild("bbb7c252-304d-4582-b2a0-89eb9d3a0855")
    end)()

    local vector = { create = Vector3.new }

    local cfg = {
        enabled       = false,
        MAX_DIST      = 1500,
        TICK          = 0.08,
        PER_TARGET_CD = 0.30,
        GLOBAL_CD     = 0.03,
        MAX_PER_TICK  = 6,
        TOOL_MATCH    = {["Radar"]=true,["RadarGun"]=true,["Radar Gun"]=true},
    }

    local lastGlobal = 0
    local perTarget  = {}

    local function now() return os.clock() end

    local function vehiclesFolder() return workspace:FindFirstChild("Vehicles") end
    local function ensurePP(m)
        if not m then return nil end
        if m.PrimaryPart then return m.PrimaryPart end
        local bp = m:FindFirstChildWhichIsA("BasePart", true)
        if bp then m.PrimaryPart = bp return bp end
        return nil
    end

    local function camLook()
        local c = workspace.CurrentCamera
        local v = c and c.CFrame.LookVector or Vector3.new(0,0,1)
        -- horizontal nahezu wie in den Logs (sehr kleines Y ist ok)
        if math.abs(v.Y) < 1e-6 then v = Vector3.new(v.X, -0.0005, v.Z) end
        return v.Unit
    end

    local function toolEquipped()
        local ch = LP.Character
        if not ch then return false end
        for _,t in ipairs(ch:GetChildren()) do
            if t:IsA("Tool") and cfg.TOOL_MATCH[t.Name] then return true end
        end
        return false
    end

    local function canFire(v, originPos)
        local pp = v.PrimaryPart or ensurePP(v); if not pp then return false end
        if (pp.Position - originPos).Magnitude > cfg.MAX_DIST then return false end
        local tnext = perTarget[v]
        if tnext and tnext > now() then return false end
        if (now() - lastGlobal) < cfg.GLOBAL_CD then return false end
        return true
    end

    -- WICHTIG: erster Vektor = Fahrzeug-Position (Hit-Punkt), zweiter = Blickrichtung
    local function fireAt(v)
        local pp = v.PrimaryPart or ensurePP(v); if not pp then return end
        local first  = pp.Position                 -- wie in funktionierenden Dumps
        local second = camLook()                   -- horizontaler Blickvektor

        local toolArg = Instance.new("Tool", nil)  -- exakt wie Spy
        REMOTE:FireServer(
            toolArg,
            vector.create(first.X,  first.Y,  first.Z),
            vector.create(second.X, second.Y, second.Z)
        )

        perTarget[v] = now() + cfg.PER_TARGET_CD
        lastGlobal   = now()
    end

    local loopConn
    local function setEnabled(on)
        if loopConn then loopConn:Disconnect(); loopConn=nil end
        if not on then
            cfg.enabled = false; table.clear(perTarget)
            if OrionLib and OrionLib.MakeNotification then
                OrionLib:MakeNotification({Name="Radar", Content="Aus", Time=1})
            end
            return
        end
        cfg.enabled = true
        local acc = 0
        loopConn = RunService.Heartbeat:Connect(function(dt)
            acc += dt; if acc < cfg.TICK then return end; acc = 0
            if not toolEquipped() then return end

            local vf = vehiclesFolder(); if not vf then return end
            local originForRange = (Players.LocalPlayer.Character
                and Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart"))
                and Players.LocalPlayer.Character.HumanoidRootPart.Position
                or Vector3.new(0,0,0)

            -- sortiere nach Distanz zum Spieler (nur für Range/Lastverteilung)
            local list = {}
            for _,v in ipairs(vf:GetChildren()) do
                local pp = v.PrimaryPart or v:FindFirstChildWhichIsA("BasePart", true)
                if pp then
                    local d = (pp.Position - originForRange).Magnitude
                    if d <= cfg.MAX_DIST then table.insert(list, {v=v, d=d}) end
                end
            end
            table.sort(list, function(a,b) return a.d < b.d end)

            local fired = 0
            for _,it in ipairs(list) do
                if fired >= cfg.MAX_PER_TICK then break end
                if canFire(it.v, originForRange) then
                    fireAt(it.v)
                    fired += 1
                end
            end
        end)
        if OrionLib and OrionLib.MakeNotification then
            OrionLib:MakeNotification({Name="Radar", Content="An", Time=1})
        end
    end

    -- UI: nur Toggle (kein Keybind)
    local sec = tab:AddSection({ Name = "Radarfalle" })
    sec:AddToggle({
        Name = "Auto-Radar (Tool ausrüsten)",
        Default = false,
        Callback = function(v) setEnabled(v) end
    })

    print("[police/radarfalle v1.4.0] loaded (vec1=vehicle pos, vec2=look dir, 1500 range)")
end
