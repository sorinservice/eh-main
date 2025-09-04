-- tabs/movement.lua
-- SorinHub - Movement Tab (UI 0.1..1.0 mapped to internal 0.8..5.0)

return function(tab, OrionLib)
    
    local Players      = game:GetService("Players")
    local RunService   = game:GetService("RunService")
    local Workspace    = game:GetService("Workspace")

    local LP = Players.LocalPlayer

    -- connection helpers
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
    local function safeDisconnect(conn)
        if conn then pcall(function() conn:Disconnect() end) end
        return nil
    end

    -- getters
    local function getHumanoid(ch)
        ch = ch or LP.Character
        return ch and ch:FindFirstChildOfClass("Humanoid")
    end
    private = nil
    local function getHRP(ch)
        ch = ch or LP.Character
        return ch and ch:FindFirstChild("HumanoidRootPart")
    end

    -- ground check
    local function isOnGround(h)
        if not h then return false end
        local st = h:GetState()
        if st == Enum.HumanoidStateType.Running or st == Enum.HumanoidStateType.RunningNoPhysics then
            return true
        end
        return h.FloorMaterial and h.FloorMaterial ~= Enum.Material.Air
    end

    ----------------------------------------------------------------
    -- UI mapping config
    local UI_MIN, UI_MAX     = 0.1, 1.0          -- what the user sees
    local MUL_MIN, MUL_MAX   = 0.8, 5.0          -- internal effective multiplier range

    -- linear remap helper: x in [a1..a2] -> [b1..b2]
    local function remap(x, a1, a2, b1, b2)
        if a2 == a1 then return b1 end
        return b1 + ( (x - a1) * (b2 - b1) / (a2 - a1) )
    end

    local SLIDE = {
        enabled    = false,
        uiFactor   = 1.0,     -- slider value in [0.1..1.0]
        conn       = nil,
        toggleObj  = nil,
    }

    local function getEffectiveMultiplier()
        local t = math.clamp(SLIDE.uiFactor, UI_MIN, UI_MAX)
        return math.clamp(remap(t, UI_MIN, UI_MAX, MUL_MIN, MUL_MAX), MUL_MIN, MUL_MAX)
    end

    ----------------------------------------------------------------
    -- Slide-Speed (grounded, MoveDirection-based, speed-capped)
    local function startSlide()
        if SLIDE.enabled then return end
        SLIDE.enabled = true

        SLIDE.conn = safeDisconnect(SLIDE.conn)

        local rayParams = RaycastParams.new()
        rayParams.FilterType = Enum.RaycastFilterType.Exclude

        SLIDE.conn = on(RunService.RenderStepped, function(dt)
            if not SLIDE.enabled then return end

            local h, r, ch = getHumanoid(), getHRP(), LP.Character
            if not (h and r and ch) then return end
            if h.Sit or not isOnGround(h) then return end

            local moveDir = h.MoveDirection
            if moveDir.Magnitude <= 0.01 then return end
            moveDir = Vector3.new(moveDir.X, 0, moveDir.Z).Unit

            local base       = (h.WalkSpeed and h.WalkSpeed > 0) and h.WalkSpeed or 16
            local multiplier = getEffectiveMultiplier()           -- <- uses mapped value
            local target     = base * multiplier

            local vel        = r.AssemblyLinearVelocity
            local curHorz    = Vector3.new(vel.X, 0, vel.Z).Magnitude
            if curHorz >= target - 0.05 then return end

            -- smoother catch-up with target-relative cap
            local deficit = target - curHorz
            local maxExtra = math.clamp(target * 0.12 * dt, 0, 10.0 * dt)
            local extra    = math.clamp(deficit * 0.6 * dt, 0, maxExtra)
            if extra <= 0 then return end

            -- simple anti-clip check forward
            rayParams.FilterDescendantsInstances = { ch }
            local origin    = r.Position
            local direction = moveDir * (extra + 0.2)
            local hit       = Workspace:Raycast(origin, direction, rayParams)
            if hit and hit.Instance and hit.Instance.CanCollide ~= false then
                return
            end

            -- nudge on XZ plane
            r.CFrame = r.CFrame + (moveDir * extra)
        end, CONNS)
    end

    local function stopSlide()
        SLIDE.enabled = false
        SLIDE.conn = safeDisconnect(SLIDE.conn)
    end

    ----------------------------------------------------------------
    -- Noclip
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
        NC.conn = safeDisconnect(NC.conn)
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
        NC.conn = safeDisconnect(NC.conn)
        local ch = LP.Character
        if ch then setPartsCollide(ch, true) end
    end

    ----------------------------------------------------------------
    -- Escape Vehicle (jump-only)
    local function escapeVehicleJumpOnly()
        local h = getHumanoid()
        if not h then return end
        pcall(function() h.Sit = false end)
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

    -- UI Slider shows 0.1..1.0 but maps internally to 0.8..5.0
    tab:AddSlider({
        Name = "Slide Multiplier (0.1–1.0)",
        Min = UI_MIN, Max = UI_MAX, Increment = 0.05,
        Default = 1.0, ValueName = "",
        Save = true, Flag = "mv_slide_mult_ui",
        Callback = function(v)
            local num = tonumber(v)
            if num then
                SLIDE.uiFactor = math.clamp(num, UI_MIN, UI_MAX)
                -- print("[Slide] ui =", SLIDE.uiFactor, "effective =", getEffectiveMultiplier())
            end
        end
    })

    -- adopt saved UI value on load (if present)
    if OrionLib and OrionLib.Flags and OrionLib.Flags["mv_slide_mult_ui"] then
        local saved = tonumber(OrionLib.Flags["mv_slide_mult_ui"])
        if saved then SLIDE.uiFactor = math.clamp(saved, UI_MIN, UI_MAX) end
    end

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

    -- optional unload hook:
    -- on(SomeUnloadSignal, function()
    --     stopSlide()
    --     stopNoclip()
    --     disconnectAll(CONNS)
    -- end)
end
