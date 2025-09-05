-- tabs/functions/vehicle/vehicle/carfly.lua
-- Teleport-basierter Car Fly (PivotTo): kamera-ausgerichtet, SafeFly, sanfter Exit,
-- Toggle (X), optional Mobile-Panel-Hooks. Kein Anchoring, keine Velocity-Forces.

return function(SV, tab, OrionLib)
    print("fly mit neuer Funktion: Test")
    local RunService  = game:GetService("RunService")
    local UserInput   = game:GetService("UserInputService")
    local Workspace   = game:GetService("Workspace")
    local Camera      = SV.Camera

    -- === Tuning ===
    local DEFAULT_SPEED    = 130      -- studs/s
    local TURBO_KEY        = Enum.KeyCode.LeftControl
    local TURBO_MULT       = 2.5
    local ROT_LERP         = 0.22     -- wie schnell zur Kamera drehen [0..1]
    local LAND_SOFT_HEIGHT = 15       -- Exit-Höhe über Boden
    local SAFE_PERIOD      = 6.0
    local SAFE_HOLD        = 0.5
    local WEAK_NOCLIP      = true     -- während Fly CanCollide=false für Parts

    -- === State ===
    local fly = {
        enabled   = false,
        speed     = DEFAULT_SPEED,
        conn      = nil,
        safeTask  = nil,
        safeOn    = false,
        uiToggle  = nil,
        lastPivot = nil,
        toggleTS  = 0,
        savedCC   = {},                 -- CanCollide restore
        mobile    = {F=false,B=false,L=false,R=false,U=false,D=false},
    }

    local function notify(t,m,s) pcall(function()
        OrionLib:MakeNotification({Name=t, Content=m, Time=s or 3})
    end) end

    -- === Helpers ===
    local function myVehicle() return SV.myVehicleFolder() end
    local function ensurePP(v) SV.ensurePrimaryPart(v); return v and v.PrimaryPart end

    local function groundRay(v, depth)
        local cf = v:GetPivot()
        local rp = RaycastParams.new()
        rp.FilterType = Enum.RaycastFilterType.Blacklist
        rp.FilterDescendantsInstances = {v}
        return Workspace:Raycast(cf.Position, Vector3.new(0, -math.max(depth or 1000, 1), 0), rp)
    end

    local function pivotModel(v, cf)
        local ok = pcall(function() v:PivotTo(cf) end)
        if not ok and v.PrimaryPart then
            pcall(function() v:SetPrimaryPartCFrame(cf) end)
        end
    end

    local function saveCollide(v)
        if not WEAK_NOCLIP then return end
        fly.savedCC = {}
        for _,d in ipairs(v:GetDescendants()) do
            if d:IsA("BasePart") then
                fly.savedCC[d] = d.CanCollide
                d.CanCollide = false
            end
        end
    end
    local function restoreCollide()
        if not WEAK_NOCLIP then return end
        for p,cc in pairs(fly.savedCC) do
            if p and p.Parent then p.CanCollide = cc end
        end
        fly.savedCC = {}
    end

    local function softLand(v)
        local hit = groundRay(v, 1000)
        if hit then
            local pos  = hit.Position + Vector3.new(0, LAND_SOFT_HEIGHT, 0)
            local look = Camera.CFrame.LookVector
            pivotModel(v, CFrame.new(pos, pos + look))
        end
    end

    -- === Core step (Teleport) ===
    local function step(dt)
        if not fly.enabled then return end
        if not SV.isSeated() then return end

        local v = myVehicle(); if not v then return end
        local pp = ensurePP(v); if not pp then return end

        -- Input → Richtung relativ zur Kamera
        local dir = Vector3.zero
        if not UserInput:GetFocusedTextBox() then
            if UserInput:IsKeyDown(Enum.KeyCode.W) or fly.mobile.F then dir += Camera.CFrame.LookVector end
            if UserInput:IsKeyDown(Enum.KeyCode.S) or fly.mobile.B then dir -= Camera.CFrame.LookVector end
            if UserInput:IsKeyDown(Enum.KeyCode.D) or fly.mobile.R then dir += Camera.CFrame.RightVector end
            if UserInput:IsKeyDown(Enum.KeyCode.A) or fly.mobile.L then dir -= Camera.CFrame.RightVector end
            if UserInput:IsKeyDown(Enum.KeyCode.Space) or fly.mobile.U then dir += Vector3.new(0,1,0) end
            if UserInput:IsKeyDown(TURBO_KEY) then dir *= TURBO_MULT end
        end

        local cf = v:GetPivot()
        local newCF = cf

        -- Drehe Nase zur Kamera (smooth)
        local lookCF = CFrame.lookAt(cf.Position, cf.Position + Camera.CFrame.LookVector)
        newCF = cf:Lerp(lookCF, math.clamp(ROT_LERP, 0, 1))

        -- Bewegungsschritt (kein initialer Hoch-TP)
        if dir.Magnitude > 0 then
            dir = dir.Unit
            local stepVec = dir * (fly.speed * dt)
            local npos = newCF.Position + stepVec
            newCF = CFrame.new(npos, npos + Camera.CFrame.LookVector)
        end

        pivotModel(v, newCF)
        fly.lastPivot = newCF
    end

    -- === SafeFly: alle 6s kurz an den Boden, 0.5s halten, zurück ===
    local function startSafe()
        if fly.safeTask then task.cancel(fly.safeTask) end
        fly.safeTask = task.spawn(function()
            while fly.enabled do
                if not fly.safeOn then task.wait(0.25)
                else
                    task.wait(SAFE_PERIOD)
                    if not fly.enabled then break end
                    local v = myVehicle(); if not v then break end
                    local before = v:GetPivot()
                    local hit = groundRay(v, 1500)
                    if hit then
                        local lockCF = CFrame.new(
                            hit.Position + Vector3.new(0, 2, 0),
                            hit.Position + Vector3.new(0, 2, 0) + Camera.CFrame.LookVector
                        )
                        local t0 = os.clock()
                        while os.clock() - t0 < SAFE_HOLD and fly.enabled do
                            pivotModel(v, lockCF)
                            RunService.Heartbeat:Wait()
                        end
                        if fly.enabled then pivotModel(v, before) end
                    end
                end
            end
        end)
    end

    -- === Toggle ===
    local function setEnabled(on)
        if on == fly.enabled then return end
        local v = myVehicle()
        if on then
            if not v then notify("Car Fly","Kein Fahrzeug."); return end
            ensurePP(v)
            saveCollide(v)
            fly.lastPivot = v:GetPivot()
            if fly.conn then fly.conn:Disconnect() end
            fly.conn = RunService.RenderStepped:Connect(step)
            startSafe()
            fly.enabled = true
            if fly.uiToggle then fly.uiToggle:Set(true) end
            notify("Car Fly", ("Aktiviert (Speed %d)"):format(fly.speed), 2)
        else
            fly.enabled = false
            if fly.conn then fly.conn:Disconnect(); fly.conn=nil end
            if fly.safeTask then task.cancel(fly.safeTask); fly.safeTask=nil end
            if v then softLand(v) end
            restoreCollide()
            if fly.uiToggle then fly.uiToggle:Set(false) end
            notify("Car Fly","Deaktiviert.", 2)
        end
    end

    local function toggle()
        local now = os.clock()
        if now - fly.toggleTS < 0.18 then return end
        fly.toggleTS = now
        setEnabled(not fly.enabled)
    end

    -- === Mobile-Panel Hooks (optional) ===
    local function spawnMobileFly()
        local gui = Instance.new("ScreenGui")
        gui.Name = "Sorin_MobileFly"
        gui.ResetOnSpawn, gui.IgnoreGuiInset, gui.Enabled = false, true, false
        gui.Parent = game:GetService("CoreGui")

        local frame = Instance.new("Frame")
        frame.Size = UDim2.fromOffset(230, 160)
        frame.Position = UDim2.fromOffset(40, 300)
        frame.BackgroundColor3 = Color3.fromRGB(25,25,25)
        frame.Parent = gui
        Instance.new("UICorner", frame).CornerRadius = UDim.new(0,12)

        local function mkBtn(txt, x, y, w, h, key)
            local b = Instance.new("TextButton")
            b.Size = UDim2.fromOffset(w,h); b.Position = UDim2.fromOffset(x,y)
            b.Text = txt; b.BackgroundColor3 = Color3.fromRGB(40,40,40)
            b.TextColor3 = Color3.fromRGB(230,230,230); b.Font = Enum.Font.GothamSemibold; b.TextSize = 14
            b.Parent = frame; Instance.new("UICorner", b).CornerRadius = UDim.new(0,8)
            b.MouseButton1Down:Connect(function() fly.mobile[key] = true end)
            b.MouseButton1Up:Connect(function() fly.mobile[key] = false end)
            b.MouseLeave:Connect(function() fly.mobile[key] = false end)
            return b
        end

        mkBtn("Toggle", 10, 34, 60, 28, "T").MouseButton1Click:Connect(toggle)
        mkBtn("^",      85, 34, 60, 28, "F")
        mkBtn("v",      85,100, 60, 28, "B")
        mkBtn("<<",     15, 67, 60, 28, "L")
        mkBtn(">>",     155,67, 60, 28, "R")
        mkBtn("Up",     155,34, 60, 28, "U")
        mkBtn("Down",   155,100, 60, 28, "D")
        return gui
    end
    local MobileFlyGui = spawnMobileFly()

    -- === UI (kompakt) ===
    local sec = tab:AddSection({ Name = "Car Fly (Teleport)" })
    fly.uiToggle = sec:AddToggle({
        Name = "Enable (nur im Auto)",
        Default = false,
        Callback = function(v) setEnabled(v) end
    })
    sec:AddBind({
        Name = "Toggle Key",
        Default = Enum.KeyCode.X,
        Hold = false,
        Callback = function() toggle() end
    })
    sec:AddToggle({
        Name = "Safe Fly (alle 6s 0.5s Boden)",
        Default = false,
        Callback = function(v) fly.safeOn = v end
    })
    sec:AddToggle({
        Name = "Mobile Panel",
        Default = false,
        Callback = function(v) if MobileFlyGui then MobileFlyGui.Enabled = v end end
    })
    sec:AddSlider({
        Name = "Speed",
        Min = 10, Max = 300, Increment = 5,
        Default = DEFAULT_SPEED,
        Callback = function(v) fly.speed = math.floor(v) end
    })

    -- Auto-off wenn Sitz verlassen
    RunService.Heartbeat:Connect(function()
        if fly.enabled and not SV.isSeated() then setEnabled(false) end
    end)
end
