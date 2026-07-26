# FE MoonJump — infinite jump / BotW-style flight

Standalone UE4SS **Lua** mod for Fading Echo (`UE_YGRO`).

## Installation

Copy the folder into:

```
<game>/UE_YGRO/Binaries/Win64/ue4ss/Mods/
```

(i.e. `FEMoonJump/enabled.txt` + `FEMoonJump/Scripts/main.lua`)

## Two modes, independent

| Key | Mode | Effect |
|---|---|---|
| **F7** | MoonJump | As long as **JUMP is held**, the vertical velocity is forced upward → continuous ascent. It's the BotW moonjump. |
| **F6** | MultiJump | `JumpMaxCount = 999` → you can re-jump in mid-air indefinitely, keeping the game's jump physics. |

Both can be active at the same time.


## How it works

- **MoonJump**: loop at ~60 Hz. It reads the key hold with
  `PlayerController:IsInputKeyDown({KeyName=FName("SpaceBar")})` (same method as the Keystrokes
  mod), and calls `pawn:LaunchCharacter({X=0,Y=0,Z=speed}, false, true)`.
  `LaunchCharacter` is a UFUNCTION of `ACharacter` (BP-exposed) → callable via UE4SS.
  `bXYOverride=false` keeps horizontal control; `bZOverride=true` overwrites the vertical
  velocity every frame, so gravity doesn't accumulate and the ascent stays steady.
- **MultiJump**: writes the pawn's `JumpMaxCount` property. It's re-applied every
  2 s, because the pawn is recreated on respawn and on zone change. The old value is
  saved and restored on shutdown.

The mod only calls gameplay UFUNCTIONs and writes no stat → it doesn't enter the
`UStatisticSubsystem` crash path described in §5 of `FadingEcho_Modding_Reference.md`.
