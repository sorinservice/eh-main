-- tabs/bypass.lua
-- VoiceChat helpers + Freecam (Shift+P, executor-friendly)
-- UI strings & comments in English.

return function(tab, OrionLib)
    ----------------------------------------------------------------
    -- Services
    local Players       = game:GetService("Players")
    local VoiceChatService = game:GetService("VoiceChatService")
    local UserInputService = game:GetService("UserInputService")
    local RunService    = game:GetService("RunService")
    local ContextActionService = game:GetService("ContextActionService")
    local Workspace     = game:GetService("Workspace")

    local LP = Players.LocalPlayer
    local Camera = Workspace.CurrentCamera

    local function notify(title, text, t)
        OrionLib:MakeNotification({ Name = title or "Info", Content = tostring(text or ""), Time = t or 3 })
    end

    ----------------------------------------------------------------
    -- ========== VoiceChat (unchanged core, small tidy) ==========
    local statusPara = tab:AddParagraph("VoiceChat Status", "Checking...")

    local function setStatus(txt)
        pcall(function() statusPara:Set(txt) end)
    end

    local function isEnabledForUser()
        local ok, enabled = pcall(function()
            return VoiceChatService:IsVoiceEnabledForUserIdAsync(LP.UserId)
        end)
        return ok and enabled
    end

    local function readStateString()
        local parts = {}
        table.insert(parts, isEnabledForUser() and "Eligible: yes" or "Eligible: no")
        local ok, state = pcall(function()
            if typeof(VoiceChatService.GetStateForUserAsync) == "function" then
                return VoiceChatService:GetStateForUserAsync(LP.UserId)
            end
        end)
        if ok and state ~= nil then table.insert(parts, "State: " .. tostring(state)) end
        return table.concat(parts, "  |  ")
    end

    setStatus(readStateString())

    local function tryJoinOnce()
        if typeof(VoiceChatService.joinVoice) == "function" then
            return pcall(function() VoiceChatService:joinVoice() end)
        end
        if typeof(VoiceChatService.Join) == "function" then
            return pcall(function() VoiceChatService:Join() end)
        end
        if typeof(VoiceChatService.JoinAsync) == "function" then
            return pcall(function() VoiceChatService:JoinAsync() end)
        end
        if typeof(VoiceChatService.JoinByGroupId) == "function" then
            return pcall(function() VoiceChatService:JoinByGroupId(tostring(game.PlaceId)) end)
        end
        return false, "No join* method available on VoiceChatService"
    end

    tab:AddButton({
        Name = "Anti-VC-Ban (Join Voice)",
        Callback = function()
            if not isEnabledForUser() then
                notify("VoiceChat", "Voice is not enabled for this account or game.", 4)
                setStatus(readStateString())
                return
            end
            local ok, err = tryJoinOnce()
            notify("VoiceChat", ok and "Join attempt sent." or ("Join failed: " .. tostring(err)), ok and 3 or 5)
            task.delay(0.5, function() setStatus(readStateString()) end)
        end
    })

    pcall(function()
        if typeof(VoiceChatService.PlayerVoiceChatStateChanged) == "RBXScriptSignal" then
            VoiceChatService.PlayerVoiceChatStateChanged:Connect(function(userId, state)
                if userId == LP.UserId then
                    setStatus("State: " .. tostring(state) .. "  |  " .. (isEnabledForUser() and "Eligible: yes" or "Eligible: no"))
                end
            end)
        end
    end)

    ----------------------------------------------------------------
    -- ===================== Freecam (Shift+P) =====================
    -- Behavior:
    --  - Toggle with Shift+P (only if "armed" via UI toggle)
    --  - RMB hold to rotate (mouse look), wheel to dolly (zoom in/out)
    --  - WASD move, Q/E up/down
    --  - Arrow Up/Down to change speed
    --  - Player controls are disabled while active (character won't move)
    ----------------------------------------------------------------
    local FC = {
        armed      = false,
        enabled    = false,
        speed      = 64,        -- studs/sec
        minSpeed   = 2,
        maxSpeed   = 2048,
        yaw        = 0,
        pitch      = 0,
        rotHold    = false,     -- RMB held
        camCF      = nil,
        wheelStep  = 6,         -- studs per wheel notch
        sens       = 0.15,      -- mouse look sensitivity (deg per pixel)
        conns      = {},
        keys       = {},
        saved      = {},
        controls   = nil,       -- PlayerModule controls
        armConn    = nil,
    }

    local function bind(fn)
        local c = fn
        table.insert(FC.conns, c)
        return c
    end
    local function connect(sig, fn)
        local c = sig:Connect(fn)
        table.insert(FC.conns, c)
        return c
    end
    local function disconnectAll()
        for _,c in ipairs(FC.conns) do pcall(function() c:Disconnect() end) end
        FC.conns = {}
    end

    local function setMouseLock(lock)
        if lock then
            UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
        else
            UserInputService.MouseBehavior = Enum.MouseBehavior.Default
        end
    end

    local function getControls()
        -- Disable default player movement cleanly (no sliding/jumping)
        local pm = LP:FindFirstChild("PlayerScripts") and LP.PlayerScripts:FindFirstChild("PlayerModule")
        if not pm then return nil end
        local ok, mod = pcall(function() return require(pm) end)
        if not ok or type(mod) ~= "table" then return nil end
        if type(mod.GetControls) == "function" then
            local ok2, controls = pcall(mod.GetControls, mod)
            if ok2 then return controls end
        end
        return nil
    end

    local function saveState()
        FC.saved.cameraType = Camera.CameraType
        FC.saved.subject    = Camera.CameraSubject
        FC.saved.cframe     = Camera.CFrame
        FC.saved.fov        = Camera.FieldOfView
        -- player motion lock backup
        local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
        if hum then
            FC.saved.walkspeed  = hum.WalkSpeed
            FC.saved.autorotate = hum.AutoRotate
        end
        FC.saved.mouseBehavior = UserInputService.MouseBehavior
    end

    local function restoreState()
        Camera.CameraType   = FC.saved.cameraType or Enum.CameraType.Custom
        Camera.CameraSubject= FC.saved.subject or LP.Character
        Camera.CFrame       = FC.saved.cframe or Camera.CFrame
        Camera.FieldOfView  = FC.saved.fov or Camera.FieldOfView
        UserInputService.MouseBehavior = FC.saved.mouseBehavior or Enum.MouseBehavior.Default
        local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
        if hum then
            if FC.saved.walkspeed ~= nil then hum.WalkSpeed = FC.saved.walkspeed end
            if FC.saved.autorotate ~= nil then hum.AutoRotate = FC.saved.autorotate end
        end
        if FC.controls then pcall(function() FC.controls:Enable() end) end
        ContextActionService:UnbindAction("Sorin_BlockMovement")
    end

    local function radians(deg) return deg * math.pi/180 end

    local function startFreecam()
        if FC.enabled then return end
        FC.enabled = true
        saveState()

        -- seed camera frame + yaw/pitch from current view
        FC.camCF = Camera.CFrame
        local x, y, _ = FC.camCF:ToEulerAnglesYXZ()     -- X=pitch, Y=yaw
        FC.pitch = math.deg(x)
        FC.yaw   = math.deg(y)

        Camera.CameraType = Enum.CameraType.Scriptable

        -- hard disable character controls
        FC.controls = getControls()
        if FC.controls then pcall(function() FC.controls:Disable() end) end

        local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
        if hum then
            hum.WalkSpeed = 0
            hum.AutoRotate = false
        end

        -- sink typical movement to be extra-safe
        ContextActionService:BindAction("Sorin_BlockMovement", function() return Enum.ContextActionResult.Sink end, false,
            Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D,
            Enum.KeyCode.Space, Enum.KeyCode.Q, Enum.KeyCode.E,
            Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift)

        -- inputs
        connect(UserInputService.InputBegan, function(input, gp)
            if gp then return end
            if input.UserInputType == Enum.UserInputType.MouseButton2 then
                FC.rotHold = true
                setMouseLock(true)
            elseif input.UserInputType == Enum.UserInputType.Keyboard then
                FC.keys[input.KeyCode] = true

                -- speed up/down with arrows
                if input.KeyCode == Enum.KeyCode.Up then
                    FC.speed = math.clamp(FC.speed * 1.15, FC.minSpeed, FC.maxSpeed)
                    notify("Freecam", ("Speed: %.0f"):format(FC.speed), 1.5)
                elseif input.KeyCode == Enum.KeyCode.Down then
                    FC.speed = math.clamp(FC.speed / 1.15, FC.minSpeed, FC.maxSpeed)
                    notify("Freecam", ("Speed: %.0f"):format(FC.speed), 1.5)
                end
            end
        end)

        connect(UserInputService.InputEnded, function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton2 then
                FC.rotHold = false
                setMouseLock(false)
            elseif input.UserInputType == Enum.UserInputType.Keyboard then
                FC.keys[input.KeyCode] = nil
            end
        end)

        -- wheel dolly: scroll forward = zoom in
        connect(UserInputService.InputChanged, function(input, gp)
            if gp or not FC.enabled then return end
            if input.UserInputType == Enum.UserInputType.MouseWheel then
                local delta = input.Position.Z     -- +1 (forward), -1 (back)
                local dir = FC.camCF.LookVector
                FC.camCF = FC.camCF + (dir * (delta * FC.wheelStep))
                Camera.CFrame = FC.camCF
            end
        end)

        -- main loop
        connect(RunService.RenderStepped, function(dt)
            if not FC.enabled then return end

            -- rotate on RMB
            if FC.rotHold then
                local md = UserInputService:GetMouseDelta()
                FC.yaw   = FC.yaw   - (md.X * FC.sens)
                FC.pitch = math.clamp(FC.pitch - (md.Y * FC.sens), -85, 85)
            end

            -- build orientation
            local rot = CFrame.fromEulerAnglesYXZ(radians(FC.pitch), radians(FC.yaw), 0)

            -- WASD + Q/E movement (A/D are correct strafes via RightVector)
            local move = Vector3.zero
            local right = rot.RightVector
            local up    = Vector3.yAxis
            local look  = rot.LookVector

            if FC.keys[Enum.KeyCode.W] then move += look end
            if FC.keys[Enum.KeyCode.S] then move -= look end
            if FC.keys[Enum.KeyCode.D] then move += right end
            if FC.keys[Enum.KeyCode.A] then move -= right end
            if FC.keys[Enum.KeyCode.E] then move += up end
            if FC.keys[Enum.KeyCode.Q] then move -= up end

            local mult = 1
            if FC.keys[Enum.KeyCode.LeftShift] or FC.keys[Enum.KeyCode.RightShift] then mult = mult * 2 end
            if FC.keys[Enum.KeyCode.LeftControl] or FC.keys[Enum.KeyCode.RightControl] then mult = mult * 0.5 end

            if move.Magnitude > 0 then
                FC.camCF = FC.camCF + (move.Unit * (FC.speed * mult * dt))
            end

            -- apply final camera
            Camera.CFrame = CFrame.new(FC.camCF.Position) * rot
        end)

        notify("Freecam", "Active (RMB to look, wheel to zoom, ↑/↓ speed).", 3)
    end

    local function stopFreecam()
        if not FC.enabled then return end
        FC.enabled = false
        disconnectAll()
        setMouseLock(false)
        restoreState()
        notify("Freecam", "Disabled.", 2)
    end

    local function toggleFreecam()
        if FC.enabled then stopFreecam() else startFreecam() end
    end

    local function setArmed(on)
        FC.armed = on and true or false
        if FC.armConn then FC.armConn:Disconnect(); FC.armConn = nil end
        if FC.armed then
            FC.armConn = UserInputService.InputBegan:Connect(function(input, gp)
                if gp then return end
                if input.KeyCode == Enum.KeyCode.P and (UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)) then
                    toggleFreecam()
                end
            end)
            notify("Freecam", "Armed. Use Shift+P to toggle.", 3)
        else
            if FC.enabled then stopFreecam() end
            notify("Freecam", "Disarmed.", 2)
        end
    end

    -- UI for freecam
    tab:AddSection({ Name = "Freecam" })
    tab:AddToggle({
        Name = "Enable Freecam (Shift+P)",
        Default = false, Save = true, Flag = "bypass_freecam_arm",
        Callback = function(v) setArmed(v) end
    })

end
