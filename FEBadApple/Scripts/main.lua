-- ============================================================================
--  FE BAD APPLE  —  make Fading Echo ITSELF play Bad Apple
--
--  Two things in this mod:
--
--  1) THE RENDERING (the real point): the game DRAWS the video with its own
--     actors. Each frame is pre-split into rectangles (see
--     badapple/make_badapple_data.py): ~44 rectangles on average, 148 at worst,
--     where a 64x48 grid would need 3072 cells. One rectangle = one stretched cube.
--     On screen: a wall of 64x48 cells replaying the video at 30 frames/s.
--
--  2) THE VIDEO HIJACK (bonus, cf. badapple/README.md): `badapple video`
--     hands an arbitrary file to the game's media player.
--
--  COMMANDS (game console, ² key):
--     badapple test            spawn ONE cube in front of you + diagnostic  <- START WITH THIS
--     badapple play            raise the screen and play (cubes mode)
--     badapple play enemies    same but with ENEMIES as pixels (low res)
--     badapple pause / resume
--     badapple stop            stop and destroy everything
--     badapple frame <n>       show a still frame (visual test)
--     badapple info            current state
--     badapple set <key> <val> cell | dist | height | pool | thickness |
--                              meshsize | enemycell | loop
--     badapple set mat alienware    dark pixels: the material of the
--                                   ALIENWARE chest, applied to the cubes
--     badapple set class chest      pixels = real ALIENWARE chests, stretched
--     badapple video [chemin]  hijack the game's media player (route 2)
--     badapple video stop
--
--  PLACEMENT: the screen is raised in front of YOU, at `dist` uu, centered at `height` uu
--  above your feet, and oriented to face your gaze at the moment of `play`.
--  Step back to see it all: 64 cells x 100 uu = 64 m wide.
--
--  SOUND: launch badapple_audio.mp4 (shipped alongside the mod) in an external
--  player at the moment of `play`. `badapple video` can also hand it to the
--  game's player, but cinematic audio goes through Wwise and may
--  be silent — hence the external player.
--
--  ⚠️ `Ar` TRAP (documented in FEDevMenu, had crashed FEKillAll v1):
--  the FOutputDevice is valid ONLY within the synchronous body of the handler, never
--  in anything deferred. Here the playback loop never touches it: it goes through
--  log() only.
-- ============================================================================

local UEHelpers = require("UEHelpers")

-- ---------------------------------------------------------------------------
--  Settings (changeable at runtime via `badapple set <key> <value>`)
-- ---------------------------------------------------------------------------
local CFG = {
    cell      = 100.0,   -- size of one cell, in engine units
    dist      = 5000.0,  -- distance of the screen in front of the player
    height    = 1800.0,  -- height of the screen's center above the player
    thickness = 0.15,    -- thickness of the cubes (local X scale)
    pool      = 160,     -- number of reused actors (>= maxRects from the meta)
    enemycell = 250.0,   -- gap between two enemies (enemies mode): ~their size
    meshsize  = 100.0,   -- mesh size in uu (the engine cube is 100)
    mesh      = "",      -- forced path of a UStaticMesh (empty = auto)
    mat       = "unlit", -- pixel material: opaque unlit = the cheapest
    class     = "",      -- actor class to use as a pixel (empty = StaticMeshActor)
    bg        = "black", -- material of the BACKGROUND panel ("none" = no background)
    bgpad     = 1.5,     -- background margin around the image, in cells
    overlap   = 0.06,    -- overlap of the cubes (closes the black gaps between them)
    resync    = 20,      -- every N frames, we reposition ALL active cubes
    loop      = 1,       -- 1 = loop back at the end
    video     = "C:/BadApple/badapple.mp4",
}

-- The engine cube is cooked into FE's pak (verified in the FModel extract:
-- Engine/Content/BasicShapes/Cube). If it isn't loaded in memory at the moment
-- we request it, we fall back to a mesh from the level (see resolveMesh).
local MESH_CANDIDATES = {
    "/Engine/BasicShapes/Cube.Cube",
    "/Engine/EngineMeshes/Cube.Cube",
}
local MESH_PREFER = { "cube", "box", "block", "brick", "crate", "caisse" }

local SMA_CLASS = "/Script/Engine.StaticMeshActor"

-- Shortcuts for `badapple set mat <name>` / `set class <name>`.
-- The ALIENWARE chest differs from the other chests ONLY by this material:
-- its Blueprint overrides nothing else (verified in the FModel extract).
-- So we can paint the cubes with it, without spawning a single chest.
local MAT_PRESETS = {
    -- GizmoMaterial: MSM_Unlit + opaque (verified in the extract). No lighting
    -- computation, so the cheapest of the three. This is the default.
    unlit     = "/Engine/EngineMaterials/GizmoMaterial.GizmoMaterial",
    -- Additive: pretty as a halo but a big fill-rate cost, and invisible
    -- on a light background.
    emissive  = "/Engine/EngineMaterials/EmissiveMeshMaterial.EmissiveMeshMaterial",
    -- The ALIENWARE chest's material: dark, but lit (so more expensive)
    -- and it inverts the image (the cubes represent the LIGHT areas).
    alienware = "/Game/Art/ENVIRO/Material/MaterialInstances/Shard_A/Gameplay/MI_XPChest_ALIENWARE.MI_XPChest_ALIENWARE",
    -- Engine unlit black: perfect for the background panel. Falls back to the
    -- game's unlit black if the engine asset isn't loaded.
    black     = "/Engine/EngineDebugMaterials/BlackUnlitMaterial.BlackUnlitMaterial",
    blackgame = "/Game/Art/ENVIRO/Material/MasterMaterials/PlaceHolder/MI_Unlit_black.MI_Unlit_black",
}
local CLASS_PRESETS = {
    chest     = "/Game/Game/Placeable/InteractiveObjects/Chest/BP_Chest_ALIENWARE.BP_Chest_ALIENWARE_C",
    chestbig  = "/Game/Game/Placeable/InteractiveObjects/Chest/BP_Chest_Big.BP_Chest_Big_C",
}

-- ---------------------------------------------------------------------------
--  Log
-- ---------------------------------------------------------------------------
local function log(m) print("[BadApple] " .. tostring(m) .. "\n") end
local function say(Ar, m)
    log(m)
    if Ar then pcall(function() Ar:Log("[BadApple] " .. tostring(m)) end) end
end
local function try(fn)
    local ok, v = pcall(fn)
    if ok then return v end
    return nil
end

-- ---------------------------------------------------------------------------
--  Engine helpers (same safeguards as the other FE mods)
-- ---------------------------------------------------------------------------
local function isRealActor(a)
    if not (a and a:IsValid()) then return false end
    local fn = ""
    pcall(function() fn = a:GetFullName() end)
    return not string.find(fn, "Default__", 1, true)
end

local function GetPawn()
    local cs = try(function() return FindAllOf("PlayerController") end)
    if cs then
        for _, c in pairs(cs) do
            if c and c:IsValid() then
                local pk = c.Pawn
                if isRealActor(pk) then return pk end
            end
        end
    end
    local p = try(UEHelpers.GetPlayerPawn)
    if isRealActor(p) then return p end
    local list = try(function() return FindAllOf("BP_CoreYgroCharacter_C") end)
    if list then
        for _, a in pairs(list) do if isRealActor(a) then return a end end
    end
    return nil
end

-- In third-person view, the pawn does NOT necessarily face where the CAMERA
-- looks: it's the view rotation that matters for placing a screen in front of you.
local function GetViewYaw(pawn)
    local cs = try(function() return FindAllOf("PlayerController") end)
    if cs then
        for _, c in pairs(cs) do
            if c and c:IsValid() and isRealActor(c.Pawn) then
                local r = try(function() return c:GetControlRotation() end)
                if r and r.Yaw then return r.Yaw, "controle" end
                local cam = try(function() return c.PlayerCameraManager end)
                if cam and cam:IsValid() then
                    local cr = try(function() return cam:GetCameraRotation() end)
                    if cr and cr.Yaw then return cr.Yaw, "camera" end
                end
            end
        end
    end
    local r = pawn and try(function() return pawn:K2_GetActorRotation() end)
    return (r and r.Yaw) or 0.0, "pawn"
end

local function GetWorldCtx()
    local w = try(UEHelpers.GetWorld)
    if w and w:IsValid() then return w end
    w = try(UEHelpers.GetWorldContextObject)
    if w and w:IsValid() then return w end
    return GetPawn()   -- an actor is a valid WorldContextObject
end

local function GetPC()
    local cs = try(function() return FindAllOf("PlayerController") end)
    if cs then
        for _, c in pairs(cs) do
            if c and c:IsValid() and isRealActor(c.Pawn) then return c end
        end
    end
    return try(UEHelpers.GetPlayerController)
end

