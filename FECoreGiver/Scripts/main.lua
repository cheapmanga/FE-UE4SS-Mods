-- ============================================================================
--  FADING ECHO — CORE GIVER
--
--  Standalone extract of the "CORE GIVER" block from the FE Unlocker: just the
--  core-granting part, without the elevators / zones / alpha walls / doors.
--
--  In-game console (F10):
--    core <element>          waste | fire | water | glitch | power
--    core <element> nograb   drops it in front of you without grabbing it
--    core list               lists the available elements
--
--  Everything runs in pcall: if one piece fails, the game keeps going.
-- ============================================================================

local UEHelpers = require("UEHelpers")

local function log(m) print("[CoreGiver] " .. tostring(m) .. "\n") end

-- Writes both to the in-game console (Ar) and to the UE4SS console.
local function cout(Ar, msg)
    pcall(function() if Ar then Ar:Log(msg) end end)
    log(msg)
end

-- ---------------------------------------------------------------------------
--  Player helpers
-- ---------------------------------------------------------------------------
-- real actor = not a Class Default Object (the CDO sits at the origin 0,0,0).
-- /!\ a:IsValid() CRASHES if `a` is not a UObject ("attempt to call a nil
-- value (method 'IsValid')"), so it goes through pcall like GetFullName().
local function isRealActor(a)
    if not a then return false end
    local valid = false; pcall(function() valid = a:IsValid() end)
    if not valid then return false end
    local fn = ""; pcall(function() fn = a:GetFullName() end)
    return not string.find(fn, "Default__", 1, true)
end

local function GetPawn()
    -- 1) pawn possessed by the PlayerController (the most reliable)
    local cs = FindAllOf("PlayerController")
    if cs then
        for _, c in pairs(cs) do
            if c and c:IsValid() then
                local pk = c.Pawn
                if isRealActor(pk) then return pk end
            end
        end
    end
    -- 2) helper UE4SS
    local ok, p = pcall(UEHelpers.GetPlayerPawn)
    if ok and isRealActor(p) then return p end
    -- 3) last resort: a NON-CDO instance of the character
    local list = FindAllOf("BP_CoreYgroCharacter_C")
    if list then
        for _, a in pairs(list) do
            if isRealActor(a) then return a end
        end
    end
    return nil
end

-- ============================================================================
--  CORE GIVER
--
--  Spawns an elemental core in front of the player (BP_PortableItem_<X>Ball,
--  derives from BP_PortableItem_C) then puts it in their hands via StartGrab.
--  The grab triggers the game's elemental charge (UI + LB + power).
--  Spawn = BeginDeferredActorSpawnFromClass + FinishSpawningActor (6 UE5 args).
--  Actual elements: Water, Waste, Lava(=fire), Corruption(=glitch).
-- ============================================================================
local CORE_BASE = "/Game/Game/Placeable/InteractiveObjects/PortableItem/"
local CORE_ELEMENTS = {
    waste  = { path = CORE_BASE .. "BP_PortableItem_WasteBall.BP_PortableItem_WasteBall_C",           short = "BP_PortableItem_WasteBall_C",      label = "Waste" },
    fire   = { path = CORE_BASE .. "BP_PortableItem_LavaBall.BP_PortableItem_LavaBall_C",             short = "BP_PortableItem_LavaBall_C",       label = "Lava (fire)" },
    water  = { path = CORE_BASE .. "BP_PortableItem_WaterBall.BP_PortableItem_WaterBall_C",           short = "BP_PortableItem_WaterBall_C",      label = "Water" },
    glitch = { path = CORE_BASE .. "BP_PortableItem_CorruptionBall.BP_PortableItem_CorruptionBall_C", short = "BP_PortableItem_CorruptionBall_C", label = "Corruption (glitch)" },
    power  = { path = CORE_BASE .. "BP_PortableItem_Power.BP_PortableItem_Power_C",                   short = "BP_PortableItem_Power_C",          label = "PowerCore" },
}

-- Stable display order for "core list" (CORE_ELEMENTS is a hash table).
local CORE_ORDER = { "waste", "fire", "water", "glitch", "power" }

