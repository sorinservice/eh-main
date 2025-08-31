-- tabs/movement.lua
-- SorinHub - Movement Tab (executor-safe ranges)
-- Features:
-- 1) Walkspeed: 0.1..30 with toggle + T keybind
-- 2) Jump modifier: up to 50 (handles JumpPower/JumpHeight modes)
-- 3) Noclip: character parts non-collide while enabled
-- 4) Fly: simple client fly (NOTE: many games kick for fly detection)
-- 5) Escape Vehicle: break seat weld / unseat (with keybind)

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
    local function getHumanoid(char)
        char = char or LP.Character
        return char and char:FindFirstChildOfClass("Humanoid")
    end
    local function getHRP(char)
        char = char or LP.Character
        return char and char:FindFirstChild("HumanoidRootPart")
    end

    ----------------------------------------------------------------
    -- Walkspeed
    local WS = {
        enabled   = false,
        value     = 16,          -- will be overwritten by slider
        guardConn = nil,
        toggleObj = nil          -- reference to Orion toggle (so keybind can flip it)
    }
    local function applyWalkspeed(v)
        WS.value = math.clamp(v or WS.value, 0.1, 30)
        local hum = getHumanoid()
        if hum and WS.enabled then
            hum.WalkSpeed = WS.value
        end
    end
    local function startWalkspeed()
        if WS.enabled then return end
        WS.enabled = true
        local hum = getHumanoid()
        if hum then hum.WalkSpeed = WS.value end
        if not WS.guardConn then
            WS.guardConn = on(RunService.Stepped, function()
                if not WS.enabled then return end
                local h = getHumanoid()
                if h and math.abs(h.WalkSpeed - WS.value) > 0.05 then
                    h.WalkSpeed = WS.value
                end
            end, CONNS)
        end
    end
    local function stopWalkspeed()
        WS.enabled = false
        -- Do NOT force default (respect game). Just stop enforcing.
    end
    -- keep on respawn
    on(LP.CharacterAdded, function()
        if WS.enabled then
            task.defer(function()
                local hum = getHumanoid()
                if hum then hum.WalkSpeed = WS.value end
            end)
        end
    end, CONNS)

    ----------------------------------------------------------------
    -- Jump modifier (up to 50)
    local JM = { value = 50 }
    local function setJump(v)
        JM.value = math.clamp(v or JM.value, 0, 50)
        local hum = getHumanoid()
        if not hum then return end

        -- Roblox uses either JumpPower (UseJumpPower=true) or JumpHeight.
        -- Keep it simple: if JumpPower exists and UseJumpPower ~= false -> set JumpPower.
        -- Else set JumpHeight with an approximate conversion (Roblox default JP=50 ≈ JH=7.2)
        local okUse = (hum.UseJumpPower == nil) or (hum.UseJumpPower == true)
        if hum.JumpPower ~= nil and okUse then
            hum.JumpPower = JM.value
        elseif hum.JumpHeight ~= nil then
            -- scale JumpHeight roughly from JumpPower
            hum.JumpHeight = JM.value * (7.2/50)
        end
    end
    on(LP.CharacterAdded, function()
        task.defer(setJump, JM.value)
    end, CONNS)

    ----------------------------------------------------------------
    -- Noclip (character parts non-collide)
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
        local char = LP.Character
        if char then setPartsCollide(char, false) end
        NC.conn = on(RunService.Stepped, function()
            if not NC.enabled then return end
            local ch = LP.Character
            if ch then setPartsCollide(ch, false) end
        end, CONNS)
    end
    local function stopNoclip()
        NC.enabled = false
        local char = LP.Character
        if char then setPartsCollide(char, true) end
    end
    on(LP.CharacterAdded, function(ch)
        if NC.enabled then
            task.defer(setPartsCollide, ch, false)
        end
    end, CONNS)

    ----------------------------------------------------------------
    -- Fly (simple client fly; many games will kick -> warn in UI)
    local FL = {
        enabled = false,
        speed   = 40,
        conn    = nil,
        keyW=false,keyA=false,keyS=false,keyD=false,keySpace=false,keyShift=false,
        prevState = nil
    }
    local function startFly()
        if FL.enabled then return end
        FL.enabled = true

        -- freeze humanoid for more predictable fly
        local hum = getHumanoid()
        if hum then
            FL.prevState = hum:FindFirstChild("PlatformStand") and hum.PlatformStand or false
            hum.PlatformStand = true
        end

        FL.conn = on(RunService.RenderStepped, function(dt)
            if not FL.enabled then return end
            local hrp = getHRP()
            local cam = workspace.CurrentCamera
            if not (hrp and cam) then return end

            local dir = Vector3.zero
            local look = cam.CFrame.LookVector
            local right = cam.CFrame.RightVector

            if FL.keyW then dir += look end
            if FL.keyS then dir -= look end
            if FL.keyA then dir -= right end
            if FL.keyD then dir += right end
            if FL.keySpace then dir += Vector3.new(0,1,0) end
            if FL.keyShift then dir -= Vector3.new(0,1,0) end

            if dir.Magnitude > 0 then
                dir = dir.Unit
                hrp.CFrame = hrp.CFrame + (dir * FL.speed * dt)
            end
        end, CONNS)
    end
    local function stopFly()
        FL.enabled = false
        local hum = getHumanoid()
        if hum and FL.prevState ~= nil then
            hum.PlatformStand = FL.prevState
        end
    end
    -- input for fly controls
    on(UserInput.InputBegan, function(input, gpe)
        if gpe then return end
        local k = input.KeyCode
        if k == Enum.KeyCode.W then FL.keyW = true
        elseif k == Enum.KeyCode.A then FL.keyA = true
        elseif k == Enum.KeyCode.S then FL.keyS = true
        elseif k == Enum.KeyCode.D then FL.keyD = true
        elseif k == Enum.KeyCode.Space then FL.keySpace = true
        elseif k == Enum.KeyCode.LeftShift or k == Enum.KeyCode.RightShift then FL.keyShift = true
        end
    end, CONNS)
    on(UserInput.InputEnded, function(input, gpe)
        if gpe then return end
        local k = input.KeyCode
        if k == Enum.KeyCode.W then FL.keyW = false
        elseif k == Enum.KeyCode.A then FL.keyA = false
        elseif k == Enum.KeyCode.S then FL.keyS = false
        elseif k == Enum.KeyCode.D then FL.keyD = false
        elseif k == Enum.KeyCode.Space then FL.keySpace = false
        elseif k == Enum.KeyCode.LeftShift or k == Enum.KeyCode.RightShift then FL.keyShift = false
        end
    end, CONNS)
    on(LP.CharacterAdded, function()
        if FL.enabled then
            -- recover PlatformStand after respawn
            task.defer(function()
                local hum = getHumanoid()
                if hum then hum.PlatformStand = true end
            end)
        end
    end, CONNS)

    ----------------------------------------------------------------
    -- Escape Vehicle (break seat weld/unseat)
    local function escapeVehicle()
        local char = LP.Character
        local hum  = getHumanoid(char)
        if not (char and hum) then return end

        -- 1) clear SeatWeld / Welds to seat
        for _,d in ipairs(char:GetDescendants()) do
            if (d:IsA("Weld") or d:IsA("Motor6D") or d:IsA("Motor")) and d.Name:lower():find("seat") then
                pcall(function() d:Destroy() end)
            end
        end
        -- fallback: search any weld whose Part0/Part1 is a Seat
        for _,d in ipairs(char:GetDescendants()) do
            if d:IsA("Weld") then
                local ok, isSeat = pcall(function()
                    return (d.Part0 and d.Part0:IsA("Seat")) or (d.Part1 and d.Part1:IsA("Seat"))
                end)
                if ok and isSeat then pcall(function() d:Destroy() end) end
            end
        end

        -- 2) force unseat and upright
        pcall(function() hum.Sit = false end)
        pcall(function() hum.PlatformStand = false end)

        -- 3) nudge upward a bit to avoid instant re-seat
        local hrp = getHRP(char)
        if hrp then
            hrp.CFrame = hrp.CFrame + Vector3.new(0, 3, 0)
            -- clear unwanted velocities
            pcall(function() hrp.AssemblyLinearVelocity = Vector3.new() end)
            pcall(function() hrp.AssemblyAngularVelocity = Vector3.new() end)
        end
    end

    ----------------------------------------------------------------
    -- UI
    tab:AddSection({Name = "Walking"})
    -- Walkspeed Toggle + Slider + Keybind (T)
    WS.toggleObj = tab:AddToggle({
        Name = "Walkspeed Override",
        Default = false, Save = true, Flag = "mv_walkspeed_on",
        Callback = function(v)
            if v then startWalkspeed() else stopWalkspeed() end
        end
    })
    tab:AddSlider({
        Name = "Walkspeed",
        Min = 0.1, Max = 30, Increment = 0.1,
        Default = 16, ValueName = "stud/s",
        Save = true, Flag = "mv_walkspeed_val",
        Callback = function(v) applyWalkspeed(v) end
    })
    tab:AddBind({
        Name = "Toggle Walkspeed (T)",
        Default = Enum.KeyCode.T, Hold = false,
        Save = true, Flag = "mv_walkspeed_bind",
        Callback = function()
            if WS.toggleObj and WS.toggleObj.Set then
                WS.toggleObj:Set(not WS.toggleObj.Value)
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

    tab:AddSection({Name = "Collision & Fly"})
    tab:AddToggle({
        Name = "Noclip (no collisions)",
        Default = false, Save = true, Flag = "mv_noclip_on",
        Callback = function(v)
            if v then startNoclip() else stopNoclip() end
        end
    })
    tab:AddToggle({
        Name = "Fly (may be detected!)",
        Default = false, Save = true, Flag = "mv_fly_on",
        Callback = function(v)
            if v then
                startFly()
                OrionLib:MakeNotification({
                    Name = "Fly",
                    Content = "Warning: Many games kick for fly detection.",
                    Time = 4
                })
            else
                stopFly()
            end
        end
    })
    tab:AddSlider({
        Name = "Fly Speed",
        Min = 5, Max = 200, Increment = 1,
        Default = 40, ValueName = "stud/s",
        Save = true, Flag = "mv_fly_speed",
        Callback = function(v) FL.speed = v end
    })

    tab:AddSection({Name = "Vehicle"})
    tab:AddButton({
        Name = "Escape Vehicle (unseat)",
        Callback = function() escapeVehicle() end
    })
    tab:AddBind({
        Name = "Escape Vehicle Bind (G)",
        Default = Enum.KeyCode.G, Hold = false,
        Save = true, Flag = "mv_escape_bind",
        Callback = function() escapeVehicle() end
    })

    ----------------------------------------------------------------
    -- Initial application after UI builds (respect saved config)
    -- Orion will call .Set on saved Flags during OrionLib:Init(), so we only
    -- need to make sure current defaults won’t force anything prematurely.
    -- The callbacks above will run once the saved values are applied.
    -- (No extra boot logic required.)
end
