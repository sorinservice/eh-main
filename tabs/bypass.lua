-- tabs/bypass.lua
-- VoiceChat helper + Game Freecam helper (pure client-side, no server remotes).
-- This file intentionally does NOT call any RemoteEvent/Function for admin features.

return function(tab, OrionLib)
    print("Modul v2.4 loaded in, u can use it")
    ----------------------------------------------------------------
    -- Services
    local Players              = game:GetService("Players")
    local VoiceChatService     = game:GetService("VoiceChatService")
    local RunService           = game:GetService("RunService")
    local UserInputService     = game:GetService("UserInputService")
    local ContextActionService = game:GetService("ContextActionService")
    local StarterGui           = game:GetService("StarterGui")
    local Camera               = workspace.CurrentCamera

    local LP = Players.LocalPlayer

    local function safeConnect(sig, fn)
        local ok, c = pcall(function() return sig:Connect(fn) end)
        return ok and c or nil
    end

    ----------------------------------------------------------------
    -- VoiceChat: light join helper (no ban-bypass, just best-effort join)
    local vcStatus = tab:AddParagraph("VoiceChat Status", "Checking...")

    local function setVCStatus(txt)
        pcall(function() vcStatus:Set(txt) end)
    end

    local function isVCEnabledForMe()
        local ok, enabled = pcall(function()
            return VoiceChatService:IsVoiceEnabledForUserIdAsync(LP.UserId)
        end)
        return ok and enabled
    end

    local function readVCStateString()
        local parts = {}
        table.insert(parts, isVCEnabledForMe() and "Eligible: yes" or "Eligible: no")
        local ok, state = pcall(function()
            if typeof(VoiceChatService.GetStateForUserAsync) == "function" then
                return VoiceChatService:GetStateForUserAsync(LP.UserId)
            end
        end)
        if ok and state ~= nil then table.insert(parts, "State: "..tostring(state)) end
        return table.concat(parts, "  |  ")
    end

    setVCStatus(readVCStateString())

    local function tryJoinOnce()
        -- Try any available local join method (these are public APIs on some clients)
        if typeof(VoiceChatService.joinVoice) == "function" then
            return pcall(function() VoiceChatService:joinVoice() end)
        end
        if typeof(VoiceChatService.Join) == "function" then
            return pcall(function() VoiceChatService:Join() end)
        end
        if typeof(VoiceChatService.JoinAsync) == "function" then
            return pcall(function() VoiceChatService:JoinAsync() end)
        end
        return false, "No join* method on this client"
    end

    tab:AddButton({
        Name = "Anti-VC-Ban (Join Voice)",
        Callback = function()
            if not isVCEnabledForMe() then
                OrionLib:MakeNotification({
                    Name = "VoiceChat",
                    Content = "Voice is not enabled for this account or in this experience.",
                    Time = 4
                })
                setVCStatus(readVCStateString())
                return
            end
            local ok, err = tryJoinOnce()
            OrionLib:MakeNotification({
                Name = "VoiceChat",
                Content = ok and "Join attempt sent." or ("Join failed: "..tostring(err)),
                Time = ok and 3 or 5
            })
            task.delay(0.5, function() setVCStatus(readVCStateString()) end)
        end
    })

    safeConnect(VoiceChatService.PlayerVoiceChatStateChanged, function(userId, state)
        if userId == LP.UserId then
            setVCStatus("State: "..tostring(state).."  |  "..(isVCEnabledForMe() and "Eligible: yes" or "Eligible: no"))
        end
    end)

    tab:AddParagraph("How it works?",
        "Tries client-side join methods only. No server calls are used.\n" ..
        "If joining fails, the account/experience likely isn't eligible."
    )

    ----------------------------------------------------------------
    -- Game Freecam Helper (client-only wiring; no unlocks; no remotes)
    local FC = {
        enabled      = false,   -- UI toggle: use helper
        active       = false,   -- detected game freecam currently active
        sinkMovement = true,    -- block character movement while freecam
        fovMin       = 40,
        fovMax       = 100,
        fovStep      = 2,
        fovTarget    = Camera and Camera.FieldOfView or 70,
        wheelConn    = nil,
        pollConn     = nil,
        sinkBound    = false,
        statusPara   = nil,
    }

    -- Detect "game freecam" by camera state heuristics.
    local function isGameFreecamActive()
        -- Heuristic: many game/dev freecams set Scriptable and decouple subject.
        if not Camera then return false end
        if Camera.CameraType ~= Enum.CameraType.Scriptable then return false end
        -- When a dev freecam is on, the character should not be the subject.
        if Camera.CameraSubject and Camera.CameraSubject:IsDescendantOf(LP.Character or Instance.new("Folder")) then
            -- Some dev cams keep Scriptable but still subject; tolerate it.
            -- We still treat as active if Scriptable.
        end
        return true
    end

    -- Smooth FOV approach
    local function approach(a,b,t) return a + (b-a) * math.clamp(t or 0.2, 0, 1) end

    local function bindMovementSink()
        if FC.sinkBound then return end
        FC.sinkBound = true
        -- Sink the main movement keys so the character doesn't move while freecam.
        local function sinkAction(_, inputState, _)
            if not FC.active then return Enum.ContextActionResult.Pass end
            if inputState == Enum.UserInputState.Begin or inputState == Enum.UserInputState.Change then
                return Enum.ContextActionResult.Sink
            end
            return Enum.ContextActionResult.Sink
        end
        ContextActionService:BindActionAtPriority("Sorin_Freecam_SinkMove", sinkAction, false,
            9e6, -- high priority
            Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D,
            Enum.KeyCode.Space, Enum.KeyCode.LeftShift, Enum.KeyCode.LeftControl,
            Enum.KeyCode.Q, Enum.KeyCode.E, Enum.KeyCode.R, Enum.KeyCode.F
        )
    end

    local function unbindMovementSink()
        if not FC.sinkBound then return end
        FC.sinkBound = false
        ContextActionService:UnbindAction("Sorin_Freecam_SinkMove")
    end

    local function onWheel(input, processed)
        if processed then return end
        if not FC.active then return end
        if input.UserInputType == Enum.UserInputType.MouseWheel then
            local delta = input.Position.Z > 0 and -FC.fovStep or FC.fovStep
            FC.fovTarget = math.clamp((Camera and Camera.FieldOfView or 70) + delta, FC.fovMin, FC.fovMax)
        end
    end

    local function startHelper()
        if FC.pollConn then return end
        -- UI hint: let Roblox show default dev freecam keybinds if any
        pcall(function()
            StarterGui:SetCore("SendNotification", {
                Title = "Freecam",
                Text  = "Press Shift+P to toggle the game's freecam (if available).",
                Duration = 4
            })
        end)

        FC.wheelConn = safeConnect(UserInputService.InputChanged, onWheel)
        FC.pollConn  = safeConnect(RunService.RenderStepped, function()
            FC.active = isGameFreecamActive()

            -- Smoothly apply FOV only while freecam is active
            if Camera and FC.active then
                Camera.FieldOfView = approach(Camera.FieldOfView, FC.fovTarget, 0.25)
            end

            -- Movement sink wiring
            if FC.sinkMovement and FC.active then
                bindMovementSink()
            else
                unbindMovementSink()
            end

            -- Status text
            if FC.statusPara then
                local txt = ("Freecam wiring: %s | Active: %s | FOV: %d")
                    :format(FC.enabled and "ON" or "OFF", FC.active and "YES" or "NO", math.floor(Camera.FieldOfView + 0.5))
                pcall(function() FC.statusPara:Set(txt) end)
            end
        end)
    end

    local function stopHelper()
        if FC.wheelConn then FC.wheelConn:Disconnect(); FC.wheelConn=nil end
        if FC.pollConn  then FC.pollConn:Disconnect();  FC.pollConn=nil  end
        unbindMovementSink()
    end

    -- UI
    tab:AddSection({Name = "Freecam"})
    FC.statusPara = tab:AddParagraph("Freecam", "Freecam wiring: OFF | Active: NO")

    tab:AddToggle({
        Name = "Use game freecam (Shift+P; helper only)",
        Default = false, Save = true, Flag = "bypass_freecam_helper",
        Callback = function(v)
            FC.enabled = v
            if v then startHelper() else stopHelper() end
        end
    })

    tab:AddToggle({
        Name = "Block character movement while freecam",
        Default = true, Save = true, Flag = "bypass_freecam_sinkmove",
        Callback = function(v)
            FC.sinkMovement = v
            -- binding is handled in the poll loop depending on FC.active
        end
    })

    tab:AddParagraph("Notes",
        "• This helper does not unlock or request admin freecam.\n" ..
        "• It only detects when the game’s freecam is active and improves UX:\n" ..
        "  - sinks character movement while freecam\n" ..
        "  - smooth mouse wheel FOV (zoom)\n" ..
        "• Toggle the real freecam with Shift+P (if provided by the game)."
    )
end
