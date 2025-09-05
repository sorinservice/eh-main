-- Teleport-CarFly v3.0 – Hover-Lock + konstantes Steigen, inkl. Mobile Fly
print("[CarFly TP v3.0] loaded")

return function(SV, tab, OrionLib)
    local RS, UI, WS = game:GetService("RunService"), game:GetService("UserInputService"), game:GetService("Workspace")
    local Cam = SV.Camera

    -- ===== Tuning =====
    local BASE_SPEED    = 130
    local ACCEL_LERP    = 0.25
    local TURN_LERP     = 0.22
    local TURBO_KEY     = Enum.KeyCode.LeftControl
    local TURBO_MULT    = 2.2
    local CLIMB_SPEED   = 60       -- konstantes Steigen pro Sekunde (Space/MobileUp)
    local DESCEND_SPEED = 60       -- konstantes Sinken (Ctrl/MobileDown)
    local MAX_STEP      = 8

    -- ===== State =====
    local fly = {
        enabled=false, speed=BASE_SPEED, vel=Vector3.zero,
        conn=nil, uiToggle=nil, toggleTS=0,
        lastCF=nil, mobileHold={F=false,B=false,L=false,R=false,U=false,D=false}
    }

    local function note(t,m,s) pcall(function() OrionLib:MakeNotification({Name=t,Content=m,Time=s or 3}) end) end
    local function veh() return SV.myVehicleFolder() end
    local function ensurePP(v) SV.ensurePrimaryPart(v); return v and v.PrimaryPart end
    local function pivotTo(v,cf) pcall(function() v:PivotTo(cf) end) end

    -- ===== Kern-Step =====
    local function step(dt)
        if not fly.enabled or not SV.isSeated() then return end
        local v=veh(); if not v then return end
        local pp=ensurePP(v); if not pp then return end

        local want = Vector3.zero
        if not UI:GetFocusedTextBox() then
            if UI:IsKeyDown(Enum.KeyCode.W) or fly.mobileHold.F then want += Cam.CFrame.LookVector end
            if UI:IsKeyDown(Enum.KeyCode.S) or fly.mobileHold.B then want -= Cam.CFrame.LookVector end
            if UI:IsKeyDown(Enum.KeyCode.D) or fly.mobileHold.R then want += Cam.CFrame.RightVector end
            if UI:IsKeyDown(Enum.KeyCode.A) or fly.mobileHold.L then want -= Cam.CFrame.RightVector end
            if UI:IsKeyDown(Enum.KeyCode.Space) or fly.mobileHold.U then want += Vector3.new(0, CLIMB_SPEED/fly.speed, 0) end
            if UI:IsKeyDown(TURBO_KEY) or fly.mobileHold.D then want -= Vector3.new(0, DESCEND_SPEED/fly.speed, 0) end
        end

        -- Geschwindigkeit
        local targetVel = Vector3.zero
        if want.Magnitude > 0 then
            local horiz = Vector3.new(want.X,0,want.Z)
            if horiz.Magnitude > 0 then horiz = horiz.Unit * fly.speed end
            local vert = Vector3.new(0, want.Y * fly.speed, 0)
            targetVel = horiz + vert
        end

        -- Hover-Lock: wenn nichts gedrückt → alte CF halten
        if want.Magnitude == 0 and fly.lastCF then
            pivotTo(v, fly.lastCF)
            fly.vel = Vector3.zero
            return
        end

        -- Glätten
        fly.vel = fly.vel:Lerp(targetVel, math.clamp(ACCEL_LERP,0,1))
        local rawStep = fly.vel * dt
        if rawStep.Magnitude > MAX_STEP then rawStep = rawStep.Unit * MAX_STEP end

        -- Rotation zur Kamera
        local cf = v:GetPivot()
        local toCam = CFrame.lookAt(cf.Position, cf.Position + Cam.CFrame.LookVector)
        local rotCF = cf:Lerp(toCam, math.clamp(TURN_LERP,0,1))

        local nextCF = CFrame.new(rotCF.Position + rawStep, rotCF.Position + rawStep + Cam.CFrame.LookVector)
        pivotTo(v, nextCF)
        fly.lastCF = nextCF
    end

    -- ===== Toggle =====
    local function setEnabled(on)
        if on == fly.enabled then return end
        local v=veh()
        if on then
            if not v then note("Car Fly","Kein Fahrzeug."); return end
            ensurePP(v)
            fly.vel=Vector3.zero
            if fly.conn then fly.conn:Disconnect() end
            fly.conn=RS.RenderStepped:Connect(step)
            fly.enabled=true
            if fly.uiToggle then fly.uiToggle:Set(true) end
            note("Car Fly","Aktiviert",2)
        else
            fly.enabled=false
            if fly.conn then fly.conn:Disconnect(); fly.conn=nil end
            fly.lastCF=nil
            if fly.uiToggle then fly.uiToggle:Set(false) end
            note("Car Fly","Deaktiviert (free fall)",2)
        end
    end

    local function toggle()
        local now=os.clock()
        if now - fly.toggleTS < 0.2 then return end
        fly.toggleTS=now
        setEnabled(not fly.enabled)
    end

    -- ===== Mobile Panel =====
    local function spawnMobileFly()
        local gui=Instance.new("ScreenGui")
        gui.Name="Sorin_MobileFly"; gui.ResetOnSpawn=false; gui.IgnoreGuiInset=true; gui.Enabled=false
        gui.Parent=game:GetService("CoreGui")
        local frame=Instance.new("Frame")
        frame.Size=UDim2.fromOffset(230,160); frame.Position=UDim2.fromOffset(40,300)
        frame.BackgroundColor3=Color3.fromRGB(25,25,25); frame.Parent=gui
        Instance.new("UICorner",frame).CornerRadius=UDim.new(0,12)
        local function mkBtn(txt,x,y,w,h,key)
            local b=Instance.new("TextButton")
            b.Size=UDim2.fromOffset(w,h); b.Position=UDim2.fromOffset(x,y)
            b.Text=txt; b.BackgroundColor3=Color3.fromRGB(40,40,40)
            b.TextColor3=Color3.fromRGB(230,230,230); b.Font=Enum.Font.GothamSemibold; b.TextSize=14
            b.Parent=frame; Instance.new("UICorner",b).CornerRadius=UDim.new(0,8)
            b.MouseButton1Down:Connect(function() fly.mobileHold[key]=true end)
            b.MouseButton1Up:Connect(function() fly.mobileHold[key]=false end)
            b.MouseLeave:Connect(function() fly.mobileHold[key]=false end)
            return b
        end
        mkBtn("Toggle",10,34,60,28,"T").MouseButton1Click:Connect(toggle)
        mkBtn("^",85,34,60,28,"F"); mkBtn("v",85,100,60,28,"B")
        mkBtn("<<",15,67,60,28,"L"); mkBtn(">>",155,67,60,28,"R")
        mkBtn("Up",155,34,60,28,"U"); mkBtn("Down",155,100,60,28,"D")
        return gui
    end
    local MobileFlyGui=spawnMobileFly()

    -- ===== UI =====
    local sec=tab:AddSection({Name="Car Fly (TP Hover v3.0)"})
    fly.uiToggle=sec:AddToggle({Name="Enable",Default=false,Callback=function(v)setEnabled(v)end})
    sec:AddBind({Name="Toggle Key",Default=Enum.KeyCode.X,Hold=false,Callback=function()toggle()end})
    sec:AddToggle({Name="Mobile Panel",Default=false,Callback=function(v)if MobileFlyGui then MobileFlyGui.Enabled=v end end})
    sec:AddSlider({Name="Speed",Min=40,Max=300,Increment=5,Default=BASE_SPEED,Callback=function(v)fly.speed=math.floor(v)end})

    RS.Heartbeat:Connect(function() if fly.enabled and not SV.isSeated() then setEnabled(false) end end)
end
