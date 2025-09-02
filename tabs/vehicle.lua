-- tabs/vehicle.lua
return function(tab, OrionLib)
    ---------------------------------------------------------------
    -- Vehicle Mod (SorinHub)
    -- - To Vehicle / Bring Vehicle (mit Sperren wenn bereits im Auto / Fly aktiv)
    -- - License Plate lokal + persistent
    -- - Car Fly (X / UI-Toggle), Safe Fly, Mobile Fly
    -- - Robust release beim Fly-Aus (kein "in der Luft hängen")
    ---------------------------------------------------------------
    local Players      = game:GetService("Players")
    local RunService   = game:GetService("RunService")
    local UserInput    = game:GetService("UserInputService")
    local HttpService  = game:GetService("HttpService")
    local Workspace    = game:GetService("Workspace")

    local LP      = Players.LocalPlayer
    local Camera  = Workspace.CurrentCamera

    local SAVE_FOLDER = OrionLib.Folder or "SorinConfig"
    local SAVE_FILE   = SAVE_FOLDER .. "/vehicle.json"

    local function notify(t, m, s) OrionLib:MakeNotification({Name=t, Content=m, Time=s or 3}) end
    local function read_json(path)
        local ok, res = pcall(function()
            if isfile and isfile(path) then return HttpService:JSONDecode(readfile(path)) end
        end)
        return ok and res or nil
    end
    local function write_json(path, tbl)
        pcall(function()
            if makefolder and not isfolder(SAVE_FOLDER) then makefolder(SAVE_FOLDER) end
            if writefile then writefile(path, HttpService:JSONEncode(tbl)) end
        end)
    end

    ----------------------------------------------------------------
    -- Persistenz (nur Kennzeichen-Text)
    ----------------------------------------------------------------
    local CFG = { plateText = "" }
    do
        local saved = read_json(SAVE_FILE)
        if type(saved) == "table" and type(saved.plateText) == "string" then
            CFG.plateText = saved.plateText
        end
    end
    local function save_cfg() write_json(SAVE_FILE, { plateText = CFG.plateText }) end

    ----------------------------------------------------------------
    -- Vehicle helpers
    ----------------------------------------------------------------
    local function VehiclesFolder()
        return Workspace:FindFirstChild("Vehicles") or Workspace:FindFirstChild("vehicles") or Workspace
    end
    local function myVehicleFolder()
        local root = VehiclesFolder(); if not root then return nil end
        local direct = root:FindFirstChild(LP.Name)
        if direct then return direct end
        for _,m in ipairs(root:GetChildren()) do
            if (m:IsA("Model") or m:IsA("Folder")) and m:GetAttribute("Owner") == LP.Name then
                return m
            end
        end
        return nil
    end
    local function ensurePrimaryPart(model)
        if not model then return false end
        if model.PrimaryPart then return true end
        for _,d in ipairs(model:GetDescendants()) do
            if d:IsA("BasePart") then model.PrimaryPart = d; if model.PrimaryPart then return true end end
        end
        return false
    end
    local function findDriveSeat(vf)
        if not vf then return nil end
        local s = vf:FindFirstChild("DriveSeat", true)
        if s and s:IsA("Seat") then return s end
        local seats = vf:FindFirstChild("Seats", true)
        if seats then
            for _,d in ipairs(seats:GetDescendants()) do
                if d:IsA("Seat") then return d end
            end
        end
        for _,d in ipairs(vf:GetDescendants()) do
            if d:IsA("Seat") then return d end
        end
        return nil
    end
    local function findDriverPrompt(vf)
        if not vf then return nil end
        for _,pp in ipairs(vf:GetDescendants()) do
            if pp:IsA("ProximityPrompt") then
                local a = string.lower(pp.ActionText or "")
                local o = string.lower(pp.ObjectText or "")
                if a:find("driver") or a:find("seat") or a:find("fahrer") or o:find("driver") or o:find("seat") or o:find("fahrer") then
                    return pp
                end
            end
        end
        return nil
    end

    local function isSeatedInOwnVehicle()
        local vf = myVehicleFolder(); if not vf then return false, nil, vf end
        local seat = findDriveSeat(vf); if not seat then return false, nil, vf end
        local hum  = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
        if hum and seat.Occupant == hum then return true, seat, vf end
        return false, seat, vf
    end

    local function pressPrompt(pp, tries)
        tries = tries or 12
        if not pp then return false end
        for _=1,tries do
            if typeof(fireproximityprompt) == "function" then
                pcall(function() fireproximityprompt(pp, math.max(pp.HoldDuration or 0.15, 0.1)) end)
            else
                pp:InputHoldBegin(); task.wait(math.max(pp.HoldDuration or 0.15, 0.1)); pp:InputHoldEnd()
            end
            task.wait(0.08)
            local okSeat = isSeatedInOwnVehicle()
            if okSeat then return true end
        end
        return false
    end

    local function sitIn(seat)
        local char = LP.Character or LP.CharacterAdded:Wait()
        local hum  = char:FindFirstChildOfClass("Humanoid")
        if not (seat and hum) then return false end

        -- 1) ProximityPrompt (bevorzugt)
        local vf = myVehicleFolder()
        local pp = vf and findDriverPrompt(vf) or nil
        if pp then
            local base = (pp.Parent and (pp.Parent.GetPivot and pp.Parent:GetPivot()) or CFrame.new(pp.Parent.Position)) or CFrame.new()
            char:WaitForChild("HumanoidRootPart").CFrame = base * CFrame.new(-1.2, 1.4, 0.2)
            task.wait(0.05)
            if pressPrompt(pp, 12) then return true end
        end

        -- 2) Direkt setzen
        local ok = pcall(function() seat:Sit(hum) end)
        if ok and seat.Occupant == hum then return true end

        -- 3) Vor den Sitz laufen (NICHT mehr "hinter" setzen)
        if hum.RootPart then
            hum:MoveTo(seat.Position + seat.CFrame.LookVector * 1)
            local t0 = time()
            while time() - t0 < 1.2 do
                task.wait()
                if seat.Occupant == hum then return true end
            end
        end
        return seat.Occupant == hum
    end

    ----------------------------------------------------------------
    -- Kennzeichen (lokal)
    ----------------------------------------------------------------
    local function applyPlateTextTo(vf, txt)
        if not (vf and txt and txt ~= "") then return end
        local lpRoot = vf:FindFirstChild("LicensePlates", true) or vf:FindFirstChild("LicencePlates", true)
        local function setLabel(container)
            if not container then return end
            local gui = container:FindFirstChild("Gui", true)
            if gui and gui:FindFirstChild("TextLabel") then
                pcall(function() gui.TextLabel.Text = txt end)
            end
        end
        if lpRoot then
            setLabel(lpRoot:FindFirstChild("Back", true))
            setLabel(lpRoot:FindFirstChild("Front", true))
        else
            for _,d in ipairs(vf:GetDescendants()) do
                if d:IsA("TextLabel") then pcall(function() d.Text = txt end) end
            end
        end
    end
    local function applyPlateToCurrent()
        local vf = myVehicleFolder()
        if vf and CFG.plateText ~= "" then
            applyPlateTextTo(vf, CFG.plateText)
            notify("Vehicle","Kennzeichen angewandt (lokal).",2)
        else
            notify("Vehicle","Kein Fahrzeug / leerer Text.",2)
        end
    end
    task.spawn(function()
        local vroot = VehiclesFolder(); if not vroot then return end
        vroot.ChildAdded:Connect(function(ch)
            task.wait(0.7)
            if ch and (ch.Name == LP.Name or ch:GetAttribute("Owner") == LP.Name) and CFG.plateText ~= "" then
                applyPlateTextTo(ch, CFG.plateText)
            end
        end)
    end)

    ----------------------------------------------------------------
    -- To / Bring Vehicle (mit Sperren)
    ----------------------------------------------------------------
    local WARN_DISTANCE = 300
    local TO_OFFSET     = CFrame.new(-2.0, 0.5, 0)
    local BRING_AHEAD   = 10
    local BRING_UP      = 2

    local function toVehicle()
        local seated = isSeatedInOwnVehicle()
        if seated then notify("Vehicle","Du sitzt bereits im Fahrzeug."); return end

        local vf = myVehicleFolder(); if not vf then notify("Vehicle","Kein eigenes Fahrzeug gefunden."); return end
        local seat = findDriveSeat(vf); if not seat then notify("Vehicle","Kein Fahrersitz gefunden."); return end

        local hrp = (LP.Character or LP.CharacterAdded:Wait()):WaitForChild("HumanoidRootPart")
        local dist = (hrp.Position - seat.Position).Magnitude
        if dist > WARN_DISTANCE then notify("Vehicle",("Achtung: weit entfernt (~%d studs)."):format(dist),3) end

        hrp.CFrame = seat.CFrame * TO_OFFSET
        task.wait(0.06)
        sitIn(seat)
    end

    local function bringVehicle()
        if isSeatedInOwnVehicle() then
            notify("Vehicle","Schon im Auto – Bring/To sind in der Fahrt deaktiviert.")
            return
        end
        -- falls Fly aktiv, ebenfalls blocken (siehe unten state)
        if _G.__Sorin_FlyActive then
            notify("Vehicle","Car Fly ist aktiv – erst deaktivieren.")
            return
        end

        local vf = myVehicleFolder(); if not vf then notify("Vehicle","Kein Fahrzeug gefunden."); return end
        ensurePrimaryPart(vf)

        local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        if not hrp then notify("Vehicle","Kein HRP."); return end

        local look = hrp.CFrame.LookVector
        local pos  = hrp.Position + look * BRING_AHEAD + Vector3.new(0, BRING_UP, 0)
        local cf   = CFrame.lookAt(pos, pos + look)
        pcall(function() vf:PivotTo(cf) end)

        local seat = findDriveSeat(vf)
        task.wait(0.05)
        if seat then sitIn(seat) end
    end

