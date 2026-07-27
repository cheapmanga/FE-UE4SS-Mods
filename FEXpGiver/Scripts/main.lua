-- ============================================================================
--  FADING ECHO — XP GIVER  (Ætherfact points)
--
--  In-game console (F10) :
--    xp             +1 Ætherfact point
--    xp <n>         +n points (e.g. xp 5)
--    xp status      current balance, without giving anything
--
--  ---------------------------------------------------------------------------
--  WHAT AN "ÆTHERFACT POINT" IS (found in the game data)
--
--  It's the **SkillPointBalance** statistic, row 3 of the DataTable
--  DT_PerksStatTemplate (/Game/Game/Perks/Test/DT_PerksStatTemplate) :
--      [ 3] SkillPointBalance   default=0  min=0  max=+Inf
--
--  Cross-checks :
--   * WBP_PerkToolTip shows "Cost" + "Ætherfact point(s)" -> it's the price of perks.
--   * EVERY DA_Perk_*.json carries a StatisticCondition on SkillPointBalance
--     (the cost check at purchase).
--   * DA_IncreaseSkillPoints_XS_StatisticModifier = "SkillPointBalance += 1.0"
--     (Operator=Addition, Operand=FlatValue 1.0, StatisticIndex=3) — it's the
--     game's level-up reward, referenced by DA_LevelUpDescriptor.
--
--  ---------------------------------------------------------------------------
--  WHY IncreaseStatisticBaseValue AND NOT ApplyStatisticModifierSet
--
--  UStatisticHolderComponent exposes 6 BlueprintCallable functions (confirmed in
--  the PDB, exec* symbols). EXACT signatures, read from the mangled symbols :
--
--      ?IncreaseStatisticBaseValue@UStatisticHolderComponent@@QEAAXVFString@@M@Z
--      ?SetStatisticBaseValue@UStatisticHolderComponent@@QEAAXVFString@@M@Z
--      ?GetStatisticValue@UStatisticHolderComponent@@QEBAMVFString@@@Z
--
--  that is : (FString StatisticName, float Value).
--
--  /!\ PITFALL — StatisticName is an **FString**, not an FName.
--  GetStatisticValue is overloaded in C++ (FString / FName / FStatisticIdentifier),
--  but it's the **FString** overload that is exposed to Blueprint. Passing an
--  FName object here crashes the game : UE4SS writes the argument as a StrProperty
--  (push_strproperty -> FString::SetCharArray) and dereferences garbage
--  -> EXCEPTION_ACCESS_VIOLATION. So we pass a raw Lua string.
--  (The FGenericPropertyParams type of the NewProp_ in the PDB does NOT let you
--   decide FName vs FString : it covers both. Only the mangled symbol tells.)
--
--  The game itself gives its points via ApplyStatisticModifierSet(DA_IncreaseSkillPoints_XS).
--  We do NOT do that here : a modifier set is a LAYER you apply/remove
--  (Apply/Unapply). Nothing guarantees that applying the same descriptor twice
--  stacks twice — yet we specifically want to be able to run 'xp' repeatedly.
--  IncreaseStatisticBaseValue writes the BASE value : it's cumulative by
--  construction, hence repeatable.
-- ============================================================================

local UEHelpers = require("UEHelpers")

local STAT = "SkillPointBalance"

local function log(m) print("[XpGiver] " .. tostring(m) .. "\n") end

-- Writes both to the in-game console (Ar) and to the UE4SS console.
local function cout(Ar, msg)
    pcall(function() if Ar then Ar:Log(msg) end end)
    log(msg)
end

-- real actor/object = not a Class Default Object.
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
--  Find the StatisticHolderComponent that carries DT_PerksStatTemplate.
--
--  Main path : PH_XP_Manager_C (ActorComponent) exposes a property
--  StatHolder : StatisticHolderComponent. It's the component that manages the
--  currency (it has UpdateCurrency(CurrencyToAdd), XPCurrency, OnCurrencyIncrease) —
--  so its holder is indeed the one for the perks template.
--
--  Fallback : we sweep the pawn's StatisticHolderComponent. Since several
--  holders coexist (one per template : health, perks...), we can't tell them
--  apart read-only — GetStatisticValue returns 0 both for
--  "stat at zero" and for "stat unknown to this template". So we decide by
--  writing : the right holder is the one whose value actually moves.
-- ---------------------------------------------------------------------------
local function ManagerHolder()
    local mgrs = FindAllOf("PH_XP_Manager_C")
    if not mgrs then return nil end
    for _, m in pairs(mgrs) do
        if isReal(m) then
            local h
            pcall(function() h = m.StatHolder end)
            if h and h:IsValid() then return h end
        end
    end
    return nil
end

local function CandidateHolders()
    local out, seen = {}, {}
    local function add(h)
        if h and h:IsValid() then
            local fn = ""; pcall(function() fn = h:GetFullName() end)
            if not seen[fn] and not string.find(fn, "Default__", 1, true) then
                seen[fn] = true; table.insert(out, h)
            end
        end
    end
    add(ManagerHolder())                      -- the right one, in principle
    local ok, list = pcall(function() return FindAllOf("StatisticHolderComponent") end)
    if ok and list then
        for _, h in pairs(list) do add(h) end -- fallback : all the others
    end
    return out
end

-- /!\ StatisticName is an FString, NOT an FName (see the header). So we pass
-- a raw Lua string : UE4SS converts it to an FString for the StrProperty.
local function ReadPoints(holder)
    local v
    local ok = pcall(function() v = holder:GetStatisticValue(STAT) end)
    if ok and type(v) == "number" then return v end
    return nil
end

-- Gives n points. Returns (holder, before, after) if it worked, otherwise nil.
local function GivePoints(n)
    for _, h in ipairs(CandidateHolders()) do
        local ready = true
        pcall(function() ready = h:IsReady() end)
        if ready ~= false then
            local before = ReadPoints(h)
            if before then
                pcall(function() h:IncreaseStatisticBaseValue(STAT, n * 1.0) end)
                local after = ReadPoints(h)
                -- We only accept it if the value REALLY moved : that's what
                -- distinguishes the perks template holder from the other holders.
                if after and after > before then return h, before, after end
            end
        end
    end
    return nil
end

RegisterConsoleCommandGlobalHandler("xp", function(FullCommand, Parameters, Ar)
    local p = Parameters or {}
    local a1 = p[1] and string.lower(p[1]) or nil

    if a1 == "status" then
        for _, h in ipairs(CandidateHolders()) do
            local v = ReadPoints(h)
            if v then
                cout(Ar, string.format("[xp] solde : %.0f point(s) d'Ætherfact.", v))
                return true
            end
        end
        cout(Ar, "[xp] holder de statistiques introuvable — es-tu bien en jeu ?")
        return true
    end

    local n = 1
    if a1 then
        n = tonumber(a1)
        if not n or n < 1 then
            cout(Ar, "[xp] usage : xp  |  xp <n>  |  xp status")
            return true
        end
        n = math.floor(n)
    end

    if not GetPawn() then
        cout(Ar, "[xp] joueur introuvable — es-tu bien en jeu (pas dans un menu) ?")
        return true
    end

    local h, before, after = GivePoints(n)
    if not h then
        cout(Ar, "[xp] échec : aucun holder n'a accepté d'incrémenter " .. STAT ..
                 ". Ouvre l'arbre de perks une fois puis réessaie.")
        return true
    end
    cout(Ar, string.format("[xp] +%d → %.0f point(s) d'Ætherfact (avant : %.0f).",
        n, after, before))
    return true
end)

log("Chargé. Console in-game (F10) : xp  |  xp <n>  |  xp status")
