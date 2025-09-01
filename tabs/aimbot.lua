return function(tab, OrionLib)
    print("[SorinHub] test aimbot tab start")

    local RunService = game:GetService("RunService")
    local tickCount = 0

    RunService.Heartbeat:Connect(function()
        tickCount += 1
        if tickCount % 60 == 0 then
            print("Aimbot heartbeat OK", tickCount)
        end
    end)

    local main = tab:AddSection({ Name = "Aimbot (Test)" })
    main:AddLabel("Loaded minimal loop")
end
