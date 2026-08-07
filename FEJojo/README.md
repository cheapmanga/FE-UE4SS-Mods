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

`USplineTravelerComponent::SetState()` pushes a movement mode and a form effect
onto the character's movement component. Only `ResetComponentState()` undoes
that, and it is called from the checkpoint Blueprint, never by the component
itself.

So the mod watches the **movement mode** and re-applies the travel state when it
falls back to walking.

Watching the mode rather than the state flag is the whole trick. During normal
travel the state flag flickers back to `Undefined` about ten times a second
while the movement mode stays `Flying` — the glitch lives in the mode, not in
the flag. Re-applying on every flicker works, but stutters badly, because each
call re-pushes the mode and the form effect. Acting only when the mode actually
drops is what makes it smooth.

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
