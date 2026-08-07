# FE Jojo

Fly anywhere. Two commands.

```
jojo on     arm it, then travel through any Pipe — you come out flying
jojo off    stop and clean up
```

**Download:** [⬇ FEJojo.zip](https://raw.githubusercontent.com/cheapmanga/FE-UE4SS-Mods/main/dist/FEJojo.zip)

## Install

Copy the `FEJojo` folder into:

```
<game>\UE_YGRO\Binaries\Win64\ue4ss\Mods\
```

Open the console with `²` (or `~`) and type `jojo on`.

## How to use it

1. `jojo on`
2. Travel through **any Pipe**, normally
3. On the way out you keep the Flying movement mode — you can now fly
4. `jojo off` when you are done

You **must** go through a Pipe. The mod does not invent the flying state, it
keeps one you actually reached.

## What this is

Travelling through a Pipe puts the character in Flying movement mode, and the
game takes it back on the way out. This mod keeps it.

On build **1.0.28121** the glitch has not been reproduced without a mod.

## How it works

### Two separate values

The character carries two things that both say something about travelling, and
telling them apart is the whole point of this mod.

**`ESplineTravelerState`** — the traveler component's own state flag:

| Value | Name | When |
|--:|---|---|
| 0 | `Undefined` | not travelling |
| 1 | `Snapping` | latching onto the spline |
| 2 | `Traveling` | riding the Pipe |
| 3 | `Ejecting` | being thrown out at the end |
| 4 | `TravelingAuto` | automatic travel |

**`EMovementMode`** — the engine's movement mode on the character:

| Value | Name |
|--:|---|
| 1 | `Walking` |
| 3 | `Falling` |
| 5 | `Flying` |

`USplineTravelerComponent::SetState()` pushes **both** a movement mode (from its
`MovementModesByState` map) and a form effect (from `GameEffectsByState`) onto
the `UCharacterMovementComponent`. Only `ResetComponentState()` undoes that, and
it is called from the checkpoint Blueprint, never by the component itself.

### Flying is what matters, not the flag

Only state **`Traveling(2)`** carries `MovementMode = Flying(5)`. That pairing is
the glitch. Everything else is noise:

- `Ejecting(3)` maps to `Falling(3)` and the game re-imposes walking on every
  tick, so holding it achieves nothing — measured at 369 useless re-applications
  in a single run.
- `Falling(3)` is what a normal jump looks like. Treating "anything but walking"
  as the glitch produces a false positive on every jump.

And the decisive observation: during ordinary travel the **state flag flickers
back to `Undefined(0)` about ten times a second while the movement mode stays
`Flying(5)`**. Traced at 20 ms:

```
t=2.96s   Snapping(1)    Falling(3)    entering the Pipe
t=3.20s   Traveling(2)   Flying(5)     riding it
t=6.22s   Undefined(0)   Flying(5)     flag cleared, MODE KEPT
t=9.48s   Undefined(0)   Walking(1)    the mode is taken back
```

The flag going to zero is harmless. Losing the mode is what ends the glitch.

### What the mod actually does

It watches the **movement mode**, and only when that falls back to `Walking(1)`
does it re-apply the travel state.

Re-applying on every flag flicker also works, but it stutters badly: each
`SetState()` re-pushes the mode *and* the form effect onto the movement
component, ten times a second. Acting only when the mode really drops is what
makes it smooth.

That is also why the mod cannot invent the state from nothing. Calling
`SetState()` with no spline attached leaves the component describing a journey
along a spline that does not exist, and the travel update dereferences it — the
game dies on the next tick with an access violation. You have to go through a
real Pipe; the mod only keeps what you reached.

## Warnings

- **This is written to saves.** Use a throwaway save. A stuck movement mode can
  survive a save.
- **`jojo off` does not clear everything.** Travelling leaves a snap attraction
  effect and a re-attach cooldown behind, and this mod cannot clear them. If
  snapping misbehaves afterwards, reload.
- Never try to force the flying state without going through a Pipe. With no
  spline attached the game crashes on the next tick — the mod refuses to do it
  for that reason.

## Compatibility

Built and tested in game on **1.0.28121**. It reads the player through three
fallback routes, so it does not require `UEHelpers` to be loaded.