----------------------------------------------------------------
-- Car Fly (nur im Auto) – debounce & camera-aligned rotation
----------------------------------------------------------------
local flyEnabled   = false
local flySpeed     = 130
local safeFly      = false
local flyConn      = nil
local savedFlags   = {}
local flyToggleUI  = nil
local lastAirCF    = nil
local toggleLockTS = 0          -- prevents double-toggles within a short window
local ROT_LERP     = 0.25       -- wie aggressiv Richtung zur Kamera lerpen (0..1)

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
            bp.Anchored   = true
            bp.CanCollide = false
        end)
    else
        for bp,fl in pairs(savedFlags) do
            if bp and bp.Parent then
                bp.Anchored   = fl.Anchored
                bp.CanCollide = fl.CanCollide
                bp.AssemblyLinearVelocity = Vector3.new(0,-10,0) -- sanfter Down-Nudge
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
            v:PivotTo(CFrame.new(hit.Position + Vector3.new(0,2,0), hit.Position + Vector3.new(0,2,0) + Camera.CFrame.LookVector))
        end)
    else
        pcall(function() v:PivotTo(cf + Vector3.new(0,-2,0)) end)
    end
end

local function toggleFly(state)
    -- debounce: verhindere Doppel-Flip (z.B. durch UI & Bind im selben Frame)
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
    if flyToggleUI then flyToggleUI:Set(flyEnabled) end

    if flyConn then flyConn:Disconnect(); flyConn = nil end
    local vf = myVehicleFolder()
    if not vf then
        flyEnabled = false
        if flyToggleUI then flyToggleUI:Set(false) end
        notify("Car Fly","Kein Fahrzeug.")
        return
    end
    ensurePrimaryPart(vf)

    if not flyEnabled then
        setFlightPhysics(vf, false)
        settleToGround(vf)          -- verhindert “in der Luft hängen bleiben”
        notify("Car Fly","Deaktiviert.")
        return
    end

    setFlightPhysics(vf, true)
    lastAirCF = vf:GetPivot()
    notify("Car Fly", ("Aktiviert (Speed %d)"):format(flySpeed))

    flyConn = RunService.RenderStepped:Connect(function(dt)
        if not flyEnabled then return end
        local v = myVehicleFolder(); if not v then return end
        local root = v:GetPivot()
        lastAirCF = root

        -- Zielrotation: immer zur Kamera schauen
        local targetLookCF = CFrame.lookAt(root.Position, root.Position + Camera.CFrame.LookVector)
        -- optional weiches Rotations-Lerp
        local newCF = root:Lerp(targetLookCF, math.clamp(ROT_LERP, 0, 1))

        -- Bewegung basierend auf Input (kameraorientiert)
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

    -- SafeFly: alle 6s kurz Boden, dann exakt zur Luft-Position zurück
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


    ----------------------------------------------------------------
    -- Mobile Fly (Hold-Buttons, nur wenn im Auto)
    ----------------------------------------------------------------
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
                if not isSeatedInOwnVehicle() then notify("Car Fly","Nur im Auto."); return end
                hold[key] = true
            end)
            b.MouseButton1Up:Connect(function() hold[key] = false end)
            b.MouseLeave:Connect(function() hold[key] = false end)
            return b
        end

        mkBtn("Toggle", 10, 34, 60, 28, "T").MouseButton1Click:Connect(function()
            if not isSeatedInOwnVehicle() then notify("Car Fly","Nur im Auto."); return end
            -- mirror UI toggle
            suppressFlyCB = true
            flyToggleUI:Set(not flyEnabled)
            suppressFlyCB = false
            toggleFly(not flyEnabled)
        end)
        mkBtn("^",      85, 34, 60, 28, "F")
        mkBtn("v",      85,100, 60, 28, "B")
        mkBtn("<<",     15, 67, 60, 28, "L")
        mkBtn(">>",     155,67, 60, 28, "R")
        mkBtn("Up",     155,34, 60, 28, "U")
        mkBtn("Down",   155,100,60, 28, "D")

        -- Drag über Titelzeile
        local dragging, start, startPos
        frame.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 and input.Position.Y - frame.AbsolutePosition.Y <= 30 then
                dragging = true; start = input.Position; startPos = frame.Position
                input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then dragging = false end
                end)
            end
        end)
        UserInput.InputChanged:Connect(function(input)
            if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
                local d = input.Position - start
                frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
            end
        end)

        -- Bewegung während Hold
        RunService.RenderStepped:Connect(function(dt)
            if not gui.Enabled or not flyEnabled then return end
            local seated, _, vfx = isSeatedInOwnVehicle()
            if not seated or not vfx then return end

            local cf = vfx:GetPivot()
            local move = Vector3.zero
            if hold.F then move += Camera.CFrame.LookVector end
            if hold.B then move -= Camera.CFrame.LookVector end
            if hold.R then move += Camera.CFrame.RightVector end
            if hold.L then move -= Camera.CFrame.RightVector end
            if hold.U then move += Vector3.new(0,1,0) end
            if hold.D then move -= Vector3.new(0,1,0) end

            if move.Magnitude > 0 then
                move = move.Unit * (flySpeed * dt)
                vfx:PivotTo(CFrame.new(cf.Position + move, (cf.Position + move) + Camera.CFrame.LookVector))
            end
        end)

        return gui
    end
    local MobileFlyGui = spawnMobileFly()

    ----------------------------------------------------------------
    -- UI (Orion)
    ----------------------------------------------------------------
    local secV  = tab:AddSection({ Name = "Vehicle" })
    local secLP = tab:AddSection({ Name = "License Plate (local)" })
    local secF  = tab:AddSection({ Name = "Car Fly" })
    local secM  = tab:AddSection({ Name = "Mobile Fly" })

    secV:AddButton({ Name = "To Vehicle (auf Sitz & einsteigen)",    Callback = function()
        -- block, wenn schon im Auto oder Fly aktiv
        if isSeatedInOwnVehicle() then notify("Vehicle","Schon im Fahrzeug."); return end
        if _G.__Sorin_FlyActive then notify("Vehicle","Car Fly aktiv – erst deaktivieren."); return end
        toVehicle()
    end })

    secV:AddButton({ Name = "Bring Vehicle (vor dich & einsteigen)", Callback = function()
        if isSeatedInOwnVehicle() then notify("Vehicle","Schon im Fahrzeug."); return end
        if _G.__Sorin_FlyActive then notify("Vehicle","Car Fly aktiv – erst deaktivieren."); return end
        bringVehicle()
    end })

    secLP:AddTextbox({
        Name = "Kennzeichen-Text",
        Default = CFG.plateText,
        TextDisappear = false,
        Callback = function(txt)
            CFG.plateText = tostring(txt or "")
            save_cfg()
        end
    })
    secLP:AddButton({ Name = "Kennzeichen anwenden (aktuelles Fahrzeug)", Callback = applyPlateToCurrent })

    -- Car Fly UI (ersetzen)
flyToggleUI = secF:AddToggle({
    Name = "Enable Car Fly (nur im Auto)",
    Default = false,
    Callback = function(v) toggleFly(v) end
})
secF:AddBind({
    Name = "Car Fly Toggle Key",
    Default = Enum.KeyCode.X,
    Hold = false,
    Callback = function() toggleFly() end   -- spiegelt Toggle, Debounce schützt
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

    secM:AddToggle({
        Name = "Mobile Fly Panel anzeigen",
        Default = false,
        Callback = function(v) if MobileFlyGui then MobileFlyGui.Enabled = v end end
    })

    -- Kennzeichen beim Join anwenden (falls gesetzt)
    task.defer(function()
        if CFG.plateText ~= "" then
            task.wait(1.0)
            pcall(applyPlateToCurrent)
        end
    end)
end
