-- tabs/vehicle/to_vehicle.lua
return function(SV, tab, OrionLib)
    local notify = SV.notify
    local WARN_DISTANCE = 300
    local TO_OFFSET     = CFrame.new(-2.0, 0.5, 0)

    local function toVehicle()
        if SV.isSeated() then notify("Vehicle","Du sitzt bereits im Fahrzeug."); return end
        local vf = SV.myVehicleFolder(); if not vf then notify("Vehicle","Kein eigenes Fahrzeug gefunden."); return end
        local seat = SV.findDriveSeat(vf); if not seat then notify("Vehicle","Kein Fahrersitz gefunden."); return end

        local hrp = (SV.LP.Character or SV.LP.CharacterAdded:Wait()):WaitForChild("HumanoidRootPart")
        local dist = (hrp.Position - seat.Position).Magnitude
        if dist > WARN_DISTANCE then
            notify("Vehicle", ("Achtung: weit entfernt (~%d studs)."):format(math.floor(dist)), 3)
        end

        hrp.CFrame = seat.CFrame * TO_OFFSET
        task.wait(0.06)
        SV.sitIn(seat)
    end

    local sec = tab:AddSection({ Name = "Vehicle (TP)" })
    sec:AddButton({ Name = "To Vehicle (auf Sitz & einsteigen)", Callback = toVehicle })
end
