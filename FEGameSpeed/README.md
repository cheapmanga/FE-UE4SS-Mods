# FE GameSpeed — slow-motion and fast-forward

Standalone UE4SS **Lua** mod for Fading Echo (`UE_YGRO`). Works on both the full game (Project Ygro) and the Fading Echo Demo.

Scales the speed of the whole game. Slow it right down to study a glitch frame by
frame, or speed it up to skip a stretch you have already practised a hundred times.

**Download:** [⬇ FEGameSpeed.zip](https://raw.githubusercontent.com/cheapmanga/FE-UE4SS-Mods/main/dist/FEGameSpeed.zip)

## Installation

Copy the folder into:

```
<game>\UE_YGRO\Binaries\Win64\ue4ss\Mods\
```

(i.e. `FEGameSpeed\enabled.txt` + `FEGameSpeed\Scripts\main.lua`)

## Console commands (² key)

| Command | Effect |
|---|---|
| `gamespeed` | Show the current dilation. |
| `gamespeed <n>` | Set it — `0.25` quarter speed, `1` normal, `3` triple. |
| `gamespeed reset` | Back to 1.0. |

Values are clamped to **0.05 – 10**. Zero is deliberately refused: a dilation of 0
freezes the game, console included, leaving no way to undo it.

## How it works

Calls `UGameplayStatics::SetGlobalTimeDilation(WorldContextObject, TimeDilation)`,
the engine's own global time scale — the same knob Unreal uses for slow-motion.
The world context is resolved through UEHelpers, falling back to the player pawn
(an actor is a valid WorldContextObject).

`gamespeed` with no argument reads the live value back with
`GetGlobalTimeDilation` rather than trusting what the mod last wrote, so it stays
honest if something else changed it.

## Notes

- ⚠️ **Not tested in game yet.** Written against the standard Unreal API; report
  anything that misbehaves.
- This is engine-level, so **physics and animation slow down too** — it is not a
  player-only speed change. For that, see `FESpeed`.
- Time dilation is not saved anywhere: restarting the game restores normal speed.
- Because everything slows down, a timer running in real time (LiveSplit) will
  **not** agree with what you see. Never use this during a run you intend to submit.
