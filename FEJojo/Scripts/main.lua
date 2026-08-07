-- ============================================================================
--  FE JOJO  —  the Jojo Glitch on demand
--
--  Two commands, that is all:
--     jojo on    arm it, then travel through any Pipe. You come out flying.
--     jojo off   stop, and clean up.
--
--  WHAT THE GLITCH IS
--  Travelling through a Pipe puts the character in Flying movement mode. On
--  the way out the game takes it back. Keep it, and you can fly anywhere.
--
--  On build 1.0.28121 the glitch has not been reproduced without a mod.
--
--  HOW IT WORKS
--  USplineTravelerComponent::SetState() pushes a movement mode and a form
--  effect onto the character's movement component. Only ResetComponentState()
--  undoes that, and it is called from the checkpoint Blueprint, never by the
--  component itself. So the mod watches the MOVEMENT MODE and, when it falls
--  back to walking, re-applies the travel state.
--
--  Watching the mode rather than the state flag is the whole trick. During
--  normal travel the state flag flickers back to Undefined about ten times a
--  second while the movement mode stays Flying — the glitch lives in the mode.
--  Re-applying on every flicker works but stutters badly, because each call
--  re-pushes the mode and the form effect onto the movement component. Acting
--  only when the mode actually drops is what makes it smooth.
--
--  The traveler is reached by name: BP_CoreYgroCharacter_C has a member
--  BP_FlyingForm_V2, and UBP_FlyingForm_V2_C derives from
--  USplineTravelerComponent. No component enumeration is involved.
--
--  ⚠️ You must ENTER A PIPE after `jojo on`. The mod never invents a travel
--  state out of nothing: forcing one with no spline attached crashes the game
--  on the next tick (access violation, confirmed). It only keeps a state you
--  genuinely reached.
--
--  Getting rid of it is easy: `jojo off`, or simply return to the menu, which
--  clears the state on its own.
--
--  ⚠️ `jojo off` does not clear the snap attraction effect nor the re-attach
--  cooldown that travelling leaves behind. Only reloading does. If snapping
--  misbehaves afterwards, reload.
--
--  PITFALLS THIS MOD RESPECTS — each has already broken something:
--   * No native iteration (ForEachFunction / ForEachProperty /
--     GetComponentsByClass): a Lua error raised inside a native C++ frame
--     propagates by longjmp over the native stack, and pcall does not catch
--     it. The traveler is reached by named member instead.
--   * The periodic loop receives a STABLE function reference. A fresh closure
--     at high frequency makes UE4SS drop its EngineTick hook, and then every
--     Lua mod stops silently.
--   * `Ar` is valid only inside the handler's synchronous body, so the loop
--     prints with print() only.
--   * o:IsValid() throws when o is not a UObject, so it goes through pcall.
--   * UEHelpers is a separate mod and is not always loaded — three fallback
--     routes are used to find the player.
-- ============================================================================

local PLAYER_CLASS    = "BP_CoreYgroCharacter_C"
local TRAVELER_MEMBER = "BP_FlyingForm_V2"

local TRAVEL_STATE = 2   -- ESplineTravelerState::Traveling, the one that flies
local MODE_WALKING = 1   -- EMovementMode::MOVE_Walking
local MODE_FLYING  = 5   -- EMovementMode::MOVE_Flying
local POLL_MS      = 50

local cachedPawn = nil
local active     = false
local restored   = 0
local announced  = false

local function log(m) print("[Jojo] " .. tostring(m) .. "\n") end

local function say(Ar, m)
    log(m)
    if Ar then pcall(function() Ar:Log("[Jojo] " .. tostring(m)) end) end
end

local function safe(what, fn)
    local ok, res = pcall(fn)
    if not ok then
        log("failed: " .. what .. " -> " .. tostring(res))
        return nil
    end
    return res
end

local function isLive(o)
    if not o then return false end
    local valid = false
    pcall(function() valid = o:IsValid() end)
    if not valid then return false end
    local fn = ""
    pcall(function() fn = o:GetFullName() end)
    return fn ~= "" and not string.find(fn, "Default__", 1, true)
