-- ============================================================================
--  FADING ECHO — GRAVITY  (v1)
--  Low gravity / gravity multiplier, written on the player's CharacterMovement.
--    gravity               show the current scale
--    gravity <n>           set it (1 = normal, 0.3 = floaty, 0 = none)
--    gravity low           preset 0.3
--    gravity reset         restore the value saved at first use
--  In-game console: ² key  (AZERTY)
-- ============================================================================
local UEHelpers = require("UEHelpers")

local function log(m) print("[Gravity] " .. tostring(m) .. "\n") end

-- ⚠️ Ar (FOutputDevice) is valid ONLY in the SYNCHRONOUS body of the handler.
-- Using it from deferred code is a dead pointer -> EXCEPTION_ACCESS_VIOLATION.
local function cout(Ar, m)
    pcall(function() if Ar then Ar:Log("[gravity] " .. tostring(m)) end end)
    log(m)
end

local function try(fn)
    local ok, v = pcall(fn)
    if ok then return v end
    return nil
end

-- Valid object. o:IsValid() CRASHES if `o` is not a UObject, hence the pcall.
local function okObj(o)
    if not o then return false end
    local valid = false
    pcall(function() valid = o:IsValid() end)
    return valid == true
end

local function fullName(o)
    local n = ""
    pcall(function() n = o:GetFullName() end)
    return n
end

-- real object = not a Class Default Object (the CDO is a template, not alive).
local function isRealObject(o)
    if not okObj(o) then return false end
    return not string.find(fullName(o), "Default__", 1, true)
end

-- ---------------------------------------------------------------------------
--  Player pawn / movement component
-- ---------------------------------------------------------------------------
local function GetPawn()
    -- The controller's Pawn is the most reliable source: it always points at the
    -- pawn currently possessed, even right after a respawn.
    local cs = try(function() return FindAllOf("PlayerController") end)
    if cs then
        for _, c in pairs(cs) do
            if okObj(c) then
                local p = try(function() return c.Pawn end)
                if isRealObject(p) then return p end
            end
        end
    end
    local ps = try(function() return FindAllOf("BP_CoreYgroCharacter_C") end)
    if ps then
        for _, p in pairs(ps) do
            if isRealObject(p) then return p end
        end
    end
    local p = try(UEHelpers.GetPlayerPawn)
    if isRealObject(p) then return p end
    return nil
end

-- The property name of the movement component is not the same on every build, so
-- we try the usual ones and, failing that, we go looking for the component itself.
local MOVE_PROPS   = { "CharacterMovement", "CharacterMovementComponent", "MovementComponent" }
local MOVE_CLASSES = { "YgroCharacterMovementComponent", "CharacterMovementComponent" }

local function GetMovement(pawn)
    if not isRealObject(pawn) then
        return nil, "player pawn not found (are you in a level, not in a menu?)"
    end
    for _, prop in ipairs(MOVE_PROPS) do
        local c = try(function() return pawn[prop] end)
        if okObj(c) then return c end
    end
    -- Fallback: enumerate the movement components and keep the one whose
    -- CharacterOwner is our pawn. CDOs are filtered out.
    local pn = fullName(pawn)
    for _, cls in ipairs(MOVE_CLASSES) do
        local cs = try(function() return FindAllOf(cls) end)
        if cs then
            for _, c in pairs(cs) do
                if isRealObject(c) then
                    local owner = try(function() return c.CharacterOwner end)
                    if okObj(owner) and fullName(owner) == pn then return c end
                end
            end
        end
    end
    return nil, "CharacterMovement not found on " .. pn ..
        " (tried " .. table.concat(MOVE_PROPS, "/") .. ", then FindAllOf on " ..
        table.concat(MOVE_CLASSES, "/") .. ")"
end

local function ReadScale()
    local mv = GetMovement(GetPawn())
    if not mv then return nil end
    return try(function() return mv.GravityScale end)
end

-- ---------------------------------------------------------------------------
--  State
-- ---------------------------------------------------------------------------
local MIN_SCALE   = 0.0     -- negative gravity = the character falls upwards forever
local MAX_SCALE   = 20.0
local LOW_PRESET  = 0.3

local Original = nil        -- GravityScale as it was the FIRST time we touched it
local Wanted   = nil        -- nil = we manage nothing, the game is left alone
local Pending  = nil        -- value the stable applier below will write

