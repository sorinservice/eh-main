-- tabs/misc.lua
-- Misc: only a clean respawn that drops/loses all tools.

return function(tab, OrionLib)
    local Players = game:GetService("Players")
    local LP      = Players.LocalPlayer

    tab:AddButton({
        Name = "Respawn (lose all weapons/tools)",
        Callback = function()
            -- 1) Remove tools from Backpack and Character (so sie beim Tod nicht mitgenommen werden)
            local function nukeTools(container)
                if not container then return end
                for _, inst in ipairs(container:GetChildren()) do
                    if inst:IsA("Tool") then
                        pcall(function() inst:Destroy() end)
                    end
                end
            end
            nukeTools(LP:FindFirstChild("Backpack"))
            nukeTools(LP.Character)

            -- 2) Kill humanoid to trigger respawn
            local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
            if hum then
                hum.Health = 0
                OrionLib:MakeNotification({
                    Name = "Utility",
                    Content = "Respawn requested (inventory cleared).",
                    Time = 3
                })
            else
                OrionLib:MakeNotification({
                    Name = "Utility",
                    Content = "No humanoid found; try rejoining if respawn fails.",
                    Time = 4
                })
            end
        end
    })

    tab:AddParagraph("Note", "This forces a respawn and deletes all Tools from your Backpack.")
end
