# FE Core Giver — Fading Echo

Standalone UE4SS **Lua** mod for Fading Echo (`UE_YGRO`). It does just **one** thing:
give you an elemental core on demand.

It's the `CORE GIVER` block of the **FE Unlocker**, extracted as-is, without the elevators,
the zones, the alpha walls or the doors.

## Installation
Copy the folder into `<game>/UE_YGRO/Binaries/Win64/ue4ss/Mods/`
(i.e. `enabled.txt` + `Scripts/main.lua`).

## Usage
Everything goes through the **in-game console** (F10). Output also goes to the UE4SS console,
prefixed `[CoreGiver]`.

| Command | Effect |
|---|---|
| `core water` | spawns a Water core and puts it in your hands |
| `core waste` | same, Waste |
| `core fire` | same, Lava |
| `core glitch` | same, Corruption |
| `core power` | same, PowerCore |
| `core <element> nograb` | drops it in front of you **without** grabbing it |
| `core list` | lists the available elements |

## How it works
The core is spawned 120 u in front of you, 40 u above, via
`BeginDeferredActorSpawnFromClass` + `FinishSpawningActor`, then passed to `StartGrab`
on your pawn. It's the **grab** that triggers the game's elemental charge (UI + LB +
power) — we don't force any variable by hand.

`nograb` skips the `StartGrab`: the core stays where it lands. Useful for testing the *Infinite Core*
as One (spawning a core without absorbing it).

## Notes
- The game's element names aren't the UI ones: `fire` → `LavaBall`,
  `glitch` → `CorruptionBall`.
- If the ball's class isn't loaded in memory yet, the mod says so and asks you
  to walk up to a core of that type once (that loads the class), then try again.
  It does not force-load the asset.
- The pawn is resolved in 3 attempts (PlayerController.Pawn → UEHelpers → non-CDO instance
  of `BP_CoreYgroCharacter_C`), and CDOs are excluded everywhere.
