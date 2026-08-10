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
    -- Rastreia locais únicos de sono (célula de 20x20 tiles)
    pcall(function()
        local xOk, x = pcall(function() return player:getX() end)
        local yOk, y = pcall(function() return player:getY() end)
        if not xOk or not yOk then return end
        local cx = math.floor(x / 20)
        local cy = math.floor(y / 20)
        local tag = "|" .. cx .. "_" .. cy .. "|"
        local setStr = md["PZCommunityRank_SleepLocSet"] or ""
        if not setStr:find(tag, 1, true) then
            md["PZCommunityRank_SleepLocSet"] = setStr .. tag
            md["PZCommunityRank_SleepLocations"] = (tonumber(md["PZCommunityRank_SleepLocations"]) or 0) + 1
        end
    end)
end, "Inicio do sono")

-- Restaurantes Spiffo visitados — detecta pelo tipo de room (spiffo_dining / spiffoskitchen)
-- Usa set de building IDs no ModData para contar cada restaurante uma unica vez.
local SPIFFO_ROOMS = { spiffo_dining = true, spiffoskitchen = true }

local function checkSpiffoVisit()
    local ok, player = pcall(getPlayer)
    if not ok or not player then return end
    local sqOk, sq = pcall(function() return player:getCurrentSquare() end)
    if not sqOk or not sq then return end
    local roomOk, room = pcall(function() return sq:getRoom() end)
    if not roomOk or not room then return end
    local nameOk, roomName = pcall(function() return room:getName() end)
    if not nameOk or not roomName then return end
    if not SPIFFO_ROOMS[roomName:lower()] then return end

    local bldOk, bldId = pcall(function()
        local bld = sq:getBuilding()
        return bld and bld:getDef() and tostring(bld:getDef():hashCode()) or nil
    end)
    if not bldOk or not bldId then return end

    local mdOk, md = pcall(function() return player:getModData() end)
    if not mdOk or not md then return end
    local setKey = "PZCommunityRank_SpiffoSet"
    local setStr = md[setKey] or ""
    local tag = "|" .. bldId .. "|"
    if setStr:find(tag, 1, true) then return end

    md[setKey] = setStr .. tag
    md["PZCommunityRank_SpiffoVisited"] = (tonumber(md["PZCommunityRank_SpiffoVisited"]) or 0) + 1
    RankLog.info("Spiffo visitado! bldId=" .. bldId .. " total=" .. md["PZCommunityRank_SpiffoVisited"])
end

-- Árvores cortadas — patch primario; evento so registrado se nao existir o patch
local _chopTreePatched = false
pcall(function()
    require "TimedActions/ISChopTreeAction"
    if ISChopTreeAction and ISChopTreeAction.perform and not ISChopTreeAction._pzRankPatched then
        local orig = ISChopTreeAction.perform
        ISChopTreeAction.perform = function(self)
            local result = orig(self)
            if self and self.character and isLocalPlayer(self.character) then
                incModCounter("PZCommunityRank_TreesCut")
            end
            return result
        end
        ISChopTreeAction._pzRankPatched = true
        _chopTreePatched = true
        RankLog.info("Arvores cortadas: patch instalado.")
    end
end)
if not _chopTreePatched then
    addOptionalEvent("OnChopTree", function(player)
        if player and isLocalPlayer(player) then incModCounter("PZCommunityRank_TreesCut") end
    end)
end

-- Livros lidos — patch primario; evento so registrado se nao existir o patch
local _readBookPatched = false
pcall(function()
    require "TimedActions/ISReadABook"
    if ISReadABook and ISReadABook.perform and not ISReadABook._pzRankPatched then
        local orig = ISReadABook.perform
        ISReadABook.perform = function(self)
            local result = orig(self)
            if self and self.character and isLocalPlayer(self.character) then
                incModCounter("PZCommunityRank_BooksRead")
            end
            return result
        end
        ISReadABook._pzRankPatched = true
        _readBookPatched = true
        RankLog.info("Livros lidos: patch instalado.")
    end
end)
if not _readBookPatched then
    addOptionalEvent("OnReadBook", function(player)
        if player and isLocalPlayer(player) then incModCounter("PZCommunityRank_BooksRead") end
    end)
