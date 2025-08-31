-- tabs/bypass.lua
-- VoiceChat helpers + "use game's Freecam" bypass wiring (Shift+P, arrows for speed, mouse wheel FOV).
-- UI keeps this inside the Bypass tab. We DO NOT toggle freecam from UI; you press Shift+P.
-- While freecam is active, character controls are disabled so the avatar won't walk.

return function(tab, OrionLib)
    print("Modul v2.2 loaded in, u can use it")
    ----------------------------------------------------------------
    -- Services
    local Players              = game:GetService("Players")
    local VoiceChatService     = game:GetService("VoiceChatService")
    local UserInputService     = game:GetService("UserInputService")
    local ContextActionService = game:GetService("ContextActionService")
    local RunService           = game:GetService("RunService")
    local VirtualInputManager  = game:GetService("VirtualInputManager")
    local LocalPlayer          = Players.LocalPlayer
    local Camera               = workspace.CurrentCamera

    ----------------------------------------------------------------
    -- Small helpers
    local conns = {}
    local function on(sig, fn)
        local c = sig:Connect(fn); table.insert(conns, c); return c
    end
    local function disconnectAll()
        for _,c in ipairs(conns) do pcall(function() c:Disconnect() end) end
        conns = {}
    end
    local function notify(t, c, time)
        OrionLib:MakeNotification({ Name = t, Content = c, Time = time or 3 })
    end

    ----------------------------------------------------------------
    -- ========== VoiceChat: simple helper ==========
    local vcPara = tab:AddParagraph("VoiceChat Status", "Checking...")

    local function vcSet(s) pcall(function() vcPara:Set(s) end) end

    local function vcEligible()
        local ok, enabled = pcall(function()
            return VoiceChatService:IsVoiceEnabledForUserIdAsync(LocalPlayer.UserId)
        end)
        return ok and enabled
    end

    local function vcStateLine()
        local parts = {}
        table.insert(parts, vcEligible() and "Eligible: yes" or "Eligible: no")
        local ok, state = pcall(function()
            if typeof(VoiceChatService.GetStateForUserAsync) == "function" then
                return VoiceChatService:GetStateForUserAsync(LocalPlayer.UserId)
            end
        end)
        if ok and state ~= nil then table.insert(parts, "State: "..tostring(state)) end
        return table.concat(parts, "  |  ")
    end
    vcSet(vcStateLine())

    local function vcTryJoin()
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
        return false, "No join* method available"
    end

    tab:AddButton({
        Name = "Anti-VC-Ban (Join Voice)",
        Callback = function()
            if not vcEligible() then
                notify("VoiceChat", "Voice is not enabled for this account or game.", 4)
                vcSet(vcStateLine()); return
            end
            local ok, err = vcTryJoin()
            notify("VoiceChat", ok and "Join attempt sent." or ("Join failed: "..tostring(err)), ok and 3 or 5)
            task.delay(0.6, function() vcSet(vcStateLine()) end)
        end
    })

    pcall(function()
        if typeof(VoiceChatService.PlayerVoiceChatStateChanged) == "RBXScriptSignal" then
            VoiceChatService.PlayerVoiceChatStateChanged:Connect(function(uid, state)
                if uid == LocalPlayer.UserId then
                    vcSet(("State: %s  |  %s"):format(tostring(state), vcEligible() and "Eligible: yes" or "Eligible: no"))
                end
            end)
        end
    end)

    tab:AddParagraph("How it works?", "Tries several join methods. If it fails, your account/game likely isn't eligible here.")

    ----------------------------------------------------------------
    -- ========== Freecam bypass: use the GAME's freecam ==========
    -- Design:
    --   * UI has only a toggle "Use game freecam".
    --   * When enabled, we wire hotkeys (Shift+P to toggle), Arrows to adjust speed, Mouse wheel to FOV.
    --   * We DO NOT force freecam on from UI; you press Shift+P (or whatever the game expects).
    --   * While freecam is active, we disable character controls to avoid avatar movement.
    --
    -- We try to find a freecam ModuleScript and map an API: .toggle(), .setSpeed(), .isActive().
    -- If none exposes an API, we emulate Shift+P with VirtualInputManager and infer activity
    -- via Camera.CameraType heuristic.

    local FC = {
        enabled   = false,  -- our wiring active?
        active    = false,  -- best-guess freecam state
        foundStr  = "Searching modules...",
        api       = nil,    -- wrapper { toggle, setSpeed?, isActive? }
        speed     = 1.0,    -- logical speed level we try to forward
        fovTarget = nil,    -- smooth FOV
        fovConn   = nil,
        statusP   = tab:AddParagraph("Freecam", "Use Shift+P to toggle. Arrows change speed. Mouse wheel zoom (FOV)."),
        ctrlObj   = nil,    -- PlayerModule controls
        lastToggleAt = 0,
    }

    local function fcStatus(s) pcall(function() FC.statusP:Set(s) end) end

    -- Controls (so avatar won't walk)
    local function getControls()
        if FC.ctrlObj ~= nil then return FC.ctrlObj end
        local ok, PlayerModule = pcall(function()
            return require(LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"))
        end)
        if ok and PlayerModule and type(PlayerModule.GetControls) == "function" then
            FC.ctrlObj = PlayerModule:GetControls()
        end
        return FC.ctrlObj
    end
    local function lockAvatar(allowMove)
        local c = getControls(); if not c then return end
        if allowMove then c:Enable() else c:Disable() end
    end

    -- Find likely freecam modules
    local function findFreecamModules()
        local arr, patterns = {}, { "freecam", "freecamera", "free_cam" }
        local roots = {
            LocalPlayer:FindFirstChild("PlayerScripts"),
            game:GetService("CoreGui"),
            game:GetService("ReplicatedStorage"),
            game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts"),
        }
        for _,root in ipairs(roots) do
            if root then
                for _,d in ipairs(root:GetDescendants()) do
                    if d:IsA("ModuleScript") then
                        local n = d.Name:lower()
                        for _,pat in ipairs(patterns) do
                            if n:find(pat, 1, true) then table.insert(arr, d); break end
                        end
                    end
                end
            end
        end
        return arr
    end

    local function buildApiFrom(moduleScript)
        local ok, mod = pcall(require, moduleScript)
        if not ok then return nil end
        local api = {}
        if typeof(mod) == "table" then
            if type(mod.Toggle) == "function" then
                api.toggle = function() return pcall(mod.Toggle, mod) end
            elseif type(mod.Enable) == "function" and type(mod.Disable) == "function" then
                local active = false
                api.toggle = function()
                    active = not active
                    return pcall(active and mod.Enable or mod.Disable, mod)
                end
            elseif type(mod.Start) == "function" and type(mod.Stop) == "function" then
                local active = false
                api.toggle = function()
                    active = not active
                    return pcall(active and mod.Start or mod.Stop, mod)
                end
            end
            if type(mod.SetSpeed) == "function"     then api.setSpeed = function(v) pcall(mod.SetSpeed, mod, v) end end
            if type(mod.SetMoveSpeed) == "function" then api.setSpeed = function(v) pcall(mod.SetMoveSpeed, mod, v) end end
            if type(mod.IsActive) == "function"     then api.isActive = function() local ok2,r=pcall(mod.IsActive,mod); return ok2 and r or nil end end
            if type(mod.GetActive) == "function"    then api.isActive = function() local ok2,r=pcall(mod.GetActive,mod);return ok2 and r or nil end end
        elseif typeof(mod) == "function" then
            api.toggle = function() return pcall(mod) end
        end
        if not api.toggle then return nil end
        return api
    end

    local function resolveFreecam()
        if FC.api then return end
        local found = findFreecamModules()
        for _,ms in ipairs(found) do
            local api = buildApiFrom(ms)
            if api then
                FC.api = api
                FC.foundStr = ("Using module: %s"):format(ms:GetFullName())
                return
            end
        end
        FC.foundStr = "No module API found (will press Shift+P)."
    end

    -- Heuristic: detect active freecam (if no .isActive API)
    local function inferActive()
        if FC.api and FC.api.isActive then
            local ok, r = pcall(FC.api.isActive); if ok and r ~= nil then return r end
        end
        -- Common pattern: freecam sets CameraType to Scriptable
        return (Camera.CameraType == Enum.CameraType.Scriptable)
    end

    local function pressShiftP()
        VirtualInputManager:SendKeyEvent(true,  Enum.KeyCode.LeftShift, false, game)
        VirtualInputManager:SendKeyEvent(true,  Enum.KeyCode.P,         false, game)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.P,         false, game)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.LeftShift, false, game)
        FC.lastToggleAt = os.clock()
    end

    local function toggleFreecam()
        resolveFreecam()
        if FC.api then
            pcall(FC.api.toggle)
        else
            pressShiftP()
        end
    end

    local function setSpeed(val, silent)
        FC.speed = math.clamp(val, 0.1, 1000)
        if FC.api and FC.api.setSpeed then pcall(FC.api.setSpeed, FC.speed) end
        if not silent then
            fcStatus(("Freecam wiring: %s | Active: %s | Speed: %.2f | %s")
                :format(FC.enabled and "ON" or "OFF", FC.active and "YES" or "NO", FC.speed, FC.foundStr))
        end
    end

    -- Smooth FOV zoom while freecam is active
    local function startFovLoop()
        if FC.fovConn then return end
        FC.fovTarget = Camera.FieldOfView
        FC.fovConn = on(RunService.RenderStepped, function(dt)
            if not FC.active then return end
            local cur, tgt = Camera.FieldOfView, FC.fovTarget or 70
            local new = cur + (tgt - cur) * math.clamp(dt * 12, 0, 1)
            Camera.FieldOfView = new
        end)
    end
    local function stopFovLoop()
        if FC.fovConn then FC.fovConn:Disconnect(); FC.fovConn=nil end
    end

    -- Periodically re-check active state and lock/unlock avatar
    local monitorConn
    local function startMonitor()
        if monitorConn then return end
        monitorConn = on(RunService.Stepped, function()
            if not FC.enabled then return end
            local was = FC.active
            FC.active = inferActive()
            if FC.active ~= was then
                if FC.active then
                    lockAvatar(false)     -- disable controls
                    startFovLoop()
                else
                    lockAvatar(true)      -- enable controls again
                    stopFovLoop()
                end
                fcStatus(("Freecam wiring: ON | Active: %s | Speed: %.2f | %s")
                    :format(FC.active and "YES" or "NO", FC.speed, FC.foundStr))
            end
        end)
    end
    local function stopMonitor()
        if monitorConn then monitorConn:Disconnect(); monitorConn=nil end
    end

    -- Input bindings (only when wiring is enabled)
    local ACTION_WHEEL = "SH_FreecamWheel"
    local ACTION_SPEED = "SH_FreecamSpeed"

    local function bindInputs()
        -- Mouse wheel -> adjust FOV target (zoom in/out), clamped
        ContextActionService:BindActionAtPriority(
            ACTION_WHEEL,
            function(_, inputState, inputObj)
                if not FC.enabled or not FC.active then return Enum.ContextActionResult.Pass end
                if inputState ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Sink end
                local delta = inputObj.Position.Z  -- wheel step (+/-1 typically)
                FC.fovTarget = math.clamp((FC.fovTarget or Camera.FieldOfView) - (delta * 2), 30, 100)
                return Enum.ContextActionResult.Sink
            end,
            false,  -- createTouchButton
            Enum.ContextActionPriority.High.Value,
            Enum.UserInputType.MouseWheel
        )

        -- Arrow keys -> change speed (we DO NOT move the avatar)
        ContextActionService:BindAction(
            ACTION_SPEED,
            function(_, state, input)
                if not FC.enabled then return Enum.ContextActionResult.Pass end
                if state ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Sink end
                if input.KeyCode == Enum.KeyCode.Up    then setSpeed(FC.speed * 1.25) end
                if input.KeyCode == Enum.KeyCode.Down  then setSpeed(FC.speed / 1.25) end
                if input.KeyCode == Enum.KeyCode.Left  then setSpeed(FC.speed * 0.9)  end
                if input.KeyCode == Enum.KeyCode.Right then setSpeed(FC.speed * 1.1)  end
                return Enum.ContextActionResult.Sink
            end,
            false,
            Enum.KeyCode.Up, Enum.KeyCode.Down, Enum.KeyCode.Left, Enum.KeyCode.Right
        )

        -- We DO NOT hijack Shift+P; the game handles it. If needed, we can emulate it:
        on(UserInputService.InputBegan, function(input, gp)
            if not FC.enabled or gp then return end
            if input.KeyCode == Enum.KeyCode.P and UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
                -- Let the game see it naturally; no action here.
                -- Optionally, if the server swallows it, you could uncomment:
                -- toggleFreecam()
            end
        end)
    end

    local function unbindInputs()
        pcall(function() ContextActionService:UnbindAction(ACTION_WHEEL) end)
        pcall(function() ContextActionService:UnbindAction(ACTION_SPEED) end)
    end

    -- UI toggle: wires/unwires everything
    tab:AddSection({Name = "Game Freecam"})
    tab:AddToggle({
        Name = "Use game freecam (Shift+P, arrows = speed, mouse wheel = zoom)",
        Default = false, Save = true, Flag = "bypass_use_game_freecam",
        Callback = function(v)
            FC.enabled = v
            if v then
                resolveFreecam()
                bindInputs()
                startMonitor()
                setSpeed(FC.speed, true)
                fcStatus(("Freecam wiring: ON | Active: %s | Speed: %.2f | %s")
                    :format(FC.active and "YES" or "NO", FC.speed, FC.foundStr))
                notify("Freecam", "Wiring enabled. Press Shift+P to toggle the game's freecam.", 4)
            else
                stopMonitor()
                unbindInputs()
                stopFovLoop()
                lockAvatar(true)
                fcStatus("Wiring: OFF")
            end
        end
    })

    -- Optional helper button if the game swallows Shift+P (only fires the key sequence).
    tab:AddButton({
        Name = "Force Shift+P (if the game blocks it)",
        Callback = function()
            pressShiftP()
        end
    })
end
