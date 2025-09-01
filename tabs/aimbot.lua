-- tabs/aimbot.lua  (Stage 3: target scan + status)
return function(tab, OrionLib)
    print("[SorinHub] Stage3 scan-only init")

    local Players      = game:GetService("Players")
    local RunService   = game:GetService("RunService")
    local UserInput    = game:GetService("UserInputService")
    local Workspace    = game:GetService("Workspace")
    local LocalPlayer  = Players.LocalPlayer
    local Camera       = Workspace.CurrentCamera

    local settings = {
        AimPart      = "Head",
        IgnoreTeam   = true,
        VisibleCheck = true,
        WallCheck    = false,
        MaxDistance  = 1000,
        FOVRadius    = 120,
    }

    -- robustes RaycastParams mit Exclude/Blacklist-Fallback
    local function mkParams(exclude)
        local p = RaycastParams.new()
        p.IgnoreWater = true
        local ok = pcall(function() p.FilterType = Enum.RaycastFilterType.Exclude end)
        if not ok then p.FilterType = Enum.RaycastFilterType.Blacklist end
        p.FilterDescendantsInstances = exclude or {}
        return p
    end

    local function isVisible(part)
        local char = LocalPlayer.Character
        if not (Camera and part and char) then return false end
        local head = char:FindFirstChild("Head"); if not head then return false end
        local res = Workspace:Raycast(head.Position, part.Position - head.Position, mkParams({char, Camera}))
        return (not res) or res.Instance:IsDescendantOf(part.Parent)
    end

    local function getClosest()
        Camera = Workspace.CurrentCamera
        local char = LocalPlayer.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if not (Camera and root) then return nil, "no camera/root" end

        local mouse = UserInput:GetMouseLocation()
        local best, bestScreen = nil, math.huge

        for _,plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer then
                local ch = plr.Character
                local hum = ch and ch:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 then
                    if settings.IgnoreTeam and plr.Team and LocalPlayer.Team and plr.Team==LocalPlayer.Team then goto continue end
                    local part = ch:FindFirstChild(settings.AimPart) or ch:FindFirstChild("HumanoidRootPart")
                    if not part then goto continue end
                    if (part.Position - root.Position).Magnitude > settings.MaxDistance then goto continue end
                    if settings.WallCheck and not isVisible(part) then goto continue end

                    local sp,on = Camera:WorldToViewportPoint(part.Position)
                    if settings.VisibleCheck and not on then goto continue end

                    local d = (Vector2.new(mouse.X,mouse.Y) - Vector2.new(sp.X,sp.Y)).Magnitude
                    if d <= settings.FOVRadius and d < bestScreen then bestScreen=d; best=plr end
                end
            end
            ::continue::
        end
        return best, best and bestScreen or nil
    end

    -- UI
    local sec = tab:AddSection({ Name="Scan Test" })
    local lbl1 = sec:AddLabel("Closest: (none)")
    local lbl2 = sec:AddLabel("ScreenDist: -")

    RunService.RenderStepped:Connect(function()
        local plr,sd = getClosest()
        if plr then
            lbl1:Set("Closest: "..plr.Name)
            lbl2:Set(("ScreenDist: %0.1f"):format(sd))
        else
            lbl1:Set("Closest: (none)")
            lbl2:Set("ScreenDist: -")
        end
    end)
end