end

-- Estruturas construídas — patch primario; evento so registrado se nao existir o patch
local _buildPatched = false
pcall(function()
    require "BuildingObjects/TimedActions/ISBuildAction"
    if ISBuildAction and ISBuildAction.perform and not ISBuildAction._pzRankPatched then
        local orig = ISBuildAction.perform
        ISBuildAction.perform = function(self)
            local result = orig(self)
            if self and self.character and isLocalPlayer(self.character) then
                incModCounter("PZCommunityRank_StructuresBuilt")
                -- Verifica se é estrutura de pedra ou móvel
                pcall(function()
                    local n = ""
                    if self.buildingItem then
                        local fn = self.buildingItem:getFullName() or ""
                        local sn = self.buildingItem:getName() or ""
                        n = (fn .. " " .. sn):lower()
                    end
                    if n:find("stone", 1, true) or n:find("pedra", 1, true) or
                       n:find("rock", 1, true) or n:find("cobble", 1, true) then
                        incModCounter("PZCommunityRank_StoneStructures")
                    end
                    if n:find("chair", 1, true) or n:find("table", 1, true) or
                       n:find("sofa", 1, true)  or n:find("couch", 1, true) or
                       n:find("shelf", 1, true) or n:find("desk", 1, true) or
                       n:find("bed", 1, true)   or n:find("crib", 1, true) or
                       n:find("cabinet", 1, true) or n:find("drawer", 1, true) or
                       n:find("wardrobe", 1, true) or n:find("bookcase", 1, true) or
                       n:find("cadeira", 1, true) or n:find("mesa", 1, true) or
                       n:find("cama", 1, true)   or n:find("prateleira", 1, true) or
                       n:find("armario", 1, true) or n:find("estante", 1, true) then
                        incModCounter("PZCommunityRank_FurnitureCrafted")
                    end
                end)
            end
            return result
        end
        ISBuildAction._pzRankPatched = true
        _buildPatched = true
        RankLog.info("Estruturas construidas: patch instalado.")
    end
end)
if not _buildPatched then
    addFirstAvailableEvent({ "OnBuildComplete", "OnBuildAction" }, function(player)
        if player and isLocalPlayer(player) then incModCounter("PZCommunityRank_StructuresBuilt") end
    end, "Estruturas construidas (evento)")
end

-- Culturas plantadas — patch primario; evento so registrado se nao existir o patch
local _seedPatched = false
pcall(function()
    require "Farming/TimedActions/ISSeedActionNew"
    if ISSeedActionNew and ISSeedActionNew.perform and not ISSeedActionNew._pzRankPatched then
        local orig = ISSeedActionNew.perform
        ISSeedActionNew.perform = function(self)
            local result = orig(self)
            if self and self.character and isLocalPlayer(self.character) then
                incModCounter("PZCommunityRank_CropsPlanted")
            end
            return result
        end
        ISSeedActionNew._pzRankPatched = true
        _seedPatched = true
        RankLog.info("Culturas plantadas: patch instalado.")
    end
end)
if not _seedPatched then
    addFirstAvailableEvent({ "OnPlantSeeds", "OnPlant" }, function(player)
        if player and isLocalPlayer(player) then incModCounter("PZCommunityRank_CropsPlanted") end
    end, "Culturas plantadas (evento)")
end

-- Ovos coletados (B42: coleta manual de ninhos)
local _eggPatched = false
pcall(function()
    require "TimedActions/Animals/ISCollectEgg"
    if ISCollectEgg and ISCollectEgg.perform and not ISCollectEgg._pzRankPatched then
        local origEgg = ISCollectEgg.perform
        ISCollectEgg.perform = function(self)
            local result = origEgg(self)
            if result ~= false and self and self.character and isLocalPlayer(self.character) then
                incModCounter("PZCommunityRank_EggsCollected")
            end
            return result
        end
        ISCollectEgg._pzRankPatched = true
        _eggPatched = true
        RankLog.info("Ovos coletados: patch instalado.")
    end
end)
if not _eggPatched then
    addFirstAvailableEvent({ "OnChickenLayEgg", "OnPlayerCollectEgg", "OnCollectEgg" }, function(player)
        if player and isLocalPlayer(player) then incModCounter("PZCommunityRank_EggsCollected") end
    end, "Ovos coletados (evento)")
