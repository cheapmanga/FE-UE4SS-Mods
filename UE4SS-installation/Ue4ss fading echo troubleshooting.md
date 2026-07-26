# TROUBLESHOOTING GUIDE
## Getting UE4SS to Run on Fading Echo

The full game crashes on launch with "No mapping for the Unicode character exists in the target multi-byte code page," while the demo works fine with the exact same installation.

- **Game:** Fading Echo (AppID 2467880)
- **UE4SS:** v3.0.1 Beta — zDEV build 1012-gc838a8ac
- **Cause:** Greek character ό (U+03CC) in the installation path
- **Duration:** ~10 minutes
- **Established:** July 19, 2026

---

## THE PROBLEM IN ONE PAGE

### Background

UE4SS installs and starts up. It finds the engine, scans the executable, everything looks fine — then it dies abruptly right after "PS scan successful," at the point where it initializes the Lua part:

```
[PS] Found GameEngineTick: 0x7ff7d4a67e60
PS scan successful
Running first pass of Lua override scans
Lua Scan attempt 1 (Phase 2)
Fatal Error: No mapping for the Unicode character exists
 in the target multi-byte code page.
```

### Why

Steam installs the full game into a folder named "Project Ygrό." The last character isn't an ordinary "o," nor even an accented Latin "ó" — it's a GREEK omicron with tonos, U+03CC. To the naked eye, in Windows Explorer, it's undetectable.

Now, Windows here is running under code page 850 (Western Europe). This character table contains no Greek characters. When UE4SS converts its own installation path into "multi-byte" text to initialize Lua, the conversion fails — and UE4SS treats that failure as a fatal error.

### Why the demo works

The demo is installed in "Fading Echo Demo" — ASCII characters only. No conversion can fail, so UE4SS sails past that point without a hitch. The UE4SS installation is rigorously identical on both sides: it's neither the UE4SS version, nor the mods, nor the config. Only the folder name.

### What's ruled out

Verified by comparing the two installations, to avoid going down these paths again:

- **UE4SS version** — identical (v3.0.1, build 1012-gc838a8ac) on both the demo and the full game.
- **Mods** — the crash happens before any Lua mod loading.
- **Config files** — UE4SS-settings.ini isn't even the culprit; it's read successfully.
- **The game itself** — it launches perfectly fine without UE4SS.

---

## DIAGNOSIS

### Confirming this is indeed the issue

Three checks, two minutes. Do this before attempting any fix: if any one of them doesn't match, the problem lies elsewhere and the rest of this guide won't help.

**1. The exact error message**

Open UE4SS.log in the game's ue4ss folder. The last line should be "Fatal Error: No mapping for the Unicode character...," right after "Lua Scan attempt 1." If the crash occurs elsewhere (during the PS scan, or after mods have loaded), it's a different problem.

**2. The installation path**

In that same log, look at the "root directory" line. If you see "Project Ygrό" with a strange-looking character, that confirms it. In the game's black console window, that character displays as a "?" — that's precisely the symptom.

**3. Windows' code page**

Open a command prompt (Windows key, type cmd, Enter) and type:

```
chcp
```

If the answer is 850, 1252, or anything other than 65001, the Greek character genuinely cannot be represented. That's the case here: code page 850.

### Diagnosis summary

Path containing ό (U+03CC) + non-UTF-8 code page = guaranteed crash at the Lua Scan. Both conditions are required — that's why the fix can act on either ONE OR the other.

---

## SOLUTION A — RECOMMENDED

### Renaming the installation folder

We remove the Greek character from the path. This is the preferred solution: it's local, reversible, and doesn't touch any system settings — which matters especially if it's not your own PC.

### The pitfall that breaks this fix

Steam keeps the contents of its config files in memory and REWRITES them when it closes. If you edit appmanifest_2467880.acf while a Steam process is still running, your change will be silently overwritten with no error message — and the Greek folder name will come back. This is the classic mistake, and the only real difficulty in this procedure.

### Procedure

**1. Fully kill Steam**

Quit Steam via Steam > Exit (not just the red X, which minimizes it to the notification area). Then open Task Manager (Ctrl+Shift+Esc), Details tab, and make sure NONE of these processes remain — end any that linger:
- steam.exe
- steamwebhelper.exe (there are often several)
- steamservice.exe
- GameOverlayUI.exe

**2. Back up the manifest**

