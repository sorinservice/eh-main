-- tabs/visuals.lua
-- Visuals / ESP for SorinHub (Orion UI)
-- Per-player: DisplayName, @Username, Distance, Equipped, Skeleton
-- All settings default OFF, persisted via Orion Flags.

return function(tab, OrionLib)

    ----------------------------------------------------------------
    -- DEV switch: allow using "Equipped" even with _default.lua mapping
    -- Set to true while you collect raw ids/names in unknown games.
    local DEV_AllowEquippedWithoutMapping = true

    ----------------------------------------------------------------
    -- Services
    local Players     = game:GetService("Players")
    local RunService  = game:GetService("RunService")
    local Workspace   = game:GetService("Workspace")

    local LocalPlayer = Players.LocalPlayer
    local Camera      = Workspace.CurrentCamera

    ----------------------------------------------------------------
    -- Early guard: Drawing API required
    if not Drawing then
        tab:AddParagraph("Notice", "Your executor does not expose the Drawing API. Visuals are disabled.")
        return
    end

    ----------------------------------------------------------------
    -- Mapping loader (per PlaceId). Fallback to _default.lua.
    local BASE_MAP_URL = "https://raw.githubusercontent.com/sorinservice/eh-main/main/mappings/"
    local DEFAULT_MAP  = "_default.lua"

    local function httpLoad(u) return game:HttpGet(u) end
    local function loadMappingFor(placeId)
        local ok, src = pcall(httpLoad, BASE_MAP_URL .. tostring(placeId) .. ".lua")
        if ok and type(src) == "string" and #src > 0 then
            local f = loadstring(src)
            local ok2, t = pcall(f)
            if ok2 and type(t) == "table" then t.__isDefault = false; return t end
        end
        local okD, srcD = pcall(httpLoad, BASE_MAP_URL .. DEFAULT_MAP)
        if okD and type(srcD) == "string" and #srcD > 0 then
            local fD = loadstring(srcD)
            local ok2, tD = pcall(fD)
            if ok2 and type(tD) == "table" then tD.__isDefault = true; return tD end
        end
        return { byId = {}, byName = {}, defaultUnknown = "Unknown Item", __isDefault = true }
    end

    local Mapping = loadMappingFor(game.PlaceId)

    ----------------------------------------------------------------
    -- State (persisted via Flags)
    local STATE = {
        enabled        = false,
        showName       = false,
        showUsername   = false,
        showDistance   = false,
        showEquipped   = false,
        showBones      = false,
        showSelf       = false,
        maxDistance    = 750, -- studs
        textColor      = Color3.fromRGB(230,230,230),
        textSize       = 13,
        textOutline    = true,
        bonesColor     = Color3.fromRGB(0,200,255),
        bonesThickness = 1.5,
    }

    ----------------------------------------------------------------
    -- UI (defaults OFF; Flags persist)
    tab:AddToggle({
        Name = "Enable ESP",
        Default = false, Save = true, Flag = "esp_enabled",
        Callback = function(v) STATE.enabled = v end
    })

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

    -- Equipped – optional dev bypass if mapping is default
    tab:AddToggle({
        Name = "Show Equipped Item",
        Default = false, Save = true, Flag = "esp_showEquipped",
        Callback = function(v)
            if Mapping.__isDefault and not DEV_AllowEquippedWithoutMapping then
                -- keep visible but block enabling
                STATE.showEquipped = false
                task.defer(function()
                    local flag = OrionLib.Flags and OrionLib.Flags["esp_showEquipped"]
                    if flag and flag.Set then flag:Set(false) end
                end)
                return
            end
            STATE.showEquipped = v
        end
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

    tab:AddSlider({
        Name = "ESP Render Range",
        Min = 50, Max = 2500, Increment = 10,
        Default = STATE.maxDistance, ValueName = "studs",
        Save = true, Flag = "esp_renderDist",
        Callback = function(v) STATE.maxDistance = v end
    })

    ----------------------------------------------------------------
    -- Drawing helpers
    local function NewText()
        local t = Drawing.new("Text")
        t.Visible = false
        t.Color = STATE.textColor
        t.Outline = STATE.textOutline
        t.Size = STATE.textSize
        t.Center = true
        t.Transparency = 1
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
    local pool = {} -- [plr] = { text=Text, bones={Line,...} }

    local function alloc(plr)
        if pool[plr] then return pool[plr] end
        local obj = { text = NewText(), bones = {} }
        for i=1,14 do obj.bones[i] = NewLine() end
        pool[plr] = obj
        return obj
    end

    local function hideObj(obj)
        if not obj then return end
        if obj.text then obj.text.Visible = false end
        if obj.bones then for _,ln in ipairs(obj.bones) do ln.Visible = false end end
    end

    local function free(plr)
        local obj = pool[plr]; if not obj then return end
        pcall(function() obj.text:Remove() end)
        for _,ln in ipairs(obj.bones) do pcall(function() ln:Remove() end) end
        pool[plr] = nil
    end
    Players.PlayerRemoving:Connect(free)

    ----------------------------------------------------------------
    -- Equipped string (mapping + dev raw output)
    local function rawIdFromTool(tool)
        -- Try common fields; executoren/scripte unterscheiden sich:
        local id = nil
        -- some tools have .AssetId; sometimes Attribute; sometimes in .ToolTip (rare)
        pcall(function() id = tool.AssetId end)
        if not id then
            pcall(function() id = tool:GetAttribute("AssetId") end)
        end
        if not id then
            -- keep nil; we’ll fall back to name only
        end
        return id and tostring(id) or nil
    end

    local function getEquippedString(char)
        -- 1) equipped Tool
        for _,inst in ipairs(char:GetChildren()) do
            if inst:IsA("Tool") then
                local byName = Mapping.byName[inst.Name]
                local byId   = Mapping.byId[rawIdFromTool(inst) or ""]
                if byName or byId then
                    return tostring(byName or byId)
                end
                -- unmapped: dev mode shows raw
                local rid = rawIdFromTool(inst)
                if Mapping.__isDefault and DEV_AllowEquippedWithoutMapping then
                    if rid then
                        return string.format("Unknown (Id: %s | Name: %s)", rid, inst.Name)
                    else
                        return string.format("Unknown (Name: %s)", inst.Name)
                    end
                end
                return Mapping.defaultUnknown or "Unknown Item"
            end
        end
        -- 2) first Accessory as last resort
        for _,inst in ipairs(char:GetChildren()) do
            if inst:IsA("Accessory") then
                local byName = Mapping.byName[inst.Name]
                if byName then return tostring(byName) end
                if Mapping.__isDefault and DEV_AllowEquippedWithoutMapping then
                    return string.format("Unknown (Name: %s)", inst.Name)
                end
                return Mapping.defaultUnknown or "Unknown Item"
            end
        end
        return "Nothing equipped"
    end

    ----------------------------------------------------------------
    -- Skeleton
    local function partPos(char, name)
        local p = char:FindFirstChild(name); return p and p.Position
    end
    local function setLine(ln, a, b)
        if not (a and b) then ln.Visible=false; return end
        local A, visA = Camera:WorldToViewportPoint(a)
        local B, visB = Camera:WorldToViewportPoint(b)
        if not (visA or visB) then ln.Visible=false; return end
        ln.From = Vector2.new(A.X, A.Y)
        ln.To   = Vector2.new(B.X, B.Y)
        ln.Color = STATE.bonesColor
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

    local function drawSkeleton(obj, char)
        local isR6 = (char:FindFirstChild("Torso") ~= nil)
        local joints = isR6 and R6_Joints or R15_Joints
        for i, pair in ipairs(joints) do
            setLine(obj.bones[i], partPos(char, pair[1]), partPos(char, pair[2]))
        end
        for i = #joints+1, #obj.bones do
            obj.bones[i].Visible = false
        end
    end

    ----------------------------------------------------------------
    -- Label builder
    local function buildLabel(plr, char, dist)
        local lines = {}
        if STATE.showName     then table.insert(lines, plr.DisplayName or plr.Name) end
        if STATE.showUsername then table.insert(lines, "@" .. plr.Name) end
        if STATE.showDistance then table.insert(lines, ("Distance: %d studs"):format(math.floor(dist+0.5))) end
        if STATE.showEquipped then table.insert(lines, getEquippedString(char)) end
        return table.concat(lines, "\n")
    end

    local function isValidTarget(plr)
        if plr == LocalPlayer and not STATE.showSelf then return false end
        return true
    end

    ----------------------------------------------------------------
    -- Render loop
    local function updateAll()
        if not STATE.enabled then
            for _,obj in pairs(pool) do hideObj(obj) end
            return
        end

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
                            local label = buildLabel(plr, char, dist)
                            if label ~= "" then
                                obj.text.Text = label
                                obj.text.Position = Vector2.new(pos.X, pos.Y)
                                obj.text.Color = STATE.textColor
                                obj.text.Size = STATE.textSize
                                obj.text.Outline = STATE.textOutline
                                obj.text.Visible = true
                            else
                                obj.text.Visible = false
                            end
                            if STATE.showBones then
                                drawSkeleton(obj, char)
                            else
                                for _,ln in ipairs(obj.bones) do ln.Visible = false end
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

    -- Cleanup on UI destroy
    table.insert(OrionLib.Connections, {
        Disconnect = function()
            if conn then pcall(function() conn:Disconnect() end) end
            for plr,_ in pairs(pool) do free(plr) end
        end
    })

end
