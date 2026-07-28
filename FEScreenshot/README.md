# FE Screenshot — take a screenshot

Standalone UE4SS **Lua** mod for Fading Echo (`UE_YGRO`). Works on both the full game (Project Ygro) and the Fading Echo Demo.

Renders a screenshot at a multiple of your screen resolution through Unreal's own
`HighResShot` command. On a 1440p screen, `shot 4` produces a 10240×5760 PNG — enough
to crop into a wallpaper or to zoom in on a detail you only half saw.

**Download:** [⬇ FEScreenshot.zip](https://raw.githubusercontent.com/cheapmanga/FE-UE4SS-Mods/main/dist/FEScreenshot.zip)

## Installation

Copy the folder into:

```
<game>\UE_YGRO\Binaries\Win64\ue4ss\Mods\
```

(i.e. `FEScreenshot\enabled.txt` + `FEScreenshot\Scripts\main.lua`)

## Console commands (² key)

| Command | Effect |
|---|---|
| `screenshot` | Screenshot at the default multiplier (**2x**). |
| `screenscreenshot <n>` | Multiplier — `shot 4` renders at four times the screen resolution. |

The multiplier is clamped to **1 – 8** and the console tells you when it clamped.
It is rounded down to a whole number, because `HighResShot` takes an integer
multiplier.

Files land in:

```
%LOCALAPPDATA%\UE_YGRO\Saved\Screenshots\
```

Unreal numbers them itself (`HighresScreenshot00000.png`, `…00001.png`, …), so the
newest file is the one you just took.

## How it works

- The mod builds the string `HighResShot <n>` and sends it through
  `UKismetSystemLibrary::ExecuteConsoleCommand(WorldContext, Command, SpecificPlayer)`.
- `SpecificPlayer` **must** be the current `PlayerController`. Passing `nil` silently
  does nothing — a lesson already paid for in two earlier mods.
- The world context comes from UEHelpers, falling back to the player pawn (an actor
  is a valid WorldContextObject).
- The capture itself is deferred into `ExecuteInGameThread`; the acknowledgement is
  printed synchronously, because the console's `FOutputDevice` is a dead pointer once
  you leave the handler body.

## Notes

- ⚠️ **Not tested in game yet.** Written against the standard Unreal
  `HighResShot` command; report anything that misbehaves.
- **No UI toggle.** `HighResShot` renders the 3D scene into its own render target and
  has no option for including the HUD — the engine only exposes a UI flag on the plain
  low-resolution `Shot` command. Rather than ship a `shot ui` that quietly does nothing,
  it was left out. Expect your screenshots to have **no HUD and no menus**.
- This mod takes over the `screenshot` name in the console, so Unreal's own built-in `Shot`
  command is shadowed while it is installed.
- High multipliers allocate a very large render target. `shot 8` on a 4K screen asks
  for a 30720-pixel-wide image — expect a long freeze, and a driver crash on a small GPU.
  Start at 2 and work up.
- A command sent without error does not prove a file was written. If nothing appears
  in `%LOCALAPPDATA%\UE_YGRO\Saved\Screenshots\`, check `UE4SS.log` and confirm you were actually in
  a loaded level.
