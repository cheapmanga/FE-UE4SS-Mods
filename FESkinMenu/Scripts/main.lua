-- ============================================================================
--  FADING ECHO — SKIN MENU
--
--  Puts One's hidden skins (Skin2/3/4) into the REAL options menu, and probes
--  whether the game's own skin delegates accept those values at all.
--
--  Commands (game console = the ² key, or the UE4SS console):
--     skinmenu               status + command reminder
--     skinmenu dump          prints the skin DataAssets as they are right now
--     skinmenu test <0-4>    calls the game's own OnSkinChanged on the player
--     skinmenu testbob <0-1> calls the game's own SetSkin on the Bob actors
--     skinmenu remap <a> <b> makes the 2 menu slots drive the skins you pick
--     skinmenu revert        puts the original values back in the slots
--     skinmenu install force grows the spinner to 5 entries (may crash, see below)
--     skinmenu bob           tries to add Bob's spinner row (known to be inert)
--
--  Detailed output: UE4SS CONSOLE WINDOW.
--
--  ---------------------------------------------------------------------------
--  WHAT THIS MOD IS FOR (build 1.0.27953, checked against the extracts)
--
--  The game ships five complete material sets for One. BP_CoreYgroCharacter
--  itself carries five populated TMap<int32, MaterialInstance> named
--  Skin0..Skin4 (slot -> material). The menu only ever offered two of them:
--      DA_Skin_One_Spinner.SpinnerOptions = [ DataValue "0", DataValue "1" ]
--
--  Selecting a spinner value fires USpinnerOptionDescriptorBase::OnExecute,
--  a SpinnerDelegate(FName SpinnerValue). One binds BP_CoreYgroCharacter::
--  OnSkinChanged(FName SpinnerValue) to it, Bob binds BP_Bob_Critter::
--  SetSkin(FName Index). So the value that travels is the DataValue STRING
--  ("0".."4"), not an index.
--
--  ---------------------------------------------------------------------------
--  WHY THIS IS NOT THE ATTEMPT THAT ALREADY FAILED
--
--  What is dead (do not retry): adding a NEW DESCRIPTOR (a new row) to
--  DA_Skin_SubSection.OptionDescriptors. That list is turned into widgets in
--  C++ when the options screen is created and nothing rebuilds it. That is the
--  only way to get Bob his own line, and it cannot be done from Lua.
--  'skinmenu bob' keeps the attempt for the record; it changes nothing.
--
--  What is NOT dead: adding VALUES INSIDE an existing spinner.
--  USpinnerOptionDescriptor exposes SetSpinnerOptions(TArray<FSpinnerParameters>)
--  plus an IsSpinnerOptionsRuntimeEditable flag, and the game uses that path
--  itself: DA_OptionSpinner_Resolution ships IsSpinnerOptionsRuntimeEditable
--  = true and has its list rebuilt at runtime by BP_OptionFunctionLibrary::
--  InitResolutionData. A spinner's values are read when the widget updates,
--  not frozen at screen creation. That is the door this mod uses.
--
--  ---------------------------------------------------------------------------
--  SETTLED IN GAME (10/08/2026)
--
--  Blueprint function bodies are bytecode: neither the JSON extract nor
--  FModel's "decompiled blueprints" show what OnSkinChanged does with its
--  argument, so it had to be tested. 'skinmenu test 2'..'test 4' all change
--  One's appearance => the delegate is GENERIC, it is not limited to "0"/"1",
--  and a menu entry carrying DataValue "2".."4" is a real button.
--
--  ---------------------------------------------------------------------------
--  UE4SS PITFALLS ALREADY PAID FOR — DO NOT REPEAT THEM
--   1. `Ar` is valid ONLY inside the SYNCHRONOUS body of the handler (else AV 0x8).
--   2. Never pass a raw Lua string where an FName is expected (AV 0x70):
--      every delegate value goes through FName(...).
--   3. `o:IsValid()` crashes if `o` is not a UObject: everything goes through okObj.
--   4. Game state is only ever touched from ExecuteInGameThread.
--   5. NEVER hand a Lua table to a UFUNCTION expecting a TArray of STRUCTS.
--      UE4SS walks the table in push_arrayproperty and dies on an access
--      violation, which pcall CANNOT catch: the game hard-crashes.
--      Paid for on 10/08/2026 with desc:SetSpinnerOptions(luaTable).
-- ============================================================================

-- ============================================================================
--  STARTUP APPLICATION
--  BOOT_REMAP holds the skin values the two menu slots should drive, applied
--  as soon as the game is up, without typing a command. Leave it empty to do
--  nothing. The change must land BEFORE the options screen is created, hence
--  the delay.
--      { 2, 3 }  -> the menu's two positions become Skin2 and Skin3
--      { }       -> the mod stays idle until you use the console
-- ============================================================================
local BOOT_REMAP    = {}        -- e.g. { 2, 3 }
local BOOT_DELAY_MS = 6000      -- delay before the automatic remap

local BASE_OPT    = "/Game/Game/Option/DataAssets/Gameplay/Skin/"
local ONE_SPINNER = BASE_OPT .. "DA_Skin_One_Spinner"
local BOB_SPINNER = BASE_OPT .. "DA_Skin_Bob_Spinner"
local SUBSECTION  = BASE_OPT .. "DA_Skin_SubSection"

local HIGHEST_SKIN = 4          -- Skin0..Skin4 exist; the menu shipped 0 and 1

-- Labels for the entries this mod adds. The game has no string-table key for
-- skins 2/3/4 (they never had a menu entry), so these are plain strings.
-- Rename them freely.
local SKIN_LABELS = {
    [0] = "Default",
    [1] = "Hellgur One",
    [2] = "Skin 2",
    [3] = "Skin 3",
    [4] = "Skin 4",
}

-- ---------------------------------------------------------------------------
--  Logging
-- ---------------------------------------------------------------------------
local function log(m) print("[FESkinMenu] " .. tostring(m) .. "\n") end
local function say(Ar, m)               -- SYNCHRONOUS handler body ONLY
    log(m)
    if Ar then pcall(function() Ar:Log("[FESkinMenu] " .. tostring(m)) end) end
end

-- ---------------------------------------------------------------------------
--  Object helpers (same guards as FESkins — see pitfall 3)
-- ---------------------------------------------------------------------------
local function okObj(o)
    if not o then return false end
    local v = false
    pcall(function() v = o:IsValid() end)
    return v
end

local function isRealObject(o)
    if not okObj(o) then return false end
    local fn = ""
    pcall(function() fn = o:GetFullName() end)
    return not string.find(fn, "Default__", 1, true)
end

local function Name(o)
    if not okObj(o) then return "(nil)" end
    local n = "?"
    pcall(function() n = o:GetFullName() end)
    return n
end

local function ShortName(o)
    local n = Name(o)
    return string.match(n, "([^%.%s/]+)$") or n
end