local function KSL()
    local o = try(UEHelpers.GetKismetSystemLibrary)
    if o and o:IsValid() then return o end
    return try(function() return StaticFindObject("/Script/Engine.Default__KismetSystemLibrary") end)
end

-- Execute a game console command. ⚠️ SpecificPlayer must be the current PC
-- (nil fails, lesson from FEDevMenu/FEPerf).
local function Console(cmd)
    local k, w, pc = KSL(), GetWorldCtx(), GetPC()
    if not (k and w) then return false end
    return (try(function() k:ExecuteConsoleCommand(w, cmd, pc); return true end)) == true
end

-- Cuts the TEMPORAL effects that make teleporting cubes SMEAR:
-- motion blur + temporal anti-aliasing (TAA/TSR keep a frame history
-- that bleeds over a jumping object). FXAA (method 1) smooths WITHOUT history.
-- Reversible: `badapple gfx on` restores TSR, or a restart is enough.
-- ⚠️ Cuts ONLY the motion blur (harmless). We NO LONGER touch
-- r.AntiAliasingMethod: this game renders via TSR (low resolution + upscaled);
-- forcing FXAA cuts the upscaling -> low-res image, white staircase edges
-- everywhere (tested: worse). To fight temporal smearing without breaking
-- the TSR, we ask TAA to keep less history (CurrentFrameWeight).
local function applyCleanGfx(Ar, on)
    -- AUTO = motion blur only (harmless). We NO LONGER touch the AA
    -- automatically: every auto tweak ended up making things worse. The temporal
    -- anti-smear settings are in manual commands (`badapple ghost`).
    if on then
        Console("r.MotionBlur.Amount 0")
        Console("r.MotionBlurQuality 0")
        if Ar then say(Ar, "motion blur coupe.") end
    else
        Console("r.MotionBlur.Amount 0.5")
        Console("r.MotionBlurQuality 4")
        Console("r.AntiAliasingMethod 4")               -- in case a test had changed it
        Console("r.TemporalAACurrentFrameWeight 0.04")
        if Ar then say(Ar, "effets graphiques par defaut restaures.") end
    end
end

local function ProbeLocation(actor)
    local loc = try(function() return actor:K2_GetActorLocation() end)
    if loc and loc.X then return { X = loc.X, Y = loc.Y, Z = loc.Z } end
    return nil
end

-- ---------------------------------------------------------------------------
--  Data loading (badapple/make_badapple_data.py produces it)
-- ---------------------------------------------------------------------------
local DATA = nil

local function loadModule(name)
    local ok, v = pcall(require, name)
    if ok and type(v) == "table" then return v end
    -- Fallback: require may not see the subfolder depending on the UE4SS config.
    local src = debug.getinfo(1, "S").source:gsub("^@", "")
    local dir = src:match("^(.*)[/\\][^/\\]*$") or "."
    local path = dir .. "/" .. name:gsub("%.", "/") .. ".lua"
    local ok2, v2 = pcall(dofile, path)
    if ok2 and type(v2) == "table" then return v2 end
    return nil
end

local function loadData(Ar)
    if DATA then return true end
    local meta = loadModule("data.badapple_meta")
    if not meta then
        say(Ar, "donnees introuvables : Scripts/data/badapple_meta.lua")
        say(Ar, "genere-les avec badapple/make_badapple_data.py")
        return false
    end
    local chunks = {}
    for c = 1, meta.chunks do
        local ch = loadModule(("data.badapple_%02d"):format(c))
        if not ch then
            say(Ar, ("morceau %d/%d manquant"):format(c, meta.chunks))
            return false
        end
        chunks[c] = ch
    end
    local DEC = {}
    for i = 1, #meta.alphabet do DEC[meta.alphabet:byte(i)] = i - 1 end
    DATA = { meta = meta, chunks = chunks, DEC = DEC }
    say(Ar, ("donnees : %dx%d, %d images a %d i/s (%.0f s), %d rects max"):format(
        meta.w, meta.h, meta.frames, meta.fps, meta.frames / meta.fps, meta.maxRects))
    if CFG.pool < meta.maxRects then
        CFG.pool = meta.maxRects
        say(Ar, "pool ajuste a " .. CFG.pool)
    end
    return true
end

local function frameStrings(i)
    local m = DATA.meta
    local c = math.floor((i - 1) / m.chunk) + 1
    local k = (i - 1) % m.chunk + 1
    local ch = DATA.chunks[c]
    if not ch then return nil, nil end
    return ch.rects[k], ch.cells[k]
end

-- Reads an encoded field (1 or 2 characters) at position i.
local function readField(s, i, nch, DEC)
    if nch == 1 then return DEC[s:byte(i)], i + 1 end
    return DEC[s:byte(i)] * 64 + DEC[s:byte(i + 1)], i + 2
end

-- ---------------------------------------------------------------------------
--  Screen geometry
-- ---------------------------------------------------------------------------
local SCREEN = nil

local function buildScreen(pawn, Ar)
    local loc = ProbeLocation(pawn)
    if not loc then say(Ar, "position du joueur illisible"); return false end
    local yaw, ysrc = GetViewYaw(pawn)
    local yr  = math.rad(yaw)
    local fx, fy = math.cos(yr), math.sin(yr)      -- forward
    local rx, ry = -math.sin(yr), math.cos(yr)     -- right
    SCREEN = {
        cx = loc.X + fx * CFG.dist,
        cy = loc.Y + fy * CFG.dist,
        cz = loc.Z + CFG.height,
        rx = rx, ry = ry, fx = fx, fy = fy, yaw = yaw,
    }
    say(Ar, ("ecran monte a %.0f uu devant toi (yaw %.0f, source %s), %d x %d cellules de %.0f uu"):format(
        CFG.dist, yaw, ysrc, DATA.meta.w, DATA.meta.h, CFG.cell))
    return true
end

-- World center + scale of an (x, y) rectangle of w x h cells.
local function rectPlacement(x, y, w, h)
    local m, S = DATA.meta, CFG.cell
    local off = (x + w * 0.5 - m.w * 0.5) * S          -- to the right
    local zof = (m.h * 0.5 - (y + h * 0.5)) * S        -- row 0 = at the top
    -- Overlap: we slightly enlarge each cube so it overlaps its
    -- neighbors and no black gap appears between the rows.
    local k = (S / CFG.meshsize) * (1.0 + CFG.overlap)
    return { X = SCREEN.cx + SCREEN.rx * off,
             Y = SCREEN.cy + SCREEN.ry * off,
             Z = SCREEN.cz + zof },
           { X = CFG.thickness, Y = w * k, Z = h * k }
end

-- Parking spot: far BEHIND the black backdrop, out of view. An inactive cube is
-- sent there in addition to being hidden -> even if SetActorHiddenInGame fails (under
-- lag), it stays occluded by the black panel and leaves no ghost bar.
local function parkSpot()
    local back = CFG.cell * 50.0
    return { X = SCREEN.cx + SCREEN.fx * back,
             Y = SCREEN.cy + SCREEN.fy * back,
             Z = SCREEN.cz - CFG.cell * 200.0 }
end

-- ---------------------------------------------------------------------------
--  Mesh and class of the "pixels"
-- ---------------------------------------------------------------------------
local function resolveMesh(Ar)
    if CFG.mesh ~= "" then
        local m = try(function() return StaticFindObject(CFG.mesh) end)
        if m and m:IsValid() then return m, CFG.mesh end
        say(Ar, "mesh force introuvable : " .. CFG.mesh)
    end
    for _, p in ipairs(MESH_CANDIDATES) do
        local m = try(function() return StaticFindObject(p) end)
        if m and m:IsValid() then return m, p end
    end
    -- Fallback: any already-loaded UStaticMesh, preferring a cube.
    local all = try(function() return FindAllOf("StaticMesh") end)
    local first = nil
    if all then
        for _, m in pairs(all) do
            if m and m:IsValid() then
                local n = tostring(try(function() return m:GetFName():ToString() end) or ""):lower()
                if not string.find(n, "default__", 1, true) then
                    first = first or m
                    for _, want in ipairs(MESH_PREFER) do
                        if string.find(n, want, 1, true) then return m, n end
                    end
                end
            end
        end
    end
    if first then
        return first, tostring(try(function() return first:GetFName():ToString() end))
    end
    return nil, nil
end

-- Actor class for "enemies" mode: we clone the class of an enemy present
-- in the area (there is no generic instantiable class).
local function resolveEnemyClass(Ar)
    if CFG.class ~= "" then
        local p = CLASS_PRESETS[CFG.class:lower()] or CFG.class
        local c = try(function() return StaticFindObject(p) end)
        if c and c:IsValid() then return c, p end
        say(Ar, "classe forcee introuvable : " .. p)
    end
    local all = try(function() return FindAllOf("BP_EnemyBase_C") end)
    if all then
        for _, e in pairs(all) do
            if isRealActor(e) then
                local c = try(function() return e:GetClass() end)
                if c and c:IsValid() then
                    return c, tostring(try(function() return c:GetFName():ToString() end))
                end
            end
        end
    end
    return nil, nil
