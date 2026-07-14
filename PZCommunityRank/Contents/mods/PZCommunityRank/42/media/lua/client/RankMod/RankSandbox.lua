-- ============================================================
--  RankSandbox.lua - Validador de configuracoes do Sandbox (B42.19+)
--
--  Compara o SandboxVars ativo com as regras do desafio oficial.
--  Abre um ISPanel de alerta quando algo diverge.
--  Nao bloqueia o jogo - apenas avisa.
--
--  Enums reais do B42.19 (extraidos do preset "Brasileirao PZ.cfg"):
--
--  ZombieLore.Speed:        1=Corredores  2=Normal  3=Lento  4=Aleatorio
--  ZombieLore.Strength:     1=Super-humano  2=Normal  3=Fraco  4=Aleatorio
--  ZombieLore.Toughness:    1=Resistente    2=Normal  3=Fragil 4=Aleatorio
--  ZombieLore.Hearing:      1=Alta  2=Normal  3=Baixa  4=Aleat.  5=Aleat.(Normal/Ruim)
--  ZombieLore.Sight:        1=Aguia 2=Normal  3=Ruim   4=Aleat.  5=Aleat.(Normal/Ruim)
--  ZombieLore.Memory:       1=Longo 2=Normal  3=Curto  4=Nenhum  5=Aleat.
--  ZombieLore.Cognition:    1=Avancado(abre portas) 2=Normal 3=Basico 4=Aleat.
--  ZombieLore.DisableFakeDead: 1=Parcial 2=Total(incl.mortos pelo jogador) 3=Nenhum
--  ZombieLore.CrawlUnderVehicle: 1=SoRastejantes 2=ExtRaro..7=Sempre
--  WaterShut / ElecShut:    1=Instantaneo 2=0-30 Dias ...
--  AlarmDecay:              1=Instantaneo .. 6=0-5 Anos
--  Alarm:                   1=Nunca .. 6=Muito Frequentemente
--  NightDarkness:           1=Comp.Escuro  2=Escuro  3=Normal  4=Claro
--  Temperature:             1=Muito Frio   2=Frio    3=Normal  4=Quente  5=M.Quente
--  Rain:                    1=Bem Seco     2=Seco    3=Normal  4=Chuvoso 5=B.Chuvoso
--  FishAbundance/NatureAbundance: 1=Muito Ruim .. 5=Muito Abundante
--  MetaEvent:               1=Nunca  2=Algumas Vezes  3=Frequentemente
--  ChanceHasGas:            1=Baixo  2=Normal  3=Alto
--  InitialGas:              1=Muito Baixo .. 6=Cheio
--  LockedCar:               1=Nunca .. 6=Muito Frequentemente
--  CarGeneralCondition:     1=Muito Baixo .. 5=Muito Alto
--  GeneratorSpawning:       1=Ext.Raro .. 7=Abundante
--  AnimalRanchChance:       1=Nunca  2=Ext.Raro .. 7=Sempre
-- ============================================================

require "RankMod/RankLog"

RankSandbox = {}

-- -- Regras do Desafio Oficial ----------------------------------------------
--
--  key:      caminho no SandboxVars (pontos indicam sub-tabela)
--  expected: valor esperado (numero, booleano ou string)
--  tol:      tolerancia para floats (padrao 0.01)

