# TyGear

TyGear automatically rolls on and equips loot for **WoW Forever**. It rolls **need** on upgrades and **greed** otherwise, using class stat weights (like WoWhead filters).

Based on [AutoGear](https://github.com/BujuArena/AutoGear) by Synthetikaryote and BujuArena ([CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/)).

Install as `Interface/AddOns/TyGear`. Disable AutoGear while using TyGear — both would fight over loot and gear.

## Getting started

1. Type `/tg` to open options.
2. Forever has one specialization per class, so TyGear uses a general class profile by default. Healers, tanks, or anyone who wants a focused damage profile should enable **Override specialization** and pick the closest match. That setting is saved per character.
3. Use `/tg toggle` anytime you want to turn automatic gearing off (for example before a loot roll you want to control yourself).

## What to expect

- Upgrades found in combat are equipped when combat ends.
- Gear TyGear cannot score, plus slot/item ignore controls, live on the **Ignored List** tab.
- Items you always want to **NEED** (for example a crafting green in a dungeon) go on the **Need List** tab; add them near the top of that tab or with a key binding.
- Vendor greys and whites to keep live on the **Keep List** tab, including **Keep unbound grey gear**. It starts with Forever crafting tools only; add more near the top of that tab.
- Weapons your class can never learn are skipped. Untrained weapons still show a score with "(won't equip)".
- Mounts are never rolled on automatically.
- **Roll on non-gear loot** is off by default. If you turn it on, TyGear greeds non-upgrade loot (including crafting reagents). Need-list items still roll NEED even when that option is off.

## Commands

`/tygear` works the same as `/tg`:

```
/tg              options menu
/tg help         list commands
/tg scan         scan bags once for better gear
/tg spec         show current specialization
/tg toggle       turn automatic gearing on or off
```

## Key bindings

Esc → Key Bindings → TyGear: bind keys to add or remove the hovered item from the vendor **keep list**, loot **need list**, or gear **ignore list**.

## Note

TyGear is for leveling convenience. Its weights are not meant for end-game group content.
