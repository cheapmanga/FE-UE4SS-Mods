# FE VoidCancel — fall forever, no void, no respawn

Standalone UE4SS **Lua** mod for Fading Echo (`UE_YGRO`).

Toggles the **Void Cancel** state on demand: you keep falling past the usual fall
limit, the void never catches you and the game never respawns you. The speedrun
setup (Cutscene Skip, then falling until the respawn fails) achieves the same
thing, but it is fiddly and **sticks to your save file**. This mod flips the same
two engine switches directly, and — crucially — **lets you turn it back off**.

**Download:** [⬇ FEVoidCancel.zip](https://raw.githubusercontent.com/cheapmanga/FE-UE4SS-Mods/main/dist/FEVoidCancel.zip)

## Installation

Copy the folder into:

```
<game>\UE_YGRO\Binaries\Win64\ue4ss\Mods\
```

(i.e. `FEVoidCancel\enabled.txt` + `FEVoidCancel\Scripts\main.lua`)

## Controls

| Key | Effect |
|---|---|
| **F9** | **Enable** the Void Cancel — fall forever, no void, no respawn. |
| **F10** | **Disable** it — restores the normal void + respawn behaviour. |

There is no console command; everything is on F9 / F10. The mod reports each
toggle (and the internal counter value) in the **UE4SS console window**.

> ⚠️ **F10 note:** depending on your UE4SS build, F10 may also open the UE4SS
> debug GUI. If the two clash, change `DEACTIVATE_KEY` at the top of
> `Scripts\main.lua` to any other `Key.*` value.

## How it works

Confirmed by reversing the binary — on the player's `UDeathBehaviorComponent`:

| Call | Effect |
|---|---|
| `PreventFallDeath()` | increments `PreventFallDeathVolumeActivated` → no void |
| `AllowFallDeath()` | decrements that counter |
| `SetPreventRevive(b)` | sets `PreventRevive` → no respawn |

The Void Cancel state is simply **counter > 0 AND `PreventRevive` = true**.

- **Enable** calls `PreventFallDeath()` + `SetPreventRevive(true)`.
- **Disable** calls `SetPreventRevive(false)`, then drains the counter back to 0
  with repeated `AllowFallDeath()` calls (guarded at 256 iterations so it can
  never spin forever, and never pushed negative). If the property can't be read
  back, it falls back to a few `AllowFallDeath()` calls plus a direct write.

The player pawn is resolved with `FindFirstOf("BP_CoreYgroCharacter_C")`, and the
component is looked up as `BP_DeathBehaviour` / `DeathBehaviour` before falling
back to a global instance.

The mod calls **only these UFUNCTIONs and manipulates no stat**, so it cannot
trigger the `UStatisticSubsystem` crash path that affects the giver-style mods.

## Notes

- Unlike the glitch setup, this state is **not** written to your save — it lives
  only for the session, and F10 clears it. That makes it safe for practice.
- Falling for a very long time can still end in a `fatal error` crash, exactly as
  with the manual glitch. Don't ride it forever.
- Every engine call is wrapped in `pcall`, and all the work happens inside
  `ExecuteInGameThread`, so a transient failure logs a line instead of killing
  the mod.
