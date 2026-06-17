-- ============================================================
--  RankMain.lua — Ponto de entrada (B42.19+)
-- ============================================================

require "RankMod/RankLog"
require "RankMod/RankData"
require "RankMod/RankCode"
require "RankMod/RankUI"

RankMain = {}
RankMain.submitted = {}

-- Coleta dados, gera código e abre a UI
local function triggerRank(player, playerIndex)
    playerIndex = playerIndex or 0

    if RankMain.submitted[playerIndex] then
        RankLog.info("triggerRank ignorado: ja submetido para playerIndex=" .. playerIndex)
        return
    end
    RankMain.submitted[playerIndex] = true

    RankLog.info("triggerRank iniciado para playerIndex=" .. playerIndex)

    local entry = RankData.collect(player)
    if not entry then
        RankLog.error("Falha ao coletar dados do personagem.")
        return
    end

    local code = RankCode.generate(entry)

    if not RankCode.isValid(code) then
        RankLog.error("Codigo gerado falhou na auto-validacao.")
        RankMain.submitted[playerIndex] = false
        return
    end

    RankSubmitUI.open(entry, code, playerIndex)
end

RankMain.triggerRank = triggerRank

-- ── Evento: morte do jogador ────────────────────────────────
local function onPlayerDeath(player, playerIndex)
    if not player or not player:isLocalPlayer() then return end

    playerIndex = playerIndex or 0
    RankLog.info("OnPlayerDeath recebido para o jogador local, playerIndex=" .. playerIndex)

    -- Delay de ~1.5s para a tela de morte do jogo aparecer primeiro.
    -- Re-obtém o player via getSpecificPlayer para evitar referência stale.
    local capturedIndex = playerIndex
    local ticks  = 0
    local TARGET = 90

    local function waitTick()
        ticks = ticks + 1
        if ticks >= TARGET then
            Events.OnTick.Remove(waitTick)
            local livePlayer = getSpecificPlayer(capturedIndex) or player
            triggerRank(livePlayer, capturedIndex)
        end
    end

    Events.OnTick.Add(waitTick)
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
    triggerRank(player, 0)
    return true
end

-- ── Menu de contexto (botão direito no mundo) ───────────────
local function onGenerateRank(worldObjects, playerIndex)
    local player = getSpecificPlayer(playerIndex)
    if not player then return end
    RankMain.submitted[playerIndex] = false
    triggerRank(player, playerIndex)
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

RankLog.info("Mod carregado — B42.19+ | v1.3.0")
