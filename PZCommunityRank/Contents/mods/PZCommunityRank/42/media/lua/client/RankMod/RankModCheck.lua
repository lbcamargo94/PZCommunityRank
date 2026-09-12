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

    -- M6: le mods.txt da pasta do save atual
    -- getFileReader(path, true) usa Zomboid/Lua/ como raiz:
    --   ../Saves/<gameMode>/<worldName>/mods.txt = Zomboid/Saves/Survival/<world>/mods.txt
    -- API correta B42: getWorld():getWorld() retorna o nome da pasta do save
    pcall(function()
        local w = getWorld and getWorld()
        if not w then RankLog.warn("[M6-Save] getWorld() indisponivel"); return end

        local worldName, gameMode

        local getWorldFn = w.getWorld
        if getWorldFn ~= nil then
            pcall(function() worldName = getWorldFn(w) end)
        end
        local getGameModeFn = w.getGameMode
        if getGameModeFn ~= nil then
            pcall(function() gameMode = getGameModeFn(w) end)
        end

        if not worldName or worldName == "" then
            RankLog.warn("[M6-Save] getWorld():getWorld() falhou ou retornou vazio")
            return
        end
        gameMode = (gameMode and gameMode ~= "") and gameMode or "Survival"
        RankLog.info("[M6-Save] save=" .. worldName .. " mode=" .. gameMode)

        local fileNames = { "mods.txt", "Mods.txt" }
        local basePath  = "../Saves/" .. gameMode .. "/" .. worldName .. "/"

        for _, fname in ipairs(fileNames) do
            local fullPath = basePath .. fname
            local ok, reader = pcall(getFileReader, fullPath, true)
            if ok and reader then
                RankLog.info("[M6-Save] lendo: " .. fullPath)
                local line = reader:readLine()
                while line do
                    line = line:match("^%s*(.-)%s*$")
                    -- Formato B42: "mod = <id>," (estruturado)
                    local modId = line:match("^mod%s*=%s*(.-)%s*,?%s*$")
                    if modId and modId ~= "" then
                        RankLog.info("[M6-Save] mod = " .. modId)
                        if not seen[modId] then seen[modId] = true; mods[#mods + 1] = modId end
                    end
                    line = reader:readLine()
                end
                pcall(function() reader:close() end)
                return
            end
        end
        RankLog.warn("[M6-Save] mods.txt nao encontrado em: " .. basePath)
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
