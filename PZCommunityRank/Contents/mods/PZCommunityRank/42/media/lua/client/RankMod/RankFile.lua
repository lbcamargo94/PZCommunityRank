-- ============================================================
--  RankFile.lua — Exporta o código de rank para arquivo .txt
--
--  Salva em <pasta Zomboid>/Lua/pz_rank/pz_rank_<personagem>.txt
--  Um arquivo por personagem; cada geração é ADICIONADA ao final.
--  O histórico completo fica registrado no mesmo arquivo.
--  O Companion sempre lê o último código (entrada mais recente).
-- ============================================================

require "RankMod/RankLog"

RankFile = {}

-- Remove caracteres inválidos em nomes de arquivo; espaços → _
local function sanitizeName(name)
    local s = (name or "Sobrevivente"):gsub('[<>:"/\\|?*]', ""):gsub("%s+", "_")
    return (s ~= "" and s) or "Sobrevivente"
end

-- Retorna data/hora real do computador como string "YYYY-MM-DD HH:MM:SS".
-- Tentativa 1: os.date (disponível no LuaJ do PZ B42, hora do sistema).
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

-- Adiciona entry + code ao arquivo do personagem (cria se não existir).
-- Cada chamada ACUMULA no mesmo arquivo — histórico completo por personagem.
-- Retorna true em sucesso; nunca lança exceção (erros vão para o log).
function RankFile.save(entry, code)
    local charName = sanitizeName(entry.character_name)
    local filename = "pz_rank_" .. charName .. ".txt"
    local filePath = "pz_rank/" .. filename

    local ts     = systemTime()
    local status = entry.is_dead and "Morto" or "Vivo"

    local content = table.concat({
        "=== PZ Community Rank ===",
        "Data/Hora : " .. ts,
        "Personagem: " .. (entry.character_name or "Sobrevivente"),
        "Profissao : " .. (entry.profession     or "Desconhecida"),
        "Status    : " .. status,
        "Sobrev.   : " .. (entry.time_str       or "?"),
        "Zumbis    : " .. tostring(entry.kills  or 0),
        "",
        "--- Codigo de Submissao ---",
        code,
        "---",
        "",
    }, "\n")

    local ok, err = pcall(function()
        -- create_dirs=true: cria pz_rank/ se ausente
        -- append=true: acumula histórico no mesmo arquivo
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
