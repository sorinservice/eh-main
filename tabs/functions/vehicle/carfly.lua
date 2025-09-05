-- Teleport-CarFly v2.2 – free-fall on exit, takeoff assist, clearance clamp
print("[CarFly TP v2.2] loaded")

return function(SV, tab, OrionLib)
    local RS, UI, WS = game:GetService("RunService"), game:GetService("UserInputService"), game:GetService("Workspace")
    local Cam = SV.Camera

    -- ===== Tuning =====
    local BASE_SPEED       = 130      -- stud/s
    local ACCEL_LERP       = 0.28
    local TURN_LERP        = 0.22
    local TURBO_KEY        = Enum.KeyCode.LeftControl
    local TURBO_MULT       = 2.4
    local CLIMB_RATE       = 85       -- reines Steigen/Sinken
    local NEAR_GROUND_BIAS = 12       -- kleiner Up-Bias wenn bodennah
    local GROUND_PROBE     = 6        -- „sehr nah“?
    local MIN_CLEARANCE    = 3.5      -- hart einzuhaltende Bodenfreiheit
    local TAKEOFF_TIME     = 0.35     -- so lange hilft die Takeoff-Assist
    local MAX_STEP         = 8        -- max. Teleport je Frame (Anti-Flag)
    local SAFE_PERIOD      = 6.0
    local SAFE_HOLD        = 0.5
    local LAND_HEIGHT      = 15       -- (nur für SafeFly-Lock; Exit nutzt free-fall)
    local WEAK_NOCLIP      = true

    -- ===== State =====
    local fly = {
        enabled=false, speed=BASE_SPEED,
        vel=Vector3.zero, conn=nil, safeTask=nil, safeOn=false,
        uiToggle=nil, toggleTS=0, savedCC={}, takeoffUntil=0
    }

    local function note(t,m,s) pcall(function()
        OrionLib:MakeNotification({Name=t, Content=m, Time=s or 3})
    end) end

    -- ===== helpers =====
    local function veh() return SV.myVehicleFolder() end
    local function ensurePP(v) SV.ensurePrimaryPart(v); return v and v.PrimaryPart end
    local function rayDownFrom(pos, v, depth)
        local rp=RaycastParams.new()
        rp.FilterType=Enum.RaycastFilterType.Blacklist
        rp.FilterDescendantsInstances={v}
        return WS:Raycast(pos, Vector3.new(0,-math.max(depth or 1,1),0), rp)
    end
    local function rayDown(v, depth) return rayDownFrom(v:GetPivot().Position, v, depth) end

    local function pivotTo(v, cf)
        local ok = pcall(function() v:PivotTo(cf) end)
        if not ok and v.PrimaryPart then
            pcall(function() v:SetPrimaryPartCFrame(cf) end)
        end
    end

    local function saveCollide(v)
        if not WEAK_NOCLIP then return end
        fly.savedCC={}
        for _,d in ipairs(v:GetDescendants()) do
            if d:IsA("BasePart") then
                fly.savedCC[d]=d.CanCollide
                d.CanCollide=false
            end
        end
    end
    local function restoreCollide()
        if not WEAK_NOCLIP then return end
        for p,cc in pairs(fly.savedCC) do
            if p and p.Parent then p.CanCollide=cc end
        end
        fly.savedCC={}
    end

    -- ===== Kern: Teleport-Step mit Takeoff & Clearance-Clamp =====
    local function step(dt)
        if not fly.enabled or not SV.isSeated() then return end
        local v=veh(); if not v then return end
        local pp=ensurePP(v); if not pp then return end

        -- Eingabe
        local want = Vector3.zero
        if not UI:GetFocusedTextBox() then
            if UI:IsKeyDown(Enum.KeyCode.W) then want += Cam.CFrame.LookVector end
            if UI:IsKeyDown(Enum.KeyCode.S) then want -= Cam.CFrame.LookVector end
            if UI:IsKeyDown(Enum.KeyCode.D) then want += Cam.CFrame.RightVector end
            if UI:IsKeyDown(Enum.KeyCode.A) then want -= Cam.CFrame.RightVector end
            if UI:IsKeyDown(Enum.KeyCode.Space) then want += Vector3.new(0, CLIMB_RATE / math.max(fly.speed,1), 0) end
            if UI:IsKeyDown(TURBO_KEY) then
                if (want.X == 0 and want.Z == 0) then
                    -- gedrückt ohne Horizontale → sinken
                    want -= Vector3.new(0, CLIMB_RATE / math.max(fly.speed,1), 0)
                end
                want *= TURBO_MULT
            end
        end

        -- Bodennähe → Up-Bias
        local near = rayDown(v, GROUND_PROBE)
        if near and (want.Y >= 0) then
            want = want + Vector3.new(0, NEAR_GROUND_BIAS / math.max(fly.speed,1), 0)
        end

        -- Zielgeschwindigkeit (stud/s)
        local targetVel = Vector3.zero
        if want.Magnitude > 0 then
            local horiz = Vector3.new(want.X,0,want.Z)
            if horiz.Magnitude > 0 then horiz = horiz.Unit * fly.speed end
            local vert  = Vector3.new(0, want.Y * fly.speed, 0)
            targetVel = horiz + vert
        end

        -- Glätten
        fly.vel = fly.vel:Lerp(targetVel, math.clamp(ACCEL_LERP, 0, 1))

        local cf = v:GetPivot()

        -- sanft zur Kamera drehen
        local toCam = CFrame.lookAt(cf.Position, cf.Position + Cam.CFrame.LookVector)
        local rotCF = cf:Lerp(toCam, math.clamp(TURN_LERP, 0, 1))

        -- Roh-Schritt
        local rawStep = fly.vel * dt

        -- Takeoff-Assist (bis MIN_CLEARANCE)
        if os.clock() < fly.takeoffUntil then
            local ground = rayDownFrom(rotCF.Position, v, 1500)
            if ground then
                local need = (ground.Position.Y + MIN_CLEARANCE) - (rotCF.Position.Y + rawStep.Y)
                if need > 0 then
                    local add = math.min(need, MAX_STEP * 0.6)
                    rawStep = rawStep + Vector3.new(0, add, 0)
                end
            end
        end

        -- Schritt-Clamp
        local mag = rawStep.Magnitude
        if mag > MAX_STEP then rawStep = rawStep.Unit * MAX_STEP end

        -- Zielposition + harte Clearance
        local npos = rotCF.Position + rawStep
        local under = rayDownFrom(npos, v, 1500)
        if under then
            local minY = under.Position.Y + MIN_CLEARANCE
            if npos.Y < minY then
                local diff = minY - npos.Y
                npos = npos + Vector3.new(0, math.min(diff, MAX_STEP), 0)
            end
        end

        local nextCF = CFrame.new(npos, npos + Cam.CFrame.LookVector)
        pivotTo(v, nextCF)
    end

    -- ===== SafeFly (kurz Bodenkontakt, dann zurück) =====
    local function startSafe()
        if fly.safeTask then task.cancel(fly.safeTask) end
        fly.safeTask = task.spawn(function()
            while fly.enabled do
                if not fly.safeOn then task.wait(0.25)
                else
                    task.wait(SAFE_PERIOD)
                    if not fly.enabled then break end
                    local v=veh(); if not v then break end
                    local before=v:GetPivot()
                    local hit=rayDown(v,1500)
                    if hit then
                        local lock = CFrame.new(hit.Position + Vector3.new(0,2,0),
                                                hit.Position + Vector3.new(0,2,0)+Cam.CFrame.LookVector)
                        local t0=os.clock()
                        while os.clock()-t0 < SAFE_HOLD and fly.enabled do
                            pivotTo(v, lock)
                            RS.Heartbeat:Wait()
                        end
                        if fly.enabled then pivotTo(v, before) end
                    end
                end
            end
        end)
    end

    -- ===== Toggle =====
    local function setEnabled(on)
        if on == fly.enabled then return end
        local v=veh()
        if on then
            if not v then note("Car Fly","Kein Fahrzeug."); return end
            ensurePP(v)
            saveCollide(v)
            fly.vel = Vector3.zero
            fly.takeoffUntil = os.clock() + TAKEOFF_TIME
            if fly.conn then fly.conn:Disconnect() end
            fly.conn = RS.RenderStepped:Connect(step)
            startSafe()
            fly.enabled = true
            if fly.uiToggle then fly.uiToggle:Set(true) end
            note("Car Fly", ("Aktiviert (Speed %d)"):format(fly.speed), 2)
        else
            fly.enabled = false
            if fly.conn then fly.conn:Disconnect(); fly.conn=nil end
            if fly.safeTask then task.cancel(fly.safeTask); fly.safeTask=nil end
            -- *** kein Absetzen mehr: free-fall ***
            restoreCollide()
            if fly.uiToggle then fly.uiToggle:Set(false) end
            note("Car Fly","Deaktiviert (free fall).",2)
        end
    end

    local function toggle()
        local now=os.clock()
        if now - fly.toggleTS < 0.18 then return end
        fly.toggleTS = now
        setEnabled(not fly.enabled)
    end

    -- ===== UI =====
    local sec = tab:AddSection({ Name = "Car Fly (Teleport v2.2)" })
    fly.uiToggle = sec:AddToggle({
        Name="Enable (nur im Auto)", Default=false,
        Callback=function(v) setEnabled(v) end
    })
    sec:AddBind({ Name="Toggle Key", Default=Enum.KeyCode.X, Hold=false, Callback=function() toggle() end })
    sec:AddToggle({ Name="Safe Fly (alle 6s 0.5s Boden)", Default=false, Callback=function(v) fly.safeOn=v end })
    sec:AddSlider({ Name="Speed", Min=40, Max=300, Increment=5, Default=BASE_SPEED, Callback=function(v) fly.speed=math.floor(v) end })

    RS.Heartbeat:Connect(function()
        if fly.enabled and not SV.isSeated() then setEnabled(false) end
    end)
end
