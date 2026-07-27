-- ============================================================
--  RankData.lua - Coleta de dados do personagem (B42.19+)
-- ============================================================

require "RankMod/RankLog"

RankData = {}

-- Coleta todas as habilidades dinamicamente via Perks.fromIndex (padrao do jogo, vide ISPerkLog.lua).
-- perk:getType() devolve o ID ingles (ex: "Blunt", "Woodwork") - o backend traduz para PT-BR.
-- perk:getParent() ~= Perks.None filtra as categorias-raiz (Fisica, Combate?) que nao tem nivel.
-- Abordagem dinamica: novos perks adicionados no B42 sao coletados automaticamente.
function RankData.getSkills(player)
    local rawTable = {}
    local strs     = {}

    local maxIndexOk, maxIndex = pcall(function() return Perks.getMaxIndex() end)
    if not maxIndexOk or not maxIndex then
        RankLog.warn("getSkills: Perks.getMaxIndex() indisponivel")
        return rawTable, strs
    end

    for i = 0, maxIndex - 1 do
        local perkEnum = Perks.fromIndex(i)
        local perkDef  = PerkFactory.getPerk(perkEnum)
        if perkDef and perkDef:getParent() ~= Perks.None then
            local lvlOk, lvl = pcall(function() return player:getPerkLevel(perkEnum) end)
            if lvlOk and lvl ~= nil then
                local id = tostring(perkDef:getType())
                table.insert(rawTable, { id = id, level = lvl })
                table.insert(strs, id .. " " .. lvl)
            end
        end
    end

    RankLog.info(string.format("getSkills: %d skills coletadas", #rawTable))
    return rawTable, strs
end

function RankData.minutesToYDHM(minutes)
    minutes = minutes or 0
    local m          = minutes % 60
    local totalHours = math.floor(minutes / 60)
    local h          = totalHours % 24
    local totalDays  = math.floor(totalHours / 24)
    local y          = math.floor(totalDays / 365)
    local d          = totalDays % 365

    local parts = {}
    if y > 0 then table.insert(parts, y .. " ano" .. (y > 1 and "s" or "")) end
    if y > 0 or d > 0 then table.insert(parts, d .. " dia" .. (d ~= 1 and "s" or "")) end
    if h > 0 or (y == 0 and d == 0) then table.insert(parts, h .. "h") end
    if m > 0 or #parts == 0 then table.insert(parts, m .. "m") end
    return table.concat(parts, ", ")
end

local function getCharacterName(player)
    if type(player.getDescriptor) ~= "function" then
        local userOk, username = pcall(function() return player:getUsername() end)
        if userOk and username and username ~= "" then return username end
        return "Sobrevivente"
    end
    local descOk, desc = pcall(function() return player:getDescriptor() end)
    if descOk and desc then
        local foreOk, forename = pcall(function() return desc:getForename() end)
        local surOk,  surname  = pcall(function() return desc:getSurname() end)
        local full = ((foreOk and forename) or "") .. " " .. ((surOk and surname) or "")
        full = full:gsub("^%s+", ""):gsub("%s+$", "")
        if full ~= "" then return full end
    end
    local userOk, username = pcall(function() return player:getUsername() end)
    if userOk and username and username ~= "" then return username end
    return "Sobrevivente"
end

-- Tentativa de obter a profissao via metodos do descriptor.
-- REGRA: NUNCA chamar um metodo sem verificar existencia antes.
-- Em B42.19 o bridge Kahlua NAO registra todos os metodos Java:
--   ? getProfession()  -> lanca RuntimeException (tipo nao mapeado)
--   ? getOccupation()  -> nil no bridge -> "Tried to call nil" (tambem logado pelo PZ)
-- Ambos os erros sao logados pelo PZ mesmo quando capturados por pcall.
-- A verificacao type(desc.X) == "function" garante que so chamamos o que existe.
local function getProfessionName(player)
    if not player then
        return "Desconhecida"
    end

    local ok, desc = pcall(function()
        return player:getDescriptor()
    end)

    if not ok or not desc then
        return "Desconhecida"
    end

    local okProf, profession = pcall(function()
        return desc:getCharacterProfession()
    end)

    if not okProf or not profession then
        return "Desconhecida"
    end

    local okDef, professionDef = pcall(function()
        return CharacterProfessionDefinition.getCharacterProfessionDefinition(profession)
    end)

    if not okDef or not professionDef then
        return tostring(profession)
    end

    local okName, professionName = pcall(function()
        return professionDef:getUIName()
    end)

    if okName and professionName and professionName ~= "" then
        return professionName
    end

    return tostring(profession)
end

-- Coleta os tracos (traits) via API oficial do B42 (ISPlayerStatsUI.lua, SpawnItems.lua):
--   player:getCharacterTraits():getKnownTraits()          -> lista de traits ativas
--   CharacterTraitDefinition.getCharacterTraitDefinition(obj):getType() -> ID ingles
-- Os IDs sao exportados em ingles (ex: "Athletic", "Smoker") para traducao no site.
local function collectTraits(player)
    local result = {}

    local ctOk, charTraits = pcall(function() return player:getCharacterTraits() end)
    if not ctOk or not charTraits then
        RankLog.warn("collectTraits: getCharacterTraits() indisponivel")
        return result
    end

    local knownOk, known = pcall(function() return charTraits:getKnownTraits() end)
    if not knownOk or not known then
        RankLog.warn("collectTraits: getKnownTraits() indisponivel")
        return result
    end

    local size = known:size()
    for i = 0, size - 1 do
        local defOk, def = pcall(function()
            return CharacterTraitDefinition.getCharacterTraitDefinition(known:get(i))
        end)
        if defOk and def then
            local typeOk, traitId = pcall(function() return tostring(def:getType()) end)
            if typeOk and traitId and traitId ~= "" and traitId ~= "nil" then
                table.insert(result, traitId)
            end
        end
    end

    RankLog.info(string.format("collectTraits: %d traits: %s",
        #result, table.concat(result, ",")))
    return result
end

-- Detecta se o jogador esta morto quando isDead nao e passado explicitamente.
local function resolveIsDead(player, isDead)
    if isDead ~= nil then return isDead end
    local ok, dead = pcall(function() return player:isDead() end)
    if ok and dead ~= nil then return dead == true end
    local hOk, hp = pcall(function()
        return player:getBodyDamage():getOverallBodyHealth()
    end)
    if hOk and type(hp) == "number" then return hp <= 0 end
    return false
end

-- isDead: true = chamado por morte, false/nil = trigger manual (jogador vivo)
function RankData.collect(player, isDead)
    if not player then
        RankLog.error("RankData.collect chamado sem player valido.")
        return nil
    end

    local timeRaw = 0
    if player.getHoursSurvived then
        timeRaw = math.floor((player:getHoursSurvived() or 0) * 60)
    elseif player.getTimeSurvived then
        timeRaw = math.floor(player:getTimeSurvived() or 0)
    else
        local gt = GameTime.getInstance()
        local worldHours = gt.getWorldAgeHours and gt:getWorldAgeHours() or 0
        timeRaw = math.floor(worldHours * 60)
    end

    local kills = 0
    if player.getZombieKills then
        kills = player:getZombieKills() or 0
    elseif player.getKills then
        kills = player:getKills() or 0
    elseif player.getNumZombiesKilled then
        kills = player:getNumZombiesKilled() or 0
    end

    local skillsRaw, skillsStrs = RankData.getSkills(player)

    local maxSkills = 0
    for _, s in ipairs(skillsRaw) do
        if s.level >= 10 then maxSkills = maxSkills + 1 end
    end

    local dead = resolveIsDead(player, isDead)
    local profession = getProfessionName(player)
    local traits = collectTraits(player)

    RankLog.info(string.format(
        "Dados coletados: kills=%d, tempo_min=%d, skills=%d, max=%d, morto=%s, prof=%s, traits=%d",
        kills, timeRaw, #skillsRaw, maxSkills, tostring(dead), profession, #traits))

    return {
        character_name = getCharacterName(player),
        profession      = profession,
        kills           = kills,
        time_raw        = timeRaw,
        time_str        = RankData.minutesToYDHM(timeRaw),
        skills          = skillsStrs,
        skills_raw      = skillsRaw,
        max_skills      = maxSkills,
        is_dead         = dead,
        traits          = traits,
    }
end