end

-- --- reaching the player and its traveler ---------------------------------

local function playerPawn()
    if isLive(cachedPawn) then return cachedPawn end

    if UEHelpers ~= nil then
        local pc = safe("UEHelpers.GetPlayerController", function()
            return UEHelpers.GetPlayerController()
        end)
        if pc then
            local pawn = safe("PlayerController.Pawn", function() return pc.Pawn end)
            if isLive(pawn) then cachedPawn = pawn return pawn end
        end
    end

    local pcs = safe("FindAllOf PlayerController", function()
        return FindAllOf("PlayerController")
    end) or {}
    for _, pc in pairs(pcs) do
        if isLive(pc) then
            local pawn = safe("PlayerController.Pawn", function() return pc.Pawn end)
            if isLive(pawn) then cachedPawn = pawn return pawn end
        end
    end

    local chars = safe("FindAllOf " .. PLAYER_CLASS, function()
        return FindAllOf(PLAYER_CLASS)
    end) or {}
    for _, c in pairs(chars) do
        if isLive(c) then cachedPawn = c return c end
    end

    return nil
end

local function traveler()
    local pawn = playerPawn()
    if not pawn then return nil end
    local t = safe(TRAVELER_MEMBER, function() return pawn[TRAVELER_MEMBER] end)
    if not isLive(t) then return nil end
    return t
end

local function movementMode()
    local t = traveler()
    local mc = t and safe("CharacterMovementComponent", function()
        return t.CharacterMovementComponent
    end) or nil
    if not isLive(mc) then
        local pawn = playerPawn()
        mc = pawn and safe("CharacterMovement", function()
            return pawn.CharacterMovement
        end) or nil
    end
    if not isLive(mc) then return nil end
    return safe("MovementMode", function() return mc.MovementMode end)
end

-- --- the loop -------------------------------------------------------------

-- Defined ONCE and passed by reference. A fresh closure here would make UE4SS
-- drop its EngineTick hook and silently stop every Lua mod.
local function keeper()
    if not active then return true end

    local mode = movementMode()
    if mode == nil then return false end

    if mode == MODE_FLYING then
        if not announced then
            announced = true
            log("flying — you are in Jojo. 'jojo off' to stop.")
        end
        return false
    end

    -- Only step in once the mode has actually fallen back to walking. The
    -- state flag flickering is harmless and must be ignored, or the game
    -- stutters.
    if mode == MODE_WALKING and announced then
        local ok = false
        pcall(function() traveler():SetState(TRAVEL_STATE) ok = true end)
        if ok then restored = restored + 1 end
    end
    return false
end

-- --- commands -------------------------------------------------------------

RegisterConsoleCommandHandler("jojo", function(FullCommand, Parameters, Ar)
    local sub = (Parameters and Parameters[1] or ""):lower()

    if sub == "on" then
        if active then
            say(Ar, "already on. 'jojo off' to stop.")
            return true
        end
        if not traveler() then
            say(Ar, "player not found — are you in a level?")
            return true
        end
        active, restored, announced = true, 0, false
        LoopAsync(POLL_MS, keeper)
        say(Ar, "armed. Now travel through any Pipe: you will come out flying.")
        say(Ar, "'jojo off' or a return to the menu clears it.")
        return true
    end

    if sub == "off" then
        if not active then
            say(Ar, "not on.")
            return true
        end
        active = false
        local t = traveler()
        if t then pcall(function() t:ResetComponentState() end) end
        say(Ar, "off. (" .. restored .. " restores)")
        say(Ar, "If snapping misbehaves afterwards, reload: travelling leaves "
                .. "residue this cannot clear.")
        return true
    end

    say(Ar, "jojo on   — arm it, then travel through a Pipe to come out flying")
    say(Ar, "jojo off  — stop and clean up")
    return true
end)

log("loaded. 'jojo on' to arm, 'jojo off' to stop.")