local RULES = {
    -- [ ZUMBIS - Populacao ]
    { key = "ZombieConfig.PopulationMultiplier",       expected = 4.0, label = "Pop. Multiplicador",         tol = 0.05 },
    { key = "ZombieConfig.PopulationStartMultiplier",  expected = 2.0, label = "Pop. Inicial",                tol = 0.05 },
    { key = "ZombieConfig.PopulationPeakMultiplier",   expected = 2.0, label = "Pop. Pico",                   tol = 0.05 },
    { key = "ZombieConfig.PopulationPeakDay",          expected = 1,   label = "Dia do Pico" },

    -- [ ZUMBIS - Comportamento ]
    { key = "ZombieLore.Speed",                        expected = 2,    label = "Velocidade (Normal=2)" },
    { key = "ZombieLore.SprinterPercentage",           expected = 0,    label = "% Corredores (0)" },
    { key = "ZombieLore.Strength",                     expected = 1,    label = "Forca (Super-humano=1)" },
    { key = "ZombieLore.Toughness",                    expected = 2,    label = "Resistencia (Normal=2)" },
    { key = "ZombieLore.Reanimate",                    expected = 1,    label = "Reanimacao (Instantaneo=1)" },
    { key = "ZombieLore.Hearing",                      expected = 1,    label = "Audicao (Alta=1)" },
    { key = "ZombieLore.Sight",                        expected = 1,    label = "Visao (Aguia=1)" },
    { key = "ZombieLore.Memory",                       expected = 1,    label = "Memoria (Longa=1)" },
    { key = "ZombieLore.Cognition",                    expected = 1,    label = "Percepcao/Portas (Avancado=1)" },
    { key = "ZombieConfig.FollowSoundDistance",        expected = 250,  label = "Raio de Audicao (250)" },
    { key = "ZombieConfig.RespawnHours",               expected = 0.0,  label = "Respawn (Nenhum=0)",          tol = 0.01 },
    { key = "ZombieConfig.RedistributeHours",          expected = 48.0, label = "Migracao de Zumbis (48h)",     tol = 0.5  },
    { key = "ZombieConfig.RallyGroupSizeVariance",     expected = 20,   label = "Variancia Horda (20)" },
    { key = "ZombieConfig.RallyTravelDistance",        expected = 10,   label = "Distancia Rally (10)" },
    { key = "ZombieLore.DisableFakeDead",              expected = 2,    label = "Fake Dead Total (2)" },
    { key = "ZombieLore.ZombiesCrawlersDragDown",      expected = true, label = "Rastejadores Derrubam" },
    { key = "ZombieConfig.RallyGroupSize",             expected = 1,    label = "Tamanho da Horda (1)" },

    -- [ LOOT ] - todas as 22 categorias do B42 (0.04 = Muito Baixo)
    { key = "FoodLootNew",          expected = 0.04, label = "Comida",                  tol = 0.01 },
    { key = "CannedFoodLootNew",    expected = 0.04, label = "Comida Enlatada",          tol = 0.01 },
    { key = "WeaponLootNew",        expected = 0.04, label = "Armas Corpo a Corpo",      tol = 0.01 },
    { key = "RangedWeaponLootNew",  expected = 0.04, label = "Armas de Longo Alcance",   tol = 0.01 },
    { key = "AmmoLootNew",          expected = 0.04, label = "Municao",                  tol = 0.01 },
    { key = "MedicalLootNew",       expected = 0.04, label = "Medico",                   tol = 0.01 },
    { key = "SurvivalGearsLootNew", expected = 0.04, label = "Equip. de Sobrev.",        tol = 0.01 },
    { key = "ClothingLootNew",      expected = 0.04, label = "Roupas",                   tol = 0.01 },
    { key = "MechanicsLootNew",     expected = 0.04, label = "Mecanica",                 tol = 0.01 },
    { key = "ToolLootNew",          expected = 0.04, label = "Ferramentas",              tol = 0.01 },
    { key = "MaterialLootNew",      expected = 0.04, label = "Materiais",                tol = 0.01 },
    { key = "CookwareLootNew",      expected = 0.04, label = "Utensilios de Cozinha",    tol = 0.01 },
    { key = "FarmingLootNew",       expected = 0.04, label = "Agricultura",              tol = 0.01 },
    { key = "SkillBookLoot",        expected = 0.04, label = "Livros de Habilidade",     tol = 0.01 },
    { key = "LiteratureLootNew",    expected = 0.04, label = "Literatura",               tol = 0.01 },
    { key = "RecipeResourceLoot",   expected = 0.04, label = "Recursos de Receitas",     tol = 0.01 },
    { key = "MediaLootNew",         expected = 0.04, label = "Midia",                    tol = 0.01 },
    { key = "MementoLootNew",       expected = 0.04, label = "Lembrancas",               tol = 0.01 },
    { key = "ContainerLootNew",     expected = 0.04, label = "Containers",               tol = 0.01 },
    { key = "KeyLootNew",           expected = 0.04, label = "Chaves",                   tol = 0.01 },
    { key = "OtherLootNew",         expected = 0.04, label = "Outros Itens",             tol = 0.01 },
    { key = "GeneratorSpawning",    expected = 1,    label = "Geradores (Ext.Raro=1)" },

    -- [ MUNDO ]
    { key = "ZombieVoronoiNoise", expected = false, label = "Voronoi Noise (Desativado)" },
    { key = "WaterShut",  expected = 1, label = "Agua Instantanea (1)" },
    { key = "ElecShut",   expected = 1, label = "Eletric. Instantanea (1)" },
    { key = "AlarmDecay", expected = 6, label = "Bateria Alarme (0-5 Anos=6)" },
    { key = "Alarm",      expected = 6, label = "Alarmes Casas (Muito Freq.=6)" },

    -- [ NATUREZA ]
    { key = "NightDarkness",  expected = 2, label = "Escuridao Noite (Escuro=2)" },
    { key = "Temperature",    expected = 2, label = "Temperatura (Frio=2)" },
    { key = "Rain",           expected = 2, label = "Chuva (Seco=2)" },
    { key = "FishAbundance",  expected = 1, label = "Pesca (Muito Ruim=1)" },
    { key = "NatureAbundance",expected = 1, label = "Natureza (Muito Ruim=1)" },

    -- [ AMBIENTE ]
    { key = "MetaEvent", expected = 2, label = "Eventos Aleatorios (AlgumasVezes=2)" },

    -- [ PERSONAGEM ]
    { key = "MultiplierConfig.Global", expected = 0.8, label = "Mult. XP Global (0.8)", tol = 0.05 },

    -- [ VEICULOS ]
    { key = "ChanceHasGas",        expected = 1, label = "Gasolina (Baixo=1)" },
    { key = "InitialGas",          expected = 1, label = "Gasolina Inicial (M.Baixo=1)" },
    { key = "LockedCar",           expected = 6, label = "Veiculos Trancados (M.Freq.=6)" },
    { key = "CarGeneralCondition", expected = 1, label = "Cond. Veiculos (M.Baixo=1)" },

    -- [ ANIMAIS ]
    { key = "AnimalRanchChance", expected = 2, label = "Animais (Ext.Raro=2)" },
}

