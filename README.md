# FE UE4SS Mods

A collection of **UE4SS Lua mods** for **Fading Echo** (`UE_YGRO` / Project Ygro).
Works on both the **full game (Project Ygro)** and the **Fading Echo Demo**.
No compilation needed — pure Lua.

## Mods

| Mod | Console cmd | What it does | Download |
|---|---|---|---|
| **FEBadApple** | `badapple` | Plays the Bad Apple!! video **rendered by the game's own cubes**, frame by frame | [⬇ FEBadApple.zip](https://raw.githubusercontent.com/cheapmanga/FE-UE4SS-Mods/main/dist/FEBadApple.zip) |
| **FEChestHopper** | `chest` | Teleport between the loaded chests (nearest first, tour of the zone) | [⬇ FEChestHopper.zip](https://raw.githubusercontent.com/cheapmanga/FE-UE4SS-Mods/main/dist/FEChestHopper.zip) |
| **FECoreGiver** | `core` | Give / spawn an elemental core on your pawn | [⬇ FECoreGiver.zip](https://raw.githubusercontent.com/cheapmanga/FE-UE4SS-Mods/main/dist/FECoreGiver.zip) |
| **FEKillAll** | `killall` | Kill all loaded enemies in the level | [⬇ FEKillAll.zip](https://raw.githubusercontent.com/cheapmanga/FE-UE4SS-Mods/main/dist/FEKillAll.zip) |
| **FEMoonJump** | `moonjump` | Infinite jump / BotW-style flight (F7 / F6) | [⬇ FEMoonJump.zip](https://raw.githubusercontent.com/cheapmanga/FE-UE4SS-Mods/main/dist/FEMoonJump.zip) |
| **FESkins** | `skin` | Access One's hidden skins | [⬇ FESkins.zip](https://raw.githubusercontent.com/cheapmanga/FE-UE4SS-Mods/main/dist/FESkins.zip) |
| **FESourceGiver** | `source` | Give / connect sources | [⬇ FESourceGiver.zip](https://raw.githubusercontent.com/cheapmanga/FE-UE4SS-Mods/main/dist/FESourceGiver.zip) |
| **FETeleport** | F6 / F7 | Save your position & rotation, then teleport back to it | [⬇ FETeleport.zip](https://raw.githubusercontent.com/cheapmanga/FE-UE4SS-Mods/main/dist/FETeleport.zip) |
| **FEVolume** | `Engine.ini` | See invisible walls, triggers & collision volumes (UE debug-draw config, not a Lua mod) | [⬇ FEVolume.zip](https://raw.githubusercontent.com/cheapmanga/FE-UE4SS-Mods/main/dist/FEVolume.zip) |
| **FEXpGiver** | `xp` | Give Ætherfact points (XP / skill points) | [⬇ FEXpGiver.zip](https://raw.githubusercontent.com/cheapmanga/FE-UE4SS-Mods/main/dist/FEXpGiver.zip) |

Each mod that ships a `README.md` documents its own commands and settings in detail.

## Installation

1. Have **[UE4SS](https://github.com/cheapmanga/FE-UE4SS-Mods/blob/main/UE4SS-installation.md)** installed for Fading Echo.
2. Download a mod's `.zip` above and extract it into:
   ```
   <game>\UE_YGRO\Binaries\Win64\ue4ss\Mods\
   ```
   You should end up with e.g. `Mods\FEBadApple\enabled.txt` and `Mods\FEBadApple\Scripts\main.lua`.
3. Launch the game. Open the console with the **²** key and type the mod's command
   (`badapple`, `chest`, …). Most mods print their help when run with no argument.

> ⚠️ Extract the `.zip`, don't copy the `main.lua` text by hand — pasting into an
> editor can reflow long lines and break the script.

## UE4SS_Signatures

`UE4SS_Signatures/StaticConstructObject.lua` is an optional AOB-scan override for
UE4SS. Some Fading Echo demo builds fail to auto-resolve `StaticConstructObject`,
which the object-spawning mods rely on. If a mod logs a `StaticConstructObject`
resolution error, drop this file into:

```
<game>\UE_YGRO\Binaries\Win64\ue4ss\UE4SS_Signatures\
```

Most builds don't need it — it's here purely for convenience.

## Notes

- These are debug / speedrun / sandbox tools for a single-player game.
- The game itself is not included.
- FEBadApple bundles its frame data (`Scripts/data/`) and its soundtrack
  (`badapple_audio.mp4`) — keep them next to the mod.
