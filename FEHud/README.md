# FE Hud — show / hide the HUD

Standalone UE4SS **Lua** mod for Fading Echo (`UE_YGRO`). Works on both the full game (Project Ygro) and the Fading Echo Demo.

A one-command mod that toggles the game's HUD off and back on — handy for clean
screenshots, video capture, or simply seeing the level without the interface in
the way.

**Download:** [⬇ FEHud.zip](https://raw.githubusercontent.com/cheapmanga/FE-UE4SS-Mods/main/dist/FEHud.zip)

## Installation

Copy the folder into:

```
<game>\UE_YGRO\Binaries\Win64\ue4ss\Mods\
```

(i.e. `FEHud\enabled.txt` + `FEHud\Scripts\main.lua`)

## Console command (² key)

Open the in-game console with the **²** key, then:

| Command | Effect |
|---|---|
| `hud` | Show / hide the HUD (toggle). Run it again to bring the HUD back. |

Detailed output goes to the **UE4SS console window**, not the in-game console.

## How it works

The game ships a `YgroCheatManager` with a `Toggle HUD` function. The mod:

1. Resolves the `PlayerController`, filtering out Class Default Objects
   (names containing `Default__`) so only the live object is used.
2. Fetches `PlayerController.CheatManager`; if there is none, it calls
   `EnableCheats()` and looks the manager up again (falling back to
   `FindAllOf("YgroCheatManager_C")`).
3. Calls the `Toggle HUD` UFUNCTION.

Two UE4SS specifics are worth knowing, both handled here:

- **The function name contains a space** (`Toggle HUD`), so it is called with
  bracket syntax: `cm[fname](cm)`.
- **Never test `type(cm[fname]) == "function"`** — UE4SS exposes UFUNCTIONs as a
  *callable userdata*, not a Lua function, so that test would wrongly reject the
  call. The mod calls directly and lets `pcall` report the real failure.

## Notes

- The console `FOutputDevice` (`Ar`) is only valid inside the **synchronous** body
  of the command handler. Using it from `ExecuteInGameThread` is a dead pointer and
  crashes with `EXCEPTION_ACCESS_VIOLATION` — that's why the mod prints through
  `say()` while synchronous and `log()` once deferred.
- The toggle goes through the game's own cheat manager, so it affects the HUD
  exactly as the built-in debug option would.
