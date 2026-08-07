# FE Skins — One's hidden skins, mesh swaps & outline removal

Standalone UE4SS **Lua** mod for Fading Echo (`UE_YGRO`). It applies One's packaged
skins directly onto the character mesh (bypassing the Options menu), can swap One's
whole model for any mesh already shipped in the game, reskin/reshape Bob, and remove
One's black silhouette (outline).

Everything is driven from a single console command: **`skin`**.

**Download:** [⬇ FESkins.zip](https://raw.githubusercontent.com/cheapmanga/FE-UE4SS-Mods/main/dist/FESkins.zip)

## Installation

Copy the folder into:

```
<game>\UE_YGRO\Binaries\Win64\ue4ss\Mods\
```

so that you end up with:

```
FESkins\enabled.txt
FESkins\Scripts\main.lua
```

## Console

Open the in-game console with the **²** key (or use the UE4SS console window), then type
commands. Short status lines are echoed to the console; **detailed output goes to the
UE4SS console window** (slot dumps, per-component logs, diagnostics).

Running `skin` with no argument prints the current state and a command reminder.

### One — hidden skins

| Command | Effect |
|---|---|
| `skin one <0-4>` | Apply material set `Skin0`..`Skin4` on One's body/head/cape |
| `skin slots` | List the player's material slots, their current material and detected part (Body/Head/Cape) |
| `skin reset` | Restore the original materials that were in place before the first change |
| `skin lock` | Toggle a re-apply loop (every 2 s) that reasserts the chosen skin if the game overwrites it |

Skin ids:

| Id | Name | In the menu? |
|---|---|---|
| `0` | Default | Yes (Default) |
| `1` | Hellgur One | Yes |
| `2` | (hidden) | No — never exposed |
| `3` | (hidden) | No — never exposed |
| `4` | (hidden) | No — never exposed |

The game ships five complete material sets under `/Game/Art/Character/Hero/Skin<N>/`
(`MI_MainCharaBody_Skin<N>`, `MI_MainCharaHead_Skin<N>`, `MI_MainCharaCape_cinematic_Skin<N>`).
The Customization menu only exposes Default (Skin0) and "Hellgur One" (Skin1); Skin2/3/4
have no menu entry at all.

### One — full model swap

Replace One's skeletal mesh with any mesh already present in the game. Same technique as
the Bob swap: `SetSkinnedAssetAndUpdate` + read-back + override purge, and it works because
these assets are already cooked and loaded.

| Command | Effect |
|---|---|
| `skin mesh` or `skin mesh list` | List the available model aliases |
| `skin mesh <alias>` | Swap One's model for the mesh of that alias |
| `skin mesh reset` / `skin mesh off` | Restore One's original model and re-show hidden components/actors |
| `skin mesh comps` | List the mesh components on the player (name, class, hidden state) |
| `skin mesh near [radius]` | List actors within `radius` units of the player (default 300) — useful to find attached props |
| `skin mesh hide <ClassName_C>` | Hide every actor of the given class (e.g. a stray prop) |
| `skin mesh show` | Re-show components previously hidden by a swap |

Available aliases:

| Alias | Model |
|---|---|
| `bob` | Bob |
| `mime` | Marcel Bob |
| `rahne` | Rahne |
| `agent` | Agent |
| `critter` | Critter |
| `builder` | Builder |
| `kheleb` | Kheleb |
| `ranged` | Ranged |
| `rusher` | Rusher |
| `bungee` | BungeeMan |
| `wonder` | Last Wonder |
| `wonder2` | Last Wonder (2) |
| `wonder4` | Last Wonder (4) |
| `wonder5` | Last Wonder (5) |
| `disappear` | Disappear |
| `cine` | Builder (cinematic) |
| `mannequin` | Unreal Mannequin |
| `hat` | Rahne's hat (gag) |
| `one` / `hero` | One (original) |

An alias can also be matched by its display label. On a swap the mod purges material
overrides (to avoid black sections), removes the black outline overlay, and hides stray
components and attached actors (hair `BP_Bigoudi_C`, stick `BP_Stick_C`).

> **Skeleton caveat.** One uses `SKEL_Hero_facial_Skeleton`. A mesh built on a *different*
> skeleton (Bob, Rahne, enemies…) will render, but the animation will not follow: Unreal
> remaps bones by name, so mismatched names leave the model frozen (T-pose) or deformed.
> Only `SK_Hero_facial_optimization` shares One's skeleton. Treat swaps as experiments, not
> guarantees — `skin mesh reset` puts everything back.

### Bob — reskin & Marcel Bob

Targets the in-world Bob actors (`BP_Bob_Critter_C` and its `_Lava_C` / `_Waste_C`
variants, de-duplicated).

| Command | Effect |
|---|---|
| `skin bob` | Marcel Bob: swap Bob's mesh to `SKEL_Bob_Mime` |
| `skin bob keep` (or `skin bob mid`) | Marcel Bob mesh, but keep the original runtime materials (the game's parameterised MIDs) instead of the mesh's raw materials, which render black |
| `skin bob standard` (or `skin bob body`) | Reset Bob's body material to `MI_BobSkin_body` (normalises an elemental variant back to the base look) |
| `skin bob off` / `skin bob reset` | Restore Bob's original materials and mesh |
| `skin bob slots` | List each Bob actor's material slots |

"Marcel Bob" is the `SKEL_Bob_Mime` mesh (a moustached mime), not a material swap:
`MI_BobSkin_Mustache` is the moustache material, not a body skin.

### Outline — remove One's black silhouette

One's outline is an inverted-shell overlay: `BP_OverlayMeshComponent` duplicates the
character mesh into extra skeletal-mesh components and applies a black (`0x101010`)
outline material. This section removes those overlay meshes.

| Command | Effect |
|---|---|
| `skin outline` or `skin outline off` | Remove the outline via a staged cascade (E1→E5): the game's `SetOverlayHidden`, then per-component visibility/hidden/custom-depth, distance cull, tick disable, and a sweep of any remaining stray skeletal-mesh doubles |
| `skin outline on` | Restore the outline to the state saved before the first removal |
| `skin outline diag` | Diagnostic dump only — **writes nothing** |
| `skin outline lock` | Toggle a loop (every 1.5 s) that re-runs the removal if the game re-imposes the outline (form change, respawn…) |
| `skin outline hard` | **Nuclear**: also empties the doubles' geometry, destroys the components and nulls the outline materials. **Irreversible** until the level reloads — `skin outline on` cannot undo what `hard` destroyed |

### Other

| Command | Effect |
|---|---|
| `skin` | Current state + command reminder |
| `skin reset` | Restore One's original materials (see above) |
| `skin lock` | Toggle the skin re-apply loop (see above) |
| `skin menu` | Attempt to wire the orphan Bob spinner into the Options menu. **Has no effect on the UI** — kept only as a record (see below) |

## How it works

- **Direct on the mesh, not the menu.** Options > Customization is built from DataAssets in
  C++ when the screen is created, and no rebuild function is exposed. Injecting the orphan
  `DA_Skin_Bob_Spinner` into the descriptor array succeeds at the data level but the on-screen
  list never changes. So the mod writes materials/meshes straight onto the character's
  `SkeletalMeshComponent` (`SetMaterial(index, mat)` and `SetSkinnedAssetAndUpdate`). `skin menu`
  keeps the (ineffective) attempt for the record.
- **Assets are loaded on demand.** An asset whose character isn't present in the current zone
  isn't in memory. `Resolve()` therefore calls `LoadAsset` in both path forms and re-reads
  several times before giving up. If a mesh/material can't be resolved, the command fails cleanly.
- **Read-back is mandatory.** `SetSkinnedAssetAndUpdate` does not raise on a rejected mesh
  (incompatible skeleton, etc.), so the code re-reads `GetSkinnedAsset()`: an unchanged asset
  means the swap was refused, not applied.
- **Maintenance loops.** Because the game recreates the pawn, its attached actors and its
  overlay on respawn / form change / streaming, three background loops keep active states
  asserted: the skin lock (2 s), the outline lock (1.5 s), and a swap-maintenance loop (1.5 s)
  that re-hides attachments and re-kills the overlay while a mesh swap is active. They run
  quietly and only log when their result changes.

## Boot-time application (launcher-driven)

The top of `main.lua` has a `BOOT_*` block that the Fading Echo launcher
(`fe_launcher/core/skins.py`) rewrites to apply a skin/mesh/outline state at load time,
without typing a command. Keys: `BOOT_MESH`, `BOOT_SKIN` (0-4, or -1 for none),
`BOOT_OUTLINE` (`keep`/`off`/`on`), `BOOT_HIDE_STICK`, `BOOT_HIDE_HAIR`, `BOOT_DELAY_MS`
(delay before applying, to let the pawn load). Left at their defaults, the mod does nothing
until you use the console.

## Notes

- One's body materials have no colour parameter; changing a skin swaps the whole material
  instance set (body/head/cape), it does not tint the existing one.
- After a model swap, One's separate accessories (hair `BP_Bigoudi_C`, stick `BP_Stick_C`)
  are hidden because their attach bones no longer exist on the new geometry; `skin mesh reset`
  brings them back.
- The mod calls gameplay UFUNCTIONs and writes no statistic, so it stays out of the
  `UStatisticSubsystem` crash path.
