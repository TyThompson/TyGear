local addonName, addon = ...

-- Helper function to color and title-case class names
function TyGear_ColorClassName(class)
    local classColors = {
        ["DEATHKNIGHT"] = "|cffc41f3b",
        ["DRUID"] = "|cffff7d0a",
        ["HUNTER"] = "|cffaad372",
        ["MAGE"] = "|cff69ccf0",
        ["PALADIN"] = "|cfff58cba",
        ["PRIEST"] = "|cffffffff",
        ["ROGUE"] = "|cfffff569",
        ["SHAMAN"] = "|cff0070de",
        ["WARLOCK"] = "|cff9482c9",
        ["WARRIOR"] = "|cffc79c6e"
    }
    local classUpper = strupper(class or "")
    local color = classColors[classUpper] or "|cffffffff" -- Fallback to white
    -- Title-case the class name (e.g., "MAGE" -> "Mage")
    local classTitle = string.lower(class or "")
    if classTitle ~= "" then
        classTitle = string.upper(classTitle:sub(1, 1)) .. classTitle:sub(2)
    end
    return color .. classTitle .. "|r"
end

-- Function to print the current Pawn spec
function TyGear_PrintPawnSpec()
    if not PawnVersion then
        print("TyGear: Pawn not loaded, cannot print spec.")
        return
    end
    if not PawnCommon or not PawnCommon.Scales then
        print("TyGear: PawnCommon or PawnCommon.Scales not available.")
        return
    end
    -- Get the player's class
    local _, class = UnitClass("player")
    local specName = nil

    -- Try to find the active scale for the player's class
    for scaleName, scale in pairs(PawnCommon.Scales) do
        if scale.Class == class and scale.IsVisible then
            specName = scaleName
            break
        end
    end

    if specName then
        -- Clean up the scale name by removing the "Pawn" prefix or other identifiers
        specName = specName:gsub("^Pawn.*%:", "") -- Remove "Pawn:Class:" prefix
        print("TyGear: Current Pawn spec for " .. class .. ": " .. specName)
    else
        print("TyGear: No active Pawn spec found for " .. class .. ".")
    end
end

-- Initialize SavedVariables
function TyGear_InitializeDB()
    TyGearDB = TyGearDB or {}
    TyGearDB.enableBoERolling = TyGearDB.enableBoERolling or false
    TyGearDB.enableAutoSellJunk = TyGearDB.enableAutoSellJunk or false
    print("TyGear: Initialized DB - enableBoERolling: " .. tostring(TyGearDB.enableBoERolling) .. ", enableAutoSellJunk: " .. tostring(TyGearDB.enableAutoSellJunk))
end