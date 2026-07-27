-- ============================================================================
--  FADING ECHO — HUD TOGGLE  (v1)
--  Standalone mod to toggle the HUD display.
--    hud             show/hide the HUD (via YgroCheatManager)
--  Detailed output: UE4SS CONSOLE WINDOW.
--  In-game console: ² key  (AZERTY)
-- ============================================================================
local UEHelpers = require("UEHelpers")

local function log(m) print("[FE-HUD] " .. tostring(m) .. "\n") end

--  Shared helpers (copied from the main toolkit to keep the mod standalone)
local function isRealObject(o)
    if not (o and o:IsValid()) then return false end
    local fn = ""
    pcall(function() fn = o:GetFullName() end)
    -- Class Default Objects are templates, not the live object.
    return not string.find(fn, "Default__", 1, true)
end

local function GetPC()
    local cs = FindAllOf("PlayerController")
    if cs then
        for _, c in pairs(cs) do if isRealObject(c) then return c end end
    end
    local ok, pc = pcall(UEHelpers.GetPlayerController)
    if ok and isRealObject(pc) then return pc end
    return nil
end

local function GetCheatManager()
    local pc = GetPC()
    if pc then
        local cm
        pcall(function() cm = pc.CheatManager end)
        if cm and cm:IsValid() then return cm end
    end
    local list = FindAllOf("YgroCheatManager_C")
    if list then
        for _, c in pairs(list) do if isRealObject(c) then return c end end
    end
    return nil
end

local function EnsureCheatManager()
    if GetCheatManager() then return true, "déjà actif" end
    local pc = GetPC()
    if not pc then return false, "PlayerController introuvable" end
    if not pcall(function() pc:EnableCheats() end) then return false, "EnableCheats() a échoué" end
    if not GetCheatManager() then return false, "EnableCheats() appelé mais CheatManager nul" end
    return true, "activé"
end

-- ============================================================================
--  COMMAND: hud
-- ============================================================================
RegisterConsoleCommandGlobalHandler("hud", function(FullCommand, Parameters, Ar)
    -- ⚠️ The `Ar` FOutputDevice is valid ONLY inside the SYNCHRONOUS body.
    -- Inside ExecuteInGameThread it is a dead pointer -> EXCEPTION_ACCESS_VIOLATION.
    -- => we use say() for the synchronous part, and log() for the deferred part.
    local function say(m)
        log(m)
        if Ar then pcall(function() Ar:Log("[FE-HUD] " .. tostring(m)) end) end
    end

    say("bascule du HUD…")

    ExecuteInGameThread(function()
        local ok, why = EnsureCheatManager()
        if not ok then
            log("CheatManager absent — échec : " .. tostring(why))
            return
        end

        local cm = GetCheatManager()
        if not cm then
            log("CheatManager toujours introuvable après EnsureCheatManager")
            return
        end

        -- ⚠️ The function name in the game contains a SPACE.
        -- (Note: in the main mod, the table strings had a trailing space
        -- because of the column alignment. Here we use the exact name
        -- "Toggle HUD" without any padding space).
        local fname = "Toggle HUD"

        local callOk, err = pcall(function()
            -- ⚠️ DO NOT test type(cm[fname]) == "function": UE4SS does NOT
            -- expose UFUNCTIONs as Lua functions but as a callable userdata.
            -- That test would reject the call. We call directly and let
            -- pcall report the real failure.
            cm[fname](cm)
        end)

        if callOk then
            log(fname .. " -> OK")
        else
            log(fname .. " -> échec : " .. tostring(err))
        end
    end)

    return true
end)

log("Chargé (HUD Toggle v1). Commande : hud")