-- tabs/vehicle.lua
return function(tab, OrionLib)
    ----------------------------------------------------------------
    -- Vehicle Mod (dev-safe)
    -- - To Vehicle (teleport beside seat, press ProximityPrompt, sit)
    -- - Bring Vehicle (pivot near player, face player direction, sit)
    -- - License plate override (local) with persistence
    -- - Car Fly (keybind X, speed 10..190, safe fly every 6s)
    -- - Mobile Fly panel (draggable)
    ----------------------------------------------------------------

    local Players      = game:GetService("Players")
    local RunService   = game:GetService("RunService")
    local UserInput    = game:GetService("UserInputService")
    local HttpService  = game:GetService("HttpService")
    local Workspace    = game:GetService("Workspace")

    local LP           = Players.LocalPlayer
    local Camera       = Workspace.CurrentCamera

    -- Persistence (only license plate text, others are per-session)
    local SAVE_FOLDER = OrionLib and OrionLib.Folder or "SorinConfig"
    local SAVE_FILE   = (SAVE_FOLDER .. "/vehicle.json")

    local function safe_read_json(path)
        local ok, data = pcall(function()
            if isfile and isfile(path) then
                return HttpService:JSONDecode(readfile(path))
            end
            return nil
        end)
        return ok and data or nil
    end
    local function safe_write_json(path, tbl)
        pcall(function()
            if makefolder and not isfolder(SAVE_FOLDER) then makefolder(SAVE_FOLDER) end
            if writefile then writefile(path, HttpService:JSONEncode(tbl)) end
        end)
    end

    local CFG = { plateText = "" }
    do
        local saved = safe_read_json(SAVE_FILE)
        if type(saved) == "table" and type(saved.plateText) == "string" then
            CFG.plateText = saved.plateText
        end
    end
    local function save_cfg() safe_write_json(SAVE_FILE, { plateText = CFG.plateText }) end

    ----------------------------------------------------------------
    -- Vehicle lookup helpers
    ----------------------------------------------------------------
    local function VehiclesFolder()
        return Workspace:FindFirstChild("Vehicles") or Workspace:FindFirstChild("vehicles") or Workspace
    end
    local function myVehicleFolder()
        local vRoot = VehiclesFolder()
        if not vRoot then return nil end
        local byName = vRoot:FindFirstChild(LP.Name)
        if byName then return byName end
        for _,m in ipairs(vRoot:GetChildren()) do
            if m:IsA("Model") or m:IsA("Folder") then
                local ownerAttr = (m.GetAttribute and m:GetAttribute("Owner")) or nil
                if ownerAttr == LP.Name then return m end
            end
        end
        return nil
    end
    local function ensurePrimaryPart(model)
        if model and model.PrimaryPart then return true end
        if not model then return false end
        for _,d in ipairs(model:GetDescendants()) do
            if d:IsA("BasePart") then
                pcall(function() model.PrimaryPart = d end)
                if model.PrimaryPart then return true end
            end
        end
        return false
    end
    local function findDriveSeat(vFolder)
        if not vFolder then return nil end
        local ds = vFolder:FindFirstChild("DriveSeat", true)
        if ds and ds:IsA("Seat") then return ds end
        local seats = vFolder:FindFirstChild("Seats", true)
        if seats then
            for _,ch in ipairs(seats:GetDescendants()) do
                if ch:IsA("Seat") then return ch end
            end
        end
        for _,d in ipairs(vFolder:GetDescendants()) do
            if d:IsA("Seat") then return d end
        end
        return nil
    end
    local function findDriverPrompt(vFolder)
        if not vFolder then return nil end
        local nearest, best = nil, math.huge
        for _,pp in ipairs(vFolder:GetDescendants()) do
            if pp:IsA("ProximityPrompt") then
                local a = string.lower(pp.ActionText or "")
                local o = string.lower(pp.ObjectText or "")
                if a:find("fahrer") or o:find("fahrer") or a:find("driver") or o:find("driver") or a:find("seat") or o:find("seat") then
                    local pos = (pp.Parent and (pp.Parent.GetPivot and pp.Parent:GetPivot().Position))
                              or (pp.Parent and pp.Parent.Position) or Vector3.zero
                    local dist = (pos - pos).Magnitude -- zero, we just want the first reasonable one
                    if dist < best then best = dist; nearest = pp end
                end
            end
        end
        return nearest
    end
    local function pressPrompt(pp, tries)
        tries = tries or 8
        if not pp then return false end
        for _=1,tries do
            if typeof(fireproximityprompt) == "function" then
                pcall(function() fireproximityprompt(pp, math.max(pp.HoldDuration or 0.15, 0.1)) end)
            else
                pp:InputHoldBegin(); task.wait(math.max(pp.HoldDuration or 0.15, 0.1)); pp:InputHoldEnd()
            end
            task.wait(0.08)
            local seat = findDriveSeat(myVehicleFolder())
            local hum  = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
            if seat and hum and seat.Occupant == hum then return true end
        end
        return false
    end
    local function sitIn(seat)
        local char = LP.Character or LP.CharacterAdded:Wait()
        local hum  = char:FindFirstChildOfClass("Humanoid")
        if not (seat and hum) then return false end
        local vf = myVehicleFolder()
        local pp = findDriverPrompt(vf)
        if pp then
            local base = (pp.Parent and ((pp.Parent.GetPivot and pp.Parent:GetPivot()) or CFrame.new(pp.Parent.Position))) or CFrame.new(pp.Parent.Position)
            char:WaitForChild("HumanoidRootPart").CFrame = base * CFrame.new(-1.2, 1.4, 0.2)
            task.wait(0.05)
            if pressPrompt(pp, 10) then return true end
        end
        local ok = pcall(function() seat:Sit(hum) end)
        if ok and seat.Occupant == hum then return true end
        if hum.RootPart then
            hum:MoveTo(seat.Position + seat.CFrame.LookVector * -1)
            local t0 = time()
            while time() - t0 < 1.2 do
                task.wait()
                if seat.Occupant == hum then return true end
            end
            hum.RootPart.CFrame = seat.CFrame * CFrame.new(0, 0.1, -0.2)
        end
        return seat.Occupant == hum
    end

    ----------------------------------------------------------------
    -- Bring/To Vehicle
    ----------------------------------------------------------------
    local WARN_DISTANCE = 300
    local TO_OFFSET     = CFrame.new(-2.0, 0.5, 0)  -- player warp beside seat
    local BRING_OFFSET  = CFrame.new(0, 0, -3.5)    -- car appears in front of player

    local function toVehicle()
        local vf = myVehicleFolder()
        local seat = findDriveSeat(vf)
        if not (vf and seat) then
            OrionLib:MakeNotification({Name="Vehicle", Content="Kein eigenes Fahrzeug gefunden.", Time=3})
            return
        end
        local hrp = (LP.Character or LP.CharacterAdded:Wait()):WaitForChild("HumanoidRootPart")
        local dist = (hrp.Position - seat.Position).Magnitude
        if dist > WARN_DISTANCE then
            OrionLib:MakeNotification({Name="Vehicle", Content=("Achtung: weit entfernt (~%d studs)."):format(math.floor(dist)), Time=3})
        end
        hrp.CFrame = seat.CFrame * TO_OFFSET
        task.wait(0.05)
        sitIn(seat)
    end

    local function bringVehicle()
        local vf = myVehicleFolder()
        local seat = findDriveSeat(vf)
        if not (vf and seat) then
            OrionLib:MakeNotification({Name="Vehicle", Content="Kein eigenes Fahrzeug gefunden.", Time=3})
            return
        end
        local hrp = (LP.Character or LP.CharacterAdded:Wait()):WaitForChild("HumanoidRootPart")
        ensurePrimaryPart(vf)
        local baseCF = hrp.CFrame
        local targetCF = CFrame.lookAt( (baseCF * BRING_OFFSET).Position, (baseCF.Position + baseCF.LookVector) ) -- face where player looks
        pcall(function() vf:PivotTo(targetCF) end)
        task.wait(0.06)
        sitIn(findDriveSeat(vf))
    end

    ----------------------------------------------------------------
    -- License plate (local only)
    ----------------------------------------------------------------
    local function applyPlateTextTo(vFolder, txt)
        if not vFolder or not txt or txt == "" then return end
        local back = vFolder:FindFirstChild("LicensePlates", true) or vFolder:FindFirstChild("LicencePlates", true)
        local function setLabel(container)
            if not container then return end
            local gui = container:FindFirstChild("Gui", true)
            if gui and gui:FindFirstChild("TextLabel") then
                local tl = gui.TextLabel
                pcall(function() tl.Text = txt end)
            end
        end
        if back then
            setLabel(back:FindFirstChild("Back", true))
            setLabel(back:FindFirstChild("Front", true))
        else
            -- fallback: search any TextLabel named-like
            for _,d in ipairs(vFolder:GetDescendants()) do
                if d:IsA("TextLabel") and (d.Name == "TextLabel") then
                    pcall(function() d.Text = txt end)
                end
            end
        end
    end
    local function applyPlateToCurrent()
        local vf = myVehicleFolder()
        if vf and CFG.plateText ~= "" then
            applyPlateTextTo(vf, CFG.plateText)
            OrionLib:MakeNotification({Name="Vehicle", Content="Kennzeichen angewandt (lokal).", Time=2})
        else
            OrionLib:MakeNotification({Name="Vehicle", Content="Kein Fahrzeug oder leerer Text.", Time=2})
        end
    end

