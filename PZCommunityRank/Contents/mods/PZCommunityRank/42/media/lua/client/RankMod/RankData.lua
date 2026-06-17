-- ============================================================
--  RankData.lua — Coleta de dados do personagem (B42.19+)
-- ============================================================

require "RankMod/RankLog"

RankData = {}

local PERKS = {
    { id = "Sprinting",    nome = "Corrida"             },
    { id = "Lightfooted",  nome = "Pés Leves"           },
    { id = "Nimble",       nome = "Agilidade"           },
    { id = "Sneaking",     nome = "Furtividade"         },
    { id = "Fitness",      nome = "Condicionamento"     },
    { id = "Strength",     nome = "Força"               },
    { id = "Axe",          nome = "Machado"             },
    { id = "LongBlunt",    nome = "Cont. Longo"         },
    { id = "ShortBlunt",   nome = "Cont. Curto"         },
    { id = "LongBlade",    nome = "Lâmina Longa"        },
    { id = "ShortBlade",   nome = "Lâmina Curta"        },
    { id = "Spear",        nome = "Lança"               },
    { id = "Maintenance",  nome = "Manutenção"          },
    { id = "Aiming",       nome = "Mira"                },
    { id = "Reloading",    nome = "Recarga"             },
    { id = "Cooking",      nome = "Culinária"           },
    { id = "Fishing",      nome = "Pesca"               },
    { id = "Trapping",     nome = "Armadilhas"          },
    { id = "Foraging",     nome = "Coleta"              },
    { id = "FirstAid",     nome = "Primeiros Socorros"  },
    { id = "Carpentry",    nome = "Carpintaria"         },
    { id = "Agriculture",  nome = "Agricultura"         },
    { id = "Electrical",   nome = "Eletricidade"        },
    { id = "Mechanics",    nome = "Mecânica"            },
    { id = "MetalWelding", nome = "Soldagem"            },
    { id = "Tailoring",    nome = "Costura"             },
    { id = "Knapping",     nome = "Lascamento"          },
    { id = "Carving",      nome = "Entalhamento"        },
    { id = "Masonry",      nome = "Alvenaria"           },
    { id = "Pottery",      nome = "Cerâmica"            },
    { id = "Blacksmith",   nome = "Ferraria"            },
    { id = "Glassmaking",  nome = "Vidraria"            },
    { id = "AnimalCare",   nome = "Cuidado Animal"      },
    { id = "Butchering",   nome = "Abate"               },
    { id = "Tracking",     nome = "Rastreamento"        },
}

local function getPerkObj(id)
    local ok1, enumVal = pcall(function() return Perks[id] end)
    if ok1 and enumVal then
        local ok2, p = pcall(function() return PerkFactory.getPerk(enumVal) end)
        if ok2 and p then return p end
        return enumVal
    end
    local ok3, p = pcall(PerkFactory.getPerkByName, id)
    if ok3 and p then return p end
    return nil
end

-- Retorna (rawTable, stringsTable) — raw para a UI, strings para o código.
function RankData.getSkills(player)
    local result = {}
    for _, perk in ipairs(PERKS) do
        local perkObj = getPerkObj(perk.id)
        if perkObj then
            local lvlOk, lvl = pcall(function() return player:getPerkLevel(perkObj) end)
            if lvlOk and lvl ~= nil then
                table.insert(result, { nome = perk.nome, level = lvl })
            end
        end
    end
    table.sort(result, function(a, b) return a.nome < b.nome end)

    local strs = {}
    for _, s in ipairs(result) do
        table.insert(strs, s.nome .. " " .. s.level)
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

-- desc:getProfession*() retornam tipos Java não-mapeados no Kahlua B42.19,
-- causando RuntimeException que escapa do pcall. Sem caminho seguro disponível.
local function getProfessionName()
    return "Desconhecida"
end

local function getWeightStr(player)
    -- Verificação de existência via dot-notation (retorna nil se não existe, não lança erro).
    if not player.getNutrition then return "?" end
    local ok, w = pcall(function() return player:getNutrition():getWeight() end)
    if ok and type(w) == "number" then
        return string.format("%.1f Kg", w):gsub("%.", ",")
    end
    return "?"
end

local function getTraitsStr(player)
    -- CharacterTrait não é tipo registrado no Kahlua B42.19:
    -- traits:get(i) causa RuntimeException que escapa do pcall.
    return ""
end

function RankData.collect(player)
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

    RankLog.info(string.format("Dados coletados: kills=%d, tempo_min=%d, skills=%d, max=%d",
        kills, timeRaw, #skillsRaw, maxSkills))

    return {
        character_name = getCharacterName(player),
        profession      = getProfessionName(),
        weight_str      = getWeightStr(player),
        traits_str      = getTraitsStr(player),
        kills           = kills,
        time_raw        = timeRaw,
        time_str        = RankData.minutesToYDHM(timeRaw),
        skills          = skillsStrs,
        skills_raw      = skillsRaw,
        max_skills      = maxSkills,
    }
end
