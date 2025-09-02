return function(tab, OrionLib)

    ----------------------------------------------------------------
    -- SIMPLE SWITCH (einfach hier umstellen)
    -- "off"    => Self-ESP immer AUS, kein Toggle sichtbar
    -- "on"     => Self-ESP immer AN,  kein Toggle sichtbar
    -- "toggle" => Toggle sichtbar (nur in diesem Script steuerbar)
    local SHOW_SELF_POLICY = "toggle"
    ----------------------------------------------------------------

    ----------------------------------------------------------------
    -- Services
    local Players     = game:GetService("Players")
    local Teams       = game:GetService("Teams")
    local RunService  = game:GetService("RunService")
    local Workspace   = game:GetService("Workspace")

    local LocalPlayer = Players.LocalPlayer
    local Camera      = Workspace.CurrentCamera

    ----------------------------------------------------------------
    -- Drawing API check
    if not Drawing then
        tab:AddParagraph("Notice", "Your executor does not expose the Drawing API. Visuals are disabled.")
        return
    end

    ----------------------------------------------------------------
    -- Config / State (persisted via Flags)
    local STATE = {
        showTeam       = false,   -- EIN Schalter: Team-Name + Teamfarbe (inkl. Skeleton-Färbung)
        showName       = false,
        showUsername   = false,
        showEquipped   = false,   -- Tools-only
        showDistance   = false,
        showBones      = false,
        showSelf       = false,   -- wird unten per Policy durchgesetzt

        maxDistance    = 750,     -- studs

        textSize       = 14,
        lineGap        = 2,       -- vertikaler Zeilenabstand
        textOutline    = true,

        colorText      = Color3.fromRGB(230,230,230),
        colorUsername  = Color3.fromRGB(200,200,200),
        colorEquipped  = Color3.fromRGB(175,175,175),

        bonesColor     = Color3.fromRGB(0,200,255),
        bonesThickness = 2,
    }

    -- Optionale feste Teamfarben (sonst Roblox TeamColor)
    local TEAM_COLORS = {
        -- ["Police"]    = Color3.fromRGB(0,170,255),
        -- ["Criminals"] = Color3.fromRGB(255,80,80),
    }
    local function colorForTeam(plr)
        if not (plr and plr.Team) then return nil end
        local custom = TEAM_COLORS[plr.Team.Name]
        if custom then return custom end
        local ok, c = pcall(function() return plr.Team.TeamColor.Color end)
        return ok and c or nil
    end

    ----------------------------------------------------------------
    -- UI (Flags speichern)
    tab:AddToggle({
        Name = "Team info (name + team color)",
        Default = false,
        Save = true,
        Flag = "esp_teamInfo",
        Callback = function(v) STATE.showTeam = v end
    })

    tab:AddToggle({ Name="Show Display Name", Default=false, Save=true, Flag="esp_showName",
        Callback=function(v) STATE.showName=v end })
    tab:AddToggle({ Name="Show @Username", Default=false, Save=true, Flag="esp_showUsername",
        Callback=function(v) STATE.showUsername=v end })
    tab:AddToggle({ Name="Show Equipped (tools only)", Default=false, Save=true, Flag="esp_showEquipped",
        Callback=function(v) STATE.showEquipped=v end })
    tab:AddToggle({ Name="Show Distance", Default=false, Save=true, Flag="esp_showDistance",
        Callback=function(v) STATE.showDistance=v end })
    tab:AddToggle({ Name="Show Skeleton", Default=false, Save=true, Flag="esp_showBones",
        Callback=function(v) STATE.showBones=v end })

    -- Self-ESP je nach Policy
    if SHOW_SELF_POLICY == "toggle" then
        tab:AddToggle({
            Name     = "Show Self",
            Default  = false,
            Save     = false,            -- absichtlich nicht persistieren
            Flag     = "esp_showSelf",
            Callback = function(v) STATE.showSelf = v end
        })
    elseif SHOW_SELF_POLICY == "on" then
        STATE.showSelf = true
        -- kein Toggle anzeigen
    else -- "off"
        STATE.showSelf = false
        -- kein Toggle anzeigen
    end

    tab:AddSlider({ Name="ESP Render Range", Min=50, Max=2500, Increment=10,
        Default=STATE.maxDistance, ValueName="studs", Save=true, Flag="esp_renderDist",
        Callback=function(v) STATE.maxDistance=v end })

    ----------------------------------------------------------------
    -- Helpers (Drawing)
    local function NewText(size, color)
        local t = Drawing.new("Text")
        t.Visible = false
        t.Size = size or STATE.textSize
        t.Color = color or STATE.colorText
        t.Center = true
        t.Outline = STATE.textOutline
        t.Transparency = 1
        t.Font = 2
        return t
    end
    local function NewLine()
        local ln = Drawing.new("Line")
        ln.Visible = false
        ln.Color = STATE.bonesColor
        ln.Thickness = STATE.bonesThickness
        ln.Transparency = 1
        return ln
    end

    ----------------------------------------------------------------
    -- Per-player pool
    -- getrennte Textobjekte je Zeile, damit nur Team-Zeile farbig ist
    local pool = {} -- [plr] = { textTeam, textName, textUser, textEquip, textDist, bones = {Line...} }

    local function alloc(plr)
        if pool[plr] then return pool[plr] end
        local obj = {
            textTeam  = NewText(STATE.textSize),                         -- farbig
            textName  = NewText(STATE.textSize, STATE.colorText),
            textUser  = NewText(STATE.textSize-1, STATE.colorUsername),
            textEquip = NewText(STATE.textSize-1, STATE.colorEquipped),
            textDist  = NewText(STATE.textSize-1, STATE.colorText),
            bones     = {}
        }
        for i=1,14 do obj.bones[i] = NewLine() end
        pool[plr] = obj
        return obj
    end
    local function hideObj(obj)
        if not obj then return end
        if obj.textTeam  then obj.textTeam.Visible=false  end
        if obj.textName  then obj.textName.Visible=false  end
        if obj.textUser  then obj.textUser.Visible=false  end
        if obj.textEquip then obj.textEquip.Visible=false end
        if obj.textDist  then obj.textDist.Visible=false  end
        if obj.bones then for _,ln in ipairs(obj.bones) do ln.Visible=false end end
    end
    local function free(plr)
        local o = pool[plr]; if not o then return end
        for _,t in ipairs({o.textTeam,o.textName,o.textUser,o.textEquip,o.textDist}) do
            pcall(function() t:Remove() end)
        end
        for _,ln in ipairs(o.bones) do pcall(function() ln:Remove() end) end
        pool[plr] = nil
    end
    Players.PlayerRemoving:Connect(free)

    ----------------------------------------------------------------
    -- Equipped-Erkennung (robuster)
    local function findEquippedTool(char)
        -- 1) direktes Tool-Kind
        local tool = char and char:FindFirstChildOfClass("Tool")
        if tool then return tool end
        -- 2) Sicherheit: manchmal hängen Tools tiefer am Character
        for _,d in ipairs(char and char:GetDescendants() or {}) do
            if d:IsA("Tool") then return d end
        end
        return nil
    end
    local function getEquippedString(char)
        local tool = findEquippedTool(char)
        return tool and tool.Name or "Nothing equipped"
    end

    ----------------------------------------------------------------
    -- Skeleton (per Frame neu zeichnen – verhindert “stuck”)
    local function partPos(char, name)
        local p = char:FindFirstChild(name); return p and p.Position
    end
    local function setLine(ln, a, b, col)
        if not (a and b) then ln.Visible=false; return end
        local A, va = Camera:WorldToViewportPoint(a)
        local B, vb = Camera:WorldToViewportPoint(b)
        if not (va or vb) then ln.Visible=false; return end
        ln.From = Vector2.new(A.X, A.Y)
        ln.To   = Vector2.new(B.X, B.Y)
        ln.Color = col or STATE.bonesColor
        ln.Thickness = STATE.bonesThickness
        ln.Visible = true
    end
    local R15 = {
        {"UpperTorso","Head"},{"LowerTorso","UpperTorso"},
        {"UpperTorso","LeftUpperArm"},{"LeftUpperArm","LeftLowerArm"},{"LeftLowerArm","LeftHand"},
        {"UpperTorso","RightUpperArm"},{"RightUpperArm","RightLowerArm"},{"RightLowerArm","RightHand"},
        {"LowerTorso","LeftUpperLeg"},{"LeftUpperLeg","LeftLowerLeg"},{"LeftLowerLeg","LeftFoot"},
        {"LowerTorso","RightUpperLeg"},{"RightUpperLeg","RightLowerLeg"},{"RightLowerLeg","RightFoot"},
    }
    local R6 = {
        {"Torso","Head"},{"Torso","Left Arm"},{"Torso","Right Arm"},
        {"Torso","Left Leg"},{"Torso","Right Leg"},
        {"Left Arm","Left Arm"},{"Right Arm","Right Arm"},{"Left Leg","Left Leg"},{"Right Leg","Right Leg"},
    }
    local function drawSkeleton(obj, char, colorOverride)
        local joints = (char:FindFirstChild("Torso") and R6 or R15)
        for i,p in ipairs(joints) do
            setLine(obj.bones[i], partPos(char,p[1]), partPos(char,p[2]), colorOverride)
        end
        for i=#joints+1, #obj.bones do obj.bones[i].Visible=false end
    end

    ----------------------------------------------------------------
    -- Label/Stacking
    local function stackLine(tObj, text, baseX, baseY, yOff, color)
        if not text or text=="" then tObj.Visible=false; return yOff end
        tObj.Text = text
        tObj.Position = Vector2.new(baseX, baseY + yOff)
        if color then tObj.Color = color end
        tObj.Outline = STATE.textOutline
        tObj.Visible = true
        return yOff + tObj.Size + STATE.lineGap
    end

    ----------------------------------------------------------------
    -- Render loop
    RunService.RenderStepped:Connect(function()
        -- Policy strikt durchsetzen (verhindert manipulierte Configs)
        if SHOW_SELF_POLICY == "off" then
            STATE.showSelf = false
        elseif SHOW_SELF_POLICY == "on" then
            STATE.showSelf = true
        end

        local myHRP = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        for _,plr in ipairs(Players:GetPlayers()) do
            -- Lokalen Spieler nur berücksichtigen, wenn showSelf aktiv
            local include = (plr ~= LocalPlayer) or (plr == LocalPlayer and STATE.showSelf)
            if include then
                local char = plr.Character
                local hum  = char and char:FindFirstChildOfClass("Humanoid")
                local hrp  = char and char:FindFirstChild("HumanoidRootPart")
                if hum and hrp and hum.Health > 0 and myHRP then
                    local dist = (myHRP.Position - hrp.Position).Magnitude
                    local obj  = alloc(plr)
                    if dist <= STATE.maxDistance then
                        local pos, onScreen = Camera:WorldToViewportPoint(hrp.Position + Vector3.new(0, 6, 0))
                        if onScreen then
                            local x, y = pos.X, pos.Y
                            local yOff = 0

                            -- Team-Zeile (farbig, wenn aktiv)
                            local teamCol = STATE.showTeam and colorForTeam(plr) or nil
                            if STATE.showTeam and plr.Team then
                                yOff = stackLine(obj.textTeam, plr.Team.Name, x, y, yOff, teamCol or STATE.colorText)
                            else
                                obj.textTeam.Visible = false
                            end

                            -- DisplayName
                            if STATE.showName then
                                yOff = stackLine(obj.textName, (plr.DisplayName or plr.Name), x, y, yOff, STATE.colorText)
                            else obj.textName.Visible=false end

                            -- @Username
                            if STATE.showUsername then
                                yOff = stackLine(obj.textUser, "@"..plr.Name, x, y, yOff, STATE.colorUsername)
                            else obj.textUser.Visible=false end

                            -- Equipped (Tools only)
                            if STATE.showEquipped then
                                yOff = stackLine(obj.textEquip, getEquippedString(char), x, y, yOff, STATE.colorEquipped)
                            else obj.textEquip.Visible=false end

                            -- Distance (immer letzte Zeile)
                            if STATE.showDistance then
                                local dTxt = ("Distance: %d studs"):format(math.floor(dist+0.5))
                                yOff = stackLine(obj.textDist, dTxt, x, y, yOff, STATE.colorText)
                            else obj.textDist.Visible=false end

                            -- Skeleton (Teamfarbe, wenn Team aktiv)
                            if STATE.showBones then
                                drawSkeleton(obj, char, teamCol or nil)
                            else
                                for _,ln in ipairs(obj.bones) do ln.Visible=false end
                            end
                        else
                            hideObj(obj)
                        end
                    else
                        hideObj(obj)
                    end
                else
                    hideObj(pool[plr])
                end
            else
                hideObj(pool[plr])
            end
        end
    end)
end
