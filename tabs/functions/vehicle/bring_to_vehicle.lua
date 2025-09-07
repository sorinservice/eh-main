-- tabs/vehicle/bring_to_vehicle.lua
return function(SV, tab, OrionLib)
    local notify = SV.notify
    local BRING_AHEAD = 10
    local BRING_UP    = 2

    local function bringVehicle()
        if SV.isSeated() then notify("Vehicle","Schon im Fahrzeug – Bring gesperrt."); return end
        local vf = SV.myVehicleFolder(); if not vf then notify("Vehicle","Kein Fahrzeug gefunden."); return end
        SV.ensurePrimaryPart(vf)

        local hrp = SV.LP.Character and SV.LP.Character:FindFirstChild("HumanoidRootPart")
        if not hrp then notify("Vehicle","Kein HRP."); return end

        local look = hrp.CFrame.LookVector
        local pos  = hrp.Position + look * BRING_AHEAD + Vector3.new(0, BRING_UP, 0)
        local cf   = CFrame.lookAt(pos, pos + look)
        pcall(function() vf:PivotTo(cf) end)

        task.wait(0.05)
        local seat = SV.findDriveSeat(vf)
        if seat then SV.sitIn(seat) end
    end

    local sec = tab:AddSection({ Name = "Vehicle (Bring)" })
    sec:AddButton({ Name = "Bring Vehicle (vor dich & einsteigen)", Callback = bringVehicle })
end