----------------------------------------------------------------
-- Car Fly (anchored, collisionless while flying)
----------------------------------------------------------------
local flyEnabled  = false
local flySpeed    = 60      -- adjustable 10..190
local safeFly     = false
local flyConn     = nil
local safeTick    = 0

-- we remember original physics flags to restore after flight
local savedFlags = {}  -- [BasePart] = {Anchored=bool, CanCollide=bool}

local function forEachPart(vf, fn)
    if not vf then return end
    for _,p in ipairs(vf:GetDescendants()) do
        if p:IsA("BasePart") then fn(p) end
    end
end

local function getVehicleRoot()
    local vf = myVehicleFolder()
    if not vf then return nil end
    ensurePrimaryPart(vf)
    return vf
end

local function setFlightPhysics(vf, on)
    if not vf then return end
    if on then
        savedFlags = {}
        forEachPart(vf, function(bp)
            savedFlags[bp] = {Anchored = bp.Anchored, CanCollide = bp.CanCollide}
            bp.Anchored   = true       -- freeze physics so PivotTo is absolute
            bp.CanCollide = false      -- prevent “sticking” to ground
        end)
    else
        for bp,flags in pairs(savedFlags) do
            if bp and bp.Parent then
                bp.Anchored   = flags.Anchored
                bp.CanCollide = flags.CanCollide
            end
        end
        savedFlags = {}
    end
