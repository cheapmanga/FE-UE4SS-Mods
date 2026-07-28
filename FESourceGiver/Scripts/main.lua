-- ============================================================================
--  FADING ECHO — SOURCE GIVER  (sources connected to the Bastion)
--
--  In-game console (F10) :
--    source              +1 source
--    source <n>          +n sources           (e.g. source 3)
--    source set <n>      sets the total to n   (e.g. source set 12 → opens the ending)
--    source status       shows the current total, without changing anything
--    source unlocked <n> +n "found" sources    (milestones 1/3/6/9), see below
--
--  ---------------------------------------------------------------------------
--  WHAT A "COMPLETED SOURCE" IS (found in the game data)
--
--  Two distinct statistics carry the word "Source" in FE :
--    * ConnectedSources = sources CONNECTED to the Bastion. It's the counter that
--      opens the ending : the Level BP YGRO_Bastion_Sh0_Gameplay tests
--      `ConnectedSources == 12` (StatisticCondition, index 18) to trigger the
--      FinalFight (12 = 3 sources × 4 zones Volcano/Tree/Quarry/Wonder).
--    * UnlockedSources = sources FOUND in the zones. Progression milestones
--      1 / 3 / 6 / 9 (index 23). Does NOT open the ending on its own.
--
--  By default this mod increments **ConnectedSources** (= "completed sources",
--  the ones that count toward the ending). `source unlocked <n>` touches the other.
--
--  ---------------------------------------------------------------------------
--  API — UStatisticHolderComponent, BlueprintCallable functions (PDB symbols) :
--      ?IncreaseStatisticBaseValue@UStatisticHolderComponent@@QEAAXVFString@@M@Z
--      ?SetStatisticBaseValue@UStatisticHolderComponent@@QEAAXVFString@@M@Z
--      ?GetStatisticValue@UStatisticHolderComponent@@QEBAMVFString@@@Z
--  that is : (FString StatisticName, float Value).
--
--  /!\ PITFALL — StatisticName is an **FString**, NOT an FName. Passing an
--  FName object crashes the game (push_strproperty → FString::SetCharArray → ACCESS
--  VIOLATION). So we pass a raw Lua string.
--
--  ConnectedSources is a stat of the **World** entity (template
--  DT_WorldEntityStatTemplate), not of the perks holder. Several
--  StatisticHolderComponent coexist (one per template) and are indistinguishable
--  read-only : GetStatisticValue returns 0 both for "stat at zero"
--  and for "stat unknown to this template". So we decide by writing : the right
--  holder is the only one whose value actually moves after a write. Once
--  found, we cache it for the following commands.
-- ============================================================================

local UEHelpers = require("UEHelpers")

local STAT_CONNECTED = "ConnectedSources"
local STAT_UNLOCKED  = "UnlockedSources"
local GOAL           = 12   -- ConnectedSources that opens the FinalFight

local function log(m) print("[SourceGiver] " .. tostring(m) .. "\n") end

-- Writes both to the in-game console (Ar) and to the UE4SS console.
local function cout(Ar, msg)
    pcall(function() if Ar then Ar:Log(msg) end end)
    log(msg)
end

-- real object = not a Class Default Object.
local function isReal(o)
    if not (o and o:IsValid()) then return false end
    local fn = ""; pcall(function() fn = o:GetFullName() end)
    return not string.find(fn, "Default__", 1, true)
end

local function GetPawn()
    local cs = FindAllOf("PlayerController")
    if cs then
        for _, c in pairs(cs) do
            if c and c:IsValid() then
                local pk = c.Pawn
                if isReal(pk) then return pk end
            end
        end
    end
    local ok, p = pcall(UEHelpers.GetPlayerPawn)
    if ok and isReal(p) then return p end
    return nil
end

-- ---------------------------------------------------------------------------
--  Statistic holders
-- ---------------------------------------------------------------------------
local function AllHolders()
    local out, seen = {}, {}
    local ok, list = pcall(function() return FindAllOf("StatisticHolderComponent") end)
    if ok and list then
        for _, h in pairs(list) do
            if h and h:IsValid() then
                local fn = ""; pcall(function() fn = h:GetFullName() end)
                if not seen[fn] and not string.find(fn, "Default__", 1, true) then
                    seen[fn] = true; table.insert(out, h)
                end
            end
        end
    end
    return out
end

-- /!\ raw Lua string (FString), never an FName. See the header.
local function ReadStat(holder, stat)
    local v
    local ok = pcall(function() v = holder:GetStatisticValue(stat) end)
    if ok and type(v) == "number" then return v end
    return nil
end

local function holderReady(h)
    local ready = true
    pcall(function() ready = h:IsReady() end)
    return ready ~= false
end

-- Cache of the holder that carries the World stat (once identified by a write
-- that moved, we reuse it for the following commands).
local sourceHolder = nil

local function cachedHolderValid()
    return sourceHolder and sourceHolder:IsValid() and isReal(sourceHolder)
end

