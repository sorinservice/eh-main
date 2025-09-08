-- tabs/functions/police/radarfalle.lua
return function(SV, tab, OrionLib)
    -- radar v1.1.1 (exact args: Instance.new("Tool", nil), vector.create(pos), vector.create(dir))

    local RunService = game:GetService("RunService")
    local REMOTE = (function()
        local rs = game:GetService("ReplicatedStorage")
        local bnl = rs:WaitForChild("Bnl")
        return bnl:WaitForChild("bbb7c252-304d-4582-b2a0-89eb9d3a0855")
    end)()

    -- decompiler zeigt vector.create(...); auf Roblox reicht Vector3.new.
    -- Wir mappen’s 1:1, damit die Aufrufsignatur identisch aussieht.
    local vector = { create = Vector3.new }

    local cfg = {
        enabled       = false,
        MAX_DIST      = 600,   -- leichte Begrenzung, sonst alles
        TICK          = 0.10,  -- Scanrate
        PER_TARGET_CD = 0.35,  -- pro Fahrzeug drosseln
        GLOBAL_CD     = 0.05,  -- global drosseln
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
        local lp = game:GetService("Players").LocalPlayer
        local ch = lp.Character or lp.CharacterAdded:Wait()
        return ch:FindFirstChild("HumanoidRootPart")
    end

    local function dirFromPlayer(toPos)
        local r = hrp()
        if not r then return Vector3.new(0,0,1) end
        local d = toPos - r.Position
        return (d.Magnitude > 1e-6) and d.Unit or Vector3.new(0,0,1)
    end

    local function canFire(v, r)
        local pp = v.PrimaryPart or ensurePP(v)
        if not pp then return false end
        if (pp.Position - r.Position).Magnitude > cfg.MAX_DIST then return false end
        local tnext = perTarget[v]
        if tnext and tnext > now() then return false end
        if (now() - lastGlobal) < cfg.GLOBAL_CD then return false end
        return true
    end

    local function fireAt(v)
        local pp = v.PrimaryPart or ensurePP(v); if not pp then return end

        local toolArg = Instance.new("Tool", nil) -- exakt wie im Spy
        local pos     = pp.Position
        local dir     = dirFromPlayer(pos)

        -- exakt wie im Spy: vector.create(...) statt Vector3.new(...)
        REMOTE:FireServer(
            toolArg,
            vector.create(pos.X, pos.Y, pos.Z),
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

            local vf = vehiclesFolder()
            local r  = hrp()
            if not vf or not r then return end

            for _,v in ipairs(vf:GetChildren()) do
                if canFire(v, r) then
                    fireAt(v)
                end
            end
        end)
        if OrionLib and OrionLib.MakeNotification then
            OrionLib:MakeNotification({Name="Radar", Content="An", Time=1})
        end
    end

    -- UI: nur Toggle + Keybind
    local sec = tab:AddSection({ Name = "Radarfalle" })
    local tgl = sec:AddToggle({
        Name = "Auto-Radar",
        Default = false,
        Callback = function(v) setEnabled(v) end
    })
    sec:AddBind({
        Name = "Toggle Key",
        Default = Enum.KeyCode.R,
        Hold = false,
        Callback = function() tgl:Set(not cfg.enabled); setEnabled(not cfg.enabled) end
    })

    print("[police/radarfalle v1.1.1] loaded (exact args spam)")
end
