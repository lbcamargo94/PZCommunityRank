-- ============================================================
--  RankGameMode.lua - Modo BRASILEIRAO PZ na tela de Nova Partida
--
--  Injeta uma entrada na lista de modos do NewGameScreen.
--  Ao selecionar, aplica automaticamente BrasileiraoChallenge.lua
--  como preset de sandbox e pula direto para o spawn select
--  (sem exibir a tela de opcoes de sandbox).
-- ============================================================

require "RankMod/RankLog"
require "RankMod/RankSandbox"

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

-- Gera/atualiza DesafioPZ.cfg em Zomboid/Sandbox Presets/ a partir do preset Lua.
--
--  Cria um SandboxOptions.new() limpo, aplica todos os valores de
--  BRASILEIRAO_CHALLENGE_PRESET via getOptionByName + parse/setValue,
--  e salva com savePresetFile("DesafioPZ"). O arquivo passa a aparecer
--  na lista de presets da tela de Sandbox para qualquer nova partida.
--  Chamado ao entrar no menu principal (OnMainMenuEnter) e em cada nova partida de desafio.

local function saveDesafioCfg()
    local preset = BRASILEIRAO_CHALLENGE_PRESET
    if not preset then return end

    local ok, err = pcall(function()
        local opts = SandboxOptions.new()
        if not opts then return end

        local function applyToOpts(tbl, prefix)
            if type(tbl) ~= "table" then return end
            for k, v in pairs(tbl) do
                if k ~= "Version" then
                    local key = prefix and (prefix .. "." .. k) or k
                    if type(v) == "table" then
                        applyToOpts(v, key)
                    else
                        pcall(function()
                            local opt = opts:getOptionByName(key)
                            if not opt then return end
                            if type(v) == "boolean" then
                                opt:setValue(v)
                            else
                                opt:parse(tostring(v))
                            end
                        end)
                    end
                end
            end
        end

        applyToOpts(preset, nil)
        opts:savePresetFile("DesafioPZ")
    end)

    if ok then
        RankLog.info("RankGameMode: DesafioPZ.cfg salvo em Sandbox Presets.")
    else
        RankLog.warn("RankGameMode: falha ao salvar DesafioPZ.cfg: " .. tostring(err))
    end
end

-- Aplica o preset BRASILEIRAO diretamente ao SandboxVars e Java SandboxOptions.
--
--  Fluxo:
--    1. saveDesafioCfg()        -> garante que DesafioPZ.cfg esta atualizado
--    2. applyValues(SandboxVars) -> garante que SandboxVars reflete o preset Lua
--    3. applyRules()             -> sincroniza os 56 valores criticos para Java

local function applyBrasileiraoPreset()
    if not BRASILEIRAO_CHALLENGE_PRESET then
        RankLog.warn("RankGameMode: BRASILEIRAO_CHALLENGE_PRESET nao disponivel - usando applyRules().")
        pcall(function() RankSandbox.applyRules() end)
        return false
    end

    saveDesafioCfg()

    local ok = false
    pcall(function() ok = RankSandbox.applyFullPreset() end)
    RankLog.info("RankGameMode: preset BRASILEIRAO aplicado.")
    return ok
end

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
--  2. Apos clickPlay: aplica nosso preset diretamente ao SandboxVars
--     (sobrepoe setDefaultSandboxVars), depois muda getGameMode() de volta
--     para Apocalypse. Com isso, quando o jogador clicar "Next" no spawn
--     select, clickNext ve getGameMode() != "Sandbox" e vai direto para
--     criacao de personagem, pulando a tela de opcoes de sandbox.

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

        -- Aplica preset apos setDefaultSandboxVars() (chamado dentro do clickPlay)
        applyBrasileiraoPreset()

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

-- Instala DesafioPZ.cfg em Zomboid/Sandbox Presets/ ao entrar no menu principal,
-- para que o preset apareca na lista da tela de Sandbox.
-- O flag evita reinstalacao desnecessaria a cada entrada no menu.
local _cfgInstalled = false
Events.OnMainMenuEnter.Add(function()
    if _cfgInstalled then return end
    _cfgInstalled = true
    saveDesafioCfg()
end)