end

-- Leite produzido (B42: ordenha manual de animais)
local _milkPatched = false
pcall(function()
    require "TimedActions/Animals/ISMilkAnimal"
    if ISMilkAnimal and ISMilkAnimal.perform and not ISMilkAnimal._pzRankPatched then
        local origMilk = ISMilkAnimal.perform
        ISMilkAnimal.perform = function(self)
            local result = origMilk(self)
            if result ~= false and self and self.character and isLocalPlayer(self.character) then
                incModCounter("PZCommunityRank_MilkProduced")
            end
            return result
        end
        ISMilkAnimal._pzRankPatched = true
        _milkPatched = true
        RankLog.info("Leite produzido: patch instalado.")
    end
end)
if not _milkPatched then
    addFirstAvailableEvent({ "OnPlayerMilkAnimal", "OnMilkAnimal", "OnAnimalMilked" }, function(player)
        if player and isLocalPlayer(player) then incModCounter("PZCommunityRank_MilkProduced") end
    end, "Leite produzido (evento)")
end

-- Categorização de receitas: ceramica, armas forjadas, refeicoes, materiais
-- Registra um handler extra em OnCraftRecipeCompleted (pode coexistir com o handler de ItemsCrafted).
addFirstAvailableEvent({ "OnCraftRecipeCompleted", "OnCraftResult" }, function(first, second, third)
    local player = nil
    for _, c in ipairs({ first, second, third }) do
        if c then
            local ok, isLocal = pcall(isLocalPlayer, c)
            if ok and isLocal then player = c; break end
        end
    end
    if not player then return end

    -- Tenta extrair o nome e categoria da receita de qualquer argumento não-player
    local recipeName = ""
    local recipeCategory = ""
    for _, c in ipairs({ first, second, third }) do
        if c and c ~= player then
            local ok, name = pcall(function()
                if type(c.getName) == "function" then return tostring(c:getName()) end
                if type(c.getDisplayName) == "function" then return tostring(c:getDisplayName()) end
                return ""
            end)
            if ok and name and #name > 2 then recipeName = name:lower(); break end
        end
    end
    for _, c in ipairs({ first, second, third }) do
        if c and c ~= player then
            local ok, cat = pcall(function()
                if type(c.getCategory) == "function" then return tostring(c:getCategory()) end
                return ""
            end)
            if ok and cat and #cat > 2 then recipeCategory = cat:lower(); break end
        end
    end
    local recipeKey = recipeCategory .. " " .. recipeName

    if recipeKey:find("ceramic", 1, true) or recipeKey:find("clay", 1, true) or
       recipeKey:find("argila", 1, true) or recipeKey:find("cerami", 1, true) or
       recipeKey:find("pottery", 1, true) or recipeKey:find("bowl", 1, true) or
       recipeKey:find("jug", 1, true) then
        incModCounter("PZCommunityRank_CeramicItems")
    end

    if recipeKey:find("forg", 1, true) or recipeKey:find("smelt", 1, true) or
       recipeKey:find("anvil", 1, true) or recipeKey:find("forja", 1, true) or
       recipeKey:find("smit", 1, true) or recipeKey:find("blacksmith", 1, true) then
        incModCounter("PZCommunityRank_ForgedWeapons")
    end

    if recipeKey:find("cook", 1, true) or recipeKey:find("bake", 1, true) or
       recipeKey:find("grill", 1, true) or recipeKey:find("cozi", 1, true) or
       recipeKey:find("assar", 1, true) or recipeKey:find("stew", 1, true) or
       recipeKey:find("soup", 1, true)  or recipeKey:find("fry", 1, true) or
       recipeKey:find("roast", 1, true) or recipeKey:find("simmer", 1, true) then
        incModCounter("PZCommunityRank_MealsCooked")
    end

    if recipeKey:find("plank", 1, true) or recipeKey:find("lumber", 1, true) or
       recipeKey:find("board", 1, true) or recipeKey:find("taboa", 1, true) or
       recipeKey:find("log ", 1, true) then
        incModCounter("PZCommunityRank_MaterialsCrafted")
    end

    -- Roupas fabricadas: instanceof Clothing nos itens resultantes
    local clothesFound = false
    for _, c in ipairs({ first, second, third }) do
        if c and c ~= player then
            local okSz, sz = pcall(function() return c.size and c:size() or -1 end)
            if okSz and type(sz) == "number" and sz >= 0 then
                for i = 0, sz - 1 do
                    local okIt, item = pcall(function() return c:get(i) end)
                    if okIt and item then
                        local okC, isC = pcall(function() return instanceof(item, "Clothing") end)
                        if okC and isC then clothesFound = true; break end
                    end
                end
            end
        end
        if clothesFound then break end
    end
    if not clothesFound then
        if recipeKey:find("sew", 1, true) or recipeKey:find("tailor", 1, true) or
           recipeKey:find("costur", 1, true) or recipeKey:find("clothing", 1, true) or
           recipeKey:find("shirt", 1, true) or recipeKey:find("pants", 1, true) or
           recipeKey:find("jacket", 1, true) or recipeKey:find("vest", 1, true) or
           recipeKey:find("camiseta", 1, true) or recipeKey:find("calca", 1, true) or
           recipeKey:find("jaqueta", 1, true) or recipeKey:find("blusa", 1, true) then
            clothesFound = true
        end
    end
    if clothesFound then incModCounter("PZCommunityRank_ClothesCrafted") end

    -- Queijo produzido
    if recipeKey:find("cheese", 1, true) or recipeKey:find("queijo", 1, true) then
        incModCounter("PZCommunityRank_CheeseProduced")
    end

    -- Estacoes de craft usadas: track categorias unicas
    pcall(function()
        local ok2, player2 = pcall(getPlayer)
        if not ok2 or not player2 then return end
        local mdOk, md = pcall(function() return player2:getModData() end)
        if not mdOk or not md then return end
        local setKey = "PZCommunityRank_StationsSet"
        local setStr = md[setKey] or ""
        local changed = false
        local function addSt(tag)
            local t = "|" .. tag .. "|"
            if setStr:find(t, 1, true) then return end
            setStr = setStr .. t; changed = true
        end
        if recipeKey:find("wood", 1, true) or recipeKey:find("carpent", 1, true) or
           recipeKey:find("madei", 1, true) or recipeKey:find("marcen", 1, true) then addSt("woodwork") end
        if recipeKey:find("weld", 1, true) or recipeKey:find("metalwork", 1, true) or
           recipeKey:find("sold", 1, true) or recipeKey:find("metal ", 1, true) then addSt("metalwork") end
        if recipeKey:find("forg", 1, true) or recipeKey:find("anvil", 1, true) or
           recipeKey:find("blacksmith", 1, true) or recipeKey:find("ferr", 1, true) then addSt("blacksmith") end
        if recipeKey:find("mason", 1, true) or recipeKey:find("alvenar", 1, true) or
           recipeKey:find("mortar", 1, true) or recipeKey:find("brick", 1, true) then addSt("masonry") end
        if recipeKey:find("potter", 1, true) or recipeKey:find("ceramic", 1, true) or
           recipeKey:find("clay", 1, true) or recipeKey:find("argila", 1, true) then addSt("pottery") end
        if recipeKey:find("glass", 1, true) or recipeKey:find("vidro", 1, true) or
           recipeKey:find("kiln", 1, true) then addSt("glassmaking") end
        if recipeKey:find("sew", 1, true) or recipeKey:find("tailor", 1, true) or
           recipeKey:find("costur", 1, true) or recipeKey:find("clothing", 1, true) then addSt("tailoring") end
        if recipeKey:find("cook", 1, true) or recipeKey:find("bake", 1, true) or
           recipeKey:find("grill", 1, true) or recipeKey:find("cozi", 1, true) then addSt("cooking") end
        if changed then
            md[setKey] = setStr
            local cnt = 0
            setStr:gsub("|[^|]+|", function() cnt = cnt + 1 end)
            md["PZCommunityRank_StationsUsed"] = cnt
        end
    end)

    -- Armas fabricadas: tenta instanceof HandWeapon nos itens resultantes (arg que tem size()),
    -- com fallback por palavras-chave no nome da receita.
    local weaponFound = false
    for _, c in ipairs({ first, second, third }) do
        if c and c ~= player then
            local okSz, sz = pcall(function() return c.size and c:size() or -1 end)
            if okSz and type(sz) == "number" and sz >= 0 then
                for i = 0, sz - 1 do
                    local okIt, item = pcall(function() return c:get(i) end)
                    if okIt and item then
                        local okW, isW = pcall(function() return instanceof(item, "HandWeapon") end)
                        if okW and isW then weaponFound = true; break end
                    end
                end
            end
        end
        if weaponFound then break end
    end
    if not weaponFound then
        if recipeName:find("spear", 1, true) or recipeName:find("lan%p?a", 1, false) or
           recipeName:find("lance", 1, true) or recipeName:find("knife", 1, true) or
           recipeName:find("faca",  1, true) or recipeName:find("blade", 1, true) or
           recipeName:find("sword", 1, true) or recipeName:find("espada",1, true) or
           recipeName:find("arrow", 1, true) or recipeName:find("flecha",1, true) or
           recipeName:find("bow",   1, true) or recipeName:find("arco",  1, true) or
           recipeName:find("club",  1, true) or recipeName:find("clava", 1, true) or
           recipeName:find("pike",  1, true) or recipeName:find("shiv",  1, true) or
           recipeName:find("shank", 1, true) or recipeName:find("mace",  1, true) then
            weaponFound = true
        end
    end
    if weaponFound then incModCounter("PZCommunityRank_WeaponsCrafted") end
end, "Itens por categoria")

