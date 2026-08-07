# FE Ascend — rise by flying, and unlimited mid-air re-jumps

Standalone UE4SS **Lua** mod for Fading Echo (`UE_YGRO`).

**Download:** [⬇ FEAscend.zip](https://raw.githubusercontent.com/cheapmanga/FE-UE4SS-Mods/main/dist/FEAscend.zip)

## Installation

Copy the folder into:

```
<game>/UE_YGRO/Binaries/Win64/ue4ss/Mods/
```

(i.e. `FEAscend/enabled.txt` + `FEAscend/Scripts/main.lua`)

## Two modes, independent

| Key | Mode | Effect |
|---|---|---|
| **F3** | Ascend | As long as **JUMP is held**, the vertical velocity is forced upward → continuous rise. This is flight, not jumping. |
| **F4** | MultiJump | `JumpMaxCount = 999` → re-jump in mid-air indefinitely, keeping the game's own jump physics. |

Both can be active at the same time.

> **Why is it not called MoonJump?** Because F3 is not one. Nothing is jumping:
> the character is pushed upward continuously, which is flight. The mode that
> actually behaves like a moon jump is **MultiJump on F4** — repeated jumps in
> mid-air. The mod used to carry the wrong name for its main mode.

> **Why F3/F4?** F6/F7 belong to FETeleport and F9/F10 to FEVoidCancel — with
> several mods installed the same key would otherwise fire two handlers at once.

## Console commands

| Command | Effect |
|---|---|
| `ascend` | toggle the rise mode |
| `ascend speed <n>` | rise speed (default 700, in cm/s) |
| `ascend key <FKey>` | watched key (default `SpaceBar`, e.g. `Gamepad_FaceButton_Bottom`) |
| `ascend status` | current state |
| `multijump` | toggle unlimited mid-air re-jumps |

## How it works

**Ascend** relies on `LaunchCharacter(vel, false, true)`, a `UFUNCTION` with a
known signature, called every frame while the key is held.

**MultiJump** writes `JumpMaxCount = 999` on the pawn and restores the original
value when switched off, so nothing is left behind.

The per-frame tick passes the **same function reference** on every pass. Handing
UE4SS a fresh closure at high frequency makes it drop its EngineTick hook, and
then every Lua mod stops silently.
