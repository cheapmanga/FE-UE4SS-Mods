# FE Skin Menu — every skin, in the game's own Options menu

<img width="700" height="261" alt="image" src="https://github.com/user-attachments/assets/d4f2605e-dd93-429e-9f67-ac642b2637a3" />


For Fading Echo **1.0.27953**.

The game already contains five skins for One and a complete "Marcel Bob" spinner for Bob. The
menu only ever offered two of One's, and never showed Bob's row at all. This restores both — in
the real Options menu, with the game's own localized names — and finishes the artwork that was
still unpainted at this build.

**Download:** [⬇ FE-Skins-27953.zip](https://raw.githubusercontent.com/cheapmanga/FE-UE4SS-Mods/main/dist/FE-Skins-27953.zip) — mod **+ content patch**

| | Vanilla 1.0.27953 | With this |
|---|---|---|
| Customization ▸ One | Default, Hellgur One | + **Gamma One**, **Glitch One**, **Æther One** |
| Customization | One only | + a **Bob** row (Default / **Marcel Bob**) |
| Marcel Bob | no row; artwork unfinished | beret, black moustache, striped legs, per-element tint |
| Æther One | textures unfinished | the final artwork |

## Installation

The download holds two pieces, with two destinations.

**Content patch** — copy the three files from `Paks/` into:

```
<game>\UE_YGRO\Content\Paks\
```

**Mod** — copy the `FESkinMenu` folder from `Mods/` into:

```
<game>\UE_YGRO\Binaries\Win64\ue4ss\Mods\
```

Then **restart the game**: containers are only mounted at launch.

The pak alone already gives you every menu entry, so it is worth installing even without UE4SS —
only Marcel Bob stays inert without the mod.

## Use

Everything happens in **Options ▸ Customization**. Pick a skin, leave the section, confirm
*Apply changes?*, then close the pause menu — One is hidden while it is open.

Bob must be **loaded in the current area** for his row to show anything, and his change lands
within about two seconds.

## Why a mod is needed at all

`BP_Bob_Critter::SetSkin` is unfinished in this build: it swaps Bob's mesh, but never fixes his
materials — so the beret shows up and nothing else does. That is Blueprint bytecode, and bytecode
cannot be added by patching content. The mod finishes the job: dynamic material instances on all
three slots, the element tint (lava / waste / water), the texture rebinds the unfinished material
needs, and a watchdog that re-applies everything whenever the game rebuilds Bob's materials
underneath it.

The console command `skinmenu` lists a set of diagnostics used while building this. They are inert
unless you call them.

## What the content patch contains

| Package | Change |
|---|---|
| `DA_Skin_One_Spinner` | 2 → 5 entries, labels taken from the game's own `ST_Characters` |
| `DA_Skin_SubSection` | 1 → 2 rows, adding Bob's spinner |
| `SKEL_Bob_Mime` | the finished mime geometry — the beret is not modelled at all in 27953 |
| 6 × `T_BobCritterSkin_*` | Marcel's finished artwork; the body albedo does not ship in 27953 |
| 4 × `*_Skin04_*` | Æther One's finished artwork |

Of One's twenty skin textures, sixteen are already final in 27953 — Hellgur, Gamma and Glitch need
nothing. Only Æther was still being painted, and only Bob's skin was reworked wholesale.

## Version

Built from **1.0.27953** and verified against **1.0.28121**, the build where all of this is
finished. Do not install it on another version: the menu DataAssets come from 27953 and would
overwrite whatever that build ships.

## Uninstall

Delete the three `UE_YGRO-Windows_P.*` files and the `FESkinMenu` folder. No game file is
overwritten — the patch is a separate container mounted on top. Set the skins back to *Default*
first: the selected value is saved, and a saved value with no matching menu entry is untested.