-- Quilômetros dirigidos (tracking de posicao do veiculo em OnTick)
local _lastVehiclePos = nil
local _pendingKm = 0.0
local _kmSaveTick = 0
local KM_SAVE_INTERVAL = 600  -- salva no ModData a cada ~10s (60fps)
local KM_TILES_PER_KM  = 500  -- ~1 tile = 2m; 500 tiles ≈ 1 km

local function updateVehicleDistance()
    local ok, player = pcall(getPlayer)
    if not ok or not player then _lastVehiclePos = nil; return end
    local vehOk, vehicle = pcall(function() return player:getVehicle() end)
    if not vehOk or not vehicle then _lastVehiclePos = nil; return end

    local px, py = 0, 0
    local posOk = pcall(function() px = vehicle:getX(); py = vehicle:getY() end)
    if not posOk then return end

    if _lastVehiclePos then
        local dx = px - _lastVehiclePos.x
        local dy = py - _lastVehiclePos.y
        _pendingKm = _pendingKm + math.sqrt(dx*dx + dy*dy) / KM_TILES_PER_KM
    end
    _lastVehiclePos = { x = px, y = py }

    _kmSaveTick = _kmSaveTick + 1
    if _kmSaveTick >= KM_SAVE_INTERVAL then
        _kmSaveTick = 0
        local mdOk, md = pcall(function() return player:getModData() end)
        if mdOk and md and _pendingKm >= 0.5 then
            md["PZCommunityRank_KmDriven"] = (tonumber(md["PZCommunityRank_KmDriven"]) or 0) + math.floor(_pendingKm)
            _pendingKm = 0.0
        end
    end
