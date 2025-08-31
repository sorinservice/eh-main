-- tabs/bypass.lua
-- SorinHub: VoiceChat helper (optional) + brand-new Freecam (arm in UI, toggle via Shift+P).
-- Code & UI text in English, per your preference.

return function(tab, OrionLib)
    ----------------------------------------------------------------
    -- Services
    local Players               = game:GetService("Players")
    local UserInputService      = game:GetService("UserInputService")
    local RunService            = game:GetService("RunService")
    local ContextActionService  = game:GetService("ContextActionService")
    local Workspace             = game:GetService("Workspace")
    local VoiceChatService      = game:GetService("VoiceChatService")

    local LP     = Players.LocalPlayer
    local Camera = Workspace.CurrentCamera

    local function notify(title, text, t)
        OrionLib:MakeNotification({ Name = title or "Info", Content = tostring(text or ""), Time = t or 3 })
    end

    ----------------------------------------------------------------
    -- (Optional) VoiceChat mini-helper (keine Auto-Retry, nur Join)
    local statusPara = tab:AddParagraph("VoiceChat", "Eligible/State: checking...")
    local function setStatus(t) pcall(function() statusPara:Set(t) end) end

    local function vcEligible()
        local ok, en = pcall(function()
            return VoiceChatService:IsVoiceEnabledForUserIdAsync(LP.UserId)
        end)
        return ok and en
    end
    local function vcStateStr()
        local parts = {}
        table.insert(parts, vcEligible() and "Eligible: yes" or "Eligible: no")
        local ok, state = pcall(function()
            if typeof(VoiceChatService.GetStateForUserAsync) == "function" then
                return VoiceChatService:GetStateForUserAsync(LP.UserId)
            end
        end)
        if ok and state ~= nil then table.insert(parts, "State: "..tostring(state)) end
        return table.concat(parts, " | ")
    end
    setStatus(vcStateStr())

    tab:AddButton({
        Name = "Join Voice",
        Callback = function()
            if not vcEligible() then
                notify("VoiceChat", "Not eligible in this place/account.", 4)
                setStatus(vcStateStr()); return
            end
            local ok =
                (typeof(VoiceChatService.joinVoice) == "function" and select(1, pcall(function() VoiceChatService:joinVoice() end))) or
                (typeof(VoiceChatService.Join)      == "function" and select(1, pcall(function() VoiceChatService:Join() end)))      or
                (typeof(VoiceChatService.JoinAsync) == "function" and select(1, pcall(function() VoiceChatService:JoinAsync() end))) or
                (typeof(VoiceChatService.JoinByGroupId) == "function" and select(1, pcall(function() VoiceChatService:JoinByGroupId(tostring(game.PlaceId)) end)))
            notify("VoiceChat", ok and "Join attempt sent." or "Join failed.", ok and 3 or 5)
            task.delay(0.4, function() setStatus(vcStateStr()) end)
        end
    })

    ----------------------------------------------------------------
    -- ======================== NEW FREECAM ========================
    -- Arm in UI; toggle with Shift+P.
    -- RMB = look; MouseWheel = FOV zoom (forward = zoom in).
    -- WASD strafe/forward, Q/E up/down. ↑/↓ speed. Shift = boost, Ctrl = slow.
    -- Character movement is fully blocked while active; state is restored.
    ----------------------------------------------------------------

    -- Access PlayerModule controls to cleanly disable default character movement.
    local function getControls()
        local pm = LP:FindFirstChild("PlayerScripts") and LP.PlayerScripts:FindFirstChild("PlayerModule")
        if not pm then return nil end
        local ok, mod = pcall(require, pm)
        if not ok or type(mod) ~= "table" then return nil end
        if type(mod.GetControls) == "function" then
            local ok2, controls = pcall(mod.GetControls, mod)
            if ok2 then return controls end
        end
        return nil
    end

    local FC = {
        armed       = false,
        enabled     = false,

        -- Motion
        speed       = 64,      -- studs/sec
        minSpeed    = 2,
        maxSpeed    = 2048,
        boostMul    = 2.0,
        slowMul     = 0.5,

        -- Smoothing
        vel         = Vector3.zero,
        accel       = 12.0,    -- how fast velocity chases target (higher = snappier)
        fovChase    = 10.0,    -- FOV smoothing strength

        -- Rotation
        yaw         = 0,
        pitch       = 0,
        sens        = 0.16,    -- deg per pixel
        holdLook    = false,   -- RMB pressed

        -- Camera
        camPos      = nil,
        fovTarget   = 70,

        -- Saved state
        saved       = {},

        -- Input state
        keys        = {},

        -- Conns
        conns       = {},
        armConn     = nil,

        controls    = nil,
    }

    local function disconnectAll()
        for _,c in ipairs(FC.conns) do pcall(function() c:Disconnect() end) end
        FC.conns = {}
    end

    local function saveState()
        FC.saved.cameraType  = Camera.CameraType
        FC.saved.subject     = Camera.CameraSubject
        FC.saved.cframe      = Camera.CFrame
        FC.saved.fov         = Camera.FieldOfView
        FC.saved.mouseMode   = UserInputService.MouseBehavior

        local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
        if hum then
            FC.saved.walkspeed  = hum.WalkSpeed
            FC.saved.autorotate = hum.AutoRotate
        end
    end

    local function restoreState()
        Camera.CameraType    = FC.saved.cameraType or Enum.CameraType.Custom
        Camera.CameraSubject = FC.saved.subject or LP.Character
        Camera.CFrame        = FC.saved.cframe or Camera.CFrame
        Camera.FieldOfView   = FC.saved.fov or Camera.FieldOfView
        UserInputService.MouseBehavior = FC.saved.mouseMode or Enum.MouseBehavior.Default

        local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
        if hum then
            if FC.saved.walkspeed  ~= nil then hum.WalkSpeed  = FC.saved.walkspeed end
            if FC.saved.autorotate ~= nil then hum.AutoRotate = FC.saved.autorotate end
        end

        if FC.controls then pcall(function() FC.controls:Enable() end) end
        ContextActionService:UnbindAction("Sorin_BlockMovement")
    end

    local function radians(deg) return deg * math.pi / 180 end
    local function chase(current, target, rate, dt)
        -- exponential smoothing toward target
        local a = 1 - math.exp(-math.max(rate, 0) * dt)
        return current + (target - current) * a
    end

    local function startFreecam()
        if FC.enabled then return end
        FC.enabled = true
        saveState()

        -- Seed orientation from current camera
        local cf = Camera.CFrame
        local x, y, z = cf:ToEulerAnglesYXZ()
        FC.pitch, FC.yaw = math.deg(x), math.deg(y)
        FC.camPos   = cf.Position
        FC.fovTarget = FC.saved.fov or Camera.FieldOfView
        FC.vel      = Vector3.zero

        Camera.CameraType = Enum.CameraType.Scriptable

        -- Disable default controls and character autorotate; block keys so the avatar won't move.
        FC.controls = getControls()
        if FC.controls then pcall(function() FC.controls:Disable() end) end

        local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
        if hum then
            hum.AutoRotate = false
        end

        ContextActionService:BindAction("Sorin_BlockMovement", function()
            return Enum.ContextActionResult.Sink
        end, false,
            Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D,
            Enum.KeyCode.Space, Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift,
            Enum.KeyCode.LeftControl, Enum.KeyCode.RightControl,
            Enum.KeyCode.Q, Enum.KeyCode.E
        )

        -- Inputs
        table.insert(FC.conns, UserInputService.InputBegan:Connect(function(input, gp)
            if gp then return end
            if input.UserInputType == Enum.UserInputType.MouseButton2 then
                FC.holdLook = true
                UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
            elseif input.UserInputType == Enum.UserInputType.Keyboard then
                FC.keys[input.KeyCode] = true
                if input.KeyCode == Enum.KeyCode.Up then
                    FC.speed = math.clamp(FC.speed * 1.15, FC.minSpeed, FC.maxSpeed)
                    notify("Freecam", ("Speed: %.0f"):format(FC.speed), 1.2)
                elseif input.KeyCode == Enum.KeyCode.Down then
                    FC.speed = math.clamp(FC.speed / 1.15, FC.minSpeed, FC.maxSpeed)
                    notify("Freecam", ("Speed: %.0f"):format(FC.speed), 1.2)
                end
            end
        end))

        table.insert(FC.conns, UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton2 then
                FC.holdLook = false
                UserInputService.MouseBehavior = Enum.MouseBehavior.Default
            elseif input.UserInputType == Enum.UserInputType.Keyboard then
                FC.keys[input.KeyCode] = nil
            end
        end))

        table.insert(FC.conns, UserInputService.InputChanged:Connect(function(input, gp)
            if gp or not FC.enabled then return end
            if input.UserInputType == Enum.UserInputType.MouseWheel then
                -- forward (Z positive) = zoom in (smaller FOV)
                local delta = input.Position.Z
                FC.fovTarget = math.clamp(FC.fovTarget - delta * 3.0, 20, 100)
            end
        end))

        -- Main loop
        table.insert(FC.conns, RunService.RenderStepped:Connect(function(dt)
            if not FC.enabled then return end

            -- Rotate while RMB held
            if FC.holdLook then
                local md = UserInputService:GetMouseDelta()
                FC.yaw   = FC.yaw   - (md.X * FC.sens)
                FC.pitch = math.clamp(FC.pitch - (md.Y * FC.sens), -85, 85)
            end
            local rot = CFrame.fromEulerAnglesYXZ(radians(FC.pitch), radians(FC.yaw), 0)

            -- Movement intent (camera-relative)
            local fwd   = rot.LookVector
            local right = rot.RightVector
            local up    = Vector3.yAxis

            local intent = Vector3.zero
            if FC.keys[Enum.KeyCode.W] then intent += fwd end
            if FC.keys[Enum.KeyCode.S] then intent -= fwd end
            if FC.keys[Enum.KeyCode.D] then intent += right end
            if FC.keys[Enum.KeyCode.A] then intent -= right end
            if FC.keys[Enum.KeyCode.E] then intent += up end
            if FC.keys[Enum.KeyCode.Q] then intent -= up end
            -- Optional: Space = up as well (comment out if you don't want it)
            -- if FC.keys[Enum.KeyCode.Space] then intent += up end

            if intent.Magnitude > 1e-3 then
                intent = intent.Unit
            end

            local mult = 1.0
            if FC.keys[Enum.KeyCode.LeftShift] or FC.keys[Enum.KeyCode.RightShift] then mult *= FC.boostMul end
            if FC.keys[Enum.KeyCode.LeftControl] or FC.keys[Enum.KeyCode.RightControl] then mult *= FC.slowMul end

            local targetVel = intent * FC.speed * mult
            FC.vel = chase(FC.vel, targetVel, FC.accel, dt)
            FC.camPos = FC.camPos + FC.vel * dt

            -- Smooth FOV toward target
            Camera.FieldOfView = chase(Camera.FieldOfView, FC.fovTarget, FC.fovChase, dt)

            -- Apply
            Camera.CFrame = CFrame.new(FC.camPos) * rot
        end))

        -- Re-apply movement block after respawn while active
        table.insert(FC.conns, LP.CharacterAdded:Connect(function()
            task.wait(0.1)
            local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
            if hum then hum.AutoRotate = false end
            ContextActionService:BindAction("Sorin_BlockMovement", function()
                return Enum.ContextActionResult.Sink
            end, false, Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D,
                Enum.KeyCode.Space, Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift,
                Enum.KeyCode.LeftControl, Enum.KeyCode.RightControl,
                Enum.KeyCode.Q, Enum.KeyCode.E)
        end))

        notify("Freecam", "Active. RMB = look, Wheel = zoom, ↑/↓ = speed.", 3)
    end

    local function stopFreecam()
        if not FC.enabled then return end
        FC.enabled = false
        disconnectAll()
        UserInputService.MouseBehavior = Enum.MouseBehavior.Default
        restoreState()
        notify("Freecam", "Disabled.", 2)
    end

    local function setArmed(on)
        if FC.armConn then FC.armConn:Disconnect(); FC.armConn = nil end
        FC.armed = on and true or false
        if not FC.armed then
            if FC.enabled then stopFreecam() end
            notify("Freecam", "Disarmed.", 2)
            return
        end
        FC.armConn = UserInputService.InputBegan:Connect(function(input, gp)
            if gp then return end
            if input.KeyCode == Enum.KeyCode.P and
               (UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)) then
                if FC.enabled then stopFreecam() else startFreecam() end
            end
        end)
        notify("Freecam", "Armed. Use Shift+P to toggle.", 3)
    end

    -- UI (only the arming toggle, as requested)
    tab:AddSection({ Name = "Freecam" })
    tab:AddToggle({
        Name = "Enable Freecam (Shift+P)",
        Default = false, Save = true, Flag = "bypass_freecam_arm",
        Callback = function(v) setArmed(v) end
    })
end
