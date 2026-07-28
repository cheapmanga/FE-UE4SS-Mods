-- ============================================================================
--  FADING ECHO — CHEST HOPPER
--
--  Console command (F10) :
--     chest              -> teleports to the next chest (1st call = the nearest)
--     chest reset        -> rebuilds the tour from your current position
--     chest prev         -> goes back to the previous chest
--     chest <n>          -> jumps straight to the n-th chest of the tour
--     chest list         -> lists the chests found + their distance
--
--  Principle : on the 1st 'chest', we collect all LOADED chests, sort them
--  by distance to the player, and walk through this frozen list. It's rebuilt
--  automatically if the number of chests changes (level streaming) or via
--  'chest reset'.
--
--  ⚠️ The sort is frozen at build time : this is intentional. A sort
--  recomputed on every jump would keep sending you back to the chest you came
--  from (distance 0), and you'd never visit the whole zone.
--
--  ⚠️ Only chests whose sub-level is LOADED are visible to
--  FindAllOf. Chests of a non-streamed zone don't exist yet on the
--  engine side — no mod can reach them. 'chest list' shows what is
--  actually found at time T.
--
--  Classes : /Game/Game/Placeable/InteractiveObjects/Chest/
-- ============================================================================

local UEHelpers = require("UEHelpers")

local function log(m) print("[ChestHopper] " .. tostring(m) .. "\n") end
local function cout(Ar, m)
    pcall(function() if Ar then Ar:Log(m) end end)
    log(m)
end

