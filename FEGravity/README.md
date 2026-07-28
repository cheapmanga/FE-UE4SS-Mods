# FE Gravity — low gravity / gravity multiplier

Standalone UE4SS **Lua** mod for Fading Echo (`UE_YGRO`). It writes `GravityScale` on the
player pawn's `CharacterMovement` component, which is what a "Low Gravity" or a "Gravity
Multiplier" cheat does under the hood: `1` is the game's normal gravity, `0.3` makes One
floaty and long-jumping, `0` removes gravity entirely (you keep whatever vertical velocity
you had, so a jump never comes back down). The value you set is re-applied in the
background, because the pawn is destroyed and rebuilt on respawn and on zone change.

**Download:** [⬇ FEGravity.zip](https://raw.githubusercontent.com/cheapmanga/FE-UE4SS-Mods/main/dist/FEGravity.zip)

## Installation

Copy the folder into:

```
<game>\UE_YGRO\Binaries\Win64\ue4ss\Mods\
```

(i.e. `FEGravity\enabled.txt` + `FEGravity\Scripts\main.lua`)

## Console commands (² key)

Open the in-game console with the **²** key, then:

| Command | Effect |
|---|---|
| `gravity` | Show the current `GravityScale`, the saved original, and whether the mod is managing it. |
| `gravity status` | Same as `gravity`. |
| `gravity <n>` | Set the scale. `1` = normal, `0.3` = floaty, `0` = no gravity. |
| `gravity low` | Preset, same as `gravity 0.3`. |
| `gravity reset` | Restore the value saved the first time the mod touched the pawn, and stop re-applying. |
| `gravity off` | Same as `gravity reset`. |

Values are clamped to `0 .. 20`. A negative scale would send the character falling upwards
with no way to land, so it is refused and the console tells you the value was clamped.

## How it works

- The pawn is resolved from `PlayerController.Pawn` first (it always points at the pawn
  currently possessed, even one frame after a respawn), then `FindAllOf("BP_CoreYgroCharacter_C")`,
  then `UEHelpers.GetPlayerPawn` as a last resort. Class Default Objects (names containing
  `Default__`) are filtered out.
- The movement component is looked up as `CharacterMovement`, then
  `CharacterMovementComponent`, then `MovementComponent`. If none of those properties
  exists on this build, the mod falls back to a `FindAllOf` on the component classes and
  keeps the one whose `CharacterOwner` is our pawn. If it still finds nothing, the console
  prints which names were tried instead of failing silently.
- The **first** time you run a `gravity` command, the current `GravityScale` is saved as
  the original. `gravity reset` writes that value back.
- While a non-default value is set, a 2 s loop re-reads `GravityScale` and re-writes it if
  the game has reset it — that is what makes the setting survive a respawn or a zone change.
  The loop does nothing at all once you have run `gravity reset`.
- Every write goes through `ExecuteInGameThread`, and always through **the same** stable
  function reference. Handing a fresh closure to `ExecuteInGameThread` from a loop gets it
  registered by UE4SS and possibly collected before it runs, which makes UE4SS drop its
  EngineTick hook and stops *every* Lua mod until the game is restarted.

## Notes

- The game recomputes movement itself each frame (`AYgroCharacter` drives it from
  its own curves and per-form settings), so the mod re-asserts the value at ~30 Hz
  rather than writing it once. It only writes when the value has actually drifted.

- **This mod has NOT been tested in game yet.** It was written from the UE4SS API and the
  standard `UCharacterMovementComponent` layout; the game was not installed on the machine
  it was written on. If a command reports that `CharacterMovement` was not found, the error
  message lists the property and class names it tried — that is the information to report.
- `GravityScale` only affects the character's own movement component. World physics objects,
  projectiles and cinematics keep normal gravity. For a global slowdown use **FEGameSpeed**
  instead.
- `gravity 0` combines badly with a jump: with no gravity at all you keep rising. Use
  `gravity reset` to come back down.
- The mod writes one movement property and calls no statistic API, so it stays out of the
  `UStatisticSubsystem` crash path.
