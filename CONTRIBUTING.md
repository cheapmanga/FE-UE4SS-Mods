# Contributing

Thanks for wanting to help! This repo collects **UE4SS Lua mods** for
**Fading Echo** (`UE_YGRO` / Project Ygro). Everything here is pure Lua — there is
nothing to compile, so contributing is mostly writing a script and a README.

Not sure where to start? Open an issue, or come talk on Discord: **cheapmanga_89714**.

## Before you start

- Install UE4SS by following the
  [Install process](UE4SS-installation/Install%20process.md).
- If something misbehaves, check the
  [troubleshooting guide](UE4SS-installation/Ue4ss%20fading%20echo%20troubleshooting.md)
  first — most install problems are already covered there.
- Test on the build you're targeting. Say in your PR whether you tested on the
  **full game**, the **demo**, or both.

## Repository layout

Every mod is a self-contained folder at the repo root, named `FE<Something>`:

```
FEMyMod/
├─ enabled.txt          <- empty file; UE4SS uses it to enable the mod
├─ README.md            <- what it does, commands, how it works
└─ Scripts/
   └─ main.lua          <- the mod itself
```

The matching `dist/FEMyMod.zip` is the download users actually grab. Build it
**from the repo root** so the archive contains the folder, not its contents:

```bash
zip -r dist/FEMyMod.zip FEMyMod
```

## Adding a mod

1. Create the `FEMyMod/` folder with the layout above.
2. Write `README.md` following the pattern of the existing ones:
   title line, one-paragraph summary, **Download** link, *Installation*,
   *Console commands* (or *Controls*) as a table, *How it works*, *Notes*.
3. Build `dist/FEMyMod.zip`.
4. Add a row to the table in [`README.md`](README.md), keeping it alphabetical.
5. Open a pull request.

## Code style

- **English only** — comments, README, and (for new mods) console output.
- Wrap every engine call in `pcall`. A mod that throws can get its hook removed
  by UE4SS, which stops **all** Lua mods, not just yours.
- Do all game-state reads and writes inside `ExecuteInGameThread`.
- Filter out Class Default Objects (names containing `Default__`) when you
  enumerate actors — the CDO is a template, not the live object.
- Prefer calling gameplay UFUNCTIONs over writing stats. Touching
  `UStatisticSubsystem` has a known crash path; the giver mods document how they
  work around it.
- Don't test `type(obj[fn]) == "function"` on a UFUNCTION — UE4SS exposes them as
  a *callable userdata*, so that check wrongly rejects valid calls. Call it and
  let `pcall` report the real error.

### The `Ar` trap

The console `FOutputDevice` (`Ar`) is valid **only inside the synchronous body**
of a command handler. Using it from deferred code (`ExecuteInGameThread`,
`ExecuteWithDelay`, a loop) is a dead pointer and crashes the game with
`EXCEPTION_ACCESS_VIOLATION`. Print with `Ar` while synchronous, and switch to
`print`/`log` once you're deferred. This has bitten more than one mod here.

### Per-frame work

Don't register a fresh closure every tick. UE4SS may garbage-collect it before it
runs, which kills the hook with
`[Lua::Registry::get_function_ref] Ref was not function` — and takes every Lua mod
down with it, at an unpredictable moment. Define **one stable function** and pass
that same reference each time (see `FEBadApple` and `FEMoonJump`).

## Pull requests

Keep a PR to one mod or one fix. In the description, say what you changed, which
build you tested on, and what you actually observed in game — "the call returned
without error" is not proof that it worked.

If you change a mod's `Scripts/`, rebuild its `dist/` zip in the same PR so the
download stays in sync.

## Reporting a bug

Open an issue with:

- the mod name and what you expected vs. what happened,
- your game build (full game or demo) and UE4SS version,
- the relevant lines from `<game>\UE_YGRO\Binaries\Win64\UE4SS.log`.

## Scope

These are debug / speedrun / sandbox tools for a **single-player** game. The game
itself is never included in this repo — no game assets, no binaries, no paks.
