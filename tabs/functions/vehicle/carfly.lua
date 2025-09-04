-- carfly_legacy.lua  – reiner Car Fly (angepasst für factory(SV, tab, OrionLib))
-- Features: Toggle + Keybind (X), kamera-ausgerichtet, SafeFly, Mobile-Panel,
-- sauberes Release beim Deaktivieren.

return function(SV, tab, OrionLib)
    print("*Heulemoji oder so*")
    ------------------------------
    -- Services / locals (nur für Fly)
    ------------------------------
    local Players     = game:GetService("Players")
    local RunService  = game:GetService("RunService")
    local UserInput   = game:GetService("UserInputService")
    local Workspace   = game:GetService("Workspace")

    local LP     = Players.LocalPlayer
    local Camera = (SV and SV.Camera) or Workspace.CurrentCamera

    local function notify(title, msg, t)
        pcall(function()
            OrionLib:MakeNotification({Name = title, Content = msg, Time = t or 3})
        end)
    end

    ------------------------------
    -- Vehicle helpers (minimal, prefer SV)
    ------------------------------
    local function VehiclesFolder()
        if SV and SV.VehiclesFolder then return SV.VehiclesFolder() end
        return Workspace:FindFirstChild("Vehicles") or Workspace:FindFirstChild("vehicles") or Workspace
    end

    local function myVehicleFolder()
        if SV and SV.myVehicleFolder then return SV.myVehicleFolder() end
        local vRoot = VehiclesFolder(); if not vRoot then return nil end
        local byName = vRoot:FindFirstChild(LP.Name)
        if byName then return byName end
        for _,m in ipairs(vRoot:GetChildren()) do
            if (m:IsA("Model") or m:IsA("Folder")) and (m.GetAttribute and m:GetAttribute("Owner") == LP.Name) then
                return m
            end
        end
        return nil
    end

    local function ensurePrimaryPart(model)
        if SV and SV.ensurePrimaryPart then return SV.ensurePrimaryPart(model) end
        if not model then return false end
        if model.PrimaryPart then return true end
        for _,d in ipairs(model:GetDescendants()) do
            if d:IsA("BasePart") then
                pcall(function() model.PrimaryPart = d end)
                if model.PrimaryPart then return true end
            end
        end
        return false
    end

    local function isSeated()
        if SV and SV.isSeated then return SV.isSeated() end
        local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
        return hum and hum.SeatPart ~= nil
    end

    ------------------------------
    -- Car Fly (nur im Auto)
    ------------------------------
    local flyEnabled   = false
    local flySpeed     = 130
    local safeFly      = false
    local flyConn      = nil
    local flyToggleUI  = nil
    local savedFlags   = {}
    local lastAirCF    = nil
    local toggleLockTS = 0
    local ROT_LERP     = 0.25 -- wie hart zur Kamera drehen (0..1)

    local function forEachPart(vf, fn)
        if not vf then return end
        for _,p in ipairs(vf:GetDescendants()) do
            if p:IsA("BasePart") then fn(p) end
        end
    end

    local function setFlightPhysics(vf, on)
        if not vf then return end
        if on then
            savedFlags = {}
            forEachPart(vf, function(bp)
                savedFlags[bp] = {Anchored = bp.Anchored, CanCollide = bp.CanCollide}
                bp.Anchored   = false
                bp.CanCollide = false
            end)
        else
            for bp,fl in pairs(savedFlags) do
                if bp and bp.Parent then
                    bp.Anchored   = fl.Anchored
                    bp.CanCollide = fl.CanCollide
                    bp.AssemblyLinearVelocity = Vector3.new(0,-10,0)
                end
            end
            savedFlags = {}
        end
    end

    local function settleToGround(v)
        if not v then return end
        local cf = v:GetPivot()
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Blacklist
        params.FilterDescendantsInstances = {v}
        local hit = Workspace:Raycast(cf.Position, Vector3.new(0,-1000,0), params)
        if hit then
            pcall(function()
                v:PivotTo(CFrame.new(hit.Position + Vector3.new(0,2,0),
                                     hit.Position + Vector3.new(0,2,0) + Camera.CFrame.LookVector))
            end)
        else
            pcall(function() v:PivotTo(cf + Vector3.new(0,-2,0)) end)
        end
    end

    local function toggleFly(state)
        local now = os.clock()
        if now - toggleLockTS < 0.25 then return end
        toggleLockTS = now

        if state == nil then state = not flyEnabled end
        if state and not isSeated() then
            notify("Car Fly","Nur im Auto nutzbar.")
            if flyToggleUI then flyToggleUI:Set(false) end
            return
        end
        if state == flyEnabled then return end

        flyEnabled = state
        _G.__Sorin_FlyActive = flyEnabled
        if flyToggleUI then flyToggleUI:Set(flyEnabled) end

        if flyConn then flyConn:Disconnect(); flyConn = nil end
        local vf = myVehicleFolder()
        if not vf then
            flyEnabled = false; _G.__Sorin_FlyActive = false
            if flyToggleUI then flyToggleUI:Set(false) end
            notify("Car Fly","Kein Fahrzeug.")
            return
        end
        ensurePrimaryPart(vf)

        if not flyEnabled then
            setFlightPhysics(vf, false)
            settleToGround(vf)
            notify("Car Fly","Deaktiviert.")
            return
        end

        setFlightPhysics(vf, true)
        lastAirCF = vf:GetPivot()
        notify("Car Fly", ("Aktiviert (Speed %d)"):format(flySpeed))

        flyConn = RunService.RenderStepped:Connect(function(dt)
            if not flyEnabled then return end
            if not isSeated() then toggleFly(false); return end

            local v = myVehicleFolder(); if not v then return end
            local root = v:GetPivot()

            local targetCF = CFrame.lookAt(root.Position, root.Position + Camera.CFrame.LookVector)
            local newCF    = root:Lerp(targetCF, math.clamp(ROT_LERP, 0, 1))

            local dir = Vector3.zero
            if UserInput:IsKeyDown(Enum.KeyCode.W) then dir += Camera.CFrame.LookVector end
            if UserInput:IsKeyDown(Enum.KeyCode.S) then dir -= Camera.CFrame.LookVector end
            if UserInput:IsKeyDown(Enum.KeyCode.D) then dir += Camera.CFrame.RightVector end
            if UserInput:IsKeyDown(Enum.KeyCode.A) then dir -= Camera.CFrame.RightVector end
            if UserInput:IsKeyDown(Enum.KeyCode.E) or UserInput:IsKeyDown(Enum.KeyCode.Space) then dir += Vector3.new(0,1,0) end
            if UserInput:IsKeyDown(Enum.KeyCode.Q) or UserInput:IsKeyDown(Enum.KeyCode.LeftControl) then dir -= Vector3.new(0,1,0) end

            if dir.Magnitude > 0 then
                dir = dir.Unit
                local step  = dir * (flySpeed * dt)
                local npos  = newCF.Position + step
                newCF = CFrame.new(npos, npos + Camera.CFrame.LookVector)
            end

            pcall(function() v:PivotTo(newCF) end)
            lastAirCF = newCF
        end)

        task.spawn(function()
            while flyEnabled do
                if not safeFly then task.wait(0.25)
                else
                    task.wait(6)
                    if not flyEnabled then break end
                    local v = myVehicleFolder(); if not v then break end
                    ensurePrimaryPart(v)
                    local before = v:GetPivot()

                    setFlightPhysics(v, false)
                    settleToGround(v)
                    task.wait(0.5)
                    setFlightPhysics(v, true)
                    pcall(function() v:PivotTo(before) end)
                    lastAirCF = before
                end
            end
        end)
    end

    RunService.Heartbeat:Connect(function()
        if flyEnabled and not isSeated() then
            toggleFly(false)
        end
    end)

    ------------------------------
    -- Mobile Fly Panel (optional)
    ------------------------------
    local function spawnMobileFly()
        local gui = Instance.new("ScreenGui")
        gui.Name = "Sorin_MobileFly"
        gui.ResetOnSpawn = false
        gui.IgnoreGuiInset = true
        gui.Enabled = false
        gui.Parent = game:GetService("CoreGui")

        local frame = Instance.new("Frame")
        frame.Size = UDim2.fromOffset(230, 160)
        frame.Position = UDim2.fromOffset(40, 300)
        frame.BackgroundColor3 = Color3.fromRGB(25,25,25)
        frame.Parent = gui
        Instance.new("UICorner", frame).CornerRadius = UDim.new(0,12)

        local title = Instance.new("TextLabel")
        title.Size = UDim2.new(1, -10, 0, 22)
        title.Position = UDim2.fromOffset(10, 6)
        title.BackgroundTransparency = 1
        title.Font = Enum.Font.GothamBold
        title.TextSize = 14
        title.TextColor3 = Color3.fromRGB(240,240,240)
        title.TextXAlignment = Enum.TextXAlignment.Left
        title.Text = "Car Fly"
        title.Parent = frame

        local hold = {F=false,B=false,L=false,R=false,U=false,D=false}
        local function mkBtn(txt, x, y, w, h, key)
            local b = Instance.new("TextButton")
            b.Size = UDim2.fromOffset(w,h); b.Position = UDim2.fromOffset(x,y)
            b.Text = txt; b.BackgroundColor3 = Color3.fromRGB(40,40,40)
            b.TextColor3 = Color3.fromRGB(230,230,230); b.Font = Enum.Font.GothamSemibold; b.TextSize = 14
            b.Parent = frame; Instance.new("UICorner", b).CornerRadius = UDim.new(0,8)
            b.MouseButton1Down:Connect(function()
                if not isSeated() then notify("Car Fly","Nur im Auto."); return end
                hold[key] = true
            end)
            b.MouseButton1Up:Connect(function() hold[key] = false end)
            b.MouseLeave:Connect(function() hold[key] = false end)
            return b
        end

        mkBtn("Toggle", 10, 34, 60, 28, "T").MouseButton1Click:Connect(function()
            if not isSeated() then notify("Car Fly","Nur im Auto."); return end
            toggleFly()
        end)
        mkBtn("^",      85, 34, 60, 28, "F")
        mkBtn("v",      85,100, 60, 28, "B")
        mkBtn("<<",     15, 67, 60, 28, "L")
        mkBtn(">>",     155,67, 60, 28, "R")
        mkBtn("Up",     155,34, 60, 28, "U")
        mkBtn("Down",   155,100,60, 28, "D")

        RunService.RenderStepped:Connect(function(dt)
            if not gui.Enabled or not flyEnabled then return end
            if not isSeated() then return end
            local v = myVehicleFolder(); if not v then return end

            local cf = v:GetPivot()
            local move = Vector3.zero
            if hold.F then move += Camera.CFrame.LookVector end
            if hold.B then move -= Camera.CFrame.LookVector end
            if hold.R then move += Camera.CFrame.RightVector end
            if hold.L then move -= Camera.CFrame.RightVector end
            if hold.U then move += Vector3.new(0,1,0) end
            if hold.D then move -= Vector3.new(0,1,0) end

            if move.Magnitude > 0 then
                move = move.Unit * (flySpeed * dt)
                v:PivotTo(CFrame.new(cf.Position + move, (cf.Position + move) + Camera.CFrame.LookVector))
            end
        end)

        return gui
    end
    local MobileFlyGui = spawnMobileFly()

    ------------------------------
    -- UI (nur für Fly)
    ------------------------------
    local secF  = tab:AddSection({ Name = "Car Fly" })

    flyToggleUI = secF:AddToggle({
        Name = "Enable Car Fly (nur im Auto)",
        Default = false,
        Callback = function(v) toggleFly(v) end
    })
    secF:AddBind({
        Name = "Car Fly Toggle Key",
        Default = Enum.KeyCode.X,
        Hold = false,
        Callback = function() toggleFly() end
    })
    secF:AddSlider({
        Name = "Fly Speed",
        Min = 10, Max = 190, Increment = 5,
        Default = 130,
        Callback = function(v) flySpeed = math.floor(v) end
    })
    secF:AddToggle({
        Name = "Safe Fly (alle 6s Boden, 0.5s)",
        Default = false,
        Callback = function(v) safeFly = v end
    })

    local secM  = tab:AddSection({ Name = "Mobile Fly" })
    secM:AddToggle({
        Name = "Mobile Fly Panel anzeigen",
        Default = false,
        Callback = function(v)
            if MobileFlyGui then MobileFlyGui.Enabled = v end
        end
    })
end
