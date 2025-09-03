-- tabs/vehicle/plates.lua
return function(SV, tab, OrionLib)
    local notify = SV.notify

    local function applyPlateToCurrent()
        local vf = SV.myVehicleFolder()
        if vf and SV.CFG.plateText ~= "" then
            SV.applyPlateTextTo(vf, SV.CFG.plateText)
            notify("Vehicle","Kennzeichen angewandt (lokal).",2)
        else
            notify("Vehicle","Kein Fahrzeug / leerer Text.",2)
        end
    end

    -- UI
    local sec = tab:AddSection({ Name = "License Plate (local)" })
    sec:AddTextbox({
        Name = "Kennzeichen-Text",
        Default = SV.CFG.plateText,
        TextDisappear = false,
        Callback = function(txt)
            SV.CFG.plateText = tostring(txt or "")
            SV.save_cfg()
        end
    })
    sec:AddButton({ Name = "Kennzeichen anwenden (aktuelles Fahrzeug)", Callback = applyPlateToCurrent })

    -- Auto-apply bei neuen Fahrzeugen
    task.spawn(function()
        local vroot = SV.VehiclesFolder(); if not vroot then return end
        vroot.ChildAdded:Connect(function(ch)
            task.wait(0.7)
            if ch and (ch.Name == SV.LP.Name or (ch.GetAttribute and ch:GetAttribute("Owner") == SV.LP.Name))
               and SV.CFG.plateText ~= "" then
                SV.applyPlateTextTo(ch, SV.CFG.plateText)
            end
        end)
    end)

    -- Nach Join automatisch setzen, wenn vorhanden
    task.defer(function()
        if SV.CFG.plateText ~= "" then
            task.wait(1.0)
            pcall(applyPlateToCurrent)
        end
    end)
end