end
addOptionalEvent("OnTick", updateVehicleDistance)

-- Cidades e bases militares visitadas (verificacao periodica de zonas do tile atual)
local _visitedCityZones = {}
local _visitedMilZones  = {}

local function checkZoneVisit()
    local ok, player = pcall(getPlayer)
    if not ok or not player then return end
    local sqOk, sq = pcall(function() return player:getCurrentSquare() end)
    if not sqOk or not sq then return end
    local mdOk, md = pcall(function() return player:getModData() end)
    if not mdOk or not md then return end

    -- Tenta via getZoneList() — método pode não existir em todas as builds B42
    if sq.getZoneList ~= nil then
    pcall(function()
        local zl = sq:getZoneList()
        if not zl then return end
        local size = 0
        pcall(function() size = zl:size() end)
        for i = 0, size - 1 do
            local zone = nil
            pcall(function() zone = zl:get(i) end)
            if not zone then break end

            local zoneName, zoneType = "", ""
            pcall(function() zoneName = tostring(zone:getName() or "") end)
            pcall(function() zoneType = tostring(zone:getType() or "") end)
            local nl = zoneName:lower()
            local tl = zoneType:lower()

            -- Cidades (zona de tipo Town/City ou nome de cidade conhecida)
            if not _visitedCityZones[zoneName] then
                if tl:find("town", 1, true) or tl:find("city", 1, true) or
                   nl:find("muldraugh", 1, true) or nl:find("rosewood", 1, true) or
                   nl:find("west point", 1, true) or nl:find("riverside", 1, true) or
                   nl:find("louisville", 1, true) or nl:find("march ridge", 1, true) or
                   nl:find("ekron", 1, true) or nl:find("doe valley", 1, true) then
                    _visitedCityZones[zoneName] = true
                    md["PZCommunityRank_CitiesVisited"] = (tonumber(md["PZCommunityRank_CitiesVisited"]) or 0) + 1
                    RankLog.info("Cidade visitada: " .. zoneName)
                end
            end

            -- Base militar
            if not _visitedMilZones[zoneName] then
                if tl:find("mil", 1, true) or nl:find("mil", 1, true) or
                   nl:find("fort", 1, true) or nl:find("base", 1, true) then
                    _visitedMilZones[zoneName] = true
                    md["PZCommunityRank_MilitaryVisited"] = (tonumber(md["PZCommunityRank_MilitaryVisited"]) or 0) + 1
                    RankLog.info("Base militar visitada: " .. zoneName)
                end
            end
        end
    end)
    end -- sq.getZoneList ~= nil

    -- Fallback: verifica nome do room atual para bases militares
    pcall(function()
        local room = sq:getRoom()
        if not room then return end
        local roomName = tostring(room:getName() or ""):lower()
        local roomKey = "room_" .. roomName
        if not _visitedMilZones[roomKey] then
            if roomName:find("armory", 1, true) or roomName:find("barracks", 1, true) or
               roomName:find("guardpost", 1, true) or roomName:find("military", 1, true) then
                _visitedMilZones[roomKey] = true
                md["PZCommunityRank_MilitaryVisited"] = (tonumber(md["PZCommunityRank_MilitaryVisited"]) or 0) + 1
                RankLog.info("Base militar visitada (room): " .. roomName)
            end
        end
    end)
