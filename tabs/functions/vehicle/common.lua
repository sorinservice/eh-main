-- tabs/vehicle/common.lua
return function(tab, OrionLib)
    local Players     = game:GetService("Players")
    local RunService  = game:GetService("RunService")
    local UserInput   = game:GetService("UserInputService")
    local HttpService = game:GetService("HttpService")
    local Workspace   = game:GetService("Workspace")

    local LP     = Players.LocalPlayer
    local Camera = Workspace.CurrentCamera

    local function notify(title, msg, t)
        pcall(function()
            OrionLib:MakeNotification({Name=title, Content=msg, Time=t or 3})
        end)
    end

    local function VehiclesFolder()
        return Workspace:FindFirstChild("Vehicles") or Workspace:FindFirstChild("vehicles") or Workspace
    end

    local function myVehicleFolder()
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
                if a:find("driver") or a:find("seat") or a:find("fahrer")
                or o:find("driver") or o:find("seat") or o:find("fahrer") then
                    return pp
                end
            end
        end
        return nil
    end

    local function isSeated()
        local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
        return hum and hum.SeatPart ~= nil
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
            if isSeated() then return true end
        end
        return false
    end

    local function sitIn(seat)
        local char = LP.Character or LP.CharacterAdded:Wait()
        local hum  = char:FindFirstChildOfClass("Humanoid")
        if not (seat and hum) then return false end

        local vf = myVehicleFolder()
        local pp = vf and findDriverPrompt(vf) or nil
        if pp then
            local baseCF = CFrame.new()
            if pp.Parent then
                if pp.Parent.GetPivot then
                    baseCF = pp.Parent:GetPivot()
                elseif pp.Parent:IsA("BasePart") then
                    baseCF = CFrame.new(pp.Parent.Position)
                end
            end
            char:WaitForChild("HumanoidRootPart").CFrame = baseCF * CFrame.new(-1.2, 1.4, 0.2)
            task.wait(0.05)
            if pressPrompt(pp, 12) then return true end
        end

        local ok = pcall(function() seat:Sit(hum) end)
        if ok and seat.Occupant == hum then return true end

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

    return {
        Services = {RunService=RunService, UserInput=UserInput, Workspace=Workspace, HttpService=HttpService},
        LP = LP, Camera = Camera, OrionLib = OrionLib,
        notify = notify,

        VehiclesFolder = VehiclesFolder,
        myVehicleFolder = myVehicleFolder,
        ensurePrimaryPart = ensurePrimaryPart,
        findDriveSeat = findDriveSeat,
        findDriverPrompt = findDriverPrompt,
        isSeated = isSeated,
        pressPrompt = pressPrompt,
        sitIn = sitIn,
    }
end
