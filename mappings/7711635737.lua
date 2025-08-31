-- Mapping für PlaceID: 7711635737
-- Du kannst nach Name (byName) ODER nach AssetId/Text-Id (byId) mappen.

-- Tipp:
--  - Tools haben oft tool.AssetId (Zahl). Falls nicht, setzt dein Game evtl. ein Attribut "AssetId".
--  - Wenn beides fehlt, kannst du zunächst byName nutzen (Tool-Instanzname im Explorer).
--  - defaultUnknown ist der Fallback-Text, wenn nichts passt.

return {
    -- Mapping nach Name (Strings, nicht Zahlen!)
    byName = {
        -- Normal Items
        ["Phone"]         = "Phone",
        ["Flashlight"]    = "Flashlight",
        ["Cones"]         = "Cones",
        ["GPS-Tracker"]   = "GPS-Tracker", 
        ["Barrier Tape"]  = "Barrier Tape",
        ["Ladder"]        = "Ladder",

        -- Police Items
        ["Handcuffs"]     = "Handcuffs",
        ["Baton"]         = "Baton",
        ["Police Trowel"] = "Police Trowel",
        ["Taser"]         = "Taser",
        ["Radar Gun"]     = "Radar Gun",
        ["Stop Stick"]    = "Stop Stick",
        ["Police Tape"]   = "Police Tape",

        -- Job Items
        ["Warning Beacons"] = "Warning Beacons",
        
        -- Weapons
        ["Glock 17"]      = "Glock 17",
        ["Flashbang"]     = "Flashbang",
        ["MP5"]           = "Weapon MP5",
        ["G36"]           = "Weapon G36",

        -- Medical/Firefighter Items
        ["Infusion"]     = "Infusion",
        ["Bandage"]       = "Bandage",
        ["Blood Transfusion"] = "Blood Transfusion",
        ["Fire Tape"] = "Fire Tape",
        ["Circular Saw"] = "Circular Saw",
        ["Sandbag"] = "Sandbag",
        ["Fire Hose"] = "Fire Hose",
        

        -- Food & Drinks
        ["Water Bottle"] = "Water Bottle",
        ["Energy Drink"] = "Energy Drink",
        ["Cookie"] = "Cookie",
    },

    -- Text, falls weder ID noch Name gefunden wird
    defaultUnknown = "Unknown Item",
}
