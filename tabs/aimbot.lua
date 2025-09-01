return function(tab, OrionLib)
    print("[SorinHub] Aimbot tab initialized")

    local aimbotSettings = {
        Enabled    = false,
        Keybind    = Enum.KeyCode.Q,
        Prediction = true,
        AimPart    = "Head",
        IgnoreTeam = true,

        FOVVisible = true,
        FOVRadius  = 100,
        FOVColor   = Color3.fromRGB(255, 0, 0),

        MaxDistance= 1000,
        Smoothness = 0.25,
    }

    -- Section: Toggles
    local main = tab:AddSection({ Name = "Main" })
    main:AddToggle({ Name="Mobile Aimbot", Default=false, Callback=function(v) print("Mobile Aimbot:",v) end })
    main:AddToggle({ Name="Aimbot", Default=aimbotSettings.Enabled, Callback=function(v) aimbotSettings.Enabled=v end })
    main:AddBind({
        Name="Aimbot Keybind",
        Default=aimbotSettings.Keybind,
        Hold=false,
        Callback=function() print("Keybind pressed") end
    })
    main:AddToggle({ Name="Hit Prediction", Default=aimbotSettings.Prediction, Callback=function(v) aimbotSettings.Prediction=v end })
    main:AddDropdown({
        Name="Aim Part",
        Options={"Head","HumanoidRootPart","UpperTorso","LowerTorso"},
        Default=aimbotSettings.AimPart,
        Callback=function(v) aimbotSettings.AimPart=v end
    })
    main:AddToggle({ Name="Ignore Team", Default=aimbotSettings.IgnoreTeam, Callback=function(v) aimbotSettings.IgnoreTeam=v end })

    -- Section: Distance & Smoothness
    local dist = tab:AddSection({ Name = "Distance / Smoothness" })
    dist:AddSlider({ Name="Max Distance", Min=100, Max=5000, Default=aimbotSettings.MaxDistance, Increment=50, ValueName="Studs", Callback=function(v) aimbotSettings.MaxDistance=v end })
    dist:AddSlider({ Name="Aimbot Smoothness", Min=0.1, Max=1, Default=aimbotSettings.Smoothness, Increment=0.05, Callback=function(v) aimbotSettings.Smoothness=v end })

    -- Section: FOV
    local fov = tab:AddSection({ Name = "FOV" })
    fov:AddColorpicker({ Name="FOV Color", Default=aimbotSettings.FOVColor, Callback=function(v) aimbotSettings.FOVColor=v end })
    fov:AddSlider({ Name="FOV Size", Min=10, Max=300, Default=aimbotSettings.FOVRadius, Increment=5, Callback=function(v) aimbotSettings.FOVRadius=v end })

    -- optional status labels
    local status = tab:AddSection({ Name = "Status" })
    status:AddLabel("Status: Inactive")
end