-- Height added to the destination : we land ABOVE the chest rather than
-- inside it (otherwise the player's capsule can get stuck in the collision).
local Z_OFFSET = 150.0

local CHEST_CLASSES = {
    "BP_Chest_Small_C",
    "BP_Chest_Medium_C",
    "BP_Chest_Big_C",
    "BP_Chest_Special_LevelUp_C",
    "BP_Chest_ALIENWARE_C",
}

-- Short label for display
local function PrettyClass(fullname)
    local n = tostring(fullname or "")
    for _, cls in ipairs(CHEST_CLASSES) do
        if string.find(n, cls, 1, true) then
            return (string.gsub(string.gsub(cls, "^BP_Chest_", ""), "_C$", ""))
        end
    end
    return "Chest"
end

-- ---------------------------------------------------------------------------
--  Actor / player helpers  (same safeguards as the other FE mods)
-- ---------------------------------------------------------------------------
-- /!\ a:IsValid() CRASHES if `a` is not a UObject ("attempt to call a nil
-- value (method 'IsValid')"), so it goes through pcall like GetFullName().
local function isRealActor(a)
    if not a then return false end
    local valid = false
    pcall(function() valid = a:IsValid() end)
    if not valid then return false end
    local fn = ""
    pcall(function() fn = a:GetFullName() end)
    -- We exclude Class Default Objects : they are templates, not
    -- actors placed in the level (they have a bogus position, often 0,0,0).
    return not string.find(fn, "Default__", 1, true)
end

local function GetPawn()
    local cs = FindAllOf("PlayerController")
    if cs then
        for _, c in pairs(cs) do
            if c and c:IsValid() then
                local pk = c.Pawn
                if isRealActor(pk) then return pk end
            end
        end
    end
    local ok, p = pcall(UEHelpers.GetPlayerPawn)
    if ok and isRealActor(p) then return p end
    local list = FindAllOf("BP_CoreYgroCharacter_C")
    if list then
        for _, a in pairs(list) do
            if isRealActor(a) then return a end
        end
    end
    return nil
end

local function ProbeLocation(actor)
    local loc
    pcall(function() loc = actor:K2_GetActorLocation() end)
    if loc and loc.X then return loc end
    return nil
end

local function Dist3(a, b)
    local dx, dy, dz = a.X - b.X, a.Y - b.Y, a.Z - b.Z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- ---------------------------------------------------------------------------
--  Collection
-- ---------------------------------------------------------------------------
local function CollectChests()
    local found, seen = {}, {}
    for _, cls in ipairs(CHEST_CLASSES) do
        local ok, list = pcall(function() return FindAllOf(cls) end)
        if ok and list then
            for _, a in pairs(list) do
                if isRealActor(a) then
                    local nok, fn = pcall(function() return a:GetFullName() end)
                    if nok and fn and not seen[fn] then
                        seen[fn] = true
                        local loc = ProbeLocation(a)
                        if loc then
                            table.insert(found, { actor = a, loc = loc, name = fn, label = PrettyClass(fn) })
                        end
                    end
                end
            end
        end
    end
    return found
end

-- ---------------------------------------------------------------------------
--  Tour state
-- ---------------------------------------------------------------------------
local tour = {}   -- list sorted by distance, frozen
local idx = 0     -- index of the last visited chest (0 = not started yet)

local function BuildTour(Ar)
    local pawn = GetPawn()
    if not pawn then return false, "player not found" end
    local ppos = ProbeLocation(pawn)
    if not ppos then return false, "player position unreadable" end

    local chests = CollectChests()
    if #chests == 0 then
        return false, "no chest loaded (zone not streamed yet?) — try 'chest list'"
    end

    for _, c in ipairs(chests) do c.dist = Dist3(ppos, c.loc) end
    table.sort(chests, function(a, b) return a.dist < b.dist end)

    tour, idx = chests, 0
    return true, nil
end

-- The tour is stale if chests have been loaded/unloaded since,
-- or if a memorized actor is no longer valid (zone change).
local function TourIsStale()
    if #tour == 0 then return true end
    if #CollectChests() ~= #tour then return true end
    for _, c in ipairs(tour) do
        if not (c.actor and c.actor:IsValid()) then return true end
    end
    return false
end

local function TeleportTo(entry)
    local pawn = GetPawn()
    if not pawn then return false, "player not found" end
    -- We re-read the position live : a chest may have moved (platform,
    -- elevator) since the tour was built.
    local loc = ProbeLocation(entry.actor) or entry.loc
    local dest = { X = loc.X, Y = loc.Y, Z = loc.Z + Z_OFFSET }
    local ok = pcall(function() pawn:K2_SetActorLocation(dest, false, {}, true) end)
    return ok, (not ok) and "K2_SetActorLocation failed" or nil
end

local function GoTo(Ar, n)
    if n < 1 or n > #tour then
        cout(Ar, "[chest] index out of tour (1.." .. #tour .. ").")
        return true
    end
    local e = tour[n]
    local ok, err = TeleportTo(e)
    if not ok then
        cout(Ar, "[chest] " .. tostring(err))
        return true
    end
    idx = n
    cout(Ar, string.format("[chest] %d/%d — %s (%.0f m from the start point)",
        n, #tour, e.label, (e.dist or 0) / 100.0))
    return true
end

-- ---------------------------------------------------------------------------
--  Console command
-- ---------------------------------------------------------------------------
RegisterConsoleCommandGlobalHandler("chest", function(FullCommand, Parameters, Ar)
    local p = Parameters or {}
    local key = (p[1] and string.lower(p[1])) or ""

    if key == "list" then
        local chests = CollectChests()
        if #chests == 0 then
            cout(Ar, "[chest] no chest loaded right now.")
            return true
        end
        local pawn = GetPawn()
        local ppos = pawn and ProbeLocation(pawn) or nil
        if ppos then
            for _, c in ipairs(chests) do c.dist = Dist3(ppos, c.loc) end
            table.sort(chests, function(a, b) return a.dist < b.dist end)
        end
        cout(Ar, "[chest] " .. #chests .. " chest(s) loaded:")
        for i, c in ipairs(chests) do
            cout(Ar, string.format("   %2d. %-12s %6.0f m", i, c.label, (c.dist or 0) / 100.0))
        end
        return true
    end

    if key == "reset" or key == "again" or key == "restart" then
        local ok, err = BuildTour(Ar)
        if not ok then cout(Ar, "[chest] " .. tostring(err)); return true end
        cout(Ar, "[chest] tour rebuilt: " .. #tour .. " chest(s). type 'chest'.")
        return true
    end

    if key == "prev" or key == "back" then
        if #tour == 0 then cout(Ar, "[chest] no tour in progress."); return true end
        return GoTo(Ar, idx - 1 >= 1 and idx - 1 or #tour)
    end

    if key == "help" or key == "?" then
        cout(Ar, "[chest] chest | chest reset | chest prev | chest <n> | chest list")
        return true
    end

    -- 'chest <n>'
    local n = tonumber(key)
    if n then
        if #tour == 0 then
            local ok, err = BuildTour(Ar)
            if not ok then cout(Ar, "[chest] " .. tostring(err)); return true end
        end
        return GoTo(Ar, math.floor(n))
    end

    if key ~= "" then
        cout(Ar, "[chest] unknown argument: " .. key .. "  (try: chest help)")
        return true
    end

    -- plain 'chest' : build if needed, then advance
    if TourIsStale() then
        local ok, err = BuildTour(Ar)
        if not ok then cout(Ar, "[chest] " .. tostring(err)); return true end
        cout(Ar, "[chest] tour: " .. #tour .. " chest(s) found.")
    end

    local nxt = idx + 1
    if nxt > #tour then
        nxt = 1
        cout(Ar, "[chest] end of tour — restarting from the nearest.")
    end
    return GoTo(Ar, nxt)
end)

log("loaded. type 'chest' in the console (F10). 'chest help' for the options.")
