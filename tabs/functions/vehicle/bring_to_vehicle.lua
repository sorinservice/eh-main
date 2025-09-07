-- tabs/vehicle/bring_to_vehicle.lua
return function(SV, tab, OrionLib)
    print("Test 3")
    local RS   = game:GetService("ReplicatedStorage")
    local PLR  = game:GetService("Players").LocalPlayer
    local CHAR = PLR.Character or PLR.CharacterAdded:Wait()

    local REMOTE = RS:WaitForChild("Bnl"):WaitForChild("fdffc7c3-4c83-4693-8a33-380ed2d60083")
    local BRING_AHEAD, BRING_UP = 10, 2
    local NEAR = CFrame.new(-2, 0.5, 0)

    local function bringVehicle()
        local vf = workspace:WaitForChild("Vehicles"):FindFirstChild(PLR.Name)
        if not vf then return end
        SV.ensurePrimaryPart(vf)

        local hrp  = (CHAR or PLR.CharacterAdded:Wait()):WaitForChild("HumanoidRootPart")
        local look = hrp.CFrame.LookVector
        local pos  = hrp.Position + look * BRING_AHEAD + Vector3.new(0, BRING_UP, 0)
        vf:PivotTo(CFrame.lookAt(pos, pos + look))

        task.wait(0.10)

        -- immer frisch über exakt den Pfad holen
        local seat = workspace:WaitForChild("Vehicles")
            :WaitForChild(PLR.Name)
            :WaitForChild("DriveSeat")

        -- 1) neben den Sitz
        hrp.CFrame = seat.CFrame * NEAR
        task.wait(0.10)

        -- 2) exakt wie SimpleSpy callt
        REMOTE:FireServer(seat, "Oj2", false)
    end

    local sec = tab:AddSection({ Name = "Vehicle (Bring)" })
    sec:AddButton({ Name = "Bring Vehicle (vor dich & einsteigen)", Callback = bringVehicle })
end
