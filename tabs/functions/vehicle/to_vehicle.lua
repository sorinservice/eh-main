-- tabs/vehicle/to_vehicle.lua
return function(SV, tab, OrionLib)
    print("Test 1.1")
    local RS   = game:GetService("ReplicatedStorage")
    local PLR  = game:GetService("Players").LocalPlayer
    local CHAR = PLR.Character or PLR.CharacterAdded:Wait()

    local REMOTE = RS:WaitForChild("Bnl"):WaitForChild("fdffc7c3-4c83-4693-8a33-380ed2d60083")
    local NEAR   = CFrame.new(-2, 0.5, 0)

    local function toVehicle()
        local hrp = CHAR:WaitForChild("HumanoidRootPart")
        local seat = workspace:WaitForChild("Vehicles")
            :WaitForChild(PLR.Name)
            :WaitForChild("DriveSeat")                -- exakt dieser Pfad

        -- 1) neben den Sitz
        hrp.CFrame = seat.CFrame * NEAR
        task.wait(0.10)

        -- 2) exakt wie SimpleSpy callt
        REMOTE:FireServer(seat, "Oj2", false)
    end

    local sec = tab:AddSection({ Name = "Vehicle (TP)" })
    sec:AddButton({ Name = "To Vehicle", Callback = toVehicle })
end
