-- tabs/vehicle/bring_to_vehicle.lua
return function(SV, tab, OrionLib)
    print("Test 1")
    local Players = game:GetService("Players")
    local RS      = game:GetService("ReplicatedStorage")
    local LP      = Players.LocalPlayer

    local notify      = SV.notify
    local BRING_AHEAD = 10
    local BRING_UP    = 2

    -- exakt dieses RemoteEvent
    local SeatRemote = RS:WaitForChild("Bnl"):WaitForChild("fdffc7c3-4c83-4693-8a33-380ed2d60083")

    local function fireSeatRemote(seat)
        SeatRemote:FireServer(seat, "Oj2", false)
    end

    local function bringVehicle()
        if SV.isSeated() then notify("Vehicle","Schon im Fahrzeug – Bring gesperrt."); return end

        local vf = SV.myVehicleFolder(); if not vf then notify("Vehicle","Kein Fahrzeug gefunden."); return end
        SV.ensurePrimaryPart(vf)

        local char = LP.Character or LP.CharacterAdded:Wait()
        local hrp  = char:FindFirstChild("HumanoidRootPart")
        if not hrp then notify("Vehicle","Kein HRP."); return end

        local look = hrp.CFrame.LookVector
        local pos  = hrp.Position + look * BRING_AHEAD + Vector3.new(0, BRING_UP, 0)
        local cf   = CFrame.lookAt(pos, pos + look)
        pcall(function() vf:PivotTo(cf) end)

        task.wait(0.1)
        local seat = SV.findDriveSeat(vf)
        if seat then fireSeatRemote(seat) else notify("Vehicle","Kein Fahrersitz gefunden.") end
    end

    local sec = tab:AddSection({ Name = "Vehicle (Bring)" })
    sec:AddButton({ Name = "Bring Vehicle (vor dich & einsteigen)", Callback = bringVehicle })
end
