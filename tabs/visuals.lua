-- tabs/visuals.lua
-- Visuals / simple nameplates for SorinHub (Orion)
-- Exports: function(tab, OrionLib) end

return function(tab, OrionLib)
    -- Services / locals
    local Players     = game:GetService("Players")
    local RunService  = game:GetService("RunService")
    local Workspace   = game:GetService("Workspace")

    local LocalPlayer = Players.LocalPlayer
    local Camera      = Workspace.CurrentCamera

    -- ==== STATE (user-tweakable via UI) ====
    local STATE = {
        enabled       = false,
        maxDistance   = 600,      -- studs
        textColor     = Color3.new(1,1,1),
        transparency  = 1,
        autoScale     = true
    }

    -- ==== Drawing API check ====
    local ok = pcall(function()
        local t = Drawing.new("Text")
        t.Visible = false
        t:Remove()
    end)

    if not ok then
        tab:AddParagraph("Heads up","Your executor does not support the Drawing API. Visuals are disabled.")
        return
    end

    -- ==== helpers ====
    local function newLabel()
        local t = Drawing.new("Text")
        t.Visible = false
        t.Center = true
        t.Outline = true
        t.Color = STATE.textColor
        t.Transparency = STATE.transparency
        t.Size = 16
        t.Font = 2 -- UI (clean)
        return t
    end

    -- Per-player label pool
    local pool = {} :: {[Player]: DrawingText}

    local function ensureFor(plr: Player)
        if pool[plr] then return pool[plr] end
        local label = newLabel()
        pool[plr] = label
        return label
    end

    local function removeFor(plr: Player)
        local t = pool[plr]
        if t then
            t:Remove()
            pool[plr] = nil
        end
    end

    -- Cleanup on leave
    Players.PlayerRemoving:Connect(removeFor)

    -- ==== UI ====
    tab:AddToggle({
        Name = "Enable Visuals",
        Default = false,
        Callback = function(v)
            STATE.enabled = v
            -- hide all when turning off
            if not v then
                for _,label in pairs(pool) do label.Visible = false end
            end
        end
    })

    tab:AddSlider({
        Name = "Render distance",
        Min = 50, Max = 2000, Increment = 10,
        Default = STATE.maxDistance,
        ValueName = "studs",
        Callback = function(val) STATE.maxDistance = val end
    })

    tab:AddColorpicker({
        Name = "Text color",
        Default = STATE.textColor,
        Callback = function(c)
            STATE.textColor = c
            for _,lbl in pairs(pool) do lbl.Color = c end
        end
    })

    -- ==== main render loop ====
    local steppedConn
    steppedConn = RunService.RenderStepped:Connect(function()
        if not STATE.enabled then return end

        local myChar = LocalPlayer.Character
        local myHRP  = myChar and myChar:FindFirstChild("HumanoidRootPart")

        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer then
                local label = ensureFor(plr)

                local char = plr.Character
                local hum  = char and char:FindFirstChildOfClass("Humanoid")
                local head = char and char:FindFirstChild("Head")
                local hrp  = char and char:FindFirstChild("HumanoidRootPart")

                local alive = hum and hum.Health > 0
                if alive and head and hrp then
                    -- distance / cull
                    local dist = (myHRP and (myHRP.Position - hrp.Position).Magnitude) or 1e9
                    if dist <= STATE.maxDistance then
                        -- screen position: a bit above head
                        local worldPos = head.Position + Vector3.new(0, 3, 0)
                        local vp, onScreen = Camera:WorldToViewportPoint(worldPos)
                        if onScreen then
                            -- equipped tool (parented to character if equipped)
                            local tool = char:FindFirstChildOfClass("Tool")
                            local toolName = tool and tool.Name or "None"

                            -- text content (English)
                            -- Line 1: DisplayName
                            -- Line 2: @username
                            -- Line 3: Equipped: X
                            -- Line 4: Distance: N studs
                            label.Text =
                                string.format("%s\n@%s\nEquipped: %s\nDistance: %d studs",
                                    plr.DisplayName or plr.Name,
                                    plr.Name,
                                    toolName,
                                    math.floor(dist + 0.5)
                                )

                            -- autoscale with distance (optional, subtle)
                            if STATE.autoScale then
                                -- closer = bigger (clamp 12..20)
                                local s = math.clamp(20 - dist * 0.01, 12, 20)
                                label.Size = s
                            end

                            label.Position = Vector2.new(vp.X, vp.Y)
                            label.Color = STATE.textColor
                            label.Transparency = STATE.transparency
                            label.Visible = true
                        else
                            label.Visible = false
                        end
                    else
                        label.Visible = false
                    end
                else
                    -- dead / missing parts
                    label.Visible = false
                end
            end
        end
    end)

    -- Safety: destroy labels when UI is closed
    task.spawn(function()
        -- wait until CoreGui parented GUI disappears
        while task.wait(1) do
            if not OrionLib or not OrionLib.IsRunning or not OrionLib:IsRunning() then
                for plr,label in pairs(pool) do
                    label:Remove()
                    pool[plr] = nil
                end
                if steppedConn then steppedConn:Disconnect() end
                break
            end
        end
    end)
end
