-- tabs/bypass.lua
-- VoiceChat helpers + Freecam arming (Shift+P). Tries Roblox's built-in Freecam if accessible; falls back to custom.
-- UI text & comments in English.

return function(tab, OrionLib)
    print("bypass loaded version: 1")
    ----------------------------------------------------------------
    -- Services
    local Players               = game:GetService("Players")
    local VoiceChatService      = game:GetService("VoiceChatService")
    local UserInputService      = game:GetService("UserInputService")
    local RunService            = game:GetService("RunService")
    local ContextActionService  = game:GetService("ContextActionService")
    local Workspace             = game:GetService("Workspace")

    local LP     = Players.LocalPlayer
    local Camera = Workspace.CurrentCamera

    local function notify(title, text, t)
        OrionLib:MakeNotification({ Name = title or "Info", Content = tostring(text or ""), Time = t or 3 })
    end

    ----------------------------------------------------------------
    -- ========================== VoiceChat =========================
    local statusPara = tab:AddParagraph("VoiceChat Status", "Checking...")

    local function setStatus(txt) pcall(function() statusPara:Set(txt) end) end

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
        if ok and state ~= nil then table.insert(parts, "State: "..tostring(state)) end
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
            notify("VoiceChat", ok and "Join attempt sent." or ("Join failed: "..tostring(err)), ok and 3 or 5)
            task.delay(0.5, function() setStatus(readStateString()) end)
        end
    })

    pcall(function()
        if typeof(VoiceChatService.PlayerVoiceChatStateChanged) == "RBXScriptSignal" then
            VoiceChatService.PlayerVoiceChatStateChanged:Connect(function(userId, state)
                if userId == LP.UserId then
                    setStatus("State: "..tostring(state).."  |  "..(isEnabledForUser() and "Eligible: yes" or "Eligible: no"))
                end
            end)
        end
    end)

    ----------------------------------------------------------------
    -- =========================== Freecam =========================
    -- Goal: Arm via UI; toggle with Shift+P.
    -- 1) Try to call Roblox's internal Freecam module if present (used on private/admin servers).
    -- 2) Otherwise, use our custom Freecam:
    --    - Hold RMB to rotate (mouse look)
    --    - Wheel = FOV zoom (forward = zoom in)
    --    - WASD move, Q/E up/down
    --    - ↑ / ↓ speed up/down
    --    - Player movement is disabled during Freecam
    ----------------------------------------------------------------

    -- Attempt to discover a baked-in "Freecam" module (executor-dependent).
    local RBXFC = {
        mod = nil,
        toggle = nil,  -- function() start/stop
        start = nil,   -- optional explicit start
        stop  = nil,   -- optional explicit stop
    }

    local function findRobloxFreecam()
        -- Best-effort: scan loaded modules for something called "Freecam".
        local ok, mods = pcall(function()
            return (typeof(getloadedmodules)=="function") and getloadedmodules() or {}
        end)
        if ok and type(mods)=="table" then
            for _,m in ipairs(mods) do
                local name = tostring(m):lower()
                if name:find("freecam") then
                    local ok2, mod = pcall(require, m)
                    if ok2 and type(mod)=="table" then
                        -- guess the API (seen variants in the wild)
                        RBXFC.mod = mod
                        RBXFC.toggle = mod.Toggle or mod.toggle or mod.ToggleFreecam or mod.ToggleFreeCam
                        RBXFC.start  = mod.Start  or mod.start  or mod.Enable or mod.enable
                        RBXFC.stop   = mod.Stop   or mod.stop   or mod.Disable or mod.disable
                        return true
                    end
                end
            end
        end
        -- Optional: try CoreGui path (can be protected; pcall anyway)
        local cg = game:GetService("CoreGui")
        local okcg, robloxGui = pcall(function() return cg:FindFirstChild("RobloxGui") end)
        if okcg and robloxGui then
            for _,desc in ipairs(robloxGui:GetDescendants()) do
                if desc:IsA("ModuleScript") and desc.Name:lower():find("freecam") then
                    local ok2, mod = pcall(require, desc)
                    if ok2 and type(mod)=="table" then
                        RBXFC.mod = mod
                        RBXFC.toggle = mod.Toggle or mod.toggle or mod.ToggleFreecam or mod.ToggleFreeCam
                        RBXFC.start  = mod.Start  or mod.start  or mod.Enable or mod.enable
                        RBXFC.stop   = mod.Stop   or mod.stop   or mod.Disable or mod.disable
                        return true
                    end
                end
            end
        end
        return false
    end

    -- Custom fallback Freecam
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
        fovTarget  = nil,
        sens       = 0.15,      -- deg per pixel
        conns      = {},
        keys       = {},
        saved      = {},
        controls   = nil
    }

    local function disconnectAll()
        for _,c in ipairs(FC.conns) do pcall(function() c:Disconnect() end) end
        FC.conns = {}
    end

    local function getControls()
        local pm = LP:FindFirstChild("PlayerScripts") and LP.PlayerScripts:FindChildOfClass("ModuleScript") -- PlayerModule may be multiple variants
        pm = LP.PlayerScripts:FindFirstChild("PlayerModule") or pm
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
        local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
        if hum then
            FC.saved.walkspeed  = hum.WalkSpeed
            FC.saved.autorotate = hum.AutoRotate
        end
        FC.saved.mouseBehavior = UserInputService.MouseBehavior
    end

    local function restoreState()
        Camera.CameraType    = FC.saved.cameraType or Enum.CameraType.Custom
        Camera.CameraSubject = FC.saved.subject or LP.Character
        Camera.CFrame        = FC.saved.cframe or Camera.CFrame
        Camera.FieldOfView   = FC.saved.fov or Camera.FieldOfView
        UserInputService.MouseBehavior = FC.saved.mouseBehavior or Enum.MouseBehavior.Default
        local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
        if hum then
            if FC.saved.walkspeed  ~= nil then hum.WalkSpeed  = FC.saved.walkspeed end
            if FC.saved.autorotate ~= nil then hum.AutoRotate = FC.saved.autorotate end
        end
        if FC.controls then pcall(function() FC.controls:Enable() end) end
        ContextActionService:UnbindAction("Sorin_BlockMovement")
    end

    local function radians(deg) return deg * math.pi/180 end

    local function startFreecamCustom()
        if FC.enabled then return end
        FC.enabled = true
        saveState()

        FC.camCF     = Camera.CFrame
        FC.fovTarget = Camera.FieldOfView
        local x, y = FC.camCF:ToEulerAnglesYXZ()
        FC.pitch, FC.yaw = math.deg(x), math.deg(y)

        Camera.CameraType = Enum.CameraType.Scriptable

        FC.controls = getControls()
        if FC.controls then pcall(function() FC.controls:Disable() end) end

        local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
        if hum then
            hum.WalkSpeed = 0
            hum.AutoRotate = false
        end

        ContextActionService:BindAction("Sorin_BlockMovement", function() return Enum.ContextActionResult.Sink end, false,
            Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D,
            Enum.KeyCode.Space, Enum.KeyCode.Q, Enum.KeyCode.E,
            Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift)

        table.insert(FC.conns, UserInputService.InputBegan:Connect(function(input, gp)
            if gp then return end
            if input.UserInputType == Enum.UserInputType.MouseButton2 then
                FC.rotHold = true
                UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
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
                FC.rotHold = false
                UserInputService.MouseBehavior = Enum.MouseBehavior.Default
            elseif input.UserInputType == Enum.UserInputType.Keyboard then
                FC.keys[input.KeyCode] = nil
            end
        end))

        -- Wheel = FOV zoom (forward = zoom in)
        table.insert(FC.conns, UserInputService.InputChanged:Connect(function(input, gp)
            if gp or not FC.enabled then return end
            if input.UserInputType == Enum.UserInputType.MouseWheel then
                local delta = input.Position.Z -- +1 forward, -1 back
                FC.fovTarget = math.clamp(FC.fovTarget - (delta * 4), 20, 100)
            end
        end))

        table.insert(FC.conns, RunService.RenderStepped:Connect(function(dt)
            if not FC.enabled then return end

            -- rotate while RMB held
            if FC.rotHold then
                local md = UserInputService:GetMouseDelta()
                FC.yaw   = FC.yaw   - (md.X * FC.sens)
                FC.pitch = math.clamp(FC.pitch - (md.Y * FC.sens), -85, 85)
            end
            local rot = CFrame.fromEulerAnglesYXZ(radians(FC.pitch), radians(FC.yaw), 0)

            -- movement (A/D strafes using RightVector)
            local move  = Vector3.zero
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
            if FC.keys[Enum.KeyCode.LeftShift] or FC.keys[Enum.KeyCode.RightShift] then mult *= 2 end
            if FC.keys[Enum.KeyCode.LeftControl] or FC.keys[Enum.KeyCode.RightControl] then mult *= 0.5 end

            if move.Magnitude > 0 then
                FC.camCF = FC.camCF + (move.Unit * (FC.speed * mult * dt))
            end

            -- smooth FOV toward target
            Camera.FieldOfView = Camera.FieldOfView + (FC.fovTarget - Camera.FieldOfView) * 0.2

            -- apply camera
            Camera.CFrame = CFrame.new(FC.camCF.Position) * rot
        end))

        notify("Freecam", "Active (RMB look, Wheel = zoom, ↑/↓ speed).", 3)
    end

    local function stopFreecamCustom()
        if not FC.enabled then return end
        FC.enabled = false
        disconnectAll()
        UserInputService.MouseBehavior = Enum.MouseBehavior.Default
        restoreState()
        notify("Freecam", "Disabled.", 2)
    end

    -- Unified toggler: prefer Roblox mod if available, else custom.
    local ROBLOX_FC_FOUND = findRobloxFreecam()

    local function toggleFreecam()
        if ROBLOX_FC_FOUND and (RBXFC.toggle or RBXFC.start or RBXFC.stop) then
            -- Try toggle. If not present, emulate with start/stop by tracking state via a flag in RBXFC.mod if exists.
            local did = false
            if RBXFC.toggle then
                local ok = pcall(RBXFC.toggle)
                did = ok and true or false
            else
                -- naive: if we ever started, call stop next time
                RBXFC._on = not RBXFC._on
                if RBXFC._on and RBXFC.start then
                    pcall(RBXFC.start)
                    did = true
                elseif (not RBXFC._on) and RBXFC.stop then
                    pcall(RBXFC.stop)
                    did = true
                end
            end
            if not did then
                -- fall back if calling failed
                ROBLOX_FC_FOUND = false
                if FC.enabled then stopFreecamCustom() else startFreecamCustom() end
            end
        else
            if FC.enabled then stopFreecamCustom() else startFreecamCustom() end
        end
    end

    local armConn
    local function setArmed(on)
        if armConn then armConn:Disconnect(); armConn = nil end
        if on then
            armConn = UserInputService.InputBegan:Connect(function(input, gp)
                if gp then return end
                if input.KeyCode == Enum.KeyCode.P and (UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)) then
                    toggleFreecam()
                end
            end)
            notify("Freecam", ROBLOX_FC_FOUND and "Armed (Roblox Freecam). Use Shift+P." or "Armed (Custom Freecam). Use Shift+P.", 3)
        else
            -- ensure off
            if FC.enabled then stopFreecamCustom() end
            if RBXFC._on and RBXFC.stop then pcall(RBXFC.stop) RBXFC._on=false end
            notify("Freecam", "Disarmed.", 2)
        end
    end

    -- UI (only arming toggle)
    tab:AddSection({ Name = "Freecam" })
    tab:AddToggle({
        Name = "Enable Freecam (Shift+P)",
        Default = false, Save = true, Flag = "bypass_freecam_arm",
        Callback = function(v) setArmed(v) end
    })
end
