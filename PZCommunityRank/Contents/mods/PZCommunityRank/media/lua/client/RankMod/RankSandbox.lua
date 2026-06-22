-- ============================================================
--  RankSandbox.lua — Validador de configurações do Sandbox (B42.19+)
--
--  Compara o SandboxVars ativo com as regras do desafio oficial.
--  Abre um ISPanel de alerta quando algo diverge.
--  Não bloqueia o jogo — apenas avisa.
--
--  Enums reais do B42.19 (extraídos do preset "Brasileirão PZ.cfg"):
--
--  ZombieLore.Speed:        1=Corredores  2=Normal  3=Lento  4=Aleatório
--  ZombieLore.Strength:     1=Super-humano  2=Normal  3=Fraco  4=Aleatório
--  ZombieLore.Toughness:    1=Resistente    2=Normal  3=Frágil 4=Aleatório
--  ZombieLore.Hearing:      1=Alta  2=Normal  3=Baixa  4=Aleat.  5=Aleat.(Normal/Ruim)
--  ZombieLore.Sight:        1=Águia 2=Normal  3=Ruim   4=Aleat.  5=Aleat.(Normal/Ruim)
--  ZombieLore.Memory:       1=Longo 2=Normal  3=Curto  4=Nenhum  5=Aleat.
--  ZombieLore.Cognition:    1=Avançado(abre portas) 2=Normal 3=Básico 4=Aleat.
--  ZombieLore.DisableFakeDead: 1=Parcial 2=Total(incl.mortos pelo jogador) 3=Nenhum
--  ZombieLore.CrawlUnderVehicle: 1=SóRastejantes 2=ExtRaro..7=Sempre
--  WaterShut / ElecShut:    1=Instantâneo 2=0-30 Dias ...
--  AlarmDecay:              1=Instantâneo .. 6=0-5 Anos
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

-- ── Regras do Desafio Oficial ──────────────────────────────────────────────
--
--  key:      caminho no SandboxVars (pontos indicam sub-tabela)
--  expected: valor esperado (número, booleano ou string)
--  tol:      tolerância para floats (padrão 0.01)

