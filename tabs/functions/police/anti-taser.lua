-- tabs/functions/police/antitaser.lua
return function(SV, tab, OrionLib)
    -- anti-taser v1.0.0 (Orion: Toggle only; English UI)

    local Players = game:GetService("Players")
    local LP      = Players.LocalPlayer

    local state = {
        enabled   = false,
        attrConn  = nil,
        charConn  = nil,
    }

    local function attach(char)
        if state.attrConn then state.attrConn:Disconnect(); state.attrConn = nil end
        if not char then return end

        -- Ensure attribute exists and is cleared once on attach
        pcall(function()
            if char:GetAttribute("Tased") == nil then
                char:SetAttribute("Tased", false)
            end
        end)

        state.attrConn = char:GetAttributeChangedSignal("Tased"):Connect(function()
            if state.enabled and char:GetAttribute("Tased") then
                pcall(function() char:SetAttribute("Tased", false) end)
            end
        end)
    end

    local function setEnabled(on)
        state.enabled = on

        if on then
            local char = LP.Character or LP.CharacterAdded:Wait()
            attach(char)
            pcall(function() char:SetAttribute("Tased", false) end)

            if not state.charConn then
                state.charConn = LP.CharacterAdded:Connect(function(newChar)
                    attach(newChar)
                    pcall(function() newChar:SetAttribute("Tased", false) end)
                end)
            end

            if OrionLib and OrionLib.MakeNotification then
                OrionLib:MakeNotification({Name="Anti Taser", Content="Enabled", Time=1})
            end
        else
            if OrionLib and OrionLib.MakeNotification then
                OrionLib:MakeNotification({Name="Anti Taser", Content="Disabled", Time=1})
            end
        end
    end

    -- UI (English)
    local sec = tab:AddSection({ Name = "Anti Taser" })
    sec:AddToggle({
        Name = "Enable Anti Taser",
        Default = false,
        Callback = function(v) setEnabled(v) end
    })

    print("[police/antitaser v1.0.0] loaded")
end
