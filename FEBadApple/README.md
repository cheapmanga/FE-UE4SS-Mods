# FE Bad Apple — Bad Apple!! rendered BY Fading Echo

UE4SS **Lua** mod for Fading Echo (`UE_YGRO`). Replays the Bad Apple!! video
**using the game's own objects**: a wall of cubes that the engine draws itself, frame
by frame, at 30 fps. Not a video slapped onto the screen — the game *builds* each
frame.

> Demo: the video plays smoothly in-game, with no trailing and no freezing.

---

## Installation

Copy the folder (without the `ue4ss-` prefix) into:

```
<game>\UE_YGRO\Binaries\Win64\ue4ss\Mods\FEBadApple\
├── enabled.txt
└── Scripts\
    ├── main.lua
    └── data\            ← the 8 files, ~1.4 MB, MANDATORY
```

⚠️ **Copy the file itself** (drag-and-drop / USB stick), don't paste its
contents into an editor: that reflows the long lines and breaks the script
(`main.lua:1: unexpected symbol`). When in doubt, check the **size** of
`main.lua` after copying.

`badapple_audio.mp4` (at the root of the folder) is the soundtrack, to be played
separately (VLC…) — it doesn't need to be inside the game.

---

## Quick start

Game console (**² / F10** key), in a **clear** area, looking out into empty space
(fly up with `FEMoonJump` if needed — the screen lands wherever you're looking):

```
badapple test        ← FIRST: spawn a single cube + diagnostic
badapple play ism    ← starts playback (recommended mode, zero trailing)
```

Start `badapple_audio.mp4` in VLC at the same moment for the sound (both run
off the wall clock → they stay in sync for the full 3 min 39).

`badapple stop` destroys everything and restores the game's settings.

---

## The three rendering modes

| Command | Rendering | When |
|---|---|---|
| **`play ism`** | **A single `InstancedStaticMeshComponent`**, one instance per rectangle | **Recommended default.** Zero trailing (instances don't write a motion vector), a single draw call → lightweight. |
| `play` | 160 reused `StaticMeshActor`s, moved each frame | Fallback. Works, but the teleporting cubes leave trails under the game's TSR. |
| `play enemies` | level **enemies** as pixels, 16×12 grid | Gag. Grabs a loaded enemy's class; it chugs, that's the whole point. |

Each frame of the video is pre-sliced into **rectangles** (RLE), ~44 on average,
148 at worst, where a 64×48 grid would be 3072 cells. One rectangle = one stretched
cube.

---

## Commands

```
badapple test              spawn ONE cube in front of you + re-read everything that works
badapple probe             full diagnostic (cube 4 m in front of the CAMERA)
badapple play [ism|enemies] start playback (no argument = actor-cubes mode)
badapple pause / resume    freeze / resume
badapple stop              stop, destroy everything, restore the game's settings
badapple frame <n>         show a still frame (framing test)
badapple info              current state (mode, frame, settings)
badapple stat              render diagnostic (visible/parked/ghost cubes)
```

The log writes a `battement : image N/6584` every ~3 s: as long as it keeps
scrolling, playback is running.

---

## Settings — `badapple set <key> <value>`

### Placement and size

| Key | Default | Effect |
|---|---|---|
| `dist` | 5000 | distance of the screen in front of you (uu) |
| `height` | 1800 | height of the screen's center (uu) |
| `cell` | 100 | cell size (uu). The screen is 64×`cell` wide — **lower it to see everything** |
| `thickness` | 0.15 | cube thickness |
| `overlap` | 0.06 | cube overlap (closes the black gaps between rows) |
| `pool` | 160 | number of cubes/instances (≥ 148) |

Example for a more compact wall: `set cell 50`, `set dist 2500`, `set height 1200`.

### The background

| Command | Effect |
|---|---|
| `set bg black` | engine black background (default). May appear **dark red** depending on the game's post-processing — stays contrasted |
| `set bg blackgame` | game black (`MI_Unlit_black`), try it if the engine black is tinted |
| `set bg none` | no background (white cells against the sky) |
| `set bgpad 1.5` | background margin around the image, in cells |

### Pixel color

| Command | Effect |
|---|---|
| `set mat unlit` | unlit material (default, the cheapest) |
| `set mat alienware` | **dark** material from the ALIENWARE chest (⚠️ inverts the image: cubes = light areas) |
| `set mat <path>` | any loaded material |

> Engine materials (`GizmoMaterial`, `MM_UNlit`) expose **no** color
> parameter → no way to tint them dynamically, hence the choice among
> already-colored materials.

### Miscellaneous

- `set class chest`: pixels = real ALIENWARE chests, stretched (`set class chestbig` for the big ones).
- `set mesh <path>`: force a mesh other than the cube.
- `set loop 0`: don't loop back at the end.
- `set resync 20`: rate of the anti-ghost sweep (actor mode only).
- `set enemycell 250`: spacing between enemies (enemies mode).

---

## Graphics effects (trailing)

At launch, `play` disables **motion blur** (harmless). The rest is manual:

```
badapple gfx on|off        clean effects (motion blur off) / game default
badapple ghost [w]         reduces the TSR temporal history (w ~0.8)
badapple aa <0|1|2|4>      anti-aliasing (4 = default; ⚠️ 0/1 BREAK the TSR → low-res image)
```

In practice: **the `ism` mode removes trailing at the source**, these commands
are only useful for actor mode.

---

## Bonus — hijacking the game's video player (route 2)

Nothing to do with cube rendering: plays any file on the game's
media players (main-menu background, cutscenes).

```
badapple video [path]      open the file on the loaded UMediaPlayers
badapple video stop        restore the original videos
```

The default path is `C:/BadApple/badapple.mp4` (`set video <path>` to
change it). Cutscene audio goes through Wwise → the sound may be muted, play
the music separately.

---

## Regenerating the data (different video / different resolution)

The data is produced by `antoine/badapple/make_badapple_data.py` (ffmpeg
required):

```bash
./make_badapple_data.py ma_video.mp4 --grid 64x48 --low 16x12
```

- `--grid 48x36` (or `40x30`): coarser but lighter if it chugs.
- `--invert`: lights up the **dark** areas (to pair with `set mat alienware`).
- `--audio`: re-extracts the soundtrack alongside the mod.

Output: `Scripts/data/badapple_*.lua` + `badapple_meta.lua`. The full README for the
three "routes" (file replacement, Lua mod, engine rendering) is in
`antoine/badapple/README.md`.

---

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| The test pattern stays **frozen** at launch | UE4SS's EngineTick hook dropped → **restart the game**. |
| `main.lua:1: unexpected symbol` | Corrupted copy (contents pasted into an editor) → re-copy the **file**. |
| I see **nothing** | Too far/high: `set dist 1500`, `set height 300`, then `badapple test`. |
| **Huge** screen, I see a corner | Step back, or `set cell 50`. |
| It **chugs** | `play ism` (the lightest), or regenerate with `--grid 40x30`. |
| **Leftover cubes** (actor mode) | Switch to `play ism`: zero ghosting by construction. |
| **Red** background instead of black | Game post-processing: `set bg blackgame`, or leave it (stays readable). |

---

## How it works (technical summary)

- **Data**: video binarized to 64×48, each frame as RLE rectangles + vertical
  merge, encoded in safe base64. Verified pixel-perfect against the real video.
- **ISM rendering**: `AddComponentByClass` creates a `UInstancedStaticMeshComponent`;
  `UpdateInstanceTransform` in **delta** (only the instances that change). The
  instances of an ISM don't write a motion vector → the TSR can't
  smear them → **no trailing**.
- **Timing**: a persistent `LoopAsync` that calls `ExecuteInGameThread` with a
  **stable** function (never recreated), otherwise the GC frees it and the loop dies at
  a random moment.
- **Anti-crash**: cubes taken out of navigation/collision (otherwise a rebuild of
  the Recast mesh on a worker → crash), out of shadows/GI/distance fields/Nanite.
- The engine cube `/Engine/BasicShapes/Cube` (100 uu, centered) is cooked into the pak.

Details and a log of the pitfalls in the project memory (`fe-badapple`,
`ue4ss-lua-tick-loop`).
