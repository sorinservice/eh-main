-- tabs/visuals.lua
-- Visuals / ESP for SorinHub (Orion UI)
-- Per-player: DisplayName, @Username, Distance, Equipped, Skeleton, Team color
-- VSC Version

return function(tab, OrionLib)

    ----------------------------------------------------------------
    -- Services
    local Players     = game:GetService("Players")
    local Teams       = game:GetService("Teams")
    local RunService  = game:GetService("RunService")
    local Workspace   = game:GetService("Workspace")

    local LocalPlayer = Players.LocalPlayer
    local Camera      = Workspace.CurrentCamera

    ----------------------------------------------------------------
    -- Drawing API prüfen
    if not Drawing then
        tab:AddParagraph("Notice", "Your executor does not expose the Drawing API. Visuals are disabled.")
        return
    end

    ----------------------------------------------------------------
    -- Mapping loader (per PlaceId). Fallback zu _default.lua
    local BASE_MAP_URL = "https://raw.githubusercontent.com/sorinservice/eh-main/main/mappings/"
    local DEFAULT_MAP  = "_default.lua"

    local function httpLoad(u) return game:HttpGet(u) end
    local function loadMappingFor(placeId)
        local ok, src = pcall(httpLoad, BASE_MAP_URL .. tostring(placeId) .. ".lua")
        if ok and type(src)=="string" and #src>0 then
            local f = loadstring(src)
            local ok2, t = pcall(f)
            if ok2 and type(t)=="table" then t.__isDefault=false; return t end
        end
        local okD, srcD = pcall(httpLoad, BASE_MAP_URL .. DEFAULT_MAP)
        if okD and type(srcD)=="string" and #srcD>0 then
            local fD = loadstring(srcD)
            local ok2, tD = pcall(fD)
            if ok2 and type(tD)=="table" then tD.__isDefault=true; return tD end
        end
        return { byId = {}, byName = {}, defaultUnknown = "Unknown Item", __isDefault = true }
    end
    local Mapping = loadMappingFor(game.PlaceId)

    ----------------------------------------------------------------
    -- Konfiguration / State (persisted via Flags)
    local STATE = {
        -- Visual content
        showName       = false,
        showUsername   = false,
        showDistance   = false,
        showEquipped   = false,
        showBones      = false,
        showSelf       = false,
        showTeam       = false,   -- Team check (color & optional text)
        showTeamName   = true,    -- Teamname zusätzlich im Label

        -- Render/Erscheinung
        maxDistance    = 750,     -- studs
        textColorBase  = Color3.fromRGB(230,230,230),
        textSize       = 13,
        textOutline    = true,
        bonesColorBase = Color3.fromRGB(0,200,255),
        bonesThickness = 1.5,

        -- DEV: immer Rohdaten für Equipped anzeigen (auch wenn Mapping vorhanden)
        devShowRawEquipped = false,
    }

    -- Team-Farben optional über Namen mappen (leer lassen = Roblox TeamColor nutzen)
    local TEAM_COLORS = {
        -- Beispiel:
        -- ["Police"] = Color3.fromRGB(0, 170, 255),
        -- ["Criminals"] = Color3.fromRGB(255, 80, 80),
    }

    local function colorForTeam(plr)
        if not (plr and plr.Team) then return nil end
        local name = plr.Team.Name
        if TEAM_COLORS[name] then return TEAM_COLORS[name] end
        -- fallback: Roblox TeamColor
        local ok, col = pcall(function() return plr.Team.TeamColor.Color end)
        if ok and col then return col end
        return nil
    end

    ----------------------------------------------------------------
    -- UI (alles OFF per Default; Flags persistieren)
    tab:AddToggle({
        Name = "Show Name",
        Default = false, Save = true, Flag = "esp_showName",
        Callback = function(v) STATE.showName = v end
    })

    tab:AddToggle({
        Name = "Show Username",
        Default = false, Save = true, Flag = "esp_showUsername",
        Callback = function(v) STATE.showUsername = v end
    })

    tab:AddToggle({
        Name = "Show Distance",
        Default = false, Save = true, Flag = "esp_showDistance",
        Callback = function(v) STATE.showDistance = v end
    })

    tab:AddToggle({
        Name = "Show Equipped Item",
        Default = false, Save = true, Flag = "esp_showEquipped",
        Callback = function(v) STATE.showEquipped = v end
    })

    tab:AddToggle({
        Name = "Show Skeleton",
        Default = false, Save = true, Flag = "esp_showBones",
        Callback = function(v) STATE.showBones = v end
    })

    tab:AddToggle({
        Name = "Show Self (developer)",
        Default = false, Save = true, Flag = "esp_showSelf",
        Callback = function(v) STATE.showSelf = v end
    })

    tab:AddToggle({
        Name = "Team check (colorize)",
        Default = false, Save = true, Flag = "esp_teamCheck",
        Callback = function(v) STATE.showTeam = v end
    })

    tab:AddToggle({
        Name = "Show team name in label",
        Default = true, Save = true, Flag = "esp_teamName",
        Callback = function(v) STATE.showTeamName = v end
    })

    tab:AddToggle({
        Name = "Debug raw equipped (append ID/Name)",
        Default = false, Save = true, Flag = "esp_rawEquipped",
        Callback = function(v) STATE.devShowRawEquipped = v end
    })

    tab:AddSlider({
        Name = "ESP Render Range",
        Min = 50, Max = 2500, Increment = 10,
        Default = STATE.maxDistance, ValueName = "studs",
        Save = true, Flag = "esp_renderDist",
        Callback = function(v) STATE.maxDistance = v end
    })

    ----------------------------------------------------------------
    -- Drawing helpers (2 Texte pro Spieler: main + equipped)
    local function NewText()
        local t = Drawing.new("Text")
        t.Visible = false
        t.Color = STATE.textColorBase
        t.Outline = STATE.textOutline
        t.Size = STATE.textSize
        t.Center = true
        t.Transparency = 1
        return t
    end
    local function NewLine()
        local ln = Drawing.new("Line")
        ln.Visible = false
        ln.Color = STATE.bonesColorBase
        ln.Thickness = STATE.bonesThickness
        ln.Transparency = 1
        return ln
    end

    ----------------------------------------------------------------
    -- Per-player pool
    -- textMain: Name/Username/Distance/Team
    -- textEquip: Equipped (grau) unter main
    local pool = {} -- [plr] = { textMain=Text, textEquip=Text, bones={Line,...} }

    local function alloc(plr)
        if pool[plr] then return pool[plr] end
        local obj = { textMain = NewText(), textEquip = NewText(), bones = {} }
        obj.textEquip.Color = Color3.fromRGB(175,175,175) -- equip grau
        for i=1,14 do obj.bones[i] = NewLine() end
        pool[plr] = obj
        return obj
    end

    local function hideObj(obj)
        if not obj then return end
        if obj.textMain then obj.textMain.Visible = false end
        if obj.textEquip then obj.textEquip.Visible = false end
        if obj.bones then for _,ln in ipairs(obj.bones) do ln.Visible = false end end
    end

    local function free(plr)
        local obj = pool[plr]; if not obj then return end
        pcall(function() obj.textMain:Remove() end)
        pcall(function() obj.textEquip:Remove() end)
        for _,ln in ipairs(obj.bones) do pcall(function() ln:Remove() end) end
        pool[plr] = nil
    end
    Players.PlayerRemoving:Connect(free)

    ----------------------------------------------------------------
    -- Equipped string (Tools-only; Accessories werden ignoriert)
    local function rawIdFromTool(tool)
        local id
        pcall(function() id = tool.AssetId end)
        if not id then pcall(function() id = tool:GetAttribute("AssetId") end) end
        return id and tostring(id) or nil
    end

    local function getEquippedString(char)
        -- Nur echte Tools berücksichtigen
        local toolFound, txt = false, nil
        for _,inst in ipairs(char:GetChildren()) do
            if inst:IsA("Tool") then
                toolFound = true
                local byName = Mapping.byName and Mapping.byName[inst.Name]
                local byId   = nil
                do
                    local rid = rawIdFromTool(inst)
                    if rid and Mapping.byId then byId = Mapping.byId[rid] end
                end

                if byName or byId then
                    txt = tostring(byName or byId)
                else
                    -- Rohdaten optional anhängen
                    if STATE.devShowRawEquipped then
                        local rid = rawIdFromTool(inst)
                        if rid then
                            txt = string.format("Unknown (Id: %s | Name: %s)", rid, inst.Name)
                        else
                            txt = string.format("Unknown (Name: %s)", inst.Name)
                        end
                    else
                        txt = Mapping.defaultUnknown or "Unknown Item"
                    end
                end
                break
            end
        end
        if not toolFound then
            return "Nothing equipped"
        end
        return txt or (Mapping.defaultUnknown or "Unknown Item")
    end

    ----------------------------------------------------------------
    -- Skeleton
    local function partPos(char, name)
        local p = char:FindFirstChild(name); return p and p.Position
    end
    local function setLine(ln, a, b, col)
        if not (a and b) then ln.Visible=false; return end
        local A, visA = Camera:WorldToViewportPoint(a)
        local B, visB = Camera:WorldToViewportPoint(b)
        if not (visA or visB) then ln.Visible=false; return end
        ln.From = Vector2.new(A.X, A.Y)
        ln.To   = Vector2.new(B.X, B.Y)
        ln.Color = col or STATE.bonesColorBase
        ln.Thickness = STATE.bonesThickness
        ln.Visible = true
    end

    local R15_Joints = {
        {"UpperTorso","Head"},
        {"LowerTorso","UpperTorso"},
        {"UpperTorso","LeftUpperArm"},
        {"LeftUpperArm","LeftLowerArm"},
        {"LeftLowerArm","LeftHand"},
        {"UpperTorso","RightUpperArm"},
        {"RightUpperArm","RightLowerArm"},
        {"RightLowerArm","RightHand"},
        {"LowerTorso","LeftUpperLeg"},
        {"LeftUpperLeg","LeftLowerLeg"},
        {"LeftLowerLeg","LeftFoot"},
        {"LowerTorso","RightUpperLeg"},
        {"RightUpperLeg","RightLowerLeg"},
        {"RightLowerLeg","RightFoot"},
    }
    local R6_Joints = {
        {"Torso","Head"},
        {"Torso","Left Arm"},
        {"Torso","Right Arm"},
        {"Torso","Left Leg"},
        {"Torso","Right Leg"},
        {"Left Arm","Left Arm"},
        {"Right Arm","Right Arm"},
        {"Left Leg","Left Leg"},
        {"Right Leg","Right Leg"},
        {"Left Arm","Left Arm"},
        {"Right Arm","Right Arm"},
        {"Left Leg","Left Leg"},
        {"Right Leg","Right Leg"},
    }

    local function drawSkeleton(obj, char, colorOverride)
        local isR6 = (char:FindFirstChild("Torso") ~= nil)
        local joints = isR6 and R6_Joints or R15_Joints
        for i, pair in ipairs(joints) do
            setLine(obj.bones[i], partPos(char, pair[1]), partPos(char, pair[2]), colorOverride)
        end
        for i = #joints+1, #obj.bones do
            obj.bones[i].Visible = false
        end
    end

    ----------------------------------------------------------------
    -- Label builder (zweizeilig: main + equipped)
    local function buildMainLabel(plr, dist)
        local lines = {}
        -- Teamname vorn dran (optional)
        if STATE.showTeam and STATE.showTeamName and plr.Team then
            table.insert(lines, "["..plr.Team.Name.."]")
        end
        if STATE.showName     then table.insert(lines, plr.DisplayName or plr.Name) end
        if STATE.showUsername then table.insert(lines, "@" .. plr.Name) end
        if STATE.showDistance then table.insert(lines, ("Distance: %d studs"):format(math.floor(dist+0.5))) end
        return table.concat(lines, "  ")
    end

    local function isValidTarget(plr)
        if plr == LocalPlayer and not STATE.showSelf then return false end
        return true
    end

    ----------------------------------------------------------------
    -- Render loop (ESP immer aktiv)
    local function updateAll()
        local myHRP = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        for _,plr in ipairs(Players:GetPlayers()) do
            if isValidTarget(plr) then
                local char = plr.Character
                local hum  = char and char:FindFirstChildOfClass("Humanoid")
                local hrp  = char and char:FindFirstChild("HumanoidRootPart")
                if hum and hrp and hum.Health > 0 and myHRP then
                    local dist = (myHRP.Position - hrp.Position).Magnitude
                    local obj  = alloc(plr)
                    if dist <= STATE.maxDistance then
                        local pos, onScreen = Camera:WorldToViewportPoint(hrp.Position + Vector3.new(0, 3, 0))
                        if onScreen then
                            -- Teamfarbe (optional)
                            local col = STATE.textColorBase
                            local teamCol = STATE.showTeam and colorForTeam(plr) or nil
                            if teamCol then col = teamCol end

                            -- MAIN label
                            local mainText = buildMainLabel(plr, dist)
                            if mainText ~= "" then
                                obj.textMain.Text = mainText
                                obj.textMain.Position = Vector2.new(pos.X, pos.Y)
                                obj.textMain.Color = col
                                obj.textMain.Size = STATE.textSize
                                obj.textMain.Outline = STATE.textOutline
                                obj.textMain.Visible = true
                            else
                                obj.textMain.Visible = false
                            end

                            -- EQUIPPED label (grau) leicht darunter
                            if STATE.showEquipped then
                                local eq = getEquippedString(char)
                                obj.textEquip.Text = eq
                                obj.textEquip.Position = Vector2.new(pos.X, pos.Y + STATE.textSize + 2)
                                obj.textEquip.Size = math.max(11, STATE.textSize - 1)
                                obj.textEquip.Outline = STATE.textOutline
                                obj.textEquip.Visible = true
                            else
                                obj.textEquip.Visible = false
                            end

                            -- SKELETON
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
    end

    local conn = RunService.RenderStepped:Connect(updateAll)

    -- Cleanup bei UI-Close
    table.insert(OrionLib.Connections, {
        Disconnect = function()
            if conn then pcall(function() conn:Disconnect() end) end
            for plr,_ in pairs(pool) do free(plr) end
        end
    })
end
