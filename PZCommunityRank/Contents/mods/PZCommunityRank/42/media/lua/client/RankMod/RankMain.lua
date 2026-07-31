-- ============================================================
--  RankMain.lua - Ponto de entrada (B42.19+)
-- ============================================================

require "RankMod/RankLog"
require "RankMod/RankData"
require "RankMod/RankCode"
require "RankMod/RankUI"
require "RankMod/RankFile"
require "RankMod/RankSandbox"
require "RankMod/RankGameMode"
require "RankMod/RankSandboxExport"
require "RankMod/RankModCheck"

RankMain = {}
RankMain.submitted = {}

-- True durante os primeiros ~120 ticks apos OnGameStart para ignorar
-- OnPlayerDeath disparado ao carregar um save com personagem ja morto.
local _isStartingUp = false

-- True quando a sessao atual e um jogo do desafio BRASILEIRAO.
-- Persiste durante toda a sessao para que checks periodicos possam
-- chamar verifyAndCorrect() em vez de apenas check().
local _isChallengeGame = false

-- True se foi detectada alteracao no preset completo durante o desafio.
-- Uma vez ativado, permanece true pelo resto da sessao mesmo apos correcao.
-- Persiste via ModData para saves carregados (PZCommunityRank_SandboxViolation).
local _sandboxViolationDetected = false

-- True se foi detectado uso de modo debug durante o desafio Brasileirao.
-- Persiste via ModData (PZCommunityRank_DebugViolation).
local _debugViolationDetected = false

-- True se foi detectado uso de mod nao permitido durante o desafio Brasileirao.
-- Persiste via ModData (PZCommunityRank_ModViolation).
local _modViolationDetected = false

-- Lista de violacoes de mod da sessao atual (ex: {"NAO_PERMITIDO:SomeMod","AUSENTE:Other"}).
-- Disponivel apenas na sessao em que a violacao foi detectada (nao persiste).
local _modViolationList = {}

-- Ultimo codigo gerado pelo silentUpdate - evita salvar arquivos sem mudanca de estado.
local _lastSilentCode = nil

-- Contador para disparo periodico (~5 min a 60fps).
local _periodicTick  = 0
local PERIODIC_TICKS = 18000

-- Contador de kills desde o ultimo silentUpdate por kills.
local _killsSinceSync = 0
local KILLS_PER_SYNC  = 5    -- dispara sync a cada 5 kills

-- Gap de horas in-game sem o mod ativo que aciona ModViolation.
-- Threshold generoso (1h) para cobrir crashes/reinicializacoes sem falso positivo.
local GAP_HOURS_THRESHOLD = 1.0

