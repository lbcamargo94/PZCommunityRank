-- ============================================================
--  RankGameMode.lua — Modo BRASILEIRAO PZ na tela de Nova Partida
--
--  Injeta uma entrada na lista de modos do NewGameScreen.
--  Ao selecionar, aplica automaticamente BrasileiraoChallenge.lua
--  como preset de sandbox e pula direto para o spawn select
--  (sem exibir a tela de opcoes de sandbox).
-- ============================================================

require "RankMod/RankLog"

-- ── Constantes ────────────────────────────────────────────────────────────

local MODE_ID    = "BrasileiraoChallenge"
local MODE_TITLE = "BRASILEIRAO PZ"
local MODE_DESC  = "Desafio oficial de sobrevivencia."
                .. " Sandbox configurado automaticamente com as regras do ranking."
                .. " Crie seu personagem, escolha o spawn e comece a sobreviver."
local MODE_THUMB = "media/textures/BrasileiraoThumb.png"

-- ── Injeção na lista de modos ─────────────────────────────────────────────
--
--  NewGameScreen.defaultGameModeData é definido em NewGameScreen.lua
--  no nível do módulo. Como arquivos de mods carregam após os vanilla,
--  a tabela já existe quando este arquivo é executado.

if not (NewGameScreen and NewGameScreen.defaultGameModeData) then
    RankLog.warn("RankGameMode: NewGameScreen nao disponivel — modo nao registrado.")
    return
end

table.insert(NewGameScreen.defaultGameModeData, 1, {
    mode  = MODE_ID,
    title = MODE_TITLE,
    desc  = MODE_DESC,
    thumb = MODE_THUMB,
})

RankLog.info("RankGameMode: modo '" .. MODE_TITLE .. "' registrado.")

-- ── Hook: clickPlay ──────────────────────────────────────────────────────
--
--  O botao "Next" da NewGameScreen chama self:clickPlay().
--  Quando o jogador confirma o modo BRASILEIRAO PZ:
--
--  1. Remapeia mode para "Apocalypse" antes do original para que:
--     a) setGameMode() receba um enum valido
--     b) O jogo pule a tela de sandbox options e va direto ao spawn select
--  2. Chama o original (clickPlay aplica o preset "Apocalypse" em linha 436)
--  3. Restaura mode e aplica nosso preset por cima — assim as configuracoes
--     do BrasileiraoChallenge.lua ficam ativas quando o mundo for criado.

local _origClickPlay = NewGameScreen.clickPlay

NewGameScreen.clickPlay = function(self)
    local isBrasileirao = self.selectedItem
                      and self.selectedItem.data
                      and self.selectedItem.data.mode == MODE_ID

    if isBrasileirao then
        self.selectedItem.data.mode = GameMode.APOCALYPSE:toString()
    end

    _origClickPlay(self)

    if isBrasileirao then
        self.selectedItem.data.mode = MODE_ID
        local ok, err = pcall(function()
            local preset = MainScreen.instance.sandOptions:getSandboxPreset(MODE_ID)
            MainScreen.instance:setSandboxPreset(preset)
        end)
        if ok then
            RankLog.info("RankGameMode: preset '" .. MODE_ID .. "' aplicado.")
        else
            RankLog.warn("RankGameMode: erro ao aplicar preset: " .. tostring(err))
        end
    end
end

RankLog.info("RankGameMode: hook clickPlay instalado.")