-- ============================================================
--  RankModCheck.lua - Verifica mods ativos contra a whitelist
--
--  A whitelist e escrita pelo Companion em:
--    <Zomboid>/Lua/pz_rank/pz_rank_allowed_mods.txt
--
--  Formato do arquivo (uma entrada por linha):
--    ALLOW:<mod_id>    -- mod permitido (opcional)
--    REQUIRE:<mod_id>  -- mod obrigatório (deve estar ativo)
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
        reader:close()
    end)

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

-- Coleta os mod IDs ativos tentando múltiplas APIs do PZ B42.
-- M1: getActiveMods() global  (funciona no B41; no B42 retorna só internos)
-- M2: ModManager:getActiveMods()
-- M3: getCore():getActiveMods()
-- M4: ModManager:getLoadedMods()  (B42: pode incluir mods de workshop)
-- M5: Iteração via ModInfo (ModManager:getModInfoList / getAllMods)
-- M6: Leitura direta do arquivo de mods do save (Zomboid/Saves/Survival/<world>/)
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

    -- M3: getCore():getActiveMods()
    pcall(function()
        local core = getCore and getCore()
        if not core then RankLog.warn("[M3-Core] getCore() nao disponivel"); return end
        local ok3, list3 = pcall(function() return core:getActiveMods() end)
        if ok3 then
            collectJavaList("[M3-Core]", list3, mods, seen)
        else
            RankLog.warn("[M3-Core] falhou: " .. tostring(list3))
        end
    end)

    -- M4: ModManager:getLoadedMods() — B42 separa "active" (engine) de "loaded" (todos)
    pcall(function()
        local mgr = ModManager
        if not mgr then return end
        local ok4, list4 = pcall(function() return mgr:getLoadedMods() end)
        if ok4 and list4 then
            collectJavaList("[M4-getLoadedMods]", list4, mods, seen)
        else
            RankLog.warn("[M4-getLoadedMods] falhou: " .. tostring(list4))
        end
    end)

    -- M5: Iteração via objetos ModInfo (getId de cada mod carregado)
    pcall(function()
        local mgr = ModManager
        if not mgr then return end

        local infoList = nil
        for _, fn in ipairs({
            function() return mgr:getModInfoList() end,
            function() return mgr:getAllMods() end,
            function() return mgr.modInfoList end,
        }) do
            local ok, res = pcall(fn)
            if ok and res then infoList = res; break end
        end

        if not infoList then
            RankLog.warn("[M5-ModInfo] nenhuma lista encontrada")
            return
        end

        local sz = 0
        pcall(function() sz = infoList:size() end)
        RankLog.info("[M5-ModInfo] " .. sz .. " entradas")

        for i = 0, sz - 1 do
            pcall(function()
                local entry = infoList:get(i)
                if not entry then return end
                local id
                for _, key in ipairs({"getId", "getModID", "getID"}) do
                    local ok, val = pcall(function() return entry[key](entry) end)
                    if ok and val then id = tostring(val); break end
                end
                if not id then
                    for _, field in ipairs({"modID", "id"}) do
                        local ok, val = pcall(function() return entry[field] end)
                        if ok and val then id = tostring(val); break end
                    end
                end
                if id then
                    RankLog.info("  [M5-ModInfo][" .. i .. "] = " .. id)
                    if not seen[id] then seen[id] = true; mods[#mods + 1] = id end
                end
            end)
        end
    end)

    -- M6: Lê arquivo de mods da pasta do save atual
    -- getFileReader com noModDir=true usa Zomboid/Lua/ como raiz;
    -- ../../Saves/Survival/<world>/mods.txt => Zomboid/Saves/Survival/<world>/mods.txt
    pcall(function()
        local world = getWorld and getWorld()
        if not world then RankLog.warn("[M6-Save] getWorld() indisponivel"); return end

        local worldName
        pcall(function() worldName = world:getWorldName() end)
        if not worldName or worldName == "" then
            RankLog.warn("[M6-Save] getWorldName() falhou")
            return
        end
        RankLog.info("[M6-Save] save = " .. worldName)

        local basePaths = {
            "../../Saves/Survival/",
            "../../Saves/Sandbox/",
        }
        local fileNames = { "mods.txt", "Mods.txt" }

        for _, base in ipairs(basePaths) do
            for _, fname in ipairs(fileNames) do
                local path = base .. worldName .. "/" .. fname
                local ok, reader = pcall(getFileReader, path, true)
                if ok and reader then
                    RankLog.info("[M6-Save] lendo: " .. path)
                    local line = reader:readLine()
                    while line do
                        line = line:match("^%s*(.-)%s*$")
                        if line ~= "" and not line:match("^#") then
                            RankLog.info("[M6-Save] mod = " .. line)
                            if not seen[line] then seen[line] = true; mods[#mods + 1] = line end
                        end
                        line = reader:readLine()
                    end
                    reader:close()
                    return
                end
            end
        end
        RankLog.warn("[M6-Save] arquivo mods.txt nao encontrado no save")
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
