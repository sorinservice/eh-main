-- tabs/functions/info/info.lua
-- Einfacher Info-Tab (Discord-Link kopieren, Warnhinweise, Version)

return function(tab, OrionLib, _Common) -- _Common optional
    local DISCORD_INVITE = "https://discord.gg/HE6Zhg5V"

    -- robuster Clipboard-Helper (verschiedene Executor-APIs)
    local function copyToClipboard(text)
        local ok = false
        if typeof(setclipboard) == "function" then
            ok = pcall(setclipboard, text)
        elseif getclipboard and setrbxclipboard then -- manche Umgebungen
            ok = pcall(setrbxclipboard, text)
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

    tab:AddLabel("Version: Developer (DEV)")

    tab:AddParagraph(
        "Thanks for using SorinHub DEV.",
        "This is the Developer Version. Why are you using this?\n" ..
        "It's not safe to use. You could be banned!!!\n" ..
        "New Tab: Vehicle Mod; not safe to use. NEVER USE MAIN ACCOUNTS!"
    )

    tab:AddButton({
        Name = "Join our Discord (copy invite)",
        Callback = function()
            copyToClipboard(DISCORD_INVITE)
        end
    })
end
