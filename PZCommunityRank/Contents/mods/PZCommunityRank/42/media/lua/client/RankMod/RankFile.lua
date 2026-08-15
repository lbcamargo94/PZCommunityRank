-- ============================================================
--  RankFile.lua - Exporta o codigo de rank para arquivo .txt
--
--  Salva em <pasta Zomboid>/Lua/pz_rank/pz_rank_<personagem>.txt
--  Um arquivo por personagem; cada geracao e ADICIONADA ao final.
--  O historico completo fica registrado no mesmo arquivo.
--  O Companion sempre le o ultimo codigo (entrada mais recente).
-- ============================================================

require "RankMod/RankLog"

RankFile = {}

-- Remove caracteres invalidos em nomes de arquivo; espacos -> _
local function sanitizeName(name)
    local s = (name or "Sobrevivente"):gsub('[<>:"/\\|?*]', ""):gsub("%s+", "_")
    return (s ~= "" and s) or "Sobrevivente"
end

-- Retorna data/hora real do computador como string "YYYY-MM-DD HH:MM:SS".
-- Tentativa 1: os.date (disponivel no LuaJ do PZ B42, hora do sistema).
-- Tentativa 2: Java System.currentTimeMillis via luajava (fallback robusto).
local function systemTime()
    local ok, s = pcall(function() return os.date("%Y-%m-%d %H:%M:%S") end)
    if ok and type(s) == "string" and #s > 10 then return s end

    local ok2, ms = pcall(function()
        return luajava.bindClass("java.lang.System"):currentTimeMillis()
    end)
    if ok2 and ms then
        local t    = math.floor(tonumber(tostring(ms)) / 1000)
        local ok3, s3 = pcall(function() return os.date("%Y-%m-%d %H:%M:%S", t) end)
        if ok3 and type(s3) == "string" then return s3 end
    end

    return "?"
end

