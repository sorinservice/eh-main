-- tabs/vehicle/bring_to_vehicle.lua
return function(SV, tab, OrionLib)
    print("Test 2")
    local Players = game:GetService("Players")
    local RS      = game:GetService("ReplicatedStorage")
    local LP      = Players.LocalPlayer

    local notify      = SV.notify
    local BRING_AHEAD = 10
    local BRING_UP    = 2
    local NEAR_OFFSET = CFrame.new(-2, 0.5, 0)

    local REMOTE_NAME = "fdffc7c3-4c83-4693-8a33-380ed2d60083"
    local SeatRemote  = RS:WaitForChild("Bnl"):WaitForChild(REMOTE_NAME)

    local function bringVehicle()
        if SV.isSeated() then notify("Vehicle","Schon im Fahrzeug – Bring gesperrt."); return end
        local vf = SV.myVehicleFolder(); if not vf then notify("Vehicle","Kein Fahrzeug gefunden."); return end
        SV.ensurePrimaryPart(vf)

        local char = LP.Character or LP.CharacterAdded:Wait()
        local hrp  = char:WaitForChild("HumanoidRootPart")

        -- 1) Fahrzeug vor den Spieler bringen
        local look = hrp.CFrame.LookVector
        local pos  = hrp.Position + look * BRING_AHEAD + Vector3.new(0, BRING_UP, 0)
        local cf   = CFrame.lookAt(pos, pos + look)
        pcall(function() vf:PivotTo(cf) end)

        -- 2) Sitz bestimmen
        local seat = SV.findDriveSeat(vf) or workspace.Vehicles[LP.Name] and workspace.Vehicles[LP.Name]:FindFirstChild("DriveSeat")
        if not seat then notify("Vehicle","Kein Fahrersitz gefunden."); return end

        -- 3) Erst TP neben den Sitz …
        hrp.CFrame = seat.CFrame * NEAR_OFFSET
        task.wait(0.12)

        -- 4) … dann Server-Join
        SeatRemote:FireServer(seat, "Oj2", false)
    end

    local sec = tab:AddSection({ Name = "Vehicle (Bring)" })
    sec:AddButton({ Name = "Bring Vehicle (vor dich & einsteigen)", Callback = bringVehicle })
end
