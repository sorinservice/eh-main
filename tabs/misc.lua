-- tabs/misc.lua
-- SorinHub | Misc Utilities (Toggles only persisted)

return function(tab, OrionLib)
    -----------------------
    -- Services & locals
    -----------------------
    local Players      = game:GetService("Players")
    local RunService   = game:GetService("RunService")
    local HttpService  = game:GetService("HttpService")
    local Workspace    = game:GetService("Workspace")
    local LP           = Players.LocalPlayer

    local function getHumanoid(char)
        return char and char:FindFirstChildOfClass("Humanoid")
    end
    local function getHRP(char)
        return char and char:FindFirstChild("HumanoidRootPart")
    end
    local function inVehicle(char)
        local hum = getHumanoid(char)
        if hum and hum.Sit then return true end
        if char then
            for _, d in ipairs(char:GetDescendants()) do
                if d:IsA("Weld") and d.Name:lower():find("seat") then
                    return true
                end
            end
        end
        return false
    end

    -----------------------
    -- Persistence
    -----------------------
    local SAVE_FOLDER = OrionLib.Folder or "SorinConfig"
    local SAVE_FILE   = SAVE_FOLDER .. "/misc.json"

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
            if makefolder and not isfolder(SAVE_FOLDER) then
                makefolder(SAVE_FOLDER)
            end
            if writefile then
                writefile(path, HttpService:JSONEncode(tbl))
            end
        end)
    end

    -----------------------
    -- Config (Toggles only)
    -----------------------
    local CFG = {
        AntiFall   = false,
        AntiArrest = false,
        AntiTaser  = false,
    }

    local saved = safe_read_json(SAVE_FILE)
    if type(saved) == "table" then
        for k,v in pairs(CFG) do
            if saved[k] ~= nil then CFG[k] = saved[k] end
        end
    end
    local function save_cfg() safe_write_json(SAVE_FILE, CFG) end

    -----------------------
    -- Anti-Fall Damage
    -----------------------
    local fallConn
    local function stepAntiFall()
        local char = LP.Character
        local hum  = getHumanoid(char)
        local hrp  = getHRP(char)
        if not (char and hum and hrp) then return end
        if hum.FloorMaterial ~= Enum.Material.Air then return end

        local vy = hrp.AssemblyLinearVelocity.Y
        if vy < -40 then -- MinFallSpeed
            local cap   = -65 -- CapDownSpeed
            local newVy = math.max(vy, cap)
            if newVy ~= vy then
                local v = hrp.AssemblyLinearVelocity
                local blendedY = vy + (newVy - vy) * 0.35 -- BlendFactor
                hrp.AssemblyLinearVelocity = Vector3.new(v.X, blendedY, v.Z)
            end
        end
    end
    local function startAntiFall()
        if fallConn then fallConn:Disconnect() end
        fallConn = RunService.Heartbeat:Connect(stepAntiFall)
    end
    local function stopAntiFall()
        if fallConn then fallConn:Disconnect(); fallConn = nil end
    end
    if CFG.AntiFall then startAntiFall() end

    -----------------------
    -- Anti-Arrest
    -----------------------
    local arrestConn
    local function stepAntiArrest()
        local char = LP.Character
        local hum  = getHumanoid(char)
        local hrp  = getHRP(char)
        if not (char and hum and hrp) then return end
        if inVehicle(char) then return end

        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LP and plr.Team and plr.Team.Name == "Police" then
                local phrp = getHRP(plr.Character)
                if phrp and (phrp.Position - hrp.Position).Magnitude < 12 then
                    local offset = hrp.CFrame.LookVector * 18 + hrp.CFrame.RightVector * 3
                    hrp.CFrame = hrp.CFrame + offset
                    break
                end
            end
        end
    end
    local function startAntiArrest()
        if arrestConn then arrestConn:Disconnect() end
        arrestConn = RunService.Heartbeat:Connect(stepAntiArrest)
    end
    local function stopAntiArrest()
        if arrestConn then arrestConn:Disconnect(); arrestConn = nil end
    end
    if CFG.AntiArrest then startAntiArrest() end

    -----------------------
    -- Anti-Taser
    -----------------------
    local taserConn
    local function stepAntiTaser()
        local hum = getHumanoid(LP.Character)
        local hrp = getHRP(LP.Character)
        if not (hum and hrp) then return end

        if hum.PlatformStand
        or hum:GetState() == Enum.HumanoidStateType.Ragdoll
        or hum:GetState() == Enum.HumanoidStateType.FallingDown
        or hum:GetState() == Enum.HumanoidStateType.Physics
        then
            hum:ChangeState(Enum.HumanoidStateType.GettingUp)
            hum:ChangeState(Enum.HumanoidStateType.Running)
            hum.PlatformStand = false
            hum.Sit = false
            hrp.CFrame = hrp.CFrame + Vector3.new(0, 1.2, 0)
        end
    end
    local function startAntiTaser()
        if taserConn then taserConn:Disconnect() end
        taserConn = RunService.Heartbeat:Connect(stepAntiTaser)
    end
    local function stopAntiTaser()
        if taserConn then taserConn:Disconnect(); taserConn = nil end
    end
    if CFG.AntiTaser then startAntiTaser() end

    -----------------------
    -- UI
    -----------------------
    local secFall  = tab:AddSection({ Name = "Anti-Fall Damage" })
    secFall:AddToggle({
        Name = "Enable Anti-Fall (Velocity Clamp)",
        Default = CFG.AntiFall,
        Callback = function(v)
            CFG.AntiFall = v; save_cfg()
            if v then startAntiFall() else stopAntiFall() end
        end
    })

    local secArr = tab:AddSection({ Name = "Anti-Arrest" })
    secArr:AddToggle({
        Name = "Enable Anti-Arrest",
        Default = CFG.AntiArrest,
        Callback = function(v)
            CFG.AntiArrest = v; save_cfg()
            if v then startAntiArrest() else stopAntiArrest() end
        end
    })

    local secTase = tab:AddSection({ Name = "Anti-Taser" })
    secTase:AddToggle({
        Name = "Enable Anti-Taser",
        Default = CFG.AntiTaser,
        Callback = function(v)
            CFG.AntiTaser = v; save_cfg()
            if v then startAntiTaser() else stopAntiTaser() end
        end
    })

    local secResp = tab:AddSection({ Name = "Respawn" })
    secResp:AddButton({
        Name = "Respawn (lose all weapons/tools)",
        Callback = function()
            local function nukeTools(c)
                if not c then return end
                for _, t in ipairs(c:GetChildren()) do
                    if t:IsA("Tool") then pcall(function() t:Destroy() end) end
                end
            end
            nukeTools(LP:FindFirstChild("Backpack"))
            nukeTools(LP.Character)
            local hum = getHumanoid(LP.Character)
            if hum then
                hum.Health = 0
                OrionLib:MakeNotification({ Name="Utility", Content="Respawn requested (inventory cleared).", Time=3 })
            end
        end
    })
end
