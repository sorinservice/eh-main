-- tabs/functions/vehicle/vehicle/plates.lua
return function(SV, tab, OrionLib)
    local notify = SV.notify

    local function applyPlateToCurrent()
        local vf = SV.myVehicleFolder()
        if vf and SV.CFG and SV.CFG.plateText ~= "" then
            SV.applyPlateTextTo(vf, SV.CFG.plateText)
        end
    end

    -- UI
    local sec = tab:AddSection({ Name = "License Plate (local)" })
    sec:AddTextbox({
        Name = "Kennzeichen-Text",
        Default = (SV.CFG and SV.CFG.plateText) or "",
        TextDisappear = false,
        Callback = function(txt)
            if SV.CFG then
                SV.CFG.plateText = tostring(txt or "")
                SV.save_cfg()
            end
        end
    })
    sec:AddButton({ Name = "Kennzeichen anwenden", Callback = applyPlateToCurrent })

    -- Auto-apply bei neuen Fahrzeugen
    task.spawn(function()
        local vroot = SV.VehiclesFolder(); if not vroot then return end
        vroot.ChildAdded:Connect(function(ch)
            task.wait(0.7)
            if ch and (ch.Name==SV.LP.Name or (ch.GetAttribute and ch:GetAttribute("Owner")==SV.LP.Name))
               and SV.CFG and SV.CFG.plateText~="" then
                SV.applyPlateTextTo(ch, SV.CFG.plateText)
            end
        end)
    end)

    -- Nach Join automatisch setzen
    task.defer(function()
        if SV.CFG and SV.CFG.plateText~="" then
            task.wait(1.0)
            pcall(applyPlateToCurrent)
        end
    end)
end
