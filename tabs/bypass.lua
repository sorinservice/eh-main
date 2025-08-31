-- tabs/bypass.lua
-- VoiceChat helpers + Moderator Freecam (Shift+P)
-- Safe, client-side only. No soft reconnects, no anticheat circumvention.

return function(tab, OrionLib)
    ----------------------------------------------------------------
    -- Services
    local Players          = game:GetService("Players")
    local VoiceChatService = game:GetService("VoiceChatService")
    local UserInputService = game:GetService("UserInputService")
    local RunService       = game:GetService("RunService")
    local Workspace        = game:GetService("Workspace")

    local LP   = Players.LocalPlayer
    local Cam  = Workspace.CurrentCamera

    ----------------------------------------------------------------
    -- ========== Voice Chat Helpers ==========
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
        if ok and state ~= nil then
            table.insert(parts, "State: " .. tostring(state))
        end
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
                OrionLib:MakeNotification({
                    Name = "VoiceChat",
                    Content = "Voice is not enabled for this account or game.",
                    Time = 4
                })
                setStatus(readStateString())
                return
            end
            local ok, err = tryJoinOnce()
            OrionLib:MakeNotification({
                Name = "VoiceChat",
                Content = ok and "Join attempt sent." or ("Join failed: " .. tostring(err)),
                Time = ok and 3 or 5
            })
            task.delay(0.5, function() setStatus(readStateString()) end)
        end
    })

    tab:AddParagraph(
        "How it works?",
        "Tries several join methods.\nIf it fails, enable Auto-Retry."
    )

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
    -- ========== Moderator Freecam (Shift+P) ==========
    local FC = {
        enabled      = false,
        speed        = 40,   -- base move speed (studs/sec)
        sprintMult   = 3.0,  -- when Shift is held
        slowMult     = 0.35, -- when Ctrl is held
        smooth       = 12,   -- higher = snappier
        yaw          = 0,
        pitch        = 0,
        pos          = nil,
        conns        = {},
        guardConn    = nil,
        mouseConn    = nil,
        old = {}
    }

    local function disconnectAll(t)
        for _,c in pairs(t) do
            pcall(function() c:Disconnect() end)
        end
        table.clear(t)
    end

    local function toYawPitch(cf)
        local _, y, _ = cf:ToOrientation()
        -- pitch: look up/down around X in camera local space
        local x, _, _ = (CFrame.new():ToObjectSpace(cf - cf.Position)):ToOrientation()
        return y, x
    end

    local function startFreecam()
        if FC.enabled then return end
        FC.enabled = true

        -- store original camera state
        FC.old.type       = Cam.CameraType
        FC.old.subject    = Cam.CameraSubject
        FC.old.cf         = Cam.CFrame
        FC.old.fov        = Cam.FieldOfView
        FC.old.mouseIcon  = UserInputService.MouseIconEnabled
        FC.old.mouseBehav = UserInputService.MouseBehavior

        FC.pos = FC.old.cf.Position
        FC.yaw, FC.pitch = toYawPitch(FC.old.cf)

        Cam.CameraType = Enum.CameraType.Scriptable
        UserInputService.MouseIconEnabled = false
        UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter

        -- mouse look
        FC.mouseConn = UserInputService.InputChanged:Connect(function(input: InputObject, gpe)
            if gpe then return end
            if input.UserInputType == Enum.UserInputType.MouseMovement then
                local delta = input.Delta
                FC.yaw   = FC.yaw   - delta.X * 0.0025
                FC.pitch = math.clamp(FC.pitch - delta.Y * 0.0025, math.rad(-85), math.rad(85))
            end
        end)

        -- per-frame movement + smoothing
        FC.conns.move = RunService.RenderStepped:Connect(function(dt)
            -- skip when typing
            if UserInputService:GetFocusedTextBox() then return end

            local forward = CFrame.fromOrientation(FC.pitch, FC.yaw, 0).LookVector
            local right   = Vector3.new(forward.Z, 0, -forward.X).Unit
            local up      = Vector3.yAxis

            local move = Vector3.zero
            if UserInputService:IsKeyDown(Enum.KeyCode.W) then move += forward end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then move -= forward end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then move -= right   end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then move += right   end
            if UserInputService:IsKeyDown(Enum.KeyCode.E) then move += up      end
            if UserInputService:IsKeyDown(Enum.KeyCode.Q) then move -= up      end

            local mult = 1.0
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift) then
                mult = mult * FC.sprintMult
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl) then
                mult = mult * FC.slowMult
            end

            if move.Magnitude > 0 then
                move = move.Unit * (FC.speed * mult * dt)
                FC.pos = FC.pos + move
            end

            -- smooth camera
            local target = CFrame.new(FC.pos) * CFrame.fromOrientation(FC.pitch, FC.yaw, 0)
            local alpha = 1 - math.exp(-FC.smooth * dt)
            Cam.CFrame = Cam.CFrame:Lerp(target, alpha)
        end)

        -- guard against game reassigning camera
        FC.guardConn = RunService.Stepped:Connect(function()
            if not FC.enabled then return end
            if Cam.CameraType ~= Enum.CameraType.Scriptable then
                Cam.CameraType = Enum.CameraType.Scriptable
            end
        end)

        OrionLib:MakeNotification({
            Name = "Freecam",
            Content = "Moderator Freecam enabled (Shift+P to toggle).",
            Time = 3
        })
    end

    local function stopFreecam()
        if not FC.enabled then return end
        FC.enabled = false

        disconnectAll(FC.conns)
        if FC.mouseConn then FC.mouseConn:Disconnect(); FC.mouseConn = nil end
        if FC.guardConn then FC.guardConn:Disconnect(); FC.guardConn = nil end

        -- restore camera + mouse
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

        OrionLib:MakeNotification({
            Name = "Freecam",
            Content = "Moderator Freecam disabled.",
            Time = 3
        })
    end

    local function toggleFreecam()
        if FC.enabled then stopFreecam() else startFreecam() end
    end

    -- Hotkey: Shift + P to toggle
    FC.conns.hotkey = UserInputService.InputBegan:Connect(function(input: InputObject, gpe)
        if gpe then return end
        if input.KeyCode == Enum.KeyCode.P then
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift) then
                toggleFreecam()
            end
        end
    end)

    -- UI for Freecam
    tab:AddSection({Name = "Moderator Freecam"})
    tab:AddParagraph("Hotkey", "Shift+P toggles Freecam")

    tab:AddToggle({
        Name = "Enable Freecam",
        Default = false, Save = true, Flag = "bypass_freecam",
        Callback = function(v)
            if v then startFreecam() else stopFreecam() end
        end
    })

    tab:AddSlider({
        Name = "Freecam Speed",
        Min = 5, Max = 300, Increment = 5,
        Default = FC.speed,
        ValueName = "studs/s",
        Save = true, Flag = "bypass_freecam_speed",
        Callback = function(v) FC.speed = v end
    })

    tab:AddSlider({
        Name = "Smoothness",
        Min = 4, Max = 30, Increment = 1,
        Default = FC.smooth,
        ValueName = "",
        Save = true, Flag = "bypass_freecam_smooth",
        Callback = function(v) FC.smooth = v end
    })

    -- Clean up freecam if character respawns (optional, stays active otherwise)
    LP.CharacterRemoving:Connect(function()
        if FC.enabled then
            -- keep it simple: just keep running (pure camera). If you prefer disabling on respawn:
            -- stopFreecam()
        end
    end)
end