-- -- Leitura de sub-tabelas via path com pontos -----------------------------
--  "ZombieLore.Speed"  ->  SandboxVars.ZombieLore.Speed
--  "Map.AllowMiniMap"  ->  SandboxVars.Map.AllowMiniMap
--  "Temperature"       ->  SandboxVars.Temperature

local function readVar(key)
    local ok, val = pcall(function()
        local t = SandboxVars
        for part in key:gmatch("[^.]+") do
            if type(t) ~= "table" and type(t) ~= "userdata" then return nil end
            t = t[part]
        end
        return t
    end)
    if ok then return val end
    return nil
end

local function valuesMatch(actual, expected, tol)
    if type(expected) == "boolean" then
        return actual == expected
    end
    if type(expected) == "number" and type(actual) == "number" then
        return math.abs(actual - expected) <= (tol or 0.01)
    end
    return actual == expected
end

-- -- Validacao principal ----------------------------------------------------

function RankSandbox.validate()
    local violations = {}
    local missing    = {}

    for _, rule in ipairs(RULES) do
        local actual = readVar(rule.key)

        if actual == nil then
            table.insert(missing, { key = rule.key, label = rule.label })
            RankLog.warn("SandboxVars." .. rule.key .. " nao encontrado")
        elseif not valuesMatch(actual, rule.expected, rule.tol) then
            table.insert(violations, {
                label    = rule.label,
                expected = rule.expected,
                got      = actual,
            })
            RankLog.warn(string.format(
                "SANDBOX INVALIDO - %s: esperado=%s atual=%s",
                rule.label, tostring(rule.expected), tostring(actual)
            ))
        else
            RankLog.info("OK - " .. rule.label .. " = " .. tostring(actual))
        end
    end

    return violations, missing
end

-- -- Escrita de sub-tabelas via path com pontos -----------------------------
--  Espelho de readVar, mas atribuindo em vez de lendo.

