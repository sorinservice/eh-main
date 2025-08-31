-- tabs/bypass.lua
-- VoiceChat helpers (safe + executor friendly) — ohne Soft Reconnect

return function(tab, OrionLib)
    local Players          = game:GetService("Players")
    local VoiceChatService = game:GetService("VoiceChatService")
    local LP               = Players.LocalPlayer

    -- UI: Live-Status (wird aktualisiert)
    local statusPara = tab:AddParagraph("VoiceChat Status", "Checking...")
    local function setStatus(txt) pcall(function() statusPara:Set(txt) end) end

    -- Eligibility check
    local function isEnabledForUser()
        local ok, enabled = pcall(function()
            return VoiceChatService:IsVoiceEnabledForUserIdAsync(LP.UserId)
        end)
        return ok and enabled
    end

    -- Statusstring zusammenbauen
    local function readStateString()
        local parts = {}
        table.insert(parts, isEnabledForUser() and "Eligible: yes" or "Eligible: no")
        local ok, state = pcall(function()
            if typeof(VoiceChatService.GetStateForUserAsync) == "function" then
                return VoiceChatService:GetStateForUserAsync(LP.UserId)
            end
        end)
        if ok and state ~= nil then table.insert(parts, "State: "..tostring(state)) end
        return table.concat(parts, "  |  ")
    end
    setStatus(readStateString())

    -- Versuche *irgendeine* Join-Variante (inkl. deiner alten)
    local function tryJoinOnce()
        if typeof(VoiceChatService.joinVoice) == "function" then
            return pcall(function() VoiceChatService:joinVoice() end)
        end
        if typeof(VoiceChatService.Join) == "function" then
            return pcall(function() VoiceChatService:Join() end)
        end
        if typeof(VoiceChatService.JoinAsync) == "function" then
            return pcall(function() VoiceChatService:JoinAsync() end)
        end
        if typeof(VoiceChatService.JoinByGroupId) == "function" then
            return pcall(function() VoiceChatService:JoinByGroupId(tostring(game.PlaceId)) end)
        end
        return false, "No join* method available on VoiceChatService"
    end

    -- Button: Join
    tab:AddButton({
        Name = "Anti-VC-Ban (Join Voice)",
        Callback = function()
            if not isEnabledForUser() then
                OrionLib:MakeNotification({
                    Name = "VoiceChat",
                    Content = "Voice is not enabled for this account or game.",
                    Time = 4
                })
                setStatus(readStateString())
                return
            end
            local ok, err = tryJoinOnce()
            OrionLib:MakeNotification({
                Name = "VoiceChat",
                Content = ok and "Join attempt sent." or ("Join failed: "..tostring(err)),
                Time = ok and 3 or 5
            })
            task.delay(0.5, function() setStatus(readStateString()) end)
        end
    })


    -- Info
    tab:AddParagraph(
        "How it works?",
        "Tries several join methods.\n" ..
        "If it fails, enable Auto-Retry."
    )

    -- Falls Signal existiert: Status updaten
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
