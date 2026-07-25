# FE Chest Hopper

UE4SS Lua mod for **Fading Echo**: teleport from chest to chest from the console.

## Installation

Copy the folder into:

```
<game>/UE_YGRO/Binaries/Win64/ue4ss/Mods/FEChestHopper/
```

Expected structure:

```
FEChestHopper/
├── enabled.txt        (empty)
└── Scripts/
    └── main.lua
```

## Usage

Open the in-game console (**F10**), then:

| Command | Effect |
|---|---|
| `chest` | teleport to the next chest — the first call goes to the **nearest** one |
| `chest reset` | rebuild the tour from your current position |
| `chest prev` | go back to the previous chest |
| `chest <n>` | jump directly to the n-th chest of the tour |
| `chest list` | list the loaded chests with their distance (in meters) |
| `chest help` | command reminder |

## How it works

On the first `chest`, the mod collects all **loaded** chests, sorts them by
distance to the player, and freezes that list. Each subsequent `chest` advances
one step. Once it reaches the end, it loops back to the start.

The tour is rebuilt automatically if the number of chests changes
(level streaming) or if a memorized chest becomes invalid.

**Why a frozen sort rather than one recomputed on every jump?** Because a
recomputed sort would always send you back to the chest you came from (distance 0):
you'd bounce back and forth between two chests without ever covering the area.

## Detected classes

```
BP_Chest_Small_C   BP_Chest_Medium_C   BP_Chest_Big_C
BP_Chest_Special_LevelUp_C   BP_Chest_ALIENWARE_C
```

Found in `/Game/Game/Placeable/InteractiveObjects/Chest/` of the FModel extract.

## Known limitations

- **Only chests whose sublevel is loaded can be reached.** Those in a zone not yet
  streamed don't exist engine-side: no mod can find them. `chest list` shows the
  real state at time T.
- **The mod doesn't tell an open chest from a closed one.** The class does expose
  a `ChestDeactivated`, but it's an object reference, not a reliable state
  boolean — filtering on it risked hiding valid chests. The tour therefore
  includes them all.
- Landing at **+150 cm above** the chest, so you don't get stuck in its
  collision. Adjustable via `Z_OFFSET` at the top of `main.lua`.

## Status

**Not tested in-game** — written from the extract and the idioms already validated
in the other FE mods (`RegisterConsoleCommandGlobalHandler`,
`K2_SetActorLocation`, filtering of `Default__`). Lua syntax verified with `luac -p`.
