-- ============================================================
--  RankModCheck.lua - Verifica mods ativos contra a whitelist
--
--  A whitelist e escrita pelo Companion em:
--    <Zomboid>/Lua/pz_rank/pz_rank_allowed_mods.txt
--
--  Formato do arquivo (uma entrada por linha):
--    ALLOW:<mod_id>    -- mod permitido (opcional)
--    REQUIRE:<mod_id>  -- mod obrigatorio (deve estar ativo)
--    Linhas em branco ou iniciadas por '#' sao ignoradas.
--
--  Comportamento quando o arquivo está ausente:
--    check() retorna nil -> RankMain nao penaliza o jogador.
--    Assim, jogadores que nunca abriram o Companion nao sao
--    desclassificados por ausencia de whitelist.
-- ============================================================

require "RankMod/RankLog"

RankModCheck = {}

local WHITELIST_FILE = "pz_rank/pz_rank_allowed_mods.txt"

-- Maximo de mods listados por extenso na modal - com mais que isso, o restante
-- vira "e mais N mod(s)" pra nao deixar a caixa gigantesca em altura.
local MODAL_MAX_LISTED_MODS = 15

-- Monta o texto da lista de mods pronto pra entrar numa ISModalDialog: quebra
-- em varias linhas (medindo largura real do texto, igual ISModalDialog.CalcSize
-- faz) e trunca a partir de MODAL_MAX_LISTED_MODS. Sem isso, uma lista longa
-- vira UMA linha so, ISModalDialog.CalcSize nao faz word-wrap e a caixa cresce
-- em largura (e altura, se muitas linhas) alem da tela, empurrando o botao OK
-- pra fora da area visivel/clicavel.
function RankModCheck.formatModListForModal(modIds)
    local shown = modIds
    local extra = 0
    if #modIds > MODAL_MAX_LISTED_MODS then
        shown = {}
        for i = 1, MODAL_MAX_LISTED_MODS do shown[i] = modIds[i] end
        extra = #modIds - MODAL_MAX_LISTED_MODS
    end

    local maxWidthPx = math.min(700, getCore():getScreenWidth() - 160)
    local tm = getTextManager()
    local lines = {}
    local current = ""
    for i, id in ipairs(shown) do
        local sep = (i < #shown) and ", " or ""
        local candidate = current .. id .. sep
        if current ~= "" and tm:MeasureStringX(UIFont.Small, candidate) > maxWidthPx then
            table.insert(lines, current)
            current = id .. sep
        else
            current = candidate
        end
    end
    if current ~= "" then table.insert(lines, current) end

    if extra > 0 then
        lines[#lines + 1] = "(e mais " .. extra .. " mod(s)...)"
    end

    return table.concat(lines, "\n")
end

-- IDs que sempre aparecem em getActiveMods() mas nao precisam ser autorizados:
--   base / Base / pzexo  = IDs internos do PZ engine
--   PZCommunityRank      = o proprio mod do desafio (sempre obrigatorio, nao cadastrado no site)
local INTERNAL_IDS = {
    ["pzexo"]            = true,
    ["base"]             = true,
    ["Base"]             = true,
    ["PZCommunityRank"]  = true,
}

-- Lê e parseia o arquivo de whitelist.
-- Retorna { allowed = {id=true,...}, required = {id=true,...} }
-- ou nil se o arquivo nao existir ou estiver vazio.
local function readWhitelist()
    -- noModDir=true: le relativo a Zomboid/Lua/ diretamente (onde o Companion escreve).
    -- noModDir=false buscaria em Zomboid/Lua/<ModId>/... que e o diretorio errado.
    local ok, reader = pcall(function()
        return getFileReader(WHITELIST_FILE, true)
    end)
    if not ok or not reader then return nil end

    local allowed  = {}
    local required = {}
    local hasEntry = false

    pcall(function()
        local line = reader:readLine()
        while line do
            line = line:match("^%s*(.-)%s*$")
            if line ~= "" and not line:match("^#") then
                local prefix, modId = line:match("^([A-Z]+):(.+)$")
                if prefix and modId and modId ~= "" then
                    hasEntry = true
                    if prefix == "ALLOW" then
                        allowed[modId] = true
                    elseif prefix == "REQUIRE" then
                        allowed[modId]  = true
                        required[modId] = true
                    end
                end
            end
            line = reader:readLine()
        end
    end)
    pcall(function() reader:close() end)

    if not hasEntry then return nil end
    return { allowed = allowed, required = required }
end

-- Itera um ArrayList<String> Java e acrescenta em `out`, sem duplicatas.
local function collectJavaList(label, javaList, out, seen)
    if not javaList then
        RankLog.warn(label .. " retornou nil")
        return
    end
    pcall(function()
        local sz = javaList:size()
        RankLog.info(label .. " retornou " .. sz .. " mod(s)")
        for i = 0, sz - 1 do
            pcall(function()
                local id = javaList:get(i)
                if id then
                    local s = tostring(id)
                    RankLog.info("  " .. label .. "[" .. i .. "] = " .. s)
                    if not seen[s] then seen[s] = true; out[#out + 1] = s end
                end
            end)
        end
    end)
end

-- Coleta os mod IDs ativos.
-- M1 e M2: APIs Java confirmadas seguras (retornam apenas IDs internos no B42).
-- M6: le mods.txt do save atual via getFileReader (puro Lua, sem Java internals).
--     API correta B42: getWorld():getWorld() = nome do save
--                      getWorld():getGameMode() = modo (Survival/Sandbox)
local function safeGetActiveModList()
    local mods = {}
    local seen = {}

    -- M1: global getActiveMods()
    local ok1, list1 = pcall(getActiveMods)
    if ok1 then
        collectJavaList("[M1-global]", list1, mods, seen)
    else
        RankLog.warn("[M1-global] getActiveMods() excecao: " .. tostring(list1))
    end

    -- M2: ModManager:getActiveMods()
    pcall(function()
        local mgr = ModManager
        if not mgr then RankLog.warn("[M2-ModManager] classe nao encontrada"); return end
        local ok2, list2 = pcall(function() return mgr:getActiveMods() end)
        if ok2 then
            collectJavaList("[M2-ModManager]", list2, mods, seen)
        else
            RankLog.warn("[M2-ModManager] falhou: " .. tostring(list2))
        end
    end)

    -- M7: getSaveInfo(getWorld():getWorld()).activeMods:getMods()
    -- API oficial PZ B42 para mods do save atual. getSaveInfo e uma funcao Lua nativa
    -- que retorna tabela com campo activeMods (objeto Java com getMods():ArrayList<String>).
    -- Iteracao: size() + get(i-1) (0-indexed), conforme LoadGameScreen.lua do PZ.
    pcall(function()
        local w = getWorld and getWorld()
        if not w then RankLog.warn("[M7-SaveInfo] getWorld() indisponivel"); return end

        local worldName
        local getWorldFn = w.getWorld
        if getWorldFn ~= nil then
            pcall(function() worldName = getWorldFn(w) end)
        end
        if not worldName or worldName == "" then
            RankLog.warn("[M7-SaveInfo] getWorld():getWorld() falhou")
            return
        end
        RankLog.info("[M7-SaveInfo] save=" .. worldName)

        local ok1, saveInfo = pcall(getSaveInfo, worldName)
        if not ok1 or not saveInfo then
            RankLog.warn("[M7-SaveInfo] getSaveInfo() falhou")
            return
        end

        local activeMods = saveInfo.activeMods
        if not activeMods then
            RankLog.warn("[M7-SaveInfo] activeMods nil no saveInfo")
            return
        end

        local ok2, modList = pcall(function() return activeMods:getMods() end)
        if not ok2 or not modList then
            RankLog.warn("[M7-SaveInfo] getMods() falhou")
            return
        end

        local sz = 0
        pcall(function() sz = modList:size() end)
        RankLog.info("[M7-SaveInfo] " .. sz .. " mod(s) no save")

        for i = 1, sz do
            pcall(function()
                local modID = modList:get(i - 1)  -- ArrayList Java e 0-indexed
                if modID and modID ~= "" then
                    local s = tostring(modID)
                    RankLog.info("[M7-SaveInfo] mod = " .. s)
                    if not seen[s] then seen[s] = true; mods[#mods + 1] = s end
                end
            end)
        end
    end)

    RankLog.info("safeGetActiveModList: total unico = " .. #mods)
    return mods
end

-- Retorna lista de mod IDs ativos, excluindo IDs internos do engine.
-- Usado por RankCode para incluir a lista no payload do codigo PZR.
function RankModCheck.getActiveModIds()
    local all  = safeGetActiveModList()
    local out  = {}
    for _, id in ipairs(all) do
        if not INTERNAL_IDS[id] then
            out[#out + 1] = id
        end
    end
    RankLog.info("getActiveModIds: " .. #out .. " mod(s) externos (total bruto: " .. #all .. ")")
    return out
end

-- Verifica mods ativos contra a whitelist.
--
-- Retorna:
--   nil        -> whitelist ausente, verificacao ignorada
--   {}         -> sem violacoes
--   { ... }    -> lista de strings descrevendo cada violacao
--
-- Violacoes possiveis:
--   "NAO_PERMITIDO:<id>"  -- mod ativo nao esta na whitelist
--   "AUSENTE:<id>"        -- mod obrigatorio nao esta ativo
function RankModCheck.check()
    local whitelist = readWhitelist()
    if not whitelist then
        RankLog.info("ModCheck: whitelist ausente (Companion nao rodou ainda) - verificacao ignorada.")
        return nil
    end

    local activeMods = safeGetActiveModList()
    local violations = {}

    -- Verifica mods ativos nao permitidos
    for _, modId in ipairs(activeMods) do
        if not INTERNAL_IDS[modId] and not whitelist.allowed[modId] then
            violations[#violations + 1] = "NAO_PERMITIDO:" .. modId
        end
    end

    -- Verifica mods obrigatorios ausentes
    local activeSet = {}
    for _, modId in ipairs(activeMods) do activeSet[modId] = true end
    for modId in pairs(whitelist.required) do
        if not activeSet[modId] then
            violations[#violations + 1] = "AUSENTE:" .. modId
        end
    end

    return violations
end

-- ============================================================
--  Auto-correcao PRE-carregamento (sem depender do Companion)
--
--  Roda no contexto de menu principal (antes do save carregar),
--  via patch em MainScreen.continueLatestSaveAux (RankModAutoFix.lua).
--  Usa a MESMA API que a tela nativa "Mods" usa para editar e
--  gravar o mods.txt de um save existente:
--    ActiveMods.getById("currentGame"):setModActive(id, false)
--    manipulateSavefile(folder, "WriteModsDotTxt")
--  Isso NAO e escrita de arquivo via Lua (getFileWriter) - e uma
--  funcao nativa do jogo, entao nao esbarra no sandbox que limita
--  getFileReader/getFileWriter a Zomboid/Lua/.
--
--  Como isso roda ANTES do save carregar, o mod bloqueado nunca
--  chega a ser carregado nesta sessao (nao e so uma correcao para
--  a proxima vez - evita o problema no acesso atual tambem).
-- ============================================================

-- Verifica se `targetId` esta presente num ArrayList<String> Java
-- (ex: activeMods:getMods()). Usado para confirmar que um save especifico
-- realmente inclui o mod, antes de aplicar qualquer correcao nele.
local function findModIdInJavaList(javaList, targetId)
    if not javaList then return false end
    local sz = 0
    pcall(function() sz = javaList:size() end)
    for i = 0, sz - 1 do
        local ok, id = pcall(function() return javaList:get(i) end)
        if ok and id and tostring(id) == targetId then
            return true
        end
    end
    return false
end

-- Retorna a lista de mod IDs violando a whitelist dentro de um
-- ArrayList<String> Java (ex: activeMods:getMods()).
local function findViolationsInJavaList(javaList, whitelist)
    local violations = {}
    if not javaList then return violations end
    local sz = 0
    pcall(function() sz = javaList:size() end)
    for i = 0, sz - 1 do
        local ok, id = pcall(function() return javaList:get(i) end)
        if ok and id then
            local s = tostring(id)
            if not INTERNAL_IDS[s] and not whitelist.allowed[s] then
                violations[#violations + 1] = s
            end
        end
    end
    return violations
end

-- Monta um mapa modId -> ModInfo varrendo todos os diretorios de mods instalados
-- (local + Workshop). Usado para saber as dependencias (getRequire()) de cada mod
-- na hora de reordenar a load order - mesma fonte que o ModSelector nativo usa.
local function buildModInfoMap()
    local map = {}
    pcall(function()
        for _, directory in ipairs(getModDirectoryTable()) do
            local modInfo = getModInfo(directory)
            if modInfo then
                local idOk, id = pcall(function() return modInfo:getId() end)
                if idOk and id and id ~= "" and not map[id] then
                    map[id] = modInfo
                end
            end
        end
    end)
    return map
end

-- Itera um ArrayList<String> Java (metodo getter de ModInfo) chamando addFn(id)
-- para cada entrada. Usado para require()/getLoadAfter()/getLoadBefore().
local function forEachModInfoListEntry(modInfo, getterName, addFn)
    local ok, list = pcall(function() return modInfo[getterName](modInfo) end)
    if not ok or not list then return end
    local sz = 0
    pcall(function() sz = list:size() end)
    for j = 0, sz - 1 do
        local idOk, id = pcall(function() return list:get(j) end)
        if idOk and id then addFn(id) end
    end
end

-- Monta um mapa modId -> lista de IDs que devem carregar ANTES dele, combinando
-- 3 campos de mod.info: require=, loadafter= (mesma semantica de ordenacao) e
-- loadbefore= (normalizado como loadAfter no mod ALVO - mesma tecnica que o
-- "Mod Load Order Sorter" usa em updateSortingRulesLoadAfter()).
local function buildDependencyMap(modInfoMap)
    local deps = {}
    local function addDep(modId, depId)
        if not modId or not depId or modId == depId then return end
        deps[modId] = deps[modId] or {}
        deps[modId][depId] = true
    end

    for modId, modInfo in pairs(modInfoMap) do
        forEachModInfoListEntry(modInfo, "getRequire", function(reqId) addDep(modId, reqId) end)
        forEachModInfoListEntry(modInfo, "getLoadAfter", function(afterId) addDep(modId, afterId) end)
        -- loadbefore=X no mod A significa "A carrega antes de X", ou seja,
        -- do ponto de vista de X, A e uma dependencia (X carrega depois de A).
        forEachModInfoListEntry(modInfo, "getLoadBefore", function(beforeId) addDep(beforeId, modId) end)
    end
    return deps
end

-- Reordena `modIds` para que toda dependencia (require=/loadafter=/loadbefore=)
-- venha antes de quem depende dela - mesma logica que
-- ModSelector.Model:correctAndSaveModOrder usa nativamente (a mesma funcao
-- do "Mod Load Order Sorter"). IMPORTANTE: so reordena dependencias que JA
-- estao em `modIds` - nunca reativa um mod que foi removido por nao ser
-- permitido so porque outro mod o lista como requisito.
local function reorderModList(modIds, modInfoMap)
    local currentSet = {}
    for _, id in ipairs(modIds) do currentSet[id] = true end

    local dependencyMap = buildDependencyMap(modInfoMap)

    local autoOrder = {}
    local added = {}
    for _, id in ipairs(modIds) do
        local depSet = dependencyMap[id]
        if depSet then
            for depId in pairs(depSet) do
                if currentSet[depId] and not added[depId] then
                    autoOrder[#autoOrder + 1] = depId
                    added[depId] = true
                end
            end
        end
        if not added[id] then
            autoOrder[#autoOrder + 1] = id
            added[id] = true
        end
    end
    return autoOrder
end

-- Remove mods nao permitidos diretamente de um objeto ActiveMods (Lua/Java),
-- e reordena o que restou - sem envolver leitura/escrita de save em disco.
-- Usado tanto pelo fix de save existente (autoFixBeforeLoad) quanto pela
-- criacao de uma nova run BRASILEIRAO (RankGameMode.lua), onde ainda nao
-- existe save/mods.txt para gravar.
--
-- Retorna:
--   nil     -> whitelist ausente ou objeto invalido - nada foi verificado
--   {}      -> nenhuma violacao encontrada
--   { ... } -> lista de mod IDs removidos (objeto ja foi corrigido e reordenado)
function RankModCheck.stripDisallowedFromActiveMods(activeModsObj)
    local whitelist = readWhitelist()
    if not whitelist then return nil end
    if not activeModsObj then return nil end

    local modListOk, modList = pcall(function() return activeModsObj:getMods() end)
    if not modListOk or not modList then return nil end

    local violations = findViolationsInJavaList(modList, whitelist)
    if #violations == 0 then return {} end

    local ok = pcall(function()
        for _, id in ipairs(violations) do
            activeModsObj:setModActive(id, false)
        end
        activeModsObj:checkMissingMods()
        activeModsObj:checkMissingMaps()

        local remaining = {}
        local sz = 0
        pcall(function() sz = activeModsObj:getMods():size() end)
        for i = 0, sz - 1 do
            local idOk, id = pcall(function() return activeModsObj:getMods():get(i) end)
            if idOk and id then remaining[#remaining + 1] = id end
        end

        local modInfoMap = buildModInfoMap()
        local reordered = reorderModList(remaining, modInfoMap)

        local modArray = activeModsObj:getMods()
        modArray:clear()
        for _, id in ipairs(reordered) do
            modArray:add(id)
        end
    end)

    if not ok then
        RankLog.error("stripDisallowedFromActiveMods: falha ao aplicar correcao.")
        return nil
    end

    return violations
end

-- Verifica e corrige o mods.txt do save `saveFolder` ANTES do carregamento.
-- Retorna uma tabela { status = ..., removed = {...} / violations = {...} }:
--   status = "skip"       -> whitelist ausente ou save sem info - nada foi checado, carregamento segue normal
--   status = "clean"      -> save ja estava correto, nada a fazer
--   status = "fixed"      -> violacoes encontradas E corrigidas com sucesso (removed = lista de IDs)
--   status = "fix_failed" -> violacoes encontradas mas a correcao NAO surtiu efeito (violations = lista de IDs)
--                            - quem chama deve tratar como inseguro e bloquear o carregamento.
function RankModCheck.autoFixBeforeLoad(saveFolder)
    local whitelist = readWhitelist()
    if not whitelist then return { status = "skip" } end

    local infoOk, saveInfo = pcall(getSaveInfo, saveFolder)
    if not infoOk or not saveInfo or not saveInfo.activeMods then
        RankLog.warn("autoFixBeforeLoad: getSaveInfo indisponivel para '" .. tostring(saveFolder) .. "'")
        return { status = "skip" }
    end

    local modListOk, modList = pcall(function() return saveInfo.activeMods:getMods() end)
    if not modListOk or not modList then
        RankLog.warn("autoFixBeforeLoad: activeMods:getMods() falhou para '" .. tostring(saveFolder) .. "'")
        return { status = "skip" }
    end

    -- So aplica a correcao em saves que JA tem PZCommunityRank na propria lista
    -- de mods. Sem isso, o patch (instalado sempre que o mod esta marcado no
    -- menu principal de Mods) mexeria em QUALQUER save carregado, mesmo saves
    -- que nunca incluiram o mod - bug real reportado apos o primeiro release.
    if not findModIdInJavaList(modList, "PZCommunityRank") then
        return { status = "skip" }
    end

    -- IMPORTANTE: manipulateSavefile precisa de saveInfo.saveDir, NAO do
    -- `saveFolder` usado em getSaveInfo(saveFolder) - sao strings diferentes.
    -- Confirmado lendo o uso oficial em MainScreen.lua (onCheckSavefileModalClick),
    -- o mesmo fluxo nativo que o jogo usa para corrigir um save com mods invalidos.
    -- Usar `saveFolder` aqui grava em um caminho errado sem lancar erro nenhum
    -- (silenciosamente nao aplica a correcao) - ja aconteceu em teste real.
    local saveDir = saveInfo.saveDir
    if not saveDir or saveDir == "" then
        RankLog.error("autoFixBeforeLoad: saveInfo.saveDir ausente para '" .. tostring(saveFolder) .. "' - correcao impossivel.")
        local violations = findViolationsInJavaList(modList, whitelist)
        if #violations == 0 then return { status = "clean" } end
        return { status = "fix_failed", violations = violations }
    end

    local currentMods = ActiveMods.getById("currentGame")
    local copyOk = pcall(function() currentMods:copyFrom(saveInfo.activeMods) end)
    if not copyOk then
        RankLog.error("autoFixBeforeLoad: falha ao copiar activeMods do save.")
        return { status = "skip" }
    end

    local violations = RankModCheck.stripDisallowedFromActiveMods(currentMods)
    if violations == nil then
        RankLog.error("autoFixBeforeLoad: falha ao aplicar correcao no ActiveMods.")
        return { status = "skip" }
    end
    if #violations == 0 then return { status = "clean" } end

    local fixOk, fixErr = pcall(function()
        manipulateSavefile(saveDir, "WriteModsDotTxt")
    end)

    if not fixOk then
        RankLog.error("autoFixBeforeLoad: falha ao gravar correcao - " .. tostring(fixErr))
        return { status = "fix_failed", violations = violations }
    end

    -- Verifica de verdade se a gravacao surtiu efeito antes de reportar sucesso -
    -- nao confiar so na ausencia de erro (manipulateSavefile pode falhar em
    -- silencio se o caminho estiver errado).
    local verifyOk, stillViolating = pcall(function()
        local freshInfo = getSaveInfo(saveFolder)
        local freshList = freshInfo and freshInfo.activeMods and freshInfo.activeMods:getMods()
        return findViolationsInJavaList(freshList, whitelist)
    end)
    if not verifyOk or (stillViolating and #stillViolating > 0) then
        RankLog.error("autoFixBeforeLoad: gravacao nao surtiu efeito - mods ainda presentes apos manipulateSavefile.")
        return { status = "fix_failed", violations = violations }
    end

    RankLog.warn(string.format(
        "autoFixBeforeLoad: %d mod(s) nao permitido(s) removido(s) do save '%s' antes do carregamento.",
        #violations, tostring(saveFolder)))
    for _, id in ipairs(violations) do RankLog.warn("  -> removido: " .. id) end

    return { status = "fixed", removed = violations }
end
