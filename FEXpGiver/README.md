# FE XP Giver — Ætherfact points

Standalone UE4SS **Lua** mod for Fading Echo (`UE_YGRO`). Type `xp` in the in-game
console: +1 Ætherfact point. Every time.

## Installation
Copy the folder into `<game>/UE_YGRO/Binaries/Win64/ue4ss/Mods/`
(i.e. `enabled.txt` + `Scripts/main.lua`).

## Usage
In-game console (F10). Output also goes to the UE4SS console, prefixed `[XpGiver]`.

| Command | Effect |
|---|---|
| `xp` | +1 Ætherfact point |
| `xp <n>` | +n points (e.g. `xp 5`) |
| `xp status` | shows the balance, granting nothing |

Each grant shows the before/after balance: if the number doesn't move, you'll see it.

## What an "Ætherfact point" is

The **`SkillPointBalance`** statistic, row 3 of `DT_PerksStatTemplate`
(`/Game/Game/Perks/Test/DT_PerksStatTemplate`, `default=0 min=0 max=+Inf`).

The name "Ætherfact" appears nowhere in the code: it's a purely UI term. The link
was established by cross-referencing four sources from the extracts:

- `WBP_PerkToolTip` displays `Cost` + `Ætherfact point(s)` → that's the price of perks.
- **Every** `DA_Perk_*.json` carries a `StatisticCondition` on `SkillPointBalance`
  → that's the cost check at purchase.
- `DA_IncreaseSkillPoints_XS_StatisticModifier` = `SkillPointBalance += 1.0`
  (`Operator=Addition`, `Operand=FlatValue 1.0`, `StatisticIndex=3`), referenced by
  `DA_LevelUpDescriptor` → that's the level-up reward.
- The data asset's `StatisticIndex: 3` matches row 3 of the table exactly.

## How it works

`UStatisticHolderComponent` exposes 6 BlueprintCallable functions (`exec*` symbols
confirmed in the PDB). Exact signatures, read from the mangled symbols:

```
?IncreaseStatisticBaseValue@UStatisticHolderComponent@@QEAAXVFString@@M@Z
?SetStatisticBaseValue@UStatisticHolderComponent@@QEAAXVFString@@M@Z
?GetStatisticValue@UStatisticHolderComponent@@QEBAMVFString@@@Z
```

i.e. `(FString StatisticName, float Value)`. The mod calls
`IncreaseStatisticBaseValue("SkillPointBalance", n)`.

### Pitfall: `StatisticName` is an `FString`, not an `FName`

`GetStatisticValue` is **overloaded** in C++ (`FString` / `FName` /
`FStatisticIdentifier`), but it's the `FString` overload that's exposed to
Blueprint. Passing an `FName` object **crashes the game**: UE4SS writes the argument
as a `StrProperty` (`push_strproperty` → `FString::SetCharArray`) and dereferences
anything → `EXCEPTION_ACCESS_VIOLATION`. You have to pass a raw Lua string.

The `FGenericPropertyParams` type of the `NewProp_` entries in the PDB **can't**
settle `FName` vs `FString`: it covers both. Only the mangled symbol says which.

**Why not `ApplyStatisticModifierSet(DA_IncreaseSkillPoints_XS)`**, which is
nevertheless the game's path? Because a modifier set is a *layer* you apply and
remove (`Apply`/`Unapply`). Nothing guarantees that applying the same descriptor
twice stacks it twice — yet the whole point here is to be able to retype `xp` in a
loop. `IncreaseStatisticBaseValue` writes the **base** value: cumulative by
construction, and therefore repeatable.

## How the right component is found

Several `StatisticHolderComponent`s coexist (one per template: health, perks…),
and they aren't distinguishable by read alone — `GetStatisticValue` returns `0`
both for "stat at zero" and for "stat unknown to this template".

- **Main path**: `PH_XP_Manager_C` (an `ActorComponent`) exposes a `StatHolder`
  property. It's the component that manages the currency — it has `UpdateCurrency(CurrencyToAdd)`,
  `XPCurrency`, `OnCurrencyIncrease` — so its holder is the one for the perks template.
- **Fallback**: sweep all `StatisticHolderComponent`s, writing then reading back.
  The right one is the one whose value actually moves; the others are ignored.

## Notes
- No key assigned (F1-F4 = FE Unlocker, F7 = FEInfiniteCore). Console only.
- No command clash with the other FE mods: `xp` is free.
- The balance is bounded to `min=0` by the table: you can't drop below zero.
