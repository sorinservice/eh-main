-- tabs/bypass.lua
-- VoiceChat helpers (safe + executor friendly)

return function(tab, OrionLib)
    local Players          = game:GetService("Players")
    local VoiceChatService = game:GetService("VoiceChatService")
    local LP               = Players.LocalPlayer

    ----------------------------------------------------------------
    -- UI: Live-Status Paragraph, wird von Code aktualisiert
    local statusPara = tab:AddParagraph("VoiceChat Status", "Checking...")

    local function setStatus(txt)
        -- kurze, robuste Aktualisierung
        pcall(function() statusPara:Set(txt) end)
    end

    ----------------------------------------------------------------
    -- Capability / Eligibility check
    local function isEnabledForUser()
        local ok, enabled = pcall(function()
            -- offiziell verfügbarer Check
            return VoiceChatService:IsVoiceEnabledForUserIdAsync(LP.UserId)
        end)
        return ok and enabled
    end

    -- liest einen möglichst nützlichen State (falls exposed)
    local function readStateString()
        -- Es gibt Spiele/Executors, wo nur ein Teil der API exposed ist
        -- Wir bauen den String daher defensiv zusammen:
        local parts = {}

        local enabled = isEnabledForUser()
        table.insert(parts, enabled and "Eligible: yes" or "Eligible: no")

        -- Manche Umgebungen haben PlayerVoiceChatStateChanged, andere nicht.
        -- Wir probieren einen aktuellen State über GetStateForUserAsync:
        local ok, state = pcall(function()
            if typeof(VoiceChatService.GetStateForUserAsync) == "function" then
                return VoiceChatService:GetStateForUserAsync(LP.UserId)
            end
        end)
        if ok and state ~= nil then
            table.insert(parts, "State: "..tostring(state))
        end

        return table.concat(parts, "  |  ")
    end

    -- initial anzeigen
    setStatus(readStateString())

    ----------------------------------------------------------------
    -- Low-level: versuche *irgendeine* Join-Methode
    local function tryJoinOnce()
        -- Dein historischer Call zuerst:
        if typeof(VoiceChatService.joinVoice) == "function" then
            return pcall(function() VoiceChatService:joinVoice() end)
        end
        -- häufige Alternativen:
        if typeof(VoiceChatService.Join) == "function" then
            return pcall(function() VoiceChatService:Join() end)
        end
        if typeof(VoiceChatService.JoinAsync) == "function" then
            return pcall(function() VoiceChatService:JoinAsync() end)
        end
        if typeof(VoiceChatService.JoinByGroupId) == "function" then
            -- manche Implementationen wollen eine Gruppen/Lobby-ID; als Fallback PlaceId
            return pcall(function() VoiceChatService:JoinByGroupId(tostring(game.PlaceId)) end)
        end
        -- Nichts Passendes gefunden
        return false, "No join* method available on VoiceChatService"
    end

    ----------------------------------------------------------------
    -- Button: “Force(ish) Join Voice”
    tab:AddButton({
        Name = "Anti-VC-Ban (Join Voice)",
        Callback = function()
            -- 1) Eligibility prüfen
            local eligible = isEnabledForUser()
            if not eligible then
                OrionLib:MakeNotification({
                    Name = "VoiceChat",
                    Content = "Voice is not enabled for this account or game.",
                    Time = 4
                })
                setStatus(readStateString())
                return
            end

            -- 2) Join versuchen (alle bekannten Varianten)
            local ok, err = tryJoinOnce()

            if ok then
                OrionLib:MakeNotification({
                    Name = "VoiceChat",
                    Content = "Join attempt sent.",
                    Time = 3
                })
            else
                OrionLib:MakeNotification({
                    Name = "VoiceChat",
                    Content = "Join failed: "..tostring(err),
                    Time = 5
                })
            end

            -- Status aktualisieren (kleiner Delay, falls async)
            task.delay(0.5, function() setStatus(readStateString()) end)
        end
    })

    ----------------------------------------------------------------
    -- Zusatz: Auto-Retry (versucht alle 5s zu joinen bis aktiv/aus)
    local AUTO = { on = false, conn = nil }

    tab:AddToggle({
        Name = "Auto-Retry join (every 5s)",
        Default = false,
        Save = true,
        Flag = "vc_autoretry",
        Callback = function(v)
            AUTO.on = v
            if v then
                -- kleiner Loop
                task.spawn(function()
                    while AUTO.on do
                        if isEnabledForUser() then
                            local ok = pcall(function()
                                -- wenn schon “drin”, nichts tun; wir versuchen es aber einmal
                                tryJoinOnce()
                            end)
                            -- status aktualisieren
                            setStatus(readStateString())
                        end
                        for i=1,50 do
                            if not AUTO.on then break end
                            task.wait(0.1)
                        end
                    end
                end)
            end
        end
    })

    ----------------------------------------------------------------
    -- “Soft Reconnect” (optional): Character respawn
    tab:AddButton({
        Name = "Soft Reconnect (respawn)",
        Callback = function()
            local char = LP.Character
            if char then
                OrionLib:MakeNotification({
                    Name = "VoiceChat",
                    Content = "Respawning your character...",
                    Time = 2
                })
                pcall(function() char:BreakJoints() end)
                task.delay(1.0, function()
                    setStatus(readStateString())
                end)
            end
        end
    })

    ----------------------------------------------------------------
    -- Info
    tab:AddParagraph(
        "How it works?",
        "Roblox does not officially expose a guaranteed Join/Leave API for Voice.\n" ..
        "This tab tries several known join methods (including your old :joinVoice()).\n" ..
        "Eligibility is checked via IsVoiceEnabledForUserIdAsync.\n" ..
        "If joining fails, try Auto-Retry or a soft reconnect (respawn)."
    )

    ----------------------------------------------------------------
    -- Optional: Live-Event (wenn vorhanden) – Status refreshen
    pcall(function()
        if typeof(VoiceChatService.PlayerVoiceChatStateChanged) == "RBXScriptSignal" then
            VoiceChatService.PlayerVoiceChatStateChanged:Connect(function(userId, state)
                if userId == LP.UserId then
                    setStatus("State: "..tostring(state).."  |  "..(isEnabledForUser() and "Eligible: yes" or "Eligible: no"))
                end
            end)
        end
    end)
end
