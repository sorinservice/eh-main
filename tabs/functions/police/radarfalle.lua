-- tabs/functions/police/radarfalle.lua
return function(SV, tab, OrionLib)
    -- radar v1.5.1 (Orion: Toggle only; requires Radar Gun equipped; range 1500)

    local RunService = game:GetService("RunService")
    local Players    = game:GetService("Players")
    local LP         = Players.LocalPlayer

    -- Remote (your game: Bnl/<uuid>)
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
        MAX_PER_TICK  = 8,
        TOOL_NAMES    = {["Radar Gun"]=true, ["Radar"]=true, ["RadarGun"]=true},
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

    local function canFire(v, originPos)
        local pp = v.PrimaryPart or ensurePP(v); if not pp then return false end
        if (pp.Position - originPos).Magnitude > cfg.MAX_DIST then return false end
        local tnext = perTarget[v]
        if tnext and tnext > now() then return false end
        if (now() - lastGlobal) < cfg.GLOBAL_CD then return false end
        return true
    end

    -- First vector = seat.Position (target), second vector = direction from player
    local function fireAt(v, originPos)
        local seat = v:FindFirstChild("DriveSeat")
        local pp   = v.PrimaryPart or ensurePP(v)
        if not seat or not pp then return end

        local first  = seat.Position
        local dirVec = (first - originPos)
        local mag    = dirVec.Magnitude
        if mag < 1e-6 then return end
        dirVec = dirVec / mag

        local toolArg = Instance.new("Tool", nil) -- dummy tool (like spy output)
        REMOTE:FireServer(
            toolArg,
            vector.create(first.X,  first.Y,  first.Z),
            vector.create(dirVec.X, dirVec.Y, dirVec.Z)
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
                OrionLib:MakeNotification({Name="Radar", Content="Auto-Radar disabled", Time=1})
            end
            return
        end
        cfg.enabled = true
        local acc = 0
        loopConn = RunService.Heartbeat:Connect(function(dt)
            acc += dt
            if acc < cfg.TICK then return end
            acc = 0

            if not radarEquipped() then return end

            local vf = vehiclesFolder(); if not vf then return end
            local root = hrp(); if not root then return end
            local origin = root.Position

            local candidates = {}
            for _,v in ipairs(vf:GetChildren()) do
                local seat = v:FindFirstChild("DriveSeat")
                local pp   = v.PrimaryPart or v:FindFirstChildWhichIsA("BasePart", true)
                if seat and pp then
                    local d = (seat.Position - origin).Magnitude
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
            OrionLib:MakeNotification({Name="Radar", Content="Auto-Radar enabled (equip Radar Gun)", Time=1})
        end
    end

    -- UI: only toggle
    local sec = tab:AddSection({ Name = "Radar Trap" })
    sec:AddToggle({
        Name = "Enable Auto-Radar (requires Radar Gun)",
        Default = false,
        Callback = function(v) setEnabled(v) end
    })

    print("[police/radarfalle v1] loaded")
end