end

-- ---------------------------------------------------------------------------
--  Actor pool
-- ---------------------------------------------------------------------------
local POOL, POOL_KIND = {}, nil

local function spawnActor(cls, loc, yaw)
    local GS = try(UEHelpers.GetGameplayStatics)
    local world = GetWorldCtx()
    if not (GS and world and cls) then return nil, "GameplayStatics/World/classe absents" end

    local yr = math.rad(yaw or 0)
    local t = {
        Rotation    = { X = 0.0, Y = 0.0, Z = math.sin(yr * 0.5), W = math.cos(yr * 0.5) },
        Translation = { X = loc.X, Y = loc.Y, Z = loc.Z },
        Scale3D     = { X = 1.0, Y = 1.0, Z = 1.0 },
    }

    -- 1 = AlwaysSpawn (we never want a collision to cancel the spawn)
    -- 0 = OverrideRootScale
    local a = try(function()
        return GS:BeginDeferredActorSpawnFromClass(world, cls, t, 1, nil, 0)
    end)
    if not (a and a:IsValid()) then
        -- Fallback: some table->FTransform conversions fail on
        -- nested structs; an empty table gives a null transform,
        -- which we fix right after with K2_SetActorLocation.
        a = try(function() return GS:BeginDeferredActorSpawnFromClass(world, cls, {}, 1, nil, 0) end)
        if not (a and a:IsValid()) then return nil, "BeginDeferredActorSpawnFromClass a echoue" end
        try(function() GS:FinishSpawningActor(a, {}, 0) end)
        try(function() a:K2_SetActorLocation(loc, false, {}, true) end)
        return a, "transformee vide + repositionnement"
    end
    try(function() GS:FinishSpawningActor(a, t, 0) end)
    return a, "ok"
end

-- The component that carries the rendering, whatever the actor type: a
-- StaticMeshActor exposes it as `StaticMeshComponent`, a Blueprint (chest,
-- enemy...) does not — hence the fallback to GetComponentByClass then RootComponent.
local function meshComponent(a)
    local c = try(function() return a.StaticMeshComponent end)
    if c and c:IsValid() then return c end
    local cls = try(function() return StaticFindObject("/Script/Engine.StaticMeshComponent") end)
    if cls then
        c = try(function() return a:GetComponentByClass(cls) end)
        if c and c:IsValid() then return c end
    end
    c = try(function() return a.RootComponent end)
    if c and c:IsValid() then return c end
    return nil
end

local MAT_OBJ = nil   -- resolved once per buildPool

-- UPrimitiveComponent flags we all set to false: each one is one fewer
-- rendering pass for 160 movable actors.
local NO_COST_FLAGS = {
    "bCastShadow", "bCastDynamicShadow", "bCastStaticShadow",
    "bAffectDynamicIndirectLighting", "bAffectDistanceFieldLighting",
    "bReceivesDecals", "bVisibleInRayTracing",
}

-- Prepares a freshly spawned actor to serve as a pixel.
-- mesh = nil when the actor already brings its own rendering (`set class` mode).
local function dressCube(a, mesh, yaw)
    try(function() a:SetMobility(2) end)                    -- Movable, otherwise immobile
    local smc = meshComponent(a)
    if smc and smc:IsValid() then
        try(function() smc:SetMobility(2) end)
        -- THE mod's GPU cost: 160 MOVABLE meshes redoing shadows, GI and
        -- distance fields every frame bring the game to its knees. We pull them
        -- out of all these passes. To be done BEFORE SetStaticMesh: it
        -- recreates the render state and therefore takes the flags into account.
        for _, k in ipairs(NO_COST_FLAGS) do try(function() smc[k] = false end) end
        try(function() smc:SetForceDisableNanite(true) end)

        -- ⚠️ THE CAUSE OF THE "Background Worker" CRASH: moving 160 actors
        -- relevant to NAVIGATION 30 times/s triggers a permanent
        -- rebuild of the Recast nav mesh, which runs on the worker
        -- threads -> EXCEPTION_ACCESS_VIOLATION. We cut the nav at the source.
        -- (SetActorEnableCollision(false) is NOT enough: it changes the response
        --  but keeps the physics body AND the contribution to the nav.)
        try(function() smc.bCanEverAffectNavigation = false end)
        try(function() smc:SetCollisionEnabled(0) end)   -- 0 = NoCollision: destroys the body
        try(function() smc:SetGenerateOverlapEvents(false) end)
        try(function() smc:SetComponentTickEnabled(false) end)

        if mesh then try(function() smc:SetStaticMesh(mesh) end) end
        if MAT_OBJ then try(function() smc:SetMaterial(0, MAT_OBJ) end) end
    end
    try(function() a:SetActorEnableCollision(false) end)
    try(function() a:SetActorTickEnabled(false) end)
    try(function() a:K2_SetActorRotation({ Pitch = 0.0, Yaw = yaw, Roll = 0.0 }, true) end)
    try(function() a:SetActorHiddenInGame(true) end)
    return smc ~= nil
end

local function dressEnemy(a)
    try(function() a:SetActorEnableCollision(false) end)
    try(function() a:SetActorTickEnabled(false) end)
    -- Same anti-crash disarming as the cubes: an enemy moves, contributes to
    -- the nav and simulates -> without this, the navigation worker crashes (cf. dressCube).
    local root = meshComponent(a)
    if root and root:IsValid() then
        try(function() root.bCanEverAffectNavigation = false end)
        try(function() root:SetCollisionEnabled(0) end)
        try(function() root:SetGenerateOverlapEvents(false) end)
        try(function() root:SetSimulatePhysics(false) end)
        try(function() root:SetComponentTickEnabled(false) end)
    end
    try(function() a:SetActorHiddenInGame(true) end)
end

local BACKDROP = nil   -- the black background panel actor

local function destroyBackdrop()
    if BACKDROP and BACKDROP:IsValid() then try(function() BACKDROP:K2_DestroyActor() end) end
    BACKDROP = nil
end

local function destroyPool()
    for _, s in ipairs(POOL) do
        if s.actor and s.actor:IsValid() then try(function() s.actor:K2_DestroyActor() end) end
    end
    POOL, POOL_KIND = {}, nil
    destroyBackdrop()
end

-- A large black panel covering the whole grid, placed SLIGHTLY behind the
-- pixel layer: the empty areas of the video (no cube) finally read as
-- black instead of showing the scenery -> true Bad Apple look, white on black.
local function buildBackdrop(mesh, Ar)
    destroyBackdrop()
    if (CFG.bg or "none"):lower() == "none" or not mesh then return end

    local matPath = MAT_PRESETS[CFG.bg:lower()] or CFG.bg
    local mat = try(function() return StaticFindObject(matPath) end)
    if not (mat and mat:IsValid()) and MAT_PRESETS[CFG.bg:lower()] == MAT_PRESETS.black then
        -- fallback: the game's unlit black
        mat = try(function() return StaticFindObject(MAT_PRESETS.blackgame) end)
        if mat and mat:IsValid() then matPath = MAT_PRESETS.blackgame end
    end
    if not (mat and mat:IsValid()) then
        say(Ar, "materiau de fond introuvable (" .. matPath .. ") -> pas de fond")
        return
    end

    local cls = try(function() return StaticFindObject(SMA_CLASS) end)
    if not (cls and cls:IsValid()) then return end

    -- Centered, but pushed 2 cells BEHIND the plane of the cubes (away from the
    -- camera = along the forward vector).
    local back = (CFG.cell * 2.0)
    local loc = { X = SCREEN.cx + SCREEN.fx * back,
                  Y = SCREEN.cy + SCREEN.fy * back,
                  Z = SCREEN.cz }
    local a, how = spawnActor(cls, loc, SCREEN.yaw)
    if not a then say(Ar, "spawn du fond a echoue : " .. tostring(how)); return end

    -- We reuse dressCube (nav/collision cut) but WITHOUT its pixel
    -- material: we force the background material right after.
    dressCube(a, mesh, SCREEN.yaw)
    local smc = meshComponent(a)
    if smc and smc:IsValid() then try(function() smc:SetMaterial(0, mat) end) end

    -- Scale: covers (w + 2*pad) x (h + 2*pad) cells, very thin.
    local m, k = DATA.meta, CFG.cell / CFG.meshsize
    local sc = { X = CFG.thickness,
                 Y = (m.w + 2 * CFG.bgpad) * k,
                 Z = (m.h + 2 * CFG.bgpad) * k }
    try(function() a:SetActorScale3D(sc) end)
    try(function() a:K2_SetActorLocation(loc, false, {}, true) end)
    try(function() a:SetActorHiddenInGame(false) end)
    BACKDROP = a
    say(Ar, "fond noir : " .. matPath)
