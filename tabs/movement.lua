-- tabs/movement.lua
-- SorinHub - Movement Tab (refined slide-speed + jump-only escape)

return function(tab, OrionLib)
    print("movement_test")
    local Players      = game:GetService("Players")
    local RunService   = game:GetService("RunService")
    local UserInput    = game:GetService("UserInputService")
    local Workspace    = game:GetService("Workspace")

    local LP = Players.LocalPlayer

    local CONNS = {}
    local function on(sig, fn, bucket)
        local c = sig:Connect(fn)
        if bucket then table.insert(bucket, c) end
        return c
    end
    local function disconnectAll(list)
        for _,c in ipairs(list) do pcall(function() c:Disconnect() end) end
        table.clear(list)
    end

    local function getHumanoid(ch)
        ch = ch or LP.Character
        return ch and ch:FindFirstChildOfClass("Humanoid")
    end
    local function getHRP(ch)
        ch = ch or LP.Character
        return ch and ch:FindFirstChild("HumanoidRootPart")
    end

    ----------------------------------------------------------------
    -- Slide-Speed (grounded, MoveDirection-based, speed-capped)
    local SLIDE = {
        enabled    = false,
        multiplier = 1.2,  -- default boost
        conn       = nil,
        toggleObj  = nil,
    }

    local function isOnGround(h)
        -- Quick ground check via state or floor material
        if not h then return false end
        local st = h:GetState()
        if st == Enum.HumanoidStateType.Running or st == Enum.HumanoidStateType.RunningNoPhysics then
            return true
        end
        return h.FloorMaterial and h.FloorMaterial ~= Enum.Material.Air
    end

    local function startSlide()
        if SLIDE.enabled then return end
        SLIDE.enabled = true

        -- Prepare raycast params once
        local rayParams = RaycastParams.new()
        rayParams.FilterType = Enum.RaycastFilterType.Exclude

        SLIDE.conn = on(RunService.RenderStepped, function(dt)
            if not SLIDE.enabled then return end
            local h   = getHumanoid()
            local r   = getHRP()
            local ch  = LP.Character
            if not (h and r and ch) then return end
            if h.Sit or not isOnGround(h) then return end

            local moveDir = h.MoveDirection
            if moveDir.Magnitude <= 0.01 then return end
            moveDir = Vector3.new(moveDir.X, 0, moveDir.Z).Unit

            -- Target speed vs current horizontal velocity
            local base       = (h.WalkSpeed and h.WalkSpeed > 0) and h.WalkSpeed or 16
            local multiplier = math.clamp(SLIDE.multiplier or 1.2, 0.8, 2.0)
            local target     = base * multiplier

            local vel        = r.AssemblyLinearVelocity
            local curHorz    = Vector3.new(vel.X, 0, vel.Z).Magnitude

            if curHorz >= target - 0.05 then return end

            -- Extra distance for this frame (soft catch-up)
            local deficit    = target - curHorz
            local extra      = math.clamp(deficit * dt, 0, 3.0 * dt) -- cap per-frame push

            if extra <= 0 then return end

            -- Simple anti-clip: raycast ahead by the extra step, skip if wall
            rayParams.FilterDescendantsInstances = { ch }
            local origin    = r.Position
            local direction = moveDir * (extra + 0.2) -- small safety margin
            local hit       = Workspace:Raycast(origin, direction, rayParams)
            if hit and hit.Instance and hit.Instance.CanCollide ~= false then
                return -- obstacle in the way; do not push
            end

            -- Apply extra displacement on XZ plane only
            r.CFrame = r.CFrame + (moveDir * extra)
        end, CONNS)
    end

    local function stopSlide()
        SLIDE.enabled = false
    end

    ----------------------------------------------------------------
    -- Noclip (unchanged)
    local NC = { enabled = false, conn = nil }
    local function setPartsCollide(ch, collide)
        if not ch then return end
        for _,d in ipairs(ch:GetDescendants()) do
            if d:IsA("BasePart") then
                pcall(function() d.CanCollide = collide end)
            end
        end
    end
    local function startNoclip()
        if NC.enabled then return end
        NC.enabled = true
        local ch = LP.Character
        if ch then setPartsCollide(ch, false) end
        NC.conn = on(RunService.Heartbeat, function()
            if not NC.enabled then return end
            local ch2 = LP.Character
            if ch2 then setPartsCollide(ch2, false) end
        end, CONNS)
    end
    local function stopNoclip()
        NC.enabled = false
        local ch = LP.Character
        if ch then setPartsCollide(ch, true) end
    end

    ----------------------------------------------------------------
    -- Escape Vehicle (jump-only)
    local function escapeVehicleJumpOnly()
        local h = getHumanoid()
        if not h then return end
        pcall(function() h.Sit = false end)
        -- short jump pulse
        task.defer(function()
            pcall(function() h.Jump = true end)
        end)
    end

    ----------------------------------------------------------------
    -- UI
    tab:AddSection({Name = "Movement"})
    SLIDE.toggleObj = tab:AddToggle({
        Name = "Slide Speed (grounded)",
        Default = false, Save = true, Flag = "mv_slide_on",
        Callback = function(v) if v then startSlide() else stopSlide() end end
    })
    tab:AddSlider({
        Name = "Slide Multiplier",
        Min = 0.8, Max = 2.0, Increment = 0.05,
        Default = 1.2, ValueName = "x",
        Save = true, Flag = "mv_slide_mult",
        Callback = function(v) SLIDE.multiplier = v end
    })
    tab:AddBind({
        Name = "Toggle Slide (T)",
        Default = Enum.KeyCode.T, Hold = false,
        Save = true, Flag = "mv_slide_bind",
        Callback = function()
            if SLIDE.toggleObj and SLIDE.toggleObj.Set then
                SLIDE.toggleObj:Set(not SLIDE.toggleObj.Value)
            end
        end
    })

    tab:AddSection({Name = "Collision"})
    tab:AddToggle({
        Name = "Noclip (no collisions)",
        Default = false, Save = true, Flag = "mv_noclip_on",
        Callback = function(v) if v then startNoclip() else stopNoclip() end end
    })

    tab:AddSection({Name = "Vehicle"})
    tab:AddButton({
        Name = "Escape Vehicle (jump)",
        Callback = function() escapeVehicleJumpOnly() end
    })
    tab:AddBind({
        Name = "Escape Vehicle Bind (G)",
        Default = Enum.KeyCode.G, Hold = false,
        Save = true, Flag = "mv_escape_bind",
        Callback = function() escapeVehicleJumpOnly() end
    })

    ----------------------------------------------------------------
    -- Respawn housekeeping
    on(LP.CharacterAdded, function()
        if NC.enabled then
            local ch = LP.Character
            task.defer(function() if ch then setPartsCollide(ch, false) end end)
        end
    end, CONNS)
end