local RULES = {
    -- [ ZUMBIS — População ]
    { key = "ZombieConfig.PopulationMultiplier",       expected = 4.0, label = "Pop. Multiplicador",         tol = 0.05 },
    { key = "ZombieConfig.PopulationStartMultiplier",  expected = 2.0, label = "Pop. Inicial",                tol = 0.05 },
    { key = "ZombieConfig.PopulationPeakMultiplier",   expected = 2.0, label = "Pop. Pico",                   tol = 0.05 },
    { key = "ZombieConfig.PopulationPeakDay",          expected = 1,   label = "Dia do Pico" },

    -- [ ZUMBIS — Comportamento ]
    -- Speed 4=Aleatório; SprinterPercentage=0 garante "nenhum corredor"
    { key = "ZombieLore.Speed",                        expected = 4,    label = "Velocidade (Aleatório=4)" },
    { key = "ZombieLore.SprinterPercentage",           expected = 0,    label = "% Corredores (0)" },
    { key = "ZombieLore.Strength",                     expected = 1,    label = "Força (Super-humano=1)" },
    { key = "ZombieLore.Toughness",                    expected = 1,    label = "Resistência (Resistente=1)" },
    { key = "ZombieLore.Hearing",                      expected = 1,    label = "Audição (Alta=1)" },
    { key = "ZombieLore.Sight",                        expected = 1,    label = "Visão (Águia=1)" },
    { key = "ZombieLore.Memory",                       expected = 1,    label = "Memória (Longa=1)" },
    { key = "ZombieLore.Cognition",                    expected = 1,    label = "Percepção/Portas (Avançado=1)" },
    { key = "ZombieConfig.FollowSoundDistance",        expected = 100,  label = "Raio de Audição (100)" },
    { key = "ZombieLore.DisableFakeDead",              expected = 2,    label = "Fake Dead Total (2)" },
    { key = "ZombieLore.ZombiesCrawlersDragDown",      expected = true, label = "Rastejadores Derrubam" },
    { key = "ZombieConfig.RallyGroupSize",             expected = 1,    label = "Tamanho da Horda (1)" },

    -- [ LOOT ] — amostra representativa de categorias
    { key = "FoodLootNew",      expected = 0.04, label = "Loot Comida (0.04)",   tol = 0.01 },
    { key = "WeaponLootNew",    expected = 0.04, label = "Loot Armas (0.04)",    tol = 0.01 },
    { key = "MedicalLootNew",   expected = 0.04, label = "Loot Médico (0.04)",   tol = 0.01 },
    { key = "AmmoLootNew",      expected = 0.04, label = "Loot Munição (0.04)",  tol = 0.01 },
    { key = "GeneratorSpawning",expected = 1,    label = "Geradores (Ext.Raro=1)" },

    -- [ MUNDO ]
    { key = "WaterShut", expected = 1, label = "Água Instantânea (1)" },
    { key = "ElecShut",  expected = 1, label = "Eletric. Instantânea (1)" },
    { key = "Alarm",     expected = 6, label = "Alarmes Casas (Muito Freq.=6)" },

    -- [ NATUREZA ]
    { key = "NightDarkness",  expected = 2, label = "Escuridão Noite (Escuro=2)" },
    { key = "Temperature",    expected = 2, label = "Temperatura (Frio=2)" },
    { key = "Rain",           expected = 2, label = "Chuva (Seco=2)" },
    { key = "FishAbundance",  expected = 1, label = "Pesca (Muito Ruim=1)" },
    { key = "NatureAbundance",expected = 1, label = "Natureza (Muito Ruim=1)" },

    -- [ AMBIENTE ]
    { key = "MetaEvent",        expected = 3,     label = "Eventos Aleatórios (Freq.=3)" },
    { key = "Map.AllowMiniMap", expected = false,  label = "Mini-Mapa Desativado" },

    -- [ PERSONAGEM ]
    { key = "MultiplierConfig.Global", expected = 0.8, label = "Mult. XP Global (0.8)", tol = 0.05 },

    -- [ VEÍCULOS ]
    { key = "ChanceHasGas",        expected = 1, label = "Gasolina (Baixo=1)" },
    { key = "InitialGas",          expected = 1, label = "Gasolina Inicial (M.Baixo=1)" },
    { key = "LockedCar",           expected = 6, label = "Veículos Trancados (M.Freq.=6)" },
    { key = "CarGeneralCondition", expected = 1, label = "Cond. Veículos (M.Baixo=1)" },

    -- [ ANIMAIS ]
    { key = "AnimalRanchChance", expected = 2, label = "Animais (Ext.Raro=2)" },
}

-- ── Leitura de sub-tabelas via path com pontos ─────────────────────────────
--  "ZombieLore.Speed"  →  SandboxVars.ZombieLore.Speed
--  "Map.AllowMiniMap"  →  SandboxVars.Map.AllowMiniMap
--  "Temperature"       →  SandboxVars.Temperature

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

-- ── Validação principal ────────────────────────────────────────────────────

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
                "SANDBOX INVALIDO — %s: esperado=%s atual=%s",
                rule.label, tostring(rule.expected), tostring(actual)
            ))
        else
            RankLog.info("OK — " .. rule.label .. " = " .. tostring(actual))
        end
    end

    return violations, missing
end

-- ── API pública ────────────────────────────────────────────────────────────

function RankSandbox.check(showMissing)
    local violations, missing = RankSandbox.validate()
    local hasViolations = #violations > 0
    local hasMissing    = #missing > 0

    if not hasViolations and not (showMissing and hasMissing) then
        RankLog.info("Sandbox OK — todas as configuracoes conferem.")
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
