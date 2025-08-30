-- tabs/info.lua
return function(tab, OrionLib)
    -- Ping-Button
    tab:AddButton({
        Name = "Ping-Notification",
        Callback = function()
            OrionLib:MakeNotification({
                Name = "Ping",
                Content = "Ping erfolgreich",
                Time = 3
            })
        end
    })

    -- Demo: Toggle + kleiner Loop
    local state = false
    tab:AddToggle({
        Name = "AutoJump",
        Default = false,
        Callback = function(v) state = v end
    })

    task.spawn(function()
        while true do
            if state then
                local plr = game.Players.LocalPlayer
                local char = plr and plr.Character
                local hum = char and char:FindFirstChildOfClass("Humanoid")
                if hum then hum.Jump = true end
            end
            task.wait(0.5)
        end
    end)
end

