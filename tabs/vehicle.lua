-- tabs/vehicle.lua
-- Vehicle Tab für SorinHub (Orion)

return function(tab, OrionLib)
  local Players  = game:GetService("Players")
  local Workspace = game:GetService("Workspace")
  local LP = Players.LocalPlayer

  -- einstellbar: Warnung ab dieser Distanz
  local MAX_DIST = 500

  local function getCarFolder()
    return Workspace:FindFirstChild("Vehicles")
  end

  local function getMyCar()
    local f = getCarFolder()
    return f and f:FindFirstChild(LP.Name) or nil
  end

  local function getDriveSeat()
    local car = getMyCar()
    if not car then return nil end
    -- erst explizit, dann generisch
    return car:FindFirstChild("DriveSeat", true) or car:FindFirstChildWhichIsA("VehicleSeat", true)
  end

  local function distToSeat(seat)
    local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    if not (hrp and seat) then return math.huge end
    return (hrp.Position - seat.Position).Magnitude
  end

  local function notify(msg, t)
    OrionLib:MakeNotification({ Name = "Vehicle", Content = tostring(msg), Time = t or 3 })
  end

  local function toVehicle()
    local seat = getDriveSeat()
    if not seat then return notify("Kein Fahrzeug gefunden.") end
    if distToSeat(seat) > MAX_DIST then return notify("Auto ist zu weit weg.") end

    local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    if hrp then
      hrp.CFrame = seat.CFrame + Vector3.new(0, 2, 0)
    end
  end

  local function bringVehicle()
    local seat = getDriveSeat()
    if not seat then return notify("Kein Fahrzeug gefunden.") end
    if distToSeat(seat) > MAX_DIST then return notify("Auto ist zu weit weg.") end

    local car = getMyCar()
    local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    if car and car.PrimaryPart and hrp then
      car:SetPrimaryPartCFrame(hrp.CFrame * CFrame.new(0, 0, -5))
      hrp.CFrame = seat.CFrame + Vector3.new(0, 2, 0)
    else
      notify("Konnte Fahrzeug nicht verschieben (PrimaryPart/HRP fehlt).")
    end
  end

  local function setPlateText(txt)
    local car = getMyCar()
    if not car then return notify("Kein Fahrzeug gefunden.") end

    local count = 0
    for _, gui in ipairs(car:GetDescendants()) do
      if gui:IsA("SurfaceGui") and string.find(gui.Name:lower(), "license") then
        local label = gui:FindFirstChildWhichIsA("TextLabel", true)
        if label then
          label.Text = txt
          count += 1
        end
      end
    end
    notify(("Kennzeichen aktualisiert (%d Flächen)."):format(count))
  end

  -- UI
  local sec = tab:AddSection({ Name = "Vehicle" })

  sec:AddButton({ Name = "To Vehicle (TP auf Sitz)", Callback = toVehicle })
  sec:AddButton({ Name = "Bring Vehicle (zum Spieler + einsteigen)", Callback = bringVehicle })

  sec:AddTextbox({
    Name = "License Plate Text (lokal)",
    Default = "",
    TextDisappear = false,
    Callback = function(v)
      setPlateText(v or "")
    end
  })

  sec:AddSlider({
    Name = "Warnung ab Distanz",
    Min = 100, Max = 2000, Increment = 50,
    Default = MAX_DIST,
    Callback = function(v) MAX_DIST = math.floor(v) end
  })
end
