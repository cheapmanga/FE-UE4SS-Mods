-- ============================================================================
--  FADING ECHO — CAMERA FOV  (v1)
--  Changes the player camera's field of view.
--    fov                   show the current FOV
--    fov <n>               set it (60-140 is the usable range, ~90 is the game default)
--    fov reset             back to the value saved the first time we touched it
--    fov lock              toggle a slow loop that re-applies the FOV (~1 s)
--  In-game console: ² key  (AZERTY)
-- ============================================================================
local UEHelpers = require("UEHelpers")

local function log(m) print("[Camera] " .. tostring(m) .. "\n") end

-- ⚠️ Ar (FOutputDevice) is valid ONLY in the SYNCHRONOUS body of the handler.
-- Using it from deferred code is a dead pointer -> EXCEPTION_ACCESS_VIOLATION.
local function cout(Ar, m)
    pcall(function() if Ar then Ar:Log("[fov] " .. tostring(m)) end end)
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

-- The FOV lives on the APlayerCameraManager owned by the PlayerController.
local function GetCam()
    local pc = GetPC()
    if pc then
        local cam = try(function() return pc.PlayerCameraManager end)
        if isRealObject(cam) then return cam end
    end
    -- Fallback: the manager exists as its own actor, so it is enumerable.
    local cs = try(function() return FindAllOf("PlayerCameraManager") end)
    if cs then
        for _, c in pairs(cs) do
            if isRealObject(c) then return c end
        end
    end
    return nil
end

-- Last-resort write target: the UCameraComponent the pawn actually renders from.
-- Only the one owned by our pawn, otherwise we would be editing some other
-- actor's camera (cinematics, spectator...).
local function GetCamComp()
    local pawn = GetPawn()
    if not pawn then return nil end
    local cs = try(function() return FindAllOf("CameraComponent") end)
    if not cs then return nil end
    for _, c in pairs(cs) do
        if isRealObject(c) then
            local owner = try(function() return c:GetOwner() end)
            if owner and okObj(owner) then
                local a, b = "", ""
                pcall(function() a = owner:GetFullName() end)
                pcall(function() b = pawn:GetFullName() end)
                if a ~= "" and a == b then return c end
            end
        end
    end
    return nil
end

local SavedFOV = nil       -- FOV read the very first time we touched the camera
local TargetFOV = nil      -- what `fov lock` keeps re-asserting
local LockOn = false
local LOCK_MS = 1000       -- ~1 s; this is a safety net, not a per-frame job

-- APlayerCameraManager::GetFOVAngle() is a BP-exposed UFUNCTION.
-- DefaultFOV is the plain property it falls back to, and is the better read
-- when a cutscene camera is momentarily driving the angle.
local function ReadFOV()
    local cam = GetCam()
    if not cam then return nil, "PlayerCameraManager not found" end
    local v = try(function() return cam:GetFOVAngle() end)
    if type(v) == "number" and v > 0 then return v, "GetFOVAngle" end
    v = try(function() return cam.DefaultFOV end)
    if type(v) == "number" and v > 0 then return v, "DefaultFOV" end
    return nil, "GetFOVAngle() and DefaultFOV are both unreadable"
end

