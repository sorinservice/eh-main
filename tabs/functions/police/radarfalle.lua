-- tabs/functions/police/radarfalle.lua
return function(SV, tab, OrionLib)
    -- radar v1.3.0 (fires only when Radar-Tool equipped, no keybind, range=1500)

    local RunService = game:GetService("RunService")
    local Players    = game:GetService("Players")
    local LP         = Players.LocalPlayer

    -- Remote (wie Spy)
    local REMOTE = (function()
        local rs = game:GetService("ReplicatedStorage")
        local bnl = rs:WaitForChild("Bnl")
        return bnl:WaitForChild("bbb7c252-304d-4582-b2a0-89eb9d3a0855")
    end)()

    -- Spy-kompatibel
    local vector = { create = Vector3.new }

    local cfg = {
        enabled       = false,
        MAX_DIST      = 1500,
        TICK          = 0.08,
        PER_TARGET_CD = 0.30,
        GLOBAL_CD     = 0.03,
        MAX_PER_TICK  = 6,
        -- Tool-Erkennung: passe bei Bedarf die Namen an
        TOOL_NAMES    = {["Radar"]=true, ["RadarGun"]=true, ["Radar Gun"]=true}
    }

    local lastGlobal = 0
    local perTarget  = {} -- [Model] = nextAllowedTime

    local function now() return os.clock() end

    local function vehiclesFolder()
        return workspace:FindFirstChild("Vehicles")
    end

    local function ensurePP(m)
        if not m then return nil end
        if m.PrimaryPart then return m.PrimaryPart end
        local bp = m:FindFirstChildWhichIsA("BasePart", true)
        if bp then m.PrimaryPart = bp return bp end
        return nil
    end

    local function hrp()
        local ch = LP.Character or LP.CharacterAdded:Wait()
        return ch and ch:FindFirstChild("HumanoidRootPart")
    end

    -- Prüft, ob ein „Radar“-Tool ausgerüstet ist (Tool parent = Character)
    local function radarEquipped()
        local ch = LP.Character
        if not ch then return false end
        for _,inst in ipairs(ch:GetChildren()) do
            if inst:IsA("Tool") and cfg.TOOL_NAMES[inst.Name] then
                return true
            end
        end
        return false
    end

    -- Mündungs-/Radar-Position leicht vor/über HRP
    local function muzzleOrigin()
        local r = hrp(); if not r then return nil end
        return r.Position + r.CFrame.LookVector * 1.5 + Vector3.new(0, 1.2, 0)
    end

    local function canFire(v, origin)
        local pp = v.PrimaryPart or ensurePP(v)
        if not pp then return false end
        if (pp.Position - origin).Magnitude > cfg.MAX_DIST then return false end
        local tnext = perTarget[v]
        if tnext and tnext > now() then return false end
        if (now() - lastGlobal) < cfg.GLOBAL_CD then return false end
        return true
    end

    local function fireAt(v, origin)
        local pp = v.PrimaryPart or ensurePP(v); if not pp then return end
        local dir = (pp.Position - origin)
        local mag = dir.Magnitude
        if mag < 1e-6 then return end
        dir = dir / mag

        local toolArg = Instance.new("Tool", nil) -- exakt wie Spy
        REMOTE:FireServer(
            toolArg,
            vector.create(origin.X, origin.Y, origin.Z),
            vector.create(dir.X, dir.Y, dir.Z)
        )

        perTarget[v] = now() + cfg.PER_TARGET_CD
        lastGlobal   = now()
    end

    local loopConn
    local function setEnabled(on)
        if loopConn then loopConn:Disconnect(); loopConn=nil end
        if not on then
            cfg.enabled = false
            table.clear(perTarget)
            if OrionLib and OrionLib.MakeNotification then
                OrionLib:MakeNotification({Name="Radar", Content="Aus", Time=1})
            end
            return
        end
        cfg.enabled = true
        local acc = 0
        loopConn = RunService.Heartbeat:Connect(function(dt)
            acc += dt
            if acc < cfg.TICK then return end
            acc = 0

            -- Nur scannen, wenn Radar-Tool AUSGERÜSTET ist
            if not radarEquipped() then return end

            local vf = vehiclesFolder(); if not vf then return end
            local origin = muzzleOrigin(); if not origin then return end

            -- Kandidaten nach Distanz sortieren
            local candidates = {}
            for _,v in ipairs(vf:GetChildren()) do
                local pp = v.PrimaryPart or v:FindFirstChildWhichIsA("BasePart", true)
                if pp then
                    local d = (pp.Position - origin).Magnitude
                    if d <= cfg.MAX_DIST then
                        table.insert(candidates, {v=v, d=d})
                    end
                end
            end
            table.sort(candidates, function(a,b) return a.d < b.d end)

            local fired = 0
            for _,it in ipairs(candidates) do
                if fired >= cfg.MAX_PER_TICK then break end
                if canFire(it.v, origin) then
                    fireAt(it.v, origin)
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
        Name = "Auto-Radar (Tool muss ausgerüstet sein)",
        Default = false,
        Callback = function(v) setEnabled(v) end
    })

    print("[police/radarfalle v1.3.0] loaded (equip-gated, origin=HRP, range=1500, no keybind)")
end
