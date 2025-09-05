-- tabs/functions/vehicle/vehicle/carfly_tp.lua
return function(SV, tab, OrionLib)
    -- Car Fly (TP precise, with reliable SafeFly)

    local RunService = game:GetService("RunService")
    local UserInput  = game:GetService("UserInputService")
    local Players    = game:GetService("Players")
    local RS         = game:GetService("ReplicatedStorage")
    local LP         = Players.LocalPlayer

    local notify = SV.notify

    -- === Tunables ===
    local SPEED_DEFAULT   = 260
    local STEP_DIST       = 1.0
    local SUBSTEPS_MAX    = 48

    local SAFE_PERIOD     = 6.0
    local SAFE_HOLD       = 0.5
    local SAFE_BACK       = true
    local SAFE_RAY_DEPTH  = 4000

    local TOGGLE_KEY      = Enum.KeyCode.X

    -- Server reseat
    local VehiclesFolder  = workspace:WaitForChild("Vehicles")
    local SeatRemote      = RS:WaitForChild("Bnl"):WaitForChild("c39ffd32-69b6-4575-aca5-67126fdc1531")

    local function reseatServer(vModel, seatIndex)
        pcall(function() SeatRemote:FireServer(vModel, seatIndex or 0) end)
    end

    -- === State ===
    local fly = {
        enabled=false, speed=SPEED_DEFAULT, safeOn=true,
        hbConn=nil, safeTask=nil, locking=false,
        uiToggle=nil, hoverCF=nil, lastAirCF=nil, debounce=0,
    }

    -- === Helpers ===
    local function myVehicle() return SV.myVehicleFolder() end
    local function ensurePP(v) SV.ensurePrimaryPart(v); return v.PrimaryPart end
    local function setNetOwner(v) pcall(function() if v and v.PrimaryPart then v.PrimaryPart:SetNetworkOwner(LP) end end) end
    local function seated() return SV.isSeated() end

    local function hasInput()
        if UserInput:GetFocusedTextBox() then return false end
        return UserInput:IsKeyDown(Enum.KeyCode.W) or UserInput:IsKeyDown(Enum.KeyCode.S)
    end
    local function dirScalar()
        local d=0
        if not UserInput:GetFocusedTextBox() then
            if UserInput:IsKeyDown(Enum.KeyCode.W) then d+=1 end
            if UserInput:IsKeyDown(Enum.KeyCode.S) then d-=1 end
        end
        return d
    end

    local function hardPivot(v, cf)
        local pp=v.PrimaryPart
        if pp then
            pp.AssemblyLinearVelocity=Vector3.zero
            pp.AssemblyAngularVelocity=Vector3.zero
        end
        v:PivotTo(cf)
    end

    local function groundHit(origin, depth, ignore)
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Blacklist
        params.FilterDescendantsInstances = ignore or {}
        return workspace:Raycast(origin, Vector3.new(0,-(depth or SAFE_RAY_DEPTH),0), params)
    end

    -- === Flight step ===
    local function step(dt)
        if not fly.enabled or fly.locking then return end
        if not seated() then return end

        local v=myVehicle(); if not v then return end
        if not v.PrimaryPart then if not ensurePP(v) then return end end
        setNetOwner(v)

        local cam=workspace.CurrentCamera
        local look=cam.CFrame.LookVector
        if look.Magnitude < 0.999 then look=look.Unit end
        local up=cam.CFrame.UpVector

        local curCF=v:GetPivot()
        local curPos=curCF.Position

        if not hasInput() then
            local keep=(fly.hoverCF and fly.hoverCF.Position) or curPos
            hardPivot(v,CFrame.lookAt(keep,keep+look,up))
            fly.lastAirCF=v:GetPivot()
            return
        end

        local s=dirScalar()
        local total=(fly.speed*dt)*(s>=0 and 1 or -1)
        local absDist=math.abs(total)
        local sub=math.clamp(math.ceil(absDist/STEP_DIST),1,SUBSTEPS_MAX)
        local stepDist=total/sub

        for _=1,sub do
            local target=curPos+(look*stepDist)
            local newCF=CFrame.lookAt(target,target+look,up)
            hardPivot(v,newCF)
            curPos=target
        end

        local final=CFrame.lookAt(curPos,curPos+look,up)
        hardPivot(v,final)
        fly.hoverCF,fly.lastAirCF=final,final
    end

    -- === SafeFly ===
    local function startSafeFly()
        if fly.safeTask then task.cancel(fly.safeTask) end
        fly.safeTask=task.spawn(function()
            while fly.enabled do
                task.wait(SAFE_PERIOD)
                if not fly.enabled then break end
                if not fly.safeOn then continue end

                local v=myVehicle()
                if v and (v.PrimaryPart or ensurePP(v)) then
                    local before=fly.lastAirCF or v:GetPivot()
                    local probeCF=v:GetPivot()

                    local hit=groundHit(probeCF.Position,SAFE_RAY_DEPTH,{v})
                    if hit then
                        fly.locking=true
                        local base=Vector3.new(probeCF.Position.X,hit.Position.Y+2,probeCF.Position.Z)
                        local cam=workspace.CurrentCamera
                        local yawFwd=(cam.CFrame.LookVector*Vector3.new(1,0,1))
                        yawFwd=(yawFwd.Magnitude>1e-3) and yawFwd.Unit or Vector3.new(0,0,-1)
                        local groundCF=CFrame.lookAt(base,base+yawFwd,cam.CFrame.UpVector)

                        local seat=SV.findDriveSeat(v)
                        local hum=LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
                        local vehModel=(VehiclesFolder and (VehiclesFolder:FindFirstChild(LP.Name) or VehiclesFolder:FindFirstChild(v.Name))) or v

                        -- reseat sofort
                        if hum then reseatServer(vehModel,0); if seat then pcall(function() seat:Sit(hum) end) end end

                        -- Boden-Lock 0.5s
                        local t0=os.clock()
                        while os.clock()-t0<SAFE_HOLD and fly.enabled do
                            hardPivot(v,groundCF)
                            if hum and (not seat or seat.Occupant~=hum) then
                                reseatServer(vehModel,0)
                                if seat then pcall(function() seat:Sit(hum) end) end
                            end
                            RunService.Heartbeat:Wait()
                        end

                        -- Zurück in die Luft
                        if SAFE_BACK and fly.enabled then
                            hardPivot(v,before)
                            fly.hoverCF,fly.lastAirCF=before,before
                            if hum and (not seat or seat.Occupant~=hum) then
                                reseatServer(vehModel,0)
                                if seat then pcall(function() seat:Sit(hum) end) end
                            end
                        end

                        fly.locking=false
                    end
                end
            end
        end)
    end

    -- === Enable/Disable ===
    local function setEnabled(on)
        if on==fly.enabled then return end
        local v=myVehicle()

        if on then
            if not v then notify("Car Fly","No vehicle."); return end
            if not v.PrimaryPart then if not ensurePP(v) then notify("Car Fly","No PrimaryPart."); return end end
            setNetOwner(v)

            local cf=v:GetPivot()
            fly.hoverCF,fly.lastAirCF=cf,cf

            if fly.hbConn then fly.hbConn:Disconnect() end
            fly.hbConn=RunService.Heartbeat:Connect(step)

            startSafeFly()
            fly.enabled=true
            if fly.uiToggle then fly.uiToggle:Set(true) end
            notify("Car Fly",("Enabled (Speed %d)"):format(fly.speed),2)
        else
            fly.enabled=false
            if fly.hbConn then fly.hbConn:Disconnect(); fly.hbConn=nil end
            if fly.safeTask then task.cancel(fly.safeTask); fly.safeTask=nil end
            fly.locking=false
            if fly.uiToggle then fly.uiToggle:Set(false) end
            notify("Car Fly","Disabled.",2)
        end
    end

    local function toggle()
        local now=os.clock()
        if now-fly.debounce<0.15 then return end
        fly.debounce=now
        setEnabled(not fly.enabled)
    end

    -- === UI minimal ===
    local sec=tab:AddSection({Name="Car Fly"})
    fly.uiToggle=sec:AddToggle({
        Name="Enable Car Fly",
        Default=false,
        Callback=function(v) setEnabled(v) end
    })
    sec:AddBind({
        Name="Toggle Key",
        Default=TOGGLE_KEY,
        Hold=false,
        Callback=function() toggle() end
    })
    sec:AddSlider({
        Name="Speed",
        Min=10, Max=800, Increment=5,
        Default=SPEED_DEFAULT,
        Callback=function(v) fly.speed=math.floor(v) end
    })
    sec:AddToggle({
        Name="Safe Fly",
        Default=true,
        Callback=function(v) fly.safeOn=v end
    })

    RunService.Heartbeat:Connect(function()
        if fly.enabled and not seated() then setEnabled(false) end
    end)

    print("[carfly v5.0.1] loaded")
end
