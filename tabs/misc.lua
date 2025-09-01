-- tabs/misc.lua
-- Misc utilities for SorinHub:
--  - Respawn (deletes all Tools first)
--  - Anti-Fall (two modes: Pads / Velocity)
--  - Anti-Arrest (soft TP away from nearby Police when on foot)
--  - Anti-Taser (recover from ragdoll/stun with subtle stabilization)

return function(tab, OrionLib)
    --// Services
    local Players       = game:GetService("Players")
    local RunService    = game:GetService("RunService")
    local Debris        = game:GetService("Debris")
    local Workspace     = game:GetService("Workspace")

    local LP            = Players.LocalPlayer
    local Camera        = Workspace.CurrentCamera

    --// ====== CODE-SIDE TUNABLES (no sliders in UI) ============================
    local CFG = {
        AntiFall = {
            Mode            = "Pads",   -- "Pads" or "Velocity" (default)
            MinFallSpeed    = 40,       -- start protecting when |vy| >= this
            MinHeightDrop   = 18,       -- start after falling at least this vertical distance

            -- Pads mode
            PadSpacingY     = 10,       -- spawn next pad after dropping this much since last pad
            PadLife         = 0.25,     -- seconds the pad remains
            PadYOffset      = 4.5,      -- place pad this far below HRP
            PadSizeXZ       = 14,       -- square pad X/Z, thickness fixed below
            PadThickness    = 0.6,      -- keeps it subtle; thin, just enough to register

            -- Velocity mode
            CapDownSpeed    = 65,       -- never allow vy < -65
            BlendFactor     = 0.35,     -- lerp strength toward clamped vy (0..1)
        },

        AntiArrest = {
            TriggerRange    = 10,       -- studs: police within this radius
            TeleportAway    = 16,       -- studs to sidestep
            Cooldown        = 1.2,      -- seconds between teleports
        },

        AntiTaser = {
            RecoverDelay    = 0.06,     -- short wait to avoid snapping mid-frame
            NudgeUp         = 1.25,     -- small lift so we don't clip floor
            SideStep        = 2.5,      -- tiny lateral move to break pin
            Cooldown        = 1.0,      -- cooldown per stun recovery
        }
    }
    --===========================================================================

    --// Utilities
    local function getHumanoid(char)      return char and char:FindFirstChildOfClass("Humanoid") end
    local function getHRP(char)           return char and char:FindFirstChild("HumanoidRootPart") end
    local function inVehicle(char, hum)
        hum = hum or getHumanoid(char)
        if not hum then return false end
        if hum.Sit then return true end
        -- also detect VehicleSeat attachments
        for _,d in ipairs(char:GetDescendants()) do
            if d:IsA("VehicleSeat") then return true end
        end
        return false
    end

    local function safeCFrameSet(hrp, cf)
        -- guard against nil/NaN
        if not hrp or not cf then return end
        if cf.X ~= cf.X or cf.Y ~= cf.Y or cf.Z ~= cf.Z then return end
        hrp.CFrame = cf
    end

    --// ========== Respawn (delete all tools first) ============================
    tab:AddButton({
        Name = "Respawn (lose all weapons/tools)",
        Callback = function()
            local function nukeTools(container)
                if not container then return end
                for _, inst in ipairs(container:GetChildren()) do
                    if inst:IsA("Tool") then pcall(function() inst:Destroy() end) end
                end
            end
            nukeTools(LP:FindFirstChild("Backpack"))
            nukeTools(LP.Character)
            local hum = getHumanoid(LP.Character)
            if hum then
                hum.Health = 0
                OrionLib:MakeNotification({ Name="Utility", Content="Respawn requested (inventory cleared).", Time=3 })
            else
                OrionLib:MakeNotification({ Name="Utility", Content="No humanoid found; rejoin if respawn fails.", Time=4 })
            end
        end
    })

    tab:AddParagraph("Note", "Respawns and deletes all Tools from your Backpack/Character.")

    --// =================== Anti-Fall: pads & velocity =========================
    -- Anti-Fall Damage (Velocity only)
local antiFallEnabled = false
local fallConn

local function stepAntiFall(dt)
    local char = LP.Character
    local hum  = getHumanoid(char)
    local hrp  = getHRP(char)
    if not (char and hum and hrp) then return end

    local vy = hrp.AssemblyLinearVelocity.Y
    local falling = vy < -CFG.AntiFall.MinFallSpeed and hum.FloorMaterial == Enum.Material.Air
    if not falling then return end

    -- Velocity clamp
    local cap     = -math.abs(CFG.AntiFall.CapDownSpeed)
    local newVy   = math.max(vy, cap)
    local v       = hrp.AssemblyLinearVelocity
    if newVy ~= vy then
        local blendedY = vy + (newVy - vy) * CFG.AntiFall.BlendFactor
        hrp.AssemblyLinearVelocity = Vector3.new(v.X, blendedY, v.Z)
    end
end

local function startAntiFall()
    if fallConn then fallConn:Disconnect() end
    fallConn = RunService.Heartbeat:Connect(stepAntiFall)
end

local function stopAntiFall()
    if fallConn then fallConn:Disconnect(); fallConn = nil end
end