end

-- Poroes explorados: conta edificios unicos visitados no subsolo (z < 0)
-- DECLARADO ANTES do OnTick que o chama para evitar forward-reference nil
local function checkBasementVisit()
    local ok, player = pcall(getPlayer)
    if not ok or not player then return end
    local zOk, z = pcall(function() return player:getZ() end)
    if not zOk or not z or z >= 0 then return end
    local sqOk, sq = pcall(function() return player:getCurrentSquare() end)
    if not sqOk or not sq then return end
    local bldOk, bldId = pcall(function()
        local bld = sq:getBuilding()
        return bld and bld:getDef() and tostring(bld:getDef():hashCode()) or nil
    end)
    if not bldOk or not bldId then return end
    local mdOk, md = pcall(function() return player:getModData() end)
    if not mdOk or not md then return end
    local tag = "|" .. bldId .. "|"
    local setStr = md["PZCommunityRank_BasementSet"] or ""
    if setStr:find(tag, 1, true) then return end
    md["PZCommunityRank_BasementSet"] = setStr .. tag
    md["PZCommunityRank_BasementsExplored"] = (tonumber(md["PZCommunityRank_BasementsExplored"]) or 0) + 1
    RankLog.info("Porao explorado: bldId=" .. bldId)
end

local _zoneCheckTick = 0
local ZONE_CHECK_TICKS = 1800  -- ~30s a 60fps
addOptionalEvent("OnTick", function()
    _zoneCheckTick = _zoneCheckTick + 1
    if _zoneCheckTick >= ZONE_CHECK_TICKS then
        _zoneCheckTick = 0
        if not _isStartingUp then
            pcall(checkZoneVisit)
            pcall(checkBasementVisit)
        end
    end
end)

