-- Mapping für PlaceID: 7711635737
-- Du kannst nach Name (byName) ODER nach AssetId/Text-Id (byId) mappen.

-- Tipp:
--  - Tools haben oft tool.AssetId (Zahl). Falls nicht, setzt dein Game evtl. ein Attribut "AssetId".
--  - Wenn beides fehlt, kannst du zunächst byName nutzen (Tool-Instanzname im Explorer).
--  - defaultUnknown ist der Fallback-Text, wenn nichts passt.

return {
    -- Mapping nach ID (Strings, nicht Zahlen!)
    byId = {
        -- ["123456"] = "Iron Sword",
        -- ["987654321"] = "Healing Wand",
        -- ["1122334455"] = "Grapple Hook",
    },

    -- Mapping nach Namen (genauer Instanzname des Tools/Accessories)
    byName = {
        ["Phone"] = "Phone",
        ["Flashlight"]    = "Flashlight",
        ["Cones"]      = "Cones",
        ["GPS Tracker"] = "GPS-Tracker", 
        ["Barrier Tape"] = "Barrier Tape",
        ["Ladder"]    = "Ladder",
        --["Cones"]      = "Cones",
        --["GPS Tracker"] = "GPS-Tracker", 
    },

    -- Text, falls weder ID noch Name gefunden wird
    defaultUnknown = "Unknown Item",
}
