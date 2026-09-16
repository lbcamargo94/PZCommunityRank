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

    -- Mostra um modal de aviso (OK-only). Se `onOk` for passado, so roda quando
    -- o jogador clicar OK - usado pra segurar o carregamento ate o aviso ser
    -- reconhecido (mostrar a modal e seguir carregando no mesmo instante nao
    -- funciona: a troca de tela do carregamento destroi a modal antes dela
    -- renderizar um frame sequer - confirmado em teste real).
    -- Se a modal falhar ao ser criada, chama onOk direto - nunca trava o
    -- jogador esperando um clique que nunca vai poder acontecer.
    local function showModal(msg, onOk)
        local created = false
        pcall(function()
            -- x=0,y=0 faz a ISModalDialog se auto-centralizar com base no
            -- tamanho REAL calculado pro texto (ISModalDialog.CalcSize), em vez
            -- de uma posicao fixa calculada supondo uma caixa pequena - com
            -- lista de mods longa a caixa cresce e uma posicao fixa deixa o
            -- botao OK fora da tela.
            local modal = ISModalDialog:new(
                0, 0,
                500, 180, msg, false, nil,
                onOk and function() onOk() end or nil)
            modal:initialise()
            modal:addToUIManager()
            modal:setAlwaysOnTop(true)
            created = true
        end)
        if not created and onOk then onOk() end
    end

    MainScreen.continueLatestSaveAux = function(fromResetLua, checkWorldVersion)
        local pending = nil  -- { kind = "info"|"blocked", list = "..." }

        pcall(function()
            local worldOk, folder = pcall(function() return getWorld():getWorld() end)
            if not worldOk or not folder or folder == "" then return end

            local result = RankModCheck.autoFixBeforeLoad(folder)
            if not result then return end

            if result.status == "fixed" and result.removed and #result.removed > 0 then
                pending = { kind = "info", list = RankModCheck.formatModListForModal(result.removed) }
            elseif result.status == "fix_failed" and result.violations and #result.violations > 0 then
                -- A correcao nao surtiu efeito (gravacao falhou ou nao foi confirmada).
                -- Carregar mesmo assim deixaria o jogador com mod(s) nao permitido(s)
                -- ativo(s) sem deteccao previa - mais seguro bloquear o carregamento
                -- do que arriscar uma correcao que nao foi verificada.
                pending = { kind = "blocked", list = RankModCheck.formatModListForModal(result.violations) }
            end
        end)

        if pending and pending.kind == "blocked" then
            RankLog.error("RankModAutoFix: correcao FALHOU - carregamento bloqueado. Mods: " .. pending.list)
            showModal("PZ Community Rank encontrou mod(s) nao permitido(s) neste save, mas NAO conseguiu corrigir automaticamente:\n\n"
                .. pending.list .. "\n\nPor seguranca, o carregamento foi cancelado. Tente novamente; se persistir, abra a tela de Mods (icone ao lado do save) e desative-os manualmente antes de continuar.")
            return
        end

        if pending and pending.kind == "info" then
            RankLog.warn("RankModAutoFix: mods removidos antes do carregamento - " .. pending.list)
            showModal("PZ Community Rank removeu automaticamente mod(s) nao permitido(s) neste save antes de carregar:\n\n"
                .. pending.list .. "\n\nO save foi corrigido e sera carregado sem eles.", function()
                    originalContinueLatestSaveAux(fromResetLua, checkWorldVersion)
                end)
            return
        end

        return originalContinueLatestSaveAux(fromResetLua, checkWorldVersion)
    end

    MainScreen._pzRankAutoFixPatched = true
    RankLog.info("RankModAutoFix: patch em MainScreen.continueLatestSaveAux instalado.")
end)