end

local function toggleFly(state)
    if state == nil then state = not flyEnabled end
    if state == flyEnabled then return end
    flyEnabled = state

    if flyConn then flyConn:Disconnect(); flyConn = nil end

    local vf = getVehicleRoot()
    if not vf then
        flyEnabled = false
        OrionLib:MakeNotification({Name="Car Fly", Content="Kein Fahrzeug gefunden.", Time=2})
        return
    end

    if not flyEnabled then
        setFlightPhysics(vf, false)
        OrionLib:MakeNotification({Name="Car Fly", Content="Deaktiviert.", Time=2})
        return
    end

    setFlightPhysics(vf, true)  -- anchor & nocollide during flight
    OrionLib:MakeNotification({Name="Car Fly", Content="Aktiviert (X zum togglen).", Time=2})

    local lastCF = vf:GetPivot()
    safeTick = 0

    flyConn = RunService.RenderStepped:Connect(function(dt)
        if not flyEnabled then return end
        local vf2 = getVehicleRoot()
        if not vf2 then return end

        local rootCF = vf2:GetPivot()
        lastCF = rootCF

        -- build direction (WASD + E up / Q down; also Space up / LeftControl down)
        local dir = Vector3.zero
        if UserInput:IsKeyDown(Enum.KeyCode.W) then dir += Camera.CFrame.LookVector end
        if UserInput:IsKeyDown(Enum.KeyCode.S) then dir -= Camera.CFrame.LookVector end
        if UserInput:IsKeyDown(Enum.KeyCode.D) then dir += Camera.CFrame.RightVector end
        if UserInput:IsKeyDown(Enum.KeyCode.A) then dir -= Camera.CFrame.RightVector end
        if UserInput:IsKeyDown(Enum.KeyCode.E) or UserInput:IsKeyDown(Enum.KeyCode.Space) then dir += Vector3.new(0,1,0) end
        if UserInput:IsKeyDown(Enum.KeyCode.Q) or UserInput:IsKeyDown(Enum.KeyCode.LeftControl) then dir -= Vector3.new(0,1,0) end

        if dir.Magnitude > 0 then
            dir = dir.Unit
            local step = dir * (flySpeed * dt)
            local newPos = rootCF.Position + step
            local lookAt = newPos + (Camera.CFrame.LookVector)
            local newCF  = CFrame.lookAt(newPos, lookAt)
            pcall(function() vf2:PivotTo(newCF) end)
            lastCF = newCF
        end

        -- Safe Fly: tap ground every ~6s then return up
        if safeFly then
            safeTick += dt
            if safeTick >= 6 then
                safeTick = 0
                -- briefly allow collisions just to “touch”
                setFlightPhysics(vf2, false)
                local rayParams = RaycastParams.new()
                rayParams.FilterType = Enum.RaycastFilterType.Blacklist
                rayParams.FilterDescendantsInstances = {vf2}
                local from = vf2:GetPivot().Position
                local hit = Workspace:Raycast(from, Vector3.new(0,-1000,0), rayParams)
                if hit then
                    local groundCF = CFrame.new(hit.Position + Vector3.new(0, 2, 0), hit.Position + Vector3.new(0,2,0) + Camera.CFrame.LookVector)
                    pcall(function() vf2:PivotTo(groundCF) end)
                end
                task.wait(0.5)
                setFlightPhysics(vf2, true)
                if lastCF then pcall(function() vf2:PivotTo(lastCF) end) end
            end
        end
    end)
