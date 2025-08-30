-- tabs/bypass.lua
-- VoiceChat: minimal “Join Voice” helper + info paragraph.

return function(tab, OrionLib)
    local VCS
    local ok, err = pcall(function()
        VCS = game:GetService("VoiceChatService")
    end)

    tab:AddButton({
        Name = "Anti-VC-Ban (Join Voice)",
        Callback = function()
            if not ok or not VCS then
                OrionLib:MakeNotification({
                    Name = "VoiceChat",
                    Content = "VoiceChatService not available on this client/account.",
                    Time = 4
                })
                return
            end

            -- Try both possible method names, depending on client
            local success, msg = pcall(function()
                if typeof(VCS.JoinVoice) == "function" then
                    VCS:JoinVoice()
                elseif typeof(VCS.joinVoice) == "function" then
                    VCS:joinVoice()
                else
                    error("JoinVoice is not a valid member of VoiceChatService")
                end
            end)

            OrionLib:MakeNotification({
                Name = success and "VoiceChat" or "VoiceChat Error",
                Content = success and "JoinVoice invoked (if eligible)." or tostring(msg),
                Time = 4
            })
        end
    })

    tab:AddParagraph(
        "How it works?",
        "If your VC is blocked in the current server, this *may* force a reconnect."
    )
end
