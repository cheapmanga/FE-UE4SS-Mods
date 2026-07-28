-- ============================================================================
--  FADING ECHO — GAME SPEED  (v1)
--  Slow-motion / fast-forward for the whole game.
--    gamespeed             show the current dilation
--    gamespeed <n>         set it (0.1 = very slow, 1 = normal, 3 = fast)
--    gamespeed reset       back to 1.0
--  In-game console: ² key  (AZERTY)
-- ============================================================================
local UEHelpers = require("UEHelpers")

local function log(m) print("[GameSpeed] " .. tostring(m) .. "\n") end

-- ⚠️ Ar (FOutputDevice) is valid ONLY in the SYNCHRONOUS body of the handler.
-- Using it from deferred code is a dead pointer -> EXCEPTION_ACCESS_VIOLATION.
local function cout(Ar, m)
    pcall(function() if Ar then Ar:Log("[gamespeed] " .. tostring(m)) end end)
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

-- real object = not a Class Default Object (the CDO is a template, not alive).
local function isRealObject(o)
    if not okObj(o) then return false end
    local fn = ""
    pcall(function() fn = o:GetFullName() end)
    return not string.find(fn, "Default__", 1, true)
end

local function GetPC()
    local cs = try(function() return FindAllOf("PlayerController") end)
    if cs then
        for _, c in pairs(cs) do
            if isRealObject(c) then return c end
        end
    end
    return try(UEHelpers.GetPlayerController)
end

local function GetPawn()
    local ps = try(function() return FindAllOf("BP_CoreYgroCharacter_C") end)
    if ps then
        for _, p in pairs(ps) do
            if isRealObject(p) then return p end
        end
    end
    return nil
end

-- An actor is a valid WorldContextObject, so the pawn is a usable fallback.
local function GetWorldCtx()
    local w = try(UEHelpers.GetWorld)
    if okObj(w) then return w end
    w = try(UEHelpers.GetWorldContextObject)
    if okObj(w) then return w end
    return GetPawn()
end

local function GSL()
    local o = try(UEHelpers.GetGameplayStatics)
    if okObj(o) then return o end
    return try(function() return StaticFindObject("/Script/Engine.Default__GameplayStatics") end)
end

local DEFAULT_SPEED = 1.0
local current = DEFAULT_SPEED

-- UGameplayStatics::SetGlobalTimeDilation(WorldContextObject, TimeDilation).
-- Engine-level, so it slows physics and animation too, not just the character.
local function ApplySpeed(n)
    local gs, w = GSL(), GetWorldCtx()
    if not (gs and w) then return false, "world not found" end
    local ok = try(function() gs:SetGlobalTimeDilation(w, n * 1.0); return true end)
    if ok ~= true then return false, "SetGlobalTimeDilation failed" end
    current = n
    return true
end

local function ReadSpeed()
    local gs, w = GSL(), GetWorldCtx()
    if not (gs and w) then return nil end
    return try(function() return gs:GetGlobalTimeDilation(w) end)
end

RegisterConsoleCommandGlobalHandler("gamespeed", function(FullCommand, Parameters, Ar)
    local a1 = string.lower(tostring(Parameters[1] or ""))

    if a1 == "" or a1 == "status" then
        local live = ReadSpeed()
        cout(Ar, ("dilation = %s%s"):format(
            tostring(live or current),
            live == nil and "  (read failed, showing the last value we set)" or ""))
        cout(Ar, "usage: gamespeed <n>  |  gamespeed reset   (1 = normal)")
        return true
    end

    if a1 == "reset" or a1 == "off" then
        local ok, why = ApplySpeed(DEFAULT_SPEED)
        cout(Ar, ok and "back to normal speed (1.0)." or ("failed: " .. tostring(why)))
        return true
    end

    local n = tonumber(a1)
    if not n then
        cout(Ar, "usage: gamespeed <n>  |  gamespeed reset")
        return true
    end

    -- The engine accepts 0, but a 0 dilation freezes the game with no way back
    -- through this same console. Clamp low; keep the ceiling sane too.
    if n < 0.05 then n = 0.05 end
    if n > 10.0 then n = 10.0 end

    local ok, why = ApplySpeed(n)
    if ok then
        cout(Ar, ("dilation set to %s"):format(tostring(n)))
    else
        cout(Ar, "failed: " .. tostring(why))
    end
    return true
end)

log("loaded. console (²): gamespeed <n> | gamespeed reset")
