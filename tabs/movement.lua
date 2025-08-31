-- tabs/session_tools.lua
-- SorinHub - Session Tools (lazy-init, neutral labels, no side-effects on load)

return function(tab, OrionLib)
    local Players    = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local UserInput  = game:GetService("UserInputService")
    local LP = Players.LocalPlayer

    -- State buckets (connections to clean up)
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

    local function hum() local ch = LP.Character return ch and ch:FindFirstChildOfClass("Humanoid") end
    local function hrp() local ch = LP.Character return ch and ch:FindFirstChild("HumanoidRootPart") end

    -- Features (constructed only after "Test Mode" is enabled)
    local features = {
        move = {
            enabled = false,
            rate = 16,        -- WalkSpeed target (0.1..30)
            guard = nil,      -- RunService connection
            ui_toggle = nil,
        },
        jump = {
            value = 50,
            guard_added = false,
        },
        collide = {
            enabled = false,
            guard = nil,
        },
        free_move = { -- formerly "Fly" (optional, can be excluded initially)
            enabled = false,
            speed = 40,
            guard = nil,
            keys = {W=false,A=false,S=false,D=false,Up=false,Down=false},
            prevPlatformStand = nil
        },
        seat = {} -- seat release
    }

    local function applyMoveRate(v)
        local f = features.move
        f.rate = math.clamp(v or f.rate, 0.1, 30)
        local h = hum()
        if h and f.enabled then h.WalkSpeed = f.rate end
    end
    local function startMoveRate()
        local f = features.move
        if f.enabled then return end
        f.enabled = true
        local h = hum(); if h then h.WalkSpeed = f.rate end
        if not f.guard then
            f.guard = on(RunService.Heartbeat, function()
                if not f.enabled then return end
                local h2 = hum()
                if h2 and math.abs(h2.WalkSpeed - f.rate) > 0.05 then
                    h2.WalkSpeed = f.rate
                end
            end, CONNS)
        end
    end
    local function stopMoveRate()
        local f = features.move
        f.enabled = false
    end

    local function setJump(v)
        local j = features.jump
        j.value = math.clamp(v or j.value, 0, 50)
        local h = hum()
        if not h then return end
        local okUse = (h.UseJumpPower == nil) or (h.UseJumpPower == true)
        if h.JumpPower ~= nil and okUse then
            h.JumpPower = j.value
        elseif h.JumpHeight ~= nil then
            h.JumpHeight = j.value * (7.2/50)
        end
    end

    local function setPartsCollide(ch, collide)
        if not ch then return end
        for _,d in ipairs(ch:GetDescendants()) do
            if d:IsA("BasePart") then pcall(function() d.CanCollide = collide end) end
        end
    end
    local function startCollisionHelper()
        local c = features.collide
        if c.enabled then return end
        c.enabled = true
        local ch = LP.Character; if ch then setPartsCollide(ch, false) end
        c.guard = on(RunService.Heartbeat, function()
            if not c.enabled then return end
            local ch2 = LP.Character
            if ch2 then setPartsCollide(ch2, false) end
        end, CONNS)
    end
    local function stopCollisionHelper()
        local c = features.collide
        c.enabled = false
        local ch = LP.Character; if ch then setPartsCollide(ch, true) end
    end

    -- Optional: free-move (“fly-like”), EXCLUDE in first tests to avoid instant flags
    local function startFreeMove()
        local f = features.free_move
        if f.enabled then return end
        f.enabled = true
        local h = hum()
        if h then f.prevPlatformStand = h.PlatformStand; h.PlatformStand = true end
        f.guard = on(RunService.RenderStepped, function(dt)
            if not f.enabled then return end
            local root, cam = hrp(), workspace.CurrentCamera
            if not (root and cam) then return end
            local dir = Vector3.zero
            local look, right = cam.CFrame.LookVector, cam.CFrame.RightVector
            if f.keys.W then dir += look end
            if f.keys.S then dir -= look end
            if f.keys.A then dir -= right end
            if f.keys.D then dir += right end
            if f.keys.Up then dir += Vector3.new(0,1,0) end
            if f.keys.Down then dir -= Vector3.new(0,1,0) end
            if dir.Magnitude > 0 then
                root.CFrame = root.CFrame + dir.Unit * f.speed * dt
            end
        end, CONNS)
    end
    local function stopFreeMove()
        local f = features.free_move
        f.enabled = false
        local h = hum()
        if h and f.prevPlatformStand ~= nil then h.PlatformStand = f.prevPlatformStand end
    end

    local function seatRelease()
        local ch = LP.Character; local h = hum()
        if not (ch and h) then return end
        for _,d in ipairs(ch:GetDescendants()) do
            if (d:IsA("Weld") or d:IsA("Motor6D") or d:IsA("Motor")) and d.Name:lower():find("seat") then
                pcall(function() d:Destroy() end)
            end
        end
        for _,d in ipairs(ch:GetDescendants()) do
            if d:IsA("Weld") then
                local ok, isSeat = pcall(function()
                    return (d.Part0 and d.Part0:IsA("Seat")) or (d.Part1 and d.Part1:IsA("Seat"))
                end)
                if ok and isSeat then pcall(function() d:Destroy() end) end
            end
        end
        pcall(function() h.Sit = false end)
        pcall(function() h.PlatformStand = false end)
        local root = hrp()
        if root then
            root.CFrame = root.CFrame + Vector3.new(0, 3, 0)
            pcall(function() root.AssemblyLinearVelocity = Vector3.new() end)
            pcall(function() root.AssemblyAngularVelocity = Vector3.new() end)
        end
    end

    ----------------------------------------------------------------
    -- UI (neutral labels; nothing registers until Test Mode enabled)
    tab:AddSection({Name = "Session Controls"})
    local armed = false

    tab:AddToggle({
        Name = "Enable Test Mode",
        Default = false,
        Save = false, -- do not persist for first diagnostics
        Callback = function(v)
            armed = v
            -- Build or teardown sub-ui dynamically to avoid static signatures
            if v then
                -- Movement
                tab:AddSection({Name = "Movement"})
                features.move.ui_toggle = tab:AddToggle({
                    Name = "Move Rate Override",
                    Default = false, Save = false,
                    Callback = function(on) if on then startMoveRate() else stopMoveRate() end end
                })
                tab:AddSlider({
                    Name = "Move Rate",
                    Min = 0.1, Max = 30, Increment = 0.1, Default = 16,
                    Save = false,
                    Callback = function(val) applyMoveRate(val) end
                })

                -- Jump
                tab:AddSection({Name = "Jump"})
                tab:AddSlider({
                    Name = "Jump Modifier",
                    Min = 0, Max = 50, Increment = 1, Default = 50, Save = false,
                    Callback = function(val) setJump(val) end
                })

                -- Collision helper
                tab:AddSection({Name = "Collision"})
                tab:AddToggle({
                    Name = "Collision Helper (no collide)",
                    Default = false, Save = false,
                    Callback = function(on) if on then startCollisionHelper() else stopCollisionHelper() end end
                })

                -- Optional: Free-move (exclude in first pass; add later when needed)
                --[[
                tab:AddSection({Name = "Free Move"})
                tab:AddToggle({
                    Name = "Free Move (client-only)",
                    Default = false, Save = false,
                    Callback = function(on)
                        if on then startFreeMove() else stopFreeMove() end
                    end
                })
                tab:AddSlider({
                    Name = "Free Move Speed",
                    Min = 5, Max = 200, Increment = 1, Default = 40, Save = false,
                    Callback = function(v) features.free_move.speed = v end
                })
                ]]

                -- Seat tools
                tab:AddSection({Name = "Seat Tools"})
                tab:AddButton({ Name = "Seat Release", Callback = seatRelease })

            else
                -- Disarm: stop all features and remove connections
                disconnectAll(CONNS)
            end
        end
    })
end
