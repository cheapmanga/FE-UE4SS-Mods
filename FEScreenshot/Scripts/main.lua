-- ============================================================================
--  FADING ECHO — HIGH RES SCREENSHOT  (v1)
--  Renders a screenshot at a multiple of the screen resolution.
--    screenshot                  screenshot at the default multiplier (2x)
--    screenshot <n>              multiplier, 1 to 8 (4 = four times the screen size)
--  Files land in: %LOCALAPPDATA%\UE_YGRO\Saved\Screenshots\
--  (packaged builds write Saved\ to LOCALAPPDATA, not the game folder —
--   same place as the Engine.ini the Volume mod uses)
--  In-game console: ² key  (AZERTY)
-- ============================================================================
local UEHelpers = require("UEHelpers")

local function log(m) print("[Screenshot] " .. tostring(m) .. "\n") end

-- ⚠️ Ar (FOutputDevice) is valid ONLY in the SYNCHRONOUS body of the handler.
-- Using it from deferred code is a dead pointer -> EXCEPTION_ACCESS_VIOLATION.
local function cout(Ar, m)
    pcall(function() if Ar then Ar:Log("[screenshot] " .. tostring(m)) end end)
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
    local pc = GetPC()
    local p = pc and try(function() return pc.Pawn end)
    if isRealObject(p) then return p end
    p = try(UEHelpers.GetPlayerPawn)
    if isRealObject(p) then return p end
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

local function KSL()
    local o = try(UEHelpers.GetKismetSystemLibrary)
    if okObj(o) then return o end
    return try(function() return StaticFindObject("/Script/Engine.Default__KismetSystemLibrary") end)
end

-- Execute a game console command. ⚠️ SpecificPlayer must be the current PC
-- (nil fails, lesson from FEDevMenu/FEPerf).
local function Console(cmd)
    local k, w, pc = KSL(), GetWorldCtx(), GetPC()
    if not (k and w) then return false end
    return (try(function() k:ExecuteConsoleCommand(w, cmd, pc); return true end)) == true
end

local DEFAULT_MULT = 2
local MIN_MULT, MAX_MULT = 1, 8
-- Packaged Unreal writes Saved\ under LOCALAPPDATA, NOT the install folder.
-- We point at the Screenshots parent: the platform subfolder is WindowsClient
-- on some builds and Windows on others, so this is the one that always holds.
local SHOT_DIR = "%LOCALAPPDATA%\\UE_YGRO\\Saved\\Screenshots\\"

RegisterConsoleCommandGlobalHandler("screenshot", function(FullCommand, Parameters, Ar)
    local a1 = tostring(Parameters[1] or "")
    local n, note = DEFAULT_MULT, ""

    if a1 ~= "" then
        local v = tonumber(a1)
        -- v ~= v catches NaN, which would slip past the clamps below and then
        -- blow up string.format("%d") with "number has no integer representation".
        if not v or v ~= v then
            cout(Ar, "usage: screenshot  |  screenshot <multiplier " .. MIN_MULT .. "-" .. MAX_MULT .. ">")
            return true
        end
        if v < MIN_MULT then v = MIN_MULT; note = " (clamped up to " .. MIN_MULT .. ")" end
        if v > MAX_MULT then v = MAX_MULT; note = " (clamped down to " .. MAX_MULT .. " — above that the GPU usually chokes)" end
        -- HighResShot takes an integer multiplier; clamp first, then floor, so a
        -- silly value like 1e20 never reaches math.floor as a float.
        n = math.floor(v)
        if n < MIN_MULT then n = MIN_MULT end
    end

    local cmd = string.format("HighResShot %d", n)

    cout(Ar, ("taking a %dx screenshot (%s)%s…"):format(n, cmd, note))
    cout(Ar, "file lands in: " .. SHOT_DIR)

    -- Deferred: the capture is engine work, it belongs on the game thread.
    -- From here on, log() only — Ar is dead outside this synchronous body.
    ExecuteInGameThread(function()
        if Console(cmd) then
            log(cmd .. " sent. Check " .. SHOT_DIR .. " — the newest .png is yours.")
        else
            log("failed to send " .. cmd ..
                " (KismetSystemLibrary, world or PlayerController not found — are you in a level?)")
        end
    end)
    return true
end)

log("loaded. console (²): screenshot | screenshot <1-8>")
log("shots are saved to: " .. SHOT_DIR)