local function writeVar(key, value)
    local ok, err = pcall(function()
        local t = SandboxVars
        local parts = {}
        for part in key:gmatch("[^.]+") do
            table.insert(parts, part)
        end
        for i = 1, #parts - 1 do
            local p  = parts[i]
            local tt = type(t)
            if tt ~= "table" and tt ~= "userdata" then
                error("container '" .. p .. "' nao e tabela (type=" .. tt .. ")")
            end
            t = t[p]
        end
        if t == nil then
            error("container nulo para chave: " .. key)
        end
        t[parts[#parts]] = value
    end)
    return ok, err
end

-- Aplica todos os valores do RULES ao SandboxVars e sincroniza com Java.
function RankSandbox.applyRules()
    local applied = 0
    local failed  = 0
    for _, rule in ipairs(RULES) do
        local ok, err = writeVar(rule.key, rule.expected)
        if ok then
            applied = applied + 1
        else
            failed = failed + 1
            RankLog.warn("applyRules: falha em " .. rule.key .. ": " .. tostring(err))
        end
    end
    -- Sincroniza cada valor para o objeto Java SandboxOptions.
    -- getSandboxOptions():fromLua() nao existe no B42.19; usamos getOptionByName
    -- + parse/setValue + set, igual ao ISServerSandboxOptionsUI (linha 739).
    for _, rule in ipairs(RULES) do
        pcall(function()
            local opt = getSandboxOptions():getOptionByName(rule.key)
            if not opt then return end
            if type(rule.expected) == "boolean" then
                opt:setValue(rule.expected)
            else
                opt:parse(tostring(rule.expected))
            end
            getSandboxOptions():set(opt:getName(), opt:getValue())
        end)
    end
    RankLog.info(string.format("applyRules: %d/%d aplicados, %d falhos.", applied, #RULES, failed))
    return applied
end

-- Verifica o sandbox e corrige automaticamente qualquer divergencia.
-- Retorna true se o sandbox esta OK apos a operacao.
function RankSandbox.verifyAndCorrect()
    RankLog.info("verifyAndCorrect: verificando configuracoes do desafio...")
    local v1, _ = RankSandbox.validate()

    if #v1 == 0 then
        RankLog.info("verifyAndCorrect: sandbox OK - nenhuma correcao necessaria.")
        return true
    end

    RankLog.warn(string.format("verifyAndCorrect: %d divergencia(s) detectada(s) - corrigindo.", #v1))
    for _, v in ipairs(v1) do
        RankLog.warn(string.format("  X  %s: esperado=%s atual=%s",
            v.label, tostring(v.expected), tostring(v.got)))
    end

    RankSandbox.applyRules()

    -- Segunda verificacao para confirmar que correcoes foram aplicadas.
    local v2, _ = RankSandbox.validate()
    if #v2 == 0 then
        RankLog.info("verifyAndCorrect: correcoes aplicadas com sucesso. Sandbox OK.")
        return true
    end

    RankLog.warn(string.format("verifyAndCorrect: %d divergencia(s) persistem apos correcao.", #v2))
    for _, v in ipairs(v2) do
        RankLog.warn(string.format("  !  %s: esperado=%s atual=%s",
            v.label, tostring(v.expected), tostring(v.got)))
    end
    return false
end

-- Verifica todos os valores numericos e booleanos de BRASILEIRAO_CHALLENGE_PRESET
-- contra o SandboxVars ativo. Nao corrige - apenas detecta.
-- Retorna (ok, violations) onde violations = lista de { key, expected, got }.
function RankSandbox.verifyFullPreset()
    local preset = BRASILEIRAO_CHALLENGE_PRESET
    if not preset then
        RankLog.warn("verifyFullPreset: BRASILEIRAO_CHALLENGE_PRESET indisponivel.")
        return true, {}
    end

    local violations = {}

    local function flatCheck(tbl, prefix)
        if type(tbl) ~= "table" then return end
        for k, v in pairs(tbl) do
            if k ~= "Version" then
                local key = prefix and (prefix .. "." .. k) or k
                if type(v) == "table" then
                    flatCheck(v, key)
                elseif type(v) == "number" or type(v) == "boolean" then
                    local actual = readVar(key)
                    if actual ~= nil and not valuesMatch(actual, v, 0.01) then
                        table.insert(violations, { key = key, expected = v, got = actual })
                    end
                end
            end
        end
    end

    flatCheck(preset, nil)

    if #violations > 0 then
        RankLog.warn(string.format(
            "verifyFullPreset: %d violacao(es) encontrada(s).", #violations))
        for _, vi in ipairs(violations) do
            RankLog.warn(string.format("  X  %s: esperado=%s atual=%s",
                vi.key, tostring(vi.expected), tostring(vi.got)))
        end
    else
        RankLog.info("verifyFullPreset: preset completo OK.")
    end

    return #violations == 0, violations
end

-- Aplica recursivamente TODOS os valores de BRASILEIRAO_CHALLENGE_PRESET
-- ao SandboxVars (Lua) E ao getSandboxOptions() (Java) via getOptionByName.
-- Garante que saves em andamento recebam o preset atualizado ao carregar,
-- inclusive em sistemas Java (IA de zumbis, veiculos, eventos de mundo).
function RankSandbox.applyFullPreset()
    local preset = BRASILEIRAO_CHALLENGE_PRESET
    if not preset then
        RankLog.warn("applyFullPreset: BRASILEIRAO_CHALLENGE_PRESET indisponivel.")
        return false
    end

    -- Etapa 1: SandboxVars (Lua) - lido pela logica de jogo escrita em Lua.
    local function applyValues(src, dst)
        if type(src) ~= "table" then return end
        for k, v in pairs(src) do
            if k ~= "Version" then
                if type(v) == "table" then
                    local child = dst[k]
                    if type(child) == "table" or type(child) == "userdata" then
                        applyValues(v, child)
                    end
                else
                    pcall(function() dst[k] = v end)
                end
            end
        end
    end
    pcall(function() applyValues(preset, SandboxVars) end)

    -- Etapa 2: getSandboxOptions() (Java) - lido pela engine (IA, fisica, eventos).
    -- Despachamos por opt:getType() igual ao ISServerSandboxOptionsUI.lua:726:
    --   boolean/enum -> setValue   |   double/integer -> parse   |   string/text -> setValue
    local function syncToJava(tbl, prefix)
        if type(tbl) ~= "table" then return end
        for k, v in pairs(tbl) do
            if k ~= "Version" then
                local key = prefix and (prefix .. "." .. k) or k
                if type(v) == "table" then
                    syncToJava(v, key)
                else
                    pcall(function()
                        local opt = getSandboxOptions():getOptionByName(key)
                        if not opt then return end
                        local optType = opt:getType()
                        if type(v) == "boolean" then
                            opt:setValue(v)
                        elseif optType == "string" or optType == "text" then
                            opt:setValue(tostring(v))
                        else
                            opt:parse(tostring(v))
                        end
                        getSandboxOptions():set(opt:getName(), opt:getValue())
                    end)
                end
            end
        end
    end
    pcall(function() syncToJava(preset, nil) end)

    RankLog.info("applyFullPreset: preset completo aplicado ao SandboxVars e SandboxOptions.")
    return true
end

-- -- API publica -------------------------------------------------------------

function RankSandbox.check(showMissing)
    local violations, missing = RankSandbox.validate()
    local hasViolations = #violations > 0
    local hasMissing    = #missing > 0

    if not hasViolations and not (showMissing and hasMissing) then
        RankLog.info("Sandbox OK - todas as configuracoes conferem.")
        return true
    end

    RankLog.warn(string.format(
        "Sandbox invalido: %d violacao(oes), %d nao encontrada(s).",
        #violations, #missing))

    for _, v in ipairs(violations) do
        RankLog.warn(string.format("  X  %s: esperado=%s atual=%s",
            v.label, tostring(v.expected), tostring(v.got)))
    end
    if showMissing and hasMissing then
        for _, m in ipairs(missing) do
            RankLog.warn("  ?  " .. m.label .. " (nao encontrado)")
        end
    end

    return false
end