end

-- Keybind X for fly toggle
UserInput.InputBegan:Connect(function(inp, gpe)
    if gpe then return end
    if inp.KeyCode == Enum.KeyCode.X then
        toggleFly()
    end
end)

    -- Mobile Fly Panel (simple / draggable)
    local function spawnMobileFly()
        local gui = Instance.new("ScreenGui")
        gui.Name = "Sorin_MobileFly"
        gui.ResetOnSpawn = false
        gui.IgnoreGuiInset = true
        gui.Enabled = false
        gui.Parent = game:GetService("CoreGui")

        local frame = Instance.new("Frame")
        frame.Size = UDim2.fromOffset(220, 140)
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

        local function mkBtn(txt, x, y, w, h, cb)
            local b = Instance.new("TextButton")
            b.Size = UDim2.fromOffset(w,h)
            b.Position = UDim2.fromOffset(x,y)
            b.Text = txt
            b.BackgroundColor3 = Color3.fromRGB(40,40,40)
            b.TextColor3 = Color3.fromRGB(230,230,230)
            b.Font = Enum.Font.GothamSemibold
            b.TextSize = 14
            b.Parent = frame
            Instance.new("UICorner", b).CornerRadius = UDim.new(0,8)
            b.MouseButton1Click:Connect(cb)
            return b
        end

        local tgl = mkBtn("Toggle", 10, 34, 60, 28, function() toggleFly() end)
        local up  = mkBtn("Up",     80, 34, 60, 28, function()
            local vf = getVehicleRoot(); if not vf then return end
            local cf = vf:GetPivot(); vf:PivotTo(cf + Vector3.new(0, 3, 0))
        end)
        local dn  = mkBtn("Down",  150,34, 60, 28, function()
            local vf = getVehicleRoot(); if not vf then return end
            local cf = vf:GetPivot(); vf:PivotTo(cf + Vector3.new(0, -3, 0))
        end)
        mkBtn("<<",  10, 68, 60, 28, function()
            local vf = getVehicleRoot(); if not vf then return end
            local cf = vf:GetPivot(); vf:PivotTo(cf + (-Camera.CFrame.RightVector * 4))
        end)
        mkBtn(">>",  150,68,60, 28, function()
            local vf = getVehicleRoot(); if not vf then return end
            local cf = vf:GetPivot(); vf:PivotTo(cf + (Camera.CFrame.RightVector * 4))
        end)
        mkBtn("^",   80, 68, 60, 28, function()
            local vf = getVehicleRoot(); if not vf then return end
            local cf = vf:GetPivot(); vf:PivotTo(cf + (Camera.CFrame.LookVector * 6))
        end)
        mkBtn("v",   80, 102,60, 28, function()
            local vf = getVehicleRoot(); if not vf then return end
            local cf = vf:GetPivot(); vf:PivotTo(cf + (-Camera.CFrame.LookVector * 6))
        end)

        -- drag
        local dragging, start, startPos
        frame.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = true
                start = input.Position
                startPos = frame.Position
                input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then dragging = false end
                end)
            end
        end)
        UserInput.InputChanged:Connect(function(input)
            if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
                local dx = input.Position - start
                frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + dx.X, startPos.Y.Scale, startPos.Y.Offset + dx.Y)
            end
        end)

        return gui
    end
    local MobileFlyGui = spawnMobileFly()

    ----------------------------------------------------------------
    -- Orion UI
    ----------------------------------------------------------------
    local secV  = tab:AddSection({ Name = "Vehicle" })
    local secLP = tab:AddSection({ Name = "License Plate (local)" })
    local secF  = tab:AddSection({ Name = "Car Fly" })
    local secM  = tab:AddSection({ Name = "Mobile Fly" })

    secV:AddButton({ Name = "To Vehicle (auf Sitz & einsteigen)", Callback = toVehicle })
    secV:AddButton({ Name = "Bring Vehicle (vor dich & einsteigen)", Callback = bringVehicle })

    secLP:AddTextbox({
        Name = "Kennzeichen-Text",
        Default = CFG.plateText,
        TextDisappear = false,
        Callback = function(txt)
            CFG.plateText = tostring(txt or "")
            save_cfg()
        end
    })
    secLP:AddButton({ Name = "Kennzeichen auf aktuelles Fahrzeug anwenden", Callback = applyPlateToCurrent })

    secF:AddBind({
        Name = "Car Fly Toggle Key",
        Default = Enum.KeyCode.X,
        Hold = false,
        Callback = function() toggleFly() end
    })
    secF:AddSlider({
        Name = "Fly Speed",
        Min = 10, Max = 190, Increment = 5,
        Default = flySpeed,
        Callback = function(v) flySpeed = math.clamp(math.floor(v+0.5), 10, 190) end
    })
    secF:AddToggle({
        Name = "Safe Fly (alle 6s kurz Bodenkontakt)",
        Default = false,
        Callback = function(v) safeFly = v end
    })

    secM:AddToggle({
        Name = "Mobile Fly Panel einblenden",
        Default = false,
        Callback = function(v) if MobileFlyGui then MobileFlyGui.Enabled = v end end
    })

    -- auto-apply plate after (re)spawn if user saved one
    task.defer(function()
        if CFG.plateText ~= "" then
            -- small delay to let vehicle spawn
            task.wait(1.0)
            pcall(applyPlateToCurrent)
        end
    end)
end