-- Ball's UClass: the class object if loaded, otherwise the class of a present instance.
local function ResolveCoreClass(e)
    local c = StaticFindObject(e.path)
    if c and c:IsValid() then return c end
    local inst = FindFirstOf(e.short)
    if inst and inst:IsValid() then
        local ok, k = pcall(function() return inst:GetClass() end)
        if ok and k and k:IsValid() then return k end
    end
    return nil
end

-- Spawns the ball in front of the player. Returns (actor, nil) or (nil, message).
local function SpawnCoreBall(e, pawn)
    local world = UEHelpers.GetWorld()
    if not (world and world:IsValid()) then return nil, "world not found." end
    local GS = StaticFindObject("/Script/Engine.Default__GameplayStatics")
    if not (GS and GS:IsValid()) then return nil, "GameplayStatics not found." end
    local KML = StaticFindObject("/Script/Engine.Default__KismetMathLibrary")
    if not (KML and KML:IsValid()) then return nil, "KismetMathLibrary not found." end
    local cls = ResolveCoreClass(e)
    if not (cls and cls:IsValid()) then
        return nil, "class not loaded (" .. e.short .. "). walk up to a " ..
                    e.label .. " core once to load it, then try again."
    end

    -- The pawn can be torn down between GetPawn() and here (level transition or
    -- respawn racing the console command) : never call it bare.
    local loc, fwd
    local okP = pcall(function()
        loc = pawn:K2_GetActorLocation()
        fwd = pawn:GetActorForwardVector()
    end)
    if not okP or not loc or not fwd then return nil, "player not found." end
    local pos = { X = loc.X + fwd.X * 120.0, Y = loc.Y + fwd.Y * 120.0, Z = loc.Z + 40.0 }
    local xf
    local okT = pcall(function()
        xf = KML:MakeTransform(pos, { Pitch = 0.0, Yaw = 0.0, Roll = 0.0 }, { X = 1.0, Y = 1.0, Z = 1.0 })
    end)
    if not okT or not xf then return nil, "MakeTransform failed." end

    local actor
    local okS, errS = pcall(function()
        actor = GS:BeginDeferredActorSpawnFromClass(world, cls, xf, 1, nil, 0)  -- 1 = AlwaysSpawn
    end)
    if not okS then return nil, "spawn raised: " .. tostring(errS) end
    if not (actor and actor:IsValid()) then return nil, "spawn returned a null actor." end

    for _, n in ipairs({ 3, 2 }) do   -- FinishSpawningActor: 3 args (recent UE5) or 2
        local okF = pcall(function()
            if n == 3 then GS:FinishSpawningActor(actor, xf, 0) else GS:FinishSpawningActor(actor, xf) end
        end)
        if okF then break end
    end
    return actor, nil
end

RegisterConsoleCommandGlobalHandler("core", function(FullCommand, Parameters, Ar)
    local p = Parameters or {}
    local key = (p[1] and string.lower(p[1])) or ""

    if key == "list" or key == "help" then
        cout(Ar, "──── available cores ────")
        for _, k in ipairs(CORE_ORDER) do
            cout(Ar, string.format("  %-7s %s", k, CORE_ELEMENTS[k].label))
        end
        cout(Ar, "→ core <element> [nograb]")
        return true
    end

    local e = CORE_ELEMENTS[key]
    if not e then
        cout(Ar, "[core] usage: core waste|fire|water|glitch|power [nograb]  |  core list")
        return true
    end
    -- 'nograb': the core appears on the ground without being grabbed (to test
    -- the infinite core in One's form: spawn a core and don't absorb it).
    local nograb = false
    for _, tok in ipairs(p) do
        local t = string.lower(tok)
        if t == "nograb" or t == "drop" or t == "nopickup" then nograb = true end
    end
    local pawn = GetPawn()
    if not pawn then cout(Ar, "[core] player not found."); return true end
    local actor, err = SpawnCoreBall(e, pawn)
    if not actor then cout(Ar, "[core] " .. tostring(err)); return true end
    if nograb then
        cout(Ar, "[core] " .. e.label .. " dropped in front of you (not grabbed).")
    else
        pcall(function() pawn:StartGrab(actor) end)
        cout(Ar, "[core] " .. e.label .. " given.")
    end
    return true
end)

log("loaded. in-game console (F10): core waste|fire|water|glitch|power [nograb]")
