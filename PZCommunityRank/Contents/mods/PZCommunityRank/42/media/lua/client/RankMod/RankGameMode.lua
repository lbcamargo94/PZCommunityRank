-- ============================================================
--  RankGameMode.lua - Modo BRASILEIRAO PZ na tela de Nova Partida
--
--  Injeta uma entrada na lista de modos do NewGameScreen.
--  Ao selecionar, aplica automaticamente BrasileiraoChallenge.lua
--  como preset de sandbox e pula direto para o spawn select
--  (sem exibir a tela de opcoes de sandbox).
-- ============================================================

require "RankMod/RankLog"

-- Constantes

local MODE_ID    = "BrasileiraoChallenge"
local MODE_TITLE = "BRASILEIRAO PZ"
local MODE_DESC  = "Desafio oficial de sobrevivencia."
                .. " Sandbox configurado automaticamente com as regras do ranking."
                .. " Crie seu personagem, escolha o spawn e comece a sobreviver."
local MODE_THUMB = "media/textures/BrasileiraoThumb.png"

-- Injecao na lista de modos
--
--  NewGameScreen.defaultGameModeData e definido em NewGameScreen.lua
--  no nivel do modulo. Como arquivos de mods carregam apos os vanilla,
--  a tabela ja existe quando este arquivo e executado.

if not (NewGameScreen and NewGameScreen.defaultGameModeData) then
    RankLog.warn("RankGameMode: NewGameScreen nao disponivel - modo nao registrado.")
    return
end

table.insert(NewGameScreen.defaultGameModeData, 1, {
    mode  = MODE_ID,
    title = MODE_TITLE,
    desc  = MODE_DESC,
    thumb = MODE_THUMB,
})

RankLog.info("RankGameMode: modo '" .. MODE_TITLE .. "' registrado.")

-- Hook: clickPlay
--
--  O botao "Next" da NewGameScreen chama self:clickPlay().
--  Quando o jogador confirma o modo BRASILEIRAO PZ:
--
--  1. Remapeia mode para "Sandbox" antes do original.
--     Com Sandbox, clickPlay chama fillList() em modo Sandbox e exibe TODOS
--     os mapas do B42 (que tem only_for_game_mode=Sandbox em map.info).
--     Alem disso, clickPlay nao sobrescreve nosso preset (linha 435 ignorada
--     quando mode == Sandbox).
--
--  2. Apos clickPlay: aplica nosso preset (sobrepoe setDefaultSandboxVars),
--     depois muda getGameMode() de volta para Apocalypse. Com isso, quando
--     o jogador clicar "Next" no spawn select, clickNext (linha 652) ve
--     getGameMode() != "Sandbox" e vai direto para criacao de personagem,
--     pulando a tela de opcoes de sandbox.

local _origClickPlay = NewGameScreen.clickPlay

NewGameScreen.clickPlay = function(self)
    local isBrasileirao = self.selectedItem
                      and self.selectedItem.data
                      and self.selectedItem.data.mode == MODE_ID

    if isBrasileirao then
        -- Sinaliza para o OnGameStart que este e um novo jogo BRASILEIRAO.
        -- O flag persiste na sessao Lua ate ser lido e zerado no grace period.
        _RankMod_PendingBrasileiraoSetup = true

        -- Sandbox: fillList() exibe todos os mapas, linha 435 nao sobrescreve preset
        self.selectedItem.data.mode = GameMode.SANDBOX:toString()
    end

    _origClickPlay(self)

    if isBrasileirao then
        self.selectedItem.data.mode = MODE_ID

        -- Aplica nosso preset apos setDefaultSandboxVars() do clickPlay
        local ok, err = pcall(function()
            local preset = MainScreen.instance.sandOptions:getSandboxPreset(MODE_ID)
            MainScreen.instance:setSandboxPreset(preset)
        end)
        if ok then
            RankLog.info("RankGameMode: preset '" .. MODE_ID .. "' aplicado.")
        else
            RankLog.warn("RankGameMode: erro ao aplicar preset: " .. tostring(err))
        end

        -- Volta para Apocalypse: fillList ja rodou em Sandbox (lista populada),
        -- agora clickNext vera getGameMode() != "Sandbox" e vai para char creation
        -- sem mostrar a tela de opcoes de sandbox.
        pcall(function()
            getWorld():setGameMode(GameMode.APOCALYPSE:toString())
        end)
        RankLog.info("RankGameMode: modo revertido para Apocalypse (spawn select aberto).")
    end
end

RankLog.info("RankGameMode: hook clickPlay instalado.")