-- ============================================================
--  RankData.lua — Coleta de dados do personagem (B42.19+)
-- ============================================================

require "RankMod/RankLog"

RankData = {}

-- IDs confirmados no B42.19 via probe de Perks[].
-- LongBlunt+ShortBlunt → mesclados em "Blunt" no B42.
-- ShortBlade, Foraging e Knapping: nomes B42 ainda não confirmados (probe em andamento).
local PERKS = {
    { id = "Sprinting",    nome = "Corrida"             },
    { id = "Lightfoot",    nome = "Pés Leves"           },
    { id = "Nimble",       nome = "Agilidade"           },
    { id = "Sneak",        nome = "Furtividade"         },
    { id = "Fitness",      nome = "Condicionamento"     },
    { id = "Strength",     nome = "Força"               },
    { id = "Axe",          nome = "Machado"             },
    { id = "Blunt",        nome = "Contundente Longo"   },
    { id = "SmallBlunt",   nome = "Contundente Curto"   },
    { id = "LongBlade",    nome = "Lâmina Longa"        },
    { id = "SmallBlade",   nome = "Lâmina Curta"        },
    { id = "Spear",        nome = "Lança"               },
    { id = "Maintenance",  nome = "Manutenção"          },
    { id = "Aiming",       nome = "Mira"                },
    { id = "Reloading",    nome = "Recarga"             },
    { id = "Cooking",      nome = "Culinária"           },
    { id = "Fishing",      nome = "Pesca"               },
    { id = "Trapping",     nome = "Armadilhas"          },
    { id = "Survivalist",  nome = "Sobrevivência"       },
    { id = "Doctor",       nome = "Medicina"            },
    { id = "Woodwork",     nome = "Marcenaria"          },
    { id = "Farming",      nome = "Agricultura"         },
    { id = "Electricity",  nome = "Eletricidade"        },
    { id = "Mechanics",    nome = "Mecânica"            },
    { id = "MetalWelding", nome = "Soldagem"            },
    { id = "Tailoring",    nome = "Costura"             },
    { id = "FlintKnapping",nome = "Lascamento"          },
    { id = "Carving",      nome = "Entalhamento"        },
    { id = "Masonry",      nome = "Alvenaria"           },
    { id = "Pottery",      nome = "Cerâmica"            },
    { id = "Blacksmith",   nome = "Ferraria"            },
    { id = "Glassmaking",  nome = "Vidraria"            },
    { id = "Husbandry",    nome = "Pecuária"            },
    { id = "Butchering",   nome = "Abate"               },
    { id = "Tracking",     nome = "Rastreamento"        },
}

-- Cache descoberto em runtime para evitar múltiplos warns do mesmo ID.
local _perkCache = {}
local _perkMiss  = {}

-- Retorna o enum constant de Perks[] ou nil.
-- player:getPerkLevel() aceita o enum constant diretamente — PerkFactory.getPerk não é necessário.
-- Perks[key] retorna nil para chaves inexistentes sem lançar exceção.
local function getPerkObj(id)
    if _perkCache[id] ~= nil then return _perkCache[id] end
    if _perkMiss[id]  then return nil end
    local p = Perks[id]
    if p ~= nil then
        _perkCache[id] = p
        return p
    end
    _perkMiss[id] = true
    RankLog.warn("getPerkObj: ID nao resolvido em B42 — " .. id)
    return nil
end


-- Retorna (rawTable, stringsTable).
-- rawTable: [{id, nome, level}] — usado internamente (maxSkills, UI futura).
-- stringsTable: ["ID nivel", ...] — formato exportado no código PZRX2.
-- Exportar o ID em inglês (em vez do nome PT-BR) permite ao backend usar uma
-- tabela de tradução central e garante que nomes PT-BR não variem entre versões.
function RankData.getSkills(player)
    local result = {}
    for _, perk in ipairs(PERKS) do
        local perkObj = getPerkObj(perk.id)
        if perkObj then
            local lvlOk, lvl = pcall(function() return player:getPerkLevel(perkObj) end)
            if lvlOk and lvl ~= nil then
                table.insert(result, { id = perk.id, nome = perk.nome, level = lvl })
            end
        end
    end
    table.sort(result, function(a, b) return a.nome < b.nome end)

    local strs = {}
    for _, s in ipairs(result) do
        table.insert(strs, s.id .. " " .. s.level)
    end
    return result, strs
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

-- Tentativa de obter a profissão via métodos do descriptor.
-- REGRA: NUNCA chamar um método sem verificar existência antes.
-- Em B42.19 o bridge Kahlua NÃO registra todos os métodos Java:
--   • getProfession()  → lança RuntimeException (tipo não mapeado)
--   • getOccupation()  → nil no bridge → "Tried to call nil" (também logado pelo PZ)
-- Ambos os erros são logados pelo PZ mesmo quando capturados por pcall.
-- A verificação type(desc.X) == "function" garante que só chamamos o que existe.
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

-- Detecta se o jogador está morto quando isDead não é passado explicitamente.
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

    RankLog.info(string.format(
        "Dados coletados: kills=%d, tempo_min=%d, skills=%d, max=%d, morto=%s, prof=%s",
        kills, timeRaw, #skillsRaw, maxSkills, tostring(dead), profession))

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
    }
end
