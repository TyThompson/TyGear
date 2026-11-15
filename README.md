# TyGear

TyGear automatically rolls on and equips loot for **WoW Forever**. It rolls **need** on upgrades and **greed** otherwise, using class stat weights from [MythicSim](https://mythicsim.com/wow-forever/stat-priority) by default (Pawn, [Forever Leveling BiS](https://github.com/thunder426/ForeverLevelingBiS-API), or your own Personal Stat Weights optional).

Based on [AutoGear](https://github.com/BujuArena/AutoGear) by Synthetikaryote and BujuArena ([CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/)).

Install as `Interface/AddOns/TyGear`. Disable AutoGear while using TyGear — both would fight over loot and gear.

## Getting started

1. Type `/tg` to open options.
2. Under **Evaluation → Stat weights**, pick **MythicSim** (default), **Pawn**, **Forever Leveling BiS**, or **Personal Stat Weights**. MythicSim uses imported EP weights from mythicsim.com; if a specialization has no MythicSim row, TyGear falls back to Pawn when it is installed. Pawn and Forever Leveling BiS are optional dependencies: when either is not loaded, that choice appears faded as **(not loaded)** and cannot be selected. Override Pawn scale stays hidden unless Pawn is selected and loaded. Forever Leveling BiS supplies weights only through its API; TyGear still scores and equips gear itself. Personal Stat Weights starts from the MythicSim numbers for every spec of your class (built-in profiles where MythicSim has no row). The import/export box at the bottom of that tab uses a short `TG2` string of only the weights you changed. Tooltips label that score **TyGear: Personal score:**.
3. Under **Evaluation**, TyGear shows the active specialization: the talent tree with the most points. With no points spent, it uses the general profile (None). **Override specialization** is directly under that. **Automatically equip gear** is under **Loot**. The override is saved per character.
4. Use `/tg toggle` anytime you want to turn automatic gearing off (for example before a loot roll you want to control yourself).

## What to expect

- Upgrades found in combat are equipped when combat ends.
- Bag items TyGear considers upgrades are marked in Baganator when TyGear is chosen as the upgrade source there (same idea as choosing TyGear as the junk source for vendor-sell items).
- Gear TyGear cannot score, slot and item ignore controls, and the keep list live on the **Ignored List** tab. Items on the ignore list, including the keep list, are not sold or evaluated.
- Items you always want to **NEED** (for example a crafting green in a dungeon) go on the **Need List** tab; add them near the top of that tab or with a key binding.
- **Keep unbound grey gear** is on the Ignored List tab with the keep list. That list starts with Forever crafting tools; add more near the top of that tab. Every fishing pole is kept when selling even if its item ID is removed.
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

Esc → Key Bindings → TyGear: the **ignore list** key keeps the hovered item and skips evaluation. The **need list** key forces NEED.

## Note

TyGear is for leveling convenience. MythicSim weights are raid-reference EP values and a strong default for Forever; they are still a guide, not a substitute for your own sim.
