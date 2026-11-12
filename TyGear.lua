-- TyGear
-- Fork of AutoGear by Synthetikaryote and BujuArena.
-- Original: https://github.com/BujuArena/AutoGear
-- License: Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International
-- https://creativecommons.org/licenses/by-nc-sa/4.0/
-- This copy is modified so the addon, saved variables, and slash commands
-- use the TyGear name. The original authors retain credit for the work.

-- to do:
-- implement classic direct % crit and direct % hit
-- Needing on meteor shard as a mage
--	In general, needing on one-handers that are near-worthless.  The plan is to only roll if it passes a minimum threshold.  That threshold should be 3x the highest weight among the 5 main stats.
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
local shouldPrintHelp = false
local maxPlayerLevel = (GetMaxPlayerLevel and GetMaxPlayerLevel())
	or (GetMaxLevelForExpansionLevel and GetExpansionLevel and GetMaxLevelForExpansionLevel(GetExpansionLevel()))
	or 60
local L = T.Localization
local ContainerIDToInventoryID = ContainerIDToInventoryID or (C_Container and C_Container.ContainerIDToInventoryID)
local GetContainerNumFreeSlots = GetContainerNumFreeSlots or (C_Container and C_Container.GetContainerNumFreeSlots)
local GetContainerNumSlots = GetContainerNumSlots or (C_Container and C_Container.GetContainerNumSlots)
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
TyGearLastEquippableBagSlot = ContainerIDToInventoryID(NUM_BAG_SLOTS) or 23
TyGearEquippableBagSlots = {}
--initialize equippable bag slots table
for i = BACKPACK_CONTAINER+1, NUM_BAG_SLOTS do
	table.insert(TyGearEquippableBagSlots, TyGearFirstEquippableBagSlot+i-1)
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
	local classNames = {}
	for token, english in pairs(ENGLISH_CLASS_NAMES) do
		classNames[#classNames + 1] = { token = token, name = english }
		local localized = TyGearClassList and TyGearClassList[token]
		if localized and localized ~= english then
			classNames[#classNames + 1] = { token = token, name = localized }
		end
	end
	table.sort(classNames, function(a, b) return #a.name > #b.name end)
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
	if (TyGearDB.AllowedVerbosity == nil) or (verbosity <= TyGearDB.AllowedVerbosity) then
		print(TyGearColorize(text))
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
	if not TyGearCharDB.UnmeasurableGearDisabled then TyGearCharDB.UnmeasurableGearDisabled = {} end
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

-- Specializations appeared only in Mists Of Pandaria. We also have make changes to Cataclysm with preferred talent tree
-- later
if IS_WOW_FOREVER then
	function TyGearDetectSpec()
		-- WoW Forever has one specialization per class; builds live in C_Traits, so there is no
		-- reliable spec to detect. Use the general class profile; role-specific profiles are
		-- available through the "Override specialization" option.
		return "None"
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

function TyGearGetGearSlotShortLabel(slot)
	if slot >= INVSLOT_FIRST_EQUIPPED and slot <= INVSLOT_LAST_EQUIPPED then
		return TyGearSlotNames[slot] or GetItemInventorySlotInfo(slot) or tostring(slot)
	elseif slot >= TyGearFirstEquippableBagSlot and slot <= TyGearLastEquippableBagSlot then
		local slotNumber = slot - TyGearFirstEquippableBagSlot + 1
		return (BAGSLOT or "Bag").." "..tostring(slotNumber)
	else
		return tostring(slot)
	end
end

function TyGearGetLockedGearSlotLabel(slot)
	if slot >= INVSLOT_FIRST_EQUIPPED and slot <= INVSLOT_LAST_EQUIPPED then
		local slotName = TyGearGetGearSlotShortLabel(slot)
		return tostring(slot)..(slotName and ": "..slotName or "")
	elseif slot >= TyGearFirstEquippableBagSlot and slot <= TyGearLastEquippableBagSlot then
		local slotName = TyGearGetGearSlotShortLabel(slot)
		return tostring(slot)..(slotName and ": "..slotName or "")
	else
		return tostring(slot)
	end
end

function TyGearGetDefaultLockedGearSlots()
	local lockedGearSlots = {}
	for slot = INVSLOT_FIRST_EQUIPPED, TyGearLastEquippableBagSlot do
		if slot <= INVSLOT_LAST_EQUIPPED or slot >= TyGearFirstEquippableBagSlot then
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
		"ExperienceGained", "numBagSlots", "ammoBagRangedAttackSpeed",
	}
	for _, field in ipairs(fields) do
		local value = info[field]
		if type(value) == "number" and value > 0 then
			return true
		end
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
		and not (TyGearCharDB and TyGearCharDB.UnmeasurableGearDisabled and TyGearCharDB.UnmeasurableGearDisabled[itemID])
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
	local disabled = TyGearCharDB and TyGearCharDB.UnmeasurableGearDisabled and TyGearCharDB.UnmeasurableGearDisabled[itemID]
	if TyGearIsKnownUnmeasurableGear(itemID) then
		return true
	end
	if IS_WOW_FOREVER and TyGearCharDB and TyGearCharDB.DiscoveredUnmeasurableGear and TyGearCharDB.DiscoveredUnmeasurableGear[itemID] and not disabled then
		return true
	end
	if type(info) == "table" and info.unmeasurableOnly and not disabled then
		return true
	end
	if TyGearCharDB and TyGearCharDB.IgnoredItemIDs and TyGearCharDB.IgnoredItemIDs[itemID] then
		if type(info) ~= "table" or info.isGear then
			return true
		end
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

--unknown items are kept so an ID can be ignored before the client has cached it
function TyGearIsEquipmentItemID(itemID)
	if not itemID or not GetItemInfoInstant then return false end
	local classID = select(6, GetItemInfoInstant(itemID))
	if not classID then return true end
	return classID == Enum.ItemClass.Weapon or classID == Enum.ItemClass.Armor
end

function TyGearSetItemIgnored(itemID, shouldIgnore)
	itemID = tonumber(itemID)
	if not itemID then return end
	if not TyGearCharDB then TyGearCharDB = {} end
	TyGearCharDB.IgnoredItemIDs = TyGearCharDB.IgnoredItemIDs or {}
	TyGearCharDB.UnmeasurableGearDisabled = TyGearCharDB.UnmeasurableGearDisabled or {}
	if shouldIgnore then
		TyGearCharDB.UnmeasurableGearDisabled[itemID] = nil
		if not TyGearIsAutoUnmeasurable(itemID) then
			TyGearCharDB.IgnoredItemIDs[itemID] = true
		end
	else
		TyGearCharDB.IgnoredItemIDs[itemID] = nil
		if TyGearIsAutoUnmeasurable(itemID) then
			TyGearCharDB.UnmeasurableGearDisabled[itemID] = true
		end
	end
	if TyGearUpdateBestItems then TyGearUpdateBestItems() end
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
	end
end

function TyGearFixLockedGearSlots() -- finds missing slots and adds them, in case Blizzard changed them around
	if not TyGearDB.LockedGearSlots then TyGearDB.LockedGearSlots = TyGearGetDefaultLockedGearSlots() return end
	for slot = INVSLOT_FIRST_EQUIPPED, TyGearLastEquippableBagSlot do
		if slot <= INVSLOT_LAST_EQUIPPED or slot >= TyGearFirstEquippableBagSlot then
			if not TyGearDB.LockedGearSlots[slot] then
				TyGearDB.LockedGearSlots[slot] = {
					["label"] = TyGearGetLockedGearSlotLabel(slot),
					["enabled"] = false
				}
			elseif TyGearDB.LockedGearSlots[slot].label then
				TyGearDB.LockedGearSlots[slot].label = TyGearGetLockedGearSlotLabel(slot)
			end
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

function TyGearGetOverrideSpecs()
	local classOrder = {}
	for className in pairs(TyGearDefaultWeights) do
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
			for specName in pairs(TyGearDefaultWeights[className]) do
				table.insert(specOrder, specName)
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

	return localizedClass, class, spec, classID
end


function TyGearDetectClassAndSpec()
	local localizedClass, class, spec, classID
	class, classID = UnitClassBase("player")
	localizedClass = TyGearClassIDList[classID].localizedName
	spec = TyGearDetectSpec()
	return localizedClass, class, spec, classID
end

function TyGearSetStatWeights()
	local localizedClass, class, spec = TyGearGetClassAndSpec()
	TyGearCurrentWeighting = TyGearDefaultWeights[class] and TyGearDefaultWeights[class][spec] or nil
	weapons = TyGearCurrentWeighting and (TyGearCurrentWeighting.weapons or "any") or "any"
	if (not TyGearCurrentWeighting) then
		if (not (TyGearDB.UsePawn and PawnIsReady and PawnIsReady())) then
			TyGearPrint("TyGear: No weighting set for "..RAID_CLASS_COLORS[class]:WrapTextInColorCode(spec.." "..localizedClass)..".", 0)
		end
		return
	end
	if (IS_WOW_FOREVER or TOC_VERSION_CURRENT >= TOC_VERSION_WOTLK) and (not (TyGearDB.UsePawn and PawnIsReady and PawnIsReady())) then
		TyGearCurrentWeighting.Crit = math.max(TyGearCurrentWeighting.Crit or 0, TyGearCurrentWeighting.SpellCrit or 0)
		if IS_WOW_FOREVER then
			-- WoW Forever combines melee, ranged and spell hit on gear
			TyGearCurrentWeighting.Hit = math.max(TyGearCurrentWeighting.Hit or 0, TyGearCurrentWeighting.SpellHit or 0)
		end
	end
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
local OPTIONS_JUMP_TOP = -46 --below the TyGear title and the AutoGear credit line
local OPTIONS_JUMP_BUTTON_HEIGHT = 22
local OPTIONS_JUMP_BUTTON_GAP = 4
local OPTIONS_CONTAINER_LEFT_OFFSET = 8
local OPTIONS_CONTAINER_RIGHT_MARGIN = 30 --room for the scroll bar
local OPTIONS_CONTAINER_BOTTOM_MARGIN = 16
local OPTIONS_PAGE_PADDING = 12
local OPTIONS_ROW_SPACING = 2
local OPTIONS_SECTION_SPACING = 12
local OPTIONS_SECTION_HEADER_HEIGHT = 20
local OPTIONS_BUTTON_SPACING = 10

---One scrolling options page. Section buttons jump down the page; the mouse wheel
---moves through every section because they are all on this page.
---@param optionsMenu table the scroll child of the options scroll frame
---@return table optionsPage with BeginOption, AddRow, AddScanButton and Finish
local function newOptionsPage(optionsMenu)
	local scrollFrame = optionsMenu:GetParent()
	local optionsPage = { jumps = {} }

	local jumpBar = CreateFrame("Frame", nil, optionsMenu)
	jumpBar:SetPoint("TOPLEFT", optionsMenu, "TOPLEFT", OPTIONS_CONTAINER_LEFT_OFFSET, OPTIONS_JUMP_TOP)
	jumpBar:SetHeight(OPTIONS_JUMP_BUTTON_HEIGHT)

	local container = CreateFrame("Frame", "TyGearOptionsContainer", optionsMenu, "BackdropTemplate")
	container:SetBackdrop({
		bgFile = "Interface/ChatFrame/ChatFrameBackground",
		edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 14,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	container:SetBackdropColor(0.1, 0.1, 0.1, 0.3)
	container:SetBackdropBorderColor(0.5, 0.5, 0.5)
	container:SetPoint("TOPLEFT", jumpBar, "BOTTOMLEFT", 0, -8)

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

	local function enableWheel(frame)
		if not frame or frame.tyGearWheel or not frame.EnableMouseWheel then return end
		frame.tyGearWheel = true
		if frame.EnableMouse and not frame:IsMouseEnabled() then
			frame:EnableMouse(true)
		end
		frame:EnableMouseWheel(true)
		frame:SetScript("OnMouseWheel", onWheel)
	end

	function optionsPage:EnableWheel(frame)
		enableWheel(frame)
	end
	enableWheel(optionsMenu)
	enableWheel(scrollFrame)
	enableWheel(jumpBar)
	enableWheel(container)
	enableWheel(page)

	local function scrollToWidget(widget)
		local menuTop = optionsMenu:GetTop()
		local widgetTop = widget:GetTop()
		if not menuTop or not widgetTop then return end
		local offset = menuTop - widgetTop
		local range = scrollRange()
		if offset < 0 then offset = 0 end
		if offset > range then offset = range end
		scrollFrame:SetVerticalScroll(offset)
	end

	function optionsPage:AddRow(row, spacing, offsetX)
		spacing = page.lastRow and (spacing or OPTIONS_ROW_SPACING) or 0
		offsetX = offsetX or 0
		row:SetParent(page)
		row:ClearAllPoints()
		if page.lastRow then
			row:SetPoint("TOPLEFT", page.lastRow, "BOTTOMLEFT", offsetX, -spacing)
		else
			row:SetPoint("TOPLEFT", page, "TOPLEFT", OPTIONS_PAGE_PADDING + offsetX, -OPTIONS_PAGE_PADDING)
		end
		page.height = page.height + spacing + row:GetHeight()
		page.lastRow = row
		enableWheel(row)
	end

	function optionsPage:AddHeader(label, isMajor)
		local header = CreateFrame("Frame", nil, page)
		header:SetSize(400, isMajor and 26 or OPTIONS_SECTION_HEADER_HEIGHT)
		local headerText = header:CreateFontString(nil, "ARTWORK", isMajor and "GameFontNormalLarge" or "GameFontNormal")
		headerText:SetPoint("BOTTOMLEFT", 4, 2)
		headerText:SetText(TyGearColorize(label))
		self:AddRow(header, isMajor and OPTIONS_SECTION_SPACING or 6)
		local button = CreateFrame("Button", nil, jumpBar, "UIPanelButtonTemplate")
		button:SetText(TyGearColorize(label))
		button:SetHeight(OPTIONS_JUMP_BUTTON_HEIGHT)
		local fontString = button.GetFontString and button:GetFontString()
		local textWidth = fontString and fontString:GetStringWidth() or 0
		if not textWidth or textWidth < 8 then
			textWidth = #label * 7
		end
		button:SetWidth(math.max(48, textWidth + 28))
		button:SetScript("OnClick", function()
			PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
			scrollToWidget(header)
		end)
		enableWheel(button)
		table.insert(self.jumps, button)
	end

	---Groups options that share a tab onto this page and adds a header when the group changes.
	function optionsPage:BeginOption(tabLabel, sectionLabel)
		if tabLabel ~= page.tab then
			if page.tab == L["Evaluation"] then
				self:AddScanButton()
			end
			page.tab = tabLabel
			page.section = nil
			self:AddHeader(tabLabel, true)
		end
		if sectionLabel and sectionLabel ~= page.section then
			page.section = sectionLabel
			self:AddHeader(sectionLabel, false)
		end
		return page
	end

	function optionsPage:AddScanButton()
		if self.scanAdded then return end
		self.scanAdded = true
		local button = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
		button:SetSize(100, 30)
		button:SetText(L["Scan"])
		button:SetScript("OnClick", function() TyGearScan() end)
		button:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_NONE")
			GameTooltip:SetPoint("BOTTOMLEFT", self, "TOPLEFT")
			GameTooltip:AddLine(TyGearColorize(L["Click this button to force a scan, the same way that TyGear scans for gear upgrades in your bags whenever new gear is looted.\n\nTip: By equipping your old item, you can use this to help determine how TyGear decided an item was an upgrade."]), nil, nil, nil, true)
			GameTooltip:Show()
		end)
		button:SetScript("OnLeave", function() GameTooltip:Hide() end)
		enableWheel(button)
		self:AddRow(button, OPTIONS_BUTTON_SPACING, 4)
	end

	function optionsPage:Finish()
		if not self.scanAdded then
			self:AddScanButton()
		end
		local function layout()
			local width = math.max((scrollFrame:GetWidth() or 0) - OPTIONS_CONTAINER_RIGHT_MARGIN, 1)
			jumpBar:SetWidth(width)
			container:SetWidth(width)
			page:SetWidth(width)
			optionsMenu:SetWidth(width + OPTIONS_CONTAINER_LEFT_OFFSET)
			local x, y = 0, 0
			local rowStep = OPTIONS_JUMP_BUTTON_HEIGHT + OPTIONS_JUMP_BUTTON_GAP
			for _, button in ipairs(self.jumps) do
				local buttonWidth = button:GetWidth()
				if x > 0 and (x + buttonWidth) > width then
					x = 0
					y = y + rowStep
				end
				button:ClearAllPoints()
				button:SetPoint("TOPLEFT", jumpBar, "TOPLEFT", x, -y)
				x = x + buttonWidth + OPTIONS_JUMP_BUTTON_GAP
			end
			local jumpHeight = y + OPTIONS_JUMP_BUTTON_HEIGHT
			jumpBar:SetHeight(jumpHeight)
			local pageHeight = page.height + OPTIONS_PAGE_PADDING
			container:SetHeight(pageHeight)
			page:SetHeight(pageHeight)
			optionsMenu:SetHeight(-OPTIONS_JUMP_TOP + jumpHeight + 8 + pageHeight + OPTIONS_CONTAINER_BOTTOM_MARGIN)
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
		local font = holder:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		font:SetPoint("TOPLEFT", 8, -2)
		font:SetWidth(480)
		font:SetJustifyH("LEFT")
		font:SetText(text)
		local height = font:GetStringHeight()
		local estimate = math.ceil(math.max(#text, 1) / 80) * 14
		if not height or height < estimate then height = estimate end
		holder:SetSize(500, height + 8)
		optionsPage:AddRow(holder)
	end

	local function addSubheader(text)
		local header = CreateFrame("Frame", nil, page)
		header:SetSize(400, 20)
		local font = header:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		font:SetPoint("BOTTOMLEFT", 4, 2)
		font:SetText(TyGearColorize(text))
		optionsPage:AddRow(header, 12)
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

	local function manualIDText()
		local ids = {}
		for itemID, ignored in pairs(TyGearCharDB.IgnoredItemIDs or {}) do
			local numericID = tonumber(itemID)
			if ignored and numericID then
				table.insert(ids, numericID)
			end
		end
		table.sort(ids)
		local parts = {}
		for _, itemID in ipairs(ids) do
			table.insert(parts, tostring(itemID))
		end
		return table.concat(parts, ", ")
	end

	local function saveManualIDs(text)
		local nextIDs = {}
		for _, itemID in ipairs(TyGearParseItemIDList(text)) do
			if not TyGearIsAutoUnmeasurable(itemID) and TyGearIsEquipmentItemID(itemID) then
				nextIDs[itemID] = true
			end
		end
		TyGearCharDB.IgnoredItemIDs = nextIDs
		if TyGearUpdateBestItems then TyGearUpdateBestItems() end
	end

	addSubheader(L["Gear slots"])
	addNote(L["Ignored slots are left out of rolling, scoring, and equipping."])
	do
		--compact multi-column grid instead of a tall full-width checkbox stack
		local slotList = {}
		for slot = INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED do
			--the tabard id is the virtual slot for two-hand weapons, so it is not listed here
			if slot ~= INVSLOT_TABARD then
				table.insert(slotList, slot)
			end
		end
		local columns = 4
		local cellWidth = 118
		local cellHeight = 20
		local padX, padY = 10, 8
		local rows = math.max(math.ceil(#slotList / columns), 1)
		local slotGrid = CreateFrame("Frame", "TyGearIgnoredGearSlotsGrid", page, "BackdropTemplate")
		slotGrid:SetSize(padX * 2 + columns * cellWidth, padY * 2 + rows * cellHeight)
		slotGrid:SetBackdrop({
			bgFile = "Interface/ChatFrame/ChatFrameBackground",
			edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 12,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
		slotGrid:SetBackdropColor(0.08, 0.08, 0.08, 0.45)
		slotGrid:SetBackdropBorderColor(0.45, 0.45, 0.45, 0.9)
		local slotDescription = L["Ignored slots are left out of rolling, scoring, and equipping."]
		for index, gearSlot in ipairs(slotList) do
			local column = (index - 1) % columns
			local rowIndex = math.floor((index - 1) / columns)
			local shortLabel = TyGearGetGearSlotShortLabel(gearSlot)
			local check = CreateFrame("CheckButton", "TyGearIgnoreSlot"..gearSlot.."CheckButton", slotGrid, "UICheckButtonTemplate")
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
			check:SetChecked(TyGearCharDB.IgnoredGearSlots[gearSlot] and true or false)
			check:SetScript("OnClick", function(self)
				local tick = self:GetChecked() and true or false
				TyGearCharDB.IgnoredGearSlots[gearSlot] = tick
				if tick then
					PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
				else
					PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
				end
				if TyGearUpdateBestItems then TyGearUpdateBestItems() end
			end)
			check:SetScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_NONE")
				GameTooltip:SetPoint("BOTTOMLEFT", self, "TOPLEFT")
				GameTooltip:AddLine(shortLabel, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, true)
				GameTooltip:AddLine(slotDescription, HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b, true)
				GameTooltip:Show()
			end)
			check:SetScript("OnLeave", function() GameTooltip:Hide() end)
			optionsPage:EnableWheel(check)
		end
		optionsPage:AddRow(slotGrid, 4, 4)
	end

	addSubheader(L["Equipped items"])
	addNote(L["Check an equipped item to leave that item out of rolling, scoring, and equipping."])
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
				row.check:SetChecked(TyGearIsItemIgnored({ id = itemID, isGear = true }) and true or false)
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
		GameTooltip:AddLine(L["Item IDs"], NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, true)
		GameTooltip:AddLine(L["Also ignore these item IDs. Shift-click equipment while this box is focused to add it. Armor and weapons are accepted."], HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b, true)
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

	local iconContainer
	local rebuildIcons
	if IS_WOW_FOREVER then
		iconContainer = CreateFrame("Frame", nil, page)
		iconContainer:SetSize(500, 20)
		local iconButtons = {}
		local iconSize, iconPad, iconColumns = 36, 4, 8

		local function acquireIconButton()
			local button = CreateFrame("Button", nil, iconContainer)
			button:SetSize(iconSize, iconSize)
			button.icon = button:CreateTexture(nil, "ARTWORK")
			button.icon:SetAllPoints()
			local highlight = button:CreateTexture(nil, "HIGHLIGHT")
			highlight:SetAllPoints()
			highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
			highlight:SetBlendMode("ADD")
			button.check = button:CreateTexture(nil, "OVERLAY")
			button.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
			button.check:SetSize(18, 18)
			button.check:SetPoint("BOTTOMRIGHT", 4, -4)
			button:SetScript("OnClick", function(self)
				local ignored = TyGearIsItemIgnored({ id = self.itemID, isGear = true })
				TyGearSetItemIgnored(self.itemID, not ignored)
				if ignored then
					PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
				else
					PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
				end
				if TyGearRefreshIgnoreSection then TyGearRefreshIgnoreSection() end
				if GameTooltip:IsOwned(self) then
					self:GetScript("OnEnter")(self)
				end
			end)
			button:SetScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:SetHyperlink("item:"..self.itemID)
				local ignored = TyGearIsItemIgnored({ id = self.itemID, isGear = true })
				GameTooltip:AddLine(ignored and L["Ignored. Click to evaluate this item."] or L["Click to ignore this item."], 1, 0.82, 0, true)
				GameTooltip:Show()
			end)
			button:SetScript("OnLeave", function() GameTooltip:Hide() end)
			optionsPage:EnableWheel(button)
			return button
		end

		rebuildIcons = function()
			local entries = {}
			local seen = {}
			if TyGearUnmeasurableGearList then
				for _, entry in ipairs(TyGearUnmeasurableGearList) do
					seen[entry.id] = true
					table.insert(entries, { id = entry.id, icon = entry.icon, name = entry.name })
				end
			end
			if TyGearCharDB and TyGearCharDB.DiscoveredUnmeasurableGear then
				for itemID in pairs(TyGearCharDB.DiscoveredUnmeasurableGear) do
					if not seen[itemID] then
						local icon = GetItemInfoInstant and select(5, GetItemInfoInstant(itemID))
						local name = GetItemInfo and GetItemInfo(itemID)
						table.insert(entries, { id = itemID, icon = icon, name = name or ("item "..itemID) })
					end
				end
			end
			table.sort(entries, function(a, b)
				return (a.name or "") < (b.name or "")
			end)
			for index, entry in ipairs(entries) do
				local button = iconButtons[index]
				if not button then
					button = acquireIconButton()
					iconButtons[index] = button
				end
				local column = (index - 1) % iconColumns
				local rowIndex = math.floor((index - 1) / iconColumns)
				button.itemID = entry.id
				button:ClearAllPoints()
				button:SetPoint("TOPLEFT", iconContainer, "TOPLEFT", 8 + column * (iconSize + iconPad), -(rowIndex * (iconSize + iconPad)))
				if entry.icon then
					button.icon:SetTexture(entry.icon)
				else
					button.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
				end
				local ignored = TyGearIsItemIgnored({ id = entry.id, isGear = true })
				if button.icon.SetDesaturated then
					button.icon:SetDesaturated(not ignored)
				end
				button.icon:SetAlpha(ignored and 1 or 0.4)
				button.check:SetShown(ignored)
				button:Show()
				if Item and Item.CreateFromItemID then
					local itemID = entry.id
					local item = Item:CreateFromItemID(itemID)
					item:ContinueOnItemLoad(function()
						if button.itemID ~= itemID or not button:IsShown() then return end
						local icon = item.GetItemIcon and item:GetItemIcon()
						if icon then button.icon:SetTexture(icon) end
					end)
				end
			end
			for index = #entries + 1, #iconButtons do
				iconButtons[index]:Hide()
			end
			local rows = math.max(math.ceil(#entries / iconColumns), 1)
			trackHeight(iconContainer, rows * (iconSize + iconPad))
		end
	end

	function TyGearRefreshIgnoreSection()
		rebuildEquipped()
		if rebuildIcons then rebuildIcons() end
		if not editBox:HasFocus() then
			showManualIDs()
		end
	end

	rebuildEquipped()
	optionsPage:AddRow(equippedContainer)
	addSubheader(L["Item IDs"])
	addNote(L["Also ignore these item IDs. Shift-click equipment while this box is focused to add it. Armor and weapons are accepted."])
	optionsPage:AddRow(editRow)
	if iconContainer then
		addSubheader(L["No measurable stats"])
		addNote(L["These items have only effects TyGear cannot score, such as a 4% chance for Fear to miss. Gear that also has a scored stat stays in normal evaluation. Click an icon to toggle it."])
		rebuildIcons()
		optionsPage:AddRow(iconContainer)
	end
	showManualIDs()
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
	local orderedOptions = {}
	for _, tab in ipairs(tabOrder) do
		for _, option in ipairs(buckets[tab]) do
			table.insert(orderedOptions, option)
		end
	end
	TyGearOptions = orderedOptions

	local function addOptionsNote(page, text)
		local holder = CreateFrame("Frame", nil, page)
		local font = holder:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		font:SetPoint("TOPLEFT", 8, -2)
		font:SetWidth(480)
		font:SetJustifyH("LEFT")
		font:SetText(TyGearColorize(text))
		local height = font:GetStringHeight()
		local estimate = math.ceil(math.max(#text, 1) / 80) * 14
		if not height or height < estimate then height = estimate end
		holder:SetSize(500, height + 8)
		optionsPage:AddRow(holder)
		return holder
	end

	local function addItemIDEditBox(page, optionName, label, description)
		local editRow = CreateFrame("Frame", nil, page)
		editRow:SetSize(500, 24)
		local labelText = editRow:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		labelText:SetPoint("LEFT", 8, 0)
		labelText:SetText(TyGearColorize(label))
		local editBox = CreateFrame("EditBox", "TyGear"..optionName.."EditBox", editRow, "InputBoxTemplate")
		editBox:SetAutoFocus(false)
		editBox:SetSize(320, 20)
		editBox:SetPoint("LEFT", labelText, "RIGHT", 12, 0)
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
		optionsPage:AddRow(editRow, 4, 4)
		return editBox
	end

	--loop through options table to build our options menu programmatically
	for _, v in ipairs(TyGearOptions) do (function()
		if (not v["option"]) or ((v["shouldUse"] ~= nil) and (v["shouldUse"] == false)) then return end
		--manual iterator to be able to start from 0 and add another one outside the loop
		i = i + 1

		--standalone item-ID lists get a labeled section row, not a checkbox with a mystery box beside it
		if v["editBox"] then
			local page = optionsPage:BeginOption(v["tab"] or L["Other"], v["section"])
			if v["description"] then
				addOptionsNote(page, v["description"])
			end
			frame[i] = addItemIDEditBox(page, v["option"], v["label"], v["description"] or "")
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

		--make a checkbox for this option on the single scrolling page
		local page = optionsPage:BeginOption(v["tab"] or L["Other"], v["section"])
		frame[i] = newCheckbox(v["option"], v["label"], description, _G["TyGearSimpleToggle"..v["option"]], page)
		optionsPage:AddRow(frame[i])
		frame[i]:SetHitRectInsets(0, -280, 0, 0) --change click region to not be super wide
		frame[i]:SetChecked(TyGearSettingsTable(v["option"])[v["option"]]) --set initial checked state based on db

		--if this has a child defined and it should be used, build its child
		if v["child"] and ((v["child"]["shouldUse"] == nil) or (v["child"]["shouldUse"] and (v["child"]["shouldUse"] ~= false))) then

			--if the child is a dropdown, build it that way
			if v["child"]["options"] then

				local width = 250
				if useModernDropdowns then
					frame[i].dropDown = CreateFrame("DropdownButton", "TyGear"..v["child"]["option"].."Dropdown", page, "WowStyle1DropdownTemplate")
					--this template draws its box at its frame edges, while UIDropDownMenuTemplate pads it by about 16 pixels on the left
					frame[i].dropDown:SetPoint("LEFT", frame[i], "RIGHT", width + 16, 0) --attach to parent
					frame[i].dropDown:SetWidth(width)
				else
					frame[i].dropDown = CreateFrame("FRAME", "TyGear"..v["child"]["option"].."Dropdown", page, "UIDropDownMenuTemplate")
					frame[i].dropDown:SetPoint("TOPLEFT", frame[i], "TOPRIGHT", width, 0) --attach to parent
					UIDropDownMenu_SetWidth(frame[i].dropDown, width)
				end
				optionsPage:EnableWheel(frame[i].dropDown)
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
	buildIgnoreSection(optionsPage)
	optionsPage:Finish()
end

local optionsMenu = CreateFrame("Frame", "TyGearOptionsMenu")
optionsMenu:SetWidth(1) -- must be set to at least 1 or the menu is invisible in the scroll frame, but will expand to show everything
optionsMenu:SetHeight(1) -- must be set to at least 1 or the menu is invisible in the scroll frame, but will expand to show everything
local optionsMenuParent = CreateFrame("ScrollFrame", "TyGearOptionsMenuScrollFrame", nil, "UIPanelScrollFrameTemplate")
optionsMenuParent.name = "TyGear"
optionsMenuParent:SetScrollChild(optionsMenu)
--the Settings shim above returns the registered category; native InterfaceOptions_AddCategory returns nothing
local optionsCategory = InterfaceOptions_AddCategory(optionsMenuParent)
if InterfaceAddOnsList_Update then InterfaceAddOnsList_Update() end

--white crafting tools kept by the default ignore list for selling white gear.
--Defined up here because the saved-variable defaults below include this list, and fishing poles of any item ID are also kept later by weapon subclass.
TyGearCraftingToolItemIDs = {
	2901, --Mining Pick
	3567, --Dwarven Fishing Pole
	4471, --Flint and Tinder
	4598, --Goblin Fishing Pole
	5956, --Blacksmith Hammer
	6218, --Runed Copper Rod
	6219, --Arclight Spanner
	6256, --Fishing Pole
	6339, --Runed Silver Rod
	6365, --Strong Fishing Pole
	6366, --Darkwood Fishing Pole
	6367, --Big Iron Fishing Pole
	7005, --Skinning Knife
	10498, --Gyromatic Micro-Adjustor
	11130, --Runed Golden Rod
	11145, --Runed Truesilver Rod
	12225, --Blump Family Fishing Pole
	16207, --Runed Arcanite Rod
	20815, --Jeweler's Kit
	39505, --Virtuoso Inking Set
	40772, --Gnomish Army Knife
	85663, --Herbalist's Spade
}

--handle PLAYER_ENTERING_WORLD events for initialization
pcall(optionsMenu.RegisterEvent,optionsMenu,"PLAYER_ENTERING_WORLD")
optionsMenu:SetScript("OnEvent", function (self, event, arg1, arg2, ...)
	if event == "PLAYER_ENTERING_WORLD" then

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
			ScoreInTooltips = true,
			ReasonsInTooltips = false,
			AlwaysCompareGear = GetCVarBool("alwaysCompareItems"),
			AlwaysShowScoreComparisons = false,
			AutoSellGreys = false,
			VendorKeepList = table.concat(TyGearCraftingToolItemIDs, ", "),
			KeepKeeperTahultPetItems = true,
			KeepUnboundGreyGear = false,
			AutoSellUnsuitableWhites = false,
			AutoSellAllWhiteGear = false,
			UsePawn = not IS_WOW_FOREVER, --TyGear built-in weights are deprecated.  We're using Pawn mainly now, so default true.  Pawn has no WoW Forever scales yet, so Forever uses the built-in class profiles.
			OverridePawnScale = false,
			PawnScale = "",
			DebugInfoInTooltips = false,
			AllowedVerbosity = 1,
			LockGearSlots = true,
			LockedGearSlots = TyGearGetDefaultLockedGearSlots()
		}

		TyGearInitializeDB(TyGearDBDefaults)
		TyGearMigrateVendorKeepList()
		TyGearInitializeCharacterSettings()
		TyGearFixLockedGearSlots()

		--initialize options menu variables
		TyGearOptions = {
			{
				["option"] = "Enabled",
				["tab"] = L["Evaluation"],
				["cliCommands"] = { "toggle", "gear", "equip" },
				["cliTrue"] = { "enable", "on", "start" },
				["cliFalse"] = { "disable", "off", "stop" },
				["label"] = L["Automatically equip gear"],
				["description"] = L["Automatically equip gear upgrades, depending on internal stat weights.  These stat weights are currently only configurable by editing the values in the TyGearDefaultWeights table in TyGear.lua.  If this is disabled, TyGear will still scan for gear when receiving new items and viewing loot rolls, but will never equip an item automatically."],
				["toggleDescriptionTrue"] = L["Automatic gearing is now enabled."],
				["toggleDescriptionFalse"] = L["Automatic gearing is now disabled.  You can still manually scan bags for upgrades with the options menu button or \"/tg scan\"."],
				["togglePostHook"] = function() TyGearUpdateBestItems() end
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
				["description"] = L["Automatically sell all grey items when interacting with a vendor.  Hold Shift while opening the vendor to skip selling that time.\n\nTyGear keeps greys it would equip as upgrades, quest items, greys the current vendor accepts as payment, greys vendors refuse to buy, and item IDs on the keep list.  It stops selling when the vendor doesn't buy items or you can't hold more gold."],
				["toggleDescriptionTrue"] = L["Automatic selling of grey items is now enabled."],
				["toggleDescriptionFalse"] = L["Automatic selling of grey items is now disabled."]
			},
			{
				["option"] = "AutoSellUnsuitableWhites",
				["tab"] = L["Vendor"],
				["section"] = L["Selling"],
				["cliCommands"] = { "sellunsuitable", "unsuitablewhites" },
				["cliTrue"] = { "enable", "on", "start" },
				["cliFalse"] = { "disable", "off", "stop" },
				["label"] = L["Automatically sell unsuitable whites"],
				["description"] = L["Automatically sell white weapons and armor your class can't equip when interacting with a vendor.  Hold Shift while opening the vendor to skip selling that time.\n\nTyGear keeps quest items, items the current vendor accepts as payment, items it would equip as upgrades, tabards, and the keep list.  Fishing poles and profession equipment are always kept.  A level requirement alone does not count as unsuitable, since you will be able to wear the item later.  It stops selling when the vendor doesn't buy items or you can't hold more gold."],
				["toggleDescriptionTrue"] = L["Automatic selling of unsuitable white items is now enabled."],
				["toggleDescriptionFalse"] = L["Automatic selling of unsuitable white items is now disabled."]
			},
			{
				["option"] = "AutoSellAllWhiteGear",
				["tab"] = L["Vendor"],
				["section"] = L["Selling"],
				["cliCommands"] = { "sellwhitegear", "whitegear" },
				["cliTrue"] = { "enable", "on", "start" },
				["cliFalse"] = { "disable", "off", "stop" },
				["label"] = L["Automatically sell all white gear"],
				["description"] = L["Automatically sell all white weapons and armor when interacting with a vendor, including pieces you can equip.  Hold Shift while opening the vendor to skip selling that time.\n\nTyGear keeps quest items, items the current vendor accepts as payment, items it would equip as upgrades, tabards, and the keep list.  Fishing poles and profession equipment are always kept.  It stops selling when the vendor doesn't buy items or you can't hold more gold."],
				["toggleDescriptionTrue"] = L["Automatic selling of all white gear is now enabled."],
				["toggleDescriptionFalse"] = L["Automatic selling of all white gear is now disabled."]
			},
			{
				["option"] = "VendorKeepList",
				["tab"] = L["Vendor"],
				["section"] = L["Keep"],
				["editBox"] = true,
				["label"] = L["Keep list"],
				["description"] = L["Item IDs separated by commas.  Greys and common (white) items listed here are kept when selling.\n\nThe list starts with crafting tools such as Skinning Knife, Mining Pick, Blacksmith Hammer, Arclight Spanner, Gyromatic Micro-Adjustor, Flint and Tinder, Gnomish Army Knife, Jeweler's Kit, Virtuoso Inking Set, Herbalist's Spade, and enchanting rods.  Every fishing pole is kept even if its item ID is removed from this list.\n\nShift-click an item while this box has focus to add it, or look up item IDs in item tooltips while the TyGear options are open."]
			},
			{
				["option"] = "KeepKeeperTahultPetItems",
				["tab"] = L["Vendor"],
				["section"] = L["Keep"],
				["label"] = L["Keep greys needed for Keeper Ta'hult's pets"],
				["description"] = L["Don't sell the grey items that Keeper Ta'hult in Oribos takes as payment for the Baubleworm pets."],
				["toggleDescriptionTrue"] = L["Keeping greys needed for Keeper Ta'hult's pets is now enabled."],
				["toggleDescriptionFalse"] = L["Keeping greys needed for Keeper Ta'hult's pets is now disabled."]
			},
			{
				["option"] = "KeepUnboundGreyGear",
				["tab"] = L["Vendor"],
				["section"] = L["Keep"],
				["label"] = L["Keep unbound grey gear"],
				["description"] = L["Don't sell grey weapons and armor which aren't soulbound, for example to sell them on the auction house instead."],
				["toggleDescriptionTrue"] = L["Keeping unbound grey gear is now enabled."],
				["toggleDescriptionFalse"] = L["Keeping unbound grey gear is now disabled."]
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
				["option"] = "UsePawn",
				["tab"] = L["Evaluation"],
				["cliCommands"] = { "pawn", "usepawn" },
				["cliTrue"] = { "enable", "on", "start" },
				["cliFalse"] = { "disable", "off", "stop" },
				["label"] = L["Use Pawn to evaluate upgrades"],
				["description"] = L["If Pawn (gear evaluation addon) is installed and configured, use a Pawn scale instead of TyGear's internal stat weights for evaluating gear upgrades.  TyGear will use the Pawn scale with a name matching the \"[class]: [spec]\" format; example \"Paladin: Retribution\". If \"Override specialization\" is also enabled, that class and spec will be used for detecting which Pawn scale name to use instead. Visible scales (not hidden in Pawn's settings) will be prioritized when detecting which scale to use."]..(((PawnIsReady ~= nil) and PawnIsReady()) and "" or "\n\n"..RED_FONT_COLOR_CODE..L["Pawn is not running, so this option will do nothing."]..FONT_COLOR_CODE_CLOSE),
				["toggleDescriptionTrue"] = L["Using Pawn for evaluating gear upgrades is now enabled."],
				["toggleDescriptionFalse"] = L["Using Pawn for evaluating gear upgrades is now disabled."],
				["togglePostHook"] = function() TyGearUpdateBestItems() end
			},
			{
				["option"] = "OverridePawnScale",
				["tab"] = L["Evaluation"],
				["shouldUse"] = ((PawnIsReady ~= nil) and PawnIsReady()),
				["cliCommands"] = { "scale", "overridepawn", "overridepawnscale" },
				["cliTrue"] = { "enable", "on", "start" },
				["cliFalse"] = { "disable", "off", "stop" },
				["label"] = L["Override Pawn scale"],
				["description"] = L["Override the Pawn scale that would normally be automatically detected in \"[class]: [spec]\" format with the Pawn scale chosen in this dropdown.\n\nThis override does nothing unless \"Use Pawn to evaluate upgrades\" is enabled."],
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
				["option"] = "LockGearSlots",
				["tab"] = L["Evaluation"],
				["cliCommands"] = { "lock", "lockslots", "lockgearslots" },
				["cliTrue"] = { "enable", "on", "start" },
				["cliFalse"] = { "disable", "off", "stop" },
				["label"] = L["Lock specified gear slots"],
				["description"] = L["Lock the specified gear slots, so TyGear will not remove or equip items in those slots.  If this is enabled and any slots are locked, TyGear will still evaluate scores for items in all slots, but will not remove or equip items in the locked slots."],
				["toggleDescriptionTrue"] = L["Locking specified gear slots is now enabled."],
				["toggleDescriptionFalse"] = L["Locking specified gear slots is now disabled."],
				["togglePostHook"] = function() TyGearUpdateBestItems() end,
				["child"] = {
					["option"] = "LockedGearSlots",
					["options"] = TyGearGetLockedGearSlots(),
					["label"] = "Gear slots to lock",
					["description"] = "Choose which gear slots to lock in this dropdown."
				}
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
			}
		}

		if (not TyGearDB.LockedGearSlots) or (#TyGearDB.LockedGearSlots == 0) then
			TyGearDB.LockedGearSlots = TyGearGetDefaultLockedGearSlots()
		end
		optionsSetup(optionsMenu)
		if not optionsMenuParent.ignoreSectionHooked then
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
		pcall(TyGearFrame.RegisterEvent,TyGearFrame,"CONFIRM_DISENCHANT_ROLL")

		TyGearFrame:SetScript("OnUpdate", TyGearMain)
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
		local usingPawn = TyGearDB.UsePawn and PawnIsReady and PawnIsReady()
		local pawnScaleName = ""
		local pawnScaleLocalizedName = ""
		if usingPawn then
			pawnScaleName, pawnScaleLocalizedName = TyGearGetPawnScaleName()
		end
		TyGearPrint("TyGear: Looks like you are a"..(realSpec:find("^[AEIOUaeiou]") and "n " or " ")..RAID_CLASS_COLORS[realClass]:WrapTextInColorCode(realSpec.." "..localizedRealClass).."."..((usingPawn or (TyGearCharDB.Override and ((realClassID ~= overrideClassID) or (realSpec ~= overrideSpec)))) and ("  However, TyGear is using "..(usingPawn and ("Pawn scale \""..PawnGetScaleColor(pawnScaleName)..(pawnScaleLocalizedName or pawnScaleName)..FONT_COLOR_CODE_CLOSE.."\"") or (RAID_CLASS_COLORS[overrideClass]:WrapTextInColorCode(overrideSpec.." "..localizedOverrideClass).." weights")).." for gear evaluation due to the \""..(usingPawn and "Use Pawn to evaluate upgrades" or "Override specialization").."\" option.") or "").."  TyGear is using weapons value \""..weapons.."\" from \""..((TyGearCharDB.Override and ((realClassID ~= overrideClassID) or (realSpec ~= overrideSpec))) and (RAID_CLASS_COLORS[overrideClass]:WrapTextInColorCode(overrideSpec.." "..localizedOverrideClass)) or (RAID_CLASS_COLORS[realClass]:WrapTextInColorCode(realSpec.." "..localizedRealClass))).."\" to determine which weapons are valid.  CanDualWield() returns \""..(CanDualWield() and "true" or "false").."\".", 0) 
		if IS_WOW_FOREVER and (not TyGearCharDB.Override) then
			TyGearPrint("TyGear: WoW Forever has one specialization per class, so TyGear uses the general class profile.  Enable \"Override specialization\" in \"/tg\" to use a healer, tank, or focused damage profile.", 0)
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
		if class and TyGearDefaultWeights[class][spec] then
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

					TyGearPrint("TyGear: "..(TyGearDB.UsePawn and "" or "While using Pawn is enabled, ").."TyGear will now use the \""..PawnGetScaleColor(truePawnScaleName)..(pawnScaleLocalizedName or truePawnScaleName)..FONT_COLOR_CODE_CLOSE.."\" Pawn scale to evaluate gear.",0)
				else
					TyGearPrint("TyGear: According to Pawn, a Pawn scale named \""..userPawnScaleName.."\" does not exist.",0)
				end
			else
				TyGearPrint("TyGear: Pawn is not ready yet.",0)
			end
		else
			TyGearPrint("TyGear: Pawn is not installed.",0)
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
	TyGearPrint("TyGear:    '/tg': options menu, including the Ignore section for equipment slots and items", 0)
	TyGearPrint("TyGear:    '/tg help': command line help", 0)
	TyGearPrint("TyGear:    '/tg scan': scan all bags for gear upgrades", 0)
	TyGearPrint("TyGear:    '/tg spec': get name of current talent specialization", 0)
	TyGearPrint("TyGear:    '/tg [gear/toggle]/[enable/on/start]/[disable/off/stop]': toggle automatic gearing", 0)
	TyGearPrint("TyGear:    '/tg roll [enable/on/start]/[disable/off/stop]': toggle automatic loot rolling", 0)
	TyGearPrint("TyGear:    '/tg bind [enable/on/start]/[disable/off/stop]': toggle automatic soul-binding confirmation", 0)
	TyGearPrint("TyGear:    '/tg neverneed [enable/on/start]/[disable/off/stop]': toggle preventing automatically rolling NEED", 0)
	TyGearPrint("TyGear:    '/tg tooltip [toggle/show/hide]': toggle showing score in item tooltips", 0)
	TyGearPrint("TyGear:    '/tg reasons [toggle/show/hide]': toggle showing won't-auto-equip reasons in item tooltips", 0)
	TyGearPrint("TyGear:    '/tg compare [enable/on/start]/[disable/off/stop]': toggle always comparing gear", 0)
	TyGearPrint("TyGear:    '/tg override [enable/on/start]/[disable/off/stop]': toggle specialization override", 0)
	TyGearPrint("TyGear:    '/tg overridespec [class]: [spec]': set override spec to \"[class]: [spec]\"",0)
	TyGearPrint("TyGear:    '/tg pawn [enable/on/start]/[disable/off/stop]': toggle using Pawn scales", 0)
	TyGearPrint("TyGear:    '/tg pawnscale [Pawn scale name]': set Pawn scale override to the specifed Pawn scale", 0)
	TyGearPrint("TyGear:    '/tg sell [enable/on/start]/[disable/off/stop]': toggle automatic selling of grey items", 0)
	TyGearPrint("TyGear:    '/tg sellunsuitable [enable/on/start]/[disable/off/stop]': toggle automatic selling of white gear you can't wear", 0)
	TyGearPrint("TyGear:    '/tg sellwhitegear [enable/on/start]/[disable/off/stop]': toggle automatic selling of all white gear", 0)
	TyGearPrint("TyGear:    '/tg verbosity [0/1/2/3]': set allowed verbosity level; valid levels are: 0 ("..TyGearGetAllowedVerbosityName(0).."), 1 ("..TyGearGetAllowedVerbosityName(1).."), 2 ("..TyGearGetAllowedVerbosityName(2).."), 3 ("..TyGearGetAllowedVerbosityName(3)..")", 0)
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
		TyGearPrint("TyGear: Allowed verbosity level is now: "..tostring(TyGearDB.AllowedVerbosity).." ("..TyGearGetAllowedVerbosityName(TyGearDB.AllowedVerbosity)..").", 0)
	end
end

function TyGearGetContainerItemInfo(bagIndex, bagSlot)
	if GetContainerItemInfo then
		local _, count, locked, quality, _, _, link = GetContainerItemInfo(bagIndex, bagSlot)
		if (link) then
			return count, locked, link
		end
	elseif C_Container and C_Container.GetContainerItemInfo then
		local itemInfo = C_Container.GetContainerItemInfo(bagIndex, bagSlot)
		if itemInfo then
			return itemInfo.stackCount, itemInfo.isLocked, itemInfo.hyperlink
		end
	end
end

TyGearFrame:SetScript("OnEvent", function (this, event, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11, arg12, ...)

	if event == "PLAYER_SPECIALIZATION_CHANGED" and arg1 == "player" then
		local localizedClass, class, spec = TyGearGetClassAndSpec()
		TyGearPrint("TyGear: Talent specialization changed.  Considering all items for gear that's better suited for "..RAID_CLASS_COLORS[class]:WrapTextInColorCode(spec.." "..localizedClass)..".", 2)
		TyGearConsiderAllItems()
	elseif event == "PLAYER_EQUIPMENT_CHANGED" or event == "BAG_CONTAINER_UPDATE" then
		TyGearQueueLocalUpdate()
		if TyGearRefreshIgnoreSection and TyGearOptionsMenuScrollFrame and TyGearOptionsMenuScrollFrame:IsShown() then
			TyGearRefreshIgnoreSection()
		end
	elseif event == "MERCHANT_CLOSED" or event == "PLAYER_LEVEL_UP" then
		if event == "MERCHANT_CLOSED" then
			TyGearStopSellingGreys()
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
		local pattern1 = LOOT_ITEM_SELF_MULTIPLE:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)"):gsub("^", "^")
		local pattern2 = LOOT_ITEM_PUSHED_SELF_MULTIPLE:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)"):gsub("^", "^")
		local pattern3 = LOOT_ITEM_CREATED_SELF_MULTIPLE:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)"):gsub("^", "^")
		local pattern4 = LOOT_ITEM_SELF:gsub("%%s", "(.+)"):gsub("^", "^")
		local pattern5 = LOOT_ITEM_PUSHED_SELF:gsub("%%s", "(.+)"):gsub("^", "^")
		local pattern6 = LOOT_ITEM_CREATED_SELF:gsub("%%s", "(.+)"):gsub("^", "^")

		local link, quantity = message:match(pattern1)
		if not link then
			link, quantity = message:match(pattern2)
			if not link then
				link, quantity = message:match(pattern3)
				if not link then
					link, quantity = message:match(pattern4), 1
					if not link then
						link, quantity = message:match(pattern5), 1
						if not link then
							link, quantity = message:match(pattern6), 1
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
		if (TyGearDB.AutoSellGreys == true)
		or (TyGearDB.AutoSellUnsuitableWhites == true)
		or (TyGearDB.AutoSellAllWhiteGear == true) then
			TyGearStartSellingGreys()
		end
	elseif event ~= "ADDON_LOADED" then
		TyGearPrint("TyGear: event fired: "..event, 3)
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
		if TyGearIsItemIgnored(rollItemInfo) then
			TyGearPrint("TyGear: "..(rollItemInfo.link or link).." is ignored, so not rolling.", 1)
			return nil, rollItemInfo, reason
		end
		if rollItemInfo.isMount then
			TyGearPrint("TyGear: "..(rollItemInfo.link or link).." is a mount, so not rolling.", 1)
			return nil, rollItemInfo, reason
		end
		local wouldNeed = TyGearConsiderAllItems(lootRollItemID, rollItemInfo, true)
		if TyGearAllValidGearSlotsProtected(rollItemInfo) then
			TyGearPrint("TyGear: "..(rollItemInfo.link or link).." only fits ignored slots, so not rolling.", 1)
			return nil, rollItemInfo, reason
		end
		if (TyGearDB.RollOnNonGearLoot == false)
		and (not rollItemInfo.isGear) then
			TyGearPrint("TyGear: "..rollItemInfo.link.." is not gear and \"Roll on non-gear loot\" is disabled, so not rolling.", 3)
			--local rollDecision is nil, so no roll
		elseif wouldNeed and canNeed then
			if rollItemInfo.Within5levels or (not rollItemInfo.unusable) then
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
			table.insert(TyGearActionQueue, newAction)
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

--reads item IDs from text containing item IDs and item links, in order and without duplicates
function TyGearParseItemIDList(text)
	--item links hold other numbers too (enchants, bonus IDs, digits in item names), so reduce each link to its item ID first
	text = string.gsub(text, "|c[^|]*|Hitem:(%d+)[^|]*|h.-|h|r", " %1 ")
	text = string.gsub(text, "|Hitem:(%d+)[^|]*|h.-|h", " %1 ")
	local itemIDs, isListed = {}, {}
	for itemIDText in string.gmatch(text, "%d+") do
		local itemID = tonumber(itemIDText)
		if (itemID > 0) and (not isListed[itemID]) then
			isListed[itemID] = true
			table.insert(itemIDs, itemID)
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
	--preserve a customized whites ignore list; otherwise start from the crafting-tool defaults
	if TyGearDB.SellWhitesIgnoreList ~= nil then
		addList(TyGearDB.SellWhitesIgnoreList)
	else
		addList(table.concat(TyGearCraftingToolItemIDs, ", "))
	end
	addList(TyGearDB.SellGreysExclusions)
	TyGearDB.VendorKeepList = table.concat(ordered, ", ")
	TyGearDB.SellGreysExclusions = nil
	TyGearDB.SellWhitesIgnoreList = nil
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

--weapons and armor a vendor pass may sell. Tabards stay, including the guild tabard, which is white.
function TyGearIsVendorWhiteGear(classID, equipLoc)
	if (classID ~= Enum.ItemClass.Weapon) and (classID ~= Enum.ItemClass.Armor) then
		return false
	end
	if (not equipLoc) or (equipLoc == "") or (equipLoc == "INVTYPE_NON_EQUIP")
	or (equipLoc == "INVTYPE_TABARD") or (equipLoc == "INVTYPE_BAG")
	or (equipLoc == "INVTYPE_QUIVER") or (equipLoc == "INVTYPE_AMMO")
	or (equipLoc == "INVTYPE_PROFESSION_TOOL") or (equipLoc == "INVTYPE_PROFESSION_GEAR") then
		return false
	end
	return true
end

--crafting tools, the keep list, fishing poles, and profession equipment stay when selling whites
function TyGearIsKeptVendorItem(itemID, classID, subclassID)
	if greySelling.keptItemIDs[itemID] then return true end
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
function TyGearShouldSellWhiteGear(itemID, link, classID, subclassID, equipLoc)
	if (TyGearDB.AutoSellUnsuitableWhites ~= true) and (TyGearDB.AutoSellAllWhiteGear ~= true) then
		return false
	end
	if TyGearIsKeptVendorItem(itemID, classID, subclassID) then return false end
	if greySelling.merchantCostItemIDs[itemID] then return false end
	if not TyGearIsVendorWhiteGear(classID, equipLoc) then return false end
	if TyGearDB.AutoSellAllWhiteGear == true then return true end
	local canEquip = TyGearPlayerCanEquipItem(itemID, link)
	return canEquip == false
end

--returns the sale value, link, and quality of the item in a bag slot if it should be sold to a vendor, or nil to keep it
function TyGearGetItemSaleValue(bag, slot)
	local count, locked, link = TyGearGetContainerItemInfo(bag, slot)
	if (not link) or locked then return end
	--battle pets have battlepet: links and can't be sold
	local itemID = tonumber(string.match(link, "item:(%d+)"))
	if not itemID then return end
	if TyGearIsItemIgnored(itemID) then return end
	local _, _, quality, _, _, _, _, _, equipLoc, _, sellPrice, classID, subclassID = GetItemInfo(link)
	if (not quality) or (not sellPrice) or (sellPrice <= 0) then return end

	--keep list is all-inclusive for greys and common (white) item IDs
	if greySelling.keptItemIDs[itemID] then return end

	if quality == 0 then
		--a white-gear pass must not sell greys unless that option is on
		if TyGearDB.AutoSellGreys ~= true then return end
		if TyGearUnsellableGreyItemIDs[itemID]
		or (TyGearDB.KeepKeeperTahultPetItems and TyGearKeeperTahultPetGreyItemIDs[itemID])
		or greySelling.merchantCostItemIDs[itemID] then
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
	elseif quality == 1 then
		if not TyGearShouldSellWhiteGear(itemID, link, classID, subclassID, equipLoc) then
			return
		end
	else
		return
	end

	if greySelling.upgradeBagSlots[bag..":"..slot] then return end
	--an item whose tooltip can't be read can't be ruled out as a quest item
	local isQuestItem, isTooltipUnreadable = TyGearIsQuestItem(bag, slot)
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

function TyGearFormatVendorSaleSummary(greyCount, whiteCount, soldValue)
	local cash = TyGearCashToString(soldValue)
	local greyText = greyCount.." grey item"..((greyCount == 1) and "" or "s")
	local whiteText = whiteCount.." white item"..((whiteCount == 1) and "" or "s")
	if (greyCount > 0) and (whiteCount > 0) then
		return "TyGear: Sold "..greyText.." and "..whiteText.." for "..cash.."."
	elseif greyCount > 0 then
		return "TyGear: Sold "..greyText.." for "..cash.."."
	elseif whiteCount > 0 then
		return "TyGear: Sold "..whiteText.." for "..cash.."."
	end
end

function TyGearStartSellingGreys()
	if greySelling then TyGearStopSellingGreys() end
	if IsShiftKeyDown() then
		TyGearPrint(TyGearVendorShiftSkipMessage(), 2)
		return
	end

	greySelling = {
		sales = {},
		soldValue = 0,
		soldCount = 0,
		soldGreyCount = 0,
		soldWhiteCount = 0,
		sellsGreys = (TyGearDB.AutoSellGreys == true),
		sellsWhites = (TyGearDB.AutoSellUnsuitableWhites == true) or (TyGearDB.AutoSellAllWhiteGear == true),
		keptItemIDs = {},
		merchantCostItemIDs = {},
		upgradeBagSlots = {},
	}
	for _, itemID in ipairs(TyGearParseItemIDList(TyGearDB.VendorKeepList or "")) do
		greySelling.keptItemIDs[itemID] = true
	end
	--keep items this vendor takes as payment for its goods
	for merchantIndex = 1, GetMerchantNumItems() do
		for costIndex = 1, (GetMerchantItemCostInfo(merchantIndex) or 0) do
			local _, _, costLink = GetMerchantItemCostItem(merchantIndex, costIndex)
			local costItemID = costLink and tonumber(string.match(costLink, "item:(%d+)"))
			if costItemID then
				greySelling.merchantCostItemIDs[costItemID] = true
			end
		end
	end
	--keep gear which TyGear would equip as upgrades, including white gear
	TyGearUpdateBestItems()
	for _, bestItem in pairs(TyGearBestItems) do
		if bestItem.bag and bestItem.slot then
			greySelling.upgradeBagSlots[bestItem.bag..":"..bestItem.slot] = true
		end
	end

	TyGearFrame:RegisterEvent("UI_ERROR_MESSAGE")
	table.insert(TyGearActionQueue, { action = "sellgreys", t = 0.0 })
end

function TyGearStopSellingGreys(reason)
	if not greySelling then return end
	TyGearSettleGreySales()
	TyGearFrame:UnregisterEvent("UI_ERROR_MESSAGE")
	if greySelling.soldCount > 0 then
		TyGearPrint(TyGearFormatVendorSaleSummary(greySelling.soldGreyCount, greySelling.soldWhiteCount, greySelling.soldValue), 1)
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
		table.insert(TyGearActionQueue, { action = "sellgreys", t = 0.0 })
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

function TyGearIsQuestItem(container, slot)
	return TyGearItemContainsText(container, slot, ITEM_BIND_QUEST or "Quest Item")
end

--returns whether a left-side line of the bag item's tooltip is exactly the search text; the second return value is true when the tooltip couldn't be read
function TyGearItemContainsText(container, slot, search)
	TyGearTooltip:SetOwner(UIParent, "ANCHOR_NONE")
	TyGearTooltip:ClearLines()
	TyGearTooltip:SetBagItem(container, slot)
	for i=1, TyGearTooltip:NumLines() do
		local mytext = _G["TyGearTooltipTextLeft" .. i]
		if (mytext) then
			local text = mytext:GetText()
			--tooltip text can be a secret value under the Midnight addon restrictions; it can't be compared then
			if issecretvalue and issecretvalue(text) then
				return nil, true
			end
			if (text == search) then
				return 1
			end
		end
	end
	return nil
end

function TyGearUpdateEquippedItem(invSlot)
	local info, score
	info = TyGearReadItemInfo(invSlot)
	score = TyGearDetermineItemScore(info)
	TyGearEquippedItems[invSlot] = {}
	TyGearEquippedItems[invSlot].info = info
	TyGearEquippedItems[invSlot].score = score
	TyGearEquippedItems[invSlot].equipped = 1
end

function TyGearUpdateEquippedItems()
	TyGearSetStatWeights()
	-- TyGearItemInfoCache = {}
	TyGearEquippedItems = {}
	local info, score
	for invSlot = INVSLOT_FIRST_EQUIPPED, TyGearLastEquippableBagSlot do
		if invSlot <= INVSLOT_LAST_EQUIPPED or invSlot >= TyGearFirstEquippableBagSlot then
			TyGearUpdateEquippedItem(invSlot)
		end
	end

	--pretend the tabard slot is a separate slot for 2-handers
	if (TyGearEquippedItems[INVSLOT_MAINHAND] and
	TyGearEquippedItems[INVSLOT_MAINHAND].info and
	TyGearEquippedItems[INVSLOT_MAINHAND].info.is2hWeapon and
	(not ((weapons == "2hDW") and CanDualWield() and IsPlayerSpell(46917)))) then
		TyGearEquippedItems[INVSLOT_TABARD] = TyGearDeepCopy(TyGearEquippedItems[INVSLOT_MAINHAND])
		TyGearEquippedItems[INVSLOT_MAINHAND].info = { name = "nothing", empty = 1 }
		TyGearEquippedItems[INVSLOT_MAINHAND].score = 0
		TyGearEquippedItems[INVSLOT_MAINHAND].equipped = nil
	else
		TyGearEquippedItems[INVSLOT_TABARD] = {}
		TyGearEquippedItems[INVSLOT_TABARD].info = { name = "nothing", empty = 1 }
		TyGearEquippedItems[INVSLOT_TABARD].score = 0
		TyGearEquippedItems[INVSLOT_TABARD].equipped = nil
	end
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

function TyGearUpdateBestItems()
	TyGearUpdateEquippedItems()

	--set starting best scores from all equipped items
	TyGearBestItems = TyGearDeepCopy(TyGearEquippedItems)

	local info

	-- table to track whether an item's been added
	TyGearBestItemsAlreadyAdded = {}

	--consider all items in bags
	for bag = 0, NUM_BAG_SLOTS do
		local slotMax = GetContainerNumSlots(bag)
		for slot = 0, slotMax do
			info = TyGearReadItemInfo(nil, nil, bag, slot)
			-- TyGearPrint((info.link or info.name or "nil").." bag and slot: "..tostring(bag or "nil").." "..tostring(slot or "nil"),0)
			TyGearConsiderItem(info, bag, slot, nil)
		end
	end
end

function TyGearConsiderAllItems(lootRollItemID, arbitraryItemInfo, noActions)
	local anythingBetter = nil

	TyGearUpdateBestItems()

	--consider item being rolled on (if any)
	if lootRollItemID and arbitraryItemInfo then
		TyGearConsiderItem(arbitraryItemInfo, nil, nil, 1)
	end

	--create all future equip actions required (only if not rolling currently)
	if (not lootRollItemID and not noActions) then
		for invSlot = INVSLOT_FIRST_EQUIPPED, TyGearLastEquippableBagSlot do
			if invSlot <= INVSLOT_LAST_EQUIPPED or invSlot >= TyGearFirstEquippableBagSlot then
				if invSlot == INVSLOT_MAINHAND or invSlot == INVSLOT_OFFHAND or invSlot == INVSLOT_TABARD then
					--skip weapons for now
				else
					local isSlotLocked = TyGearDB.LockGearSlots and TyGearDB.LockedGearSlots[invSlot].enabled
					local equippedInfo = TyGearEquippedItems[invSlot].info
					local equippedScore = TyGearEquippedItems[invSlot].score
					if (not TyGearIsGearSlotProtected(invSlot)) and (not TyGearBestItems[invSlot].equipped) then
						anythingBetter = 1
						TyGearPrint("TyGear: "..(TyGearBestItems[invSlot].info.link or TyGearBestItems[invSlot].info.name).." ("..string.format("%.2f", TyGearBestItems[invSlot].score)..") was determined to be better than "..(equippedInfo.link or equippedInfo.name).." ("..string.format("%.2f", equippedScore)..").  "..((TyGearDB.Enabled == true) and (isSlotLocked and "Would equip, but slot "..tostring(invSlot or "nil").." is locked." or "Equipping.") or "Would equip if automatic gear equipping was enabled."), 1)
						TyGearPrintItem(TyGearBestItems[invSlot].info)
						TyGearPrintItem(equippedInfo)
						if not isSlotLocked then
							local newAction = {}
							newAction.action = "equip"
							newAction.t = GetTime()
							newAction.container = TyGearBestItems[invSlot].bag
							newAction.slot = TyGearBestItems[invSlot].slot
							newAction.replaceSlot = invSlot
							newAction.info = TyGearBestItems[invSlot].info
							newAction.score = TyGearBestItems[invSlot].score
							table.insert(TyGearActionQueue, newAction)
						end
					end
				end
			end
		end
		--handle weapons
		local isMainHandSlotLocked = TyGearDB.LockGearSlots and TyGearDB.LockedGearSlots[INVSLOT_MAINHAND].enabled
		local isOffHandSlotLocked = TyGearDB.LockGearSlots and TyGearDB.LockedGearSlots[INVSLOT_OFFHAND].enabled
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
					table.insert(TyGearActionQueue, newAction)
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
					table.insert(TyGearActionQueue, newAction)
				end
			end
			if (mainSwap or offSwap) then
				anythingBetter = 1
				if (mainSwap and offSwap) then
					if (TyGearIsTwoHandEquipped()) then
						local equippedMain = TyGearEquippedItems[INVSLOT_TABARD].info
						local mainScore = TyGearEquippedItems[INVSLOT_TABARD].score
						TyGearPrint("TyGear: "..(TyGearBestItems[INVSLOT_MAINHAND].info.link or TyGearBestItems[INVSLOT_MAINHAND].info.name).." ("..string.format("%.2f", TyGearBestItems[INVSLOT_MAINHAND].score)..") combined with "..(TyGearBestItems[INVSLOT_OFFHAND].info.link or TyGearBestItems[INVSLOT_OFFHAND].info.name).." ("..string.format("%.2f", TyGearBestItems[INVSLOT_OFFHAND].score)..") was determined to be better than "..(equippedMain.link or equippedMain.name).." ("..string.format("%.2f", mainScore)..").  "..((TyGearDB.Enabled == true) and ((isMainHandSlotLocked or isOffHandSlotLocked) and "Would equip, but slot "..tostring((isMainHandSlotLocked and INVSLOT_MAINHAND or INVSLOT_OFFHAND) or "nil").." is locked." or "Equipping.") or "Would equip if automatic gear equipping was enabled."), 1)
						TyGearPrintItem(TyGearBestItems[INVSLOT_MAINHAND].info)
						TyGearPrintItem(TyGearBestItems[INVSLOT_OFFHAND].info)
						TyGearPrintItem(equippedMain)
					else
						local equippedMain = TyGearEquippedItems[INVSLOT_MAINHAND].info
						local mainScore = TyGearEquippedItems[INVSLOT_MAINHAND].score
						local equippedOff = TyGearEquippedItems[INVSLOT_OFFHAND].info
						local offScore = TyGearEquippedItems[INVSLOT_OFFHAND].score
						TyGearPrint("TyGear: "..(TyGearBestItems[INVSLOT_MAINHAND].info.link or TyGearBestItems[INVSLOT_MAINHAND].info.name).." ("..string.format("%.2f", TyGearBestItems[INVSLOT_MAINHAND].score)..") combined with "..(TyGearBestItems[INVSLOT_OFFHAND].info.link or TyGearBestItems[INVSLOT_OFFHAND].info.name).." ("..string.format("%.2f", TyGearBestItems[INVSLOT_OFFHAND].score)..") was determined to be better than "..(equippedMain.link or equippedMain.name).." ("..string.format("%.2f", mainScore)..") combined with "..(equippedOff.link or equippedOff.name).." ("..string.format("%.2f", offScore)..").  "..((TyGearDB.Enabled == true) and ((isMainHandSlotLocked or isOffHandSlotLocked) and "Would equip, but slot "..tostring((isMainHandSlotLocked and INVSLOT_MAINHAND or INVSLOT_OFFHAND) or "nil").." is locked." or "Equipping.") or "Would equip if automatic gear equipping was enabled."), 1)
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
					TyGearPrint("TyGear: "..(TyGearBestItems[invSlot].info.link or TyGearBestItems[invSlot].info.name).." ("..string.format("%.2f", TyGearBestItems[invSlot].score)..") was determined to be better than "..(equippedInfo.link or equippedInfo.name).." ("..string.format("%.2f", equippedScore)..").  "..((TyGearDB.Enabled == true) and (((invSlot == INVSLOT_MAINHAND and isMainHandSlotLocked) or (invSlot == INVSLOT_OFFHAND and isOffHandSlotLocked)) and "Would equip, but slot "..tostring((isMainHandSlotLocked and INVSLOT_MAINHAND or INVSLOT_OFFHAND) or "nil").." is locked." or "Equipping.") or "Would equip if automatic gear equipping was enabled."), 1)
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
				TyGearPrint("TyGear: "..(TyGearBestItems[INVSLOT_TABARD].info.link or TyGearBestItems[INVSLOT_TABARD].info.name).." ("..string.format("%.2f", TyGearBestItems[INVSLOT_TABARD].score)..") was determined to be better than "..(equippedMain.link or equippedMain.name).." ("..string.format("%.2f", mainScore)..")"..(showBothSlots and ((" combined with "..(equippedOff.link or equippedOff.name).." ("..string.format("%.2f", offScore))..")") or "")..".  "..((TyGearDB.Enabled == true) and ((isMainHandSlotLocked or isOffHandSlotLocked) and "Would equip, but slot "..tostring((isMainHandSlotLocked and INVSLOT_MAINHAND or INVSLOT_OFFHAND) or "nil").." is locked." or "Equipping.") or "Would equip if automatic gear equipping was enabled."), 1)
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
					table.insert(TyGearActionQueue, newAction)
				end
			end
		end
	elseif (lootRollItemID) then
		--decide whether to roll on the item or not
		for invSlot = INVSLOT_FIRST_EQUIPPED, TyGearLastEquippableBagSlot do
			if invSlot <= INVSLOT_LAST_EQUIPPED or invSlot >= TyGearFirstEquippableBagSlot then
				if (TyGearBestItems[invSlot].rollOn and
				(invSlot ~= INVSLOT_MAINHAND or invSlot ~= INVSLOT_OFFHAND or TyGearIs1hWorthwhile(invSlot)) and
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
	local minScore = 3 * math.max(unpack({
		TyGearCurrentWeighting.Strength or 0,
		TyGearCurrentWeighting.Agility or 0,
		TyGearCurrentWeighting.Stamina or 0,
		TyGearCurrentWeighting.Intellect or 0,
		TyGearCurrentWeighting.Spirit or 0}))
	return TyGearBestItems[i].score > minScore and TyGearBestItems[i].score > TyGearBestItems[INVSLOT_TABARD].score * (i == INVSLOT_MAINHAND and 0.15 or 0.05)
end

--companion function to TyGearConsiderAllItems
function TyGearConsiderItem(info, bag, slot, rollOn)
	if info.empty
	or TyGearIsItemIgnored(info)
	or (info.guid and TyGearBestItemsAlreadyAdded[info.guid])
	or (info.isAmmoBag
	and	TyGearBestItems[INVSLOT_RANGED].info.isRangedWeapon)
	and (not TyGearIsAmmoBagValidForRangedWeapon(info, TyGearBestItems[INVSLOT_RANGED].info)) then
		return
	end
	if (info.usable or (rollOn and info.Within5levels)) then
		local score = TyGearDetermineItemScore(info)
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
				local skipThisSlot = false
				for _, otherGearSlot in pairs(info.validGearSlots) do
					if gearSlot ~= otherGearSlot then
						if not TyGearIsGearPairEquippableTogether(info, TyGearBestItems[otherGearSlot].info) then
							skipThisSlot = true
						end
					end
				end
				if not skipThisSlot and
				((not TyGearBestItems[gearSlot]) or
				(TyGearBestItems[gearSlot].info.empty or
				(not TyGearBestItems[gearSlot].score) or
				(TyGearBestItems[gearSlot].score < lowestScoringValidGearSlotScore))) then
					lowestScoringValidGearSlot = gearSlot
					lowestScoringValidGearSlotScore = TyGearBestItems[gearSlot] and TyGearBestItems[gearSlot].score or 0
				end
				end
			end

			if (
				((score > lowestScoringValidGearSlotScore) and (not info.isAmmoBag))
				or TyGearBestItems[lowestScoringValidGearSlot].info.empty
				or TyGearBestItems[lowestScoringValidGearSlot].info.unusable
				or (info.isAmmoBag
					and TyGearIsAmmoBagValidForBestKnownRangedWeapon(info)
					and ((score > lowestScoringValidGearSlotScore)
					or (not TyGearIsAmmoBagValidForBestKnownRangedWeapon(TyGearBestItems[lowestScoringValidGearSlot].info)))
				)
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
	local gearSlotTable = {
		[Enum.InventoryType.IndexNonEquipType]       = nil,
		[Enum.InventoryType.IndexAmmoType]           = nil, -- ignore ammo because it's hard to match with weapon type
		[Enum.InventoryType.IndexHeadType]           = { INVSLOT_HEAD },
		[Enum.InventoryType.IndexNeckType]           = { INVSLOT_NECK },
		[Enum.InventoryType.IndexShoulderType]       = { INVSLOT_SHOULDER },
		[Enum.InventoryType.IndexBodyType]           = { INVSLOT_BODY },
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
		[Enum.InventoryType.IndexBagType]            = TyGearEquippableBagSlots,
		[Enum.InventoryType.IndexQuiverType]         = (weapons == "ranged")
		                                               and TyGearEquippableBagSlots
                                                       or nil
	}

	return gearSlotTable[info.invType]
end

-- indicates slots that go together as a set
-- for example, the set of slots for a shield is { main-hand and off-hand } even though the shield can only be equipped in the off-hand
-- this is useful to find which slots to use to add scores together from all items in those slots
function TyGearGetSetSlots(info)
	local setSlotTable = {
		[Enum.InventoryType.IndexNonEquipType]       = nil,
		[Enum.InventoryType.IndexAmmoType]           = nil, -- ignore ammo because it's hard to match with weapon type
		[Enum.InventoryType.IndexHeadType]           = { INVSLOT_HEAD },
		[Enum.InventoryType.IndexNeckType]           = { INVSLOT_NECK },
		[Enum.InventoryType.IndexShoulderType]       = { INVSLOT_SHOULDER },
		[Enum.InventoryType.IndexBodyType]           = { INVSLOT_BODY },
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
		[Enum.InventoryType.IndexBagType]            = TyGearEquippableBagSlots,
		[Enum.InventoryType.IndexQuiverType]         = (weapons == "ranged")
		                                               and TyGearEquippableBagSlots
                                                       or nil
	}

	return setSlotTable[info.invType]
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
	if TyGearDB.UsePawn and PawnIsReady and PawnIsReady() then
		local pawnScaleName, pawnScaleLocalizedName = TyGearGetPawnScaleName()
		local pawnScaleColor = PawnGetScaleColor(pawnScaleName)
		local score = TyGearDetermineItemScore(info)
		-- 3 decimal places max
		score = math.floor(score * 1000) / 1000
		TyGearPrint("TyGear:         "..(((pawnScaleLocalizedName or pawnScaleName) and pawnScaleColor) and ("Pawn \""..pawnScaleColor..(pawnScaleLocalizedName or pawnScaleName)..FONT_COLOR_CODE_CLOSE.."\"") or "TyGear").." score: "..(score or "nil"),2)
	elseif (not (TyGearDB.UsePawn and PawnIsReady and PawnIsReady())) then
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

function TyGearReadItemInfo(inventoryID, lootRollID, container, slot, link, tooltipData)
	if not tooltipData then
		TyGearTooltip:SetOwner(UIParent, "ANCHOR_NONE")
		TyGearTooltip:ClearLines()
	end

	local info = {}

	info.link = link

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
		if not tooltipData then tooltipData = C_TooltipInfo and C_TooltipInfo.GetBagItem(container, slot) end
		if not tooltipData then TyGearTooltip:SetBagItem(container, slot) end
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
		if not tooltipData then
			if C_TooltipInfo and C_TooltipInfo.GetInventoryItem then
				tooltipData = C_TooltipInfo.GetInventoryItem("player", inventoryID)
			else
				TyGearTooltip:SetInventoryItem("player", inventoryID)
			end
		end
	elseif lootRollID then
		if not info.link then
			info.link = GetLootRollItemLink(lootRollID)
		end
		info.item = Item:CreateFromItemLink(select(3,ExtractHyperlinkString(info.link)))
		if C_TooltipInfo and C_TooltipInfo.GetLootRollItem then
			tooltipData = C_TooltipInfo.GetLootRollItem(lootRollID)
		else
			TyGearTooltip:SetLootRollItem(lootRollID)
		end
	elseif link then
		info.link = link
		info.item = Item:CreateFromItemLink(select(3,ExtractHyperlinkString(info.link)))
		if C_TooltipInfo and C_TooltipInfo.GetHyperlink then
			tooltipData = C_TooltipInfo.GetHyperlink(info.link)
		else
			TyGearTooltip:SetHyperlink(info.link)
		end
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

	info.id = info.item:GetItemID()
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
	info.classID, info.subclassID = select(6,GetItemInfoInstant(info.id))
	info.name = C_Item.GetItemNameByID(info.id)
	info.rarity = info.item:GetItemQuality()
	info.rarityColor = info.item:GetItemQualityColor()
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

	-- EF: this might actually be breaking it as I think it's caching empty tooltips before they're fully loaded
	-- caching did not show a performance benefit, so commented this and the below out
	-- info.linkHash = TyGearStringHash(info.link)
	-- local cachediteminfo = TyGearItemInfoCache[info.linkHash]
	-- if cachediteminfo then return cachediteminfo end

	info.invType = C_Item.GetItemInventoryTypeByID(info.id) or 0
	info.isGear = info.invType > 0

	if (info.classID == Enum.ItemClass.Miscellaneous) and
	(info.subclassID == Enum.ItemMiscellaneousSubclass.Mount) then
		info.isMount = 1
		return info -- mounts are never auto-rolled; leave them for the player
	elseif not info.isGear then
		return info -- return early if the item isn't gear
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
			--tooltip text can be a secret value under the Midnight addon restrictions (Retail 12, WoW Forever); it can't be parsed then
			if issecretvalue and issecretvalue(textLeftText) then
				info.unusable = 1
				info.reason = "(item data is restricted right now)"
				if TyGearIsItemIgnored(info) then
					info.ignored = 1
					info.usable = nil
					info.reason = "("..L["ignored"]..")"
				end
				return info
			end
			local text = select(1,string.gsub(textLeftText:lower(),",",""))
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
			if info.classID == Enum.ItemClass.Weapon then
				if string.find(text, "damage per second") then info.DPS = (info.DPS or 0) + value end
				local minDamage, maxDamage = string.match(text, "([0-9]+%.?[0-9]*) ?%- ?([0-9]+%.?[0-9]*) damage")
				if minDamage and maxDamage then
					info.Damage = (info.Damage or 0) + ((tonumber(minDamage) + tonumber(maxDamage))/2)
					minDamage, maxDamage = nil, nil
				end
			end
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

			--check for red text on the right side
			local textRight, textRightText
			if tooltipData and tooltipData.lines then
				textRight = tooltipData.lines[i].rightText or tooltipData.lines[i].textRight
				textRightText = textRight
			else
				textRight = _G["TyGearTooltipTextRight"..i]
			end
			if textRight then
				local r, g, b
				if textRight.GetTextColor then
					r, g, b = textRight:GetTextColor()
				else
					r, g, b = tooltipData.lines[i].rightColor:GetRGB()
				end
				if not textRightText then
					textRightText = textRight:GetText()
				end
				if issecretvalue and issecretvalue(textRightText) then
					info.unusable = 1
					info.reason = "(item data is restricted right now)"
					if TyGearIsItemIgnored(info) then
						info.ignored = 1
						info.usable = nil
						info.reason = "("..L["ignored"]..")"
					end
					return info
				end
				if (not isInItemSetSection) and ((g==0 or r/g>3) and (b==0 or r/b>3) and math.abs(b-g)<0.1 and r>0.5 and textRightText) then --this is red text
					info.reason = "(found red text: \""..textRightText.."\")"
					info.unusable = 1
				end
			end
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
			and (info.classID ~= Enum.ItemClass.Armor)
			and (info.subclassID ~= Enum.ItemArmorSubclass.Shield) then
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

	if info.isGear then
		info.shouldShowScoreInTooltip = 1
	end
	if (not info.unusable) and info.isGear then
		info.usable = 1
	elseif not info.isGear then
		info.unusable = 1
		info.reason = "(item can't be equipped. info.invType = '".. tostring(info.invType) .."')"
	end

	--WoW Forever gear whose tooltip has an effect and no scored stat is ignored.
	--Gear that also has a stat TyGear can score is kept and evaluated on that stat.
	local tooltipWasUnreadable = info.reason == "(this item's tooltip is not yet available)" or info.reason == "(item data is restricted right now)"
	if IS_WOW_FOREVER and info.isGear and info.classID ~= Enum.ItemClass.Container and info.sawEquipEffect
	and not TyGearItemHasMeasurableStats(info) and not tooltipWasUnreadable then
		info.unmeasurableOnly = 1
		TyGearRememberUnmeasurableGear(info)
	end
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
	local realLocalizedClass, realClass, realSpec, realClassID = TyGearDetectClassAndSpec()
	local overrideLocalizedClass, overrideClass, overrideSpec, overrideClassID = TyGearGetClassAndSpec()

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
				return trueScaleName, scale.LocalizedName
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
				return scaleName, scale.LocalizedName
			end
		end

		-- Try to find a visible scale with localized name matching the full TyGearCharDB.OverrideSpec string (example: "Paladin: Protection")
		for scaleName, scale in pairs(PawnCommon.Scales) do
			if PawnIsScaleVisible(scaleName)
			and TyGearCharDB.OverrideSpec
			and TyGearCharDB.OverrideSpec == scale.LocalizedName
			and scale.Values
			and next(scale.Values) then
				return scaleName, scale.LocalizedName
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
				return scaleName, scale.LocalizedName
			end
		end

		-- Try to find a visible scale matching just the override spec name (example: "Protection")
		for scaleName, scale in pairs(PawnCommon.Scales) do
			if PawnIsScaleVisible(scaleName)
			and overrideSpec == scaleName
			and scale.Values
			and next(scale.Values) then
				return scaleName, scale.LocalizedName
			end
		end

		-- Try to find a visible scale with name matching just the override localized class name (example: "Paladin")
		for scaleName, scale in pairs(PawnCommon.Scales) do
			if PawnIsScaleVisible(scaleName)
			and overrideLocalizedClass == scaleName
			and scale.Values
			and next(scale.Values) then
				return scaleName, scale.LocalizedName
			end
		end

		-- Try to find any scale matching the full TyGearCharDB.OverrideSpec string (example: "Paladin: Protection")
		for scaleName, scale in pairs(PawnCommon.Scales) do
			if TyGearCharDB.OverrideSpec
			and TyGearCharDB.OverrideSpec == scaleName
			and scale.Values
			and next(scale.Values) then
				return scaleName, scale.LocalizedName
			end
		end

		-- Try to find any scale with localized name matching the full TyGearCharDB.OverrideSpec string (example: "Paladin: Protection")
		for scaleName, scale in pairs(PawnCommon.Scales) do
			if TyGearCharDB.OverrideSpec
			and TyGearCharDB.OverrideSpec == scale.LocalizedName
			and scale.Values
			and next(scale.Values) then
				return scaleName, scale.LocalizedName
			end
		end

		-- Try to find any scale with class ID matching the override class ID and name containing the override spec name (example: "Protection")
		for scaleName, scale in pairs(PawnCommon.Scales) do
			if scale.ClassID == overrideClassID
			and string.find(scaleName, overrideSpec)
			and scale.Values
			and next(scale.Values) then
				return scaleName, scale.LocalizedName
			end
		end

		-- Try to find any scale with name containing just the override spec name (example: "Protection")
		for scaleName, scale in pairs(PawnCommon.Scales) do
			if string.find(scaleName, overrideSpec)
			and scale.Values
			and next(scale.Values) then
				return scaleName, scale.LocalizedName
			end
		end

		-- Try to find any scale with class ID matching override class ID
		for scaleName, scale in pairs(PawnCommon.Scales) do
			if overrideClassID == scale.ClassID
			and scale.Values
			and next(scale.Values) then
				return scaleName, scale.LocalizedName
			end
		end

		-- Try to find any scale with name containing just the override localized class name (example: "Paladin")
		for scaleName, scale in pairs(PawnCommon.Scales) do
			if string.find(scaleName, overrideLocalizedClass)
			and scale.Values
			and next(scale.Values) then
				return scaleName, scale.LocalizedName
			end
		end

		-- Try to find any scale with name containing just the override class name (example: "PALADIN")
		for scaleName, scale in pairs(PawnCommon.Scales) do
			if string.find(scaleName, overrideClass)
			and scale.Values
			and next(scale.Values) then
				return scaleName, scale.LocalizedName
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
			return scaleName, scale.LocalizedName
		end
	end

	-- Try to find a visible scale matching the real localized class and spec string (example: "Warrior: Arms")
	for scaleName, scale in pairs(PawnCommon.Scales) do
		if PawnIsScaleVisible(scaleName)
		and realClassAndSpec == scale.LocalizedName
		and scale.Values
		and next(scale.Values) then
			return scaleName, scale.LocalizedName
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
			return scaleName, scale.LocalizedName
		end
	end

	-- Try to find a visible scale matching just the real spec name (example: "Arms")
	for scaleName, scale in pairs(PawnCommon.Scales) do
		if PawnIsScaleVisible(scaleName)
		and realSpec == scaleName
		and scale.Values
		and next(scale.Values) then
			return scaleName, scale.LocalizedName
		end
	end

	-- Try to find a visible scale matching just the real class name (example: "Warrior")
	for scaleName, scale in pairs(PawnCommon.Scales) do
		if PawnIsScaleVisible(scaleName)
		and realLocalizedClass == scaleName
		and scale.Values
		and next(scale.Values) then
			return scaleName, scale.LocalizedName
		end
	end

	-- Try to find any scale matching the real class and spec string (example: "Warrior: Arms")
	for scaleName, scale in pairs(PawnCommon.Scales) do
		if realClassAndSpec == scaleName
		and scale.Values
		and next(scale.Values) then
			return scaleName, scale.LocalizedName
		end
	end

	-- Try to find any scale matching the real localized class and spec string (example: "Warrior: Arms")
	for scaleName, scale in pairs(PawnCommon.Scales) do
		if realClassAndSpec == scale.LocalizedName
		and scale.Values
		and next(scale.Values) then
			return scaleName, scale.LocalizedName
		end
	end

	-- Try to find any scale matching just the real spec name (example: "Arms")
	for scaleName, scale in pairs(PawnCommon.Scales) do
		if realSpec == scaleName
		and scale.Values
		and next(scale.Values) then
			return scaleName, scale.LocalizedName
		end
	end

	-- Try to find any scale matching just the real localized class name (example: "Warrior")
	for scaleName, scale in pairs(PawnCommon.Scales) do
		if realLocalizedClass == scaleName
		and scale.Values
		and next(scale.Values) then
			return scaleName, scale.LocalizedName
		end
	end

	-- Try to find the matching class with the matching real spec in the localized scale name
	for scaleName, scale in pairs(PawnCommon.Scales) do
		if scale.ClassID == realClassID
		and scale.LocalizedName
		and string.find(scale.LocalizedName, realSpec)
		and scale.Values
		and next(scale.Values) then
			return scaleName, scale.LocalizedName
		end
	end

	-- Try to find the matching class with the matching real spec in the scale name
	for scaleName, scale in pairs(PawnCommon.Scales) do
		if scale.ClassID == realClassID
		and string.find(scaleName, realSpec)
		and scale.Values
		and next(scale.Values) then
			return scaleName, scale.LocalizedName
		end
	end

	-- Try to find the matching real class
	for scaleName, scale in pairs(PawnCommon.Scales) do
		if scale.ClassID == realClassID
		and scale.Values
		and next(scale.Values) then
			return scaleName, scale.LocalizedName
		end
	end

	-- Use the first visible
	for scaleName, scale in pairs(PawnCommon.Scales) do
		if PawnIsScaleVisible(scaleName)
		and scale.Values
		and next(scale.Values) then
			return scaleName, scale.LocalizedName
		end
	end

	-- Just use the first one that has values
	for ScaleName, Scale in pairs(PawnCommon.Scales) do
		if Scale.Values and next(Scale.Values) then
			return ScaleName, Scale.LocalizedName
		end
	end
end

function TyGearGetWeaponType(itemClassID, itemSubClassID)
	--ask WoW what type of weapon it is
	if (itemClassID == Enum.ItemClass.Weapon) or ((itemClassID == Enum.ItemClass.Armor) and (itemSubClassID == Enum.ItemArmorSubclass.Shield)) then
		return itemSubClassID
	end
end

function TyGearDetermineItemScore(info)
	if info.empty then return 0 end
	if info.classID == Enum.ItemClass.Container then
		if info.subclassID == 0 then -- generic (typical) bag; there's no Enum.ItemContainerSubclass
			return info.numBagSlots or 0
		else
			return (info.numBagSlots or 0) * E -- specialized bags suck, so consider them only better than nothing
		end
	elseif info.isAmmoBag and info.numBagSlots and (UnitClassBase("player") == "HUNTER") then
		return info.numBagSlots + (info.ammoBagRangedAttackSpeed and info.ammoBagRangedAttackSpeed or 0)
	end

	if TyGearDB.UsePawn and PawnIsReady and PawnIsReady() then
		local pawnItemData = PawnGetItemData(info.link)
		if pawnItemData then
			local score = PawnGetSingleValueFromItem(pawnItemData, TyGearGetPawnScaleName())
			if score == 0 then
				return E
			else
				return score or 0
			end
		end
	end

	-- This error trap sucks, but execution can reach here with no TyGearCurrentWeighting and I don't know how
	if (not TyGearCurrentWeighting) then
		TyGearSetStatWeights()
		if (not TyGearCurrentWeighting) then return 0 end
	end

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
		(TyGearCurrentWeighting.DPS or 0) * (info.DPS or 0) +
		(TyGearCurrentWeighting.Damage or 0) * (info.Damage or 0) +
		((UnitLevel("player") < maxPlayerLevel and not (IsXPUserDisabled and IsXPUserDisabled())) and
		(TyGearCurrentWeighting.ExperienceGained or 0) * (info.ExperienceGained or 0) or 0)
	if score == 0 then
		return E
	else
		return score or 0
	end
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
	local lowestScoringValidGearSlotScore = TyGearDetermineItemScore(info)
	local lowestScoringValidGearInfo = info
	local equippedSetScore = 0
	for i=1,(info.numValidGearSlots or 0) do
		equippedSetScore = equippedSetScore + (TyGearEquippedItems[info.validGearSlots[i]].score or 0)
	end
	if info.is2hWeapon and (not (CanDualWield() and IsPlayerSpell(46917))) then
		local mainHandInfo = TyGearReadItemInfo(INVSLOT_MAINHAND)
		local mainHandScore = TyGearDetermineItemScore(mainHandInfo)
		local offHandScore = TyGearDetermineItemScore(TyGearReadItemInfo(INVSLOT_OFFHAND))
		local oneHandedWeaponsScore = mainHandScore + offHandScore
		lowestScoringValidGearInfo = mainHandInfo
		lowestScoringValidGearSlot = INVSLOT_MAINHAND
		lowestScoringValidGearSlotScore = oneHandedWeaponsScore
		equippedSetScore = oneHandedWeaponsScore
	elseif info.is1hWeaponOrOffHand
	and TyGearIsTwoHandEquipped() then
		lowestScoringValidGearInfo = TyGearReadItemInfo(INVSLOT_MAINHAND)
		lowestScoringValidGearSlot = INVSLOT_MAINHAND
		lowestScoringValidGearSlotScore = TyGearDetermineItemScore(lowestScoringValidGearInfo)
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
				if (not skipThisSlot) and
				(TyGearEquippedItems[gearSlot].info.empty or
				(TyGearEquippedItems[gearSlot].score <= lowestScoringValidGearSlotScore)) then
					lowestScoringValidGearInfo = TyGearEquippedItems[gearSlot].info
					lowestScoringValidGearSlot = gearSlot
					lowestScoringValidGearSlotScore = TyGearEquippedItems[gearSlot].score
				end
				end
			end
		end
		if info.is1hWeaponOrOffHand and not equipped then
			equippedSetScore = TyGearEquippedItems[INVSLOT_MAINHAND].score + TyGearEquippedItems[INVSLOT_OFFHAND].score
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
	and ((weapons == "dagger and any")
	and (a.subclassID ~= Enum.ItemWeaponSubclass.Dagger)
	and (b.subclassID ~= Enum.ItemWeaponSubclass.Dagger))
	or ((weapons == "weapon and shield")
	and (a.subclassID ~= Enum.ItemArmorSubclass.Shield)
	and (b.subclassID ~= Enum.ItemArmorSubclass.Shield))) then
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
	if not TyGearBestItems then TyGearUpdateBestItems() end
	local setSlots = TyGearGetSetSlots(info)
	local bestSetScore = 0
	local bestSet = {}
	local lowestBestItemIndex = 0
	local lowestBestItemScore = 0
	local bestItem
	local thisIsABestItem
	if setSlots then
		for i,slot in ipairs(setSlots) do
			if (not TyGearBestItems) or (not TyGearBestItems[slot]) or (TyGearBestItems[slot].info and TyGearBestItems[slot].info.empty) then
				return bestSet, bestSetScore, 1, lowestBestItemScore
			end
			local bestInfo = TyGearBestItems[slot].info
			if bestInfo and (
				(
					bestInfo.link
					and bestInfo.link == info.link
				) or (
					info.guid and
					bestInfo.guid and
					bestInfo.guid == info.guid
				)
			) then
				thisIsABestItem = 1
			end
			if bestInfo
			and TyGearIsGearPairEquippableTogether(info, bestInfo) then
				bestItem = TyGearBestItems[slot]
				if lowestBestItemScore == 0
				or bestItem.score < lowestBestItemScore then
					lowestBestItemIndex = i
					lowestBestItemScore = bestItem.score
				end
				table.insert(bestSet, bestItem)
			end
		end
		if not thisIsABestItem then
			table.remove(bestSet, lowestBestItemIndex)
		end
		for i = 1,(#bestSet or 0) do
			bestSetScore = bestSetScore + bestSet[i].score
		end
	end
	return bestSet, bestSetScore, thisIsABestItem, lowestBestItemScore
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
	if TyGearDB.UsePawn and PawnIsReady and PawnIsReady() then
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
		local shouldShowBestSet = ((info.is1hWeaponOrOffHand
		or (info.numValidGearSlots and info.numValidGearSlots > 1))
		and (not isAComparisonTooltip))
		score = TyGearDetermineItemScore(info)
		bestSet, bestSetScore = TyGearGetBestSetItems(info)
		scoreWithBestSet = score + (bestSetScore or 0)
		lowestScoringEquippedItemInfo, lowestScoringEquippedItemScore, lowestScoringEquippedItemSlot, equippedSetScore = TyGearGetTooltipScoreComparisonInfo(info, equipped)
		local isAnyComparisonTooltipVisible = ItemRefTooltip:IsVisible() or ShoppingTooltip1:IsVisible() or ShoppingTooltip2:IsVisible()
		local shouldShowComparisonLine = (not isAComparisonTooltip and (not isAnyComparisonTooltipVisible or TyGearDB.AlwaysShowScoreComparisons)) and not equipped
		if (scoreWithBestSet > equippedSetScore) and not info.ignored and not TyGearAllValidGearSlotsProtected(info) then
			scoreColor = GREEN_FONT_COLOR
		elseif (scoreWithBestSet < equippedSetScore) and not info.ignored then
			scoreColor = RED_FONT_COLOR
		end
		-- 3 decimal places max
		score = math.floor(score * 1000) / 1000
		bestSetScore = math.floor(bestSetScore * 1000) / 1000
		scoreWithBestSet = math.floor(scoreWithBestSet * 1000) / 1000
		equippedSetScore = math.floor(equippedSetScore * 1000) / 1000
		local scoreLinePrefix = (((pawnScaleLocalizedName or pawnScaleName) and pawnScaleColor) and "TyGear: Pawn \""..pawnScaleColor..(pawnScaleLocalizedName or pawnScaleName)..FONT_COLOR_CODE_CLOSE.."\"" or "TyGear")
		if shouldShowComparisonLine or shouldShowBestSet then
			lowestScoringEquippedItemScore = math.floor(lowestScoringEquippedItemScore * 1000) / 1000
			tooltip:AddDoubleLine(scoreLinePrefix.." score".." (equipped"..(((not TyGearIsTwoHandEquipped()) and info.isWeaponOrOffHand and not info.isRangedWeapon) and " pair" or (shouldShowBestSet and " set" or "")).."):",
			equippedSetScore,
			HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b,
			HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)
		end
		tooltip:AddDoubleLine(scoreLinePrefix.." score"..((shouldShowComparisonLine and not isAComparisonTooltip or shouldShowBestSet) and " (this"..((shouldShowBestSet) and " and best "..(info.numValidGearSlots > 2 and "set" or "pairing") or "")..")" or "")..":",
		(((info.unusable == 1) and (RED_FONT_COLOR_CODE.."(won't equip) "..FONT_COLOR_CODE_CLOSE) or "")..scoreWithBestSet) or "nil",
		HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b,
		scoreColor.r, scoreColor.g, scoreColor.b)
		if (TyGearDB.ReasonsInTooltips == true) and info.unusable then
			tooltip:AddDoubleLine("TyGear: won't auto-equip",
			info.reason,
			RED_FONT_COLOR.r,RED_FONT_COLOR.g,RED_FONT_COLOR.b,
			RED_FONT_COLOR.r,RED_FONT_COLOR.g,RED_FONT_COLOR.b)
		end
		if shouldShowBestSet then
			local thisScore = math.floor(TyGearDetermineItemScore(info) * 1000) / 1000
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
else
	GameTooltip:HookScript("OnTooltipSetItem", TyGearTooltipHook)
	GameTooltip:HookScript("OnTooltipSetItem", TyGearAddItemIDToTooltip)
	ShoppingTooltip1:HookScript("OnTooltipSetItem", TyGearTooltipHook)
	ShoppingTooltip2:HookScript("OnTooltipSetItem", TyGearTooltipHook)
	ItemRefTooltip:HookScript("OnTooltipSetItem", TyGearTooltipHook)
	if AtlasLootTooltip then
		AtlasLootTooltip:HookScript("OnTooltipSetItem", TyGearTooltipHook)
	end
end

function TyGearQueueLocalUpdate()
	--check if there's already a local update action in queue
	local localUpdateFound = nil
	for i, curAction in ipairs(TyGearActionQueue) do
		if curAction.t and (curAction.action == "localupdate") then
			localUpdateFound = 1
		end
	end
	if (not localUpdateFound) then
		--no local update found, so create a new one and set it to run immediately
		table.insert(TyGearActionQueue, { action = "localupdate", t = 0.0 })
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
		table.insert(TyGearActionQueue, { action = "scan", t = GetTime() + 0.5 })
	end
end

function TyGearMain()
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
				end
			end
			if (not TyGearSomeItemDataIsMissing) then
				if curAction.t and curAction.action == "roll" then
					if GetTime() > curAction.t then
						if curAction.rollType == 1 then
							TyGearPrint("TyGear: "..(((TyGearDB.AutoLootRoll == true) and (TyGearDB.NeverAutoNeed ~= true)) and "Rolling " or "If automatically rolling "..((TyGearDB.NeverAutoNeed ~= true) and "" or (GREEN_FONT_COLOR_CODE.."NEED"..FONT_COLOR_CODE_CLOSE.." ")).."on loot was enabled, would roll ")..GREEN_FONT_COLOR_CODE.."NEED"..FONT_COLOR_CODE_CLOSE.." on "..curAction.info.link..".", 1)
						elseif curAction.rollType == 2 then
							TyGearPrint("TyGear: "..((TyGearDB.AutoLootRoll == true) and "Rolling " or "If automatically rolling on loot was enabled, would roll ")..RED_FONT_COLOR_CODE.."GREED"..FONT_COLOR_CODE_CLOSE.." on "..curAction.info.link..".", 1)
						end
						local rarity = curAction.info.rarity
						if ((TyGearDB.NeverAutoNeed ~= true) or (curAction.rollType ~= 1)) and
						((((rarity < 3) or (rarity == 3 and not (curAction.info.boe))) and (TyGearDB.AutoLootRoll == true)) or
						((rarity == 3) and curAction.info.boe and (TyGearDB.AutoRollOnBoEBlues == true)) or
						((rarity == 4) and (TyGearDB.AutoRollOnEpics == true))) then
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
								if (GetInventoryItemID("player", curAction.replaceSlot) == curAction.info.id) then
									curAction.ensuringEquipped = nil
									if (not TyGearActionQueue[i+1]) or (not TyGearActionQueue[i+1].ensuringEquipped) then
										TyGearUpdateEquippedItems()
									end
									curAction.t = nil
									queueQueueRebuild = 1
								end
							else
								if ((not curAction.container) or (not curAction.slot))
								and curAction.info and curAction.info.itemLocation or (curAction.info.item and curAction.info.item.GetItemLocation and curAction.info.item:HasItemLocation()) then
									local itemLocation = curAction.info.itemLocation or curAction.info.item:GetItemLocation()
									curAction.container, curAction.slot = itemLocation:GetBagAndSlot()
								end
								if (not curAction.container) or (not curAction.slot) then
									TyGearBrokenAction = curAction
									TyGearPrint("Error: The current equip action has either no container or no slot! This should never happen, so it must be a bug. It's now been saved to global variable TyGearBrokenAction, so try \"/dump TyGearBrokenAction\" and send the output to the TyGear author.",0)
									curAction.t = nil
									queueQueueRebuild = 1
								--everything below needs the container and slot, so it only runs when both are known
								-- prevent equip error when bag is replacing the bag it's inside
								elseif curAction.replaceSlot >= TyGearFirstEquippableBagSlot
								and curAction.container == (curAction.replaceSlot - TyGearFirstEquippableBagSlot + 1) then
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
										PickupContainerItem(curAction.container, curAction.slot)
										EquipCursorItem(curAction.replaceSlot)
										curAction.ensuringEquipped = 1
										curAction.movedOutOfBag = nil
									end
								else
									PickupContainerItem(curAction.container, curAction.slot)
									EquipCursorItem(curAction.replaceSlot)
									curAction.ensuringEquipped = 1
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
						end
					end
				elseif curAction.t and (curAction.action == "sellgreys") then
					if (GetTime() > curAction.t) then
						curAction.t = nil
						queueQueueRebuild = 1
						if greySelling then TyGearSellGreysTick() end
					end
				end
			end
		end
		if queueQueueRebuild then
			local rebuiltQueue = {}
			for _, curAction in ipairs(TyGearActionQueue) do
				if curAction.t then table.insert(rebuiltQueue, curAction) end
			end
			TyGearActionQueue = rebuiltQueue
			queueQueueRebuild = nil
		end
	end
end
