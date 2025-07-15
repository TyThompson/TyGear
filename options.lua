local addonName, addon = ...

-- Initialize SavedVariables
function TyGear_InitializeDB()
    TyGearDB = TyGearDB or {}
    TyGearDB.enableBoERolling = TyGearDB.enableBoERolling or false
    TyGearDB.enableAutoSellJunk = TyGearDB.enableAutoSellJunk or false
end

-- Create the options frame
local optionsFrame = CreateFrame("Frame", "TyGearOptionsFrame", InterfaceOptionsFramePanelContainer)
optionsFrame.name = "TyGear"
optionsFrame:SetScript("OnShow", function(self)
    -- Ensure the frame is only initialized once
    if not self.initialized then
        self.initialized = true
        
        -- Title
        local title = self:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 16, -16)
        title:SetText("TyGear Options")
        
        -- Checkbox for enabling BoE rolling
        local boeCheckbox = CreateFrame("CheckButton", "TyGearBoECheckbox", self, "InterfaceOptionsCheckButtonTemplate")
        boeCheckbox:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -20)
        _G[boeCheckbox:GetName() .. "Text"]:SetText("Enable rolling on Bind on Equip")
        
        -- Load saved variable or set default
        boeCheckbox:SetChecked(TyGearDB and TyGearDB.enableBoERolling)
        
        -- Save setting when checkbox is toggled
        boeCheckbox:SetScript("OnClick", function(self)
            TyGearDB = TyGearDB or {}
            TyGearDB.enableBoERolling = self:GetChecked()
        end)
        
        -- Checkbox for enabling auto-sell junk
        local junkCheckbox = CreateFrame("CheckButton", "TyGearJunkCheckbox", self, "InterfaceOptionsCheckButtonTemplate")
        junkCheckbox:SetPoint("TOPLEFT", boeCheckbox, "BOTTOMLEFT", 0, -10)
        _G[junkCheckbox:GetName() .. "Text"]:SetText("Enable auto-sell junk at vendors")
        
        -- Load saved variable or set default
        junkCheckbox:SetChecked(TyGearDB and TyGearDB.enableAutoSellJunk)
        
        -- Save setting when checkbox is toggled
        junkCheckbox:SetScript("OnClick", function(self)
            TyGearDB = TyGearDB or {}
            TyGearDB.enableAutoSellJunk = self:GetChecked()
        end)
    end
end)

-- Register the options panel
InterfaceOptions_AddCategory(optionsFrame)