local secFall = tab:AddSection({ Name = "Anti-Fall Damage" })
secFall:AddToggle({
    Name = "Enable Anti-Fall (Velocity Clamp)",
    Default = false,
    Callback = function(v)
        antiFallEnabled = v
        if v then startAntiFall() else stopAntiFall() end
    end
})


    --// =================== Anti-Arrest (soft TP) ==============================
    local antiArrestEnabled = false
    local arrestConn
    local lastArrestTP = 0

    local function isPolice(plr)
        local t = plr.Team
        return t and (t.Name == "Police")
    end
    local function isCitizen(plr)
        local t = plr.Team
        return t and (t.Name == "Citizen")
    end

    local function stepAntiArrest(dt)
        local now = os.clock()
        if now - lastArrestTP < CFG.AntiArrest.Cooldown then return end

        local char = LP.Character
        local hum  = getHumanoid(char)
        local hrp  = getHRP(char)
        if not (char and hum and hrp) then return end
        if inVehicle(char, hum) then return end
        if not isCitizen(LP) then return end -- only protect citizens from police

        local myPos = hrp.Position
        for _,plr in ipairs(Players:GetPlayers()) do
            if plr ~= LP and isPolice(plr) and plr.Character then
                local phrp = getHRP(plr.Character)
                if phrp then
                    local dist = (phrp.Position - myPos).Magnitude
                    if dist <= CFG.AntiArrest.TriggerRange then
                        -- teleport sideways away from officer (relative to camera forward)
                        local forward = Camera.CFrame.LookVector
                        local right   = Camera.CFrame.RightVector
                        local awayDir = (myPos - phrp.Position).Unit
                        -- mix world 'away' with camera right for a more natural sidestep
                        local dir = (awayDir + right * 0.5).Unit
                        local target = myPos + dir * CFG.AntiArrest.TeleportAway
                        safeCFrameSet(hrp, CFrame.new(target))
                        lastArrestTP = now
                        OrionLib:MakeNotification({
                            Name = "Anti-Arrest",
                            Content = "Teleported away from nearby Police.",
                            Time = 2
                        })
                        return
                    end
                end
            end
        end
    end

    local function startAntiArrest()
        if arrestConn then arrestConn:Disconnect() end
        lastArrestTP = 0
        arrestConn = RunService.Heartbeat:Connect(stepAntiArrest)
    end
    local function stopAntiArrest()
        if arrestConn then arrestConn:Disconnect(); arrestConn = nil end
    end

    local secArrest = tab:AddSection({ Name = "Anti-Arrest" })
    secArrest:AddToggle({
        Name = "Enable Anti-Arrest (on foot)",
        Default = false,
        Callback = function(v)
            antiArrestEnabled = v
            if v then startAntiArrest() else stopAntiArrest() end
        end
    })

    --// =================== Anti-Taser (stun recovery) =========================
    local antiTaserEnabled = false
    local taserConn
    local lastTaserFix = 0

    -- Detect a “taser-like” state: sudden ragdoll/platform stand / no movement control.
    local function looksStunned(hum, hrp)
        if not (hum and hrp) then return false end
        -- platform stand is common for ragdolls
        if hum.PlatformStand then return true end
        -- some games zero out WalkSpeed or set JumpPower very low
        if hum.WalkSpeed <= 2 then
            -- also check we are not seated
            if not hum.Sit then return true end
        end
        return false
    end

    local function recoverFromTaser(hum, hrp)
        local now = os.clock()
        if now - lastTaserFix < CFG.AntiTaser.Cooldown then return end
        lastTaserFix = now

        task.delay(CFG.AntiTaser.RecoverDelay, function()
            if not (hum and hrp and hum.Parent and hrp.Parent) then return end
            -- gentle un-stun
            hum.PlatformStand = false
            pcall(function() hum:ChangeState(Enum.HumanoidStateType.Running) end)

            -- micro lift + sidestep to avoid immediate re-stun/ground friction
            local cf = hrp.CFrame
            local side = Camera.CFrame.RightVector * CFG.AntiTaser.SideStep
            local up   = Vector3.new(0, CFG.AntiTaser.NudgeUp, 0)
            safeCFrameSet(hrp, CFrame.new((cf.Position + side + up)))
        end)
    end

    local function stepAntiTaser(dt)
        local char = LP.Character
        local hum  = getHumanoid(char)
        local hrp  = getHRP(char)
        if not (char and hum and hrp) then return end
        if not looksStunned(hum, hrp) then return end
        recoverFromTaser(hum, hrp)
    end

    local function startAntiTaser()
        if taserConn then taserConn:Disconnect() end
        lastTaserFix = 0
        taserConn = RunService.Heartbeat:Connect(stepAntiTaser)
    end
    local function stopAntiTaser()
        if taserConn then taserConn:Disconnect(); taserConn = nil end
    end

    local secTaser = tab:AddSection({ Name = "Anti-Taser" })
    secTaser:AddToggle({
        Name = "Enable Anti-Taser",
        Default = false,
        Callback = function(v)
            antiTaserEnabled = v
            if v then startAntiTaser() else stopAntiTaser() end
        end
    })

    --// Cleanup when UI is closed (if your Orion exposes a close hook, bind it there)
    -- best-effort local cleanup function:
    local function cleanup()
        stopAntiFall()
        stopAntiArrest()
        stopAntiTaser()
    end

    -- Optional: add a maintenance button
    local secMaint = tab:AddSection({ Name = "Maintenance" })
    secMaint:AddButton({
        Name = "Stop All Protections",
        Callback = cleanup
    })
end
