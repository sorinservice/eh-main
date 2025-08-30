-- tabs/visuals.lua
-- Visuals / Nametags (DisplayName, @Username, Distance, Equipped Item) + Render Distance

return function(tab, OrionLib)
    -- Services
    local Players    = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local Camera     = workspace.CurrentCamera
    local LocalPlayer= Players.LocalPlayer

    -- Settings (über UI veränderbar)
    local STATE = {
        enabled    = false,
        maxDist    = 300, -- Studs
        textColor  = Color3.fromRGB(255,255,255),
        outlineCol = Color3.fromRGB(0,0,0)
    }

    -- Drawing-Check
    if not Drawing or not Drawing.new then
        tab:AddParagraph("Hinweis",
            "Dein Executor stellt keine Drawing-API bereit. Visuals funktionieren hier nicht.")
        return
    end

    -- UI
    tab:AddParagraph("Visuals", "Nametag zeigt: DisplayName, @Username, Distance, Equipped Item")
    tab:AddToggle({
        Name = "Nametag ESP",
        Default = false,
        Callback = function(v) STATE.enabled = v end
    })
    tab:AddSlider({
        Name = "Render Distance",
        Min = 50, Max = 1000, Increment = 10,
        Default = STATE.maxDist, ValueName = "studs",
        Callback = function(v) STATE.maxDist = v end
    })

    -- Drawing-Helper
    local function NewText(size)
        local t = Drawing.new("Text")
        t.Visible      = false
        t.Center       = true
        t.Size         = size or 16
        t.Color        = STATE.textColor
        t.Outline      = true
        t.OutlineColor = STATE.outlineCol
        return t
    end

    -- Per-Player Textobjekte
    local pool = {} -- [player] = {top=Text, sub=Text}

    local function destroy(plr)
        local obj = pool[plr]
        if not obj then return end
        pcall(function() obj.top:Remove() end)
        pcall(function() obj.sub:Remove() end)
        pool[plr] = nil
    end

    local function ensure(plr)
        if plr == LocalPlayer then return end
        if pool[plr] then return end
        pool[plr] = { top = NewText(16), sub = NewText(14) }
    end

    local function equippedName(char)
        if not char then return "" end
        local tool = char:FindFirstChildOfClass("Tool")
        return tool and tool.Name or ""
    end

    -- initial + join/leave
    for _,plr in ipairs(Players:GetPlayers()) do ensure(plr) end
    Players.PlayerAdded:Connect(ensure)
    Players.PlayerRemoving:Connect(destroy)

    -- Render-Loop
    RunService.RenderStepped:Connect(function()
        if not STATE.enabled then
            for _,obj in pairs(pool) do
                obj.top.Visible = false
                obj.sub.Visible = false
            end
            return
        end

        local lchar = LocalPlayer.Character
        local lhrp  = lchar and lchar:FindFirstChild("HumanoidRootPart")

        for plr,obj in pairs(pool) do
            local char = plr.Character
            local head = char and char:FindFirstChild("Head")
            local hrp  = char and char:FindFirstChild("HumanoidRootPart")
            local hum  = char and char:FindFirstChildOfClass("Humanoid")

            if head and hrp and hum and hum.Health > 0 and lhrp then
                local dist = (lhrp.Position - hrp.Position).Magnitude
                if dist <= STATE.maxDist then
                    local worldPos = head.Position + Vector3.new(0, head.Size.Y + 0.5, 0)
                    local screenPos, onScreen = Camera:WorldToViewportPoint(worldPos)
                    if onScreen then
                        obj.top.Text     = string.format("%s  (@%s)", plr.DisplayName, plr.Name)
                        obj.sub.Text     = string.format("%dm  %s", math.floor(dist + 0.5), equippedName(char))
                        obj.top.Position = Vector2.new(screenPos.X, screenPos.Y)
                        obj.sub.Position = Vector2.new(screenPos.X, screenPos.Y + 16)
                        obj.top.Visible  = true
                        obj.sub.Visible  = true
                    else
                        obj.top.Visible, obj.sub.Visible = false, false
                    end
                else
                    obj.top.Visible, obj.sub.Visible = false, false
                end
            else
                obj.top.Visible, obj.sub.Visible = false, false
            end
        end
    end)
end