-- DataAssets referenced by the options menu are loaded with the menu, but not
-- necessarily before it has been opened once: insist, like FESkins does.
local function Resolve(path)
    local short = string.match(path, "([^/]+)$")
    local full = path .. "." .. short
    local obj = StaticFindObject(full)
    if okObj(obj) then return obj end
    for _ = 1, 3 do
        pcall(function() LoadAsset(path) end)
        obj = StaticFindObject(full)
        if okObj(obj) then return obj end
        pcall(function() LoadAsset(full) end)
        obj = StaticFindObject(full)
        if okObj(obj) then return obj end
    end
    return nil
end

local function GetPawn()
    local cs = FindAllOf("PlayerController")
    if cs then
        for _, c in pairs(cs) do
            if isRealObject(c) then
                local pk
                pcall(function() pk = c.Pawn end)
                if isRealObject(pk) then return pk end
            end
        end
    end
    local list = FindAllOf("BP_CoreYgroCharacter_C")
    if list then
        for _, a in pairs(list) do if isRealObject(a) then return a end end
    end
    return nil
end

-- ⚠️ DEDUPLICATION MANDATORY: _Lava_C and _Waste_C INHERIT from BP_Bob_Critter_C,
-- so FindAllOf on the parent also returns the children (FESkins paid for this).
local BOB_CLASSES = { "BP_Bob_Critter_C", "BP_Bob_Critter_Lava_C", "BP_Bob_Critter_Waste_C" }

