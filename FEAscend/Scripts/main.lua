-- ============================================================================
--  FADING ECHO — ASCEND  (rise by flying, and unlimited mid-air re-jumps)
--
--  Two independent modes:
--   - ASCEND (F3)    : as long as JUMP is HELD, we force the vertical velocity
--                      -> the character rises continuously. This is FLIGHT, not
--                      jumping: nothing about it resembles a moon jump, which is
--                      why the mod is no longer called that. The mode that IS a
--                      moon jump is MultiJump on F4.
--                      Relies on LaunchCharacter(vel, false, true): a UFUNCTION
--                      of ACharacter, hence callable via UE4SS.
--   - MULTIJUMP (F4) : JumpMaxCount = 999 -> you can re-jump in mid-air at will
--                      ("classic" infinite jump, keeps the game's physics).
--
--  Console (²):
--   ascend            toggle ascend
--   ascend speed <n>  rise speed (default 700, in cm/s)
--   ascend key <FKey> watched key (default SpaceBar; e.g. Gamepad_FaceButton_Bottom)
--   multijump           toggle multijump
--   ascend status     current state
-- ============================================================================

local UEHelpers = require("UEHelpers")

local RISE_SPEED   = 700          -- cm/s; ~700 = strong but controllable rise
local JUMP_KEY     = "SpaceBar"   -- FKey watched for the hold
local MULTI_COUNT  = 999
local TICK_MS      = 16           -- ~60 Hz

local AscendOn, MultiOn = false, false
local SavedJumpMax = nil          -- to restore cleanly

local function log(m) print("[Ascend] " .. tostring(m) .. "\n") end
local function cout(Ar, m)
    pcall(function() if Ar then Ar:Log(m) end end)
    log(m)
end

-- ---------------------------------------------------------------------------
--  Player / controller
-- ---------------------------------------------------------------------------
local function isRealActor(a)
    if not (a and a:IsValid()) then return false end
    local fn = ""; pcall(function() fn = a:GetFullName() end)
    return not string.find(fn, "Default__", 1, true)
end

local function GetPC()
    local cs = FindAllOf("PlayerController")
    if cs then
        for _, c in pairs(cs) do
            if c and c:IsValid() and isRealActor(c.Pawn) then return c end
        end
    end
    return nil
end

local function GetPawn()
    local pc = GetPC()
    if pc and isRealActor(pc.Pawn) then return pc.Pawn end
    local ok, p = pcall(UEHelpers.GetPlayerPawn)
    if ok and isRealActor(p) then return p end
    return nil
end

local function IsJumpHeld(pc)
    local ok, down = pcall(function()
        return pc:IsInputKeyDown({ KeyName = FName(JUMP_KEY) })
    end)
    return ok and down == true
end

-- ---------------------------------------------------------------------------
--  ASCEND: rise loop as long as the key is held
-- ---------------------------------------------------------------------------
-- Pawn for the current tick. Written by the async loop, READ by the stable
-- function below: it must NOT be captured by a per-pass closure (see why below).
local TickPawn = nil

-- STABLE function, defined ONCE and passed BY REFERENCE to ExecuteInGameThread.
-- Why it must never be recreated: a FRESH closure handed over 60x/s is registered
-- by UE4SS and can be freed by the GC before it runs -> "[Lua::Registry::
-- get_function_ref] Ref was not function" -> UE4SS REMOVES the EngineTick hook ->
-- EVERY Lua mod stops until the game restarts, at an unpredictable moment.
-- (Same fix as FEBadApple's gameTick.)
local function ascendTick()
    -- Under pcall: an error must NEVER reach the hook (same consequence as above).
    pcall(function()
        local pawn = TickPawn
        if not isRealActor(pawn) then return end
        -- XYOverride=false : we keep horizontal control.
        -- ZOverride=true   : we override the vertical velocity -> clean rise,
        --                    gravity doesn't accumulate.
        pawn:LaunchCharacter({ X = 0.0, Y = 0.0, Z = RISE_SPEED * 1.0 }, false, true)
    end)
end

LoopAsync(TICK_MS, function()
    if AscendOn then
        pcall(function()
            local pc = GetPC()
            if not (pc and IsJumpHeld(pc)) then return end
            local pawn = pc.Pawn
            if not isRealActor(pawn) then return end
            TickPawn = pawn
            ExecuteInGameThread(ascendTick)   -- same ref every pass, GC-safe
        end)
    end
    return false
end)

-- ---------------------------------------------------------------------------
--  MULTIJUMP : JumpMaxCount
-- ---------------------------------------------------------------------------
local function ApplyMultiJump(on)
    local pawn = GetPawn()
    if not pawn then return false, "player not found" end
    local ok, err = pcall(function()
        if on then
            if SavedJumpMax == nil then SavedJumpMax = pawn.JumpMaxCount end
            pawn.JumpMaxCount = MULTI_COUNT
        else
            pawn.JumpMaxCount = SavedJumpMax or 1
        end
    end)
    if not ok then return false, tostring(err) end
    return true
end

-- The pawn is recreated on respawn / zone change: we reapply in the background.
LoopAsync(2000, function()
    if MultiOn then
        pcall(function()
            local pawn = GetPawn()
            if pawn and (pawn.JumpMaxCount or 0) < MULTI_COUNT then
                pawn.JumpMaxCount = MULTI_COUNT
            end
        end)
    end
    return false
end)

-- ---------------------------------------------------------------------------
--  Toggles
-- ---------------------------------------------------------------------------
local function ToggleAscend(Ar)
    AscendOn = not AscendOn
    cout(Ar, "[ascend] " .. (AscendOn and ("ON — hold " .. JUMP_KEY .. " to rise (" .. RISE_SPEED .. " cm/s).") or "OFF."))
end

local function ToggleMulti(Ar)
    local want = not MultiOn
    local ok, err = ApplyMultiJump(want)
    if not ok then cout(Ar, "[multijump] failed: " .. tostring(err)); return end
    MultiOn = want
    cout(Ar, "[multijump] " .. (MultiOn and ("ON — JumpMaxCount = " .. MULTI_COUNT .. ".") or "OFF — JumpMaxCount restored."))
end

-- F3 / F4: F6/F7 belong to FETeleport (save/load position) and F9/F10 to FEVoidCancel.
RegisterKeyBind(Key.F3, function() ToggleAscend(nil) end)
RegisterKeyBind(Key.F4, function() ExecuteInGameThread(function() ToggleMulti(nil) end) end)

-- ---------------------------------------------------------------------------
--  Console
-- ---------------------------------------------------------------------------
RegisterConsoleCommandGlobalHandler("ascend", function(FullCommand, Parameters, Ar)
    local p   = Parameters or {}
    local sub = (p[1] and string.lower(p[1])) or "toggle"

    if sub == "speed" then
        local n = tonumber(p[2])
        if not n then cout(Ar, "[ascend] usage: ascend speed <number>"); return true end
        RISE_SPEED = n
        cout(Ar, "[ascend] rise speed = " .. n .. " cm/s.")
        return true
    end

    if sub == "key" then
        if not p[2] then cout(Ar, "[ascend] usage: ascend key <FKey>  (e.g. SpaceBar)"); return true end
        JUMP_KEY = p[2]
        cout(Ar, "[ascend] watched key = " .. JUMP_KEY .. ".")
        return true
    end

    if sub == "status" then
        local pawn = GetPawn()
        local jm = "?"
        pcall(function() if pawn then jm = tostring(pawn.JumpMaxCount) end end)
        -- %s and not %d: `ascend speed 250.5` stores a float, and %d raises
        -- "number has no integer representation" in Lua 5.4 (no pcall here).
        cout(Ar, string.format("[ascend] ascend=%s multi=%s speed=%s key=%s JumpMaxCount=%s",
            tostring(AscendOn), tostring(MultiOn), RISE_SPEED, JUMP_KEY, jm))
        return true
    end

    ToggleAscend(Ar)
    return true
end)

RegisterConsoleCommandGlobalHandler("multijump", function(FullCommand, Parameters, Ar)
    ExecuteInGameThread(function() ToggleMulti(Ar) end)
    return true
end)

log("loaded. F3 = ascend (hold " .. JUMP_KEY .. "), F4 = multijump. Console: ascend | multijump.")
