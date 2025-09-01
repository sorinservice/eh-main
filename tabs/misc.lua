-- tabs/misc.lua
-- Misc utilities for SorinHub (executor-friendly, client-side)
-- Features:
-- 1) Anti Fall Damage (soft-landing right before ground)
-- 2) Anti Arrest (auto step/teleport away from nearby Police when not in vehicle)
-- 3) Anti Taser (auto recover from ragdoll/PlatformStand/FallingDown)

return function(tab, OrionLib)
    ----------------------------------------------------------------
    -- Services
    ----------------------------------------------------------------
    local Players        = game:GetService("Players")
    local RunService     = game:GetService("RunService")
    local UserInput      = game:GetService("UserInputService")
    local Workspace      = game:GetService("Workspace")
    local TweenService   = game:GetService("TweenService")

    local LP             = Players.LocalPlayer
    local Camera         = Workspace.CurrentCamera

    ----------------------------------------------------------------
    -- Small helpers
    ----------------------------------------------------------------
    local function notify(title, text, t)
        OrionLib:MakeNotification({ Name = title or "Misc", Content = text or "", Time = t or 3 })
    end

    local function getHumanoid(char)
        return char and char:FindFirstChildOfClass("Humanoid") or nil
    end

    local function getHRP(char)
        return char and char:FindFirstChild("HumanoidRootPart") or nil
    end

    local function isInVehicle(hum)
        if not hum then return false end
        local seat = hum.SeatPart
        return seat ~= nil and seat:IsA("VehicleSeat")
    end

    local function unitOrZero(v)
        if v.Magnitude > 0 then return v.Unit else return Vector3.new() end
    end

    -- Safe BodyVelocity pulse (exec-friendly, minimal lifetime)
    local function pulseBodyVelocity(hrp, vel, lifetime)
        if not (hrp and hrp:IsDescendantOf(Workspace)) then return end
        local bv = Instance.new("BodyVelocity")
        bv.MaxForce = Vector3.new(1e5,1e5,1e5)
        bv.Velocity = vel
        bv.P = 1250
        bv.Parent = hrp
        task.delay(lifetime or 0.12, function()
            if bv then pcall(function() bv:Destroy() end) end
        end)
    end

    -- Raycast down from point, returns hitPos, hitNormal, hitInstance, dist
    local function rayDown(origin, maxDist, ignoreList)
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = ignoreList or {}
        params.IgnoreWater = false
        local res = Workspace:Raycast(origin, Vector3.new(0, -maxDist, 0), params)
        if res then
            return res.Position, res.Normal, res.Instance, (origin - res.Position).Magnitude
        end
        return nil, nil, nil, math.huge
    end

    -- Step to safe position on ground near a given point (simple downcast)
    local function snapToGroundNear(pos, maxDrop, ignoreList)
        local hitPos = select(1, rayDown(pos + Vector3.new(0, 2, 0), maxDrop or 50, ignoreList))
        return hitPos and (hitPos + Vector3.new(0, 2.5, 0)) or pos
    end

    ----------------------------------------------------------------
    -- STATE & UI
    ----------------------------------------------------------------
    local state = {
        antiFallEnabled   = false,
        antiArrestEnabled = false,
        antiTaserEnabled  = false,

        -- Anti-FallDamage
        fall_minSpeed     = 45,   -- |Y-velocity| threshold to intervene
        fall_probeDist    = 10,   -- start braking when ground < this (studs)
        fall_brakeFactor  = 0.55, -- multiplier applied to downward speed (lower = more braking)
        fall_pulseTime    = 0.12, -- seconds for BodyVelocity pulse

        -- Anti-Arrest
        arrest_radius     = 10,   -- proximity radius to trigger (studs)
        arrest_teleDist   = 16,   -- how far to teleport away
        arrest_cooldown   = 1.0,  -- seconds

        -- Anti-Taser
        taser_cooldown    = 0.75, -- seconds between recoveries
        taser_upwardKick  = 15,   -- small vertical kick to help recovery
    }

    local lastArrestTime = 0
    local lastTaserRecover= 0

    -- UI sections
    local secFall   = tab:AddSection({ Name = "Anti Fall Damage" })
    local secArrest = tab:AddSection({ Name = "Anti Arrest (Police proximity)" })
    local secTaser  = tab:AddSection({ Name = "Anti Taser (ragdoll recovery)" })

    -- Anti FallDamage
    secFall:AddToggle({
        Name = "Enable Anti Fall Damage",
        Default = false,
        Callback = function(v) state.antiFallEnabled = v end
    })
    secFall:AddSlider({
        Name = "Trigger Distance (to ground)",
        Min = 5, Max = 30, Increment = 1, Default = state.fall_probeDist,
        ValueName = "studs",
        Callback = function(v) state.fall_probeDist = math.floor(v) end
    })
    secFall:AddSlider({
        Name = "Min Down Speed",
        Min = 20, Max = 120, Increment = 5, Default = state.fall_minSpeed,
        ValueName = "|Vy|",
        Callback = function(v) state.fall_minSpeed = math.floor(v) end
    })
    secFall:AddSlider({
        Name = "Brake Factor",
        Min = 0.25, Max = 0.9, Increment = 0.05, Default = state.fall_brakeFactor,
        ValueName = "×speed",
        Callback = function(v) state.fall_brakeFactor = tonumber(string.format("%.2f", v)) end
    })

    -- Anti Arrest
    secArrest:AddToggle({
        Name = "Enable Anti Arrest",
        Default = false,
        Callback = function(v) state.antiArrestEnabled = v end
    })
    secArrest:AddSlider({
        Name = "Police Trigger Radius",
        Min = 6, Max = 25, Increment = 1, Default = state.arrest_radius,
        ValueName = "studs",
        Callback = function(v) state.arrest_radius = math.floor(v) end
    })
    secArrest:AddSlider({
        Name = "Teleport Distance",
        Min = 10, Max = 40, Increment = 1, Default = state.arrest_teleDist,
        ValueName = "studs",
        Callback = function(v) state.arrest_teleDist = math.floor(v) end
    })

    -- Anti Taser
    secTaser:AddToggle({
        Name = "Enable Anti Taser",
        Default = false,
        Callback = function(v) state.antiTaserEnabled = v end
    })
    secTaser:AddSlider({
        Name = "Recovery Cooldown",
        Min = 0.25, Max = 2.0, Increment = 0.05, Default = state.taser_cooldown,
        ValueName = "sec",
        Callback = function(v) state.taser_cooldown = tonumber(string.format("%.2f", v)) end
    })

    tab:AddParagraph("Note", "All features are client-side. Tune thresholds for your game. If your server has its own stun/arrest logic, consider adding server-authoritative checks later.")

    ----------------------------------------------------------------
    -- Anti Fall Damage loop
    ----------------------------------------------------------------
    local function fallTick(dt)
        if not state.antiFallEnabled then return end
        local char = LP.Character
        local hum  = getHumanoid(char)
        local hrp  = getHRP(char)
        if not (hum and hrp) then return end

        -- Only act during freefall-like states
        local st = hum:GetState()
        if st ~= Enum.HumanoidStateType.Freefall and st ~= Enum.HumanoidStateType.FallingDown then
            return
        end

        -- Downward speed check
        local vy = hrp.Velocity.Y
        if vy >= -state.fall_minSpeed then return end

        -- Ground distance
        local hitPos, _, _, dist = rayDown(hrp.Position, math.max(6, state.fall_probeDist), {char})
        if dist <= state.fall_probeDist then
            -- Apply braking just before impact
            local v = hrp.Velocity
            local damped = Vector3.new(v.X * 0.7, v.Y * state.fall_brakeFactor, v.Z * 0.7)
            pulseBodyVelocity(hrp, damped, state.fall_pulseTime)
        end
    end

    ----------------------------------------------------------------
    -- Anti Arrest loop
    ----------------------------------------------------------------
    local function isPolice(plr)
        return plr.Team and plr.Team.Name == "Police"
    end

    local function arrestTick(dt)
        if not state.antiArrestEnabled then return end
        local char = LP.Character
        local hum  = getHumanoid(char)
        local hrp  = getHRP(char)
        if not (hum and hrp) then return end
        if isInVehicle(hum) then return end  -- do nothing in cars

        local now = os.clock()
        if (now - lastArrestTime) < state.arrest_cooldown then return end

        -- find nearest Police within radius
        local nearest, nDist, nHRP = nil, math.huge, nil
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LP and isPolice(plr) then
                local c = plr.Character
                local pHRP = getHRP(c)
                local pHum = getHumanoid(c)
                if pHRP and pHum and pHum.Health > 0 then
                    local d = (pHRP.Position - hrp.Position).Magnitude
                    if d < nDist then
                        nDist = d
                        nHRP = pHRP
                        nearest = plr
                    end
                end
            end
        end
        if nearest and nDist <= state.arrest_radius then
            -- Tele away opposite of police direction, clamp to ground
            local awayDir = unitOrZero(hrp.Position - nHRP.Position)
            if awayDir.Magnitude < 0.1 then
                awayDir = unitOrZero(Camera.CFrame.LookVector) * -1 -- fallback
            end
            local target = hrp.Position + awayDir * state.arrest_teleDist
            target = snapToGroundNear(target, 60, {char})
            -- gentle teleport
            hrp.CFrame = CFrame.new(target, target + Camera.CFrame.LookVector)
            lastArrestTime = now
            -- small horizontal impulse to break grapples
            pulseBodyVelocity(hrp, awayDir * 28 + Vector3.new(0, 6, 0), 0.10)
            notify("Anti Arrest", "Teleported away from Police proximity.", 2)
        end
    end

    ----------------------------------------------------------------
    -- Anti Taser: state watcher + recovery
    ----------------------------------------------------------------
    local function tryRecover(hum, hrp)
        if not (state.antiTaserEnabled and hum and hrp) then return end
        local now = os.clock()
        if (now - lastTaserRecover) < state.taser_cooldown then return end

        -- Clear common stun/KO patterns
        hum:ChangeState(Enum.HumanoidStateType.GettingUp)
        hum.PlatformStand = false
        hum.Sit = false

        -- Give a tiny upward kick & stabilize horizontal speed
        local v = hrp.Velocity
        local fixed = Vector3.new(v.X * 0.5, math.max(v.Y, state.taser_upwardKick), v.Z * 0.5)
        pulseBodyVelocity(hrp, fixed, 0.10)

        lastTaserRecover = now
        -- (optional) notify once in a while
        -- notify("Anti Taser", "Recovered from stun.", 1.5)
    end

    local stateConn
    local function bindTaserWatcher()
        if stateConn then stateConn:Disconnect() end
        local hum = getHumanoid(LP.Character)
        if not hum then return end
        stateConn = hum.StateChanged:Connect(function(old,new)
            if not state.antiTaserEnabled then return end
            if new == Enum.HumanoidStateType.FallingDown
            or new == Enum.HumanoidStateType.Ragdoll
            or new == Enum.HumanoidStateType.PlatformStanding
            or new == Enum.HumanoidStateType.Physics then
                tryRecover(hum, getHRP(LP.Character))
            end
        end)
    end

    -- Rebind watcher on character spawn
    local function onCharacterAdded(char)
        task.wait(0.1)
        bindTaserWatcher()
    end
    if LP.Character then onCharacterAdded(LP.Character) end
    LP.CharacterAdded:Connect(onCharacterAdded)

    ----------------------------------------------------------------
    -- Main heartbeat
    ----------------------------------------------------------------
    local hbConn = RunService.Heartbeat:Connect(function(dt)
        -- Light-weight ticks
        fallTick(dt)
        arrestTick(dt)
        -- AntiTaser is event-driven (StateChanged), plus:
        if state.antiTaserEnabled then
            local hum = getHumanoid(LP.Character)
            local hrp = getHRP(LP.Character)
            if hum and hrp then
                -- in case game sets PlatformStand without state change
                if hum.PlatformStand or hum.Sit then
                    tryRecover(hum, hrp)
                end
            end
        end
    end)

    ----------------------------------------------------------------
    -- Cleanup on tab close (if your Orion exposes it later, hook here)
    ----------------------------------------------------------------
    -- (no OnClose in this Orion fork; if you add one, disconnect hbConn/stateConn)
end
