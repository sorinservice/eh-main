-- tabs/misc.lua
-- SorinHub Misc (nur für DEIN Spiel / private Tests!)
-- - Respawn & Inventar leeren
-- - Anti-FallDamage (HipHeight-Cushion, sanft, kein Velocity-Hack)
-- - Anti-Arrest (Teleport weg von Police, wenn nicht im Fahrzeug)
-- - Anti-Taser (State/PlatformStand/Constraints/Anim-Stop)
-- Hinweis: Enthält Debug-Prints, um echte Taser/Fall-Mechanik zu erkennen.

return function(tab, OrionLib)
    ------------------------------------------
    -- Services
    ------------------------------------------
    local Players    = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local Collection = game:GetService("CollectionService")
    local LP         = Players.LocalPlayer

    ------------------------------------------
    -- Hardcoded Settings (keine Slider)
    ------------------------------------------
    -- Anti-Fall
    local FALL_PROBE_DIST   = 12.0   -- Bodennähe, ab der gepuffert wird (Studs)
    local FALL_SAFE_OFFSET  = 2.4    -- Ziel-Höhe über Boden (HipHeight / “Schwebekante”)
    local FALL_RELAX_SPEED  = 0.35   -- wie schnell HipHeight wieder normalisiert

    -- Anti-Arrest
    local ARREST_RADIUS     = 12     -- Erkennungsradius (Studs)
    local ARREST_TELEPORT   = 15     -- Teleport-Offset (Studs)

    -- Anti-Taser
    local TASER_MAX_RECOVER = 0.30   -- kurze Sperre, um Spam zu vermeiden (Sek.)
    local DEFAULT_WALKSPEED = 16     -- Nur als Fallback, wird nicht “fest” überschrieben

    ------------------------------------------
    -- UI (nur Toggles)
    ------------------------------------------
    local secResp = tab:AddSection({ Name = "Respawn" })
    local secFall = tab:AddSection({ Name = "Anti FallDamage" })
    local secArr  = tab:AddSection({ Name = "Anti Arrest" })
    local secTas  = tab:AddSection({ Name = "Anti Taser" })

    -- Respawn-Button (aus deinem alten Tab)
    secResp:AddButton({
        Name = "Respawn (lose all weapons/tools)",
        Callback = function()
            local function nukeTools(container)
                if not container then return end
                for _,inst in ipairs(container:GetChildren()) do
                    if inst:IsA("Tool") then pcall(function() inst:Destroy() end) end
                end
            end
            nukeTools(LP:FindFirstChild("Backpack"))
            nukeTools(LP.Character)

            local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
            if hum then
                hum.Health = 0
                OrionLib:MakeNotification({ Name="Utility", Content="Respawn requested (inventory cleared).", Time=3 })
            else
                OrionLib:MakeNotification({ Name="Utility", Content="No humanoid found; try rejoining if respawn fails.", Time=4 })
            end
        end
    })
    tab:AddParagraph("Note", "This forces a respawn and deletes all Tools from your Backpack.")

    -- Toggles
    local antiFallEnabled   = false
    local antiArrestEnabled = false
    local antiTaserEnabled  = false

    secFall:AddToggle({
        Name = "Enable Anti-FallDamage",
        Default = false,
        Callback = function(v) antiFallEnabled = v end
    })
    secArr:AddToggle({
        Name = "Enable Anti-Arrest",
        Default = false,
        Callback = function(v) antiArrestEnabled = v end
    })
    secTas:AddToggle({
        Name = "Enable Anti-Taser",
        Default = false,
        Callback = function(v) antiTaserEnabled = v end
    })

    ------------------------------------------
    -- Helpers
    ------------------------------------------
    local function HumanoidFromChar(char)
        return char and char:FindFirstChildOfClass("Humanoid")
    end
    local function HRP(char)
        return char and char:FindFirstChild("HumanoidRootPart")
    end
    local function InVehicle(hum)
        if not hum then return false end
        return hum.Sit or hum.SeatPart ~= nil
    end
    local function MyTeamName(plr)
        local t = plr.Team
        return t and t.Name or nil
    end

    local function RayDown(origin, dist, ignore)
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = ignore or {}
        local result = workspace:Raycast(origin, Vector3.new(0, -dist, 0), params)
        if result then
            local gap = origin.Y - result.Position.Y
            return result, gap
        end
        return nil, nil
    end

    ------------------------------------------
    -- Anti-FallDamage (HipHeight-Cushion)
    ------------------------------------------
    local hipTarget     = nil       -- Ziel-HipHeight während Dämpfung
    local lastGroundGap = nil       -- nur fürs Debug
    local baseHipHeight = nil       -- merken & sanft zurück

    local function AntiFallTick(dt)
        if not antiFallEnabled then
            -- sauber zurück
            local hum = HumanoidFromChar(LP.Character)
            if hum and baseHipHeight then
                hum.HipHeight = hum.HipHeight + (baseHipHeight - hum.HipHeight) * math.clamp(dt * 4, 0, 1)
            end
            hipTarget = nil
            return
        end

        local char = LP.Character
        local hum  = HumanoidFromChar(char)
        local hrp  = HRP(char)
        if not (hum and hrp) then return end

        if baseHipHeight == nil then
            baseHipHeight = hum.HipHeight
        end

        local state = hum:GetState()
        if state ~= Enum.HumanoidStateType.Freefall and state ~= Enum.HumanoidStateType.FallingDown then
            -- relax Richtung baseline
            if hipTarget == nil and baseHipHeight then
                hum.HipHeight = hum.HipHeight + (baseHipHeight - hum.HipHeight) * math.clamp(dt / math.max(0.0001, (1 - FALL_RELAX_SPEED)), 0, 1)
            end
            return
        end

        local result, gap = RayDown(hrp.Position, FALL_PROBE_DIST + 10, {char})
        lastGroundGap = gap
        if result and gap and gap <= FALL_PROBE_DIST then
            -- halte ~FALL_SAFE_OFFSET über Boden
            hipTarget = FALL_SAFE_OFFSET
            -- nähere HipHeight sanft an hipTarget an
            hum.HipHeight = hum.HipHeight + (hipTarget - hum.HipHeight) * math.clamp(dt * 20, 0, 1)
            -- kurze “Landung” sobald wir sehr nahe sind
            if gap <= (FALL_SAFE_OFFSET + 0.3) then
                pcall(function() hum:ChangeState(Enum.HumanoidStateType.Landed) end)
            end
        else
            hipTarget = nil
            -- während Freefall, aber weit weg vom Boden: HipHeight langsam Richtung baseline
            if baseHipHeight then
                hum.HipHeight = hum.HipHeight + (baseHipHeight - hum.HipHeight) * math.clamp(dt * 1.5, 0, 1)
            end
        end
    end

    ------------------------------------------
    -- Anti-Arrest (Police näher als ARREST_RADIUS)
    ------------------------------------------
    local function AntiArrestTick(dt)
        if not antiArrestEnabled then return end
        local char = LP.Character
        local hum  = HumanoidFromChar(char)
        local hrp  = HRP(char)
        if not (hum and hrp) then return end
        if InVehicle(hum) then return end

        for _,plr in ipairs(Players:GetPlayers()) do
            if plr ~= LP and MyTeamName(plr) == "Police" then
                local phrp = HRP(plr.Character)
                if phrp then
                    local dist = (phrp.Position - hrp.Position).Magnitude
                    if dist <= ARREST_RADIUS then
                        -- Teleport leicht diagonal (pseudo-zufällig)
                        local dx = (math.random() > 0.5 and 1 or -1) * ARREST_TELEPORT
                        local dz = (math.random() > 0.5 and 1 or -1) * ARREST_TELEPORT
                        hrp.CFrame = hrp.CFrame + Vector3.new(dx, 0, dz)
                        OrionLib:MakeNotification({ Name="Anti-Arrest", Content="Teleported away from Police proximity.", Time=2 })
                        break
                    end
                end
            end
        end
    end

    ------------------------------------------
    -- Anti-Taser (mehrgleisig)
    -- Wir beobachten:
    --  - Humanoid.StateChanged / PlatformStand
    --  - neue Constraints (Ragdoll/Hinge/BallSocket)
    --  - Animationen (falls “tase”/“stun” im Name/Id)
    --  - “Unstuck”-Fallback: Sitz/Anchor/WalkSpeed-Minimum
    ------------------------------------------
    local lastRecover = 0
    local charConn = {}
    local function disconnectCharConns()
        for _,c in ipairs(charConn) do pcall(function() c:Disconnect() end) end
        table.clear(charConn)
    end

    local function onCharacterAdded(char)
        disconnectCharConns()
        if not char then return end

        -- State watcher
        local hum = HumanoidFromChar(char)
        if hum then
            table.insert(charConn, hum.StateChanged:Connect(function(_, new)
                if not antiTaserEnabled then return end
                if new == Enum.HumanoidStateType.Physics or new == Enum.HumanoidStateType.Ragdoll then
                    print("[AntiTaser] Humanoid state:", new.Name, " => clearing PlatformStand")
                    hum.PlatformStand = false
                    hum.Sit = false
                end
            end))
        end

        -- Descendant watcher (Constraints/Tags/Animations)
        table.insert(charConn, char.DescendantAdded:Connect(function(inst)
            if not antiTaserEnabled then return end
            -- Ragdoll-Constraints
            if inst:IsA("BallSocketConstraint") or inst:IsA("HingeConstraint") or inst:IsA("AngularVelocity") then
                local n = (inst.Name or ""):lower()
                if n:find("ragdoll") or n:find("tase") or n:find("stun") then
                    print("[AntiTaser] Removing constraint:", inst.ClassName, inst.Name)
                    pcall(function() inst:Destroy() end)
                end
            end
            -- Bool/Value Tags
            if inst:IsA("BoolValue") or inst:IsA("StringValue") then
                local n = (inst.Name or ""):lower()
                if n:find("stun") or n:find("tase") then
                    print("[AntiTaser] Clearing tag:", inst.Name)
                    pcall(function() inst:Destroy() end)
                end
            end
            -- AnimationTrack-Stop (Heuristik)
            if inst:IsA("Animation") then
                local id = tostring(inst.AnimationId or ""):lower()
                if id:find("tase") or id:find("stun") then
                    print("[AntiTaser] Found Animation with 'tase/stun':", inst.AnimationId)
                    local animator = hum and (hum:FindFirstChildOfClass("Animator"))
                    if animator then
                        for _,track in ipairs(animator:GetPlayingAnimationTracks()) do
                            local tid = tostring(track.Animation.AnimationId or ""):lower()
                            if tid:find("tase") or tid:find("stun") then
                                print("[AntiTaser] Stopping track:", tid)
                                pcall(function() track:Stop(0) end)
                            end
                        end
                    end
                end
            end
        end))
    end

    -- init char hooks
    onCharacterAdded(LP.Character)
    LP.CharacterAdded:Connect(onCharacterAdded)

    local function AntiTaserTick(dt)
        if not antiTaserEnabled then return end
        local char = LP.Character
        local hum  = HumanoidFromChar(char)
        local hrp  = HRP(char)
        if not (hum and hrp) then return end

        -- Harte Guards (ohne Werte “festzunageln”)
        if hum.PlatformStand then
            print("[AntiTaser] Clearing PlatformStand")
            hum.PlatformStand = false
        end
        if hum.Sit and not InVehicle(hum) then
            print("[AntiTaser] Clearing Sit (not in vehicle)")
            hum.Sit = false
        end

        -- Fallback: wenn WS künstlich auf 0 gehalten wird, kurze Recovery
        if time() - lastRecover > TASER_MAX_RECOVER then
            if hum.WalkSpeed < 1 and not InVehicle(hum) then
                print("[AntiTaser] WalkSpeed low, nudging up briefly")
                local old = hum.WalkSpeed
                hum.WalkSpeed = DEFAULT_WALKSPEED
                lastRecover = time()
                task.delay(0.15, function()
                    -- Server setzt üblicherweise wieder seinen Wert,
                    -- wir zwingen nichts dauerhaft.
                    hum.WalkSpeed = old
                end)
            end
        end
    end

    ------------------------------------------
    -- Heartbeat Loop
    ------------------------------------------
    RunService.Heartbeat:Connect(function(dt)
        AntiFallTick(dt)
        AntiArrestTick(dt)
        AntiTaserTick(dt)
    end)
end
