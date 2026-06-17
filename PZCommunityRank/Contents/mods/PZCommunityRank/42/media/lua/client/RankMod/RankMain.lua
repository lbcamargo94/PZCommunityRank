-- ============================================================
--  RankMain.lua — Ponto de entrada (B42.19+)
-- ============================================================

require "RankMod/RankLog"
require "RankMod/RankData"
require "RankMod/RankCode"
require "RankMod/RankUI"
require "RankMod/RankFile"

RankMain = {}
RankMain.submitted = {}

-- Coleta dados, gera código e abre a UI.
-- isDead: true quando chamado do evento de morte, false/nil para trigger manual.
local function triggerRank(player, playerIndex, isDead)
    playerIndex = playerIndex or 0

    if RankMain.submitted[playerIndex] then
        RankLog.info("triggerRank ignorado: ja submetido para playerIndex=" .. playerIndex)
        return
    end
    RankMain.submitted[playerIndex] = true

    RankLog.info("triggerRank iniciado para playerIndex=" .. playerIndex .. " isDead=" .. tostring(isDead))

    local entry = RankData.collect(player, isDead)
    if not entry then
        RankLog.error("Falha ao coletar dados do personagem.")
        RankMain.submitted[playerIndex] = false
        return
    end

    local code = RankCode.generate(entry)

    if not RankCode.isValid(code) then
        RankLog.error("Codigo gerado falhou na auto-validacao.")
        RankMain.submitted[playerIndex] = false
        return
    end

    RankFile.save(entry, code)
    RankSubmitUI.open(entry, code, playerIndex)
end

RankMain.triggerRank = triggerRank

-- Verifica se o player é o jogador local de forma defensiva (B42.19).
-- Em B42, isLocalPlayer() pode lançar exceção em objetos de jogador morto/transicionando.
local function isLocalPlayer(player, _playerIndex)
    local ok, result = pcall(function() return player:isLocalPlayer() end)
    if ok and result == true  then return true  end
    if ok and result == false then return false end
    -- isLocalPlayer() falhou; em single-player toda morte é do jogador local.
    -- Em multiplayer (isClient()=true) negamos para evitar falso positivo.
    return not (isClient and isClient())
end

-- ── Evento: morte do jogador ────────────────────────────────
local function onPlayerDeath(player, playerIndex)
    if not player then return end

    playerIndex = playerIndex or 0

    if not isLocalPlayer(player, playerIndex) then return end

    RankLog.info("OnPlayerDeath recebido para o jogador local, playerIndex=" .. playerIndex)

    -- Morte sempre deve abrir a janela, mesmo que o jogador tenha usado o menu
    -- de contexto antes de morrer (que teria deixado submitted=true).
    RankMain.submitted[playerIndex] = false

    -- Captura a referência do player ANTES da morte ser processada.
    -- Não re-obtém via getSpecificPlayer() pois o slot pode ser nil após a morte.
    local capturedPlayer = player
    local capturedIndex  = playerIndex
    local frames = 0
    -- Events.OnPreUI dispara no loop de render (sempre ativo, mesmo durante a tela
    -- de morte). Events.OnTick dispara no loop de lógica, que fica pausado no B42.19
    -- enquanto a death screen está ativa — por isso o counter nunca chegava a 90.
    local TARGET = 60  -- ~1s a 60fps; dá tempo da tela de morte aparecer primeiro

    local waitFrame
    waitFrame = function()
        frames = frames + 1
        if frames >= TARGET then
            Events.OnPreUI.Remove(waitFrame)
            triggerRank(capturedPlayer, capturedIndex, true)
        end
    end

    Events.OnPreUI.Add(waitFrame)
end

-- ── Resetar controle ao iniciar nova partida ────────────────
local function onGameStart()
    RankMain.submitted = {}
    RankLog.info("OnGameStart: controle de submissao resetado.")
end

-- ── Comando manual /rank no chat ────────────────────────────
local function onChatCommand(text)
    if text ~= "/rank" then return end
    local player = getPlayer()
    if not player then
        RankLog.warn("/rank chamado mas getPlayer() retornou nil.")
        return true
    end
    RankLog.info("Comando /rank executado manualmente.")
    RankMain.submitted[0] = false  -- permite gerar novamente
    triggerRank(player, 0, false)
    return true
end

-- ── Menu de contexto (botão direito no mundo) ───────────────
local function onGenerateRank(worldObjects, playerIndex)
    local player = getSpecificPlayer(playerIndex)
    if not player then return end
    RankMain.submitted[playerIndex] = false
    triggerRank(player, playerIndex, false)
end

local function onFillWorldContextMenu(playerIndex, context, worldObjects, test)
    if test then return end
    local player = getSpecificPlayer(playerIndex)
    if not player then return end
    context:addOption("Gerar Rank", worldObjects, onGenerateRank, playerIndex)
end

Events.OnPlayerDeath.Add(onPlayerDeath)
Events.OnGameStart.Add(onGameStart)
Events.OnFillWorldObjectContextMenu.Add(onFillWorldContextMenu)

-- OnTryTalkInChat foi removido no B42; registra apenas se existir
if Events.OnTryTalkInChat then
    Events.OnTryTalkInChat.Add(onChatCommand)
else
    RankLog.warn("OnTryTalkInChat indisponivel nesta versao. Comando /rank desabilitado.")
end

RankLog.info("Mod carregado — B42.19+ | v1.4.0")
