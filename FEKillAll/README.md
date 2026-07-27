# FE KillAll — kill every loaded enemy

Standalone UE4SS **Lua** mod for Fading Echo (`UE_YGRO`). Works on both the full game (Project Ygro) and the Fading Echo Demo.

It works around `UYgroCheatManager_C::KillAllEnemies()`, which returns without error
but never actually kills the enemies placed in the level: its internal `Enemies` array
appears to be fed by the debug squad system, not by the enemies spawned in the map.

Instead of going through the CheatManager, this mod enumerates the live enemies itself
and triggers each one's death through its own `BP_DeathBehaviour` component (which
inherits from `UDeathBehaviorComponent`).

**Download:** [⬇ FEKillAll.zip](https://raw.githubusercontent.com/cheapmanga/FE-UE4SS-Mods/main/dist/FEKillAll.zip)

## Installation

Copy the folder into:

```
<game>\UE_YGRO\Binaries\Win64\ue4ss\Mods\
```

(i.e. `FEKillAll\enabled.txt` + `FEKillAll\Scripts\main.lua`)

## Console commands (² key)

Open the in-game console with the **²** key, then:

| Command | Effect |
|---|---|
| `killall` | Kill every currently loaded enemy. |
| `killall count` | Count the loaded enemies without killing anything. |

Any argument other than `count` is treated as a plain `killall`.

## How it works

- Enemies are found with `FindAllOf("BP_EnemyBase_C")`. Class Default Objects
  (names containing `Default__`) are filtered out, so only live instances remain.
- For each enemy, the mod resolves its `BP_DeathBehaviour` component and tries three
  death paths in order, stopping at the first that succeeds:

  | Order | Call | Notes |
  |---|---|---|
  | 1 | `NotifyHealthToZero()` | Clean path, inherited from `UDeathBehaviorComponent`, BlueprintCallable. |
  | 2 | `["Die Common"]` | Blueprint function whose name contains a space, so it is called with bracket syntax. |
  | 3 | `TriggerInstantFallDeath()` | Last resort, the "fatal fall" path. |

- After a run it reports how many enemies were killed vs. failed, and a breakdown of
  which method was used. Every enemy call is wrapped in `pcall`, so a single failure
  never aborts the whole pass.

## Notes

- If `killall` reports "no enemy loaded", you are likely not in a zone with living
  enemies — the command only affects what is currently loaded.
- The mod is fully synchronous. This matters because the console `FOutputDevice` (`Ar`)
  is only valid inside the synchronous body of the command handler; using it from
  deferred code crashed an earlier version.
- A call returning without error does not prove the enemy actually died. Always confirm
  on screen after running `killall`.
