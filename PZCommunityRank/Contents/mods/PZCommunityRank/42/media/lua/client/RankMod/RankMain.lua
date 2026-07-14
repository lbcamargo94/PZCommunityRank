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

-- Ultimo codigo gerado pelo silentUpdate - evita salvar arquivos sem mudanca de estado.
local _lastSilentCode = nil

-- Contador para disparo periodico (~5 min a 60fps).
local _periodicTick  = 0
local PERIODIC_TICKS = 18000

-- Contador de kills desde o ultimo silentUpdate por kills.
local _killsSinceSync = 0
local KILLS_PER_SYNC  = 5    -- dispara sync a cada 5 kills

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
    entry.sandbox_ok = sandboxOk

    local code = RankCode.generate(entry)
    if not RankCode.isValid(code) then
        RankLog.error("Codigo invalido apos geracao.")
        RankMain.submitted[playerIndex] = false
        return
    end

    RankFile.save(entry, code)
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
    entry.sandbox_ok = sandboxOk

    local code = RankCode.generate(entry)
    if not RankCode.isValid(code) then return end

    if code == _lastSilentCode then
        RankLog.info("silentUpdate: estado inalterado, arquivo nao regravado")
        return
    end
    _lastSilentCode = code

    RankFile.save(entry, code)
    pcall(function() RankSandboxExport.export(entry.character_name) end)
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
        local presetOk = false
        pcall(function() presetOk = checkAndDisqualify(capturedPlayer) end)
        if not presetOk then
            RankLog.warn("Periodic: violacoes corrigidas" ..
                (_sandboxViolationDetected and " - jogador DESCLASSIFICADO." or "."))
        end
    else
        RankLog.info("Periodic: ~5 min - disparando sync")
    end

    safeSilentUpdate(player, 0)
end)

RankLog.info("Mod carregado - B42.19+ | v2.2.15")
