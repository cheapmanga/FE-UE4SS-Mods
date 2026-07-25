# FE Volume — see invisible walls, triggers & collision volumes

**This is not a Lua mod.** It's an `Engine.ini` that turns on Unreal Engine's
built-in **debug-draw / debug view modes**, which complement the console and debug
tooling that already ship with **[UE4SS](https://github.com/UE4SS-RE/RE-UE4SS)**.
Once it's in place you can visualize the collision geometry the game normally hides:
invisible walls, trigger volumes, blocking volumes, scene queries, etc. — ideal for
route planning and glitch hunting.

There is nothing to compile and no `main.lua`: the whole "mod" is the single
`Engine.ini` file, plus (optionally) UE4SS installed so you have the in-game console.

## What it enables

The `Engine.ini` here flips on, among other things:

- `r.ForceDebugViewModes` / `r.AllowDebugViewmodes` / `r.VisualizeEnabled` — unlock the debug view modes
- `p.EnableDebugDraw` / `p.DrawDebugHelpers` — draw collision & physics helpers
- `r.DebugDrawAllSceneQueries` / `r.VisualizeOccludedPrimitives` — show queries and occluded geometry
- `bEnableOnScreenDebugMessages` + verbose `[Core.Log]` — on-screen debug text and detailed logs

## Where it goes

Copy `Engine.ini` into your **per-user** Fading Echo config folder:

```
C:\Users\<YOUR_USER>\AppData\Local\UE_YGRO\Saved\Config\Windows\Engine.ini
```

(You can paste `%LOCALAPPDATA%\UE_YGRO\Saved\Config\Windows` into the Explorer
address bar to jump straight there. The folder only exists **after** the game has
been launched at least once.)

## ⚠️ Steam wipes it on every launch — read this

Fading Echo / Steam **regenerates this `Engine.ini` on each launch**, so your copy
gets erased and you have to put it back **every single time** before you play.

To make that painless, keep a small backup tree next to the game so re-applying is
one double-click:

```
FadingEcho-Debug\
├─ Engine.ini                 <- the file from this folder (your master copy)
└─ apply-engine-ini.bat       <- double-click to copy it into place
```

Recommended routine each session:

1. **Launch the game once** (this recreates the config folder and its default `Engine.ini`).
2. Alt-tab out, **run `apply-engine-ini.bat`** (or copy `Engine.ini` in by hand).
3. Alt-tab back in — the debug draw is now active. Open the UE4SS console with the
   **²** key if you want to toggle individual `r.` / `p.` cvars live.

> 💡 Optional time-saver: after copying `Engine.ini`, set it to **read-only**
> (right-click → Properties → Read-only). On some builds that stops the game from
> overwriting it, so you can skip the re-copy. It doesn't work on every build — if
> the debug draw stops showing, the file was wiped anyway and you're back to the
> copy-each-launch routine above.

## apply-engine-ini.bat

The bundled `apply-engine-ini.bat` copies the `Engine.ini` sitting next to it into
`%LOCALAPPDATA%\UE_YGRO\Saved\Config\Windows`. Keep the two files together and run
the `.bat` after each launch.

## Notes

- This only changes **your local** debug/render config; it doesn't touch game files
  and is trivially reverted (delete the file, or just relaunch — Steam resets it).
- Verbose logging makes `UE4SS.log` and the UE logs much larger; harmless, but expect
  bigger log files while it's active.
- If you see no debug geometry, confirm the file really landed at the path above and
  wasn't wiped by a relaunch.
