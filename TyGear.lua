-- TyGear
-- Fork of AutoGear by Synthetikaryote and BujuArena.
-- Original: https://github.com/BujuArena/AutoGear
-- License: Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International
-- https://creativecommons.org/licenses/by-nc-sa/4.0/
-- This copy is modified so the addon, saved variables, and slash commands
-- use the TyGear name. The original authors retain credit for the work.

-- to do:
-- implement classic direct % crit and direct % hit
-- Don't roll on loot I already have in my bag
-- Greeded in something within 5 levels that was an upgrade.  Specifically, Gauntlets of Divinity versus equipped Algae Fists.

-- accomodate for "no item link received"
-- other non-gear it should let you roll
-- add rolling on offset
-- factor in racial weapon bonuses
-- eye of arachnida slot nil error

---@type TyGearAddon
local _, T = ...

---Current TOC version
---you should know how this versions works to compare.
---Example WoW Version to TOC Version:
--- - v1.2.0 -> 10200
--- - v3.4.3 -> 30403
--- - v9.7.2 -> 90702
--- - v10.0.1 -> 100001
---
---Start numbers for every expansion:
--- - Vanilla: 10000
--- - TBC: 20000
--- - WotLK: 30000
--- - Cata: 40000
--- - MoP: 50000
--- - WoD: 60000
--- - Legion: 70000
--- - BfA: 80000
--- - SL: 90000
--- - DF: 100000
--- - TWW: 110000
--- - Midnight: 120000
local TOC_VERSION_CURRENT = select(4, GetBuildInfo())
local TOC_VERSION_TBC = 20000
local TOC_VERSION_WOTLK = 30000
local TOC_VERSION_CATA = 40000
local TOC_VERSION_MOP = 50000
local TOC_VERSION_WOD = 60000
local TOC_VERSION_LEGION = 70000
local TOC_VERSION_BFA = 80000
local TOC_VERSION_SL = 90000
local TOC_VERSION_DF = 100000
local TOC_VERSION_TWW = 110000
local TOC_VERSION_MIDNIGHT = 120000

---WoW Forever runs the modern (Mainline) UI engine and API but reports a 1.x interface number (16001),
---so TOC_VERSION_CURRENT alone must not be used to decide which API family is present.
---The TOC range is a fallback in case the project constant is renamed before launch.
local IS_WOW_FOREVER = (WOW_PROJECT_CAMELOT ~= nil and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT)
	or (type(TOC_VERSION_CURRENT) == "number" and TOC_VERSION_CURRENT >= 16000 and TOC_VERSION_CURRENT < TOC_VERSION_TBC)

local _ --prevent taint when using throwaway variable
local next = next -- bind next locally for speed
--local lastlink
TyGearActionQueue = {}
local queueQueueRebuild
local weapons
local tUpdate = 0
local TyGearMainLoopActive
local TyGearCachedPawnScaleName
local TyGearCachedPawnScaleLocalizedName
local TyGearPawnScaleCacheKey
local TyGearScoreCache = {}
local TyGearCachedClassLocalized
local TyGearCachedClass
local TyGearCachedSpec
local TyGearCachedClassID
local TyGearClassSpecCacheKey
local TyGearValidGearSlotsCache = {}
local TyGearSetSlotsCache = {}
local TyGearWeaponSlotCacheKey
local TyGearWeightingCacheKey
local TyGearColorizeClassNamesCache
local TyGearLootPatterns
local EMPTY_SLOT_INFO = { name = "nothing", empty = 1 }

local function TyGearWipeTable(t)
	if not t then return {} end
	for k in pairs(t) do
		t[k] = nil
	end
	return t
end

function TyGearInvalidatePerformanceCaches()
	TyGearCachedPawnScaleName = nil
	TyGearCachedPawnScaleLocalizedName = nil
	TyGearPawnScaleCacheKey = nil
	TyGearWipeTable(TyGearScoreCache)
	TyGearClassSpecCacheKey = nil
	TyGearCachedClassLocalized = nil
	TyGearCachedClass = nil
	TyGearCachedSpec = nil
	TyGearCachedClassID = nil
	TyGearWipeTable(TyGearValidGearSlotsCache)
	TyGearWipeTable(TyGearSetSlotsCache)
	TyGearWeaponSlotCacheKey = nil
	TyGearWeightingCacheKey = nil
end

function TyGearEnsureMainLoop()
	if not TyGearMainLoopActive and TyGearFrame then
		TyGearFrame:SetScript("OnUpdate", TyGearMain)
		TyGearMainLoopActive = true
	end
end

function TyGearStopMainLoopIfIdle()
	if TyGearMainLoopActive and (#TyGearActionQueue == 0) and TyGearFrame then
		TyGearFrame:SetScript("OnUpdate", nil)
		TyGearMainLoopActive = nil
	end
end

function TyGearQueueAction(action)
	table.insert(TyGearActionQueue, action)
	TyGearEnsureMainLoop()
end

function TyGearGetLootPatterns()
	if TyGearLootPatterns then return TyGearLootPatterns end
	TyGearLootPatterns = {
		LOOT_ITEM_SELF_MULTIPLE:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)"):gsub("^", "^"),
		LOOT_ITEM_PUSHED_SELF_MULTIPLE:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)"):gsub("^", "^"),
		LOOT_ITEM_CREATED_SELF_MULTIPLE:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)"):gsub("^", "^"),
		LOOT_ITEM_SELF:gsub("%%s", "(.+)"):gsub("^", "^"),
		LOOT_ITEM_PUSHED_SELF:gsub("%%s", "(.+)"):gsub("^", "^"),
		LOOT_ITEM_CREATED_SELF:gsub("%%s", "(.+)"):gsub("^", "^"),
	}
	return TyGearLootPatterns
end
local shouldPrintHelp = false
local maxPlayerLevel = (GetMaxPlayerLevel and GetMaxPlayerLevel())
	or (GetMaxLevelForExpansionLevel and GetExpansionLevel and GetMaxLevelForExpansionLevel(GetExpansionLevel()))
	or 60
local L = T.Localization
--Key Bindings UI labels (Bindings.xml); assign keys under Key Bindings → TyGear
_G["BINDING_HEADER_TYGEAR"] = "TyGear"
_G["BINDING_NAME_TYGEAR_TOGGLE_NEED"] = L["Toggle hovered item on need list"]
_G["BINDING_NAME_TYGEAR_TOGGLE_IGNORE"] = L["Toggle hovered item on ignore list"]
local ContainerIDToInventoryID = ContainerIDToInventoryID or (C_Container and C_Container.ContainerIDToInventoryID)
local GetContainerNumFreeSlots = GetContainerNumFreeSlots or (C_Container and C_Container.GetContainerNumFreeSlots)
local GetContainerNumSlots = GetContainerNumSlots or (C_Container and C_Container.GetContainerNumSlots)
local GetContainerItemID = GetContainerItemID or (C_Container and C_Container.GetContainerItemID)
local GetDetailedItemLevelInfo = (C_Item and C_Item.GetDetailedItemLevelInfo) or GetDetailedItemLevelInfo
local GetItemCount = (C_Item and function(info, includeBank, includeUses, includeReagentBank, includeAccountBank)
	if info then
		return C_Item.GetItemCount(info, includeBank or false, includeUses or false, includeReagentBank or true, includeAccountBank or true)
	end
end) or GetItemCount
local GetItemInfo = GetItemInfo or (C_Item and C_Item.GetItemInfo)
local GetItemInfoInstant = GetItemInfoInstant or (C_Item and C_Item.GetItemInfoInstant)
local GetItemInventorySlotInfo = GetItemInventorySlotInfo or (C_Item and C_Item.GetItemInventorySlotInfo)
local GetItemSpell = GetItemSpell or (C_Item and C_Item.GetItemSpell)
local GetMouseFocus = GetMouseFocus or (GetMouseFoci and (function()
	local frames = GetMouseFoci()
	return frames and frames[1];
end))
local GetNumTalentTabs = GetNumTalentTabs or GetNumSpecializations
local GetSpecialization = GetSpecialization or (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization)
local GetSpecializationInfo = GetSpecializationInfo or (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo)
local InterfaceOptions_AddCategory = InterfaceOptions_AddCategory or function(frame, addOn, position)
	frame.OnCommit = frame.okay
	frame.OnDefault = frame.default
	frame.OnRefresh = frame.refresh

	if frame.parent then
		local category = Settings.GetCategory(frame.parent)
		local subcategory, layout = Settings.RegisterCanvasLayoutSubcategory(category, frame, frame.name)
		return subcategory, category
	else
		local category, layout = Settings.RegisterCanvasLayoutCategory(frame, frame.name, frame.name)
		Settings.RegisterAddOnCategory(category)
		return category
	end
end
local InterfaceOptionsFrame_OpenToCategory = InterfaceOptionsFrame_OpenToCategory or Settings.OpenToCategory
local IsPlayerSpell = C_SpellBook and C_SpellBook.IsSpellKnown or IsPlayerSpell
local PickupContainerItem = PickupContainerItem or (C_Container and C_Container.PickupContainerItem)
local UseContainerItem = UseContainerItem or (C_Container and C_Container.UseContainerItem)
ITEM_UNIQUE_EQUIPPABLE_SANITIZED_PATTERN = select(1,string.gsub(ITEM_UNIQUE_EQUIPPABLE,"%-","%%-"))
TyGearWouldRoll = "nil"
TyGearSomeItemDataIsMissing = nil
TyGearFirstEquippableBagSlot = ContainerIDToInventoryID(1) or 20
TyGearLastEquippableBagSlot = ContainerIDToInventoryID(math.min(NUM_BAG_SLOTS or 4, 4)) or (TyGearFirstEquippableBagSlot + 3)
-- Dedicated reagent bags (INVTYPE_REAGENTBAG / subclass 11) only fit the reagent bag slot.
-- Profession and soul bags (subclass 1..10) may fill that slot or a normal bag slot.
-- PutItemInBag needs the reagent bag button's id: GetInventorySlotInfo("ReagentBag0Slot"),
-- CONTAINER_BAG_OFFSET+5, 24 when the offset is still 19, or 35 after bag slots moved to 31-35.
-- A classic ContainerIDToInventoryID(5) is a bank bag and must not be passed to PutItemInBag.
local function TyGearInventorySlotIsBankBag(slot)
	if not slot then return false end
	local bankOffset = BANK_CONTAINER_INVENTORY_OFFSET
	local bankCount = (NUM_BANKBAGSLOTS or 7) + 2
	if type(bankOffset) == "number" and bankOffset >= 40 and slot >= bankOffset and slot < bankOffset + bankCount then
		return true
	end
	return slot >= 63 and slot <= 98
end

local function TyGearInventorySlotIsGear(slot)
	return type(slot) == "number"
		and INVSLOT_FIRST_EQUIPPED
		and INVSLOT_LAST_EQUIPPED
		and slot >= INVSLOT_FIRST_EQUIPPED
		and slot <= INVSLOT_LAST_EQUIPPED
end

local function TyGearSlotIsOneOfFourNormalBags(slot)
	local first = TyGearFirstEquippableBagSlot
	return type(slot) == "number" and type(first) == "number" and slot >= first and slot <= first + 3
end

-- Character bag inventory ids. Classic uses 20-23. Current clients use 31-34. The reagent slot is the one after those.
local function TyGearSlotIsKnownNormalBag(slot)
	if TyGearSlotIsOneOfFourNormalBags(slot) then return true end
	return type(slot) == "number" and ((slot >= 20 and slot <= 23) or (slot >= 31 and slot <= 34))
end

TyGearReagentBagContainer = nil
TyGearReagentBagSlot = nil
TyGearReagentBagButtonID = nil
TyGearReagentBagSlotOverride = nil
TyGearEquippableBagSlots = {}

local function TyGearButtonPutID(button)
	if not button or not button.GetID then return nil end
	local id = button:GetID()
	if type(id) ~= "number" or id <= 0 then return nil end
	if issecretvalue and issecretvalue(id) then return nil end
	return id
end

local function TyGearFrameName(frame)
	local name = frame and frame.GetName and frame:GetName()
	if type(name) ~= "string" or name == "" then return nil end
	if issecretvalue and issecretvalue(name) then return nil end
	return name
end

local function TyGearButtonBagID(button)
	if not button or not button.GetBagID then return nil end
	local bagID = button:GetBagID()
	if type(bagID) ~= "number" or bagID <= 0 then return nil end
	if issecretvalue and issecretvalue(bagID) then return nil end
	return bagID
end

-- Lower is better. The bag bar button is what a click passes to PutItemInBag.
local function TyGearReagentButtonRank(button)
	if not button or not button.GetID then return nil end
	local name = TyGearFrameName(button) or ""
	if string.find(name, "CharacterReagentBag", 1, true) then return 1 end
	if string.find(name, "ReagentBag", 1, true) then return 2 end
	if button.commandName == "TOGGLEREAGENTBAG1" then return 3 end
	if string.find(name, "Reagent", 1, true) then return 4 end
	if TyGearButtonBagID(button) == 5 then return 5 end
end

local function TyGearConsiderReagentButton(button, bestRank, bestButton, bestID, bestBag)
	local rank = TyGearReagentButtonRank(button)
	if not rank then return bestRank, bestButton, bestID, bestBag end
	local id = TyGearButtonPutID(button)
	if not id then return bestRank, bestButton, bestID, bestBag end
	local bagID = TyGearButtonBagID(button)
	local better = (not bestRank) or rank < bestRank
	if (not better) and rank == bestRank and TyGearSlotIsOneOfFourNormalBags(bestID) and not TyGearSlotIsOneOfFourNormalBags(id) then
		better = true
	end
	if better then
		return rank, button, id, bagID
	end
	return bestRank, bestButton, bestID, bestBag
end

-- The id Blizzard passes to PutItemInBag when the reagent bag button is clicked.
local function TyGearFindReagentBagButton()
	local bestRank, bestButton, bestID, bestBag
	local function consider(button)
		bestRank, bestButton, bestID, bestBag = TyGearConsiderReagentButton(button, bestRank, bestButton, bestID, bestBag)
	end
	local names = {
		"CharacterReagentBag0Slot",
		"CharacterReagentBagSlot",
		"ReagentBag0Slot",
		"MainMenuBarReagentBagButton",
	}
	for _, name in ipairs(names) do
		consider(_G[name])
	end
	if bestButton and bestRank <= 2 then
		return bestButton, bestID, bestBag
	end
	local roots = {
		_G.BagsBar,
		_G.MainMenuBarBagButtons,
		_G.MainMenuBarArtFrame,
		_G.CharacterBag0Slot and _G.CharacterBag0Slot.GetParent and _G.CharacterBag0Slot:GetParent(),
		_G.MainMenuBarBackpackButton and _G.MainMenuBarBackpackButton.GetParent and _G.MainMenuBarBackpackButton:GetParent(),
	}
	local function walk(frame, depth)
		if not frame or depth > 5 or not frame.GetChildren then return end
		local children = { frame:GetChildren() }
		for _, child in ipairs(children) do
			consider(child)
			walk(child, depth + 1)
		end
	end
	local seen = {}
	for _, root in ipairs(roots) do
		if root and not seen[root] then
			seen[root] = true
			consider(root)
			walk(root, 1)
		end
	end
	if not bestButton and EnumerateFrames then
		local frame = EnumerateFrames()
		local n = 0
		while frame and n < 5000 do
			n = n + 1
			consider(frame)
			if bestRank and bestRank <= 2 then break end
			frame = EnumerateFrames(frame)
		end
	end
	if bestButton then
		return bestButton, bestID, bestBag
	end
end

local function TyGearInventorySlotInfoID(slotName)
	if type(slotName) ~= "string" then return nil end
	local getters = {}
	if C_PaperDollInfo and C_PaperDollInfo.GetInventorySlotInfo then
		table.insert(getters, C_PaperDollInfo.GetInventorySlotInfo)
	end
	if GetInventorySlotInfo then
		table.insert(getters, GetInventorySlotInfo)
	end
	for _, getter in ipairs(getters) do
		local ok, id = pcall(getter, slotName)
		if ok and type(id) == "number" and id > 0 and not (issecretvalue and issecretvalue(id)) then
			return id
		end
	end
end

-- The global may be nil at file load. Look it up again once the container API exists.
local function TyGearContainerToInventoryID(container)
	local fn = ContainerIDToInventoryID
	if (not fn) and C_Container and C_Container.ContainerIDToInventoryID then
		fn = C_Container.ContainerIDToInventoryID
	end
	if not fn or not container then return nil end
	local ok, slot = pcall(fn, container)
	if ok and type(slot) == "number" and slot > 0 and not (issecretvalue and issecretvalue(slot)) then
		return slot
	end
end

local function TyGearRefreshNormalBagSlotRange()
	local normalBags = math.min(NUM_BAG_SLOTS or 4, 4)
	local first = TyGearContainerToInventoryID(1)
	local last = TyGearContainerToInventoryID(normalBags)
	if not first or not last then return false end
	if TyGearInventorySlotIsBankBag(first) or TyGearInventorySlotIsBankBag(last) then return false end
	if TyGearInventorySlotIsGear(first) or last < first then return false end
	local changed = first ~= TyGearFirstEquippableBagSlot or last ~= TyGearLastEquippableBagSlot
	TyGearFirstEquippableBagSlot = first
	TyGearLastEquippableBagSlot = last
	return changed
end

local function TyGearRebuildEquippableBagSlots()
	TyGearEquippableBagSlots = {}
	local normalBags = math.min(NUM_BAG_SLOTS or 4, 4)
	for i = 1, normalBags do
		if i ~= TyGearReagentBagContainer then
			local invSlot = TyGearFirstEquippableBagSlot + i - 1
			if invSlot ~= TyGearReagentBagSlot and not TyGearInventorySlotIsGear(invSlot) then
				table.insert(TyGearEquippableBagSlots, invSlot)
			end
		end
	end
	TyGearLastManagedGearSlot = (TyGearReagentBagSlot and math.max(TyGearLastEquippableBagSlot, TyGearReagentBagSlot)) or TyGearLastEquippableBagSlot
end

-- Ids worth giving to PutItemInBag, best first. The button id is what a click on the reagent slot uses.
-- Classic offset 19 makes that id 24. After bag slots moved, it is 35. Try each one that is not a normal or bank bag.
local function TyGearCollectReagentBagSlotCandidates()
	local list = {}
	local seen = {}
	local function add(id, trustButton)
		if type(id) ~= "number" or id <= 0 or seen[id] then return end
		if issecretvalue and issecretvalue(id) then return end
		if TyGearInventorySlotIsGear(id) then return end
		if not trustButton then
			if TyGearInventorySlotIsBankBag(id) then return end
			if TyGearSlotIsKnownNormalBag(id) then return end
		end
		seen[id] = true
		table.insert(list, id)
	end
	-- Confirmed in game on WoW Forever: PutItemInBag(35) equips the cursor item into the reagent bag slot.
	add(35, true)
	if TyGearReagentBagSlotOverride and not (IS_WOW_FOREVER and TyGearReagentBagSlotOverride ~= 35) then
		add(TyGearReagentBagSlotOverride, true)
	end
	if TyGearReagentBagButtonID then
		add(TyGearReagentBagButtonID, true)
	end
	add(TyGearInventorySlotInfoID("ReagentBag0Slot"), false)
	add(TyGearInventorySlotInfoID("REAGENTBAG0SLOT"), false)
	local container = TyGearReagentBagContainer or 5
	local offset = (type(CONTAINER_BAG_OFFSET) == "number" and CONTAINER_BAG_OFFSET) or 19
	add(offset + container, false)
	add(19 + container, false)
	add(30 + container, false)
	if container == 5 then
		add(35, false)
	end
	add(TyGearContainerToInventoryID(container), false)
	return list
end

function TyGearReagentBagSlotCandidates()
	return TyGearCollectReagentBagSlotCandidates()
end

-- Bag buttons and ContainerIDToInventoryID can be missing while this file loads. Resolve again at login and before each scan.
function TyGearRefreshReagentBagSlot()
	local hasReagentSlot = IS_WOW_FOREVER
		or (type(TOC_VERSION_CURRENT) == "number" and TOC_VERSION_CURRENT >= TOC_VERSION_DF)
		or (NUM_REAGENTBAG_SLOTS and NUM_REAGENTBAG_SLOTS > 0)
	if not hasReagentSlot then
		TyGearReagentBagContainer = nil
		TyGearReagentBagSlot = nil
		TyGearRebuildEquippableBagSlots()
		return
	end
	local rangeChanged = TyGearRefreshNormalBagSlotRange()
	local button, buttonID, buttonBag = TyGearFindReagentBagButton()
	TyGearReagentBagButton = button
	local previousButton = TyGearReagentBagButtonID
	local previousContainer = TyGearReagentBagContainer
	local previousSlot = TyGearReagentBagSlot
	TyGearReagentBagButtonID = buttonID
	-- Forever's reagent bag is container 5. An Enum.BagIndex.ReagentBag that points at a bank bag is not it.
	local container = 5
	if type(buttonBag) == "number" and buttonBag >= 1 and buttonBag <= 6 then
		container = buttonBag
	elseif (not IS_WOW_FOREVER) and Enum and Enum.BagIndex and type(Enum.BagIndex.ReagentBag) == "number" then
		container = Enum.BagIndex.ReagentBag
	end
	TyGearReagentBagContainer = container
	local candidates = TyGearCollectReagentBagSlotCandidates()
	local slot
	for _, id in ipairs(candidates) do
		if not TyGearSlotIsKnownNormalBag(id) then
			slot = id
			break
		end
	end
	slot = slot or candidates[1]
	-- Forever's reagent bag button takes PutItemInBag(35). Use that id for reads and equips.
	if IS_WOW_FOREVER then
		slot = 35
	end
	local slotChanged = slot ~= previousSlot or container ~= previousContainer or buttonID ~= previousButton or rangeChanged
	if not slotChanged and TyGearEquippableBagSlots[1] then
		return
	end
	TyGearReagentBagSlot = slot
	TyGearRebuildEquippableBagSlots()
	if slotChanged then
		TyGearWipeTable(TyGearValidGearSlotsCache)
		TyGearWipeTable(TyGearSetSlotsCache)
	end
end

function TyGearAdoptReagentBagSlot(id)
	if type(id) ~= "number" or id <= 0 then return end
	if TyGearSlotIsKnownNormalBag(id) then return end
	if id == TyGearReagentBagSlot and id == TyGearReagentBagSlotOverride then return end
	TyGearReagentBagSlotOverride = id
	TyGearRefreshReagentBagSlot()
end

TyGearRefreshReagentBagSlot()

-- Container (class 1) subclasses from GetItemInfoInstant / Enum.ItemContainerSubclass.
local REAGENT_BAG_SUBCLASS_ID = 11 -- Enum.ItemContainerSubclass.ReagentBag
local SOUL_BAG_SUBCLASS_ID = 1 -- Soul Bag (Warlock soul shards)
local FIRST_PROFESSION_BAG_SUBCLASS_ID = 1 -- Soul .. Cooking / Tackle (1..10)
local LAST_PROFESSION_BAG_SUBCLASS_ID = 10

function TyGearIsSoulBag(info)
	if not info then return nil end
	if info.isSoulBag then return 1 end
	if info.classID == Enum.ItemClass.Container and info.subclassID == SOUL_BAG_SUBCLASS_ID then
		return 1
	end
end

-- Dedicated reagent bags: INVTYPE_REAGENTBAG and/or container subclass 11.
function TyGearIsDedicatedReagentBag(classID, subclassID, equipLoc)
	if classID ~= (Enum and Enum.ItemClass and Enum.ItemClass.Container) then return nil end
	if equipLoc == "INVTYPE_REAGENTBAG" then return 1 end
	if subclassID == REAGENT_BAG_SUBCLASS_ID then return 1 end
	local reagentSubclass = Enum and Enum.ItemContainerSubclass and (Enum.ItemContainerSubclass.ReagentBag or Enum.ItemContainerSubclass.Reagent)
	if reagentSubclass and subclassID == reagentSubclass then return 1 end
end

-- Profession and soul bags Forever allows in the reagent slot (subclass 1..10).
function TyGearIsProfessionOrSoulBag(classID, subclassID)
	if classID ~= (Enum and Enum.ItemClass and Enum.ItemClass.Container) then return nil end
	if subclassID and subclassID >= FIRST_PROFESSION_BAG_SUBCLASS_ID and subclassID <= LAST_PROFESSION_BAG_SUBCLASS_ID then
		return 1
	end
end

function TyGearIsReagentBag(info)
	if not info then return nil end
	if info.isReagentBag then return 1 end
	return TyGearIsDedicatedReagentBag(info.classID, info.subclassID, info.equipLoc)
end

-- Profession/soul bags that may fill an empty reagent slot. Dedicated reagent bags use TyGearIsReagentBag.
function TyGearUsesReagentBagSlot(info)
	if not TyGearReagentBagSlot or not info or TyGearIsReagentBag(info) then return nil end
	if IS_WOW_FOREVER and TyGearIsProfessionOrSoulBag(info.classID, info.subclassID) then
		return 1
	end
end

-- Reagent slot first, then the normal bag slots. The first empty slot wins a tie, so the reagent slot is preferred.
function TyGearReagentAndNormalBagSlots()
	if not TyGearReagentBagSlot then
		return TyGearEquippableBagSlots
	end
	local slots = { TyGearReagentBagSlot }
	for _, slot in ipairs(TyGearEquippableBagSlots) do
		if slot ~= TyGearReagentBagSlot then
			table.insert(slots, slot)
		end
	end
	return slots
end

function TyGearBagSlotsForItem(info)
	-- INVTYPE_REAGENTBAG is restricted to the reagent slot.
	if TyGearIsReagentBag(info) then
		return TyGearReagentBagSlot and { TyGearReagentBagSlot } or nil
	end
	-- Profession/soul bags fill an empty reagent slot; they are not scored as general bags.
	if TyGearUsesReagentBagSlot(info) then
		return TyGearReagentBagSlot and { TyGearReagentBagSlot } or nil
	end
	return TyGearEquippableBagSlots
end

function TyGearIsManagedGearSlot(slot)
	if not slot then return nil end
	if slot >= INVSLOT_FIRST_EQUIPPED and slot <= INVSLOT_LAST_EQUIPPED then
		return 1
	end
	if slot >= TyGearFirstEquippableBagSlot and slot <= TyGearLastEquippableBagSlot then
		return 1
	end
	if TyGearReagentBagSlot and slot == TyGearReagentBagSlot then
		return 1
	end
end

--equipment slots offered in Locked gear slots; tabard is the virtual 2H slot, shirts are not scored, and bags are not lockable there
function TyGearIsLockableGearSlot(slot)
	if not slot then return nil end
	if slot == INVSLOT_TABARD or slot == INVSLOT_BODY then return nil end
	if slot >= INVSLOT_FIRST_EQUIPPED and slot <= INVSLOT_LAST_EQUIPPED then
		return 1
	end
end

-- bag index (container id) for an equipped bag inventory slot, or nil for non-bags
function TyGearGetContainerForEquippedBagSlot(invSlot)
	if TyGearReagentBagSlot and invSlot == TyGearReagentBagSlot then
		return TyGearReagentBagContainer
	end
	if invSlot and invSlot >= TyGearFirstEquippableBagSlot and invSlot <= TyGearLastEquippableBagSlot then
		return invSlot - TyGearFirstEquippableBagSlot + 1
	end
end

-- backpack through the normal bags, plus the reagent bag when it is the next container
function TyGearGetLastBagToScan()
	local lastBag = NUM_BAG_SLOTS or 0
	if TyGearReagentBagContainer == lastBag + 1 then
		return TyGearReagentBagContainer
	end
	return lastBag
end

function TyGearGetReagentBagSlotName()
	if GetItemSubClassInfo and Enum and Enum.ItemClass and Enum.ItemClass.Container then
		local ok, name = pcall(GetItemSubClassInfo, Enum.ItemClass.Container, REAGENT_BAG_SUBCLASS_ID)
		if ok and type(name) == "string" and name ~= "" then
			return name
		end
	end
	return "Reagent Bag"
end

function TyGearAssignReagentBagSlots(info)
	if not info or not TyGearIsReagentBag(info) then return end
	info.isReagentBag = 1
	info.isGear = 1
	if info.invType == 0 and Enum and Enum.InventoryType and Enum.InventoryType.IndexBagType then
		info.invType = Enum.InventoryType.IndexBagType
	end
	TyGearRefreshReagentBagSlot()
	info.validGearSlots = TyGearBagSlotsForItem(info)
	info.numValidGearSlots = 0
	if info.validGearSlots then
		for _ in pairs(info.validGearSlots) do
			info.numValidGearSlots = info.numValidGearSlots + 1
		end
	end
	if info.numValidGearSlots == 0 then
		info.validGearSlots = nil
		info.usable = nil
		return
	end
	-- Keep-list bags may still fill an empty reagent slot; only true ignores stay unusable.
	if not info.ignored and not TyGearIsItemIgnored(info) then
		local reason = info.reason
		local tooltipBlocked = type(reason) == "string" and (
			string.find(reason, "invalid item", 1, true)
			or string.find(reason, "restricted", 1, true)
			or string.find(reason, "not yet available", 1, true)
		)
		if (not info.unusable) or (not reason) or tooltipBlocked then
			info.unusable = nil
			info.usable = 1
			if tooltipBlocked then
				info.reason = nil
			end
		end
	end
end

--initialize gear slot names table
TyGearSlotNames = {}
--PaperDollItemsFrame may not exist yet when this file loads (e.g. on WoW Forever)
for _,v in pairs(PaperDollItemsFrame and {PaperDollItemsFrame:GetChildren()} or {}) do
	if v.GetID and v.GetName then
		local slotID = v:GetID()
		if slotID >= INVSLOT_FIRST_EQUIPPED and slotID <= INVSLOT_LAST_EQUIPPED then
			TyGearSlotNames[slotID] = _G[strupper(strsub(v:GetName(), 10))]
		end
	end
end

function TyGearSerializeTable(val, name, skipnewlines, depth)
	skipnewlines = skipnewlines or false
	depth = depth or 0

	local tmp = string.rep(" ", depth)

	if name then tmp = tmp .. name .. " = " end

	if type(val) == "table" then
		tmp = tmp .. "{" .. (not skipnewlines and "\n" or "")

		for k, v in pairs(val) do
			tmp =  tmp .. TyGearSerializeTable(v, k, skipnewlines, depth + 1) .. "," .. (not skipnewlines and "\n" or "")
		end

		tmp = tmp .. string.rep(" ", depth) .. "}"
	elseif type(val) == "number" then
		tmp = tmp .. tostring(val)
	elseif type(val) == "string" then
		tmp = tmp .. string.format("%q", val)
	elseif type(val) == "boolean" then
		tmp = tmp .. (val and "true" or "false")
	else
		tmp = tmp .. "\"[inserializeable datatype:" .. type(val) .. "]\""
	end

	return tmp
end

function TyGearStringHash(text)
	local counter = 1
	local len = string.len(text)
	for i = 1, len, 3 do
		counter = math.fmod(counter*8161, 4294967279) +  -- 2^32 - 17: Prime!
		(string.byte(text,i)*16776193) +
		((string.byte(text,i+1) or (len-i+256))*8372226) +
		((string.byte(text,i+2) or (len-i+256))*3932164)
	end
	return math.fmod(counter, 4294967291) -- 2^32 - 5: Prime (and different from the prime in the loop)
end

--names of verbosity levels
local verbosityNames = {
	[0] = "errors",
	"info",
	"details",
	"debug",
}
-- set default value if key unknown
setmetatable(verbosityNames, {__index = function () return "funky" end})

function TyGearGetAllowedVerbosityName(allowedverbosity)
	return verbosityNames[allowedverbosity]
end

function TyGearGetAllowedVerbosityLabel(allowedverbosity)
	local name = verbosityNames[allowedverbosity]
	if name == "funky" then
		return tostring(allowedverbosity)
	end
	return L[string.format("%d: %s", allowedverbosity, name)]
end

function TyGearGetAllowedVerbosityOptions()
	local options = {}
	for level = 0, 3 do
		table.insert(options, {
			["label"] = TyGearGetAllowedVerbosityLabel(level),
			["value"] = level,
		})
	end
	return options
end

local QUALITY_COLOR_HEX = {
	[0] = "9d9d9d", -- poor
	[1] = "ffffff", -- common
	[2] = "1eff00", -- uncommon
	[3] = "0070dd", -- rare
	[4] = "a335ee", -- epic
	[5] = "ff8000", -- legendary
	[6] = "e6cc80", -- artifact
	[7] = "00ccff", -- heirloom
}

local ENGLISH_CLASS_NAMES = {
	WARRIOR = "Warrior",
	PALADIN = "Paladin",
	HUNTER = "Hunter",
	ROGUE = "Rogue",
	PRIEST = "Priest",
	DEATHKNIGHT = "Death Knight",
	SHAMAN = "Shaman",
	MAGE = "Mage",
	WARLOCK = "Warlock",
	MONK = "Monk",
	DRUID = "Druid",
	DEMONHUNTER = "Demon Hunter",
	EVOKER = "Evoker",
}

--longer rarity words first so "greens" is not split into a colored "green"
local QUALITY_WORDS = {
	{ quality = 2, words = { "greens", "green", "grüne", "gruene", "grün", "gruen" } },
	{ quality = 3, words = { "blues", "blue", "blaue", "blau" } },
	{ quality = 4, words = { "epics", "epic", "epische", "episch" } },
	{ quality = 0, words = { "greys", "grey", "gray", "graue", "grau" } },
	{ quality = 1, words = { "whites", "white", "weiße", "weisse", "weiß", "weiss" } },
	{ gold = true, words = { "golds", "gold" } },
}

local function colorMarkup(color, fallbackHex)
	if color then
		if color.GenerateHexColorMarkup then
			return color:GenerateHexColorMarkup()
		end
		if type(color.colorStr) == "string" then
			local hex = color.colorStr
			if hex:sub(1, 2) == "|c" then return hex end
			if #hex == 6 then hex = "ff"..hex end
			return "|c"..hex
		end
		if color.r ~= nil and color.g ~= nil and color.b ~= nil then
			return string.format("|cff%02x%02x%02x", math.floor(color.r * 255 + 0.5), math.floor(color.g * 255 + 0.5), math.floor(color.b * 255 + 0.5))
		end
	end
	if fallbackHex then
		return "|cff"..fallbackHex
	end
end

local function qualityMarkup(quality)
	local entry = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
	local color = entry and (entry.color or entry) or nil
	if entry and entry.hex then return entry.hex end
	return colorMarkup(color, QUALITY_COLOR_HEX[quality] or "ffffff")
end

local function asciiLetterAt(text, index)
	if index < 1 or index > #text then return false end
	local byte = text:byte(index)
	return (byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122)
end

local function insideColorCode(text, position)
	local last = nil
	local i = 1
	while i < position do
		local colorStart = text:find("|c", i, true)
		local colorEnd = text:find("|r", i, true)
		if colorStart and colorStart < position and (not colorEnd or colorStart < colorEnd) then
			last = "c"
			i = colorStart + 2
		elseif colorEnd and colorEnd < position then
			last = "r"
			i = colorEnd + 2
		else
			break
		end
	end
	return last == "c"
end

local function colorizeWord(text, word, markup)
	if not text or text == "" or not word or word == "" then return text end
	local lowerText = text:lower()
	local lowerWord = word:lower()
	local parts = {}
	local i = 1
	while i <= #text do
		local startAt, endAt = lowerText:find(lowerWord, i, true)
		if not startAt then
			parts[#parts + 1] = text:sub(i)
			break
		end
		if not asciiLetterAt(text, startAt - 1) and not asciiLetterAt(text, endAt + 1) and not insideColorCode(text, startAt) then
			parts[#parts + 1] = text:sub(i, startAt - 1)
			parts[#parts + 1] = markup
			parts[#parts + 1] = text:sub(startAt, endAt)
			parts[#parts + 1] = "|r"
			i = endAt + 1
		else
			parts[#parts + 1] = text:sub(i, endAt)
			i = endAt + 1
		end
	end
	return table.concat(parts)
end

---Colors class names and item-quality words the way the WoW UI does.
function TyGearColorize(text)
	if type(text) ~= "string" or text == "" then return text end
	local classNames = TyGearColorizeClassNamesCache
	if not classNames then
		classNames = {}
		for token, english in pairs(ENGLISH_CLASS_NAMES) do
			classNames[#classNames + 1] = { token = token, name = english }
			local localized = TyGearClassList and TyGearClassList[token]
			if localized and localized ~= english then
				classNames[#classNames + 1] = { token = token, name = localized }
			end
		end
		table.sort(classNames, function(a, b) return #a.name > #b.name end)
		TyGearColorizeClassNamesCache = classNames
	end
	for _, entry in ipairs(classNames) do
		local markup = colorMarkup(RAID_CLASS_COLORS and RAID_CLASS_COLORS[entry.token], nil)
		if markup then
			text = colorizeWord(text, entry.name, markup)
		end
	end
	for _, group in ipairs(QUALITY_WORDS) do
		local markup = group.gold and "|cffffd100" or qualityMarkup(group.quality)
		for _, word in ipairs(group.words) do
			text = colorizeWord(text, word, markup)
		end
	end
	return text
end

--printing function to check allowed verbosity level
function TyGearPrint(text, verbosity)
	if verbosity == nil then verbosity = 0 end
	if TyGearDB.AllowedVerbosity ~= nil and verbosity > TyGearDB.AllowedVerbosity then
		return
	end
	print(TyGearColorize(text))
end

--Map ping, by file id. Forever plays this id, and it is not the level-up, quest, or loot cue.
local TyGearUpgradeChimeFile = 567416
local TyGearUpgradeChimeFileName = "MapPing"

function TyGearGetUpgradeChimeFileName()
	return TyGearUpgradeChimeFileName
end

--Pleasant confirmation chime when TyGear finishes equipping an upgrade (e.g. after winning a party loot roll).
function TyGearPlayUpgradeEquippedChime(force)
	if not force and TyGearDB and TyGearDB.PlayUpgradeChime == false then return end
	if PlaySoundFile then
		pcall(PlaySoundFile, TyGearUpgradeChimeFile, "Master")
	end
end

--initialize table for storing saved variables
--TyGearDB is shared by every character. Specialization override is stored separately
--in TyGearCharDB so an alt does not inherit the main's spec.
if (not TyGearDB) then TyGearDB = {} end
if (not TyGearCharDB) then TyGearCharDB = {} end

function TyGearSettingsTable(optionName)
	if optionName == "Override" or optionName == "OverrideSpec" then
		return TyGearCharDB
	end
	return TyGearDB
end

function TyGearInitializeCharacterSettings()
	if not TyGearCharDB then TyGearCharDB = {} end
	if TyGearCharDB.Override == nil then
		TyGearCharDB.Override = false
	end
	if TyGearCharDB.OverrideSpec == nil or TyGearCharDB.OverrideSpec == "" then
		TyGearCharDB.OverrideSpec = TyGearGetDefaultOverrideSpec()
	end
	--drop any copy that older builds saved in the shared table
	TyGearDB["Override"] = nil
	TyGearDB["OverrideSpec"] = nil
	if not TyGearCharDB.IgnoredGearSlots then
		TyGearCharDB.IgnoredGearSlots = TyGearGetDefaultIgnoredGearSlots()
	end
	if not TyGearCharDB.IgnoredItemIDs then TyGearCharDB.IgnoredItemIDs = {} end
	--older builds could opt unmeasurable Forever gear back into evaluation; that toggle is gone
	TyGearCharDB.UnmeasurableGearDisabled = nil
	if not TyGearCharDB.DiscoveredUnmeasurableGear then TyGearCharDB.DiscoveredUnmeasurableGear = {} end
end

--initialize item info cache for quicker repeat lookups
-- TyGearItemInfoCache = {}

--fill class lists for lookups later
local playerIsFemale = (C_PlayerInfo.GetSex(PlayerLocation:CreateFromUnit("player")) == 1)
if _G.FillLocalizedClassList then
	TyGearClassList = {}
	FillLocalizedClassList(TyGearClassList, playerIsFemale)
else
	TyGearClassList = LocalizedClassList(playerIsFemale)
end
if not TyGearClassList["DEATHKNIGHT"] then TyGearClassList["DEATHKNIGHT"] = "Death Knight" end
if not TyGearClassList["DEMONHUNTER"] then TyGearClassList["DEMONHUNTER"] = "Demon Hunter" end
if not TyGearClassList["EVOKER"] then TyGearClassList["EVOKER"] = "Evoker" end
if not TyGearClassList["MONK"] then TyGearClassList["MONK"] = "Monk" end
TyGearReverseClassList = {}
for k, v in pairs(TyGearClassList) do
	TyGearReverseClassList[v] = k
end

TyGearClassIDList = {
	[1] = {
		fileName="WARRIOR",
		localizedName=TyGearClassList["WARRIOR"]
	},
	[2] = {
		fileName="PALADIN",
		localizedName=TyGearClassList["PALADIN"]
	},
	[3] = {
		fileName="HUNTER",
		localizedName=TyGearClassList["HUNTER"]
	},
	[4] = {
		fileName="ROGUE",
		localizedName=TyGearClassList["ROGUE"]
	},
	[5] = {
		fileName="PRIEST",
		localizedName=TyGearClassList["PRIEST"]
	},
	[6] = {
		fileName="DEATHKNIGHT",
		localizedName=TyGearClassList["DEATHKNIGHT"]
	},
	[7] = {
		fileName="SHAMAN",
		localizedName=TyGearClassList["SHAMAN"]
	},
	[8] = {
		fileName="MAGE",
		localizedName=TyGearClassList["MAGE"]
	},
	[9] = {
		fileName="WARLOCK",
		localizedName=TyGearClassList["WARLOCK"]
	},
	[10] = {
		fileName="MONK",
		localizedName=TyGearClassList["MONK"]
	},
	[11] = {
		fileName="DRUID",
		localizedName=TyGearClassList["DRUID"]
	},
	[12] = {
		fileName="DEMONHUNTER",
		localizedName=TyGearClassList["DEMONHUNTER"]
	},
	[13] = {
		fileName="EVOKER",
		localizedName=TyGearClassList["EVOKER"]
	}
}
TyGearReverseClassIDList = {}
for k, v in pairs(TyGearClassIDList) do
	TyGearReverseClassIDList[v.fileName] = {}
	TyGearReverseClassIDList[v.fileName].id = k
	TyGearReverseClassIDList[v.fileName].localizedName = v.localizedName
end

--initialize missing saved variables with default values; call only after PLAYER_ENTERING_WORLD
function TyGearInitializeDB(defaults, reset)
	if TyGearDB == nil or reset ~= nil then TyGearDB = {} end
	for k,v in pairs(defaults) do
		if _G["TyGearDB"][k] == nil then
			_G["TyGearDB"][k] = v
		end
	end
end

-- Talent tab info. WotLK-style returns id, name, description, icon, pointsSpent.
-- Vanilla returns name, icon, pointsSpent. Use the global, not GetNumSpecializations.
local function TyGearReadTalentTab(index)
	if not _G.GetTalentTabInfo then return nil end
	local ok, a, b, c, _, e = pcall(_G.GetTalentTabInfo, index)
	if not ok then return nil end
	if type(b) == "string" and type(e) == "number" then
		return b, e
	end
	if type(a) == "string" and type(c) == "number" then
		return a, c
	end
end

-- Classic talent tabs, left to right. WoW Forever draws these as trait tabs, in this order.
local TyGearForeverTalentTabOrder = {
	DRUID = { "Balance", "Feral Combat", "Restoration" },
	HUNTER = { "Beast Mastery", "Marksmanship", "Survival" },
	MAGE = { "Arcane", "Fire", "Frost" },
	PALADIN = { "Holy", "Protection", "Retribution" },
	PRIEST = { "Discipline", "Holy", "Shadow" },
	ROGUE = { "Assassination", "Combat", "Subtlety" },
	SHAMAN = { "Elemental", "Enhancement", "Restoration" },
	WARLOCK = { "Affliction", "Demonology", "Destruction" },
	WARRIOR = { "Arms", "Fury", "Protection" },
}

local function TyGearPlainNumber(value)
	if type(issecretvalue) == "function" and issecretvalue(value) then
		return nil
	end
	return tonumber(value)
end

local function TyGearTraitNodePoints(info)
	if type(info) ~= "table" then return 0 end
	local purchased = TyGearPlainNumber(info.ranksPurchased)
	if purchased and purchased > 0 then
		return purchased
	end
	if type(info.activeEntry) == "table" then
		local rank = TyGearPlainNumber(info.activeEntry.rank)
		if rank and rank > 0 then
			return rank
		end
	end
	return 0
end

local function TyGearSpecNamedInText(className, text)
	if type(text) ~= "string" or text == "" or not className or not TyGearGetWeightSpecNames then
		return nil
	end
	local lower = string.lower(text)
	local best
	for specName in pairs(TyGearGetWeightSpecNames(className)) do
		if specName ~= "None" and string.find(lower, string.lower(specName), 1, true) then
			if not best or #specName > #best then
				best = specName
			end
		end
	end
	return best
end

local function TyGearClusterTraitNodes(nodes)
	local items = {}
	for _, info in ipairs(nodes) do
		local x = TyGearPlainNumber(info.posX)
		if x then
			table.insert(items, { x = x, points = TyGearTraitNodePoints(info), info = info })
		end
	end
	table.sort(items, function(a, b) return a.x < b.x end)
	if #items == 0 then return {} end
	local unique = {}
	local seen
	for _, item in ipairs(items) do
		local key = math.floor(item.x + 0.5)
		if key ~= seen then
			table.insert(unique, key)
			seen = key
		end
	end
	local gaps = {}
	for i = 1, #unique - 1 do
		table.insert(gaps, { index = i, gap = unique[i + 1] - unique[i] })
	end
	table.sort(gaps, function(a, b) return a.gap > b.gap end)
	local splitAfter = {}
	if #unique >= 6 and #gaps >= 2 then
		local small = {}
		for i = 3, #gaps do
			table.insert(small, gaps[i].gap)
		end
		table.sort(small)
		local median = small[math.ceil(#small / 2)] or 0
		local threshold = median * 1.5
		for n = 1, 2 do
			if gaps[n].gap > threshold then
				splitAfter[gaps[n].index] = true
			end
		end
	end
	local clusters = {}
	local current
	local uniqueIndex = 0
	seen = nil
	for _, item in ipairs(items) do
		local key = math.floor(item.x + 0.5)
		if key ~= seen then
			if seen ~= nil then
				uniqueIndex = uniqueIndex + 1
				if splitAfter[uniqueIndex] then
					current = nil
				end
			end
			seen = key
		end
		if not current then
			current = { minX = item.x, points = 0, nodes = {} }
			table.insert(clusters, current)
		end
		current.points = current.points + item.points
		table.insert(current.nodes, item.info)
	end
	return clusters
end

local function TyGearTraitTabName(className, cluster, index, tabOrder)
	if cluster.subTreeName and cluster.subTreeName ~= "" then
		return cluster.subTreeName
	end
	local traits = C_Traits
	if traits and traits.GetConditionInfo and cluster.configID then
		for _, info in ipairs(cluster.nodes) do
			if type(info.conditionIDs) == "table" then
				for _, condID in ipairs(info.conditionIDs) do
					local ok, cond = pcall(traits.GetConditionInfo, cluster.configID, condID)
					if ok and type(cond) == "table" then
						local named = TyGearSpecNamedInText(className, cond.tooltipFormat)
						if named then return named end
					end
				end
			end
		end
	end
	return tabOrder and tabOrder[index] or nil
end

-- WoW Forever spends talent points on trait nodes, grouped into the three classic tabs.
function TyGearHighestTraitTalentTabName()
	local classTalents = C_ClassTalents
	local traits = C_Traits
	if not (classTalents and classTalents.GetActiveConfigID and traits and traits.GetConfigInfo and traits.GetTreeNodes and traits.GetNodeInfo) then
		return nil
	end
	local configID = classTalents.GetActiveConfigID()
	if not configID then return nil end
	local ok, config = pcall(traits.GetConfigInfo, configID)
	if not ok or type(config) ~= "table" or type(config.treeIDs) ~= "table" then
		return nil
	end
	local className = UnitClassBase and UnitClassBase("player")
	local tabOrder = className and TyGearForeverTalentTabOrder[className]
	local tabs = {}
	for _, treeID in ipairs(config.treeIDs) do
		local nodesOK, nodeIDs = pcall(traits.GetTreeNodes, treeID)
		if not nodesOK or type(nodeIDs) ~= "table" then
			nodesOK, nodeIDs = pcall(traits.GetTreeNodes, configID, treeID)
		end
		local nodes = {}
		if nodesOK and type(nodeIDs) == "table" then
			for _, nodeID in ipairs(nodeIDs) do
				local nodeOK, info = pcall(traits.GetNodeInfo, configID, nodeID)
				if nodeOK and type(info) == "table" and (info.ID == nil or info.ID ~= 0) then
					table.insert(nodes, info)
				end
			end
		end
		local groups
		local subtreeSeen = {}
		local subtreeOrder = {}
		for _, info in ipairs(nodes) do
			if info.subTreeID then
				local id = info.subTreeID
				local group = subtreeSeen[id]
				if not group then
					group = { points = 0, nodes = {}, subTreeID = id, configID = configID, minX = TyGearPlainNumber(info.posX) or 0 }
					subtreeSeen[id] = group
					table.insert(subtreeOrder, group)
					if traits.GetSubTreeInfo then
						local subOK, sub = pcall(traits.GetSubTreeInfo, configID, id)
						if subOK and type(sub) == "table" and type(sub.name) == "string" then
							group.subTreeName = sub.name
						end
					end
				end
				group.points = group.points + TyGearTraitNodePoints(info)
				table.insert(group.nodes, info)
			end
		end
		if #subtreeOrder > 0 then
			table.sort(subtreeOrder, function(a, b) return a.minX < b.minX end)
			groups = subtreeOrder
		else
			groups = TyGearClusterTraitNodes(nodes)
			for _, group in ipairs(groups) do
				group.configID = configID
			end
		end
		for _, group in ipairs(groups) do
			table.insert(tabs, group)
		end
	end
	local bestName, bestPoints
	local useTabOrder = tabOrder and #tabs == #tabOrder
	for index, tab in ipairs(tabs) do
		local name = TyGearTraitTabName(className, tab, index, useTabOrder and tabOrder or nil)
		if name and tab.points and (bestPoints == nil or tab.points > bestPoints) then
			bestPoints = tab.points
			bestName = name
		end
	end
	if not bestPoints or bestPoints <= 0 or not bestName then
		return nil
	end
	return bestName
end

-- The talent tree with the most points. Equal totals keep the earlier tree. Nil when every tree has 0.
function TyGearHighestClassicTalentTabName()
	if not _G.GetNumTalentTabs or not _G.GetTalentTabInfo then return nil end
	local numTalentTabs = _G.GetNumTalentTabs()
	if type(numTalentTabs) ~= "number" or numTalentTabs < 1 then return nil end
	local bestName, bestPoints
	for i = 1, numTalentTabs do
		local name, points = TyGearReadTalentTab(i)
		if type(name) == "string" and type(points) == "number" and (bestPoints == nil or points > bestPoints) then
			bestPoints = points
			bestName = name
		end
	end
	if not bestPoints or bestPoints <= 0 or type(bestName) ~= "string" then return nil end
	bestName = string.gsub(bestName, "^%s+", "")
	bestName = string.gsub(bestName, "%s+$", "")
	if bestName == "" then return nil end
	return bestName
end

function TyGearHighestTalentTabName()
	return TyGearHighestClassicTalentTabName() or TyGearHighestTraitTalentTabName()
end

-- Match a talent-tab name to a weight-table spec. Unknown names are returned as-is.
function TyGearMatchWeightSpecName(className, talentName)
	if type(talentName) ~= "string" or talentName == "" then return nil end
	local wanted = string.lower(talentName)
	if className and TyGearGetWeightSpecNames then
		-- Forever's feral tree is Feral Combat. The shorter Feral row is a later rename.
		if IS_WOW_FOREVER and wanted == "feral" then
			for specName in pairs(TyGearGetWeightSpecNames(className)) do
				if specName == "Feral Combat" then
					return specName
				end
			end
		end
		for specName in pairs(TyGearGetWeightSpecNames(className)) do
			if string.lower(specName) == wanted then
				return specName
			end
		end
		local aliases = {
			["feral"] = "Feral Combat",
			["outlaw"] = "Combat",
		}
		local alias = aliases[wanted]
		if alias then
			for specName in pairs(TyGearGetWeightSpecNames(className)) do
				if specName == alias then
					return specName
				end
			end
		end
	end
	return talentName
end

function TyGearActiveSpecializationLine()
	local localizedClass, class, spec
	if TyGearDetectClassAndSpec then
		local ok, a, b, c = pcall(TyGearDetectClassAndSpec)
		if ok then
			localizedClass, class, spec = a, b, c
		end
	end
	spec = spec or "None"
	local specText = (class and TyGearSpecColoredText(class, spec)) or spec
	local classText = (class and localizedClass and TyGearClassColoredText(class, localizedClass)) or (localizedClass or "")
	if classText ~= "" then
		specText = specText.." "..classText
	end
	return L["Active specialization: "]..specText
end

function TyGearRefreshActiveSpecCallout()
	if TyGearActiveSpecCallout and TyGearActiveSpecCallout.SetText then
		TyGearActiveSpecCallout:SetText(TyGearActiveSpecializationLine())
	end
end

-- Specializations appeared only in Mists Of Pandaria. We also have make changes to Cataclysm with preferred talent tree
-- later
if IS_WOW_FOREVER then
	function TyGearDetectSpec()
		-- The active spec is the talent tree with the most points. No points spent uses the general profile.
		local className = UnitClassBase and UnitClassBase("player")
		local tab = TyGearHighestTalentTabName()
		if not tab then return "None" end
		return TyGearMatchWeightSpecName(className, tab) or "None"
	end
elseif TOC_VERSION_CURRENT < TOC_VERSION_MOP then
	function TyGearDetectSpec()
		-- GetSpecialization() doesn't exist until MoP
		-- Instead, this finds the talent tree where the most points are allocated.
		local highestSpec = nil
		local highestPointsSpent = nil
		local numTalentTabs = GetNumTalentTabs()
		if (not numTalentTabs) or (numTalentTabs < 2) then
			TyGearPrint("TyGear: numTalentTabs in TyGearGetSpec() is "..tostring(numTalentTabs),0)
		end
		-- It needs a condition of being above 0 or else it will assign highestSpec to the first talent tree even if there are 0 points in it.
		local _, spec, _, _, pointsSpent = GetTalentTabInfo(1)
		if pointsSpent and pointsSpent >= 0 then
			highestPointsSpent = pointsSpent
			if pointsSpent > 0 then highestSpec = spec end
			for i = 2, numTalentTabs do
				local _, spec, _, _, pointsSpent = GetTalentTabInfo(i)
				if (pointsSpent > highestPointsSpent) then
					highestPointsSpent = pointsSpent
					highestSpec = spec
				end
			end
		else
			for i = 1, numTalentTabs do
				local spec, _, pointsSpent = GetTalentTabInfo(i)
				if (highestPointsSpent == nil or pointsSpent > highestPointsSpent) then
					highestPointsSpent = pointsSpent
					highestSpec = spec
				end
			end
		end
		if (highestPointsSpent == 0) then
			return "None"
		end

		-- If they're feral, determine if they're a tank and call it Guardian.
		if (highestSpec == "Feral" or highestSpec == "Feral Combat") then
			local tankiness = 0
			if TOC_VERSION_CURRENT < TOC_VERSION_WOTLK then
				tankiness = tankiness + select(5, GetTalentInfo(2, 3)) * 1.0 --Feral Instinct
				tankiness = tankiness + select(5, GetTalentInfo(2, 7)) * 5 --Feral Charge
				tankiness = tankiness + select(5, GetTalentInfo(2, 5)) * 0.5 --Thick Hide
				tankiness = tankiness + select(5, GetTalentInfo(2, 9)) * -100 --Improved Shred
				tankiness = tankiness + select(5, GetTalentInfo(2, 12)) * 100 --Primal Fury
			else
				tankiness = tankiness + select(5, GetTalentInfo(2, 15)) * 3 --Survival Instincts
				tankiness = tankiness + select(5, GetTalentInfo(2, 10)) * 1 --Feral Charge
				tankiness = tankiness + select(5, GetTalentInfo(2, 22)) * 1 --Primal Precision
				tankiness = tankiness + select(5, GetTalentInfo(2, 1)) * 1 --Thick Hide
				tankiness = tankiness + select(5, GetTalentInfo(2, 19)) * -100 --Predatory Instincts
				tankiness = tankiness + select(5, GetTalentInfo(2, 28)) * 100 --Protector of the Pack
			end
			if (tankiness >= 5) then return "Guardian" end
		end

		return highestSpec
	end
else
	function TyGearDetectSpec()
		local currentSpec = GetSpecialization()
		local currentSpecName = currentSpec and select(2, GetSpecializationInfo(currentSpec)) or "None"
		if (currentSpec == 5) then
			return "None"
		else
			return currentSpecName
		end
	end
end

function TyGearGetDefaultOverrideSpec()
	local className = UnitClass("player")
	local spec = TyGearDetectSpec()
	if spec then
		return className..": "..spec
	end
end

-- Rings and trinkets share one localized name for both slots; append the inventory slot id.
local function TyGearGearSlotNeedsSlotId(slot)
	return slot == INVSLOT_FINGER1 or slot == INVSLOT_FINGER2
		or slot == INVSLOT_TRINKET1 or slot == INVSLOT_TRINKET2
end

local function TyGearGetGearSlotBaseName(slot)
	if slot >= INVSLOT_FIRST_EQUIPPED and slot <= INVSLOT_LAST_EQUIPPED then
		return TyGearSlotNames[slot] or GetItemInventorySlotInfo(slot) or tostring(slot)
	elseif TyGearReagentBagSlot and slot == TyGearReagentBagSlot then
		return TyGearGetReagentBagSlotName()
	elseif slot >= TyGearFirstEquippableBagSlot and slot <= TyGearLastEquippableBagSlot then
		local slotNumber = slot - TyGearFirstEquippableBagSlot + 1
		return (BAGSLOT or "Bag").." "..tostring(slotNumber)
	else
		return tostring(slot)
	end
end

function TyGearGetGearSlotShortLabel(slot)
	local name = TyGearGetGearSlotBaseName(slot)
	if slot >= INVSLOT_FIRST_EQUIPPED and slot <= INVSLOT_LAST_EQUIPPED and TyGearGearSlotNeedsSlotId(slot) then
		return name.." "..tostring(slot)
	end
	return name
end

function TyGearGetLockedGearSlotLabel(slot)
	if slot >= INVSLOT_FIRST_EQUIPPED and slot <= INVSLOT_LAST_EQUIPPED then
		local slotName = TyGearGetGearSlotBaseName(slot)
		return tostring(slot)..(slotName and ": "..slotName or "")
	elseif TyGearReagentBagSlot and slot == TyGearReagentBagSlot then
		return tostring(slot)..": "..TyGearGetReagentBagSlotName()
	elseif slot >= TyGearFirstEquippableBagSlot and slot <= TyGearLastEquippableBagSlot then
		local slotName = TyGearGetGearSlotBaseName(slot)
		return tostring(slot)..(slotName and ": "..slotName or "")
	else
		return tostring(slot)
	end
end

function TyGearGetDefaultLockedGearSlots()
	local lockedGearSlots = {}
	for slot = INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED do
		if TyGearIsLockableGearSlot(slot) then
			lockedGearSlots[slot] = {
				["label"] = TyGearGetLockedGearSlotLabel(slot),
				["enabled"] = false
			}
		end
	end
	return lockedGearSlots
end

function TyGearGetLockedGearSlots()
	if not TyGearDB.LockedGearSlots then
		TyGearDB.LockedGearSlots = TyGearGetDefaultLockedGearSlots()
	end
	return TyGearDB.LockedGearSlots
end

--checked slots are locked; there is no separate master lock toggle
function TyGearIsGearSlotLocked(invSlot)
	if not invSlot or not TyGearDB or not TyGearDB.LockedGearSlots then return false end
	local slotData = TyGearDB.LockedGearSlots[invSlot]
	return slotData and slotData.enabled and true or false
end

--old LockGearSlots master toggle gated per-slot locks; drop it and preserve "off" as no slots locked
function TyGearMigrateLockGearSlots()
	if not TyGearDB or TyGearDB.LockGearSlots == nil then return end
	if TyGearDB.LockGearSlots == false and TyGearDB.LockedGearSlots then
		for _, slotData in pairs(TyGearDB.LockedGearSlots) do
			if type(slotData) == "table" then
				slotData.enabled = false
			end
		end
	end
	TyGearDB.LockGearSlots = nil
end

--equipment slots only: bags are outside INVSLOT_LAST_EQUIPPED
function TyGearGetDefaultIgnoredGearSlots()
	local ignoredGearSlots = {}
	for slot = INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED do
		ignoredGearSlots[slot] = false
	end
	return ignoredGearSlots
end

function TyGearItemHasMeasurableStats(info)
	if not info then return false end
	local fields = {
		"Strength", "Agility", "Stamina", "Intellect", "Spirit", "Armor",
		"Dodge", "Parry", "Block", "Defense", "SpellPower", "SpellPenetration",
		"Haste", "Mp5", "AttackPower", "ArmorPenetration", "Crit", "SpellCrit",
		"Hit", "SpellHit", "Expertise", "RedSockets", "YellowSockets", "BlueSockets",
		"MetaSockets", "Mastery", "Multistrike", "Versatility", "DPS", "Damage",
		"WeaponSpeed", "MinDamage", "MaxDamage",
		"ExperienceGained", "numBagSlots", "ammoBagRangedAttackSpeed",
	}
	for _, field in ipairs(fields) do
		local value = info[field]
		if type(value) == "number" and value > 0 then
			return true
		end
	end
end

-- Fill AvgDamage / WeaponDPS from whichever of min-max, DPS, or speed the tooltip provided.
-- GetItemStats does not include base weapon damage or swing speed on Classic/Forever.
function TyGearNormalizeWeaponDamageStats(info)
	if not info or info.classID ~= Enum.ItemClass.Weapon then return end
	if info.MinDamage and info.MaxDamage then
		info.Damage = (info.MinDamage + info.MaxDamage) / 2
	end
	if (not info.DPS or info.DPS <= 0) and info.Damage and info.WeaponSpeed and info.WeaponSpeed > 0 then
		info.DPS = info.Damage / info.WeaponSpeed
	elseif info.DPS and info.DPS > 0 and info.WeaponSpeed and info.WeaponSpeed > 0
	and (not info.Damage or info.Damage <= 0) then
		info.Damage = info.DPS * info.WeaponSpeed
	end
end

-- Parse one lowered tooltip line (left+right already joined) for base weapon damage and speed.
function TyGearParseWeaponTooltipLine(info, text)
	if not info or not text or info.classID ~= Enum.ItemClass.Weapon then return end
	local dpsVal = tonumber(string.match(text, "([0-9]+%.?[0-9]*)%s*damage per second"))
	if dpsVal and dpsVal > 0 then
		info.DPS = math.max(info.DPS or 0, dpsVal)
	end
	local minDamage, maxDamage = string.match(text, "([0-9]+%.?[0-9]*)%s*%-%s*([0-9]+%.?[0-9]*)%s*damage")
	if minDamage and maxDamage then
		info.MinDamage = tonumber(minDamage)
		info.MaxDamage = tonumber(maxDamage)
		info.Damage = (info.MinDamage + info.MaxDamage) / 2
	end
	local speed = string.match(text, "speed%s+([0-9]+%.?[0-9]*)")
	if speed then
		info.WeaponSpeed = tonumber(speed)
	end
end

--true when a tooltip line is an equip, use, or proc effect rather than a scored stat
function TyGearLineIsItemEffect(text)
	if not text or text == "" then return false end
	local prefixes = {
		ITEM_SPELL_TRIGGER_ONEQUIP,
		ITEM_SPELL_TRIGGER_ONUSE,
		ITEM_SPELL_TRIGGER_ONPROC,
		"Equip:",
		"Use:",
		"Chance on hit:",
		"Chance on",
	}
	for _, prefix in ipairs(prefixes) do
		if prefix and string.sub(text, 1, string.len(prefix)) == prefix:lower() then
			return true
		end
	end
end

function TyGearIsKnownUnmeasurableGear(itemID)
	return IS_WOW_FOREVER and itemID and TyGearUnmeasurableGear and TyGearUnmeasurableGear[itemID]
end

--true when this equipment should be left out of rolling, scoring, and equipping
function TyGearIsItemIgnored(info)
	if not info then return false end
	local itemID
	if type(info) == "number" or type(info) == "string" then
		itemID = tonumber(info)
	else
		itemID = tonumber(info.id)
	end
	if not itemID then return false end
	--gear TyGear cannot score is always ignored; there is no toggle to evaluate it
	if TyGearIsKnownUnmeasurableGear(itemID) then
		return true
	end
	if IS_WOW_FOREVER and TyGearCharDB and TyGearCharDB.DiscoveredUnmeasurableGear and TyGearCharDB.DiscoveredUnmeasurableGear[itemID] then
		return true
	end
	if type(info) == "table" and info.unmeasurableOnly then
		return true
	end
	--any item on the ignore list is kept and left out of evaluation, gear or not
	if TyGearCharDB and TyGearCharDB.IgnoredItemIDs and TyGearCharDB.IgnoredItemIDs[itemID] then
		return true
	end
end

--the tabard id is also the virtual slot for two-hand weapons, so a tabard checkbox is not offered
function TyGearIsGearSlotProtected(invSlot)
	if not invSlot or not TyGearCharDB then return false end
	local function equippedInfo(slot)
		local equipped = TyGearEquippedItems and TyGearEquippedItems[slot]
		if equipped and equipped.info and not equipped.info.empty then
			return equipped.info
		end
	end
	local function itemProtects(slot)
		local info = equippedInfo(slot)
		return info and TyGearIsItemIgnored(info)
	end
	local parked = equippedInfo(INVSLOT_TABARD)
	local parkedTwoHand = parked and parked.classID == Enum.ItemClass.Weapon and TyGearIsItemIgnored(parked)
	if invSlot ~= INVSLOT_TABARD and TyGearCharDB.IgnoredGearSlots and TyGearCharDB.IgnoredGearSlots[invSlot] then
		return true
	end
	if not TyGearEquippedItems then return false end
	if invSlot == INVSLOT_TABARD then
		if parkedTwoHand then return true end
		if TyGearCharDB.IgnoredGearSlots and (TyGearCharDB.IgnoredGearSlots[INVSLOT_MAINHAND] or TyGearCharDB.IgnoredGearSlots[INVSLOT_OFFHAND]) then
			return true
		end
		if itemProtects(INVSLOT_MAINHAND) or itemProtects(INVSLOT_OFFHAND) then
			return true
		end
		return false
	end
	if itemProtects(invSlot) then return true end
	if (invSlot == INVSLOT_MAINHAND or invSlot == INVSLOT_OFFHAND) and parkedTwoHand then
		return true
	end
end

function TyGearIsAutoUnmeasurable(itemID)
	if not IS_WOW_FOREVER or not itemID then return false end
	if TyGearUnmeasurableGear and TyGearUnmeasurableGear[itemID] then return true end
	if TyGearCharDB and TyGearCharDB.DiscoveredUnmeasurableGear and TyGearCharDB.DiscoveredUnmeasurableGear[itemID] then return true end
end

function TyGearGetIgnoredItemIDOrder()
	if not TyGearCharDB then TyGearCharDB = {} end
	TyGearCharDB.IgnoredItemIDs = TyGearCharDB.IgnoredItemIDs or {}
	local order = TyGearCharDB.IgnoredItemIDOrder
	if type(order) ~= "table" then
		order = {}
		TyGearCharDB.IgnoredItemIDOrder = order
	end
	--drop stale IDs and append any set members missing from the order
	local seen, cleaned = {}, {}
	for _, itemID in ipairs(order) do
		itemID = tonumber(itemID)
		if itemID and TyGearCharDB.IgnoredItemIDs[itemID] and not seen[itemID] then
			seen[itemID] = true
			table.insert(cleaned, itemID)
		end
	end
	local missing = {}
	for itemID, ignored in pairs(TyGearCharDB.IgnoredItemIDs) do
		itemID = tonumber(itemID)
		if ignored and itemID and not seen[itemID] then
			table.insert(missing, itemID)
		end
	end
	table.sort(missing)
	for _, itemID in ipairs(missing) do
		table.insert(cleaned, itemID)
	end
	TyGearCharDB.IgnoredItemIDOrder = cleaned
	return cleaned
end

function TyGearSetItemIgnored(itemID, shouldIgnore)
	itemID = tonumber(itemID)
	if not itemID then return end
	--unmeasurable Forever gear stays ignored; only manual Item IDs are toggled here
	if TyGearIsAutoUnmeasurable(itemID) then return end
	if not TyGearCharDB then TyGearCharDB = {} end
	TyGearCharDB.IgnoredItemIDs = TyGearCharDB.IgnoredItemIDs or {}
	local order = TyGearGetIgnoredItemIDOrder()
	for index = #order, 1, -1 do
		if order[index] == itemID then
			table.remove(order, index)
		end
	end
	if shouldIgnore then
		TyGearCharDB.IgnoredItemIDs[itemID] = true
		table.insert(order, 1, itemID)
	else
		TyGearCharDB.IgnoredItemIDs[itemID] = nil
	end
	if TyGearUpdateBestItems then TyGearUpdateBestItems() end
end

--item ID and link from the item tooltip currently under the mouse (or a pinned ItemRefTooltip)
function TyGearGetHoveredItem()
	local function fromTooltip(tooltip)
		if not tooltip or not tooltip.IsShown or not tooltip:IsShown() then return end
		local name, link
		if tooltip.GetItem then
			name, link = tooltip:GetItem()
		end
		if (not link or (issecretvalue and issecretvalue(link))) and (tooltip.GetPrimaryTooltipData or tooltip.GetTooltipData) then
			local tooltipData = tooltip.GetPrimaryTooltipData and tooltip:GetPrimaryTooltipData() or tooltip:GetTooltipData()
			if tooltipData then
				link = tooltipData.hyperlink
				if (not link) and tooltipData.guid and C_Item and C_Item.GetItemLinkByGUID then
					link = C_Item.GetItemLinkByGUID(tooltipData.guid)
				end
				if (not link) and tooltipData.id then
					link = "item:"..tostring(tooltipData.id)
				end
				if (not name) and tooltipData.lines and tooltipData.lines[1] then
					name = tooltipData.lines[1].leftText
				end
			end
		end
		if not link or (issecretvalue and issecretvalue(link)) then return end
		local itemID = tonumber(string.match(link, "item:(%d+)"))
		if not itemID then return end
		return itemID, link, name
	end

	local itemID, link, name = fromTooltip(GameTooltip)
	if itemID then return itemID, link, name end
	itemID, link, name = fromTooltip(ItemRefTooltip)
	if itemID then return itemID, link, name end

	--bags / character pane: resolve from the button under the mouse when the tooltip has no link yet
	local guid = TyGearDetectHoveredItemGUID and TyGearDetectHoveredItemGUID()
	if guid and C_Item then
		if C_Item.GetItemIDByGUID then
			itemID = C_Item.GetItemIDByGUID(guid)
		end
		if C_Item.GetItemLinkByGUID then
			link = C_Item.GetItemLinkByGUID(guid)
		end
		if itemID then
			return itemID, link or ("item:"..tostring(itemID)), name
		end
	end
end

local vendorKeepListCacheKey
local vendorKeepListCache

function TyGearIsOnVendorKeepList(itemID)
	itemID = tonumber(itemID)
	if not itemID then return false end
	--profession weapon tools (Skinning Knife, Mining Pick, fishing poles, …) stay kept even if the saved list was cleared
	if TyGearCraftingToolItemIDSet and TyGearCraftingToolItemIDSet[itemID] then
		return true
	end
	if not TyGearDB then return false end
	local text = TyGearDB.VendorKeepList or ""
	if vendorKeepListCacheKey ~= text then
		vendorKeepListCacheKey = text
		vendorKeepListCache = {}
		for _, listedID in ipairs(TyGearParseItemIDList(text)) do
			vendorKeepListCache[listedID] = true
		end
	end
	return vendorKeepListCache[itemID] and true or false
end

-- Resolve an item ID from a number, string, or info table.
local function TyGearItemIDFrom(info)
	if type(info) == "number" or type(info) == "string" then
		return tonumber(info)
	elseif type(info) == "table" then
		return tonumber(info.id)
	end
end

-- Keep-list / hard-kept crafting tools that are not on the true ignore list.
-- These stay unsold, but may still fill an empty gear slot (something > nothing).
function TyGearIsVendorKeepOnly(info)
	if TyGearIsItemIgnored(info) then return false end
	local itemID = TyGearItemIDFrom(info)
	return itemID and TyGearIsOnVendorKeepList(itemID) and true or false
end

-- Left out of selling. True ignore-list / unmeasurable items are also left out of all
-- evaluation and equipping. Keep-list items are unsold but may fill empty slots.
-- Slot protection stays on TyGearIsItemIgnored so a kept crafting tool does not lock its slot.
function TyGearIsLeftOut(info)
	if TyGearIsItemIgnored(info) then return true end
	local itemID = TyGearItemIDFrom(info)
	if itemID and TyGearIsOnVendorKeepList(itemID) then return true end
end

function TyGearIsOnNeedList(itemID)
	itemID = tonumber(itemID)
	if not itemID or not TyGearDB then return false end
	for _, listedID in ipairs(TyGearParseItemIDList(TyGearDB.NeedList or "")) do
		if listedID == itemID then return true end
	end
	return false
end

function TyGearRefreshVendorKeepListEditBox()
	local editBox = _G["TyGearVendorKeepListEditBox"]
	if editBox and editBox.SetText and not editBox:HasFocus() then
		editBox:SetText((TyGearDB and TyGearDB.VendorKeepList) or "")
		editBox:SetCursorPosition(0)
	end
	if TyGearRefreshKeepList then TyGearRefreshKeepList() end
end

function TyGearRefreshNeedListEditBox()
	local editBox = _G["TyGearNeedListEditBox"]
	if editBox and editBox.SetText and not editBox:HasFocus() then
		editBox:SetText((TyGearDB and TyGearDB.NeedList) or "")
		editBox:SetCursorPosition(0)
	end
	if TyGearRefreshNeedList then TyGearRefreshNeedList() end
end

function TyGearSetVendorKeepListItem(itemID, shouldKeep)
	itemID = tonumber(itemID)
	if not itemID then return end
	--default profession weapon tools are hard-kept and stay out of the editable keep-list text
	if TyGearCraftingToolItemIDSet and TyGearCraftingToolItemIDSet[itemID] then
		return
	end
	if not TyGearDB then TyGearDB = {} end
	local ordered, seen = {}, {}
	for _, listedID in ipairs(TyGearParseItemIDList(TyGearDB.VendorKeepList or "")) do
		if listedID ~= itemID and not seen[listedID] then
			seen[listedID] = true
			table.insert(ordered, listedID)
		end
	end
	if shouldKeep then
		--newest entries stay near the top of the saved list
		table.insert(ordered, 1, itemID)
	end
	TyGearDB.VendorKeepList = table.concat(ordered, ", ")
	TyGearRefreshVendorKeepListEditBox()
	if TyGearQueueVendorJunkRefresh then TyGearQueueVendorJunkRefresh() end
	if TyGearUpdateBestItems then TyGearUpdateBestItems() end
end

function TyGearSetNeedListItem(itemID, shouldNeed)
	itemID = tonumber(itemID)
	if not itemID then return end
	if not TyGearDB then TyGearDB = {} end
	local ordered, seen = {}, {}
	for _, listedID in ipairs(TyGearParseItemIDList(TyGearDB.NeedList or "")) do
		if listedID ~= itemID and not seen[listedID] then
			seen[listedID] = true
			table.insert(ordered, listedID)
		end
	end
	if shouldNeed then
		--newest entries stay near the top of the saved list
		table.insert(ordered, 1, itemID)
	end
	TyGearDB.NeedList = table.concat(ordered, ", ")
	TyGearRefreshNeedListEditBox()
end

function TyGearItemDisplay(link, itemID, name)
	if link and not (issecretvalue and issecretvalue(link)) and string.find(link, "|H") then
		return link
	end
	if name and name ~= "" then
		return name.." ("..tostring(itemID)..")"
	end
	return "item "..tostring(itemID)
end

--Key Bindings → TyGear: hover an item, then press the assigned key
function TyGearBindingToggleNeed()
	local itemID, link, name = TyGearGetHoveredItem()
	if not itemID then
		TyGearPrint("TyGear: "..L["Hover an item, then press this key to toggle it on the need list."], 0)
		return
	end
	local need = not TyGearIsOnNeedList(itemID)
	TyGearSetNeedListItem(itemID, need)
	local display = TyGearItemDisplay(link, itemID, name)
	if need then
		TyGearPrint("TyGear: "..string.format(L["Added %s to the need list."], display), 0)
	else
		TyGearPrint("TyGear: "..string.format(L["Removed %s from the need list."], display), 0)
	end
end

--one binding: the ignore list keeps the item and leaves it out of evaluation
function TyGearBindingToggleIgnore()
	local itemID, link, name = TyGearGetHoveredItem()
	if not itemID then
		TyGearPrint("TyGear: "..L["Hover an item, then press this key to keep it and skip evaluation."], 0)
		return
	end
	if TyGearIsAutoUnmeasurable(itemID) then
		TyGearPrint("TyGear: "..L["TyGear cannot score this item, so it stays ignored."], 0)
		return
	end
	local ignored = TyGearCharDB and TyGearCharDB.IgnoredItemIDs and TyGearCharDB.IgnoredItemIDs[itemID] and true or false
	TyGearSetItemIgnored(itemID, not ignored)
	if TyGearRefreshIgnoreSection then TyGearRefreshIgnoreSection() end
	local display = TyGearItemDisplay(link, itemID, name)
	if not ignored then
		TyGearPrint("TyGear: "..string.format(L["Added %s to the ignore list. It will be kept and not evaluated."], display), 0)
	else
		TyGearPrint("TyGear: "..string.format(L["Removed %s from the ignore list."], display), 0)
	end
end

function TyGearAddListBindingHintsToTooltip(tooltip)
	if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
	local needKey = GetBindingKey and GetBindingKey("TYGEAR_TOGGLE_NEED")
	local ignoreKey = GetBindingKey and GetBindingKey("TYGEAR_TOGGLE_IGNORE")
	if not needKey and not ignoreKey then return end
	local hasItem = false
	if tooltip.GetItem then
		local _, link = tooltip:GetItem()
		hasItem = link and not (issecretvalue and issecretvalue(link))
	end
	if (not hasItem) and (tooltip.GetPrimaryTooltipData or tooltip.GetTooltipData) then
		local tooltipData = tooltip.GetPrimaryTooltipData and tooltip:GetPrimaryTooltipData() or tooltip:GetTooltipData()
		hasItem = tooltipData and (tooltipData.hyperlink or tooltipData.guid or tooltipData.id) and true or false
	end
	if not hasItem then return end
	local parts = {}
	if ignoreKey then
		table.insert(parts, ignoreKey..": "..L["keep and ignore"])
	end
	if needKey then
		table.insert(parts, needKey..": "..L["need list"])
	end
	tooltip:AddLine("TyGear  "..table.concat(parts, "  "), 0.5, 0.5, 0.5, true)
end

function TyGearAllValidGearSlotsProtected(info)
	if not info or not info.validGearSlots then return false end
	local any = false
	for _, gearSlot in pairs(info.validGearSlots) do
		any = true
		if not TyGearIsGearSlotProtected(gearSlot) then
			return false
		end
	end
	return any
end

function TyGearRememberUnmeasurableGear(info)
	if not IS_WOW_FOREVER or not info or not info.id or not info.unmeasurableOnly then return end
	if TyGearUnmeasurableGear and TyGearUnmeasurableGear[info.id] then return end
	if not TyGearCharDB then TyGearCharDB = {} end
	TyGearCharDB.DiscoveredUnmeasurableGear = TyGearCharDB.DiscoveredUnmeasurableGear or {}
	if not TyGearCharDB.DiscoveredUnmeasurableGear[info.id] then
		TyGearCharDB.DiscoveredUnmeasurableGear[info.id] = true
		if TyGearRefreshIgnoreSection then TyGearRefreshIgnoreSection() end
		if TyGearRefreshIgnoredGearList then TyGearRefreshIgnoredGearList() end
	end
end

function TyGearFixLockedGearSlots() -- finds missing slots and adds them, in case Blizzard changed them around
	if not TyGearDB.LockedGearSlots then TyGearDB.LockedGearSlots = TyGearGetDefaultLockedGearSlots() return end
	for slot = INVSLOT_FIRST_EQUIPPED, TyGearLastManagedGearSlot do
		if TyGearIsLockableGearSlot(slot) then
			if not TyGearDB.LockedGearSlots[slot] then
				TyGearDB.LockedGearSlots[slot] = {
					["label"] = TyGearGetLockedGearSlotLabel(slot),
					["enabled"] = false
				}
			elseif TyGearDB.LockedGearSlots[slot].label then
				TyGearDB.LockedGearSlots[slot].label = TyGearGetLockedGearSlotLabel(slot)
			end
		elseif TyGearDB.LockedGearSlots[slot] then
			--drop tabard, shirt, and bag entries left over from older defaults
			TyGearDB.LockedGearSlots[slot] = nil
		end
	end
end

--an invisible tooltip that TyGear can scan for various information
local tooltipFrame = CreateFrame("GameTooltip", "TyGearTooltip", UIParent, "GameTooltipTemplate")

--the main frame
TyGearFrame = CreateFrame("Frame", nil, UIParent)
TyGearFrame:SetWidth(1) TyGearFrame:SetHeight(1)
TyGearFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)

local E = 0.000001 --epsilon; non-zero value that's insignificantly different from 0, used here for the purpose of valuing gear that has higher stats that give the player "almost no benefit"
-- regex for finding 0 in this block to replace with E: (?<=[^ ] = )0(?=[^\.0-9])
if TOC_VERSION_CURRENT < TOC_VERSION_CATA then
	TyGearDefaultWeights = {
		["DEATHKNIGHT"] = {
			["None"] = {
				Strength = 1.05, Agility = E, Stamina = 0.5, Intellect = E, Spirit = E,
				Armor = 1, Dodge = 0.5, Parry = 0.5, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 0.8, Mp5 = E,
				AttackPower = 1, ArmorPenetration = 0.005, Crit = 1, SpellCrit = 1, Hit = 0.15, SpellHit = E,
				Expertise = 0.3, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 0.33, DamageSpellProc = 0.25, MeleeProc = 0.25, RangedProc = E,
				DPS = 1.2, Damage = 0.8
			},
			["Blood"] = {
				weapons = "2h",
				Strength = 1.05, Agility = E, Stamina = 0.5, Intellect = E, Spirit = E,
				Armor = 1, Dodge = 0.5, Parry = 0.5, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 0.8, Mp5 = E,
				AttackPower = 1, ArmorPenetration = 0.005, Crit = 1, SpellCrit = 1, Hit = 0.15, SpellHit = E,
				Expertise = 0.3, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 0.33, DamageSpellProc = 0.2, MeleeProc = 0.25, RangedProc = E,
				DPS = 1, Damage = 1
			},
			["Frost"] = {
				weapons = "dual wield",
				Strength = 1.05, Agility = E, Stamina = 0.05, Intellect = E, Spirit = E,
				Armor = 1, Dodge = 0.5, Parry = 0.5, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 1.22, Mp5 = E,
				AttackPower = 1, ArmorPenetration = 0.005, Crit = 1, SpellCrit = 1, Hit = 0.15, SpellHit = E,
				Expertise = 0.3, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 0.33, DamageSpellProc = 0.25, MeleeProc = 0.33, RangedProc = E,
				DPS = 1.2, Damage = 0.8
			},
			["Unholy"] = {
				weapons = "2h",
				Strength = 1.05, Agility = E, Stamina = 0.05, Intellect = E, Spirit = E,
				Armor = 1, Dodge = 0.5, Parry = 0.5, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 0.8, Mp5 = E,
				AttackPower = 1, ArmorPenetration = 0.005, Crit = 1, SpellCrit = 1, Hit = 0.15, SpellHit = E,
				Expertise = 0.3, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 0.33, DamageSpellProc = 0.33, MeleeProc = 0.2, RangedProc = E,
				DPS = 1.33333, Damage = 0.66667
			}
		},
		["DEMONHUNTER"] = {
			["None"] = {
				Strength = E, Agility = 1.1, Stamina = 0.05, Intellect = E, Spirit = E,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 1.05, Mp5 = E,
				AttackPower = 1, ArmorPenetration = E, Crit = 1.1, SpellCrit = 1.1, Hit = 1.75, SpellHit = E,
				Expertise = 1.85, Versatility = 0.8, Multistrike = 1, Mastery = 1.5, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 0.33, DamageSpellProc = 0.1, MeleeProc = 0.33, RangedProc = E,
				DPS = 3.075
			},
			["Havoc"] = {
				weapons = "dual wield",
				Strength = E, Agility = 1.1, Stamina = 0.05, Intellect = E, Spirit = E,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 1.05, Mp5 = E,
				AttackPower = 1, ArmorPenetration = E, Crit = 1.1, SpellCrit = 1.1, Hit = 1.75, SpellHit = E,
				Expertise = 1.85, Versatility = 0.8, Multistrike = 1, Mastery = 1.5, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 0.33, DamageSpellProc = 0.2, MeleeProc = 0.33, RangedProc = E,
				DPS = 3.075
			},
			["Vengeance"] = {
				weapons = "dual wield",
				Strength = E, Agility = 1.05, Stamina = 1, Intellect = E, Spirit = E,
				Armor = 0.8, Dodge = 0.4, Parry = E, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 0.8, Mp5 = E,
				AttackPower = 1, ArmorPenetration = E, Crit = 1.1, SpellCrit = 1.1, Hit = 0.3, SpellHit = E,
				Expertise = 0.4, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 0.33, DamageSpellProc = 0.1, MeleeProc = 0.25, RangedProc = E,
				DPS = 2
			},
			["Devourer"] = {
				weapons = "dual wield",
				Strength = E, Agility = E, Stamina = 0.05, Intellect = 1.05, Spirit = E,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = 1, SpellPenetration = E, Haste = 1.5, Mp5 = E,
				AttackPower = E, ArmorPenetration = E, Crit = 1.1, SpellCrit = 1.1, Hit = 1.75, SpellHit = 1.75,
				Expertise = 1.85, Versatility = 0.8, Multistrike = 1, Mastery = 1.5, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 0.33, DamageSpellProc = 0.33, MeleeProc = E, RangedProc = E,
				DPS = E
			}
		},
		["DRUID"] = {
			["None"] = {
				Strength = E, Agility = E, Stamina = 0.05, Intellect = 0.26, Spirit = 0.5,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = 0.5, SpellPenetration = E, Haste = 0.5, Mp5 = 0.05,
				AttackPower = E, ArmorPenetration = E, Crit = 0.9, SpellCrit = 0.9, Hit = 0.9, SpellHit = 0.9,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 1.45, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = 0.33, DamageProc = 0.33, DamageSpellProc = 0.33, MeleeProc = 0.33, RangedProc = E,
				DPS = 1
			},
			["Balance"] = {
				Strength = E, Agility = E, Stamina = 0.05, Intellect = 0.26, Spirit = 0.1,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = 0.8, SpellPenetration = 0.1, Haste = 0.8, Mp5 = 0.01,
				AttackPower = E, ArmorPenetration = E, Crit = 0.1, SpellCrit = 1, Hit = 0.1, SpellHit = 1,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 0.6, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = 0.05, DamageProc = 0.33, DamageSpellProc = 0.33, MeleeProc = E, RangedProc = E,
				DPS = 0.01
			},
			["Feral"] = {
				Strength = 0.3, Agility = 1.05, Stamina = 1, Intellect = 0.1, Spirit = 0.2,
				Armor = 0.08, Dodge = 0.4, Parry = E, Block = E, Defense = 0.05,
				SpellPower = E, SpellPenetration = E, Haste = 0.8, Mp5 = E,
				AttackPower = 1, ArmorPenetration = E, Crit = 1.1, SpellCrit = E, Hit = 0.3, SpellHit = E,
				Expertise = 0.4, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = 0.05, DamageProc = 0.33, DamageSpellProc = E, MeleeProc = 0.33, RangedProc = E,
				DPS = 0.8
			},
			["Feral Combat"] = { -- Classic spec name
				Strength = 0.3, Agility = 1.05, Stamina = 1, Intellect = 0.1, Spirit = 0.2,
				Armor = 0.08, Dodge = 0.4, Parry = E, Block = E, Defense = 0.05,
				SpellPower = E, SpellPenetration = E, Haste = 0.8, Mp5 = E,
				AttackPower = 1, ArmorPenetration = E, Crit = 1.1, SpellCrit = E, Hit = 0.3, SpellHit = E,
				Expertise = 0.4, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = 0.05, DamageProc = 0.33, DamageSpellProc = E, MeleeProc = 0.33, RangedProc = E,
				DPS = 0.8
			},
			["Guardian"] = {
				Strength = E, Agility = 1.05, Stamina = 1, Intellect = E, Spirit = E,
				Armor = 0.08, Dodge = 0.4, Parry = E, Block = E, Defense = 1.33,
				SpellPower = E, SpellPenetration = E, Haste = 0.8, Mp5 = E,
				AttackPower = 1, ArmorPenetration = E, Crit = 1.1, SpellCrit = E, Hit = 0.3, SpellHit = E,
				Expertise = 0.4, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = 0.05, DamageProc = 0.33, DamageSpellProc = E, MeleeProc = 0.33, RangedProc = E,
				DPS = 0.8
			},
			["Restoration"] = {
				Strength = E, Agility = E, Stamina = 0.05, Intellect = 0.6, Spirit = 1.0,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = 0.85, SpellPenetration = E, Haste = 0.8, Mp5 = 3,
				AttackPower = E, ArmorPenetration = E, Crit = E, SpellCrit = 0.5, Hit = E, SpellHit = E,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 0.65, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = 0.33, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 0.01
			}
		},
		["EVOKER"] = {
			["None"] = {
				Strength = E, Agility = E, Stamina = E, Intellect = 4.14, Spirit = E,
				Armor = E, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = 4, SpellPenetration = E, Haste = 3.47, Mp5 = E,
				AttackPower = E, ArmorPenetration = E, Crit = 2.65, Hit = E,
				Expertise = E, Versatility = 2.89, Multistrike = E, Mastery = 0.24, ExperienceGained = E,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = 1.33, DamageProc = 1.33, DamageSpellProc = 1.33, MeleeProc = E, RangedProc = E,
				DPS = E
			},
			["Devastation"] = {
				Strength = E, Agility = E, Stamina = E, Intellect = 4.14, Spirit = E,
				Armor = E, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = 4, SpellPenetration = E, Haste = 3.47, Mp5 = E,
				AttackPower = E, ArmorPenetration = E, Crit = 2.65, Hit = E,
				Expertise = E, Versatility = 2.89, Multistrike = E, Mastery = 0.24, ExperienceGained = E,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 1.33, DamageSpellProc = 1.33, MeleeProc = E, RangedProc = E,
				DPS = E
			},
			["Preservation"] = {
				Strength = E, Agility = E, Stamina = E, Intellect = 4.14, Spirit = E,
				Armor = E, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = 4, SpellPenetration = E, Haste = 3.47, Mp5 = E,
				AttackPower = E, ArmorPenetration = E, Crit = 2.65, Hit = E,
				Expertise = E, Versatility = 2.89, Multistrike = E, Mastery = 0.24, ExperienceGained = E,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = 1.33, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = E
			},
			["Augmentation"] = {
				Strength = E, Agility = E, Stamina = E, Intellect = 4.14, Spirit = E,
				Armor = E, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = 4, SpellPenetration = E, Haste = 3.47, Mp5 = E,
				AttackPower = E, ArmorPenetration = E, Crit = 2.65, Hit = E,
				Expertise = E, Versatility = 2.89, Multistrike = E, Mastery = 0.24, ExperienceGained = E,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 1.33, DamageSpellProc = 1.33, MeleeProc = E, RangedProc = E,
				DPS = E
			}
		},
		["HUNTER"] = {
			["None"] = {
				Strength = 0.3, Agility = 1.05, Stamina = 0.15, Intellect = E, Spirit = 0.2,
				Armor = 0.0001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 0.8, Mp5 = E,
				AttackPower = 1, ArmorPenetration = 0.8, Crit = 0.8, SpellCrit = E, Hit = 0.4, SpellHit = E,
				Expertise = 0.1, Versatility = 0.8, Multistrike = 1, Mastery = E, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 0.33, DamageSpellProc = E, MeleeProc = 0.1, RangedProc = 0.33,
				DPS = 2
			},
			["Beast Mastery"] = {
				Strength = 0.3, Agility = 1.05, Stamina = 0.15, Intellect = E, Spirit = 0.2,
				Armor = 0.0001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 0.9, Mp5 = E,
				AttackPower = 1, ArmorPenetration = 0.8, Crit = 2, SpellCrit = E, Hit = 1.4, SpellHit = E,
				Expertise = 0.1, Versatility = 0.8, Multistrike = 1, Mastery = 1.5, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 0.33, DamageSpellProc = E, MeleeProc = E, RangedProc = 0.33,
				DPS = 2
			},
			["Marksmanship"] = {
				Strength = 0.3, Agility = 1.05, Stamina = 0.15, Intellect = E, Spirit = 0.2,
				Armor = 0.0001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 1.61, Mp5 = E,
				AttackPower = 1, ArmorPenetration = E, Crit = 1.66, SpellCrit = E, Hit = 3.49, SpellHit = E,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 1.38, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 0.33, DamageSpellProc = E, MeleeProc = E, RangedProc = 0.33,
				DPS = 2
			},
			["Survival"] = {
				Strength = 0.3, Agility = 1.05, Stamina = 0.15, Intellect = E, Spirit = 0.2,
				Armor = 0.0001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 1.33, Mp5 = E,
				AttackPower = 1, ArmorPenetration = E, Crit = 1.37, SpellCrit = E, Hit = 3.19, SpellHit = E,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 1.27, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 0.33, DamageSpellProc = 0.1, MeleeProc = 0.25, RangedProc = 0.1,
				DPS = 2
			}
		},
		["MAGE"] = {
			["None"] = {
				Strength = E, Agility = E, Stamina = 0.05, Intellect = 0.40, Spirit = 0.9,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = 2.8, SpellPenetration = 0.005, Haste = 1.28, Mp5 = .005,
				AttackPower = E, ArmorPenetration = E, Crit = E, SpellCrit = 1.3, Hit = E, SpellHit = 1.25,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 1.4, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 0.33, DamageSpellProc = 0.33, MeleeProc = E, RangedProc = E,
				DPS = 0.01
			},
			["Arcane"] = {
				Strength = E, Agility = E, Stamina = 0.01, Intellect = 0.40, Spirit = 0.9,
				Armor = 0.0001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = 1.1, SpellPenetration = 0.2, Haste = 0.5, Mp5 = E,
				AttackPower = E, ArmorPenetration = E, Crit = E, SpellCrit = 1.3, Hit = E, SpellHit = 1.25,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 0.9, ExperienceGained = 100,
				RedSockets = 10, YellowSockets = 8, BlueSockets = 7, MetaSockets = 20,
				HealingProc = E, DamageProc = 0.33, DamageSpellProc = 0.33, MeleeProc = E, RangedProc = E,
				DPS = 0.01
			},
			["Fire"] = {
				Strength = E, Agility = E, Stamina = 0.05, Intellect = 1, Spirit = 0.9,
				Armor = 0.0001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = 1.1, SpellPenetration = E, Haste = 0.8, Mp5 = E,
				AttackPower = E, ArmorPenetration = E, Crit = E, SpellCrit = 2.4, Hit = E, SpellHit = 1.75,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 0.9, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 0.33, DamageSpellProc = 0.33, MeleeProc = E, RangedProc = E,
				DPS = 0.01
			},
			["Frost"] = {
				Strength = E, Agility = E, Stamina = 0.05, Intellect = 0.40, Spirit = 0.8,
				Armor = 0.0001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = 1, SpellPenetration = 0.3, Haste = 0.8, Mp5 = E,
				AttackPower = E, ArmorPenetration = E, Crit = E, SpellCrit = 1.3, Hit = E, SpellHit = 1.25,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 0.9, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 0.33, DamageSpellProc = 0.33, MeleeProc = E, RangedProc = E,
				DPS = 0.01
			}
		},
		["MONK"] = {
			["None"] = {
				Strength = E, Agility = 1.1, Stamina = 0.05, Intellect = E, Spirit = E,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 1.05, Mp5 = E,
				AttackPower = 1, ArmorPenetration = E, Crit = 1.1, SpellCrit = 1.1, Hit = 1.75, SpellHit = 1.75,
				Expertise = 1.85, Versatility = 0.8, Multistrike = 1, Mastery = 1.5, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = 0.1, DamageProc = 0.33, DamageSpellProc = 0.1, MeleeProc = 0.33, RangedProc = E,
				DPS = 3.075
			},
			["Brewmaster"] = {
				weapons = "2h",
				Strength = E, Agility = 1.05, Stamina = 1, Intellect = E, Spirit = E,
				Armor = 0.8, Dodge = 0.4, Parry = E, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 0.8, Mp5 = E,
				AttackPower = 1, ArmorPenetration = E, Crit = 1.1, SpellCrit = 1.1, Hit = 0.3, SpellHit = 0.3,
				Expertise = 0.4, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 0.33, DamageSpellProc = E, MeleeProc = 0.33, RangedProc = E,
				DPS = 1, Damage = 1
			},
			["Windwalker"] = {
				weapons = "dual wield",
				Strength = E, Agility = 1.1, Stamina = 0.05, Intellect = E, Spirit = E,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 1.05, Mp5 = E,
				AttackPower = 1, ArmorPenetration = E, Crit = 1.1, SpellCrit = 1.1, Hit = 1.75, SpellHit = 1.75,
				Expertise = 1.85, Versatility = 0.8, Multistrike = 1, Mastery = 1.5, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = 0.05, DamageProc = 0.33, DamageSpellProc = 0.05, MeleeProc = 0.33, RangedProc = E,
				DPS = 3.075
			},
			["Mistweaver"] = {
				Strength = E, Agility = E, Stamina = 0.05, Intellect = 0.26, Spirit = 0.60,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = 0.85, SpellPenetration = E, Haste = 0.8, Mp5 = 0.05,
				AttackPower = E, ArmorPenetration = E, Crit = 0.6, SpellCrit = 0.6, Hit = E, SpellHit = E,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 0.65, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = 0.33, DamageProc = 0.05, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 0.13333, Damage = 0.06667
			}
		},
		["PALADIN"] = {
			["None"] = {
				Strength = 2.33, Agility = E, Stamina = 0.05, Intellect = E, Spirit = 1,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 0.79, Mp5 = E,
				AttackPower = 1, ArmorPenetration = E, Crit = 0.98, SpellCrit = 0.98, Hit = 1.77, SpellHit = 0.77,
				Expertise = 1.3, Versatility = 0.8, Multistrike = 1, Mastery = 1.13, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = 0.33, DamageProc = 0.33, DamageSpellProc = 0.33, MeleeProc = 0.33, RangedProc = E,
				DPS = 1.33333, Damage = 0.66667
			},
			["Holy"] = {
				Strength = E, Agility = E, Stamina = 0.05, Intellect = 0.26, Spirit = 1,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = 0.7, SpellPenetration = E, Haste = 0.8, Mp5 = E,
				AttackPower = E, ArmorPenetration = E, Crit = E, SpellCrit = 0.1, Hit = E, SpellHit = 0.1,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 0.3, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = 0.33, DamageProc = 0.1, DamageSpellProc = 0.1, MeleeProc = 0.05, RangedProc = E,
				DPS = 0.01
			},
			["Protection"] = {
				weapons = "weapon and shield",
				Strength = 1, Agility = 0.3, Stamina = 0.65, Intellect = 0.1, Spirit = 0.3,
				Armor = 0.05, Dodge = 0.8, Parry = 0.75, Block = 0.8, Defense = 3,
				SpellPower = 0.05, SpellPenetration = E, Haste = 0.5, Mp5 = E,
				AttackPower = 0.4, ArmorPenetration = 0.1, Crit = 0.25, SpellCrit = E, Hit = E,
				Expertise = 0.2, Versatility = 0.8, Multistrike = 1, Mastery = 0.05, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = 0.05, DamageProc = 0.33, DamageSpellProc = 0.25, SpellProc = 0.25, MeleeProc = 0.1, RangedProc = E,
				DPS = 1.33333, Damage = 0.66667
			},
			["Retribution"] = {
				weapons = "2h",
				Strength = 2.33, Agility = E, Stamina = 0.05, Intellect = 0.1, Spirit = 0.3,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 0.79, Mp5 = E,
				AttackPower = 1, ArmorPenetration = E, Crit = 0.98, SpellCrit = 0.1, Hit = 1.77, SpellHit = 0.1,
				Expertise = 1.3, Versatility = 0.8, Multistrike = 1, Mastery = 1.13, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = 0.05, DamageProc = 0.33, DamageSpellProc = E, MeleeProc = 0.25, RangedProc = E,
				DPS = 1, Damage = 1
			}
		},
		["PRIEST"] = {
			["None"] = {
				Strength = E, Agility = E, Stamina = 0.05, Intellect = 0.26, Spirit = 1,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = 2.75, SpellPenetration = E, Haste = 2, Mp5 = 4,
				AttackPower = E, ArmorPenetration = E, Crit = E, SpellCrit = 1.6, Hit = E, SpellHit = 1.95,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 1.7, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = 0.33, DamageProc = 0.33, DamageSpellProc = 0.33, MeleeProc = E, RangedProc = E,
				DPS = 0.01
			},
			["Discipline"] = {
				Strength = E, Agility = E, Stamina = E, Intellect = 0.26, Spirit = 1,
				Armor = 0.0001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = 0.8, SpellPenetration = E, Haste = 1, Mp5 = 4,
				AttackPower = E, ArmorPenetration = E, Crit = E, SpellCrit = 0.25, Hit = E, SpellHit = E,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 0.5, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = 0.33, DamageProc = 0.1, DamageSpellProc = 0.1, MeleeProc = E, RangedProc = E,
				DPS = 0.01
			},
			["Holy"] = {
				Strength = E, Agility = E, Stamina = 0.05, Intellect = 0.26, Spirit = 1.8,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = 0.7, SpellPenetration = E, Haste = 0.47, Mp5 = 4,
				AttackPower = E, ArmorPenetration = E, Crit = E, SpellCrit = 0.47, Hit = E, SpellHit = E,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 0.36, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = 0.33, DamageProc = 0.1, DamageSpellProc = 0.1, MeleeProc = E, RangedProc = E,
				DPS = 0.01
			},
			["Shadow"] = {
				Strength = E, Agility = E, Stamina = 0.05, Intellect = 0.26, Spirit = 1,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = 1, SpellPenetration = E, Haste = 1, Mp5 = 3,
				AttackPower = E, ArmorPenetration = E, Crit = E, SpellCrit = 1, Hit = E, SpellHit = 1,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = 0.1, DamageProc = 0.33, DamageSpellProc = 0.33, MeleeProc = E, RangedProc = E,
				DPS = 0.01
			}
		},
		["ROGUE"] = {
			["None"] = {
				weapons = "dagger and any",
				Strength = E, Agility = 1.1, Stamina = 0.05, Intellect = E, Spirit = E,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 1.05, Mp5 = E,
				AttackPower = 1, ArmorPenetration = E, Crit = 1.1, SpellCrit = E, Hit = 1.75, SpellHit = E,
				Expertise = 1.85, Versatility = 0.8, Multistrike = 1, Mastery = 1.5, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 0.33, DamageSpellProc = E, MeleeProc = 0.33, RangedProc = E,
				DPS = 3.075
			},
			["Assassination"] = {
				weapons = "dagger and any",
				Strength = E, Agility = 1.1, Stamina = 0.05, Intellect = E, Spirit = E,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 1.05, Mp5 = E,
				AttackPower = 1, ArmorPenetration = E, Crit = 1.1, SpellCrit = E, Hit = 1.75, SpellHit = E,
				Expertise = 1.1, Versatility = 0.8, Multistrike = 1, Mastery = 1.3, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 0.33, DamageSpellProc = E, MeleeProc = 0.33, RangedProc = E,
				DPS = 2
			},
			["Outlaw"] = {
				weapons = "dual wield",
				Strength = E, Agility = 1.1, Stamina = 0.05, Intellect = E, Spirit = E,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 1.05, Mp5 = E,
				AttackPower = 1, ArmorPenetration = E, Crit = 1.1, SpellCrit = E, Hit = 1.75, SpellHit = E,
				Expertise = 1.85, Versatility = 0.8, Multistrike = 1, Mastery = 1.5, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 0.33, DamageSpellProc = E, MeleeProc = 0.33, RangedProc = E,
				DPS = 3.075
			},
			["Combat"] = {
				weapons = "dual wield",
				Strength = E, Agility = 1.1, Stamina = 0.05, Intellect = E, Spirit = E,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 1.05, Mp5 = E,
				AttackPower = 1, ArmorPenetration = E, Crit = 1.1, SpellCrit = E, Hit = 1.75, SpellHit = E,
				Expertise = 1.85, Versatility = 0.8, Multistrike = 1, Mastery = 1.5, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 0.33, DamageSpellProc = E, MeleeProc = 0.33, RangedProc = E,
				DPS = 3.075
			},
			["Subtlety"] = {
				weapons = "dagger and any",
				Strength = 0.3, Agility = 1.1, Stamina = 0.2, Intellect = E, Spirit = E,
				Armor = 0.001, Dodge = 0.1, Parry = 0.1, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 0.5, Mp5 = E,
				AttackPower = 0.4, ArmorPenetration = E, Crit = 1.1, SpellCrit = E, Hit = 0.6, SpellHit = E,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 0.9, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 0.33, DamageSpellProc = E, MeleeProc = 0.33, RangedProc = E,
				DPS = 2
			}
		},
		["SHAMAN"] = {
			["None"] = {
				Strength = E, Agility = 1, Stamina = 0.05, Intellect = 0.26, Spirit = 1,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = 1, SpellPenetration = 1, Haste = 1, Mp5 = E,
				AttackPower = 1, ArmorPenetration = 1, Crit = 1.11, SpellCrit = 1.11, Hit = 2.7, SpellHit = 2.7,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 1.62, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 0.33, DamageSpellProc = 0.33, MeleeProc = 0.33, RangedProc = E,
				DPS = 1.2, Damage = 0.8
			},
			["Elemental"] = {
				Strength = E, Agility = E, Stamina = 0.05, Intellect = 0.26, Spirit = 1,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = 0.6, SpellPenetration = 0.1, Haste = 0.9, Mp5 = E,
				AttackPower = E, ArmorPenetration = E, Crit = 0.9, SpellCrit = 0.9, Hit = E, SpellHit = E,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 0.33, DamageSpellProc = 0.33, MeleeProc = E, RangedProc = E,
				DPS = 0.13333, Damage = 0.06667
			},
			["Enhancement"] = {
				weapons = "dual wield",
				Strength = E, Agility = 1.05, Stamina = 0.1, Intellect = E, Spirit = 1,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 0.95, Mp5 = E,
				AttackPower = 1, ArmorPenetration = 0.4, Crit = 1, SpellCrit = 1, Hit = 0.8, SpellHit = 0.8,
				Expertise = 0.3, Versatility = 0.8, Multistrike = 0.95, Mastery = 1, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 0.33, DamageSpellProc = E, MeleeProc = 0.33, RangedProc = E,
				DPS = 1.2, Damage = 0.8
			},
			["Restoration"] = {
				Strength = E, Agility = E, Stamina = 0.05, Intellect = 0.26, Spirit = 1,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = 0.75, SpellPenetration = E, Haste = 0.6, Mp5 = E,
				AttackPower = E, ArmorPenetration = E, Crit = 0.4, SpellCrit = 0.4, Hit = E, SpellHit = E,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 0.55, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = 0.33, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 0.01
			}
		},
		["WARLOCK"] = {
			["None"] = {
				Strength = E, Agility = E, Stamina = 0.4, Intellect = 0.2, Spirit = 0.7,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = 1, SpellPenetration = 0.05, Haste = 2.32, Mp5 = E,
				AttackPower = E, ArmorPenetration = E, Crit = E, SpellCrit = 4, Hit = E, SpellHit = 7,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 1.24, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 0.33, DamageSpellProc = 0.33, MeleeProc = E, RangedProc = E,
				DPS = 0.01
			},
			["Affliction"] = {
				Strength = E, Agility = E, Stamina = 0.4, Intellect = 0.2, Spirit = 0.7,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = 1, SpellPenetration = 0.05, Haste = 2.32, Mp5 = 1.5,
				AttackPower = E, ArmorPenetration = E, Crit = E, SpellCrit = 4, Hit = E, SpellHit = 7,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 1.24, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 0.33, DamageSpellProc = 0.33, MeleeProc = E, RangedProc = E,
				DPS = 0.01
			},
			["Demonology"] = {
				Strength = E, Agility = E, Stamina = 0.4, Intellect = 0.2, Spirit = 0.7,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = 1, SpellPenetration = 0.05, Haste = 2.37, Mp5 = 1.5,
				AttackPower = E, ArmorPenetration = E, Crit = E, SpellCrit = 4, Hit = E, SpellHit = 7,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 2.57, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 0.33, DamageSpellProc = 0.33, MeleeProc = E, RangedProc = E,
				DPS = 0.01
			},
			["Destruction"] = {
				Strength = E, Agility = E, Stamina = 0.4, Intellect = 0.2, Spirit = 0.7,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = 1, SpellPenetration = 0.05, Haste = 2.08, Mp5 = 1.5,
				AttackPower = E, ArmorPenetration = E, Crit = E, SpellCrit = 6, Hit = E, SpellHit = 7,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 1.4, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 0.33, DamageSpellProc = 0.33, MeleeProc = E, RangedProc = E,
				DPS = 0.01
			}
		},
		["WARRIOR"] = {
			["None"] = {
				Strength = 2.02, Agility = 0.5, Stamina = 0.05, Intellect = E, Spirit = E,
				Armor = 0.001, Dodge = E, Parry = E, Block = 0.5, Defense = 4,
				SpellPower = E, SpellPenetration = E, Haste = 0.8, Mp5 = E,
				AttackPower = 0.88, ArmorPenetration = E, Crit = 1.34, SpellCrit = E, Hit = 2, SpellHit = E,
				Expertise = 1.46, Versatility = 0.8, Multistrike = 1, Mastery = 0.9, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 0.33, DamageSpellProc = E, MeleeProc = 0.33, RangedProc = E,
				DPS = 1.33333, Damage = 0.66667
			},
			["Arms"] = {
				weapons = "2h",
				Strength = 2.02, Agility = 0.5, Stamina = 0.05, Intellect = E, Spirit = E,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 0.8, Mp5 = E,
				AttackPower = 0.88, ArmorPenetration = E, Crit = 1.34, SpellCrit = E, Hit = 2, SpellHit = E,
				Expertise = 1.46, Versatility = 0.8, Multistrike = 1, Mastery = 0.9, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 0.33, DamageSpellProc = E, MeleeProc = 0.33, RangedProc = E,
				DPS = 1, Damage = 1
			},
			["Fury"] = {
				weapons = ((TOC_VERSION_CURRENT >= TOC_VERSION_WOTLK) and "2hDW" or "dual wield"),
				Strength = 2.98, Agility = 0.5, Stamina = 0.05, Intellect = E, Spirit = E,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 1.37, Mp5 = E,
				AttackPower = 1.36, ArmorPenetration = E, Crit = 1.98, SpellCrit = E, Hit = 2.47, SpellHit = E,
				Expertise = 2.47, Versatility = 0.8, Multistrike = 1, Mastery = 1.57, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 0.33, DamageSpellProc = E, MeleeProc = 0.33, RangedProc = E,
				DPS = 1.2, Damage = 0.8
			},
			["Protection"] = {
				weapons = "weapon and shield",
				Strength = 1.2, Agility = 0.5, Stamina = 1.5, Intellect = E, Spirit = E,
				Armor = 0.13, Dodge = 1, Parry = 1.03, Block = 0.5, Defense = 4,
				SpellPower = E, SpellPenetration = E, Haste = E, Mp5 = E,
				AttackPower = E, ArmorPenetration = E, Crit = 0.4, SpellCrit = E, Hit = 0.02, SpellHit = E,
				Expertise = 0.04, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 0.33, DamageSpellProc = E, MeleeProc = 0.33, RangedProc = E,
				DPS = 1.33333, Damage = 0.66667
			}
		}
	}
else
	TyGearDefaultWeights = {
		["DEATHKNIGHT"] = {
			["None"] = {
				Strength = 1.05, Agility = E, Stamina = 0.5, Intellect = E, Spirit = E,
				Armor = 1, Dodge = 0.5, Parry = 0.5, Block = E,
				SpellPower = E, SpellPenetration = E, Haste = 0.8, Mp5 = E,
				AttackPower = 1, ArmorPenetration = 0.005, Crit = 1, Hit = 0.15,
				Expertise = 0.3, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 2
			},
			["Blood"] = {
				weapons = "2h",
				Strength = 1.05, Agility = E, Stamina = 0.5, Intellect = E, Spirit = E,
				Armor = 1, Dodge = 0.5, Parry = 0.5, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 0.8, Mp5 = E,
				AttackPower = 1, ArmorPenetration = 0.005, Crit = 1, Hit = 0.15,
				Expertise = 0.3, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 2
			},
			["Frost"] = {
				weapons = "dual wield",
				Strength = 1.05, Agility = E, Stamina = 0.05, Intellect = E, Spirit = E,
				Armor = 1, Dodge = 0.5, Parry = 0.5, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 1.22, Mp5 = E,
				AttackPower = 1, ArmorPenetration = 0.005, Crit = 1, Hit = 0.15,
				Expertise = 0.3, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 2
			},
			["Unholy"] = {
				weapons = "2h",
				Strength = 1.05, Agility = E, Stamina = 0.05, Intellect = E, Spirit = E,
				Armor = 1, Dodge = 0.5, Parry = 0.5, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 0.8, Mp5 = E,
				AttackPower = 1, ArmorPenetration = 0.005, Crit = 1, Hit = 0.15,
				Expertise = 0.3, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 2
			}
		},
		["DEMONHUNTER"] = {
			["None"] = {
				Strength = E, Agility = 1.1, Stamina = 0.05, Intellect = E, Spirit = E,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 1.05, Mp5 = E,
				AttackPower = 1, ArmorPenetration = E, Crit = 1.1, Hit = 1.75,
				Expertise = 1.85, Versatility = 0.8, Multistrike = 1, Mastery = 1.5, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 1, DamageSpellProc = E, MeleeProc = 1, RangedProc = E,
				DPS = 3.075
			},
			["Havoc"] = {
				weapons = "dual wield",
				Strength = E, Agility = 1.1, Stamina = 0.05, Intellect = E, Spirit = E,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 1.05, Mp5 = E,
				AttackPower = 1, ArmorPenetration = E, Crit = 1.1, Hit = 1.75,
				Expertise = 1.85, Versatility = 0.8, Multistrike = 1, Mastery = 1.5, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 1, DamageSpellProc = E, MeleeProc = 1, RangedProc = E,
				DPS = 3.075
			},
			["Vengeance"] = {
				weapons = "dual wield",
				Strength = E, Agility = 1.05, Stamina = 1, Intellect = E, Spirit = E,
				Armor = 0.8, Dodge = 0.4, Parry = E, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 0.8, Mp5 = E,
				AttackPower = 1, ArmorPenetration = E, Crit = 1.1, Hit = 0.3,
				Expertise = 0.4, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 1, DamageSpellProc = E, MeleeProc = 1, RangedProc = E,
				DPS = 2
			},
			["Devourer"] = {
				weapons = "dual wield",
				Strength = E, Agility = E, Stamina = 0.05, Intellect = 1.05, Spirit = E,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = 1, SpellPenetration = E, Haste = 1.5, Mp5 = E,
				AttackPower = E, ArmorPenetration = E, Crit = 1.1, SpellCrit = 1.1, Hit = 1.75, SpellHit = 1.75,
				Expertise = 1.85, Versatility = 0.8, Multistrike = 1, Mastery = 1.5, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 1, DamageSpellProc = 0.9, MeleeProc = 1, RangedProc = E,
				DPS = E
			}
		},
		["DRUID"] = {
			["None"] = {
				Strength = E, Agility = E, Stamina = 0.05, Intellect = 1, Spirit = 0.5,
				Armor = 0.001, Dodge = E, Parry = E, Block = E,
				SpellPower = 0.5, SpellPenetration = E, Haste = 0.5, Mp5 = 0.05,
				AttackPower = E, ArmorPenetration = E, Crit = 0.9, Hit = 0.9,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 1.45, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = 1, DamageProc = 1, DamageSpellProc = 1, MeleeProc = E, RangedProc = E,
				DPS = 1
			},
			["Balance"] = {
				Strength = E, Agility = E, Stamina = 0.05, Intellect = 1, Spirit = 0.1,
				Armor = 0.001, Dodge = E, Parry = E, Block = E,
				SpellPower = 0.8, SpellPenetration = 0.1, Haste = 0.8, Mp5 = 0.01,
				AttackPower = E, ArmorPenetration = E, Crit = 0.4, Hit = 0.05,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 0.6, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 1.0, DamageSpellProc = 1.0, MeleeProc = E, RangedProc = E,
				DPS = 0.01
			},
			["Feral"] = {
				Strength = E, Agility = 1.05, Stamina = 1, Intellect = E, Spirit = E,
				Armor = 0.8, Dodge = 0.4, Parry = E, Block = E,
				SpellPower = E, SpellPenetration = E, Haste = 0.8, Mp5 = E,
				AttackPower = 1, ArmorPenetration = E, Crit = 1.1, Hit = 0.3,
				Expertise = 0.4, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 1, DamageSpellProc = E, MeleeProc = 1, RangedProc = E,
				DPS = 0.8
			},
			["Feral Combat"] = { -- Cataclysm Classic spec name
				Strength = E, Agility = 1.05, Stamina = 1, Intellect = E, Spirit = E,
				Armor = 0.8, Dodge = 0.4, Parry = E, Block = E,
				SpellPower = E, SpellPenetration = E, Haste = 0.8, Mp5 = E,
				AttackPower = 1, ArmorPenetration = E, Crit = 1.1, Hit = 0.3,
				Expertise = 0.4, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 1, DamageSpellProc = E, MeleeProc = 1, RangedProc = E,
				DPS = 0.8
			},
			["Guardian"] = {
				Strength = E, Agility = 1.05, Stamina = 1, Intellect = E, Spirit = E,
				Armor = 0.8, Dodge = 0.4, Parry = E, Block = E,
				SpellPower = E, SpellPenetration = E, Haste = 0.8, Mp5 = E,
				AttackPower = 1, ArmorPenetration = E, Crit = 1.1, Hit = 0.3,
				Expertise = 0.4, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 1, DamageSpellProc = E, MeleeProc = 1, RangedProc = E,
				DPS = 0.8
			},
			["Restoration"] = {
				Strength = E, Agility = E, Stamina = 0.05, Intellect = 1, Spirit = 0.60,
				Armor = 0.001, Dodge = E, Parry = E, Block = E,
				SpellPower = 0.85, SpellPenetration = E, Haste = 0.8, Mp5 = 0.05,
				AttackPower = E, ArmorPenetration = E, Crit = 0.6, Hit = E,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 0.65, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = 1, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 0.01
			}
		},
		["EVOKER"] = {
			["None"] = {
				Strength = E, Agility = E, Stamina = E, Intellect = 4.14, Spirit = E,
				Armor = E, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 3.47, Mp5 = E,
				AttackPower = E, ArmorPenetration = E, Crit = 2.65, Hit = E,
				Expertise = E, Versatility = 2.89, Multistrike = E, Mastery = 0.24, ExperienceGained = E,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = E
			},
			["Devastation"] = {
				Strength = E, Agility = E, Stamina = E, Intellect = 4.14, Spirit = E,
				Armor = E, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 3.47, Mp5 = E,
				AttackPower = E, ArmorPenetration = E, Crit = 2.65, Hit = E,
				Expertise = E, Versatility = 2.89, Multistrike = E, Mastery = 0.24, ExperienceGained = E,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = E
			},
			["Preservation"] = {
				Strength = E, Agility = E, Stamina = E, Intellect = 4.14, Spirit = E,
				Armor = E, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 3.47, Mp5 = E,
				AttackPower = E, ArmorPenetration = E, Crit = 2.65, Hit = E,
				Expertise = E, Versatility = 2.89, Multistrike = E, Mastery = 0.24, ExperienceGained = E,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = E
			},
			["Augmentation"] = {
				Strength = E, Agility = E, Stamina = E, Intellect = 4.14, Spirit = E,
				Armor = E, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 3.47, Mp5 = E,
				AttackPower = E, ArmorPenetration = E, Crit = 2.65, Hit = E,
				Expertise = E, Versatility = 2.89, Multistrike = E, Mastery = 0.24, ExperienceGained = E,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = E
			}
		},
		["HUNTER"] = {
			["None"] = {
				weapons = "ranged",
				Strength = 0.5, Agility = 1.05, Stamina = 0.1, Intellect = E, Spirit = E,
				Armor = 0.0001, Dodge = E, Parry = E, Block = E,
				SpellPower = E, SpellPenetration = E, Haste = 0.8, Mp5 = E,
				AttackPower = 1, ArmorPenetration = 0.8, Crit = 0.8, Hit = 0.4,
				Expertise = 0.1, Versatility = 0.8, Multistrike = 1, Mastery = E, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 1.0, DamageSpellProc = E, MeleeProc = E, RangedProc = 1,
				DPS = 2
			},
			["Beast Mastery"] = {
				weapons = "ranged",
				Strength = 0.5, Agility = 1.05, Stamina = 0.1, Intellect = E, Spirit = E,
				Armor = 0.0001, Dodge = E, Parry = E, Block = E,
				SpellPower = E, SpellPenetration = E, Haste = 0.9, Mp5 = E,
				AttackPower = 1, ArmorPenetration = 0.8, Crit = 1.1, Hit = 0.4,
				Expertise = 0.1, Versatility = 0.8, Multistrike = 1, Mastery = 1.5, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 1.0, DamageSpellProc = E, MeleeProc = E, RangedProc = 1,
				DPS = 2
			},
			["Marksmanship"] = {
				weapons = "ranged",
				Strength = E, Agility = 1.05, Stamina = 0.05, Intellect = E, Spirit = E,
				Armor = 0.005, Dodge = E, Parry = E, Block = E,
				SpellPower = E, SpellPenetration = E, Haste = 1.61, Mp5 = E,
				AttackPower = 1, ArmorPenetration = E, Crit = 1.66, Hit = 3.49,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 1.38, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 1, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 2
			},
			["Survival"] = {
				Strength = E, Agility = 1.05, Stamina = 0.05, Intellect = E, Spirit = E,
				Armor = 0.005, Dodge = E, Parry = E, Block = E,
				SpellPower = E, SpellPenetration = E, Haste = 1.33, Mp5 = E,
				AttackPower = 1, ArmorPenetration = E, Crit = 1.37, Hit = 3.19,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 1.27, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 2
			}
		},
		["MAGE"] = {
			["None"] = {
				Strength = E, Agility = E, Stamina = 0.05, Intellect = 5.16, Spirit = 0.05,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = 2.8, SpellPenetration = 0.005, Haste = 1.28, Mp5 = .005,
				AttackPower = E, ArmorPenetration = E, Crit = 1.34, Hit = 3.21,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 1.4, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 0.01
			},
			["Arcane"] = {
				Strength = E, Agility = E, Stamina = 0.01, Intellect = 1, Spirit = E,
				Armor = 0.0001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = 0.6, SpellPenetration = 0.2, Haste = 0.5, Mp5 = E,
				AttackPower = E, ArmorPenetration = E, Crit = 0.9, Hit = 0.7,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 0.9, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 1, DamageSpellProc = 1, MeleeProc = E, RangedProc = E,
				DPS = 0.01
			},
			["Fire"] = {
				Strength = E, Agility = E, Stamina = 0.05, Intellect = 1, Spirit = 0.05,
				Armor = 0.0001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = 0.8, SpellPenetration = E, Haste = 0.8, Mp5 = E,
				AttackPower = E, ArmorPenetration = E, Crit = 1.2, Hit = E,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 0.9, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 1, DamageSpellProc = 1, MeleeProc = E, RangedProc = E,
				DPS = 0.01
			},
			["Frost"] = {
				Strength = E, Agility = E, Stamina = 0.05, Intellect = 1, Spirit = 0.05,
				Armor = 0.0001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = 0.9, SpellPenetration = 0.3, Haste = 0.8, Mp5 = E,
				AttackPower = E, ArmorPenetration = E, Crit = 0.8, Hit = 0.7,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 0.9, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 1, DamageSpellProc = 1, MeleeProc = E, RangedProc = E,
				DPS = 0.01
			}
		},
		["MONK"] = {
			["None"] = {
				Strength = E, Agility = 1.1, Stamina = 0.05, Intellect = E, Spirit = E,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 1.05, Mp5 = E,
				AttackPower = 1, ArmorPenetration = E, Crit = 1.1, Hit = 1.75,
				Expertise = 1.85, Versatility = 0.8, Multistrike = 1, Mastery = 1.5, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 1, DamageSpellProc = E, MeleeProc = 1, RangedProc = E,
				DPS = 3.075
			},
			["Brewmaster"] = {
				weapons = "2h",
				Strength = E, Agility = 1.05, Stamina = 1, Intellect = E, Spirit = E,
				Armor = 0.8, Dodge = 0.4, Parry = E, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 0.8, Mp5 = E,
				AttackPower = 1, ArmorPenetration = E, Crit = 1.1, Hit = 0.3,
				Expertise = 0.4, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 1, DamageSpellProc = E, MeleeProc = 1, RangedProc = E,
				DPS = 2
			},
			["Windwalker"] = {
				weapons = "dual wield",
				Strength = E, Agility = 1.1, Stamina = 0.05, Intellect = E, Spirit = E,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 1.05, Mp5 = E,
				AttackPower = 1, ArmorPenetration = E, Crit = 1.1, Hit = 1.75,
				Expertise = 1.85, Versatility = 0.8, Multistrike = 1, Mastery = 1.5, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 1, DamageSpellProc = E, MeleeProc = 1, RangedProc = E,
				DPS = 3.075
			},
			["Mistweaver"] = {
				Strength = E, Agility = E, Stamina = 0.05, Intellect = 1, Spirit = 0.60,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = 0.85, SpellPenetration = E, Haste = 0.8, Mp5 = 0.05,
				AttackPower = E, ArmorPenetration = E, Crit = 0.6, Hit = E,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 0.65, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = 1, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 1
			}
		},
		["PALADIN"] = {
			["None"] = {
				Strength = 2.33, Agility = E, Stamina = 0.05, Intellect = E, Spirit = E,
				Armor = 0.001, Dodge = E, Parry = E, Block = E,
				SpellPower = E, SpellPenetration = E, Haste = 0.79, Mp5 = E,
				AttackPower = 1, ArmorPenetration = E, Crit = 0.98, Hit = 1.77,
				Expertise = 1.3, Versatility = 0.8, Multistrike = 1, Mastery = 1.13, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 2
			},
			["Holy"] = {
				Strength = E, Agility = E, Stamina = 0.05, Intellect = 0.8, Spirit = 0.9,
				Armor = 0.001, Dodge = E, Parry = E, Block = E,
				SpellPower = 0.7, SpellPenetration = E, Haste = 0.8, Mp5 = E,
				AttackPower = E, ArmorPenetration = E, Crit = 1, Hit = E,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 0.3, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = 1, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 0.01
			},
			["Protection"] = {
				weapons = "weapon and shield",
				Strength = 1, Agility = 0.3, Stamina = 0.65, Intellect = 0.05, Spirit = E,
				Armor = 0.05, Dodge = 0.8, Parry = 0.75, Block = 0.8, SpellPower = 0.05,
				AttackPower = 0.4, Haste = 0.5, ArmorPenetration = 0.1,
				Crit = 0.25, Hit = E, Expertise = 0.2, Versatility = 0.8, Multistrike = 1, Mastery = 0.05, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				MeleeProc = 1.0, SpellProc = 0.5, DamageProc = 1.0,
				DPS = 2
			},
			["Retribution"] = {
				weapons = "2h",
				Strength = 2.33, Agility = E, Stamina = 0.05, Intellect = E, Spirit = E,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 0.79, Mp5 = E,
				AttackPower = 1, ArmorPenetration = E, Crit = 0.98, Hit = 1.77,
				Expertise = 1.3, Versatility = 0.8, Multistrike = 1, Mastery = 1.13, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 2
			}
		},
		["PRIEST"] = {
			["None"] = {
				Strength = E, Agility = E, Stamina = 0.05, Intellect = 1, Spirit = 1,
				Armor = 0.001, Dodge = E, Parry = E, Block = E,
				SpellPower = 2.75, SpellPenetration = E, Haste = 2, Mp5 = E,
				AttackPower = E, ArmorPenetration = E, Crit = 1.6, Hit = 1.95,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 1.7, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 0.01
			},
			["Discipline"] = {
				Strength = E, Agility = E, Stamina = E, Intellect = 1, Spirit = 1,
				Armor = 0.0001, Dodge = E, Parry = E, Block = E,
				SpellPower = 0.8, SpellPenetration = E, Haste = 1, Mp5 = E,
				AttackPower = E, ArmorPenetration = E, Crit = 0.25, Hit = E,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 0.5, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = 1.0, DamageProc = 0.5, DamageSpellProc = 0.5, MeleeProc = E, RangedProc = E,
				DPS = 0.01
			},
			["Holy"] = {
				Strength = E, Agility = E, Stamina = 0.05, Intellect = 1, Spirit = 1,
				Armor = 0.001, Dodge = E, Parry = E, Block = E,
				SpellPower = 1, SpellPenetration = E, Haste = 0.47, Mp5 = E,
				AttackPower = E, ArmorPenetration = E, Crit = 0.47, Hit = E,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 0.36, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = 1, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 0.01
			},
			["Shadow"] = {
				Strength = E, Agility = E, Stamina = 0.05, Intellect = 1, Spirit = 0.1,
				Armor = 0.001, Dodge = E, Parry = E, Block = E,
				SpellPower = 1, SpellPenetration = E, Haste = 1, Mp5 = E,
				AttackPower = E, ArmorPenetration = E, Crit = 1, Hit = E,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 0.01
			}
		},
		["ROGUE"] = {
			["None"] = {
				weapons = "dual wield",
				Strength = E, Agility = 1.1, Stamina = 0.05, Intellect = E, Spirit = E,
				Armor = 0.001, Dodge = E, Parry = E, Block = E,
				SpellPower = E, SpellPenetration = E, Haste = 1.05, Mp5 = E,
				AttackPower = 1, ArmorPenetration = E, Crit = 1.1, Hit = 1.75,
				Expertise = 1.85, Versatility = 0.8, Multistrike = 1, Mastery = 1.5, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 3.075
			},
			["Assassination"] = {
				weapons = "dagger",
				Strength = E, Agility = 1.1, Stamina = 0.05, Intellect = E, Spirit = E,
				Armor = 0.001, Dodge = E, Parry = E, Block = E,
				SpellPower = E, SpellPenetration = E, Haste = 1.05, Mp5 = E,
				AttackPower = 1, ArmorPenetration = E, Crit = 1.1, Hit = 1.75,
				Expertise = 1.1, Versatility = 0.8, Multistrike = 1, Mastery = 1.3, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 2
			},
			["Outlaw"] = {
				weapons = "dual wield",
				Strength = E, Agility = 1.1, Stamina = 0.05, Intellect = E, Spirit = E,
				Armor = 0.001, Dodge = E, Parry = E, Block = E,
				SpellPower = E, SpellPenetration = E, Haste = 1.05, Mp5 = E,
				AttackPower = 1, ArmorPenetration = E, Crit = 1.1, Hit = 1.75,
				Expertise = 1.85, Versatility = 0.8, Multistrike = 1, Mastery = 1.5, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 3.075
			},
			["Combat"] = {
				weapons = "dual wield",
				Strength = E, Agility = 1.1, Stamina = 0.05, Intellect = E, Spirit = E,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 1.05, Mp5 = E,
				AttackPower = 1, ArmorPenetration = E, Crit = 1.1, Hit = 1.75,
				Expertise = 1.85, Versatility = 0.8, Multistrike = 1, Mastery = 1.5, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 3.075
			},
			["Subtlety"] = {
				weapons = "dagger and any",
				Strength = 0.3, Agility = 1.1, Stamina = 0.2, Intellect = E, Spirit = E,
				Armor = 0.001, Dodge = 0.1, Parry = 0.1, Block = E,
				SpellPower = E, SpellPenetration = E, Haste = 0.5, Mp5 = E,
				AttackPower = 0.4, ArmorPenetration = E, Crit = 1.1, Hit = 0.6,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 0.9, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 1, DamageSpellProc = E, MeleeProc = 1, RangedProc = E,
				DPS = 2
			}
		},
		["SHAMAN"] = {
			["None"] = {
				Strength = E, Agility = 1, Stamina = 0.05, Intellect = 1, Spirit = E,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = 1, SpellPenetration = 1, Haste = 1, Mp5 = E,
				AttackPower = 1, ArmorPenetration = 1, Crit = 1.11, Hit = 2.7,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 1.62, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 2
			},
			["Elemental"] = {
				Strength = E, Agility = E, Stamina = 0.05, Intellect = 1, Spirit = 1,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = 0.6, SpellPenetration = 0.1, Haste = 0.9, Mp5 = E,
				AttackPower = E, ArmorPenetration = E, Crit = 0.9, Hit = E,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 1, DamageSpellProc = 1, MeleeProc = E, RangedProc = E,
				DPS = 2
			},
			["Enhancement"] = {
				weapons = "dual wield",
				Strength = E, Agility = 1.05, Stamina = 0.1, Intellect = E, Spirit = E,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 0.95, Mp5 = E,
				AttackPower = 1, ArmorPenetration = 0.4, Crit = 1, Hit = 0.8,
				Expertise = 0.3, Versatility = 0.8, Multistrike = 0.95, Mastery = 1, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = 1, DamageSpellProc = E, MeleeProc = 1, RangedProc = E,
				DPS = 2
			},
			["Restoration"] = {
				Strength = E, Agility = E, Stamina = 0.05, Intellect = 1, Spirit = 0.65,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = 0.75, SpellPenetration = E, Haste = 0.6, Mp5 = E,
				AttackPower = E, ArmorPenetration = E, Crit = 0.4, Hit = E,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 0.55, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 0.01
			}
		},
		["WARLOCK"] = {
			["None"] = {
				Strength = E, Agility = E, Stamina = 0.05, Intellect = 3.68, Spirit = 0.005,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = 2.81, SpellPenetration = 0.05, Haste = 2.32, Mp5 = E,
				AttackPower = E, ArmorPenetration = E, Crit = 1.79, Hit = 2.78,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 1.24, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 0.01
			},
			["Affliction"] = {
				Strength = E, Agility = E, Stamina = 0.05, Intellect = 3.68, Spirit = 0.005,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = 2.81, SpellPenetration = 0.05, Haste = 2.32, Mp5 = E,
				AttackPower = E, ArmorPenetration = E, Crit = 1.79, Hit = 2.78,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 1.24, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 0.01
			},
			["Demonology"] = {
				Strength = E, Agility = E, Stamina = 0.05, Intellect = 3.79, Spirit = 0.005,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = 2.91, SpellPenetration = 0.05, Haste = 2.37, Mp5 = E,
				AttackPower = E, ArmorPenetration = E, Crit = 1.95, Hit = 3.74,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 2.57, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 0.01
			},
			["Destruction"] = {
				Strength = E, Agility = E, Stamina = 0.05, Intellect = 3.3, Spirit = 0.005,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = 2.62, SpellPenetration = 0.05, Haste = 2.08, Mp5 = E,
				AttackPower = E, ArmorPenetration = E, Crit = 1.4, Hit = 2.83,
				Expertise = E, Versatility = 0.8, Multistrike = 1, Mastery = 1.4, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 0.01
			}
		},
		["WARRIOR"] = {
			["None"] = {
				Strength = 2.02, Agility = E, Stamina = 0.05, Intellect = E, Spirit = E,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 0.8, Mp5 = E,
				AttackPower = 0.88, ArmorPenetration = E, Crit = 1.34, Hit = 2,
				Expertise = 1.46, Versatility = 0.8, Multistrike = 1, Mastery = 0.9, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 2
			},
			["Arms"] = {
				weapons = "2h",
				Strength = 2.02, Agility = E, Stamina = 0.05, Intellect = E, Spirit = E,
				Armor = 0.001, Dodge = E, Parry = E, Block = E, Defense = E,
				SpellPower = E, SpellPenetration = E, Haste = 0.8, Mp5 = E,
				AttackPower = 0.88, ArmorPenetration = E, Crit = 1.34, Hit = 2,
				Expertise = 1.46, Versatility = 0.8, Multistrike = 1, Mastery = 0.9, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 2
			},
			["Fury"] = {
				weapons = "2hDW",
				Strength = 2.98, Agility = E, Stamina = 0.05, Intellect = E, Spirit = E,
				Armor = 0.001, Dodge = E, Parry = E, Block = E,
				SpellPower = E, SpellPenetration = E, Haste = 1.37, Mp5 = E,
				AttackPower = 1.36, ArmorPenetration = E, Crit = 1.98, Hit = 2.47,
				Expertise = 2.47, Versatility = 0.8, Multistrike = 1, Mastery = 1.57, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 2
			},
			["Protection"] = {
				weapons = "weapon and shield",
				Strength = 1.2, Agility = E, Stamina = 1.5, Intellect = E, Spirit = E,
				Armor = 0.16, Dodge = 1, Parry = 1.03, Block = E,
				SpellPower = E, SpellPenetration = E, Haste = E, Mp5 = E,
				AttackPower = E, ArmorPenetration = E, Crit = 0.4, Hit = 0.02,
				Expertise = 0.04, Versatility = 0.8, Multistrike = 1, Mastery = 1, ExperienceGained = 100,
				RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
				HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
				DPS = 2
			}
		}
	}
end

TyGearOverrideSpecs = {
	{
		["label"] = TyGearClassList["DEATHKNIGHT"],
		["subLabels"] = {"None", "Blood", "Frost", "Unholy"}
	},
	{
		["label"] = TyGearClassList["DEMONHUNTER"],
		["subLabels"] = {"None", "Havoc", "Vengeance", "Devourer"}
	},
	{
		["label"] = TyGearClassList["DRUID"],
		["subLabels"] = {"None", "Balance", "Feral", "Guardian", "Restoration"}
	},
	{
		["label"] = TyGearClassList["EVOKER"],
		["subLabels"] = {"None", "Devastation", "Preservation", "Augmentation"}
	},
	{
		["label"] = TyGearClassList["HUNTER"],
		["subLabels"] = {"None", "Beast Mastery", "Marksmanship", "Survival"}
	},
	{
		["label"] = TyGearClassList["MAGE"],
		["subLabels"] = {"None", "Arcane", "Fire", "Frost"}
	},
	{
		["label"] = TyGearClassList["MONK"],
		["subLabels"] = {"None", "Brewmaster", "Mistweaver", "Windwalker"}
	},
	{
		["label"] = TyGearClassList["PALADIN"],
		["subLabels"] = {"None", "Holy", "Protection", "Retribution"}
	},
	{
		["label"] = TyGearClassList["PRIEST"],
		["subLabels"] = {"None", "Discipline", "Holy", "Shadow"}
	},
	{
		["label"] = TyGearClassList["ROGUE"],
		["subLabels"] = {"None", "Assassination", "Combat", "Outlaw", "Subtlety"}
	},
	{
		["label"] = TyGearClassList["SHAMAN"],
		["subLabels"] = {"None", "Enhancement", "Elemental", "Restoration"}
	},
	{
		["label"] = TyGearClassList["WARLOCK"],
		["subLabels"] = {"None", "Affliction", "Demonology", "Destruction"}
	},
	{
		["label"] = TyGearClassList["WARRIOR"],
		["subLabels"] = {"None", "Arms", "Fury", "Protection"}
	}
}

-- Specs with a color of their own. Specs not listed here use their class color.
-- Chosen only where the spec has a clear identity, such as Frost mage being blue.
TyGearSpecColors = {
	["DEATHKNIGHT"] = {
		["Blood"] = {0.80, 0.08, 0.08},
		["Frost"] = {0.40, 0.75, 1.00},
		["Unholy"] = {0.35, 0.85, 0.25},
	},
	["DRUID"] = {
		["Balance"] = {0.68, 0.48, 1.00},
		["Guardian"] = {0.72, 0.52, 0.28},
		["Restoration"] = {0.25, 0.85, 0.40},
	},
	["EVOKER"] = {
		["Devastation"] = {0.92, 0.28, 0.24},
		["Preservation"] = {0.30, 0.82, 0.40},
		["Augmentation"] = {0.85, 0.60, 0.28},
	},
	["MAGE"] = {
		["Arcane"] = {0.75, 0.42, 1.00},
		["Fire"] = {1.00, 0.38, 0.10},
		["Frost"] = {0.30, 0.62, 1.00},
	},
	["MONK"] = {
		["Brewmaster"] = {0.90, 0.60, 0.20},
		["Mistweaver"] = {0.35, 0.85, 0.75},
	},
	["PALADIN"] = {
		["Holy"] = {1.00, 0.86, 0.30},
	},
	["PRIEST"] = {
		["Holy"] = {1.00, 0.86, 0.30},
		["Shadow"] = {0.62, 0.38, 0.95},
	},
	["ROGUE"] = {
		["Assassination"] = {0.25, 0.78, 0.30},
		["Subtlety"] = {0.55, 0.40, 0.95},
	},
	["SHAMAN"] = {
		["Restoration"] = {0.25, 0.80, 0.65},
	},
	["WARLOCK"] = {
		["Demonology"] = {0.30, 0.85, 0.22},
		["Destruction"] = {1.00, 0.38, 0.10},
	},
}

-- These classes are not playable on WoW Forever, so they stay out of the override spec list there.
local TyGearClassesHiddenOnForever = {
	["DEATHKNIGHT"] = true,
	["DEMONHUNTER"] = true,
	["EVOKER"] = true,
	["MONK"] = true,
}

-- Spec names that are not Forever talent trees (modern renames or later splits).
-- Weights stay in TyGearDefaultWeights for other clients and legacy saved overrides.
local TyGearSpecsHiddenOnForever = {
	["DRUID"] = {
		["Feral"] = true, -- Forever tree is "Feral Combat"
		["Guardian"] = true, -- bear tank is still Feral Combat
	},
	["ROGUE"] = {
		["Outlaw"] = true, -- Forever tree is "Combat"
	},
}

-- Weapon subclasses each Forever class can learn (including skills not yet trained).
-- Untrained-but-learnable weapons still get tooltip scores; class-incompatible ones are skipped.
-- Built lazily so Enum.ItemWeaponSubclass is available when first needed.
local TyGearForeverClassWeapons
local TyGearForeverKnownWeaponSubclasses

local function TyGearAddForeverWeapon(allowed, known, subclassID)
	if not subclassID then return end
	allowed[subclassID] = true
	known[subclassID] = true
end

local function TyGearEnsureForeverWeaponTables()
	if TyGearForeverClassWeapons then return true end
	local W = Enum and Enum.ItemWeaponSubclass
	if not W then return false end
	-- Fist weapons use Unarmed in the item subclass enum
	local fist = W.Unarmed or W.FistWeapon
	local known = {}
	local function weapons(...)
		local allowed = {}
		for i = 1, select("#", ...) do
			TyGearAddForeverWeapon(allowed, known, select(i, ...))
		end
		return allowed
	end
	TyGearForeverClassWeapons = {
		["DRUID"] = weapons(W.Dagger, fist, W.Mace1H, W.Polearm, W.Staff, W.Mace2H),
		["HUNTER"] = weapons(W.Bows, W.Crossbow, W.Dagger, fist, W.Guns, W.Axe1H, W.Sword1H, W.Polearm, W.Staff, W.Thrown, W.Axe2H, W.Sword2H),
		["MAGE"] = weapons(W.Dagger, W.Sword1H, W.Staff, W.Wand),
		["PALADIN"] = weapons(W.Axe1H, W.Mace1H, W.Sword1H, W.Polearm, W.Axe2H, W.Mace2H, W.Sword2H),
		["PRIEST"] = weapons(W.Dagger, W.Mace1H, W.Staff, W.Wand),
		["ROGUE"] = weapons(W.Bows, W.Crossbow, W.Dagger, fist, W.Guns, W.Axe1H, W.Mace1H, W.Sword1H, W.Thrown),
		["SHAMAN"] = weapons(W.Dagger, fist, W.Axe1H, W.Mace1H, W.Staff, W.Axe2H, W.Mace2H),
		["WARLOCK"] = weapons(W.Dagger, W.Sword1H, W.Staff, W.Wand),
		["WARRIOR"] = weapons(W.Bows, W.Crossbow, W.Dagger, fist, W.Guns, W.Axe1H, W.Mace1H, W.Sword1H, W.Polearm, W.Staff, W.Thrown, W.Axe2H, W.Mace2H, W.Sword2H),
	}
	if W.Fishingpole then known[W.Fishingpole] = true end
	TyGearForeverKnownWeaponSubclasses = known
	return true
end

--true when this Forever class can learn the weapon subclass (trained or not).
--nil when the client/tables can't answer; false when the class can never use it.
--Fishing poles are usable by every class. Uses the real player class, not override weights.
function TyGearForeverClassCanUseWeapon(subclassID)
	if not IS_WOW_FOREVER or not subclassID then return nil end
	if not TyGearEnsureForeverWeaponTables() then return nil end
	local W = Enum.ItemWeaponSubclass
	if W.Fishingpole and subclassID == W.Fishingpole then return true end
	if not TyGearForeverKnownWeaponSubclasses[subclassID] then return nil end
	local class = UnitClassBase("player")
	local allowed = TyGearForeverClassWeapons[class]
	if not allowed then return nil end
	return allowed[subclassID] and true or false
end

local function TyGearWrapRGB(text, r, g, b)
	if CreateColor then
		return CreateColor(r, g, b):WrapTextInColorCode(text)
	end
	return string.format("|cff%02x%02x%02x%s|r", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5), text)
end

function TyGearClassColoredText(classToken, text)
	local color = RAID_CLASS_COLORS and classToken and RAID_CLASS_COLORS[classToken]
	if not (color and text) then return text end
	if color.WrapTextInColorCode then
		return color:WrapTextInColorCode(text)
	end
	if color.colorStr then
		return color.colorStr..text.."|r"
	end
	if color.r then
		return TyGearWrapRGB(text, color.r, color.g, color.b)
	end
	return text
end

function TyGearSpecColoredText(classToken, specName)
	local rgb = classToken and TyGearSpecColors[classToken] and TyGearSpecColors[classToken][specName]
	if rgb then
		return TyGearWrapRGB(specName, rgb[1], rgb[2], rgb[3])
	end
	return TyGearClassColoredText(classToken, specName)
end

-- Colors "Mage: Frost" for the closed dropdown. The saved value stays uncolored.
function TyGearColorizeSpecChoice(value)
	if type(value) ~= "string" then return value end
	local localizedClass, spec = string.match(value, "^(.-): (.+)$")
	if not (localizedClass and spec and TyGearReverseClassList) then return value end
	local classToken = TyGearReverseClassList[localizedClass]
	if not classToken then return value end
	return TyGearClassColoredText(classToken, localizedClass)..": "..TyGearSpecColoredText(classToken, spec)
end

function TyGearGetWeightSpecNames(className)
	local specs = {}
	if TyGearDefaultWeights[className] then
		for specName in pairs(TyGearDefaultWeights[className]) do
			specs[specName] = true
		end
	end
	if TyGearMythicSimWeights and TyGearMythicSimWeights[className] then
		for specName in pairs(TyGearMythicSimWeights[className]) do
			specs[specName] = true
		end
	end
	return specs
end

function TyGearGetOverrideSpecs()
	local classNames = {}
	for className in pairs(TyGearDefaultWeights) do
		classNames[className] = true
	end
	if TyGearMythicSimWeights then
		for className in pairs(TyGearMythicSimWeights) do
			classNames[className] = true
		end
	end
	local classOrder = {}
	for className in pairs(classNames) do
		if (not IS_WOW_FOREVER) or (not TyGearClassesHiddenOnForever[className]) then
			table.insert(classOrder, className)
		end
	end
	table.sort(classOrder)

	local overrideSpecs = {}
	for i = 1, #classOrder do
		local className = classOrder[i]
		local localizedClassName = TyGearClassList[className]
		if localizedClassName then
			local specOrder = {}
			local hiddenSpecs = IS_WOW_FOREVER and TyGearSpecsHiddenOnForever[className]
			for specName in pairs(TyGearGetWeightSpecNames(className)) do
				if not (hiddenSpecs and hiddenSpecs[specName]) then
					table.insert(specOrder, specName)
				end
			end
			table.sort(specOrder, function(a, b)
				if a == "None" then
					return true
				elseif b == "None" then
					return false
				else
					return a < b
				end
			end)
			table.insert(overrideSpecs, {
				["label"] = localizedClassName,
				["class"] = className,
				["subLabels"] = specOrder,
			})
		end
	end
	TyGearOverrideSpecs = overrideSpecs
	return TyGearOverrideSpecs
end

function TyGearGetClassAndSpec()
	local cacheKey = (TyGearCharDB and TyGearCharDB.Override and (TyGearCharDB.OverrideSpec or "1")) or "0"
	if TyGearClassSpecCacheKey == cacheKey and TyGearCachedClass then
		return TyGearCachedClassLocalized, TyGearCachedClass, TyGearCachedSpec, TyGearCachedClassID
	end
	local localizedClass, class, spec, classID

	-- Override가 켜져 있고 저장된 OverrideSpec 이 있으면 거기서 먼저 시도
	if TyGearCharDB.Override and TyGearCharDB.OverrideSpec then
		-- "죽음의 기사: Blood" / "악마사냥꾼: Havoc" 같은 형식 가정
		local overrideLocalizedClass, overrideSpec = string.match(TyGearCharDB.OverrideSpec, "(.+): ?(.+)")
		if overrideLocalizedClass and overrideSpec then
			-- 로컬 직업명 -> 영문 직업 토큰 (예: "악마사냥꾼" -> "DEMONHUNTER")
			local overrideClassToken = TyGearReverseClassList[overrideLocalizedClass]
			if overrideClassToken and TyGearReverseClassIDList[overrideClassToken] then
				localizedClass = overrideLocalizedClass
				class        = overrideClassToken
				spec         = overrideSpec
				classID      = TyGearReverseClassIDList[overrideClassToken].id
			end
		end
	end

	-- 위에서 제대로 못 구했으면 실제 캐릭 정보로 fallback
	if (localizedClass == nil) or (class == nil) or (spec == nil) or (classID == nil) then
		localizedClass, class, spec, classID = TyGearDetectClassAndSpec()
	end

	TyGearClassSpecCacheKey = cacheKey
	TyGearCachedClassLocalized, TyGearCachedClass, TyGearCachedSpec, TyGearCachedClassID = localizedClass, class, spec, classID
	return localizedClass, class, spec, classID
end


function TyGearDetectClassAndSpec()
	local localizedClass, class, spec, classID
	class, classID = UnitClassBase("player")
	localizedClass = TyGearClassIDList[classID].localizedName
	spec = TyGearDetectSpec()
	return localizedClass, class, spec, classID
end

TyGearStatWeightSystemMythicSim = "MythicSim"
TyGearStatWeightSystemPawn = "Pawn"
TyGearStatWeightSystemForeverLevelingBIS = "ForeverLevelingBIS"
TyGearStatWeightSystemPersonal = "Personal"
TyGearPersonalStatWeightsExportHeader = "TyGear Personal Stat Weights v1"
TyGearFLBOnChangedRegistered = false

-- Forever Leveling BiS API → TyGear weight-table keys. Missing FLB keys stay at E.
-- Weapon DPS/speed from GetWeights become TyGearCurrentWeighting.weapon; TyGear still scores items itself.
TyGearFLBStatKeyMap = {
	str = "Strength",
	agi = "Agility",
	sta = "Stamina",
	int = "Intellect",
	spi = "Spirit",
	exprtng = "Expertise",
	splpen = "SpellPenetration",
	defrtng = "Defense",
	block = "Block",
	manargn = "Mp5",
	critPct = "Crit",
	hitPct = "Hit",
	dodgePct = "Dodge",
	parryPct = "Parry",
}

TyGearFLBSpecKeyByClass = {
	WARRIOR = { Arms = "arms", Fury = "fury", Protection = "protection" },
	PALADIN = { Holy = "holy", Protection = "protection", Retribution = "retribution" },
	HUNTER = { ["Beast Mastery"] = "beastmastery", Marksmanship = "marksmanship", Survival = "survival" },
	ROGUE = { Assassination = "assassination", Combat = "combat", Subtlety = "subtlety" },
	PRIEST = { Discipline = "discipline", Holy = "holy", Shadow = "shadow" },
	SHAMAN = { Elemental = "elemental", Enhancement = "enhancement", Restoration = "restoration" },
	MAGE = { Arcane = "arcane", Fire = "fire", Frost = "frost" },
	WARLOCK = { Affliction = "affliction", Demonology = "demonology", Destruction = "destruction" },
	DRUID = {
		Balance = "balance",
		Feral = "feral",
		["Feral Combat"] = "feral",
		["Feral (Bear)"] = "bear",
		Guardian = "bear",
		Restoration = "restoration",
	},
}

TyGearFLBWeaponsBySetup = {
	twohand = "2h",
	dualwield = "dual wield",
	shield = "weapon and shield",
	held = "any",
	onehand = "any",
}

-- Editable EP weights. forever = false stays out of the Forever tab (those stats are not on gear there).
-- code is the short token used by the TG2 import/export string. localeKey reuses the lowercase tooltip word.
TyGearPersonalStatFields = {
	{ key = "Strength", code = "Str", label = "Strength", localeKey = "strength" },
	{ key = "Agility", code = "Agi", label = "Agility", localeKey = "agility" },
	{ key = "Stamina", code = "Sta", label = "Stamina", localeKey = "stamina" },
	{ key = "Intellect", code = "Int", label = "Intellect", localeKey = "intellect" },
	{ key = "Spirit", code = "Spi", label = "Spirit", localeKey = "spirit" },
	{ key = "Armor", code = "Arm", label = "Armor", localeKey = "armor" },
	{ key = "Dodge", code = "Dod", label = "Dodge" },
	{ key = "Parry", code = "Par", label = "Parry" },
	{ key = "Block", code = "Blk", label = "Block", localeKey = "block" },
	{ key = "Defense", code = "Def", label = "Defense" },
	{ key = "AttackPower", code = "AP", label = "Attack Power" },
	{ key = "SpellPower", code = "SP", label = "Spell Power" },
	{ key = "Crit", code = "Cri", label = "Crit" },
	{ key = "SpellCrit", code = "SC", label = "Spell Crit" },
	{ key = "Hit", code = "Hit", label = "Hit" },
	{ key = "SpellHit", code = "SH", label = "Spell Hit" },
	{ key = "Haste", code = "Has", label = "Haste" },
	{ key = "Expertise", code = "Exp", label = "Expertise" },
	{ key = "ArmorPenetration", code = "ArP", label = "Armor Penetration" },
	{ key = "SpellPenetration", code = "SpP", label = "Spell Penetration" },
	{ key = "Mp5", code = "Mp5", label = "Mana per 5" },
	{ key = "DPS", code = "DPS", label = "Weapon DPS" },
	{ key = "Damage", code = "Dmg", label = "Weapon Damage" },
	{ key = "HealingProc", code = "HP", label = "Healing Proc" },
	{ key = "DamageProc", code = "DP", label = "Damage Proc" },
	{ key = "DamageSpellProc", code = "DSP", label = "Spell Damage Proc" },
	{ key = "MeleeProc", code = "MP", label = "Melee Proc" },
	{ key = "RangedProc", code = "RP", label = "Ranged Proc" },
	{ key = "Mastery", code = "Mas", label = "Mastery", forever = false },
	{ key = "Versatility", code = "Ver", label = "Versatility", forever = false },
	{ key = "Multistrike", code = "MS", label = "Multistrike", forever = false },
	{ key = "RedSockets", code = "RS", label = "Red Socket", forever = false },
	{ key = "YellowSockets", code = "YS", label = "Yellow Socket", forever = false },
	{ key = "BlueSockets", code = "BS", label = "Blue Socket", forever = false },
	{ key = "MetaSockets", code = "Meta", label = "Meta Socket", forever = false },
	{ key = "ExperienceGained", code = "XP", label = "Experience Gained" },
}

function TyGearIsPawnReady()
	return (PawnIsReady ~= nil) and PawnIsReady()
end

-- Forever Leveling BiS API v2+ exposes GetWeights. TyGear only reads weights; scoring stays internal.
function TyGearIsForeverLevelingBISReady()
	local api = ForeverLevelingBiS_API
	return api ~= nil and (api.version or 1) >= 2 and type(api.GetWeights) == "function"
end

-- Gray label used when a dropdown choice exists but cannot be selected (e.g. Pawn not loaded).
function TyGearFadeDisabledOptionLabel(label)
	if type(label) ~= "string" then return label end
	if GRAY_FONT_COLOR and GRAY_FONT_COLOR.WrapTextInColorCode then
		return GRAY_FONT_COLOR:WrapTextInColorCode(label)
	end
	if GRAY_FONT_COLOR_CODE and FONT_COLOR_CODE_CLOSE then
		return GRAY_FONT_COLOR_CODE..label..FONT_COLOR_CODE_CLOSE
	end
	return "|cff808080"..label.."|r"
end

-- Stat weight system dropdown entries. Optional engines stay visible when unloaded, but faded and not selectable.
function TyGearGetStatWeightSystemDropdownOptions()
	local pawnReady = TyGearIsPawnReady()
	local pawnLabel = pawnReady and L["Pawn"] or TyGearFadeDisabledOptionLabel(L["Pawn (not loaded)"])
	local flbReady = TyGearIsForeverLevelingBISReady()
	local flbLabel = flbReady and L["Forever Leveling BiS"] or TyGearFadeDisabledOptionLabel(L["Forever Leveling BiS (not loaded)"])
	return {
		{ ["label"] = L["MythicSim"], ["value"] = TyGearStatWeightSystemMythicSim },
		{ ["label"] = pawnLabel, ["value"] = TyGearStatWeightSystemPawn, ["disabled"] = not pawnReady },
		{ ["label"] = flbLabel, ["value"] = TyGearStatWeightSystemForeverLevelingBIS, ["disabled"] = not flbReady },
		{ ["label"] = L["Personal Stat Weights"], ["value"] = TyGearStatWeightSystemPersonal },
	}
end

function TyGearGetStatWeightSystem()
	local system = TyGearDB and TyGearDB.StatWeightSystem
	if system == TyGearStatWeightSystemPawn
	or system == TyGearStatWeightSystemForeverLevelingBIS
	or system == TyGearStatWeightSystemPersonal then
		return system
	end
	return TyGearStatWeightSystemMythicSim
end

function TyGearSetStatWeightSystem(system)
	if not TyGearDB then return false end
	if system == TyGearStatWeightSystemPawn then
		if not TyGearIsPawnReady() then
			return false
		end
		TyGearDB.StatWeightSystem = TyGearStatWeightSystemPawn
		TyGearDB.UsePawn = true
	elseif system == TyGearStatWeightSystemForeverLevelingBIS then
		if not TyGearIsForeverLevelingBISReady() then
			return false
		end
		TyGearDB.StatWeightSystem = TyGearStatWeightSystemForeverLevelingBIS
		TyGearDB.UsePawn = false
		TyGearEnsureForeverLevelingBISOnChanged()
	elseif system == TyGearStatWeightSystemPersonal then
		TyGearDB.StatWeightSystem = TyGearStatWeightSystemPersonal
		TyGearDB.UsePawn = false
	else
		TyGearDB.StatWeightSystem = TyGearStatWeightSystemMythicSim
		TyGearDB.UsePawn = false
	end
	TyGearWeightingCacheKey = nil
	if TyGearSetStatWeights then TyGearSetStatWeights() end
	if TyGearUpdateBestItems then TyGearUpdateBestItems() end
	if TyGearRefreshPawnOptionsVisibility then TyGearRefreshPawnOptionsVisibility() end
	if TyGearRefreshPersonalStatWeightEditors then TyGearRefreshPersonalStatWeightEditors() end
	return true
end

-- Override Pawn scale (and its dropdown) only belong in the menu while Pawn is loaded and selected.
function TyGearRefreshPawnOptionsVisibility()
	local show = TyGearGetStatWeightSystem() == TyGearStatWeightSystemPawn and TyGearIsPawnReady()
	local check = _G["TyGearOverridePawnScaleCheckButton"]
	local dropDown = _G["TyGearPawnScaleDropdown"]
	-- Block rows own the checkbox; hide the whole row so Relayout can collapse the gap.
	local row = check and check:GetParent()
	if row and row.tyGearMeasure then
		row:SetShown(show)
	else
		if check then check:SetShown(show) end
		if dropDown then dropDown:SetShown(show) end
	end
	if TyGearOptionsPage and TyGearOptionsPage.Relayout then
		TyGearOptionsPage:Relayout()
	end
end

-- Older installs only had UsePawn. Prefer MythicSim unless the player had already enabled Pawn.
-- If an optional engine was saved but is not loaded, fall back to MythicSim.
function TyGearMigrateStatWeightSystem()
	if not TyGearDB then return end
	if TyGearDB.StatWeightSystem ~= TyGearStatWeightSystemMythicSim
	and TyGearDB.StatWeightSystem ~= TyGearStatWeightSystemPawn
	and TyGearDB.StatWeightSystem ~= TyGearStatWeightSystemForeverLevelingBIS
	and TyGearDB.StatWeightSystem ~= TyGearStatWeightSystemPersonal then
		if TyGearDB.UsePawn and TyGearIsPawnReady() then
			TyGearDB.StatWeightSystem = TyGearStatWeightSystemPawn
		else
			TyGearDB.StatWeightSystem = TyGearStatWeightSystemMythicSim
		end
	end
	if TyGearDB.StatWeightSystem == TyGearStatWeightSystemPawn and not TyGearIsPawnReady() then
		TyGearDB.StatWeightSystem = TyGearStatWeightSystemMythicSim
	end
	if TyGearDB.StatWeightSystem == TyGearStatWeightSystemForeverLevelingBIS and not TyGearIsForeverLevelingBISReady() then
		TyGearDB.StatWeightSystem = TyGearStatWeightSystemMythicSim
	end
	TyGearDB.UsePawn = (TyGearDB.StatWeightSystem == TyGearStatWeightSystemPawn)
end

function TyGearMapSpecToForeverLevelingBIS(class, spec)
	if not class or not spec or spec == "None" then return nil end
	local byClass = TyGearFLBSpecKeyByClass[class]
	return byClass and byClass[spec] or nil
end

-- Map Forever Leveling BiS GetWeights() into a TyGear weight table. Does not call ScoreItem/GetGain/IsUpgrade.
function TyGearConvertForeverLevelingBISWeights(weights, setup, flbSpec)
	if type(weights) ~= "table" then return nil end
	local function num(value)
		return tonumber(value) or 0
	end
	local out = {
		Strength = E, Agility = E, Stamina = E, Intellect = E, Spirit = E,
		Armor = E, Dodge = E, Parry = E, Block = E, Defense = E,
		SpellPower = E, SpellPenetration = E, Haste = E, Mp5 = E,
		AttackPower = E, ArmorPenetration = E, Crit = E, SpellCrit = E, Hit = E, SpellHit = E,
		Expertise = E, Versatility = E, Multistrike = E, Mastery = E, ExperienceGained = E,
		RedSockets = E, YellowSockets = E, BlueSockets = E, MetaSockets = E,
		HealingProc = E, DamageProc = E, DamageSpellProc = E, MeleeProc = E, RangedProc = E,
		DPS = E, Damage = E,
	}
	for flbKey, tyGearKey in pairs(TyGearFLBStatKeyMap) do
		local value = num(weights[flbKey])
		if value ~= 0 then
			out[tyGearKey] = value
		end
	end
	local armor = num(weights.armor) + num(weights.armorbonus)
	if armor ~= 0 then
		out.Armor = armor
	end
	if num(weights.block) == 0 and num(weights.blockPct) ~= 0 then
		out.Block = num(weights.blockPct)
	end
	out.AttackPower = math.max(num(weights.atkpwr), num(weights.rgdatkpwr), num(weights.feratkpwr))
	if out.AttackPower == 0 then out.AttackPower = E end
	out.SpellPower = math.max(
		num(weights.splpwr), num(weights.spldmg), num(weights.splheal),
		num(weights.arcsplpwr), num(weights.firsplpwr), num(weights.frosplpwr),
		num(weights.holsplpwr), num(weights.natsplpwr), num(weights.shasplpwr)
	)
	if out.SpellPower == 0 then out.SpellPower = E end

	out.weapons = (setup and TyGearFLBWeaponsBySetup[setup]) or "any"
	local dps = num(weights.dps)
	local ohDps = num(weights.ohDps)
	local rangedDps = num(weights.rangedDps)
	-- FLB speed weights are per 0.1s slower than the reference; TyGear multiplies by (speed - norm) in seconds.
	local speedBonus = num(weights.speed) * 10
	local rangedSpeedBonus = num(weights.rangedSpeed) * 10
	local speedRef = tonumber(weights.speedRef)
	local rangedSpeedRef = tonumber(weights.rangedSpeedRef) or 2.8

	if flbSpec == "feral" or flbSpec == "bear" then
		out.weapon = {
			feral = true,
			mh_dps = (dps > E) and dps or 0,
			oh_dps = 0,
		}
	elseif rangedDps > E and dps <= E then
		out.weapons = "ranged"
		out.weapon = {
			ranged = true,
			mh_dps = rangedDps,
			oh_dps = 0,
			norm_speed = rangedSpeedRef,
			speed_bonus = rangedSpeedBonus,
		}
	elseif dps > E or ohDps > E or speedBonus > E then
		local pref = out.weapons
		out.weapon = {
			mh_dps = dps,
			oh_dps = ohDps,
			norm_speed = speedRef or ((pref == "2h") and 3.3 or 2.4),
			speed_bonus = speedBonus,
		}
	else
		out.weapon = { mh_dps = 0, oh_dps = 0 }
	end
	-- Keep ranged DPS/speed even when melee weights drove the primary weapon table (rogue/warrior thrown, hunter with both).
	if out.weapon and (rangedDps > E or rangedSpeedBonus ~= 0) then
		out.weapon.ranged_dps = rangedDps
		out.weapon.ranged_norm_speed = rangedSpeedRef
		out.weapon.ranged_speed_bonus = rangedSpeedBonus
	end
	return out
end

function TyGearGetForeverLevelingBISWeighting(class, spec)
	if not TyGearIsForeverLevelingBISReady() then
		return nil, nil
	end
	local api = ForeverLevelingBiS_API
	local flbSpec = TyGearMapSpecToForeverLevelingBIS(class, spec)
	local setup
	local mainSpec, mainSetup, classFile
	if type(api.GetSpec) == "function" then
		mainSpec, mainSetup, classFile = api.GetSpec()
	end
	local weights
	if (not flbSpec) or spec == "None" then
		-- No TyGear talent tree yet: use the main spec/setup the player picked in Forever Leveling BiS.
		weights = api.GetWeights()
		flbSpec = mainSpec
		setup = mainSetup
	else
		if classFile == class and mainSpec then
			if mainSpec == flbSpec or (flbSpec == "survival" and mainSpec == "survivalmelee") then
				flbSpec = mainSpec
				setup = mainSetup
			end
		end
		weights = api.GetWeights(class, flbSpec, nil, setup)
	end
	local converted = TyGearConvertForeverLevelingBISWeights(weights, setup, flbSpec)
	if not converted then
		return nil, nil
	end
	return converted, TyGearStatWeightSystemForeverLevelingBIS
end

-- Refresh TyGear weights when Forever Leveling BiS changes its model, profile, or gear context.
function TyGearEnsureForeverLevelingBISOnChanged()
	if TyGearFLBOnChangedRegistered then return end
	local api = ForeverLevelingBiS_API
	if not (api and type(api.OnChanged) == "function") then return end
	TyGearFLBOnChangedRegistered = true
	api.OnChanged(function()
		if TyGearGetStatWeightSystem() ~= TyGearStatWeightSystemForeverLevelingBIS then
			return
		end
		TyGearWeightingCacheKey = nil
		if TyGearSetStatWeights then TyGearSetStatWeights() end
		if TyGearUpdateBestItems then TyGearUpdateBestItems() end
	end)
end

function TyGearPersonalStatFieldsForUI()
	local fields = {}
	for _, field in ipairs(TyGearPersonalStatFields) do
		if (not IS_WOW_FOREVER) or field.forever ~= false then
			table.insert(fields, field)
		end
	end
	return fields
end

function TyGearPersonalStatLabel(field)
	local named = L[field.label]
	if named ~= field.label then
		return named
	end
	if field.localeKey then
		local lower = L[field.localeKey]
		if lower ~= field.localeKey then
			local first = string.sub(lower, 1, 1)
			if string.byte(first) < 128 then
				return string.upper(first)..string.sub(lower, 2)
			end
			return lower
		end
	end
	return field.label
end

function TyGearFormatPersonalStatWeight(value)
	value = tonumber(value) or 0
	if math.abs(value) <= 0.0000005 then
		return "0"
	end
	local text = string.format("%.4f", value)
	text = string.gsub(text, "(%..-)0+$", "%1")
	text = string.gsub(text, "%.$", "")
	return text
end

-- Edit boxes created while the tab is hidden keep a bad scroll offset and look empty until clicked.
function TyGearSetPersonalWeightEditText(edit, value)
	if not edit or (edit.HasFocus and edit:HasFocus()) then return end
	edit:SetText(TyGearFormatPersonalStatWeight(value))
	if edit.SetCursorPosition then
		edit:SetCursorPosition(0)
	end
end

function TyGearNormalizePersonalStatWeight(value)
	value = tonumber(value)
	if not value or value ~= value or value == math.huge or value == -math.huge then
		return nil
	end
	-- MythicSim stores unused stats as a tiny epsilon. Treat that as zero in the editor.
	if math.abs(value) <= 0.000001 then
		return 0
	end
	return value
end

function TyGearPersonalWeightsRoot()
	if not TyGearDB then TyGearDB = {} end
	if type(TyGearDB.PersonalStatWeights) ~= "table" then
		TyGearDB.PersonalStatWeights = {}
	end
	return TyGearDB.PersonalStatWeights
end

function TyGearGetPersonalSpecNames(className)
	local names = {}
	if not className then return names end
	local hidden = IS_WOW_FOREVER and TyGearSpecsHiddenOnForever[className]
	for specName in pairs(TyGearGetWeightSpecNames(className)) do
		if not (hidden and hidden[specName]) then
			table.insert(names, specName)
		end
	end
	table.sort(names, function(a, b)
		if a == "None" then
			return true
		elseif b == "None" then
			return false
		end
		return a < b
	end)
	return names
end

function TyGearFindPersonalSpecName(className, text)
	if not className or type(text) ~= "string" then return nil end
	text = string.gsub(text, "^%s+", "")
	text = string.gsub(text, "%s+$", "")
	if text == "" then return nil end
	local wanted = string.lower(text)
	for _, specName in ipairs(TyGearGetPersonalSpecNames(className)) do
		if string.lower(specName) == wanted then
			return specName
		end
	end
	return nil
end

function TyGearFindPersonalStatKey(name)
	if type(name) ~= "string" then return nil end
	local wanted = string.lower(name)
	if wanted == "weapons" or wanted == "w" then
		return "weapons"
	end
	for _, field in ipairs(TyGearPersonalStatFields) do
		if string.lower(field.key) == wanted or (field.code and string.lower(field.code) == wanted) then
			return field.key
		end
	end
	return nil
end

function TyGearNormalizePersonalClassToken(text)
	if type(text) ~= "string" then return nil end
	text = string.gsub(text, "^%s+", "")
	text = string.gsub(text, "%s+$", "")
	text = string.gsub(text, "^\"", "")
	text = string.gsub(text, "\"$", "")
	if text == "" then return nil end
	local upper = string.upper(text)
	if TyGearClassList and TyGearClassList[upper] then
		return upper
	end
	if TyGearReverseClassList then
		if TyGearReverseClassList[text] then
			return TyGearReverseClassList[text]
		end
		for localized, token in pairs(TyGearReverseClassList) do
			if string.lower(localized) == string.lower(text) then
				return token
			end
		end
	end
	return nil
end

function TyGearNewPersonalSpecWeights(className, specName)
	local source = TyGearGetMythicSimWeighting(className, specName) or TyGearGetBuiltInWeighting(className, specName)
	local row = {}
	for _, field in ipairs(TyGearPersonalStatFields) do
		row[field.key] = TyGearNormalizePersonalStatWeight(source and source[field.key]) or 0
	end
	if source and type(source.weapons) == "string" and source.weapons ~= "" then
		row.weapons = source.weapons
	end
	return row
end

-- True when this saved spec has no real weight yet (missing, or every stat still 0 with no weapon preference).
function TyGearPersonalSpecRowIsBlank(row)
	if type(row) ~= "table" then return true end
	for _, field in ipairs(TyGearPersonalStatFields) do
		local value = tonumber(row[field.key])
		if value and math.abs(value) > 0.000001 then
			return false
		end
	end
	return not (type(row.weapons) == "string" and row.weapons ~= "")
end

function TyGearCopyMissingPersonalStatWeights(row, defaults)
	if type(row) ~= "table" or type(defaults) ~= "table" then return end
	for _, field in ipairs(TyGearPersonalStatFields) do
		if row[field.key] == nil then
			row[field.key] = defaults[field.key]
		end
	end
	if row.weapons == nil and type(defaults.weapons) == "string" and defaults.weapons ~= "" then
		row.weapons = defaults.weapons
	end
end

-- Saved rows from the first version could be empty. Fill those once from MythicSim.
-- A spec the player later sets entirely to 0 stays 0, because this does not run again.
function TyGearMigrateBlankPersonalWeights()
	if not TyGearDB or TyGearDB.PersonalStatWeightsBlankMigrated then return end
	local root = TyGearDB.PersonalStatWeights
	if type(root) == "table" then
		for className, classWeights in pairs(root) do
			if type(classWeights) == "table" and type(className) == "string" then
				for specName, row in pairs(classWeights) do
					if type(specName) == "string" and TyGearPersonalSpecRowIsBlank(row) then
						classWeights[specName] = TyGearNewPersonalSpecWeights(className, specName)
					elseif type(row) == "table" then
						TyGearCopyMissingPersonalStatWeights(row, TyGearNewPersonalSpecWeights(className, specName))
					end
				end
			end
		end
	end
	TyGearDB.PersonalStatWeightsBlankMigrated = true
end

-- Fill any missing spec for this class with its MythicSim weights (built-in profile when MythicSim has no row).
-- Existing edits are left alone. Missing stats inside an edited spec are filled from that same default.
function TyGearEnsurePersonalClassWeights(className)
	if not className or className == "" then return nil end
	TyGearMigrateBlankPersonalWeights()
	local root = TyGearPersonalWeightsRoot()
	local classWeights = root[className]
	if type(classWeights) ~= "table" then
		classWeights = {}
		root[className] = classWeights
	end
	for _, specName in ipairs(TyGearGetPersonalSpecNames(className)) do
		local defaults = TyGearNewPersonalSpecWeights(className, specName)
		local row = classWeights[specName]
		if type(row) ~= "table" then
			classWeights[specName] = defaults
		else
			TyGearCopyMissingPersonalStatWeights(row, defaults)
		end
	end
	return classWeights
end

function TyGearResetPersonalClassWeights(className)
	if not className or className == "" then return nil end
	local root = TyGearPersonalWeightsRoot()
	root[className] = nil
	local classWeights = TyGearEnsurePersonalClassWeights(className)
	TyGearWeightingCacheKey = nil
	if TyGearSetStatWeights then TyGearSetStatWeights() end
	if TyGearUpdateBestItems then TyGearUpdateBestItems() end
	if TyGearRefreshPersonalStatWeightEditors then TyGearRefreshPersonalStatWeightEditors() end
	return classWeights
end

function TyGearGetPersonalWeighting(className, specName)
	if not className or not specName or className == "" or specName == "" then
		return nil
	end
	local classWeights = TyGearEnsurePersonalClassWeights(className)
	return classWeights and classWeights[specName] or nil
end

-- Saved weights for this spec, or the MythicSim/built-in starting values when nothing is saved yet.
-- Reading does not write saved variables. Opening the tab stores any spec that is still missing.
function TyGearPeekPersonalSpecWeights(className, specName)
	local saved = TyGearDB and TyGearDB.PersonalStatWeights
		and TyGearDB.PersonalStatWeights[className]
		and TyGearDB.PersonalStatWeights[className][specName]
	if type(saved) == "table" then
		return saved
	end
	return TyGearNewPersonalSpecWeights(className, specName)
end

function TyGearSetPersonalStatWeight(className, specName, statKey, value)
	local row = TyGearGetPersonalWeighting(className, specName)
	if not row or not statKey then return end
	if statKey == "weapons" then
		if type(value) ~= "string" or value == "" or row.weapons == value then return end
		row.weapons = value
	else
		value = TyGearNormalizePersonalStatWeight(value)
		if value == nil or row[statKey] == value then return end
		row[statKey] = value
	end
	TyGearWeightingCacheKey = nil
	if TyGearSetStatWeights then TyGearSetStatWeights() end
	if TyGearUpdateBestItems then TyGearUpdateBestItems() end
end

-- TG2 is one line: the class, then only the stats that differ from that spec's MythicSim (or built-in) start.
-- TG2:MAGE@engine|Frost:Int=2,Has=-0.04|Fire:W=any
function TyGearPersonalStatWeightsDiffer(current, starting)
	return TyGearFormatPersonalStatWeight(current) ~= TyGearFormatPersonalStatWeight(starting)
end

function TyGearExportPersonalStatWeights(className)
	local classWeights = TyGearEnsurePersonalClassWeights(className)
	local header = "TG2:"..tostring(className)
	local engine = TyGearMythicSimMeta and TyGearMythicSimMeta.engine
	if type(engine) == "string" and engine ~= "" then
		header = header.."@"..engine
	end
	local parts = { header }
	for _, specName in ipairs(TyGearGetPersonalSpecNames(className)) do
		local row = classWeights and classWeights[specName]
		local base = TyGearNewPersonalSpecWeights(className, specName)
		local bits = {}
		for _, field in ipairs(TyGearPersonalStatFields) do
			local current = row and row[field.key] or 0
			local starting = base and base[field.key] or 0
			if TyGearPersonalStatWeightsDiffer(current, starting) then
				table.insert(bits, field.code.."="..TyGearFormatPersonalStatWeight(current))
			end
		end
		local currentWeapons = (row and row.weapons) or ""
		local baseWeapons = (base and base.weapons) or ""
		if currentWeapons ~= baseWeapons then
			table.insert(bits, "W="..currentWeapons)
		end
		if #bits > 0 then
			table.insert(parts, specName..":"..table.concat(bits, ","))
		end
	end
	return table.concat(parts, "|")
end

function TyGearImportPersonalStatWeightsV2(text, currentClass)
	local body = string.match(text, "^TG2:(.*)$")
	if not body or body == "" then
		return false, L["Could not find any specs in that text."]
	end
	local segments = {}
	for segment in string.gmatch(body, "[^|]+") do
		segment = string.gsub(segment, "^%s+", "")
		segment = string.gsub(segment, "%s+$", "")
		if segment ~= "" then
			table.insert(segments, segment)
		end
	end
	if #segments == 0 then
		return false, L["Could not find any specs in that text."]
	end
	local classText, engine = string.match(segments[1], "^([^@]+)@(.+)$")
	if not classText then
		classText = segments[1]
	end
	local parsedClass = TyGearNormalizePersonalClassToken(classText)
	if not parsedClass then
		return false, string.format(L["Unrecognized class in that export: %s"], classText)
	end
	if currentClass and parsedClass ~= currentClass then
		local parsedName = (TyGearClassList and TyGearClassList[parsedClass]) or parsedClass
		local currentName = (TyGearClassList and TyGearClassList[currentClass]) or currentClass
		return false, string.format(L["That export is for %s. This tab edits %s."], parsedName, currentName)
	end
	local parsed = {}
	local unknownSpecs = {}
	local badPairs = 0
	for index = 2, #segments do
		local specText, pairsText = string.match(segments[index], "^(.-):(.+)$")
		if not specText or specText == "" or not pairsText then
			badPairs = badPairs + 1
		else
			local specName = TyGearFindPersonalSpecName(parsedClass, specText)
			if not specName then
				table.insert(unknownSpecs, specText)
			else
				parsed[specName] = parsed[specName] or {}
				for pair in string.gmatch(pairsText, "[^,]+") do
					local code, valueText = string.match(pair, "^%s*([^=]+)%s*=%s*(.*)$")
					if not code then
						badPairs = badPairs + 1
					else
						local statKey = TyGearFindPersonalStatKey(code)
						if statKey == "weapons" then
							valueText = string.gsub(valueText or "", "^%s+", "")
							valueText = string.gsub(valueText, "%s+$", "")
							parsed[specName].weapons = valueText
						elseif statKey then
							local value = TyGearNormalizePersonalStatWeight(valueText)
							if value == nil then
								badPairs = badPairs + 1
							else
								parsed[specName][statKey] = value
							end
						else
							badPairs = badPairs + 1
						end
					end
				end
			end
		end
	end
	-- The string lists only changes, so start from MythicSim and then apply those changes.
	local root = TyGearPersonalWeightsRoot()
	local classWeights = {}
	root[parsedClass] = classWeights
	for _, specName in ipairs(TyGearGetPersonalSpecNames(parsedClass)) do
		local row = TyGearNewPersonalSpecWeights(parsedClass, specName)
		classWeights[specName] = row
		local incoming = parsed[specName]
		if incoming then
			for statKey, value in pairs(incoming) do
				if statKey == "weapons" then
					if value ~= "" then
						row.weapons = value
					else
						row.weapons = nil
					end
				else
					row[statKey] = value
				end
			end
		end
	end
	TyGearWeightingCacheKey = nil
	if TyGearSetStatWeights then TyGearSetStatWeights() end
	if TyGearUpdateBestItems then TyGearUpdateBestItems() end
	local message = L["Imported personal stat weights."]
	if type(engine) == "string" and engine ~= "" and TyGearMythicSimMeta and TyGearMythicSimMeta.engine and engine ~= TyGearMythicSimMeta.engine then
		message = message.." "..L["Those changes were applied on top of the current MythicSim weights. The MythicSim baseline in that string is older."]
	end
	if #unknownSpecs > 0 then
		message = message.." "..string.format(L["Skipped unknown spec: %s."], table.concat(unknownSpecs, ", "))
	end
	if badPairs > 0 then
		message = message.." "..string.format(L["Skipped %d unreadable lines."], badPairs)
	end
	return true, message
end

function TyGearImportPersonalStatWeights(text, currentClass)
	if type(text) == "string" then
		local trimmed = string.gsub(text, "^%s+", "")
		trimmed = string.gsub(trimmed, "%s+$", "")
		if string.sub(trimmed, 1, 4) == "TG2:" then
			return TyGearImportPersonalStatWeightsV2(trimmed, currentClass)
		end
	end
	return TyGearImportPersonalStatWeightsV1(text, currentClass)
end

function TyGearImportPersonalStatWeightsV1(text, currentClass)
	if type(text) ~= "string" then
		return false, L["Paste exported weights into the box, then click Import."]
	end
	text = string.gsub(text, "\r\n", "\n")
	text = string.gsub(text, "\r", "\n")
	if string.gsub(text, "%s", "") == "" then
		return false, L["Paste exported weights into the box, then click Import."]
	end
	local parsedClass
	local specs = {}
	local order = {}
	local currentSpec
	local unknownSpecs = {}
	local badLines = 0
	for line in string.gmatch(text, "[^\n]+") do
		line = string.gsub(line, "^%s+", "")
		line = string.gsub(line, "%s+$", "")
		if line ~= "" and line ~= TyGearPersonalStatWeightsExportHeader and not string.find(line, "^TyGear Personal Stat Weights") then
			local classText = string.match(line, "^[Cc]lass:%s*(.+)$")
			local specText = string.match(line, "^[Ss]pec:%s*(.+)$")
			local keyText, valueText = string.match(line, "^([^:]+):%s*(.+)$")
			if classText and not specText then
				parsedClass = TyGearNormalizePersonalClassToken(classText)
				if not parsedClass then
					return false, string.format(L["Unrecognized class in that export: %s"], classText)
				end
			elseif specText then
				local specName = TyGearFindPersonalSpecName(parsedClass or currentClass, specText)
				if not specName then
					currentSpec = nil
					table.insert(unknownSpecs, specText)
				else
					currentSpec = specName
					if not specs[specName] then
						specs[specName] = {}
						table.insert(order, specName)
					end
				end
			elseif keyText and valueText and currentSpec then
				local statKey = TyGearFindPersonalStatKey(keyText)
				if statKey == "weapons" then
					valueText = string.gsub(valueText, "^%s+", "")
					valueText = string.gsub(valueText, "%s+$", "")
					if valueText ~= "" then
						specs[currentSpec].weapons = valueText
					else
						badLines = badLines + 1
					end
				elseif statKey then
					local value = TyGearNormalizePersonalStatWeight(valueText)
					if value == nil then
						badLines = badLines + 1
					else
						specs[currentSpec][statKey] = value
					end
				else
					badLines = badLines + 1
				end
			elseif not classText then
				badLines = badLines + 1
			end
		end
	end
	if parsedClass and currentClass and parsedClass ~= currentClass then
		local parsedName = (TyGearClassList and TyGearClassList[parsedClass]) or parsedClass
		local currentName = (TyGearClassList and TyGearClassList[currentClass]) or currentClass
		return false, string.format(L["That export is for %s. This tab edits %s."], parsedName, currentName)
	end
	local className = parsedClass or currentClass
	if not className or #order == 0 then
		return false, L["Could not find any specs in that text."]
	end
	for _, specName in ipairs(order) do
		local row = TyGearGetPersonalWeighting(className, specName)
		local incoming = specs[specName]
		for statKey, value in pairs(incoming) do
			row[statKey] = value
		end
	end
	TyGearWeightingCacheKey = nil
	if TyGearSetStatWeights then TyGearSetStatWeights() end
	if TyGearUpdateBestItems then TyGearUpdateBestItems() end
	local message = L["Imported personal stat weights."]
	if #unknownSpecs > 0 then
		message = message.." "..string.format(L["Skipped unknown spec: %s."], table.concat(unknownSpecs, ", "))
	end
	if badLines > 0 then
		message = message.." "..string.format(L["Skipped %d unreadable lines."], badLines)
	end
	return true, message
end

function TyGearGetMythicSimWeighting(class, spec)
	return TyGearMythicSimWeights and TyGearMythicSimWeights[class] and TyGearMythicSimWeights[class][spec] or nil
end

function TyGearGetBuiltInWeighting(class, spec)
	return TyGearDefaultWeights[class] and TyGearDefaultWeights[class][spec] or nil
end

-- Prefer MythicSim EP weights; fall back to built-in healer/legacy profiles when MythicSim has no row.
function TyGearGetInternalWeighting(class, spec)
	local mythic = TyGearGetMythicSimWeighting(class, spec)
	if mythic then
		return mythic, TyGearStatWeightSystemMythicSim
	end
	local builtIn = TyGearGetBuiltInWeighting(class, spec)
	if builtIn then
		return builtIn, "BuiltIn"
	end
	return nil, nil
end

-- True when item scores should come from Pawn instead of internal weights.
function TyGearUsingPawn()
	if TyGearGetStatWeightSystem() == TyGearStatWeightSystemPersonal then
		return false
	end
	if TyGearGetStatWeightSystem() == TyGearStatWeightSystemForeverLevelingBIS then
		return false
	end
	if not TyGearIsPawnReady() then
		return false
	end
	if TyGearGetStatWeightSystem() == TyGearStatWeightSystemPawn then
		return true
	end
	-- MythicSim is selected: fall back to Pawn only when this class/spec has no internal weights.
	local _, class, spec = TyGearGetClassAndSpec()
	local weighting = TyGearGetInternalWeighting(class, spec)
	return weighting == nil
end

function TyGearGetWeightSourceLabel()
	if TyGearUsingPawn() then
		local pawnScaleName, pawnScaleLocalizedName = TyGearGetPawnScaleName()
		local pawnScaleColor = PawnGetScaleColor and PawnGetScaleColor(pawnScaleName)
		if (pawnScaleLocalizedName or pawnScaleName) and pawnScaleColor then
			return "Pawn \""..pawnScaleColor..(pawnScaleLocalizedName or pawnScaleName)..FONT_COLOR_CODE_CLOSE.."\""
		end
		return "Pawn"
	end
	if TyGearGetStatWeightSystem() == TyGearStatWeightSystemPersonal
	or TyGearCurrentWeightSource == TyGearStatWeightSystemPersonal then
		return "Personal"
	end
	if TyGearGetStatWeightSystem() == TyGearStatWeightSystemForeverLevelingBIS
	or TyGearCurrentWeightSource == TyGearStatWeightSystemForeverLevelingBIS then
		return "Forever Leveling BiS"
	end
	if TyGearCurrentWeightSource == TyGearStatWeightSystemMythicSim then
		return "MythicSim"
	end
	return "TyGear"
end

-- Item tooltips. Personal weights use "TyGear: Personal score:" rather than the system name.
function TyGearGetTooltipScorePrefix()
	if TyGearGetStatWeightSystem() == TyGearStatWeightSystemPersonal and not TyGearUsingPawn() then
		return "TyGear: Personal"
	end
	return "TyGear: "..TyGearGetWeightSourceLabel()
end

-- Resolve the weapons preference used for slot validity. Dual-wield profiles must not
-- leave the off-hand empty before Dual Wield is learned (shields stay valid via "any").
function TyGearApplyWeaponsPreference()
	local pref = TyGearCurrentWeighting and (TyGearCurrentWeighting.weapons or "any") or "any"
	if (pref == "dual wield" or pref == "2hDW") and not (CanDualWield and CanDualWield()) then
		pref = "any"
	end
	if weapons ~= pref then
		TyGearWipeTable(TyGearValidGearSlotsCache)
		TyGearWipeTable(TyGearSetSlotsCache)
	end
	weapons = pref
end

-- Offline weapon swing EP (GetItemStats omits base damage/speed). 1 AP ≈ 1 EP baseline;
-- Classic: 14 AP ≈ 1 Weapon DPS. Spec multipliers discount yellow-hit share and OH penalty.
-- Profiles may set weighting.weapon explicitly; otherwise defaults come from weapons preference.
function TyGearEnsureWeaponWeights()
	local w = TyGearCurrentWeighting
	if not w or w.weapon then return end
	local _, class, spec = TyGearGetClassAndSpec()
	local pref = w.weapons or "any"
	local ap = w.AttackPower or 0
	local publishedDps = w.DPS or 0

	-- Casters/healers: tooltip green stats only; ignore swing DPS/speed.
	if ap <= E then
		w.weapon = { mh_dps = 0, oh_dps = 0 }
		return
	end

	-- Feral: only Weapon DPS matters (form swing timer); keep MythicSim DPS EP if present.
	if class == "DRUID" and spec and (string.find(spec, "Feral") or spec == "Guardian") then
		w.weapon = {
			feral = true,
			mh_dps = (publishedDps > E) and publishedDps or 3.31,
			oh_dps = 0,
		}
		w.DPS = E
		w.Damage = E
		return
	end

	-- Already-calibrated EP-per-DPS from MythicSim (Rogue ~7+, etc.): promote as-is.
	if publishedDps >= 3 then
		w.weapon = {
			mh_dps = publishedDps,
			oh_dps = publishedDps * 0.5,
			norm_speed = (pref == "dagger" or pref == "dagger and any") and 1.7
				or ((pref == "2h" or pref == "2hDW") and 3.3 or 2.4),
			speed_bonus = 0,
		}
		w.DPS = E
		w.Damage = E
		return
	end

	-- Hunter ranged: published DPS is already EP per weapon DPS.
	if pref == "ranged" then
		w.weapon = {
			ranged = true,
			mh_dps = (publishedDps > E) and publishedDps or 1.2,
			oh_dps = 0,
		}
		w.DPS = E
		w.Damage = E
		return
	end

	-- Physical swingers: EP per DPS ≈ (11–13.5) * AttackPowerWeight when AP=1 → 12.5 EP/DPS.
	-- speed is extra EP per second slower than the normalized swing, before AttackPower scaling.
	-- Shield specs leave it at 0. Specials use the normalized 2.4s 1H speed, and white-hit
	-- threat per second is weapon DPS, so a slow low-DPS axe must not beat a faster hammer.
	local scale = ap
	local defaults = {
		["2h"] = { mh = 12.5, oh = 0, norm = 3.3, speed = 200 },
		["2hDW"] = { mh = 12.0, oh = 6.0, norm = 3.3, speed = 150 },
		["weapon and shield"] = { mh = 11.0, oh = 0, norm = 2.4, speed = 0 },
		["dual wield"] = { mh = 11.0, oh = 6.0, norm = 2.4, speed = 50 },
		["dagger"] = { mh = 11.0, oh = 6.0, norm = 1.7, speed = 0 },
		["dagger and any"] = { mh = 11.0, oh = 6.0, norm = 1.7, speed = 0 },
		["any"] = { mh = 12.0, oh = 6.0, norm = 2.4, speed = 100 },
	}
	local d = defaults[pref] or defaults["any"]
	w.weapon = {
		mh_dps = d.mh * scale,
		oh_dps = d.oh * scale,
		norm_speed = d.norm,
		speed_bonus = d.speed * scale,
	}
	w.DPS = E
	w.Damage = E
end

-- Weapon swing contribution for a candidate slot. OH uses oh_dps; MH/2H use mh_dps + speed.
-- Ranged/thrown: DPS only, except Hunters who also use ranged speed. Floor at 0 (FLB ScoreItem parity).
function TyGearGetWeaponSwingEP(info, gearSlot)
	local weapon = TyGearCurrentWeighting and TyGearCurrentWeighting.weapon
	if not weapon or not info or info.classID ~= Enum.ItemClass.Weapon then return 0 end
	if Enum.ItemWeaponSubclass and info.subclassID == Enum.ItemWeaponSubclass.Wand then return 0 end
	local dps = info.DPS or 0
	if dps <= 0 and info.Damage and info.WeaponSpeed and info.WeaponSpeed > 0 then
		dps = info.Damage / info.WeaponSpeed
	end
	if dps <= 0 then return 0 end

	local isRangedItem = info.isRangedWeapon or TyGearIsInvTypeRanged(info.invType)
	if weapon.feral and not isRangedItem then
		local feralWeight = weapon.mh_dps or 0
		if feralWeight <= E then return 0 end
		return dps * feralWeight
	end

	if isRangedItem then
		local dpsWeight = (weapon.ranged_dps and weapon.ranged_dps > E) and weapon.ranged_dps or (weapon.mh_dps or 0)
		if dpsWeight <= E then return 0 end
		local ep = dps * dpsWeight
		local _, class = TyGearGetClassAndSpec()
		-- Only hunters care about ranged weapon speed; rogue/warrior thrown is DPS-only.
		if class == "HUNTER" then
			local speed = info.WeaponSpeed
			local norm = weapon.ranged_norm_speed or weapon.norm_speed
			local speedBonus = weapon.ranged_speed_bonus
			if speedBonus == nil then
				speedBonus = weapon.speed_bonus or 0
			end
			if speed and norm and speedBonus > E then
				ep = ep + (speed - norm) * speedBonus
			end
		end
		if ep < 0 then
			return 0
		end
		return ep
	end

	local forOffHand = gearSlot == INVSLOT_OFFHAND
	local dpsWeight = forOffHand and (weapon.oh_dps or 0) or (weapon.mh_dps or 0)
	if dpsWeight <= E then return 0 end
	local ep = dps * dpsWeight
	local speed = info.WeaponSpeed
	local norm = weapon.norm_speed
	local speedBonus = weapon.speed_bonus or 0
	-- Only specs that set speed_bonus (2H Slam and similar) gain EP for a slower swing.
	-- Normalized specials ignore speed. Shield profiles leave speed_bonus at 0.
	if (not forOffHand) and speed and norm and speedBonus > E then
		ep = ep + (speed - norm) * speedBonus
	end
	if ep < 0 then
		return 0
	end
	return ep
end

function TyGearSetStatWeights()
	local localizedClass, class, spec, classID = TyGearGetClassAndSpec()
	local weightingKey = ((TyGearCharDB and TyGearCharDB.Override and (TyGearCharDB.OverrideSpec or "")) or (class.."|"..spec)).."|"..tostring(TyGearGetStatWeightSystem()).."|"..tostring(TyGearDB and TyGearDB.OverridePawnScale and TyGearDB.PawnScale or "")
	if TyGearWeightingCacheKey == weightingKey then
		-- CanDualWield can change after learning the skill; refresh weapons even on a cache hit.
		TyGearApplyWeaponsPreference()
		return
	end
	TyGearInvalidatePerformanceCaches()
	TyGearCachedClassLocalized, TyGearCachedClass, TyGearCachedSpec, TyGearCachedClassID = localizedClass, class, spec, classID
	TyGearClassSpecCacheKey = (TyGearCharDB and TyGearCharDB.Override and (TyGearCharDB.OverrideSpec or "")) or (class.."|"..spec)
	local baseWeighting, weightSource
	if TyGearGetStatWeightSystem() == TyGearStatWeightSystemPersonal then
		baseWeighting = TyGearGetPersonalWeighting(class, spec)
		weightSource = baseWeighting and TyGearStatWeightSystemPersonal or nil
	elseif TyGearGetStatWeightSystem() == TyGearStatWeightSystemForeverLevelingBIS then
		baseWeighting, weightSource = TyGearGetForeverLevelingBISWeighting(class, spec)
	else
		baseWeighting, weightSource = TyGearGetInternalWeighting(class, spec)
	end
	TyGearCurrentWeightSource = weightSource
	if baseWeighting then
		-- shallow copy so Crit/Hit merges do not mutate the shared defaults table
		TyGearCurrentWeighting = {}
		for k, v in pairs(baseWeighting) do
			TyGearCurrentWeighting[k] = v
		end
	else
		TyGearCurrentWeighting = nil
	end
	TyGearWeightingCacheKey = weightingKey
	if (not TyGearCurrentWeighting) then
		TyGearApplyWeaponsPreference()
		if not TyGearUsingPawn() then
			TyGearPrint("TyGear: No weighting set for "..RAID_CLASS_COLORS[class]:WrapTextInColorCode(spec.." "..localizedClass)..".", 0)
		end
		return
	end
	if (IS_WOW_FOREVER or TOC_VERSION_CURRENT >= TOC_VERSION_WOTLK) and (not TyGearUsingPawn()) then
		TyGearCurrentWeighting.Crit = math.max(TyGearCurrentWeighting.Crit or 0, TyGearCurrentWeighting.SpellCrit or 0)
		if IS_WOW_FOREVER then
			-- WoW Forever combines melee, ranged and spell hit on gear
			TyGearCurrentWeighting.Hit = math.max(TyGearCurrentWeighting.Hit or 0, TyGearCurrentWeighting.SpellHit or 0)
		end
	end
	-- Personal weights keep the numbers the player typed, including zero.
	-- MythicSim (and some built-ins) omit Armor. Keep a tiny floor so better armor
	-- still upgrades otherwise-equal low-level pieces without competing with real EPs.
	-- Forever Leveling BiS already publishes Armor when it matters; still floor unused primaries.
	if TyGearCurrentWeightSource ~= TyGearStatWeightSystemPersonal then
		if (TyGearCurrentWeighting.Armor or 0) <= E then
			TyGearCurrentWeighting.Armor = 0.001
		end
		-- MythicSim sets unused primaries to E (e.g. Warrior Spirit/Stamina). Rings, necks,
		-- and trinkets that only have those stats then score as 0 (Lookie's Spyglass = +1 Spirit).
		-- A small floor keeps jewelry comparable without competing with real EPs (Str/Agi/etc.).
		for _, stat in ipairs({ "Strength", "Agility", "Stamina", "Intellect", "Spirit" }) do
			if (TyGearCurrentWeighting[stat] or 0) <= E then
				TyGearCurrentWeighting[stat] = 0.01
			end
		end
	end
	TyGearEnsureWeaponWeights()
	TyGearApplyWeaponsPreference()
end

local function newCheckbox(dbname, label, description, onClick, optionsMenu)
	label = TyGearColorize(label)
	description = TyGearColorize(description)
	local check = CreateFrame("CheckButton", "TyGear"..dbname.."CheckButton", optionsMenu, "InterfaceOptionsCheckButtonTemplate")
	check:SetScript("OnClick", function(self)
		local tick = self:GetChecked()
		onClick(self, tick and true or false)
		if tick then
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		else
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
		end
	end)
	check.label = _G[check:GetName().."Text"]
	check.label:SetText(label)
	check.tooltipText = label
	check:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_NONE")
		GameTooltip:SetPoint("BOTTOMLEFT", self, "TOPLEFT")
		GameTooltip:AddLine(label,NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b,true)
		GameTooltip:AddLine(description,HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b,true)
		GameTooltip:Show()
	end)
	check:SetScript("OnLeave", function() GameTooltip:Hide() end)
	check.tooltipRequirement = description
	return check
end

--compact multi-column gear-slot checkbox grid (Ignore and Lock slots)
local function createGearSlotCheckboxGrid(parent, frameName, checkNamePrefix, slotList, isChecked, setChecked, description, enableWheel)
	local columns = 4
	local cellWidth = 118
	local cellHeight = 20
	local padX, padY = 10, 8
	local rows = math.max(math.ceil(#slotList / columns), 1)
	local slotGrid = CreateFrame("Frame", frameName, parent, "BackdropTemplate")
	slotGrid:SetSize(padX * 2 + columns * cellWidth, padY * 2 + rows * cellHeight)
	slotGrid:SetBackdrop({
		bgFile = "Interface/ChatFrame/ChatFrameBackground",
		edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	slotGrid:SetBackdropColor(0.08, 0.08, 0.08, 0.45)
	slotGrid:SetBackdropBorderColor(0.45, 0.45, 0.45, 0.9)
	for index, gearSlot in ipairs(slotList) do
		local column = (index - 1) % columns
		local rowIndex = math.floor((index - 1) / columns)
		local shortLabel = TyGearGetGearSlotShortLabel(gearSlot)
		local check = CreateFrame("CheckButton", checkNamePrefix..gearSlot.."CheckButton", slotGrid, "UICheckButtonTemplate")
		check:SetSize(20, 20)
		check:SetPoint("TOPLEFT", slotGrid, "TOPLEFT", padX + column * cellWidth, -(padY + rowIndex * cellHeight))
		local label = _G[check:GetName().."Text"]
		if label then
			label:SetFontObject(GameFontHighlightSmall)
			label:SetText(shortLabel)
			label:SetWordWrap(false)
			label:ClearAllPoints()
			label:SetPoint("LEFT", check, "RIGHT", 2, 0)
			label:SetWidth(cellWidth - 26)
			label:SetJustifyH("LEFT")
		end
		check:SetHitRectInsets(0, -(cellWidth - 24), 2, 2)
		check:SetChecked(isChecked(gearSlot) and true or false)
		check:SetScript("OnClick", function(self)
			local tick = self:GetChecked() and true or false
			setChecked(gearSlot, tick)
			if tick then
				PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
			else
				PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
			end
		end)
		check:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_NONE")
			GameTooltip:SetPoint("BOTTOMLEFT", self, "TOPLEFT")
			GameTooltip:AddLine(shortLabel, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, true)
			GameTooltip:AddLine(description, HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b, true)
			GameTooltip:Show()
		end)
		check:SetScript("OnLeave", function() GameTooltip:Hide() end)
		if enableWheel then enableWheel(check) end
	end
	return slotGrid
end

--all modern clients have the modern menu system (Blizzard_Menu); older clients only have UIDropDownMenu, which taints the default UI in Classic without TaintLess
local useModernDropdowns = (MenuUtil ~= nil) and (WowStyle1DropdownMixin ~= nil)

local function setDropdownText(dropdown, text)
	text = TyGearColorize(TyGearColorizeSpecChoice(text))
	if useModernDropdowns then
		--OverrideText ignores nil, and it stops the menu from replacing the text with its own selection text
		dropdown:OverrideText(text or "")
	else
		UIDropDownMenu_SetText(dropdown, text)
	end
end

-- Class rows use the class color. Spec rows use a spec color where one is defined, otherwise the class color.
-- Entries that are not a class or spec, such as Pawn scales, keep the general colorizer.
local function dropdownEntryText(entry, specName)
	if entry["class"] then
		if specName then
			return TyGearSpecColoredText(entry["class"], specName)
		end
		return TyGearClassColoredText(entry["class"], entry["label"])
	end
	return TyGearColorize(specName or entry["label"])
end

local function closeDropdownMenu(dropdown)
	if useModernDropdowns then
		dropdown:CloseMenu()
	else
		CloseDropDownMenus()
	end
end

--options window layout in pixels
local OPTIONS_CONTAINER_TOP = -46 --below the TyGear title and the AutoGear credit line
local OPTIONS_CONTAINER_LEFT_OFFSET = 8
local OPTIONS_CONTAINER_RIGHT_MARGIN = 30 --room for the scroll bar
local OPTIONS_CONTAINER_BOTTOM_MARGIN = 16
local OPTIONS_PAGE_PADDING = 12
local OPTIONS_ROW_SPACING = 2
local OPTIONS_SECTION_SPACING = 12
local OPTIONS_SECTION_HEADER_HEIGHT = 20
local OPTIONS_BUTTON_SPACING = 10
local OPTIONS_BLOCK_PAD = 12
local OPTIONS_BLOCK_ROW_GAP = 10
local OPTIONS_BLOCK_WIDTH_INSET = 8

local function tyGearApplySectionBlockBackdrop(frame)
	frame:SetBackdrop({
		bgFile = "Interface/ChatFrame/ChatFrameBackground",
		edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	-- Waypoint-like dark charcoal panel
	frame:SetBackdropColor(0.11, 0.11, 0.12, 0.92)
	frame:SetBackdropBorderColor(0.48, 0.48, 0.48, 0.95)
end

---Waypoint-style setting row: title + muted description on the left, control on the right.
local function newBlockSettingRow(parent, dbname, label, description, onClick)
	label = TyGearColorize(label)
	description = TyGearColorize(description)
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(500, 36)

	local check = CreateFrame("CheckButton", "TyGear"..dbname.."CheckButton", row, "InterfaceOptionsCheckButtonTemplate")
	check:SetPoint("RIGHT", row, "RIGHT", -2, 0)
	local templateText = _G[check:GetName().."Text"]
	if templateText then
		templateText:SetText("")
		templateText:Hide()
	end
	check:SetHitRectInsets(0, 0, 0, 0)
	check:SetScript("OnClick", function(self)
		local tick = self:GetChecked()
		onClick(self, tick and true or false)
		if tick then
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		else
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
		end
	end)

	local title = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	title:SetPoint("TOPLEFT", 4, -2)
	title:SetPoint("RIGHT", check, "LEFT", -14, 0)
	title:SetJustifyH("LEFT")
	title:SetWordWrap(false)
	title:SetText(label)

	local desc = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
	desc:SetPoint("RIGHT", check, "LEFT", -14, 0)
	desc:SetJustifyH("LEFT")
	if desc.SetMaxLines then
		desc:SetMaxLines(3)
	end
	desc:SetText(description or "")

	local function measure()
		local titleH = title:GetStringHeight() or 14
		local descH = (description and description ~= "") and (desc:GetStringHeight() or 12) or 0
		local textH = titleH + ((descH > 0) and (descH + 2) or 0)
		local height = math.max(textH + 8, 28)
		row:SetHeight(height)
		check:ClearAllPoints()
		check:SetPoint("RIGHT", row, "RIGHT", -2, 0)
	end
	measure()
	row.tyGearMeasure = measure

	check.tooltipText = label
	check.tooltipRequirement = description
	check.label = title
	row.check = check
	row.title = title
	row.description = desc
	row:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_NONE")
		GameTooltip:SetPoint("BOTTOMLEFT", self, "TOPLEFT")
		GameTooltip:AddLine(label, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, true)
		GameTooltip:AddLine(description, HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b, true)
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	row:EnableMouse(true)
	-- Clicking the text toggles the checkbox, matching the dense Waypoint rows.
	row:SetScript("OnMouseUp", function(_, button)
		if button and button ~= "LeftButton" then return end
		if not check:IsEnabled() then return end
		if check.IsMouseOver and check:IsMouseOver() then return end
		check:Click()
	end)

	return row
end

---One scrolling options page. The mouse wheel moves through every section
---because they are all on this page.
---@param optionsMenu table the scroll child of the options scroll frame
---@return table optionsPage with BeginOption, AddRow, AddScanButton and Finish
local function newOptionsPage(optionsMenu)
	local scrollFrame = optionsMenu:GetParent()
	local optionsPage = {}

	local container = CreateFrame("Frame", "TyGearOptionsContainer", optionsMenu, "BackdropTemplate")
	container:SetBackdrop({
		bgFile = "Interface/ChatFrame/ChatFrameBackground",
		edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 14,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	container:SetBackdropColor(0.1, 0.1, 0.1, 0.3)
	container:SetBackdropBorderColor(0.5, 0.5, 0.5)
	container:SetPoint("TOPLEFT", optionsMenu, "TOPLEFT", OPTIONS_CONTAINER_LEFT_OFFSET, OPTIONS_CONTAINER_TOP)

	local page = CreateFrame("Frame", nil, container)
	page:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
	page:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, 0)
	page.height = OPTIONS_PAGE_PADDING
	optionsPage.page = page

	local function scrollRange()
		if scrollFrame.GetVerticalScrollRange then
			local range = scrollFrame:GetVerticalScrollRange()
			if range and range > 0 then return range end
		end
		return math.max(0, (optionsMenu:GetHeight() or 0) - (scrollFrame:GetHeight() or 0))
	end

	local function onWheel(_, delta)
		if ScrollFrameTemplate_OnMouseWheel then
			ScrollFrameTemplate_OnMouseWheel(scrollFrame, delta)
			return
		end
		local range = scrollRange()
		local nextScroll = (scrollFrame:GetVerticalScroll() or 0) - (delta * 60)
		if nextScroll < 0 then nextScroll = 0 end
		if nextScroll > range then nextScroll = range end
		scrollFrame:SetVerticalScroll(nextScroll)
	end

	-- Guard against DropdownButton's intrinsic OnMouseWheel_Intrinsic and its
	-- SetScript handler both firing for the same wheel tick (double scroll).
	local function pageWheel(self, delta)
		if self._tyGearWheelLock then return end
		self._tyGearWheelLock = true
		onWheel(self, delta)
		self._tyGearWheelLock = nil
	end

	local function enableWheel(frame)
		if not frame or not frame.EnableMouseWheel then return end
		if frame.EnableMouse and not frame:IsMouseEnabled() then
			frame:EnableMouse(true)
		end
		frame:EnableMouseWheel(true)
		-- WowStyle1DropdownTemplate / DropdownButton cycles radio selections from
		-- OnMouseWheel_Intrinsic -> Rotate (Override specialization, Override Pawn
		-- scale, etc.). Override the intrinsic method, the script, and
		-- Rotate/Increment/Decrement so the wheel only scrolls this options page
		-- when the cursor is over a dropdown.
		if frame.OnMouseWheel_Intrinsic then
			frame.OnMouseWheel_Intrinsic = pageWheel
		end
		if frame.Rotate then
			frame.Rotate = function() end
			frame.Increment = function() end
			frame.Decrement = function() end
		end
		frame.OnMouseWheel = pageWheel
		frame:SetScript("OnMouseWheel", pageWheel)
		frame.tyGearWheel = true
	end

	function optionsPage:EnableWheel(frame)
		enableWheel(frame)
	end
	enableWheel(optionsMenu)
	enableWheel(scrollFrame)
	enableWheel(container)
	enableWheel(page)

	page.rows = {}

	local function placeRow(row, spacing, offsetX, afterRow)
		row:SetParent(page)
		row:ClearAllPoints()
		local left = OPTIONS_PAGE_PADDING + offsetX
		if afterRow then
			row:SetPoint("TOP", afterRow, "BOTTOM", 0, -spacing)
			row:SetPoint("LEFT", page, "LEFT", left, 0)
		else
			row:SetPoint("TOPLEFT", page, "TOPLEFT", left, -OPTIONS_PAGE_PADDING)
		end
		-- Stretch section blocks so child rows can wrap against a real width during build.
		if row.tyGearBlock then
			row:SetPoint("RIGHT", page, "RIGHT", -left, 0)
		end
		enableWheel(row)
	end

	local function placeBlockRow(block, row, spacing, afterRow)
		row:SetParent(block)
		row:ClearAllPoints()
		local left = OPTIONS_BLOCK_PAD
		if afterRow then
			row:SetPoint("TOP", afterRow, "BOTTOM", 0, -spacing)
			row:SetPoint("LEFT", block, "LEFT", left, 0)
			row:SetPoint("RIGHT", block, "RIGHT", -OPTIONS_BLOCK_PAD, 0)
		else
			row:SetPoint("TOPLEFT", block, "TOPLEFT", left, -OPTIONS_BLOCK_PAD)
			row:SetPoint("TOPRIGHT", block, "TOPRIGHT", -OPTIONS_BLOCK_PAD, -OPTIONS_BLOCK_PAD)
		end
		enableWheel(row)
		if row.tyGearMeasure then row.tyGearMeasure() end
	end

	local function reflowBlock(block)
		if not block or not block.tyGearBlock then return 0 end
		block.lastRow = nil
		local height = OPTIONS_BLOCK_PAD
		for _, entry in ipairs(block.blockRows) do
			local row = entry.row
			if row:IsShown() then
				local gap = block.lastRow and entry.spacing or 0
				placeBlockRow(block, row, gap, block.lastRow)
				height = height + gap + (row:GetHeight() or 0)
				block.lastRow = row
			else
				row:ClearAllPoints()
			end
		end
		height = height + OPTIONS_BLOCK_PAD
		block:SetHeight(math.max(height, OPTIONS_BLOCK_PAD * 2))
		return block:GetHeight() or height
	end

	function optionsPage:AddRow(row, spacing, offsetX)
		-- When a section block is open, legacy callers (Ignore builders, notes, grids)
		-- should land inside it. The block frame itself still uses the page path below.
		if page.block and row ~= page.block and not row.tyGearBlock then
			self:AddBlockRow(row, spacing)
			return
		end
		--offsetX is always from the page's left padding, not relative to the previous row,
		--so a one-off indent (Scan Bags, slot grids) does not shove later rows sideways
		offsetX = offsetX or 0
		local storedSpacing = spacing or OPTIONS_ROW_SPACING
		local appliedSpacing = page.lastRow and storedSpacing or 0
		placeRow(row, appliedSpacing, offsetX, page.lastRow)
		page.height = page.height + appliedSpacing + (row:GetHeight() or 0)
		page.lastRow = row
		table.insert(page.rows, {
			row = row,
			spacing = storedSpacing,
			offsetX = offsetX,
		})
	end

	function optionsPage:CloseBlock()
		if not page.block then return end
		reflowBlock(page.block)
		page.block = nil
	end

	function optionsPage:OpenBlock()
		self:CloseBlock()
		local block = CreateFrame("Frame", nil, page, "BackdropTemplate")
		tyGearApplySectionBlockBackdrop(block)
		block.tyGearBlock = true
		block.blockRows = {}
		block.lastRow = nil
		block:SetHeight(OPTIONS_BLOCK_PAD * 2)
		-- Provisional width so description wrap/measure works before Finish layout.
		local provisional = math.max((scrollFrame:GetWidth() or 0) - OPTIONS_CONTAINER_RIGHT_MARGIN - OPTIONS_PAGE_PADDING * 2 - OPTIONS_BLOCK_WIDTH_INSET, 420)
		block:SetWidth(provisional)
		page.block = block
		self:AddRow(block, OPTIONS_SECTION_SPACING, OPTIONS_BLOCK_WIDTH_INSET)
		return block
	end

	---Add a row inside the active Waypoint-style section block (opens one if needed).
	function optionsPage:AddBlockRow(row, spacing)
		if not page.block then
			self:OpenBlock()
		end
		local block = page.block
		local storedSpacing = spacing or OPTIONS_BLOCK_ROW_GAP
		table.insert(block.blockRows, { row = row, spacing = storedSpacing })
		local oldHeight = block:GetHeight() or 0
		local newHeight = reflowBlock(block)
		page.height = page.height + (newHeight - oldHeight)
	end

	-- Re-chain visible rows after Show/Hide so hidden options leave no gap.
	function optionsPage:Relayout()
		page.lastRow = nil
		page.height = OPTIONS_PAGE_PADDING
		for _, entry in ipairs(page.rows) do
			local row = entry.row
			if row.tyGearBlock then
				reflowBlock(row)
				local anyVisible = false
				for _, blockEntry in ipairs(row.blockRows) do
					if blockEntry.row:IsShown() then
						anyVisible = true
						break
					end
				end
				row:SetShown(anyVisible)
			end
			if row:IsShown() then
				local appliedSpacing = page.lastRow and entry.spacing or 0
				placeRow(row, appliedSpacing, entry.offsetX, page.lastRow)
				page.height = page.height + appliedSpacing + (row:GetHeight() or 0)
				page.lastRow = row
			else
				row:ClearAllPoints()
			end
		end
		self:UpdateHeight()
	end

	function optionsPage:AddHeader(label, isMajor)
		self:CloseBlock()
		local header = CreateFrame("Frame", nil, page)
		header:SetSize(400, isMajor and 26 or OPTIONS_SECTION_HEADER_HEIGHT)
		local headerText = header:CreateFontString(nil, "ARTWORK", isMajor and "GameFontNormalLarge" or "GameFontNormal")
		headerText:SetPoint("BOTTOMLEFT", 4, 2)
		headerText:SetText(TyGearColorize(label))
		self:AddRow(header, isMajor and OPTIONS_SECTION_SPACING or 6)
	end

	---Groups options onto this page. Section labels open a Waypoint-style block underneath.
	function optionsPage:BeginOption(tabLabel, sectionLabel)
		if tabLabel ~= page.tab then
			self:CloseBlock()
			page.tab = tabLabel
			page.section = nil
			self:AddHeader(tabLabel, true)
		end
		if sectionLabel and sectionLabel ~= page.section then
			self:CloseBlock()
			page.section = sectionLabel
			self:AddHeader(sectionLabel, false)
			self:OpenBlock()
		elseif not sectionLabel then
			-- Tab-only groups (Ignore) open blocks around their own subheaders
			-- so we do not leave an empty panel under the major header.
			if page.section then
				self:CloseBlock()
				page.section = nil
			end
		end
		return page
	end

	function optionsPage:AddScanButton()
		if self.scanAdded then return end
		self.scanAdded = true
		self:CloseBlock()
		local button = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
		button:SetHeight(30)
		button:SetText(L["Scan Bags"])
		local fontString = button.GetFontString and button:GetFontString()
		local textWidth = fontString and fontString:GetStringWidth() or 0
		if not textWidth or textWidth < 8 then
			textWidth = #L["Scan Bags"] * 7
		end
		button:SetWidth(math.max(100, textWidth + 28))
		button:SetScript("OnClick", function() TyGearScan() end)
		button:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_NONE")
			GameTooltip:SetPoint("BOTTOMLEFT", self, "TOPLEFT")
			GameTooltip:AddLine(TyGearColorize(L["Click this button to force a bag scan, the same way that TyGear scans for gear upgrades in your bags whenever new gear is looted.\n\nTip: By equipping your old item, you can use this to help determine how TyGear decided an item was an upgrade."]), nil, nil, nil, true)
			GameTooltip:Show()
		end)
		button:SetScript("OnLeave", function() GameTooltip:Hide() end)
		enableWheel(button)
		self:AddRow(button, OPTIONS_BUTTON_SPACING)
	end

	function optionsPage:Finish()
		self:CloseBlock()
		local function layout()
			local width = math.max((scrollFrame:GetWidth() or 0) - OPTIONS_CONTAINER_RIGHT_MARGIN, 1)
			container:SetWidth(width)
			page:SetWidth(width)
			optionsMenu:SetWidth(width + OPTIONS_CONTAINER_LEFT_OFFSET)
			local innerWidth = math.max(width - OPTIONS_PAGE_PADDING * 2 - OPTIONS_BLOCK_WIDTH_INSET, 1)
			for _, entry in ipairs(page.rows) do
				local row = entry.row
				if row.tyGearBlock then
					row:SetWidth(innerWidth)
					reflowBlock(row)
				end
			end
			-- Recompute page height after block widths change wrapped text height.
			page.lastRow = nil
			page.height = OPTIONS_PAGE_PADDING
			for _, entry in ipairs(page.rows) do
				local row = entry.row
				if row:IsShown() then
					local appliedSpacing = page.lastRow and entry.spacing or 0
					placeRow(row, appliedSpacing, entry.offsetX, page.lastRow)
					page.height = page.height + appliedSpacing + (row:GetHeight() or 0)
					page.lastRow = row
				end
			end
			local pageHeight = page.height + OPTIONS_PAGE_PADDING
			container:SetHeight(pageHeight)
			page:SetHeight(pageHeight)
			optionsMenu:SetHeight(-OPTIONS_CONTAINER_TOP + pageHeight + OPTIONS_CONTAINER_BOTTOM_MARGIN)
			if scrollFrame.UpdateScrollChildRect then
				scrollFrame:UpdateScrollChildRect()
			end
		end
		if not self.layoutHooked then
			self.layoutHooked = true
			scrollFrame:HookScript("OnSizeChanged", layout)
		end
		self.layout = layout
		layout()
	end

	function optionsPage:UpdateHeight()
		if self.layout then self.layout() end
	end

	return optionsPage
end

local function buildIgnoreSection(optionsPage)
	local page = optionsPage:BeginOption(L["Ignore"])

	local function addNote(text)
		local holder = CreateFrame("Frame", nil, page)
		local font = holder:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
		font:SetPoint("TOPLEFT", 4, -2)
		font:SetPoint("TOPRIGHT", holder, "TOPRIGHT", -4, -2)
		font:SetJustifyH("LEFT")
		if font.SetMaxLines then font:SetMaxLines(6) end
		font:SetText(TyGearColorize(text))
		local height = font:GetStringHeight()
		local estimate = math.ceil(math.max(#text, 1) / 80) * 14
		if not height or height < estimate then height = estimate end
		holder:SetHeight(height + 8)
		optionsPage:AddBlockRow(holder)
	end

	-- Gold section title outside the panel, then a fresh block for that subsection.
	local function addSubheader(text)
		optionsPage:CloseBlock()
		local header = CreateFrame("Frame", nil, page)
		header:SetSize(400, OPTIONS_SECTION_HEADER_HEIGHT)
		local font = header:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		font:SetPoint("BOTTOMLEFT", 4, 2)
		font:SetText(TyGearColorize(text))
		optionsPage:AddRow(header, OPTIONS_SECTION_SPACING)
		optionsPage:OpenBlock()
	end

	local function trackHeight(container, height)
		height = math.max(height, 20)
		container:SetHeight(height)
		if container.appliedHeight then
			page.height = page.height + (height - container.appliedHeight)
			optionsPage:UpdateHeight()
		end
		container.appliedHeight = height
	end

	local addItemsHelp = L["Item names or IDs separated by commas. Items on this list are kept and not evaluated. Shift-click an item while this box is focused to add it, or assign \"Toggle hovered item on ignore list\" in Key Bindings and press it while hovering an item. New items are added near the top of the list."]

	local function manualIDText()
		local parts = {}
		for _, itemID in ipairs(TyGearGetIgnoredItemIDOrder()) do
			table.insert(parts, tostring(itemID))
		end
		return table.concat(parts, ", ")
	end

	local function saveManualIDs(text)
		local previous = TyGearCharDB.IgnoredItemIDs or {}
		local parsed = TyGearParseItemIDList(text)
		local nextIDs, seen, newOnes, rest = {}, {}, {}, {}
		for _, itemID in ipairs(parsed) do
			if not seen[itemID] and not TyGearIsAutoUnmeasurable(itemID) then
				seen[itemID] = true
				nextIDs[itemID] = true
				if previous[itemID] then
					table.insert(rest, itemID)
				else
					table.insert(newOnes, itemID)
				end
			end
		end
		local ordered = {}
		for _, itemID in ipairs(newOnes) do
			table.insert(ordered, itemID)
		end
		for _, itemID in ipairs(rest) do
			table.insert(ordered, itemID)
		end
		TyGearCharDB.IgnoredItemIDs = nextIDs
		TyGearCharDB.IgnoredItemIDOrder = ordered
		if TyGearUpdateBestItems then TyGearUpdateBestItems() end
	end

	addSubheader(L["Gear slots"])
	addNote(L["Ignored slots are left out of rolling, scoring, and equipping."])
	do
		local slotList = {}
		for slot = INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED do
			--tabard is the virtual 2H slot; shirts are not scored, so neither is listed here
			if slot ~= INVSLOT_TABARD and slot ~= INVSLOT_BODY then
				table.insert(slotList, slot)
			end
		end
		local slotGrid = createGearSlotCheckboxGrid(
			page,
			"TyGearIgnoredGearSlotsGrid",
			"TyGearIgnoreSlot",
			slotList,
			function(gearSlot)
				return TyGearCharDB.IgnoredGearSlots[gearSlot]
			end,
			function(gearSlot, tick)
				TyGearCharDB.IgnoredGearSlots[gearSlot] = tick
				if TyGearUpdateBestItems then TyGearUpdateBestItems() end
			end,
			L["Ignored slots are left out of rolling, scoring, and equipping."],
			function(frame) optionsPage:EnableWheel(frame) end
		)
		optionsPage:AddRow(slotGrid, 4, 4)
	end

	addSubheader(L["Equipped items"])
	addNote(L["Check an equipped item to leave that item out of selling, rolling, scoring, and equipping."])
	local equippedContainer = CreateFrame("Frame", nil, page)
	equippedContainer:SetSize(500, 20)
	equippedContainer.emptyText = equippedContainer:CreateFontString(nil, "ARTWORK", "GameFontDisable")
	equippedContainer.emptyText:SetPoint("TOPLEFT", 8, -2)
	equippedContainer.emptyText:SetText(L["Nothing is equipped."])
	local equippedRows = {}
	local equippedSerial = 0

	local function acquireEquippedRow()
		equippedSerial = equippedSerial + 1
		local row = CreateFrame("Frame", nil, equippedContainer)
		row:SetSize(500, 28)
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(24, 24)
		row.icon:SetPoint("LEFT", 2, 0)
		row.check = CreateFrame("CheckButton", "TyGearIgnoreEquipped"..equippedSerial.."CheckButton", row, "InterfaceOptionsCheckButtonTemplate")
		row.check:SetPoint("LEFT", row.icon, "RIGHT", 2, 0)
		local templateText = _G[row.check:GetName().."Text"]
		if templateText then templateText:SetText("") end
		row.name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		row.name:SetPoint("LEFT", row.check, "RIGHT", 2, 0)
		row.name:SetPoint("RIGHT", row, "RIGHT", -4, 0)
		row.name:SetJustifyH("LEFT")
		row.name:SetWordWrap(false)
		row.check:SetScript("OnClick", function(self)
			local itemID = self:GetParent().itemID
			if TyGearIsAutoUnmeasurable(itemID) then
				self:SetChecked(true)
				return
			end
			local tick = self:GetChecked() and true or false
			TyGearSetItemIgnored(itemID, tick)
			if tick then
				PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
			else
				PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
			end
			if TyGearRefreshIgnoreSection then TyGearRefreshIgnoreSection() end
		end)
		row.check:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetHyperlink("item:"..self:GetParent().itemID)
			if TyGearIsAutoUnmeasurable(self:GetParent().itemID) then
				GameTooltip:AddLine(L["TyGear cannot score this item, so it stays ignored."], 1, 0.82, 0, true)
			end
			GameTooltip:Show()
		end)
		row.check:SetScript("OnLeave", function() GameTooltip:Hide() end)
		optionsPage:EnableWheel(row.check)
		return row
	end

	local function rebuildEquipped()
		local shown = 0
		for slot = INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED do
			local itemID = GetInventoryItemID("player", slot)
			if itemID then
				shown = shown + 1
				local row = equippedRows[shown]
				if not row then
					row = acquireEquippedRow()
					equippedRows[shown] = row
				end
				row.itemID = itemID
				row:ClearAllPoints()
				row:SetPoint("TOPLEFT", equippedContainer, "TOPLEFT", 0, -((shown - 1) * 28))
				row.icon:SetTexture(GetInventoryItemTexture("player", slot) or "Interface\\Icons\\INV_Misc_QuestionMark")
				local autoIgnored = TyGearIsAutoUnmeasurable(itemID)
				row.check:SetChecked(TyGearIsItemIgnored({ id = itemID, isGear = true }) and true or false)
				if row.check.SetEnabled then
					row.check:SetEnabled(not autoIgnored)
				elseif autoIgnored then
					row.check:Disable()
				else
					row.check:Enable()
				end
				local link = GetInventoryItemLink("player", slot)
				row.name:SetText((link or ("item "..itemID)).."   "..(TyGearGetLockedGearSlotLabel(slot) or ""))
				row:Show()
			end
		end
		for index = shown + 1, #equippedRows do
			equippedRows[index]:Hide()
		end
		equippedContainer.emptyText:SetShown(shown == 0)
		trackHeight(equippedContainer, shown == 0 and 20 or (shown * 28))
	end

	local editRow = CreateFrame("Frame", nil, page)
	editRow:SetSize(500, 24)
	local editBox = CreateFrame("EditBox", "TyGearIgnoredItemIDsEditBox", editRow, "InputBoxTemplate")
	editBox:SetAutoFocus(false)
	editBox:SetSize(320, 20)
	editBox:SetPoint("LEFT", 12, 0)
	local suppressEditBoxSave = false
	local function showManualIDs()
		suppressEditBoxSave = true
		editBox:SetText(manualIDText())
		editBox:SetCursorPosition(0)
		suppressEditBoxSave = false
	end
	editBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	editBox:SetScript("OnEscapePressed", function(self)
		showManualIDs()
		self:ClearFocus()
	end)
	editBox:SetScript("OnEditFocusLost", function(self)
		if suppressEditBoxSave then return end
		saveManualIDs(self:GetText())
		if TyGearRefreshIgnoreSection then TyGearRefreshIgnoreSection() end
	end)
	editBox:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_NONE")
		GameTooltip:SetPoint("BOTTOMLEFT", self, "TOPLEFT")
		GameTooltip:AddLine(L["Add items"], NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, true)
		GameTooltip:AddLine(addItemsHelp, HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b, true)
		GameTooltip:Show()
	end)
	editBox:SetScript("OnLeave", function() GameTooltip:Hide() end)
	optionsPage:EnableWheel(editBox)
	local function insertItemLink(text)
		if editBox:HasFocus() and text and string.find(text, "item:%d+") then
			editBox:Insert(" "..text)
		end
	end
	if ChatFrameUtil and ChatFrameUtil.InsertLink then
		hooksecurefunc(ChatFrameUtil, "InsertLink", insertItemLink)
	elseif ChatEdit_InsertLink then
		hooksecurefunc("ChatEdit_InsertLink", insertItemLink)
	end

	function TyGearRefreshIgnoreSection()
		rebuildEquipped()
		if not editBox:HasFocus() then
			showManualIDs()
		end
	end

	rebuildEquipped()
	optionsPage:AddRow(equippedContainer)
	addSubheader(L["Add items"])
	addNote(addItemsHelp)
	optionsPage:AddRow(editRow)
	showManualIDs()

	--keep list and its options live on the ignore list; items here are not sold (empty slots may still be filled)
	addSubheader(L["Keep List"])
	local keepListDescription = L["Item names or IDs separated by commas.  Greys and common (white) items listed here are not sold. They can still fill an empty gear slot, but they are not treated as upgrades over gear you already wear.\n\nWhite selling only covers weapons and armor, so non-gear whites do not need to be listed. Profession weapons such as Skinning Knife, Mining Pick, Blacksmith Hammer, Arclight Spanner, and Herbalist's Spade are always kept and do not need to be listed. Every fishing pole is kept even if it is not listed here.\n\nShift-click an item while this box has focus to add it, look up item IDs in item tooltips while the TyGear options are open, or assign \"Toggle hovered item on ignore list\" in Key Bindings and press it while hovering an item. New items are added near the top of the list."]
	addNote(keepListDescription)

	local unboundRow = newBlockSettingRow(
		page,
		"KeepUnboundGreyGear",
		L["Keep unbound grey gear"],
		L["Don't sell grey weapons and armor which aren't soulbound, for example to sell them on the auction house instead."],
		function(_, value)
			if not TyGearDB then TyGearDB = {} end
			TyGearDB.KeepUnboundGreyGear = value and true or false
			TyGearPrint("TyGear: "..(TyGearDB.KeepUnboundGreyGear and L["Keeping unbound grey gear is now enabled."] or L["Keeping unbound grey gear is now disabled."]), 0)
			if TyGearQueueVendorJunkRefresh then TyGearQueueVendorJunkRefresh() end
		end
	)
	unboundRow.check:SetChecked(TyGearDB and TyGearDB.KeepUnboundGreyGear)
	optionsPage:AddBlockRow(unboundRow)

	local tahultRow = newBlockSettingRow(
		page,
		"KeepKeeperTahultPetItems",
		L["Keep greys needed for Keeper Ta'hult's pets"],
		L["Don't sell the grey items that Keeper Ta'hult in Oribos takes as payment for the Baubleworm pets."],
		function(_, value)
			if not TyGearDB then TyGearDB = {} end
			TyGearDB.KeepKeeperTahultPetItems = value and true or false
			TyGearPrint("TyGear: "..(TyGearDB.KeepKeeperTahultPetItems and L["Keeping greys needed for Keeper Ta'hult's pets is now enabled."] or L["Keeping greys needed for Keeper Ta'hult's pets is now disabled."]), 0)
			if TyGearQueueVendorJunkRefresh then TyGearQueueVendorJunkRefresh() end
		end
	)
	tahultRow.check:SetChecked(TyGearDB and TyGearDB.KeepKeeperTahultPetItems)
	optionsPage:AddBlockRow(tahultRow)

	local keepEditRow = CreateFrame("Frame", nil, page)
	keepEditRow:SetSize(500, 24)
	local keepEditBox = CreateFrame("EditBox", "TyGearVendorKeepListEditBox", keepEditRow, "InputBoxTemplate")
	keepEditBox:SetAutoFocus(false)
	keepEditBox:SetSize(320, 20)
	keepEditBox:SetPoint("LEFT", 12, 0)
	local suppressKeepEditBoxSave = false
	local function showKeepListText()
		suppressKeepEditBoxSave = true
		keepEditBox:SetText((TyGearDB and TyGearDB.VendorKeepList) or "")
		keepEditBox:SetCursorPosition(0)
		suppressKeepEditBoxSave = false
	end
	local function saveKeepListText(text)
		if not TyGearDB then TyGearDB = {} end
		local previous = {}
		for _, itemID in ipairs(TyGearParseItemIDList(TyGearDB.VendorKeepList or "")) do
			previous[itemID] = true
		end
		local parsed = TyGearParseItemIDList(text or "")
		local seen, newOnes, rest = {}, {}, {}
		for _, itemID in ipairs(parsed) do
			--hard-kept profession tools stay out of the editable text box
			if not seen[itemID] and not (TyGearCraftingToolItemIDSet and TyGearCraftingToolItemIDSet[itemID]) then
				seen[itemID] = true
				if previous[itemID] then
					table.insert(rest, itemID)
				else
					table.insert(newOnes, itemID)
				end
			end
		end
		local ordered = {}
		for _, itemID in ipairs(newOnes) do
			table.insert(ordered, itemID)
		end
		for _, itemID in ipairs(rest) do
			table.insert(ordered, itemID)
		end
		TyGearDB.VendorKeepList = table.concat(ordered, ", ")
		showKeepListText()
		if TyGearQueueVendorJunkRefresh then TyGearQueueVendorJunkRefresh() end
		if TyGearUpdateBestItems then TyGearUpdateBestItems() end
		if TyGearRefreshKeepList then TyGearRefreshKeepList() end
	end
	keepEditBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	keepEditBox:SetScript("OnEscapePressed", function(self)
		showKeepListText()
		self:ClearFocus()
	end)
	keepEditBox:SetScript("OnEditFocusLost", function(self)
		if suppressKeepEditBoxSave then return end
		saveKeepListText(self:GetText())
	end)
	keepEditBox:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_NONE")
		GameTooltip:SetPoint("BOTTOMLEFT", self, "TOPLEFT")
		GameTooltip:AddLine(L["Keep List"], NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, true)
		GameTooltip:AddLine(keepListDescription, HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b, true)
		GameTooltip:Show()
	end)
	keepEditBox:SetScript("OnLeave", function() GameTooltip:Hide() end)
	optionsPage:EnableWheel(keepEditBox)
	local function insertKeepItemLink(text)
		if keepEditBox:HasFocus() and text and string.find(text, "item:%d+") then
			keepEditBox:Insert(" "..text)
		end
	end
	if ChatFrameUtil and ChatFrameUtil.InsertLink then
		hooksecurefunc(ChatFrameUtil, "InsertLink", insertKeepItemLink)
	elseif ChatEdit_InsertLink then
		hooksecurefunc("ChatEdit_InsertLink", insertKeepItemLink)
	end
	optionsPage:AddRow(keepEditRow)
	showKeepListText()
end

--Ignore controls for the Forever Ignored List Settings tab (slots, equipped, manual IDs)
local function buildIgnoreSectionOntoListMenu(listMenu, anchorBelow)
	local function addNote(anchor, text)
		local holder = CreateFrame("Frame", nil, listMenu)
		holder:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6)
		holder:SetPoint("RIGHT", listMenu, "RIGHT", -8, 0)
		local font = holder:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		font:SetPoint("TOPLEFT", 0, 0)
		font:SetWidth(480)
		font:SetJustifyH("LEFT")
		font:SetWordWrap(true)
		font:SetText(text)
		local height = font:GetStringHeight() or 14
		if height < 14 then height = 14 end
		holder:SetHeight(height + 2)
		return holder
	end

	local function addSubheader(anchor, text, spacing)
		local header = listMenu:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		header:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -(spacing or 12))
		header:SetText(TyGearColorize(text))
		return header
	end

	local ignoreHeader = addSubheader(anchorBelow, L["Ignore"], 14)

	local slotsNote = addNote(ignoreHeader, L["Ignored slots are left out of rolling, scoring, and equipping."])
	local slotList = {}
	for slot = INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED do
		if slot ~= INVSLOT_TABARD and slot ~= INVSLOT_BODY then
			table.insert(slotList, slot)
		end
	end
	local slotGrid = createGearSlotCheckboxGrid(
		listMenu,
		"TyGearIgnoredGearSlotsGrid",
		"TyGearIgnoreSlot",
		slotList,
		function(gearSlot)
			return TyGearCharDB.IgnoredGearSlots[gearSlot]
		end,
		function(gearSlot, tick)
			TyGearCharDB.IgnoredGearSlots[gearSlot] = tick
			if TyGearUpdateBestItems then TyGearUpdateBestItems() end
		end,
		L["Ignored slots are left out of rolling, scoring, and equipping."],
		nil
	)
	slotGrid:ClearAllPoints()
	slotGrid:SetPoint("TOPLEFT", slotsNote, "BOTTOMLEFT", 0, -4)

	local equippedHeader = addSubheader(slotGrid, L["Equipped items"], 14)
	local equippedNote = addNote(equippedHeader, L["Check an equipped item to leave that item out of selling, rolling, scoring, and equipping."])
	local equippedContainer = CreateFrame("Frame", nil, listMenu)
	equippedContainer:SetPoint("TOPLEFT", equippedNote, "BOTTOMLEFT", 0, -4)
	equippedContainer:SetPoint("RIGHT", listMenu, "RIGHT", -8, 0)
	equippedContainer:SetHeight(20)
	equippedContainer.emptyText = equippedContainer:CreateFontString(nil, "ARTWORK", "GameFontDisable")
	equippedContainer.emptyText:SetPoint("TOPLEFT", 0, 0)
	equippedContainer.emptyText:SetText(L["Nothing is equipped."])
	local equippedRows = {}
	local equippedSerial = 0

	local function acquireEquippedRow()
		equippedSerial = equippedSerial + 1
		local row = CreateFrame("Frame", nil, equippedContainer)
		row:SetSize(500, 28)
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(24, 24)
		row.icon:SetPoint("LEFT", 2, 0)
		row.check = CreateFrame("CheckButton", "TyGearIgnoreEquipped"..equippedSerial.."CheckButton", row, "InterfaceOptionsCheckButtonTemplate")
		row.check:SetPoint("LEFT", row.icon, "RIGHT", 2, 0)
		local templateText = _G[row.check:GetName().."Text"]
		if templateText then templateText:SetText("") end
		row.name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		row.name:SetPoint("LEFT", row.check, "RIGHT", 2, 0)
		row.name:SetPoint("RIGHT", row, "RIGHT", -4, 0)
		row.name:SetJustifyH("LEFT")
		row.name:SetWordWrap(false)
		row.check:SetScript("OnClick", function(self)
			local itemID = self:GetParent().itemID
			if TyGearIsAutoUnmeasurable(itemID) then
				self:SetChecked(true)
				return
			end
			local tick = self:GetChecked() and true or false
			TyGearSetItemIgnored(itemID, tick)
			if tick then
				PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
			else
				PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
			end
			if TyGearRefreshIgnoreSection then TyGearRefreshIgnoreSection() end
		end)
		row.check:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetHyperlink("item:"..self:GetParent().itemID)
			if TyGearIsAutoUnmeasurable(self:GetParent().itemID) then
				GameTooltip:AddLine(L["TyGear cannot score this item, so it stays ignored."], 1, 0.82, 0, true)
			end
			GameTooltip:Show()
		end)
		row.check:SetScript("OnLeave", function() GameTooltip:Hide() end)
		return row
	end

	local function rebuildEquipped()
		local shown = 0
		for slot = INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED do
			local itemID = GetInventoryItemID("player", slot)
			if itemID then
				shown = shown + 1
				local row = equippedRows[shown]
				if not row then
					row = acquireEquippedRow()
					equippedRows[shown] = row
				end
				row.itemID = itemID
				row:ClearAllPoints()
				row:SetPoint("TOPLEFT", equippedContainer, "TOPLEFT", 0, -((shown - 1) * 28))
				row:SetPoint("TOPRIGHT", equippedContainer, "TOPRIGHT", 0, -((shown - 1) * 28))
				row.icon:SetTexture(GetInventoryItemTexture("player", slot) or "Interface\\Icons\\INV_Misc_QuestionMark")
				local autoIgnored = TyGearIsAutoUnmeasurable(itemID)
				row.check:SetChecked(TyGearIsItemIgnored({ id = itemID, isGear = true }) and true or false)
				if row.check.SetEnabled then
					row.check:SetEnabled(not autoIgnored)
				elseif autoIgnored then
					row.check:Disable()
				else
					row.check:Enable()
				end
				local link = GetInventoryItemLink("player", slot)
				row.name:SetText((link or ("item "..itemID)).."   "..(TyGearGetLockedGearSlotLabel(slot) or ""))
				row:Show()
			end
		end
		for index = shown + 1, #equippedRows do
			equippedRows[index]:Hide()
		end
		equippedContainer.emptyText:SetShown(shown == 0)
		equippedContainer:SetHeight(shown == 0 and 20 or (shown * 28))
	end

	local addItemsHelp = L["Item names or IDs separated by commas. Items on this list are kept and not evaluated. Shift-click an item while this box is focused to add it, or assign \"Toggle hovered item on ignore list\" in Key Bindings and press it while hovering an item. New items are added near the top of the list."]

	local function manualIDText()
		local parts = {}
		for _, itemID in ipairs(TyGearGetIgnoredItemIDOrder()) do
			table.insert(parts, tostring(itemID))
		end
		return table.concat(parts, ", ")
	end

	local function saveManualIDs(text)
		local previous = TyGearCharDB.IgnoredItemIDs or {}
		local parsed = TyGearParseItemIDList(text)
		local nextIDs, seen, newOnes, rest = {}, {}, {}, {}
		for _, itemID in ipairs(parsed) do
			if not seen[itemID] and not TyGearIsAutoUnmeasurable(itemID) then
				seen[itemID] = true
				nextIDs[itemID] = true
				if previous[itemID] then
					table.insert(rest, itemID)
				else
					table.insert(newOnes, itemID)
				end
			end
		end
		local ordered = {}
		for _, itemID in ipairs(newOnes) do
			table.insert(ordered, itemID)
		end
		for _, itemID in ipairs(rest) do
			table.insert(ordered, itemID)
		end
		TyGearCharDB.IgnoredItemIDs = nextIDs
		TyGearCharDB.IgnoredItemIDOrder = ordered
		if TyGearUpdateBestItems then TyGearUpdateBestItems() end
	end

	local idsHeader = addSubheader(equippedContainer, L["Add items"], 14)
	local idsNote = addNote(idsHeader, addItemsHelp)
	local editRow = CreateFrame("Frame", nil, listMenu)
	editRow:SetPoint("TOPLEFT", idsNote, "BOTTOMLEFT", 0, -2)
	editRow:SetPoint("RIGHT", listMenu, "RIGHT", -8, 0)
	editRow:SetHeight(24)
	local editBox = CreateFrame("EditBox", "TyGearIgnoredItemIDsEditBox", editRow, "InputBoxTemplate")
	editBox:SetAutoFocus(false)
	editBox:SetHeight(20)
	editBox:SetPoint("LEFT", 4, 0)
	editBox:SetPoint("RIGHT", editRow, "RIGHT", -4, 0)
	local suppressEditBoxSave = false
	local function showManualIDs()
		suppressEditBoxSave = true
		editBox:SetText(manualIDText())
		editBox:SetCursorPosition(0)
		suppressEditBoxSave = false
	end
	editBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	editBox:SetScript("OnEscapePressed", function(self)
		showManualIDs()
		self:ClearFocus()
	end)
	editBox:SetScript("OnEditFocusLost", function(self)
		if suppressEditBoxSave then return end
		saveManualIDs(self:GetText())
		if TyGearRefreshIgnoreSection then TyGearRefreshIgnoreSection() end
	end)
	editBox:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_NONE")
		GameTooltip:SetPoint("BOTTOMLEFT", self, "TOPLEFT")
		GameTooltip:AddLine(L["Add items"], NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, true)
		GameTooltip:AddLine(addItemsHelp, HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b, true)
		GameTooltip:Show()
	end)
	editBox:SetScript("OnLeave", function() GameTooltip:Hide() end)
	local function insertItemLink(text)
		if editBox:HasFocus() and text and string.find(text, "item:%d+") then
			editBox:Insert(" "..text)
		end
	end
	if ChatFrameUtil and ChatFrameUtil.InsertLink then
		hooksecurefunc(ChatFrameUtil, "InsertLink", insertItemLink)
	elseif ChatEdit_InsertLink then
		hooksecurefunc("ChatEdit_InsertLink", insertItemLink)
	end

	function TyGearRefreshIgnoreSection()
		rebuildEquipped()
		if not editBox:HasFocus() then
			showManualIDs()
		end
		--equipped rows change height; refresh the unmeasurable list layout once without re-entering
		if (not TyGearIgnoreSectionRefreshingList) and TyGearRefreshIgnoredGearList then
			TyGearIgnoreSectionRefreshingList = true
			TyGearRefreshIgnoredGearList()
			TyGearIgnoreSectionRefreshingList = nil
		end
	end

	rebuildEquipped()
	showManualIDs()
	return editRow
end

--the keep list is built below and hosted on this same tab
local buildKeepListSection

--Forever Ignored List tab: ignore controls, the keep list, then ignored items
local function buildIgnoredGearListPage(listMenu)
	local title = listMenu:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 8, -8)
	title:SetText(L["Ignored List"])

	local ignoreBottom = buildIgnoreSectionOntoListMenu(listMenu, title)
	local keepBottom = buildKeepListSection(listMenu, ignoreBottom)

	local listHeader = listMenu:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	listHeader:SetPoint("TOPLEFT", keepBottom, "BOTTOMLEFT", 0, -18)
	listHeader:SetText(L["Ignored items"])

	local listContainer = CreateFrame("Frame", "TyGearIgnoredGearListContainer", listMenu)
	listContainer:SetPoint("TOPLEFT", listHeader, "BOTTOMLEFT", 0, -8)
	listContainer:SetPoint("RIGHT", listMenu, "RIGHT", -8, 0)
	listContainer:SetHeight(20)

	local emptyText = listContainer:CreateFontString(nil, "ARTWORK", "GameFontDisable")
	emptyText:SetPoint("TOPLEFT", 0, 0)
	emptyText:SetText(L["No items are on the ignored list."])

	local note = listMenu:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	note:SetPoint("TOPLEFT", listContainer, "BOTTOMLEFT", 0, -14)
	note:SetWidth(480)
	note:SetJustifyH("LEFT")
	note:SetText(L["Disclaimer: items TyGear cannot score (for example a 4% chance for Fear to miss) are listed below without checkboxes and stay ignored automatically. Gear that also has a scored stat stays in normal evaluation. Use Add items above for anything else you want ignored; those appear at the top with checkboxes."])
	listMenu.ignoredGearNote = note

	local rows = {}
	local rowHeight = 28
	local rowSerial = 0

	local function acquireRow()
		rowSerial = rowSerial + 1
		local row = CreateFrame("Frame", nil, listContainer)
		row:SetSize(500, rowHeight)
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(24, 24)
		row.icon:SetPoint("LEFT", 0, 0)
		--checkbox only for user-added items; out-of-the-box unmeasurable gear stays listed without a toggle
		row.check = CreateFrame("CheckButton", "TyGearIgnoredGearRow"..rowSerial.."CheckButton", row, "InterfaceOptionsCheckButtonTemplate")
		row.check:SetPoint("LEFT", row.icon, "RIGHT", 2, 0)
		local templateText = _G[row.check:GetName().."Text"]
		if templateText then templateText:SetText("") end
		row.name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		row.name:SetJustifyH("LEFT")
		row.name:SetWordWrap(false)
		row.check:SetScript("OnClick", function(self)
			local parent = self:GetParent()
			if parent.builtIn then
				self:SetChecked(true)
				return
			end
			local itemID = parent.itemID
			local keep = self:GetChecked() and true or false
			TyGearSetItemIgnored(itemID, keep)
			if keep then
				PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
			else
				PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
			end
			if TyGearRefreshIgnoreSection then TyGearRefreshIgnoreSection() end
		end)
		row.check:SetScript("OnEnter", function(self)
			local parent = self:GetParent()
			if not parent.itemID then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetHyperlink("item:"..parent.itemID)
			GameTooltip:AddLine(L["Uncheck to remove this item from the ignored list."], 1, 0.82, 0, true)
			GameTooltip:Show()
		end)
		row.check:SetScript("OnLeave", function() GameTooltip:Hide() end)
		row:EnableMouse(true)
		row:SetScript("OnEnter", function(self)
			if not self.itemID then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetHyperlink("item:"..self.itemID)
			if self.builtIn then
				GameTooltip:AddLine(L["TyGear cannot score this item, so it stays ignored."], 1, 0.82, 0, true)
			else
				GameTooltip:AddLine(L["Uncheck to remove this item from the ignored list."], 1, 0.82, 0, true)
			end
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", function() GameTooltip:Hide() end)
		return row
	end

	local function collectEntries()
		local entries, seen = {}, {}
		--user-added ignore IDs first (newest at the top), then out-of-the-box unmeasurable gear
		for _, itemID in ipairs(TyGearGetIgnoredItemIDOrder()) do
			local icon = GetItemInfoInstant and select(5, GetItemInfoInstant(itemID))
			local name = GetItemInfo and GetItemInfo(itemID)
			seen[itemID] = true
			table.insert(entries, { id = itemID, icon = icon, name = name or ("item "..itemID), builtIn = false })
		end
		local builtin = {}
		if TyGearUnmeasurableGearList then
			for _, entry in ipairs(TyGearUnmeasurableGearList) do
				if not seen[entry.id] then
					seen[entry.id] = true
					table.insert(builtin, { id = entry.id, icon = entry.icon, name = entry.name, builtIn = true })
				end
			end
		end
		if TyGearCharDB and TyGearCharDB.DiscoveredUnmeasurableGear then
			for itemID in pairs(TyGearCharDB.DiscoveredUnmeasurableGear) do
				if not seen[itemID] then
					local icon = GetItemInfoInstant and select(5, GetItemInfoInstant(itemID))
					local name = GetItemInfo and GetItemInfo(itemID)
					table.insert(builtin, { id = itemID, icon = icon, name = name or ("item "..itemID), builtIn = true })
				end
			end
		end
		table.sort(builtin, function(a, b)
			return (a.name or "") < (b.name or "")
		end)
		for _, entry in ipairs(builtin) do
			table.insert(entries, entry)
		end
		return entries
	end

	local layoutIgnoredGearPage
	function TyGearRefreshIgnoredGearList()
		if not listMenu:IsShown() and listContainer.builtOnce then
			listContainer.needsRefresh = true
			return
		end
		listContainer.builtOnce = true
		listContainer.needsRefresh = false
		local entries = collectEntries()
		for index, entry in ipairs(entries) do
			local row = rows[index]
			if not row then
				row = acquireRow()
				rows[index] = row
			end
			row.itemID = entry.id
			row.builtIn = entry.builtIn and true or false
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", listContainer, "TOPLEFT", 0, -((index - 1) * rowHeight))
			row:SetPoint("TOPRIGHT", listContainer, "TOPRIGHT", 0, -((index - 1) * rowHeight))
			row.icon:SetTexture(entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
			row.name:ClearAllPoints()
			row.name:SetPoint("RIGHT", row, "RIGHT", -4, 0)
			if row.builtIn then
				row.check:Hide()
				row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
			else
				row.check:Show()
				row.check:SetChecked(true)
				row.name:SetPoint("LEFT", row.check, "RIGHT", 2, 0)
			end
			row.name:SetText(entry.name or ("item "..entry.id))
			row:Show()
			if Item and Item.CreateFromItemID then
				local itemID = entry.id
				local item = Item:CreateFromItemID(itemID)
				item:ContinueOnItemLoad(function()
					if row.itemID ~= itemID or not row:IsShown() then return end
					local icon = item.GetItemIcon and item:GetItemIcon()
					local name = item.GetItemName and item:GetItemName()
					if icon then row.icon:SetTexture(icon) end
					if name then row.name:SetText(name) end
				end)
			end
		end
		for index = #entries + 1, #rows do
			rows[index]:Hide()
		end
		emptyText:SetShown(#entries == 0)
		local height = #entries == 0 and 20 or (#entries * rowHeight)
		listContainer:SetHeight(height)
		note:ClearAllPoints()
		note:SetPoint("TOPLEFT", listContainer, "BOTTOMLEFT", 0, -14)
		layoutIgnoredGearPage()
	end

	layoutIgnoredGearPage = function()
		local top = listMenu:GetTop()
		local bottom = note:GetBottom()
		local height
		if top and bottom and (top > bottom) then
			height = (top - bottom) + 24
		else
			local keepCount = #TyGearParseItemIDList((TyGearDB and TyGearDB.VendorKeepList) or "")
			local keepHeight = (keepCount == 0) and 20 or (keepCount * 28)
			local ignoredCount = #collectEntries()
			local ignoredHeight = (ignoredCount == 0) and 20 or (ignoredCount * 28)
			--title, ignore controls, keep options, and both lists before the frames are sized
			height = 900 + keepHeight + ignoredHeight
		end
		listMenu:SetHeight(height)
		local scrollFrame = listMenu:GetParent()
		if scrollFrame and scrollFrame.UpdateScrollChildRect then
			scrollFrame:UpdateScrollChildRect()
		end
	end
	listMenu.layoutIgnoredGearPage = layoutIgnoredGearPage

	listMenu:HookScript("OnShow", function()
		if TyGearRefreshKeepList then TyGearRefreshKeepList() end
		if listContainer.needsRefresh or not listContainer.builtOnce then
			TyGearRefreshIgnoredGearList()
		else
			layoutIgnoredGearPage()
		end
	end)
	TyGearRefreshIgnoredGearList()
end

--Keep list and keep options, hosted on the ignore list. Items here are not sold; they may still fill empty slots.
buildKeepListSection = function(listMenu, anchorBelow)
	local header = listMenu:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	header:SetPoint("TOPLEFT", anchorBelow, "BOTTOMLEFT", 0, -18)
	header:SetText(L["Keep List"])

	local note = listMenu:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	note:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)
	note:SetWidth(480)
	note:SetJustifyH("LEFT")
	note:SetText(L["Greys and common (white) items listed here are not sold. They can still fill an empty gear slot, but they are not treated as upgrades over gear you already wear. White selling only covers weapons and armor, so non-gear whites do not need to be listed. Profession weapons that exist on WoW Forever, such as Skinning Knife, Mining Pick, Blacksmith Hammer, and Arclight Spanner, are always kept and do not need to be listed. Every fishing pole is kept even if it is not listed here."])
	listMenu.keepListNote = note

	local unboundCheck = newCheckbox(
		"KeepUnboundGreyGear",
		L["Keep unbound grey gear"],
		L["Don't sell grey weapons and armor which aren't soulbound, for example to sell them on the auction house instead."],
		function(_, value)
			if not TyGearDB then TyGearDB = {} end
			TyGearDB.KeepUnboundGreyGear = value and true or false
			TyGearPrint("TyGear: "..(TyGearDB.KeepUnboundGreyGear and L["Keeping unbound grey gear is now enabled."] or L["Keeping unbound grey gear is now disabled."]), 0)
			if TyGearQueueVendorJunkRefresh then TyGearQueueVendorJunkRefresh() end
		end,
		listMenu
	)
	unboundCheck:SetPoint("TOPLEFT", note, "BOTTOMLEFT", -2, -10)
	unboundCheck:SetChecked(TyGearDB and TyGearDB.KeepUnboundGreyGear)
	unboundCheck:SetHitRectInsets(0, -280, 0, 0)
	listMenu.keepUnboundCheck = unboundCheck

	local addItemsHelp = L["Item names or IDs separated by commas. Shift-click an item while this box has focus to add it, look up item IDs in item tooltips while the TyGear options are open, or assign \"Toggle hovered item on ignore list\" in Key Bindings and press it while hovering an item. That keeps the item from being sold; it can still fill an empty gear slot. New items are added near the top of the list."]

	local addHeader = listMenu:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	addHeader:SetPoint("TOPLEFT", unboundCheck, "BOTTOMLEFT", 2, -14)
	addHeader:SetText(L["Add items"])

	local addNote = listMenu:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	addNote:SetPoint("TOPLEFT", addHeader, "BOTTOMLEFT", 0, -6)
	addNote:SetWidth(480)
	addNote:SetJustifyH("LEFT")
	addNote:SetText(addItemsHelp)
	listMenu.keepListAddNote = addNote

	local editRow = CreateFrame("Frame", nil, listMenu)
	editRow:SetPoint("TOPLEFT", addNote, "BOTTOMLEFT", 0, -2)
	editRow:SetPoint("RIGHT", listMenu, "RIGHT", -8, 0)
	editRow:SetHeight(24)
	local editBox = CreateFrame("EditBox", "TyGearVendorKeepListEditBox", editRow, "InputBoxTemplate")
	editBox:SetAutoFocus(false)
	editBox:SetHeight(20)
	editBox:SetPoint("LEFT", 4, 0)
	editBox:SetPoint("RIGHT", editRow, "RIGHT", -4, 0)
	local suppressEditBoxSave = false
	local function showKeepListText()
		suppressEditBoxSave = true
		editBox:SetText((TyGearDB and TyGearDB.VendorKeepList) or "")
		editBox:SetCursorPosition(0)
		suppressEditBoxSave = false
	end
	local function saveKeepListText(text)
		if not TyGearDB then TyGearDB = {} end
		local previous = {}
		for _, itemID in ipairs(TyGearParseItemIDList(TyGearDB.VendorKeepList or "")) do
			previous[itemID] = true
		end
		local parsed = TyGearParseItemIDList(text or "")
		local seen, newOnes, rest = {}, {}, {}
		for _, itemID in ipairs(parsed) do
			--hard-kept profession tools stay out of the editable text box
			if not seen[itemID] and not (TyGearCraftingToolItemIDSet and TyGearCraftingToolItemIDSet[itemID]) then
				seen[itemID] = true
				if previous[itemID] then
					table.insert(rest, itemID)
				else
					table.insert(newOnes, itemID)
				end
			end
		end
		local ordered = {}
		for _, itemID in ipairs(newOnes) do
			table.insert(ordered, itemID)
		end
		for _, itemID in ipairs(rest) do
			table.insert(ordered, itemID)
		end
		TyGearDB.VendorKeepList = table.concat(ordered, ", ")
		showKeepListText()
		if TyGearQueueVendorJunkRefresh then TyGearQueueVendorJunkRefresh() end
		if TyGearUpdateBestItems then TyGearUpdateBestItems() end
		if TyGearRefreshKeepList then TyGearRefreshKeepList() end
	end
	editBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	editBox:SetScript("OnEscapePressed", function(self)
		showKeepListText()
		self:ClearFocus()
	end)
	editBox:SetScript("OnEditFocusLost", function(self)
		if suppressEditBoxSave then return end
		saveKeepListText(self:GetText())
	end)
	editBox:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_NONE")
		GameTooltip:SetPoint("BOTTOMLEFT", self, "TOPLEFT")
		GameTooltip:AddLine(L["Add items"], NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, true)
		GameTooltip:AddLine(addItemsHelp, HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b, true)
		GameTooltip:Show()
	end)
	editBox:SetScript("OnLeave", function() GameTooltip:Hide() end)
	local function insertItemLink(text)
		if editBox:HasFocus() and text and string.find(text, "item:%d+") then
			editBox:Insert(" "..text)
		end
	end
	if ChatFrameUtil and ChatFrameUtil.InsertLink then
		hooksecurefunc(ChatFrameUtil, "InsertLink", insertItemLink)
	elseif ChatEdit_InsertLink then
		hooksecurefunc("ChatEdit_InsertLink", insertItemLink)
	end
	showKeepListText()

	local keptHeader = listMenu:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	keptHeader:SetPoint("TOPLEFT", editRow, "BOTTOMLEFT", 0, -14)
	keptHeader:SetText(L["Kept items"])

	local listContainer = CreateFrame("Frame", "TyGearKeepListContainer", listMenu)
	listContainer:SetPoint("TOPLEFT", keptHeader, "BOTTOMLEFT", 0, -8)
	listContainer:SetPoint("RIGHT", listMenu, "RIGHT", -8, 0)
	listContainer:SetHeight(20)

	local emptyText = listContainer:CreateFontString(nil, "ARTWORK", "GameFontDisable")
	emptyText:SetPoint("TOPLEFT", 0, 0)
	emptyText:SetText(L["No items are on the keep list."])

	local rows = {}
	local rowHeight = 28
	local rowSerial = 0

	local function defaultKeepSet()
		local set = {}
		for _, itemID in ipairs(TyGearCraftingToolItemIDs or {}) do
			set[itemID] = true
		end
		return set
	end

	local function acquireRow()
		rowSerial = rowSerial + 1
		local row = CreateFrame("Frame", nil, listContainer)
		row:SetSize(500, rowHeight)
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(24, 24)
		row.icon:SetPoint("LEFT", 0, 0)
		--checkbox only for user-added items; out-of-the-box crafting tools stay listed without a toggle
		row.check = CreateFrame("CheckButton", "TyGearKeepListRow"..rowSerial.."CheckButton", row, "InterfaceOptionsCheckButtonTemplate")
		row.check:SetPoint("LEFT", row.icon, "RIGHT", 2, 0)
		local templateText = _G[row.check:GetName().."Text"]
		if templateText then templateText:SetText("") end
		row.name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		row.name:SetJustifyH("LEFT")
		row.name:SetWordWrap(false)
		row.check:SetScript("OnClick", function(self)
			local parent = self:GetParent()
			if parent.builtIn then
				self:SetChecked(true)
				return
			end
			local itemID = parent.itemID
			local keep = self:GetChecked() and true or false
			TyGearSetVendorKeepListItem(itemID, keep)
			if keep then
				PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
			else
				PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
			end
		end)
		row.check:SetScript("OnEnter", function(self)
			local parent = self:GetParent()
			if not parent.itemID then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetHyperlink("item:"..parent.itemID)
			GameTooltip:AddLine(L["Uncheck to remove this item from the keep list."], 1, 0.82, 0, true)
			GameTooltip:Show()
		end)
		row.check:SetScript("OnLeave", function() GameTooltip:Hide() end)
		row:EnableMouse(true)
		row:SetScript("OnEnter", function(self)
			if not self.itemID then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetHyperlink("item:"..self.itemID)
			if self.builtIn then
				GameTooltip:AddLine(L["Included with TyGear's default keep list."], 1, 0.82, 0, true)
			else
				GameTooltip:AddLine(L["Uncheck to remove this item from the keep list."], 1, 0.82, 0, true)
			end
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", function() GameTooltip:Hide() end)
		return row
	end

	local function collectEntries()
		local defaults = defaultKeepSet()
		local user, builtin, seen = {}, {}, {}
		--preserve newest-first order for user-added items; defaults stay below without checkboxes
		for _, itemID in ipairs(TyGearParseItemIDList((TyGearDB and TyGearDB.VendorKeepList) or "")) do
			if not seen[itemID] then
				seen[itemID] = true
				local icon = GetItemInfoInstant and select(5, GetItemInfoInstant(itemID))
				local name = GetItemInfo and GetItemInfo(itemID)
				local entry = { id = itemID, icon = icon, name = name or ("item "..itemID), builtIn = defaults[itemID] and true or false }
				if entry.builtIn then
					table.insert(builtin, entry)
				else
					table.insert(user, entry)
				end
			end
		end
		--always list out-of-the-box profession tools, even when the saved keep list was cleared
		for _, itemID in ipairs(TyGearCraftingToolItemIDs or {}) do
			if not seen[itemID] then
				seen[itemID] = true
				local icon = GetItemInfoInstant and select(5, GetItemInfoInstant(itemID))
				local name = GetItemInfo and GetItemInfo(itemID)
				table.insert(builtin, { id = itemID, icon = icon, name = name or ("item "..itemID), builtIn = true })
			end
		end
		table.sort(builtin, function(a, b)
			return (a.name or "") < (b.name or "")
		end)
		for _, entry in ipairs(builtin) do
			table.insert(user, entry)
		end
		return user
	end

	function TyGearRefreshKeepList()
		if not listMenu:IsShown() and listContainer.builtOnce then
			listContainer.needsRefresh = true
			return
		end
		listContainer.builtOnce = true
		listContainer.needsRefresh = false
		if unboundCheck and unboundCheck.SetChecked then
			unboundCheck:SetChecked(TyGearDB and TyGearDB.KeepUnboundGreyGear)
		end
		if not editBox:HasFocus() then
			showKeepListText()
		end
		local entries = collectEntries()
		for index, entry in ipairs(entries) do
			local row = rows[index]
			if not row then
				row = acquireRow()
				rows[index] = row
			end
			row.itemID = entry.id
			row.builtIn = entry.builtIn and true or false
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", listContainer, "TOPLEFT", 0, -((index - 1) * rowHeight))
			row:SetPoint("TOPRIGHT", listContainer, "TOPRIGHT", 0, -((index - 1) * rowHeight))
			row.icon:SetTexture(entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
			row.name:ClearAllPoints()
			row.name:SetPoint("RIGHT", row, "RIGHT", -4, 0)
			if row.builtIn then
				row.check:Hide()
				row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
			else
				row.check:Show()
				row.check:SetChecked(true)
				row.name:SetPoint("LEFT", row.check, "RIGHT", 2, 0)
			end
			row.name:SetText(entry.name or ("item "..entry.id))
			row:Show()
			if Item and Item.CreateFromItemID then
				local itemID = entry.id
				local item = Item:CreateFromItemID(itemID)
				item:ContinueOnItemLoad(function()
					if row.itemID ~= itemID or not row:IsShown() then return end
					local icon = item.GetItemIcon and item:GetItemIcon()
					local name = item.GetItemName and item:GetItemName()
					if icon then row.icon:SetTexture(icon) end
					if name then row.name:SetText(name) end
				end)
			end
		end
		for index = #entries + 1, #rows do
			rows[index]:Hide()
		end
		emptyText:SetShown(#entries == 0)
		local height = #entries == 0 and 20 or (#entries * rowHeight)
		listContainer:SetHeight(height)
		if listMenu.layoutIgnoredGearPage then
			listMenu.layoutIgnoredGearPage()
		end
	end

	TyGearRefreshKeepList()
	return listContainer
end

--Forever Need List tab: add box near the top, then items TyGear should always NEED on
local function buildNeedListPage(listMenu)
	local title = listMenu:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 8, -8)
	title:SetText(L["Need List"])

	local note = listMenu:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	note:SetPoint("TOPLEFT", 8, -28)
	note:SetWidth(480)
	note:SetJustifyH("LEFT")
	note:SetText(L["Items listed here are always rolled NEED when they appear as group loot, even if they are not gear upgrades. Useful for crafting greens you keep needing in a dungeon. Mounts and ignored items are still skipped."])
	listMenu.needListNote = note

	local addItemsHelp = L["Item names or IDs separated by commas. Shift-click an item while this box has focus to add it, look up item IDs in item tooltips while the TyGear options are open, or assign \"Toggle hovered item on need list\" in Key Bindings and press it while hovering an item. New items are added near the top of the list."]

	local addHeader = listMenu:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	addHeader:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -14)
	addHeader:SetText(L["Add items"])

	local addNote = listMenu:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	addNote:SetPoint("TOPLEFT", addHeader, "BOTTOMLEFT", 0, -6)
	addNote:SetWidth(480)
	addNote:SetJustifyH("LEFT")
	addNote:SetText(addItemsHelp)
	listMenu.needListAddNote = addNote

	local editRow = CreateFrame("Frame", nil, listMenu)
	editRow:SetPoint("TOPLEFT", addNote, "BOTTOMLEFT", 0, -2)
	editRow:SetPoint("RIGHT", listMenu, "RIGHT", -8, 0)
	editRow:SetHeight(24)
	local editBox = CreateFrame("EditBox", "TyGearNeedListEditBox", editRow, "InputBoxTemplate")
	editBox:SetAutoFocus(false)
	editBox:SetHeight(20)
	editBox:SetPoint("LEFT", 4, 0)
	editBox:SetPoint("RIGHT", editRow, "RIGHT", -4, 0)
	local suppressEditBoxSave = false
	local function showNeedListText()
		suppressEditBoxSave = true
		editBox:SetText((TyGearDB and TyGearDB.NeedList) or "")
		editBox:SetCursorPosition(0)
		suppressEditBoxSave = false
	end
	local function saveNeedListText(text)
		if not TyGearDB then TyGearDB = {} end
		local previous = {}
		for _, itemID in ipairs(TyGearParseItemIDList(TyGearDB.NeedList or "")) do
			previous[itemID] = true
		end
		local parsed = TyGearParseItemIDList(text or "")
		local seen, newOnes, rest = {}, {}, {}
		for _, itemID in ipairs(parsed) do
			if not seen[itemID] then
				seen[itemID] = true
				if previous[itemID] then
					table.insert(rest, itemID)
				else
					table.insert(newOnes, itemID)
				end
			end
		end
		local ordered = {}
		for _, itemID in ipairs(newOnes) do
			table.insert(ordered, itemID)
		end
		for _, itemID in ipairs(rest) do
			table.insert(ordered, itemID)
		end
		TyGearDB.NeedList = table.concat(ordered, ", ")
		showNeedListText()
		if TyGearRefreshNeedList then TyGearRefreshNeedList() end
	end
	editBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	editBox:SetScript("OnEscapePressed", function(self)
		showNeedListText()
		self:ClearFocus()
	end)
	editBox:SetScript("OnEditFocusLost", function(self)
		if suppressEditBoxSave then return end
		saveNeedListText(self:GetText())
	end)
	editBox:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_NONE")
		GameTooltip:SetPoint("BOTTOMLEFT", self, "TOPLEFT")
		GameTooltip:AddLine(L["Add items"], NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, true)
		GameTooltip:AddLine(addItemsHelp, HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b, true)
		GameTooltip:Show()
	end)
	editBox:SetScript("OnLeave", function() GameTooltip:Hide() end)
	local function insertItemLink(text)
		if editBox:HasFocus() and text and string.find(text, "item:%d+") then
			editBox:Insert(" "..text)
		end
	end
	if ChatFrameUtil and ChatFrameUtil.InsertLink then
		hooksecurefunc(ChatFrameUtil, "InsertLink", insertItemLink)
	elseif ChatEdit_InsertLink then
		hooksecurefunc("ChatEdit_InsertLink", insertItemLink)
	end
	showNeedListText()

	local neededHeader = listMenu:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	neededHeader:SetPoint("TOPLEFT", editRow, "BOTTOMLEFT", 0, -14)
	neededHeader:SetText(L["Needed items"])

	local listContainer = CreateFrame("Frame", "TyGearNeedListContainer", listMenu)
	listContainer:SetPoint("TOPLEFT", neededHeader, "BOTTOMLEFT", 0, -8)
	listContainer:SetPoint("RIGHT", listMenu, "RIGHT", -8, 0)
	listContainer:SetHeight(20)

	local emptyText = listContainer:CreateFontString(nil, "ARTWORK", "GameFontDisable")
	emptyText:SetPoint("TOPLEFT", 0, 0)
	emptyText:SetText(L["No items are on the need list."])

	local rows = {}
	local rowHeight = 28
	local rowSerial = 0

	local function acquireRow()
		rowSerial = rowSerial + 1
		local row = CreateFrame("Frame", nil, listContainer)
		row:SetSize(500, rowHeight)
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(24, 24)
		row.icon:SetPoint("LEFT", 0, 0)
		row.check = CreateFrame("CheckButton", "TyGearNeedListRow"..rowSerial.."CheckButton", row, "InterfaceOptionsCheckButtonTemplate")
		row.check:SetPoint("LEFT", row.icon, "RIGHT", 2, 0)
		local templateText = _G[row.check:GetName().."Text"]
		if templateText then templateText:SetText("") end
		row.name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		row.name:SetPoint("LEFT", row.check, "RIGHT", 2, 0)
		row.name:SetPoint("RIGHT", row, "RIGHT", -4, 0)
		row.name:SetJustifyH("LEFT")
		row.name:SetWordWrap(false)
		row.check:SetScript("OnClick", function(self)
			local itemID = self:GetParent().itemID
			local need = self:GetChecked() and true or false
			TyGearSetNeedListItem(itemID, need)
			if need then
				PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
			else
				PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
			end
		end)
		row.check:SetScript("OnEnter", function(self)
			local parent = self:GetParent()
			if not parent.itemID then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetHyperlink("item:"..parent.itemID)
			GameTooltip:AddLine(L["Uncheck to remove this item from the need list."], 1, 0.82, 0, true)
			GameTooltip:Show()
		end)
		row.check:SetScript("OnLeave", function() GameTooltip:Hide() end)
		row:EnableMouse(true)
		row:SetScript("OnEnter", function(self)
			if not self.itemID then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetHyperlink("item:"..self.itemID)
			GameTooltip:AddLine(L["Uncheck to remove this item from the need list."], 1, 0.82, 0, true)
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", function() GameTooltip:Hide() end)
		return row
	end

	local function collectEntries()
		local entries = {}
		--preserve saved order so newly added IDs stay near the top
		for _, itemID in ipairs(TyGearParseItemIDList((TyGearDB and TyGearDB.NeedList) or "")) do
			local icon = GetItemInfoInstant and select(5, GetItemInfoInstant(itemID))
			local name = GetItemInfo and GetItemInfo(itemID)
			table.insert(entries, { id = itemID, icon = icon, name = name or ("item "..itemID) })
		end
		return entries
	end

	local function headerHeight()
		local function measured(fontString, fallback)
			local height = fontString:GetStringHeight() or fallback
			local estimate = math.ceil(math.max(#(fontString:GetText() or ""), 1) / 80) * 14
			if height < estimate then height = estimate end
			return height
		end
		--title + note + add header + add note + edit row + needed header + spacings
		return 28 + measured(note, 40) + 14 + 16 + 6 + measured(addNote, 28) + 2 + 24 + 14 + 16 + 8
	end

	function TyGearRefreshNeedList()
		if not listMenu:IsShown() and listContainer.builtOnce then
			listContainer.needsRefresh = true
			return
		end
		listContainer.builtOnce = true
		listContainer.needsRefresh = false
		if not editBox:HasFocus() then
			showNeedListText()
		end
		local entries = collectEntries()
		for index, entry in ipairs(entries) do
			local row = rows[index]
			if not row then
				row = acquireRow()
				rows[index] = row
			end
			row.itemID = entry.id
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", listContainer, "TOPLEFT", 0, -((index - 1) * rowHeight))
			row:SetPoint("TOPRIGHT", listContainer, "TOPRIGHT", 0, -((index - 1) * rowHeight))
			row.icon:SetTexture(entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
			row.name:SetText(entry.name or ("item "..entry.id))
			row.check:SetChecked(true)
			row:Show()
			if Item and Item.CreateFromItemID then
				local itemID = entry.id
				local item = Item:CreateFromItemID(itemID)
				item:ContinueOnItemLoad(function()
					if row.itemID ~= itemID or not row:IsShown() then return end
					local icon = item.GetItemIcon and item:GetItemIcon()
					local name = item.GetItemName and item:GetItemName()
					if icon then row.icon:SetTexture(icon) end
					if name then row.name:SetText(name) end
				end)
			end
		end
		for index = #entries + 1, #rows do
			rows[index]:Hide()
		end
		emptyText:SetShown(#entries == 0)
		local height = #entries == 0 and 20 or (#entries * rowHeight)
		listContainer:SetHeight(height)
		listMenu:SetHeight(headerHeight() + height + 16)
		local scrollFrame = listMenu:GetParent()
		if scrollFrame and scrollFrame.UpdateScrollChildRect then
			scrollFrame:UpdateScrollChildRect()
		end
	end

	listMenu:HookScript("OnShow", function()
		if listContainer.needsRefresh or not listContainer.builtOnce then
			TyGearRefreshNeedList()
		end
	end)
	TyGearRefreshNeedList()
end

local function optionsSetup(optionsMenu)
	local i = 0
	local frame = {}
	frame[i] = optionsMenu:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	frame[i]:SetPoint("TOPLEFT", 8, -8)
	frame[i]:SetText("TyGear")
	i = i + 1
	frame[i] = optionsMenu:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	frame[i]:SetPoint("TOPLEFT", 8, -28)
	frame[i]:SetJustifyH("LEFT")
	frame[i]:SetText(L["Fork of AutoGear by Synthetikaryote and BujuArena."])
	local optionsPage = newOptionsPage(optionsMenu)
	TyGearOptionsPage = optionsPage
	--keep each former tab's options together, in the order those tabs first appear
	local tabOrder, buckets = {}, {}
	for _, option in ipairs(TyGearOptions) do
		local tab = option["tab"] or L["Other"]
		if not buckets[tab] then
			buckets[tab] = {}
			table.insert(tabOrder, tab)
		end
		table.insert(buckets[tab], option)
	end
	local tabRank = {
		[L["Evaluation"]] = 1,
		[L["Loot"]] = 2,
		[L["Tooltips"]] = 3,
		[L["Vendor"]] = 4,
		[L["Chat"]] = 5,
	}
	table.sort(tabOrder, function(a, b)
		local rankA, rankB = tabRank[a] or 50, tabRank[b] or 50
		if rankA ~= rankB then return rankA < rankB end
		return tostring(a) < tostring(b)
	end)
	local orderedOptions = {}
	for _, tab in ipairs(tabOrder) do
		for _, option in ipairs(buckets[tab]) do
			table.insert(orderedOptions, option)
		end
	end
	TyGearOptions = orderedOptions

	--Scan Bags sits above Evaluation so it is not buried under options and does not indent later rows
	optionsPage:AddScanButton()

	local function addOptionsNote(page, text)
		local holder = CreateFrame("Frame", nil, page)
		local font = holder:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
		font:SetPoint("TOPLEFT", 4, -2)
		font:SetPoint("TOPRIGHT", holder, "TOPRIGHT", -4, -2)
		font:SetJustifyH("LEFT")
		if font.SetMaxLines then font:SetMaxLines(4) end
		font:SetText(TyGearColorize(text))
		local height = font:GetStringHeight()
		local estimate = math.ceil(math.max(#text, 1) / 80) * 14
		if not height or height < estimate then height = estimate end
		holder:SetHeight(height + 8)
		optionsPage:AddBlockRow(holder)
		return holder
	end

	local function addItemIDEditBox(page, optionName, label, description, editBoxPostHook)
		local editRow = CreateFrame("Frame", nil, page)
		editRow:SetSize(500, 24)
		local labelText = editRow:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		labelText:SetPoint("LEFT", 4, 0)
		labelText:SetText(TyGearColorize(label))
		local editBox = CreateFrame("EditBox", "TyGear"..optionName.."EditBox", editRow, "InputBoxTemplate")
		editBox:SetAutoFocus(false)
		editBox:SetSize(280, 20)
		editBox:SetPoint("RIGHT", editRow, "RIGHT", -4, 0)
		local function showSavedText()
			editBox:SetText(TyGearSettingsTable(optionName)[optionName] or "")
			editBox:SetCursorPosition(0)
		end
		showSavedText()
		editBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
		editBox:SetScript("OnEscapePressed", function(self)
			showSavedText()
			self:ClearFocus()
		end)
		editBox:SetScript("OnEditFocusLost", function(self)
			TyGearSettingsTable(optionName)[optionName] = table.concat(TyGearParseItemIDList(self:GetText()), ", ")
			showSavedText()
			if editBoxPostHook then editBoxPostHook() end
		end)
		editBox:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_NONE")
			GameTooltip:SetPoint("BOTTOMLEFT", self, "TOPLEFT")
			GameTooltip:AddLine(TyGearColorize(label), NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, true)
			GameTooltip:AddLine(TyGearColorize(description), HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b, true)
			local itemIDs = TyGearParseItemIDList(TyGearSettingsTable(optionName)[optionName] or "")
			if #itemIDs > 0 then
				GameTooltip:AddLine(" ")
				for _, itemID in ipairs(itemIDs) do
					--the item's link is nil until the client has cached the item
					GameTooltip:AddDoubleLine((select(2, GetItemInfo(itemID))) or ("item "..itemID), itemID)
				end
			end
			GameTooltip:Show()
		end)
		editBox:SetScript("OnLeave", function() GameTooltip:Hide() end)
		optionsPage:EnableWheel(editBox)
		local function insertItemLink(text)
			if editBox:HasFocus() and text and string.find(text, "item:%d+") then
				editBox:Insert(text)
			end
		end
		if ChatFrameUtil and ChatFrameUtil.InsertLink then
			hooksecurefunc(ChatFrameUtil, "InsertLink", insertItemLink)
		elseif ChatEdit_InsertLink then
			hooksecurefunc("ChatEdit_InsertLink", insertItemLink)
		end
		optionsPage:AddBlockRow(editRow, 4)
		return editBox
	end

	local function addActiveSpecCallout(page)
		local holder = CreateFrame("Frame", nil, page)
		holder:SetSize(500, 24)
		local font = holder:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		font:SetPoint("LEFT", 4, 0)
		font:SetPoint("RIGHT", -4, 0)
		font:SetJustifyH("LEFT")
		font:SetWordWrap(false)
		font:SetText(TyGearActiveSpecializationLine())
		TyGearActiveSpecCallout = font
		holder:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_NONE")
			GameTooltip:SetPoint("BOTTOMLEFT", self, "TOPLEFT")
			GameTooltip:AddLine(L["Active specialization"], NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, true)
			GameTooltip:AddLine(L["The talent tree with the most points. TyGear uses this unless Override specialization is on. With no points spent, this is None, the general profile."], HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b, true)
			GameTooltip:Show()
		end)
		holder:SetScript("OnLeave", function() GameTooltip:Hide() end)
		holder:EnableMouse(true)
		optionsPage:EnableWheel(holder)
		optionsPage:AddBlockRow(holder, 2)
	end

	local function beginListedOption(v)
		local page = optionsPage:BeginOption(v["tab"] or L["Other"], v["section"])
		if (v["tab"] or L["Other"]) == L["Evaluation"] and not optionsPage.activeSpecShown then
			optionsPage.activeSpecShown = true
			addActiveSpecCallout(page)
		end
		return page
	end

	--loop through options table to build our options menu programmatically
	for _, v in ipairs(TyGearOptions) do (function()
		if (not v["option"]) or ((v["shouldUse"] ~= nil) and (v["shouldUse"] == false)) then return end
		--manual iterator to be able to start from 0 and add another one outside the loop
		i = i + 1

		--standalone item-ID lists get a labeled section row, not a checkbox with a mystery box beside it
		if v["editBox"] then
			local page = beginListedOption(v)
			if v["description"] then
				addOptionsNote(page, v["description"])
			end
			frame[i] = addItemIDEditBox(page, v["option"], v["label"], v["description"] or "", v["editBoxPostHook"])
			return
		end

		--standalone string dropdown (flat label/value list), e.g. MythicSim vs Pawn
		if v["dropdown"] and v["options"] then
			local page = beginListedOption(v)
			local row = CreateFrame("Frame", nil, page)
			row:SetSize(500, 40)
			local labelText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
			labelText:SetPoint("TOPLEFT", 4, -2)
			labelText:SetText(TyGearColorize(v["label"]))
			local descText
			if v["description"] then
				descText = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
				descText:SetPoint("TOPLEFT", labelText, "BOTTOMLEFT", 0, -2)
				descText:SetJustifyH("LEFT")
				if descText.SetMaxLines then descText:SetMaxLines(3) end
				descText:SetText(TyGearColorize(v["description"]))
			end
			local width = v["dropdownWidth"] or 220
			local dropDown
			local function dropdownOptions()
				if type(v["options"]) == "function" then
					return v["options"]()
				end
				return v["options"]
			end
			local function labelForValue(value)
				for _, entry in ipairs(dropdownOptions()) do
					if entry["value"] == value then
						return entry["label"]
					end
				end
				return value
			end
			local function entryIsDisabled(entry)
				return entry and entry["disabled"] and true or false
			end
			if useModernDropdowns then
				dropDown = CreateFrame("DropdownButton", "TyGear"..v["option"].."Dropdown", row, "WowStyle1DropdownTemplate")
				dropDown:SetPoint("RIGHT", row, "RIGHT", -2, 0)
				dropDown:SetWidth(width)
			else
				dropDown = CreateFrame("FRAME", "TyGear"..v["option"].."Dropdown", row, "UIDropDownMenuTemplate")
				dropDown:SetPoint("RIGHT", row, "RIGHT", 16, 0)
				UIDropDownMenu_SetWidth(dropDown, width)
			end
			if descText then
				descText:SetPoint("RIGHT", dropDown, "LEFT", -12, 0)
			end
			labelText:SetPoint("RIGHT", dropDown, "LEFT", -12, 0)
			local function measureDropdownRow()
				local titleH = labelText:GetStringHeight() or 14
				local descH = descText and (descText:GetStringHeight() or 12) or 0
				row:SetHeight(math.max(titleH + ((descH > 0) and (descH + 2) or 0) + 8, 28))
			end
			row.tyGearMeasure = measureDropdownRow
			measureDropdownRow()
			setDropdownText(dropDown, labelForValue(TyGearSettingsTable(v["option"])[v["option"]]))
			dropDown.SetValue = function(self, value)
				for _, entry in ipairs(dropdownOptions()) do
					if entry["value"] == value and entryIsDisabled(entry) then
						return
					end
				end
				TyGearSettingsTable(v["option"])[v["option"]] = value
				setDropdownText(self, labelForValue(value))
				closeDropdownMenu(self)
			end
			if v["dropdownPostHook"] then
				hooksecurefunc(dropDown, "SetValue", v["dropdownPostHook"])
			end
			if useModernDropdowns then
				dropDown:SetupMenu(function(dropdown, rootDescription)
					for _, entry in ipairs(dropdownOptions()) do
						local radio = rootDescription:CreateRadio(TyGearColorize(entry["label"]), function()
							return TyGearSettingsTable(v["option"])[v["option"]] == entry["value"]
						end, function()
							if entryIsDisabled(entry) then return end
							dropdown:SetValue(entry["value"])
						end)
						if entryIsDisabled(entry) and radio and radio.SetEnabled then
							radio:SetEnabled(false)
						end
					end
				end)
			else
				UIDropDownMenu_Initialize(dropDown, function(self)
					local info = UIDropDownMenu_CreateInfo()
					info.func = self.SetValue
					for _, entry in ipairs(dropdownOptions()) do
						info.text = TyGearColorize(entry["label"])
						info.arg1 = entry["value"]
						info.checked = (TyGearSettingsTable(v["option"])[v["option"]] == entry["value"])
						info.disabled = entryIsDisabled(entry)
						UIDropDownMenu_AddButton(info)
					end
				end)
			end
			optionsPage:EnableWheel(dropDown)
			if dropDown.HookScript and not dropDown.tyGearWheelShowHook then
				dropDown.tyGearWheelShowHook = true
				dropDown:HookScript("OnShow", function(self)
					optionsPage:EnableWheel(self)
				end)
			end
			frame[i] = row
			optionsPage:AddBlockRow(frame[i])
			--The toggle below speaks StatWeightSystem names. Other dropdowns only use SetValue.
			if v["option"] ~= "StatWeightSystem" then return end
			_G["TyGearToggle"..v["option"]] = function(force)
				local system
				local lowered = type(force) == "string" and string.lower(force) or nil
				if force == true or lowered == "pawn" then
					if not TyGearIsPawnReady() then
						TyGearPrint("TyGear: "..L["Pawn is not installed."], 0)
						return
					end
					system = TyGearStatWeightSystemPawn
				elseif lowered == "foreverlevelingbis" or lowered == "foreverleveling" or lowered == "foreverbis" or lowered == "flb" then
					if not TyGearIsForeverLevelingBISReady() then
						TyGearPrint("TyGear: "..L["Forever Leveling BiS is not installed."], 0)
						return
					end
					system = TyGearStatWeightSystemForeverLevelingBIS
				elseif lowered == "personal" or lowered == "personalstatweights" or lowered == "custom" then
					system = TyGearStatWeightSystemPersonal
				elseif force == false or lowered == "mythicsim" or lowered == "mythic" then
					system = TyGearStatWeightSystemMythicSim
				else
					-- Cycle: MythicSim → Pawn (if ready) → Forever Leveling BiS (if ready) → Personal → MythicSim
					local current = TyGearGetStatWeightSystem()
					local order = { TyGearStatWeightSystemMythicSim }
					if TyGearIsPawnReady() then
						table.insert(order, TyGearStatWeightSystemPawn)
					end
					if TyGearIsForeverLevelingBISReady() then
						table.insert(order, TyGearStatWeightSystemForeverLevelingBIS)
					end
					table.insert(order, TyGearStatWeightSystemPersonal)
					local nextSystem = order[1]
					for i, candidate in ipairs(order) do
						if candidate == current then
							nextSystem = order[(i % #order) + 1]
							break
						end
					end
					system = nextSystem
				end
				if system == TyGearStatWeightSystemPawn and not TyGearIsPawnReady() then
					TyGearPrint("TyGear: "..L["Pawn is not installed."], 0)
					return
				end
				if system == TyGearStatWeightSystemForeverLevelingBIS and not TyGearIsForeverLevelingBISReady() then
					TyGearPrint("TyGear: "..L["Forever Leveling BiS is not installed."], 0)
					return
				end
				if not TyGearSetStatWeightSystem(system) then
					return
				end
				setDropdownText(dropDown, labelForValue(TyGearDB.StatWeightSystem))
				local message
				if system == TyGearStatWeightSystemPawn then
					message = L["Using Pawn for evaluating gear upgrades is now enabled."]
				elseif system == TyGearStatWeightSystemForeverLevelingBIS then
					message = L["Using Forever Leveling BiS for evaluating gear upgrades is now enabled."]
				elseif system == TyGearStatWeightSystemPersonal then
					message = L["Using Personal Stat Weights for evaluating gear upgrades is now enabled."]
				else
					message = L["Using MythicSim for evaluating gear upgrades is now enabled."]
				end
				TyGearPrint("TyGear: "..message, 0)
			end
			-- Keep the old slash name working: "/tg pawn on|off"
			_G["TyGearToggleUsePawn"] = function(force)
				_G["TyGearToggleStatWeightSystem"](force)
			end
			if v["cliCommands"] then
				hooksecurefunc(SlashCmdList, "TyGear", function(msg, ...)
					local command = nil
					local force = nil
					for _, w in ipairs(v["cliCommands"]) do
						if param1 == w then
							command = v["option"]
							shouldPrintHelp = false
							if param2 == "mythicsim" or param2 == "mythic" or param2 == "pawn"
							or param2 == "foreverlevelingbis" or param2 == "foreverleveling" or param2 == "foreverbis" or param2 == "flb"
							or param2 == "personal" or param2 == "personalstatweights" then
								force = param2
								break
							end
							if not v["cliTrue"] then break end
							for _, x in ipairs(v["cliTrue"]) do
								if param2 == x then
									force = true
									break
								end
							end
							if force ~= nil or (not v["cliFalse"]) then break end
							for _, x in ipairs(v["cliFalse"]) do
								if param2 == x then
									force = false
									break
								end
							end
							break
						end
					end
					if command then _G["TyGearToggle"..command](force) end
				end)
			end
			return
		end

		--standalone gear-slot grid: checked slots are locked, with no master toggle
		if v["slotGrid"] then
			local page = beginListedOption(v)
			if v["description"] then
				addOptionsNote(page, v["description"])
			end
			local lockedSlots = TyGearGetLockedGearSlots()
			local slotList = {}
			for slot = INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED do
				if TyGearIsLockableGearSlot(slot) then
					table.insert(slotList, slot)
				end
			end
			frame[i] = createGearSlotCheckboxGrid(
				page,
				"TyGear"..v["option"].."Grid",
				"TyGearLockSlot",
				slotList,
				function(gearSlot)
					return lockedSlots[gearSlot] and lockedSlots[gearSlot].enabled
				end,
				function(gearSlot, tick)
					if not lockedSlots[gearSlot] then
						lockedSlots[gearSlot] = {
							["label"] = TyGearGetLockedGearSlotLabel(gearSlot),
							["enabled"] = false
						}
					end
					lockedSlots[gearSlot].enabled = tick
					if TyGearUpdateBestItems then TyGearUpdateBestItems() end
				end,
				TyGearColorize(v["description"] or ""),
				function(widget) optionsPage:EnableWheel(widget) end
			)
			optionsPage:AddBlockRow(frame[i], 4)
			return
		end

		--function to run when toggling this option by clicking the checkbox
		_G["TyGearSimpleToggle"..v["option"]] = function(self, value)
			if v["cvar"] then
				SetCVar(v["cvar"], value and 1 or 0)
			end
			TyGearSettingsTable(v["option"])[v["option"]] = value
			TyGearPrint("TyGear: "..(TyGearSettingsTable(v["option"])[v["option"]] and v["toggleDescriptionTrue"] or v["toggleDescriptionFalse"]), 3)
			TyGearPrint("TyGear: TyGearDB."..v["option"].." is "..(TyGearSettingsTable(v["option"])[v["option"]] and "true" or "false")..".",3)
		end

		--function to run when toggling this option via command-line interface
		_G["TyGearToggle"..v["option"]] = function(force)
			if TyGearSettingsTable(v["option"])[v["option"]] == nil then return end
			if force ~= nil then
				TyGearSettingsTable(v["option"])[v["option"]] = force
			else
				TyGearSettingsTable(v["option"])[v["option"]] = (not TyGearSettingsTable(v["option"])[v["option"]])
			end
			if v["cvar"] then SetCVar(v["cvar"], force or (GetCVarBool(v["cvar"]) and 0 or 1)) end
			TyGearPrint("TyGear: "..(TyGearSettingsTable(v["option"])[v["option"]] and v["toggleDescriptionTrue"] or v["toggleDescriptionFalse"]), 0)
			if _G["TyGear"..v["option"].."CheckButton"] == nil then return end
			_G["TyGear"..v["option"].."CheckButton"]:SetChecked(v["cvar"] and GetCVarBool(v["cvar"]) or TyGearSettingsTable(v["option"])[v["option"]])
		end

		if v["togglePostHook"] then
			hooksecurefunc("TyGearSimpleToggle"..v["option"], v["togglePostHook"])
			hooksecurefunc("TyGearToggle"..v["option"], v["togglePostHook"])
		end

		--set description, and if this option is a cvar shortcut, add explanation of cvars to description
		local description = v["description"]..(v["cvar"] and "\n\n"..L["This is a shortcut for the \"%s\" CVar provided by Blizzard.  Toggling this will toggle that CVar."]:format(v["cvar"]) or "")

		--make a Waypoint-style block row for this option (title/description left, checkbox right)
		local page = beginListedOption(v)
		frame[i] = newBlockSettingRow(page, v["option"], v["label"], description, _G["TyGearSimpleToggle"..v["option"]])
		local check = frame[i].check
		check:SetChecked(TyGearSettingsTable(v["option"])[v["option"]]) --set initial checked state based on db
		optionsPage:AddBlockRow(frame[i])

		if v["playSound"] then
			local playButton = CreateFrame("Button", "TyGear"..v["option"].."PlayButton", frame[i])
			playButton:SetSize(26, 26)
			playButton:SetPoint("RIGHT", check, "LEFT", -6, 0)
			playButton:SetFrameLevel((frame[i]:GetFrameLevel() or 1) + 5)
			playButton:RegisterForClicks("LeftButtonUp")
			playButton:EnableMouse(true)
			--The stopwatch uses this spellbook page arrow as its play button.
			playButton:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
			playButton:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down")
			playButton:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
			local fileName = frame[i]:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
			fileName:SetPoint("RIGHT", playButton, "LEFT", -4, 0)
			fileName:SetText(TyGearGetUpgradeChimeFileName())
			if frame[i].title then
				frame[i].title:SetPoint("RIGHT", fileName, "LEFT", -10, 0)
			end
			if frame[i].description then
				frame[i].description:SetPoint("RIGHT", fileName, "LEFT", -10, 0)
			end
			playButton:SetScript("OnClick", function()
				TyGearPlayUpgradeEquippedChime(true)
			end)
			playButton:SetScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_NONE")
				GameTooltip:SetPoint("BOTTOMLEFT", self, "TOPLEFT")
				GameTooltip:AddLine(TyGearGetUpgradeChimeFileName(), NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, true)
				GameTooltip:AddLine(L["Play this sound. This works even when the option is off."], HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b, true)
				GameTooltip:Show()
			end)
			playButton:SetScript("OnLeave", function()
				GameTooltip:Hide()
			end)
			optionsPage:EnableWheel(playButton)
		end

		--if this has a child defined and it should be used, build its child
		if v["child"] and ((v["child"]["shouldUse"] == nil) or (v["child"]["shouldUse"] and (v["child"]["shouldUse"] ~= false))) then

			--if the child is a dropdown, build it that way
			if v["child"]["options"] then

				local width = 250
				if useModernDropdowns then
					frame[i].dropDown = CreateFrame("DropdownButton", "TyGear"..v["child"]["option"].."Dropdown", frame[i], "WowStyle1DropdownTemplate")
					-- Sit left of the checkbox inside the block row.
					frame[i].dropDown:SetPoint("RIGHT", check, "LEFT", -8, 0)
					frame[i].dropDown:SetWidth(width)
				else
					frame[i].dropDown = CreateFrame("FRAME", "TyGear"..v["child"]["option"].."Dropdown", frame[i], "UIDropDownMenuTemplate")
					frame[i].dropDown:SetPoint("RIGHT", check, "LEFT", 12, 0)
					UIDropDownMenu_SetWidth(frame[i].dropDown, width)
				end
				if frame[i].title then
					frame[i].title:SetPoint("RIGHT", frame[i].dropDown, "LEFT", -10, 0)
				end
				if frame[i].description then
					frame[i].description:SetPoint("RIGHT", frame[i].dropDown, "LEFT", -10, 0)
				end
				--newDropdown(v["child"]["option"], v["child"]["label"], v["child"]["description"], _G["TyGearSelectFrom"..v["child"]["option"].."Dropdown"], v["child"]["options"], optionsMenu)
				--frame[i].dropDown:SetHitRectInsets(0, -280, 0, 0) --change click region to not be super wide
				if type(TyGearSettingsTable(v["child"]["option"])[v["child"]["option"]]) == 'string' then
					setDropdownText(frame[i].dropDown, TyGearSettingsTable(v["child"]["option"])[v["child"]["option"]])
				elseif type(TyGearSettingsTable(v["child"]["option"])[v["child"]["option"]]) == 'table' then
					local label
					for _, l in pairs(v["child"]["options"]) do
						if l["enabled"] then
							if label then
								label = label..", "..l["label"]
							else
								label = l["label"]
							end
						end
					end
					setDropdownText(_G["TyGear"..v["child"]["option"].."Dropdown"], label)
				end

				--function to run when using this dropdown
				_G["TyGear"..v["child"]["option"].."Dropdown"].SetValue = function(self, value)
					if type(TyGearSettingsTable(v["child"]["option"])[v["child"]["option"]]) == 'string' then
						TyGearSettingsTable(v["child"]["option"])[v["child"]["option"]] = value
						setDropdownText(_G["TyGear"..v["child"]["option"].."Dropdown"], value)
						closeDropdownMenu(_G["TyGear"..v["child"]["option"].."Dropdown"])
					end
				end

				if v["child"]["dropdownPostHook"] then
					hooksecurefunc(_G["TyGear"..v["child"]["option"].."Dropdown"], "SetValue", v["child"]["dropdownPostHook"])
				end

				if useModernDropdowns then
					--same menu as the UIDropDownMenu version below, built with the modern menu system
					frame[i].dropDown:SetupMenu(function(dropdown, rootDescription)
						if type(TyGearSettingsTable(v["child"]["option"])[v["child"]["option"]]) == 'string' then
							for _, j in ipairs(v["child"]["options"]) do
								--the label is selected when the stored value is one of its subLabels; it only opens its submenu, so its responder does nothing
								local labelDescription = rootDescription:CreateRadio(dropdownEntryText(j), function()
									return (TyGearSettingsTable(v["child"]["option"])[v["child"]["option"]] and string.match(TyGearSettingsTable(v["child"]["option"])[v["child"]["option"]], "^"..j["label"]..":")) and true or false
								end, function() end)
								for _, z in ipairs(j["subLabels"] or {}) do
									local value = j["label"]..": "..z
									labelDescription:CreateRadio(dropdownEntryText(j, z), function()
										return (TyGearSettingsTable(v["child"]["option"])[v["child"]["option"]] == value) or (TyGearSettingsTable(v["child"]["option"])[v["child"]["option"]] == z)
									end, function()
										dropdown:SetValue(value)
									end)
								end
							end
						elseif type(TyGearSettingsTable(v["child"]["option"])[v["child"]["option"]]) == 'table' then
							for _, j in pairs(v["child"]["options"]) do
								--checkboxes keep the menu open, like keepShownOnClick
								rootDescription:CreateCheckbox(TyGearColorize(j["label"]), function()
									return j["enabled"] and true or false
								end, function()
									j["enabled"] = not j["enabled"]
									local label
									for _, l in pairs(v["child"]["options"]) do
										if l["enabled"] then
											if label then
												label = label..", "..l["label"]
											else
												label = l["label"]
											end
										end
									end
									setDropdownText(dropdown, label)
								end)
							end
						end
					end)
				else
					UIDropDownMenu_Initialize(_G["TyGear"..v["child"]["option"].."Dropdown"], function(self, level, menuList)
						local info = UIDropDownMenu_CreateInfo()
						if (level or 1) == 1 then
							--display the labels
							if type(TyGearSettingsTable(v["child"]["option"])[v["child"]["option"]]) == 'string' then
								for _, j in ipairs(v["child"]["options"]) do
									info.text = dropdownEntryText(j)
									info.checked = (TyGearSettingsTable(v["child"]["option"])[v["child"]["option"]] and (string.match(TyGearSettingsTable(v["child"]["option"])[v["child"]["option"]], "^"..j["label"]..":") and true or false) or false)
									info.menuList = j
									info.hasArrow = (j["subLabels"] and true or false)
									UIDropDownMenu_AddButton(info)
								end
							elseif type(TyGearSettingsTable(v["child"]["option"])[v["child"]["option"]]) == 'table' then
								for _, j in pairs(v["child"]["options"]) do
									info.text = TyGearColorize(j["label"])
									info.keepShownOnClick = true
									info.isNotRadio = true
									info.checked = j["enabled"]
									info.func = function(self) j["enabled"] = self.checked
										local label
										for _, l in pairs(v["child"]["options"]) do
											if l["enabled"] then
												if label then
													label = label..", "..l["label"]
												else
													label = l["label"]
												end
											end
										end
										setDropdownText(_G["TyGear"..v["child"]["option"].."Dropdown"], label)
									end
									info.menuList = j
									info.hasArrow = (j["subLabels"] and true or false)
									UIDropDownMenu_AddButton(info)
								end
							end
						else
							--display the subLabels
							info.func = self.SetValue
							if menuList["subLabels"] then
								for _, z in ipairs(menuList["subLabels"]) do
									info.text = dropdownEntryText(menuList, z)
									info.arg1 = menuList["label"]..": "..z
									info.checked = ((TyGearSettingsTable(v["child"]["option"])[v["child"]["option"]] == info.arg1) or (TyGearSettingsTable(v["child"]["option"])[v["child"]["option"]] == z))
									UIDropDownMenu_AddButton(info, level)
								end
							end
						end
					end)
				end
				--after SetupMenu so the page-scroll handler wins over selection cycling.
				--Re-apply on show: DropdownSelectionTextMixin:OnShow regenerates the menu,
				--and Override Pawn scale (and the other option dropdowns) must keep scrolling
				--the options page instead of rotating the selected radio.
				optionsPage:EnableWheel(frame[i].dropDown)
				if frame[i].dropDown.HookScript and not frame[i].dropDown.tyGearWheelShowHook then
					frame[i].dropDown.tyGearWheelShowHook = true
					frame[i].dropDown:HookScript("OnShow", function(self)
						optionsPage:EnableWheel(self)
					end)
				end

			--if the child is a text box for a list of item IDs, build it that way
			elseif v["child"]["editBox"] then
				local width = 250
				local editBox = CreateFrame("EditBox", "TyGear"..v["child"]["option"].."EditBox", page, "InputBoxTemplate")
				frame[i].editBox = editBox
				--the checkbox's click region reaches 280 pixels to its right, so start past it
				editBox:SetPoint("LEFT", frame[i], "RIGHT", width + 32, 0)
				editBox:SetSize(width, 20)
				editBox:SetAutoFocus(false)
				optionsPage:EnableWheel(editBox)
				local function showSavedText()
					editBox:SetText(TyGearSettingsTable(v["child"]["option"])[v["child"]["option"]])
					editBox:SetCursorPosition(0)
				end
				showSavedText()
				editBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
				editBox:SetScript("OnEscapePressed", function(self)
					showSavedText()
					self:ClearFocus()
				end)
				editBox:SetScript("OnEditFocusLost", function(self)
					TyGearSettingsTable(v["child"]["option"])[v["child"]["option"]] = table.concat(TyGearParseItemIDList(self:GetText()), ", ")
					showSavedText()
				end)
				editBox:SetScript("OnEnter", function(self)
					GameTooltip:SetOwner(self, "ANCHOR_NONE")
					GameTooltip:SetPoint("BOTTOMLEFT", self, "TOPLEFT")
					GameTooltip:AddLine(TyGearColorize(v["child"]["label"]), NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, true)
					GameTooltip:AddLine(TyGearColorize(v["child"]["description"]), HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b, true)
					local itemIDs = TyGearParseItemIDList(TyGearSettingsTable(v["child"]["option"])[v["child"]["option"]])
					if #itemIDs > 0 then
						GameTooltip:AddLine(" ")
						for _, itemID in ipairs(itemIDs) do
							--the item's link is nil until the client has cached the item
							GameTooltip:AddDoubleLine((select(2, GetItemInfo(itemID))) or ("item "..itemID), itemID)
						end
					end
					GameTooltip:Show()
				end)
				editBox:SetScript("OnLeave", function() GameTooltip:Hide() end)
				--shift-clicking an item inserts its link into the chat edit box, so do the same for this box while it has focus
				local function insertItemLink(text)
					if editBox:HasFocus() and text and string.find(text, "item:%d+") then
						editBox:Insert(text)
					end
				end
				if ChatFrameUtil and ChatFrameUtil.InsertLink then
					hooksecurefunc(ChatFrameUtil, "InsertLink", insertItemLink)
				elseif ChatEdit_InsertLink then
					hooksecurefunc("ChatEdit_InsertLink", insertItemLink)
				end
			end
		end

		--if this is a cvar, hook Blizzard's SetCVar function to update our checkbox
		if v["cvar"] then
			hooksecurefunc("SetCVar",function(CVar, ...)
				if ((_G["TyGear"..v["option"].."CheckButton"] ~= nil) and (CVar == v["cvar"])) then
					_G["TyGear"..v["option"].."CheckButton"]:SetChecked(GetCVarBool(v["cvar"]))
				end
			end)
		end

		--if command-line interface commands are defined, add handling of those to the end of our cli command handling function
		if v["cliCommands"] then
			hooksecurefunc(SlashCmdList, "TyGear", function(msg, ...)
				local command = nil
				local force = nil
				for _, w in ipairs(v["cliCommands"]) do
					if param1 == w then
						command = v["option"]
						shouldPrintHelp = false
						if not v["cliTrue"] then break end
						for _, x in ipairs(v["cliTrue"]) do
							if param2 == x then
								force = true
								break
							end
						end
						if force or (not v["cliFalse"]) then break end
						for _, x in ipairs(v["cliFalse"]) do
							if param2 == x then
								force = false
								break
							end
						end
						break
					end
				end
				if command then _G["TyGearToggle"..command](force) end
			end)
		end
	end)() end
	hooksecurefunc(SlashCmdList, "TyGear", function(msg, ...)
		if shouldPrintHelp then
			TyGearPrintHelp()
			shouldPrintHelp = false
		end
	end)
	--Forever hosts Ignore on the Ignored List Settings tab instead of the main page
	if not IS_WOW_FOREVER then
		buildIgnoreSection(optionsPage)
	end
	local optionsScroll = optionsMenu:GetParent()
	if optionsScroll and optionsScroll.HookScript then
		optionsScroll:HookScript("OnShow", function()
			if TyGearRefreshActiveSpecCallout then TyGearRefreshActiveSpecCallout() end
		end)
	end
	optionsPage:Finish()
end

--Personal Stat Weights tab: one block of stat boxes per spec of the logged-in class, import/export at the bottom
local function buildPersonalStatWeightsPage(listMenu)
	local classToken = UnitClassBase and UnitClassBase("player")
	if classToken then
		TyGearEnsurePersonalClassWeights(classToken)
	end
	local title = listMenu:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 8, -8)
	title:SetText(L["Personal Stat Weights"])

	local note = listMenu:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	note:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	note:SetWidth(480)
	note:SetJustifyH("LEFT")
	note:SetText(L["Every spec starts filled with its MythicSim weights. Specs MythicSim does not publish start from TyGear's built-in profile instead. Change any number to make it yours. 0 means that stat adds nothing to the score. On WoW Forever, Hit and Spell Hit share the higher weight, and Crit and Spell Crit do the same. None is the general profile, used when no talent tree has points and Override specialization is off.\n\nWhen Stat weight system is Personal Stat Weights, item tooltips show TyGear: Personal score:"])
	listMenu.personalNote = note

	local status = listMenu:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	status:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -10)
	status:SetWidth(480)
	status:SetJustifyH("LEFT")
	listMenu.personalStatus = status

	local resetButton
	if classToken then
		resetButton = CreateFrame("Button", "TyGearPersonalStatWeightsResetButton", listMenu, "UIPanelButtonTemplate")
		resetButton:SetSize(200, 22)
		resetButton:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, -8)
		resetButton:SetText(L["Reset to default"])
		resetButton:SetScript("OnClick", function()
			local editors = TyGearPersonalWeightEditors
			if editors and editors.specs then
				for _, specEditors in pairs(editors.specs) do
					if specEditors.edits then
						for _, edit in pairs(specEditors.edits) do
							edit.tyGearSuppress = true
							if edit.ClearFocus then edit:ClearFocus() end
							edit.tyGearSuppress = nil
						end
					end
				end
			end
			TyGearResetPersonalClassWeights(classToken)
			TyGearPrint("TyGear: "..L["Reset personal stat weights to MythicSim."], 0)
		end)
		resetButton:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_NONE")
			GameTooltip:SetPoint("BOTTOMLEFT", self, "TOPLEFT")
			GameTooltip:AddLine(L["Reset to default"], NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, true)
			GameTooltip:AddLine(L["Replace every spec on this tab with its MythicSim weights. Specs MythicSim does not publish go back to TyGear's built-in profile."], HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b, true)
			GameTooltip:Show()
		end)
		resetButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
		listMenu.personalResetButton = resetButton
	end

	local function statusText()
		if not classToken then
			return L["Log in on a character to edit personal stat weights."]
		end
		local localized = (TyGearClassList and TyGearClassList[classToken]) or classToken
		local _, evalClass, evalSpec = TyGearGetClassAndSpec()
		local evalLocalized = (TyGearClassList and TyGearClassList[evalClass]) or evalClass or ""
		if TyGearGetStatWeightSystem() ~= TyGearStatWeightSystemPersonal then
			local current = TyGearGetStatWeightSystem()
			if current == TyGearStatWeightSystemForeverLevelingBIS then
				current = L["Forever Leveling BiS"]
			end
			return string.format(L["These weights are used when Stat weight system is set to Personal Stat Weights. TyGear is currently using %s."], current)
		end
		if evalClass ~= classToken then
			return string.format(L["Override specialization is using %s. Edit those weights on that class. This tab is your %s."], (evalSpec or "").." "..evalLocalized, localized)
		end
		return string.format(L["TyGear is scoring %s with these weights. Tooltips show TyGear: Personal score:"], evalSpec or "None")
	end

	local function specHeaderText(specName)
		local label = TyGearSpecColoredText(classToken, specName)
		local _, evalClass, evalSpec = TyGearGetClassAndSpec()
		if evalClass == classToken and evalSpec == specName then
			label = label.." "..L["(active)"]
		end
		return label
	end

	TyGearPersonalWeightEditors = {
		classToken = classToken,
		status = status,
		statusText = statusText,
		specHeader = specHeaderText,
		specs = {},
	}

	local function forwardWheel(widget)
		if not widget or not widget.EnableMouseWheel then return end
		widget:EnableMouseWheel(true)
		widget:SetScript("OnMouseWheel", function(_, delta)
			local scroll = listMenu:GetParent()
			if not scroll then return end
			if ScrollFrameTemplate_OnMouseWheel then
				ScrollFrameTemplate_OnMouseWheel(scroll, delta)
				return
			end
			local range = scroll.GetVerticalScrollRange and scroll:GetVerticalScrollRange() or 0
			local nextScroll = (scroll:GetVerticalScroll() or 0) - (delta * 40)
			if nextScroll < 0 then nextScroll = 0 end
			if nextScroll > range then nextScroll = range end
			scroll:SetVerticalScroll(nextScroll)
		end)
	end

	local anchor = status
	local fields = TyGearPersonalStatFieldsForUI()
	local columns = 2
	local columnWidth = 236
	local rowHeight = 22
	local fieldRows = math.max(math.ceil(#fields / columns), 1)
	local serial = 0

	if not classToken then
		status:SetText(statusText())
	else
		local localized = (TyGearClassList and TyGearClassList[classToken]) or classToken
		local classLine = listMenu:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
		classLine:SetPoint("TOPLEFT", resetButton or status, "BOTTOMLEFT", 0, -8)
		classLine:SetText(TyGearClassColoredText(classToken, localized))
		anchor = classLine
		status:SetText(statusText())

		for _, specName in ipairs(TyGearGetPersonalSpecNames(classToken)) do
			local block = CreateFrame("Frame", nil, listMenu, "BackdropTemplate")
			block:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -12)
			block:SetPoint("RIGHT", listMenu, "RIGHT", -8, 0)
			block:SetHeight(36 + fieldRows * rowHeight)
			block:SetBackdrop({
				bgFile = "Interface/ChatFrame/ChatFrameBackground",
				edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
				tile = true, tileSize = 16, edgeSize = 12,
				insets = { left = 3, right = 3, top = 3, bottom = 3 },
			})
			block:SetBackdropColor(0.08, 0.08, 0.08, 0.45)
			block:SetBackdropBorderColor(0.45, 0.45, 0.45, 0.9)
			forwardWheel(block)

			local header = block:CreateFontString(nil, "ARTWORK", "GameFontNormal")
			header:SetPoint("TOPLEFT", 10, -8)
			header:SetText(specHeaderText(specName))
			local edits = {}
			local starting = TyGearPeekPersonalSpecWeights(classToken, specName)
			for index, field in ipairs(fields) do
				serial = serial + 1
				local column = (index - 1) % columns
				local rowIndex = math.floor((index - 1) / columns)
				local cell = CreateFrame("Frame", nil, block)
				cell:SetSize(columnWidth - 8, rowHeight)
				cell:SetPoint("TOPLEFT", block, "TOPLEFT", 8 + column * columnWidth, -(28 + rowIndex * rowHeight))
				local label = cell:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
				label:SetPoint("LEFT", 0, 0)
				label:SetWidth(148)
				label:SetJustifyH("LEFT")
				label:SetWordWrap(false)
				label:SetText(TyGearPersonalStatLabel(field))
				local edit = CreateFrame("EditBox", "TyGearPersonalWeight"..serial, cell, "InputBoxTemplate")
				edit:SetSize(72, 20)
				edit:SetPoint("LEFT", label, "RIGHT", 4, 0)
				edit:SetAutoFocus(false)
				edit:SetMaxLetters(16)
				edit:SetTextInsets(5, 4, 0, 0)
				if edit.SetTextColor then
					edit:SetTextColor(1, 1, 1)
				end
				edit:SetFrameLevel((cell:GetFrameLevel() or 1) + 2)
				TyGearSetPersonalWeightEditText(edit, starting and starting[field.key])
				edit:HookScript("OnShow", function(self)
					local row = TyGearPeekPersonalSpecWeights(classToken, specName)
					TyGearSetPersonalWeightEditText(self, row and row[field.key])
				end)
				edit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
				edit:SetScript("OnEscapePressed", function(self)
					local row = TyGearPeekPersonalSpecWeights(classToken, specName)
					self.tyGearSuppress = true
					self:SetText(TyGearFormatPersonalStatWeight(row and row[field.key]))
					if self.SetCursorPosition then self:SetCursorPosition(0) end
					self:ClearFocus()
					self.tyGearSuppress = nil
				end)
				edit:SetScript("OnEditFocusLost", function(self)
					if self.tyGearSuppress then return end
					local value = TyGearNormalizePersonalStatWeight(self:GetText())
					if value == nil then
						local row = TyGearPeekPersonalSpecWeights(classToken, specName)
						self:SetText(TyGearFormatPersonalStatWeight(row and row[field.key]))
						if self.SetCursorPosition then self:SetCursorPosition(0) end
						return
					end
					TyGearSetPersonalStatWeight(classToken, specName, field.key, value)
					self:SetText(TyGearFormatPersonalStatWeight(value))
					if self.SetCursorPosition then self:SetCursorPosition(0) end
				end)
				edit:SetScript("OnEnter", function(self)
					GameTooltip:SetOwner(self, "ANCHOR_NONE")
					GameTooltip:SetPoint("BOTTOMLEFT", self, "TOPLEFT")
					GameTooltip:AddLine(TyGearSpecColoredText(classToken, specName).." "..TyGearPersonalStatLabel(field), NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, true)
					GameTooltip:AddLine(string.format(L["Weight per point of %s. 0 means this stat does not add to the score."], TyGearPersonalStatLabel(field)), HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b, true)
					GameTooltip:Show()
				end)
				edit:SetScript("OnLeave", function() GameTooltip:Hide() end)
				forwardWheel(edit)
				forwardWheel(cell)
				edits[field.key] = edit
			end
			TyGearPersonalWeightEditors.specs[specName] = { header = header, edits = edits }
			anchor = block
		end
	end

	local importHeader = listMenu:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	importHeader:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -18)
	importHeader:SetText(L["Import and export"])

	local importNote = listMenu:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	importNote:SetPoint("TOPLEFT", importHeader, "BOTTOMLEFT", 0, -6)
	importNote:SetWidth(480)
	importNote:SetJustifyH("LEFT")
	importNote:SetText(L["Export fills the box with a short TG2 string of only the weights you changed from MythicSim. An unchanged class exports as TG2:CLASS. Import reads that string, or an older line-by-line export, and replaces this class's weights. The class in the string has to match this character."])
	listMenu.personalImportNote = importNote

	-- Single-line InputBoxTemplate: multi-line height left the cursor under the short border after Enter.
	local importBox = CreateFrame("EditBox", "TyGearPersonalStatWeightsImportEditBox", listMenu, "InputBoxTemplate")
	importBox:SetPoint("TOPLEFT", importNote, "BOTTOMLEFT", 4, -8)
	importBox:SetSize(460, 20)
	importBox:SetAutoFocus(false)
	importBox:SetMultiLine(false)
	importBox:SetMaxLetters(20000)
	importBox:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
	importBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	importBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	importBox:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_NONE")
		GameTooltip:SetPoint("BOTTOMLEFT", self, "TOPLEFT")
		GameTooltip:AddLine(L["Import and export"], NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, true)
		GameTooltip:AddLine(L["Export fills the box with a short TG2 string of only the weights you changed from MythicSim. An unchanged class exports as TG2:CLASS. Import reads that string, or an older line-by-line export, and replaces this class's weights. The class in the string has to match this character."], HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b, true)
		GameTooltip:Show()
	end)
	importBox:SetScript("OnLeave", function() GameTooltip:Hide() end)
	listMenu.personalImportBox = importBox

	local exportButton = CreateFrame("Button", "TyGearPersonalStatWeightsExportButton", listMenu, "UIPanelButtonTemplate")
	exportButton:SetSize(120, 24)
	exportButton:SetPoint("TOPLEFT", importBox, "BOTTOMLEFT", -4, -8)
	exportButton:SetText(L["Export"])
	exportButton:SetScript("OnClick", function()
		if not classToken then return end
		local text = TyGearExportPersonalStatWeights(classToken)
		importBox:SetText(text or "")
		importBox:SetFocus()
		importBox:HighlightText()
		TyGearPrint("TyGear: "..L["Exported personal stat weights. The box lists only weights that differ from MythicSim."], 0)
		if TyGearRefreshPersonalStatWeightEditors then TyGearRefreshPersonalStatWeightEditors() end
	end)
	exportButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_NONE")
		GameTooltip:SetPoint("BOTTOMLEFT", self, "TOPLEFT")
		GameTooltip:AddLine(L["Export"], NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, true)
		GameTooltip:AddLine(L["Fill the box with a short string of the weights you changed. Copy that string to share or restore them."], HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b, true)
		GameTooltip:Show()
	end)
	exportButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

	local importButton = CreateFrame("Button", "TyGearPersonalStatWeightsImportButton", listMenu, "UIPanelButtonTemplate")
	importButton:SetSize(120, 24)
	importButton:SetPoint("LEFT", exportButton, "RIGHT", 8, 0)
	importButton:SetText(L["Import"])
	importButton:SetScript("OnClick", function()
		if not classToken then return end
		local ok, message = TyGearImportPersonalStatWeights(importBox:GetText(), classToken)
		TyGearPrint("TyGear: "..(message or ""), 0)
		if ok and TyGearRefreshPersonalStatWeightEditors then
			TyGearRefreshPersonalStatWeightEditors()
		end
	end)
	importButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_NONE")
		GameTooltip:SetPoint("BOTTOMLEFT", self, "TOPLEFT")
		GameTooltip:AddLine(L["Import"], NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, true)
		GameTooltip:AddLine(L["Read the box and save those weights for this class."], HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b, true)
		GameTooltip:Show()
	end)
	importButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
	listMenu.personalBottom = importButton

	local function layoutPersonalPage()
		local top = listMenu:GetTop()
		local bottom = importButton:GetBottom()
		local height
		if top and bottom and top > bottom then
			height = (top - bottom) + 24
		else
			local specCount = classToken and #TyGearGetPersonalSpecNames(classToken) or 0
			height = 420 + specCount * (48 + fieldRows * rowHeight)
		end
		listMenu:SetHeight(height)
		local scroll = listMenu:GetParent()
		if scroll and scroll.UpdateScrollChildRect then
			scroll:UpdateScrollChildRect()
		end
	end
	listMenu.layoutPersonalPage = layoutPersonalPage
	listMenu:HookScript("OnShow", function()
		if TyGearRefreshPersonalStatWeightEditors then TyGearRefreshPersonalStatWeightEditors() end
		layoutPersonalPage()
	end)
	status:SetText(statusText())
	layoutPersonalPage()
end

function TyGearRefreshPersonalStatWeightEditors()
	local editors = TyGearPersonalWeightEditors
	if not editors then return end
	if editors.status and editors.statusText then
		editors.status:SetText(editors.statusText())
	end
	local classToken = editors.classToken
	if not classToken or not editors.specs then return end
	for specName, specEditors in pairs(editors.specs) do
		if specEditors.header and editors.specHeader then
			specEditors.header:SetText(editors.specHeader(specName))
		end
		local row = TyGearPeekPersonalSpecWeights(classToken, specName)
		if specEditors.edits and row then
			for statKey, edit in pairs(specEditors.edits) do
				TyGearSetPersonalWeightEditText(edit, row[statKey])
			end
		end
	end
end

local optionsMenu = CreateFrame("Frame", "TyGearOptionsMenu")
optionsMenu:SetWidth(1) -- must be set to at least 1 or the menu is invisible in the scroll frame, but will expand to show everything
optionsMenu:SetHeight(1) -- must be set to at least 1 or the menu is invisible in the scroll frame, but will expand to show everything
local optionsMenuParent = CreateFrame("ScrollFrame", "TyGearOptionsMenuScrollFrame", nil, "UIPanelScrollFrameTemplate")
optionsMenuParent.name = "TyGear"
optionsMenuParent:SetScrollChild(optionsMenu)
--the Settings shim above returns the registered category; native InterfaceOptions_AddCategory returns nothing
local optionsCategory = InterfaceOptions_AddCategory(optionsMenuParent)

--Settings subtabs used on WoW Forever. The keep list lives on the Ignored gear tab.
local ignoredGearListMenu
local ignoredGearListMenuParent
local needListMenu
local needListMenuParent
local personalWeightsMenu
local personalWeightsMenuParent
if IS_WOW_FOREVER then
	ignoredGearListMenu = CreateFrame("Frame", "TyGearIgnoredGearListMenu")
	ignoredGearListMenu:SetWidth(1)
	ignoredGearListMenu:SetHeight(1)
	ignoredGearListMenuParent = CreateFrame("ScrollFrame", "TyGearIgnoredGearListMenuScrollFrame", nil, "UIPanelScrollFrameTemplate")
	ignoredGearListMenuParent.name = L["Ignored List"]
	ignoredGearListMenuParent:SetScrollChild(ignoredGearListMenu)
	if optionsCategory and Settings and Settings.RegisterCanvasLayoutSubcategory then
		Settings.RegisterCanvasLayoutSubcategory(optionsCategory, ignoredGearListMenuParent, ignoredGearListMenuParent.name)
	else
		ignoredGearListMenuParent.parent = optionsMenuParent.name
		InterfaceOptions_AddCategory(ignoredGearListMenuParent)
	end

	needListMenu = CreateFrame("Frame", "TyGearNeedListMenu")
	needListMenu:SetWidth(1)
	needListMenu:SetHeight(1)
	needListMenuParent = CreateFrame("ScrollFrame", "TyGearNeedListMenuScrollFrame", nil, "UIPanelScrollFrameTemplate")
	needListMenuParent.name = L["Need List"]
	needListMenuParent:SetScrollChild(needListMenu)
	if optionsCategory and Settings and Settings.RegisterCanvasLayoutSubcategory then
		Settings.RegisterCanvasLayoutSubcategory(optionsCategory, needListMenuParent, needListMenuParent.name)
	else
		needListMenuParent.parent = optionsMenuParent.name
		InterfaceOptions_AddCategory(needListMenuParent)
	end
end

personalWeightsMenu = CreateFrame("Frame", "TyGearPersonalStatWeightsMenu")
personalWeightsMenu:SetWidth(1)
personalWeightsMenu:SetHeight(1)
personalWeightsMenuParent = CreateFrame("ScrollFrame", "TyGearPersonalStatWeightsMenuScrollFrame", nil, "UIPanelScrollFrameTemplate")
personalWeightsMenuParent.name = L["Personal Stat Weights"]
personalWeightsMenuParent:SetScrollChild(personalWeightsMenu)
if optionsCategory and Settings and Settings.RegisterCanvasLayoutSubcategory then
	Settings.RegisterCanvasLayoutSubcategory(optionsCategory, personalWeightsMenuParent, personalWeightsMenuParent.name)
else
	personalWeightsMenuParent.parent = optionsMenuParent.name
	InterfaceOptions_AddCategory(personalWeightsMenuParent)
end

if InterfaceAddOnsList_Update then InterfaceAddOnsList_Update() end

--white profession weapons hard-kept when selling greys and white gear (not stored in the editable keep-list box).
--Skinning Knife, Mining Pick, fishing poles, etc. stay kept even if VendorKeepList is empty.
--Non-gear whites are omitted: white selling only evaluates weapons and armor.
--Fishing poles of any item ID are also kept later by weapon subclass.
--Post-vanilla tools are omitted on WoW Forever, which does not have those professions or items.
local TyGearCraftingToolItemIDsClassic = {
	2901, --Mining Pick
	5956, --Blacksmith Hammer
	6219, --Arclight Spanner
	6256, --Fishing Pole
	6365, --Strong Fishing Pole
	6367, --Big Iron Fishing Pole
	7005, --Skinning Knife
	12225, --Blump Family Fishing Pole
	247789, --Novice's Practice Wand
}
--removed from the default keep list (fishing poles still kept by weapon subclass; non-gear whites are never sold as white gear)
local TyGearRemovedDefaultKeepListItemIDs = {
	[3567] = true, --Dwarven Fishing Pole
	[4471] = true, --Flint and Tinder
	[4598] = true, --Goblin Fishing Pole
	[6218] = true, --Runed Copper Rod
	[6339] = true, --Runed Silver Rod
	[6366] = true, --Darkwood Fishing Pole
	[10498] = true, --Gyromatic Micro-Adjustor
	[11130] = true, --Runed Golden Rod
	[11145] = true, --Runed Truesilver Rod
	[16207] = true, --Runed Arcanite Rod
	[20815] = true, --Jeweler's Kit
	[39505] = true, --Virtuoso Inking Set
	[40772] = true, --Gnomish Army Knife
}
local TyGearCraftingToolItemIDsPostClassic = {
	85663, --Herbalist's Spade (two-hand weapon on MoP-era clients)
}
TyGearCraftingToolItemIDsMissingOnForever = {}
for _, itemID in ipairs(TyGearCraftingToolItemIDsPostClassic) do
	TyGearCraftingToolItemIDsMissingOnForever[itemID] = true
end
TyGearCraftingToolItemIDs = {}
TyGearCraftingToolItemIDSet = {}
for _, itemID in ipairs(TyGearCraftingToolItemIDsClassic) do
	table.insert(TyGearCraftingToolItemIDs, itemID)
	TyGearCraftingToolItemIDSet[itemID] = true
end
if not IS_WOW_FOREVER then
	for _, itemID in ipairs(TyGearCraftingToolItemIDsPostClassic) do
		table.insert(TyGearCraftingToolItemIDs, itemID)
		TyGearCraftingToolItemIDSet[itemID] = true
	end
end

--handle PLAYER_ENTERING_WORLD events for initialization
pcall(optionsMenu.RegisterEvent,optionsMenu,"PLAYER_ENTERING_WORLD")
optionsMenu:SetScript("OnEvent", function (self, event, arg1, arg2, ...)
	if event == "PLAYER_ENTERING_WORLD" then
		TyGearRefreshReagentBagSlot()

		--default values for variables saved between sessions
		TyGearDBDefaults = {
			Enabled = true,
			AutoLootRoll = true,
			AutoRollOnBoEBlues = false,
			AutoRollOnEpics = false,
			RollOnNonGearLoot = not IS_WOW_FOREVER, --off on WoW Forever: leave non-gear loot rolls to the player
			NeverAutoNeed = false,
			AutoConfirmBinding = true,
			AutoConfirmBindingBlues = false,
			AutoConfirmBindingEpics = false,
			PlayUpgradeChime = true,
			ScoreInTooltips = true,
			ReasonsInTooltips = false,
			AlwaysCompareGear = GetCVarBool("alwaysCompareItems"),
			AlwaysShowScoreComparisons = false,
			AutoSellGreys = false,
			--profession weapon tools are hard-kept; the editable box only holds user-added IDs
			VendorKeepList = "",
			NeedList = "",
			KeepKeeperTahultPetItems = true,
			KeepUnboundGreyGear = false,
			AutoSellUnsuitableWhites = false,
			AutoSellAllWhiteGear = false,
			-- Forever defaults to MythicSim EP weights; Pawn remains the optional fallback / alternate system.
			StatWeightSystem = TyGearStatWeightSystemMythicSim,
			UsePawn = false, -- kept in sync with StatWeightSystem for older saved-variable readers and slash commands
			OverridePawnScale = false,
			PawnScale = "",
			DebugInfoInTooltips = false,
			AllowedVerbosity = 1,
			LockedGearSlots = TyGearGetDefaultLockedGearSlots()
		}

		TyGearInitializeDB(TyGearDBDefaults)
		TyGearMigrateStatWeightSystem()
		TyGearEnsureForeverLevelingBISOnChanged()
		if UnitClassBase then
			TyGearEnsurePersonalClassWeights(UnitClassBase("player"))
		end
		TyGearMigrateVendorKeepList()
		TyGearPruneForeverVendorKeepList()
		TyGearPruneRemovedDefaultKeepListItems()
		TyGearStripDefaultVendorKeepListItems()
		TyGearInitializeCharacterSettings()
		TyGearFixLockedGearSlots()
		TyGearMigrateLockGearSlots()

		--initialize options menu variables
		TyGearOptions = {
			{
				["option"] = "Enabled",
				["tab"] = L["Loot"],
				["cliCommands"] = { "toggle", "gear", "equip" },
				["cliTrue"] = { "enable", "on", "start" },
				["cliFalse"] = { "disable", "off", "stop" },
				["label"] = L["Automatically equip gear"],
				["description"] = L["Automatically equip gear upgrades, depending on internal stat weights.  These stat weights are currently only configurable by editing the values in the TyGearDefaultWeights table in TyGear.lua.  If this is disabled, TyGear will still scan for gear when receiving new items and viewing loot rolls, but will never equip an item automatically.\n\nBag items TyGear considers upgrades are marked in Baganator when TyGear is chosen as the upgrade source there."],
				["toggleDescriptionTrue"] = L["Automatic gearing is now enabled."],
				["toggleDescriptionFalse"] = L["Automatic gearing is now disabled.  You can still manually scan bags for upgrades with the options menu button or \"/tg scan\"."],
				["togglePostHook"] = function() TyGearUpdateBestItems() end
			},
			{
				["option"] = "PlayUpgradeChime",
				["tab"] = L["Loot"],
				["cliCommands"] = { "chime", "sound", "upgradechime" },
				["cliTrue"] = { "enable", "on", "start" },
				["cliFalse"] = { "disable", "off", "stop" },
				["label"] = L["Play a sound when an upgrade is equipped"],
				["playSound"] = true,
				["description"] = L["Play a short sound when TyGear finishes equipping an upgrade.  The triangle next to this option plays %s so you can hear it."]:format(TyGearGetUpgradeChimeFileName()),
				["toggleDescriptionTrue"] = L["The upgrade equipped sound is now enabled."],
				["toggleDescriptionFalse"] = L["The upgrade equipped sound is now disabled."]
			},
			{
				["option"] = "AutoLootRoll",
				["tab"] = L["Loot"],
				["section"] = L["Rolling"],
				["cliCommands"] = { "roll", "loot", "rolling" },
				["cliTrue"] = { "enable", "on", "start" },
				["cliFalse"] = { "disable", "off", "stop" },
				["label"] = L["Automatically roll on greens and BoP blues"],
				["description"] = L["Automatically roll on group loot of green rarity and blues which bind when picked up, depending on internal stat weights.  If this is disabled, TyGear will still evaluate these loot rolls and print its evaluation if verbosity is set to 1 (%s) or higher."]:format(TyGearGetAllowedVerbosityName(1)),
				["toggleDescriptionTrue"] = L["Automatically rolling on loot of green rarity and blues which bind when picked up is now enabled."],
				["toggleDescriptionFalse"] = L["Automatically rolling on loot of green rarity and blues which bind when picked up is now disabled.  TyGear will still try to equip gear received through other means, but you will have to roll on this loot manually."]
			},
			{
				["option"] = "AutoRollOnBoEBlues",
				["tab"] = L["Loot"],
				["section"] = L["Rolling"],
				["cliCommands"] = { "rollboeblues", "rollonboeblues", "lootboeblues" },
				["cliTrue"] = { "enable", "on", "start" },
				["cliFalse"] = { "disable", "off", "stop" },
				["label"] = L["Automatically roll on BoE blues"],
				["description"] = L["Automatically roll on group loot of blue rarity which binds when equipped, depending on internal stat weights.  If this is disabled, TyGear will still evaluate these loot rolls and print its evaluation if verbosity is set to 1 (%s) or higher."]:format(TyGearGetAllowedVerbosityName(1)),
				["toggleDescriptionTrue"] = L["Automatically rolling on group loot of blue rarity which binds when equipped is now enabled."],
				["toggleDescriptionFalse"] = L["Automatically rolling on group loot of blue rarity which binds when equipped is now disabled.  TyGear will still try to equip gear received through other means, but you will have to roll on this loot manually."]
			},
			{
				["option"] = "AutoRollOnEpics",
				["tab"] = L["Loot"],
				["section"] = L["Rolling"],
				["cliCommands"] = { "rollepics", "rollonepics", "lootepics" },
				["cliTrue"] = { "enable", "on", "start" },
				["cliFalse"] = { "disable", "off", "stop" },
				["label"] = L["Automatically roll on epics"],
				["description"] = L["Automatically roll on group loot of epic rarity, depending on internal stat weights.  If this is disabled, TyGear will still evaluate these loot rolls and print its evaluation if verbosity is set to 1 (%s) or higher."]:format(TyGearGetAllowedVerbosityName(1)),
				["toggleDescriptionTrue"] = L["Automatically rolling on group loot of epic rarity is now enabled."],
				["toggleDescriptionFalse"] = L["Automatically rolling on group loot of epic rarity is now disabled.  TyGear will still try to equip gear received through other means, but you will have to roll on this loot manually."]
			},
			{
				["option"] = "RollOnNonGearLoot",
				["tab"] = L["Loot"],
				["section"] = L["Rolling"],
				["cliCommands"] = { "nongear", "nongearloot", "allloot" },
				["cliTrue"] = { "enable", "on", "start" },
				["cliFalse"] = { "disable", "off", "stop" },
				["label"] = L["Roll on non-gear loot"],
				["description"] = L["Roll on all group loot, including loot that is not gear.  If this is enabled, TyGear will roll GREED on non-gear loot.  Mounts are never rolled on automatically."],
				["toggleDescriptionTrue"] = L["Rolling on non-gear loot is now enabled.  TyGear will roll GREED on non-gear loot.  Mounts are never rolled on automatically."],
				["toggleDescriptionFalse"] = L["Rolling on non-gear loot is now disabled."]
			},
			{
				["option"] = "NeverAutoNeed",
				["tab"] = L["Loot"],
				["section"] = L["Rolling"],
				["cliCommands"] = { "neverautoneed", "neverneed", "noneed", "onlyautogreed", "onlygreed", "greedonly", "justgreed" },
				["cliTrue"] = { "enable", "on", "start" },
				["cliFalse"] = { "disable", "off", "stop" },
				["label"] = L["Never auto-need; only greed"],
				["description"] = L["Never automatically roll NEED.  If this is enabled, TyGear will be prevented from automatically rolling NEED when it detects an upgrade, leaving the loot roll interactive to allow manual control of that roll.  It will still be allowed to roll GREED when an upgrade is not detected and automatic rolling is enabled for the detected rarity."],
				["toggleDescriptionTrue"] = L["Rolling only GREED automatically is now enabled.  TyGear will be unable to roll NEED automatically."],
				["toggleDescriptionFalse"] = L["Rolling only GREED automatically is now disabled.  TyGear will be able to roll NEED on detected upgrades automatically."]
			},
			{
				["option"] = "AutoConfirmBinding",
				["tab"] = L["Loot"],
				["section"] = L["Soul-binding"],
				["cliCommands"] = { "bind", "boe", "soulbinding" },
				["cliTrue"] = { "enable", "on", "start" },
				["cliFalse"] = { "disable", "off", "stop" },
				["label"] = L["Automatically confirm soul-binding for non-blues/non-epics"],
				["description"] = L["Automatically confirm soul-binding when equipping an upgrade that does not have blue or epic rarity, causing it to become soulbound.  If this is disabled, TyGear will still try to equip non-blue/non-epic binding gear, but you will have to confirm soul-binding manually."],
				["toggleDescriptionTrue"] = L["Automatically confirming soul-binding for non-blues/non-epics is now enabled."],
				["toggleDescriptionFalse"] = L["Automatically confirming soul-binding for non-blues/non-epics is now disabled.  TyGear will still try to equip non-blue/non-epic binding gear, but you will have to confirm soul-binding manually."]
			},
			{
				["option"] = "AutoConfirmBindingBlues",
				["tab"] = L["Loot"],
				["section"] = L["Soul-binding"],
				["cliCommands"] = { "blue", "blues", "bindblues", "autobindblues" },
				["cliTrue"] = { "enable", "on", "start" },
				["cliFalse"] = { "disable", "off", "stop" },
				["label"] = L["Automatically confirm soul-binding for blues"],
				["description"] = L["Automatically confirm soul-binding when equipping an upgrade that has blue rarity, causing it to become soulbound.  If this is disabled, TyGear will still try to equip blue binding gear, but you will have to confirm soul-binding manually."],
				["toggleDescriptionTrue"] = L["Automatically confirming soul-binding for blues is now enabled."],
				["toggleDescriptionFalse"] = L["Automatically confirming soul-binding for blues is now disabled.  TyGear will still try to equip blue binding gear, but you will have to confirm soul-binding manually."]
			},
			{
				["option"] = "AutoConfirmBindingEpics",
				["tab"] = L["Loot"],
				["section"] = L["Soul-binding"],
				["cliCommands"] = { "epic", "epics", "bindepics", "autobindepics" },
				["cliTrue"] = { "enable", "on", "start" },
				["cliFalse"] = { "disable", "off", "stop" },
				["label"] = L["Automatically confirm soul-binding for epics"],
				["description"] = L["Automatically confirm soul-binding when equipping an upgrade that has epic rarity, causing it to become soulbound.  If this is disabled, TyGear will still try to equip epic binding gear, but you will have to confirm soul-binding manually."],
				["toggleDescriptionTrue"] = L["Automatically confirming soul-binding for epics is now enabled."],
				["toggleDescriptionFalse"] = L["Automatically confirming soul-binding for epics is now disabled.  TyGear will still try to equip epic binding gear, but you will have to confirm soul-binding manually."]
			},
			{
				["option"] = "ScoreInTooltips",
				["tab"] = L["Tooltips"],
				["cliCommands"] = { "score", "tooltip", "tooltips" },
				["cliTrue"] = { "show", "enable", "on", "start" },
				["cliFalse"] = { "hide", "disable", "off", "stop" },
				["label"] = L["Show TyGear score in item tooltips"],
				["description"] = L["Show total TyGear item score from internal TyGear stat weights in item tooltips."],
				["toggleDescriptionTrue"] = L["Showing score in item tooltips is now enabled."],
				["toggleDescriptionFalse"] = L["Showing score in item tooltips is now disabled."]
			},
			{
				["option"] = "ReasonsInTooltips",
				["tab"] = L["Tooltips"],
				["cliCommands"] = { "reason", "reasons" },
				["cliTrue"] = { "show", "enable", "on", "start" },
				["cliFalse"] = { "hide", "disable", "off", "stop" },
				["label"] = L["Show won't-equip reasons in item tooltips"],
				["description"] = L["Show reasons TyGear won't automatically equip items in item tooltips, except when the score is lower than the equipped item's score."],
				["toggleDescriptionTrue"] = L["Showing won't-auto-equip reasons in item tooltips is now enabled."],
				["toggleDescriptionFalse"] = L["Showing won't-auto-equip reasons in item tooltips is now disabled."]
			},
			{
				["option"] = "AlwaysCompareGear",
				["tab"] = L["Tooltips"],
				["cliCommands"] = { "compare", "alwayscompare", "alwayscomparegear" },
				["cliTrue"] = { "enable", "on", "start" },
				["cliFalse"] = { "disable", "off", "stop" },
				["cvar"] = "alwaysCompareItems",
				["label"] = L["Always show equipped gear comparison tooltips"],
				["description"] = L["Always show equipped gear comparison tooltips when viewing tooltips for gear that's not equipped.  If this is disabled, you can still show gear comparison tooltips while holding the Shift key."],
				["toggleDescriptionTrue"] = L["Always showing gear comparison tooltips when viewing gear tooltips is now enabled."],
				["toggleDescriptionFalse"] = L["Always showing gear comparison tooltips when viewing gear tooltips is now disabled.  You can still show gear comparison tooltips while holding the Shift key."]
			},
			{
				["option"] = "AlwaysShowScoreComparisons",
				["tab"] = L["Tooltips"],
				["cliCommands"] = { "scorecomparisons", "scorecomparisonsalways", "alwaysshowscorecomparisons" },
				["cliTrue"] = { "enable", "on", "start" },
				["cliFalse"] = { "disable", "off", "stop" },
				["label"] = L["Always show score comparisons in tooltips"],
				["description"] = L["Always show score comparisons in the item tooltip, even when also showing the comparison tooltip.  If this is enabled, only the score for the current item will be shown in the tooltip."],
				["toggleDescriptionTrue"] = L["Always show score comparisons in gear tooltips is now enabled."],
				["toggleDescriptionFalse"] = L["Always show score comparisons in gear tooltips is now disabled."]
			},
			{
				["option"] = "AutoSellGreys",
				["tab"] = L["Vendor"],
				["section"] = L["Selling"],
				["cliCommands"] = { "sell", "sellgreys", "greys" },
				["cliTrue"] = { "enable", "on", "start" },
				["cliFalse"] = { "disable", "off", "stop" },
				["label"] = L["Automatically sell greys"],
				["description"] = L["Automatically sell all grey items when interacting with a vendor.  Hold Shift while opening the vendor to skip selling that time.\n\nTyGear keeps greys it would equip as upgrades, quest items, greys the current vendor accepts as payment, greys vendors refuse to buy, and item IDs on the ignore list or the keep list.  It stops selling when the vendor doesn't buy items or you can't hold more gold.\n\nItems TyGear would sell are marked as junk for bag addons such as Baganator (choose TyGear as the junk source there) and for the default bags."],
				["toggleDescriptionTrue"] = L["Automatic selling of grey items is now enabled."],
				["toggleDescriptionFalse"] = L["Automatic selling of grey items is now disabled."],
				["togglePostHook"] = function() TyGearQueueVendorJunkRefresh() end
			},
			{
				["option"] = "AutoSellUnsuitableWhites",
				["tab"] = L["Vendor"],
				["section"] = L["Selling"],
				["cliCommands"] = { "sellunsuitable", "unsuitablewhites" },
				["cliTrue"] = { "enable", "on", "start" },
				["cliFalse"] = { "disable", "off", "stop" },
				["label"] = L["Automatically sell unsuitable white gear"],
				["description"] = L["Only sells white gear (weapons and armor). Automatically sell white weapons and armor your class can't equip when interacting with a vendor.  Other white items such as trade goods and enchanting rods are never sold by this option.  Hold Shift while opening the vendor to skip selling that time.\n\nTyGear keeps quest items, items the current vendor accepts as payment, items it would equip as upgrades, tabards, the ignore list, and the keep list.  Fishing poles and profession equipment are always kept.  A level requirement alone does not count as unsuitable, since you will be able to wear the item later.  It stops selling when the vendor doesn't buy items or you can't hold more gold.\n\nItems TyGear would sell are marked as junk for bag addons such as Baganator (choose TyGear as the junk source there) and for the default bags."],
				["toggleDescriptionTrue"] = L["Automatic selling of unsuitable white gear is now enabled."],
				["toggleDescriptionFalse"] = L["Automatic selling of unsuitable white gear is now disabled."],
				["togglePostHook"] = function() TyGearQueueVendorJunkRefresh() end
			},
			{
				["option"] = "AutoSellAllWhiteGear",
				["tab"] = L["Vendor"],
				["section"] = L["Selling"],
				["cliCommands"] = { "sellwhitegear", "whitegear" },
				["cliTrue"] = { "enable", "on", "start" },
				["cliFalse"] = { "disable", "off", "stop" },
				["label"] = L["Automatically sell all white gear"],
				["description"] = L["Only sells white gear (weapons and armor). Automatically sell all white weapons and armor when interacting with a vendor, including pieces you can equip.  Other white items such as trade goods and enchanting rods are never sold by this option.  Hold Shift while opening the vendor to skip selling that time.\n\nTyGear keeps quest items, items the current vendor accepts as payment, items it would equip as upgrades, tabards, the ignore list, and the keep list.  Fishing poles and profession equipment are always kept.  It stops selling when the vendor doesn't buy items or you can't hold more gold.\n\nItems TyGear would sell are marked as junk for bag addons such as Baganator (choose TyGear as the junk source there) and for the default bags."],
				["toggleDescriptionTrue"] = L["Automatic selling of all white gear is now enabled."],
				["toggleDescriptionFalse"] = L["Automatic selling of all white gear is now disabled."],
				["togglePostHook"] = function() TyGearQueueVendorJunkRefresh() end
			},
			{
				["option"] = "VendorKeepList",
				["tab"] = L["Vendor"],
				["section"] = L["Keep"],
				["shouldUse"] = false, --the keep list lives on the ignore list
				["editBox"] = true,
				["label"] = L["Keep List"],
				["description"] = L["Item names or IDs separated by commas.  Greys and common (white) items listed here are not sold. They can still fill an empty gear slot, but they are not treated as upgrades over gear you already wear.\n\nWhite selling only covers weapons and armor, so non-gear whites do not need to be listed. Profession weapons such as Skinning Knife, Mining Pick, Blacksmith Hammer, Arclight Spanner, and Herbalist's Spade are always kept and do not need to be listed. Every fishing pole is kept even if it is not listed here.\n\nShift-click an item while this box has focus to add it, look up item IDs in item tooltips while the TyGear options are open, or assign \"Toggle hovered item on ignore list\" in Key Bindings and press it while hovering an item. New items are added near the top of the list."],
				["editBoxPostHook"] = function() TyGearQueueVendorJunkRefresh() end
			},
			{
				["option"] = "KeepKeeperTahultPetItems",
				["tab"] = L["Vendor"],
				["section"] = L["Keep"],
				["shouldUse"] = false, --retail hosts this on the ignore list; Oribos is not in WoW Forever
				["label"] = L["Keep greys needed for Keeper Ta'hult's pets"],
				["description"] = L["Don't sell the grey items that Keeper Ta'hult in Oribos takes as payment for the Baubleworm pets."],
				["toggleDescriptionTrue"] = L["Keeping greys needed for Keeper Ta'hult's pets is now enabled."],
				["toggleDescriptionFalse"] = L["Keeping greys needed for Keeper Ta'hult's pets is now disabled."],
				["togglePostHook"] = function() TyGearQueueVendorJunkRefresh() end
			},
			{
				["option"] = "KeepUnboundGreyGear",
				["tab"] = L["Vendor"],
				["section"] = L["Keep"],
				["shouldUse"] = false, --this option lives on the ignore list
				["label"] = L["Keep unbound grey gear"],
				["description"] = L["Don't sell grey weapons and armor which aren't soulbound, for example to sell them on the auction house instead."],
				["toggleDescriptionTrue"] = L["Keeping unbound grey gear is now enabled."],
				["toggleDescriptionFalse"] = L["Keeping unbound grey gear is now disabled."],
				["togglePostHook"] = function() TyGearQueueVendorJunkRefresh() end
			},
			{
				["option"] = "NeedList",
				["tab"] = L["Loot"],
				["section"] = L["Need List"],
				["shouldUse"] = not IS_WOW_FOREVER, --Forever uses the Need List Settings tab instead
				["editBox"] = true,
				["label"] = L["Need List"],
				["description"] = L["Item names or IDs separated by commas. Items listed here are always rolled NEED when they appear as group loot, even if they are not gear upgrades. Useful for crafting greens you keep needing in a dungeon.\n\nShift-click an item while this box has focus to add it, look up item IDs in item tooltips while the TyGear options are open, or assign \"Toggle hovered item on need list\" in Key Bindings and press it while hovering an item. New items are added near the top of the list."]
			},
			{
				["option"] = "Override",
				["tab"] = L["Evaluation"],
				["cliCommands"] = { "override" },
				["cliTrue"] = { "enable", "on", "start" },
				["cliFalse"] = { "disable", "off", "stop" },
				["label"] = L["Override specialization"],
				["description"] = L["Override specialization with the specialization chosen in this dropdown.  If this is enabled, TyGear will evaluate gear by multiplying stats by the stat weights for the chosen specialization instead of the spec detected automatically.  This choice is saved for this character, so alts keep their own spec."],
				["toggleDescriptionTrue"] = L["Specialization overriding is now enabled.  TyGear will use the specialization selected in the dropdown for evaluating gear."],
				["toggleDescriptionFalse"] = L["Specialization overriding is now disabled.  TyGear will use your class and its detected specialization for evaluating gear.  Type \"/tg spec\" to check what specialization TyGear detects for your character."],
				["togglePostHook"] = function() TyGearUpdateBestItems() end,
				["child"] = {
					["option"] = "OverrideSpec",
					["options"] = TyGearGetOverrideSpecs(),
					["label"] = "Override specialization",
					["description"] = "Override specialization with the spec chosen in this dropdown.  If this is enabled, TyGear will evaluate gear by multiplying stats by the stat weights for the chosen specialization instead of the specialization detected automatically.  This choice is saved for this character, so alts keep their own spec.",
					["dropdownPostHook"] = function() TyGearSetStatWeights() end
				}
			},
			{
				["option"] = "StatWeightSystem",
				["tab"] = L["Evaluation"],
				["section"] = L["Stat weights"],
				["dropdown"] = true,
				["cliCommands"] = { "weights", "statsystem", "statweights", "pawn", "usepawn", "flb", "foreverbis", "foreverlevelingbis" },
				["cliTrue"] = { "pawn", "enable", "on", "start" },
				["cliFalse"] = { "mythicsim", "mythic", "disable", "off", "stop" },
				["dropdownWidth"] = 250,
				-- Function so optional engines refresh faded/disabled state if the menu is rebuilt.
				["options"] = TyGearGetStatWeightSystemDropdownOptions,
				["label"] = L["Stat weight system"],
				["description"] = L["Choose which stat weight system TyGear uses to score gear.\n\nMythicSim (default): EP weights from mythicsim.com for WoW Forever specs. Healers and specs MythicSim does not publish still use TyGear's built-in profiles, then fall back to Pawn when those are missing and Pawn is installed.\n\nPawn: use a Pawn scale when Pawn is installed. TyGear looks for a scale named \"[class]: [spec]\" (example \"Paladin: Retribution\"); with \"Override specialization\" enabled, that class and spec are used instead. Visible Pawn scales are preferred. When Pawn is not loaded, that choice appears faded and cannot be selected, and Override Pawn scale stays hidden.\n\nForever Leveling BiS: use stat weights from the Forever Leveling BiS addon API (GetWeights only). TyGear still scores and equips with its own logic. When Forever Leveling BiS is not loaded, that choice appears faded and cannot be selected.\n\nPersonal Stat Weights: the numbers you enter on the Personal Stat Weights tab, for each spec of your class. Tooltips call that score \"TyGear: Personal score:\"."],
				["dropdownPostHook"] = function()
					TyGearSetStatWeightSystem(TyGearDB.StatWeightSystem)
				end
			},
			{
				["option"] = "OverridePawnScale",
				["tab"] = L["Evaluation"],
				["section"] = L["Stat weights"],
				-- Built only when Pawn is loaded; shown only while the stat weight system is Pawn.
				["shouldUse"] = TyGearIsPawnReady(),
				["cliCommands"] = { "scale", "overridepawn", "overridepawnscale" },
				["cliTrue"] = { "enable", "on", "start" },
				["cliFalse"] = { "disable", "off", "stop" },
				["label"] = L["Override Pawn scale"],
				["description"] = L["Override the Pawn scale that would normally be automatically detected in \"[class]: [spec]\" format with the Pawn scale chosen in this dropdown.\n\nOnly shown when the stat weight system is set to Pawn."],
				["toggleDescriptionTrue"] = L["Overriding Pawn scale with the selected scale is now enabled."],
				["toggleDescriptionFalse"] = L["Overriding Pawn scale with the selected scale is now disabled."],
				["togglePostHook"] = function() TyGearUpdateBestItems() end,
				["child"] = {
					["option"] = "PawnScale",
					["options"] = (function() if PawnIsReady and PawnIsReady() then return TyGearGetPawnScales() end end)(),
					["label"] = "Pawn scale to use",
					["description"] = "Override the Pawn scale that would normally be automatically detected in \"[class]: [spec]\" format with the Pawn scale chosen in this dropdown.",
					["shouldUse"] = (PawnIsReady and PawnIsReady()),
					["dropdownPostHook"] = function(self, value)
						if TyGearDB.PawnScale and string.len(TyGearDB.PawnScale)>0 then
							local numMatches
							TyGearDB.PawnScale, numMatches = string.gsub(TyGearDB.PawnScale, "^Visible: ?", "", 1)
							if numMatches and numMatches == 0 then TyGearDB.PawnScale = string.gsub(TyGearDB.PawnScale, "^Hidden: ?", "", 1) end
							setDropdownText(TyGearPawnScaleDropdown, TyGearDB.PawnScale)
						end
						TyGearSetStatWeights()
					end
				}
			},
			{
				["option"] = "LockedGearSlots",
				["slotGrid"] = true,
				["tab"] = L["Evaluation"],
				["section"] = L["Locked gear slots"],
				["label"] = L["Locked gear slots"],
				["description"] = L["Checked slots are left alone: TyGear will not remove or equip items there. Scores are still evaluated for all slots."]
			},
			{
				["option"] = "DebugInfoInTooltips",
				["tab"] = L["Tooltips"],
				["cliCommands"] = { "debuginfo", "debuginfointooltips", "test", "testmode", "rolltestmode" },
				["cliTrue"] = { "enable", "on", "start" },
				["cliFalse"] = { "disable", "off", "stop" },
				["label"] = L["Show debug info in item tooltips (%swarning%s: laggy!)"]:format(RED_FONT_COLOR_CODE, FONT_COLOR_CODE_CLOSE),
				["description"] = L["This is a test mode to show debug info in tooltips, such as the real roll outcome if the item viewed dropped as a loot roll.  This is to help the developers find and fix bugs in TyGear.  You can use it to help too and report issues.\n\n%sWarning%s: laggy!"]:format(RED_FONT_COLOR_CODE, FONT_COLOR_CODE_CLOSE),
				["toggleDescriptionTrue"] = L["Debug info in tooltips is now enabled. Info such as whether TyGear would \"%sNEED%s\" or \"%sGREED%s\" on an item will be shown in item tooltips.  (%swarning%s: laggy!)"]:format(GREEN_FONT_COLOR_CODE, FONT_COLOR_CODE_CLOSE, RED_FONT_COLOR_CODE, FONT_COLOR_CODE_CLOSE, RED_FONT_COLOR_CODE, FONT_COLOR_CODE_CLOSE),
				["toggleDescriptionFalse"] = L["Debug info in tooltips is now disabled."]
			},
			{
				["option"] = "AllowedVerbosity",
				["tab"] = L["Chat"],
				["dropdown"] = true,
				["dropdownWidth"] = 160,
				["options"] = TyGearGetAllowedVerbosityOptions,
				["label"] = L["Chat verbosity"],
				["description"] = L["How much TyGear prints in chat.  0 (errors) prints only problems.  1 (info) also prints equip and roll decisions.  2 (details) adds spec changes and extra detail.  3 (debug) prints everything, including a line for every setting change."],
				["dropdownPostHook"] = function()
					TyGearSetAllowedVerbosity(TyGearDB.AllowedVerbosity)
				end
			}
		}

		if (not TyGearDB.LockedGearSlots) or (#TyGearDB.LockedGearSlots == 0) then
			TyGearDB.LockedGearSlots = TyGearGetDefaultLockedGearSlots()
		end
		optionsSetup(optionsMenu)
		TyGearRefreshPawnOptionsVisibility()
		if ignoredGearListMenu and not ignoredGearListMenu.built then
			ignoredGearListMenu.built = true
			buildIgnoredGearListPage(ignoredGearListMenu)
			local function layoutIgnoredGearList()
				local width = math.max((ignoredGearListMenuParent:GetWidth() or 0) - 30, 1)
				ignoredGearListMenu:SetWidth(width + 8)
				if ignoredGearListMenu.ignoredGearNote then
					ignoredGearListMenu.ignoredGearNote:SetWidth(math.max(width - 8, 100))
				end
				if ignoredGearListMenu.keepListNote then
					ignoredGearListMenu.keepListNote:SetWidth(math.max(width - 8, 100))
				end
				if ignoredGearListMenu.keepListAddNote then
					ignoredGearListMenu.keepListAddNote:SetWidth(math.max(width - 8, 100))
				end
				if TyGearRefreshKeepList then TyGearRefreshKeepList() end
				if TyGearRefreshIgnoredGearList then TyGearRefreshIgnoredGearList() end
				if ignoredGearListMenuParent.UpdateScrollChildRect then
					ignoredGearListMenuParent:UpdateScrollChildRect()
				end
			end
			ignoredGearListMenuParent:HookScript("OnSizeChanged", layoutIgnoredGearList)
			layoutIgnoredGearList()
		end
		if needListMenu and not needListMenu.built then
			needListMenu.built = true
			buildNeedListPage(needListMenu)
			local function layoutNeedList()
				local width = math.max((needListMenuParent:GetWidth() or 0) - 30, 1)
				needListMenu:SetWidth(width + 8)
				if needListMenu.needListNote then
					needListMenu.needListNote:SetWidth(math.max(width - 8, 100))
				end
				if needListMenu.needListAddNote then
					needListMenu.needListAddNote:SetWidth(math.max(width - 8, 100))
				end
				if TyGearRefreshNeedList then TyGearRefreshNeedList() end
				if needListMenuParent.UpdateScrollChildRect then
					needListMenuParent:UpdateScrollChildRect()
				end
			end
			needListMenuParent:HookScript("OnSizeChanged", layoutNeedList)
			layoutNeedList()
		end
		if personalWeightsMenu and not personalWeightsMenu.built then
			personalWeightsMenu.built = true
			buildPersonalStatWeightsPage(personalWeightsMenu)
			local function layoutPersonalWeights()
				local width = math.max((personalWeightsMenuParent:GetWidth() or 0) - 30, 1)
				personalWeightsMenu:SetWidth(width + 8)
				if personalWeightsMenu.personalNote then
					personalWeightsMenu.personalNote:SetWidth(math.max(width - 16, 100))
				end
				if personalWeightsMenu.personalStatus then
					personalWeightsMenu.personalStatus:SetWidth(math.max(width - 16, 100))
				end
				if personalWeightsMenu.personalImportNote then
					personalWeightsMenu.personalImportNote:SetWidth(math.max(width - 16, 100))
				end
				if personalWeightsMenu.personalImportBox then
					personalWeightsMenu.personalImportBox:SetWidth(math.max(width - 36, 120))
				end
				if personalWeightsMenu.layoutPersonalPage then
					personalWeightsMenu.layoutPersonalPage()
				end
				if personalWeightsMenuParent.UpdateScrollChildRect then
					personalWeightsMenuParent:UpdateScrollChildRect()
				end
			end
			personalWeightsMenuParent:HookScript("OnSizeChanged", layoutPersonalWeights)
			layoutPersonalWeights()
		end
		if IS_WOW_FOREVER then
			if ignoredGearListMenuParent and not ignoredGearListMenuParent.ignoreSectionHooked then
				ignoredGearListMenuParent.ignoreSectionHooked = true
				ignoredGearListMenuParent:HookScript("OnShow", function()
					if TyGearRefreshIgnoreSection then TyGearRefreshIgnoreSection() end
				end)
			end
		elseif not optionsMenuParent.ignoreSectionHooked then
			optionsMenuParent.ignoreSectionHooked = true
			optionsMenuParent:HookScript("OnShow", function()
				if TyGearRefreshIgnoreSection then TyGearRefreshIgnoreSection() end
			end)
		end

		hooksecurefunc("GetQuestReward", function() TyGearQueueLocalUpdate() end)

		TyGearQueueLocalUpdate()

		optionsMenu:UnregisterAllEvents()
		optionsMenu:SetScript("OnEvent", nil)

		pcall(TyGearFrame.RegisterEvent,TyGearFrame,"START_LOOT_ROLL")
		pcall(TyGearFrame.RegisterEvent,TyGearFrame,"CONFIRM_LOOT_ROLL")
		pcall(TyGearFrame.RegisterEvent,TyGearFrame,"CHAT_MSG_LOOT")
		pcall(TyGearFrame.RegisterEvent,TyGearFrame,"EQUIP_BIND_CONFIRM")
		pcall(TyGearFrame.RegisterEvent,TyGearFrame,"EQUIP_BIND_TRADEABLE_CONFIRM") --Fires when the player tries to equip a soulbound item that can still be traded to eligible players
		pcall(TyGearFrame.RegisterEvent,TyGearFrame,"MERCHANT_SHOW")
		pcall(TyGearFrame.RegisterEvent,TyGearFrame,"MERCHANT_CLOSED")              --Purchases produce no CHAT_MSG_LOOT, so scan once the merchant closes
		pcall(TyGearFrame.RegisterEvent,TyGearFrame,"PLAYER_LEVEL_UP")              --Items with a level requirement become usable without any loot event
		pcall(TyGearFrame.RegisterEvent,TyGearFrame,"PLAYER_EQUIPMENT_CHANGED")     --Fires when equipment is equipped or unequipped from the player, excluding bags
		pcall(TyGearFrame.RegisterEvent,TyGearFrame,"BAG_CONTAINER_UPDATE")         --Fires when bags are equipped or unequipped from the player
		pcall(TyGearFrame.RegisterEvent,TyGearFrame,"PLAYER_SPECIALIZATION_CHANGED")
		pcall(TyGearFrame.RegisterEvent,TyGearFrame,"CHARACTER_POINTS_CHANGED")
		pcall(TyGearFrame.RegisterEvent,TyGearFrame,"PLAYER_TALENT_UPDATE")
		pcall(TyGearFrame.RegisterEvent,TyGearFrame,"TRAIT_CONFIG_UPDATED")
		pcall(TyGearFrame.RegisterEvent,TyGearFrame,"TRAIT_NODE_CHANGED")
		pcall(TyGearFrame.RegisterEvent,TyGearFrame,"TRAIT_TREE_CURRENCY_INFO_UPDATED")
		pcall(TyGearFrame.RegisterEvent,TyGearFrame,"CONFIRM_DISENCHANT_ROLL")
		pcall(TyGearFrame.RegisterEvent,TyGearFrame,"ADDON_LOADED")                 --late-loaded Baganator/Bagnon junk and upgrade plugins

		TyGearSetupVendorJunkIntegrations()

		-- OnUpdate is enabled only while the action queue has work (see TyGearEnsureMainLoop)
		TyGearEnsureMainLoop()
	end
end)

_G["SLASH_TyGear1"] = "/TyGear"
_G["SLASH_TyGear2"] = "/tygear"
_G["SLASH_TyGear3"] = "/tg"
SlashCmdList["TyGear"] = function(msg)
	param1, param2, param3, param4, param5 = msg:match("([^%s,]*)[%s,]*([^%s,]*)[%s,]*([^%s,]*)[%s,]*([^%s,]*)[%s,]*([^%s,]*)[%s,]*")
	if (not param1) then param1 = "" end
	if (not param2) then param2 = "" end
	if (not param3) then param3 = "" end
	if (not param4) then param4 = "" end
	if (not param5) then param5 = "" end
	if (param1 == "enable" or param1 == "on" or param1 == "start") then
		TyGearToggleEnabled(true)
	elseif (param1 == "disable" or param1 == "off" or param1 == "stop") then
		TyGearToggleEnabled(false)
	elseif (param1 == "scan") then
		TyGearScan()
	elseif (param1 == "spec") then
		local localizedRealClass, realClass, realSpec, realClassID = TyGearDetectClassAndSpec()
		local localizedOverrideClass, overrideClass, overrideSpec, overrideClassID = TyGearGetClassAndSpec()
		local usingPawn = TyGearUsingPawn()
		local weightSystem = TyGearGetStatWeightSystem()
		local pawnScaleName = ""
		local pawnScaleLocalizedName = ""
		if usingPawn then
			pawnScaleName, pawnScaleLocalizedName = TyGearGetPawnScaleName()
		end
		TyGearPrint("TyGear: Looks like you are a"..(realSpec:find("^[AEIOUaeiou]") and "n " or " ")..RAID_CLASS_COLORS[realClass]:WrapTextInColorCode(realSpec.." "..localizedRealClass).."."..((usingPawn or (TyGearCharDB.Override and ((realClassID ~= overrideClassID) or (realSpec ~= overrideSpec)))) and ("  However, TyGear is using "..(usingPawn and ("Pawn scale \""..PawnGetScaleColor(pawnScaleName)..(pawnScaleLocalizedName or pawnScaleName)..FONT_COLOR_CODE_CLOSE.."\"") or (RAID_CLASS_COLORS[overrideClass]:WrapTextInColorCode(overrideSpec.." "..localizedOverrideClass).." weights")).." for gear evaluation due to the \""..(usingPawn and "Stat weight system: Pawn" or "Override specialization").."\" option.") or "").."  Stat weight system: "..weightSystem..(TyGearCurrentWeightSource and (" ("..TyGearCurrentWeightSource.." weights)") or "")..".  TyGear is using weapons value \""..weapons.."\" from \""..((TyGearCharDB.Override and ((realClassID ~= overrideClassID) or (realSpec ~= overrideSpec))) and (RAID_CLASS_COLORS[overrideClass]:WrapTextInColorCode(overrideSpec.." "..localizedOverrideClass)) or (RAID_CLASS_COLORS[realClass]:WrapTextInColorCode(realSpec.." "..localizedRealClass))).."\" to determine which weapons are valid.  CanDualWield() returns \""..(CanDualWield() and "true" or "false").."\".", 0) 
		if IS_WOW_FOREVER and (not TyGearCharDB.Override) and realSpec == "None" then
			TyGearPrint("TyGear: No talent points spent, so TyGear uses the general class profile.  Spend points in a talent tree, or enable \"Override specialization\", to use a healer, tank, or focused damage profile.", 0)
		end
	elseif (param1 == "verbosity") or (param1 == "allowedverbosity") then
		TyGearSetAllowedVerbosity(param2)
	elseif ((param1 == "setspec") or
	(param1 == "overridespec") or
	(param1 == "overridespecialization") or
	(param1 == "specoverride")) then
		local params = param2..(string.len(param3)>0 and " "..param3 or "")..(string.len(param4)>0 and " "..param4 or "")..(string.len(param5)>0 and " "..param5 or "")
		local localizedClassName, spec = string.match(params, "^\"?([^:\"]-): ([^:\"]+)\"?$")
		local class = TyGearReverseClassList[localizedClassName]
		local hasWeights = class and (TyGearGetInternalWeighting(class, spec) ~= nil)
		if hasWeights then
			local overridespec = localizedClassName..": "..spec
			TyGearCharDB.OverrideSpec = overridespec
			if TyGearOverrideSpecDropdown then
				TyGearOverrideSpecDropdown:SetValue(overridespec)
			end
			TyGearPrint("TyGear: "..(TyGearCharDB.Override and "" or "While \"Override specialization\" is enabled, ").."TyGear will now use "..RAID_CLASS_COLORS[class]:WrapTextInColorCode(overridespec).." weights to evaluate gear.",0)
		else
			TyGearPrint("TyGear: Unrecognized command. Usage: \"/tg overridespec [class]: [spec]\" (example: \"/tg overridespec Hunter: Beast Mastery\")",0)
		end
	elseif ((param1 == "pawnscale") or
	(param1 == "setpawnscale") or
	(param1 == "setscale") or
	(param1 == "scaleoverride")) then
		-- TyGearItemInfoCache = {}
		if PawnIsReady then
			if PawnIsReady() then
				local userPawnScaleName = param2..(string.len(param3)>0 and " "..param3 or "")..(string.len(param4)>0 and " "..param4 or "")..(string.len(param5)>0 and " "..param5 or "")
				if string.len(userPawnScaleName) == 0 then
					TyGearPrint("TyGear: Usage: \"/tg pawnscale [Pawn scale name]\" (example: \"/tg pawnscale Hunter: Beast Mastery\")",0)
					return
				end
				local truePawnScaleName, pawnScaleLocalizedName = TyGearGetPawnScaleName(userPawnScaleName)
				if PawnDoesScaleExist(truePawnScaleName) then
					TyGearDB.PawnScale = userPawnScaleName
					if TyGearPawnScaleDropdown then
						setDropdownText(TyGearPawnScaleDropdown, TyGearDB.PawnScale)
					end

					TyGearPrint("TyGear: "..((TyGearGetStatWeightSystem() == TyGearStatWeightSystemPawn) and "" or "While the stat weight system is set to Pawn, ").."TyGear will now use the \""..PawnGetScaleColor(truePawnScaleName)..(pawnScaleLocalizedName or truePawnScaleName)..FONT_COLOR_CODE_CLOSE.."\" Pawn scale to evaluate gear.",0)
				else
					TyGearPrint("TyGear: According to Pawn, a Pawn scale named \""..userPawnScaleName.."\" does not exist.",0)
				end
			else
				TyGearPrint("TyGear: Pawn is not ready yet.",0)
			end
		else
			TyGearPrint("TyGear: "..L["Pawn is not installed."],0)
		end
	elseif (param1 == "") then
		if InCombatLockdown() then
			--opening the settings panel is a restricted action in combat on modern clients
			TyGearPrint("TyGear: The options menu can't be opened in combat.  Type \"/tg\" again after combat.", 0)
		elseif Settings and Settings.OpenToCategory then
			local categoryID = optionsCategory and optionsCategory.GetID and optionsCategory:GetID()
			if not categoryID then
				--category registered natively: find it by the name it was registered with
				for _, category in next, SettingsPanel:GetAllCategories() do
					if category.name == optionsMenuParent.name then
						assert(not categoryID, 'found multiple instances of the same category')
						categoryID = category:GetID()
					end
				end
			end
			Settings.OpenToCategory(categoryID)
		else
			if not InterfaceAddOnsList_Update then
				InterfaceOptionsFrame_OpenToCategory(optionsMenu)
			end
			InterfaceOptionsFrame_OpenToCategory(optionsMenu)
		end
	else
		shouldPrintHelp = true
	end
end

function TyGearPrintHelp()
	TyGearPrint("TyGear: "..((param1 == "help") and "" or "Unrecognized command.  ").."Recognized commands (also /tygear):", 0)
	TyGearPrint("TyGear:    '/tg': options menu, including Ignore for equipment slots and items"..(IS_WOW_FOREVER and (", the Ignored List tab for ignore settings and the keep list, and the Need List tab for forced NEED rolls") or "")..", and the Personal Stat Weights tab", 0)
	TyGearPrint("TyGear:    '/tg help': command line help", 0)
	TyGearPrint("TyGear:    '/tg scan': scan all bags for gear upgrades", 0)
	TyGearPrint("TyGear:    '/tg spec': get name of current talent specialization", 0)
	TyGearPrint("TyGear:    '/tg [gear/toggle]/[enable/on/start]/[disable/off/stop]': toggle automatic gearing", 0)
	TyGearPrint("TyGear:    '/tg chime [enable/on/start]/[disable/off/stop]': toggle the sound played when an upgrade is equipped", 0)
	TyGearPrint("TyGear:    '/tg roll [enable/on/start]/[disable/off/stop]': toggle automatic loot rolling", 0)
	TyGearPrint("TyGear:    '/tg bind [enable/on/start]/[disable/off/stop]': toggle automatic soul-binding confirmation", 0)
	TyGearPrint("TyGear:    '/tg neverneed [enable/on/start]/[disable/off/stop]': toggle preventing automatically rolling NEED", 0)
	TyGearPrint("TyGear:    '/tg tooltip [toggle/show/hide]': toggle showing score in item tooltips", 0)
	TyGearPrint("TyGear:    '/tg reasons [toggle/show/hide]': toggle showing won't-auto-equip reasons in item tooltips", 0)
	TyGearPrint("TyGear:    '/tg compare [enable/on/start]/[disable/off/stop]': toggle always comparing gear", 0)
	TyGearPrint("TyGear:    '/tg override [enable/on/start]/[disable/off/stop]': toggle specialization override", 0)
	TyGearPrint("TyGear:    '/tg overridespec [class]: [spec]': set override spec to \"[class]: [spec]\"",0)
	TyGearPrint("TyGear:    '/tg weights [mythicsim/pawn/personal]': choose MythicSim (default), Pawn, or Personal Stat Weights", 0)
	TyGearPrint("TyGear:    '/tg pawn [enable/on/start]/[disable/off/stop]': same as weights; on selects Pawn, off selects MythicSim", 0)
	TyGearPrint("TyGear:    '/tg pawnscale [Pawn scale name]': set Pawn scale override to the specifed Pawn scale", 0)
	TyGearPrint("TyGear:    '/tg sell [enable/on/start]/[disable/off/stop]': toggle automatic selling of grey items", 0)
	TyGearPrint("TyGear:    '/tg sellunsuitable [enable/on/start]/[disable/off/stop]': toggle automatic selling of white gear you can't wear", 0)
	TyGearPrint("TyGear:    '/tg sellwhitegear [enable/on/start]/[disable/off/stop]': toggle automatic selling of all white gear", 0)
	TyGearPrint("TyGear:    '/tg verbosity [0/1/2/3]': set allowed verbosity level; valid levels are: 0 ("..TyGearGetAllowedVerbosityName(0).."), 1 ("..TyGearGetAllowedVerbosityName(1).."), 2 ("..TyGearGetAllowedVerbosityName(2).."), 3 ("..TyGearGetAllowedVerbosityName(3)..")", 0)
	TyGearPrint("TyGear:    Key Bindings → TyGear: the ignore list key keeps the hovered item and skips evaluation; the need list key forces NEED", 0)
	TyGearPrint("TyGear: Fork of AutoGear by Synthetikaryote and BujuArena. Original: https://github.com/BujuArena/AutoGear (CC BY-NC-SA 4.0).", 0)
end

function TyGearSetAllowedVerbosity(allowedverbosity)
	allowedverbosity = tonumber(allowedverbosity)
	if type(allowedverbosity) ~= "number" then
		TyGearPrint("TyGear: The current allowed verbosity level is "..tostring(TyGearDB.AllowedVerbosity).." ("..TyGearGetAllowedVerbosityName(TyGearDB.AllowedVerbosity).."). Valid levels are: 0 ("..TyGearGetAllowedVerbosityName(0).."), 1 ("..TyGearGetAllowedVerbosityName(1).."), 2 ("..TyGearGetAllowedVerbosityName(2).."), 3 ("..TyGearGetAllowedVerbosityName(3)..").", 0)
		return
	end

	if allowedverbosity < 0 or allowedverbosity > 3 then
		TyGearPrint("TyGear: That is an invalid allowed verbosity level. Valid levels are: 0 ("..TyGearGetAllowedVerbosityName(0).."), 1 ("..TyGearGetAllowedVerbosityName(1).."), 2 ("..TyGearGetAllowedVerbosityName(2).."), 3 ("..TyGearGetAllowedVerbosityName(3)..").", 0)
		return
	else
		TyGearDB.AllowedVerbosity = allowedverbosity
		local dropdown = _G["TyGearAllowedVerbosityDropdown"]
		if dropdown then
			setDropdownText(dropdown, TyGearGetAllowedVerbosityLabel(allowedverbosity))
		end
		TyGearPrint("TyGear: Allowed verbosity level is now: "..tostring(TyGearDB.AllowedVerbosity).." ("..TyGearGetAllowedVerbosityName(TyGearDB.AllowedVerbosity)..").", 0)
	end
end

function TyGearGetContainerItemInfo(bagIndex, bagSlot)
	--Forever/Mainline: GetContainerItemInfo returns a ContainerItemInfo table (same as C_Container).
	--Classic Era multi-return is texture, count, locked, quality, readable, lootable, link.
	--Returns count, locked, link, quality, itemID. Quality/itemID help junk marks when GetItemInfo is still empty.
	local info
	if C_Container and C_Container.GetContainerItemInfo then
		info = C_Container.GetContainerItemInfo(bagIndex, bagSlot)
	elseif GetContainerItemInfo then
		local a, b, c, d, e, f, g = GetContainerItemInfo(bagIndex, bagSlot)
		if type(a) == "table" then
			info = a
		elseif g then
			return b, c, g, d, nil
		end
	end
	if info then
		return info.stackCount, info.isLocked, info.hyperlink, info.quality, info.itemID
	end
end

function TyGearOnDetectedSpecChanged()
	local hadSpec = TyGearCachedSpec ~= nil
	local previousSpec = TyGearCachedSpec
	TyGearInvalidatePerformanceCaches()
	if TyGearSetStatWeights then TyGearSetStatWeights() end
	if TyGearRefreshActiveSpecCallout then TyGearRefreshActiveSpecCallout() end
	local localizedClass, class, spec = TyGearGetClassAndSpec()
	if hadSpec and spec ~= previousSpec and class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class] then
		TyGearPrint("TyGear: Talent specialization changed.  Considering all items for gear that's better suited for "..RAID_CLASS_COLORS[class]:WrapTextInColorCode(spec.." "..localizedClass)..".", 2)
		if TyGearConsiderAllItems then TyGearConsiderAllItems() end
	end
end

TyGearFrame:SetScript("OnEvent", function (this, event, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11, arg12, ...)

	if (event == "PLAYER_SPECIALIZATION_CHANGED" and arg1 == "player")
	or event == "CHARACTER_POINTS_CHANGED"
	or event == "PLAYER_TALENT_UPDATE"
	or event == "TRAIT_CONFIG_UPDATED"
	or event == "TRAIT_NODE_CHANGED"
	or event == "TRAIT_TREE_CURRENCY_INFO_UPDATED" then
		TyGearOnDetectedSpecChanged()
	elseif event == "PLAYER_EQUIPMENT_CHANGED" then
		-- Only refresh the changed equipped slot; avoid a full bag tooltip rescan per equip event
		TyGearHandleEquipmentChanged(arg1)
		--re-evaluate junk/upgrade marks: worn upgrades can free bag whites that were treated as upgrades
		TyGearQueueVendorJunkRefresh()
		TyGearQueueUpgradeRefresh()
		if TyGearRefreshIgnoreSection then
			local ignoreShown = (TyGearOptionsMenuScrollFrame and TyGearOptionsMenuScrollFrame:IsShown())
				or (TyGearIgnoredGearListMenuScrollFrame and TyGearIgnoredGearListMenuScrollFrame:IsShown())
			if ignoreShown then
				TyGearRefreshIgnoreSection()
			end
		end
	elseif event == "BAG_CONTAINER_UPDATE" then
		TyGearQueueLocalUpdate()
		if TyGearRefreshIgnoreSection then
			local ignoreShown = (TyGearOptionsMenuScrollFrame and TyGearOptionsMenuScrollFrame:IsShown())
				or (TyGearIgnoredGearListMenuScrollFrame and TyGearIgnoredGearListMenuScrollFrame:IsShown())
			if ignoreShown then
				TyGearRefreshIgnoreSection()
			end
		end
	elseif event == "BAG_UPDATE" then
		--registered while auto-sell or Baganator upgrade marks are active; not a full gear scan
		TyGearQueueVendorJunkRefresh()
		TyGearQueueUpgradeRefresh()
	elseif event == "MERCHANT_CLOSED" or event == "PLAYER_LEVEL_UP" then
		if event == "MERCHANT_CLOSED" then
			TyGearStopSellingGreys()
			TyGearQueueVendorJunkRefresh()
			TyGearQueueUpgradeRefresh()
		end
		-- Scan after the merchant closes (not during selling, so bag slots stay stable) and after leveling up.
		TyGearQueueScan()
	elseif event == "UI_ERROR_MESSAGE" then
		--in client versions before the original 7.0.3, the message is the only arg; in later mainline clients, and in classic clients since 1.13.2, a message type is the first arg
		TyGearHandleSellingError((type(arg1) == "string") and arg1 or arg2)
	elseif event == "START_LOOT_ROLL" then
		local link = GetLootRollItemLink(arg1)
		TyGearHandleLootRoll(link, arg1)
	elseif event == "CONFIRM_LOOT_ROLL" or event == "CONFIRM_DISENCHANT_ROLL" then
		ConfirmLootRoll(arg1, arg2)
	elseif event == "CHAT_MSG_LOOT" then --when receiving a new item
		local message = arg1
		--loot messages are secret values in dungeons, raids and encounters under the Midnight addon restrictions
		--(Retail 12, WoW Forever); they can't be matched then, so just scan the bags for the new item
		if issecretvalue and issecretvalue(message) then
			TyGearQueueScan()
			return
		end
		local patterns = TyGearGetLootPatterns()
		local link, quantity = message:match(patterns[1])
		if not link then
			link, quantity = message:match(patterns[2])
			if not link then
				link, quantity = message:match(patterns[3])
				if not link then
					link, quantity = message:match(patterns[4]), 1
					if not link then
						link, quantity = message:match(patterns[5]), 1
						if not link then
							link, quantity = message:match(patterns[6]), 1
						end
					end
				end
			end
		end

		local linkInvType
		if link then
			linkInvType = C_Item.GetItemInventoryTypeByID(link)
			if linkInvType then
				-- if it's not gear, return early to avoid scanning for upgrades
				if (linkInvType == Enum.InventoryType.IndexNonEquipType) then
					TyGearPrint("TyGear: Skipping scan because looted item "..link.." is not equippable gear.", 3)
					TyGearQueueVendorJunkRefresh()
					TyGearQueueUpgradeRefresh()
					return
				--make sure a fishing pole isn't replaced while fishing
				elseif (TyGearIsInvTypeWeapon(linkInvType) and TyGearIsMainHandAFishingPole()) then
					TyGearPrint("TyGear: Skipping scan because "..link.." is a weapon and a fishing pole is equipped. This is intentional to prevent replacing fishing poles while fishing.", 3)
					return
				end
			else
				TyGearPrint("TyGear: No inventory type was found for looted item "..link.." from CHAT_MSG_LOOT event message \""..message.."\". Scanning anyway in case it was gear.", 3)
			end
		else
			TyGearPrint("TyGear: No item link was found in CHAT_MSG_LOOT event message \""..message.."\". Scanning anyway in case the looted item was gear.", 3)
		end

		TyGearQueueScan()
	elseif (event == "EQUIP_BIND_CONFIRM") or
	(event == "EQUIP_BIND_REFUNDABLE_CONFIRM") or
	(event == "EQUIP_BIND_TRADEABLE_CONFIRM") then
		local rarity = Item:CreateFromItemLocation(C_Cursor.GetCursorItem()):GetItemQuality()
		if rarity == nil then return end
		if ((rarity ~= 3) and (rarity ~= 4) and (TyGearDB.AutoConfirmBinding == true)) or
		((rarity == 3) and (TyGearDB.AutoConfirmBindingBlues == true)) or
		((rarity == 4) and (TyGearDB.AutoConfirmBindingEpics == true)) then
			EquipPendingItem(arg1)
		end
	elseif event == "MERCHANT_SHOW" then
		TyGearQueueVendorJunkRefresh()
		TyGearQueueUpgradeRefresh()
		if (TyGearDB.AutoSellGreys == true)
		or (TyGearDB.AutoSellUnsuitableWhites == true)
		or (TyGearDB.AutoSellAllWhiteGear == true) then
			TyGearStartSellingGreys()
		end
	elseif event == "ADDON_LOADED" then
		if ((arg1 == "Baganator") or (arg1 == "Bagnon")) and TyGearDB then
			TyGearSetupVendorJunkIntegrations()
		end
	else
		if TyGearDB.AllowedVerbosity and TyGearDB.AllowedVerbosity >= 3 then
			TyGearPrint("TyGear: event fired: "..event, 3)
		end
	end
end)

function TyGearDecideRoll(link, lootRollID)
	if not TyGearCurrentWeighting then TyGearSetStatWeights() end
	if TyGearCurrentWeighting then
		local rollDecision = nil
		local canNeed = lootRollID and select(6,GetLootRollItemInfo(lootRollID)) or 1
		local lootRollItemID = GetItemInfoInstant(link)
		local rollItemInfo = TyGearReadItemInfo(nil, nil, nil, nil, link)
		local reason = rollItemInfo.reason or "(no reason set)"
		local onNeedList = TyGearIsOnNeedList(lootRollItemID or (rollItemInfo and rollItemInfo.id))
		-- True ignore-list items never roll. Keep-list items may still NEED when they fill an empty slot.
		if TyGearIsItemIgnored(rollItemInfo) then
			TyGearPrint("TyGear: "..(rollItemInfo.link or link).." is ignored, so not rolling.", 1)
			return nil, rollItemInfo, reason
		end
		if rollItemInfo.isMount then
			TyGearPrint("TyGear: "..(rollItemInfo.link or link).." is a mount, so not rolling.", 1)
			return nil, rollItemInfo, reason
		end
		local wouldNeed = onNeedList or TyGearConsiderAllItems(lootRollItemID, rollItemInfo, true)
		if (not onNeedList) and TyGearAllValidGearSlotsProtected(rollItemInfo) then
			TyGearPrint("TyGear: "..(rollItemInfo.link or link).." only fits ignored slots, so not rolling.", 1)
			return nil, rollItemInfo, reason
		end
		if (TyGearDB.RollOnNonGearLoot == false)
		and (not rollItemInfo.isGear)
		and (not onNeedList) then
			TyGearPrint("TyGear: "..rollItemInfo.link.." is not gear and \"Roll on non-gear loot\" is disabled, so not rolling.", 3)
			--local rollDecision is nil, so no roll
		elseif wouldNeed and canNeed then
			if onNeedList then
				rollDecision = 1 --need; explicit need-list items always need when possible
			elseif rollItemInfo.Within5levels or (not rollItemInfo.unusable) then
				local maxNumberOfCopiesAllowedToNeed = rollItemInfo.unique and 1
					or rollItemInfo.numEquippable
					or #rollItemInfo.validGearSlots
				local numberOfCopiesOwned = GetItemCount(rollItemInfo.id, true)
				if numberOfCopiesOwned >= maxNumberOfCopiesAllowedToNeed then
					TyGearPrint("TyGear: "..rollItemInfo.link.." is an upgrade usable within 5 levels, but you already have "..tostring(numberOfCopiesOwned).." cop"..(numberOfCopiesOwned == 1 and "y" or "ies")..", so rolling "..RED_FONT_COLOR_CODE.."GREED"..FONT_COLOR_CODE_CLOSE..".",3)
					rollDecision = 2 --greed
				else
					rollDecision = 1 --need
				end
			else
				rollDecision = 1 --need
			end
		else
			rollDecision = 2 --greed
			if (wouldNeed and not canNeed) then
				TyGearPrint("TyGear: Would roll NEED, but NEED is not an option for "..rollItemInfo.link..".", 1)
			end
		end
		return rollDecision, rollItemInfo, reason
	else
		local localizedClass, class, spec = TyGearGetClassAndSpec()
		TyGearPrint("TyGear: No weighting set for "..RAID_CLASS_COLORS[class]:WrapTextInColorCode(spec.." "..localizedClass)..".", 0)
	end
end

function TyGearHandleLootRoll(link, lootRollID)
	local item = Item:CreateFromItemLink(link)
	item:ContinueOnItemLoad(function()
		TyGearHandleLootRollCallback(link, lootRollID)
	end)
end

function TyGearHandleLootRollCallback(link, lootRollID)
		local rollDecision, rollItemInfo, reason = TyGearDecideRoll(link, lootRollID)
		if not rollItemInfo then
			TyGearPrint("TyGear: Error: Could not read item info for "..(link and link or "the rollable loot")..".", 0)
		elseif rollItemInfo.unusable then
			TyGearPrint("TyGear: "..link.." will not be equipped.  "..reason, 1)
		end
		if rollDecision then
			local newAction = {}
			newAction.action = "roll"
			newAction.t = GetTime() --roll right away
			newAction.rollID = lootRollID
			newAction.rollType = rollDecision
			newAction.info = rollItemInfo
			TyGearQueueAction(newAction)
		end
end

-- from Attrition addon
function TyGearCashToString(cash)
	if not cash then return "" end

	local gold   = floor(cash / (100 * 100))
	local silver = math.fmod(floor(cash / 100), 100)
	local copper = math.fmod(floor(cash), 100)
	gold         = gold   > 0 and "|cffeeeeee"..gold  .."|r|cffffd700g|r" or ""
	silver       = silver > 0 and "|cffeeeeee"..silver.."|r|cffc7c7cfs|r" or ""
	copper       = copper > 0 and "|cffeeeeee"..copper.."|r|cffeda55fc|r" or ""
	copper       = (silver ~= "" and copper ~= "") and " "..copper or copper
	silver       = (gold   ~= "" and silver ~= "") and " "..silver or silver

	return gold..silver..copper
end

--resolve an item name to an item ID using the client cache, bags, equipped gear, and known lists
function TyGearFindItemIDByName(name)
	if not name or name == "" then return end
	name = string.gsub(name, "^%s*(.-)%s*$", "%1")
	if name == "" or tonumber(name) then return end
	local lower = string.lower(name)

	if GetItemInfoInstant then
		local itemID = GetItemInfoInstant(name)
		itemID = tonumber(itemID)
		if itemID and itemID > 0 then return itemID end
	end
	if GetItemInfo then
		local _, itemLink = GetItemInfo(name)
		if itemLink then
			local itemID = tonumber(string.match(itemLink, "item:(%d+)"))
			if itemID and itemID > 0 then return itemID end
		end
	end

	local function nameMatches(itemID)
		if not itemID or not GetItemInfo then return false end
		local itemName = GetItemInfo(itemID)
		return itemName and string.lower(itemName) == lower
	end

	for slot = INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED do
		local itemID = GetInventoryItemID("player", slot)
		if nameMatches(itemID) then return itemID end
	end

	local lastBag = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
	for bag = 0, lastBag do
		for slot = 1, GetContainerNumSlots(bag) or 0 do
			local itemID = GetContainerItemID(bag, slot)
			if nameMatches(itemID) then return itemID end
		end
	end

	if TyGearUnmeasurableGearList then
		for _, entry in ipairs(TyGearUnmeasurableGearList) do
			if entry.name and string.lower(entry.name) == lower then
				return entry.id
			end
		end
	end

	if TyGearCraftingToolItemIDs then
		for _, itemID in ipairs(TyGearCraftingToolItemIDs) do
			if nameMatches(itemID) then return itemID end
		end
	end
end

--reads item IDs from text containing item IDs, item names, and item links, in order and without duplicates
function TyGearParseItemIDList(text)
	--item links hold other numbers too (enchants, bonus IDs, digits in item names), so reduce each link to its item ID first
	text = string.gsub(text or "", "|c[^|]*|Hitem:(%d+)[^|]*|h.-|h|r", " %1 ")
	text = string.gsub(text, "|Hitem:(%d+)[^|]*|h.-|h", " %1 ")
	local itemIDs, isListed = {}, {}
	local function addID(itemID)
		itemID = tonumber(itemID)
		if itemID and itemID > 0 and not isListed[itemID] then
			isListed[itemID] = true
			table.insert(itemIDs, itemID)
		end
	end
	for segment in string.gmatch(text..",", "([^,]*),") do
		segment = string.gsub(segment, "^%s*(.-)%s*$", "%1")
		if segment ~= "" then
			local asNumber = tonumber(segment)
			if asNumber then
				addID(asNumber)
			else
				local byName = TyGearFindItemIDByName(segment)
				if byName then
					addID(byName)
				else
					--bare numeric lists without commas still work
					for itemIDText in string.gmatch(segment, "%d+") do
						addID(itemIDText)
					end
				end
			end
		end
	end
	return itemIDs
end

--fold the old greys exclusion list and whites ignore list into one keep list of grey and common item IDs
function TyGearMigrateVendorKeepList()
	if (TyGearDB.SellGreysExclusions == nil) and (TyGearDB.SellWhitesIgnoreList == nil) then
		return
	end
	local seen, ordered = {}, {}
	local function addList(text)
		for _, itemID in ipairs(TyGearParseItemIDList(text or "")) do
			if not seen[itemID] then
				seen[itemID] = true
				table.insert(ordered, itemID)
			end
		end
	end
	--preserve a customized whites ignore list; profession tools are hard-kept and need not be seeded
	if TyGearDB.SellWhitesIgnoreList ~= nil then
		addList(TyGearDB.SellWhitesIgnoreList)
	end
	addList(TyGearDB.SellGreysExclusions)
	TyGearDB.VendorKeepList = table.concat(ordered, ", ")
	TyGearDB.SellGreysExclusions = nil
	TyGearDB.SellWhitesIgnoreList = nil
end

--drop post-vanilla crafting tools that are not in WoW Forever from a saved keep list
function TyGearPruneForeverVendorKeepList()
	if not IS_WOW_FOREVER or not TyGearDB or TyGearDB.VendorKeepList == nil then
		return
	end
	if not TyGearCraftingToolItemIDsMissingOnForever then return end
	local ordered = {}
	local removed = false
	for _, itemID in ipairs(TyGearParseItemIDList(TyGearDB.VendorKeepList or "")) do
		if TyGearCraftingToolItemIDsMissingOnForever[itemID] then
			removed = true
		else
			table.insert(ordered, itemID)
		end
	end
	if removed then
		TyGearDB.VendorKeepList = table.concat(ordered, ", ")
	end
end

--drop items that were removed from the default keep list (fishing poles kept by subclass; non-gear whites never sold as white gear)
function TyGearPruneRemovedDefaultKeepListItems()
	if not TyGearDB or TyGearDB.VendorKeepList == nil then
		return
	end
	if not TyGearRemovedDefaultKeepListItemIDs then return end
	local ordered = {}
	local removed = false
	for _, itemID in ipairs(TyGearParseItemIDList(TyGearDB.VendorKeepList or "")) do
		if TyGearRemovedDefaultKeepListItemIDs[itemID] then
			removed = true
		else
			table.insert(ordered, itemID)
		end
	end
	if removed then
		TyGearDB.VendorKeepList = table.concat(ordered, ", ")
	end
end

--drop hard-kept profession tools from the editable keep-list text; they stay protected by ID set / subclass
function TyGearStripDefaultVendorKeepListItems()
	if not TyGearDB or TyGearDB.VendorKeepList == nil then
		return
	end
	if not TyGearCraftingToolItemIDSet then return end
	local ordered = {}
	local removed = false
	for _, itemID in ipairs(TyGearParseItemIDList(TyGearDB.VendorKeepList or "")) do
		if TyGearCraftingToolItemIDSet[itemID] then
			removed = true
		else
			table.insert(ordered, itemID)
		end
	end
	if removed then
		TyGearDB.VendorKeepList = table.concat(ordered, ", ")
	end
end

--greys which have a sell price but which vendors refuse to buy
TyGearUnsellableGreyItemIDs = {
	[200590] = true, --Carefully Rolled Message
	[200592] = true, --Dirty Old Satchel
	[200593] = true, --Sealed Expedition Note
	[200594] = true, --Thaelin's Second Favorite Comb
	[200595] = true, --Odorous Parchment
	[200596] = true, --Letter from Thaelin Darkanvil
	[200606] = true, --Previously Owned Map
	[228431] = true, --Rock Buddy
}

--greys which Keeper Ta'hult in Oribos takes as payment for the Baubleworm pets
TyGearKeeperTahultPetGreyItemIDs = {
	[3300] = true, --Rabbit's Foot
	[3670] = true, --Large Slimy Bone
	[6150] = true, --A Frayed Knot
	[11406] = true, --Rotting Bear Carcass
	[11944] = true, --Dark Iron Baby Booties
	[25402] = true, --The Stoppable Force
	[36812] = true, --Ground Gear
	[62072] = true, --Robble's Wobbly Staff
	[67410] = true, --Very Unlucky Rock
}

--state of selling greys and white gear at the open vendor; nil while not selling
local greySelling

--true when this class can equip the item. Nil when the client can't answer.
--A level requirement does not make this false; IsEquippableItem checks class and item type.
function TyGearPlayerCanEquipItem(itemID, link)
	local canEquip
	if IsEquippableItem then
		canEquip = IsEquippableItem(link or itemID)
	elseif C_Item and C_Item.IsEquippableItem then
		local ok
		ok, canEquip = pcall(C_Item.IsEquippableItem, itemID)
		if not ok then return nil end
	else
		return nil
	end
	if issecretvalue and issecretvalue(canEquip) then return nil end
	return canEquip and true or false
end

--weapons and armor a vendor pass may sell. Tabards and shirts stay (cosmetic; not evaluated).
function TyGearIsVendorWhiteGear(classID, equipLoc)
	if (classID ~= Enum.ItemClass.Weapon) and (classID ~= Enum.ItemClass.Armor) then
		return false
	end
	if (not equipLoc) or (equipLoc == "") or (equipLoc == "INVTYPE_NON_EQUIP")
	or (equipLoc == "INVTYPE_TABARD") or (equipLoc == "INVTYPE_BODY") or (equipLoc == "INVTYPE_BAG")
	or (equipLoc == "INVTYPE_QUIVER") or (equipLoc == "INVTYPE_AMMO")
	or (equipLoc == "INVTYPE_PROFESSION_TOOL") or (equipLoc == "INVTYPE_PROFESSION_GEAR") then
		return false
	end
	return true
end

function TyGearVendorSellOptionsEnabled()
	return TyGearDB
		and ((TyGearDB.AutoSellGreys == true)
			or (TyGearDB.AutoSellUnsuitableWhites == true)
			or (TyGearDB.AutoSellAllWhiteGear == true))
end

--keptItemIDs, merchantCostItemIDs, upgradeBagSlots, questItemCache; includeMerchantCosts reads the open vendor
function TyGearBuildVendorSellContext(includeMerchantCosts, refreshUpgrades)
	local context = {
		keptItemIDs = {},
		merchantCostItemIDs = {},
		upgradeBagSlots = {},
		questItemCache = {},
		ignoreLocked = true,
	}
	if TyGearDB then
		for _, itemID in ipairs(TyGearParseItemIDList(TyGearDB.VendorKeepList or "")) do
			context.keptItemIDs[itemID] = true
		end
	end
	--profession weapon tools stay unsold even when VendorKeepList was cleared
	for _, itemID in ipairs(TyGearCraftingToolItemIDs or {}) do
		context.keptItemIDs[itemID] = true
	end
	if includeMerchantCosts and GetMerchantNumItems and GetMerchantItemCostInfo and GetMerchantItemCostItem then
		for merchantIndex = 1, GetMerchantNumItems() do
			for costIndex = 1, (GetMerchantItemCostInfo(merchantIndex) or 0) do
				local _, _, costLink = GetMerchantItemCostItem(merchantIndex, costIndex)
				local costItemID = costLink and tonumber(string.match(costLink, "item:(%d+)"))
				if costItemID then
					context.merchantCostItemIDs[costItemID] = true
				end
			end
		end
	end
	if refreshUpgrades and TyGearUpdateBestItems then
		TyGearUpdateBestItems()
	elseif (not TyGearEquippedItems) or (not next(TyGearEquippedItems)) then
		if TyGearUpdateEquippedItems then TyGearUpdateEquippedItems() end
	end
	if TyGearBestItems then
		for invSlot, bestItem in pairs(TyGearBestItems) do
			--only protect bag gear that is still better than what is worn
			if bestItem.bag and bestItem.slot and (not bestItem.equipped) then
				local equipped = TyGearEquippedItems and TyGearEquippedItems[invSlot]
				if (not equipped) or (not equipped.info) or equipped.info.empty
				or ((bestItem.score or 0) > (equipped.score or 0)) then
					context.upgradeBagSlots[bestItem.bag..":"..bestItem.slot] = true
				end
			end
		end
	end
	return context
end

--crafting tools, the keep list, fishing poles, and profession equipment stay when selling whites
function TyGearIsKeptVendorItem(itemID, classID, subclassID, context)
	context = context or greySelling
	if context and context.keptItemIDs[itemID] then return true end
	--Skinning Knife, Mining Pick, Blacksmith Hammer, Arclight Spanner, fishing poles on the default list, …
	if itemID and TyGearCraftingToolItemIDSet and TyGearCraftingToolItemIDSet[itemID] then
		return true
	end
	local fishingPoleSubclass = Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Fishingpole
	if fishingPoleSubclass and (classID == Enum.ItemClass.Weapon) and (subclassID == fishingPoleSubclass) then
		return true
	end
	--Dragonflight and later profession tools and accessories are not weapons or armor
	local professionClass = Enum.ItemClass and Enum.ItemClass.Profession
	if professionClass and (classID == professionClass) then
		return true
	end
	return false
end

--whether a white item should be sold by the white-gear options
function TyGearShouldSellWhiteGear(itemID, link, classID, subclassID, equipLoc, context)
	context = context or greySelling
	if (TyGearDB.AutoSellUnsuitableWhites ~= true) and (TyGearDB.AutoSellAllWhiteGear ~= true) then
		return false
	end
	if TyGearIsKeptVendorItem(itemID, classID, subclassID, context) then return false end
	if context and context.merchantCostItemIDs[itemID] then return false end
	if not TyGearIsVendorWhiteGear(classID, equipLoc) then return false end
	if TyGearDB.AutoSellAllWhiteGear == true then return true end
	local canEquip = TyGearPlayerCanEquipItem(itemID, link)
	return canEquip == false
end

--read quality/class/equip/sell price for a bag slot; prefer live container data when GetItemInfo is empty or secret
local function TyGearGetBagItemVendorInfo(bag, slot, link, containerQuality, containerItemID)
	local itemID = containerItemID or (link and tonumber(string.match(link, "item:(%d+)")))
	local _, _, quality, _, _, _, _, _, equipLoc, _, sellPrice, classID, subclassID = GetItemInfo(link or itemID)

	local function isUsable(value)
		return value ~= nil and not (issecretvalue and issecretvalue(value))
	end

	if not isUsable(quality) then
		quality = containerQuality
	end
	if not isUsable(quality) and Item and Item.CreateFromBagAndSlot then
		local item = Item:CreateFromBagAndSlot(bag, slot)
		if item and item.IsItemEmpty and (not item:IsItemEmpty()) and item.GetItemQuality then
			local itemQuality = item:GetItemQuality()
			if isUsable(itemQuality) then
				quality = itemQuality
			end
		end
	end

	if (not isUsable(classID)) or (not isUsable(subclassID)) or (not isUsable(equipLoc)) or equipLoc == "" then
		local _, _, _, instantEquipLoc, _, instantClassID, instantSubclassID = GetItemInfoInstant(itemID or link)
		if not isUsable(classID) then classID = instantClassID end
		if not isUsable(subclassID) then subclassID = instantSubclassID end
		if (not isUsable(equipLoc)) or equipLoc == "" then equipLoc = instantEquipLoc end
	end

	if (not isUsable(sellPrice)) or sellPrice <= 0 then
		local _, _, _, _, _, _, _, _, _, _, idSellPrice = GetItemInfo(itemID)
		if isUsable(idSellPrice) and idSellPrice > 0 then
			sellPrice = idSellPrice
		end
	end

	return itemID, quality, sellPrice, classID, subclassID, equipLoc
end

--returns the sale value, link, and quality of the item in a bag slot if it should be sold to a vendor, or nil to keep it
--context defaults to the active greySelling session; junk marking passes its own context
--covers greys and, when those options are on, white weapons/armor TyGear would sell
function TyGearGetItemSaleValue(bag, slot, context)
	context = context or greySelling
	if not context then return end
	local count, locked, link, containerQuality, containerItemID = TyGearGetContainerItemInfo(bag, slot)
	if not link then return end
	count = count or 1
	if locked and (not context.ignoreLocked) then return end
	local itemID, quality, sellPrice, classID, subclassID, equipLoc = TyGearGetBagItemVendorInfo(bag, slot, link, containerQuality, containerItemID)
	--battle pets have battlepet: links and can't be sold
	if not itemID then return end
	--ignore list items, including the keep list, are not sold
	if TyGearIsLeftOut(itemID) then return end
	if (not quality) or (issecretvalue and issecretvalue(quality)) then return end
	if (not sellPrice) or (issecretvalue and issecretvalue(sellPrice)) or sellPrice <= 0 then return end

	local poorQuality = (Enum.ItemQuality and Enum.ItemQuality.Poor) or 0
	local commonQuality = (Enum.ItemQuality and Enum.ItemQuality.Common) or 1

	--keep list is all-inclusive for greys and common (white) item IDs
	if context.keptItemIDs[itemID] then return end

	if quality == poorQuality then
		--a white-gear pass must not sell greys unless that option is on
		if TyGearDB.AutoSellGreys ~= true then return end
		if TyGearUnsellableGreyItemIDs[itemID]
		or (TyGearDB.KeepKeeperTahultPetItems and TyGearKeeperTahultPetGreyItemIDs[itemID])
		or context.merchantCostItemIDs[itemID] then
			return
		end
		if TyGearDB.KeepUnboundGreyGear and ((classID == Enum.ItemClass.Weapon) or (classID == Enum.ItemClass.Armor)) then
			local isBound
			if C_Item and C_Item.IsBound and ItemLocation then
				isBound = C_Item.IsBound(ItemLocation:CreateFromBagAndSlot(bag, slot))
			else
				isBound = TyGearItemContainsText(bag, slot, ITEM_SOULBOUND)
			end
			if not isBound then return end
		end
	elseif quality == commonQuality then
		--AutoSellUnsuitableWhites / AutoSellAllWhiteGear: same rules for vendor selling and junk marks
		if not TyGearShouldSellWhiteGear(itemID, link, classID, subclassID, equipLoc, context) then
			return
		end
	else
		return
	end

	local bagSlotKey = bag..":"..slot
	if context.upgradeBagSlots[bagSlotKey] then return end
	--an item whose tooltip can't be read can't be ruled out as a quest item
	local cachedQuest = context.questItemCache[bagSlotKey]
	local isQuestItem, isTooltipUnreadable
	if cachedQuest ~= nil then
		isQuestItem, isTooltipUnreadable = cachedQuest[1], cachedQuest[2]
	else
		isQuestItem, isTooltipUnreadable = TyGearIsQuestItem(bag, slot)
		context.questItemCache[bagSlotKey] = { isQuestItem, isTooltipUnreadable }
	end
	if isQuestItem or isTooltipUnreadable then return end

	return sellPrice * count, link, quality
end

--counts sales which went through, judging by the item having left its bag slot; returns whether any sale is still pending
function TyGearSettleGreySales()
	local isAnySalePending = false
	for _, sale in pairs(greySelling.sales) do
		if not sale.isSold then
			local _, locked, link = TyGearGetContainerItemInfo(sale.bag, sale.slot)
			if link ~= sale.link then
				sale.isSold = true
				greySelling.soldValue = greySelling.soldValue + sale.value
				greySelling.soldCount = greySelling.soldCount + 1
				if sale.quality == 1 then
					greySelling.soldWhiteCount = greySelling.soldWhiteCount + 1
				else
					greySelling.soldGreyCount = greySelling.soldGreyCount + 1
				end
				if sale.link then
					table.insert(greySelling.soldItems, { link = sale.link, value = sale.value })
				end
			elseif locked then
				isAnySalePending = true
			end
		end
	end
	return isAnySalePending
end

--sells everything that should be sold and returns whether selling needs another pass
function TyGearSellGreysPass()
	local needsAnotherPass = TyGearSettleGreySales()
	for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS) do
		for slot = 1, GetContainerNumSlots(bag) do
			local value, link, quality = TyGearGetItemSaleValue(bag, slot)
			if value then
				local saleKey = bag..":"..slot..":"..link
				local sale = greySelling.sales[saleKey]
				if not sale then
					sale = { bag = bag, slot = slot, link = link, value = value, quality = quality, attempts = 0 }
					greySelling.sales[saleKey] = sale
				end
				if sale.attempts < 10 then
					sale.attempts = sale.attempts + 1
					UseContainerItem(bag, slot)
					needsAnotherPass = true
				end
			end
		end
	end
	return needsAnotherPass
end

function TyGearVendorShiftSkipMessage()
	local sellWhites = (TyGearDB.AutoSellUnsuitableWhites == true) or (TyGearDB.AutoSellAllWhiteGear == true)
	local sellGreys = (TyGearDB.AutoSellGreys == true)
	if sellWhites and sellGreys then
		return "TyGear: Not selling greys or white gear this time because Shift was held while opening the vendor."
	elseif sellWhites then
		return "TyGear: Not selling white gear this time because Shift was held while opening the vendor."
	end
	return "TyGear: Not selling greys this time because Shift was held while opening the vendor."
end

--one complete chat line per sold item, e.g. TyGear: Sold [Well-stitched Robe] for 55c.
function TyGearFormatVendorSaleSummary(soldItems)
	if (not soldItems) or (#soldItems == 0) then return end
	local lines = {}
	for _, item in ipairs(soldItems) do
		lines[#lines + 1] = "TyGear: Sold "..item.link.." for "..TyGearCashToString(item.value).."."
	end
	return table.concat(lines, "\n")
end

function TyGearStartSellingGreys()
	if greySelling then TyGearStopSellingGreys() end
	if IsShiftKeyDown() then
		TyGearPrint(TyGearVendorShiftSkipMessage(), 2)
		return
	end

	--refresh upgrades and include this vendor's payment items
	greySelling = TyGearBuildVendorSellContext(true, true)
	greySelling.sales = {}
	greySelling.soldValue = 0
	greySelling.soldCount = 0
	greySelling.soldGreyCount = 0
	greySelling.soldWhiteCount = 0
	greySelling.soldItems = {}
	greySelling.sellsGreys = (TyGearDB.AutoSellGreys == true)
	greySelling.sellsWhites = (TyGearDB.AutoSellUnsuitableWhites == true) or (TyGearDB.AutoSellAllWhiteGear == true)
	greySelling.ignoreLocked = nil

	TyGearFrame:RegisterEvent("UI_ERROR_MESSAGE")
	TyGearQueueAction({ action = "sellgreys", t = GetTime() + 0.2 })
end

function TyGearStopSellingGreys(reason)
	if not greySelling then return end
	TyGearSettleGreySales()
	TyGearFrame:UnregisterEvent("UI_ERROR_MESSAGE")
	if greySelling.soldCount > 0 then
		TyGearPrint(TyGearFormatVendorSaleSummary(greySelling.soldItems), 1)
	end
	if reason then
		local what = "greys"
		if greySelling.sellsWhites and greySelling.sellsGreys then
			what = "items"
		elseif greySelling.sellsWhites then
			what = "white gear"
		end
		TyGearPrint("TyGear: Stopped selling "..what.." because "..reason..".", 1)
	end
	greySelling = nil
end

function TyGearSellGreysTick()
	--using a bag item with no vendor open would use or equip it instead of selling it
	if not (MerchantFrame and MerchantFrame:IsShown()) then
		TyGearStopSellingGreys()
		return
	end
	if not TyGearSellGreysPass() then
		TyGearStopSellingGreys()
	else
		TyGearQueueAction({ action = "sellgreys", t = GetTime() + 0.2 })
	end
end

function TyGearHandleSellingError(message)
	if (not greySelling) or (not message) or (issecretvalue and issecretvalue(message)) then return end
	if message == ERR_VENDOR_DOESNT_BUY then
		TyGearStopSellingGreys("this vendor doesn't buy items")
	elseif message == ERR_TOO_MUCH_GOLD then
		TyGearStopSellingGreys("you have max gold on this character")
	end
end

--bag slots TyGear would sell at a vendor; bag addons such as Baganator read this as junk
local vendorJunkSlots = {}
local vendorJunkListeners = {}
local vendorJunkBagEventRegistered
local vendorJunkIntegrationsReady
--Baganator upgrade plugin: item links better than equipped gear
local upgradeLinks = {}
local upgradeListeners = {}
local upgradeBagEventWanted
local baganatorUpgradeRegistered

function TyGearIsVendorJunk(bag, slot)
	return vendorJunkSlots[bag..":"..slot] == true
end

function TyGearAddVendorJunkListener(callback)
	if type(callback) == "function" then
		table.insert(vendorJunkListeners, callback)
	end
end

local function TyGearNotifyVendorJunkListeners()
	for _, callback in ipairs(vendorJunkListeners) do
		pcall(callback)
	end
end

function TyGearSyncVendorJunkBagEvent()
	if not TyGearFrame then return end
	--upgrades also need BAG_UPDATE; keep it while either junk selling or upgrade marks are active
	local wantEvent = (TyGearVendorSellOptionsEnabled() or upgradeBagEventWanted) and true or false
	if wantEvent and not vendorJunkBagEventRegistered then
		pcall(TyGearFrame.RegisterEvent, TyGearFrame, "BAG_UPDATE")
		vendorJunkBagEventRegistered = true
	elseif (not wantEvent) and vendorJunkBagEventRegistered then
		pcall(TyGearFrame.UnregisterEvent, TyGearFrame, "BAG_UPDATE")
		vendorJunkBagEventRegistered = nil
	end
end

local vendorJunkContext

function TyGearRefreshVendorJunkMarks()
	wipe(vendorJunkSlots)
	vendorJunkContext = nil
	if not TyGearVendorSellOptionsEnabled() then
		TyGearSyncVendorJunkBagEvent()
		TyGearNotifyVendorJunkListeners()
		return
	end
	local merchantOpen = MerchantFrame and MerchantFrame:IsShown()
	--refresh BestItems so bag whites beaten by worn gear are not kept as upgrades
	vendorJunkContext = TyGearBuildVendorSellContext(merchantOpen, true)
	for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS) do
		for slot = 1, GetContainerNumSlots(bag) do
			if TyGearGetItemSaleValue(bag, slot, vendorJunkContext) then
				vendorJunkSlots[bag..":"..slot] = true
			end
		end
	end
	TyGearSyncVendorJunkBagEvent()
	TyGearNotifyVendorJunkListeners()
end

function TyGearQueueVendorJunkRefresh()
	if not TyGearDB then return end
	local debounceUntil = GetTime() + 0.35
	for _, curAction in ipairs(TyGearActionQueue) do
		if curAction.t and (curAction.action == "vendorjunk") then
			if curAction.t < debounceUntil then
				curAction.t = debounceUntil
			end
			return
		end
	end
	TyGearQueueAction({ action = "vendorjunk", t = debounceUntil })
end

local baganatorJunkRegistered
local bagnonJunkRegistered
local blizzardJunkRegistered

local function TyGearRegisterBaganatorJunkPlugin()
	if baganatorJunkRegistered then return end
	if not (Baganator and Baganator.API and Baganator.API.RegisterJunkPlugin) then return end
	Baganator.API.RegisterJunkPlugin("TyGear", "tygear", function(bagID, slotID)
		if not TyGearVendorSellOptionsEnabled() then return false end
		local key = bagID..":"..slotID
		if vendorJunkSlots[key] then return true end
		--Baganator may query before the debounced cache rebuild finishes
		if not vendorJunkContext then
			vendorJunkContext = TyGearBuildVendorSellContext(false, true)
		end
		local isJunk = TyGearGetItemSaleValue(bagID, slotID, vendorJunkContext) and true or false
		if isJunk then
			vendorJunkSlots[key] = true
		end
		return isJunk
	end)
	TyGearAddVendorJunkListener(function()
		if Baganator.API.RequestItemButtonsRefresh then
			Baganator.API.RequestItemButtonsRefresh()
		end
	end)
	baganatorJunkRegistered = true
end

local function TyGearRegisterBagnonJunkMarks()
	if bagnonJunkRegistered then return end
	if not (Bagnon and Bagnon.Item and Bagnon.Item.UpdateBorder) then return end
	local UpdateBorder = Bagnon.Item.UpdateBorder
	local r, g, b = 0.62, 0.62, 0.62
	if GetItemQualityColor then
		r, g, b = GetItemQualityColor(0)
	end
	function Bagnon.Item:UpdateBorder(...)
		UpdateBorder(self, ...)
		--only override Bagnon's junk icon while TyGear is marking vendor-sell items
		if not TyGearVendorSellOptionsEnabled() then return end
		local bag, slot = self.GetBag and self:GetBag(), self.GetID and self:GetID()
		if (type(bag) ~= "number") or (not slot) then return end
		if self.JunkIcon then
			self.JunkIcon:Hide()
		end
		if TyGearIsVendorJunk(bag, slot) then
			if self.IconGlow then
				self.IconGlow:SetVertexColor(r, g, b, 0.5)
				self.IconGlow:Show()
			end
			if self.JunkIcon then
				self.JunkIcon:Show()
			end
		end
	end
	TyGearAddVendorJunkListener(function()
		if Bagnon.Frames and Bagnon.Frames.Update then
			Bagnon.Frames:Update()
		end
	end)
	bagnonJunkRegistered = true
end

local function TyGearRegisterBlizzardBagJunkMarks()
	if blizzardJunkRegistered then return end
	--own coin texture: default bags hide JunkIcon on every refresh, and white sell gear needs a mark
	local coins = setmetatable({}, { __mode = "k" })
	local function mark(button, bag, slot)
		if (not button) or (type(bag) ~= "number") or (not slot) then return end
		local junk = TyGearIsVendorJunk(bag, slot)
		local coin = coins[button]
		if not coin then
			if not junk then return end
			coin = button:CreateTexture(nil, "OVERLAY", nil, 6)
			local usedAtlas = coin.SetAtlas and pcall(coin.SetAtlas, coin, "bags-junkcoin", true)
			if not usedAtlas then
				coin:SetTexture("Interface\\Buttons\\UI-GroupLoot-Coin-Up")
				coin:SetSize(16, 16)
			end
			coin:SetPoint("TOPLEFT", 1, 0)
			coins[button] = coin
		end
		coin:SetShown(junk)
	end

	local refresh
	if _G.ContainerFrameContainer then
		local frames = { _G.ContainerFrameCombinedBags }
		for _, frame in ipairs(ContainerFrameContainer.ContainerFrames) do
			table.insert(frames, frame)
		end
		local function refreshFrame(frame)
			if not (frame and frame.EnumerateValidItems) then return end
			for _, button in frame:EnumerateValidItems() do
				if button and button.GetBagID then
					mark(button, button:GetBagID(), button:GetID())
				end
			end
		end
		for _, frame in ipairs(frames) do
			if frame and frame.UpdateItems then
				hooksecurefunc(frame, "UpdateItems", refreshFrame)
			end
		end
		refresh = function()
			for _, frame in ipairs(frames) do
				refreshFrame(frame)
			end
		end
	elseif _G.ContainerFrame_Update then
		local function refreshFrame(frame)
			if not frame then return end
			local name = frame:GetName()
			for i = 1, frame.size or 0 do
				local button = _G[name.."Item"..i]
				if button then
					mark(button, frame:GetID(), button:GetID())
				end
			end
		end
		hooksecurefunc("ContainerFrame_Update", refreshFrame)
		refresh = function()
			for i = 1, (NUM_CONTAINER_FRAMES or 0) do
				refreshFrame(_G["ContainerFrame"..i])
			end
		end
	end
	if refresh then
		TyGearAddVendorJunkListener(refresh)
		blizzardJunkRegistered = true
	end
end

function TyGearSetupVendorJunkIntegrations()
	if vendorJunkIntegrationsReady then
		--bag addons may load later; retry those registrations
		pcall(TyGearRegisterBaganatorJunkPlugin)
		pcall(TyGearRegisterBagnonJunkMarks)
		pcall(TyGearRegisterBaganatorUpgradePlugin)
		TyGearQueueVendorJunkRefresh()
		TyGearQueueUpgradeRefresh()
		return
	end
	vendorJunkIntegrationsReady = true
	local isAddOnLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
	if isAddOnLoaded("Baganator") then
		pcall(TyGearRegisterBaganatorJunkPlugin)
		pcall(TyGearRegisterBaganatorUpgradePlugin)
	end
	if isAddOnLoaded("Bagnon") then
		pcall(TyGearRegisterBagnonJunkMarks)
	end
	pcall(TyGearRegisterBlizzardBagJunkMarks)
	TyGearQueueVendorJunkRefresh()
	TyGearQueueUpgradeRefresh()
end

--whether info would score better than the weakest valid equipped slot TyGear manages
-- Keep-list items only count as upgrades when they fill an empty slot (something > nothing).
function TyGearWouldUpgradeEquipped(info)
	if (not info) or info.empty or (not info.isGear) or TyGearIsItemIgnored(info) then
		return false
	end
	if info.classCannotUseWeapon then return false end
	if not (info.usable or info.Within5levels) then return false end
	if TyGearIsReagentBag(info) then
		TyGearAssignReagentBagSlots(info)
	end
	if (not info.validGearSlots) or TyGearAllValidGearSlotsProtected(info) then
		return false
	end
	if (not TyGearEquippedItems) or (not next(TyGearEquippedItems)) then
		if TyGearUpdateEquippedItems then TyGearUpdateEquippedItems() end
	end
	if not TyGearEquippedItems then return false end

	local keepOnly = TyGearIsVendorKeepOnly(info)
	local lowestSlot
	local lowestScore
	for _, gearSlot in pairs(info.validGearSlots) do
		if not TyGearIsGearSlotProtected(gearSlot) then
			local equipped = TyGearEquippedItems[gearSlot]
			local score = 0
			if equipped and equipped.info and (not equipped.info.empty) then
				score = equipped.score or 0
			end
			if (not lowestSlot) or (score < lowestScore) then
				lowestSlot = gearSlot
				lowestScore = score
			end
		end
	end
	if not lowestSlot then return false end

	local equipped = TyGearEquippedItems[lowestSlot]
	local equippedInfo = equipped and equipped.info
	if TyGearIsReagentBag(info) then
		local currentDedicated = TyGearIsReagentBag(equippedInfo)
		local currentProfession = TyGearUsesReagentBagSlot(equippedInfo)
		if currentProfession and (not currentDedicated) then
			return true
		end
	elseif TyGearUsesReagentBagSlot(info) and (not TyGearIsReagentBag(info)) then
		if TyGearIsReagentBag(equippedInfo) then
			return false
		end
	end

	local score = TyGearDetermineItemScore(info, lowestSlot)
	if (not equippedInfo) or equippedInfo.empty then
		return true
	end
	-- Keep-list items stay unsold and do not replace worn gear; empty slots only.
	if keepOnly then
		return false
	end
	if info.isAmmoBag then
		local ranged = TyGearEquippedItems[INVSLOT_RANGED]
		local rangedInfo = ranged and ranged.info
		if rangedInfo and rangedInfo.isRangedWeapon
		and (not TyGearIsAmmoBagValidForRangedWeapon(info, rangedInfo)) then
			return false
		end
		local equippedValid = rangedInfo and TyGearIsAmmoBagValidForRangedWeapon(equippedInfo, rangedInfo)
		local candidateValid = (not rangedInfo) or (not rangedInfo.isRangedWeapon)
			or TyGearIsAmmoBagValidForRangedWeapon(info, rangedInfo)
		return candidateValid and ((score > lowestScore) or (not equippedValid))
	end
	return score > lowestScore
end

function TyGearIsItemLinkUpgrade(itemLink)
	if not itemLink then return false end
	local cached = upgradeLinks[itemLink]
	if cached ~= nil then return cached end
	local info = TyGearReadItemInfo(nil, nil, nil, nil, itemLink)
	local isUpgrade = TyGearWouldUpgradeEquipped(info) and true or false
	upgradeLinks[itemLink] = isUpgrade
	return isUpgrade
end

function TyGearAddUpgradeListener(callback)
	if type(callback) == "function" then
		table.insert(upgradeListeners, callback)
	end
end

local function TyGearNotifyUpgradeListeners()
	for _, callback in ipairs(upgradeListeners) do
		pcall(callback)
	end
end

function TyGearRefreshUpgradeMarks()
	wipe(upgradeLinks)
	if not TyGearDB then
		TyGearSyncVendorJunkBagEvent()
		TyGearNotifyUpgradeListeners()
		return
	end
	if (not TyGearEquippedItems) or (not next(TyGearEquippedItems)) then
		if TyGearUpdateEquippedItems then TyGearUpdateEquippedItems() end
	end
	for bag = 0, TyGearGetLastBagToScan() do
		for slot = 1, (GetContainerNumSlots(bag) or 0) do
			local itemID = GetContainerItemID and GetContainerItemID(bag, slot)
			if itemID then
				local invType = C_Item.GetItemInventoryTypeByID(itemID) or 0
				local _, _, classID, subclassID, equipLoc = TyGearItemIdentity(itemID)
				local isReagentBag = TyGearIsDedicatedReagentBag(classID, subclassID, equipLoc)
				local isProfessionBag = TyGearIsProfessionOrSoulBag(classID, subclassID)
				if (invType > 0) or isReagentBag or isProfessionBag then
					local info = TyGearReadItemInfo(nil, nil, bag, slot)
					if info and info.link then
						local isUpgrade = TyGearWouldUpgradeEquipped(info) and true or false
						upgradeLinks[info.link] = isUpgrade
					end
				end
			end
		end
	end
	TyGearSyncVendorJunkBagEvent()
	TyGearNotifyUpgradeListeners()
end

function TyGearQueueUpgradeRefresh()
	if not TyGearDB then return end
	local debounceUntil = GetTime() + 0.35
	for _, curAction in ipairs(TyGearActionQueue) do
		if curAction.t and (curAction.action == "upgrade") then
			if curAction.t < debounceUntil then
				curAction.t = debounceUntil
			end
			return
		end
	end
	TyGearQueueAction({ action = "upgrade", t = debounceUntil })
end

function TyGearRegisterBaganatorUpgradePlugin()
	if baganatorUpgradeRegistered then return end
	if not (Baganator and Baganator.API and Baganator.API.RegisterUpgradePlugin) then return end
	Baganator.API.RegisterUpgradePlugin("TyGear", "tygear", function(itemLink)
		return TyGearIsItemLinkUpgrade(itemLink)
	end)
	TyGearAddUpgradeListener(function()
		if Baganator.API.RequestItemButtonsRefresh then
			local reason
			if Baganator.Constants and Baganator.Constants.RefreshReason then
				reason = {
					Baganator.Constants.RefreshReason.ItemWidgets,
					Baganator.Constants.RefreshReason.Searches,
				}
			end
			Baganator.API.RequestItemButtonsRefresh(reason)
		end
	end)
	baganatorUpgradeRegistered = true
	upgradeBagEventWanted = true
	TyGearSyncVendorJunkBagEvent()
end

function TyGearIsQuestItem(container, slot)
	return TyGearItemContainsText(container, slot, ITEM_BIND_QUEST or "Quest Item")
end

--returns whether a left-side line of the bag item's tooltip is exactly the search text; the second return value is true when the tooltip couldn't be read
function TyGearItemContainsText(container, slot, search)
	TyGearTooltip:SetOwner(UIParent, "ANCHOR_NONE")
	TyGearTooltip:ClearLines()
	TyGearTooltip:SetBagItem(container, slot)
	local sawReadable, sawSecret
	for i=1, TyGearTooltip:NumLines() do
		local mytext = _G["TyGearTooltipTextLeft" .. i]
		if (mytext) then
			local text = mytext:GetText()
			--tooltip text can be a secret value under the Midnight addon restrictions; skip those lines
			if issecretvalue and issecretvalue(text) then
				sawSecret = true
			elseif text then
				sawReadable = true
				if (text == search) then
					return 1
				end
			end
		end
	end
	--only treat as unreadable when nothing could be compared
	if sawSecret and (not sawReadable) then
		return nil, true
	end
	return nil
end

function TyGearUpdateEquippedItem(invSlot)
	local info = TyGearReadItemInfo(invSlot)
	local score = TyGearDetermineItemScore(info, invSlot)
	local slotInfo = TyGearEquippedItems[invSlot]
	if not slotInfo then
		slotInfo = {}
		TyGearEquippedItems[invSlot] = slotInfo
	end
	slotInfo.info = info
	slotInfo.score = score
	slotInfo.equipped = 1
	slotInfo.bag = nil
	slotInfo.slot = nil
end

function TyGearSyncTwoHandTabardSlot()	--pretend the tabard slot is a separate slot for 2-handers
	if (TyGearEquippedItems[INVSLOT_MAINHAND] and
	TyGearEquippedItems[INVSLOT_MAINHAND].info and
	TyGearEquippedItems[INVSLOT_MAINHAND].info.is2hWeapon and
	(not ((weapons == "2hDW") and CanDualWield() and IsPlayerSpell(46917)))) then
		local mh = TyGearEquippedItems[INVSLOT_MAINHAND]
		TyGearEquippedItems[INVSLOT_TABARD] = {
			info = mh.info,
			score = mh.score,
			equipped = mh.equipped,
		}
		mh.info = EMPTY_SLOT_INFO
		mh.score = 0
		mh.equipped = nil
	else
		local tabard = TyGearEquippedItems[INVSLOT_TABARD]
		if not tabard then
			tabard = {}
			TyGearEquippedItems[INVSLOT_TABARD] = tabard
		end
		tabard.info = EMPTY_SLOT_INFO
		tabard.score = 0
		tabard.equipped = nil
	end
end

function TyGearSyncBestItemWithEquipped(invSlot)
	if (not TyGearBestItems) or (not TyGearEquippedItems) or (not invSlot) then return end
	local equipped = TyGearEquippedItems[invSlot]
	local best = TyGearBestItems[invSlot]
	if not equipped then return end
	if not best then
		TyGearBestItems[invSlot] = {
			info = equipped.info,
			score = equipped.score,
			equipped = equipped.equipped,
		}
		return
	end
	if equipped.info and (not equipped.info.empty) and best.info and (
		(equipped.info.guid and best.info.guid and equipped.info.guid == best.info.guid) or
		(equipped.info.link and best.info.link and equipped.info.link == best.info.link) or
		(equipped.info.id and best.info.id and equipped.info.id == best.info.id and best.equipped)
	) then
		best.info = equipped.info
		best.score = equipped.score
		best.equipped = 1
		best.bag = nil
		best.slot = nil
	elseif best.equipped then
		best.info = equipped.info
		best.score = equipped.score
		best.equipped = equipped.equipped
		best.bag = nil
		best.slot = nil
	elseif best.bag and equipped.info and (not equipped.info.empty)
	and ((best.score or 0) <= (equipped.score or 0)) then
		--manual equip of better gear: bag candidate is no longer an upgrade
		best.info = equipped.info
		best.score = equipped.score
		best.equipped = equipped.equipped
		best.bag = nil
		best.slot = nil
	end
end

function TyGearHandleEquipmentChanged(invSlot)
	if (not TyGearEquippedItems) or (not next(TyGearEquippedItems)) then
		TyGearQueueLocalUpdate()
		return
	end
	if not TyGearCurrentWeighting then
		TyGearSetStatWeights()
	end
	if not invSlot then
		TyGearQueueLocalUpdate()
		return
	end
	TyGearUpdateEquippedItem(invSlot)
	if invSlot == INVSLOT_MAINHAND or invSlot == INVSLOT_OFFHAND then
		-- MH/OH changes can move the pretended 2H tabard slot
		if invSlot == INVSLOT_OFFHAND then
			TyGearUpdateEquippedItem(INVSLOT_MAINHAND)
		end
		TyGearSyncTwoHandTabardSlot()
		TyGearSyncBestItemWithEquipped(INVSLOT_MAINHAND)
		TyGearSyncBestItemWithEquipped(INVSLOT_OFFHAND)
		TyGearSyncBestItemWithEquipped(INVSLOT_TABARD)
	else
		TyGearSyncBestItemWithEquipped(invSlot)
	end
end

function TyGearUpdateEquippedItems()
	TyGearRefreshReagentBagSlot()
	TyGearSetStatWeights()
	if not TyGearEquippedItems then
		TyGearEquippedItems = {}
	else
		TyGearWipeTable(TyGearEquippedItems)
	end
	for invSlot = INVSLOT_FIRST_EQUIPPED, TyGearLastManagedGearSlot do
		if TyGearIsManagedGearSlot(invSlot) then
			TyGearUpdateEquippedItem(invSlot)
		end
	end
	TyGearSyncTwoHandTabardSlot()
end

function TyGearDeepCopy(object)
	local object_type = type(object)
	local newObject
	if object_type == 'table' then
		newObject = {}
		for orig_key, orig_value in next, object, nil do
			newObject[TyGearDeepCopy(orig_key)] = TyGearDeepCopy(orig_value)
		end
		setmetatable(newObject, TyGearDeepCopy(getmetatable(object)))
	else -- number, string, boolean, etc
		newObject = object
	end
	return newObject
end

function TyGearResetBestItemsFromEquipped()
	if (not TyGearEquippedItems) or (not next(TyGearEquippedItems)) then
		TyGearUpdateEquippedItems()
	end
	if not TyGearBestItems then
		TyGearBestItems = {}
	else
		TyGearWipeTable(TyGearBestItems)
	end
	for invSlot, data in pairs(TyGearEquippedItems) do
		TyGearBestItems[invSlot] = {
			info = data.info,
			score = data.score,
			equipped = data.equipped,
		}
	end
	if not TyGearBestItemsAlreadyAdded then
		TyGearBestItemsAlreadyAdded = {}
	else
		TyGearWipeTable(TyGearBestItemsAlreadyAdded)
	end
end

-- GetItemInfoInstant's first return is the item id, not the name.
-- Returns name, itemSubType, classID, subclassID, equipLoc.
function TyGearItemIdentity(itemID)
	if not itemID or not GetItemInfoInstant then return end
	local ok, _, _, itemSubType, equipLoc, _, classID, subclassID = pcall(GetItemInfoInstant, itemID)
	if not ok then return end
	if issecretvalue then
		if issecretvalue(itemSubType) then itemSubType = nil end
		if issecretvalue(equipLoc) then equipLoc = nil end
		if issecretvalue(classID) then classID = nil end
		if issecretvalue(subclassID) then subclassID = nil end
	end
	local name
	if C_Item and C_Item.GetItemNameByID then
		local nameOk, itemName = pcall(C_Item.GetItemNameByID, itemID)
		if nameOk and type(itemName) == "string" and itemName ~= "" and not (issecretvalue and issecretvalue(itemName)) then
			name = itemName
		end
	end
	return name, itemSubType, classID, subclassID, equipLoc
end

function TyGearScanBagsForBestItems()
	local info
	for bag = 0, TyGearGetLastBagToScan() do
		local slotMax = GetContainerNumSlots(bag) or 0
		for slot = 0, slotMax do
			local itemID = GetContainerItemID and GetContainerItemID(bag, slot)
			if itemID then
				local invType = C_Item.GetItemInventoryTypeByID(itemID) or 0
				local _, _, classID, subclassID, equipLoc = TyGearItemIdentity(itemID)
				local isReagentBag = TyGearIsDedicatedReagentBag(classID, subclassID, equipLoc)
				local isProfessionBag = TyGearIsProfessionOrSoulBag(classID, subclassID)
				if (invType > 0) or isReagentBag or isProfessionBag then
					info = TyGearReadItemInfo(nil, nil, bag, slot)
					TyGearConsiderItem(info, bag, slot, nil)
				end
			end
		end
	end
end

function TyGearUpdateBestItems(skipBagScan)
	TyGearUpdateEquippedItems()
	TyGearResetBestItemsFromEquipped()
	if not skipBagScan then
		TyGearScanBagsForBestItems()
	end
	if TyGearQueueUpgradeRefresh then TyGearQueueUpgradeRefresh() end
end

function TyGearConsiderAllItems(lootRollItemID, arbitraryItemInfo, noActions)
	local anythingBetter = nil

	-- Loot-roll decisions only need equipped gear vs the roll item; skip bag tooltip scans.
	-- Always re-read equipped scores (and drop the score cache) so a prior partial/secret
	-- tooltip pass cannot leave a slot at ~0 and cause NEED on a clear downgrade
	-- (e.g. legs 2.6 vs equipped legs 22).
	if lootRollItemID and arbitraryItemInfo and noActions then
		TyGearWipeTable(TyGearScoreCache)
		TyGearUpdateEquippedItems()
		TyGearResetBestItemsFromEquipped()
	else
		TyGearUpdateBestItems()
	end

	--consider item being rolled on (if any)
	if lootRollItemID and arbitraryItemInfo then
		TyGearConsiderItem(arbitraryItemInfo, nil, nil, 1)
	end

	--create all future equip actions required (only if not rolling currently)
	if (not lootRollItemID and not noActions) then
		TyGearRedirectReagentBagsToReagentSlot()
		-- One scan should unequip the less preferred equal bag (non-soulbound before soulbound).
		TyGearRetargetBagUpgradesAwayFromPreferredBags()
		local bagEquipDelay = 0
		for invSlot = INVSLOT_FIRST_EQUIPPED, TyGearLastManagedGearSlot do
			if TyGearIsManagedGearSlot(invSlot) then
				if invSlot == INVSLOT_MAINHAND or invSlot == INVSLOT_OFFHAND or invSlot == INVSLOT_TABARD then
					--skip weapons for now
				else
					local equippedSlot = TyGearEquippedItems[invSlot]
					local bestSlot = TyGearBestItems[invSlot]
					if equippedSlot and bestSlot
					and (not TyGearIsGearSlotProtected(invSlot)) and (not bestSlot.equipped) then
					local isSlotLocked = TyGearIsGearSlotLocked(invSlot)
					local equippedInfo = equippedSlot.info
					local equippedScore = equippedSlot.score
						anythingBetter = 1
						TyGearPrint("TyGear: "..TyGearFormatItemWithScore(TyGearBestItems[invSlot].info, TyGearBestItems[invSlot].score).." was determined to be better than "..TyGearFormatItemWithScore(equippedInfo, equippedScore)..".  "..((TyGearDB.Enabled == true) and (isSlotLocked and "Would equip, but slot "..tostring(invSlot or "nil").." is locked." or "Equipping.") or "Would equip if automatic gear equipping was enabled."), 1)
						TyGearPrintItem(TyGearBestItems[invSlot].info)
						TyGearPrintItem(equippedInfo)
						if not isSlotLocked then
							local newAction = {}
							newAction.action = "equip"
							-- Space bag equips so a later bag can be re-found after the earlier one shifts bag contents.
							local isBagEquip = TyGearGetContainerForEquippedBagSlot(invSlot) and true or false
							newAction.t = GetTime() + (isBagEquip and bagEquipDelay or 0)
							if isBagEquip then
								bagEquipDelay = bagEquipDelay + 0.4
							end
							newAction.container = TyGearBestItems[invSlot].bag
							newAction.slot = TyGearBestItems[invSlot].slot
							newAction.replaceSlot = invSlot
							newAction.reagentEquip = (invSlot == TyGearReagentBagSlot) and TyGearBestItems[invSlot].info and (TyGearIsReagentBag(TyGearBestItems[invSlot].info) or TyGearUsesReagentBagSlot(TyGearBestItems[invSlot].info)) and true or nil
							newAction.fromEquippedSlot = TyGearBestItems[invSlot].fromEquippedSlot
							newAction.info = TyGearBestItems[invSlot].info
							newAction.score = TyGearBestItems[invSlot].score
							TyGearQueueAction(newAction)
						end
					end
				end
			end
		end
		--handle weapons
		local isMainHandSlotLocked = TyGearIsGearSlotLocked(INVSLOT_MAINHAND)
		local isOffHandSlotLocked = TyGearIsGearSlotLocked(INVSLOT_OFFHAND)
		if (TyGearBestItems[INVSLOT_MAINHAND].score + TyGearBestItems[INVSLOT_OFFHAND].score > TyGearBestItems[INVSLOT_TABARD].score)
		or (TyGearEquippedItems[INVSLOT_TABARD].info.unusable)
		or (((not TyGearBestItems[INVSLOT_MAINHAND].info.empty)
		or (not TyGearBestItems[INVSLOT_OFFHAND].info.empty))
		and TyGearBestItems[INVSLOT_TABARD].info.empty) then
			local extraDelay = 0
			local mainSwap, offSwap
			--main hand
			if (not TyGearBestItems[INVSLOT_MAINHAND].equipped) and (not TyGearBestItems[INVSLOT_MAINHAND].info.empty) and (not TyGearIsGearSlotProtected(INVSLOT_MAINHAND)) then
				mainSwap = 1
				if not isMainHandSlotLocked then
					local newAction = {}
					newAction.action = "equip"
					newAction.t = GetTime()
					newAction.container = TyGearBestItems[INVSLOT_MAINHAND].bag
					newAction.slot = TyGearBestItems[INVSLOT_MAINHAND].slot
					newAction.replaceSlot = INVSLOT_MAINHAND
					newAction.info = TyGearBestItems[INVSLOT_MAINHAND].info
					newAction.score = TyGearBestItems[INVSLOT_MAINHAND].score
					TyGearQueueAction(newAction)
					extraDelay = 0.5
				end
			end
			--off-hand
			if (not TyGearBestItems[INVSLOT_OFFHAND].equipped) and (not TyGearBestItems[INVSLOT_OFFHAND].info.empty) and (not TyGearIsGearSlotProtected(INVSLOT_OFFHAND)) then
				offSwap = 1
				if not isOffHandSlotLocked then
					local newAction = {}
					newAction.action = "equip"
					newAction.t = GetTime() + extraDelay --do it after a longer delay
					newAction.container = TyGearBestItems[INVSLOT_OFFHAND].bag
					newAction.slot = TyGearBestItems[INVSLOT_OFFHAND].slot
					newAction.replaceSlot = INVSLOT_OFFHAND
					newAction.info = TyGearBestItems[INVSLOT_OFFHAND].info
					newAction.score = TyGearBestItems[INVSLOT_OFFHAND].score
					TyGearQueueAction(newAction)
				end
			end
			if (mainSwap or offSwap) then
				anythingBetter = 1
				if (mainSwap and offSwap) then
					if (TyGearIsTwoHandEquipped()) then
						local equippedMain = TyGearEquippedItems[INVSLOT_TABARD].info
						local mainScore = TyGearEquippedItems[INVSLOT_TABARD].score
						TyGearPrint("TyGear: "..TyGearFormatItemWithScore(TyGearBestItems[INVSLOT_MAINHAND].info, TyGearBestItems[INVSLOT_MAINHAND].score).." combined with "..TyGearFormatItemWithScore(TyGearBestItems[INVSLOT_OFFHAND].info, TyGearBestItems[INVSLOT_OFFHAND].score).." was determined to be better than "..TyGearFormatItemWithScore(equippedMain, mainScore)..".  "..((TyGearDB.Enabled == true) and ((isMainHandSlotLocked or isOffHandSlotLocked) and "Would equip, but slot "..tostring((isMainHandSlotLocked and INVSLOT_MAINHAND or INVSLOT_OFFHAND) or "nil").." is locked." or "Equipping.") or "Would equip if automatic gear equipping was enabled."), 1)
						TyGearPrintItem(TyGearBestItems[INVSLOT_MAINHAND].info)
						TyGearPrintItem(TyGearBestItems[INVSLOT_OFFHAND].info)
						TyGearPrintItem(equippedMain)
					else
						local equippedMain = TyGearEquippedItems[INVSLOT_MAINHAND].info
						local mainScore = TyGearEquippedItems[INVSLOT_MAINHAND].score
						local equippedOff = TyGearEquippedItems[INVSLOT_OFFHAND].info
						local offScore = TyGearEquippedItems[INVSLOT_OFFHAND].score
						TyGearPrint("TyGear: "..TyGearFormatPairingWithScores(TyGearBestItems[INVSLOT_MAINHAND].info, TyGearBestItems[INVSLOT_MAINHAND].score, TyGearBestItems[INVSLOT_OFFHAND].info, TyGearBestItems[INVSLOT_OFFHAND].score).." was determined to be better than "..TyGearFormatPairingWithScores(equippedMain, mainScore, equippedOff, offScore)..".  "..((TyGearDB.Enabled == true) and ((isMainHandSlotLocked or isOffHandSlotLocked) and "Would equip, but slot "..tostring((isMainHandSlotLocked and INVSLOT_MAINHAND or INVSLOT_OFFHAND) or "nil").." is locked." or "Equipping.") or "Would equip if automatic gear equipping was enabled."), 1)
						TyGearPrintItem(TyGearBestItems[INVSLOT_MAINHAND].info)
						TyGearPrintItem(TyGearBestItems[INVSLOT_OFFHAND].info)
						TyGearPrintItem(equippedMain)
						TyGearPrintItem(equippedOff)
					end
				else
					local invSlot = INVSLOT_MAINHAND
					if (offSwap) then invSlot = INVSLOT_OFFHAND end
					local equippedInfo = TyGearEquippedItems[invSlot].info
					local equippedScore = TyGearEquippedItems[invSlot].score
					TyGearPrint("TyGear: "..TyGearFormatItemWithScore(TyGearBestItems[invSlot].info, TyGearBestItems[invSlot].score).." was determined to be better than "..TyGearFormatItemWithScore(equippedInfo, equippedScore)..".  "..((TyGearDB.Enabled == true) and (((invSlot == INVSLOT_MAINHAND and isMainHandSlotLocked) or (invSlot == INVSLOT_OFFHAND and isOffHandSlotLocked)) and "Would equip, but slot "..tostring((isMainHandSlotLocked and INVSLOT_MAINHAND or INVSLOT_OFFHAND) or "nil").." is locked." or "Equipping.") or "Would equip if automatic gear equipping was enabled."), 1)
					TyGearPrintItem(TyGearBestItems[invSlot].info)
					TyGearPrintItem(equippedInfo)
				end
			end
		elseif (TyGearBestItems[INVSLOT_TABARD].score > (TyGearBestItems[INVSLOT_MAINHAND].score + TyGearBestItems[INVSLOT_OFFHAND].score))
		or ((not TyGearBestItems[INVSLOT_TABARD].info.empty)
		and ((TyGearBestItems[INVSLOT_MAINHAND].info.empty)
		and (TyGearBestItems[INVSLOT_OFFHAND].info.empty))) then
			if (not TyGearBestItems[INVSLOT_TABARD].equipped) and (not TyGearBestItems[INVSLOT_TABARD].info.empty) and (not TyGearIsGearSlotProtected(INVSLOT_TABARD)) then
				anythingBetter = 1
				local showBothSlots = TyGearIsTwoHandEquipped()
				local mainSlot = showBothSlots and INVSLOT_TABARD or INVSLOT_MAINHAND
				local equippedMain = TyGearEquippedItems[mainSlot].info
				local mainScore = TyGearEquippedItems[mainSlot].score
				local equippedOff = TyGearEquippedItems[INVSLOT_OFFHAND].info
				local offScore = TyGearEquippedItems[INVSLOT_OFFHAND].score
				TyGearPrint("TyGear: "..TyGearFormatItemWithScore(TyGearBestItems[INVSLOT_TABARD].info, TyGearBestItems[INVSLOT_TABARD].score).." was determined to be better than "..(showBothSlots and TyGearFormatPairingWithScores(equippedMain, mainScore, equippedOff, offScore) or TyGearFormatItemWithScore(equippedMain, mainScore))..".  "..((TyGearDB.Enabled == true) and ((isMainHandSlotLocked or isOffHandSlotLocked) and "Would equip, but slot "..tostring((isMainHandSlotLocked and INVSLOT_MAINHAND or INVSLOT_OFFHAND) or "nil").." is locked." or "Equipping.") or "Would equip if automatic gear equipping was enabled."), 1)
				TyGearPrintItem(TyGearBestItems[INVSLOT_TABARD].info)
				TyGearPrintItem(equippedMain)
				if showBothSlots then TyGearPrintItem(equippedOff) end
				if (not isMainHandSlotLocked) and (not isOffHandSlotLocked) then
					local newAction = {}
					newAction.action = "equip"
					newAction.t = GetTime() + 0.5 --do it after a short delay
					newAction.container = TyGearBestItems[INVSLOT_TABARD].bag
					newAction.slot = TyGearBestItems[INVSLOT_TABARD].slot
					newAction.replaceSlot = INVSLOT_MAINHAND
					newAction.info = TyGearBestItems[INVSLOT_TABARD].info
					newAction.score = TyGearBestItems[INVSLOT_TABARD].score
					TyGearQueueAction(newAction)
				end
			end
		end
	elseif (lootRollItemID) then
		--decide whether to roll on the item or not
		for invSlot = INVSLOT_FIRST_EQUIPPED, TyGearLastManagedGearSlot do
			if TyGearIsManagedGearSlot(invSlot) then
				-- Must use `and` for the MH/OH exclusion: `or` is always true because a
				-- slot cannot be both MAINHAND and OFFHAND, which skipped TyGearIs1hWorthwhile
				-- and let near-worthless 1H pieces NEED over an empty MH/OH left by a parked 2H.
				if (TyGearBestItems[invSlot].rollOn and
				((invSlot ~= INVSLOT_MAINHAND and invSlot ~= INVSLOT_OFFHAND) or TyGearIs1hWorthwhile(invSlot)) and
				(invSlot ~= INVSLOT_TABARD or TyGearIsBest2hBetterThanBestMainAndOff())) then
					return 1
				end
			end
		end
		return nil
	end
	return anythingBetter
end

function TyGearIsBest2hBetterThanBestMainAndOff()
	return TyGearBestItems[INVSLOT_TABARD].score > TyGearBestItems[INVSLOT_MAINHAND].score + TyGearBestItems[INVSLOT_OFFHAND].score
end

function TyGearIs1hWorthwhile(i)
	-- 3x the highest weight among the 5 main stats
	local minScore = 3 * math.max(
		TyGearCurrentWeighting.Strength or 0,
		TyGearCurrentWeighting.Agility or 0,
		TyGearCurrentWeighting.Stamina or 0,
		TyGearCurrentWeighting.Intellect or 0,
		TyGearCurrentWeighting.Spirit or 0)
	return TyGearBestItems[i].score > minScore and TyGearBestItems[i].score > TyGearBestItems[INVSLOT_TABARD].score * (i == INVSLOT_MAINHAND and 0.15 or 0.05)
end

-- Print bag slot counts as "6 slots" / "4 slots" instead of 6.00 / 4.00; keep decimals for gear scores.
function TyGearFormatScore(score, info)
	score = tonumber(score) or 0
	-- Empty gear slots are not bags; only real containers print as "N slots".
	if info and (not info.empty) and (info.classID == Enum.ItemClass.Container or info.isReagentBag or TyGearIsReagentBag(info) or TyGearUsesReagentBagSlot(info)) then
		local slots = math.floor(score + 0.5)
		return tostring(slots).." slot"..(slots == 1 and "" or "s")
	end
	-- Only print whole numbers for meaningful magnitudes. Tiny positive scores (jewelry
	-- with floor-weighted Spirit/Stamina) must not round to "0".
	local nearest = math.floor(score + 0.5)
	if nearest ~= 0 and math.abs(score - nearest) < 0.0005 then
		return tostring(nearest)
	end
	if math.abs(score) < 0.0005 then
		return "0"
	end
	return string.format("%.2f", score)
end

-- "Item (score)" for equip messages; empty slots are just "nothing" with no parenthetical.
function TyGearFormatItemWithScore(info, score)
	if (not info) or info.empty then
		return "nothing"
	end
	return (info.link or info.name or "nothing").." ("..TyGearFormatScore(score, info)..")"
end

-- MH+OH comparison text. Both empty → "nothing"; one empty → the other item alone.
function TyGearFormatPairingWithScores(infoA, scoreA, infoB, scoreB)
	local aEmpty = (not infoA) or infoA.empty
	local bEmpty = (not infoB) or infoB.empty
	if aEmpty and bEmpty then
		return "nothing"
	end
	if aEmpty then
		return TyGearFormatItemWithScore(infoB, scoreB)
	end
	if bEmpty then
		return TyGearFormatItemWithScore(infoA, scoreA)
	end
	return TyGearFormatItemWithScore(infoA, scoreA).." combined with "..TyGearFormatItemWithScore(infoB, scoreB)
end

--when two bags have the same score (same slot count), prefer dedicated reagent bags, then Forever Warlock soul bags, then soulbound
function TyGearBagShouldReplaceEqualScore(candidate, current)
	if not candidate or candidate.classID ~= Enum.ItemClass.Container then return false end
	if not current or current.empty then return true end
	local candidateDedicated = TyGearIsReagentBag(candidate)
	local currentDedicated = TyGearIsReagentBag(current)
	if candidateDedicated and not currentDedicated then return true end
	if currentDedicated and not candidateDedicated then return false end
	if IS_WOW_FOREVER and UnitClassBase("player") == "WARLOCK" then
		local candidateSoul = TyGearIsSoulBag(candidate)
		local currentSoul = TyGearIsSoulBag(current)
		if candidateSoul and not currentSoul then return true end
		if currentSoul and not candidateSoul then return false end
	end
	if candidate.bop and not current.bop then return true end
	return false
end

-- True when bagInfo should be the one unequipped if it ties keptInfo on slot count.
-- keptInfo is the bag we would rather leave equipped (soulbound, soul bag, dedicated reagent).
function TyGearPreferToDisplaceBag(bagInfo, keptInfo)
	if not bagInfo or not keptInfo or bagInfo.empty or keptInfo.empty then return false end
	if bagInfo.classID ~= Enum.ItemClass.Container or keptInfo.classID ~= Enum.ItemClass.Container then
		return false
	end
	return TyGearBagShouldReplaceEqualScore(keptInfo, bagInfo)
end

local function TyGearInfoFitsGearSlot(info, gearSlot)
	if not info or not gearSlot or not info.validGearSlots then return false end
	for _, slot in pairs(info.validGearSlots) do
		if slot == gearSlot then return true end
	end
end

-- A larger bag aimed at a soulbound bag leaves that soulbound in inventory, and the
-- matching non-soulbound bag stays equipped until the next scan. Point the upgrade
-- at the bag we would rather unequip before any equip action is queued.
function TyGearRetargetBagUpgradesAwayFromPreferredBags()
	if not TyGearBestItems or not TyGearEquippedItems or not TyGearEquippableBagSlots then return end
	local slots = {}
	local seen = {}
	local function addSlot(slot)
		if slot and not seen[slot] then
			seen[slot] = true
			table.insert(slots, slot)
		end
	end
	for _, slot in ipairs(TyGearEquippableBagSlots) do
		addSlot(slot)
	end
	addSlot(TyGearReagentBagSlot)
	for _, slotA in ipairs(slots) do
		local bestA = TyGearBestItems[slotA]
		local equippedA = TyGearEquippedItems[slotA]
		local equippedInfoA = equippedA and equippedA.info
		if bestA and (not bestA.equipped) and equippedInfoA and (not equippedInfoA.empty)
		and (not TyGearIsGearSlotProtected(slotA)) then
			for _, slotB in ipairs(slots) do
				if slotA ~= slotB and (not TyGearIsGearSlotProtected(slotB)) and (not TyGearIsGearSlotLocked(slotB)) then
					local bestB = TyGearBestItems[slotB]
					local equippedB = TyGearEquippedItems[slotB]
					local equippedInfoB = equippedB and equippedB.info
					if bestB and bestB.equipped and equippedInfoB and (not equippedInfoB.empty)
					and (equippedA.score or 0) == (equippedB.score or 0)
					and TyGearInfoFitsGearSlot(bestA.info, slotB)
					and TyGearPreferToDisplaceBag(equippedInfoB, equippedInfoA) then
						local upgradeScore = bestA.score or 0
						local destScore = equippedB.score or 0
						local upgradeWins = (upgradeScore > destScore)
							or ((upgradeScore == destScore) and TyGearBagShouldReplaceEqualScore(bestA.info, equippedInfoB))
						if upgradeWins then
							TyGearBestItems[slotB] = {
								info = bestA.info,
								score = bestA.score,
								equipped = nil,
								bag = bestA.bag,
								slot = bestA.slot,
								fromEquippedSlot = bestA.fromEquippedSlot,
								rollOn = bestA.rollOn,
							}
							TyGearBestItems[slotA] = {
								info = equippedInfoA,
								score = equippedA.score,
								equipped = 1,
							}
							break
						end
					end
				end
			end
		end
	end
end

-- Dedicated reagent bags belong in the reagent slot. Profession/soul bags may fill it when empty.
-- Move a candidate there when it was considered for a normal bag slot (or is already worn in one).
function TyGearRedirectReagentBagsToReagentSlot()
	if not TyGearReagentBagSlot or not TyGearBestItems then return end
	if not TyGearBestItems[TyGearReagentBagSlot] then
		local equipped = TyGearEquippedItems and TyGearEquippedItems[TyGearReagentBagSlot]
		TyGearBestItems[TyGearReagentBagSlot] = {
			info = (equipped and equipped.info) or EMPTY_SLOT_INFO,
			score = (equipped and equipped.score) or 0,
			equipped = 1,
		}
	end
	if TyGearIsGearSlotProtected(TyGearReagentBagSlot) then return end
	local function reagentEmpty(current)
		return not current or not current.info or current.info.empty or current.info.unusable
	end
	local function beats(candidate, current)
		if not candidate or not candidate.info or candidate.info.empty or candidate.info.unusable then
			return false
		end
		if TyGearIsItemIgnored(candidate.info) then return false end
		local isDedicated = TyGearIsReagentBag(candidate.info)
		local isProfession = TyGearUsesReagentBagSlot(candidate.info)
		if not isDedicated and not isProfession then return false end
		-- Profession/soul bags only fill an empty reagent slot; dedicated bags can replace a weaker one.
		if isProfession and not isDedicated and not reagentEmpty(current) then
			return false
		end
		if reagentEmpty(current) then return true end
		-- Keep-list bags fill an empty reagent slot only; they do not replace worn bags.
		if TyGearIsVendorKeepOnly(candidate.info) then return false end
		if not isDedicated then return false end
		local candidateScore = candidate.score or 0
		local currentScore = current.score or 0
		if candidateScore > currentScore then return true end
		if candidateScore < currentScore then return false end
		return TyGearBagShouldReplaceEqualScore(candidate.info, current.info)
	end
	local function restoreEquipped(bagSlot)
		local equipped = TyGearEquippedItems and TyGearEquippedItems[bagSlot]
		TyGearBestItems[bagSlot] = {
			info = (equipped and equipped.info) or EMPTY_SLOT_INFO,
			score = (equipped and equipped.score) or 0,
			equipped = 1,
		}
	end
	local function copyBest(best)
		return {
			info = best.info,
			score = best.score,
			equipped = nil,
			bag = best.bag,
			slot = best.slot,
			fromEquippedSlot = best.fromEquippedSlot,
			rollOn = best.rollOn,
		}
	end
	for _, bagSlot in ipairs(TyGearEquippableBagSlots) do
		local best = TyGearBestItems[bagSlot]
		local reagentBest = TyGearBestItems[TyGearReagentBagSlot]
		-- A reagent-compatible bag chosen for a normal slot: move it to the reagent slot when it belongs there.
		-- INVTYPE_REAGENTBAG cannot stay in a normal bag slot, so restore whatever was equipped there.
		if best and not best.equipped and beats(best, reagentBest) then
			TyGearBestItems[TyGearReagentBagSlot] = copyBest(best)
			restoreEquipped(bagSlot)
		end
		reagentBest = TyGearBestItems[TyGearReagentBagSlot]
		local equipped = TyGearEquippedItems and TyGearEquippedItems[bagSlot]
		-- Already worn in a normal slot: pick it up into the reagent slot when it belongs there.
		if equipped and beats(equipped, reagentBest) then
			TyGearBestItems[TyGearReagentBagSlot] = {
				info = equipped.info,
				score = equipped.score,
				equipped = nil,
				bag = nil,
				slot = nil,
				fromEquippedSlot = bagSlot,
			}
			restoreEquipped(bagSlot)
		end
	end
end

--companion function to TyGearConsiderAllItems
-- Keep-list items are skipped for replacing worn gear, but still fill empty slots.
function TyGearConsiderItem(info, bag, slot, rollOn)
	if info.empty
	or TyGearIsItemIgnored(info)
	or (info.guid and TyGearBestItemsAlreadyAdded[info.guid])
	or (info.isAmmoBag
	and	TyGearBestItems[INVSLOT_RANGED].info.isRangedWeapon)
	and (not TyGearIsAmmoBagValidForRangedWeapon(info, TyGearBestItems[INVSLOT_RANGED].info)) then
		return
	end
	local keepOnly = TyGearIsVendorKeepOnly(info)
	-- Dedicated reagent bags only use the reagent slot.
	if TyGearIsReagentBag(info) then
		TyGearAssignReagentBagSlots(info)
		if not info.validGearSlots then
			return
		end
	end
	if (info.usable or (rollOn and info.Within5levels)) then
		if info.isGear and info.validGearSlots then
			local lowestScoringValidGearSlot
			local lowestScoringValidGearSlotScore
			for _, gearSlot in ipairs(info.validGearSlots) do
				if not TyGearIsGearSlotProtected(gearSlot) then
					lowestScoringValidGearSlot = gearSlot
					lowestScoringValidGearSlotScore = TyGearBestItems[gearSlot] and TyGearBestItems[gearSlot].score or 0
					break
				end
			end
			--every slot this item can use is ignored
			if not lowestScoringValidGearSlot then return end
			for _, gearSlot in pairs(info.validGearSlots) do
				if not TyGearIsGearSlotProtected(gearSlot) then
				if not TyGearBestItems[gearSlot] then
					TyGearBestItems[gearSlot] = { info = EMPTY_SLOT_INFO, score = 0, equipped = 1 }
				end
				local skipThisSlot = false
				for _, otherGearSlot in pairs(info.validGearSlots) do
					if gearSlot ~= otherGearSlot then
						if not TyGearBestItems[otherGearSlot] then
							TyGearBestItems[otherGearSlot] = { info = EMPTY_SLOT_INFO, score = 0, equipped = 1 }
						end
						if not TyGearIsGearPairEquippableTogether(info, TyGearBestItems[otherGearSlot].info) then
							skipThisSlot = true
						end
					end
				end
				local slotBest = TyGearBestItems[gearSlot]
				local slotScore = slotBest.score or 0
				-- Same slot count: unequip the non-soulbound bag and leave the soulbound one worn.
				local tiedBagToDisplace = false
				if info.classID == Enum.ItemClass.Container
				and (not slotBest.info.empty)
				and slotScore == lowestScoringValidGearSlotScore
				and gearSlot ~= lowestScoringValidGearSlot then
					local kept = TyGearBestItems[lowestScoringValidGearSlot]
					local keptInfo = kept and kept.info
					if keptInfo then
						tiedBagToDisplace = TyGearPreferToDisplaceBag(slotBest.info, keptInfo)
					end
				end
				if not skipThisSlot and
				((not slotBest.score) or
				slotBest.info.empty or
				(slotScore < lowestScoringValidGearSlotScore) or
				tiedBagToDisplace) then
					lowestScoringValidGearSlot = gearSlot
					lowestScoringValidGearSlotScore = slotScore
				end
				end
			end

			if not TyGearBestItems[lowestScoringValidGearSlot] then
				TyGearBestItems[lowestScoringValidGearSlot] = { info = EMPTY_SLOT_INFO, score = 0, equipped = 1 }
			end
			-- Score after choosing the slot so OH weapons use oh_dps swing EP.
			local score = TyGearDetermineItemScore(info, lowestScoringValidGearSlot)
			local currentBestInfo = TyGearBestItems[lowestScoringValidGearSlot].info
			-- Dedicated reagent bags always beat profession/soul bags for the reagent slot.
			local candidateDedicated = TyGearIsReagentBag(info)
			local currentDedicated = TyGearIsReagentBag(currentBestInfo)
			local candidateProfession = TyGearUsesReagentBagSlot(info)
			local currentProfession = TyGearUsesReagentBagSlot(currentBestInfo)
			local professionCannotReplaceDedicated = candidateProfession and not candidateDedicated and currentDedicated
			local dedicatedBeatsProfession = candidateDedicated and currentProfession and not currentDedicated
			-- Do not treat currentBestInfo.unusable as an automatic win. Equipped gear can be
			-- flagged unusable from a restricted/partial tooltip while still holding a real
			-- score; allowing any usable candidate to replace it caused NEED on downgrades
			-- (trash legs at 2.6 over worn legs at 22). Empty slots still accept any candidate,
			-- including keep-list items (something equipped > nothing).
			if not professionCannotReplaceDedicated and (
				currentBestInfo.empty
				or ((not keepOnly) and (
					dedicatedBeatsProfession
					or ((score > lowestScoringValidGearSlotScore) and (not info.isAmmoBag))
					or ((score == lowestScoringValidGearSlotScore)
						and (not info.isAmmoBag)
						and TyGearBagShouldReplaceEqualScore(info, currentBestInfo))
					or (info.isAmmoBag
						and TyGearIsAmmoBagValidForBestKnownRangedWeapon(info)
						and ((score > lowestScoringValidGearSlotScore)
						or (not TyGearIsAmmoBagValidForBestKnownRangedWeapon(currentBestInfo)))
					)
				))
			) then
				-- TyGearPrint(info.link.." bag and slot: "..tostring(bag or "nil").." "..tostring(slot or "nil"),0)
				if info.guid then TyGearBestItemsAlreadyAdded[info.guid] = 1 end
				TyGearBestItems[lowestScoringValidGearSlot].info = info
				TyGearBestItems[lowestScoringValidGearSlot].score = score
				TyGearBestItems[lowestScoringValidGearSlot].equipped = nil
				TyGearBestItems[lowestScoringValidGearSlot].bag = bag
				TyGearBestItems[lowestScoringValidGearSlot].slot = slot
				TyGearBestItems[lowestScoringValidGearSlot].rollOn = rollOn
				return true
			end
		end
	end
end

function TyGearIsAmmoBagValidForBestKnownRangedWeapon(info)
	return TyGearIsAmmoBagValidForRangedWeapon (
		info,
		(TyGearBestItems and TyGearBestItems[INVSLOT_RANGED])
		and TyGearBestItems[INVSLOT_RANGED].info
		or TyGearReadItemInfo(INVSLOT_RANGED)
	)
end

function TyGearGetValidGearSlots(info)
	local dualWield = CanDualWield() and 1 or 0
	local titanGrip = IsPlayerSpell(46917) and 1 or 0
	local cacheKey = (weapons or "any").."|"..dualWield.."|"..titanGrip.."|"..tostring(info.invType).."|"..tostring(info.subclassID or 0).."|"..(TyGearIsReagentBag(info) and "R" or "0").."|"..(TyGearUsesReagentBagSlot(info) and "1" or "0").."|"..tostring(TyGearReagentBagSlot or 0)
	local cached = TyGearValidGearSlotsCache[cacheKey]
	if cached ~= nil then
		return cached ~= false and cached or nil
	end
	local gearSlotTable = {
		[Enum.InventoryType.IndexNonEquipType]       = nil,
		[Enum.InventoryType.IndexAmmoType]           = nil, -- ignore ammo because it's hard to match with weapon type
		[Enum.InventoryType.IndexHeadType]           = { INVSLOT_HEAD },
		[Enum.InventoryType.IndexNeckType]           = { INVSLOT_NECK },
		[Enum.InventoryType.IndexShoulderType]       = { INVSLOT_SHOULDER },
		[Enum.InventoryType.IndexBodyType]           = nil, -- shirts are cosmetic; do not evaluate or equip
		[Enum.InventoryType.IndexChestType]          = { INVSLOT_CHEST },
		[Enum.InventoryType.IndexRobeType]           = { INVSLOT_CHEST },
		[Enum.InventoryType.IndexWaistType]          = { INVSLOT_WAIST },
		[Enum.InventoryType.IndexLegsType]           = { INVSLOT_LEGS },
		[Enum.InventoryType.IndexFeetType]           = { INVSLOT_FEET },
		[Enum.InventoryType.IndexWristType]          = { INVSLOT_WRIST },
		[Enum.InventoryType.IndexHandType]           = { INVSLOT_HAND },
		[Enum.InventoryType.IndexFingerType]         = { INVSLOT_FINGER1, INVSLOT_FINGER2 },
		[Enum.InventoryType.IndexTrinketType]        = { INVSLOT_TRINKET1, INVSLOT_TRINKET2 },
		[Enum.InventoryType.IndexCloakType]          = { INVSLOT_BACK },
		[Enum.InventoryType.IndexWeaponType]         = ((weapons == "any")
		                                               or (weapons == "dagger and any")
		                                               or (weapons == "dagger")
		                                               or ((weapons == "dual wield") and (not IsPlayerSpell(46917)))
		                                               or ((TOC_VERSION_CURRENT < TOC_VERSION_MOP)
		                                               and (weapons == "ranged")))
		                                               and (CanDualWield()
		                                               and { INVSLOT_MAINHAND, INVSLOT_OFFHAND }
		                                               or { INVSLOT_MAINHAND })
		                                               or ((weapons == "weapon and shield")
		                                               and { INVSLOT_MAINHAND }
		                                               or nil),
		[Enum.InventoryType.IndexShieldType]         = ((weapons == "any")
		                                               or (weapons == "weapon and shield"))
		                                               and { INVSLOT_OFFHAND }
		                                               or nil,
		[Enum.InventoryType.Index2HweaponType]       = ((weapons == "2hDW")
		                                               and CanDualWield() and IsPlayerSpell(46917)
		                                               and (info.subclassID ~= Enum.ItemWeaponSubclass.Staff)
		                                               and ((TOC_VERSION_CURRENT >= TOC_VERSION_MOP)
		                                               or (info.subclassID ~= Enum.ItemWeaponSubclass.Polearm)))
		                                               and { INVSLOT_MAINHAND, INVSLOT_OFFHAND }
		                                               or (((weapons == "any")
		                                               or (weapons == "2h")
		                                               or ((weapons == "dual wield") and (not CanDualWield())))
		                                               and { INVSLOT_TABARD }
		                                               or nil),
		[Enum.InventoryType.IndexWeaponmainhandType] = ((weapons == "any")
		                                               or (weapons == "weapon and shield")
		                                               or (weapons == "dagger and any")
		                                               or (weapons == "dagger")
		                                               or ((weapons == "dual wield") and (not IsPlayerSpell(46917)))
		                                               or ((TOC_VERSION_CURRENT < TOC_VERSION_MOP)
		                                               and (weapons == "ranged")))
		                                               and { INVSLOT_MAINHAND }
		                                               or nil,
		[Enum.InventoryType.IndexWeaponoffhandType]  = (CanDualWield()
		                                               and ((weapons == "any")
		                                               or (weapons == "dagger and any")
		                                               or (weapons == "dagger")
		                                               or ((weapons == "dual wield") and (not IsPlayerSpell(46917)))
		                                               or ((TOC_VERSION_CURRENT < TOC_VERSION_MOP)
		                                               and (weapons == "ranged"))))
		                                               and { INVSLOT_OFFHAND }
		                                               or nil,
		[Enum.InventoryType.IndexHoldableType]       = (weapons == "any")
		                                               and { INVSLOT_OFFHAND }
		                                               or nil,
		[Enum.InventoryType.IndexRangedType]         = (TOC_VERSION_CURRENT < TOC_VERSION_MOP)
		                                               and { INVSLOT_RANGED }
		                                               or ((weapons == "ranged")
		                                               and { INVSLOT_MAINHAND }
		                                               or nil),
		[Enum.InventoryType.IndexThrownType]         = (TOC_VERSION_CURRENT < TOC_VERSION_MOP)
		                                               and { INVSLOT_RANGED }
		                                               or ((weapons == "ranged")
		                                               and { INVSLOT_MAINHAND }
		                                               or nil),
		[Enum.InventoryType.IndexRangedrightType]    = (TOC_VERSION_CURRENT < TOC_VERSION_MOP)
		                                               and { INVSLOT_RANGED }
		                                               or (((weapons == "ranged")
													   or (info.subclassID == Enum.ItemWeaponSubclass.Wand))
		                                               and { INVSLOT_MAINHAND }
		                                               or nil),
		[Enum.InventoryType.IndexRelicType]          = (TOC_VERSION_CURRENT < TOC_VERSION_MOP)
		                                               and { INVSLOT_RANGED }
		                                               or nil,
		[Enum.InventoryType.IndexTabardType]         = nil, -- INVSLOT_TABARD is used for evaluating 2h weapons
		[Enum.InventoryType.IndexBagType]            = TyGearBagSlotsForItem(info),
		[Enum.InventoryType.IndexQuiverType]         = (weapons == "ranged")
		                                               and TyGearEquippableBagSlots
                                                       or nil
	}

	local result = gearSlotTable[info.invType]
	TyGearValidGearSlotsCache[cacheKey] = result or false
	return result
end

-- indicates slots that go together as a set
-- for example, the set of slots for a shield is { main-hand and off-hand } even though the shield can only be equipped in the off-hand
-- this is useful to find which slots to use to add scores together from all items in those slots
function TyGearGetSetSlots(info)
	local dualWield = CanDualWield() and 1 or 0
	local titanGrip = IsPlayerSpell(46917) and 1 or 0
	local cacheKey = (weapons or "any").."|"..dualWield.."|"..titanGrip.."|"..tostring(info.invType).."|"..tostring(info.subclassID or 0).."|"..(TyGearIsReagentBag(info) and "R" or "0").."|"..(TyGearUsesReagentBagSlot(info) and "1" or "0").."|"..tostring(TyGearReagentBagSlot or 0)
	local cached = TyGearSetSlotsCache[cacheKey]
	if cached ~= nil then
		return cached ~= false and cached or nil
	end
	local setSlotTable = {
		[Enum.InventoryType.IndexNonEquipType]       = nil,
		[Enum.InventoryType.IndexAmmoType]           = nil, -- ignore ammo because it's hard to match with weapon type
		[Enum.InventoryType.IndexHeadType]           = { INVSLOT_HEAD },
		[Enum.InventoryType.IndexNeckType]           = { INVSLOT_NECK },
		[Enum.InventoryType.IndexShoulderType]       = { INVSLOT_SHOULDER },
		[Enum.InventoryType.IndexBodyType]           = nil, -- shirts are cosmetic; do not evaluate or equip
		[Enum.InventoryType.IndexChestType]          = { INVSLOT_CHEST },
		[Enum.InventoryType.IndexRobeType]           = { INVSLOT_CHEST },
		[Enum.InventoryType.IndexWaistType]          = { INVSLOT_WAIST },
		[Enum.InventoryType.IndexLegsType]           = { INVSLOT_LEGS },
		[Enum.InventoryType.IndexFeetType]           = { INVSLOT_FEET },
		[Enum.InventoryType.IndexWristType]          = { INVSLOT_WRIST },
		[Enum.InventoryType.IndexHandType]           = { INVSLOT_HAND },
		[Enum.InventoryType.IndexFingerType]         = { INVSLOT_FINGER1, INVSLOT_FINGER2 },
		[Enum.InventoryType.IndexTrinketType]        = { INVSLOT_TRINKET1, INVSLOT_TRINKET2 },
		[Enum.InventoryType.IndexCloakType]          = { INVSLOT_BACK },
		[Enum.InventoryType.IndexWeaponType]         = ((weapons == "any")
		                                               or (weapons == "dagger and any")
		                                               or (weapons == "dagger")
		                                               or ((weapons == "dual wield") and (not IsPlayerSpell(46917)))
		                                               or ((TOC_VERSION_CURRENT < TOC_VERSION_MOP)
		                                               and (weapons == "ranged")))
		                                               and (CanDualWield()
		                                               and { INVSLOT_MAINHAND, INVSLOT_OFFHAND }
		                                               or { INVSLOT_MAINHAND })
		                                               or ((weapons == "weapon and shield")
		                                               and { INVSLOT_MAINHAND, INVSLOT_OFFHAND }
		                                               or nil),
		[Enum.InventoryType.IndexShieldType]         = ((weapons == "any")
		                                               or (weapons == "weapon and shield"))
		                                               and { INVSLOT_MAINHAND, INVSLOT_OFFHAND }
		                                               or nil,
		[Enum.InventoryType.Index2HweaponType]       = ((weapons == "2hDW")
		                                               and CanDualWield() and IsPlayerSpell(46917)
		                                               and (info.subclassID ~= Enum.ItemWeaponSubclass.Staff)
		                                               and ((TOC_VERSION_CURRENT >= TOC_VERSION_MOP)
		                                               or (info.subclassID ~= Enum.ItemWeaponSubclass.Polearm)))
		                                               and { INVSLOT_MAINHAND, INVSLOT_OFFHAND }
		                                               or (((weapons == "any")
		                                               or (weapons == "2h")
		                                               or ((weapons == "dual wield") and (not CanDualWield())))
		                                               and { INVSLOT_TABARD }
		                                               or nil),
		[Enum.InventoryType.IndexWeaponmainhandType] = ((weapons == "any")
		                                               or (weapons == "weapon and shield")
		                                               or (weapons == "dagger and any")
		                                               or (weapons == "dagger")
		                                               or ((weapons == "dual wield") and (not IsPlayerSpell(46917)))
		                                               or ((TOC_VERSION_CURRENT < TOC_VERSION_MOP)
		                                               and (weapons == "ranged")))
		                                               and { INVSLOT_MAINHAND, INVSLOT_OFFHAND }
		                                               or nil,
		[Enum.InventoryType.IndexWeaponoffhandType]  = (CanDualWield()
		                                               and ((weapons == "any")
		                                               or (weapons == "dagger and any")
		                                               or (weapons == "dagger")
		                                               or ((weapons == "dual wield") and (not IsPlayerSpell(46917)))
		                                               or ((TOC_VERSION_CURRENT < TOC_VERSION_MOP)
		                                               and (weapons == "ranged"))))
		                                               and { INVSLOT_MAINHAND, INVSLOT_OFFHAND }
		                                               or nil,
		[Enum.InventoryType.IndexHoldableType]       = (weapons == "any")
		                                               and { INVSLOT_MAINHAND, INVSLOT_OFFHAND }
		                                               or nil,
		[Enum.InventoryType.IndexRangedType]         = (TOC_VERSION_CURRENT < TOC_VERSION_MOP)
		                                               and { INVSLOT_RANGED }
		                                               or ((weapons == "ranged")
													   and { INVSLOT_MAINHAND }
													   or nil),
		[Enum.InventoryType.IndexThrownType]         = (TOC_VERSION_CURRENT < TOC_VERSION_MOP)
		                                               and { INVSLOT_RANGED }
		                                               or ((weapons == "ranged")
													   and { INVSLOT_MAINHAND }
													   or nil),
		[Enum.InventoryType.IndexRangedrightType]    = (TOC_VERSION_CURRENT < TOC_VERSION_MOP)
		                                               and { INVSLOT_RANGED }
		                                               or ((weapons == "ranged")
		                                               and { INVSLOT_MAINHAND }
		                                               or (((info.subclassID == Enum.ItemWeaponSubclass.Wand)
		                                               and { INVSLOT_MAINHAND, INVSLOT_OFFHAND })
		                                               or nil)),
		[Enum.InventoryType.IndexRelicType]          = (TOC_VERSION_CURRENT < TOC_VERSION_MOP)
		                                               and { INVSLOT_RANGED }
		                                               or nil,
		[Enum.InventoryType.IndexTabardType]         = nil, -- INVSLOT_TABARD is used for evaluating 2h weapons
		[Enum.InventoryType.IndexBagType]            = TyGearBagSlotsForItem(info),
		[Enum.InventoryType.IndexQuiverType]         = (weapons == "ranged")
		                                               and TyGearEquippableBagSlots
                                                       or nil
	}

	local result = setSlotTable[info.invType]
	TyGearSetSlotsCache[cacheKey] = result or false
	return result
end

function TyGearIsInvTypeWeapon(invType)
	if not invType then return nil end
	return TyGearIsInvTypeTwoHanded(invType) or
	TyGearIsInvTypeOneHanded(invType) or
	TyGearIsInvTypeRangedOrRelic(invType)
end

function TyGearIsInvTypeOneHanded(invType)
	if not invType then return nil end
	return (invType == Enum.InventoryType.IndexWeaponType) or
	(invType == Enum.InventoryType.IndexWeaponmainhandType) or
	(invType == Enum.InventoryType.IndexWeaponoffhandType) or
	(invType == Enum.InventoryType.IndexShieldType) or
	(invType == Enum.InventoryType.IndexHoldableType) or
	((TOC_VERSION_CURRENT >= TOC_VERSION_MOP) and (invType == Enum.InventoryType.IndexRangedrightType))
end

function TyGearIsInvTypeTwoHanded(invType)
	if not invType then return nil end
	return (invType == Enum.InventoryType.Index2HweaponType) or
	((TOC_VERSION_CURRENT >= TOC_VERSION_MOP) and (invType == Enum.InventoryType.IndexRangedType))
end

function TyGearIsInvTypeRangedOrRelic(invType)
	if not invType then return nil end
	return (TOC_VERSION_CURRENT < TOC_VERSION_MOP) and (
		TyGearIsInvTypeRanged(invType) or
		TyGearIsInvTypeRelic(invType)
	)
end

function TyGearIsInvTypeRanged(invType)
	if not invType then return nil end
	return (TOC_VERSION_CURRENT < TOC_VERSION_MOP) and (
		(invType == Enum.InventoryType.IndexRangedType) or
		(invType == Enum.InventoryType.IndexRangedrightType) or
		(invType == Enum.InventoryType.IndexThrownType)
	)
end

function TyGearIsInvTypeRelic(invType)
	if not invType then return nil end
	return (TOC_VERSION_CURRENT < TOC_VERSION_MOP) and (
		invType == Enum.InventoryType.IndexRelicType
	)
end

function TyGearIsAmmoBagAQuiverForArrows(info)
	if (not info.classID) or (not info.subclassID) then return nil end
	return (info.isAmmoBag) and (info.subclassID == 2)
end

function TyGearIsAmmoBagABulletPouch(info)
	if (not info.classID) or (not info.subclassID) then return nil end
	return (info.isAmmoBag) and (info.subclassID == 3)
end

function TyGearIsAmmoBagValidForRangedWeapon(ammoBag, rangedWeapon)
	if (not ammoBag.isAmmoBag)
	or (not rangedWeapon.isRangedWeapon)
	or (not rangedWeapon.classID)
	or (not rangedWeapon.subclassID) then
		return nil
	end
	return (TyGearIsAmmoBagAQuiverForArrows(ammoBag) and
	(TyGearIsRangedWeaponABowOrCrossbow(rangedWeapon))) or
	(TyGearIsAmmoBagABulletPouch(ammoBag) and
	TyGearIsRangedWeaponAGun(rangedWeapon))
end

function TyGearIsRangedWeaponABowOrCrossbow(info)
	if (not info.classID) or (not info.subclassID) then return nil end
	return (info.classID == Enum.ItemClass.Weapon) and
	((info.subclassID == Enum.ItemWeaponSubclass.Bows) or
	(info.subclassID == Enum.ItemWeaponSubclass.Crossbow))
end

function TyGearIsRangedWeaponAGun(info)
	if (not info.classID) or (not info.subclassID) then return nil end
	return ((info.classID == Enum.ItemClass.Weapon) and
	(info.subclassID == Enum.ItemWeaponSubclass.Guns))
end

function TyGearIsItemTwoHanded(itemID)
	if not itemID then return nil end
	return TyGearIsInvTypeTwoHanded(C_Item.GetItemInventoryTypeByID(itemID))
end

function TyGearIsTwoHandEquipped()
	return TyGearIsItemTwoHanded(GetInventoryItemID("player", INVSLOT_MAINHAND))
end

function TyGearIsMainHandAFishingPole()
	local mainHandID = GetInventoryItemID("player", INVSLOT_MAINHAND)
	if mainHandID then
		local itemClassID, itemSubClassID = select(6, GetItemInfoInstant(GetInventoryItemID("player", INVSLOT_MAINHAND)))
		return ((itemClassID == Enum.ItemClass.Weapon) and (itemSubClassID == Enum.ItemWeaponSubclass.Fishingpole))
	end
end

function TyGearPrintItem(info)
	TyGearPrint("TyGear:     "..(info.link or info.name)..":", 2)
	if TyGearUsingPawn() then
		local score = TyGearDetermineItemScore(info)
		-- 3 decimal places max
		score = math.floor(score * 1000) / 1000
		TyGearPrint("TyGear:         "..TyGearGetWeightSourceLabel().." score: "..(score or "nil"),2)
	elseif TyGearCurrentWeighting then
		for k,v in pairs(info) do
			if (k ~= "Name" and TyGearCurrentWeighting[k]) then
				TyGearPrint("TyGear:         "..k..": "..string.format("%.2f", v).." * "..TyGearCurrentWeighting[k].." = "..string.format("%.2f", v * TyGearCurrentWeighting[k]), 2)
			end
		end
	else
		TyGearPrint("TyGear:         (error: Stats aren't ready to be printed.)", 2)
	end
end

--matches the item set header line in item tooltips, like "Midnight Herald's Regalia (2/5)"; ITEM_SET_NAME is "%s (%d/%d)" in English and is localized, so magic characters are escaped before turning its format specifiers into pattern items
local ITEM_SET_NAME_PATTERN = "^"..(ITEM_SET_NAME:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0"):gsub("%%s", ".+"):gsub("%%d", "%%d+")).."$"

-- Forever/modern tooltips often put armor and block on a rightText column ("Armor" / "189")
-- or omit readable tooltip numbers under secret-value rules. C_Item.GetItemStats still returns
-- RESISTANCE0_NAME (armor) and ITEM_MOD_BLOCK_VALUE (shield block), which shields need to score.
-- Include both SHORT and non-SHORT keys; clients vary on which GetItemStats emits.
local TyGearItemStatsAPIFieldMap = {
	ITEM_MOD_STRENGTH = "Strength",
	ITEM_MOD_STRENGTH_SHORT = "Strength",
	ITEM_MOD_AGILITY = "Agility",
	ITEM_MOD_AGILITY_SHORT = "Agility",
	ITEM_MOD_STAMINA = "Stamina",
	ITEM_MOD_STAMINA_SHORT = "Stamina",
	ITEM_MOD_INTELLECT = "Intellect",
	ITEM_MOD_INTELLECT_SHORT = "Intellect",
	ITEM_MOD_SPIRIT = "Spirit",
	ITEM_MOD_SPIRIT_SHORT = "Spirit",
	RESISTANCE0_NAME = "Armor",
	ITEM_MOD_DEFENSE_SKILL_RATING = "Defense",
	ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = "Defense",
	ITEM_MOD_DODGE_RATING = "Dodge",
	ITEM_MOD_DODGE_RATING_SHORT = "Dodge",
	ITEM_MOD_PARRY_RATING = "Parry",
	ITEM_MOD_PARRY_RATING_SHORT = "Parry",
	ITEM_MOD_ATTACK_POWER = "AttackPower",
	ITEM_MOD_ATTACK_POWER_SHORT = "AttackPower",
	ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "DPS",
	ITEM_MOD_SPELL_POWER = "SpellPower",
	ITEM_MOD_SPELL_POWER_SHORT = "SpellPower",
	ITEM_MOD_SPELL_DAMAGE_DONE = "SpellPower",
	ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "SpellPower",
	ITEM_MOD_SPELL_HEALING_DONE = "SpellPower",
	ITEM_MOD_MANA_REGENERATION = "Mp5",
	ITEM_MOD_MANA_REGENERATION_SHORT = "Mp5",
	ITEM_MOD_POWER_REGEN0_SHORT = "Mp5",
	ITEM_MOD_HIT_RATING = "Hit",
	ITEM_MOD_HIT_RATING_SHORT = "Hit",
	ITEM_MOD_HIT_MELEE_RATING = "Hit",
	ITEM_MOD_CRIT_RATING = "Crit",
	ITEM_MOD_CRIT_RATING_SHORT = "Crit",
	ITEM_MOD_CRIT_MELEE_RATING = "Crit",
	ITEM_MOD_CRIT_SPELL_RATING = "SpellCrit",
	ITEM_MOD_CRIT_SPELL_RATING_SHORT = "SpellCrit",
	ITEM_MOD_HIT_SPELL_RATING = "SpellHit",
	ITEM_MOD_HIT_SPELL_RATING_SHORT = "SpellHit",
	ITEM_MOD_HASTE_RATING = "Haste",
	ITEM_MOD_HASTE_RATING_SHORT = "Haste",
	ITEM_MOD_EXPERTISE_RATING = "Expertise",
	ITEM_MOD_EXPERTISE_RATING_SHORT = "Expertise",
	ITEM_MOD_ARMOR_PENETRATION_RATING = "ArmorPenetration",
	ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT = "ArmorPenetration",
	ITEM_MOD_SPELL_PENETRATION = "SpellPenetration",
	ITEM_MOD_SPELL_PENETRATION_SHORT = "SpellPenetration",
	ITEM_MOD_MASTERY_RATING = "Mastery",
	ITEM_MOD_MASTERY_RATING_SHORT = "Mastery",
	ITEM_MOD_VERSATILITY = "Versatility",
}

-- Strip color/texture markup so "|cnIQ3:+5|r Strength" still yields value 5, not 3 from IQ3.
function TyGearStripTooltipMarkup(text)
	if type(text) ~= "string" or text == "" then return text end
	text = string.gsub(text, "|c%x%x%x%x%x%x%x%x", "")
	text = string.gsub(text, "|cn[^:]*:", "")
	text = string.gsub(text, "|r", "")
	text = string.gsub(text, "|A[^|]*|a", "")
	text = string.gsub(text, "|T[^|]*|t", "")
	text = string.gsub(text, "|H.-|h", "")
	text = string.gsub(text, "|h", "")
	return text
end

function TyGearReadableStatNumber(value)
	if type(value) ~= "number" then return nil end
	if issecretvalue and issecretvalue(value) then return nil end
	if value > 0 then return value end
end

function TyGearGetItemStatsTable(itemLink, itemID)
	local function tryStats(link)
		if type(link) ~= "string" or link == "" then return end
		if issecretvalue and issecretvalue(link) then return end
		if C_Item and C_Item.GetItemStats then
			local ok, result = pcall(C_Item.GetItemStats, link)
			if ok and type(result) == "table" then
				return result
			end
		end
		if GetItemStats then
			local ok, result = pcall(GetItemStats, link)
			if ok and type(result) == "table" then
				return result
			end
		end
	end
	local stats = tryStats(itemLink)
	-- Full hyperlinks can be secret or fail on Forever; plain item:id still returns green stats.
	if not stats and itemID then
		stats = tryStats("item:"..tostring(itemID))
	end
	return stats
end

-- Fill gaps left by tooltip parsing. Uses max() so tooltip enchants/procs are not wiped,
-- while shields still pick up base armor and block value when the tooltip omitted them.
function TyGearApplyItemStatsFromAPI(info)
	if not info or info.empty then return end
	local stats = TyGearGetItemStatsTable(info.link, info.id)
	if not stats then return end
	for apiKey, field in pairs(TyGearItemStatsAPIFieldMap) do
		local apiValue = TyGearReadableStatNumber(stats[apiKey])
		if apiValue then
			info[field] = math.max(info[field] or 0, apiValue)
		end
	end
	-- Block value and block rating are separate API keys; both feed info.Block like tooltip "block" matches.
	local apiBlock = (TyGearReadableStatNumber(stats.ITEM_MOD_BLOCK_VALUE) or 0)
		+ (TyGearReadableStatNumber(stats.ITEM_MOD_BLOCK_VALUE_SHORT) or 0)
		+ (TyGearReadableStatNumber(stats.ITEM_MOD_BLOCK_RATING) or 0)
		+ (TyGearReadableStatNumber(stats.ITEM_MOD_BLOCK_RATING_SHORT) or 0)
	if apiBlock > 0 then
		info.Block = math.max(info.Block or 0, apiBlock)
	end
end

function TyGearReadItemInfo(inventoryID, lootRollID, container, slot, link, tooltipData)
	local info = {}
	info.link = link
	local needsTooltip = not tooltipData

	if container and slot then
		info.item = Item:CreateFromBagAndSlot(container, slot)
		if info.item:IsItemEmpty() then
			info.empty = 1
			info.name = "nothing"
			return info
		end
		if not info.link then
			info.link = info.item:GetItemLink()
		end
		info.id = info.item:GetItemID()
	elseif inventoryID then
		info.item = Item:CreateFromEquipmentSlot(inventoryID)
		if info.item:IsItemEmpty() then
			info.empty = 1
			info.name = "nothing"
			return info
		end
		if not info.link then
			info.link = info.item:GetItemLink()
		end
		info.id = info.item:GetItemID()
	elseif lootRollID then
		if not info.link then
			info.link = GetLootRollItemLink(lootRollID)
		end
		info.item = Item:CreateFromItemLink(select(3,ExtractHyperlinkString(info.link)))
		info.id = info.item:GetItemID()
	elseif link then
		info.link = link
		info.item = Item:CreateFromItemLink(select(3,ExtractHyperlinkString(info.link)))
		info.id = info.item:GetItemID()
	else
		TyGearPrint(
			"inventoryID: "..tostring(inventoryID or "nil")..
			"; lootRollID: "..tostring(lootRollID or "nil")..
			"; container: "..tostring(container or "nil")..
			"; slot: "..tostring(slot or "nil")..
			"; link: "..tostring(link or "nil"),
			3
		)
	end

	if not info.id and info.item then
		info.id = info.item:GetItemID()
	end
	info.itemLocation = info.item and info.item.HasItemLocation and info.item:HasItemLocation() and info.item:GetItemLocation()
	if not (info.itemLocation and info.itemLocation.IsValid and info.itemLocation:IsValid() and info.itemLocation:HasAnyLocation()) then
		info.itemLocation = nil
	end
	if not info.id then
		TyGearPrint("Error: "..tostring(info.name or "nil").." doesn't have an item ID",3)
		TyGearPrint(
			"inventoryID: "..tostring(inventoryID or "nil")..
			"; lootRollID: "..tostring(lootRollID or "nil")..
			"; container: "..tostring(container or "nil")..
			"; slot: "..tostring(slot or "nil")..
			"; link: "..tostring(info.link or "nil"),
			3
		)
		return info
	end
	local itemName, itemSubType, classID, subclassID, equipLoc = TyGearItemIdentity(info.id)
	info.classID, info.subclassID = classID, subclassID
	info.subclassName = itemSubType
	info.equipLoc = equipLoc
	if type(itemName) ~= "string" and type(info.link) == "string" then
		itemName = string.match(info.link, "%[(.-)%]")
	end
	if type(itemName) == "string" and itemName ~= "" and not (issecretvalue and issecretvalue(itemName)) then
		info.name = itemName
	elseif info.item and info.item.GetItemName then
		local fromItem = info.item:GetItemName()
		if type(fromItem) == "string" and fromItem ~= "" and not (issecretvalue and issecretvalue(fromItem)) then
			info.name = fromItem
		end
	end
	info.rarity = info.item:GetItemQuality()
	info.rarityColor = info.item:GetItemQualityColor()
	info.invType = C_Item.GetItemInventoryTypeByID(info.id) or 0
	info.isGear = info.invType > 0
	-- Ammo, shirts, and tabards have an inventory type but are not scored or equipped as gear.
	-- (Ammo especially: matching it to weapon type is unreliable, and tooltips would crash comparing to a nil equipped score.)
	if info.isGear and Enum and Enum.InventoryType then
		local inv = Enum.InventoryType
		if info.invType == inv.IndexAmmoType
		or info.invType == inv.IndexBodyType
		or info.invType == inv.IndexTabardType then
			info.isGear = nil
		end
	elseif info.isGear and (info.equipLoc == "INVTYPE_AMMO"
		or info.equipLoc == "INVTYPE_BODY"
		or info.equipLoc == "INVTYPE_TABARD") then
		info.isGear = nil
	end
	-- Projectile ammo is class 6 even when inventory enums are incomplete.
	if info.isGear and Enum and Enum.ItemClass and Enum.ItemClass.Projectile
	and info.classID == Enum.ItemClass.Projectile then
		info.isGear = nil
	end

	-- Detect reagent and profession bags from classID / subclassID / equipLoc (not names or item ids).
	-- Dedicated reagent bags and Forever profession/soul bags belong in the reagent bag slot;
	-- keep them even if inventory type is missing.
	if TyGearIsReagentBag(info) then
		info.isReagentBag = 1
		info.isGear = 1
		if info.invType == 0 and Enum and Enum.InventoryType then
			info.invType = Enum.InventoryType.IndexBagType
		end
	elseif TyGearUsesReagentBagSlot(info) then
		if TyGearIsSoulBag(info) then
			info.isSoulBag = 1
		end
		info.isGear = 1
		if info.invType == 0 and Enum and Enum.InventoryType then
			info.invType = Enum.InventoryType.IndexBagType
		end
	end

	if (info.classID == Enum.ItemClass.Miscellaneous) and
	(info.subclassID == Enum.ItemMiscellaneousSubclass.Mount) then
		info.isMount = 1
		if not info.link then
			info.link = info.item:GetItemLink()
		end
		return info -- mounts are never auto-rolled; leave them for the player
	elseif not info.isGear then
		-- Skip tooltip work for non-gear; bag scans hit this path often
		if not info.link then
			info.link = info.item:GetItemLink()
		end
		return info
	end

	-- Forever: weapons this class can never learn are not evaluated (no score, no upgrade/roll consideration).
	-- Weapons the class can learn but has not trained still go through scoring so tooltips can show the score with "(won't equip)".
	if IS_WOW_FOREVER and info.classID == Enum.ItemClass.Weapon
	and TyGearForeverClassCanUseWeapon(info.subclassID) == false then
		if not info.link then
			info.link = info.item:GetItemLink()
		end
		info.unusable = 1
		info.classCannotUseWeapon = 1
		local realLocalizedClass, realClass = TyGearDetectClassAndSpec()
		local coloredClass = (RAID_CLASS_COLORS[realClass] and RAID_CLASS_COLORS[realClass]:WrapTextInColorCode(realLocalizedClass)) or realLocalizedClass
		info.reason = "("..coloredClass.." can't use this weapon)"
		return info
	end

	-- Deferred tooltip fill: only gear reaches here
	if needsTooltip then
		TyGearTooltip:SetOwner(UIParent, "ANCHOR_NONE")
		TyGearTooltip:ClearLines()
		if container and slot then
			tooltipData = C_TooltipInfo and C_TooltipInfo.GetBagItem(container, slot)
			if not tooltipData then TyGearTooltip:SetBagItem(container, slot) end
		elseif inventoryID then
			if C_TooltipInfo and C_TooltipInfo.GetInventoryItem then
				tooltipData = C_TooltipInfo.GetInventoryItem("player", inventoryID)
			else
				TyGearTooltip:SetInventoryItem("player", inventoryID)
			end
		elseif lootRollID then
			if C_TooltipInfo and C_TooltipInfo.GetLootRollItem then
				tooltipData = C_TooltipInfo.GetLootRollItem(lootRollID)
			else
				TyGearTooltip:SetLootRollItem(lootRollID)
			end
		elseif info.link then
			if C_TooltipInfo and C_TooltipInfo.GetHyperlink then
				tooltipData = C_TooltipInfo.GetHyperlink(info.link)
			else
				TyGearTooltip:SetHyperlink(info.link)
			end
		end
	end

	info.guid = tooltipData and tooltipData.guid or info.item:GetItemGUID()
	if info.link == nil then
		TyGearPrint("Error: "..tostring(info.name or "nil").." doesn't have a link",3)
		TyGearPrint(
			"inventoryID: "..tostring(inventoryID or "nil")..
			"; lootRollID: "..tostring(lootRollID or "nil")..
			"; container: "..tostring(container or "nil")..
			"; slot: "..tostring(slot or "nil")..
			"; link: "..tostring(info.link or "nil"),
			3
		)
		return info
	end

	info.RedSockets = 0
	info.YellowSockets = 0
	info.BlueSockets = 0
	info.MetaSockets = 0
	local localizedClass, class, spec = TyGearGetClassAndSpec()

	if info.isGear then
		if TyGearIsInvTypeWeapon(info.invType) then
			info.isWeaponOrOffHand = 1
		end
		if TyGearIsInvTypeTwoHanded(info.invType) then
			info.is2hWeapon = 1
		elseif TyGearIsInvTypeOneHanded(info.invType) then
			info.is1hWeaponOrOffHand = 1
		elseif TyGearIsInvTypeRanged(info.invType) then
			info.isRangedWeapon = 1
		elseif TyGearIsInvTypeRelic(info.invType) then
			info.isRelic = 1
		end
		if info.classID == Enum.ItemClass.Quiver then
			info.isAmmoBag = 1
		end
		info.validGearSlots = TyGearGetValidGearSlots(info)
		info.numValidGearSlots = 0
		if not info.validGearSlots then
			info.unusable = 1
			info.reason = "(invalid item for "..RAID_CLASS_COLORS[class]:WrapTextInColorCode(spec.." "..localizedClass)..")"
		else
			for _, slot in pairs(info.validGearSlots) do
				info.numValidGearSlots = info.numValidGearSlots + 1
			end
		end
	end

	local numLines = tooltipData and #tooltipData.lines or TyGearTooltip:NumLines()
	local textLeft, textRight
	--disabled set bonuses used to be grey but turned red in Midnight, leading to needing this detection to prevent falsely detecting items with disabled set bonuses as unusable
	--the item set section starts at its header line and comes after the item's own requirements; red text there (like an inactive set bonus's "Requires level 80 or below") is about the set, not about using the item
	local isInItemSetSection = false
	local sawSecretTooltipLine = false

	for i = 1, numLines do
		local textLeftText
		if tooltipData and tooltipData.lines then
			textLeft = tooltipData.lines[i].leftText
			textLeftText = textLeft
		else
			textLeft = _G["TyGearTooltipTextLeft"..i]
		end
		if textLeft then
			local r, g, b
			if textLeft.GetTextColor then
				r, g, b = textLeft:GetTextColor()
			else
				r, g, b = tooltipData.lines[i].leftColor:GetRGB()
			end
			if not textLeftText then
				textLeftText = textLeft:GetText() or ""
			end
			-- Secret lines can't be parsed, but later lines (or GetItemStats) still may be.
			-- Aborting here made rings/necks score as 0 when only some lines were restricted.
			if issecretvalue and issecretvalue(textLeftText) then
				sawSecretTooltipLine = true
				if TyGearIsReagentBag(info) then
					TyGearAssignReagentBagSlots(info)
					return info
				end
				if TyGearUsesReagentBagSlot(info) then
					info.validGearSlots = TyGearBagSlotsForItem(info)
					info.numValidGearSlots = 0
					if info.validGearSlots then
						for _ in pairs(info.validGearSlots) do
							info.numValidGearSlots = info.numValidGearSlots + 1
						end
					end
					if info.numValidGearSlots > 0 and not info.ignored and not TyGearIsItemIgnored(info) then
						info.unusable = nil
						info.usable = 1
						info.reason = nil
					end
					return info
				end
				TyGearApplyItemStatsFromAPI(info)
				TyGearNormalizeWeaponDamageStats(info)
			else
			textLeftText = TyGearStripTooltipMarkup(textLeftText)
			-- Read rightText early so split stat lines ("Armor" | "189") still score.
			local textRight, textRightText
			if tooltipData and tooltipData.lines then
				textRight = tooltipData.lines[i].rightText or tooltipData.lines[i].textRight
				textRightText = textRight
			else
				textRight = _G["TyGearTooltipTextRight"..i]
			end
			if textRight and not textRightText then
				textRightText = textRight.GetText and textRight:GetText() or textRight
			end
			if textRightText and issecretvalue and issecretvalue(textRightText) then
				textRightText = nil
			elseif type(textRightText) == "string" then
				textRightText = TyGearStripTooltipMarkup(textRightText)
			end
			local text = select(1,string.gsub(textLeftText:lower(),",",""))
			if type(textRightText) == "string" and textRightText ~= "" then
				text = text.." "..select(1, string.gsub(textRightText:lower(), ",", ""))
			end
			if TyGearLineIsItemEffect(text) then
				info.sawEquipEffect = 1
			end
			if (i > 1) and string.match(textLeftText, ITEM_SET_NAME_PATTERN) then
				isInItemSetSection = true
			end
			if i==1 then
				info.name = textLeftText
				if info.name == "Retrieving item information" or not info.item:IsItemDataCached() then
					if not TyGearSomeItemDataIsMissing then
						TyGearSomeItemDataIsMissing = 1
						TyGearPrint("TyGear: An item was not yet ready on the client side when updating TyGear's local item info, so updating TyGear's table of equipped items again.",3)
						TyGearQueueLocalUpdate()
					end
					info.unusable = 1
					info.reason = "(this item's tooltip is not yet available)"
				end
			end
			if (i==2 or i==3) then
				-- local currentItem = GameTooltip:GetItem()
				-- if currentItem and info.id == Item:CreateFromItemLink(currentItem):GetItemID() then TyGearPrint(text,3) end
				if string.find(textLeftText, ITEM_BIND_ON_EQUIP) or
				string.find(textLeftText, ITEM_BIND_ON_USE) then
					info.boe = 1
				end
				if string.find(textLeftText, ITEM_SOULBOUND) or
				string.find(textLeftText, ITEM_BIND_ON_PICKUP) or
				string.find(textLeftText, ITEM_BIND_TO_ACCOUNT) or
				string.find(textLeftText, ITEM_BIND_TO_BNETACCOUNT) or
				string.find(textLeftText, ITEM_BIND_QUEST) then
					info.bop = 1
				end
			end
			if (i==numLines) and
			(not info.bop) then
				info.boe = 1
			end
			if textLeftText == ITEM_UNIQUE or textLeftText == ITEM_UNIQUE_EQUIPPABLE then
				info.unique = 1
			elseif string.find(textLeftText, ITEM_UNIQUE_EQUIPPABLE_SANITIZED_PATTERN) then
				local uniqueType, numEquippable = string.match(textLeftText, ITEM_UNIQUE_EQUIPPABLE_SANITIZED_PATTERN.."[：:]+ ?(%C-) ?[%(（]-(%d+)[%)）]-$")
				if uniqueType and numEquippable then
					info.uniqueType = uniqueType
					info.numEquippable = tonumber(numEquippable)
				end
				TyGearPrint("TyGear: uniqueType, numEquippable in \""..textLeftText.."\": \""..tostring(uniqueType).."\", "..tostring(numEquippable), 3)
			end
			local multiplier = 1.0
			if string.find(text, "chance to") and not string.find(text, "improves") then multiplier = multiplier/3.0 end
			if string.find(text, "use:") then multiplier = multiplier/6.0 end
			-- don't count greyed out set bonus lines
			if r < 0.8 and g < 0.8 and b < 0.8 and string.find(text, "set:") then multiplier = 0 end
			-- note: these proc checks may not be correct for all cases
			if string.find(text, "chance") or string.find(text, "use:") then
				if string.find(text, "deal damage") then multiplier = multiplier * (TyGearCurrentWeighting.DamageProc or 0) end
				if string.find(text, "damage and healing") then multiplier = multiplier * math.max((TyGearCurrentWeighting.HealingProc or 0), (TyGearCurrentWeighting.DamageProc or 0))
				elseif string.find(text, "healing spells") then multiplier = multiplier * (TyGearCurrentWeighting.HealingProc or 0)
				elseif string.find(text, "damage spells") then multiplier = multiplier * (TyGearCurrentWeighting.DamageSpellProc or 0)
				end
				if string.find(text, "melee and ranged") then multiplier = multiplier * math.max((TyGearCurrentWeighting.MeleeProc or 0), (TyGearCurrentWeighting.RangedProc or 0))
				elseif string.find(text, "melee attacks") then multiplier = multiplier * (TyGearCurrentWeighting.MeleeProc or 0)
				elseif string.find(text, "ranged attacks") then multiplier = multiplier * (TyGearCurrentWeighting.RangedProc or 0)
				end
			end
			local value = tonumber(string.match(text, "-?[0-9]+%.?[0-9]*")) or 0
			if value then
				value = value * multiplier
			else
				value = 0
			end
			if value > 0
			and (
				string.find(text, " bag") or
				string.find(text, " pouch") or
				string.find(text, " pack") or
				string.find(text, " sack") or
				string.find(text, " satchel") or
				string.find(text, " quiver") or
				string.find(text, " ammo pouch") or
				string.find(text, " tackle box")
			) then
				info.numBagSlots = (info.numBagSlots or 0) + value
			end
			if value > 0
			and info.isAmmoBag
			and string.find(text, "ranged attack speed") then
				info.ammoBagRangedAttackSpeed = (info.ammoBagRangedAttackSpeed or 0) + value
			end
			if string.find(text, "already known") then
				info.alreadyKnown = 1
				info.unusable = 1
				info.reason = "(this item has been learned already)"
			end
			local isHealer = spec=="Holy" or spec=="Restoration" or spec=="Mistweaver" or spec=="Discipline"
			if string.find(text, L["strength"]) then info.Strength = (info.Strength or 0) + value end
			if string.find(text, L["agility"]) then info.Agility = (info.Agility or 0) + value end
			if string.find(text, L["intellect"]) then info.Intellect = (info.Intellect or 0) + value end
			if string.find(text, L["stamina"]) then info.Stamina = (info.Stamina or 0) + value end
			if string.find(text, L["spirit"]) then info.Spirit = (info.Spirit or 0) + value end
			if string.find(text, L["armor"]) and not string.find(text, "lowers their armor") and not string.find(text, "armor penetration") then info.Armor = (info.Armor or 0) + value end
			if string.find(text, "attack power") and not string.find(text, "when fighting") and (not string.find(text, "forms only") or class=="DRUID") then info.AttackPower = (info.AttackPower or 0) + value end
			if ((string.find(text, "spell power") or string.find(text, "spell damage")) or
				string.find(text, "damage and healing") or
				(string.find(text, "frost spell damage") or string.find(text, "damage done by frost spells and effects")) and (spec=="Frost" or class=="MAGE" and spec=="None") or
				(string.find(text, "fire spell damage") or string.find(text, "damage done by fire spells and effects")) and (spec=="Fire" or class=="MAGE" and spec=="None") or
				(string.find(text, "arcane spell damage") or string.find(text, "damage done by arcane spells and effects")) and (spec=="Arcane" or class=="MAGE" and spec=="None") or
				(string.find(text, "shadow spell damage") or string.find(text, "damage done by shadow spells and effects")) and (class=="WARLOCK") or
				(string.find(text, "nature spell damage") or string.find(text, "damage done by nature spells and effects")) and (spec=="Balance" or class=="DRUID" and spec=="None") or
				(string.find(text, "healing") and isHealer) or
				(string.find(text, "increases healing done") and isHealer)) then info.SpellPower = (info.SpellPower or 0) + value
			elseif IS_WOW_FOREVER and string.find(text, "healing") then
				-- on WoW Forever, bonus healing also grants spell damage at one third of its value
				info.SpellPower = (info.SpellPower or 0) + (value / 3)
			end
			if IS_WOW_FOREVER then
				-- WoW Forever combines melee, ranged and spell critical strike on gear
				if string.find(text, "critical strike") then info.Crit = (info.Crit or 0) + value end
			elseif TOC_VERSION_CURRENT < TOC_VERSION_WOTLK then
				if string.find(text, "critical strike with spells by") or string.find(text, "spell critical strike") or string.find(text, "spell critical rating") then info.SpellCrit = (info.SpellCrit or 0) + value end
				if string.find(text, "critical strike by") then info.Crit = (info.Crit or 0) + value end
				if string.find(text, "hit with spells by") or string.find(text, "spell hit rating by") then info.SpellHit = (info.SpellHit or 0) + value end
				if string.find(text, "critical strike by") then info.Crit = (info.Crit or 0) + value end
			else
				if string.find(text, "critical strike") then info.Crit = (info.Crit or 0) + value end
			end
			if TOC_VERSION_CURRENT < TOC_VERSION_WOD then
				if string.find(text, "hit by") or string.find(text, "improves hit rating by") or string.find(text, "your hit rating by")
				or (IS_WOW_FOREVER and string.find(text, "hit rating")) then
					info.Hit = (info.Hit or 0) + value
				end
			end
			if IS_WOW_FOREVER then
				if string.find(text, "expertise") then info.Expertise = (info.Expertise or 0) + value end
				if string.find(text, "armor penetration") then info.ArmorPenetration = (info.ArmorPenetration or 0) + value end
				if string.find(text, "spell penetration") then info.SpellPenetration = (info.SpellPenetration or 0) + value end
			end
			if string.find(text, "haste") then info.Haste = (info.Haste or 0) + value end
			if string.find(text, "mana per 5") or string.find(text, "mana every 5") then info.Mp5 = (info.Mp5 or 0) + value end
			if string.find(text, "meta socket") then info.MetaSockets = info.MetaSockets + 1 end
			if string.find(text, "red socket") then info.RedSockets = info.RedSockets + 1 end
			if string.find(text, "yellow socket") then info.YellowSockets = info.YellowSockets + 1 end
			if string.find(text, "blue socket") then info.BlueSockets = info.BlueSockets + 1 end
			if string.find(text, "dodge") then info.Dodge = (info.Dodge or 0) + value end
			if string.find(text, "parry") then info.Parry = (info.Parry or 0) + value end
			if string.find(text, L["block"]) then info.Block = (info.Block or 0) + value end
			if string.find(text, "defense") then info.Defense = (info.Defense or 0) + value end
			if string.find(text, "mastery") then info.Mastery = (info.Mastery or 0) + value end
			if string.find(text, "multistrike") then info.Multistrike = (info.Multistrike or 0) + value end
			if string.find(text, "versatility") then info.Versatility = (info.Versatility or 0) + value end
			if string.find(text, "experience gained") then info.ExperienceGained = (info.ExperienceGained or 0) + value end
			-- Base weapon damage/speed are not in GetItemStats; parse from tooltip lines.
			TyGearParseWeaponTooltipLine(info, text)
			--check for being a pattern or the like
			if string.find(text, "pattern:") then info.unusable = 1 end
			if string.find(text, "plans:") then info.unusable = 1 end

			--check for red text on the left
			if (not isInItemSetSection) and ((g==0 or r/g>3) and (b==0 or r/b>3) and math.abs(b-g)<0.1 and r>0.5 and textLeftText) then --this is red text
				--if Within5levels was already set but we found another red text, clear it, because we really can't use this
				if info.Within5levels then info.Within5levels = nil end
				--if there's not already a reason we cannot use and this is just a required level, check if it's within 5 levels
				if (not info.unusable and string.find(text, "requires level") and value - UnitLevel("player") <= 5) then
					info.Within5levels = 1
				end
				info.reason = "(found red text: \""..((textLeftText:len() > 25) and ((textLeftText):sub(1,20).."[...]") or textLeftText).."\")"
				info.unusable = 1
			end

			--check for red text on the right side (textRight/textRightText already resolved above)
			if textRight then
				local rr, rg, rb
				if textRight.GetTextColor then
					rr, rg, rb = textRight:GetTextColor()
				elseif tooltipData and tooltipData.lines and tooltipData.lines[i].rightColor then
					rr, rg, rb = tooltipData.lines[i].rightColor:GetRGB()
				end
				if rr and rg and rb
				and (not isInItemSetSection)
				and ((rg==0 or rr/rg>3) and (rb==0 or rr/rb>3) and math.abs(rb-rg)<0.1 and rr>0.5 and textRightText) then --this is red text
					info.reason = "(found red text: \""..textRightText.."\")"
					info.unusable = 1
				end
			end
			end -- non-secret tooltip line
		end
	end

	-- Base armor / shield block / primary stats from the item API when tooltip lines omitted them.
	-- Weapon DPS may appear here; min/max damage and swing speed still require the tooltip.
	TyGearApplyItemStatsFromAPI(info)
	TyGearNormalizeWeaponDamageStats(info)
	-- Tooltip may be empty while GetItemStats already has armor/block (common for shields on Forever).
	if info.unusable and (
		info.reason == "(this item's tooltip is not yet available)"
		or info.reason == "(item data is restricted right now)"
	) and TyGearItemHasMeasurableStats(info) then
		info.unusable = nil
		info.reason = nil
	end
	-- Only mark restricted when every useful line was secret and GetItemStats found nothing.
	if sawSecretTooltipLine and (not TyGearItemHasMeasurableStats(info)) and (not info.unusable) then
		info.unusable = 1
		info.reason = "(item data is restricted right now)"
		if TyGearIsItemIgnored(info) then
			info.ignored = 1
			info.usable = nil
			info.reason = "("..L["ignored"]..")"
		end
	end

	if info.RedSockets == 0 then info.RedSockets = nil end
	if info.YellowSockets == 0 then info.YellowSockets = nil end
	if info.BlueSockets == 0 then info.BlueSockets = nil end
	if info.MetaSockets == 0 then info.MetaSockets = nil end

	if info.isWeaponOrOffHand then
		if info.invType == Enum.InventoryType.IndexWeaponmainhandType then
			if ((weapons == "dagger")
			or (weapons == "dagger and any"))
			and info.subclassID ~= Enum.ItemWeaponSubclass.Dagger then
				info.unusable = 1
				info.reason = "("..RAID_CLASS_COLORS[class]:WrapTextInColorCode(spec.." "..localizedClass).." needs a dagger main hand)"
			elseif weapons == "2h"
			or (weapons == "2hDW" and CanDualWield() and IsPlayerSpell(46917)) or
			((TOC_VERSION_CURRENT >= TOC_VERSION_MOP)
			and weapons == "ranged") then
				info.unusable = 1
				info.reason = "("..RAID_CLASS_COLORS[class]:WrapTextInColorCode(spec.." "..localizedClass).." needs a two-handed weapon)"
			end
		elseif info.invType == Enum.InventoryType.IndexShieldType then
			if (weapons ~= "weapon and shield") and (weapons ~= "any") then
				info.unusable = 1
				info.reason = "("..RAID_CLASS_COLORS[class]:WrapTextInColorCode(spec.." "..localizedClass).." should not use a shield)"
			end
		elseif info.invType == Enum.InventoryType.Index2HweaponType then
			if weapons == "weapon and shield" then
				info.unusable = 1
				info.reason = "("..RAID_CLASS_COLORS[class]:WrapTextInColorCode(spec.." "..localizedClass).." needs a weapon and shield)"
			elseif weapons == "dual wield" and CanDualWield() and (not IsPlayerSpell(46917)) then
				info.unusable = 1
				info.reason = "("..RAID_CLASS_COLORS[class]:WrapTextInColorCode(spec.." "..localizedClass).." should dual wield one-handers)"
			elseif weapons == "2hDW" and CanDualWield() and IsPlayerSpell(46917) then
				if info.subclassID == Enum.ItemWeaponSubclass.Staff then
					info.unusable = 1
					info.reason = "(Titan's Grip doesn't work with a staff)"
				elseif info.subclassID == Enum.ItemWeaponSubclass.Polearm and TOC_VERSION_CURRENT < TOC_VERSION_MOP then
					info.unusable = 1
					info.reason = "(Titan's Grip doesn't work with a polearm)"
				end
			elseif ((TOC_VERSION_CURRENT >= TOC_VERSION_MOP)
			and weapons == "ranged") then
				info.unusable = 1
				info.reason = "("..RAID_CLASS_COLORS[class]:WrapTextInColorCode(spec.." "..localizedClass).." should use a ranged weapon)"
			end
		elseif info.invType == Enum.InventoryType.IndexHoldableType then
			if weapons == "2h"
			or (weapons == "dual wield" and CanDualWield())
			or weapons == "weapon and shield"
			or ((TOC_VERSION_CURRENT >= TOC_VERSION_MOP)
			and weapons == "ranged") then
				info.unusable = 1
				info.reason = "("..RAID_CLASS_COLORS[class]:WrapTextInColorCode(spec.." "..localizedClass).." needs the off-hand for a weapon or shield)"
			end
		elseif info.invType == Enum.InventoryType.IndexWeaponoffhandType then
			if weapons == "2h"
			or ((TOC_VERSION_CURRENT >= TOC_VERSION_MOP)
			and weapons == "ranged") then
				info.unusable = 1
				info.reason = "("..RAID_CLASS_COLORS[class]:WrapTextInColorCode(spec.." "..localizedClass).." needs a two-handed weapon)"
			elseif weapons == "dagger"
			and info.subclassID ~= Enum.ItemWeaponSubclass.Dagger then
				info.unusable = 1
				info.reason = "("..RAID_CLASS_COLORS[class]:WrapTextInColorCode(spec.." "..localizedClass).." needs a dagger in the off-hand)"
			elseif weapons == "weapon and shield"
			and ((info.classID ~= Enum.ItemClass.Armor)
			or (info.subclassID ~= Enum.ItemArmorSubclass.Shield)) then
				info.unusable = 1
				info.reason = "("..RAID_CLASS_COLORS[class]:WrapTextInColorCode(spec.." "..localizedClass).." needs a shield in the off-hand)"
			elseif weapons == "dual wield"
			and CanDualWield()
			and (not IsPlayerSpell(46917))
			and (info.classID == Enum.ItemClass.Armor)
			and (info.subclassID == Enum.ItemArmorSubclass.Shield) then
				info.unusable = 1
				info.reason = "("..RAID_CLASS_COLORS[class]:WrapTextInColorCode(spec.." "..localizedClass).." should dual wield and not use a shield)"
			end
		elseif info.invType == Enum.InventoryType.IndexWeaponType then
			if weapons == "2h"
			or ((TOC_VERSION_CURRENT >= TOC_VERSION_MOP)
			and (weapons == "ranged")) then
				info.unusable = 1
				info.reason = "("..RAID_CLASS_COLORS[class]:WrapTextInColorCode(spec.." "..localizedClass).." should use a two-handed weapon)"
			elseif (weapons == "2hDW" and CanDualWield() and IsPlayerSpell(46917)) then
				info.unusable = 1
				info.reason =  "("..RAID_CLASS_COLORS[class]:WrapTextInColorCode(spec.." "..localizedClass).." should dual wield two-handers)"
			elseif (weapons == "dagger"
			and info.subclassID ~= Enum.ItemWeaponSubclass.Dagger) then
				info.unusable = 1
				info.reason = "("..RAID_CLASS_COLORS[class]:WrapTextInColorCode(spec.." "..localizedClass).." needs a dagger in each hand)"
			end
		elseif (TOC_VERSION_CURRENT >= TOC_VERSION_MOP)
		and (info.invType == Enum.InventoryType.IndexRangedType)
		and	(weapons ~= "ranged"
		and info.subclassID ~= Enum.ItemWeaponSubclass.Wand) then
			info.unusable = 1
			info.reason = "("..RAID_CLASS_COLORS[class]:WrapTextInColorCode(spec.." "..localizedClass).." should not use a ranged 2h weapon)"
		end
	end

	info.equipped = not not inventoryID

	-- Class-incompatible Forever weapons return earlier without a score. Learnable weapons that
	-- currently can't be equipped (untrained skill, level, and so on) still show a score here.
	if info.isGear and not info.classCannotUseWeapon then
		info.shouldShowScoreInTooltip = 1
	end
	if (not info.unusable) and info.isGear then
		info.usable = 1
	elseif not info.isGear then
		info.unusable = 1
		info.reason = "(item can't be equipped. info.invType = '".. tostring(info.invType) .."')"
	end

	--A reagent bag's only valid slot is the reagent bag slot, even if an earlier pass treated it as a normal bag.
	TyGearAssignReagentBagSlots(info)

	--WoW Forever gear whose tooltip has an effect and no scored stat is ignored.
	--Gear that also has a stat TyGear can score is kept and evaluated on that stat.
	local tooltipWasUnreadable = info.reason == "(this item's tooltip is not yet available)" or info.reason == "(item data is restricted right now)"
	if IS_WOW_FOREVER and info.isGear and info.classID ~= Enum.ItemClass.Container and info.sawEquipEffect
	and not TyGearItemHasMeasurableStats(info) and not tooltipWasUnreadable then
		info.unmeasurableOnly = 1
		TyGearRememberUnmeasurableGear(info)
	end
	-- True ignore-list / unmeasurable items stay fully out of evaluation.
	-- Keep-list items remain usable so they can fill empty slots (something > nothing).
	if TyGearIsItemIgnored(info) then
		info.ignored = 1
		info.unusable = 1
		info.usable = nil
		info.reason = "("..L["ignored"]..")"
	elseif info.isGear and TyGearAllValidGearSlotsProtected(info) then
		info.unusable = 1
		info.usable = nil
		info.reason = "("..L["every slot this item can use is ignored"]..")"
	end

	--caching did not show a performance benefit, so commented this out
	-- if not TyGearIsItemDataMissing then
	-- 	TyGearItemInfoCache[info.linkHash] = info
	-- end

	return info
end

function TyGearGetPawnScales()
	TyGearPawnScales = {
		{
			["label"] = "Visible",
			["subLabels"] = {}
		},
		{
			["label"] = "Hidden",
			["subLabels"] = {}
		}
	}
	TyGearPawnScalesFromPawn = PawnGetAllScalesEx()
	for _, v in ipairs(TyGearPawnScalesFromPawn) do
		if v["IsVisible"] then
			table.insert(TyGearPawnScales[1]["subLabels"], v["LocalizedName"] or v["Name"])
		else
			table.insert(TyGearPawnScales[2]["subLabels"], v["LocalizedName"] or v["Name"])
		end
	end
	return TyGearPawnScales
end

function TyGearGetPawnScaleName(scaleNameToFind)
	local cacheKey = tostring(scaleNameToFind or "").."|"..tostring(TyGearDB.OverridePawnScale and TyGearDB.PawnScale or "").."|"..tostring(TyGearCharDB.Override and TyGearCharDB.OverrideSpec or "")
	if (not scaleNameToFind) and TyGearPawnScaleCacheKey == cacheKey and TyGearCachedPawnScaleName then
		return TyGearCachedPawnScaleName, TyGearCachedPawnScaleLocalizedName
	end
	local realLocalizedClass, realClass, realSpec, realClassID = TyGearDetectClassAndSpec()
	local overrideLocalizedClass, overrideClass, overrideSpec, overrideClassID = TyGearGetClassAndSpec()
	local function cacheAndReturn(name, localized)
		if not scaleNameToFind then
			TyGearPawnScaleCacheKey = cacheKey
			TyGearCachedPawnScaleName = name
			TyGearCachedPawnScaleLocalizedName = localized
		end
		return name, localized
	end

	-- Try to find the selected Pawn scale
	if TyGearDB.OverridePawnScale and TyGearDB.PawnScale then
		if not TyGearPawnScales then TyGearGetPawnScales() end
		scaleNameToFind = scaleNameToFind or TyGearDB.PawnScale
		for trueScaleName, scale in pairs(PawnCommon.Scales) do
			if ((scaleNameToFind == trueScaleName)
			or (scale.LocalizedName
			and (scaleNameToFind == scale.LocalizedName)))
			and scale.Values
			and next(scale.Values) then
				return cacheAndReturn(trueScaleName, scale.LocalizedName)
			end
		end
	end

	if TyGearCharDB.Override then

		-- Try to find a visible scale with name matching the full TyGearCharDB.OverrideSpec string (example: "Paladin: Protection")
		for scaleName, scale in pairs(PawnCommon.Scales) do
			if PawnIsScaleVisible(scaleName)
			and TyGearCharDB.OverrideSpec
			and TyGearCharDB.OverrideSpec == scaleName
			and scale.Values
			and next(scale.Values) then
				return cacheAndReturn(scaleName, scale.LocalizedName)
			end
		end

		-- Try to find a visible scale with localized name matching the full TyGearCharDB.OverrideSpec string (example: "Paladin: Protection")
		for scaleName, scale in pairs(PawnCommon.Scales) do
			if PawnIsScaleVisible(scaleName)
			and TyGearCharDB.OverrideSpec
			and TyGearCharDB.OverrideSpec == scale.LocalizedName
			and scale.Values
			and next(scale.Values) then
				return cacheAndReturn(scaleName, scale.LocalizedName)
			end
		end

		-- Try to find a visible scale with class ID matching the override class ID and override spec name found in the localized scale name (example: "Protection")
		for scaleName, scale in pairs(PawnCommon.Scales) do
			if PawnIsScaleVisible(scaleName)
			and TyGearCharDB.OverrideSpec
			and overrideClassID == scale.ClassID
			and scale.LocalizedName
			and string.find(scale.LocalizedName, overrideSpec)
			and scale.Values and next(scale.Values) then
				return cacheAndReturn(scaleName, scale.LocalizedName)
			end
		end

		-- Try to find a visible scale matching just the override spec name (example: "Protection")
		for scaleName, scale in pairs(PawnCommon.Scales) do
			if PawnIsScaleVisible(scaleName)
			and overrideSpec == scaleName
			and scale.Values
			and next(scale.Values) then
				return cacheAndReturn(scaleName, scale.LocalizedName)
			end
		end

		-- Try to find a visible scale with name matching just the override localized class name (example: "Paladin")
		for scaleName, scale in pairs(PawnCommon.Scales) do
			if PawnIsScaleVisible(scaleName)
			and overrideLocalizedClass == scaleName
			and scale.Values
			and next(scale.Values) then
				return cacheAndReturn(scaleName, scale.LocalizedName)
			end
		end

		-- Try to find any scale matching the full TyGearCharDB.OverrideSpec string (example: "Paladin: Protection")
		for scaleName, scale in pairs(PawnCommon.Scales) do
			if TyGearCharDB.OverrideSpec
			and TyGearCharDB.OverrideSpec == scaleName
			and scale.Values
			and next(scale.Values) then
				return cacheAndReturn(scaleName, scale.LocalizedName)
			end
		end

		-- Try to find any scale with localized name matching the full TyGearCharDB.OverrideSpec string (example: "Paladin: Protection")
		for scaleName, scale in pairs(PawnCommon.Scales) do
			if TyGearCharDB.OverrideSpec
			and TyGearCharDB.OverrideSpec == scale.LocalizedName
			and scale.Values
			and next(scale.Values) then
				return cacheAndReturn(scaleName, scale.LocalizedName)
			end
		end

		-- Try to find any scale with class ID matching the override class ID and name containing the override spec name (example: "Protection")
		for scaleName, scale in pairs(PawnCommon.Scales) do
			if scale.ClassID == overrideClassID
			and string.find(scaleName, overrideSpec)
			and scale.Values
			and next(scale.Values) then
				return cacheAndReturn(scaleName, scale.LocalizedName)
			end
		end

		-- Try to find any scale with name containing just the override spec name (example: "Protection")
		for scaleName, scale in pairs(PawnCommon.Scales) do
			if string.find(scaleName, overrideSpec)
			and scale.Values
			and next(scale.Values) then
				return cacheAndReturn(scaleName, scale.LocalizedName)
			end
		end

		-- Try to find any scale with class ID matching override class ID
		for scaleName, scale in pairs(PawnCommon.Scales) do
			if overrideClassID == scale.ClassID
			and scale.Values
			and next(scale.Values) then
				return cacheAndReturn(scaleName, scale.LocalizedName)
			end
		end

		-- Try to find any scale with name containing just the override localized class name (example: "Paladin")
		for scaleName, scale in pairs(PawnCommon.Scales) do
			if string.find(scaleName, overrideLocalizedClass)
			and scale.Values
			and next(scale.Values) then
				return cacheAndReturn(scaleName, scale.LocalizedName)
			end
		end

		-- Try to find any scale with name containing just the override class name (example: "PALADIN")
		for scaleName, scale in pairs(PawnCommon.Scales) do
			if string.find(scaleName, overrideClass)
			and scale.Values
			and next(scale.Values) then
				return cacheAndReturn(scaleName, scale.LocalizedName)
			end
		end

	end

	local realClassAndSpec = realLocalizedClass..": "..realSpec

	-- Try to find a visible scale matching the real class and spec string (example: "Warrior: Arms")
	for scaleName, scale in pairs(PawnCommon.Scales) do
		if PawnIsScaleVisible(scaleName)
		and realClassAndSpec == scaleName
		and scale.Values
		and next(scale.Values) then
			return cacheAndReturn(scaleName, scale.LocalizedName)
		end
	end

	-- Try to find a visible scale matching the real localized class and spec string (example: "Warrior: Arms")
	for scaleName, scale in pairs(PawnCommon.Scales) do
		if PawnIsScaleVisible(scaleName)
		and realClassAndSpec == scale.LocalizedName
		and scale.Values
		and next(scale.Values) then
			return cacheAndReturn(scaleName, scale.LocalizedName)
		end
	end

	-- Try to find a visible scale with matching real class ID and with localized name containing the real spec name (example: "Arms")
	for scaleName, scale in pairs(PawnCommon.Scales) do
		if PawnIsScaleVisible(scaleName)
		and scale.ClassID == realClassID
		and scale.LocalizedName
		and string.find(scale.LocalizedName, realSpec)
		and scale.Values
		and next(scale.Values) then
			return cacheAndReturn(scaleName, scale.LocalizedName)
		end
	end

	-- Try to find a visible scale matching just the real spec name (example: "Arms")
	for scaleName, scale in pairs(PawnCommon.Scales) do
		if PawnIsScaleVisible(scaleName)
		and realSpec == scaleName
		and scale.Values
		and next(scale.Values) then
			return cacheAndReturn(scaleName, scale.LocalizedName)
		end
	end

	-- Try to find a visible scale matching just the real class name (example: "Warrior")
	for scaleName, scale in pairs(PawnCommon.Scales) do
		if PawnIsScaleVisible(scaleName)
		and realLocalizedClass == scaleName
		and scale.Values
		and next(scale.Values) then
			return cacheAndReturn(scaleName, scale.LocalizedName)
		end
	end

	-- Try to find any scale matching the real class and spec string (example: "Warrior: Arms")
	for scaleName, scale in pairs(PawnCommon.Scales) do
		if realClassAndSpec == scaleName
		and scale.Values
		and next(scale.Values) then
			return cacheAndReturn(scaleName, scale.LocalizedName)
		end
	end

	-- Try to find any scale matching the real localized class and spec string (example: "Warrior: Arms")
	for scaleName, scale in pairs(PawnCommon.Scales) do
		if realClassAndSpec == scale.LocalizedName
		and scale.Values
		and next(scale.Values) then
			return cacheAndReturn(scaleName, scale.LocalizedName)
		end
	end

	-- Try to find any scale matching just the real spec name (example: "Arms")
	for scaleName, scale in pairs(PawnCommon.Scales) do
		if realSpec == scaleName
		and scale.Values
		and next(scale.Values) then
			return cacheAndReturn(scaleName, scale.LocalizedName)
		end
	end

	-- Try to find any scale matching just the real localized class name (example: "Warrior")
	for scaleName, scale in pairs(PawnCommon.Scales) do
		if realLocalizedClass == scaleName
		and scale.Values
		and next(scale.Values) then
			return cacheAndReturn(scaleName, scale.LocalizedName)
		end
	end

	-- Try to find the matching class with the matching real spec in the localized scale name
	for scaleName, scale in pairs(PawnCommon.Scales) do
		if scale.ClassID == realClassID
		and scale.LocalizedName
		and string.find(scale.LocalizedName, realSpec)
		and scale.Values
		and next(scale.Values) then
			return cacheAndReturn(scaleName, scale.LocalizedName)
		end
	end

	-- Try to find the matching class with the matching real spec in the scale name
	for scaleName, scale in pairs(PawnCommon.Scales) do
		if scale.ClassID == realClassID
		and string.find(scaleName, realSpec)
		and scale.Values
		and next(scale.Values) then
			return cacheAndReturn(scaleName, scale.LocalizedName)
		end
	end

	-- Try to find the matching real class
	for scaleName, scale in pairs(PawnCommon.Scales) do
		if scale.ClassID == realClassID
		and scale.Values
		and next(scale.Values) then
			return cacheAndReturn(scaleName, scale.LocalizedName)
		end
	end

	-- Use the first visible
	for scaleName, scale in pairs(PawnCommon.Scales) do
		if PawnIsScaleVisible(scaleName)
		and scale.Values
		and next(scale.Values) then
			return cacheAndReturn(scaleName, scale.LocalizedName)
		end
	end

	-- Just use the first one that has values
	for ScaleName, Scale in pairs(PawnCommon.Scales) do
		if Scale.Values and next(Scale.Values) then
			return cacheAndReturn(ScaleName, Scale.LocalizedName)
		end
	end
end

function TyGearGetWeaponType(itemClassID, itemSubClassID)
	--ask WoW what type of weapon it is
	if (itemClassID == Enum.ItemClass.Weapon) or ((itemClassID == Enum.ItemClass.Armor) and (itemSubClassID == Enum.ItemArmorSubclass.Shield)) then
		return itemSubClassID
	end
end

function TyGearDetermineItemScore(info, gearSlot)
	if info.empty then return 0 end
	-- Slot matters for dual-wield OH swing EP; TABARD (virtual 2H) uses MH weights.
	local scoreSlot = gearSlot
	if scoreSlot == INVSLOT_TABARD then
		scoreSlot = INVSLOT_MAINHAND
	end
	local cacheKey = info.link or info.guid or info.id
	if cacheKey and scoreSlot and info.classID == Enum.ItemClass.Weapon then
		cacheKey = cacheKey..":"..tostring(scoreSlot)
	end
	if cacheKey and TyGearScoreCache[cacheKey] ~= nil then
		return TyGearScoreCache[cacheKey]
	end
	local function storeScore(score)
		if cacheKey then
			TyGearScoreCache[cacheKey] = score
		end
		return score
	end
	if info.classID == Enum.ItemClass.Container then
		-- Bags are scored by how many slots they add. Dedicated reagent bags and Forever
		-- profession/soul bags (reagent-slot fillers) use the real slot count so a Mining Pack
		-- shows as 4, not 0.00. Other specialized bags only beat an empty normal bag slot.
		if info.subclassID == 0
		or info.isReagentBag
		or TyGearIsReagentBag(info)
		or TyGearUsesReagentBagSlot(info) then
			return storeScore(info.numBagSlots or 0)
		else
			return storeScore((info.numBagSlots or 0) * E) -- specialized bags suck, so consider them only better than nothing
		end
	elseif info.isAmmoBag and info.numBagSlots and (UnitClassBase("player") == "HUNTER") then
		return storeScore(info.numBagSlots + (info.ammoBagRangedAttackSpeed and info.ammoBagRangedAttackSpeed or 0))
	end

	if TyGearUsingPawn() then
		local pawnItemData = PawnGetItemData(info.link)
		if pawnItemData then
			local score = PawnGetSingleValueFromItem(pawnItemData, TyGearGetPawnScaleName()) or 0
			-- Gear is never worth a negative score.
			if score < 0 then
				score = 0
			end
			if score == 0 then
				return storeScore(E)
			else
				return storeScore(score)
			end
		end
	end

	-- This error trap sucks, but execution can reach here with no TyGearCurrentWeighting and I don't know how
	if (not TyGearCurrentWeighting) then
		TyGearSetStatWeights()
		if (not TyGearCurrentWeighting) then return storeScore(0) end
	end

	-- Green/white stats from GetItemStats + tooltip. Weapon swing EP is separate (base damage/speed).
	local score = (TyGearCurrentWeighting.Strength or 0) * (info.Strength or 0) +
		(TyGearCurrentWeighting.Agility or 0) * (info.Agility or 0) +
		(TyGearCurrentWeighting.Stamina or 0) * (info.Stamina or 0) +
		(TyGearCurrentWeighting.Intellect or 0) * (info.Intellect or 0) +
		(TyGearCurrentWeighting.Spirit or 0) * (info.Spirit or 0) +
		(TyGearCurrentWeighting.Armor or 0) * (info.Armor or 0) +
		(TyGearCurrentWeighting.Dodge or 0) * (info.Dodge or 0) +
		(TyGearCurrentWeighting.Parry or 0) * (info.Parry or 0) +
		(TyGearCurrentWeighting.Block or 0) * (info.Block or 0) +
		(TyGearCurrentWeighting.Defense or 0) * (info.Defense or 0) +
		(TyGearCurrentWeighting.SpellPower or 0) * (info.SpellPower or 0) +
		(TyGearCurrentWeighting.SpellPenetration or 0) * (info.SpellPenetration or 0) +
		(TyGearCurrentWeighting.Haste or 0) * (info.Haste or 0) +
		(TyGearCurrentWeighting.Mp5 or 0) * (info.Mp5 or 0) +
		(TyGearCurrentWeighting.AttackPower or 0) * (info.AttackPower or 0) +
		(TyGearCurrentWeighting.ArmorPenetration or 0) * (info.ArmorPenetration or 0) +
		(TyGearCurrentWeighting.Crit or 0) * (info.Crit or 0) +
		(TyGearCurrentWeighting.SpellCrit or 0) * (info.SpellCrit or 0) +
		(TyGearCurrentWeighting.Hit or 0) * (info.Hit or 0) +
		(TyGearCurrentWeighting.SpellHit or 0) * (info.SpellHit or 0) +
		(TyGearCurrentWeighting.Expertise or 0) * (info.Expertise or 0) +
		(TyGearCurrentWeighting.RedSockets or 0) * (info.RedSockets or 0) +
		(TyGearCurrentWeighting.YellowSockets or 0) * (info.YellowSockets or 0) +
		(TyGearCurrentWeighting.BlueSockets or 0) * (info.BlueSockets or 0) +
		(TyGearCurrentWeighting.MetaSockets or 0) * (info.MetaSockets or 0) +
		(TyGearCurrentWeighting.Mastery or 0) * (info.Mastery or 0) +
		(TyGearCurrentWeighting.Multistrike or 0) * (info.Multistrike or 0) +
		(TyGearCurrentWeighting.Versatility or 0) * (info.Versatility or 0) +
		((UnitLevel("player") < maxPlayerLevel and not (IsXPUserDisabled and IsXPUserDisabled())) and
		(TyGearCurrentWeighting.ExperienceGained or 0) * (info.ExperienceGained or 0) or 0)

	if TyGearCurrentWeighting.weapon then
		score = score + TyGearGetWeaponSwingEP(info, scoreSlot)
	else
		score = score
			+ (TyGearCurrentWeighting.DPS or 0) * (info.DPS or 0)
			+ (TyGearCurrentWeighting.Damage or 0) * (info.Damage or 0)
	end

	-- Gear is never worth a negative score (speed penalties and negative weights included).
	if score < 0 then
		score = 0
	end
	if score == 0 then
		return storeScore(E)
	else
		return storeScore(score or 0)
	end
end

function TyGearInventoryItemIs(itemID, slot)
	if not itemID or not slot or not GetInventoryItemID then return false end
	local id = GetInventoryItemID("player", slot)
	if not id or (issecretvalue and issecretvalue(id)) then return false end
	return id == itemID
end

-- Item ids in the bag slots before an equip attempt. false means the slot was read and empty.
-- A second copy of the same bag already worn in a normal slot must not look like the one we just moved.
function TyGearSnapshotEquippedBags()
	local snap = {}
	local function take(slot)
		if not slot or snap[slot] ~= nil or not GetInventoryItemID then return end
		local id = GetInventoryItemID("player", slot)
		if issecretvalue and issecretvalue(id) then return end
		snap[slot] = id or false
	end
	local first = TyGearFirstEquippableBagSlot
	if type(first) == "number" then
		for id = first, first + 3 do
			take(id)
		end
	end
	-- Classic bag ids are 20-23. Current clients use 31-34. Record both so a bag that lands in the other range is visible.
	for id = 20, 23 do
		take(id)
	end
	for id = 31, 34 do
		take(id)
	end
	for _, id in ipairs(TyGearEquippableBagSlots) do
		take(id)
	end
	for _, id in ipairs(TyGearReagentBagSlotCandidates()) do
		take(id)
	end
	take(TyGearReagentBagSlot)
	return snap
end

function TyGearBagSlotNewlyHolds(itemID, slot, before)
	if not TyGearInventoryItemIs(itemID, slot) then return false end
	if not before then return true end
	return before[slot] ~= itemID
end

-- Where a reagent bag just landed when PutItemInBag was given the wrong id.
function TyGearFindRegularBagSlotHolding(itemID, before)
	if not itemID then return nil end
	local first = TyGearFirstEquippableBagSlot
	if type(first) == "number" then
		for id = first, first + 3 do
			if id ~= TyGearReagentBagSlot and TyGearBagSlotNewlyHolds(itemID, id, before) then
				return id
			end
		end
	end
	for _, id in ipairs(TyGearEquippableBagSlots) do
		if id ~= TyGearReagentBagSlot and TyGearBagSlotNewlyHolds(itemID, id, before) then
			return id
		end
	end
	for id = 20, 23 do
		if id ~= TyGearReagentBagSlot and TyGearBagSlotNewlyHolds(itemID, id, before) then
			return id
		end
	end
	for id = 31, 34 do
		if id ~= TyGearReagentBagSlot and TyGearBagSlotNewlyHolds(itemID, id, before) then
			return id
		end
	end
end

function TyGearReagentTriedSuffix(tried)
	if type(tried) ~= "table" then return "" end
	local ids = {}
	for id in pairs(tried) do
		if type(id) == "number" then
			table.insert(ids, id)
		end
	end
	if not ids[1] then return "" end
	table.sort(ids)
	local parts = {}
	for i, id in ipairs(ids) do
		parts[i] = tostring(id)
	end
	return " Tried inventory slot "..table.concat(parts, ", ").."."
end

-- Put the cursor item into the reagent bag slot. A wrong id equips it in a normal bag; pick that back up and try the next id.
-- Returns true (landed), "pending" (cursor empty, slot not updated yet), or false (still on the cursor, or back on the cursor).
function TyGearTryPutReagentBag(info, tried, before)
	if not info or not PutItemInBag then return false end
	tried = tried or {}
	local function cursorHasItem()
		return CursorHasItem and CursorHasItem()
	end
	local function cursorStillHoldsBag()
		if not cursorHasItem() then return false end
		if not GetCursorInfo then return true end
		local cursorType, cursorID = GetCursorInfo()
		if issecretvalue and (issecretvalue(cursorType) or issecretvalue(cursorID)) then
			return true
		end
		if cursorType == "item" then
			return cursorID == info.id
		end
		return true
	end
	-- PutItemInBag(35) is the reagent bag slot on WoW Forever. Try it before any other id,
	-- and do not pick the bag back up when the cursor no longer holds it.
	local provenID = 35
	if not tried[provenID] and cursorHasItem() then
		tried[provenID] = true
		PutItemInBag(provenID)
		if TyGearInventoryItemIs(info.id, provenID) or not cursorStillHoldsBag() then
			TyGearAdoptReagentBagSlot(provenID)
			return true
		end
	end
	if IS_WOW_FOREVER then
		return false
	end
	local function reagentSlotHolding()
		for _, id in ipairs(TyGearReagentBagSlotCandidates()) do
			-- A normal bag slot is not a successful reagent equip, even if a bad id just put the bag there.
			if not TyGearSlotIsKnownNormalBag(id) and TyGearBagSlotNewlyHolds(info.id, id, before) then
				return id
			end
		end
	end
	local function accept(id)
		TyGearAdoptReagentBagSlot(id)
		return true
	end
	local function pullOutOfRegularSlot()
		local wrong = TyGearFindRegularBagSlotHolding(info.id, before)
		if wrong and PickupInventoryItem then
			PickupInventoryItem(wrong)
			return true
		end
		return false
	end
	-- nil means keep trying. true means the bag is in a reagent-slot id. "pending" means the cursor is empty and the slot has not updated yet.
	local function afterPut(id)
		local holding = reagentSlotHolding()
		if holding then
			return accept(holding)
		end
		if pullOutOfRegularSlot() then
			return nil
		end
		if not cursorHasItem() then
			return "pending", id
		end
	end

	local button = TyGearReagentBagButton
	if button and button.PutItemInBag then
		local id = TyGearButtonPutID(button)
		if id and not tried[id] and cursorHasItem() then
			tried[id] = true
			pcall(button.PutItemInBag, button)
			local result, pendingID = afterPut(id)
			if result ~= nil then
				return result, pendingID
			end
		end
	end

	local pendingID
	for _, id in ipairs(TyGearReagentBagSlotCandidates()) do
		if not tried[id] then
			if not cursorHasItem() then
				local holding = reagentSlotHolding()
				if holding then return accept(holding) end
				return false
			end
			tried[id] = true
			PutItemInBag(id)
			local result, pending = afterPut(id)
			if result == true then return true end
			if result == "pending" then
				pendingID = pending
				break
			end
		end
	end
	local holding = reagentSlotHolding()
	if holding then return accept(holding) end
	if pendingID then
		return "pending", pendingID
	end
	return false
end

-- Equipping one bag shifts bag contents; re-find the item by id before the next pickup.
function TyGearFindBagItemLocation(itemID, preferredBag, preferredSlot)
	itemID = tonumber(itemID)
	if not itemID or not GetContainerItemID then return end
	if preferredBag and preferredSlot and GetContainerItemID(preferredBag, preferredSlot) == itemID then
		return preferredBag, preferredSlot
	end
	for bag = 0, TyGearGetLastBagToScan() do
		for slot = 1, (GetContainerNumSlots(bag) or 0) do
			if GetContainerItemID(bag, slot) == itemID then
				return bag, slot
			end
		end
	end
end

function TyGearRefreshActionBagLocation(curAction)
	if not curAction or not curAction.info or not curAction.info.id then return end
	local bag, slot = TyGearFindBagItemLocation(curAction.info.id, curAction.container, curAction.slot)
	if bag and slot then
		curAction.container = bag
		curAction.slot = slot
		return true
	end
end

function TyGearReturnCursorItem(curAction)
	if not (CursorHasItem and CursorHasItem()) and curAction and curAction.info then
		local wrong = TyGearFindRegularBagSlotHolding(curAction.info.id, curAction.bagSnapshot)
		if wrong then
			PickupInventoryItem(wrong)
		end
	end
	if not (CursorHasItem and CursorHasItem()) then return end
	if curAction and curAction.container and curAction.slot and not TyGearGetContainerItemInfo(curAction.container, curAction.slot) then
		PickupContainerItem(curAction.container, curAction.slot)
		if not (CursorHasItem and CursorHasItem()) then return end
	end
	if curAction and curAction.reagentSourceSlot and PutItemInBag and not (curAction.info and TyGearIsReagentBag(curAction.info)) then
		PutItemInBag(curAction.reagentSourceSlot)
		if not (CursorHasItem and CursorHasItem()) then return end
	end
	TyGearStashCursorItem()
end

-- EquipCursorItem on a bag uses the first open regular bag slot.
-- PutItemInBag targets the bag slot itself. Reagent bags never use EquipCursorItem.
function TyGearPlaceCursorItem(slot, info)
	if slot and TyGearGetContainerForEquippedBagSlot(slot) and PutItemInBag then
		PutItemInBag(slot)
	elseif info and TyGearIsReagentBag(info) then
		return
	else
		EquipCursorItem(slot)
	end
end

function TyGearEquipActionBag(curAction, putBack)
	local info = curAction and curAction.info
	--Only the reagent slot uses the reagent button id. A reagent bag aimed at a normal slot uses that slot.
	if (curAction.reagentEquip or curAction.replaceSlot == TyGearReagentBagSlot) and info and (TyGearIsReagentBag(info) or TyGearUsesReagentBagSlot(info)) then
		curAction.reagentEquip = true
		TyGearRefreshReagentBagSlot()
		if not TyGearReagentBagSlot then
			if CursorHasItem and CursorHasItem() and putBack then
				putBack()
			end
			return false
		end
		curAction.reagentTried = curAction.reagentTried or {}
		curAction.bagSnapshot = curAction.bagSnapshot or TyGearSnapshotEquippedBags()
		local result, pendingID = TyGearTryPutReagentBag(info, curAction.reagentTried, curAction.bagSnapshot)
		if result == true then
			curAction.replaceSlot = TyGearReagentBagSlot
			return true
		end
		if result == "pending" then
			curAction.replaceSlot = pendingID or TyGearReagentBagSlot
			return true
		end
		if CursorHasItem and CursorHasItem() then
			if putBack then
				putBack()
			end
			if CursorHasItem and CursorHasItem() then
				TyGearReturnCursorItem(curAction)
			end
		end
		return false
	end
	TyGearPlaceCursorItem(curAction.replaceSlot, info)
	if not TyGearGetContainerForEquippedBagSlot(curAction.replaceSlot) then
		return true
	end
	return TyGearResolveBagCursor(info, putBack)
end

-- Put a displaced item into a bag. PutItemInBag would equip a bag, so this only fills empty slots.
function TyGearStashCursorItem()
	if not (CursorHasItem and CursorHasItem()) then return end
	if GetContainerNumFreeSlots(BACKPACK_CONTAINER) > 0 and PutItemInBackpack then
		PutItemInBackpack()
		if not (CursorHasItem and CursorHasItem()) then return end
	end
	for bag = 1, (NUM_BAG_SLOTS or 0) do
		if CursorHasItem and not CursorHasItem() then return end
		local freeSlots, bagType = GetContainerNumFreeSlots(bag)
		if bagType == 0 and freeSlots > 0 then
			for slot = 1, (GetContainerNumSlots(bag) or 0) do
				if not TyGearGetContainerItemInfo(bag, slot) then
					PickupContainerItem(bag, slot)
					return
				end
			end
		end
	end
end

-- true when the bag landed in replaceSlot. A cursor still holding that same item is put back by putBack.
function TyGearResolveBagCursor(info, putBack)
	if not (CursorHasItem and CursorHasItem()) then return true end
	local cursorType, cursorID = nil, nil
	if GetCursorInfo then
		cursorType, cursorID = GetCursorInfo()
	end
	if issecretvalue and (issecretvalue(cursorType) or issecretvalue(cursorID)) then
		TyGearStashCursorItem()
		return true
	end
	if cursorType == "item" and info and cursorID == info.id then
		if putBack then putBack() end
		return false
	end
	TyGearStashCursorItem()
	return true
end

function TyGearBagEquipSlotName(slot)
	if TyGearReagentBagSlot and slot == TyGearReagentBagSlot then
		return "reagent bag slot"
	end
	return "bag slot"
end

function TyGearGetAllBagsNumFreeSlots()
	local slotCount = 0
	for i = 0, NUM_BAG_SLOTS do
		local freeSlots, bagType = GetContainerNumFreeSlots(i)
		if (bagType == 0) then
			slotCount = slotCount + freeSlots
		end
	end
	return slotCount
end

function TyGearPutItemInEmptyBagSlot()
	if GetContainerNumFreeSlots(BACKPACK_CONTAINER) > 0 then PutItemInBackpack() end
	for i = 1, NUM_BAG_SLOTS do
		local freeSlots, bagType = GetContainerNumFreeSlots(i)
		if (bagType == 0 and freeSlots > 0) then
			PutItemInBag(CONTAINER_BAG_OFFSET+i)
		end
	end
end

function TyGearScan()
	TyGearSetStatWeights()
	if (not TyGearCurrentWeighting) then
		local localizedClass, class, spec = TyGearGetClassAndSpec()
		TyGearPrint("TyGear: No weighting set for "..RAID_CLASS_COLORS[class]:WrapTextInColorCode(spec.." "..localizedClass)..".", 0)
		return
	end
	TyGearPrint("TyGear: Scanning bags for upgrades.", 2)
	if (not TyGearConsiderAllItems()) then
		TyGearPrint("TyGear: Nothing better was found", 1)
	end
end

--[[ TyGearRecursivePrint(struct, [limit], [indent])   Recursively print arbitrary data.
	Set limit (default 100) to stanch infinite loops.
	Indents tables as [KEY] VALUE, nested tables as [KEY] [KEY]...[KEY] VALUE
	Set indent ("") to prefix each line:    Mytable [KEY] [KEY]...[KEY] VALUE
--]]
function TyGearRecursivePrint(s, l, i) -- recursive Print (structure, limit, indent)
	l = (l) or 100; i = i or ""	-- default item limit, indent string
	if (l<1) then print "ERROR: Item limit reached."; return l-1 end;
	local ts = type(s);
	if (ts ~= "table") then print (i,ts,s); return l-1 end
	print (i,ts);           -- print "table"
	for k,v in pairs(s) do  -- print "[KEY] VALUE"
		l = TyGearRecursivePrint(v, l, i.."["..tostring(k).."]");
		if (l < 0) then break end
	end
	return l
end

local function localDump(o)
	if type(o) == 'table' then
		local s = '{' .. string.char(10)
		for k,v in pairs(o) do
			if type(k) == 'string' then k = '"'..k..'"' end
			s = '  ' .. s .. '['..tostring(k)..'] = ' .. localDump(v) .. ',' .. string.char(10)
		end
		return s .. '}' .. string.char(10)
	else
		return tostring(o)
	end
end

function TyGearDump(o)
	TyGearPrint(localDump(o))
end

function TyGearGetTooltipScoreComparisonInfo(info, equipped)
	local lowestScoringValidGearSlot
	local lowestScoringValidGearInfo = info
	local equippedSetScore = 0
	for i=1,(info.numValidGearSlots or 0) do
		equippedSetScore = equippedSetScore + (TyGearEquippedItems[info.validGearSlots[i]].score or 0)
	end
	-- Candidate score is filled after the target slot is known (OH uses oh_dps).
	local lowestScoringValidGearSlotScore
	if info.is2hWeapon and (not (CanDualWield() and IsPlayerSpell(46917))) then
		local mainHandInfo, mainHandScore, offHandScore
		if TyGearEquippedItems and TyGearEquippedItems[INVSLOT_MAINHAND] and TyGearEquippedItems[INVSLOT_OFFHAND] then
			-- Prefer pretended 2H tabard slot when present
			if TyGearEquippedItems[INVSLOT_TABARD] and TyGearEquippedItems[INVSLOT_TABARD].info and not TyGearEquippedItems[INVSLOT_TABARD].info.empty then
				mainHandInfo = TyGearEquippedItems[INVSLOT_TABARD].info
				mainHandScore = TyGearEquippedItems[INVSLOT_TABARD].score or 0
				offHandScore = 0
			else
				mainHandInfo = TyGearEquippedItems[INVSLOT_MAINHAND].info
				mainHandScore = TyGearEquippedItems[INVSLOT_MAINHAND].score or 0
				offHandScore = TyGearEquippedItems[INVSLOT_OFFHAND].score or 0
			end
		else
			mainHandInfo = TyGearReadItemInfo(INVSLOT_MAINHAND)
			mainHandScore = TyGearDetermineItemScore(mainHandInfo, INVSLOT_MAINHAND)
			offHandScore = TyGearDetermineItemScore(TyGearReadItemInfo(INVSLOT_OFFHAND), INVSLOT_OFFHAND)
		end
		local oneHandedWeaponsScore = mainHandScore + offHandScore
		lowestScoringValidGearInfo = mainHandInfo
		lowestScoringValidGearSlot = INVSLOT_MAINHAND
		lowestScoringValidGearSlotScore = oneHandedWeaponsScore
		equippedSetScore = oneHandedWeaponsScore
	elseif info.is1hWeaponOrOffHand
	and TyGearIsTwoHandEquipped() then
		if TyGearEquippedItems and TyGearEquippedItems[INVSLOT_TABARD] and TyGearEquippedItems[INVSLOT_TABARD].info and not TyGearEquippedItems[INVSLOT_TABARD].info.empty then
			lowestScoringValidGearInfo = TyGearEquippedItems[INVSLOT_TABARD].info
			lowestScoringValidGearSlotScore = TyGearEquippedItems[INVSLOT_TABARD].score or 0
		elseif TyGearEquippedItems and TyGearEquippedItems[INVSLOT_MAINHAND] then
			lowestScoringValidGearInfo = TyGearEquippedItems[INVSLOT_MAINHAND].info
			lowestScoringValidGearSlotScore = TyGearEquippedItems[INVSLOT_MAINHAND].score or 0
		else
			lowestScoringValidGearInfo = TyGearReadItemInfo(INVSLOT_MAINHAND)
			lowestScoringValidGearSlotScore = TyGearDetermineItemScore(lowestScoringValidGearInfo, INVSLOT_MAINHAND)
		end
		lowestScoringValidGearSlot = INVSLOT_MAINHAND
		equippedSetScore = lowestScoringValidGearSlotScore
	else
		if info.validGearSlots then
			local firstOpenSlot
			for _, gearSlot in ipairs(info.validGearSlots) do
				if not TyGearIsGearSlotProtected(gearSlot) then
					firstOpenSlot = gearSlot
					break
				end
			end
			local firstValidGearSlot = firstOpenSlot or info.validGearSlots[1]
			lowestScoringValidGearSlot = firstValidGearSlot
			lowestScoringValidGearSlotScore = TyGearEquippedItems[firstValidGearSlot].score
			lowestScoringValidGearInfo = TyGearEquippedItems[firstValidGearSlot].info
			for _, gearSlot in ipairs(info.validGearSlots) do
				if not TyGearIsGearSlotProtected(gearSlot) then
				local skipThisSlot = false
				for _, otherGearSlot in pairs(info.validGearSlots) do
					if gearSlot ~= otherGearSlot then
						if not TyGearIsGearPairEquippableTogether(info, TyGearEquippedItems[otherGearSlot].info) then
							skipThisSlot = true
						end
					end
				end
				local equippedHere = TyGearEquippedItems[gearSlot]
				local equippedInfo = equippedHere and equippedHere.info
				local equippedScore = equippedHere and equippedHere.score
				local takeThisSlot = false
				if equippedInfo and (equippedInfo.empty or (not equippedScore) or (equippedScore < lowestScoringValidGearSlotScore)) then
					takeThisSlot = true
				elseif equippedInfo and equippedScore == lowestScoringValidGearSlotScore then
					if info.classID == Enum.ItemClass.Container then
						takeThisSlot = TyGearPreferToDisplaceBag(equippedInfo, lowestScoringValidGearInfo)
					else
						takeThisSlot = true
					end
				end
				if (not skipThisSlot) and takeThisSlot then
					lowestScoringValidGearInfo = equippedInfo
					lowestScoringValidGearSlot = gearSlot
					lowestScoringValidGearSlotScore = equippedScore
				end
				end
			end
		end
	end
	return lowestScoringValidGearInfo, lowestScoringValidGearSlotScore, lowestScoringValidGearSlot, equippedSetScore
end

function TyGearGetOppositeHandSlot(invSlot)
	if (invSlot ~= INVSLOT_MAINHAND) and (invSlot ~= INVSLOT_OFFHAND) then return end
	return (invSlot == INVSLOT_MAINHAND and INVSLOT_OFFHAND or INVSLOT_MAINHAND)
end

function TyGearIsGearPairEquippableTogether(a, b)
	if (not a) or (not b) or a.empty or b.empty then return 1 end
	if (not a.validGearSlots)
	or (not b.validGearSlots)
	or (a.guid == b.guid)
	or ((a.id == b.id)
	and ((GetItemCount(a.id, true) < 2)
	or (a.unique)))
	or (a.uniqueType and (a.uniqueType == b.uniqueType) and (a.numEquippable < 2) and (b.numEquippable < 2))
	or (a.ammoBagRangedAttackSpeed and b.ammoBagRangedAttackSpeed)
	or ((a.is1hWeaponOrOffHand and b.is1hWeaponOrOffHand)
	and (
		((weapons == "dagger and any")
		and (a.subclassID ~= Enum.ItemWeaponSubclass.Dagger)
		and (b.subclassID ~= Enum.ItemWeaponSubclass.Dagger))
		or ((weapons == "weapon and shield")
		and (a.subclassID ~= Enum.ItemArmorSubclass.Shield)
		and (b.subclassID ~= Enum.ItemArmorSubclass.Shield))
	)) then
		-- TyGearPrint("AG: "..a.link.." ("..(a.guid or "missing guid")..") and "..b.link.." ("..(b.guid or "missing guid")..") are not equippable together", 3)
		return
	end
	for _, firstSlot in pairs(a.validGearSlots) do
		for _, secondSlot in pairs(b.validGearSlots) do
			if (firstSlot ~= secondSlot)
			and (not (((firstSlot == INVSLOT_MAINHAND)
			or (firstSlot == INVSLOT_OFFHAND))
			and (secondSlot == INVSLOT_TABARD)))
			and (not ((firstSlot == INVSLOT_TABARD)
			and ((secondSlot == INVSLOT_MAINHAND)
			or (secondSlot == INVSLOT_OFFHAND))))
			then
				-- TyGearPrint("AG: "..a.link.." ("..(a.guid or "missing guid")..") and "..b.link.." ("..(b.guid or "missing guid")..") are equippable together", 3)
				return 1
			end
		end
	end
end

function TyGearGetBestSetItems(info)
	-- Never trigger a full bag scan from tooltip hover; fall back to equipped scores
	local bestSource = TyGearBestItems or TyGearEquippedItems
	if not bestSource then
		return {}, 0, nil, 0
	end
	local setSlots = TyGearGetSetSlots(info)
	if not setSlots then
		return {}, 0, nil, 0
	end
	-- Choose the slot this item would take: prefer empty, else the lowest-scoring valid slot.
	-- Pairing is everything else in the set — never drop the main-hand when the off-hand is empty.
	local replaceSlots = info.validGearSlots or setSlots
	local replaceSlot
	local replaceScore
	local thisIsABestItem
	for _, slot in ipairs(replaceSlots) do
		local slotBest = bestSource[slot]
		local empty = (not slotBest) or (not slotBest.info) or slotBest.info.empty
		local score = empty and 0 or (slotBest.score or 0)
		local bestInfo = slotBest and slotBest.info
		local isThis = bestInfo and (
			(bestInfo.link and info.link and bestInfo.link == info.link)
			or (info.guid and bestInfo.guid and bestInfo.guid == info.guid)
		)
		if isThis then
			thisIsABestItem = 1
		end
		if empty then
			replaceSlot = slot
			replaceScore = 0
			break
		elseif (not replaceSlot) or score < replaceScore then
			replaceSlot = slot
			replaceScore = score
		end
	end
	local bestSet = {}
	local bestSetScore = 0
	for _, slot in ipairs(setSlots) do
		if slot ~= replaceSlot then
			local slotBest = bestSource[slot]
			if slotBest and slotBest.info and (not slotBest.info.empty)
			and TyGearIsGearPairEquippableTogether(info, slotBest.info) then
				table.insert(bestSet, slotBest)
				bestSetScore = bestSetScore + (slotBest.score or 0)
			end
		end
	end
	return bestSet, bestSetScore, thisIsABestItem, replaceScore or 0
end

function TyGearDetectHoveredItemGUID()
	local focus = GetMouseFocus()
	if (not focus) or (focus:GetObjectType() ~= "Button") then return end
	local focusParent = focus.GetParent and focus:GetParent()
	if not focusParent then return end
	local focusParentName = focusParent.GetName and focusParent:GetName()
	if not focusParentName then return end
	if focusParentName:match("PaperDoll") then
		local item = Item:CreateFromEquipmentSlot(focus:GetID())
		if (not item) or (not item.IsItemEmpty) or item:IsItemEmpty() then return end
		return item:GetItemGUID()
	elseif (
		focusParentName:match("Inv") or
		focusParentName:match("Bag") or
		focusParentName:match("Container")
	) then
		local item = Item:CreateFromBagAndSlot(focusParent:GetID(), focus:GetID())
		if (not item) or (not item.IsItemEmpty) or item:IsItemEmpty() then return end
		return item:GetItemGUID()
	end
end

function TyGearGetEquippedSlotFromItemGUID(guid)
	if not guid then return end
	for slot,item in pairs(TyGearEquippedItems) do
		if (item.info.guid == guid) and item.equipped then return slot end
	end
end

function TyGearTooltipHook(tooltip, tooltipData)
	if (not TyGearDB.ScoreInTooltips) then return end
	local tooltipName = tooltip:GetName()
	if (not (
		tooltipName=="GameTooltip"
		or tooltipName=="ShoppingTooltip1"
		or tooltipName=="ShoppingTooltip2"
		or tooltipName=="ItemRefTooltip"
		or tooltipName=="AtlasLootTooltip"
	)) then
		return
	end
	if (not TyGearCurrentWeighting) then TyGearSetStatWeights() end
	local isAComparisonTooltip = (tooltipName ~= "GameTooltip") and (tooltipName ~= "AtlasLootTooltip")
	local name, link, equipped, guid
	if tooltip.GetPrimaryTooltipData or tooltip.GetTooltipData then
		if not tooltipData then
			tooltipData = tooltip.GetPrimaryTooltipData and tooltip:GetPrimaryTooltipData() or (tooltip.GetTooltipData and tooltip:GetTooltipData())
		end
		if not tooltipData then tooltip:AddDoubleLine("TyGear error:", "no tooltip data") return end
		guid = tooltipData.guid or ((not isAComparisonTooltip) and TyGearDetectHoveredItemGUID())
		name = tooltipData.lines[1].leftText
		link = tooltipData.hyperlink or (guid and C_Item.GetItemLinkByGUID(guid))
		equipped = guid and TyGearGetEquippedSlotFromItemGUID(guid)
	elseif tooltip.GetItem then
		name, link = tooltip:GetItem()
		guid = (not isAComparisonTooltip) and TyGearDetectHoveredItemGUID()
		equipped = tooltip.IsEquippedItem and tooltip:IsEquippedItem(tooltip) or (guid and TyGearGetEquippedSlotFromItemGUID(guid))
	end
	if not link then
		if not guid then
			tooltip:AddDoubleLine("TyGear tooltip error:", "no item link or GUID")
		end
		TyGearPrint("TyGear: No item link for "..(name or "(no name)").." on "..tooltipName,3)
		return
	end
	local info = TyGearReadItemInfo(nil,nil,nil,nil,link,tooltipData)

	if (not isAComparisonTooltip) and (not info.guid) then
		info.guid = guid
	end
	local pawnScaleName
	local pawnScaleLocalizedName
	local pawnScaleColor
	if TyGearUsingPawn() then
		pawnScaleName, pawnScaleLocalizedName = TyGearGetPawnScaleName()
		pawnScaleColor = PawnGetScaleColor(pawnScaleName)
	end
	local lowestScoringEquippedItemInfo
	local lowestScoringEquippedItemScore
	local lowestScoringEquippedItemSlot
	local equippedSetScore
	local score
	local bestSetScore
	local scoreWithBestSet
	local bestSet
	local scoreColor = HIGHLIGHT_FONT_COLOR
	if info.shouldShowScoreInTooltip then
		-- Weapon/off-hand "this and best pairing" is only meaningful against a two-hander.
		-- Shields into an empty off-hand compare as a single slot, not against the main-hand.
		local pairedAgainstTwoHand = info.is1hWeaponOrOffHand and TyGearIsTwoHandEquipped()
		local multiSlotNonWeapon = (not info.is1hWeaponOrOffHand) and info.numValidGearSlots and info.numValidGearSlots > 1
		local shouldShowBestSet = (not isAComparisonTooltip) and (pairedAgainstTwoHand or multiSlotNonWeapon)
		lowestScoringEquippedItemInfo, lowestScoringEquippedItemScore, lowestScoringEquippedItemSlot, equippedSetScore = TyGearGetTooltipScoreComparisonInfo(info, equipped)
		local scoreGearSlot = lowestScoringEquippedItemSlot
			or (info.is2hWeapon and INVSLOT_MAINHAND)
			or (info.validGearSlots and info.validGearSlots[1])
		score = TyGearDetermineItemScore(info, scoreGearSlot)
		bestSet, bestSetScore = TyGearGetBestSetItems(info)
		scoreWithBestSet = score + (bestSetScore or 0)
		local isAnyComparisonTooltipVisible = ItemRefTooltip:IsVisible() or ShoppingTooltip1:IsVisible() or ShoppingTooltip2:IsVisible()
		local shouldShowComparisonLine = (not isAComparisonTooltip and (not isAnyComparisonTooltipVisible or TyGearDB.AlwaysShowScoreComparisons)) and not equipped
		local usePairScore = shouldShowBestSet
		local compareScore = usePairScore and scoreWithBestSet or score
		-- Empty/invalid slots leave the equipped score nil; treat as 0 so color compare never crashes.
		local compareAgainst = (usePairScore and equippedSetScore or lowestScoringEquippedItemScore) or 0
		if (compareScore > compareAgainst) and not info.ignored and not TyGearAllValidGearSlotsProtected(info) then
			scoreColor = GREEN_FONT_COLOR
		elseif (compareScore < compareAgainst) and not info.ignored then
			scoreColor = RED_FONT_COLOR
		end
		-- 3 decimal places max
		score = math.floor(score * 1000) / 1000
		bestSetScore = math.floor((bestSetScore or 0) * 1000) / 1000
		scoreWithBestSet = math.floor(scoreWithBestSet * 1000) / 1000
		equippedSetScore = math.floor((equippedSetScore or 0) * 1000) / 1000
		lowestScoringEquippedItemScore = math.floor((lowestScoringEquippedItemScore or 0) * 1000) / 1000
		local displayScore = usePairScore and scoreWithBestSet or score
		local displayEquipped = usePairScore and equippedSetScore or lowestScoringEquippedItemScore
		local scoreLinePrefix = TyGearGetTooltipScorePrefix()
		if shouldShowComparisonLine or shouldShowBestSet then
			local equippedLabel = "equipped"
			if pairedAgainstTwoHand then
				equippedLabel = "equipped (2h)"
			elseif multiSlotNonWeapon then
				equippedLabel = "equipped set"
			end
			tooltip:AddDoubleLine(scoreLinePrefix.." score ("..equippedLabel.."):",
			displayEquipped,
			HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b,
			HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)
		end
		local thisLabel = ""
		if shouldShowComparisonLine or shouldShowBestSet then
			if shouldShowBestSet then
				thisLabel = " (this and best "..((info.numValidGearSlots or 0) > 2 and "set" or "pairing")..")"
			else
				thisLabel = " (this)"
			end
		end
		tooltip:AddDoubleLine(scoreLinePrefix.." score"..thisLabel..":",
		(((info.unusable == 1) and (RED_FONT_COLOR_CODE.."(won't equip) "..FONT_COLOR_CODE_CLOSE) or "")..displayScore) or "nil",
		HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b,
		scoreColor.r, scoreColor.g, scoreColor.b)
		if (TyGearDB.ReasonsInTooltips == true) and info.unusable then
			tooltip:AddDoubleLine("TyGear: won't auto-equip",
			info.reason,
			RED_FONT_COLOR.r,RED_FONT_COLOR.g,RED_FONT_COLOR.b,
			RED_FONT_COLOR.r,RED_FONT_COLOR.g,RED_FONT_COLOR.b)
		end
		if shouldShowBestSet then
			local thisScore = math.floor(TyGearDetermineItemScore(info, scoreGearSlot) * 1000) / 1000
			tooltip:AddDoubleLine(scoreLinePrefix.." score (this; "..info.link.."):",
			tostring(thisScore or 0),
			HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b,
			scoreColor.r, scoreColor.g, scoreColor.b)
			for i=1,(#bestSet or 0) do
				if bestSet[i] and bestSet[i].info then
					tooltip:AddDoubleLine(scoreLinePrefix.." score (best "..((info.numValidGearSlots or 0) > 2 and "set item "..tostring(i) or "pairing").."; "..(bestSet[i].info.link or bestSet[i].info.name).."):",
					tostring(math.floor((bestSet[i].score or 0) * 1000) / 1000),
					HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b,
					HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)
				end
			end
		end
	end
	if (TyGearDB.DebugInfoInTooltips == true) then
		tooltip:AddDoubleLine(
			"TyGear: item GUID:",
			tostring(info.guid or (info.item and info.item:GetItemGUID()) or "nil"),
			HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b,
			HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b
		)
		tooltip:AddDoubleLine(
			"TyGear: item ID:",
			tostring(info.id or "nil"),
			HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b,
			HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b
		)
		tooltip:AddDoubleLine(
			"TyGear: item level:",
			tostring(GetDetailedItemLevelInfo(info.link) or "nil"),
			HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b,
			HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b
		)
		tooltip:AddDoubleLine(
			"TyGear: InventoryType:",
			tostring(info.invType or "nil"),
			HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b,
			HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b
		)
		if PawnIsReady and PawnIsReady() then
			local pawnScaleName, pawnScaleLocalizedName = TyGearGetPawnScaleName()
			tooltip:AddDoubleLine(
				"TyGear: Pawn scale name:",
				(pawnScaleName or "nil"),
				HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b,
				HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b
			)
			tooltip:AddDoubleLine(
				"TyGear: Pawn scale localized name:",
				(pawnScaleLocalizedName or "nil"),
				HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b,
				HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b
			)
			local pawnItemData = PawnGetItemData(info.link)
			tooltip:AddDoubleLine(
				"TyGear: Pawn value:",
				tostring(
					info and (
						info.link and (
							PawnCanItemHaveStats(info.link) and (
								pawnItemData and (
									PawnGetSingleValueFromItem(
										pawnItemData,TyGearGetPawnScaleName()
									) or "nil Pawn value"
								) or "nil Pawn item data"
							) or "Pawn says item can't have stats"
						) or "nil AG item link"
					) or "nil AG item info"
				),
				HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b,
				HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b
			)
		end
		tooltip:AddDoubleLine(
			"TyGear: info.is1hWeaponOrOffHand:",
			tostring(info.is1hWeaponOrOffHand or "nil"),
			HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b,
			HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b
		)
		tooltip:AddDoubleLine(
			"TyGear: info.is2hWeapon:",
			tostring(info.is2hWeapon or "nil"),
			HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b,
			HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b
		)
		tooltip:AddDoubleLine(
			"TyGear: item class ID:",
			tostring(info.classID or "nil"),
			HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b,
			HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b
		)
		tooltip:AddDoubleLine(
			"TyGear: item subclass ID:",
			tostring(info.subclassID or "nil"),
			HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b,
			HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b
		)
		tooltip:AddDoubleLine(
			"TyGear: valid gear slots:",
			table.concat(info.validGearSlots or {}, ", "),
			HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b,
			HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b
		)
		tooltip:AddDoubleLine(
			"TyGear: rarity:",
			tostring(info.rarity or "nil"),
			HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b,
			info.rarityColor and info.rarityColor.r or HIGHLIGHT_FONT_COLOR.r,
			info.rarityColor and info.rarityColor.g or HIGHLIGHT_FONT_COLOR.g,
			info.rarityColor and info.rarityColor.b or HIGHLIGHT_FONT_COLOR.b
		)
		local soulbindingTable = {}
		soulbindingTable[1] = info.boe and "BoE" or info.bop and "BoP" or "none"
		if info.boe and info.bop then
			soulbindingTable[2] = "BoP"
		end
		tooltip:AddDoubleLine(
			"TyGear: soulbinding:",
			table.concat(soulbindingTable,", "),
			HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b,
			HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b
		)
		tooltip:AddDoubleLine(
			"TyGear: lowest-scoring equipped item slot:",
			tostring(lowestScoringEquippedItemSlot or "nil"),
			HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b,
			HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b
		)
		tooltip:AddDoubleLine(
			"TyGear: lowest-scoring equipped item:",
			lowestScoringEquippedItemInfo and ((lowestScoringEquippedItemInfo.empty and "nothing") or (lowestScoringEquippedItemInfo.link or lowestScoringEquippedItemInfo.name or "nil")) or "nil",
			HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b,
			HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b
		)
		tooltip:AddDoubleLine(
			"TyGear: lowest-scoring equipped item score:",
			lowestScoringEquippedItemScore or "nil",
			HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b,
			HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b
		)
		-- local rollDecision = TyGearDecideRoll(info.link)
		-- tooltip:AddDoubleLine(
		-- 	"TyGear: would roll:",
		-- 	(rollDecision == 1 and GREEN_FONT_COLOR_CODE.."NEED" or (rollDecision == 2 and RED_FONT_COLOR_CODE.."GREED" or HIGHLIGHT_FONT_COLOR_CODE.."no roll"))..FONT_COLOR_CODE_CLOSE,
		-- 	HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b,
		-- 	HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b
		-- )
	end
	-- TyGearPrint("tooltip type:"..tostring(tooltipData))
	-- TyGearPrint("name: "..tostring(name).."; link: "..tostring(link).."; guid: "..tostring(guid).."; equipped: "..tostring(TyGearSlotNames and TyGearSlotNames[equipped] or equipped))
end

--idTip adds its own "ItemID" line to item tooltips unless it's turned off overall or for items in its settings; versions without settings don't define idTipConfig and always add it
function TyGearIsIdTipShowingItemIDs()
	local isAddOnLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
	if not isAddOnLoaded("idTip") then return false end
	if type(idTipConfig) ~= "table" then return true end
	return (idTipConfig.enabled ~= false) and (idTipConfig.itemEnabled ~= false)
end

--show item IDs in item tooltips while the TyGear options are open, for filling in the grey selling exclusions
function TyGearAddItemIDToTooltip(tooltip)
	if (tooltip ~= GameTooltip) or (not optionsMenuParent:IsVisible()) or TyGearIsIdTipShowingItemIDs() then return end
	local _, link = tooltip:GetItem()
	if (not link) or (issecretvalue and issecretvalue(link)) then return end
	local itemID = string.match(link, "item:(%d+)")
	if itemID then
		tooltip:AddDoubleLine(L["Item ID"], itemID)
	end
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and C_TooltipInfo then
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, TyGearTooltipHook)
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, TyGearAddItemIDToTooltip)
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, TyGearAddListBindingHintsToTooltip)
else
	GameTooltip:HookScript("OnTooltipSetItem", TyGearTooltipHook)
	GameTooltip:HookScript("OnTooltipSetItem", TyGearAddItemIDToTooltip)
	GameTooltip:HookScript("OnTooltipSetItem", TyGearAddListBindingHintsToTooltip)
	ShoppingTooltip1:HookScript("OnTooltipSetItem", TyGearTooltipHook)
	ShoppingTooltip2:HookScript("OnTooltipSetItem", TyGearTooltipHook)
	ItemRefTooltip:HookScript("OnTooltipSetItem", TyGearTooltipHook)
	ItemRefTooltip:HookScript("OnTooltipSetItem", TyGearAddListBindingHintsToTooltip)
	if AtlasLootTooltip then
		AtlasLootTooltip:HookScript("OnTooltipSetItem", TyGearTooltipHook)
	end
end

function TyGearQueueLocalUpdate()
	--check if there's already a local update action in queue
	local localUpdateFound = nil
	local debounceUntil = GetTime() + 0.25
	for i, curAction in ipairs(TyGearActionQueue) do
		if curAction.t and (curAction.action == "localupdate") then
			-- Coalesce bursts (multi-slot equip) into one delayed rescan
			if curAction.t < debounceUntil then
				curAction.t = debounceUntil
			end
			localUpdateFound = 1
		end
	end
	if (not localUpdateFound) then
		TyGearQueueAction({ action = "localupdate", t = debounceUntil })
	end
end

function TyGearQueueScan()
	--check if there's already a scan action in queue
	local scanFound = nil
	for i, curAction in ipairs(TyGearActionQueue) do
		if curAction.t and (curAction.action == "scan") then
			--push the time ahead until all the items have arrived
			curAction.t = GetTime() + 1.0
			scanFound = 1
		end
	end
	if (not scanFound) then
		--no scan found, so create a new one
		TyGearQueueAction({ action = "scan", t = GetTime() + 0.5 })
	end
end

function TyGearMain()
	if (#TyGearActionQueue == 0) then
		TyGearStopMainLoopIfIdle()
		return
	end
	if (GetTime() - tUpdate > 0.05) then
		tUpdate = GetTime()
		--future actions
		local queuedActionCount = #TyGearActionQueue
		for i = 1, queuedActionCount do
			local curAction = TyGearActionQueue[i]

			-- if there's any item data missing, don't do anything that matters and instead try updating again
			if curAction.t and curAction.action == "localupdate" then
				if GetTime() > curAction.t then
					TyGearSomeItemDataIsMissing = nil
					curAction.t = nil
					queueQueueRebuild = 1
					TyGearUpdateBestItems() -- this will set TyGearSomeItemDataIsMissing again if necessary
					TyGearQueueVendorJunkRefresh()
					TyGearQueueUpgradeRefresh()
				end
			end
			if (not TyGearSomeItemDataIsMissing) then
				if curAction.t and curAction.action == "roll" then
					if GetTime() > curAction.t then
						local forceNeedFromList = (curAction.rollType == 1) and curAction.info and TyGearIsOnNeedList(curAction.info.id)
						local mayAutoNeed = (TyGearDB.NeverAutoNeed ~= true) or forceNeedFromList
						if curAction.rollType == 1 then
							TyGearPrint("TyGear: "..(((TyGearDB.AutoLootRoll == true) and mayAutoNeed) and "Rolling " or "If automatically rolling "..(mayAutoNeed and "" or (GREEN_FONT_COLOR_CODE.."NEED"..FONT_COLOR_CODE_CLOSE.." ")).."on loot was enabled, would roll ")..GREEN_FONT_COLOR_CODE.."NEED"..FONT_COLOR_CODE_CLOSE.." on "..curAction.info.link..".", 1)
						elseif curAction.rollType == 2 then
							TyGearPrint("TyGear: "..((TyGearDB.AutoLootRoll == true) and "Rolling " or "If automatically rolling on loot was enabled, would roll ")..RED_FONT_COLOR_CODE.."GREED"..FONT_COLOR_CODE_CLOSE.." on "..curAction.info.link..".", 1)
						end
						local rarity = curAction.info.rarity
						if (mayAutoNeed or (curAction.rollType ~= 1)) and
						((((rarity < 3) or (rarity == 3 and not (curAction.info.boe))) and (TyGearDB.AutoLootRoll == true)) or
						((rarity == 3) and curAction.info.boe and (TyGearDB.AutoRollOnBoEBlues == true)) or
						((rarity == 4) and (TyGearDB.AutoRollOnEpics == true)) or
						forceNeedFromList) then
							RollOnLoot(curAction.rollID, curAction.rollType)
						end
						curAction.t = nil
						queueQueueRebuild = 1
					end
				elseif curAction.t and (curAction.action == "equip" and not UnitAffectingCombat("player") and not UnitIsDeadOrGhost("player")) then
					if (GetTime() > curAction.t) then
						if ((TyGearDB.Enabled ~= nil) and (TyGearDB.Enabled == true)) then
							if (not curAction.messageAlready) then
								TyGearPrint("TyGear: Equipping "..(curAction.info.link or curAction.info.name)..".", 2)
								curAction.messageAlready = 1
							end
							if (curAction.removeMainHandFirst) then
								if (TyGearGetAllBagsNumFreeSlots() > 0) then
									TyGearPrint("TyGear: Removing the two-hander to equip the off-hand", 1)
									PickupInventoryItem(INVSLOT_MAINHAND)
									TyGearPutItemInEmptyBagSlot()
									curAction.removeMainHandFirst = nil
									curAction.waitingOnEmptyMainHand = 1
								else
									TyGearPrint("TyGear: Cannot equip the off-hand because bags are too full to remove the two-hander", 0)
									curAction.t = nil
									queueQueueRebuild = 1
								end
							elseif (curAction.waitingOnEmptyMainHand and not TyGearEquippedItems[INVSLOT_MAINHAND].info.empty) then
								TyGearUpdateEquippedItem(INVSLOT_MAINHAND)
							elseif (curAction.waitingOnEmptyMainHand and TyGearEquippedItems[INVSLOT_MAINHAND].info.empty) then
								TyGearPrint("TyGear: Main hand detected to be clear.  Equipping now.", 1)
								curAction.waitingOnEmptyMainHand = nil
							elseif (curAction.ensuringEquipped) then
								-- TyGearPrint("checking whether equipped: "..curAction.info.link,3)
								local function finishEquipped()
									curAction.ensuringEquipped = nil
									if (not TyGearActionQueue[i+1]) or (not TyGearActionQueue[i+1].ensuringEquipped) then
										TyGearUpdateEquippedItems()
										TyGearPlayUpgradeEquippedChime()
									end
									curAction.t = nil
									queueQueueRebuild = 1
								end
								if (GetInventoryItemID("player", curAction.replaceSlot) == curAction.info.id)
								and not (curAction.reagentEquip and TyGearSlotIsKnownNormalBag(curAction.replaceSlot)) then
									finishEquipped()
								elseif curAction.reagentEquip or (curAction.replaceSlot == TyGearReagentBagSlot and curAction.info and (TyGearIsReagentBag(curAction.info) or TyGearUsesReagentBagSlot(curAction.info))) then
									curAction.reagentEquip = true
									local foundSlot
									for _, candidate in ipairs(TyGearReagentBagSlotCandidates()) do
										if not TyGearSlotIsKnownNormalBag(candidate) and TyGearBagSlotNewlyHolds(curAction.info.id, candidate, curAction.bagSnapshot) then
											foundSlot = candidate
											break
										end
									end
									if foundSlot then
										curAction.replaceSlot = foundSlot
										TyGearAdoptReagentBagSlot(foundSlot)
										finishEquipped()
									elseif curAction.reagentGaveUp then
										curAction.ensureTicks = (curAction.ensureTicks or 0) + 1
										if curAction.ensureTicks >= 40 then
											TyGearPrint("TyGear: Could not equip "..(curAction.info.link or curAction.info.name or "that bag").." into the reagent bag slot."..TyGearReagentTriedSuffix(curAction.reagentTried), 0)
											curAction.t = nil
											queueQueueRebuild = 1
										end
									else
									local wrong = TyGearFindRegularBagSlotHolding(curAction.info.id, curAction.bagSnapshot)
									if wrong then
										PickupInventoryItem(wrong)
										local landed = TyGearEquipActionBag(curAction, function()
											TyGearReturnCursorItem(curAction)
										end)
										if landed and not TyGearSlotIsKnownNormalBag(curAction.replaceSlot) and GetInventoryItemID("player", curAction.replaceSlot) == curAction.info.id then
											finishEquipped()
										elseif not landed then
											curAction.reagentGaveUp = 1
											TyGearReturnCursorItem(curAction)
											TyGearPrint("TyGear: Could not equip "..(curAction.info.link or curAction.info.name or "that bag").." into the reagent bag slot."..TyGearReagentTriedSuffix(curAction.reagentTried), 0)
											curAction.t = nil
											queueQueueRebuild = 1
										else
											curAction.ensureTicks = (curAction.ensureTicks or 0) + 1
											if curAction.ensureTicks >= 40 then
												TyGearPrint("TyGear: Could not equip "..(curAction.info.link or curAction.info.name or "that bag").." into the reagent bag slot."..TyGearReagentTriedSuffix(curAction.reagentTried), 0)
												curAction.t = nil
												queueQueueRebuild = 1
											end
										end
									else
										curAction.ensureTicks = (curAction.ensureTicks or 0) + 1
										if curAction.ensureTicks >= 40 then
											TyGearPrint("TyGear: Could not equip "..(curAction.info.link or curAction.info.name or "that bag").." into the reagent bag slot."..TyGearReagentTriedSuffix(curAction.reagentTried), 0)
											curAction.t = nil
											queueQueueRebuild = 1
										end
									end
									end
								elseif TyGearGetContainerForEquippedBagSlot(curAction.replaceSlot) then
									curAction.ensureTicks = (curAction.ensureTicks or 0) + 1
									if curAction.ensureTicks >= 40 then
										TyGearPrint("TyGear: Could not equip "..(curAction.info.link or curAction.info.name or "that bag").." into the "..TyGearBagEquipSlotName(curAction.replaceSlot).."."..TyGearReagentTriedSuffix(curAction.reagentTried), 0)
										curAction.t = nil
										queueQueueRebuild = 1
									end
								end
							elseif curAction.fromEquippedSlot then
								-- the bag is already worn in a normal slot; move it to the slot it belongs in
								local sourceSlot = curAction.fromEquippedSlot
								local wantedID = curAction.info and curAction.info.id
								if wantedID and GetInventoryItemID and GetInventoryItemID("player", sourceSlot) ~= wantedID then
									local foundSlot
									for slot = 31, 34 do
										if GetInventoryItemID("player", slot) == wantedID then
											foundSlot = slot
											break
										end
									end
									if not foundSlot then
										for slot = 20, 23 do
											if GetInventoryItemID("player", slot) == wantedID then
												foundSlot = slot
												break
											end
										end
									end
									if foundSlot then
										sourceSlot = foundSlot
									end
								end
								curAction.reagentSourceSlot = curAction.reagentSourceSlot or sourceSlot
								PickupInventoryItem(sourceSlot)
								local landed = TyGearEquipActionBag(curAction, function()
									PutItemInBag(sourceSlot)
								end)
								if landed then
									curAction.ensuringEquipped = 1
									curAction.fromEquippedSlot = nil
								else
									local triedSuffix = TyGearReagentTriedSuffix(curAction.reagentTried)
									curAction.reagentTried = nil
									curAction.attempts = (curAction.attempts or 0) + 1
									if curAction.attempts >= 3 then
										TyGearPrint("TyGear: Could not move "..(curAction.info.link or curAction.info.name or "that bag").." into the "..TyGearBagEquipSlotName(curAction.replaceSlot).."."..triedSuffix, 0)
										curAction.t = nil
										queueQueueRebuild = 1
									else
										curAction.t = GetTime() + 0.5
									end
								end
							else
								if ((not curAction.container) or (not curAction.slot))
								and curAction.info and curAction.info.itemLocation or (curAction.info.item and curAction.info.item.GetItemLocation and curAction.info.item:HasItemLocation()) then
									local itemLocation = curAction.info.itemLocation or curAction.info.item:GetItemLocation()
									curAction.container, curAction.slot = itemLocation:GetBagAndSlot()
								end
								-- Equipping an earlier bag shifts later bag/slot indexes; re-find by item id.
								TyGearRefreshActionBagLocation(curAction)
								if (not curAction.container) or (not curAction.slot) then
									TyGearBrokenAction = curAction
									TyGearPrint("Error: The current equip action has either no container or no slot! This should never happen, so it must be a bug. It's now been saved to global variable TyGearBrokenAction, so try \"/dump TyGearBrokenAction\" and send the output to the TyGear author.",0)
									curAction.t = nil
									queueQueueRebuild = 1
								--everything below needs the container and slot, so it only runs when both are known
								-- prevent equip error when bag is replacing the bag it's inside
								elseif TyGearGetContainerForEquippedBagSlot(curAction.replaceSlot)
								and curAction.container == TyGearGetContainerForEquippedBagSlot(curAction.replaceSlot) then
									if not curAction.movedOutOfBag then
										local destBag, destSlot
										for b = 0, NUM_BAG_SLOTS do
											if b ~= curAction.container then
												local freeSlots, bagType = GetContainerNumFreeSlots(b)
												if bagType == 0 and freeSlots > 0 then
													local slotMax = GetContainerNumSlots(b)
													for s = 1, slotMax do
														if not TyGearGetContainerItemInfo(b, s) then
															destBag = b
															destSlot = s
															break
														end
													end
													if destBag then break end
												end
											end
										end
										if destBag then
											PickupContainerItem(curAction.container, curAction.slot)
											PickupContainerItem(destBag, destSlot)
											curAction.container = destBag
											curAction.slot = destSlot
											curAction.movedOutOfBag = true
										else
											TyGearPrint("TyGear: Cannot equip bag because there is no empty slot in another bag to move it to.", 0)
											curAction.t = nil
											queueQueueRebuild = 1
										end
									else
										TyGearRefreshActionBagLocation(curAction)
										local sourceContainer, sourceSlot = curAction.container, curAction.slot
										PickupContainerItem(sourceContainer, sourceSlot)
										local landed = TyGearEquipActionBag(curAction, function()
											PickupContainerItem(sourceContainer, sourceSlot)
										end)
										if landed then
											curAction.ensuringEquipped = 1
											curAction.movedOutOfBag = nil
										else
											curAction.ensuringEquipped = nil
											curAction.movedOutOfBag = nil
											local triedSuffix = TyGearReagentTriedSuffix(curAction.reagentTried)
											curAction.reagentTried = nil
											curAction.attempts = (curAction.attempts or 0) + 1
											if curAction.attempts >= 3 then
												TyGearPrint("TyGear: Could not equip "..(curAction.info.link or curAction.info.name or "that bag").." into the "..TyGearBagEquipSlotName(curAction.replaceSlot).."."..triedSuffix, 0)
												curAction.t = nil
												queueQueueRebuild = 1
											else
												curAction.t = GetTime() + 0.5
											end
										end
									end
								else
									TyGearRefreshActionBagLocation(curAction)
									local sourceContainer, sourceSlot = curAction.container, curAction.slot
									PickupContainerItem(sourceContainer, sourceSlot)
									local landed = TyGearEquipActionBag(curAction, function()
										PickupContainerItem(sourceContainer, sourceSlot)
									end)
									if landed then
										curAction.ensuringEquipped = 1
									else
										local triedSuffix = TyGearReagentTriedSuffix(curAction.reagentTried)
										curAction.reagentTried = nil
										curAction.attempts = (curAction.attempts or 0) + 1
										if curAction.attempts >= 3 then
											TyGearPrint("TyGear: Could not equip "..(curAction.info.link or curAction.info.name or "that bag").." into the "..TyGearBagEquipSlotName(curAction.replaceSlot).."."..triedSuffix, 0)
											curAction.t = nil
											queueQueueRebuild = 1
										else
											curAction.t = GetTime() + 0.5
										end
									end
								end
							end
						else
							curAction.t = nil
							queueQueueRebuild = 1
						end
					end
				elseif curAction.t and (curAction.action == "scan") then
					if (GetTime() > curAction.t) then
						TyGearConsiderAllItems()
						if not TyGearSomeItemDataIsMissing then
							curAction.t = nil
							queueQueueRebuild = 1
							TyGearQueueVendorJunkRefresh()
							TyGearQueueUpgradeRefresh()
						end
					end
				elseif curAction.t and (curAction.action == "sellgreys") then
					if (GetTime() > curAction.t) then
						curAction.t = nil
						queueQueueRebuild = 1
						if greySelling then TyGearSellGreysTick() end
					end
				elseif curAction.t and (curAction.action == "vendorjunk") then
					if (GetTime() > curAction.t) then
						curAction.t = nil
						queueQueueRebuild = 1
						TyGearRefreshVendorJunkMarks()
					end
				elseif curAction.t and (curAction.action == "upgrade") then
					if (GetTime() > curAction.t) then
						curAction.t = nil
						queueQueueRebuild = 1
						TyGearRefreshUpgradeMarks()
					end
				end
			end
		end
		if queueQueueRebuild then
			local writeIndex = 1
			for readIndex = 1, #TyGearActionQueue do
				local curAction = TyGearActionQueue[readIndex]
				if curAction.t then
					TyGearActionQueue[writeIndex] = curAction
					writeIndex = writeIndex + 1
				end
			end
			for i = writeIndex, #TyGearActionQueue do
				TyGearActionQueue[i] = nil
			end
			queueQueueRebuild = nil
			TyGearStopMainLoopIfIdle()
		end
	end
end
