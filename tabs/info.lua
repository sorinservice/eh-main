-- tabs/info.lua  (BETA)
return function(tab, OrionLib)
    local DISCORD_INVITE = "https://discord.gg/HE6Zhg5V"

    local function copyToClipboard(text)
        local ok = false
        if setclipboard then
            ok = pcall(setclipboard, text)
        elseif syn and syn.write_clipboard then
            ok = pcall(syn.write_clipboard, text)
        elseif toclipboard then
            ok = pcall(toclipboard, text)
        end

        if ok then
            OrionLib:MakeNotification({
                Name = "Discord",
                Content = "Invite-Link wurde in die Zwischenablage kopiert.",
                Time = 4
            })
        else
            OrionLib:MakeNotification({
                Name = "Hinweis",
                Content = "Konnte nicht kopieren – Link in der Konsole ausgegeben.",
                Time = 6
            })
            print("[SorinHub] Discord invite:", text)
        end
    end

    tab:AddLabel("Version: Beta (BETA)")

    tab:AddParagraph(
        "Thanks for testing SorinHub",
        "This is the Beta Version.\n" ..
        "New: Graphics Tab"
    )

    tab:AddButton({
        Name = "Join our Discord (copy invite)",
        Callback = function()
            copyToClipboard(DISCORD_INVITE)
        end
    })
end
