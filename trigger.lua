local addonName, addon = ...

-- Event frame for core addon events
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("BAG_UPDATE")

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        print("TyGear: Addon loaded")
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "BAG_UPDATE" then
        if CheckForNewEquip then
            CheckForNewEquip() -- Defined in find.lua
        else
            print("TyGear: Error - CheckForNewEquip not found")
        end
    end
end)

SLASH_TYGEAR1 = "/tygear"

SlashCmdList["TYGEAR"] = function(msg)
    if msg == "help" then
        print("TyGear Commands:")
        print("/tygear scan - Scan your bags for upgrades.")
        if PawnVersion then
            print("Pawn version: " .. tostring(PawnVersion))
            if TyGear_PrintPawnSpec then
                TyGear_PrintPawnSpec()
            else
                print("TyGear: Error - TyGear_PrintPawnSpec not found")
            end
        else
            print("TyGear: Pawn not loaded.")
        end
        print("TyGear tested with Pawn version 1.3 on 3.3.5 Client")
    elseif msg == "scan" then
        if ManualBagScan then
            ManualBagScan() -- Defined in find.lua
        else
            print("TyGear: Error - ManualBagScan not found")
        end
    end
end