-- Adiciona entry + code ao arquivo do personagem (cria se nao existir).
-- Cada chamada ACUMULA no mesmo arquivo - historico completo por personagem.
-- Retorna true em sucesso; nunca lanca excecao (erros vao para o log).
function RankFile.save(entry, code)
    local charName = sanitizeName(entry.character_name)
    local filename = "pz_rank_" .. charName .. ".txt"
    local filePath = "pz_rank/" .. filename

    local ts     = systemTime()
    local status = entry.is_dead and "Morto" or "Vivo"

    local parts = {
        "=== PZ Community Rank ===",
        "Data/Hora : " .. ts,
        "Personagem: " .. (entry.character_name or "Sobrevivente"),
        "Profissao : " .. (entry.profession     or "Desconhecida"),
        "Status    : " .. status,
        "Sobrev.   : " .. (entry.time_str       or "?"),
        "Zumbis    : " .. tostring(entry.kills  or 0),
    }
    if entry.disqualification_reason then
        parts[#parts + 1] = "Motivo    : " .. entry.disqualification_reason
    end
    parts[#parts + 1] = ""
    parts[#parts + 1] = "--- Codigo de Submissao ---"
    parts[#parts + 1] = code
    parts[#parts + 1] = "---"
    parts[#parts + 1] = ""

    local content = table.concat(parts, "\n")

    local ok, err = pcall(function()
        -- create_dirs=true: cria pz_rank/ se ausente
        -- append=true: acumula historico no mesmo arquivo
        local w = getFileWriter(filePath, true, true)
        if not w then error("getFileWriter retornou nil") end
        w:write(content)
        w:close()
    end)

    if ok then
        RankLog.info("Arquivo atualizado: " .. filePath)
    else
        RankLog.error("Falha ao atualizar " .. filePath .. ": " .. tostring(err))
    end
    return ok
end

-- Exporta stats de conquistas para pz_rank_stats_<charname>.log.
-- Lido pelo Companion localmente — NAO e enviado ao backend.
-- Conteudo JSON com os 33 campos de conquistas (PZRX3-8).
-- .log porque B42.20 bloqueia .json no getFileWriter.
function RankFile.saveStats(entry)
    local safeName = sanitizeName(entry.character_name or "Sobrevivente")
    local ext      = entry.extended or {}
    local filePath = "pz_rank/pz_rank_stats_" .. safeName .. ".log"

    local json = string.format(
        '{"type":"rank_stats","version":"1.0","character":"%s","stats":{' ..
        '"animals_killed":%d,"fish_caught":%d,"crops_harvested":%d,' ..
        '"items_crafted":%d,"houses_looted":%d,"hours_without_sleep":%d,' ..
        '"trees_cut":%d,"books_read":%d,"structures_built":%d,"crops_planted":%d,' ..
        '"spiffo_visited":%d,' ..
        '"eggs_collected":%d,"milk_produced":%d,"stone_structures":%d,' ..
        '"ceramic_items":%d,"forged_weapons":%d,"km_driven":%d,' ..
        '"cities_visited":%d,"military_visited":%d,"meals_cooked":%d,' ..
        '"water_collected":%d,"materials_crafted":%d,"animal_tracks":%d,' ..
        '"weapons_crafted":%d,' ..
        '"furniture_crafted":%d,"clothes_crafted":%d,"cheese_produced":%d,' ..
        '"doors_opened":%d,"sleep_locations":%d,"basements_explored":%d,' ..
        '"stations_used":%d,"animal_species":%d,"days_no_canned":%d}}',
        (entry.character_name or "Sobrevivente"):gsub('"', '\\"'),
        ext.animals_killed      or 0,
        ext.fish_caught         or 0,
        ext.crops_harvested     or 0,
        ext.items_crafted       or 0,
        ext.houses_looted       or 0,
        ext.hours_without_sleep or 0,
        ext.trees_cut           or 0,
        ext.books_read          or 0,
        ext.structures_built    or 0,
        ext.crops_planted       or 0,
        ext.spiffo_visited      or 0,
        ext.eggs_collected      or 0,
        ext.milk_produced       or 0,
        ext.stone_structures    or 0,
        ext.ceramic_items       or 0,
        ext.forged_weapons      or 0,
        ext.km_driven           or 0,
        ext.cities_visited      or 0,
        ext.military_visited    or 0,
        ext.meals_cooked        or 0,
        ext.water_collected     or 0,
        ext.materials_crafted   or 0,
        ext.animal_tracks       or 0,
        ext.weapons_crafted     or 0,
        ext.furniture_crafted   or 0,
        ext.clothes_crafted     or 0,
        ext.cheese_produced     or 0,
        ext.doors_opened        or 0,
        ext.sleep_locations     or 0,
        ext.basements_explored  or 0,
        ext.stations_used       or 0,
        ext.animal_species      or 0,
        ext.days_no_canned      or 0
    )

    local ok, err = pcall(function()
        local w = getFileWriter(filePath, true, false)
        if not w then error("getFileWriter retornou nil") end
        w:write(json)
        w:close()
    end)

    if ok then
        RankLog.info("Stats salvas: " .. filePath)
    else
        RankLog.error("Falha ao salvar stats " .. filePath .. ": " .. tostring(err))
    end
    return ok
end

-- Exporta manifesto de personagens para pz_rank_saves.json.
-- Lido pelo Companion para popular a tela "Meus Saves".
-- Faz upsert do personagem atual; o Companion acumula entradas por char_name.
function RankFile.saveManifest(entry)
    local safeName = sanitizeName(entry.character_name or "Sobrevivente")
    local status   = entry.is_dead and "dead" or "alive"
    local ts       = math.floor(os.time and os.time() or 0)

    local json = string.format(
        '{"type":"rank_saves","version":"1.0","characters":[{"name":"%s","status":"%s","kills":%d,"updated_at":%d}]}',
        (entry.character_name or "Sobrevivente"):gsub('"', '\\"'),
        status,
        entry.kills or 0,
        ts
    )

    -- .json e bloqueado em B42.20 — salva como .log mas o Companion espera .json
    -- Para manter compat com ambas as versoes, tenta .json e cai para .log
    local filePath = "pz_rank/pz_rank_saves.json"
    local ok = pcall(function()
        local w = getFileWriter(filePath, true, false)
        if not w then error("getFileWriter retornou nil") end
        w:write(json)
        w:close()
    end)

    if not ok then
        -- B42.20+: .json bloqueado, usa extensao .log
        filePath = "pz_rank/pz_rank_saves.log"
        local ok2, err2 = pcall(function()
            local w = getFileWriter(filePath, true, false)
            if not w then error("getFileWriter retornou nil") end
            w:write(json)
            w:close()
        end)
        if ok2 then
            RankLog.info("Manifesto salvo (fallback .log): " .. filePath)
        else
            RankLog.error("Falha ao salvar manifesto: " .. tostring(err2))
        end
    else
        RankLog.info("Manifesto salvo: " .. filePath)
    end
end

-- Exporta delta de heatmap para pz_rank_heatmap_<charname>.log.
-- Lido pelo Companion e enviado como heatmap_delta no POST de sync.
function RankFile.saveHeatmap(player, charName)
    if not player or not charName then return end
    local safeName = sanitizeName(charName)
    local md
    local mdOk = pcall(function() md = player:getModData() end)
    if not mdOk or not md then return end

    local parts = {}

    -- Coleta kills por célula a partir do índice PZCommunityRank_HeatKillCells
    local cellsStr = md["PZCommunityRank_HeatKillCells"] or ""
    for cell in cellsStr:gmatch("|([^|]+)|") do
        local gxStr, gyStr = cell:match("^(-?%d+)_(-?%d+)$")
        if gxStr and gyStr then
            local count = tonumber(md["PZCommunityRank_HeatKill_" .. gxStr .. "_" .. gyStr]) or 0
            if count > 0 then
                parts[#parts + 1] = string.format(
                    '{"type":"kill","gx":%s,"gy":%s,"count":%d}', gxStr, gyStr, count)
            end
        end
    end

    -- Posição de morte (se registrada)
    local dGX = tonumber(md["PZCommunityRank_HeatDeathGX"])
    local dGY = tonumber(md["PZCommunityRank_HeatDeathGY"])
    if dGX and dGY then
        parts[#parts + 1] = string.format(
            '{"type":"death","gx":%d,"gy":%d,"count":1}', dGX, dGY)
    end

    -- Posição de base (se registrada)
    local bGX = tonumber(md["PZCommunityRank_HeatBaseGX"])
    local bGY = tonumber(md["PZCommunityRank_HeatBaseGY"])
    if bGX and bGY then
        parts[#parts + 1] = string.format(
            '{"type":"base","gx":%d,"gy":%d,"count":1}', bGX, bGY)
    end

    if #parts == 0 then return end

    local json     = "[" .. table.concat(parts, ",") .. "]"
    -- B42.20 bloqueia .json no getFileWriter; o conteudo permanece JSON.
    local filePath = "pz_rank/pz_rank_heatmap_" .. safeName .. ".log"

    local written = false
    local ok2, err2 = pcall(function()
        local w = getFileWriter(filePath, true, false)
        if not w then return end
        w:write(json)
        w:close()
        written = true
    end)

    if ok2 and written then
        RankLog.info("Heatmap salvo: " .. filePath .. " (" .. #parts .. " pontos)")
    elseif not ok2 then
        RankLog.error("Falha ao salvar heatmap " .. filePath .. ": " .. tostring(err2))
    else
        RankLog.warn("Heatmap: getFileWriter recusou o arquivo .log.")
    end
end