-- Increments `stat` by n on the right holder. Returns (holder, before, after) or nil.
local function IncreaseStat(stat, n)
    -- 1) try the cached holder first.
    if cachedHolderValid() and holderReady(sourceHolder) then
        local before = ReadStat(sourceHolder, stat)
        if before then
            pcall(function() sourceHolder:IncreaseStatisticBaseValue(stat, n * 1.0) end)
            local after = ReadStat(sourceHolder, stat)
            if after and after > before then return sourceHolder, before, after end
        end
    end
    -- 2) otherwise sweep all holders : the right one is the one whose value moves.
    for _, h in ipairs(AllHolders()) do
        if holderReady(h) then
            local before = ReadStat(h, stat)
            if before then
                pcall(function() h:IncreaseStatisticBaseValue(stat, n * 1.0) end)
                local after = ReadStat(h, stat)
                if after and after > before then
                    sourceHolder = h
                    return h, before, after
                end
            end
        end
    end
    return nil
end

-- Sets `stat` to target on the right holder. Returns (holder, before, after) or nil.
local function SetStat(stat, target)
    local function tryOn(h)
        if not holderReady(h) then return nil end
        local before = ReadStat(h, stat)
        if not before then return nil end
        pcall(function() h:SetStatisticBaseValue(stat, target * 1.0) end)
        local after = ReadStat(h, stat)
        -- accepted if the value indeed equals the target (and we could read it back).
        if after and math.abs(after - target) < 0.001 then return before, after end
        return nil
    end

    if cachedHolderValid() then
        local b, a = tryOn(sourceHolder)
        if a then return sourceHolder, b, a end
    end
    for _, h in ipairs(AllHolders()) do
        local b, a = tryOn(h)
        if a then sourceHolder = h; return h, b, a end
    end
    return nil
end

-- Reads `stat` on the first holder that knows it (cache preferred).
local function StatusOf(stat)
    if cachedHolderValid() then
        local v = ReadStat(sourceHolder, stat)
        if v then return v end
    end
    -- Read-only we can't tell "0" from "unknown" ; we return the largest
    -- value read (an already-connected source = value > 0 on the right holder).
    local best = nil
    for _, h in ipairs(AllHolders()) do
        local v = ReadStat(h, stat)
        if v and (not best or v > best) then best = v end
    end
    return best
end

-- ---------------------------------------------------------------------------
--  Console command
-- ---------------------------------------------------------------------------
local USAGE = "[source] usage: source | source <n> | source set <n> | source status | source unlocked <n>"

RegisterConsoleCommandGlobalHandler("source", function(FullCommand, Parameters, Ar)
    local p  = Parameters or {}
    local a1 = p[1] and string.lower(p[1]) or nil
    local a2 = p[2]

    -- source status
    if a1 == "status" or a1 == "get" then
        local c = StatusOf(STAT_CONNECTED)
        local u = StatusOf(STAT_UNLOCKED)
        cout(Ar, string.format("[source] connected (ConnectedSources): %s / %d%s",
            c and string.format("%.0f", c) or "?", GOAL,
            u and string.format("   |   found (UnlockedSources): %.0f", u) or ""))
        if not c then
            cout(Ar, "[source] holder not found — are you actually in game (not in a menu)?")
        end
        return true
    end

    -- source set <n>
    if a1 == "set" then
        local target = tonumber(a2)
        if not target or target < 0 then cout(Ar, USAGE); return true end
        target = math.floor(target)
        if not GetPawn() then cout(Ar, "[source] player not found — are you actually in game?"); return true end
        local h, before, after = SetStat(STAT_CONNECTED, target)
        if not h then
            cout(Ar, "[source] failed: no holder accepted a write to " .. STAT_CONNECTED ..
                     ". Load the Bastion first, then try again.")
            return true
        end
        cout(Ar, string.format("[source] ConnectedSources set to %.0f (was: %.0f).", after, before))
        if after >= GOAL then
            cout(Ar, "[source] >= 12 -> FinalFight condition met.")
        end
        return true
    end

    -- source unlocked <n>
    if a1 == "unlocked" or a1 == "found" then
        local n = tonumber(a2) or 1
        if n < 1 then cout(Ar, USAGE); return true end
        n = math.floor(n)
        if not GetPawn() then cout(Ar, "[source] player not found — are you actually in game?"); return true end
        local h, before, after = IncreaseStat(STAT_UNLOCKED, n)
        if not h then
            cout(Ar, "[source] failed: no holder accepted an increment of " .. STAT_UNLOCKED .. ".")
            return true
        end
        cout(Ar, string.format("[source] +%d -> %.0f source(s) found (was: %.0f).", n, after, before))
        return true
    end

    -- source  |  source <n>   → increments ConnectedSources
    local n = 1
    if a1 then
        n = tonumber(a1)
        if not n or n < 1 then cout(Ar, USAGE); return true end
        n = math.floor(n)
    end

    if not GetPawn() then
        cout(Ar, "[source] player not found — are you actually in game (not in a menu)?")
        return true
    end

    local h, before, after = IncreaseStat(STAT_CONNECTED, n)
    if not h then
        cout(Ar, "[source] failed: no holder accepted an increment of " .. STAT_CONNECTED ..
                 ". Load the Bastion first (where the sources get connected), then try again.")
        return true
    end
    cout(Ar, string.format("[source] +%d -> %.0f / %d source(s) connected (was: %.0f).",
        n, after, GOAL, before))
    if after >= GOAL and before < GOAL then
        cout(Ar, "[source] >= 12 -> FinalFight condition met.")
    end
    return true
end)

log("loaded. In-game console (F10): source | source <n> | source set <n> | source status")
