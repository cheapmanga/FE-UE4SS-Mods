# UE4SS Installation for Fading Echo

Here is the step-by-step guide to installing **UE4SS** and the necessary signatures for Fading Echo.

## Important Warning (Known Steam Folder Issue)
The full game on Steam installs by default in a folder containing a hidden special character (`Project Ygrό`). The last character is not a regular 'o', but a Greek omicron with tonos (U+03CC). This causes UE4SS to crash on startup. If you encounter an error when launching, **refer to Step 3** and the provided troubleshooting guide.

---

## Step 1: Download and Extract UE4SS

1. Download the experimental version of UE4SS:
   **[zDEV-UE4SS_v3.0.1-1015-g4b96f82b.zip](https://github.com/UE4SS-RE/RE-UE4SS/releases/download/experimental-latest/zDEV-UE4SS_v3.0.1-1015-g4b96f82b.zip)**

2. Navigate to the game's installation directory, then open the `Win64` folder:
   `...\steamapps\common\[Game Folder Name]\UE_YGRO\Binaries\Win64\`

3. **Extract** the entire contents of the `.zip` archive directly into this `Win64` folder. (You should end up with a `ue4ss` folder and the `xinput1_3.dll` file in the same location as the game's executable).

---

## Step 2: Add the Custom Signature

For the game engine to be correctly analyzed, a custom signature is required.

1. Download the signature file (Download raw file):
   **[StaticConstructObject.lua](https://downgit.github.io/#/home?url=https://github.com/cheapmanga/FE-UE4SS-Mods/blob/main/UE4SS_Signatures/StaticConstructObject.lua)**

2. Move this `.lua` file into the UE4SS signatures folder:
   `...\Binaries\Win64\ue4ss\signatures\`

---

## Step 3: Troubleshooting (UE4SS Crash on Startup)

If the game launches but the UE4SS console crashes with the error `Fatal Error: No mapping for the Unicode character exists in the target multi-byte code page`, this is the known folder name issue.

**Read and follow the complete repair guide here:** 
**[DEPANNAGE_UE4SS_Fading_Echo.pdf](https://github.com/cheapmanga/FE-UE4SS-Mods/blob/main/UE4SS-installation/Ue4ss%20fading%20echo%20troubleshooting.md)**

*(The "Solution A" in the PDF will explain how to safely rename the folder and modify the Steam `appmanifest_2467880.acf` file while Steam is completely closed).*
