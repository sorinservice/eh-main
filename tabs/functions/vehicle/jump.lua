-- tabs/vehicle/jump.lua
return function(SV, tab, OrionLib)
    local notify = SV.notify
    local TUNE = {
        POWER_UP  = 90,  -- fester vertikaler Impuls
        POWER_FWD = 35,  -- leichter Vorwärts-Impuls
    }

    local function doJump()
        local vf = SV.myVehicleFolder()
        if not vf then notify("Jump","Kein Fahrzeug."); return end
        if not SV.ensurePrimaryPart(vf) or not vf.PrimaryPart then notify("Jump","Kein PrimaryPart."); return end

        local pp   = vf.PrimaryPart
        local mass = math.max(pp.AssemblyMass, 1)

        -- Vorwärtsrichtung (nur XZ-Ebene), falls 0 → Standard nach vorne
        local fwd = Vector3.new(pp.CFrame.LookVector.X, 0, pp.CFrame.LookVector.Z)
        if fwd.Magnitude < 1e-3 then
            fwd = Vector3.new(0,0,-1)
        else
            fwd = fwd.Unit
        end

        -- Impuls = Richtung * (Power * Masse)
        local impulse = (fwd * (TUNE.POWER_FWD * mass)) + Vector3.new(0, TUNE.POWER_UP * mass, 0)
        pp:ApplyImpulse(impulse)
    end

    tab:AddButton({ Name = "Vehicle Jump", Callback = doJump })
end
