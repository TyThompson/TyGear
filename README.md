# TyGear

TyGear is a separate World of Warcraft addon based on [AutoGear](https://github.com/BujuArena/AutoGear) by **Synthetikaryote** and **BujuArena**. It keeps that addon's behavior and is licensed under the same [Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International](https://creativecommons.org/licenses/by-nc-sa/4.0/) license. This copy is modified so it installs and runs under its own name.

The original AutoGear authors and contributors retain credit for the design and implementation. Other contributors are listed in the [original repository history](https://github.com/BujuArena/AutoGear). Ty maintains this fork. TyGear is not affiliated with or endorsed by the original AutoGear project.

- Original addon: [GitHub](https://github.com/BujuArena/AutoGear), [CurseForge](https://www.curseforge.com/wow/addons/autogear), [WoWInterface](https://www.wowinterface.com/downloads/info26415)
- This fork changes the addon name, saved variables (`TyGearDB`), frame and function names, and slash commands. CurseForge project 39179 and WoWInterface ID 26415 stay with AutoGear and are not used here.
- Chat commands are `/tg`, `/tygear`, and `/TyGear`.
- Override specialization is saved for each character. Other options are shared. An alt does not inherit another character's spec.
- Install the folder as `Interface/AddOns/TyGear` so it matches `TyGear.toc`. Leave the original AutoGear addon disabled while TyGear is enabled; both would try to roll on loot and equip gear.
- Releases use the [BigWigs Packager](https://github.com/BigWigsMods/packager) GitHub Action. Push a tag matching `N-N-N` or `N-N-N-alpha1` / `N-N-N-beta1` to build a zip, GitHub Release, and CurseForge upload (project `1799929`). Optional later: `WOWI_API_TOKEN` / `WAGO_API_TOKEN` plus matching IDs in `TyGear.toc`.

TyGear automatically rolls on and equips loot according to stat weights like WoWhead filters. TyGear rolls "need" on upgrades and "greed" otherwise.

Included in TyGear are default stat weights for all specs of all classes. Using these weights, TyGear will roll "need" on better loot and equip it for you when it can.

Stat weights work like the advanced filter on WoWhead. For example, if you specify that 1 point of strength is worth 1 point and 1 point of crit is worth 0.5 points, an item with 5 strength and 3 crit will be worth 6.5 points. That item might then replace an item in the same slot with 3 strength and 2 crit, worth 4 points. If the first item was presented in a loot roll, TyGear would roll "need" and if you won the roll, it would equip the new item as soon as it could.

The default stat weights may not be what you prefer. If you want to change them, stat weights for all classes and specs can be found in the "SetStatWeights()" function in "[wow]\Interface\AddOns\TyGear\TyGear.lua". Simply edit the numbers there, save the file, and type "/run ReloadUI()" to update. A GUI for setting stat weights would be nice, but the original authors haven't been motivated to make one yet. Code patches are welcome. This includes improvements to TyGear's current stat weights, which sometimes need updating due to WoW class balance changes.

If you receive an upgrade mid-combat, TyGear queues the upgrade to be equipped when combat ends. It used to equip weapon upgrades immediately because weapons could be changed in combat, but due to addons that automated weapon swaps in combat for DPS at maximum level, Blizzard now prevents addons from swapping weapons in combat automatically. You can still equip them manually earlier than TyGear can if you notice you've received a weapon upgrade.

## WoW Forever

TyGear also runs on WoW Forever (interface 16001).

- Forever has one specialization per class, so TyGear uses the general class profile (`None`). If you heal, tank, or want a more focused damage profile, enable **Override specialization** in `/tg` and choose the closest profile. That choice is saved for the current character. Healers should do this, because the general profile values bonus healing only as spell damage (one third of its value).
- Forever's combined hit and critical strike, expertise, and armor/spell penetration are read from item tooltips.
- On Forever, **Use Pawn** and **Roll on non-gear loot** default to off; Pawn has no Forever scales yet.
- Forever gear with only effects TyGear cannot score (no measurable stats) is always ignored. The **Ignored gear** options tab lists those items.
- Forever weapons the player's class can never learn are not scored or considered for upgrades. Weapons the class can learn but has not trained still show a TyGear score in the tooltip with "(won't equip)".
- Loot messages and tooltip text can be restricted (secret values) in dungeons and during encounters. TyGear then scans your bags instead of reading the loot message, and treats items it can't read as not evaluable.

Chat commands (`/tygear` is the same as `/tg`):
```
/tg - options menu
/tg help - chat commands
/tg scan - manually run automatic gearing once (scan all bags for better gear)
/tg spec - query name of current specialization
/tg toggle/[enable/on/start]/[disable/off/stop] - toggle automatic gearing
/tg verbosity [0/1/2]: set allowed verbosity level; valid levels are: 0 (errors), 1 (info), 2 (details)
```

Key Bindings (Esc → Key Bindings → TyGear): assign keys to toggle the hovered item on the vendor **keep list** or the gear **ignore list**. Hover a bag, character, or chat item tooltip and press the key.

Warning: TyGear currently automatically rolls "greed" on everything that isn't a gear upgrade for the current spec, including crafting reagents, when "Roll on non-gear loot" is enabled. Mounts are never rolled on automatically. It works quite well for leveling quickly and conveniently, but you should disable it before loot rolls you want control over. To do so, simply run "/tg toggle" or toggle it from the options menu.

Warning: TyGear is not recommended for use at max level. Its weights are not optimal, nor are stat weights ideal for determining upgrades in end-game content. TyGear is meant primarily as a convenience for leveling quickly. Using it at max level, especially in team PvE or PvP, is likely to get you kicked from various groups and guilds. Calculating proper upgrades using [SimulationCraft](https://www.simulationcraft.org/) is preferable. This will be very time-consuming, but worth it for your powerful max-level character.
