-- ============================================================================
--  FADING ECHO — SKINS  (v2)
--
--  Applies One's hidden skins directly to his mesh, without going through
--  the options menu (see "WHY NOT THE MENU" below).
--
--  Commands (game console = the ² key, or UE4SS console):
--     skin              status + command reminder
--     skin slots        lists the player's material slots and their contents
--     skin one <0-4>    applies the Skin0..Skin4 material set
--     skin reset        restores the original materials
--     skin lock         reapplies in a loop (if the game overwrites our skin)
--     skin menu         attempt to wire in Bob's spinner (see below)
--
--  Detailed output: UE4SS CONSOLE WINDOW.
--
--  ---------------------------------------------------------------------------
--  WHAT EXISTS IN THE GAME (build 1.0.27900)
--
--  Five complete, packaged material sets, THREE of which have no menu entry at
--  all: /Game/Art/Character/Hero/Skin<N>/  with, for each N from 0 to 4:
--      MI_MainCharaBody_Skin<N>       (body)
--      MI_MainCharaHead_Skin<N>       (head)
--      MI_MainCharaCape_cinematic_Skin<N>  (cape)
--  The Customization menu only exposes Default (Skin0) and "Hellgur One" (Skin1).
--
--  ---------------------------------------------------------------------------
--  WHY NOT THE MENU (established, do not retry)
--
--  Options > Customization is driven by DataAssets:
--      DA_Skin_SubSection.OptionDescriptors = [ DA_Skin_One_Spinner ]
--  DA_Skin_Bob_Spinner exists, complete ("Marcel Bob", SetSkin delegate), but
--  is referenced nowhere: orphan asset, never hooked up by the devs.
--
--  ADDING TO THE TArray WORKS (verified: 1 -> 2 entries, read back correctly),
--  BUT THE DISPLAY DOES NOT CHANGE: the list is built in C++ when the options
--  screen is created, and NO rebuild function is exposed
--  (UOptionMenuScreen has only 5 UFUNCTION, all navigation; UOptionSubsystem
--  only exposes GetOption). Tried afterward AND at startup: no effect.
--  => So we act directly on the mesh. 'skin menu' keeps the attempt, for the
--     record, but it changes nothing in the UI.
--
--  ---------------------------------------------------------------------------
--  UE4SS PITFALLS ALREADY PAID FOR — DO NOT REPEAT THEM
--   1. `Ar` is valid ONLY inside the SYNCHRONOUS body of the handler (else AV 0x8).
--   2. A UFUNCTION is NOT a Lua `function`: never test the type.
--   3. Never pass a raw Lua string to an FName/FText parameter (AV 0x70).
--      => we use SetMaterial(index, mat), NOT SetMaterialByName(FName, mat).
-- ============================================================================

local UEHelpers = require("UEHelpers")

-- ============================================================================
--  STARTUP APPLICATION — driven by the launcher (fe_launcher/core/skins.py)
--  These constants are rewritten by the launcher; do not rename the keys.
--  The mod normally activates ONLY via the F10 console; this block lets you
--  apply a skin as soon as the level loads, without typing a command.
-- ============================================================================
local BOOT_MESH    = "none"    -- mesh alias to apply at startup, or "none"
local BOOT_SKIN    = -1        -- One skin to apply (0-4), or -1 to do nothing
local BOOT_OUTLINE = "keep"    -- "keep" | "off" | "on": outline state at startup
local BOOT_HIDE_STICK  = false -- true = hide the stick (BP_Stick_C) at startup
local BOOT_HIDE_HAIR   = false -- true = hide the curler/hair (BP_Bigoudi_C) at startup
local BOOT_DELAY_MS = 4000     -- delay before applying (lets the pawn load)

local SKIN_BASE = "/Game/Art/Character/Hero/Skin"
local PARTS = {                      -- slot pattern -> material prefix
    { key = "Body", asset = "MI_MainCharaBody_Skin" },
    { key = "Head", asset = "MI_MainCharaHead_Skin" },
    { key = "Cape", asset = "MI_MainCharaCape_cinematic_Skin" },
}

-- ⚠️ The reapplication loops run every 1.5 s: without a safeguard they flood
-- the console and make it impossible to read a command
-- (observed 22/07). quietDepth > 0 = output suppressed. The loops run in
-- silent mode and emit only ONE line when their result CHANGES.
local quietDepth = 0
local function log(m)
    if quietDepth > 0 then return end
    print("[FESkins] " .. tostring(m) .. "\n")
end
local function loud(m) print("[FESkins] " .. tostring(m) .. "\n") end
local function quietly(fn)
    quietDepth = quietDepth + 1
    local ok, r = pcall(fn)
    quietDepth = quietDepth - 1
    if not ok then return nil end
    return r
end
local function say(Ar, m)            -- SYNCHRONOUS handler body ONLY
    log(m)
    if Ar then pcall(function() Ar:Log("[FESkins] " .. tostring(m)) end) end
end

-- ---------------------------------------------------------------------------
--  Helpers
-- ---------------------------------------------------------------------------
-- ⚠️ `o:IsValid()` CRASHES if `o` is not a UObject: "attempt to call a nil
-- value (method 'IsValid')". Real case (22/07): iterating with pairs() over the
-- TArray returned by K2_GetComponentsByClass yields non-object entries.
-- EVERY validity check goes through here.
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

-- The character's mesh is ACharacter's standard SkeletalMeshComponent
-- (CharacterMesh0, on SK_Hero_facial).
local function GetMesh()
    local pawn = GetPawn()
    if not pawn then return nil, "player not found" end
    local m
    pcall(function() m = pawn.Mesh end)
    if okObj(m) then return m, nil end
    return nil, "Mesh component not found on the pawn"
end

-- ⚠️ An asset whose character is NOT present in the area is not loaded into
-- memory: StaticFindObject fails until LoadAsset has succeeded
-- (observed 22/07: SKEL_Agent / SKEL_Rusher / SKEL_Ranged / SK_Builder
-- not found even though the paths are correct).
-- So we insist: LoadAsset in both its forms, then several read-backs.
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

