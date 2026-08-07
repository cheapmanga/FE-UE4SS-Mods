# FE Camera — change the field of view

Standalone UE4SS **Lua** mod for Fading Echo (`UE_YGRO`).

Widens or narrows the player camera's field of view. A wide FOV shows more of the
room around One (handy for screenshots and for reading a platforming section), a
narrow one zooms in on a detail. The original value is saved the first time you
touch it, so `fov reset` always gets you back.

**Download:** [⬇ FECamera.zip](https://raw.githubusercontent.com/cheapmanga/FE-UE4SS-Mods/main/dist/FECamera.zip)

## Installation

Copy the folder into:

```
<game>\UE_YGRO\Binaries\Win64\ue4ss\Mods\
```

(i.e. `FECamera\enabled.txt` + `FECamera\Scripts\main.lua`)

## Console commands (² key)

| Command | Effect |
|---|---|
| `fov` | Show the current FOV, the saved original, and the lock state. |
| `fov <n>` | Set the FOV — `60` is tight, `90` is roughly the game default, `120` is wide. |
| `fov reset` | Restore the value saved at first use and release the lock. |
| `fov lock` | Toggle a slow loop (~1 s) that re-applies the FOV if the game overwrites it. |

`fov status` is the same as a bare `fov`. Values are clamped to **10 – 170**:
extreme angles are a legitimate screenshot trick, but below ~10 the view
degenerates into an unusable sliver.

## How it works

- The FOV lives on the `APlayerCameraManager` owned by the `PlayerController`
  (`PlayerController.PlayerCameraManager`). If that reference is missing, the mod
  falls back to enumerating `PlayerCameraManager` actors and filtering out Class
  Default Objects.
- Setting the FOV tries **three** paths and reports which ones took:
  1. `SetFOV(NewFOV)` — the BP-exposed UFUNCTION on the camera manager, which
     locks the angle;
  2. the `DefaultFOV` property — survives a camera that recomputes its own value;
  3. the pawn's `UCameraComponent.FieldOfView` — only the component owned by
     *our* pawn, so cinematic and spectator cameras are left alone.
- Reading uses `GetFOVAngle()` and falls back to `DefaultFOV`.
- `fov reset` re-applies the saved value and then calls `UnlockFOV()`, so the game
  gets its camera back instead of staying pinned at the last value we asked for.
- `fov lock` runs a 1 s `LoopAsync` that hands **one stable function reference** to
  `ExecuteInGameThread`. Passing a fresh closure every pass would let the GC free it
  before it runs, which makes UE4SS drop the EngineTick hook and stops *every* Lua
  mod until the game restarts.

## Notes

- ⚠️ **Not tested in game yet.** Written against the standard Unreal camera API;
  report anything that misbehaves.
- The game can reassert its own FOV on camera transitions (cutscenes, forms, zone
  changes). That is exactly what `fov lock` is for — turn it on if your value keeps
  slipping back.
- Nothing is saved to disk: restarting the game restores the normal FOV.
- A call returning without error does not prove the camera moved. The status line
  tells you which write paths succeeded — check the screen too.
- Changing the FOV changes what you can see of a room. Don't use it in a run you
  intend to submit unless the ruleset allows it.
