-- tabs/bypass.lua
-- VoiceChat helper + "use the game's Freecam" wiring (Shift+P hotkey pass-through)
-- Arrows adjust freecam speed (if the module exposes a setter); mouse wheel = FOV zoom.
-- While freecam is active, character controls are disabled so the avatar won't walk.

return function(tab, OrionLib)
    print("Modul v2.3 loaded in, u can use it")
    ------------------------------------------------------------
    -- Services
    local Players              = game:GetService("Players")
    local VoiceChatService     = game:GetService("VoiceChatService")
    local UserInputService     = game:GetService("UserInputService")
    local ContextActionService = game:GetService("ContextActionService")
    local RunService           = game:GetService("RunService")
    local VirtualInputManager  = game:GetService("VirtualInputManager")
    local StarterPlayer        = game:GetService("StarterPlayer")
    local CoreGui              = game:GetService("CoreGui")
    local ReplicatedStorage    = game:GetService("ReplicatedStorage")

    local LP      = Players.LocalPlayer
    local Camera  = workspace.CurrentCamera

    local function notify(t, c, tm) OrionLib:MakeNotification({Name=t, Content=c, Time=tm or 3}) end
    local function on(sig, fn, bucket) local c=sig:Connect(fn); if bucket then table.insert(bucket,c) end; return c end
    local function disconnectAll(list) for _,c in ipairs(list) do pcall(function() c:Disconnect() end) end; table.clear(list) end

    ------------------------------------------------------------
    -- VoiceChat helper (unchanged behavior)
    local vcPara = tab:AddParagraph("VoiceChat Status", "Checking...")
    local function vcSet(s) pcall(function() vcPara:Set(s) end) end

    local function vcEligible()
        local ok, enabled = pcall(function() return VoiceChatService:IsVoiceEnabledForUserIdAsync(LP.UserId) end)
        return ok and enabled
    end
    local function vcStateLine()
        local parts = {}
        table.insert(parts, vcEligible() and "Eligible: yes" or "Eligible: no")
        local ok, state = pcall(function()
            if typeof(VoiceChatService.GetStateForUserAsync) == "function" then
                return VoiceChatService:GetStateForUserAsync(LP.UserId)
            end
        end)
        if ok and state ~= nil then table.insert(parts, "State: "..tostring(state)) end
        return table.concat(parts, "  |  ")
    end
    vcSet(vcStateLine())

    local function vcTryJoin()
        if typeof(VoiceChatService.joinVoice) == "function" then return pcall(function() VoiceChatService:joinVoice() end) end
        if typeof(VoiceChatService.Join) == "function"      then return pcall(function() VoiceChatService:Join()      end) end
        if typeof(VoiceChatService.JoinAsync) == "function"  then return pcall(function() VoiceChatService:JoinAsync()  end) end
        if typeof(VoiceChatService.JoinByGroupId) == "function" then
            return pcall(function() VoiceChatService:JoinByGroupId(tostring(game.PlaceId)) end)
        end
        return false, "No join* method available"
    end

    tab:AddButton({
        Name = "Anti-VC-Ban (Join Voice)",
        Callback = function()
            if not vcEligible() then notify("VoiceChat","Voice is not enabled for this account or game.",4); vcSet(vcStateLine()); return end
            local ok, err = vcTryJoin()
            notify("VoiceChat", ok and "Join attempt sent." or ("Join failed: "..tostring(err)), ok and 3 or 5)
            task.delay(0.6, function() vcSet(vcStateLine()) end)
        end
    })

    tab:AddParagraph("How it works?", "Tries several join methods. If it fails, your account/game likely isn't eligible here.")

    ------------------------------------------------------------
    -- Game Freecam wiring
    local FC = {
        enabled   = false,          -- wiring enabled?
        active    = false,          -- is freecam currently active? (inferred/API)
        api       = nil,            -- {toggle, setSpeed?, isActive?}
        speed     = 1.0,            -- logical speed level
        fovTarget = nil, fovConn=nil,
        ctrl      = nil,            -- PlayerModule controls
        conns     = {},
        foundStr  = "Searching…",
        statusP   = tab:AddParagraph("Freecam", "Use Shift+P to toggle. Arrows = speed. Mouse wheel = zoom (FOV)."),
        wheelAction = "SH_FC_WHEEL",
        speedAction = "SH_FC_SPEED"
    }
    local function fcStatus()
        pcall(function()
            FC.statusP:Set(
                ("Wiring: %s | Active: %s | Speed: %.2f | %s")
                :format(FC.enabled and "ON" or "OFF", FC.active and "YES" or "NO", FC.speed, FC.foundStr)
            )
        end)
    end

    -- Controls helper (disable during freecam so avatar won't walk)
    local function getControls()
        if FC.ctrl then return FC.ctrl end
        local ok, PlayerModule = pcall(function() return require(LP:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule")) end)
        if ok and PlayerModule and type(PlayerModule.GetControls) == "function" then
            FC.ctrl = PlayerModule:GetControls()
        end
        return FC.ctrl
    end
    local function setAvatarInputEnabled(enabled)
        local c = getControls(); if not c then return end
        if enabled then c:Enable() else c:Disable() end
    end

    -- Find Roblox/third-party freecam modules and build a small API wrapper
    local function findCandidates()
        local roots = {
            LP:FindFirstChild("PlayerScripts"),
            CoreGui:FindFirstChild("RobloxGui"),
            ReplicatedStorage,
            StarterPlayer:FindFirstChild("StarterPlayerScripts")
        }
        local picks, pats = {}, { "freecamera", "freecamerainstaller", "freecamcontroller", "freecam", "free_cam" }
        for _,root in ipairs(roots) do
            if root then
                for _,d in ipairs(root:GetDescendants()) do
                    if d:IsA("ModuleScript") then
                        local n = d.Name:lower()
                        for _,pat in ipairs(pats) do
                            if n:find(pat, 1, true) then table.insert(picks, d); break end
                        end
                    end
                end
            end
        end
        return picks
    end

    local function buildApi(ms)
        local ok, mod = pcall(require, ms); if not ok then return nil end
        local api = {}
        if typeof(mod) == "table" then
            if type(mod.Toggle) == "function" then
                api.toggle = function() return pcall(mod.Toggle, mod) end
            elseif type(mod.Enable) == "function" and type(mod.Disable) == "function" then
                local state=false; api.toggle=function() state=not state; return pcall(state and mod.Enable or mod.Disable, mod) end
            elseif type(mod.Start) == "function" and type(mod.Stop) == "function" then
                local state=false; api.toggle=function() state=not state; return pcall(state and mod.Start or mod.Stop, mod) end
            end
            if type(mod.SetSpeed) == "function"     then api.setSpeed = function(v) pcall(mod.SetSpeed, mod, v) end end
            if type(mod.SetMoveSpeed) == "function" then api.setSpeed = function(v) pcall(mod.SetMoveSpeed, mod, v) end end
            if type(mod.IsActive) == "function"     then api.isActive = function() local ok2,r=pcall(mod.IsActive,mod); return ok2 and r or nil end end
            if type(mod.GetActive) == "function"    then api.isActive = function() local ok2,r=pcall(mod.GetActive,mod); return ok2 and r or nil end end
        elseif typeof(mod) == "function" then
            api.toggle = function() return pcall(mod) end
        end
        if not api.toggle then return nil end
        return api
    end

    local function resolveApi()
        if FC.api then return end
        -- Prefer RobloxGui.Modules.Server.FreeCamera if present
        local robloxFreeCam = CoreGui:FindFirstChild("RobloxGui")
            and CoreGui.RobloxGui:FindFirstChild("Modules")
            and CoreGui.RobloxGui.Modules:FindFirstChild("Server")
            and CoreGui.RobloxGui.Modules.Server:FindFirstChild("FreeCamera")

        if robloxFreeCam then
            -- Try the obvious ModuleScript inside (named "FreeCamera")
            for _,d in ipairs(robloxFreeCam:GetDescendants()) do
                if d:IsA("ModuleScript") and d.Name:lower() == "freecamera" then
                    local api = buildApi(d)
                    if api then
                        FC.api = api
                        FC.foundStr = "Using Roblox FreeCamera module"
                        return
                    end
                end
            end
        end

        -- Fallback: scan typical places
        for _,ms in ipairs(findCandidates()) do
            local api = buildApi(ms)
            if api then
                FC.api = api
                FC.foundStr = ("Using module: %s"):format(ms:GetFullName())
                return
            end
        end

        FC.foundStr = "No module API found (will press Shift+P)"
    end

    -- If no API, emulate Shift+P
    local function pressShiftP()
        VirtualInputManager:SendKeyEvent(true,  Enum.KeyCode.LeftShift, false, game)
        VirtualInputManager:SendKeyEvent(true,  Enum.KeyCode.P,         false, game)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.P,         false, game)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.LeftShift, false, game)
    end
    local function toggleFreecam()
        resolveApi()
        if FC.api then pcall(FC.api.toggle) else pressShiftP() end
    end

    -- Activity inference (if the API can’t tell us)
    local function inferActive()
        if FC.api and FC.api.isActive then
            local ok,r = pcall(FC.api.isActive); if ok and r ~= nil then return r end
        end
        -- Very common: freecam sets scriptable camera
        return Camera.CameraType == Enum.CameraType.Scriptable
    end

    local function setSpeed(val, silent)
        FC.speed = math.clamp(val, 0.1, 1000)
        if FC.api and FC.api.setSpeed then pcall(FC.api.setSpeed, FC.speed) end
        if not silent then fcStatus() end
    end

    -- Smooth FOV (mouse wheel)
    local function startFovLoop()
        if FC.fovConn then return end
        FC.fovTarget = Camera.FieldOfView
        FC.fovConn = on(RunService.RenderStepped, function(dt)
            if not FC.active then return end
            local cur, tgt = Camera.FieldOfView, FC.fovTarget or 70
            Camera.FieldOfView = cur + (tgt - cur) * math.clamp(dt * 12, 0, 1)
        end, FC.conns)
    end

    -- Monitor: keep controls off while active, update status text
    local function startMonitor()
        on(RunService.Stepped, function()
            if not FC.enabled then return end
            local was = FC.active
            FC.active = inferActive()
            if FC.active ~= was then
                if FC.active then
                    setAvatarInputEnabled(false)  -- stop avatar movement
                    startFovLoop()
                else
                    setAvatarInputEnabled(true)
                end
                fcStatus()
            end
        end, FC.conns)
    end

    -- Bind inputs (wheel = FOV, arrows = speed)
    local function bindInputs()
        ContextActionService:BindActionAtPriority(
            FC.wheelAction,
            function(_, state, input)
                if not (FC.enabled and FC.active) then return Enum.ContextActionResult.Pass end
                if state ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Sink end
                local step = input.Position.Z -- +/-1 typically
                FC.fovTarget = math.clamp((FC.fovTarget or Camera.FieldOfView) - step * 2, 30, 100)
                return Enum.ContextActionResult.Sink
            end,
            false,
            Enum.ContextActionPriority.High.Value,
            Enum.UserInputType.MouseWheel
        )
        ContextActionService:BindAction(
            FC.speedAction,
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
    end
    local function unbindInputs()
        pcall(function() ContextActionService:UnbindAction(FC.wheelAction) end)
        pcall(function() ContextActionService:UnbindAction(FC.speedAction) end)
    end

    -- UI
    tab:AddSection({Name = "Game Freecam"})
    local function enableWiring()
        if FC.enabled then return end
        FC.enabled = true
        resolveApi()
        bindInputs()
        startMonitor()
        setSpeed(FC.speed, true)
        fcStatus()
        notify("Freecam", "Wiring enabled. Press Shift+P to toggle the game's freecam.", 4)
    end
    local function disableWiring()
        if not FC.enabled then return end
        FC.enabled = false
        setAvatarInputEnabled(true)
        unbindInputs()
        disconnectAll(FC.conns)
        if FC.fovConn then FC.fovConn:Disconnect(); FC.fovConn=nil end
        fcStatus()
    end

    tab:AddToggle({
        Name = "Use game freecam (Shift+P · arrows = speed · mouse wheel = FOV)",
        Default = false, Save = true, Flag = "bypass_use_game_freecam",
        Callback = function(v) if v then enableWiring() else disableWiring() end end
    })

    -- Helper if the game swallows Shift+P
    tab:AddButton({
        Name = "Force Shift+P (if the game blocks it)",
        Callback = function() toggleFreecam() end
    })

    ------------------------------------------------------------
    -- Flag alias bridge (prevents warnings from old configs with 'bypass_freecam_arm')
    -- If your Orion loader tries to :Set on an old flag name, mirror it here.
    OrionLib.Flags = OrionLib.Flags or {}
    if not OrionLib.Flags["bypass_freecam_arm"] then
        OrionLib.Flags["bypass_freecam_arm"] = {
            Value = false, Save = true, Type = "Toggle",
            Set = function(val)
                -- Mirror into the current flag
                local f = OrionLib.Flags["bypass_use_game_freecam"]
                if f and f.Set then f:Set(val) end
            end
        }
    end
end
