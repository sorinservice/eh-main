-- tabs/vehicle/boost.lua
return function(SV, tab, OrionLib)
    local WS = SV.Services.Workspace
    local notify = SV.notify

    local boost = { force = 320 } -- Skaliert mit Masse

    local function doBoost()
        local vf = SV.myVehicleFolder(); if not vf then notify("Boost","Kein Fahrzeug."); return end
        if not SV.ensurePrimaryPart(vf) or not vf.PrimaryPart then notify("Boost","Kein PrimaryPart."); return end
        local pp   = vf.PrimaryPart
        local mass = math.max(pp.AssemblyMass, 1)
        local dir  = (SV.isSeated() and pp.CFrame.LookVector) or SV.Camera.CFrame.LookVector
        pp:ApplyImpulse(dir.Unit * (boost.force * mass))
        notify("Boost", "Schub!", 1.5)
    end

    local sec = tab:AddSection({ Name = "Vehicle Actions" })
    sec:AddButton({ Name = "Vehicle Boost", Callback = doBoost })
    sec:AddSlider({
        Name = "Boost-Stärke",
        Min=100, Max=800, Increment=10, Default=boost.force,
        Callback = function(v) boost.force = math.floor(v) end
    })
end
