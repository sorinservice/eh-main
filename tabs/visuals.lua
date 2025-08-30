-- tabs/visuals.lua
-- Visuals / ESP for SorinHub – modular, performant, Orion UI

return function(tab, OrionLib)

    ----------------------------------------------------------------
    -- Services / locals
    local Players     = game:GetService("Players")
    local RunService  = game:GetService("RunService")
    local Workspace   = game:GetService("Workspace")

    local LocalPlayer = Players.LocalPlayer
    local Camera      = Workspace.CurrentCamera

    ----------------------------------------------------------------
    -- State (controlled by UI)
    local STATE = {
        enabled       = false,
        showName      = false,
        showUsername  = false,
        showDistance  = false,
        showEquipped  = false,
        showBones     = false,
        showSelf      = false,
        maxDistance   = 750,  -- studs
        textColor     = Color3.fromRGB(230, 230, 230),
        textSize      = 13,
        textOutline   = true,
        bonesColor    = Color3.fromRGB(0, 200, 255),
        bonesThickness= 1.5,
        textTransparency = 0,    -- 0..1 (Drawing.Text uses 0..1)
        lineTransparency = 1,    -- Drawing.Line transparency is alpha 0..1 (1 = fully visible)
    }

    ----------------------------------------------------------------
    -- Mapping loader (per PlaceId). Fallback to _default.lua.
    local BASE_MAP_URL = "https://raw.githubusercontent.com/sorinservice/eh-main/main/mappings/"
    local DEFAULT_MAP  = "_default.lua"

    local function httpLoad(url)
        return game:HttpGet(url)
    end

    local function loadMappingFor(placeId)
        -- try place-specific
        local urlPlace = BASE_MAP_URL .. tostring(placeId) .. ".lua"
        local ok1, src1 = pcall(httpLoad, urlPlace)
        if ok1 and type(src1)=="string" and #src1>0 then
            local f = loadstring(src1)
            local okf, tbl = pcall(f)
            if okf and type(tbl)=="table" then
                tbl.__isDefault = false
                return tbl
            end
        end
        -- fallback default
        local urlDef = BASE_MAP_URL .. DEFAULT_MAP
        local ok2, src2 = pcall(httpLoad, urlDef)
        if ok2 and type(src2)=="string" and #src2>0 then
            local f = loadstring(src2)
            local okf, tbl = pcall(f)
            if okf and type(tbl)=="table" then
                tbl.__isDefault = true
                return tbl
            end
        end
        return { byId = {}, byName = {}, defaultUnknown = "Unknown Item", __isDefault = true }
    end

    local Mapping = loadMappingFor(game.PlaceId)

    ----------------------------------------------------------------
    -- Drawing API availability check
    local canDraw = (Drawing ~= nil)
    if not canDraw then
        tab:AddParagraph("Notice", "Your executor does not expose Drawing API. Visuals tab is disabled.")
        return
    end

    ----------------------------------------------------------------
    -- UI (each element has a Flag so Orion saves/restores it)
    tab:AddToggle({
        Name = "Enable ESP",
        Default = false,
        Flag = "esp_enabled",
        Save = true,
        Callback = function(v) STATE.enabled = v end
    })

    tab:AddToggle({
        Name = "Show Name",
        Default = true,
        Flag = "esp_showName",
        Save = true,
        Callback = function(v) STATE.showName = v end
    })

    tab:AddToggle({
        Name = "Show Username",
        Default = true,
        Flag = "esp_showUsername",
        Save = true,
        Callback = function(v) STATE.showUsername = v end
    })

    tab:AddToggle({
        Name = "Show Distance",
        Default = true,
        Flag = "esp_showDistance",
        Save = true,
        Callback = function(v) STATE.showDistance = v end
    })

    local usingDefaultMapping = (Mapping.__isDefault == true)

    tab:AddToggle({
        Name = "Show Equipped Item",
        Default = false,
        Flag = "esp_showEquipped",
        Save = true,
        Callback = function(v)
            if usingDefaultMapping then
                -- keep visible but do not allow enabling
                OrionLib.Flags["esp_showEquipped"]:Set(false)
                OrionLib:MakeNotification({
                    Name = "Mapping",
                    Content = "No game-specific mapping found. Equipped items are disabled.",
                    Time = 4
                })
                return
            end
            STATE.showEquipped = v
        end
    })

    tab:AddToggle({
        Name = "Show Skeleton",
        Default = false,
        Flag = "esp_showBones",
        Save = true,
        Callback = function(v) STATE.showBones = v end
    })

    tab:AddToggle({
        Name = "Show Self (developer)",
        Default = false,
        Flag = "esp_showSelf",
        Save = true,
        Callback = function(v) STATE.showSelf = v end
    })

    tab:AddSlider({
        Name = "ESP Render Range",
        Min = 50, Max = 2500, Increment = 10,
        Default = STATE.maxDistance,
        ValueName = "studs",
        Flag = "esp_renderDist",
        Save = true,
        Callback = function(v) STATE.maxDistance = v end
    })

    ----------------------------------------------------------------
    -- Helpers: Drawing constructors
    local function NewText()
        local t = Drawing.new("Text")
        t.Visible = false
        t.Color = STATE.textColor
        t.Outline = STATE.textOutline
        t.Size = STATE.textSize
        t.Center = true
        t.Transparency = 1 - STATE.textTransparency
        return t
    end

    local function NewLine(col)
        local ln = Drawing.new("Line")
        ln.Visible = false
        ln.Color = col or STATE.bonesColor
        ln.Thickness = STATE.bonesThickness
        ln.Transparency = STATE.lineTransparency
        return ln
    end

    ----------------------------------------------------------------
    -- Per-player pool: text + skeleton lines
    local pool = {}  -- [player] = { text=DrawingText, bones={Line,...} }

    local function allocFor(plr)
        if pool[plr] then return pool[plr] end
        local obj = { text = NewText(), bones = {} }
        -- skeleton needs a handful of lines
        for i=1,16 do obj.bones[i] = NewLine() end
        pool[plr] = obj
        return obj
    end

    local function freeFor(plr)
        local obj = pool[plr]
        if not obj then return end
        if obj.text then pcall(function() obj.text:Remove() end) end
        if obj.bones then
            for _,ln in ipairs(obj.bones) do pcall(function() ln:Remove() end) end
        end
        pool[plr] = nil
    end

    Players.PlayerRemoving:Connect(function(plr) freeFor(plr) end)

    ----------------------------------------------------------------
    -- Equipped item string via Mapping (placeholder logic)
    local function getEquippedString(char)
        -- Example heuristic:
        -- 1) Tool in backpack/character
        -- 2) Otherwise first Accessory class name
        local equippedName

        -- Tool equipped
        for _,inst in ipairs(char:GetChildren()) do
            if inst:IsA("Tool") then
                local mapName = Mapping.byName[inst.Name]
                local mapId   = Mapping.byId[tostring(inst.AssetId or inst.Name)]
                equippedName = mapName or mapId or inst.Name
                break
            end
        end

        if not equippedName then
            -- Any accessory (hat/face etc.)
            for _,inst in ipairs(char:GetChildren()) do
                if inst:IsA("Accessory") then
                    local mapName = Mapping.byName[inst.Name]
                    equippedName = mapName or inst.Name
                    break
                end
            end
        end

        if not equippedName then
            return "Nothing equipped"
        end
        return tostring(equippedName)
    end

    ----------------------------------------------------------------
    -- Skeleton joints resolver (supports R15 & R6 best-effort)
    local function headPos(char) local h=char:FindFirstChild("Head"); return h and h.Position end
    local function partPos(char, name)
        local p = char:FindFirstChild(name); return p and p.Position
    end

    local function setLine(ln, a, b)
        if not (a and b) then ln.Visible=false; return end
        local A,visA = Camera:WorldToViewportPoint(a)
        local B,visB = Camera:WorldToViewportPoint(b)
        local on = visA or visB
        ln.From = Vector2.new(A.X, A.Y)
        ln.To   = Vector2.new(B.X, B.Y)
        ln.Visible = on
    end

    local function drawSkeleton(obj, char)
        -- Try R15 names first; fallback to common R6 names if missing.
        local HRP = char:FindFirstChild("HumanoidRootPart")
        if not HRP then
            for _,ln in ipairs(obj.bones) do ln.Visible=false end
            return
        end

        local joints = {
            -- spine
            { "UpperTorso", "Head" },
            { "LowerTorso", "UpperTorso" },

            -- arms (left)
            { "UpperTorso","LeftUpperArm" },
            { "LeftUpperArm","LeftLowerArm" },
            { "LeftLowerArm","LeftHand" },

            -- arms (right)
            { "UpperTorso","RightUpperArm" },
            { "RightUpperArm","RightLowerArm" },
            { "RightLowerArm","RightHand" },

            -- legs (left)
            { "LowerTorso","LeftUpperLeg" },
            { "LeftUpperLeg","LeftLowerLeg" },
            { "LeftLowerLeg","LeftFoot" },

            -- legs (right)
            { "LowerTorso","RightUpperLeg" },
            { "RightUpperLeg","RightLowerLeg" },
            { "RightLowerLeg","RightFoot" },
        }

        -- If R6, adapt names
        local isR6 = (char:FindFirstChild("Torso") ~= nil)
        if isR6 then
            joints = {
                { "Torso","Head" },
                -- arms
                { "Torso","Left Arm" }, { "Left Arm","Left Arm" }, { "Left Arm","Left Arm" },
                { "Torso","Right Arm" },{ "Right Arm","Right Arm" },{ "Right Arm","Right Arm" },
                -- legs
                { "Torso","Left Leg" }, { "Left Leg","Left Leg" }, { "Left Leg","Left Leg" },
                { "Torso","Right Leg"},{ "Right Leg","Right Leg"},{ "Right Leg","Right Leg" },
            }
        end

        for i, pair in ipairs(joints) do
            local a = partPos(char, pair[1])
            local b = partPos(char, pair[2])
            setLine(obj.bones[i], a, b)
            obj.bones[i].Color = STATE.bonesColor
            obj.bones[i].Thickness = STATE.bonesThickness
            obj.bones[i].Transparency = STATE.lineTransparency
        end
        -- hide any unused lines
        for i = #joints+1, #obj.bones do
            obj.bones[i].Visible = false
        end
    end

    ----------------------------------------------------------------
    -- Per-frame updater
    local function buildLabel(plr, char, dist)
        local lines = {}

        if STATE.showName then
            table.insert(lines, "@" .. (plr.DisplayName or plr.Name))
        end
        if STATE.showUsername then
            table.insert(lines, "(" .. plr.Name .. ")")
        end
        if STATE.showDistance then
            table.insert(lines, ("Distance: %d studs"):format(math.floor(dist + 0.5)))
        end
        if STATE.showEquipped then
            table.insert(lines, getEquippedString(char))
        end

        if #lines == 0 then
            return "" -- nothing to show
        end
        -- first line (name) bold effect via outline already; just join with newlines
        return table.concat(lines, "\n")
    end

    local function isValidTarget(plr)
        if plr == LocalPlayer and not STATE.showSelf then return false end
        return true
    end

    local function updateAll()
        if not STATE.enabled then
            -- hide everything fast
            for _,obj in pairs(pool) do
                if obj.text then obj.text.Visible=false end
                if obj.bones then for _,ln in ipairs(obj.bones) do ln.Visible=false end end
            end
            return
        end

        for _,plr in ipairs(Players:GetPlayers()) do
            if isValidTarget(plr) then
                local char = plr.Character
                local hum = char and char:FindFirstChildOfClass("Humanoid")
                local hrp = char and char:FindFirstChild("HumanoidRootPart")
                if hum and hrp and hum.Health > 0 then
                    local obj = allocFor(plr)

                    -- distance cull
                    local dist = (LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart"))
                        and (LocalPlayer.Character.HumanoidRootPart.Position - hrp.Position).Magnitude
                        or math.huge
                    if dist <= STATE.maxDistance then
                        local screenPos, onScreen = Camera:WorldToViewportPoint(hrp.Position + Vector3.new(0, 3, 0))
                        if onScreen then
                            -- TEXT
                            local label = buildLabel(plr, char, dist)
                            if label ~= "" then
                                obj.text.Text = label
                                obj.text.Position = Vector2.new(screenPos.X, screenPos.Y)
                                obj.text.Color = STATE.textColor
                                obj.text.Size = STATE.textSize
                                obj.text.Outline = STATE.textOutline
                                obj.text.Transparency = 1 - STATE.textTransparency
                                obj.text.Visible = true
                            else
                                obj.text.Visible = false
                            end

                            -- SKELETON
                            if STATE.showBones then
                                drawSkeleton(obj, char)
                            else
                                for _,ln in ipairs(obj.bones) do ln.Visible=false end
                            end
                        else
                            obj.text.Visible = false
                            for _,ln in ipairs(obj.bones) do ln.Visible=false end
                        end
                    else
                        obj.text.Visible = false
                        for _,ln in ipairs(obj.bones) do ln.Visible=false end
                    end
                else
                    -- invalid char
                    local obj = pool[plr]
                    if obj then
                        obj.text.Visible = false
                        for _,ln in ipairs(obj.bones) do ln.Visible=false end
                    end
                end
            else
                -- not a valid target => hide
                local obj = pool[plr]
                if obj then
                    obj.text.Visible = false
                    for _,ln in ipairs(obj.bones) do ln.Visible=false end
                end
            end
        end
    end

    ----------------------------------------------------------------
    -- Render loop
    local connection
    connection = RunService.RenderStepped:Connect(updateAll)

    -- Safety: clean up if script/UI is closed
    local function cleanup()
        if connection then pcall(function() connection:Disconnect() end) end
        for plr,_ in pairs(pool) do freeFor(plr) end
    end
    OrionLib.Connections = OrionLib.Connections or {}
    table.insert(OrionLib.Connections, {Disconnect = cleanup})
end