local function GetBobActors()
    local out, seen = {}, {}
    for _, cls in ipairs(BOB_CLASSES) do
        local ok, list = pcall(function() return FindAllOf(cls) end)
        if ok and list then
            for _, a in pairs(list) do
                if isRealObject(a) then
                    local k = Name(a)
                    if not seen[k] then seen[k] = true; out[#out + 1] = a end
                end
            end
        end
    end
    return out
end

-- ---------------------------------------------------------------------------
--  Reading a spinner descriptor
-- ---------------------------------------------------------------------------
-- Returns entries (1-based array of {dataValue, label, text, raw}), the TArray
-- itself, and its length. `text` is the live FText, kept so an entry the game
-- already had can be rewritten without losing its localization.
local function ReadEntries(desc)
    local arr
    pcall(function() arr = desc.SpinnerOptions end)
    if not arr then return nil, nil, 0, "SpinnerOptions unreadable" end
    local n = 0
    pcall(function() n = arr:GetArrayNum() end)
    local out = {}
    for i = 1, n do
        local e
        pcall(function() e = arr[i] end)
        local dv, label, txt = "?", "?", nil
        if e then
            pcall(function() dv = e.DataValue:ToString() end)
            pcall(function() txt = e.LocalizedValue end)
            pcall(function() label = e.LocalizedValue:ToString() end)
        end
        out[i] = { dataValue = dv, label = label, text = txt, raw = e }
    end
    return out, arr, n, nil
end

local function DumpSpinner(say_, Ar, path)
    local desc = Resolve(path)
    if not desc then say_(Ar, "  " .. path .. " -> NOT FOUND"); return end
    local editable, defIndex = "?", "?"
    pcall(function() editable = tostring(desc.IsSpinnerOptionsRuntimeEditable) end)
    pcall(function() defIndex = tostring(desc.DefaultIndex) end)
    local entries, _, n = ReadEntries(desc)
    say_(Ar, string.format("  %s : %d entrie(s), RuntimeEditable=%s, DefaultIndex=%s",
                           ShortName(desc), n or 0, editable, defIndex))
    if entries then
        for i, e in ipairs(entries) do
            say_(Ar, string.format("     [%d] DataValue=%-4s label=%s", i - 1, e.dataValue, e.label))
        end
    end
end

-- ---------------------------------------------------------------------------
--  PROBE — call the game's own delegate targets directly
--
--  This bypasses the menu entirely: it is exactly what the spinner would do
--  when the player moves it, so a positive result proves the menu entries
--  would work. A negative result proves they would be dead buttons.
-- ---------------------------------------------------------------------------
local function SlotReport()
    local pawn = GetPawn()
    if not pawn then return nil, "player not found" end
    local mesh
    pcall(function() mesh = pawn.Mesh end)
    if not okObj(mesh) then return nil, "Mesh component not found on the pawn" end
    local n = 0
    pcall(function() n = mesh:GetNumMaterials() end)
    local out = {}
    for i = 0, n - 1 do
        local mat, parent
        pcall(function() mat = mesh:GetMaterial(i) end)
        -- Materials in place are MIDs created at runtime, never the asset names.
        -- The parent is what tells which Skin<N> set is actually applied.
        pcall(function() parent = mat.Parent end)
        out[#out + 1] = string.format("[%d] %s (parent: %s)", i, ShortName(mat), ShortName(parent))
    end
    return out, nil
end

local function ProbeOne(value)
    local pawn = GetPawn()
    if not pawn then return false, "player not found" end
    -- ⚠️ pitfall 2: FName parameter, never a raw Lua string.
    local ok = pcall(function() pawn:OnSkinChanged(FName(tostring(value))) end)
    if not ok then return false, "the call to OnSkinChanged was refused" end
    return true, "OnSkinChanged(\"" .. value .. "\") called"
end

local function ProbeBob(value)
    local actors = GetBobActors()
    if #actors == 0 then return false, "no Bob found (not loaded in this area?)" end
    local n = 0
    for _, a in ipairs(actors) do
        if pcall(function() a:SetSkin(FName(tostring(value))) end) then n = n + 1 end
    end
    if n == 0 then return false, "the call to SetSkin was refused on every Bob" end
    return true, "SetSkin(\"" .. value .. "\") called on " .. n .. "/" .. #actors .. " Bob(s)"
end

-- ---------------------------------------------------------------------------
--  GETTING THE VALUES INTO THE MENU
--
--  ☠️ WHAT KILLED THE GAME (10/08/2026, do not retry):
--      desc:SetSpinnerOptions(luaTable)
--  UE4SS cannot build a TArray of STRUCTS out of a Lua table. It crashes
--  inside push_arrayproperty -> for_each_in_table -> luaH_next with an
--  EXCEPTION_ACCESS_VIOLATION, and **pcall does not catch that**: a C++ access
--  violation is a hard Fatal error, the game dies. The call is gone from this
--  mod, and the same goes for any UFUNCTION taking a TArray<FStruct>.
--
--  What is left, by decreasing safety:
--
--  1. REMAP (safe, default). The two entries the game ships are real, already
--     allocated struct elements. Rewriting the DataValue of an existing element
--     is a plain FName property write — the best-supported operation there is.
--     So the menu keeps two positions, but you choose WHICH skins they drive:
--     'skinmenu remap 2 3' turns them into Skin2 / Skin3.
--
--  2. GROW IN PLACE (risky, 'install force' only). Copies an element past the
--     end of the array, then rewrites its DataValue. It needs UE4SS to assign a
--     struct into an array slot and to grow the array, neither of which is
--     established. It may well crash like SetSpinnerOptions did. One restart.
--
--  3. Patch DA_Skin_One_Spinner on disk in a `_P` IoStore container. No runtime
--     trickery, five real entries, proper labels, and it is the only route that
--     can give Bob his own row. This is the real answer.
-- ---------------------------------------------------------------------------
local savedOriginal = nil       -- entries as they were before the first install

local function RememberOriginal(entries)
    if savedOriginal or not entries then return end
    savedOriginal = {}
    for i, e in ipairs(entries) do
        savedOriginal[i] = { dataValue = e.dataValue, text = e.text, label = e.label }
    end
    log("original spinner saved (" .. #savedOriginal .. " entries)")
end

local function CountEntries(desc)
    local _, _, n = ReadEntries(desc)
    return n or 0
end

-- ---------------------------------------------------------------------------
--  1. REMAP — rewrite the DataValue of the entries the game already has
--
--  No allocation, no array growth, no struct built from Lua: just an FName
--  written into an existing element. The menu still shows two positions (and
--  their original labels, which will now lie), but they drive the skins you
--  choose.
-- ---------------------------------------------------------------------------
local function RemapEntries(values)
    local desc = Resolve(ONE_SPINNER)
    if not desc then return false, "DA_Skin_One_Spinner not found" end
    local entries, arr, n = ReadEntries(desc)
    if not arr or n == 0 then return false, "SpinnerOptions unreadable" end
    RememberOriginal(entries)

    if #values > n then
        return false, "the spinner has " .. n .. " slot(s), you gave " .. #values .. " value(s)"
    end

    for i = 1, #values do
        local v = values[i]
        if not pcall(function() arr[i].DataValue = FName(tostring(v)) end) then
            return false, "DataValue write refused on slot " .. i
        end
    end

    -- Read back: a write that does not raise proves nothing.
    local after = ReadEntries(desc)
    local got = {}
    for i = 1, #values do got[i] = after and after[i] and after[i].dataValue or "?" end
    for i = 1, #values do
        if got[i] ~= tostring(values[i]) then
            return false, "read-back mismatch on slot " .. i .. " (got " .. got[i] .. ")"
        end
    end
    return true, "menu slots now drive skins " .. table.concat(got, " / ")
end

-- ---------------------------------------------------------------------------
--  2. GROW IN PLACE — 'skinmenu install force' only
--
--  ⚠️ NOT ESTABLISHED, MAY CRASH THE GAME. It needs two things UE4SS is not
--  known to support on a TArray of structs: assigning a struct into a slot, and
--  growing the array past its allocation. SetSpinnerOptions already died on the
--  struct-array path (see above), so treat a crash here as expected, not as a
--  surprise. Cost of failure: one restart.
-- ---------------------------------------------------------------------------
local function InstallInPlace(desc)
    local entries, arr, n = ReadEntries(desc)
    if not arr then return false, "SpinnerOptions unreadable" end
    if n == 0 then return false, "empty spinner, nothing to copy from" end
    RememberOriginal(entries)

    for v = n, HIGHEST_SKIN do               -- v = the DataValue being added
        local src
        pcall(function() src = arr[1] end)   -- template struct to copy
        if not src then return false, "could not read a template entry" end
        if not pcall(function() arr[v + 1] = src end) then
            return false, "array write refused at entry " .. v
        end
        if not pcall(function() arr[v + 1].DataValue = FName(tostring(v)) end) then
            return false, "DataValue write refused at entry " .. v
        end
        -- Label: best effort. If FText cannot be written from Lua the entry
        -- still works, it just shows the template's text.
        pcall(function() arr[v + 1].LocalizedValue = SKIN_LABELS[v] or ("Skin " .. v) end)
    end

    local after = CountEntries(desc)
    if after ~= HIGHEST_SKIN + 1 then
        return false, "array holds " .. after .. " entries after the writes"
    end
    return true, "in-place growth (" .. n .. " -> " .. after .. " entries)"
end

local function InstallOne()
    local desc = Resolve(ONE_SPINNER)
    if not desc then return false, "DA_Skin_One_Spinner not found" end
    local n = CountEntries(desc)
    if n > HIGHEST_SKIN then
        return true, "already grown (" .. n .. " entries)"
    end
    return InstallInPlace(desc)
end

-- Revert = write the saved DataValues back into the slots they came from.
-- Never through SetSpinnerOptions (that is what crashed the game).
local function RevertOne()
    if not savedOriginal then return false, "no original state saved (nothing changed this session)" end
    local values = {}
    for i, e in ipairs(savedOriginal) do values[i] = e.dataValue end
    local ok, msg = RemapEntries(values)
    if not ok then return false, msg .. " — restart the game to get the vanilla spinner back" end
    -- If 'install force' had grown the array, the extra entries are still there:
    -- only a restart drops them.
    return true, "original DataValues restored (" .. table.concat(values, " / ") .. ")"
end

-- ============================================================================
--  MARCEL BOB — what the game itself does, done here because 1.0.27953 does not
--
--  Established by diffing 1.0.27953 against 1.0.28121 (where the row works):
--    * Bob's assets are IDENTICAL between the two builds — same meshes, same
--      slots (M_EyeGlass / M_Bob / M_bob_accessories), same materials.
--    * The only difference is the body of BP_Bob_Critter::SetSkin, unfinished
--      in 27953. So nothing is missing from the build: only the logic.
--
--  WHAT THE FINISHED GAME ACTUALLY DOES — read straight off 1.0.28121 with
--  'skinmenu bobslots', before and after ticking Marcel Bob in the menu:
--        OFF : mesh SKEL_Bob       [1] MID_MM_Bob_body   [2] MID_MM_Bob_Mustache
--        ON  : mesh SKEL_Bob_Mime  [1] MI_BobSkin_body   [2] MI_BobSkin_Mustache
--  So it is a MESH SWAP **AND** the material pair — all three together. The mime
--  mesh is referenced softly/dynamically, which is why it appears nowhere in the
--  Blueprint's imports; searching the asset for it proves nothing.
--
--  The material pair, and the texture names that name it:
--        slot M_Bob             MM_Bob_body     -> T_BobCritter_*
--                               MI_BobSkin_body -> T_BobCritterSKIN_*
--        slot M_bob_accessories MM_Bob_Mustache     -> T_BobCritter_Accessories_*
--                               MI_BobSkin_Mustache -> T_BobCritterSKIN_Accessories_*
--  Both must be applied together. Putting the mustache material on the BODY is
--  the mistake that made this look nonsensical before: it belongs on the
--  accessories slot.
-- ============================================================================
local BOB_ART = "/Game/Art/Character/Bob/"
local BOB_CLASSES_HOOK = "/Game/Game/Pawn/AI/Critter/Shard/BP_Bob_Critter.BP_Bob_Critter_C:SetSkin"

local bobOriginals = nil        -- { [actorFullName] = { [slot] = material } }
local bobOriginalMesh = nil     -- { [actorFullName] = skinned asset }
local bobSkinOn = false

-- Section order, identical on SKEL_Bob and SKEL_Bob_Mime (read off 1.0.28121).
local BOB_SLOT_EYES, BOB_SLOT_BODY, BOB_SLOT_ACC = 0, 1, 2

-- The element tint lives on the MID the game built for this actor (a Lava Bob
-- carries the lava FluidColor / "Emissive Color"). Rather than rebuild those
-- values, we read them off that MID and copy them onto a fresh MID made from the
-- skin material — so the skin arrives without flattening the element.
-- Both values travel as engine objects, never as Lua tables: see pitfall 5.
-- Values straight out of BP_Bob_Critter's defaults in 1.0.28121, where the
-- finished SetSkin writes them. ElementName defaults to Water, which is why a
-- Lava Bob turns blue under the raw skin material.
local ELEMENT_COLOURS = {
    Lava  = { FluidColor = { 1.0, 0.027276, 0.0, 1.0 },
              ["Emissive Color"] = { 1.0, 0.3943, 0.0, 1.0 } },
    Waste = { FluidColor = { 0.138432, 0.715694, 0.0, 1.0 },
              ["Emissive Color"] = { 0.434154, 1.0, 0.038204, 1.0 } },
    Water = { FluidColor = { 0.0, 0.132018, 0.715278, 1.0 },
              ["Emissive Color"] = { 0.0, 0.66615, 1.0, 1.0 } },
}

local function ElementOf(actor)
    local n = Name(actor)
    if string.find(n, "Lava", 1, true) then return "Lava" end
    if string.find(n, "Waste", 1, true) then return "Waste" end
    return "Water"
end

-- ⚠️ We never BUILD an FLinearColor from a Lua table (pitfall 5: a struct handed
-- to the engine as a table is what hard-crashed the game). We read the parameter
-- back — that hands us a real engine struct — mutate its fields, and hand the
-- same object in. No conversion anywhere.
local function SetColour(mid, param, rgba)
    local name, v = FName(param), nil
    if not pcall(function() v = mid:K2_GetVectorParameterValue(name) end) or v == nil then
        return false
    end
    if not pcall(function()
        v.R, v.G, v.B, v.A = rgba[1], rgba[2], rgba[3], rgba[4]
    end) then
        return false
    end
    return pcall(function() mid:SetVectorParameterValue(name, v) end)
end

-- Swaps the mesh on EVERY skeletal mesh component of the actor that currently
-- carries the character's mesh — the main one plus the outline shells created by
-- BP_OverlayMeshComponent. Enumerated through BlueprintCreatedComponents, the
-- only path that answered on this build (K2_GetComponentsByClass returns 0).
local function SwapEverySkeletalMesh(actor, mainComp, want, previous)
    local swapped = 0
    local function trySwap(c)
        local currentName = ShortName(c:GetSkinnedAsset())
        -- Only the shells that mirror the character, never a foreign mesh.
        if currentName ~= "SKEL_Bob" and currentName ~= "SKEL_Bob_Mime" then return end
        pcall(function() c:SetSkinnedAssetAndUpdate(want, true) end)
        -- ⚠️ READ-BACK MANDATORY: the call raises nothing when a mesh is refused.
        if ShortName(c:GetSkinnedAsset()) == ShortName(want) then
            swapped = swapped + 1
        else
            log("   swap REFUSED on " .. ShortName(c))
        end
    end

    if okObj(mainComp) then pcall(function() trySwap(mainComp) end) end

    local arr, n = nil, 0
    pcall(function() arr = actor.BlueprintCreatedComponents end)
    pcall(function() n = arr:GetArrayNum() end)
    for i = 1, n do
        local c
        pcall(function() c = arr[i] end)
        if okObj(c) and Name(c) ~= Name(mainComp) then
            local sk
            pcall(function() sk = c:GetSkinnedAsset() end)
            if okObj(sk) then pcall(function() trySwap(c) end) end
        end
    end
    return swapped
end

-- Read off 1.0.28121 with the mod in passive mode, so this is the devs' own
-- end state, not ours: ALL THREE slots are dynamic instances, and all three
-- carry the element colours plus "Emissive strength" = 10. Doing it on the body
-- alone (the first attempt) left the eyes and the moustache flat black.
local EMISSIVE_STRENGTH = 10.0

-- ⚠️ THE REASON MARCEL BOB NEVER LOOKED RIGHT ON 1.0.27953.
-- MI_BobSkin_body is an UNFINISHED material in this build. Compared with 1.0.28121:
--        BaseColor : T_BobCritter_BCA (the ORDINARY Bob albedo)  ->  T_BobCritterSkin_BCA
--        Emissive  : T_BobCritterSkin_E                          ->  T_BobCritter_E
-- and `T_BobCritterSkin_BCA` **does not exist in the 27953 pak at all** (checked at pak
-- level: retoc extracts 0 assets for that name, while every other Skin texture extracts
-- fine). So Bob's body was wearing the normal Bob's skin, and no amount of Lua could
-- invent the missing pixels.
--
-- The companion content patch (UE_YGRO-Windows_P) ships those pixels: the package
-- T_BobCritterSkin_E now physically carries the 1.0.28121 albedo (same PF_DXT1 2048x2048,
-- same bulk size to the byte, so the original header still describes it correctly). That
-- name was free: T_BobCritterSkin_E is referenced by MI_BobSkin_body ALONE, and the
-- finished material does not use it anymore.
-- Hence the two rebinds below. Without the pak they are harmless: the parameters simply
-- keep pointing at what the build already had.
local BOB_BODY_TEXTURES = {
    { param = "BaseColor", asset = "T_BobCritterSkin_E" },   -- carries the skin albedo
    { param = "Basecolor", asset = "T_BobCritterSkin_E" },   -- the material exposes both spellings
    { param = "Emissive",  asset = "T_BobCritter_E" },
}

local function RebindBodyTextures(mid)
    for _, t in ipairs(BOB_BODY_TEXTURES) do
        local tex = Resolve(BOB_ART .. "Textures/" .. t.asset)
        if tex then
            local ok = pcall(function()
                mid:SetTextureParameterValue(FName(t.param), tex)
            end)
            log(string.format("   texture %-10s -> %s %s", t.param, t.asset,
                ok and "" or "(REFUSED)"))
        else
            log("   texture " .. t.asset .. " not found")
        end
    end
end

local function ParameteriseBobSlots(comp, actor, body, tash)
    local element = ElementOf(actor)
    local colours = ELEMENT_COLOURS[element]
    local done = 0
    for slot = BOB_SLOT_EYES, BOB_SLOT_ACC do
        local source
        if slot == BOB_SLOT_BODY then
            source = body
        elseif slot == BOB_SLOT_ACC then
            source = tash
        else
            -- The eyes keep their own material; the game only wraps it in a MID.
            pcall(function() source = comp:GetMaterial(slot) end)
        end
        if okObj(source) then
            local mid
            -- The third argument (FName OptionalName) is NOT optional for UE4SS:
            -- leaving it out is what made this call fail silently at first.
            -- CreateDynamicMaterialInstance also ASSIGNS the result to the slot,
            -- so there is no SetMaterial to do afterwards.
            pcall(function()
                mid = comp:CreateDynamicMaterialInstance(slot, source, FName("None"))
            end)
            if okObj(mid) then
                for param, rgba in pairs(colours) do SetColour(mid, param, rgba) end
                pcall(function()
                    mid:SetScalarParameterValue(FName("Emissive strength"), EMISSIVE_STRENGTH)
                end)
                if slot == BOB_SLOT_BODY then RebindBodyTextures(mid) end
                done = done + 1
                log(string.format("   slot %d -> MID of %s, %s colours",
                    slot, ShortName(source), element))
            else
                log(string.format("   slot %d: no dynamic instance (left flat)", slot))
            end
        end
    end
    return done
end

-- Passive mode: observe, never write. Essential when reading the reference
-- build (1.0.28121), where the GAME applies Marcel Bob — writing on top of it
-- would replace its parameterised MIDs with raw instances and we would end up
-- measuring our own work instead of the devs'.
local passive = false

local function ApplyBobSkin(on)
    if passive then return false, "passive mode: nothing written" end
    local actors = GetBobActors()
    if #actors == 0 then return false, "no Bob found (not loaded in this area?)" end

    local body = on and Resolve(BOB_ART .. "MI_BobSkin_body") or nil
    local tash = on and Resolve(BOB_ART .. "MI_BobSkin_Mustache") or nil
    local mime = on and Resolve(BOB_ART .. "SKEL_Bob_Mime") or nil
    if on and not (body and tash and mime) then
        return false, "skin assets could not be loaded (mesh or materials)"
    end

    bobOriginals = bobOriginals or {}
    bobOriginalMesh = bobOriginalMesh or {}
    local touched = 0
    for _, a in ipairs(actors) do
        local comp
        pcall(function() comp = a.Mesh end)
        if okObj(comp) then
            local key = Name(a)
            local n = 0
            pcall(function() n = comp:GetNumMaterials() end)

            if not bobOriginals[key] then          -- remember before touching
                bobOriginals[key] = {}
                for i = 0, n - 1 do
                    local cur
                    pcall(function() cur = comp:GetMaterial(i) end)
                    bobOriginals[key][i] = cur
                end
                pcall(function() bobOriginalMesh[key] = comp:GetSkinnedAsset() end)
            end

            -- The mesh goes FIRST: the materials are then written onto the new
            -- geometry's slots. Both meshes carry the same 3 slots in the same
            -- order (verified in game on 1.0.28121), so nothing goes black.
            --
            -- ⚠️ AND NOT ONLY THIS COMPONENT. BP_OverlayMeshComponent duplicates
            -- the character into extra SkeletalMeshComponents that draw the black
            -- outline as an inverted shell. Swapping CharacterMesh0 alone left
            -- those shells shaped like the OLD Bob, so an old-Bob silhouette was
            -- drawn over the new body — found with 'skinmenu bobprobe', which
            -- showed components 21 and 22 still holding SKEL_Bob.
            local want = on and mime or bobOriginalMesh[key]
            if okObj(want) then
                local swapped = SwapEverySkeletalMesh(a, comp, want, bobOriginalMesh[key])
                log(string.format("   %s mesh -> %s on %d component(s)",
                    ShortName(a), ShortName(want), swapped))
                pcall(function() n = comp:GetNumMaterials() end)
            end

            -- ⚠️ PURGE MANDATORY. The overrides of the previous mesh survive the
            -- swap and land on sections that no longer mean the same thing on the
            -- new geometry: that is what put the right materials in the wrong
            -- places. Clearing them makes the component fall back to the mesh's
            -- own defaults, which is the state the finished game ends up in.
            for i = 0, n - 1 do
                pcall(function() comp:SetMaterial(i, nil) end)
            end

            if on then
                -- By INDEX, not by guessing from the material in place: the
                -- 1.0.28121 dump shows both meshes carry the same three sections,
                -- 0 eyes / 1 body / 2 accessories. Each becomes a dynamic instance
                -- carrying this actor's element colours — that is what the finished
                -- game does, measured, not guessed.
                touched = touched + ParameteriseBobSlots(comp, a, body, tash)
            else
                for i = 0, n - 1 do
                    local target = bobOriginals[key][i]
                    if target and pcall(function() comp:SetMaterial(i, target) end) then
                        touched = touched + 1
                    end
                end
            end
        end
    end
    if touched == 0 then return false, "no slot could be written" end
    bobSkinOn = on
    return true, (on and "Marcel Bob applied on " or "default Bob restored on ")
                 .. #actors .. " actor(s), " .. touched .. " slot(s)"
end

-- The game calls SetSkin when the menu row changes — if the delegate is bound.
-- Hooking it makes the patched menu row do what it does in 1.0.28121.
local hookOk = pcall(function()
    RegisterHook(BOB_CLASSES_HOOK, function(Context, Index)
        local v = ""
        pcall(function() v = Index:get():ToString() end)
        log("SetSkin fired with " .. tostring(v))
        local ok, msg = ApplyBobSkin(v ~= "0")
        log("   -> " .. tostring(msg))
    end)
end)
log(hookOk and "hook on BP_Bob_Critter::SetSkin installed"
            or "hook on BP_Bob_Critter::SetSkin REFUSED (option polling still covers it)")

-- Fallback + maintenance: the delegate may never be bound in this build, and the
-- game recreates Bob on respawn / zone change. One stable closure, low frequency.
-- Is Bob still wearing OUR version of the skin?
--
-- Going through the menu, the game's own (unfinished) SetSkin runs on section exit
-- and rebuilds the materials from MI_BobSkin_body — whose BaseColor still points at
-- the ORDINARY Bob's albedo in this build. The geometry survives (it comes from the
-- mesh) but the paint does not: beret and moustache stop being black and the legs
-- lose their stripes. Watching for that exact signature is what catches it.
local ALBEDO_CARRIER = "T_BobCritterSkin_E"     -- the package holding the skin albedo

local function BobStateIsOurs(actor)
    local comp
    pcall(function() comp = actor.Mesh end)
    if not okObj(comp) then return true end                 -- nothing to judge yet
    if ShortName(comp:GetSkinnedAsset()) ~= "SKEL_Bob_Mime" then return false end
    local mat, tex
    pcall(function() mat = comp:GetMaterial(BOB_SLOT_BODY) end)
    if not okObj(mat) then return false end
    pcall(function() tex = mat:K2_GetTextureParameterValue(FName("BaseColor")) end)
    return okObj(tex) and ShortName(tex) == ALBEDO_CARRIER
end

-- Reasserts the skin on Bobs that appeared since the last pass (respawn, streaming)
-- or whose materials the game rebuilt underneath us (the menu path above).
local function ReassertBobSkin()
    for _, a in ipairs(GetBobActors()) do
        local fresh = not (bobOriginals and bobOriginals[Name(a)])
        if fresh or not BobStateIsOurs(a) then
            log(fresh and "new Bob: applying Marcel"
                       or "Marcel was overwritten by the game: re-applying")
            ApplyBobSkin(true)
            return
        end
    end
end

local lastBobOption = nil
LoopAsync(2000, function()
    ExecuteInGameThread(function()
        local sub = FindFirstOf("OptionSubsystem")
        local desc = Resolve(BOB_SPINNER)
        local value = nil
        if okObj(sub) and desc then
            local opt
            pcall(function() opt = sub:GetOption(desc) end)
            if okObj(opt) then pcall(function() value = opt.IndexCurrentValue end) end
        end
        -- ⚠️ There used to be a "the mesh is already the mime one, so the build did
        -- the job itself" guard here. It silently disabled the mod on 27953: the
        -- game's own SetSkin DOES swap the mesh (that is where the beret came from),
        -- so the guard fired on the menu path and the materials were never applied.
        -- Symptom: the beret appears and nothing else. Judge the FULL state instead
        -- — mesh AND albedo — which is what BobStateIsOurs does.
        if value ~= nil and value ~= lastBobOption then
            lastBobOption = value
            local ok, msg = ApplyBobSkin(value ~= 0)
            log("option Bob = " .. tostring(value) .. " -> " .. tostring(msg))
        elseif value ~= nil and value ~= 0 then
            -- Option still on: keep our version asserted, whatever the game rebuilds.
            ReassertBobSkin()
        elseif bobSkinOn then
            ReassertBobSkin()
        end
    end)
    return false
end)

-- ---------------------------------------------------------------------------
--  BOB'S ROW — kept for the record, expected to change nothing on screen
--
--  The subsection list becomes widgets in C++ at screen creation and no
--  rebuild function is exposed (UOptionMenuScreen has 5 UFUNCTIONs, all
--  navigation; UOptionSubsystem exposes only GetOption). Verified in game:
--  the array does grow, the UI does not. Getting Bob a real row needs the
--  DataAsset patched on disk, not Lua.
-- ---------------------------------------------------------------------------
local function AttachBobSpinner()
    local sub = Resolve(SUBSECTION)
    local bob = Resolve(BOB_SPINNER)
    if not (sub and bob) then return false, "DataAssets not found" end
    local arr
    pcall(function() arr = sub.OptionDescriptors end)
    if not arr then return false, "OptionDescriptors unreadable" end
    local n = 0
    pcall(function() n = arr:GetArrayNum() end)
    for i = 1, n do
        local v
        pcall(function() v = arr[i] end)
        if v and Name(v) == Name(bob) then return true, "already wired in (" .. n .. " entries)" end
    end
    if not pcall(function() arr[n + 1] = bob end) then return false, "write refused" end
    local after = 0
    pcall(function() after = arr:GetArrayNum() end)
    return after > n, "array " .. n .. " -> " .. after .. " (no effect on the UI, see header)"
end

-- ---------------------------------------------------------------------------
--  Console command
-- ---------------------------------------------------------------------------
local function Help(Ar)
    say(Ar, "commands:")
    say(Ar, "   skinmenu dump            state of the skin DataAssets")
    say(Ar, "   skinmenu test <0-4>      fires the game's OnSkinChanged on One (no menu involved)")
    say(Ar, "   skinmenu testbob <0-1>   fires the game's SetSkin on the Bob actors")
    say(Ar, "   skinmenu bobskin on|off  applies Marcel Bob directly (materials, not a mesh)")
    say(Ar, "   skinmenu bobslots        dumps every Bob material slot (diagnostic)")
    say(Ar, "   skinmenu passive on/off  observe only, write nothing (for reference dumps)")
    say(Ar, "   skinmenu bobcomps        dumps Bob components, anim class and scale")
    say(Ar, "   skinmenu bobprobe        EVERYTHING: components, anim, all material params")
    say(Ar, "   skinmenu remap <a> <b>   makes the 2 menu slots drive skins a and b   <- SAFE")
    say(Ar, "   skinmenu revert          puts the original values back in the slots")
    say(Ar, "   skinmenu install force   tries to grow the spinner to 5 entries   <- MAY CRASH")
    say(Ar, "   skinmenu bob             tries Bob's row (inert, kept for the record)")
    say(Ar, "after 'remap': close the pause menu, reopen Options > Customization.")
end

RegisterConsoleCommandGlobalHandler("skinmenu", function(FullCommand, Parameters, Ar)
    local p = Parameters or {}
    local key = (p[1] and string.lower(p[1])) or ""

    if key == "" then
        local desc = Resolve(ONE_SPINNER)
        if desc then
            local entries, _, n = ReadEntries(desc)
            local vals = {}
            for i = 1, (n or 0) do vals[i] = entries[i].dataValue end
            say(Ar, "One's spinner: " .. (n or 0) .. " slot(s), driving skin(s) "
                    .. table.concat(vals, " / ") .. "   (vanilla: 0 / 1)")
        else
            say(Ar, "DA_Skin_One_Spinner not loaded yet — open Options once, then retry.")
        end
        Help(Ar)
        return true
    end

    if key == "dump" then
        say(Ar, "skin DataAssets:")
        DumpSpinner(say, Ar, ONE_SPINNER)
        DumpSpinner(say, Ar, BOB_SPINNER)
        local sub = Resolve(SUBSECTION)
        if sub then
            local arr, n = nil, 0
            pcall(function() arr = sub.OptionDescriptors end)
            if arr then pcall(function() n = arr:GetArrayNum() end) end
            say(Ar, "  DA_Skin_SubSection : " .. n .. " descriptor row(s)")
            for i = 1, n do
                local v
                pcall(function() v = arr[i] end)
                say(Ar, "     [" .. i .. "] " .. ShortName(v))
            end
        else
            say(Ar, "  DA_Skin_SubSection -> NOT FOUND")
        end
        return true
    end

    if key == "test" then
        local v = tonumber(p[2])
        if not v or v < 0 or v > HIGHEST_SKIN then
            say(Ar, "usage: skinmenu test <0-" .. HIGHEST_SKIN .. ">")
            return true
        end
        say(Ar, "calling the game's own OnSkinChanged with \"" .. v .. "\"…")
        say(Ar, "watch One: if he changes, the menu entries are worth adding.")
        ExecuteInGameThread(function()              -- no Ar here (pitfall 1)
            local before = SlotReport()
            local ok, msg = ProbeOne(v)
            log("test -> " .. tostring(msg))
            local after = SlotReport()
            if before and after then
                log("materials before -> after:")
                for i = 1, math.max(#before, #after) do
                    log("   " .. tostring(before[i]))
                    log("     => " .. tostring(after[i]))
                end
            end
        end)
        return true
    end

    -- Ground-truth probe. Run it in a build where Marcel Bob WORKS (1.0.28121),
    -- once with the skin off and once with it on: the diff is exactly what the
    -- finished SetSkin does, with no bytecode reading involved.
    -- Exhaustive probe. The parameter list is not guessed: it is every named
    -- parameter found in MM_Bob_body, MM_Bob_Mustache and MM_GlassSimple in the
    -- 1.0.27953 extract. Each name is probed as scalar, vector AND texture,
    -- because the same name is used for different types across those materials.
    if key == "bobprobe" then
        say(Ar, "full probe of every Bob (details in the UE4SS console)…")
        ExecuteInGameThread(function()              -- no Ar here
            -- Every named parameter found in MM_Bob_body, MM_Bob_Mustache and
            -- MM_GlassSimple. Probed as scalar, vector AND texture: the same
            -- name serves different types across those materials.
            local PARAMS = {
                "BaseColor", "Basecolor", "Blink", "BlinkColor", "BlinkSpeed",
                "Color", "DeactivateWorldLayer", "DissolveBurnThickness",
                "DissolveColor", "DissolveSize", "DissolveTransitionValue",
                "DissovleEmBoost", "Emissive", "Emissive Color",
                "Emissive strength", "EmissivePower", "FluidColor",
                "FresnelStrength", "MaxRough", "MinRough", "Opacity",
                "OpacityStrength", "PortalSphereLocation", "PortalSphereRadius",
                "RefractionDepthBias", "Shadow Version", "WorldLayer",
                "WorldLoaded", "WorldPortal",
            }

            local function DumpMaterials(c)
                local n = nil
                pcall(function() n = c:GetNumMaterials() end)
                if not n or n == 0 then return end
                for i = 0, n - 1 do
                    local mat, parent
                    pcall(function() mat = c:GetMaterial(i) end)
                    pcall(function() parent = mat.Parent end)
                    log(string.format("       slot %d : %s  (parent %s)",
                        i, ShortName(mat), ShortName(parent)))
                    if okObj(mat) then
                        for _, prm in ipairs(PARAMS) do
                            local nm = FName(prm)
                            local sc
                            if pcall(function() sc = mat:K2_GetScalarParameterValue(nm) end)
                               and sc ~= nil and sc ~= 0 then
                                log(string.format("            %-22s scalar %s", prm, tostring(sc)))
                            end
                            local v
                            if pcall(function() v = mat:K2_GetVectorParameterValue(nm) end)
                               and v ~= nil then
                                local r, g, b, al
                                pcall(function() r, g, b, al = v.R, v.G, v.B, v.A end)
                                if r and not (r == 0 and g == 0 and b == 0 and al == 0) then
                                    log(string.format("            %-22s vector %s %s %s %s",
                                        prm, tostring(r), tostring(g), tostring(b), tostring(al)))
                                end
                            end
                            local t
                            if pcall(function() t = mat:K2_GetTextureParameterValue(nm) end)
                               and okObj(t) then
                                log(string.format("            %-22s texture %s", prm, ShortName(t)))
                            end
                        end
                    end
                end
            end

            local function DumpComponent(c, tag)
                local cls = "?"
                pcall(function() cls = c:GetClass():GetFName():ToString() end)
                local vis, hidden = "?", "?"
                pcall(function() vis = tostring(c.bVisible) end)
                pcall(function() hidden = tostring(c.bHiddenInGame) end)
                log(string.format("  %s %-30s %-26s visible=%s hidden=%s",
                    tag, ShortName(c), cls, vis, hidden))
                local sx, sy, sz
                pcall(function()
                    local sc = c.RelativeScale3D
                    sx, sy, sz = sc.X, sc.Y, sc.Z
                end)
                if sx then
                    log(string.format("       scale %s %s %s",
                        tostring(sx), tostring(sy), tostring(sz)))
                end
                local skinned, animCls, animInst
                pcall(function() skinned = c:GetSkinnedAsset() end)
                pcall(function() animCls = c.AnimClass end)
                pcall(function() animInst = c.AnimScriptInstance end)
                if okObj(skinned) then
                    log("       mesh " .. ShortName(skinned)
                        .. "   animClass " .. ShortName(animCls)
                        .. "   animInstance " .. ShortName(animInst))
                end
                DumpMaterials(c)
            end

            -- Several ways in, and we SAY which one answered: the previous probe
            -- reported "0 components" and went silent, which told us nothing.
            local function EachComponent(a, fn)
                for _, path in ipairs({ "/Script/Engine.SceneComponent",
                                        "/Script/Engine.ActorComponent" }) do
                    local cls = StaticFindObject(path)
                    if okObj(cls) then
                        local arr, n = nil, 0
                        pcall(function() arr = a:K2_GetComponentsByClass(cls) end)
                        pcall(function() n = arr:GetArrayNum() end)
                        log(string.format("  (%s -> %d)", path, n))
                        if n > 0 then
                            for i = 1, n do
                                local c
                                pcall(function() c = arr[i] end)
                                if okObj(c) then fn(c, "[" .. i .. "]") end
                            end
                            return n
                        end
                    else
                        log("  (class not found: " .. path .. ")")
                    end
                end
                for _, prop in ipairs({ "BlueprintCreatedComponents", "InstanceComponents" }) do
                    local arr, n = nil, 0
                    pcall(function() arr = a[prop] end)
                    pcall(function() n = arr:GetArrayNum() end)
                    log(string.format("  (%s -> %d)", prop, n))
                    if n > 0 then
                        for i = 1, n do
                            local c
                            pcall(function() c = arr[i] end)
                            if okObj(c) then fn(c, "<" .. i .. ">") end
                        end
                        return n
                    end
                end
                return 0
            end

            for _, a in ipairs(GetBobActors()) do
                log("################ " .. Name(a))
                local hid, x, y, z = "?", "?", "?", "?"
                pcall(function() hid = tostring(a.bHidden) end)
                pcall(function()
                    local l = a:K2_GetActorLocation()
                    x, y, z = l.X, l.Y, l.Z
                end)
                log(string.format("  actor hidden=%s  location=%s %s %s",
                    hid, tostring(x), tostring(y), tostring(z)))

                -- The main mesh is reachable directly, so the probe can never
                -- come back empty again even if the enumeration fails.
                local mesh
                pcall(function() mesh = a.Mesh end)
                if okObj(mesh) then
                    DumpComponent(mesh, "(a.Mesh)")
                else
                    log("  a.Mesh unreadable")
                end

                local n = EachComponent(a, DumpComponent)
                log("  " .. n .. " component(s) enumerated")
            end
            log("################ end of probe")
        end)
        return true
    end

    -- The materials and the mesh now match the reference build exactly, so any
    -- remaining visual difference lives outside them: an attached component, a
    -- hidden one, or the animation blueprint. This dumps that layer.
    if key == "bobcomps" then
        say(Ar, "dumping Bob's components (details in the UE4SS console)…")
        ExecuteInGameThread(function()              -- no Ar here
            for _, a in ipairs(GetBobActors()) do
                log("=== " .. ShortName(a) .. " ===")
                local mesh
                pcall(function() mesh = a.Mesh end)
                if okObj(mesh) then
                    local anim, cls = nil, nil
                    pcall(function() anim = mesh.AnimScriptInstance end)
                    pcall(function() cls = mesh.AnimClass end)
                    log("   anim class    : " .. ShortName(cls))
                    log("   anim instance : " .. ShortName(anim))
                    local sx, sy, sz = "?", "?", "?"
                    pcall(function()
                        local s = mesh.RelativeScale3D
                        sx, sy, sz = s.X, s.Y, s.Z
                    end)
                    log(string.format("   mesh scale    : %s %s %s",
                        tostring(sx), tostring(sy), tostring(sz)))
                end
                local comps
                pcall(function()
                    comps = a:K2_GetComponentsByClass(
                        StaticFindObject("/Script/Engine.ActorComponent"))
                end)
                if comps then
                    local i = 0
                    pcall(function()
                        for _, c in pairs(comps) do
                            if okObj(c) then
                                i = i + 1
                                local cls = "?"
                                pcall(function() cls = c:GetClass():GetFName():ToString() end)
                                local vis, hid = "?", "?"
                                pcall(function() vis = tostring(c.bVisible) end)
                                pcall(function() hid = tostring(c.bHiddenInGame) end)
                                log(string.format("   [%d] %-34s %-28s visible=%s hidden=%s",
                                    i, ShortName(c), cls, vis, hid))
                            end
                        end
                    end)
                    log("   " .. i .. " component(s)")
                end
            end
        end)
        return true
    end

    if key == "passive" then
        passive = ((p[2] and string.lower(p[2])) or "on") ~= "off"
        say(Ar, passive and "passive mode ON: the mod observes and writes nothing."
                        or  "passive mode OFF: the mod applies Marcel Bob again.")
        say(Ar, "use it on a build where the GAME already does the job, so a dump")
        say(Ar, "reads the devs' work and not ours.")
        return true
    end

    if key == "bobslots" then
        say(Ar, "dumping Bob's material slots (details in the UE4SS console)…")
        ExecuteInGameThread(function()              -- no Ar here
            local actors = GetBobActors()
            log("=== " .. #actors .. " Bob actor(s) ===")
            for _, a in ipairs(actors) do
                log("actor " .. ShortName(a) .. "  (" .. Name(a) .. ")")
                local comp
                pcall(function() comp = a.Mesh end)
                if okObj(comp) then
                    local n = 0
                    pcall(function() n = comp:GetNumMaterials() end)
                    local mesh = "?"
                    pcall(function() mesh = ShortName(comp:GetSkinnedAsset()) end)
                    log("   mesh: " .. mesh .. ", " .. n .. " slot(s)")
                    for i = 0, n - 1 do
                        local mat, parent
                        pcall(function() mat = comp:GetMaterial(i) end)
                        pcall(function() parent = mat.Parent end)
                        log(string.format("   [%d] %s   (parent: %s)",
                            i, ShortName(mat), ShortName(parent)))
                        -- Parameters, not just which material: once the slots
                        -- match the reference build, any remaining difference
                        -- lives in here.
                        for _, p in ipairs({ "FluidColor", "Emissive Color",
                                             "BlinkColor", "DissolveColor" }) do
                            local v
                            if pcall(function() v = mat:K2_GetVectorParameterValue(FName(p)) end)
                               and v ~= nil then
                                local r, g, b, al = "?", "?", "?", "?"
                                pcall(function() r, g, b, al = v.R, v.G, v.B, v.A end)
                                log(string.format("        %-16s %s %s %s %s",
                                    p, tostring(r), tostring(g), tostring(b), tostring(al)))
                            end
                        end
                        for _, p in ipairs({ "EmissivePower", "Emissive strength" }) do
                            local v
                            if pcall(function() v = mat:K2_GetScalarParameterValue(FName(p)) end)
                               and v ~= nil then
                                log(string.format("        %-16s %s", p, tostring(v)))
                            end
                        end
                    end
                else
                    log("   no mesh component")
                end
            end
        end)
        return true
    end

    if key == "bobskin" then
        local sub = (p[2] and string.lower(p[2])) or "on"
        if sub ~= "on" and sub ~= "off" then
            say(Ar, "usage: skinmenu bobskin on|off")
            return true
        end
        say(Ar, sub == "on" and "applying Marcel Bob (body + accessories materials)…"
                            or  "restoring the default Bob…")
        ExecuteInGameThread(function()              -- no Ar here
            local ok, msg = ApplyBobSkin(sub == "on")
            log("bobskin -> " .. (ok and "OK: " or "FAILED: ") .. tostring(msg))
        end)
        return true
    end

    if key == "testbob" then
        local v = tonumber(p[2])
        if not v or v < 0 then
            say(Ar, "usage: skinmenu testbob <0-1>   (1 = Marcel Bob)")
            return true
        end
        say(Ar, "calling the game's own SetSkin with \"" .. v .. "\" on every Bob…")
        ExecuteInGameThread(function()              -- no Ar here
            local ok, msg = ProbeBob(v)
            log("testbob -> " .. tostring(msg))
        end)
        return true
    end

    if key == "remap" then
        local a, b = tonumber(p[2]), tonumber(p[3])
        local values = {}
        for _, v in ipairs({ a, b }) do
            if v and v >= 0 and v <= HIGHEST_SKIN then values[#values + 1] = v end
        end
        if #values == 0 then
            say(Ar, "usage: skinmenu remap <a> [b]   with a, b in 0-" .. HIGHEST_SKIN)
            say(Ar, "example: skinmenu remap 2 3   -> the 2 menu slots drive Skin2 and Skin3")
            return true
        end
        say(Ar, "rewriting the menu slots…")
        say(Ar, "then: close the pause menu and reopen Options > Customization.")
        say(Ar, "note: the labels keep saying Default / Hellgur One — they are string-table")
        say(Ar, "      entries and cannot be rewritten from Lua. Only the effect changes.")
        ExecuteInGameThread(function()              -- no Ar here
            local ok, msg = RemapEntries(values)
            log("remap -> " .. (ok and "OK: " or "FAILED: ") .. tostring(msg))
        end)
        return true
    end

    if key == "install" then
        if (p[2] and string.lower(p[2])) ~= "force" then
            say(Ar, "'install' asks UE4SS to grow a TArray of structs. The sibling call")
            say(Ar, "SetSpinnerOptions already killed the game that way (access violation")
            say(Ar, "inside push_arrayproperty — pcall does NOT catch it).")
            say(Ar, "Use 'skinmenu remap <a> <b>' instead: same result through the menu,")
            say(Ar, "no allocation, no risk. If you want to try anyway, and accept losing")
            say(Ar, "the session: skinmenu install force")
            return true
        end
        say(Ar, "growing One's spinner to 5 entries — this may hard-crash the game…")
        ExecuteInGameThread(function()              -- no Ar here
            local ok, msg = InstallOne()
            log("install -> " .. (ok and "OK: " or "FAILED: ") .. tostring(msg))
        end)
        return true
    end

    if key == "revert" then
        say(Ar, "restoring One's original spinner…")
        ExecuteInGameThread(function()              -- no Ar here
            local ok, msg = RevertOne()
            log("revert -> " .. (ok and "OK: " or "FAILED: ") .. tostring(msg))
        end)
        return true
    end

    if key == "bob" then
        say(Ar, "attempting to add Bob's row (reminder: the UI will not change)…")
        ExecuteInGameThread(function()              -- no Ar here
            local ok, msg = AttachBobSpinner()
            log("bob -> " .. tostring(msg))
        end)
        return true
    end

    say(Ar, "unknown command: " .. key)
    Help(Ar)
    return true
end)

-- ---------------------------------------------------------------------------
--  Startup
--  ⚠️ A fresh closure re-armed at high frequency tears the EngineTick hook down
--  and kills every Lua mod. This LoopAsync fires once and returns true to stop:
--  no re-arming, no per-frame work.
-- ---------------------------------------------------------------------------
if BOOT_REMAP and #BOOT_REMAP > 0 then
    LoopAsync(BOOT_DELAY_MS, function()
        ExecuteInGameThread(function()
            local ok, msg = RemapEntries(BOOT_REMAP)
            log("boot remap -> " .. (ok and "OK: " or "FAILED: ") .. tostring(msg))
        end)
        return true                                 -- stop the loop
    end)
end

log("=== FESkinMenu v12 — menu path fixed (bad guard removed) ===")
log("loaded. Type 'skinmenu' in the console for the command list.")
log("'skinmenu test <0-4>' applies a skin right away; 'skinmenu remap <a> <b>' puts")
log("the ones you pick behind the two Customization menu positions.")
