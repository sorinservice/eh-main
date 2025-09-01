-- tabs/vehicle.lua
-- Vehicle Mod für SorinHub

return function(tab, OrionLib)
  print("VehicleMod loaded. | Not safe to use, dev version 1.0\n" ..
        "Warn Distance: 300 Studs.")
  local Players    = game:GetService("Players")
  local RunService = game:GetService("RunService")
  local Workspace  = game:GetService("Workspace")
  local Http       = game:GetService("HttpService")

  local LP         = Players.LocalPlayer

  ----------------------------------------------------------------
  -- Einstellungen (CODE-ONLY)
  ----------------------------------------------------------------
  local MAX_WARN_DIST = 300      -- Distanz (Studs), ab der wir "zu weit" warnen
  local BRING_OFFSET  = CFrame.new(0, 0, -6) -- wohin das Auto vor dich gestellt wird
  local SIT_ATTEMPTS  = 6        -- wie oft wir versuchen, dich in den Sitz zu setzen
  local SIT_DELAY     = 0.08     -- Pause zwischen Versuchen (Sekunden)

  ----------------------------------------------------------------
  -- Persistenz (nur PlateText)
  ----------------------------------------------------------------
  local SAVE_FOLDER = OrionLib.Folder or "SorinConfig"
  local SAVE_FILE   = SAVE_FOLDER .. "/vehicle.json"

  local CFG = { PlateText = "" }

  local function read_cfg()
    local ok, data = pcall(function()
      if isfile and isfile(SAVE_FILE) then
        return Http:JSONDecode(readfile(SAVE_FILE))
      end
    end)
    if ok and type(data) == "table" and type(data.PlateText) == "string" then
      CFG.PlateText = data.PlateText
    end
  end

  local function write_cfg()
    pcall(function()
      if makefolder and not isfolder(SAVE_FOLDER) then makefolder(SAVE_FOLDER) end
      if writefile then writefile(SAVE_FILE, Http:JSONEncode(CFG)) end
    end)
  end

  read_cfg()

  ----------------------------------------------------------------
  -- Helpers
  ----------------------------------------------------------------
  local function notify(msg, t)
    OrionLib:MakeNotification({ Name = "Vehicle", Content = tostring(msg), Time = t or 3 })
  end

  local function vehiclesFolder()
    return Workspace:FindFirstChild("Vehicles")
  end

  local function myCar()
    local f = vehiclesFolder()
    if not f then return nil end
    return f:FindFirstChild(LP.Name)
  end

  local function ensurePrimaryPart(car)
    if not car then return end
    if car.PrimaryPart then return end
    -- priorisieren: DriveSeat > VehicleSeat > irgendein Part
    local seat = car:FindFirstChild("DriveSeat", true) or car:FindFirstChildWhichIsA("VehicleSeat", true)
    if seat then
      car.PrimaryPart = seat
      return
    end
    for _,p in ipairs(car:GetDescendants()) do
      if p:IsA("BasePart") then
        car.PrimaryPart = p
        return
      end
    end
  end

  local function driveSeat()
    local car = myCar()
    if not car then return nil end
    return car:FindFirstChild("DriveSeat", true) or car:FindFirstChildWhichIsA("VehicleSeat", true)
  end

  local function distToSeat(seat)
    local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    if not (hrp and seat) then return math.huge end
    return (hrp.Position - seat.Position).Magnitude
  end

  local function myHumanoid()
    local ch = LP.Character
    return ch and ch:FindFirstChildOfClass("Humanoid") or nil
  end

  local function sitInSeat(seat)
    -- Mehrfach versuchen: TP leicht über den Sitz und Sit triggern
    local hum = myHumanoid()
    local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    if not (hum and hrp and seat) then return false end

    for _ = 1, SIT_ATTEMPTS do
      -- positionieren (leicht oberhalb, minimal versetzt)
      hrp.CFrame = seat.CFrame * CFrame.new(0, 1.0, 0)
      task.wait(0.02)
      -- Sit auslösen
      pcall(function()
        hum.Sit = true
        if typeof(seat.Sit) == "function" then seat:Sit(hum) end
      end)
      task.wait(SIT_DELAY)
      -- hat's geklappt?
      if seat.Occupant == hum then
        return true
      end
    end
    return (seat.Occupant == hum)
  end

  ----------------------------------------------------------------
  -- Kennzeichen anwenden (exakte Pfade + Fallback Schreibweise)
  ----------------------------------------------------------------
  local function findPlateLabel(root, sideName) -- sideName = "Front" oder "Back"
    local body = root and root:FindFirstChild("Body")
    if not body then return nil end

    local lp = body:FindFirstChild("LicencePlates") or body:FindFirstChild("LicensePlates")
    if not lp then return nil end

    local side = lp:FindFirstChild(sideName)
    if not side then return nil end

    local gui = side:FindFirstChild("Gui")
    if not gui then return nil end

    return gui:FindFirstChildOfClass("TextLabel")
  end

  local function applyPlatesTo(car, text)
    if not (car and text) then return 0 end
    local n = 0
    for _, side in ipairs({ "Front", "Back" }) do
      local lbl = findPlateLabel(car, side)
      if lbl then
        pcall(function() lbl.Text = text end)
        n += 1
      end
    end
    return n
  end

  local function applyPlatesToMyCar()
    local car = myCar()
    if not car then return 0 end
    return applyPlatesTo(car, CFG.PlateText)
  end

  -- Auto-Apply auf neue Fahrzeuge (bei Respawn etc.)
  local vf = vehiclesFolder()
  if vf then
    vf.ChildAdded:Connect(function(child)
      if child.Name == LP.Name then
        -- kurz warten bis Struktur steht
        task.wait(0.25)
        if CFG.PlateText ~= "" then
          applyPlatesTo(child, CFG.PlateText)
        end
      end
    end)
  end

  ----------------------------------------------------------------
  -- Aktionen
  ----------------------------------------------------------------
  local function action_toVehicle()
    local seat = driveSeat()
    if not seat then return notify("Kein Fahrzeug/DriveSeat gefunden.") end

    if distToSeat(seat) > MAX_WARN_DIST then
      notify(("Auto ist zu weit weg (> %d studs)."):format(MAX_WARN_DIST))
      return
    end

    if sitInSeat(seat) then
      notify("Eingestiegen.")
    else
      notify("Konnte nicht einsteigen (Anti-TP/Anti-Seat?).")
    end
  end

  local function action_bringVehicle()
    local car  = myCar()
    local seat = driveSeat()
    if not (car and seat) then return notify("Kein Fahrzeug/DriveSeat gefunden.") end

    if distToSeat(seat) > MAX_WARN_DIST then
      notify(("Auto ist zu weit weg (> %d studs)."):format(MAX_WARN_DIST))
      return
    end

    ensurePrimaryPart(car)

    local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    if not (car.PrimaryPart and hrp) then
      return notify("Konnte Fahrzeug nicht versetzen (PrimaryPart/HRP fehlt).")
    end

    -- Fahrzeug kurz vor dich setzen
    pcall(function()
      car:SetPrimaryPartCFrame(hrp.CFrame * BRING_OFFSET)
    end)

    -- und einsteigen
    if sitInSeat(seat) then
      notify("Fahrzeug gebracht & eingestiegen.")
    else
      notify("Fahrzeug gebracht, aber nicht eingestiegen.")
    end
  end

  local function action_setPlate(text)
    text = tostring(text or ""):sub(1, 20)
    CFG.PlateText = text
    write_cfg()

    local count = applyPlatesToMyCar()
    if count > 0 then
      notify(("Kennzeichen gesetzt (%d Flächen)."):format(count))
    else
      notify("Kennzeichen gespeichert. Wird auf neue Fahrzeuge angewendet.")
    end
  end

  ----------------------------------------------------------------
  -- UI
  ----------------------------------------------------------------
  local sec = tab:AddSection({ Name = "Vehicle" })
  sec:AddButton({ Name = "To Vehicle (auf Sitz & einsteigen)", Callback = action_toVehicle })
  sec:AddButton({ Name = "Bring Vehicle (vor dich & einsteigen)", Callback = action_bringVehicle })

  local sec2 = tab:AddSection({ Name = "License Plate (lokal)" })
  sec2:AddTextbox({
    Name = "Kennzeichen-Text",
    Default = CFG.PlateText or "",
    TextDisappear = false,
    Callback = action_setPlate
  })

  sec2:AddButton({
    Name = "Kennzeichen auf aktuelles Fahrzeug anwenden",
    Callback = function()
      local n = applyPlatesToMyCar()
      notify(n > 0 and ("Angewendet (%d)."):format(n) or "Kein aktives Fahrzeug gefunden.")
    end
  })
end
