# FE Source Giver

UE4SS (Lua) mod for **Fading Echo** — increments the number of **sources connected to the Bastion** via a console command.

**Download:** [⬇ FESourceGiver.zip](https://raw.githubusercontent.com/cheapmanga/FE-UE4SS-Mods/main/dist/FESourceGiver.zip)

## Installation

Copy the `ue4ss-FESourceGiver` folder into:

```
<game>\UE_YGRO\...\Binaries\Win64\ue4ss\Mods\
```

(keep the `Scripts/main.lua` + `enabled.txt` structure).

## Commands (in-game console, opened with **F10**)

| Command            | Effect |
|---------------------|-------|
| `source`            | +1 connected source |
| `source <n>`        | +n sources (e.g. `source 3`) |
| `source set <n>`    | set the total to n (e.g. `source set 12` → opens the ending) |
| `source status`     | show the current total, without changing anything |
| `source unlocked <n>` | +n *found* sources (the other stat, milestones 1/3/6/9) |

## What it touches

Two distinct stats exist in the game:

- **`ConnectedSources`** — sources *connected* to the Bastion. This is what this mod
  increments by default. The Level Blueprint tests `ConnectedSources == 12` to
  trigger the **FinalFight** (12 = 3 sources × 4 zones). So `source set 12`
  meets the condition for the ending.
- **`UnlockedSources`** — sources *found* in the zones (milestones 1/3/6/9).
  Accessible via `source unlocked <n>`.

## Technical notes

- API: `UStatisticHolderComponent` → `IncreaseStatisticBaseValue` /
  `SetStatisticBaseValue` / `GetStatisticValue`, signature `(FString, float)`.
- The stat name is an **FString** (raw Lua string) — passing an `FName`
  would crash the game.
- `ConnectedSources` is a stat of the *World* entity; the right holder is found
  automatically by "write then read back" (the only one whose value changes), then
  cached.
- Everything runs in `pcall`: if one piece fails, the game keeps going.
