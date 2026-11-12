-- New WoW Forever equipment whose bonuses TyGear cannot score.
-- An item is listed when it is new, is armor or a weapon, has a spell effect,
-- and has no stat, armor, damage, resistance, bonus-armor, or socket fields.
-- Effects that already match a scored stat are omitted, and so is gear that has
-- both a scored stat and an unscored effect. Lookup is Forever-only.
TyGearUnmeasurableGearList = {
	{ id = 272433, icon = 135829, name = "Burning Totem" }, -- Increases the duration of your Flame Shock ability by 3 sec.
	{ id = 273840, icon = 136155, name = "Cursed Murloc Eye" }, -- Spells and attacks deal 2 Shadow damage. Deals 4 times as much damage to Murlocs.
	{ id = 268873, icon = 134228, name = "Defender of the Barkskin" }, -- Calls forth a Barkskin Ancestor to fight at your side and heal you for 20 sec.
	{ id = 260806, icon = 133872, name = "Emergency Field Cloak" }, -- Gives invisibility for 10 sec.
	{ id = 272428, icon = 611424, name = "Enraged Idol" }, -- Your Enrage ability generates an additional 10 Rage over its duration.
	{ id = 260821, icon = 133868, name = "EZ and SAF Field Transporter: Mt. Hyjal" }, -- Rips the dimensional walls asunder and transports you to Kaylaena's Workshop on Mount Hyjal. Technical prob...
	{ id = 260802, icon = 134535, name = "EZ-Thro Bronze Mortar" }, -- Inflicts 85 to 115 Fire damage and stuns targets in a 5 yd radius for 2 sec. Any damage will break the effect.
	{ id = 260819, icon = 133860, name = "EZ-Thro Field Transporter: Gadgetzan" }, -- Safely transport yourself to Gadgetzan in Tanaris! Emphasis on Safe! Yup, nothing bad could ever happen whi...
	{ id = 263436, icon = 135829, name = "Firestorm Totem" }, -- Reduces the mana cost of your totems by 5%.
	{ id = 260824, icon = 133864, name = "Gnomish Poultryizer" }, -- Turns the target into a chicken for 15 sec. Well, that is assuming the transmogrification polarity has not...
	{ id = 270226, icon = 133980, name = "Golden Banana" }, -- Increases all attributes by 16 for 15 sec. Effect and duration are doubled in Forest and Grassland areas.
	{ id = 274445, icon = 133452, name = "Greater Insignia of the Alliance" }, -- Removes all movement impairing effects and all effects which cause loss of control of your character.
	{ id = 274444, icon = 133453, name = "Greater Insignia of the Horde" }, -- Removes all movement impairing effects and all effects which cause loss of control of your character.
	{ id = 260205, icon = 134464, name = "Highborne Research Tablet" }, -- Chance on hit to deal 69 to 81 Arcane damage. Deals 2 times as much damage to Naga and Satyrs.
	{ id = 272427, icon = 134912, name = "Howling Idol" }, -- Reduces the cooldown of your Shifting Power ability by 0.5 sec.
	{ id = 263411, icon = 134914, name = "Idol of Shifting Tides" }, -- Reduces the mana cost of shapeshifting spells by 40.
	{ id = 279250, icon = 236162, name = "Idol of Swiftness" }, -- Reduces the cooldown of your Swiftmend spell by 3 sec.
	{ id = 272429, icon = 132848, name = "Idol of Synthesis" }, -- Each of your heal over time effects on the target reduces the remaining cooldown on Swiftmend by 1 sec when...
	{ id = 279251, icon = 134233, name = "Idol of the Ursine Twins" }, -- Your Lacerate hits have a 10% chance to reset the cooldown on Primal Bite.
	{ id = 272436, icon = 133743, name = "Libram of Economy" }, -- Reduces the Mana cost of your Holy Light ability by 5%.
	{ id = 249442, icon = 134916, name = "Libram of Invocation" }, -- Reduces the mana cost of your Seal spells by 5%.
	{ id = 272435, icon = 133736, name = "Libram of Law" }, -- Increases the damage of your Judgement ability by 4%.
	{ id = 277844, icon = 458243, name = "Mirage Mirror" }, -- Increases movement speed by 25% for 10 sec. While out of combat in Desert areas, gain an additional 25% mov...
	{ id = 273820, icon = 133364, name = "Nightskulker Ring" }, -- Reduces the hit chance of Fear effects against you by 4%. Increases movement speed by 2% in Duskwood.
	{ id = 249398, icon = 310733, name = "Polished Driftwood Icon" }, -- Allows 8% of your Mana regeneration to continue while casting.
	{ id = 260820, icon = 133859, name = "SAF-T Emergency Ripper: Everlook" }, -- Rips the dimensional walls asunder and transports you to Everlook in Winterspring. There are technical prob...
	{ id = 280766, icon = 133633, name = "Satchel of Potions" }, -- Reach into the bag and hope for the best.
	{ id = 269741, icon = 463480, name = "Scented Runewood Brooch" }, -- Harmful spell casts and attacks against Furbolg have a chance to deal 84 to 126 Nature damage. Charm target...
	{ id = 272434, icon = 133744, name = "Sentinel's Libram" }, -- Reduces the cooldown of your Swift Judgement talent by 10 sec.
	{ id = 272430, icon = 463485, name = "Swarming Idol" }, -- Increases the duration of your Insect Swarm ability by 2 sec.
	{ id = 249441, icon = 136063, name = "Talons of Wrath" }, -- Causes Wrath to have a 50% chance to restore 35 Mana.
	{ id = 249397, icon = 133745, name = "Tenets of the Silver Hand" }, -- Increases your damage against Undead by 1%.
	{ id = 274648, icon = 134128, name = "The Desert Rose" }, -- Increases mount speed by 7% in Desert areas.
	{ id = 272431, icon = 4667424, name = "Tidal Totem" }, -- Reduces the Mana cost of your Healing Wave ability by 5%.
	{ id = 249443, icon = 134919, name = "Totem of Ancestral Protection" }, -- Reduces the cooldown of Grounding Totem by 1 sec.
	{ id = 263412, icon = 134919, name = "Totem of Charged Flames" }, -- Reduces the mana cost of Flame Shock and Lightning Bolt by 5 Mana.
	{ id = 272432, icon = 1020304, name = "Totem of the Storm" }, -- Your Lightning Bolt ability can now also trigger the Maelstrom Weapon talent, but with a 50% reduced chance.
	{ id = 276895, icon = 237431, name = "Transformative Cocoon" }, -- Absorb up to 260 to 300 damage and Stun yourself for 5 sec. When the Stun expires, gain 60% increased movem...
	{ id = 277950, icon = 1529268, name = "Wastewanderer Rations" }, -- Your Well Fed buffs metabolize 50% slower. This effect is increased by an additional 50% in Wasteland areas.
}

TyGearUnmeasurableGear = {}
for _, entry in ipairs(TyGearUnmeasurableGearList) do
	TyGearUnmeasurableGear[entry.id] = entry
end