-- STABLE function, defined ONCE and passed BY REFERENCE to ExecuteInGameThread.
-- Why it must never be recreated: a FRESH closure handed over from a loop is
-- registered by UE4SS and can be freed by the GC before it runs -> "[Lua::Registry::
-- get_function_ref] Ref was not function" -> UE4SS REMOVES the EngineTick hook ->
-- EVERY Lua mod stops until the game restarts, at an unpredictable moment.
-- (Same pattern as FEMoonJump's moonTick.)
local function gravityApply()
    -- Under pcall: an error must NEVER reach the hook (same consequence as above).
    pcall(function()
        local v = Pending
        if v == nil then return end
        local mv = GetMovement(GetPawn())
        if not mv then return end
        mv.GravityScale = v * 1.0
    end)
end

-- Queue a write for the game thread. Reads are fine from here, WRITES are not.
local function Push(v)
    Pending = v
    ExecuteInGameThread(gravityApply)   -- same ref every time, GC-safe
end

-- The game RECOMPUTES this value itself (AYgroCharacter drives movement from its
-- own curves / form settings), so a one-shot write is overwritten within a frame.
-- We therefore re-assert at ~30 Hz, and only while the user asked for a value.
-- The write happens ONLY when the value has actually drifted, so a quiet frame
-- costs one property read. `gravity reset` sets Wanted = nil and the loop idles.
LoopAsync(33, function()
    if Wanted ~= nil then
        pcall(function()
            local cur = ReadScale()
            if cur == nil then return end
            if math.abs(cur - Wanted) > 0.0001 then Push(Wanted) end
        end)
    end
    return false
end)

-- ---------------------------------------------------------------------------
--  Console
-- ---------------------------------------------------------------------------
local USAGE = "usage: gravity <n> | gravity low | gravity reset   (1 = normal, 0.3 = floaty, 0 = none)"

RegisterConsoleCommandGlobalHandler("gravity", function(FullCommand, Parameters, Ar)
    local p  = Parameters or {}
    local a1 = string.lower(tostring(p[1] or ""))

    if a1 == "" or a1 == "status" then
        local live = ReadScale()
        cout(Ar, ("GravityScale = %s%s"):format(
            tostring(live or Wanted or "?"),
            live == nil and "  (read failed — pawn or CharacterMovement not reachable)" or ""))
        cout(Ar, ("original = %s   managed = %s"):format(
            tostring(Original or "not saved yet"), tostring(Wanted ~= nil)))
        cout(Ar, USAGE)
        return true
    end

    -- Resolve the component synchronously: it is a READ, and it lets us report a
    -- real diagnostic through Ar instead of failing silently in the game thread.
    local pawn   = GetPawn()
    local mv, why = GetMovement(pawn)
    if not mv then
        cout(Ar, "failed: " .. tostring(why))
        return true
    end

    local live = try(function() return mv.GravityScale end)
    if live == nil then
        cout(Ar, "failed: GravityScale is not readable on this CharacterMovement.")
        return true
    end
    if Original == nil then Original = live end

    if a1 == "reset" or a1 == "off" then
        local back = Original or 1.0
        Wanted = nil                    -- stop the background re-apply
        Push(back)
        cout(Ar, ("restored: GravityScale = %s (original)."):format(tostring(back)))
        return true
    end

    local n
    if a1 == "low" then
        n = LOW_PRESET
    else
        n = tonumber(a1)
    end
    if not n then
        cout(Ar, USAGE)
        return true
    end

    -- A negative scale makes the character fall upwards with no way to land, and a
    -- huge one nails it to the floor. Clamp both ends and say so.
    local clamped = n
    if clamped < MIN_SCALE then clamped = MIN_SCALE end
    if clamped > MAX_SCALE then clamped = MAX_SCALE end
    if clamped ~= n then
        cout(Ar, ("%s is out of range, clamped to %s (allowed: %s..%s)."):format(
            tostring(n), tostring(clamped), tostring(MIN_SCALE), tostring(MAX_SCALE)))
    end

    Wanted = clamped
    Push(clamped)
    cout(Ar, ("GravityScale = %s  (was %s, original %s) — held against the game's own updates."):format(
        tostring(clamped), tostring(live), tostring(Original)))
    return true
end)

log("loaded. console (²): gravity <n> | gravity low | gravity reset")