end

local function buildPool(kind, n, Ar)
    destroyPool()
    local origin = { X = SCREEN.cx, Y = SCREEN.cy, Z = SCREEN.cz }
    local cls, mesh, label

    if kind == "enemies" then
        cls, label = resolveEnemyClass(Ar)
        if not cls then
            say(Ar, "aucun ennemi charge dans la zone : impossible de recuperer une classe.")
            say(Ar, "va dans une zone avec des ennemis, ou `badapple set class <chemin>`.")
            return false
        end
        say(Ar, "classe des pixels : " .. tostring(label))
    elseif CFG.class ~= "" then
        -- Pixels = whole actors (chests...). They bring their own
        -- rendering: we assign them no mesh, we stretch them as-is.
        local p = CLASS_PRESETS[CFG.class:lower()] or CFG.class
        cls = try(function() return StaticFindObject(p) end)
        if not (cls and cls:IsValid()) then
            say(Ar, "classe introuvable (pas chargee dans cette zone ?) : " .. p)
            say(Ar, "les coffres ne sont charges que dans une zone qui en contient.")
            return false
        end
        mesh, label = nil, p
        say(Ar, "pixels = acteurs " .. p)
    else
        cls = try(function() return StaticFindObject(SMA_CLASS) end)
        if not (cls and cls:IsValid()) then
            say(Ar, "classe StaticMeshActor introuvable"); return false
        end
        mesh, label = resolveMesh(Ar)
        if not mesh then
            say(Ar, "aucun UStaticMesh utilisable trouve. Charge un niveau, ou "
                 .. "`badapple set mesh /Engine/BasicShapes/Cube.Cube`.")
            return false
        end
        say(Ar, "mesh des pixels : " .. tostring(label))
    end

    MAT_OBJ = nil
    if CFG.mat ~= "" then
        local p = MAT_PRESETS[CFG.mat:lower()] or CFG.mat
        local m = try(function() return StaticFindObject(p) end)
        if m and m:IsValid() then
            MAT_OBJ = m
            say(Ar, "materiau des pixels : " .. p)
        else
            say(Ar, "materiau introuvable (pas charge dans cette zone ?) : " .. p)
            say(Ar, "-> les pixels garderont le materiau du mesh")
        end
    end

    local how = nil
    for i = 1, n do
        local a, err = spawnActor(cls, origin, SCREEN.yaw)
        if not a then
            say(Ar, ("spawn %d/%d a echoue : %s"):format(i, n, tostring(err)))
            if i == 1 then return false end
            break
        end
        how = how or err
        if kind == "enemies" then dressEnemy(a) else dressCube(a, mesh, SCREEN.yaw) end
        -- Render component cached: allows hiding/showing at the
        -- COMPONENT level (more reliable than the actor alone) without looking it up each frame.
        POOL[i] = { actor = a, smc = meshComponent(a), x = -1, y = -1, w = -1, h = -1, hidden = true }
    end

    POOL_KIND = kind
    say(Ar, ("%d acteurs prets (%s)"):format(#POOL, tostring(how)))

    -- Black background: a cube mesh is needed even in enemies/chests mode (where
    -- `mesh` may be nil because the actors bring their own rendering).
    local bgMesh = mesh or resolveMesh(Ar)
    buildBackdrop(bgMesh, Ar)

    return #POOL > 0
end

-- ---------------------------------------------------------------------------
--  Rendering a frame
-- ---------------------------------------------------------------------------
local lostActors = 0
-- Forces one frame to reposition ALL active cubes, even if the cache says they
-- haven't moved. Used to heal "stuck" cubes: under lag, a
-- K2_SetActorLocation can be missed, the cube stays at the old position while
-- the cache thinks it moved it -> ghost line that persists. A periodic
-- resync (every CFG.resync frames) makes it disappear in <1 s.
local FORCE_RESYNC = false

-- Hide / show a cube RELIABLY: at the actor AND component level.
-- SetActorHiddenInGame alone proved insufficient on some builds.
local function showSlot(slot)
    local a = slot.actor
    try(function() a:SetActorHiddenInGame(false) end)
    if slot.smc then try(function() slot.smc:SetVisibility(true, true) end) end
    slot.hidden, slot.parked = false, false
end

local function hideSlot(slot)
    local a = slot.actor
    try(function() a:SetActorHiddenInGame(true) end)
    if slot.smc then try(function() slot.smc:SetVisibility(false, true) end) end
    slot.hidden = true
end

-- Hides cubes with index > n: hidden AND parked behind the background. Normally
-- each cube is hidden/parked only ONCE per transition (cheap).
-- On resync (force=true) we RE-hide and RE-park all the extras unconditionally:
-- this catches a "straggler" cube whose hiding or parking had failed
-- once (the slot.parked flag was set anyway, so never retried).
local function hideExtras(n, force)
    for k = n + 1, #POOL do
        local slot = POOL[k]
        local a = slot.actor
        if a and a:IsValid() then
            if force or not slot.hidden then hideSlot(slot) end
            if force or not slot.parked then
                try(function() a:K2_SetActorLocation(parkSpot(), false, {}, true) end)
                slot.parked = true
                slot.x, slot.y, slot.w, slot.h = -1, -1, -1, -1  -- cache invalidated: will force a real reposition on return
            end
        end
    end
end

-- Rolling sweep: each frame, we "heal" a small slice of cubes by
-- realigning their REAL position onto the memorized intent (cache). This continuously
-- catches any straggler cube (hiding/move missed once) without the spike
-- of a global resync. A visible cube is put back on its rectangle, a hidden cube
-- is re-parked. The whole pool is reviewed in ~(#POOL / slice) frames.
local healCursor = 0
local function healSlice(k)
    local total = #POOL
    if total == 0 then return end
    for _ = 1, math.min(k, total) do
        healCursor = (healCursor % total) + 1
        local slot = POOL[healCursor]
        local a = slot.actor
        if a and a:IsValid() then
            if slot.hidden then
                try(function() a:K2_SetActorLocation(parkSpot(), false, {}, true) end)
                hideSlot(slot)
                slot.parked = true
            elseif slot.x >= 0 then
                local loc, sc = rectPlacement(slot.x, slot.y, slot.w, slot.h)
                try(function() a:SetActorScale3D(sc) end)
                try(function() a:K2_SetActorLocation(loc, false, {}, true) end)
            end
        end
    end
end

local function renderRects(s)
    local DEC, nch = DATA.DEC, DATA.meta.charsPerField
    local i, len, n = 1, #s, 0
    while i <= len - (4 * nch - 1) do
        local x, y, w, h
        x, i = readField(s, i, nch, DEC)
        y, i = readField(s, i, nch, DEC)
        w, i = readField(s, i, nch, DEC); w = w + 1
        h, i = readField(s, i, nch, DEC); h = h + 1
        n = n + 1
        local slot = POOL[n]
        if slot then
            local a = slot.actor
            if a and a:IsValid() then
                local loc, sc = rectPlacement(x, y, w, h)
                -- The scale doesn't change often -> we keep it as a delta.
                if slot.w ~= w or slot.h ~= h then
                    try(function() a:SetActorScale3D(sc) end)
                end
                -- ⚠️ The POSITION is ALWAYS re-applied (no delta). Under
                -- lag a K2_SetActorLocation can fail; by replaying it each
                -- frame, a stuck cube is fixed on the very next frame instead
                -- of staying blocked (missing shape interior / ghost bar).
                try(function() a:K2_SetActorLocation(loc, false, {}, true) end)
                slot.x, slot.y, slot.w, slot.h = x, y, w, h
                if slot.hidden then showSlot(slot) end
            else
                lostActors = lostActors + 1
            end
        end
    end
    hideExtras(n, FORCE_RESYNC)
    return n
end

-- Enemies mode: one lit cell = one enemy. No stretching possible,
-- so no rectangles: we read the low-resolution grid.
local function renderCells(s)
    local DEC, m = DATA.DEC, DATA.meta
    local W, H = m.lowW, m.lowH
    local n, bit, ci, acc, nb = 0, 0, 1, 0, 0
    for idx = 0, W * H - 1 do
        if nb == 0 then
            acc = DEC[s:byte(ci)] or 0; ci = ci + 1; nb = 6
        end
        bit = math.floor(acc / 32) % 2
        acc = (acc * 2) % 64
        nb = nb - 1
        if bit == 1 then
            n = n + 1
            local slot = POOL[n]
            if slot and slot.actor and slot.actor:IsValid() then
                local x, y = idx % W, math.floor(idx / W)
                if slot.x ~= x or slot.y ~= y then
                    -- An enemy doesn't stretch: the gap between two cells
                    -- equals its own size (CFG.enemycell), not that of a cube.
                    local S = CFG.enemycell
                    local off = (x + 0.5 - W * 0.5) * S
                    local zof = (H * 0.5 - (y + 0.5)) * S
                    local loc = { X = SCREEN.cx + SCREEN.rx * off,
                                  Y = SCREEN.cy + SCREEN.ry * off,
                                  Z = SCREEN.cz + zof }
                    try(function() slot.actor:K2_SetActorLocation(loc, false, {}, true) end)
                    slot.x, slot.y = x, y
                end
                if slot.hidden then showSlot(slot) end
            end
        end
    end
    hideExtras(n, FORCE_RESYNC)
    return n
end

-- ---------------------------------------------------------------------------
--  ISM MODE (InstancedStaticMeshComponent) — the real anti-smear solution
--  ---------------------------------------------------------------------------
--  ONE single component holds all the cells as "instances". The
--  instances of an ISM do NOT write a motion vector (the
--  PerInstancePrevTransform field stays empty), so the TSR cannot spread them:
--  NO smearing, by construction, even when we move the cells. As a bonus,
--  a single draw call -> far lighter than 160 actors.
-- ---------------------------------------------------------------------------
local ISM = { host = nil, comp = nil }
local ISM_CLASS = "/Script/Engine.InstancedStaticMeshComponent"
local ISM_PREV = nil   -- previous state of each instance (for delta rendering)

local function ismDestroy()
    if ISM.host and ISM.host:IsValid() then try(function() ISM.host:K2_DestroyActor() end) end
    ISM.host, ISM.comp, ISM_PREV = nil, nil, nil
end

local function ismBuild(mesh, matObj, Ar)
    ismDestroy()
    local hostCls = try(function() return StaticFindObject(SMA_CLASS) end)
    if not (hostCls and hostCls:IsValid()) then say(Ar, "ISM: StaticMeshActor introuvable"); return false end
    local origin = { X = SCREEN.cx, Y = SCREEN.cy, Z = SCREEN.cz }
    local host = spawnActor(hostCls, origin, SCREEN.yaw)
    if not host then say(Ar, "ISM: spawn de l'hote a echoue"); return false end
    ISM.host = host

    local ismCls = try(function() return StaticFindObject(ISM_CLASS) end)
    if not (ismCls and ismCls:IsValid()) then say(Ar, "ISM: classe composant introuvable"); return false end
    local idt = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 },
                  Translation = { X = 0, Y = 0, Z = 0 },
                  Scale3D = { X = 1, Y = 1, Z = 1 } }
    -- bManualAttachment=false (attaches to the root), bDeferredFinish=false (ready right away)
    local comp = try(function() return host:AddComponentByClass(ismCls, false, idt, false) end)
    if not (comp and comp:IsValid()) then say(Ar, "ISM: AddComponentByClass a echoue"); return false end
    ISM.comp = comp

    try(function() comp:SetStaticMesh(mesh) end)
    if matObj then try(function() comp:SetMaterial(0, matObj) end) end
    for _, k in ipairs(NO_COST_FLAGS) do try(function() comp[k] = false end) end
    try(function() comp.bCanEverAffectNavigation = false end)
    try(function() comp:SetForceDisableNanite(true) end)
    try(function() comp:SetCollisionEnabled(0) end)

    -- Pre-fills the instance pool, all collapsed to scale 0 (invisible).
    local zero = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = origin,
                   Scale3D = { X = 0, Y = 0, Z = 0 } }
    for _ = 1, CFG.pool do try(function() comp:AddInstance(zero, true) end) end
    ISM_PREV = {}                       -- all instances start "collapsed"
    for idx = 0, CFG.pool - 1 do ISM_PREV[idx] = "c" end
    local cnt = try(function() return comp:GetInstanceCount() end) or 0
    say(Ar, ("ISM pret : %d instances (1 seul draw call, zero trainee)"):format(cnt))
    return cnt > 0
