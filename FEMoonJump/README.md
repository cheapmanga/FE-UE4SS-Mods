# FE MoonJump — infinite jump / BotW-style flight

Standalone UE4SS **Lua** mod for Fading Echo (`UE_YGRO`).

## Installation

Copy the folder into:

```
<game>/UE_YGRO/Binaries/Win64/ue4ss/Mods/FEMoonJump/
```

(i.e. `FEMoonJump/enabled.txt` + `FEMoonJump/Scripts/main.lua`)

## Two modes, independent

| Key | Mode | Effect |
|---|---|---|
| **F7** | MoonJump | As long as **JUMP is held**, the vertical velocity is forced upward → continuous ascent. It's the BotW moonjump. |
| **F6** | MultiJump | `JumpMaxCount = 999` → you can re-jump in mid-air indefinitely, keeping the game's jump physics. |

Both can be active at the same time.

## Console (F10)

```
moonjump              toggle
moonjump speed <n>    ascent speed, cm/s (default 700)
moonjump key <FKey>   watched key (default SpaceBar)
moonjump status       current state
multijump             toggle
```

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

## To check in-game (not tested)

- **Controller**: set `moonjump key Gamepad_FaceButton_Bottom` if you play on a pad.
- If the jump key has been remapped, `moonjump key <FKey>` accepts any Unreal FKey name.
- If `LaunchCharacter` doesn't respond, it means the pawn doesn't inherit from `ACharacter` as assumed:
  the fallback would be to write `Velocity.Z` directly on the `CharacterMovement`. Let me know, we'll
  adjust.
- Going very high can take you out of the loaded zone: combine with `ue4ss-FEFreeRoam`
  (red walls + reroute off) and, in case of a fatal fall, the Void Cancel toggle.
