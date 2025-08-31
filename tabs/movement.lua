-- tabs/movement.lua
-- SorinHub - Movement Tab (slide-speed + soft escape)
-- Changes vs old version:
--  - Speed: adds extra ground distance per frame (keeps animations, no WalkSpeed enforcement)
--  - Escape Vehicle: uses Jump + small upward nudge (no weld/motor destruction)

return function(tab, OrionLib)
    ----------------------------------------------------------------
    -- Services / locals
    local Players      = game:GetService("Players")
    local RunService   = game:GetService("RunService")
    local UserInput    = game:GetService("UserInputService")
    local LP           = Players.LocalPlayer

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
    local function hum(char)
        char = char or LP.Character
        return char and char:FindFirstChildOfClass("Humanoid")
    end
    local function hrp(char)
        char = char or LP.Character
        return char and char:FindFirstChild("HumanoidRootPart")
    end

    ----------------------------------------------------------------
    -- Slide-Speed (does NOT touch Humanoid.WalkSpeed)
    -- Idea: when the player is moving, add a small extra displacement along the move direction.
    -- Result: looks like normal walking (anims intact) but covers more ground ("slide").
    local SLIDE = {
        enabled   = false,
        multiplier= 1.0,   -- 1.0 = normal (no boost). 0.1..3.0 allowed
        conn      = nil,
        keybind   = Enum.KeyCode.T,
        toggleObj = nil,
    }

    local function startSlide()
        if SLIDE.enabled then return end
        SLIDE.enabled = true

        -- Per-frame extra displacement if player is moving on ground.
        SLIDE.conn = on(RunService.RenderStepped, function(dt)
            if not SLIDE.enabled then return end
            local h = hum(); local root = hrp()
            local cam = workspace.CurrentCamera
            if not (h and root and cam) then return end

            -- Only apply when player intends to move: either WASD pressed or MoveDirection present.
            local moveDir = h.MoveDirection
            local hasInput =
                UserInput:IsKeyDown(Enum.KeyCode.W)
                or UserInput:IsKeyDown(Enum.KeyCode.A)
                or UserInput:IsKeyDown(Enum.KeyCode.S)
                or UserInput:IsKeyDown(Enum.KeyCode.D)

            if (not hasInput) and (moveDir.Magnitude <= 0) then
                return
            end

            -- Constrain to XZ plane; animations remain the same.
            if moveDir.Magnitude > 0 then
                moveDir = Vector3.new(moveDir.X, 0, moveDir.Z).Unit
            else
                -- Fallback: infer from camera if MoveDirection is zero but keys are down
                local look = cam.CFrame.LookVector
                moveDir = Vector3.new(look.X, 0, look.Z).Unit
            end

            -- Compute extra distance: (multiplier - 1) * baseSpeed * dt
            -- Use current humanoid WalkSpeed as the "base", but do NOT set it.
            local base = h.WalkSpeed or 16
            local extraFactor = math.clamp((SLIDE.multiplier or 1.0) - 1.0, -0.9, 2.0)
            if math.abs(extraFactor) < 1e-3 then return end

            local extra = base * extraFactor * dt
            if extra ~= 0 then
                -- Keep Y the same to avoid fake jumps; tiny tilt corrections are okay.
                root.CFrame = root.CFrame + (moveDir * extra)
            end
        end, CONNS)
    end

    local function stopSlide()
        SLIDE.enabled = false
    end

    ----------------------------------------------------------------
    -- Jump modifier (kept; harmless if used within safe range)
    local JM = { value = 50 }
    local function setJump(v)
        JM.value = math.clamp(v or JM.value, 0, 50)
        local h = hum()
        if not h then return end
        local okUse = (h.UseJumpPower == nil) or (h.UseJumpPower == true)
        if h.JumpPower ~= nil and okUse then
            h.JumpPower = JM.value
        elseif h.JumpHeight ~= nil then
            h.JumpHeight = JM.value * (7.2/50)
        end
    end

    ----------------------------------------------------------------
    -- Noclip (unchanged; toggles character parts collision)
    local NC = { enabled = false, conn = nil }
    local function setPartsCollide(char, collide)
        if not char then return end
        for _,d in ipairs(char:GetDescendants()) do
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
    -- Soft Escape Vehicle (no weld/motor destruction)
    -- Strategy:
    --  1) Try to unsit (Humanoid.Sit=false)
    --  2) Force a Jump pulse
    --  3) Nudge HRP slightly upward and clear velocities
    local function softEscapeVehicle()
        local ch = LP.Character; local h = hum(ch); local root = hrp(ch)
        if not (ch and h and root) then return end

        -- Attempt to unsit & jump
        pcall(function() h.Sit = false end)
        task.delay(0.02, function()
            pcall(function() h.Jump = true end)
        end)

        -- Small upward nudge to avoid instant reseat
        root.CFrame = root.CFrame + Vector3.new(0, 2.25, 0)

        -- Clear residual velocities to stabilize
        pcall(function() root.AssemblyLinearVelocity = Vector3.new() end)
        pcall(function() root.AssemblyAngularVelocity = Vector3.new() end)
    end

    ----------------------------------------------------------------
    -- (Optional) Fly is intentionally omitted here to reduce hard flags.
    -- If you still want it, keep it in a separate tab/build for testing.

    ----------------------------------------------------------------
    -- UI
    tab:AddSection({Name = "Movement"})
    SLIDE.toggleObj = tab:AddToggle({
        Name = "Slide Speed (no WalkSpeed edit)",
        Default = false, Save = true, Flag = "mv_slide_on",
        Callback = function(v)
            if v then startSlide() else stopSlide() end
        end
    })

    tab:AddSlider({
        Name = "Slide Multiplier",
        Min = 0.1, Max = 3.0, Increment = 0.05,
        Default = 1.0, ValueName = "x",
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

    tab:AddSection({Name = "Jump"})
    tab:AddSlider({
        Name = "Jump Modifier",
        Min = 0, Max = 50, Increment = 1,
        Default = 50, ValueName = "power/height",
        Save = true, Flag = "mv_jump_val",
        Callback = function(v) setJump(v) end
    })

    tab:AddSection({Name = "Collision"})
    tab:AddToggle({
        Name = "Noclip (no collisions)",
        Default = false, Save = true, Flag = "mv_noclip_on",
        Callback = function(v)
            if v then startNoclip() else stopNoclip() end
        end
    })

    tab:AddSection({Name = "Vehicle"})
    tab:AddButton({
        Name = "Escape Vehicle (soft)",
        Callback = function() softEscapeVehicle() end
    })
    tab:AddBind({
        Name = "Escape Vehicle Bind (G)",
        Default = Enum.KeyCode.G, Hold = false,
        Save = true, Flag = "mv_escape_bind",
        Callback = function() softEscapeVehicle() end
    })

    ----------------------------------------------------------------
    -- Respawn handling: only apply jump value when user changed it
    on(LP.CharacterAdded, function()
        -- Re-apply jump setting if user saved a non-default
        task.defer(function() setJump(JM.value) end)
        -- Noclip re-apply if enabled
        if NC.enabled then
            local ch = LP.Character
            task.defer(function() if ch then setPartsCollide(ch, false) end end)
        end
        -- Slide: nothing to do; it only acts while enabled per-frame
    end, CONNS)
end
