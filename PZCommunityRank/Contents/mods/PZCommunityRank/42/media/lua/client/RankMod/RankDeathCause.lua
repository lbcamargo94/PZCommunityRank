-- RankDeathCause.lua
-- Detecção estruturada de causa de morte integrada ao PZCommunityRank.
-- Adaptado da lógica do mod CauseOfDeath (Steam Workshop #3775044475).
-- Retorna chaves estruturadas (ex: "zombie_horde") em vez de strings localizadas;
-- a tradução fica no frontend.
--
-- Ordem de prioridade: causas violentas/instantâneas primeiro, lentas/acumuladas por último.
--
-- NOTA KAHLUA: pcall NÃO captura java.lang.RuntimeException — apenas erros Lua.
-- Todo acesso a método Java que possa lançar RuntimeException usa pcall individual.

RankDeathCause = RankDeathCause or {}

-- Black box recorder: velocidade do veículo não sobrevive ao momento da morte.
RankDeathCause.lastSpeed = {}
RankDeathCause.lastCrash = {}

-- Memória de bleach: o stat POISON sozinho não distingue causa.
RankDeathCause.lastBleach = {}

local CRASH_DROP_KMH        = 25
local CRASH_MEMORY_SECONDS  = 30
local BLEACH_MEMORY_SECONDS = 1800

-- ISDrinkFromBottle pode não existir em todas as builds do B42; carrega de forma segura.
local _drinkOk = pcall(function() require "TimedActions/ISDrinkFromBottle" end)

-- anyBodyPart: itera partes do corpo Java com pcall completo.
local function anyBodyPart(bd, checkFn)
    local ok, result = pcall(function()
        local parts = bd:getBodyParts()
        for i = 0, parts:size() - 1 do
            if checkFn(parts:get(i)) then return true end
        end
        return false
    end)
    return ok and result == true
end

local function trackVehicleSpeed(playerObj)
    -- Envolvido em pcall: isDead/isSeatedInVehicle/getCurrentSpeedKmHour
    -- são chamadas Java que podem lançar RuntimeException a qualquer tick.
    pcall(function()
        if not playerObj or playerObj:isDead() then return end
        if not playerObj:isSeatedInVehicle() then return end
        local vehicle = playerObj:getVehicle()
        if not vehicle then return end
        local speed = math.abs(vehicle:getCurrentSpeedKmHour())
        local prev = RankDeathCause.lastSpeed[playerObj]
        if prev and (prev - speed) >= CRASH_DROP_KMH then
            RankDeathCause.lastCrash[playerObj] = { speed = math.floor(speed + 0.5), time = getTimestamp() }
        end
        RankDeathCause.lastSpeed[playerObj] = speed
    end)
end
Events.OnPlayerUpdate.Add(trackVehicleSpeed)

if _drinkOk and ISDrinkFromBottle and ISDrinkFromBottle.drink then
    local origDrink = ISDrinkFromBottle.drink
    function ISDrinkFromBottle:drink(food, percentage)
        -- self.character pode ser nil se o objeto for criado antes do personagem carregar
        if self.character then
            local ok, hasBleach = pcall(function()
                return food and food:getFluidContainer() and food:getFluidContainer():contains(Fluid.Bleach)
            end)
            if ok and hasBleach then
                RankDeathCause.lastBleach[self.character] = getTimestamp()
            end
        end
        -- origDrink sem pcall propagaria RuntimeException para o engine; envolver protege a cadeia
        local callOk, err = pcall(origDrink, self, food, percentage)
        if not callOk then
            print("[RankDeathCause] origDrink falhou: " .. tostring(err))
        end
    end
end

-- ── Detectores individuais ─────────────────────────────────────────────────

local function detectVehicle(p)
    local crash = RankDeathCause.lastCrash[p]
    if not crash then return nil end
    if getTimestamp() - crash.time > CRASH_MEMORY_SECONDS then return nil end
    return "vehicle"
end

local function detectPvP(p)
    if not p.getLastHitCharacter then return nil end
    local ok, killer = pcall(function() return p:getLastHitCharacter() end)
    if not ok or not killer then return nil end
    if not instanceof(killer, "IsoPlayer") or killer == p then return nil end
    return "pvp"
end

local function detectZombie(p)
    local bdOk, bd = pcall(function() return p:getBodyDamage() end)
    if not bdOk or not bd then return nil end

    local horde = false
    local ok1, dragDown = pcall(function() return p:isDeathDragDown() end)
    if ok1 and dragDown then horde = true end
    if not horde then
        local ok2, count = pcall(function() return p:getSurroundingAttackingZombies() end)
        if ok2 and count and count >= 2 then horde = true end
    end

    local bitten = anyBodyPart(bd, function(pt) return pt:bitten() or pt:isInfectedWound() end)

    -- Mortalidade instantânea: bd:isInfected() é o flag real do vírus sistêmico.
    local systemic = false
    if not bitten and not horde then
        local ok3, inf = pcall(function() return bd:isInfected() end)
        if ok3 and inf then systemic = true end
    end

    if not bitten and not horde and not systemic then return nil end
    if horde    then return "zombie_horde" end
    if bitten   then return "zombie"       end
    return "zombie_virus"
end

local function detectBurned(p)
    local ok, onFire = pcall(function() return p:isOnFire() end)
    if ok and onFire then return "burned" end
    return nil
end

local function detectBled(p)
    local bdOk, bd = pcall(function() return p:getBodyDamage() end)
    if not bdOk or not bd then return nil end
    if anyBodyPart(bd, function(pt) return pt:bleeding() end) then return "bled" end
    return nil
end

local function detectInfection(p)
    local bdOk, bd = pcall(function() return p:getBodyDamage() end)
    if not bdOk or not bd then return nil end
    if anyBodyPart(bd, function(pt) return pt:isInfectedWound() or pt:getWoundInfectionLevel() > 0 end) then
        return "infection"
    end
    return nil
end

local function detectPoison(p)
    -- Cadeia p:getStats():get(...) partida em dois pcall: se getStats() retornar
    -- null Java o segundo :get() lançaria RuntimeException escapando pcall único.
    local statsOk, stats = pcall(function() return p:getStats() end)
    if not statsOk or not stats then return nil end
    local poisonOk, poisonVal = pcall(function() return stats:get(CharacterStat.POISON) end)
    if not poisonOk or not poisonVal or poisonVal <= 0 then return nil end
    local last = RankDeathCause.lastBleach[p]
    if last and (getTimestamp() - last <= BLEACH_MEMORY_SECONDS) then
        return "bleach"
    end
    return "poison"
end

local function detectFall(p)
    local ok, fd = pcall(function() return p:getFallDamage() end)
    if not ok or not fd then return nil end
    local ok2, lethal = pcall(function() return fd:isLethalFall() end)
    if ok2 and lethal then return "fall" end
    return nil
end

local FATAL_MOODLE = 4

-- Helper: lê nível de moodle com cadeia pcall segura.
-- p:getMoodles() pode retornar null Java → getMoodleLevel nesse null lança RuntimeException.
local function getMoodleLevel(p, moodleType)
    local moodlesOk, moodles = pcall(function() return p:getMoodles() end)
    if not moodlesOk or not moodles then return -1 end
    local lvlOk, lvl = pcall(function() return moodles:getMoodleLevel(moodleType) end)
    if not lvlOk or lvl == nil then return -1 end
    return lvl
end

local function detectCold(p)
    if getMoodleLevel(p, MoodleType.HYPOTHERMIA) >= FATAL_MOODLE then return "cold" end
    return nil
end

local function detectSick(p)
    if getMoodleLevel(p, MoodleType.SICK) >= FATAL_MOODLE then return "sick" end
    return nil
end

local function detectHunger(p)
    if getMoodleLevel(p, MoodleType.HUNGRY) >= FATAL_MOODLE then return "hunger" end
    return nil
end

local function detectThirst(p)
    if getMoodleLevel(p, MoodleType.THIRST) >= FATAL_MOODLE then return "thirst" end
    return nil
end

local DETECTORS = {
    detectVehicle,
    detectPvP,
    detectZombie,
    detectBurned,
    detectBled,
    detectInfection,
    detectPoison,
    detectFall,
    detectCold,
    detectSick,
    detectHunger,
    detectThirst,
}

-- Retorna chave estruturada ou string vazia se desconhecida.
function RankDeathCause.detect(playerObj)
    if not playerObj then return "" end
    for _, det in ipairs(DETECTORS) do
        local ok, key = pcall(det, playerObj)
        if ok and key then
            return key
        elseif not ok then
            print("[RankDeathCause] detector falhou: " .. tostring(key))
        end
    end
    return ""
end