-- Água coletada (torneiras, pocos, chuva)
addFirstAvailableEvent({ "OnPlayerFillContainer", "OnFillLiquidContainer", "OnFillContainer" }, function(first, second)
    local player = second or first
    if not player or not isLocalPlayer(player) then return end
    incModCounter("PZCommunityRank_WaterCollected")
end, "Agua coletada")

-- Rastros de animais rastreados
addFirstAvailableEvent({ "OnPlayerTrackAnimal", "OnAnimalTrackFound", "OnTrackAnimal" }, function(player)
    if not player or not isLocalPlayer(player) then return end
    incModCounter("PZCommunityRank_AnimalTracks")
end, "Rastros de animais")

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

-- ── Novos contadores PZRX8 ──────────────────────────────────────────────────

-- Portas abertas
local _doorPatched = false
pcall(function()
    require "TimedActions/ISOpenDoorAction"
    if ISOpenDoorAction and ISOpenDoorAction.perform and not ISOpenDoorAction._pzRankPatched then
        local orig = ISOpenDoorAction.perform
        ISOpenDoorAction.perform = function(self)
            local result = orig(self)
            if self and self.character and isLocalPlayer(self.character) then
                incModCounter("PZCommunityRank_DoorsOpened")
            end
            return result
        end
        ISOpenDoorAction._pzRankPatched = true
        _doorPatched = true
        RankLog.info("Portas abertas: patch instalado.")
    end
end)
if not _doorPatched then
    addFirstAvailableEvent({ "OnDoorOpen", "OnOpenDoor" }, function(player)
        if player and isLocalPlayer(player) then incModCounter("PZCommunityRank_DoorsOpened") end
    end, "Portas abertas (evento)")
end

-- Dias sem enlatados: patch em ISEatFoodAction, flag persistida no ModData
local _eatFoodPatched = false
pcall(function()
    require "TimedActions/ISEatFoodAction"
    if ISEatFoodAction and ISEatFoodAction.perform and not ISEatFoodAction._pzRankPatched then
        local orig = ISEatFoodAction.perform
        ISEatFoodAction.perform = function(self)
            local result = orig(self)
            if result ~= false and self and self.character and isLocalPlayer(self.character) then
                pcall(function()
                    local item = self.item
                    if not item then return end
                    -- getEatType() retorna "Can"/"Candrink" para enlatados (API vanilla)
                    local isCanned = false
                    local eatOk, eatType = pcall(function() return tostring(item:getEatType() or "") end)
                    if eatOk and (eatType == "Can" or eatType == "Candrink") then
                        isCanned = true
                    end
                    -- fallback por nome caso getEatType nao esteja disponivel
                    if not isCanned then
                        local typeName = tostring(item:getType() or ""):lower()
                        local dispName = tostring(item:getDisplayName() or ""):lower()
                        if typeName:find("can", 1, true) or typeName:find("tin", 1, true) or
                           dispName:find("canned", 1, true) or dispName:find("enlatad", 1, true) then
                            isCanned = true
                        end
                    end
                    if isCanned then
                        local mdOk, md = pcall(function() return self.character:getModData() end)
                        if mdOk and md then md["PZCommunityRank_AteCannedToday"] = 1 end
                    end
                end)
            end
            return result
        end
        ISEatFoodAction._pzRankPatched = true
        _eatFoodPatched = true
        RankLog.info("Dias sem enlatados: patch instalado.")
    end
end)

