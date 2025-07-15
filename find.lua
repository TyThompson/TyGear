function ManualBagScan()
    print("TyGear: Scanning for upgrades...")
end

local trackedItems = {}

function CheckForNewEquip()
    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) do
            local itemLink = GetContainerItemLink(bag, slot)
            if itemLink and not trackedItems[itemLink] then
                local _, _, _, _, _, itemType = GetItemInfo(itemLink)
                if itemType == "Armor" or itemType == "Weapon" then
                    trackedItems[itemLink] = true
                    print("|cff00ff00New gear added:|r " .. itemLink)
                end
            end
        end
    end
end