-- Three write paths, all attempted: SetFOV locks the angle on the manager,
-- DefaultFOV survives a camera that recomputes its own value, and the pawn's
-- CameraComponent is there for the case where the manager just mirrors it.
-- We report which ones took, because "no error" is not proof anything moved.
local function ApplyFOV(n)
    local cam = GetCam()
    if not cam then return false, "PlayerCameraManager not found" end

    local done = {}
    if try(function() cam:SetFOV(n * 1.0); return true end) == true then
        done[#done + 1] = "SetFOV"
    end
    if try(function() cam.DefaultFOV = n * 1.0; return true end) == true then
        done[#done + 1] = "DefaultFOV"
    end
    local cc = GetCamComp()
    if cc and try(function() cc.FieldOfView = n * 1.0; return true end) == true then
        done[#done + 1] = "FieldOfView"
    end

    if #done == 0 then
        return false, "no writable FOV path (SetFOV, DefaultFOV and FieldOfView all failed)"
    end
    return true, table.concat(done, "+")
end

-- UnlockFOV() releases the lock SetFOV puts on the manager, so the game gets
-- its camera back instead of staying pinned at whatever we last asked for.
local function ResetFOV()
    if SavedFOV == nil then return false, "nothing saved yet — the FOV was never changed" end
    local ok, how = ApplyFOV(SavedFOV)
    local cam = GetCam()
    if cam then try(function() cam:UnlockFOV() end) end
    return ok, how
end

-- STABLE function, defined ONCE and passed BY REFERENCE to ExecuteInGameThread.
-- A FRESH closure handed over from a loop is registered by UE4SS and can be
-- freed by the GC before it runs -> "[Lua::Registry::get_function_ref] Ref was
-- not function" -> UE4SS REMOVES the EngineTick hook -> EVERY Lua mod stops
-- until the game restarts. (Same rule as FEMoonJump's moonTick.)
local function fovTick()
    -- Under pcall: an error must NEVER reach the hook (same consequence as above).
    pcall(function()
        if not LockOn then return end
        local n = TargetFOV
        if type(n) ~= "number" then return end
        ApplyFOV(n)
    end)
end

LoopAsync(LOCK_MS, function()
    if LockOn then
        ExecuteInGameThread(fovTick)   -- same ref every pass, GC-safe
    end
    return false
end)

RegisterConsoleCommandGlobalHandler("fov", function(FullCommand, Parameters, Ar)
    local a1 = string.lower(tostring(Parameters[1] or ""))

    if a1 == "" or a1 == "status" then
        local live, how = ReadFOV()
        if live then
            cout(Ar, ("fov = %s   (read via %s)"):format(tostring(live), tostring(how)))
        else
            cout(Ar, "fov = ?   (read failed: " .. tostring(how) .. ")")
        end
        cout(Ar, ("saved original = %s | lock = %s | lock target = %s"):format(
            tostring(SavedFOV or "none yet"), tostring(LockOn), tostring(TargetFOV or "none")))
        cout(Ar, "usage: fov <n> | fov reset | fov lock   (60-140 usable, ~90 is the default)")
        return true
    end

    if a1 == "reset" or a1 == "off" then
        LockOn = false
        if SavedFOV == nil then
            cout(Ar, "nothing to reset — the FOV was never changed in this session.")
            return true
        end
        cout(Ar, ("restoring fov %s…"):format(tostring(SavedFOV)))
        -- Deferred: every game-state write goes through the game thread.
        -- From here on, log() only — Ar is dead outside this synchronous body.
        ExecuteInGameThread(function()
            local ok, how = ResetFOV()
            log(ok and ("fov restored via " .. tostring(how) .. ", lock released.")
                   or ("reset failed: " .. tostring(how)))
        end)
        return true
    end

    if a1 == "lock" then
        if LockOn then
            LockOn = false
            cout(Ar, "lock OFF — the game may move the FOV again on camera transitions.")
            return true
        end
        -- Lock whatever we last set; if we never set anything, lock what is live.
        if TargetFOV == nil then
            local live = ReadFOV()
            if not live then
                cout(Ar, "lock refused: cannot read the current FOV. Set one first: fov 100")
                return true
            end
            TargetFOV = live
        end
        LockOn = true
        cout(Ar, ("lock ON — re-applying fov %s every %s ms."):format(tostring(TargetFOV), tostring(LOCK_MS)))
        return true
    end

    local n = tonumber(a1)
    if not n or n ~= n then
        cout(Ar, "usage: fov <n> | fov reset | fov lock")
        return true
    end

    -- Clamped wide rather than tight: an extreme FOV is a legitimate screenshot
    -- trick and `fov reset` always gets you back. Below ~10 the view degenerates.
    if n < 10 then n = 10 end
    if n > 170 then n = 170 end

    -- Save the untouched value BEFORE the first write, that is what `reset` uses.
    if SavedFOV == nil then
        local live = ReadFOV()
        if live then SavedFOV = live end
    end

    TargetFOV = n
    cout(Ar, ("setting fov to %s…"):format(tostring(n)))
    ExecuteInGameThread(function()
        local ok, how = ApplyFOV(n)
        if ok then
            log(("fov = %s (written via %s). If the game overwrites it, use: fov lock")
                :format(tostring(n), tostring(how)))
        else
            log("failed: " .. tostring(how))
        end
    end)
    return true
end)

log("loaded. console (²): fov <n> | fov reset | fov lock")
