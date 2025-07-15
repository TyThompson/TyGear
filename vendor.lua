-- Helper function to format copper into gold/silver/copper with colors
local function FormatMoney(copper)
    local gold = floor(copper / 10000)
    copper = copper - gold * 10000
    local silver = floor(copper / 100)
    copper = copper - silver * 100
    local result = ""
    if gold > 0 then
        result = result .. "|cffffd700" .. gold .. "g|r "
    end
    if silver > 0 or gold > 0 then
        result = result .. "|cffffffff" .. silver .. "s|r "
    end
    result = result .. "|cffcd7f32" .. copper .. "c|r"
    return result
end

-- Auto-sell junk items when vendor window is opened
function AutoSellJunk()
    -- print("TyGear: AutoSellJunk function called")
    if not TyGearDB then
        print("TyGear: Error - TyGearDB not initialized")
        return
    end
    if not TyGearDB.enableAutoSellJunk then
        print("TyGear: Auto-sell junk disabled")
        return
    end
    if not MerchantFrame or not MerchantFrame:IsVisible() then
        print("TyGear: Vendor window not open, skipping auto-sell")
        return
    end
    print("TyGear: Scanning for junk items...")
    local totalSold = 0
    local totalProfit = 0
    for bag = 0, 4 do
        local slots = GetContainerNumSlots(bag)
        -- print("TyGear: Checking bag " .. bag .. " with " .. slots .. " slots")
        for slot = 1, slots do
            local itemID = GetContainerItemID(bag, slot)
            if itemID then
                local name, itemLink, itemQuality, _, _, _, _, _, _, _, sellPrice = GetItemInfo(itemID)
                local _, itemCount, isLocked = GetContainerItemInfo(bag, slot)
                if name then
                    -- print("TyGear: Found item: " .. name .. " (Quality: " .. itemQuality .. ", Locked: " .. tostring(isLocked) .. ", SellPrice: " .. (sellPrice or 0) .. ", ItemLink: " .. (itemLink or "nil") .. ", Count: " .. (itemCount or 1) .. ")")
                    if itemQuality == 0 and sellPrice and sellPrice > 0 and not isLocked then
                        print("TyGear: Selling junk item: " .. name .. " (" .. FormatMoney(sellPrice * (itemCount or 1)) .. ")")
                        UseContainerItem(bag, slot)
                        totalSold = totalSold + (itemCount or 1)
                        totalProfit = totalProfit + (sellPrice * (itemCount or 1))
                    end
                else
                    print("TyGear: Failed to get item info for itemID " .. itemID .. " in bag " .. bag .. ", slot " .. slot)
                end
            else
                -- print("TyGear: No item in bag " .. bag .. ", slot " .. slot)
            end
        end
    end
    if totalSold > 0 then
        print("TyGear: Sold " .. totalSold .. " junk item(s) for " .. FormatMoney(totalProfit) .. ".")
    else
        print("TyGear: No sellable junk items found.")
    end
end

-- Register MERCHANT_SHOW event in vendor.lua
local vendorFrame = CreateFrame("Frame")
vendorFrame:RegisterEvent("MERCHANT_SHOW")
vendorFrame:SetScript("OnEvent", function(self, event)
    if event == "MERCHANT_SHOW" then
        -- print("TyGear: MERCHANT_SHOW event triggered (vendor.lua)")
        AutoSellJunk()
    end
end)