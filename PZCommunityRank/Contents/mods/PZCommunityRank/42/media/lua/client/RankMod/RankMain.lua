-- ============================================================
--  RankMain.lua — Ponto de entrada (B42.19+)
-- ============================================================

require "RankMod/RankLog"
require "RankMod/RankData"
require "RankMod/RankCode"
require "RankMod/RankUI"
require "RankMod/RankFile"
require "RankMod/RankSandbox"
require "RankMod/RankSandboxExport"

RankMain = {}
RankMain.submitted = {}

-- True durante os primeiros ~120 ticks após OnGameStart para ignorar
-- OnPlayerDeath disparado ao carregar um save com personagem já morto.
local _isStartingUp = false

-- Último código gerado pelo silentUpdate — evita salvar arquivos sem mudança de estado.
local _lastSilentCode = nil

-- Contador para disparo periódico (~5 min a 60fps).
local _periodicTick  = 0
local PERIODIC_TICKS = 18000

-- Contador de kills desde o último silentUpdate por kills.
local _killsSinceSync = 0
local KILLS_PER_SYNC  = 10   -- dispara sync a cada 10 kills

-- Coleta dados, gera código, salva arquivo e abre a UI de resultado.
-- O Companion (app externo) faz o sync via arquivo — nenhuma rede aqui.
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

    -- Valida sandbox e embute o resultado no entry para inclusão no código.
    local sandboxOk = true
    pcall(function() sandboxOk = (RankSandbox.check(false) == true) end)
    entry.sandbox_ok = sandboxOk
    if not sandboxOk then
        RankLog.warn("triggerRank: sandbox invalido — codigo sera marcado como 'invalido'.")
    end

    local code = RankCode.generate(entry)
    if not RankCode.isValid(code) then
        RankLog.error("Codigo invalido apos geracao.")
        RankMain.submitted[playerIndex] = false
        return
    end

    RankFile.save(entry, code)
    -- Exporta sandbox em arquivo separado — independente do PZRX2
    pcall(function() RankSandboxExport.export(entry.character_name) end)
    RankSubmitUI.open(entry, code, playerIndex)
end

RankMain.triggerRank = triggerRank

-- Salva arquivo sem abrir UI — usada em saves periódicos e ao sair do mundo.
-- Deduplicação via código: se o estado não mudou, não gera novo arquivo.
local function silentUpdate(player, playerIndex)
    playerIndex = playerIndex or 0
    if RankMain.submitted[playerIndex] then return end  -- jogador já morreu neste run

    local entry = RankData.collect(player, false)
    if not entry then return end

    local sandboxOk = true
    pcall(function() sandboxOk = (RankSandbox.check(false) == true) end)
    entry.sandbox_ok = sandboxOk

    local code = RankCode.generate(entry)
    if not RankCode.isValid(code) then return end

    if code == _lastSilentCode then return end  -- estado não mudou
    _lastSilentCode = code

    RankFile.save(entry, code)
    pcall(function() RankSandboxExport.export(entry.character_name) end)
    RankLog.info("silentUpdate: arquivo gerado sem UI")
end

local function isLocalPlayer(player)
    local ok, result = pcall(function() return player:isLocalPlayer() end)
    if ok and result == true  then return true  end
    if ok and result == false then return false end
    return not (isClient and isClient())
end

-- ── Evento: morte do jogador ────────────────────────────────
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

-- ── Evento: início de partida ───────────────────────────────
local function onGameStart()
    RankMain.submitted = {}
    _killsSinceSync    = 0
    _lastSilentCode    = nil
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
            -- Sync inicial + validação de sandbox após carregamento estável.
            local ok, player = pcall(getPlayer)
            if ok and player and isLocalPlayer(player) then
                silentUpdate(player, 0)
            end
            pcall(function() RankSandbox.check(false) end)
        end
    end
    pcall(function() Events.OnTick.Add(clearStartup) end)
end

-- ── Comando /rank no chat ───────────────────────────────────
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

-- ── Menu de contexto ────────────────────────────────────────
local function onGenerateRank(worldObjects, playerIndex)
    local player = getSpecificPlayer(playerIndex)
    if not player then return end
    RankMain.submitted[playerIndex] = false
    triggerRank(player, playerIndex, false)
end

-- OnFillWorldObjectContextMenu: primeiro arg é o índice do jogador (número inteiro),
-- não o objeto player — o nome 'player' nas funções do jogo é enganoso.
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

-- ── Atualização + validação ao salvar / sair do mundo ─────
-- B42: OnSave foi substituido por OnPostSave (dispara após o save, inclusive ao sair para o menu).
pcall(function()
    Events.OnPostSave.Add(function()
        if _isStartingUp then return end
        local ok, player = pcall(getPlayer)
        if not ok or not player then return end
        if not isLocalPlayer(player) then return end
        silentUpdate(player, 0)
        pcall(function() RankSandbox.check(false) end)
    end)
end)

-- ── Atualização ao subir de nível em qualquer skill ────────
-- A assinatura do evento varia entre versões do PZ; capturamos o player direto.
pcall(function()
    Events.LevelPerk.Add(function(...)
        if _isStartingUp then return end
        local ok, player = pcall(getPlayer)
        if not ok or not player then return end
        if not isLocalPlayer(player) then return end
        silentUpdate(player, 0)
    end)
end)

-- ── Atualização ao matar um zumbi (debounce: 1 sync a cada 10 kills) ──
pcall(function()
    Events.OnZombieDead.Add(function(zombie)
        if _isStartingUp then return end
        _killsSinceSync = _killsSinceSync + 1
        if _killsSinceSync < KILLS_PER_SYNC then return end
        _killsSinceSync = 0
        local ok, player = pcall(getPlayer)
        if not ok or not player then return end
        if not isLocalPlayer(player) then return end
        silentUpdate(player, 0)
    end)
end)

-- ── Atualização a cada novo dia no jogo ────────────────────
pcall(function()
    Events.EveryDays.Add(function()
        if _isStartingUp then return end
        local ok, player = pcall(getPlayer)
        if not ok or not player then return end
        if not isLocalPlayer(player) then return end
        silentUpdate(player, 0)
    end)
end)

-- ── Atualização periódica a cada ~5 min ────────────────────
Events.OnTick.Add(function()
    _periodicTick = _periodicTick + 1
    if _periodicTick < PERIODIC_TICKS then return end
    _periodicTick = 0

    if _isStartingUp then return end
    local ok, player = pcall(getPlayer)
    if not ok or not player then return end
    if not isLocalPlayer(player) then return end
    silentUpdate(player, 0)
end)

RankLog.info("Mod carregado — B42.19+ | v2.0.10")
