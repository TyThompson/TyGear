---@type TyGearAddon
local _, T = ...;
if GetLocale() == "deDE" then
	-- options window: tabs and sections
	T.Localization["Evaluation"] = "Bewertung"
	T.Localization["Loot"] = "Beute"
	T.Localization["Rolling"] = "Würfeln"
	T.Localization["Soul-binding"] = "Seelenbindung"
	T.Localization["Tooltips"] = "Tooltips"
	T.Localization["Vendor"] = "Händler"
	T.Localization["Selling"] = "Verkaufen"
	T.Localization["Other"] = "Sonstiges"

	-- options window: general texts
	T.Localization["This is a shortcut for the \"%s\" CVar provided by Blizzard.  Toggling this will toggle that CVar."] = "Dies ist eine Abkürzung für die CVar \"%s\" von Blizzard.  Das Umschalten dieser Option schaltet auch diese CVar um."
	T.Localization["Fork of AutoGear by Synthetikaryote and BujuArena."] = "Fork von AutoGear von Synthetikaryote und BujuArena."
	T.Localization["Scan Bags"] = "Taschen scannen"
	T.Localization["Click this button to force a bag scan, the same way that TyGear scans for gear upgrades in your bags whenever new gear is looted.\n\nTip: By equipping your old item, you can use this to help determine how TyGear decided an item was an upgrade."] = "Klicke auf diese Schaltfläche, um einen Taschen-Scan zu erzwingen – genauso, wie TyGear deine Taschen nach Ausrüstungsverbesserungen durchsucht, sobald neue Ausrüstung erbeutet wird.\n\nTipp: Wenn du deinen alten Gegenstand wieder anlegst, kannst du damit nachvollziehen, warum TyGear einen Gegenstand als Verbesserung eingestuft hat."

	-- option: Enabled
	T.Localization["Automatically equip gear"] = "Ausrüstung automatisch anlegen"
	T.Localization["Automatically equip gear upgrades, depending on internal stat weights.  These stat weights are currently only configurable by editing the values in the TyGearDefaultWeights table in TyGear.lua.  If this is disabled, TyGear will still scan for gear when receiving new items and viewing loot rolls, but will never equip an item automatically."] = "Ausrüstungsverbesserungen anhand der internen Wertegewichtung automatisch anlegen.  Diese Gewichtung lässt sich derzeit nur über die Tabelle TyGearDefaultWeights in TyGear.lua ändern.  Ist dies deaktiviert, sucht TyGear beim Erhalt neuer Gegenstände und bei Beutewürfen weiterhin nach Ausrüstung, legt aber nie automatisch etwas an."
	T.Localization["Automatic gearing is now enabled."] = "Automatisches Anlegen von Ausrüstung ist jetzt aktiviert."
	T.Localization["Automatic gearing is now disabled.  You can still manually scan bags for upgrades with the options menu button or \"/tg scan\"."] = "Automatisches Anlegen von Ausrüstung ist jetzt deaktiviert.  Du kannst deine Taschen weiterhin mit der Schaltfläche im Optionsmenü oder mit \"/tg scan\" nach Verbesserungen durchsuchen."

	-- option: AutoLootRoll
	T.Localization["Automatically roll on greens and BoP blues"] = "Automatisch auf grüne und beim Aufheben gebundene blaue Gegenstände würfeln"
	T.Localization["Automatically roll on group loot of green rarity and blues which bind when picked up, depending on internal stat weights.  If this is disabled, TyGear will still evaluate these loot rolls and print its evaluation if verbosity is set to 1 (%s) or higher."] = "Bei Gruppenbeute automatisch auf grüne Gegenstände und beim Aufheben gebundene blaue Gegenstände würfeln, abhängig von der internen Wertegewichtung.  Ist dies deaktiviert, bewertet TyGear diese Beutewürfe weiterhin und gibt die Bewertung aus, wenn die Ausführlichkeit auf 1 (%s) oder höher steht."
	T.Localization["Automatically rolling on loot of green rarity and blues which bind when picked up is now enabled."] = "Automatisches Würfeln auf grüne und beim Aufheben gebundene blaue Beute ist jetzt aktiviert."
	T.Localization["Automatically rolling on loot of green rarity and blues which bind when picked up is now disabled.  TyGear will still try to equip gear received through other means, but you will have to roll on this loot manually."] = "Automatisches Würfeln auf grüne und beim Aufheben gebundene blaue Beute ist jetzt deaktiviert.  TyGear versucht weiterhin, auf anderem Weg erhaltene Ausrüstung anzulegen, aber auf diese Beute musst du selbst würfeln."

	-- option: AutoRollOnBoEBlues
	T.Localization["Automatically roll on BoE blues"] = "Automatisch auf beim Anlegen gebundene blaue Gegenstände würfeln"
	T.Localization["Automatically roll on group loot of blue rarity which binds when equipped, depending on internal stat weights.  If this is disabled, TyGear will still evaluate these loot rolls and print its evaluation if verbosity is set to 1 (%s) or higher."] = "Bei Gruppenbeute automatisch auf blaue, beim Anlegen gebundene Gegenstände würfeln, abhängig von der internen Wertegewichtung.  Ist dies deaktiviert, bewertet TyGear diese Beutewürfe weiterhin und gibt die Bewertung aus, wenn die Ausführlichkeit auf 1 (%s) oder höher steht."
	T.Localization["Automatically rolling on group loot of blue rarity which binds when equipped is now enabled."] = "Automatisches Würfeln auf blaue, beim Anlegen gebundene Gruppenbeute ist jetzt aktiviert."
	T.Localization["Automatically rolling on group loot of blue rarity which binds when equipped is now disabled.  TyGear will still try to equip gear received through other means, but you will have to roll on this loot manually."] = "Automatisches Würfeln auf blaue, beim Anlegen gebundene Gruppenbeute ist jetzt deaktiviert.  TyGear versucht weiterhin, auf anderem Weg erhaltene Ausrüstung anzulegen, aber auf diese Beute musst du selbst würfeln."

	-- option: AutoRollOnEpics
	T.Localization["Automatically roll on epics"] = "Automatisch auf epische Gegenstände würfeln"
	T.Localization["Automatically roll on group loot of epic rarity, depending on internal stat weights.  If this is disabled, TyGear will still evaluate these loot rolls and print its evaluation if verbosity is set to 1 (%s) or higher."] = "Bei Gruppenbeute automatisch auf epische Gegenstände würfeln, abhängig von der internen Wertegewichtung.  Ist dies deaktiviert, bewertet TyGear diese Beutewürfe weiterhin und gibt die Bewertung aus, wenn die Ausführlichkeit auf 1 (%s) oder höher steht."
	T.Localization["Automatically rolling on group loot of epic rarity is now enabled."] = "Automatisches Würfeln auf epische Gruppenbeute ist jetzt aktiviert."
	T.Localization["Automatically rolling on group loot of epic rarity is now disabled.  TyGear will still try to equip gear received through other means, but you will have to roll on this loot manually."] = "Automatisches Würfeln auf epische Gruppenbeute ist jetzt deaktiviert.  TyGear versucht weiterhin, auf anderem Weg erhaltene Ausrüstung anzulegen, aber auf diese Beute musst du selbst würfeln."

	-- option: RollOnNonGearLoot
	T.Localization["Roll on non-gear loot"] = "Auf Beute würfeln, die keine Ausrüstung ist"
	T.Localization["Roll on all group loot, including loot that is not gear.  If this is enabled, TyGear will roll GREED on non-gear loot.  Mounts are never rolled on automatically."] = "Auf jede Gruppenbeute würfeln, auch auf Beute, die keine Ausrüstung ist.  Ist dies aktiviert, würfelt TyGear GIER auf Beute, die keine Ausrüstung ist.  Auf Reittiere wird nie automatisch gewürfelt."
	T.Localization["Rolling on non-gear loot is now enabled.  TyGear will roll GREED on non-gear loot.  Mounts are never rolled on automatically."] = "Würfeln auf Beute, die keine Ausrüstung ist, ist jetzt aktiviert.  TyGear würfelt GIER auf Beute, die keine Ausrüstung ist.  Auf Reittiere wird nie automatisch gewürfelt."
	T.Localization["Rolling on non-gear loot is now disabled."] = "Würfeln auf Beute, die keine Ausrüstung ist, ist jetzt deaktiviert."

	-- option: NeverAutoNeed
	T.Localization["Never auto-need; only greed"] = "Nie automatisch Bedarf, nur Gier"
	T.Localization["Never automatically roll NEED.  If this is enabled, TyGear will be prevented from automatically rolling NEED when it detects an upgrade, leaving the loot roll interactive to allow manual control of that roll.  It will still be allowed to roll GREED when an upgrade is not detected and automatic rolling is enabled for the detected rarity."] = "Nie automatisch BEDARF würfeln.  Ist dies aktiviert, würfelt TyGear bei einer erkannten Verbesserung nicht automatisch BEDARF, sondern lässt den Beutewurf offen, damit du selbst entscheiden kannst.  GIER darf TyGear weiterhin würfeln, wenn keine Verbesserung erkannt wird und automatisches Würfeln für diese Qualität aktiviert ist."
	T.Localization["Rolling only GREED automatically is now enabled.  TyGear will be unable to roll NEED automatically."] = "Automatisch nur GIER würfeln ist jetzt aktiviert.  TyGear kann nicht mehr automatisch BEDARF würfeln."
	T.Localization["Rolling only GREED automatically is now disabled.  TyGear will be able to roll NEED on detected upgrades automatically."] = "Automatisch nur GIER würfeln ist jetzt deaktiviert.  TyGear kann bei erkannten Verbesserungen wieder automatisch BEDARF würfeln."

	-- option: AutoConfirmBinding
	T.Localization["Automatically confirm soul-binding for non-blues/non-epics"] = "Seelenbindung für nicht blaue/nicht epische Gegenstände automatisch bestätigen"
	T.Localization["Automatically confirm soul-binding when equipping an upgrade that does not have blue or epic rarity, causing it to become soulbound.  If this is disabled, TyGear will still try to equip non-blue/non-epic binding gear, but you will have to confirm soul-binding manually."] = "Die Seelenbindung automatisch bestätigen, wenn eine Verbesserung angelegt wird, die weder blau noch episch ist; der Gegenstand wird dadurch seelengebunden.  Ist dies deaktiviert, versucht TyGear weiterhin, solche bindenden Gegenstände anzulegen, aber du musst die Seelenbindung selbst bestätigen."
	T.Localization["Automatically confirming soul-binding for non-blues/non-epics is now enabled."] = "Automatisches Bestätigen der Seelenbindung für nicht blaue/nicht epische Gegenstände ist jetzt aktiviert."
	T.Localization["Automatically confirming soul-binding for non-blues/non-epics is now disabled.  TyGear will still try to equip non-blue/non-epic binding gear, but you will have to confirm soul-binding manually."] = "Automatisches Bestätigen der Seelenbindung für nicht blaue/nicht epische Gegenstände ist jetzt deaktiviert.  TyGear versucht weiterhin, solche bindenden Gegenstände anzulegen, aber du musst die Seelenbindung selbst bestätigen."

	-- option: AutoConfirmBindingBlues
	T.Localization["Automatically confirm soul-binding for blues"] = "Seelenbindung für blaue Gegenstände automatisch bestätigen"
	T.Localization["Automatically confirm soul-binding when equipping an upgrade that has blue rarity, causing it to become soulbound.  If this is disabled, TyGear will still try to equip blue binding gear, but you will have to confirm soul-binding manually."] = "Die Seelenbindung automatisch bestätigen, wenn eine blaue Verbesserung angelegt wird; der Gegenstand wird dadurch seelengebunden.  Ist dies deaktiviert, versucht TyGear weiterhin, blaue bindende Gegenstände anzulegen, aber du musst die Seelenbindung selbst bestätigen."
	T.Localization["Automatically confirming soul-binding for blues is now enabled."] = "Automatisches Bestätigen der Seelenbindung für blaue Gegenstände ist jetzt aktiviert."
	T.Localization["Automatically confirming soul-binding for blues is now disabled.  TyGear will still try to equip blue binding gear, but you will have to confirm soul-binding manually."] = "Automatisches Bestätigen der Seelenbindung für blaue Gegenstände ist jetzt deaktiviert.  TyGear versucht weiterhin, blaue bindende Gegenstände anzulegen, aber du musst die Seelenbindung selbst bestätigen."

	-- option: AutoConfirmBindingEpics
	T.Localization["Automatically confirm soul-binding for epics"] = "Seelenbindung für epische Gegenstände automatisch bestätigen"
	T.Localization["Automatically confirm soul-binding when equipping an upgrade that has epic rarity, causing it to become soulbound.  If this is disabled, TyGear will still try to equip epic binding gear, but you will have to confirm soul-binding manually."] = "Die Seelenbindung automatisch bestätigen, wenn eine epische Verbesserung angelegt wird; der Gegenstand wird dadurch seelengebunden.  Ist dies deaktiviert, versucht TyGear weiterhin, epische bindende Gegenstände anzulegen, aber du musst die Seelenbindung selbst bestätigen."
	T.Localization["Automatically confirming soul-binding for epics is now enabled."] = "Automatisches Bestätigen der Seelenbindung für epische Gegenstände ist jetzt aktiviert."
	T.Localization["Automatically confirming soul-binding for epics is now disabled.  TyGear will still try to equip epic binding gear, but you will have to confirm soul-binding manually."] = "Automatisches Bestätigen der Seelenbindung für epische Gegenstände ist jetzt deaktiviert.  TyGear versucht weiterhin, epische bindende Gegenstände anzulegen, aber du musst die Seelenbindung selbst bestätigen."

	-- option: ScoreInTooltips
	T.Localization["Show TyGear score in item tooltips"] = "TyGear-Wertung in Gegenstands-Tooltips anzeigen"
	T.Localization["Show total TyGear item score from internal TyGear stat weights in item tooltips."] = "Die gesamte TyGear-Wertung eines Gegenstands (aus der internen Wertegewichtung) im Gegenstands-Tooltip anzeigen."
	T.Localization["Showing score in item tooltips is now enabled."] = "Anzeige der Wertung in Gegenstands-Tooltips ist jetzt aktiviert."
	T.Localization["Showing score in item tooltips is now disabled."] = "Anzeige der Wertung in Gegenstands-Tooltips ist jetzt deaktiviert."

	-- option: ReasonsInTooltips
	T.Localization["Show won't-equip reasons in item tooltips"] = "Gründe gegen das Anlegen in Gegenstands-Tooltips anzeigen"
	T.Localization["Show reasons TyGear won't automatically equip items in item tooltips, except when the score is lower than the equipped item's score."] = "Im Gegenstands-Tooltip anzeigen, warum TyGear einen Gegenstand nicht automatisch anlegt – außer wenn die Wertung nur niedriger ist als die des angelegten Gegenstands."
	T.Localization["Showing won't-auto-equip reasons in item tooltips is now enabled."] = "Anzeige der Gründe gegen automatisches Anlegen in Gegenstands-Tooltips ist jetzt aktiviert."
	T.Localization["Showing won't-auto-equip reasons in item tooltips is now disabled."] = "Anzeige der Gründe gegen automatisches Anlegen in Gegenstands-Tooltips ist jetzt deaktiviert."

	-- option: AlwaysCompareGear
	T.Localization["Always show equipped gear comparison tooltips"] = "Vergleichs-Tooltips mit angelegter Ausrüstung immer anzeigen"
	T.Localization["Always show equipped gear comparison tooltips when viewing tooltips for gear that's not equipped.  If this is disabled, you can still show gear comparison tooltips while holding the Shift key."] = "Beim Betrachten nicht angelegter Ausrüstung immer die Vergleichs-Tooltips der angelegten Ausrüstung anzeigen.  Ist dies deaktiviert, kannst du die Vergleichs-Tooltips weiterhin mit gedrückter Umschalttaste anzeigen."
	T.Localization["Always showing gear comparison tooltips when viewing gear tooltips is now enabled."] = "Vergleichs-Tooltips beim Betrachten von Ausrüstung immer anzeigen ist jetzt aktiviert."
	T.Localization["Always showing gear comparison tooltips when viewing gear tooltips is now disabled.  You can still show gear comparison tooltips while holding the Shift key."] = "Vergleichs-Tooltips beim Betrachten von Ausrüstung immer anzeigen ist jetzt deaktiviert.  Mit gedrückter Umschalttaste kannst du sie weiterhin anzeigen."

	-- option: AlwaysShowScoreComparisons
	T.Localization["Always show score comparisons in tooltips"] = "Wertungsvergleiche in Tooltips immer anzeigen"
	T.Localization["Always show score comparisons in the item tooltip, even when also showing the comparison tooltip.  If this is enabled, only the score for the current item will be shown in the tooltip."] = "Wertungsvergleiche immer im Gegenstands-Tooltip anzeigen, auch wenn zusätzlich der Vergleichs-Tooltip angezeigt wird.  Ist dies aktiviert, wird im Tooltip nur die Wertung des aktuellen Gegenstands angezeigt."
	T.Localization["Always show score comparisons in gear tooltips is now enabled."] = "Wertungsvergleiche in Ausrüstungs-Tooltips immer anzeigen ist jetzt aktiviert."
	T.Localization["Always show score comparisons in gear tooltips is now disabled."] = "Wertungsvergleiche in Ausrüstungs-Tooltips immer anzeigen ist jetzt deaktiviert."

	-- option: AutoSellGreys
	T.Localization["Automatically sell greys"] = "Graue Gegenstände automatisch verkaufen"
	T.Localization["Automatically sell all grey items when interacting with a vendor.  Hold Shift while opening the vendor to skip selling that time.\n\nTyGear keeps greys it would equip as upgrades, quest items, greys the current vendor accepts as payment, greys vendors refuse to buy, and item IDs on the ignore list or the keep list.  It stops selling when the vendor doesn't buy items or you can't hold more gold.\n\nItems TyGear would sell are marked as junk for bag addons such as Baganator (choose TyGear as the junk source there) and for the default bags."] = "Beim Ansprechen eines Händlers automatisch alle grauen Gegenstände verkaufen.  Halte beim Öffnen des Händlers die Umschalttaste gedrückt, um das Verkaufen dieses Mal auszulassen.\n\nTyGear behält graue Gegenstände, die es als Verbesserung anlegen würde, Questgegenstände, graue Gegenstände, die der aktuelle Händler als Bezahlung annimmt, graue Gegenstände, die Händler nicht ankaufen, und Gegenstands-IDs auf der Ignorieren-Liste oder der Behalten-Liste.  Es hört auf zu verkaufen, wenn der Händler nichts ankauft oder du kein weiteres Gold tragen kannst.\n\nGegenstände, die TyGear verkaufen würde, werden für Taschen-Addons wie Baganator als Plunder markiert (wähle dort TyGear als Plunder-Quelle) und auch in den Standardtaschen."
	T.Localization["Automatic selling of grey items is now enabled."] = "Automatisches Verkaufen grauer Gegenstände ist jetzt aktiviert."
	T.Localization["Automatic selling of grey items is now disabled."] = "Automatisches Verkaufen grauer Gegenstände ist jetzt deaktiviert."
	T.Localization["Keep"] = "Behalten"
	T.Localization["Keep List"] = "Behalten-Liste"
	T.Localization["Kept items"] = "Behaltene Gegenstände"
	T.Localization["No items are on the keep list."] = "Keine Gegenstände auf der Behalten-Liste."
	T.Localization["Uncheck to remove this item from the keep list."] = "Haken entfernen, um diesen Gegenstand von der Behalten-Liste zu nehmen."
	T.Localization["Greys and common (white) items listed here are part of the ignore list, so they are not sold or evaluated. The list starts with crafting tools that exist on WoW Forever, such as Skinning Knife, Mining Pick, Blacksmith Hammer, Arclight Spanner, Gyromatic Micro-Adjustor, Flint and Tinder, and enchanting rods. Every fishing pole is kept even if its item ID is removed from this list."] = "Hier aufgeführte graue und gewöhnliche (weiße) Gegenstände gehören zur Ignorieren-Liste und werden daher weder verkauft noch bewertet. Die Liste enthält anfangs Handwerkszeuge, die es auf WoW Forever gibt, wie Kürschnermesser, Spitzhacke, Schmiedehammer, Arclight-Schraubenschlüssel, Gyromatischer Mikroregler, Feuerstein und Zunder und Verzauberungsruten. Jede Angelrute wird behalten, auch wenn ihre Gegenstands-ID aus dieser Liste entfernt wird."
	T.Localization["Item names or IDs separated by commas.  Greys and common (white) items listed here are part of the ignore list, so they are not sold or evaluated.\n\nThe list starts with crafting tools such as Skinning Knife, Mining Pick, Blacksmith Hammer, Arclight Spanner, Gyromatic Micro-Adjustor, Flint and Tinder, Gnomish Army Knife, Jeweler's Kit, Virtuoso Inking Set, Herbalist's Spade, and enchanting rods.  Every fishing pole is kept even if its item ID is removed from this list.\n\nShift-click an item while this box has focus to add it, look up item IDs in item tooltips while the TyGear options are open, or assign \"Toggle hovered item on ignore list\" in Key Bindings and press it while hovering an item. That keeps the item and skips evaluation. New items are added near the top of the list."] = "Gegenstandsnamen oder -IDs, durch Kommas getrennt.  Hier aufgeführte graue und gewöhnliche (weiße) Gegenstände gehören zur Ignorieren-Liste und werden daher weder verkauft noch bewertet.\n\nDie Liste enthält anfangs Handwerkszeuge wie Kürschnermesser, Spitzhacke, Schmiedehammer, Angelruten und weitere Berufsgeräte.  Jede Angelrute wird behalten, auch wenn ihre Gegenstands-ID aus dieser Liste entfernt wird.\n\nKlicke mit gedrückter Umschalttaste auf einen Gegenstand, während dieses Feld den Fokus hat, um ihn hinzuzufügen, lies Gegenstands-IDs in den Tooltips ab, während die TyGear-Optionen geöffnet sind, oder weise unter Tastaturbelegung \"Toggle hovered item on ignore list\" eine Taste zu und drücke sie, während du über einem Gegenstand schwebst. Das behält den Gegenstand und lässt die Bewertung aus. Neue Gegenstände werden oben in der Liste eingefügt."
	T.Localization["Included with TyGear's default keep list."] = "Teil von TyGears Standard-Behalten-Liste."
	T.Localization["Item names or IDs separated by commas. Shift-click an item while this box has focus to add it, look up item IDs in item tooltips while the TyGear options are open, or assign \"Toggle hovered item on ignore list\" in Key Bindings and press it while hovering an item. That keeps the item and skips evaluation. New items are added near the top of the list."] = "Gegenstandsnamen oder -IDs, durch Kommas getrennt. Umschalt-Klick auf einen Gegenstand fügt ihn hinzu, solange dieses Feld den Fokus hat, schlage Gegenstands-IDs in Tooltips nach, während die TyGear-Optionen offen sind, oder weise unter Tastaturbelegung \"Toggle hovered item on ignore list\" eine Taste zu und drücke sie, während du über einem Gegenstand schwebst. Das behält den Gegenstand und lässt die Bewertung aus. Neue Gegenstände werden oben in der Liste eingefügt."
	T.Localization["Item ID"] = "Gegenstands-ID"
	T.Localization["Toggle hovered item on keep list"] = "Gegenstand unter dem Mauszeiger auf Behalten-Liste umschalten"
	T.Localization["Toggle hovered item on ignore list"] = "Gegenstand unter dem Mauszeiger auf Ignorieren-Liste umschalten"
	T.Localization["Hover an item, then press this key to keep it and skip evaluation."] = "Bewege den Mauszeiger über einen Gegenstand und drücke diese Taste, um ihn zu behalten und nicht zu bewerten."
	T.Localization["Added %s to the ignore list. It will be kept and not evaluated."] = "%s zur Ignorieren-Liste hinzugefügt. Wird behalten und nicht bewertet."
	T.Localization["keep and ignore"] = "behalten und ignorieren"
	T.Localization["Item IDs separated by commas. Shift-click an item while this box has focus to add it, look up item IDs in item tooltips while the TyGear options are open, or assign \"Toggle hovered item on ignore list\" in Key Bindings and press it while hovering an item. That keeps the item and skips evaluation."] = "Gegenstands-IDs, durch Kommas getrennt. Umschalt-Klick auf einen Gegenstand fügt ihn hinzu, solange dieses Feld den Fokus hat, schlage Gegenstands-IDs in Tooltips nach, während die TyGear-Optionen offen sind, oder weise unter Tastaturbelegung \"Toggle hovered item on ignore list\" eine Taste zu und drücke sie, während du über einem Gegenstand schwebst. Das behält den Gegenstand und lässt die Bewertung aus."
	T.Localization["Hover an item, then press this key to toggle it on the keep list."] = "Bewege den Mauszeiger über einen Gegenstand und drücke diese Taste, um ihn auf der Behalten-Liste umzuschalten."
	T.Localization["Hover an item, then press this key to toggle it on the ignore list."] = "Bewege den Mauszeiger über einen Gegenstand und drücke diese Taste, um ihn auf der Ignorieren-Liste umzuschalten."
	T.Localization["Only armor and weapons can be added to the ignore list."] = "Nur Rüstung und Waffen können zur Ignorieren-Liste hinzugefügt werden."
	T.Localization["Added %s to the keep list."] = "%s zur Behalten-Liste hinzugefügt."
	T.Localization["Removed %s from the keep list."] = "%s von der Behalten-Liste entfernt."
	T.Localization["Added %s to the ignore list."] = "%s zur Ignorieren-Liste hinzugefügt."
	T.Localization["Removed %s from the ignore list."] = "%s von der Ignorieren-Liste entfernt."
	T.Localization["keep list"] = "Behalten-Liste"
	T.Localization["need list"] = "Bedarf-Liste"
	T.Localization["ignore list"] = "Ignorieren-Liste"
	T.Localization["Need List"] = "Bedarf-Liste"
	T.Localization["Toggle hovered item on need list"] = "Gegenstand unter dem Mauszeiger auf Bedarf-Liste umschalten"
	T.Localization["Hover an item, then press this key to toggle it on the need list."] = "Bewege den Mauszeiger über einen Gegenstand und drücke diese Taste, um ihn auf der Bedarf-Liste umzuschalten."
	T.Localization["Added %s to the need list."] = "%s zur Bedarf-Liste hinzugefügt."
	T.Localization["Removed %s from the need list."] = "%s von der Bedarf-Liste entfernt."
	T.Localization["Needed items"] = "Benötigte Gegenstände"
	T.Localization["No items are on the need list."] = "Keine Gegenstände auf der Bedarf-Liste."
	T.Localization["Uncheck to remove this item from the need list."] = "Haken entfernen, um diesen Gegenstand von der Bedarf-Liste zu nehmen."
	T.Localization["Items listed here are always rolled NEED when they appear as group loot, even if they are not gear upgrades. Useful for crafting greens you keep needing in a dungeon. Mounts and ignored items are still skipped."] = "Hier aufgeführte Gegenstände werden bei Gruppenbeute immer mit BEDARF gewürfelt, auch wenn sie keine Ausrüstungsverbesserung sind. Nützlich für Handwerks-Grüne, die du in einem Dungeon immer brauchst. Reittiere und ignorierte Gegenstände werden weiterhin übersprungen."
	T.Localization["Item names or IDs separated by commas. Shift-click an item while this box has focus to add it, look up item IDs in item tooltips while the TyGear options are open, or assign \"Toggle hovered item on need list\" in Key Bindings and press it while hovering an item. New items are added near the top of the list."] = "Gegenstandsnamen oder -IDs, durch Kommas getrennt. Umschalt-Klick auf einen Gegenstand fügt ihn hinzu, solange dieses Feld den Fokus hat, schlage Gegenstands-IDs in Tooltips nach, während die TyGear-Optionen offen sind, oder weise unter Tastaturbelegung \"Toggle hovered item on need list\" eine Taste zu und drücke sie, während du über einem Gegenstand schwebst. Neue Gegenstände werden oben in der Liste eingefügt."
	T.Localization["Item names or IDs separated by commas. Items listed here are always rolled NEED when they appear as group loot, even if they are not gear upgrades. Useful for crafting greens you keep needing in a dungeon.\n\nShift-click an item while this box has focus to add it, look up item IDs in item tooltips while the TyGear options are open, or assign \"Toggle hovered item on need list\" in Key Bindings and press it while hovering an item. New items are added near the top of the list."] = "Gegenstandsnamen oder -IDs, durch Kommas getrennt. Hier aufgeführte Gegenstände werden bei Gruppenbeute immer mit BEDARF gewürfelt, auch wenn sie keine Ausrüstungsverbesserung sind. Nützlich für Handwerks-Grüne, die du in einem Dungeon immer brauchst.\n\nUmschalt-Klick auf einen Gegenstand fügt ihn hinzu, solange dieses Feld den Fokus hat, schlage Gegenstands-IDs in Tooltips nach, während die TyGear-Optionen offen sind, oder weise unter Tastaturbelegung \"Toggle hovered item on need list\" eine Taste zu und drücke sie, während du über einem Gegenstand schwebst. Neue Gegenstände werden oben in der Liste eingefügt."

	-- option: KeepKeeperTahultPetItems
	T.Localization["Keep greys needed for Keeper Ta'hult's pets"] = "Graue Gegenstände für Hüter Ta'hults Haustiere behalten"
	T.Localization["Don't sell the grey items that Keeper Ta'hult in Oribos takes as payment for the Baubleworm pets."] = "Die grauen Gegenstände nicht verkaufen, die Hüter Ta'hult in Oribos als Bezahlung für die Glitzerwurm-Haustiere annimmt."
	T.Localization["Keeping greys needed for Keeper Ta'hult's pets is now enabled."] = "Behalten grauer Gegenstände für Hüter Ta'hults Haustiere ist jetzt aktiviert."
	T.Localization["Keeping greys needed for Keeper Ta'hult's pets is now disabled."] = "Behalten grauer Gegenstände für Hüter Ta'hults Haustiere ist jetzt deaktiviert."

	-- option: KeepUnboundGreyGear
	T.Localization["Keep unbound grey gear"] = "Ungebundene graue Ausrüstung behalten"
	T.Localization["Don't sell grey weapons and armor which aren't soulbound, for example to sell them on the auction house instead."] = "Graue Waffen und Rüstungen, die nicht seelengebunden sind, nicht verkaufen, zum Beispiel um sie stattdessen im Auktionshaus zu verkaufen."
	T.Localization["Keeping unbound grey gear is now enabled."] = "Behalten ungebundener grauer Ausrüstung ist jetzt aktiviert."
	T.Localization["Keeping unbound grey gear is now disabled."] = "Behalten ungebundener grauer Ausrüstung ist jetzt deaktiviert."

	-- option: AutoSellUnsuitableWhites
	T.Localization["Automatically sell unsuitable whites"] = "Ungeeignete weiße Gegenstände automatisch verkaufen"
	T.Localization["Automatically sell white weapons and armor your class can't equip when interacting with a vendor.  Hold Shift while opening the vendor to skip selling that time.\n\nTyGear keeps quest items, items the current vendor accepts as payment, items it would equip as upgrades, tabards, the ignore list, and the keep list.  Fishing poles and profession equipment are always kept.  A level requirement alone does not count as unsuitable, since you will be able to wear the item later.  It stops selling when the vendor doesn't buy items or you can't hold more gold.\n\nItems TyGear would sell are marked as junk for bag addons such as Baganator (choose TyGear as the junk source there) and for the default bags."] = "Beim Ansprechen eines Händlers automatisch weiße Waffen und Rüstungen verkaufen, die deine Klasse nicht anlegen kann.  Halte beim Öffnen des Händlers die Umschalttaste gedrückt, um das Verkaufen dieses Mal auszulassen.\n\nTyGear behält Questgegenstände, Gegenstände, die der aktuelle Händler als Bezahlung annimmt, Gegenstände, die es als Verbesserung anlegen würde, Wappenröcke, die Ignorieren-Liste und die Behalten-Liste.  Angelruten und Berufsausrüstung werden immer behalten.  Eine reine Stufenanforderung gilt nicht als ungeeignet, weil du den Gegenstand später anlegen kannst.  Es hört auf zu verkaufen, wenn der Händler nichts ankauft oder du kein weiteres Gold tragen kannst.\n\nGegenstände, die TyGear verkaufen würde, werden für Taschen-Addons wie Baganator als Plunder markiert (wähle dort TyGear als Plunder-Quelle) und auch in den Standardtaschen."
	T.Localization["Automatic selling of unsuitable white items is now enabled."] = "Automatisches Verkaufen ungeeigneter weißer Gegenstände ist jetzt aktiviert."
	T.Localization["Automatic selling of unsuitable white items is now disabled."] = "Automatisches Verkaufen ungeeigneter weißer Gegenstände ist jetzt deaktiviert."

	-- option: AutoSellAllWhiteGear
	T.Localization["Automatically sell all white gear"] = "Alle weiße Ausrüstung automatisch verkaufen"
	T.Localization["Automatically sell all white weapons and armor when interacting with a vendor, including pieces you can equip.  Hold Shift while opening the vendor to skip selling that time.\n\nTyGear keeps quest items, items the current vendor accepts as payment, items it would equip as upgrades, tabards, the ignore list, and the keep list.  Fishing poles and profession equipment are always kept.  It stops selling when the vendor doesn't buy items or you can't hold more gold.\n\nItems TyGear would sell are marked as junk for bag addons such as Baganator (choose TyGear as the junk source there) and for the default bags."] = "Beim Ansprechen eines Händlers automatisch alle weißen Waffen und Rüstungen verkaufen, auch solche, die du anlegen kannst.  Halte beim Öffnen des Händlers die Umschalttaste gedrückt, um das Verkaufen dieses Mal auszulassen.\n\nTyGear behält Questgegenstände, Gegenstände, die der aktuelle Händler als Bezahlung annimmt, Gegenstände, die es als Verbesserung anlegen würde, Wappenröcke, die Ignorieren-Liste und die Behalten-Liste.  Angelruten und Berufsausrüstung werden immer behalten.  Es hört auf zu verkaufen, wenn der Händler nichts ankauft oder du kein weiteres Gold tragen kannst.\n\nGegenstände, die TyGear verkaufen würde, werden für Taschen-Addons wie Baganator als Plunder markiert (wähle dort TyGear als Plunder-Quelle) und auch in den Standardtaschen."
	T.Localization["Automatic selling of all white gear is now enabled."] = "Automatisches Verkaufen der gesamten weißen Ausrüstung ist jetzt aktiviert."
	T.Localization["Automatic selling of all white gear is now disabled."] = "Automatisches Verkaufen der gesamten weißen Ausrüstung ist jetzt deaktiviert."

	-- option: Override
	T.Localization["Override specialization"] = "Spezialisierung überschreiben"
	T.Localization["Override specialization with the specialization chosen in this dropdown.  If this is enabled, TyGear will evaluate gear by multiplying stats by the stat weights for the chosen specialization instead of the spec detected automatically.  This choice is saved for this character, so alts keep their own spec."] = "Die Spezialisierung durch die in dieser Auswahlliste gewählte ersetzen.  Ist dies aktiviert, bewertet TyGear Ausrüstung mit der Wertegewichtung der gewählten Spezialisierung statt der automatisch erkannten.  Diese Auswahl wird für diesen Charakter gespeichert, damit Nebencharaktere ihre eigene Spezialisierung behalten."
	T.Localization["Specialization overriding is now enabled.  TyGear will use the specialization selected in the dropdown for evaluating gear."] = "Überschreiben der Spezialisierung ist jetzt aktiviert.  TyGear bewertet Ausrüstung mit der in der Auswahlliste gewählten Spezialisierung."
	T.Localization["Specialization overriding is now disabled.  TyGear will use your class and its detected specialization for evaluating gear.  Type \"/tg spec\" to check what specialization TyGear detects for your character."] = "Überschreiben der Spezialisierung ist jetzt deaktiviert.  TyGear bewertet Ausrüstung mit deiner Klasse und der erkannten Spezialisierung.  Mit \"/tg spec\" siehst du, welche Spezialisierung TyGear für deinen Charakter erkennt."

	-- option: UsePawn
	T.Localization["Use Pawn to evaluate upgrades"] = "Pawn zur Bewertung von Verbesserungen verwenden"
	T.Localization["If Pawn (gear evaluation addon) is installed and configured, use a Pawn scale instead of TyGear's internal stat weights for evaluating gear upgrades.  TyGear will use the Pawn scale with a name matching the \"[class]: [spec]\" format; example \"Paladin: Retribution\". If \"Override specialization\" is also enabled, that class and spec will be used for detecting which Pawn scale name to use instead. Visible scales (not hidden in Pawn's settings) will be prioritized when detecting which scale to use."] = "Wenn Pawn (Addon zur Ausrüstungsbewertung) installiert und eingerichtet ist, eine Pawn-Skala statt der internen TyGear-Wertegewichtung zur Bewertung von Verbesserungen verwenden.  TyGear verwendet die Pawn-Skala, deren Name dem Format \"[Klasse]: [Spezialisierung]\" entspricht, z. B. \"Paladin: Retribution\".  Ist zusätzlich \"Spezialisierung überschreiben\" aktiviert, bestimmen diese Klasse und Spezialisierung den Namen der Skala.  Sichtbare Skalen (in Pawn nicht ausgeblendet) haben bei der Auswahl Vorrang."
	T.Localization["Pawn is not running, so this option will do nothing."] = "Pawn läuft nicht, daher hat diese Option keine Wirkung."
	T.Localization["Using Pawn for evaluating gear upgrades is now enabled."] = "Bewertung von Verbesserungen mit Pawn ist jetzt aktiviert."
	T.Localization["Using Pawn for evaluating gear upgrades is now disabled."] = "Bewertung von Verbesserungen mit Pawn ist jetzt deaktiviert."

	-- option: OverridePawnScale
	T.Localization["Override Pawn scale"] = "Pawn-Skala überschreiben"
	T.Localization["Override the Pawn scale that would normally be automatically detected in \"[class]: [spec]\" format with the Pawn scale chosen in this dropdown.\n\nThis override does nothing unless \"Use Pawn to evaluate upgrades\" is enabled."] = "Die normalerweise im Format \"[Klasse]: [Spezialisierung]\" automatisch erkannte Pawn-Skala durch die in dieser Auswahlliste gewählte ersetzen.\n\nDies wirkt nur, wenn \"Pawn zur Bewertung von Verbesserungen verwenden\" aktiviert ist."
	T.Localization["Overriding Pawn scale with the selected scale is now enabled."] = "Überschreiben der Pawn-Skala mit der gewählten Skala ist jetzt aktiviert."
	T.Localization["Overriding Pawn scale with the selected scale is now disabled."] = "Überschreiben der Pawn-Skala mit der gewählten Skala ist jetzt deaktiviert."

	-- option: LockedGearSlots
	T.Localization["Locked gear slots"] = "Gesperrte Ausrüstungsplätze"
	T.Localization["Checked slots are left alone: TyGear will not remove or equip items there. Scores are still evaluated for all slots."] = "Markierte Plätze bleiben unangetastet: TyGear legt dort nichts ab oder an. Bewertungen werden weiterhin für alle Plätze berechnet."

	-- tab: Ignore
	T.Localization["Ignore"] = "Ignorieren"
	T.Localization["Gear slots"] = "Ausrüstungsplätze"
	T.Localization["Ignored slots are left out of rolling, scoring, and equipping."] = "Ignorierte Plätze werden beim Würfeln, Bewerten und Anlegen ausgelassen."
	T.Localization["Equipped items"] = "Angelegte Gegenstände"
	T.Localization["Check an equipped item to leave that item out of selling, rolling, scoring, and equipping."] = "Markiere einen angelegten Gegenstand, damit er beim Verkaufen, Würfeln, Bewerten und Anlegen ausgelassen wird."
	T.Localization["Nothing is equipped."] = "Nichts ist angelegt."
	T.Localization["Item IDs"] = "Gegenstands-IDs"
	T.Localization["Item names or IDs separated by commas. Items on this list are kept and not evaluated. Shift-click an item while this box is focused to add it, or assign \"Toggle hovered item on ignore list\" in Key Bindings and press it while hovering an item. New items are added near the top of the list."] = "Gegenstandsnamen oder -IDs, durch Kommas getrennt. Gegenstände auf dieser Liste werden behalten und nicht bewertet. Umschalt-Klick auf einen Gegenstand fügt ihn hinzu, solange dieses Feld den Fokus hat, oder weise unter Tastaturbelegung \"Toggle hovered item on ignore list\" eine Taste zu und drücke sie, während du über einem Gegenstand schwebst. Neue Gegenstände werden oben in der Liste eingefügt."
	T.Localization["Ignored List"] = "Ignorier-Liste"
	T.Localization["Disclaimer: items TyGear cannot score (for example a 4% chance for Fear to miss) are listed below without checkboxes and stay ignored automatically. Gear that also has a scored stat stays in normal evaluation. Use Add items above for anything else you want ignored; those appear at the top with checkboxes."] = "Hinweis: Gegenstände, die TyGear nicht bewerten kann (etwa 4% Chance, dass Furcht verfehlt), stehen unten ohne Häkchen und bleiben automatisch ignoriert. Ausrüstung mit einem zusätzlich bewertbaren Wert bleibt in der normalen Bewertung. Nutze oben \"Gegenstände hinzufügen\" für alles andere; diese erscheinen oben mit Häkchen."
	T.Localization["Add items"] = "Gegenstände hinzufügen"
	T.Localization["Ignored items"] = "Ignorierte Gegenstände"
	T.Localization["No items are on the ignored list."] = "Keine Gegenstände auf der Ignorier-Liste."
	T.Localization["TyGear cannot score this item, so it stays ignored."] = "TyGear kann diesen Gegenstand nicht bewerten, daher bleibt er ignoriert."
	T.Localization["Uncheck to remove this item from the ignored list."] = "Haken entfernen, um diesen Gegenstand von der Ignorier-Liste zu nehmen."
	T.Localization["ignored"] = "ignoriert"
	T.Localization["every slot this item can use is ignored"] = "jeder Platz, den dieser Gegenstand nutzen kann, ist ignoriert"

	-- option: DebugInfoInTooltips
	T.Localization["Show debug info in item tooltips (%swarning%s: laggy!)"] = "Debug-Infos in Gegenstands-Tooltips anzeigen (%sWarnung%s: verursacht Ruckler!)"
	T.Localization["This is a test mode to show debug info in tooltips, such as the real roll outcome if the item viewed dropped as a loot roll.  This is to help the developers find and fix bugs in TyGear.  You can use it to help too and report issues.\n\n%sWarning%s: laggy!"] = "Ein Testmodus, der Debug-Infos in Tooltips anzeigt, etwa wie TyGear würfeln würde, wenn der betrachtete Gegenstand als Beutewurf fiele.  Er hilft den Entwicklern, Fehler in TyGear zu finden und zu beheben.  Du kannst damit ebenfalls helfen und Probleme melden.\n\n%sWarnung%s: verursacht Ruckler!"
	T.Localization["Debug info in tooltips is now enabled. Info such as whether TyGear would \"%sNEED%s\" or \"%sGREED%s\" on an item will be shown in item tooltips.  (%swarning%s: laggy!)"] = "Debug-Infos in Tooltips sind jetzt aktiviert.  Gegenstands-Tooltips zeigen z. B., ob TyGear \"%sBEDARF%s\" oder \"%sGIER%s\" würfeln würde.  (%sWarnung%s: verursacht Ruckler!)"
	T.Localization["Debug info in tooltips is now disabled."] = "Debug-Infos in Tooltips sind jetzt deaktiviert."
end