end

local function ismRender(s)
    local comp = ISM.comp
    if not (comp and comp:IsValid()) then return 0 end
    local DEC, nch = DATA.DEC, DATA.meta.charsPerField

    -- First parse the frame's rectangles.
    local rects, i, len = {}, 1, #s
    while i <= len - (4 * nch - 1) do
        local x, y, w, h
        x, i = readField(s, i, nch, DEC)
        y, i = readField(s, i, nch, DEC)
        w, i = readField(s, i, nch, DEC); w = w + 1
        h, i = readField(s, i, nch, DEC); h = h + 1
        rects[#rects + 1] = { x, y, w, h }
    end

    local pool = CFG.pool
    local yr = math.rad(SCREEN.yaw)
    local qz, qw = math.sin(yr * 0.5), math.cos(yr * 0.5)
    local center = { X = SCREEN.cx, Y = SCREEN.cy, Z = SCREEN.cz }

    -- ⚠️ DELTA: touch only the instances that CHANGE. Updating all 160
    -- each frame + rebuilding the buffer froze the game after a few
    -- frames. We compare to the previous state (ISM_PREV) and update only the
    -- strict minimum; a SINGLE rebuild (the last change carries dirty).
    ISM_PREV = ISM_PREV or {}
    -- 1) determine the desired key of each instance (rectangle or "collapse")
    local desired = {}
    for idx = 0, pool - 1 do
        local r = rects[idx + 1]
        desired[idx] = r and (r[1] .. "," .. r[2] .. "," .. r[3] .. "," .. r[4]) or "c"
    end
    -- 2) collect the instances to change
    local changed = {}
    for idx = 0, pool - 1 do
        if ISM_PREV[idx] ~= desired[idx] then changed[#changed + 1] = idx end
    end
    -- 3) apply; only the LAST change rebuilds the buffer
    for j = 1, #changed do
        local idx = changed[j]
        local r = rects[idx + 1]
        local t
        if r then
            local loc, sc = rectPlacement(r[1], r[2], r[3], r[4])
            t = { Rotation = { X = 0, Y = 0, Z = qz, W = qw }, Translation = loc, Scale3D = sc }
        else
            t = { Rotation = { X = 0, Y = 0, Z = qz, W = qw }, Translation = center,
                  Scale3D = { X = 0, Y = 0, Z = 0 } }
        end
        local dirty = (j == #changed)
        try(function() comp:UpdateInstanceTransform(idx, t, true, dirty, true) end)
        ISM_PREV[idx] = desired[idx]
    end
    return #rects
end

local function renderFrame(i)
    local r, c = frameStrings(i)
    if POOL_KIND == "ism" then
        if r then return ismRender(r) end
    elseif POOL_KIND == "enemies" then
        if c then return renderCells(c) end
    elseif r then
        return renderRects(r)
    end
    return 0
end

-- ---------------------------------------------------------------------------
--  Playback
-- ---------------------------------------------------------------------------
local PLAY = { on = false, paused = false, t0 = nil, last = -1 }

-- ⚠️ This function is called 60 times per second. The previous version
-- redid a UEHelpers.GetGameplayStatics() + GetWorldCtx() on every call,
-- and GetWorldCtx could fall back to FindAllOf("PlayerController") = a
-- FULL scan of the UObjects array, 60 times per second. That was the
-- number-one cause of the stutter. We cache and only re-resolve on
-- invalidation (area change).
local CLOCK = { gs = nil, world = nil }

local function resetClock() CLOCK.gs, CLOCK.world = nil, nil end

local function realSeconds()
    if not (CLOCK.gs and CLOCK.gs:IsValid()) then
        CLOCK.gs = try(UEHelpers.GetGameplayStatics)
    end
    if not (CLOCK.world and CLOCK.world:IsValid()) then
        CLOCK.world = GetWorldCtx()
    end
    if not (CLOCK.gs and CLOCK.world) then return nil end
    return try(function() return CLOCK.gs:GetRealTimeSeconds(CLOCK.world) end)
end

local function stopPlayback()
    PLAY.on, PLAY.paused, PLAY.t0, PLAY.last = false, false, nil, -1
    resetClock()
end

-- The work of one frame, executed on the GAME THREAD only.
local function tickFrame()
    -- In ISM mode, POOL is empty (everything is in the instanced component): the
    -- render condition must accept either an actor pool or the ISM.
    local ready = (#POOL > 0) or (POOL_KIND == "ism" and ISM.comp and ISM.comp:IsValid())
    if not (PLAY.on and not PLAY.paused and DATA and ready) then return end
    local t = realSeconds()
    if not t then return end
    if not PLAY.t0 then PLAY.t0 = t end
    local m = DATA.meta
    local idx = math.floor((t - PLAY.t0) * m.fps) + 1
    if idx > m.frames then
        if CFG.loop == 1 then
            PLAY.t0 = t; idx = 1
        else
            log("fin de la video")
            stopPlayback()
            return
        end
    end
    if idx ~= PLAY.last then
        PLAY.last = idx
        renderFrame(idx)
        -- Heartbeat: every ~90 rendered frames (~3 s), we write
        -- the current frame. If the log keeps going when the screen has "frozen", the
        -- loop is still running -> it's the ISM rendering. If it stops, the loop
        -- is dead. That's the freeze diagnostic.
        PLAY.renders = (PLAY.renders or 0) + 1
        if PLAY.renders % 90 == 0 then log("battement : image " .. idx .. "/" .. m.frames) end
        -- Rolling sweep (actors mode only; the ISM has no ghosts).
        if POOL_KIND ~= "ism" and CFG.resync > 0 then
            healSlice(math.max(1, math.ceil(#POOL / CFG.resync)))
        end
    end
end

-- ---------------------------------------------------------------------------
--  Cadence: persistent LoopAsync + ExecuteInGameThread with a STABLE function
-- ---------------------------------------------------------------------------
-- ⚠️ History of the attempts that FAILED:
--  1) LoopAsync + ExecuteInGameThread(FRESH closure on every pass) -> UE4SS
--     removes the hook: "[Lua::Registry::get_function_ref] Ref was not function".
--     REAL CAUSE (only understood on 25/07, after the random freeze): the
--     FRESH CLOSURE passed 30-60x/s is registered and then sometimes freed by
--     the GC before it runs -> the ref becomes invalid -> the loop dies AT
--     AN UNPREDICTABLE MOMENT (random freeze, "it gets more or less far").
--  2) ExecuteWithDelay re-arming itself with a fresh closure: SAME problem,
--     same random freeze.
--
-- THE FIX: a SINGLE function, defined once (gameTick), passed as-is to
-- ExecuteInGameThread on every pass. The reference stays alive (upvalue), the
-- GC cannot free it -> no more "Ref was not function". This is the FEMoonJump
-- pattern, but with the function reused instead of recreated.
--
-- (No usable per-frame hook in this game: BP_YgroHud doesn't implement
-- ReceiveDrawHUD, cf. the failure of the Keystrokes Lua mods.)

-- The work of one frame, on the game thread. STABLE function (never recreated).
local function gameTick()
    -- Under pcall: an error must NEVER propagate up to the hook (otherwise UE4SS
    -- removes it and ALL Lua mods stop).
    local ok, err = pcall(tickFrame)
    if not ok then
        PLAY.on = false
        log("erreur de rendu, lecture arretee : " .. tostring(err))
    end
end

-- Persistent loop, registered ONCE at load time. It always runs; a simple
-- PLAY.on flag decides whether we render. `gameTick` is passed by REFERENCE
-- (no fresh closure) -> stable ref, no random freeze.
LoopAsync(30, function()
    if PLAY.on and not PLAY.paused then
        pcall(function() ExecuteInGameThread(gameTick) end)
    end
    return false   -- never stop the loop
end)

local function startChain() end   -- the loop is already started at load time

-- ---------------------------------------------------------------------------
--  Media player hijack (route 2 — see badapple/README.md)
-- ---------------------------------------------------------------------------
local KNOWN_PLAYERS = {
    "/Game/Movies/MediaSystem/YGROMediaPlayer.YGROMediaPlayer",
    "/Game/Movies/MediaSystem/YGROMedia_StartMenu.YGROMedia_StartMenu",
    "/Game/Movies/MediaSystem/YGROMediaPlayerBootFlow.YGROMediaPlayerBootFlow",
}
local savedUrls = {}

local function findPlayers()
    local out, seen = {}, {}
    for _, p in ipairs(KNOWN_PLAYERS) do
        local o = try(function() return StaticFindObject(p) end)
        if o and o:IsValid() then
            local n = tostring(try(function() return o:GetFName():ToString() end))
            if not seen[n] then seen[n] = true; out[#out + 1] = o end
        end
    end
    local all = try(function() return FindAllOf("MediaPlayer") end)
    if all then
        for _, o in pairs(all) do
            if isRealActor(o) or (o and o:IsValid()) then
                local n = tostring(try(function() return o:GetFName():ToString() end))
                if n and not seen[n] and not string.find(n, "Default__", 1, true) then
                    seen[n] = true; out[#out + 1] = o
                end
            end
        end
    end
    return out
end

local function hijackVideo(Ar)
    local players = findPlayers()
    if #players == 0 then say(Ar, "aucun lecteur media charge (es-tu au menu ?)"); return end
    local ok = 0
    for _, p in ipairs(players) do
        local n = tostring(try(function() return p:GetFName():ToString() end))
        if savedUrls[n] == nil then
            savedUrls[n] = tostring(try(function() return p:GetUrl() end) or "")
        end
        try(function() p.NativeAudioOut = true end)
        try(function() p.PlayOnOpen = true end)
        local opened = try(function() return p:OpenFile(CFG.video) end)
        if opened == false or opened == nil then
            opened = try(function() return p:OpenUrl("file://" .. CFG.video) end)
        end
        try(function() p:SetLooping(true) end)
        try(function() p:Play() end)
        if opened ~= false then ok = ok + 1 end
        say(Ar, "  " .. n .. " : " .. (opened == false and "refuse" or "ouvert"))
    end
    say(Ar, ok .. "/" .. #players .. " lecteur(s) sur " .. CFG.video)
end

local function restoreVideo(Ar)
    for _, p in ipairs(findPlayers()) do
        local n = tostring(try(function() return p:GetFName():ToString() end))
        local u = savedUrls[n]
        if u and u ~= "" then
            try(function() p:OpenUrl(u) end); try(function() p:Play() end)
            say(Ar, "  " .. n .. " restaure")
        else
            try(function() p:Close() end)
        end
    end
end

-- ---------------------------------------------------------------------------
--  Commandes
-- ---------------------------------------------------------------------------
local function cmdTest(Ar)
    local pawn = GetPawn()
    if not pawn then say(Ar, "joueur introuvable"); return end
    if not loadData(Ar) then return end
    if not buildScreen(pawn, Ar) then return end

    local mesh, label = resolveMesh(Ar)
    say(Ar, "mesh : " .. tostring(label or "AUCUN"))
    if not mesh then return end

    local cls = try(function() return StaticFindObject(SMA_CLASS) end)
    say(Ar, "classe StaticMeshActor : " .. (cls and cls:IsValid() and "ok" or "INTROUVABLE"))
    if not (cls and cls:IsValid()) then return end

    local loc = { X = SCREEN.cx, Y = SCREEN.cy, Z = SCREEN.cz }
    local a, how = spawnActor(cls, loc, SCREEN.yaw)
    say(Ar, "spawn : " .. tostring(how))
    if not a then return end

    local hasSmc = dressCube(a, mesh, SCREEN.yaw)
    say(Ar, "composant StaticMesh : " .. (hasSmc and "ok" or "ABSENT"))
    try(function() a:SetActorScale3D({ X = 5.0, Y = 5.0, Z = 5.0 }) end)
    try(function() a:SetActorHiddenInGame(false) end)
    say(Ar, ("un cube devrait etre visible a %.0f uu devant toi, %.0f uu en hauteur.")
        :format(CFG.dist, CFG.height))
    say(Ar, "rien ? -> `badapple set dist 1500`, `badapple set height 300`, puis retente.")
    say(Ar, "`badapple stop` le detruira avec le reste.")
    POOL[#POOL + 1] = { actor = a, x = -1, y = -1, w = -1, h = -1, hidden = false }
end

-- Full diagnostic: every step is READ BACK instead of being assumed successful.
-- Places a cube 4 m in front of the camera, at chest height: impossible to miss
-- if it really is being drawn.
local function cmdProbe(Ar)
    local pawn = GetPawn()
    if not pawn then say(Ar, "joueur introuvable"); return end
    local loc = ProbeLocation(pawn)
    if not loc then say(Ar, "position du joueur illisible"); return end
    local prot = try(function() return pawn:K2_GetActorRotation() end)
    local vyaw, vsrc = GetViewYaw(pawn)
    say(Ar, ("joueur : X=%.0f Y=%.0f Z=%.0f"):format(loc.X, loc.Y, loc.Z))
    say(Ar, ("yaw pawn=%.0f | yaw vue=%.0f (%s)"):format((prot and prot.Yaw) or 0, vyaw, vsrc))

    local mesh, mlabel = resolveMesh(Ar)
    if not mesh then say(Ar, "AUCUN mesh utilisable"); return end
    say(Ar, "mesh : " .. tostring(mlabel))

    local cls = try(function() return StaticFindObject(SMA_CLASS) end)
    if not (cls and cls:IsValid()) then say(Ar, "classe StaticMeshActor introuvable"); return end

    local yr = math.rad(vyaw)
    local dest = { X = loc.X + math.cos(yr) * 400.0,
                   Y = loc.Y + math.sin(yr) * 400.0,
                   Z = loc.Z + 150.0 }
    local a, how = spawnActor(cls, dest, vyaw)
    if not a then say(Ar, "spawn KO : " .. tostring(how)); return end
    say(Ar, "spawn : " .. tostring(how))

    local smc = meshComponent(a)
    say(Ar, "composant de rendu : " .. (smc and "trouve" or "ABSENT"))
    if not smc then return end

    local mobBefore = try(function() return smc.Mobility end)
    local okMob = pcall(function() a:SetMobility(2) end)
    local mobAfter = try(function() return smc.Mobility end)
    say(Ar, ("mobility : avant=%s appel=%s apres=%s   (2 = Movable)")
        :format(tostring(mobBefore), tostring(okMob), tostring(mobAfter)))

    local callOk, ret = pcall(function() return smc:SetStaticMesh(mesh) end)
    local assigned = try(function() return smc.StaticMesh end)
    say(Ar, ("SetStaticMesh : appel=%s retour=%s -> StaticMesh=%s")
        :format(tostring(callOk), tostring(ret),
                assigned and tostring(try(function() return assigned:GetFName():ToString() end))
                          or "NUL  <<< la cause si c'est NUL"))

    pcall(function() a:SetActorScale3D({ X = 3.0, Y = 3.0, Z = 3.0 }) end)
    pcall(function() a:SetActorHiddenInGame(false) end)
    pcall(function() smc:SetVisibility(true, true) end)
    pcall(function() smc:SetHiddenInGame(false, true) end)

    local rloc = ProbeLocation(a)
    local rsc  = try(function() return a:GetActorScale3D() end)
    say(Ar, ("demande : X=%.0f Y=%.0f Z=%.0f"):format(dest.X, dest.Y, dest.Z))
    say(Ar, ("relu    : X=%.0f Y=%.0f Z=%.0f  echelle=%s")
        :format(rloc and rloc.X or 0, rloc and rloc.Y or 0, rloc and rloc.Z or 0,
                rsc and ("%.1f"):format(rsc.X) or "?"))
    say(Ar, ("visibilite : bHidden=%s bVisible=%s bHiddenInGame=%s IsVisible=%s")
        :format(tostring(try(function() return a.bHidden end)),
                tostring(try(function() return smc.bVisible end)),
                tostring(try(function() return smc.bHiddenInGame end)),
                tostring(try(function() return smc:IsVisible() end))))
    say(Ar, "materiau 0 : " .. tostring(try(function()
        local m = smc:GetMaterial(0)
        return m and m:GetFName():ToString() or "NUL"
    end)))

    say(Ar, "un cube de 3 m est cense etre a 4 m devant la camera, hauteur torse.")
    say(Ar, "verdict du moteur dans 1 s (regarde le log UE4SS)...")
    -- WasRecentlyRendered is the ONLY proof that the engine really drew it.
    -- Ar is dead past this point: we only log through log() from now on.
    -- ExecuteWithDelay already runs on the game thread: no nesting with
    -- ExecuteInGameThread (cf. the warning about the cadence further down).
    ExecuteWithDelay(1200, function()
        if not (a and a:IsValid()) then log("l'acteur a disparu entre-temps") return end
        local seen = try(function() return a:WasRecentlyRendered(1.0) end)
        log("WasRecentlyRendered = " .. tostring(seen))
        if seen == true then
            log("-> le moteur le DESSINE : le probleme est le cadrage/l'echelle, pas le rendu.")
        else
            log("-> le moteur ne le dessine PAS : mesh nul, materiau, ou hors champ.")
        end
    end)
    POOL[#POOL + 1] = { actor = a, x = -1, y = -1, w = -1, h = -1, hidden = false }
end

local function cmdPlay(Ar, kind)
    local pawn = GetPawn()
    if not pawn then say(Ar, "joueur introuvable"); return end
    if not loadData(Ar) then return end
    if not buildScreen(pawn, Ar) then return end
    ismDestroy()   -- clears any ISM left over from a previous playback

    -- ISM mode: a single instanced component, zero trailing. We resolve the mesh
    -- and the material as in cubes mode, then build the component.
    if kind == "ism" then
        destroyPool()   -- in case an actor pool was running
        local mesh = resolveMesh(Ar)
        if not mesh then say(Ar, "ISM: aucun mesh cube utilisable"); return end
        local matObj = nil
        if CFG.mat ~= "" then
            local p = MAT_PRESETS[CFG.mat:lower()] or CFG.mat
            matObj = try(function() return StaticFindObject(p) end)
        end
        if not ismBuild(mesh, matObj, Ar) then return end
        buildBackdrop(mesh, Ar)
        POOL_KIND = "ism"
    else
        local n = (kind == "enemies") and math.min(CFG.pool, DATA.meta.lowW * DATA.meta.lowH) or CFG.pool
        if kind == "enemies" then
            say(Ar, "mode ennemis : " .. DATA.meta.lowW .. "x" .. DATA.meta.lowH
                 .. " cellules, jusqu'a " .. n .. " ennemis a l'ecran. Ca va ramer, c'est le jeu.")
            say(Ar, "trop lent ? `badapple stop`, `badapple set pool 64`, puis relance.")
        end
        if not buildPool(kind or "cubes", n, Ar) then return end
    end

    lostActors = 0
    resetClock()
    PLAY.t0, PLAY.last, PLAY.paused, PLAY.on = nil, -1, false, true

    -- STARTUP TEST PATTERN, drawn SYNCHRONOUSLY (so without depending on the
    -- EngineTick hook): the screen is never empty at launch, and if it stays
    -- FROZEN the diagnosis is immediate -> the loop isn't running.
    -- We take the 1st NON-EMPTY frame: the video opens on ~1.4 s of black, so
    -- frame 1 would prove nothing. PLAY.last stays at -1, so the loop does
    -- resume from frame 1 and the test pattern disappears right away.
    -- We want a READABLE frame, not the first one with a single stray rectangle.
    local probeIdx, fallback = nil, nil
    local perRect = 4 * DATA.meta.charsPerField
    for i = 1, math.min(600, DATA.meta.frames) do
        local r = frameStrings(i)
        local nr = r and (#r / perRect) or 0
        if nr > 0 and not fallback then fallback = i end
        if nr >= 8 then probeIdx = i break end
    end
    probeIdx = probeIdx or fallback or 1
    local drawn = renderFrame(probeIdx)
    startChain()
    applyCleanGfx(Ar, true)   -- cuts motion blur + temporal AA (anti-trailing)
    say(Ar, ("lecture lancee (%s). Mire : image %d, %d rectangles."):format(
        kind or "cubes", probeIdx, drawn))
    say(Ar, "Elle doit disparaitre aussitot (la video ouvre sur 1,4 s de noir).")
    say(Ar, "Elle reste FIGEE ? -> le hook EngineTick d'UE4SS a saute : redemarre le jeu.")
    say(Ar, "Sinon lance badapple_audio.mp4 maintenant. `badapple stop` pour tout detruire.")
end

-- Render diagnostic: compares what SHOULD be on screen (data) with what really
-- is (actor state).
local function cmdStat(Ar)
    if POOL_KIND == "ism" then
        local idx = PLAY.last
        local r = frameStrings(idx)
        local expected = r and (#r / (4 * DATA.meta.charsPerField)) or 0
        local cnt = (ISM.comp and ISM.comp:IsValid()) and try(function() return ISM.comp:GetInstanceCount() end) or 0
        say(Ar, ("mode ISM : image %d, %d rectangles attendus, %d instances dans le composant")
            :format(idx, math.floor(expected), cnt or 0))
        say(Ar, "en ISM il n'y a pas de fantome possible (1 composant, instances collapsees).")
        return
    end
    if not (DATA and #POOL > 0) then say(Ar, "rien en cours (lance `badapple play`)"); return end
    local idx = PLAY.last
    local r = frameStrings(idx)
    local expected = 0
    if r then expected = #r / (4 * DATA.meta.charsPerField) end

    -- Expected parking position (very low Z). A "hidden" cube must be there.
    local park = parkSpot()
    local flagVis, invalid = 0, 0
    local hidVis, hidParked, hidStuck = 0, 0, 0   -- for the slots marked hidden
    for _, s in ipairs(POOL) do
        if not s.hidden then flagVis = flagVis + 1 end
        local a = s.actor
        if a and a:IsValid() then
            if s.hidden then
                -- Is a hidden cube REALLY out of frame? We read its position.
                local loc = try(function() return a:K2_GetActorLocation() end)
                local far = loc and (math.abs((loc.Z or 0) - park.Z) < 5000.0)
                local h = try(function() return a.bHidden end)
                local reallyHidden = (h == true or h == 1)
                if far then hidParked = hidParked + 1
                elseif reallyHidden then hidVis = hidVis + 1     -- flagged hidden but NOT parked (masking assumed OK)
                else hidStuck = hidStuck + 1 end                 -- neither parked nor masked = visible GHOST
            end
        else
            invalid = invalid + 1
        end
    end
    say(Ar, ("image %d : %d rectangles attendus, mod pense %d visibles"):format(
        idx, math.floor(expected), flagVis))
    say(Ar, ("caches : %d gares(hors champ) + %d masques-non-gares + %d FANTOMES-visibles ; invalides=%d")
        :format(hidParked, hidVis, hidStuck, invalid))
    if hidStuck > 0 then
        say(Ar, ("-> %d cube(s) FANTOME visibles : le garage echoue. C'est le vrai bug."):format(hidStuck))
    elseif hidVis > 0 then
        say(Ar, ("-> %d caches non gares mais masques : OK SI SetActorHiddenInGame cache vraiment."):format(hidVis))
        say(Ar, "   Si tu vois quand meme des rectangles, c'est que le masquage seul ne suffit pas.")
    else
        say(Ar, "-> tous les caches sont gares hors champ : aucun fantome possible.")
    end
    say(Ar, ("fond present=%s"):format(tostring(BACKDROP ~= nil and BACKDROP:IsValid())))
end

local function cmdInfo(Ar)
    say(Ar, "etat : " .. (PLAY.on and (PLAY.paused and "en pause" or "en lecture") or "arrete")
         .. "  mode=" .. tostring(POOL_KIND or "-")
         .. "  image=" .. tostring(PLAY.last) .. "/" .. (DATA and DATA.meta.frames or "?"))
    say(Ar, ("acteurs=%d  perdus=%d"):format(#POOL, lostActors))
    if PLAY.on and PLAY.last <= 1 then
        say(Ar, "!! l'image n'a jamais avance : la boucle ne tourne pas.")
        say(Ar, "!! le hook EngineTick d'UE4SS a ete retire par une erreur anterieure.")
        say(Ar, "!! -> REDEMARRE LE JEU (plus aucun mod Lua ne recoit de tick).")
    end
    say(Ar, ("cell=%.0f dist=%.0f height=%.0f pool=%d thickness=%.2f meshsize=%.0f loop=%d")
        :format(CFG.cell, CFG.dist, CFG.height, CFG.pool, CFG.thickness, CFG.meshsize, CFG.loop))
    say(Ar, "mesh=" .. (CFG.mesh ~= "" and CFG.mesh or "auto")
         .. "  mat=" .. (CFG.mat ~= "" and CFG.mat or "defaut")
         .. "  class=" .. (CFG.class ~= "" and CFG.class or "StaticMeshActor"))
    say(Ar, "video (route 2) = " .. CFG.video)
end

RegisterConsoleCommandHandler("badapple", function(FullCommand, Parameters, Ar)
    local sub = (Parameters and Parameters[1] or ""):lower()

    if sub == "" or sub == "help" then
        say(Ar, "test | probe | play [ism|enemies] | pause | resume | stop | frame <n> | info | stat")
        say(Ar, "play ism = mode InstancedStaticMesh : ZERO trainee (recommande si tu vois des restes)")
        say(Ar, "gfx on|off  = effets par defaut / mode propre (anti-trainee)")
        say(Ar, "aa <0|1|2|4> = anti-aliasing (0/1 sans trainee, 4 = defaut du jeu)")
        say(Ar, "probe = diagnostic complet : cube a 4 m devant la CAMERA + relecture de tout")
        say(Ar, "set <cell|dist|height|pool|thickness|meshsize|enemycell|bgpad|resync|loop> <nombre>")
        say(Ar, "set bg black|none      fond noir derriere l'image (defaut black)")
        say(Ar, "set mat alienware      pixels sombres (materiau du coffre ALIENWARE)")
        say(Ar, "set class chest        pixels = vrais coffres ALIENWARE etires")
        say(Ar, "set mesh|mat|class|bg <chemin>  pour un asset quelconque")
        say(Ar, "video [chemin] | video stop")
        say(Ar, "COMMENCE PAR `badapple test` : il spawn un seul cube et dit ce qui marche.")
        return true
    end

    if sub == "test"  then cmdTest(Ar)  return true end
    if sub == "probe" then cmdProbe(Ar) return true end
    if sub == "play"  then
        local a2 = (Parameters[2] or ""):lower()
        local kind = (a2 == "enemies" and "enemies") or (a2 == "ism" and "ism") or "cubes"
        cmdPlay(Ar, kind)
        return true
    end

    if sub == "pause"  then PLAY.paused = true;  say(Ar, "pause");   return true end
    if sub == "resume" then
        -- We shift t0 to resume from the frame where we stopped.
        local t = realSeconds()
        if t and PLAY.last > 0 then PLAY.t0 = t - (PLAY.last - 1) / DATA.meta.fps end
        PLAY.paused = false; say(Ar, "reprise"); return true
    end

    if sub == "stop" then
        stopPlayback()
        destroyPool()
        ismDestroy()
        restoreVideo(Ar)
        applyCleanGfx(Ar, false)   -- rend au jeu ses effets graphiques normaux
        say(Ar, "arrete, acteurs detruits")
        return true
    end

    if sub == "frame" then
        local n = tonumber(Parameters[2] or "")
        if not n then say(Ar, "usage : badapple frame 121"); return true end
        local pawn = GetPawn()
        if not pawn or not loadData(Ar) then return true end
        -- Nothing ready? We set up a mode (ISM running -> we keep it).
        if POOL_KIND ~= "ism" and #POOL == 0 then
            if not buildScreen(pawn, Ar) then return true end
            if not buildPool("cubes", CFG.pool, Ar) then return true end
        end
        n = math.max(1, math.min(DATA.meta.frames, math.floor(n)))
        local drawn = renderFrame(n)
        say(Ar, ("image %d affichee : %d rectangles"):format(n, drawn))
        return true
    end

    if sub == "info" then
        if not DATA then loadData(Ar) end
        cmdInfo(Ar); return true
    end

    if sub == "stat" then cmdStat(Ar); return true end

    if sub == "gfx" then
        local a2 = (Parameters[2] or ""):lower()
        applyCleanGfx(Ar, a2 == "on")   -- "on" = effets par defaut ; sinon = mode propre
        return true
    end

    if sub == "aa" then
        local nn = tonumber(Parameters[2] or "")
        if not nn then say(Ar, "usage : badapple aa <0=aucun|1=FXAA|2=TAA|4=TSR>"); return true end
        Console("r.AntiAliasingMethod " .. math.floor(nn))
        say(Ar, "AntiAliasingMethod = " .. math.floor(nn) .. " (4 = defaut du jeu ; 1/0 cassent le TSR)")
        return true
    end

    -- Reduces temporal trailing WITHOUT touching the AA method (TSR intact).
    if sub == "ghost" then
        local w = tonumber(Parameters[2] or "")
        w = w or 0.8   -- 0.04 = defaut UE ; plus haut = moins d'historique = moins de trainee
        Console("r.TemporalAACurrentFrameWeight " .. tostring(w))
        Console("r.TSR.History.ScreenPercentage 100")
        say(Ar, ("poids image courante = %.2f (0.04 defaut ; ~0.8 tue la trainee)"):format(w))
        return true
    end

    if sub == "set" then
        local key = (Parameters[2] or ""):lower()
        local raw = FullCommand:match("^%s*badapple%s+set%s+%S+%s+(.+)$")
        if not raw then say(Ar, "usage : badapple set dist 3000"); return true end
        raw = raw:gsub('^"(.*)"$', "%1")
        if key == "mesh" or key == "class" or key == "mat" or key == "bg" then
            CFG[key] = raw
        elseif CFG[key] ~= nil then
            local v = tonumber(raw)
            if not v then say(Ar, "valeur numerique attendue"); return true end
            CFG[key] = v
        else
            say(Ar, "cle inconnue : " .. key); return true
        end
        say(Ar, key .. " = " .. tostring(CFG[key]))
        if key == "cell" or key == "dist" or key == "height" or key == "meshsize" then
            -- The slots remember their last position: we invalidate them so
            -- the next frame repositions everything.
            for _, s in ipairs(POOL) do s.x, s.y, s.w, s.h = -1, -1, -1, -1 end
            local pawn = GetPawn()
            if pawn and DATA then buildScreen(pawn, Ar) end
        end
        return true
    end

    if sub == "video" then
        local arg2 = (Parameters[2] or ""):lower()
        if arg2 == "stop" then restoreVideo(Ar); say(Ar, "lecteurs restaures"); return true end
        local raw = FullCommand:match("^%s*badapple%s+video%s+(.+)$")
        if raw then CFG.video = raw:gsub("\\", "/"):gsub('^"(.*)"$', "%1") end
        say(Ar, "detournement vers " .. CFG.video)
        hijackVideo(Ar)
        return true
    end

    say(Ar, "sous-commande inconnue : " .. sub .. "  (`badapple help`)")
    return true
end)

log("charge. `badapple help` pour les commandes, `badapple test` pour valider le spawn.")
