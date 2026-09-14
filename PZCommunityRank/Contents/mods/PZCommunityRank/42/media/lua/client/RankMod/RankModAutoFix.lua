-- ============================================================
--  RankModAutoFix.lua - Corrige o save ANTES dele carregar
--
--  Intercepta MainScreen.continueLatestSaveAux (funcao unica para
--  onde convergem tanto o botao "Play" da tela Load Game quanto o
--  atalho "Continuar" do menu principal) e, antes do jogo carregar
--  o save selecionado, remove do mods.txt qualquer mod nao permitido
--  pela whitelist do Companion (RankModCheck.autoFixBeforeLoad).
--
--  Roda inteiramente no contexto de menu principal, sem depender do
--  jogador ter aberto o Companion para corrigir "da proxima vez":
--  a correcao acontece na hora, antes do save carregar, entao o mod
--  bloqueado nem chega a ser carregado nesta sessao.
--
--  Se o Companion nunca rodou (sem whitelist gravada), nada e feito.
-- ============================================================

require "RankMod/RankLog"
require "RankMod/RankModCheck"

pcall(function()
    require "OptionScreens/MainScreen"

    if not MainScreen or not MainScreen.continueLatestSaveAux then
        RankLog.warn("RankModAutoFix: MainScreen.continueLatestSaveAux indisponivel - patch nao instalado.")
        return
    end
    if MainScreen._pzRankAutoFixPatched then return end

    local originalContinueLatestSaveAux = MainScreen.continueLatestSaveAux

    MainScreen.continueLatestSaveAux = function(fromResetLua, checkWorldVersion)
        pcall(function()
            local worldOk, folder = pcall(function() return getWorld():getWorld() end)
            if not worldOk or not folder or folder == "" then return end

            local violations = RankModCheck.autoFixBeforeLoad(folder)
            if violations and #violations > 0 then
                local list = table.concat(violations, ", ")
                RankLog.warn("RankModAutoFix: mods removidos antes do carregamento - " .. list)
                pcall(function()
                    local msg = "PZ Community Rank removeu automaticamente mod(s) nao permitido(s) neste save antes de carregar:\n\n"
                        .. list .. "\n\nO save foi corrigido e sera carregado sem eles."
                    local modal = ISModalDialog:new(
                        getCore():getScreenWidth() / 2 - 250,
                        getCore():getScreenHeight() / 2 - 90,
                        500, 180, msg, false, nil, nil)
                    modal:initialise()
                    modal:addToUIManager()
                    modal:setAlwaysOnTop(true)
                end)
            end
        end)

        return originalContinueLatestSaveAux(fromResetLua, checkWorldVersion)
    end

    MainScreen._pzRankAutoFixPatched = true
    RankLog.info("RankModAutoFix: patch em MainScreen.continueLatestSaveAux instalado.")
end)
