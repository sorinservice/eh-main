-- tabs/functions/vehicle/vehicle/common.lua
return function(tab, OrionLib)
    local Players     = game:GetService("Players")
    local RunService  = game:GetService("RunService")
    local UserInput   = game:GetService("UserInputService")
    local HttpService = game:GetService("HttpService")
    local Workspace   = game:GetService("Workspace")

    local LP     = Players.LocalPlayer
    local Camera = Workspace.CurrentCamera

    -- ---------------- Notifications ----------------
    local function notify(title, msg, t)
        pcall(function()
            OrionLib:MakeNotification({Name=title, Content=msg, Time=t or 3})
        end)
    end

    -- ---------------- Vehicle helpers --------------
    local function VehiclesFolder()
        return Workspace:FindFirstChild("Vehicles") or Workspace:FindFirstChild("vehicles") or Workspace
    end

    local function myVehicleFolder()
        local vRoot = VehiclesFolder(); if not vRoot then return nil end
        local byName = vRoot:FindFirstChild(LP.Name)
        if byName then return byName end
        for _,m in ipairs(vRoot:GetChildren()) do
            if (m:IsA("Model") or m:IsA("Folder")) and (m.GetAttribute and m:GetAttribute("Owner")==LP.Name) then
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
            if typeof(fireproximityprompt)=="function" then
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
                if pp.Parent.GetPivot then baseCF = pp.Parent:GetPivot()
                elseif pp.Parent:IsA("BasePart") then baseCF = CFrame.new(pp.Parent.Position) end
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

    -- ---------------- Plate persistence -------------
    local SAVE_FOLDER = OrionLib.Folder or "SorinConfig"
    local SAVE_FILE   = SAVE_FOLDER .. "/vehicle.json"

    local function read_json(path)
        local ok, res = pcall(function()
            if isfile and isfile(path) then
                return HttpService:JSONDecode(readfile(path))
            end
        end)
        return ok and res or nil
    end
    local function write_json(path, tbl)
        pcall(function()
            if makefolder and not isfolder(SAVE_FOLDER) then makefolder(SAVE_FOLDER) end
            if writefile then writefile(path, HttpService:JSONEncode(tbl)) end
        end)
    end

    local CFG = { plateText = "" }
    do
        local saved = read_json(SAVE_FILE)
        if type(saved)=="table" and type(saved.plateText)=="string" then
            CFG.plateText = saved.plateText
        end
    end
    local function save_cfg()
        write_json(SAVE_FILE, { plateText = CFG.plateText })
    end

    local function applyPlateTextTo(vf, txt)
        if not (vf and txt and txt~="") then return end
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

    -- Rückgabe: SV
    return {
        -- services & context
        Services = { RunService=RunService, UserInput=UserInput, Workspace=Workspace, HttpService=HttpService },
        LP = LP, Camera = Camera, OrionLib = OrionLib,

        -- ui helper
        notify = notify,

        -- vehicle utils
        VehiclesFolder = VehiclesFolder,
        myVehicleFolder = myVehicleFolder,
        ensurePrimaryPart = ensurePrimaryPart,
        findDriveSeat = findDriveSeat,
        findDriverPrompt = findDriverPrompt,
        isSeated = isSeated,
        pressPrompt = pressPrompt,
        sitIn = sitIn,

        -- plate cfg + helpers (für plates.lua)
        CFG = CFG,
        save_cfg = save_cfg,
        applyPlateTextTo = applyPlateTextTo,
    }
end
