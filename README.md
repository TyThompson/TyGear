# TyGear

TyGear automatically rolls on and equips loot for **WoW Forever**, based on [AutoGear](https://github.com/BujuArena/AutoGear) by **Synthetikaryote** and **BujuArena**. It keeps that addon's behavior and is licensed under the same [Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International](https://creativecommons.org/licenses/by-nc-sa/4.0/) license.

The original AutoGear authors and contributors retain credit for the design and implementation. Ty maintains this fork. TyGear is not affiliated with or endorsed by the original AutoGear project.

- Original addon: [GitHub](https://github.com/BujuArena/AutoGear), [CurseForge](https://www.curseforge.com/wow/addons/autogear), [WoWInterface](https://www.wowinterface.com/downloads/info26415)
- Chat commands: `/tg`, `/tygear`, and `/TyGear`
- Install the folder as `Interface/AddOns/TyGear`. Leave AutoGear disabled while TyGear is enabled; both would try to roll on loot and equip gear.

TyGear rolls **need** on upgrades and **greed** otherwise, using stat weights similar to WoWhead filters. Default weights are included for every class. For example, if 1 strength is worth 1 and 1 crit is worth 0.5, an item with 5 strength and 3 crit scores 6.5 — and would replace a same-slot item worth 4.

If you receive an upgrade mid-combat, TyGear waits until combat ends to equip it. Weapons cannot be swapped by addons in combat; you can still equip them yourself sooner if you notice an upgrade.

## WoW Forever

Forever has one specialization per class, so TyGear uses the general class profile by default. If you heal, tank, or want a more focused damage profile, open `/tg`, enable **Override specialization**, and pick the closest profile. That choice is saved per character. Healers should set this — the general profile only counts bonus healing as a fraction of spell damage.

- Combined hit and critical strike, expertise, and armor/spell penetration are read from item tooltips.
- **Use Pawn** and **Roll on non-gear loot** default to off.
- Gear TyGear cannot score (no measurable stats) is ignored. See the **Ignored gear** tab in options.
- Weapons your class can never learn are skipped. Weapons you can learn but have not trained still show a score with "(won't equip)".
- In dungeons and encounters, loot text can be restricted. TyGear then checks your bags instead, and treats unreadable items as not evaluable.

## Commands

`/tygear` is the same as `/tg`:

```
/tg - options menu
/tg help - chat commands
/tg scan - scan bags once for better gear
/tg spec - show current specialization
/tg toggle/[enable/on/start]/[disable/off/stop] - toggle automatic gearing
/tg verbosity [0/1/2] - 0 errors, 1 info, 2 details
```

## Key bindings

Esc → Key Bindings → TyGear: assign keys to toggle the hovered item on the vendor **keep list** or the gear **ignore list**. Hover a bag, character, or chat item tooltip and press the key.

## Warnings

- With **Roll on non-gear loot** enabled, TyGear rolls greed on non-upgrade loot (including crafting reagents). Mounts are never rolled on. Disable automatic gearing before rolls you want to control with `/tg toggle` or the options menu.
- TyGear is meant for leveling convenience. Its weights are not optimal for end-game content, especially in group PvE or PvP.
