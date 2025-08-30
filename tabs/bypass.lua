-- tabs/bypass.lua
-- Bypass / Anti-VC Bann Tab (Demo)

return function(tab, OrionLib)

    -- Button: Versuch VoiceChat neu zu joinen
    tab:AddButton({
        Name = "Anti-VC-Ban",
        Callback = function()
            -- ruft VoiceChatService auf
            local ok, err = pcall(function()
                game:GetService("VoiceChatService"):JoinVoice()
            end)
            if ok then
                OrionLib:MakeNotification({
                    Name = "VoiceChat",
                    Content = "JoinVoice() ausgeführt.",
                    Time = 3
                })
            else
                OrionLib:MakeNotification({
                    Name = "VoiceChat",
                    Content = "Fehler: "..tostring(err),
                    Time = 4
                })
            end
        end
    })

    -- Infotext (Demo)
    tab:AddParagraph(
        "How it works?",
        "If your Voicechat is banned in the same Lobby you are currently in, you can reconnect it."
    )

end
