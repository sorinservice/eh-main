-- tabs/vehicle/jump.lua
return function(SV, tab, OrionLib)
    local notify = SV.notify
    local J = { power = 220 } -- Skaliert mit Masse

    local function doJump()
        local vf = SV.myVehicleFolder(); if not vf then notify("Jump","Kein Fahrzeug."); return end
        if not SV.ensurePrimaryPart(vf) or not vf.PrimaryPart then notify("Jump","Kein PrimaryPart."); return end
        local pp   = vf.PrimaryPart
        local mass = math.max(pp.AssemblyMass, 1)
        pp:ApplyImpulse(Vector3.new(0, J.power * mass, 0))
        notify("Jump", "Hop!", 1.2)
    end

    local sec = tab:AddSection({ Name = "Vehicle Jump" })
    sec:AddButton({ Name = "Vehicle Jump", Callback = doJump })
    sec:AddSlider({
        Name = "Jump-Power",
        Min=80, Max=600, Increment=10, Default=J.power,
        Callback = function(v) J.power = math.floor(v) end
    })
end