Go to `E:\SteamLibrary\steamapps\` (one level ABOVE the common folder). Copy-paste `appmanifest_2467880.acf` into the same folder to keep a backup copy. If anything goes wrong, restore this file to return to the original state.

**3. Rename the game folder**

In `E:\SteamLibrary\steamapps\common\`, rename "Project Ygrό" to "Project Ygro."

*Retype the entire name*
Don't just fix the last letter: select the whole name and retype it by hand, character by character. Otherwise you risk keeping the Greek ό without realizing it — it looks like a perfectly ordinary "o" on screen.

**4. Edit the manifest**

Open `appmanifest_2467880.acf` with Notepad (right-click > Open with > Notepad). Find the installdir line:

- Before: `"installdir" "Project Ygrό"`
- After: `"installdir" "Project Ygro"`

**5. SAVE — for real**

Ctrl+S, then close Notepad. Immediately reopen the file and reread the installdir line to confirm the change actually took. This check takes three seconds and saves you from thinking the fix was applied when it wasn't.

**6. Relaunch Steam and verify**

Steam should show Fading Echo as installed, without offering a download. If so, launch the game: UE4SS should now get past the Lua Scan and load the mods.

### If Steam puts the Greek name back

Reopen the .acf file after relaunching Steam. If the installdir line has reverted to "Project Ygrό," a Steam process was still running during step 4 — start over and be thorough with step 1.

If the problem persists even with Steam fully shut down, move on to Solution B.

### After a game update

A major update could theoretically recreate the folder with its original name. If the crash reappears someday for no apparent reason, start by checking the folder name: that's probably it, and the fix is the one on this page.

---

## SOLUTION B — FALLBACK

### Switching Windows to UTF-8

Instead of removing the Greek character from the path, we make Windows able to represent it. This is drastic and permanent: it fixes the problem regardless of whatever name Steam gives the folder in the future.

### Only use this if Solution A has failed

This is a GLOBAL system setting, requiring administrator rights and a restart. Some poorly written old software assumes an ANSI code page and may start displaying garbled characters. On a PC that isn't yours, get the owner's consent and note carefully which box was checked so you can revert it.

### Procedure

**1. Open Regional Settings**

Windows key, type "Region," open Control Panel > Region.

**2. Administrative tab**

Click "Change system locale…" Windows will ask for administrator rights.

**3. Check the UTF-8 box**

Check "Beta: Use Unicode UTF-8 for worldwide language support."

**4. Restart**

Confirm with OK and restart the PC — the change only takes effect after a restart.

**5. Verify**

Reopen a command prompt and type `chcp`: the answer should now be 65001. Launch the game; UE4SS should get past the Lua Scan.

### To undo

Same path, uncheck the box, restart. The system reverts to code page 850.

---

## APPENDICES

### Solution C — taking the game out of Steam

Last resort, if the two previous solutions are impossible. Run a copy of the game from a clean path, outside the Steam folder tree. Cost: the game's disk size, doubled.

**1. Copy the game**

Copy the entire "Project Ygrό" folder to a path with no special characters at all, for example `E:\Games\ProjectYgro`.

**2. Declare the AppID**

In `E:\Games\ProjectYgro\UE_YGRO\Binaries\Win64\`, create a text file named `steam_appid.txt` containing only:

```
2467880
```

**3. Launch directly**

With Steam open in the background, launch `UE_YGRO_Steam-Win64-Shipping.exe` directly from Explorer — not from the Steam library. The steam_appid.txt lets the game authenticate normally with the Steam client.

*A rather pleasant side effect*
The original Steam installation stays intact and updates normally, while you mod the copy freely. For reverse engineering or mod development, this separation is often convenient.

### Verifying the fix worked

Open UE4SS.log and look for the following line — it's the marker of success, the one that was missing from the full game's log:

```
StaticConstructObject_Internal address: 0x... <- Lua Script
```

If it's there, the Lua Scan passed and UE4SS is fully functional.

### If a problem remains after the fix

Once the path is fixed, any new crash is necessarily of a different nature — the Mods folder contains about twenty mods, and one of them could be causing an issue independently. Method: clear mods.txt (or set all entries to 0), verify the game launches, then re-enable mods in small batches until you identify the culprit.

### Hiding UE4SS windows

By default, UE4SS opens one or more console windows in addition to the game's. Useful for diagnostics, cluttered for playing or recording video. To have only the game window on screen:

**1. Open the config**

Edit `UE4SS-settings.ini`, at the root of the ue4ss folder (the same one that contains UE4SS.log and the Mods folder).

**2. Find the [Debug] section**

It groups everything related to consoles and the debug interface.

**3. Set everything to 0**

Every setting in this section that's set to 1 should be changed to 0. The exact names vary by UE4SS version, but the principle stays the same: in [Debug], no more 1s. On v3.0.1, it looks like this:

```
[Debug]
SimpleConsoleEnabled = 0
DebugConsoleEnabled = 0
DebugConsoleVisible = 0
```

**4. Relaunch the game**

No more stray windows. UE4SS and the mods keep running normally.

*The log keeps being written*
Hiding the consoles doesn't disable UE4SS or logging: UE4SS.log keeps being updated normally. So you can play without a stray window and reread the log afterward if something goes wrong. To live-diagnose something again, just set these settings back to 1.

### A mod that "doesn't work": check your keyboard

Before suspecting a mod, check that the keypress is actually reaching the game. Many keyboards — especially on laptops and compact models — have a row of F-keys set to media mode by default: pressing F6 sends "previous track" instead of F6, unless you hold Fn.

The symptom is misleading, because the mod loads correctly and other keys work. In the log, you'll see the mod's loading line, but absolutely nothing happens when you press the key.

- Test while holding Fn together with the F key. If that works, it's confirmed.
- Swap the default behavior: often Fn+Esc or Fn+CapsLock, otherwise in the BIOS ("Action Keys Mode," "Function Key Behavior," "Hotkey Mode" depending on the brand).
- On laptop keyboards, some F-keys are also intercepted by the manufacturer before they even reach Windows.

**The instinct to have**

If the log shows the mod loaded but absolutely nothing when you press its key, it's probably not the mod: the keypress simply never arrives. Test with Fn before diving into debugging.

### Quick reference

| Item | Value |
|---|---|
| Fading Echo AppID | 2467880 |
| Steam manifest | `E:\SteamLibrary\steamapps\appmanifest_2467880.acf` |
| Game folder | `E:\SteamLibrary\steamapps\common\Project Ygrό` |
| UE4SS folder | `...\Project Ygrό\UE_YGRO\Binaries\Win64\ue4ss\` |
| UE4SS log | `...\Binaries\Win64\ue4ss\UE4SS.log` |
| UE4SS version | v3.0.1 Beta — zDEV-UE4SS_v3.0.1-1012-gc838a8ac |
| Demo path | `E:\SteamLibrary\steamapps\common\Fading Echo Demo` |
| Culprit character | ό — Greek omicron with tonos, U+03CC, UTF-8 CF 8C |

### One-sentence takeaway

If UE4SS dies on "No mapping for the Unicode character," check the game's path in UE4SS.log before anything else — and be wary of letters that look like normal letters.