-- Verifica todos os valores do preset completo. Se houver divergencias:
--   1. Ativa _sandboxViolationDetected (permanente na sessao).
--   2. Persiste PZCommunityRank_SandboxViolation no ModData do jogador.
--   3. Chama verifyAndCorrect() para corrigir os valores (impede vantagem continua).
-- Retorna true se o preset estava integro (sem violacoes detectadas).
local function checkAndDisqualify(player)
    local presetOk, violations = true, {}
    pcall(function()
        presetOk, violations = RankSandbox.verifyFullPreset()
    end)

    if not presetOk then
        _sandboxViolationDetected = true
        RankLog.warn(string.format(
            "DESCLASSIFICADO: %d alteracao(es) no preset do desafio detectada(s).", #violations))
        pcall(function()
            if player then
                player:getModData()["PZCommunityRank_SandboxViolation"] = true
            end
        end)
    end

    -- Corrige os valores independentemente da desclassificacao.
    pcall(function() RankSandbox.verifyAndCorrect() end)

    return presetOk
end

-- Verifica se o Companion sinalizou limpeza de violacao via arquivo.
-- Se encontrado com conteudo "clear": limpa flags de ModData e em memoria,
-- depois marca o arquivo como consumido para nao repetir na proxima sessao.
local function checkClearViolationFile(player)
    local content = nil
    pcall(function()
        local r = getFileReader("pz_rank/pz_rank_clear_violation.txt", false)
        if not r then return end
        content = r:readLine()
        r:close()
    end)
    if content ~= "clear" then return end

    pcall(function()
        local md = player:getModData()
        md["PZCommunityRank_SandboxViolation"] = nil
        md["PZCommunityRank_DebugViolation"]   = nil
        md["PZCommunityRank_ModViolation"]     = nil
        -- Reseta o timestamp de horas para que o gap nao dispare novamente na proxima carga
        md["PZCommunityRank_LastSyncHours"]    = player:getHoursSurvived()
    end)
    _sandboxViolationDetected = false
    _debugViolationDetected   = false
    _modViolationDetected     = false
    _modViolationList         = {}

    pcall(function()
        local w = getFileWriter("pz_rank/pz_rank_clear_violation.txt", false, false)
        if w then w:write("done") w:close() end
    end)
    RankLog.warn("checkClearViolationFile: violacoes limpas via sinal do Companion.")
end

-- Retorna true se o save atual e um jogo do desafio Brasileirao.
-- Usa ModData (PZCommunityRank_IsChallenge) para distinguir de sessoes genéricas.
local function isBrasileiraoGame(player)
    if not player then return false end
    local ok, md = pcall(function() return player:getModData() end)
    return ok and md and md["PZCommunityRank_IsChallenge"] == true
end

-- Verifica se o modo debug esta ativo durante um jogo Brasileirao.
-- Se ativo: desclassifica o jogador (permanente na sessao + persistido no ModData).
local function checkDebugMode(player)
    if _debugViolationDetected then return end
    local debugActive = false
    pcall(function()
        debugActive = getCore():getDebug() == true
    end)
    if not debugActive then return end

    _debugViolationDetected   = true
    _sandboxViolationDetected = true
    RankLog.warn("DESCLASSIFICADO: modo debug ativo durante o desafio Brasileirao.")
    pcall(function()
        if player then
            local md = player:getModData()
            md["PZCommunityRank_SandboxViolation"] = true
            md["PZCommunityRank_DebugViolation"]   = true
        end
    end)
end

-- Verifica mods ativos contra a whitelist gerada pelo Companion.
-- Se violacoes encontradas: persiste PZCommunityRank_ModViolation e marca _modViolationDetected.
-- Retorna true se nenhuma violacao foi detectada (ou whitelist ausente).
local function checkModViolation(player)
    if _modViolationDetected then return false end

    local violations = nil
    pcall(function() violations = RankModCheck.check() end)

    if violations == nil then return true end  -- whitelist ausente, ignora
    if #violations == 0  then return true end  -- sem violacoes

    _modViolationDetected = true
    _modViolationList     = violations
    RankLog.warn(string.format("DESCLASSIFICADO: %d mod(s) nao permitido(s) detectado(s).", #violations))
    for _, v in ipairs(violations) do RankLog.warn("  -> " .. v) end

    pcall(function()
        if player then
            player:getModData()["PZCommunityRank_ModViolation"] = true
        end
    end)
    return false
end

-- Retorna a string de motivo de desclassificacao por mod, incluindo a lista de IDs.
-- Formato: "mods:NAO_PERMITIDO:id1,AUSENTE:id2" (maximo 10 entradas para nao inflar o codigo).
-- Retorna "mods" se a lista nao estiver disponivel (violacao restaurada via ModData).
local function buildModReason()
    if #_modViolationList == 0 then return "mods" end
    local cap = {}
    for i = 1, math.min(10, #_modViolationList) do
        cap[i] = _modViolationList[i]
    end
    return "mods:" .. table.concat(cap, ",")
end

-- Coleta dados, gera codigo, salva arquivo e abre a UI de resultado.
-- O Companion (app externo) faz o sync via arquivo - nenhuma rede aqui.
local function triggerRank(player, playerIndex, isDead)
    playerIndex = playerIndex or 0

    if RankMain.submitted[playerIndex] then
        RankLog.info("triggerRank ignorado: ja submetido index=" .. playerIndex)
        return
    end
    RankMain.submitted[playerIndex] = true

    local entry = RankData.collect(player, isDead)
    if not entry then
        RankLog.error("Falha ao coletar dados.")
        RankMain.submitted[playerIndex] = false
        return
    end

    -- Checa debug antes de qualquer outra validacao — garante captura mesmo que o
    -- tick periodico nao tenha disparado ainda (ex: morte nos primeiros 5 minutos).
    pcall(function() checkDebugMode(player) end)
    pcall(function() checkModViolation(player) end)

    -- Valida sandbox: desclassificacao por preset alterado tem prioridade sobre check pontual.
    local sandboxOk = true
    if _sandboxViolationDetected then
        sandboxOk = false
        RankLog.warn("triggerRank: desclassificado por alteracao no preset - codigo marcado invalido.")
    else
        pcall(function() sandboxOk = (RankSandbox.check(false) == true) end)
        if not sandboxOk then
            RankLog.warn("triggerRank: sandbox invalido - codigo sera marcado como 'invalido'.")
        end
    end
    local anyViolation = not sandboxOk
    entry.sandbox_ok = not anyViolation
    if anyViolation then
        if _debugViolationDetected then
            entry.disqualification_reason = "debug"
        else
            entry.disqualification_reason = "sandbox"
        end
    end

    local code = RankCode.generate(entry)
    if not RankCode.isValid(code) then
        RankLog.error("Codigo invalido apos geracao.")
        RankMain.submitted[playerIndex] = false
        return
    end

    RankFile.save(entry, code)
    pcall(function() RankFile.saveHeatmap(player, entry.character_name) end)
    -- Exporta sandbox em arquivo separado - independente do PZRX2
    pcall(function() RankSandboxExport.export(entry.character_name) end)
    RankSubmitUI.open(entry, code, playerIndex)
end

RankMain.triggerRank = triggerRank

-- Salva arquivo sem abrir UI - usada em saves periodicos e ao sair do mundo.
-- Deduplicacao via codigo: se o estado nao mudou, nao gera novo arquivo.
-- IMPORTANTE: chamada sempre dentro de pcall para nao desregistrar handlers de evento.
local function silentUpdate(player, playerIndex)
    playerIndex = playerIndex or 0
    if RankMain.submitted[playerIndex] then return end  -- jogador ja morreu neste run

    local entry = RankData.collect(player, false)
    if not entry then return end

    local sandboxOk = true
    if _sandboxViolationDetected then
        sandboxOk = false
    else
        pcall(function() sandboxOk = (RankSandbox.check(false) == true) end)
    end
    local anyViolation = not sandboxOk
    entry.sandbox_ok = not anyViolation
    if anyViolation then
        if _debugViolationDetected then
            entry.disqualification_reason = "debug"
        else
            entry.disqualification_reason = "sandbox"
        end
    end

    local code = RankCode.generate(entry)
    if not RankCode.isValid(code) then return end

    if code == _lastSilentCode then
        RankLog.info("silentUpdate: estado inalterado, arquivo nao regravado")
        return
    end
    _lastSilentCode = code

    RankFile.save(entry, code)
    pcall(function() RankFile.saveHeatmap(player, entry.character_name) end)
    pcall(function() RankSandboxExport.export(entry.character_name) end)

    -- Registra hora atual para detectar gap de jogo sem o mod na proxima sessao
    if _isChallengeGame then
        pcall(function()
            player:getModData()["PZCommunityRank_LastSyncHours"] = player:getHoursSurvived()
        end)
    end

    RankLog.info("silentUpdate: arquivo sincronizado - " .. (entry.character_name or "?"))
end

-- Wrapper seguro: garante que silentUpdate nao pode crashar o handler do evento.
local function safeSilentUpdate(player, playerIndex)
    local ok, err = pcall(silentUpdate, player, playerIndex)
    if not ok then
        RankLog.error("silentUpdate falhou (protegido): " .. tostring(err))
    end
end

local function isLocalPlayer(player)
    local ok, result = pcall(function() return player:isLocalPlayer() end)
    if ok and result == true  then return true  end
    if ok and result == false then return false end
    return not (isClient and isClient())
end

-- -- Evento: morte do jogador --------------------------------
local function onPlayerDeath(player, playerIndex)
    if not player then return end
    playerIndex = playerIndex or 0
    if not isLocalPlayer(player) then return end

    -- Ignora disparos durante o carregamento de saves com personagem morto
    if _isStartingUp then
        RankLog.info("OnPlayerDeath ignorado: save carregado com personagem ja morto.")
        return
    end

    RankLog.info("OnPlayerDeath: jogador local morreu, index=" .. playerIndex)
    RankMain.submitted[playerIndex] = false

    -- Registra posição de morte para heatmap antes da tela de morte
    pcall(recordHeatmapDeath, player)

    -- Aguarda ~60 ticks para a tela de morte renderizar antes de abrir a UI.
    -- Events.OnPreUI foi removido no B42.19; usa OnTick como fallback.
    local capturedPlayer = player
    local capturedIndex  = playerIndex
    local frames = 0

    local waitTick
    waitTick = function()
        frames = frames + 1
        if frames >= 60 then
            pcall(function() Events.OnTick.Remove(waitTick) end)
            triggerRank(capturedPlayer, capturedIndex, true)
        end
    end

    local ok = pcall(function() Events.OnTick.Add(waitTick) end)
    if not ok then
        RankLog.warn("OnPlayerDeath: Events.OnTick indisponivel, chamando direto.")
        triggerRank(capturedPlayer, capturedIndex, true)
    end
end

-- -- Evento: inicio de partida -------------------------------
local function onGameStart()
    RankMain.submitted = {}
    _killsSinceSync           = 0
    _lastSilentCode           = nil
    _periodicTick             = 0
    _isChallengeGame          = false
    _sandboxViolationDetected = false
    _debugViolationDetected   = false
    _modViolationDetected     = false
    RankLog.info("OnGameStart: submissoes resetadas.")

    -- Grace period: bloqueia OnPlayerDeath nos primeiros 120 ticks para evitar
    -- falso disparo ao carregar save com personagem morto.
    _isStartingUp = true
    local graceTicks = 0
    local clearStartup
    clearStartup = function()
        graceTicks = graceTicks + 1
        if graceTicks >= 120 then
            _isStartingUp = false
            pcall(function() Events.OnTick.Remove(clearStartup) end)
            RankLog.info("OnGameStart: grace period concluido.")

            -- Com o mod ativo, qualquer sessao e tratada como desafio.
            -- _RankMod_PendingBrasileiraoSetup indica novo jogo via modo desafio:
            -- nesse caso apenas marca o save no ModData e limpa o flag global.
            _isChallengeGame = true

            if _RankMod_PendingBrasileiraoSetup then
                _RankMod_PendingBrasileiraoSetup = nil
                pcall(function()
                    local p2 = getPlayer()
                    if p2 then
                        p2:getModData()["PZCommunityRank_IsChallenge"] = true
                    end
                end)
                RankLog.info("OnGameStart: novo jogo BRASILEIRAO - marcado como desafio.")
            else
                RankLog.info("OnGameStart: mod ativo - aplicando preset do desafio.")
            end

            -- Restaura desclassificacao gravada em sessao anterior.
            pcall(function()
                local p2 = getPlayer()
                if p2 and p2:getModData()["PZCommunityRank_SandboxViolation"] then
                    _sandboxViolationDetected = true
                    RankLog.warn("OnGameStart: save com desclassificacao previa - sandbox_ok=false.")
                end
            end)
            pcall(function()
                local p2 = getPlayer()
                if p2 and p2:getModData()["PZCommunityRank_DebugViolation"] then
                    _debugViolationDetected   = true
                    _sandboxViolationDetected = true
                    RankLog.warn("OnGameStart: save com desclassificacao por debug previa.")
                end
            end)
            pcall(function()
                local p2 = getPlayer()
                if p2 and p2:getModData()["PZCommunityRank_ModViolation"] then
                    _modViolationDetected = true
                    RankLog.warn("OnGameStart: save com desclassificacao por mod nao permitido previa.")
                end
            end)

            -- Detecta gap de horas jogadas sem o mod ativo (bypass via desativacao do mod).
            -- Deve rodar ANTES de checkClearViolationFile para que o clear do moderador
            -- possa resetar o gap (LastSyncHours) e evitar re-flag na proxima carga.
            pcall(function()
                local p2 = getPlayer()
                if not p2 then return end
                local md = p2:getModData()
                local lastKnownHours = md["PZCommunityRank_LastSyncHours"]
                if not lastKnownHours then return end
                local currentHours = p2:getHoursSurvived()
                local gap = currentHours - lastKnownHours
                if gap > GAP_HOURS_THRESHOLD then
                    _modViolationDetected = true
                    md["PZCommunityRank_ModViolation"] = true
                    RankLog.warn(string.format(
                        "OnGameStart: %.1fh sem mod detectado (last=%.2f atual=%.2f) - DESCLASSIFICADO.",
                        gap, lastKnownHours, currentHours))
                end
            end)

            -- Verifica se o Companion sinalizou limpeza de violacao.
            -- Deve rodar APOS o gap check para poder sobrescrever flags e resetar LastSyncHours.
            pcall(function()
                local p2 = getPlayer()
                if p2 then checkClearViolationFile(p2) end
            end)

            -- Reaplica o preset completo (SandboxVars + Java SandboxOptions).
            RankLog.info("OnGameStart: reaplicando preset completo do desafio...")
            pcall(function() RankSandbox.applyFullPreset() end)

            -- Sync inicial apos carregamento estavel e correcao de sandbox.
            RankLog.info("OnGameStart: sync inicial")
            local ok, player = pcall(getPlayer)
            if ok and player and isLocalPlayer(player) then
                safeSilentUpdate(player, 0)
            end
        end
    end
    pcall(function() Events.OnTick.Add(clearStartup) end)
end

-- -- Comando /rank no chat -----------------------------------
local function onChatCommand(text)
    if text ~= "/rank" then return end
    local player = getPlayer()
    if not player then
        RankLog.warn("/rank: getPlayer() retornou nil.")
        return true
    end
    RankLog.info("/rank executado manualmente.")
    RankMain.submitted[0] = false
    triggerRank(player, 0, false)
    return true
end

-- -- Menu de contexto ----------------------------------------
local function onGenerateRank(worldObjects, playerIndex)
    local player = getSpecificPlayer(playerIndex)
    if not player then return end
    RankMain.submitted[playerIndex] = false
    triggerRank(player, playerIndex, false)
end

-- OnFillWorldObjectContextMenu: primeiro arg e o indice do jogador (numero inteiro),
-- nao o objeto player - o nome 'player' nas funcoes do jogo e enganoso.
local function onFillWorldContextMenu(playerIndex, context, worldObjects, test)
    if test then return end
    local player = getSpecificPlayer(playerIndex)
    if not player then return end
    context:addOption("Gerar Rank", worldObjects, onGenerateRank, playerIndex)
end

Events.OnPlayerDeath.Add(onPlayerDeath)
Events.OnGameStart.Add(onGameStart)
Events.OnFillWorldObjectContextMenu.Add(onFillWorldContextMenu)

-- ── Heatmap — acumula eventos por célula de grid ────────────────────────────
-- Célula = coordenada // 100 (cada célula cobre 100×100 blocos do jogo).
-- Os acumuladores ficam no ModData e são lidos pelo RankFile antes de enviar.

-- Obtém a célula de grid do jogador local (retorna nil se indisponível).
local function getPlayerGridCell(player)
    local xOk, x = pcall(function() return player:getX() end)
    local yOk, y = pcall(function() return player:getY() end)
    if not xOk or not yOk or not x or not y then return nil end
    return math.floor(x / 100), math.floor(y / 100)
end

-- Incrementa o contador de kills na célula do jogador.
local function incHeatmapKill(player)
    if not player then return end
    local gx, gy = getPlayerGridCell(player)
    if not gx then return end
    local mdOk, md = pcall(function() return player:getModData() end)
    if not mdOk or not md then return end
    local key = "PZCommunityRank_HeatKill_" .. gx .. "_" .. gy
    md[key] = (tonumber(md[key]) or 0) + 1
    -- Mantém índice de células para iteração no RankFile (mesmo padrão do LootedBldSet)
    local cellTag = "|" .. gx .. "_" .. gy .. "|"
    local cells   = md["PZCommunityRank_HeatKillCells"] or ""
    if not cells:find(cellTag, 1, true) then
        md["PZCommunityRank_HeatKillCells"] = cells .. cellTag
    end
end

-- Registra a posição de morte do jogador.
local function recordHeatmapDeath(player)
    if not player then return end
    local gx, gy = getPlayerGridCell(player)
    if not gx then return end
    local mdOk, md = pcall(function() return player:getModData() end)
    if not mdOk or not md then return end
    md["PZCommunityRank_HeatDeathGX"] = gx
    md["PZCommunityRank_HeatDeathGY"] = gy
end

-- Registra a posição atual como base (chamado no silentUpdate periódico).
local function recordHeatmapBase(player)
    if not player then return end
    local gx, gy = getPlayerGridCell(player)
    if not gx then return end
    local mdOk, md = pcall(function() return player:getModData() end)
    if not mdOk or not md then return end
    md["PZCommunityRank_HeatBaseGX"] = gx
    md["PZCommunityRank_HeatBaseGY"] = gy
end

-- ── Contadores PZRX3 — estatísticas estendidas ──────────────────────────────
-- Cada listener incrementa um contador no ModData do jogador local.
-- Eventos opcionais mudam entre builds do PZ. Acessar `.Add` em um evento
-- inexistente gera "attempted index: Add of non-table: null" mesmo dentro de
-- pcall, portanto validamos o objeto de evento antes de registrar o listener.

local function addOptionalEvent(eventName, callback)
    local event = Events and Events[eventName]
    if not event then
        return false
    end

    local ok, err = pcall(function()
        event.Add(callback)
    end)
    if not ok then
        RankLog.warn("Falha ao registrar " .. eventName .. ": " .. tostring(err))
        return false
    end
    return true
end

-- Registra somente o primeiro alias existente. Algumas builds expõem mais de
-- um nome para a mesma ação; registrar todos faria o contador subir em dobro.
local function addFirstAvailableEvent(eventNames, callback, featureName)
    for _, eventName in ipairs(eventNames) do
        if addOptionalEvent(eventName, callback) then
            RankLog.info(featureName .. ": usando evento " .. eventName .. ".")
            return true
        end
    end
    RankLog.warn(featureName .. ": nenhum evento compativel nesta build; usando apenas APIs/fallbacks disponiveis.")
    return false
end

-- Incrementa um contador inteiro no ModData do jogador local.
local function incModCounter(key)
    local ok, player = pcall(getPlayer)
    if not ok or not player then return end
    local mdOk, md = pcall(function() return player:getModData() end)
    if not mdOk or not md then return end
    md[key] = (tonumber(md[key]) or 0) + 1
end

-- Animais abatidos -----------------------------------------------------------
-- B42.20 nao expoe OnAnimalDead. Rastreia animais atingidos pelo jogador ate
-- morrerem (inclusive os que fogem sangrando) e integra o abate manual.
local _trackedAnimals = {}
local _countedAnimals = {}
local ANIMAL_TRACK_TICKS = 18000 -- abandona referencias antigas apos ~5 min

local function recordAnimalKill(animal)
    if not animal or _countedAnimals[animal] then return end
    _countedAnimals[animal] = true
    incModCounter("PZCommunityRank_AnimalsKilled")
    RankLog.info("Animal abatido contabilizado.")
end

local function trackAnimalHit(owner, weapon, hitObject)
    if not owner or not isLocalPlayer(owner) then return end
    if not hitObject or not instanceof(hitObject, "IsoAnimal") then return end
    if _countedAnimals[hitObject] then return end

    for _, tracked in ipairs(_trackedAnimals) do
        if tracked.animal == hitObject then
            tracked.ticks = 0
            return
        end
    end
    _trackedAnimals[#_trackedAnimals + 1] = { animal = hitObject, ticks = 0 }
end

local function updateTrackedAnimalDeaths()
    for i = #_trackedAnimals, 1, -1 do
        local tracked = _trackedAnimals[i]
        local animal = tracked.animal
        tracked.ticks = tracked.ticks + 1

        -- IsoAnimal:isDead() e isExistInTheWorld() sao APIs usadas pelos
        -- scripts vanilla B42. Se sumiu logo apos ser atingido, virou cadáver.
        if animal:isDead() or not animal:isExistInTheWorld() then
            recordAnimalKill(animal)
            table.remove(_trackedAnimals, i)
        elseif tracked.ticks >= ANIMAL_TRACK_TICKS then
            table.remove(_trackedAnimals, i)
        end
    end
end

addOptionalEvent("OnWeaponHitXp", trackAnimalHit)
addOptionalEvent("OnTick", updateTrackedAnimalDeaths)

-- Abate pela ação contextual (animais domésticos/presos).
pcall(function()
    require "TimedActions/Animals/ISKillAnimal"
    if ISKillAnimal and ISKillAnimal.complete and not ISKillAnimal._pzRankPatched then
        local originalComplete = ISKillAnimal.complete
        ISKillAnimal.complete = function(self)
            local animal = self and self.animal
            local character = self and self.character
            local completed = originalComplete(self)
            if completed and character and isLocalPlayer(character) and animal then
                recordAnimalKill(animal)
            end
            return completed
        end
        ISKillAnimal._pzRankPatched = true
        RankLog.info("Animais abatidos: fallback B42 instalado.")
    end
end)

-- Mantém compatibilidade caso uma build futura volte a expor OnAnimalDead.
addFirstAvailableEvent({ "OnAnimalDead" }, function(animal)
    local ok, player = pcall(getPlayer)
    if not ok or not player then return end
    -- Confirma que foi o jogador local que matou (lastAttacker pode ser nil)
    local attackerOk, attacker = pcall(function() return animal:getAttackedBy() end)
    if attackerOk and attacker and attacker ~= player then return end
    recordAnimalKill(animal)
end, "Animais abatidos")

-- Peixes capturados
local function recordFishCaught(player)
    if not isLocalPlayer(player) then return end
    incModCounter("PZCommunityRank_FishCaught")
    RankLog.info("Peixe capturado contabilizado.")
end

-- B42.20 conclui a pesca por ISPickupFishAction e nao expoe evento publico.
-- self.isFish distingue peixe verdadeiro de lixo retirado da agua.
pcall(function()
    require "TimedActions/Fishing/TimedActions/ISPickupFishAction"
    if ISPickupFishAction and ISPickupFishAction.complete
            and not ISPickupFishAction._pzRankPatched then
        local originalComplete = ISPickupFishAction.complete
        ISPickupFishAction.complete = function(self)
            local completed = originalComplete(self)
            if completed and self and self.isFish and not self._pzRankFishCounted then
                self._pzRankFishCounted = true
                recordFishCaught(self.character)
            end
            return completed
        end
        ISPickupFishAction._pzRankPatched = true
        RankLog.info("Peixes capturados: fallback B42 instalado.")
    end
end)

-- Mantém compatibilidade com builds futuras que voltem a expor o evento.
addFirstAvailableEvent({ "OnPlayerFishCaught", "OnFishCaught" }, function(player)
    recordFishCaught(player)
end, "Peixes capturados")

-- Vegetais colhidos (B42 usa OnPlantHarvested ou OnFarmPlantHarvested)
addFirstAvailableEvent({ "OnPlantHarvested", "OnFarmPlantHarvested" }, function(first, second)
    local player = second or first
    if not player or not isLocalPlayer(player) then return end
    incModCounter("PZCommunityRank_CropsHarvested")
end, "Vegetais colhidos")

-- Itens fabricados (craft/receita completada)
addFirstAvailableEvent({ "OnCraftRecipeCompleted", "OnCraftResult" }, function(first, second, third)
    -- As assinaturas variam por build: procura o jogador em qualquer argumento.
    local candidates = { first, second, third }
    for _, candidate in ipairs(candidates) do
        if candidate and isLocalPlayer(candidate) then
            incModCounter("PZCommunityRank_ItemsCrafted")
            return
        end
    end
end, "Itens fabricados")

-- Casas saqueadas: conta prédios únicos onde o jogador abriu um container.
-- Usa um set de IDs de building em ModData para evitar contar o mesmo prédio duas vezes.
addOptionalEvent("OnContainerUpdate", function(container)
        -- B42.20 tambem dispara OnContainerUpdate sem argumento ao atualizar
        -- portas e outros objetos do mundo.
        if not container or not instanceof(container, "ItemContainer") then return end
        local ok, player = pcall(getPlayer)
        if not ok or not player then return end
        -- Obtém o building ID do container (via IsoObject pai)
        local bldOk, bldId = pcall(function()
            local parent = container:getParent()
            local sq = parent and parent:getSquare()
            if not sq then return nil end
            local bld = sq:getBuilding()
            return bld and bld:getDef() and tostring(bld:getDef():hashCode()) or nil
        end)
        if not bldOk or not bldId then return end
        local mdOk, md = pcall(function() return player:getModData() end)
        if not mdOk or not md then return end
        local setKey = "PZCommunityRank_LootedBldSet"
        local setStr = md[setKey] or ""
        local tag = "|" .. bldId .. "|"
        if setStr:find(tag, 1, true) then return end
        -- Novo prédio — registra e incrementa
        md[setKey] = setStr .. tag
        md["PZCommunityRank_HousesLooted"] = (tonumber(md["PZCommunityRank_HousesLooted"]) or 0) + 1
end)

-- Horas sem dormir (pico): atualizado a cada tick periódico e ao adormecer.
-- Ao acordar, o pico NÃO é resetado — queremos o recorde acumulado da run.
local function updateHoursWithoutSleep()
    local ok, player = pcall(getPlayer)
    if not ok or not player then return end
    -- B42.20 nao expoe Stats:getHoursWithoutSleep() ao Lua. Deriva o valor
    -- usando o horario registrado pelo evento de sono quando ele existir.
    local current = nil
    local mdOk, md = pcall(function() return player:getModData() end)
    if mdOk and md and md["PZCommunityRank_LastSleepHours"] then
        local hoursOk, hours = pcall(function() return player:getHoursSurvived() end)
        if hoursOk and hours then
            current = math.max(0, math.floor(hours - (md["PZCommunityRank_LastSleepHours"] or hours)))
        end
    end
    if not current or current <= 0 then return end
    local mdOk2, md2 = pcall(function() return player:getModData() end)
    if not mdOk2 or not md2 then return end
    local prev = tonumber(md2["PZCommunityRank_HoursWithoutSleep"]) or 0
    if current > prev then
        md2["PZCommunityRank_HoursWithoutSleep"] = current
    end
end

-- Registra o horário de última sonecada para o cálculo de fallback
addFirstAvailableEvent({ "OnPlayerStartSleeping", "OnPlayerSleep" }, function(player)
    if not isLocalPlayer(player) then return end
    -- Guarda o pico antes de dormir
    updateHoursWithoutSleep()
    -- Marca o horário do último sono (para calcular horas awake depois)
    local ok, md = pcall(function() return player:getModData() end)
    if not ok or not md then return end
    local hOk, hours = pcall(function() return player:getHoursSurvived() end)
    if hOk and hours then
        md["PZCommunityRank_LastSleepHours"] = hours
    end
end, "Inicio do sono")

if Events.OnTryTalkInChat then
    Events.OnTryTalkInChat.Add(onChatCommand)
else
    RankLog.warn("OnTryTalkInChat indisponivel no B42. Comando /rank desabilitado.")
end

-- -- Atualizacao + validacao ao salvar / sair do mundo -----
-- B42: OnSave foi substituido por OnPostSave (dispara apos o save, inclusive ao sair para o menu).
pcall(function()
    Events.OnPostSave.Add(function()
        if _isStartingUp then return end
        RankLog.info("OnPostSave: disparando sync")
        local ok, player = pcall(getPlayer)
        if not ok or not player then return end
        if not isLocalPlayer(player) then return end
        if _isChallengeGame then
            local p2 = player
            pcall(function() checkDebugMode(p2) end)
            pcall(function() checkModViolation(p2) end)
            pcall(function() checkAndDisqualify(p2) end)
        else
            pcall(function() RankSandbox.check(false) end)
        end
        safeSilentUpdate(player, 0)
    end)
end)

-- -- Atualizacao ao subir de nivel em qualquer skill --------
-- A assinatura do evento varia entre versoes do PZ; capturamos o player direto.
pcall(function()
    Events.LevelPerk.Add(function(...)
        if _isStartingUp then return end
        RankLog.info("LevelPerk: disparando sync")
        local ok, player = pcall(getPlayer)
        if not ok or not player then return end
        if not isLocalPlayer(player) then return end
        safeSilentUpdate(player, 0)
    end)
end)

-- -- Atualizacao ao matar um zumbi (debounce: 1 sync a cada 5 kills) --
pcall(function()
    Events.OnZombieDead.Add(function(zombie)
        if _isStartingUp then return end
        _killsSinceSync = _killsSinceSync + 1

        -- Acumula kill na célula de grid do jogador (heatmap)
        local ok2, player2 = pcall(getPlayer)
        if ok2 and player2 and isLocalPlayer(player2) then
            pcall(incHeatmapKill, player2)
        end

        if _killsSinceSync < KILLS_PER_SYNC then return end
        _killsSinceSync = 0
        RankLog.info("OnZombieDead: " .. KILLS_PER_SYNC .. " kills - disparando sync")
        local ok, player = pcall(getPlayer)
        if not ok or not player then return end
        if not isLocalPlayer(player) then return end
        safeSilentUpdate(player, 0)
    end)
end)

-- -- Atualizacao a cada novo dia no jogo --------------------
pcall(function()
    Events.EveryDays.Add(function()
        if _isStartingUp then return end
        RankLog.info("EveryDays: novo dia - disparando sync")
        local ok, player = pcall(getPlayer)
        if not ok or not player then return end
        if not isLocalPlayer(player) then return end
        if _isChallengeGame then
            local p2 = player
            pcall(function() checkDebugMode(p2) end)
            pcall(function() checkModViolation(p2) end)
            pcall(function() checkAndDisqualify(p2) end)
        end
        safeSilentUpdate(player, 0)
    end)
end)

-- -- Verificacao + correcao periodica do desafio (~5 min) ---
-- Para jogos de desafio: verifica o sandbox e aplica correcoes se necessario,
-- depois sincroniza o arquivo. Garante que alteracoes externas (outros mods,
-- configuracoes manuais) sejam revertidas automaticamente.
Events.OnTick.Add(function()
    _periodicTick = _periodicTick + 1
    if _periodicTick < PERIODIC_TICKS then return end
    _periodicTick = 0

    if _isStartingUp then return end

    local ok, player = pcall(getPlayer)
    if not ok or not player then return end
    if not isLocalPlayer(player) then return end

    if _isChallengeGame then
        RankLog.info("Periodic: ~5 min - verificando preset completo do desafio")
        local capturedPlayer = player
        pcall(function() checkDebugMode(capturedPlayer) end)
        pcall(function() checkModViolation(capturedPlayer) end)
        local presetOk = false
        pcall(function() presetOk = checkAndDisqualify(capturedPlayer) end)
        if not presetOk then
            RankLog.warn("Periodic: violacoes corrigidas" ..
                (_sandboxViolationDetected and " - jogador DESCLASSIFICADO." or "."))
        end
    else
        RankLog.info("Periodic: ~5 min - disparando sync")
    end

    -- Atualiza pico de horas sem dormir a cada ciclo periódico
    pcall(updateHoursWithoutSleep)

    -- Registra posição atual como base (usada no heatmap)
    pcall(recordHeatmapBase, player)

    safeSilentUpdate(player, 0)
end)

-- -- Tela de morte: desabilita "Criar Novo Personagem" no desafio Brasileirao --
-- ISPostDeathUI.prerender seta buttonRespawn:setVisible() a cada frame.
-- Sobrescrevemos apos o original rodar e forcamos o botao invisivel quando
-- PZCommunityRank_IsChallenge = true no ModData do jogador.
-- O resultado e cacheado no objeto (self._rankIsChallengeGame) para evitar
-- lookup de ModData a cada frame — o valor nao muda durante a sessao de morte.
pcall(function()
    if not ISPostDeathUI then return end
    local _origPrerender = ISPostDeathUI.prerender
    ISPostDeathUI.prerender = function(self)
        _origPrerender(self)
        if not self.buttonRespawn then return end
        if not self.buttonRespawn:isVisible() then return end
        if self._rankIsChallengeGame == nil then
            local player = getSpecificPlayer(self.playerIndex or 0)
            self._rankIsChallengeGame = isBrasileiraoGame(player)
        end
        if self._rankIsChallengeGame then
            self.buttonRespawn:setVisible(false)
        end
    end
    RankLog.info("ISPostDeathUI: patch instalado - botao Criar Novo Personagem desabilitado no desafio.")
end)

RankLog.info("Mod carregado - B42.20 | v2.8.3")
