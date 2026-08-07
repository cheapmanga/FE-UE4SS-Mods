# FE Teleport — save & restore your position

Standalone UE4SS **Lua** mod for Fading Echo (`UE_YGRO` / Project Ygro).
No compilation needed — pure Lua.

A lightweight alternative to the Cheat Engine teleport table: press one key to
memorize where you stand, move anywhere, press another to snap back. Ideal for
practicing a route, retrying a jump, or hunting glitches from a fixed spot.

**Download:** [⬇ FETeleport.zip](https://raw.githubusercontent.com/cheapmanga/FE-UE4SS-Mods/main/dist/FETeleport.zip)

## Installation

Copy the folder into:

```
<game>\UE_YGRO\Binaries\Win64\ue4ss\Mods\
```

(i.e. `FETeleport\enabled.txt` + `FETeleport\Scripts\main.lua`)

Then launch the game. The mod loads automatically and prints
`[FadingEchoTrainer] loaded; F6 saves position, F7 loads position` to
`Win64\UE4SS.log`.

## Controls

| Key | Effect |
|---|---|
| **F6** | Save the current player position **and** rotation (including camera/control rotation). |
| **F7** | Teleport back to the saved position and rotation. |

There is no console command — everything is on F6 / F7. Only one slot is kept;
pressing F6 again overwrites it. The slot is cleared when the game is closed.

## How it works

- The player actor is resolved through `GameplayStatics.GetPlayerCharacter`
  (falling back to `GetPlayerPawn`, then to the `PlayerController.Pawn`), using
  **UEHelpers** when available and a `StaticFindObject` fallback otherwise.
- **Save** reads `K2_GetActorLocation` / `K2_GetActorRotation` on the pawn and
  `GetControlRotation` on the controller, then copies the raw X/Y/Z and
  Pitch/Yaw/Roll into plain Lua tables (so the saved values survive the pawn
  being recreated on respawn or zone change).
- **Load** calls `K2_SetActorLocationAndRotation(pos, rot, sweep=false, {}, teleport=true)`
  and re-applies the control rotation with `SetControlRotation`, so the camera
  faces the same way it did when you saved.
- Every game-state read/write is wrapped in `pcall` and run through
  `ExecuteInGameThread`, so a transient failure (pawn not ready yet, mid-load)
  logs a line instead of crashing the mod.

The mod only calls gameplay UFUNCTIONs and writes no stat, so it stays clear of
the `UStatisticSubsystem` crash path that affects the giver-style mods.

## Notes

- If F7 does nothing, check `Win64\UE4SS.log` — a "no valid player actor" line
  means the pawn wasn't ready (e.g. still on a loading screen); try again once
  you're in control.
- Teleporting far enough can land you outside the loaded zone. Pair it with
  `Void Cancel` if you plan to save a spot that is out of bounds.
