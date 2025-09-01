-- tabs/vehicle.lua
-- Vehicle Tab für SorinHub

return function(tab, OrionLib)
    local Players = game:GetService("Players")
    local Workspace = game:GetService("Workspace")
    local LocalPlayer = Players.LocalPlayer

    -- Config
    local MAX_DIST = 500 -- ab welcher Entfernung kommt Warnung

    -- Hilfsfunktionen
    local function getVehicle()
        local folder = Workspace:FindFirstChild("Vehicles")
        if not folder then return nil end
        return folder:FindFirstChild(LocalPlayer.Name)
    end

    local function getDriveSeat()
        local car = getVehicle()
        if not car then return nil end
        return car:FindFirstChildWhichIsA("VehicleSeat", true) or car:FindFirstChild("DriveSeat", true)
    end

    local function distanceToSeat(seat)
        if not seat or not LocalPlayer.Character then return math.huge end
        local hrp = LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not hrp then return math.huge end
        return (hrp.Position - seat.Position).Magnitude
    end

    -- Actions
    local function toVehicle()
        local seat = getDriveSeat()
        if not seat then
            OrionLib:MakeNotification({
                Name = "Vehicle",
                Content = "Kein Fahrzeug gefunden!",
                Time = 3
            })
            return
        end
        if distanceToSeat(seat) > MAX_DIST then
            OrionLib:MakeNotification({
                Name = "Vehicle",
                Content = "Dein Auto ist zu weit weg!",
                Time = 4
            })
            return
        end

        -- Teleport auf den Sitz
        local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if hrp then
            hrp.CFrame = seat.CFrame + Vector3.new(0, 2, 0)
        end
    end

    local function bringVehicle()
        local seat = getDriveSeat()
        if not seat then
            OrionLib:MakeNotification({
                Name = "Vehicle",
                Content = "Kein Fahrzeug gefunden!",
                Time = 3
            })
            return
        end

        local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not hrp then return end

        if distanceToSeat(seat) > MAX_DIST then
            OrionLib:MakeNotification({
                Name = "Vehicle",
                Content = "Dein Auto ist zu weit weg!",
                Time = 4
            })
            return
        end

        -- Setze Fahrzeug zum Spieler
        local car = getVehicle()
        if car and car.PrimaryPart then
            car:SetPrimaryPartCFrame(hrp.CFrame + Vector3.new(0, 0, -5))
            -- optional: dich gleich auf den Sitz setzen
            hrp.CFrame = seat.CFrame + Vector3.new(0, 2, 0)
        end
    end

    local function setPlateText(text)
        local car = getVehicle()
        if not car then return end
        for _, part in ipairs(car:GetDescendants()) do
            if part:IsA("SurfaceGui") and string.find(part.Name, "License") then
                local label = part:FindFirstChildWhichIsA("TextLabel", true)
                if label then
                    label.Text = text
                end
            end
        end
    end

    -- UI
    tab:AddButton({
        Name = "To Vehicle",
        Callback = toVehicle
    })

    tab:AddButton({
        Name = "Bring Vehicle",
        Callback = bringVehicle
    })

    tab:AddTextbox({
        Name = "Set License Plate",
        Default = "",
        TextDisappear = false,
        Callback = function(txt)
            setPlateText(txt)
            OrionLib:MakeNotification({
                Name = "Vehicle",
                Content = "Kennzeichen gesetzt: " .. txt,
                Time = 3
            })
        end
    })

    tab:AddParagraph("Info", "Dein Auto wird über Workspace.Vehicles[Username] erkannt.\nWenn es zu weit weg ist (> " .. MAX_DIST .. " studs), gibt es eine Warnung.")
end
