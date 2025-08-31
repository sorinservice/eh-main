-- tabs/bypass.lua
-- VoiceChat helpers + Moderator Freecam system
-- UI exposes only a master toggle; actual Freecam toggled via Shift+P.
-- Speed with Arrow Up/Down; Zoom with mouse wheel (FOV).
-- If a native/Moderator Freecam module is available, we prefer it; otherwise, fallback.

return function(tab, OrionLib)
    ----------------------------------------------------------------
    -- Services
    local Players          = game:GetService("Players")
    local VoiceChatService = game:GetService("VoiceChatService")
    local UserInputService = game:GetService("UserInputService")
    local RunService       = game:GetService("RunService")
    local Workspace        = game:GetService("Workspace")

    local LP  = Players.LocalPlayer
    local Cam = Workspace.CurrentCamera

    local function notify(title, text, t)
        OrionLib:MakeNotification({ Name = title or "Info", Content = tostring(text or ""), Time = t or 3 })
    end

    local function disconnectAll(t)
        for _,c in pairs(t) do pcall(function() c:Disconnect() end) end
        table.clear(t)
    end

    ----------------------------------------------------------------
    -- ========== Voice Chat Helpers (unchanged API) ==========
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

    tab:AddParagraph("How it works?", "Tries several join methods.\nIf it fails, enable Auto-Retry.")

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
    -- ========== Freecam System ==========
    local FC = {
        systemEnabled = false,   -- master switch (UI)
        active        = false,   -- currently in freecam
        useNative     = false,   -- true if we found/loaded a native module
        native        = nil,     -- { enable=fn, disable=fn, toggle=fn } if available

        -- fallback state
        speed       = 40,        -- studs/s
        yaw         = 0,
        pitch       = 0,
        pos         = nil,
        smooth      = 12,
        conns       = {},
        guardConn   = nil,
        mouseConn   = nil,

        -- restore store
        old = {},
    }

    -- Try to locate a native/Moderator freecam module (best-effort, safe to fail)
    local function findNativeFreecam()
        local candidates = {}
        local cg = game:GetService("CoreGui")
        local ps = LP:FindFirstChildOfClass("PlayerScripts")

        local function scan(container)
            if not container then return end
            for _,d in ipairs(container:GetDescendants()) do
                if d:IsA("ModuleScript") and (
                    d.Name:lower() == "freecam" or
                    d.Name:lower() == "modfreecam" or
                    d.Name:lower() == "moderatorfreecam"
                ) then
                    table.insert(candidates, d)
                end
            end
        end

        pcall(scan, cg)
        pcall(scan, ps)

        for _,mod in ipairs(candidates) do
            local ok, lib = pcall(require, mod)
            if ok and type(lib) == "table" then
                -- Heuristics: accept common shapes
                if type(lib.Toggle) == "function" or type(lib.toggle) == "function"
                or type(lib.Enable) == "function" or type(lib.enable) == "function"
                or type(lib.Start)  == "function" or type(lib.start)  == "function" then
                    return {
                        ref = lib,
                        enable = lib.Enable or lib.enable or lib.Start or lib.start or lib.Toggle or lib.toggle,
                        disable = lib.Disable or lib.disable or lib.Stop or lib.stop or lib.Toggle or lib.toggle,
                        toggle = lib.Toggle or lib.toggle
                    }
                end
            end
        end
        return nil
    end

    -- Fallback freecam (our implementation)
    local function startFallback()
        if FC.active then return end
        FC.active = true

        -- store
        FC.old.type       = Cam.CameraType
        FC.old.subject    = Cam.CameraSubject
        FC.old.cf         = Cam.CFrame
        FC.old.fov        = Cam.FieldOfView
        FC.old.mouseIcon  = UserInputService.MouseIconEnabled
        FC.old.mouseBehav = UserInputService.MouseBehavior

        FC.pos = FC.old.cf.Position

        -- derive yaw/pitch
        do
            local look = FC.old.cf.LookVector
            FC.yaw   = math.atan2(-look.X, -look.Z) -- face direction
            FC.pitch = math.asin(look.Y)
        end

        Cam.CameraType = Enum.CameraType.Scriptable
        UserInputService.MouseIconEnabled = false
        UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter

        -- mouse look
        FC.mouseConn = UserInputService.InputChanged:Connect(function(input, gpe)
            if gpe then return end
            if input.UserInputType == Enum.UserInputType.MouseMovement then
                local d = input.Delta
                FC.yaw   = FC.yaw   - d.X * 0.0025
                FC.pitch = math.clamp(FC.pitch - d.Y * 0.0025, math.rad(-85), math.rad(85))
            end
        end)

        -- movement + smoothing
        FC.conns.move = RunService.RenderStepped:Connect(function(dt)
            if UserInputService:GetFocusedTextBox() then return end

            local forward = CFrame.fromOrientation(FC.pitch, FC.yaw, 0).LookVector
            -- FIX: proper right-hand side vector (A/D were inverted previously)
            local right   = forward:Cross(Vector3.yAxis).Unit
            local up      = Vector3.yAxis

            local v = Vector3.zero
            if UserInputService:IsKeyDown(Enum.KeyCode.W) then v += forward end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then v -= forward end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then v -= right   end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then v += right   end
            if UserInputService:IsKeyDown(Enum.KeyCode.E) then v += up      end
            if UserInputService:IsKeyDown(Enum.KeyCode.Q) then v -= up      end

            local mult = 1
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift) then
                mult = mult * 3.0
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl) then
                mult = mult * 0.35
            end

            if v.Magnitude > 0 then
                v = v.Unit * (FC.speed * mult * dt)
                FC.pos += v
            end

            local target = CFrame.new(FC.pos) * CFrame.fromOrientation(FC.pitch, FC.yaw, 0)
            local alpha = 1 - math.exp(-FC.smooth * dt)
            Cam.CFrame = Cam.CFrame:Lerp(target, alpha)
        end)

        -- guard: keep scriptable
        FC.guardConn = RunService.Stepped:Connect(function()
            if not FC.active then return end
            if Cam.CameraType ~= Enum.CameraType.Scriptable then
                Cam.CameraType = Enum.CameraType.Scriptable
            end
        end)
    end

    local function stopFallback()
        if not FC.active then return end
        FC.active = false
        disconnectAll(FC.conns)
        if FC.mouseConn then FC.mouseConn:Disconnect(); FC.mouseConn = nil end
        if FC.guardConn then FC.guardConn:Disconnect(); FC.guardConn = nil end

        -- restore
        pcall(function()
            Cam.CameraType    = FC.old.type or Enum.CameraType.Custom
            Cam.CameraSubject = FC.old.subject
            Cam.CFrame        = FC.old.cf or Cam.CFrame
            Cam.FieldOfView   = FC.old.fov or Cam.FieldOfView
        end)
        pcall(function()
            UserInputService.MouseIconEnabled = (FC.old.mouseIcon ~= nil) and FC.old.mouseIcon or true
            UserInputService.MouseBehavior    = FC.old.mouseBehav or Enum.MouseBehavior.Default
        end)
    end

    local function toggleFallback()
        if FC.active then
            stopFallback()
            notify("Freecam", "Disabled.", 2)
        else
            startFallback()
            notify("Freecam", "Enabled (use Arrow Up/Down for speed, Mouse Wheel to zoom).", 4)
        end
    end

    -- Native wrapper (if available)
    local function startNative()
        if FC.active then return end
        FC.active = true
        if FC.native.toggle then
            FC.native.toggle()
        elseif FC.native.enable then
            FC.native.enable()
        end
    end
    local function stopNative()
        if not FC.active then return end
        FC.active = false
        if FC.native.toggle then
            FC.native.toggle()
        elseif FC.native.disable then
            FC.native.disable()
        end
    end
    local function toggleNative()
        if FC.active then stopNative() else startNative() end
        notify("Freecam", FC.active and "Enabled." or "Disabled.", 2)
    end

    -- Master input dispatcher (only active when systemEnabled)
    local InputConns = {}

    local function bindInputs()
        if InputConns.bound then return end
        InputConns.bound = true

        -- Shift+P toggles freecam
        InputConns.began = UserInputService.InputBegan:Connect(function(input, gpe)
            if gpe then return end

            if input.KeyCode == Enum.KeyCode.P then
                if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift) then
                    if FC.useNative then toggleNative() else toggleFallback() end
                end
            end

            -- Arrow key speed control (fallback only)
            if not FC.useNative and FC.active then
                if input.KeyCode == Enum.KeyCode.Up then
                    FC.speed = math.clamp(FC.speed * 1.15, 5, 1000)
                    notify("Freecam", ("Speed: %.1f"):format(FC.speed), 1.5)
                elseif input.KeyCode == Enum.KeyCode.Down then
                    FC.speed = math.clamp(FC.speed / 1.15, 5, 1000)
                    notify("Freecam", ("Speed: %.1f"):format(FC.speed), 1.5)
                end
            end
        end)

        -- Mouse wheel zoom (adjust FOV while active)
        InputConns.changed = UserInputService.InputChanged:Connect(function(input, gpe)
            if gpe then return end
            if input.UserInputType == Enum.UserInputType.MouseWheel and FC.active then
                local delta = input.Position.Z  -- +1/-1
                local newFov = math.clamp(Cam.FieldOfView - delta * 2.5, 20, 90)
                Cam.FieldOfView = newFov
            end
        end)
    end

    local function unbindInputs()
        if not InputConns.bound then return end
        if InputConns.began then InputConns.began:Disconnect() end
        if InputConns.changed then InputConns.changed:Disconnect() end
        InputConns.began, InputConns.changed = nil, nil
        InputConns.bound = false
    end

    -- Master toggle (UI) — arms/disarms hotkeys; does NOT start the camera.
    tab:AddSection({Name = "Moderator Freecam"})
    tab:AddParagraph("Hotkey", "Shift+P toggles camera.\nArrow Up/Down = speed (fallback)\nMouse Wheel = zoom (FOV)")

    tab:AddToggle({
        Name = "Enable Freecam System",
        Default = false, Save = true, Flag = "bypass_freecam_system",
        Callback = function(enabled)
            if enabled then
                -- try native once
                if not FC.native then
                    FC.native = findNativeFreecam()
                    FC.useNative = FC.native ~= nil
                    if FC.useNative then
                        notify("Freecam", "Using native freecam module.", 3)
                    else
                        notify("Freecam", "Native freecam not found; using fallback.", 3)
                    end
                end
                FC.systemEnabled = true
                bindInputs()
                notify("Freecam", "System armed. Press Shift+P to toggle.", 3)
            else
                -- disable camera if currently active
                if FC.active then
                    if FC.useNative then stopNative() else stopFallback() end
                end
                FC.systemEnabled = false
                unbindInputs()
                notify("Freecam", "System disabled.", 2)
            end
        end
    })

    -- Optional: ensure camera restored on character/respawn
    LP.CharacterRemoving:Connect(function()
        if FC.active and not FC.useNative then
            stopFallback()
        end
    end)
end
