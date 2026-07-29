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

-- Exporta delta de heatmap para pz_rank_heatmap_<charname>.json.
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
    local filePath = "pz_rank/pz_rank_heatmap_" .. safeName .. ".json"

    local ok2, err2 = pcall(function()
        local w = getFileWriter(filePath, true, false)
        if not w then error("getFileWriter retornou nil") end
        w:write(json)
        w:close()
    end)

    if ok2 then
        RankLog.info("Heatmap salvo: " .. filePath .. " (" .. #parts .. " pontos)")
    else
        RankLog.error("Falha ao salvar heatmap " .. filePath .. ": " .. tostring(err2))
    end
end