-- ---------------------------------------------------------------------------
--  Slot discovery
--  We read each slot's current material and infer its nature (Body /
--  Head / Cape) from its name. More reliable than assuming an index order.
-- ---------------------------------------------------------------------------
local function ReadSlots()
    local mesh, err = GetMesh()
    if not mesh then return nil, err end
    local n = 0
    pcall(function() n = mesh:GetNumMaterials() end)
    if n == 0 then return nil, "no material slot (mesh not initialized yet?)" end

    local slots = {}
    for i = 0, n - 1 do                       -- engine index: 0-based
        local mat
        pcall(function() mat = mesh:GetMaterial(i) end)
        local nm = ShortName(mat)
        local part = nil
        for _, p in ipairs(PARTS) do
            if string.find(nm, p.key, 1, true) then part = p.key break end
        end
        slots[#slots + 1] = { index = i, mat = mat, name = nm, part = part }
    end
    return slots, nil
end

-- ---------------------------------------------------------------------------
--  Memory of the original materials (for 'skin reset')
-- ---------------------------------------------------------------------------
local original = nil

local function RememberOriginal(slots)
    if original then return end
    original = {}
    for _, s in ipairs(slots) do original[s.index] = s.mat end
    log("original materials saved (" .. #slots .. " slots)")
end

-- ---------------------------------------------------------------------------
--  Applying a skin
-- ---------------------------------------------------------------------------
local current = nil       -- index of the applied skin, or nil

local function ApplySkin(n)
    local mesh, err = GetMesh()
    if not mesh then return false, err end
    local slots, err2 = ReadSlots()
    if not slots then return false, err2 end
    RememberOriginal(slots)

    -- Resolves the 3 materials of the requested skin.
    local mats = {}
    for _, p in ipairs(PARTS) do
        local path = SKIN_BASE .. n .. "/" .. p.asset .. n
        local m = Resolve(path)
        if m then mats[p.key] = m else log("  not found: " .. path) end
    end
    if not next(mats) then return false, "no material of Skin" .. n .. " could be loaded" end

    local applied, skipped = 0, 0
    for _, s in ipairs(slots) do
        local target = s.part and mats[s.part] or nil
        if target then
            if pcall(function() mesh:SetMaterial(s.index, target) end) then
                applied = applied + 1
            else
                log("  SetMaterial failed on slot " .. s.index)
            end
        else
            skipped = skipped + 1
        end
    end
    if applied == 0 then return false, "no slot could be matched (try 'skin slots')" end
    current = n
    return true, applied .. " slot(s) applied, " .. skipped .. " skipped"
end

local function ResetSkin()
    if not original then return false, "no original state saved" end
    local mesh, err = GetMesh()
    if not mesh then return false, err end
    local n = 0
    for i, mat in pairs(original) do
        if mat and pcall(function() mesh:SetMaterial(i, mat) end) then n = n + 1 end
    end
    current = nil
    return true, n .. " slot(s) restored"
end

-- ============================================================================
--  BOB — the "Marcel Bob" skin
--
--  The DA_Skin_Bob_Spinner spinner (orphan, see header) announces a
--  "Marcel Bob" skin. The corresponding assets do exist:
--      MI_BobSkin_Mustache / MM_Bob_Mustache   (materials)
--      SKEL_Bob_Mime                            (dedicated mesh)
--  versus MI_BobSkin_body / SKEL_Bob for the default version.
--  => Marcel Bob = Bob as a mustachioed mime.
--
--  By default we change ONLY the materials (reversible, no risk to the
--  animation). The mesh swap is behind 'skin bob mime', explicit:
--  SKEL_Bob_Mime should share SKEL_Bob_Skeleton, but this is not verified.
-- ============================================================================
local BOB_BASE    = "/Game/Art/Character/Bob/"
local BOB_CLASSES = { "BP_Bob_Critter_C", "BP_Bob_Critter_Lava_C", "BP_Bob_Critter_Waste_C" }

local bobOriginalMats = nil     -- { [actorFullName] = { [slot] = mat } }
local bobOriginalMesh = nil     -- { [actorFullName] = skinnedAsset }
local bobMode         = nil     -- nil | "mime" | "standard" (for the lock)

-- ⚠️ DEDUPLICATION MANDATORY: BP_Bob_Critter_Lava_C and _Waste_C INHERIT from
-- BP_Bob_Critter_C, so FindAllOf on the parent class also returns the
-- children. Without this filter we process the same actor several times (seen
-- in game: "2 Bob found" when there was only one).
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

local function GetBobMesh(actor)
    local m
    pcall(function() m = actor.Mesh end)
    if okObj(m) then return m end
    -- Fallback: first SkeletalMeshComponent found on the actor.
    pcall(function()
        local comps = actor:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.SkeletalMeshComponent"))
        if comps then pcall(function() for _, c in pairs(comps) do if okObj(c) then m = c break end end end) end
    end)
    return okObj(m) and m or nil
end

-- ⚠️ LESSON FROM IN-GAME TESTING (22/07): Bob's slot layout is
--      [0] MI_GlassSimple_EyeBob            -> eyes
--      [1] MI_BobSkin_body / MI_CharacterEnemy_Critter_<element>  -> BODY
--      [2] MM_Bob_Mustache                  -> MUSTACHE (dedicated mesh section)
-- MI_BobSkin_Mustache is therefore the MUSTACHE material, not a body skin.
-- Applying it to the body gives nothing coherent (tested, nonsensical result).
-- "Marcel Bob" = the SKEL_Bob_Mime MESH, not a material swap.
--
--   mode "mime"     -> swaps the mesh to SKEL_Bob_Mime (the real Marcel Bob)
--   mode "standard" -> puts the body back on MI_BobSkin_body (normalizes an
--                      elemental variant back to the base Bob)
-- keepMats = true -> after the mesh swap, we RESTORE the materials that were
-- in place before (the MIDs parameterized by the game), instead of purging the overrides.
-- Tested hypothesis: raw MI_BobSkin_body renders BLACK because its parameters are
-- injected at runtime by the game; the original MIDs, on the other hand, are complete.
-- The skeleton is shared (SKEL_Bob_Skeleton), so the swap is legitimate.
local function ApplyBobSkin(mode, alsoMesh, keepMats)
    local actors = GetBobActors()
    if #actors == 0 then return false, "no Bob found (not loaded in this area?)" end

    local mat = (mode == "standard") and Resolve(BOB_BASE .. "MI_BobSkin_body") or nil
    local mesh = alsoMesh and Resolve(BOB_BASE .. "SKEL_Bob_Mime") or nil
    if alsoMesh and not mesh then log("  SKEL_Bob_Mime not found") end
    if not mat and not mesh then return false, "nothing to apply (neither material nor mesh resolved)" end

    bobOriginalMats = bobOriginalMats or {}
    bobOriginalMesh = bobOriginalMesh or {}

    local touched, slots = 0, 0
    for _, a in ipairs(actors) do
        local comp = GetBobMesh(a)
        if comp then
            local key = Name(a)
            local n = 0
            pcall(function() n = comp:GetNumMaterials() end)

            if not bobOriginalMats[key] then       -- remember before touching
                bobOriginalMats[key] = {}
                for i = 0, n - 1 do
                    local cur
                    pcall(function() cur = comp:GetMaterial(i) end)
                    bobOriginalMats[key][i] = cur
                end
                pcall(function() bobOriginalMesh[key] = comp:GetSkinnedAsset() end)
            end

            -- ⚠️ The materials in place are MID_ created at runtime by the
            -- game (the pawn's DynamicMaterials variable): their names are
            -- "MID_<material>_<number>", NOT the asset name. Searching for
            -- "BobSkin" therefore matched nothing (seen in game).
            -- Rule adopted: we replace everything EXCEPT the eyes and the mustache,
            -- which are distinct mesh sections to keep.
            -- Materials: only in "standard" mode, and only on the
            -- BODY (neither the eyes nor the mustache, which are dedicated sections).
            if mat then
                for i = 0, n - 1 do
                    local cur
                    pcall(function() cur = comp:GetMaterial(i) end)
                    local nm = ShortName(cur)
                    local isEye  = string.find(nm, "Eye", 1, true) ~= nil
                    local isTash = string.find(nm, "Mustache", 1, true) ~= nil
                    if not isEye and not isTash then
                        if pcall(function() comp:SetMaterial(i, mat) end) then
                            slots = slots + 1
                            log("    slot " .. i .. " : " .. nm .. " -> " .. ShortName(mat))
                        end
                    end
                end
            end

            if mesh then
                local before = "?"
                pcall(function() before = ShortName(comp:GetSkinnedAsset()) end)
                local called = pcall(function() comp:SetSkinnedAssetAndUpdate(mesh, true) end)
                -- ⚠️ READ-BACK MANDATORY: SetSkinnedAssetAndUpdate does NOT raise
                -- an error if the mesh is rejected (incompatible skeleton, etc.).
                -- A "successful" call therefore proves nothing — only the read-back does.
                local after = "?"
                pcall(function() after = ShortName(comp:GetSkinnedAsset()) end)
                log("    mesh : " .. before .. " -> " .. after
                    .. (called and "" or "  (call refused)"))
                if after == before then
                    log("    !! the mesh DID NOT CHANGE in the data: incompatible skeleton,")
                    log("       or the game reimposes it. Try 'skin lock'.")
                else
                    -- ⚠️ After a mesh swap, the material OVERRIDES set on the
                    -- old indices STAY in place. Since the new geometry does not
                    -- have the same section split, some slots end up with an
                    -- unsuitable or empty material -> BLACK rendering
                    -- (seen in game on 22/07 on the mane).
                    -- Fix: restore the materials the mesh declares itself.
                    -- Reading USkeletalMesh:GetMaterials() gives nothing usable
                    -- here (array of FSkeletalMaterial structs: indexing
                    -- fails from Lua, tested -> 0 retrieved).
                    -- So we PURGE the overrides: without an override, the component
                    -- falls back to the materials the mesh carries natively.
                    local cleared, nn = 0, 0
                    pcall(function() nn = comp:GetNumMaterials() end)
                    if keepMats and bobOriginalMats[key] then
                        -- We restore the original MIDs onto the new geometry.
                        for i = 0, nn - 1 do
                            local om = bobOriginalMats[key][i]
                            if om and pcall(function() comp:SetMaterial(i, om) end) then
                                cleared = cleared + 1
                            end
                        end
                        log("    original materials restored: " .. cleared .. "/" .. nn)
                    else
                        for i = 0, nn - 1 do
                            if pcall(function() comp:SetMaterial(i, nil) end) then cleared = cleared + 1 end
                        end
                        log("    overrides purged: " .. cleared .. "/" .. nn)
                    end
                    for i = 0, nn - 1 do
                        local cur
                        pcall(function() cur = comp:GetMaterial(i) end)
                        log("      [" .. i .. "] " .. ShortName(cur))
                    end
                end
            end
            touched = touched + 1
        end
    end
    if slots == 0 and not mesh then
        return false, touched .. " Bob found but nothing was applied"
    end
    bobMode = mode
    return true, touched .. " Bob" .. (slots > 0 and (", " .. slots .. " slot(s)") or "") .. (mesh and " + mesh mime" or "")
end

-- ⚠️ The original memory is lost if the mod's Lua state is reloaded (copying
-- main.lua over during a session). We can, however, restore the base mesh
-- without it: SKEL_Bob is an asset, we resolve it directly.
local function ResetBob()
    local fallbackMesh = Resolve(BOB_BASE .. "SKEL_Bob")
    if not bobOriginalMats then
        if not fallbackMesh then return false, "no original memory and SKEL_Bob not resolved" end
        local k = 0
        for _, a in ipairs(GetBobActors()) do
            local comp = GetBobMesh(a)
            if comp then
                pcall(function() comp:SetSkinnedAssetAndUpdate(fallbackMesh, true) end)
                local nn = 0
                pcall(function() nn = comp:GetNumMaterials() end)
                for i = 0, nn - 1 do pcall(function() comp:SetMaterial(i, nil) end) end
                k = k + 1
            end
        end
        bobMode = nil
        return true, k .. " Bob restored to SKEL_Bob (fallback, no original memory)"
    end
    local n = 0
    for _, a in ipairs(GetBobActors()) do
        local comp = GetBobMesh(a)
        local key = Name(a)
        if comp and bobOriginalMats[key] then
            for i, mat in pairs(bobOriginalMats[key]) do
                if mat and pcall(function() comp:SetMaterial(i, mat) end) then n = n + 1 end
            end
            local om = bobOriginalMesh and bobOriginalMesh[key]
            if om then pcall(function() comp:SetSkinnedAssetAndUpdate(om, true) end) end
        end
    end
    bobMode = nil
    return true, n .. " slot(s) restored on Bob"
end

-- ============================================================================
--  REPLACE ONE'S MODEL with any mesh ALREADY IN THE GAME
--
--  Same technique as for Bob: SetSkinnedAssetAndUpdate + read-back + purge
--  of the overrides. Works because the assets are already cooked and loaded.
--
--  ⚠️ SKELETON LIMITATION: One uses SKEL_Hero_facial_Skeleton. A mesh built
--  on ANOTHER skeleton (Bob, Rahne, enemies…) will be rendered, but the animation
--  won't follow: Unreal remaps bones BY NAME, so if the names differ the
--  model stays frozen, in T-pose or deformed. Only SK_Hero_facial_optimization
--  shares One's skeleton (and therefore looks just like him feature for feature).
--  In other words: it's worth trying, not guaranteed. 'skin mesh reset' restores.
-- ============================================================================
local MESHES = {
    { "bob",       "/Game/Art/Character/Bob/SKEL_Bob",                          "Bob" },
    { "mime",      "/Game/Art/Character/Bob/SKEL_Bob_Mime",                     "Marcel Bob" },
    { "rahne",     "/Game/Art/Character/Rahne/SK_Rahne_facial",                 "Rahne" },
    { "agent",     "/Game/Art/Character/Agent/SKEL_Agent",                      "Agent" },
    { "critter",   "/Game/Art/Character/Critter/SKEL_Critter",                  "Critter" },
    { "builder",   "/Game/Art/Character/Builder/SK_Builder",                    "Builder" },
    { "kheleb",    "/Game/Art/Character/Kheleb/SKEL_Kheleb",                    "Kheleb" },
    { "ranged",    "/Game/Art/Character/Ranged/SKEL_Ranged",                    "Ranged" },
    { "rusher",    "/Game/Art/Character/Rusher/SKEL_Rusher",                    "Rusher" },
    -- ⚠️ SK_BungeeMan is only 12 KB: it is NOT the mesh (applying it set the
    -- character to nil, hence invisible). The real one is SKM_BungeeMan (696 KB).
    { "bungee",    "/Game/Art/Character/BungeeMan/SKM_BungeeMan",               "BungeeMan" },
    { "wonder",    "/Game/Art/Character/LastWonder/SKEL_LastWonder_Step01",     "Last Wonder" },
    { "wonder2",   "/Game/Art/Character/LastWonder/SKEL_LastWonder_Step02",     "Last Wonder (2)" },
    { "wonder4",   "/Game/Art/Character/LastWonder/SKEL_LastWonder_Step04",     "Last Wonder (4)" },
    { "wonder5",   "/Game/Art/Character/LastWonder/SKEL_LastWonder_Step05",     "Last Wonder (5)" },
    { "disappear", "/Game/Art/Character/Disappear/SKEL_Disappear",              "Disappear" },
    { "cine",      "/Game/Art/Character/Builder/SK_BuilderCINEMATIC",           "Builder (cinematic)" },
    { "mannequin", "/Game/SoStylized/Demo/Pawn/Mannequin/Character/Mesh/SK_Mannequin", "Mannequin Unreal" },
    { "hat",       "/Game/Art/Character/Rahne/SK_Rahne_hat",                    "Rahne's hat (gag)" },
    -- ⚠️ EXTERNAL ASSET: exists ONLY if the custom pak is mounted in Content/Paks/.
    -- Resolve() will fail cleanly as long as that is not the case.
    -- Path captured via "Copy reference" in the UE 5.6 editor:
    --   /Script/Engine.SkeletalMesh'/Game/Test_Alien-Animal-Blender_2_81.Test_Alien-Animal-Blender_2_81'
    -- Mind the mix of dashes/underscores: Test_Alien-Animal-Blender_2_81
    { "alien",     "/Game/Test_Alien-Animal-Blender_2_81",                      "Alien Animal (custom pak)" },
    { "one",       "/Game/Art/Character/Hero/Hero_Facial_Final/SK_Hero_facial", "One (original)" },
    { "hero",      "/Game/Art/Character/Hero/Hero_Facial_Final/SK_Hero_facial", "One (alias)" },
}

local oneOriginalMesh = nil

-- ⚠️ FORWARD DECLARATIONS: SwapOneMesh (below) calls these functions, but
-- they are DEFINED AFTER it. Without these lines, Lua compiles them as
-- globals and they are nil at runtime
-- ("attempt to call a nil value (global 'HideStrayComponents')", seen on 22/07).
local ListPawnMeshComponents, ClassOf, HideStrayComponents, UnhideStrayComponents
local HideAttachedActors, UnhideAttachedActors
local HideActorsByClass, ListNearbyActors, KNOWN_ATTACHMENTS
-- State tables: declared HERE because SwapOneMesh (below) uses them,
-- while their original section comes after it.
local hidden, hiddenActors = {}, {}
local HandleOverlay
-- OUTLINE module (black outline): declared HERE because HandleOverlay and the
-- maintenance loop call them before their definition (pitfall g).
local GetOverlayComp, CollectOverlaySMC, ReadState, DumpState
local KillOutline, RestoreOutline, DiagOutline
local outlineLocked = false
local meshSwapTarget = nil     -- mesh currently forced, nil if none

-- Finds an entry by its alias (column 1), then by its label.
local function FindEntry(list, key)
    key = string.lower(key or "")
    if key == "" then return nil end
    for _, e in ipairs(list) do
        if string.lower(e[1]) == key then return e end
    end
    for _, e in ipairs(list) do
        if string.lower(e[3] or "") == key then return e end
    end
    return nil
end

local function SwapOneMesh(entry)
    local mesh, err = GetMesh()
    if not mesh then return false, err end
    local target = Resolve(entry[2])
    if not target then return false, "mesh not found: " .. entry[2] end

    if not oneOriginalMesh then
        pcall(function() oneOriginalMesh = mesh:GetSkinnedAsset() end)
        log("One's original mesh saved: " .. ShortName(oneOriginalMesh))
    end

    local before = "?"
    pcall(function() before = ShortName(mesh:GetSkinnedAsset()) end)
    pcall(function() mesh:SetSkinnedAssetAndUpdate(target, true) end)
    local after = "?"
    pcall(function() after = ShortName(mesh:GetSkinnedAsset()) end)
    log("  mesh : " .. before .. " -> " .. after)
    if after == before then
        return false, "the mesh did NOT change (refused by the engine)"
    end

    -- Purge the overrides, otherwise One's materials stay stuck on the
    -- new geometry and some sections render black (cf. Bob).
    local nn = 0
    pcall(function() nn = mesh:GetNumMaterials() end)
    for i = 0, nn - 1 do pcall(function() mesh:SetMaterial(i, nil) end) end
    log("  overrides purged: " .. nn)
    for i = 0, nn - 1 do
        local cur
        pcall(function() cur = mesh:GetMaterial(i) end)
        log("    [" .. i .. "] " .. ShortName(cur))
    end

    -- Hair, stick…: pawn components AND attached actors (the hair is
    -- a ChildActor, invisible to K2_GetComponentsByClass).
    -- ⚠️ THE "BLACK ONE" THAT FOLLOWS THE PLAYER: the pawn carries a
    -- BP_OverlayMeshComponent (cf. UOverlayMeshComponent in the binary) that renders
    -- a COPY of the character. It stays on SK_Hero_facial after the swap, hence
    -- a dark double stuck to the player (seen 22/07).
    -- We apply the SAME mesh to it, and failing that we hide it.
    HandleOverlay(target)

    local h = HideStrayComponents(mesh)
    local a = HideAttachedActors() + HideActorsByClass(KNOWN_ATTACHMENTS, true)
    meshSwapTarget = target        -- enables permanent maintenance (see the loop)
    return true, entry[3] .. " applied (" .. nn .. " slots, "
                 .. h .. " component(s) + " .. a .. " actor(s) hidden)"
end

-- ---------------------------------------------------------------------------
--  One's ancillary components (hair, stick…)
--
--  These are components DISTINCT from the main mesh, attached to bones of
--  One's skeleton. After a model swap, those bones no longer exist on the
--  new geometry: the components fall back to the pawn's origin and stay
--  visible AT THE PLAYER'S FEET (seen in game on 22/07 with Rahne).
--  So we hide them, and 'skin mesh reset' shows them again.
-- ---------------------------------------------------------------------------
-- (hidden: declared above)

-- ⚠️ Querying SkeletalMeshComponent + StaticMeshComponent IS NOT ENOUGH:
-- UE5's hair is a GroomComponent, and other accessories may
-- use yet other classes (seen on 22/07: One's hair and stick
-- stayed visible even though nothing was hidden).
-- UPrimitiveComponent is the parent class of EVERYTHING that renders on screen.
ListPawnMeshComponents = function()
    local pawn = GetPawn()
    if not pawn then return {} end
    local out, seen = {}, {}
    local cls = StaticFindObject("/Script/Engine.PrimitiveComponent")
    if not cls then return out end
    local comps
    pcall(function() comps = pawn:K2_GetComponentsByClass(cls) end)
    if not comps then return out end

    local function add(c)
        if okObj(c) then
            local k = Name(c)
            if not seen[k] then seen[k] = true; out[#out + 1] = c end
        end
    end

    -- Path 1: TArray API (the return is a TArray, not a Lua table).
    local n = 0
    pcall(function() n = comps:GetArrayNum() end)
    if n and n > 0 then
        for i = 1, n do
            local c
            pcall(function() c = comps[i] end)
            add(c)
        end
    else
        -- Path 2: fallback, in case UE4SS returns a classic table.
        pcall(function()
            for _, c in pairs(comps) do add(c) end
        end)
    end
    return out
end

-- Class name of a component, for diagnostics.
ClassOf = function(o)
    local n = "?"
    pcall(function() n = o:GetClass():GetFName():ToString() end)
    if n == "?" then pcall(function() n = o:GetClass():GetFullName() end) end
    return n
end

-- ---------------------------------------------------------------------------
--  ATTACHED ACTORS (hair, stick…)
--
--  ⚠️ One's hair is NOT a component of the pawn: it is a
--  ChildActorComponent (`BP_Bigoudi`, cf. Art/Character/Hair/Bigoudi/), so a
--  SEPARATE ACTOR. K2_GetComponentsByClass only returns the PAWN's components and
--  never sees it — hence "0 component hidden" while the hair
--  stayed on screen (22/07).
--  The game does the same thing when switching to water form: everything disappears.
--  So we go through GetAttachedActors + SetActorHiddenInGame.
--  (GetChildActor is NOT exposed; SetActorHiddenInGame and GetAttachedActors are.)
-- ---------------------------------------------------------------------------
-- (hiddenActors: declared above)

-- ⚠️ Neither K2_GetComponentsByClass nor GetAttachedActors return the hair
-- (seen 22/07: 0 component, 0 actor). BP_Bigoudi is a VFX ChildActor
-- (Art/VFX/Bigoudi/, Niagara NS_Bigoudi): so we look for it by its CLASS,
-- which does not depend on any enumeration.
-- Identified in game (22/07) via 'skin mesh near':
--   BP_Bigoudi_C = the hair (VFX ChildActor)   ✅ hiding confirmed
--   BP_Stick_C   = One's stick
KNOWN_ATTACHMENTS = { "BP_Bigoudi_C", "BP_Stick_C" }

HideActorsByClass = function(classes, hide)
    local n = 0
    for _, cls in ipairs(classes) do
        local list
        pcall(function() list = FindAllOf(cls) end)
        if list then
            for _, a in pairs(list) do
                if isRealObject(a) then
                    if pcall(function() a:SetActorHiddenInGame(hide) end) then
                        n = n + 1
                        if hide then hiddenActors[#hiddenActors + 1] = a end
                        log("    " .. (hide and "hidden" or "shown") .. " : " .. ShortName(a))
                    end
                end
            end
        end
    end
    return n
end

-- Discovery: actors very close to the player (the stick is one of them).
ListNearbyActors = function(radius)
    local pawn = GetPawn()
    if not pawn then return {} end
    local ploc
    pcall(function() ploc = pawn:K2_GetActorLocation() end)
    if not ploc then return {} end
    local out = {}
    local all
    pcall(function() all = FindAllOf("Actor") end)
    if not all then return out end
    for _, a in pairs(all) do
        if isRealObject(a) and Name(a) ~= Name(pawn) then
            local l
            pcall(function() l = a:K2_GetActorLocation() end)
            if l then
                local dx, dy, dz = l.X - ploc.X, l.Y - ploc.Y, l.Z - ploc.Z
                local d = math.sqrt(dx * dx + dy * dy + dz * dz)
                if d < radius then out[#out + 1] = { actor = a, dist = d } end
            end
        end
    end
    table.sort(out, function(x, y) return x.dist < y.dist end)
    return out
end

-- ---------------------------------------------------------------------------
--  ONE'S OUTLINE / BLACK SILHOUETTE
--
--  ACTUAL MECHANISM (established statically on 22/07, cf. .utoc + PDB + decomp):
--  the outline is NOT an overlay material and NOT the custom depth. It is an
--  INVERTED SHELL: at BeginPlay, BP_OverlayMeshComponent DUPLICATES the
--  character's mesh by creating additional USkeletalMeshComponent
--  (GenerateSkeletalMeshes), to which it applies a MID derived from
--  MM_OutlineOverlay (TwoSided + Masked + Unlit + Thickness… = normal
--  extrusion, color 0x101010, hence the black).
--
--  WHY THE OLD CODE FAILED (two causes, the 2nd is the real one):
--   1. UOverlayMeshComponent derives from UActorComponent, NOT from USceneComponent:
--      it has NEITHER GetChildrenComponents NOR SetHiddenInGame. The pcalls
--      "succeeded" without doing anything (pitfall h: a call without an error
--      proves nothing).
--   2. ABOVE ALL: the doubles are attached to the character's "Mesh" component
--      (K2_AttachToComponent). They are SIBLINGS of the manager component, never
--      its children. Descending its tree could find nothing.
--
--  SO WE ACT ON THE SkeletalMeshComponent THEMSELVES, collected from the UNION
--  of three sources (none is guaranteed populated at runtime):
--      ov.SkeletalsOverlay                       (Blueprint variable)
--      ov.OutlineOverlay.SkeletalMeshComponents  (native UOverlayMesh)
--      ov.StatusOverlay.SkeletalMeshComponents   (native UOverlayMesh)
--
--  ⚠️ The Blueprint bytecode is not readable (FModel does not export it): we
--  don't know which of these arrays is actually filled. The logs from
--  CollectOverlaySMC will settle it on the first in-game try.
-- ---------------------------------------------------------------------------

-- State SAVED BEFORE any write, for 'skin outline on'.
-- outlineSaved.comps = { { smc, vis, hid, cd } }   outlineSaved.ov = { … }
local outlineSaved = nil

GetOverlayComp = function()
    local pawn = GetPawn()
    if not pawn then return nil end
    local ov
    pcall(function() ov = pawn.BP_OverlayMeshComponent end)
    if okObj(ov) then return ov end
    -- Fallback: scan by class name. Dedup on GetFullName (pitfall e:
    -- FindAllOf / the enumerations also return subclasses).
    local seen = {}
    for _, c in ipairs(ListPawnMeshComponents()) do
        if okObj(c) then
            local fn = Name(c)
            if not seen[fn] then
                seen[fn] = true
                local sig = (ClassOf(c) or "") .. " " .. ShortName(c)
                if string.find(sig, "OverlayMeshComponent", 1, true) then return c end
            end
        end
    end
    return nil
end

-- Union of the three sources, deduplicated on GetFullName.
CollectOverlaySMC = function(ov)
    local out, seen = {}, {}
    local function push(o, src)
        if not okObj(o) then return end
        local fn = Name(o)
        if seen[fn] then return end
        seen[fn] = true
        out[#out + 1] = o
        log("      + " .. src .. " : " .. ShortName(o) .. " [" .. (ClassOf(o) or "?") .. "]")
    end
    -- UE4SS TArrays are read via GetArrayNum()+[i]; pairs() fallback if needed.
    local function eatArray(arr, src)
        if arr == nil then log("      (" .. src .. " : nil)") return end
        local cnt = 0
        pcall(function() cnt = arr:GetArrayNum() end)
        if cnt and cnt > 0 then
            for i = 1, cnt do
                local e
                pcall(function() e = arr[i] end)
                push(e, src)
            end
        else
            pcall(function() for _, e in pairs(arr) do push(e, src) end end)
        end
    end

    local a
    pcall(function() a = ov.SkeletalsOverlay end)
    eatArray(a, "SkeletalsOverlay")

    for _, slot in ipairs({ "OutlineOverlay", "StatusOverlay" }) do
        local om
        pcall(function() om = ov[slot] end)
        if okObj(om) then
            local arr
            pcall(function() arr = om.SkeletalMeshComponents end)
            eatArray(arr, slot .. ".SkeletalMeshComponents")
        else
            log("      (" .. slot .. " : nil/invalid)")
        end
    end
    return out
end

-- Read-back of a component. Depending on the UE4SS version, visibility is exposed
-- as bVisible or only via IsVisible(): we try both. A "?" in the
-- log means "the read-back proved nothing", NOT "the write succeeded".
ReadState = function(smc)
    local vis, hid, cd, ass = "?", "?", "?", "?"
    pcall(function() vis = tostring(smc.bVisible) end)
    if vis == "?" or vis == "nil" then pcall(function() vis = tostring(smc:IsVisible()) end) end
    pcall(function() hid = tostring(smc.bHiddenInGame) end)
    pcall(function() cd = tostring(smc.bRenderCustomDepth) end)
    pcall(function() ass = ShortName(smc:GetSkinnedAsset()) end)
    return vis, hid, cd, ass
end

-- Logs the list's state and RETURNS the number still visible.
-- It is this value that decides whether we step down a level in the cascade.
DumpState = function(list, tag)
    local alive = 0
    for _, smc in ipairs(list) do
        if okObj(smc) then
            local v, h, cd, a = ReadState(smc)
            local ko = (v ~= "false" and h ~= "true")
            if ko then alive = alive + 1 end
            log("      [" .. tag .. "] " .. ShortName(smc)
                .. "  bVisible=" .. v .. "  bHiddenInGame=" .. h
                .. "  customDepth=" .. cd .. "  asset=" .. a
                .. (ko and "   << STILL VISIBLE" or ""))
        end
    end
    log("      [" .. tag .. "] still visible: " .. alive .. " / " .. #list)
    return alive
end

-- Saves the original state ONLY ONCE, before the first write.
local function SaveOutlineState(ov, smcs)
    if outlineSaved then return end
    outlineSaved = { comps = {}, ov = {} }
    for _, smc in ipairs(smcs) do
        local v, h, cd = ReadState(smc)
        outlineSaved.comps[#outlineSaved.comps + 1] =
            { smc = smc, vis = v, hid = h, cd = cd }
    end
    pcall(function() outlineSaved.ov.mdd = ov["Max Draw Distance"] end)
    pcall(function() outlineSaved.ov.tick = ov.bTickEnabled end)
    pcall(function() outlineSaved.ov.one = ov.OwnerIsOne end)
    pcall(function() outlineSaved.ov.outMat = ov.OutlineMaterial end)
    pcall(function() outlineSaved.ov.staMat = ov.StatusMaterial end)
    log("  [outline] original state saved (" .. #outlineSaved.comps .. " component(s))")
end

-- ---------------------------------------------------------------------------
--  DIAGNOSTIC — modifies NOTHING
-- ---------------------------------------------------------------------------
DiagOutline = function()
    log("  [outline/diag] ---------------------------------------------")
    local pawn = GetPawn()
    if not pawn then log("  [outline/diag] player not found") return 0 end
    local ov = GetOverlayComp()
    if not okObj(ov) then
        log("  [outline/diag] BP_OverlayMeshComponent NOT FOUND on the pawn")
    else
        log("  [outline/diag] component = " .. ShortName(ov) .. " [" .. (ClassOf(ov) or "?") .. "]")
        for _, k in ipairs({ "OwnerIsOne", "bTickEnabled" }) do
            local v = "?"
            pcall(function() v = tostring(ov[k]) end)
            log("      ov." .. k .. " = " .. v)
        end
        local mdd = "?"
        pcall(function() mdd = tostring(ov["Max Draw Distance"]) end)
        log("      ov['Max Draw Distance'] = " .. mdd)
        for _, k in ipairs({ "OutlineMaterial", "StatusMaterial" }) do
            local m
            pcall(function() m = ov[k] end)
            log("      ov." .. k .. " = " .. ShortName(m))
        end
    end

    local smcs = {}
    if okObj(ov) then smcs = CollectOverlaySMC(ov) end
    log("  [outline/diag] " .. #smcs .. " overlay SkeletalMeshComponent")
    DumpState(smcs, "diag")

    -- Materials carried by the doubles: these are MID_ created at runtime,
    -- their name is NOT that of the MI_OutlineOne asset (pitfall f).
    for _, smc in ipairs(smcs) do
        local n = 0
        pcall(function() n = smc:GetNumMaterials() end)
        for i = 0, n - 1 do
            local m
            pcall(function() m = smc:GetMaterial(i) end)
            log("      mat " .. ShortName(smc) .. "[" .. i .. "] = " .. ShortName(m))
        end
    end

    -- The main mesh: custom depth = targeting system, NOT the silhouette.
    local mesh = GetMesh()
    if okObj(mesh) then
        local v, h, cd, a = ReadState(mesh)
        log("  [outline/diag] main Mesh " .. ShortName(mesh)
            .. " asset=" .. a .. " bVisible=" .. v .. " hidden=" .. h .. " customDepth=" .. cd)
        local ovm
        pcall(function() ovm = mesh:GetOverlayMaterial() end)
        log("      GetOverlayMaterial() = " .. ShortName(ovm) .. "  (ruled out: not the mechanism)")
    end

    -- Any other SkeletalMeshComponent of the pawn: "double" candidates.
    local mainFN = okObj(mesh) and Name(mesh) or "?"
    local seen = {}
    for _, c in ipairs(ListPawnMeshComponents()) do
        if okObj(c) then
            local fn = Name(c)
            if not seen[fn] and fn ~= mainFN
               and string.find(ClassOf(c) or "", "SkeletalMeshComponent", 1, true) then
                seen[fn] = true
                local v, h, cd, a = ReadState(c)
                log("      other SMC: " .. ShortName(c) .. " asset=" .. a
                    .. " bVisible=" .. v .. " hidden=" .. h .. " customDepth=" .. cd)
            end
        end
    end
    log("  [outline/diag] ---------------------------------------------")
    return #smcs
end

-- ---------------------------------------------------------------------------
--  REMOVAL — cascade E1 -> E6, each step gated by the READ-BACK
--  of the previous one (pitfall h). hard=true enables step 6, IRREVERSIBLE
--  until the level is reloaded.
-- ---------------------------------------------------------------------------
KillOutline = function(hard)
    local ov = GetOverlayComp()
    if not okObj(ov) then log("  [outline] BP_OverlayMeshComponent NOT FOUND") return 0 end
    log("  [outline] component = " .. ShortName(ov) .. " [" .. (ClassOf(ov) or "?") .. "]")

    local smcs = CollectOverlaySMC(ov)
    log("  [outline] " .. #smcs .. " overlay SkeletalMeshComponent collected")
    SaveOutlineState(ov, smcs)
    DumpState(smcs, "BEFORE")

    -- STEP 1 — the game's official path. UFUNCTION BlueprintCallable, a single
    -- BoolProperty parameter: no FName/FText risk (pitfall c).
    local ok1 = pcall(function() ov:SetOverlayHidden(true) end)
    log("  [outline] E1 SetOverlayHidden(true) call=" .. tostring(ok1))
    if #smcs > 0 and DumpState(smcs, "E1") == 0 then
        log("  [outline] fixed at step 1")
        return #smcs
    end

    -- STEP 2 — direct action on each double. Literal replica of
    -- UOverlayMesh::Deactivate (decomp: SetVisibility loop over the array).
    -- We CONTINUE even if it works: TagsChanged / UpdateOverlayByDistance
    -- may show them again.
    for _, smc in ipairs(smcs) do
        pcall(function() smc:SetVisibility(false, true) end)
        pcall(function() smc:SetHiddenInGame(true, true) end)
        pcall(function() smc:SetRenderCustomDepth(false) end)
    end
    log("  [outline] E2 SetVisibility/SetHiddenInGame on " .. #smcs .. " component(s)")
    if #smcs > 0 then DumpState(smcs, "E2") end

    -- STEP 3 — distance cull. ⚠️ the Blueprint variable's name CONTAINS
    -- SPACES: the bracket notation is MANDATORY.
    pcall(function() ov:SetMaxDrawDistance(1.0) end)
    pcall(function() ov["Max Draw Distance"] = 1.0 end)
    local mdd = "?"
    pcall(function() mdd = tostring(ov["Max Draw Distance"]) end)
    log("  [outline] E3 'Max Draw Distance' read back = " .. mdd)

    -- STEP 4 — block the REGENERATION (tick -> UpdateOverlayByDistance).
    -- ⚠️ We NEVER call GenerateSkeletalMeshes (FName parameter, and it
    -- would recreate the doubles) nor UpdateOverlayParameters with a raw string.
    pcall(function() ov:SetComponentTickEnabled(false) end)
    pcall(function() ov.OwnerIsOne = false end)
    local tick, one = "?", "?"
    pcall(function() tick = tostring(ov.bTickEnabled) end)
    pcall(function() one = tostring(ov.OwnerIsOne) end)
    log("  [outline] E4 bTickEnabled=" .. tick .. "  OwnerIsOne=" .. one)

    -- STEP 5 — safety net: any SkeletalMeshComponent of the pawn that is
    -- NOT the main Mesh and is still visible. This is the decisive step if
    -- the three arrays are empty.
    local pawn, mainMesh = GetPawn(), nil
    if pawn then pcall(function() mainMesh = pawn.Mesh end) end
    local mainFN = okObj(mainMesh) and Name(mainMesh) or "?"
    local extra, seen = 0, {}
    for _, c in ipairs(ListPawnMeshComponents()) do
        if okObj(c) then
            local fn = Name(c)
            if not seen[fn] and fn ~= mainFN
               and string.find(ClassOf(c) or "", "SkeletalMeshComponent", 1, true) then
                seen[fn] = true
                local v, h, cd, a = ReadState(c)
                if v ~= "false" and h ~= "true" then
                    log("      [E5] survivor " .. ShortName(c) .. " asset=" .. a)
                    if not outlineSaved.extra then outlineSaved.extra = {} end
                    outlineSaved.extra[#outlineSaved.extra + 1] =
                        { smc = c, vis = v, hid = h, cd = cd }
                    pcall(function() c:SetVisibility(false, true) end)
                    pcall(function() c:SetHiddenInGame(true, true) end)
                    local v2, h2 = ReadState(c)
                    log("      [E5] -> bVisible=" .. v2 .. "  bHiddenInGame=" .. h2)
                    extra = extra + 1
                end
            end
        end
    end
    log("  [outline] E5 " .. extra .. " extra component(s) processed")

    -- STEP 6 — NUCLEAR, only on 'skin outline hard'. Empties the geometry
    -- of the doubles, destroys the components, then neutralizes the material seed
    -- so that RegenerateMID recreates nothing opaque. IRREVERSIBLE.
    if hard then
        for _, smc in ipairs(smcs) do
            pcall(function() smc:SetSkinnedAssetAndUpdate(nil, true) end)
            local _, _, _, a = ReadState(smc)
            log("      [E6] " .. ShortName(smc) .. " asset after clearing = " .. a)
        end
        for _, smc in ipairs(smcs) do
            local nm = ShortName(smc)
            pcall(function() smc:DestroyComponent(nil) end)
            local still = "?"
            pcall(function() still = tostring(okObj(smc)) end)
            log("      [E6] DestroyComponent " .. nm .. " -> still valid=" .. still)
        end
        pcall(function() ov.OutlineMaterial = nil end)
        pcall(function() ov.StatusMaterial = nil end)
        local om, sm = "?", "?"
        pcall(function() om = ShortName(ov.OutlineMaterial) end)
        pcall(function() sm = ShortName(ov.StatusMaterial) end)
        log("      [E6] OutlineMaterial read back = " .. om .. "  StatusMaterial read back = " .. sm)
    end

    return #smcs
end

-- ---------------------------------------------------------------------------
--  RESTORATION — restores the state memorized BEFORE the first removal.
--  No effect on what step 6 destroyed (warn the user).
-- ---------------------------------------------------------------------------
RestoreOutline = function()
    if not outlineSaved then return false, "nothing to restore (outline never removed)" end
    local ov = GetOverlayComp()
    local n = 0

    local function put(rec)
        local smc = rec.smc
        if not okObj(smc) then
            log("      [restore] component destroyed, not restorable: " .. tostring(rec.hid))
            return
        end
        pcall(function() smc:SetVisibility(rec.vis ~= "false", true) end)
        pcall(function() smc:SetHiddenInGame(rec.hid == "true", true) end)
        pcall(function() smc:SetRenderCustomDepth(rec.cd == "true") end)
        local v, h = ReadState(smc)
        log("      [restore] " .. ShortName(smc) .. " -> bVisible=" .. v .. " hidden=" .. h)
        n = n + 1
    end

    for _, rec in ipairs(outlineSaved.comps) do put(rec) end
    for _, rec in ipairs(outlineSaved.extra or {}) do put(rec) end

    if okObj(ov) then
        pcall(function() ov:SetOverlayHidden(false) end)
        if outlineSaved.ov.mdd ~= nil then
            pcall(function() ov:SetMaxDrawDistance(outlineSaved.ov.mdd) end)
            pcall(function() ov["Max Draw Distance"] = outlineSaved.ov.mdd end)
        end
        pcall(function() ov:SetComponentTickEnabled(outlineSaved.ov.tick ~= false) end)
        if outlineSaved.ov.one ~= nil then pcall(function() ov.OwnerIsOne = outlineSaved.ov.one end) end
        if outlineSaved.ov.outMat ~= nil then pcall(function() ov.OutlineMaterial = outlineSaved.ov.outMat end) end
        if outlineSaved.ov.staMat ~= nil then pcall(function() ov.StatusMaterial = outlineSaved.ov.staMat end) end
        local mdd, tick, one = "?", "?", "?"
        pcall(function() mdd = tostring(ov["Max Draw Distance"]) end)
        pcall(function() tick = tostring(ov.bTickEnabled) end)
        pcall(function() one = tostring(ov.OwnerIsOne) end)
        log("      [restore] ov : MaxDrawDistance=" .. mdd .. " tick=" .. tick .. " OwnerIsOne=" .. one)
    end
    return true, n .. " component(s) restored"
end

-- Compatibility: the mesh swap and the maintenance loop still call
-- HandleOverlay. Aligning the doubles onto the new mesh did not work
-- (they are created once at BeginPlay from SK_Hero_facial): we remove them.
HandleOverlay = function(_target)
    return KillOutline(false)
end

HideAttachedActors = function()
    local pawn = GetPawn()
    if not pawn then return 0 end
    local list
    -- Depending on the build, UE4SS returns the output either as a return value or via the out param.
    pcall(function() list = pawn:GetAttachedActors(nil, true, true) end)
    if not list then pcall(function() list = pawn:GetAttachedActors() end) end
    if not list then return 0 end

    local n, cnt = 0, 0
    pcall(function() cnt = list:GetArrayNum() end)
    local function tryHide(a)
        if not okObj(a) then return end
        if Name(a) == Name(pawn) then return end
        if pcall(function() a:SetActorHiddenInGame(true) end) then
            hiddenActors[#hiddenActors + 1] = a
            n = n + 1
            log("    actor hidden: " .. ShortName(a))
        end
    end
    if cnt and cnt > 0 then
        for i = 1, cnt do
            local a
            pcall(function() a = list[i] end)
            tryHide(a)
        end
    else
        pcall(function() for _, a in pairs(list) do tryHide(a) end end)
    end
    return n
end

UnhideAttachedActors = function()
    local n = 0
    for _, a in ipairs(hiddenActors) do
        if okObj(a) and pcall(function() a:SetActorHiddenInGame(false) end) then n = n + 1 end
    end
    hiddenActors = {}
    return n
end

HideStrayComponents = function(mainMesh)
    local n = 0
    for _, c in ipairs(ListPawnMeshComponents()) do
        if Name(c) ~= Name(mainMesh) then
            local visible = true
            -- bHiddenInGame is a PROPERTY (dot access), not a method.
            pcall(function() visible = not c.bHiddenInGame end)
            if visible then
                if pcall(function() c:SetHiddenInGame(true, true) end) then
                    hidden[#hidden + 1] = c
                    n = n + 1
                    log("    hidden: " .. ShortName(c) .. "  [" .. ClassOf(c) .. "]")
                else
                    log("    FAILED to hide: " .. ShortName(c) .. "  [" .. ClassOf(c) .. "]")
                end
            end
        end
    end
    return n
end

UnhideStrayComponents = function()
    local n = 0
    for _, c in ipairs(hidden) do
        if okObj(c) and pcall(function() c:SetHiddenInGame(false, true) end) then
            n = n + 1
        end
    end
    hidden = {}
    return n
end

local function ResetOneMesh()
    local mesh, err = GetMesh()
    if not mesh then return false, err end
    local target = oneOriginalMesh
                or Resolve("/Game/Art/Character/Hero/Hero_Facial_Final/SK_Hero_facial")
    if not target then return false, "original mesh not found" end
    pcall(function() mesh:SetSkinnedAssetAndUpdate(target, true) end)
    local nn = 0
    pcall(function() nn = mesh:GetNumMaterials() end)
    for i = 0, nn - 1 do pcall(function() mesh:SetMaterial(i, nil) end) end
    meshSwapTarget = nil        -- stops the permanent maintenance
    HideActorsByClass(KNOWN_ATTACHMENTS, false)
    local u = UnhideStrayComponents()
    local ua = UnhideAttachedActors()
    return true, "One restored to " .. ShortName(target)
                 .. " (" .. u .. " component(s) + " .. ua .. " actor(s) shown again)"
end

-- ---------------------------------------------------------------------------
--  Lock: the pawn has a DynamicMaterials variable and the game can reapply
--  its own materials (form change, respawn…). This loop restores
--  the chosen skin. NO Ar here.
-- ---------------------------------------------------------------------------
local locked = false

-- ⚠️ Hiding ONCE does not hold: BP_Bigoudi is a ChildActor that the game
-- RECREATES (respawn, form change, streaming), and the overlay realigns
-- onto the original mesh. Hence a result that "works every other time"
-- (seen 22/07). So we reapply as long as a swap is active.
local lastAttachSig = nil
LoopAsync(1500, function()
    if meshSwapTarget then
        pcall(function()
            ExecuteInGameThread(function()
                local n = quietly(function()
                    local a = HideActorsByClass(KNOWN_ATTACHMENTS, true) or 0
                    local o = HandleOverlay(meshSwapTarget) or 0
                    return a .. "/" .. o
                end)
                if n and n ~= lastAttachSig then
                    lastAttachSig = n
                    loud("swap maintenance: " .. n .. " (actors/overlay)")
                end
            end)
        end)
    end
    return false
end)

-- Outline lock: if the game reimposes the silhouette (form change,
-- respawn, TagsChanged…), we relaunch the cascade. NO `Ar` here (pitfall a).
local lastOutlineSig = nil
LoopAsync(1500, function()
    if outlineLocked then
        pcall(function()
            ExecuteInGameThread(function()
                local r = quietly(function() return KillOutline(false) end)
                local sig = tostring(r)
                if sig ~= lastOutlineSig then
                    lastOutlineSig = sig
                    loud("outline lock: state -> " .. sig)
                end
            end)
        end)
    end
    return false
end)

LoopAsync(2000, function()
    if locked then
        pcall(function()
            ExecuteInGameThread(function()
                quietly(function()
                    if current then ApplySkin(current) end
                    -- Bob too: if the game reimposes its mesh/material, we restore it.
                    if bobMode then ApplyBobSkin(bobMode, bobMode == "mime") end
                end)
            end)
        end)
    end
    return false
end)

-- ---------------------------------------------------------------------------
--  "menu" attempt kept for the record (no effect on the display)
-- ---------------------------------------------------------------------------
local BASE_OPT = "/Game/Game/Option/DataAssets/Gameplay/Skin/"

local function AttachBobSpinner()
    local sub = Resolve(BASE_OPT .. "DA_Skin_SubSection")
    local bob = Resolve(BASE_OPT .. "DA_Skin_Bob_Spinner")
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
RegisterConsoleCommandGlobalHandler("skin", function(FullCommand, Parameters, Ar)
    local p = Parameters or {}
    local key = (p[1] and string.lower(p[1])) or ""

    if key == "slots" then
        local slots, err = ReadSlots()
        if not slots then say(Ar, "error: " .. tostring(err)); return true end
        say(Ar, #slots .. " material slot(s) on the player:")
        for _, s in ipairs(slots) do
            say(Ar, string.format("   [%d] %-40s -> %s", s.index, s.name, s.part or "(unmatched)"))
        end
        say(Ar, "current skin: " .. (current and ("Skin" .. current) or "original"))
        return true
    end

    if key == "reset" then
        say(Ar, "restoring original materials…")
        locked = false
        ExecuteInGameThread(function()          -- no Ar here
            local ok, msg = ResetSkin()
            log("reset -> " .. tostring(msg))
        end)
        return true
    end

    if key == "lock" then
        locked = not locked
        say(Ar, locked and "lock ON: the skin will be reapplied every 2 s."
                       or  "lock released.")
        return true
    end

    if key == "menu" then
        say(Ar, "attempting to wire in Bob's spinner…")
        say(Ar, "(reminder: the menu list is frozen at creation, the UI will not change)")
        ExecuteInGameThread(function()          -- no Ar here
            local ok, msg = AttachBobSpinner()
            log("menu -> " .. tostring(msg))
        end)
        return true
    end

    if key == "mesh" then
        local sub = (p[2] and string.lower(p[2])) or ""
        if sub == "" or sub == "list" then
            say(Ar, "available models (already in the game) — usage: skin mesh <alias>")
            for _, m in ipairs(MESHES) do
                say(Ar, string.format("   %-9s %s", m[1], m[3]))
            end
            say(Ar, "skin mesh reset  -> restores One")
            say(Ar, "⚠️ different skeleton = frozen or deformed model. That's expected.")
            return true
        end
        if sub == "near" then
            local r = tonumber(p[3]) or 300
            local near = ListNearbyActors(r)
            say(Ar, #near .. " actor(s) within " .. r .. " units:")
            for i = 1, math.min(#near, 25) do
                say(Ar, string.format("   %6.0f  %s", near[i].dist, ShortName(near[i].actor)))
            end
            return true
        end
        if sub == "hide" then
            local cls = p[3]
            if not cls then say(Ar, "usage: skin mesh hide <ClassName_C>"); return true end
            say(Ar, "hiding all " .. cls .. "…")
            ExecuteInGameThread(function()          -- no Ar here
                log("hidden: " .. HideActorsByClass({ cls }, true))
            end)
            return true
        end
        if sub == "comps" then
            local comps = ListPawnMeshComponents()
            say(Ar, #comps .. " mesh component(s) on the player:")
            for _, c in ipairs(comps) do
                local hid = "?"
                pcall(function() hid = tostring(c.bHiddenInGame) end)
                say(Ar, string.format("   %-34s [%s] hidden=%s", ShortName(c), ClassOf(c), hid))
            end
            return true
        end
        if sub == "show" then
            say(Ar, "showing hidden components again…")
            ExecuteInGameThread(function()          -- no Ar here
                log("shown again: " .. UnhideStrayComponents())
            end)
            return true
        end
        if sub == "reset" or sub == "off" then
            say(Ar, "restoring One's model…")
            ExecuteInGameThread(function()          -- no Ar here
                local ok, msg = ResetOneMesh()
                log("mesh reset -> " .. tostring(msg))
            end)
            return true
        end
        local entry = FindEntry(MESHES, sub)
        if not entry then say(Ar, "unknown: '" .. sub .. "' — type 'skin mesh list'"); return true end
        say(Ar, "replacing One's model with " .. entry[3] .. "…")
        ExecuteInGameThread(function()              -- no Ar here
            local ok, msg = SwapOneMesh(entry)
            log("skin mesh " .. sub .. " -> " .. (ok and msg or ("failed: " .. tostring(msg))))
        end)
        return true
    end

    if key == "bob" then
        local sub = (p[2] and string.lower(p[2])) or ""
        if sub == "off" or sub == "reset" then
            say(Ar, "restoring Bob…")
            ExecuteInGameThread(function()          -- no Ar here
                local ok, msg = ResetBob()
                log("bob off -> " .. tostring(msg))
            end)
            return true
        end
        if sub == "slots" then
            local actors = GetBobActors()
            say(Ar, #actors .. " Bob found")
            for _, a in ipairs(actors) do
                local comp = GetBobMesh(a)
                if comp then
                    local n = 0
                    pcall(function() n = comp:GetNumMaterials() end)
                    say(Ar, "  " .. ShortName(a) .. " : " .. n .. " slot(s)")
                    for i = 0, n - 1 do
                        local cur
                        pcall(function() cur = comp:GetMaterial(i) end)
                        say(Ar, string.format("     [%d] %s", i, ShortName(cur)))
                    end
                end
            end
            return true
        end
        -- 'skin bob'          -> mime (THIS is it, Marcel Bob: the mesh)
        -- 'skin bob standard' -> puts the body back on MI_BobSkin_body
        if sub == "standard" or sub == "body" then
            say(Ar, "Bob's body -> MI_BobSkin_body…")
            ExecuteInGameThread(function()          -- no Ar here
                local ok, msg = ApplyBobSkin("standard", false)
                log("skin bob standard -> " .. (ok and msg or ("failed: " .. tostring(msg))))
            end)
            return true
        end
        -- 'skin bob keep': mime mesh + original materials (MIDs parameterized by
        -- the game) instead of the mesh's raw materials, which render black.
        local keep = (sub == "keep" or sub == "mid")
        say(Ar, "Marcel Bob: swapping the mesh to SKEL_Bob_Mime"
                .. (keep and " (+ original materials kept)" or "") .. "…")
        ExecuteInGameThread(function()              -- no Ar here
            local ok, msg = ApplyBobSkin("mime", true, keep)
            log("skin bob -> " .. (ok and msg or ("failed: " .. tostring(msg))))
        end)
        return true
    end

    if key == "outline" then
        local sub = (p[2] and string.lower(p[2])) or ""

        if sub == "diag" then
            say(Ar, "outline diagnostic — nothing will be changed.")
            say(Ar, "full detail in the UE4SS CONSOLE WINDOW.")
            ExecuteInGameThread(function()          -- no Ar here
                local n = DiagOutline()
                log("outline diag -> " .. tostring(n) .. " overlay component(s)")
            end)
            return true
        end

        if sub == "on" then
            say(Ar, "restoring the outline…")
            outlineLocked = false
            ExecuteInGameThread(function()          -- no Ar here
                local ok, msg = RestoreOutline()
                log("outline on -> " .. tostring(msg))
            end)
            return true
        end

        if sub == "lock" then
            outlineLocked = not outlineLocked
            say(Ar, outlineLocked and "outline lock ON: removal rerun every 1.5 s."
                                  or  "outline lock released.")
            if outlineLocked then
                ExecuteInGameThread(function()      -- no Ar here
                    log("outline lock -> " .. tostring(KillOutline(false)) .. " component(s)")
                end)
            end
            return true
        end

        if sub == "" or sub == "off" or sub == "hard" then
            local hard = (sub == "hard")
            say(Ar, hard and "NUCLEAR outline removal (irreversible until the level reloads)…"
                          or  "outline removal (cascade E1→E5)…")
            say(Ar, "full detail in the UE4SS CONSOLE WINDOW.")
            ExecuteInGameThread(function()          -- no Ar here
                local n = KillOutline(hard)
                log("outline " .. (hard and "hard" or "off") .. " -> "
                    .. tostring(n) .. " overlay component(s) processed")
            end)
            return true
        end

        say(Ar, "usage: skin outline off | on | diag | lock | hard")
        return true
    end

    if key == "one" then
        local n = tonumber(p[2])
        if not n or n < 0 or n > 4 then
            say(Ar, "usage: skin one <0-4>   (0 = default, 1 = Hellgur, 2-4 = hidden)")
            return true
        end
        n = math.floor(n)
        say(Ar, "applying Skin" .. n .. "…")
        ExecuteInGameThread(function()          -- no Ar here
            local ok, msg = ApplySkin(n)
            log("skin one " .. n .. " -> " .. (ok and msg or ("failed: " .. tostring(msg))))
        end)
        return true
    end

    say(Ar, "ONE: skin one <0-4> | skin slots")
    say(Ar, "BOB: skin bob (mime mesh) | skin bob keep (mime + original materials)")
    say(Ar, "     skin bob standard | skin bob off | skin bob slots")
    say(Ar, "OUTLINE: skin outline off (removes the black silhouette) | skin outline on")
    say(Ar, "         skin outline diag (writes nothing) | skin outline lock | skin outline hard")
    say(Ar, "OTHER: skin reset | skin lock | skin menu")
    say(Ar, "Skin0 = default, Skin1 = Hellgur One, Skin2/3/4 = never exposed in the menu")
    say(Ar, "Bob: 'Marcel Bob' = MI_BobSkin_Mustache (+ SKEL_Bob_Mime mesh with 'mime')")
    say(Ar, "current skin: " .. (current and ("Skin" .. current) or "original")
            .. " | lock: " .. tostring(locked))
    return true
end)

log("loaded (v2). 'skin slots' to explore, 'skin one 2' for a hidden skin.")

-- ============================================================================
--  Startup application (see the BOOT_* block at the top).
--  We wait BOOT_DELAY_MS for the player's pawn to be ready, then apply
--  what the launcher requested. In silent mode so as not to pollute the
--  console. Each step is protected: an error does not prevent the following ones.
-- ============================================================================
if BOOT_MESH ~= "none" or BOOT_SKIN >= 0 or BOOT_OUTLINE ~= "keep"
   or BOOT_HIDE_STICK or BOOT_HIDE_HAIR then
    -- No ExecuteWithDelay here (the mod does not depend on it): we arm a LoopAsync
    -- that runs only once after BOOT_DELAY_MS, while the pawn loads.
    local booted = false
    LoopAsync(BOOT_DELAY_MS, function()
        if booted then return true end   -- true = stops the loop
        booted = true
        ExecuteInGameThread(function()
            quietly(function()
                if BOOT_SKIN >= 0 then ApplySkin(BOOT_SKIN) end
                if BOOT_MESH ~= "none" then
                    local entry = FindEntry(MESHES, BOOT_MESH)
                    if entry then SwapOneMesh(entry) end
                end
                -- Outline: KillOutline(false) removes the silhouette, RestoreOutline restores it.
                if BOOT_OUTLINE == "off" then KillOutline(false)
                elseif BOOT_OUTLINE == "on" then RestoreOutline() end
                if BOOT_HIDE_STICK then HideActorsByClass({ "BP_Stick_C" }, true) end
                if BOOT_HIDE_HAIR  then HideActorsByClass({ "BP_Bigoudi_C" }, true) end
            end)
            loud("startup application done (driven by the launcher)")
        end)
        return true
    end)
end
