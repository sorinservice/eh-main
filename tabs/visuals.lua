-- tabs/visuals.lua
-- Visuals / ESP für SorinHub – modular, performant, mit UI-Steuerung (Orion)

return function(tab, OrionLib)
    -- ==== Services / Locals ====
    local Players     = game:GetService("Players")
    local RunService  = game:GetService("RunService")
    local Workspace   = game:GetService("Workspace")

    local LocalPlayer = Players.LocalPlayer
    local Camera      = Workspace.CurrentCamera

    -- ==== State (wird über UI geändert) ====
    local STATE = {
        enabled         = false,
        tracers         = true,
        teamCheck       = true,
        autoThickness   = true,
        shifter         = true,

        boxColor        = Color3.fromRGB(255, 0, 0),
        tracerColor     = Color3.fromRGB(255, 0, 0),
        allyColor       = Color3.fromRGB(90, 215, 25),
        enemyColor      = Color3.fromRGB(240, 20, 20),

        baseThickness   = 2,
        boxTransparency = 1,
        tracerTransparency = 1,
    }

    -- ==== Kompatibilität prüfen (Drawing API) ====
    local canDraw = (Drawing ~= nil) and pcall(function() local _ = Drawing.new("Line"); _.Visible=false; _.Remove() end)
    if not canDraw then
        tab:AddParagraph("Hinweis", "Dein Executor bietet keine Drawing API.\nDas Visuals-Tab wird deaktiviert.")
        return
    end

    -- ==== Drawing-Objekt Helfer ====
    local function NewLine(col, thick, transp)
        local line = Drawing.new("Line")
        line.Visible       = false
        line.Color         = col or STATE.boxColor
        line.Thickness     = thick or STATE.baseThickness
        line.Transparency  = transp or STATE.boxTransparency
        return line
    end

    local function NewQuad(col, thick, transp)
        local q = Drawing.new("Quad")
        q.Visible       = false
        q.Filled        = false
        q.Color         = col or STATE.boxColor
        q.Thickness     = thick or STATE.baseThickness
        q.Transparency  = transp or STATE.boxTransparency
        return q
    end

    -- pro Spieler: 12 Linien für 3D-Box + 1 Tracer + 1 Shifter-Quad
    local pool = {}  -- [player] = {lines={...}, tracer=Line, shifter=Quad}

    local function allocFor(plr)
        if pool[plr] then return pool[plr] end
        local lines = {
            NewLine(), NewLine(), NewLine(), NewLine(), -- top 1..4
            NewLine(), NewLine(), NewLine(), NewLine(), -- bottom 5..8
            NewLine(), NewLine(), NewLine(), NewLine(), -- sides 9..12
        }
        local tracer  = NewLine(STATE.tracerColor, STATE.baseThickness, STATE.tracerTransparency)
        local shifter = NewQuad(STATE.enemyColor, STATE.baseThickness, STATE.boxTransparency)

        pool[plr] = { lines = lines, tracer = tracer, shifter = shifter, shifterOffset = 0, debounce = 0 }
        return pool[plr]
    end

    local function freeFor(plr)
        local slot = pool[plr]
        if not slot then return end
        for _,ln in ipairs(slot.lines) do pcall(function() ln:Remove() end) end
        if slot.tracer  then pcall(function() slot.tracer:Remove() end) end
        if slot.shifter then pcall(function() slot.shifter:Remove() end) end
        pool[plr] = nil
    end

    local function hideAllFor(plr)
        local slot = pool[plr]
        if not slot then return end
        for _,ln in ipairs(slot.lines) do ln.Visible = false end
        if slot.tracer  then slot.tracer.Visible  = false end
        if slot.shifter then slot.shifter.Visible = false end
    end

    -- ==== Mathe / Utils ====
    local function lerp(a,b,t) return a + (b-a)*t end

    local function setLine(l, from, to)
        l.From = from
        l.To   = to
        l.Visible = true
    end

    local function setThickness(slot, value)
        for _,ln in ipairs(slot.lines) do ln.Thickness = value end
        slot.tracer.Thickness  = value
        slot.shifter.Thickness = value
    end

    local function setTeamColors(slot, isAlly)
        local col = isAlly and STATE.allyColor or STATE.enemyColor
        for _,ln in ipairs(slot.lines) do ln.Color = col end
        slot.shifter.Color = (isAlly and STATE.enemyColor or STATE.allyColor) -- Kontrast
    end

    local function applyBaseColors(slot)
        for _,ln in ipairs(slot.lines) do ln.Color = STATE.boxColor end
        slot.tracer.Color = STATE.tracerColor
        slot.shifter.Color = STATE.boxColor
    end

    -- ==== Hauptrender ====
    local rsConn -- RenderStepped connection

    local function startRender()
        if rsConn then return end
        rsConn = RunService.RenderStepped:Connect(function()
            if not STATE.enabled then
                -- ausgeknipst -> alles verstecken
                for plr,_ in pairs(pool) do hideAllFor(plr) end
                return
            end

            local lpChar = LocalPlayer.Character
            local lpHRP  = lpChar and lpChar:FindFirstChild("HumanoidRootPart")

            for _,plr in ipairs(Players:GetPlayers()) do
                if plr ~= LocalPlayer then
                    local slot = allocFor(plr)
                    local char = plr.Character
                    local hum  = char and char:FindFirstChildOfClass("Humanoid")
                    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
                    local head = char and char:FindFirstChild("Head")

                    if hum and hrp and head and hum.Health > 0 then
                        local _, onScreen = Camera:WorldToViewportPoint(hrp.Position)
                        if onScreen then
                            -- Box-Größe relativ zum Kopf
                            local scale = head.Size.Y/2
                            local size3 = Vector3.new(2, 3, 1.5) * (scale * 2)

                            -- 8 Eckpunkte (Top & Bottom)
                            local top1 = Camera:WorldToViewportPoint((hrp.CFrame * CFrame.new(-size3.X,  size3.Y, -size3.Z)).Position)
                            local top2 = Camera:WorldToViewportPoint((hrp.CFrame * CFrame.new(-size3.X,  size3.Y,  size3.Z)).Position)
                            local top3 = Camera:WorldToViewportPoint((hrp.CFrame * CFrame.new( size3.X,  size3.Y,  size3.Z)).Position)
                            local top4 = Camera:WorldToViewportPoint((hrp.CFrame * CFrame.new( size3.X,  size3.Y, -size3.Z)).Position)

                            local bot1 = Camera:WorldToViewportPoint((hrp.CFrame * CFrame.new(-size3.X, -size3.Y, -size3.Z)).Position)
                            local bot2 = Camera:WorldToViewportPoint((hrp.CFrame * CFrame.new(-size3.X, -size3.Y,  size3.Z)).Position)
                            local bot3 = Camera:WorldToViewportPoint((hrp.CFrame * CFrame.new( size3.X, -size3.Y,  size3.Z)).Position)
                            local bot4 = Camera:WorldToViewportPoint((hrp.CFrame * CFrame.new( size3.X, -size3.Y, -size3.Z)).Position)

                            -- Team-Farbe oder feste Farben?
                            if STATE.teamCheck and plr.Team and LocalPlayer.Team then
                                setTeamColors(slot, plr.Team == LocalPlayer.Team)
                            else
                                applyBaseColors(slot)
                            end

                            -- AutoThickness
                            if STATE.autoThickness and lpHRP then
                                local dist = (lpHRP.Position - hrp.Position).Magnitude
                                local thick = math.clamp(1 / math.max(dist, 1) * 100, 0.1, 4)
                                setThickness(slot, thick)
                            else
                                setThickness(slot, STATE.baseThickness)
                            end

                            -- Top (1..4)
                            setLine(slot.lines[1],  Vector2.new(top1.X, top1.Y), Vector2.new(top2.X, top2.Y))
                            setLine(slot.lines[2],  Vector2.new(top2.X, top2.Y), Vector2.new(top3.X, top3.Y))
                            setLine(slot.lines[3],  Vector2.new(top3.X, top3.Y), Vector2.new(top4.X, top4.Y))
                            setLine(slot.lines[4],  Vector2.new(top4.X, top4.Y), Vector2.new(top1.X, top1.Y))
                            -- Bottom (5..8)
                            setLine(slot.lines[5],  Vector2.new(bot1.X, bot1.Y), Vector2.new(bot2.X, bot2.Y))
                            setLine(slot.lines[6],  Vector2.new(bot2.X, bot2.Y), Vector2.new(bot3.X, bot3.Y))
                            setLine(slot.lines[7],  Vector2.new(bot3.X, bot3.Y), Vector2.new(bot4.X, bot4.Y))
                            setLine(slot.lines[8],  Vector2.new(bot4.X, bot4.Y), Vector2.new(bot1.X, bot1.Y))
                            -- Sides (9..12)
                            setLine(slot.lines[9],  Vector2.new(bot1.X, bot1.Y), Vector2.new(top1.X, top1.Y))
                            setLine(slot.lines[10], Vector2.new(bot2.X, bot2.Y), Vector2.new(top2.X, top2.Y))
                            setLine(slot.lines[11], Vector2.new(bot3.X, bot3.Y), Vector2.new(top3.X, top3.Y))
                            setLine(slot.lines[12], Vector2.new(bot4.X, bot4.Y), Vector2.new(top4.X, top4.Y))

                            -- Tracer
                            if STATE.tracers then
                                local foot = Camera:WorldToViewportPoint((hrp.CFrame * CFrame.new(0, -size3.Y, 0)).Position)
                                slot.tracer.Color        = STATE.teamCheck and slot.lines[1].Color or STATE.tracerColor
                                slot.tracer.Transparency = STATE.tracerTransparency
                                slot.tracer.From         = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y)
                                slot.tracer.To           = Vector2.new(foot.X, foot.Y)
                                slot.tracer.Visible      = true
                            else
                                slot.tracer.Visible = false
                            end

                            -- Shifter (animiertes Quad in Körperhöhe)
                            if STATE.shifter then
                                -- einfacher Ping-Pong
                                slot.debounce = slot.debounce or 0
                                slot.shifterOffset = lerp(slot.shifterOffset or 0, math.sin(os.clock()*2) * size3.Y, 0.25)

                                local sY = slot.shifterOffset
                                local s1 = Camera:WorldToViewportPoint((hrp.CFrame * CFrame.new(-size3.X, sY, -size3.Z)).Position)
                                local s2 = Camera:WorldToViewportPoint((hrp.CFrame * CFrame.new(-size3.X, sY,  size3.Z)).Position)
                                local s3 = Camera:WorldToViewportPoint((hrp.CFrame * CFrame.new( size3.X, sY,  size3.Z)).Position)
                                local s4 = Camera:WorldToViewportPoint((hrp.CFrame * CFrame.new( size3.X, sY, -size3.Z)).Position)

                                slot.shifter.PointA = Vector2.new(s1.X, s1.Y)
                                slot.shifter.PointB = Vector2.new(s2.X, s2.Y)
                                slot.shifter.PointC = Vector2.new(s3.X, s3.Y)
                                slot.shifter.PointD = Vector2.new(s4.X, s4.Y)
                                slot.shifter.Visible = true
                            else
                                slot.shifter.Visible = false
                            end
                        else
                            hideAllFor(plr)
                        end
                    else
                        hideAllFor(plr)
                    end
                end
            end

            -- Aufräumen für Spieler, die nicht mehr existieren
            for plr,_ in pairs(pool) do
                if not Players:FindFirstChild(plr.Name) then
                    freeFor(plr)
                end
            end
        end)
    end

    local function stopRender()
        if rsConn then rsConn:Disconnect() rsConn = nil end
        for plr,_ in pairs(pool) do hideAllFor(plr) end
    end

    -- ==== Player Join/Leave: nur Pool verwalten ====
    local addConn = Players.PlayerAdded:Connect(function(plr) allocFor(plr) end)
    local remConn = Players.PlayerRemoving:Connect(function(plr) freeFor(plr) end)
    for _,plr in ipairs(Players:GetPlayers()) do if plr ~= LocalPlayer then allocFor(plr) end end

    -- ==== UI (Orion) ====
    tab:AddSection({ Name = "ESP – Grundfunktionen" })

    tab:AddToggle({
        Name = "ESP aktivieren",
        Default = false,
        Callback = function(v)
            STATE.enabled = v
            if v then startRender() else stopRender() end
        end
    })

    tab:AddToggle({
        Name = "Tracer",
        Default = STATE.tracers,
        Callback = function(v) STATE.tracers = v end
    })

    tab:AddToggle({
        Name = "Team-Check",
        Default = STATE.teamCheck,
        Callback = function(v) STATE.teamCheck = v end
    })

    tab:AddToggle({
        Name = "Auto-Thickness",
        Default = STATE.autoThickness,
        Callback = function(v) STATE.autoThickness = v end
    })

    tab:AddToggle({
        Name = "Shifter-Effekt",
        Default = STATE.shifter,
        Callback = function(v) STATE.shifter = v end
    })

    tab:AddSlider({
        Name = "Grund-Linienstärke",
        Min = 1, Max = 6, Increment = 1, Default = STATE.baseThickness,
        Callback = function(val)
            STATE.baseThickness = val
            for _,slot in pairs(pool) do setThickness(slot, val) end
        end
    })

    tab:AddSection({ Name = "Farben" })

    tab:AddColorpicker({
        Name = "Box-Farbe",
        Default = STATE.boxColor,
        Callback = function(c)
            STATE.boxColor = c
            for _,slot in pairs(pool) do
                for _,ln in ipairs(slot.lines) do ln.Color = c end
                if not STATE.teamCheck then slot.shifter.Color = c end
            end
        end
    })

    tab:AddColorpicker({
        Name = "Tracer-Farbe",
        Default = STATE.tracerColor,
        Callback = function(c)
            STATE.tracerColor = c
        end
    })

    tab:AddColorpicker({
        Name = "Ally-Farbe",
        Default = STATE.allyColor,
        Callback = function(c) STATE.allyColor = c end
    })

    tab:AddColorpicker({
        Name = "Enemy-Farbe",
        Default = STATE.enemyColor,
        Callback = function(c) STATE.enemyColor = c end
    })

    -- ==== Cleanup falls Tab/Script geschlossen wird ====
    -- (Orion ruft kein Destroy-Hook pro Tab; wir sichern zumindest Render + Drawings)
    local function cleanupAll()
        stopRender()
        addConn:Disconnect()
        remConn:Disconnect()
        for plr,_ in pairs(pool) do freeFor(plr) end
    end

    -- Optional: Schaltfläche zum harten Reset
    tab:AddButton({
        Name = "Visuals zurücksetzen",
        Callback = function()
            cleanupAll()
            -- Pool neu anlegen
            for _,plr in ipairs(Players:GetPlayers()) do if plr ~= LocalPlayer then allocFor(plr) end end
            if STATE.enabled then startRender() end
            OrionLib:MakeNotification({ Name="Reset", Content="Visuals neu initialisiert.", Time=3 })
        end
    })
end