-- Especies de animais criados/alimentados
local _animalSpeciesPatched = false
pcall(function()
    require "TimedActions/Animals/ISFeedAnimal"
    if ISFeedAnimal and ISFeedAnimal.perform and not ISFeedAnimal._pzRankPatched then
        local orig = ISFeedAnimal.perform
        ISFeedAnimal.perform = function(self)
            local result = orig(self)
            if result ~= false and self and self.character and isLocalPlayer(self.character) and self.animal then
                pcall(function()
                    local animal = self.animal
                    local speciesOk, species = pcall(function()
                        if type(animal.getSpecies) == "function" then
                            return tostring(animal:getSpecies())
                        end
                        if type(animal.getType) == "function" then
                            return tostring(animal:getType())
                        end
                        return nil
                    end)
                    if not speciesOk or not species or species == "" or species == "nil" then return end
                    local mdOk, md = pcall(function() return self.character:getModData() end)
                    if not mdOk or not md then return end
                    local tag = "|" .. species:lower() .. "|"
                    local setStr = md["PZCommunityRank_AnimalSpeciesSet"] or ""
                    if not setStr:find(tag, 1, true) then
                        md["PZCommunityRank_AnimalSpeciesSet"] = setStr .. tag
                        md["PZCommunityRank_AnimalSpecies"] = (tonumber(md["PZCommunityRank_AnimalSpecies"]) or 0) + 1
                        RankLog.info("Nova especie de animal: " .. species)
                    end
                end)
            end
            return result
        end
        ISFeedAnimal._pzRankPatched = true
        _animalSpeciesPatched = true
        RankLog.info("Especies de animais: patch instalado.")
    end
end)
if not _animalSpeciesPatched then
    addFirstAvailableEvent({ "OnAnimalFed", "OnFeedAnimal" }, function(animal, player)
        if not player or not isLocalPlayer(player) then return end
        if not animal then return end
        pcall(function()
            local speciesOk, species = pcall(function()
                if type(animal.getSpecies) == "function" then return tostring(animal:getSpecies()) end
                return tostring(animal:getType())
            end)
            if not speciesOk or not species or species == "" then return end
            local mdOk, md = pcall(function() return player:getModData() end)
            if not mdOk or not md then return end
            local tag = "|" .. species:lower() .. "|"
            local setStr = md["PZCommunityRank_AnimalSpeciesSet"] or ""
            if not setStr:find(tag, 1, true) then
                md["PZCommunityRank_AnimalSpeciesSet"] = setStr .. tag
                md["PZCommunityRank_AnimalSpecies"] = (tonumber(md["PZCommunityRank_AnimalSpecies"]) or 0) + 1
            end
        end)
    end, "Especies de animais (evento)")
end

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
        -- Atualiza contador de dias sem enlatados
        pcall(function()
            local mdOk, md = pcall(function() return player:getModData() end)
            if not mdOk or not md then return end
            if md["PZCommunityRank_AteCannedToday"] == 1 then
                md["PZCommunityRank_DaysNoCanned"] = 0
            else
                md["PZCommunityRank_DaysNoCanned"] = (tonumber(md["PZCommunityRank_DaysNoCanned"]) or 0) + 1
            end
            md["PZCommunityRank_AteCannedToday"] = 0
        end)
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
local _spiffoCheckTick = 0
local SPIFFO_CHECK_TICKS = 300  -- ~5 segundos a 60fps

Events.OnTick.Add(function()
    -- Verificacao rapida de visita a Spiffo (a cada ~5s, independente do ciclo principal)
    _spiffoCheckTick = _spiffoCheckTick + 1
    if _spiffoCheckTick >= SPIFFO_CHECK_TICKS then
        _spiffoCheckTick = 0
        if not _isStartingUp then
            pcall(checkSpiffoVisit)
        end
    end

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

RankLog.info("Mod carregado - B42.20 | v2.13.2")
