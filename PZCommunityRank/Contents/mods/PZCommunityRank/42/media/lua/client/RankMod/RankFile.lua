-- ============================================================
--  RankFile.lua — Exporta o código de rank para arquivo .txt
--
--  Salva em <pasta Zomboid>/pz_rank/pz_rank_<data>_<hora>_<seq>.txt
--  O diretório pz_rank/ é criado automaticamente se não existir.
--  O contador sequencial (_seq) garante nomes únicos no mesmo segundo.
-- ============================================================

require "RankMod/RankLog"

RankFile = {}

-- Contador por sessão; garante unicidade quando dois códigos são gerados no mesmo segundo.
local _seq = 0

local function fileTimestamp()
    local ok, s = pcall(function() return os.date("%Y-%m-%d_%H-%M-%S") end)
    if ok and type(s) == "string" then return s end
    local ok2, t = pcall(function() return tostring(math.floor(os.time())) end)
    return (ok2 and t) or "000000"
end

-- Salva entry + code em pz_rank/pz_rank_<ts>_<seq>.txt
-- Retorna true em sucesso; nunca lança exceção (erros vão para o log).
function RankFile.save(entry, code)
    _seq = _seq + 1
    local ts       = fileTimestamp()
    local filename = "pz_rank_" .. ts .. "_" .. _seq .. ".txt"
    local path     = "pz_rank/" .. filename

    local status  = entry.is_dead and "Morto" or "Vivo"
    local content = table.concat({
        "=== PZ Community Rank ===",
        "Data/Hora : " .. ts:gsub("_", " "),
        "Personagem: " .. (entry.character_name or "Sobrevivente"),
        "Profissao : " .. (entry.profession     or "Desconhecida"),
        "Status    : " .. status,
        "Sobrev.   : " .. (entry.time_str       or "?"),
        "Zumbis    : " .. tostring(entry.kills  or 0),
        "",
        "--- Codigo de Submissao ---",
        code,
    }, "\n")

    local ok, err = pcall(function()
        -- Parâmetros: (path, create_dirs=true, append=false) → cria pz_rank/ se ausente,
        -- escreve arquivo novo (não acumula em um único arquivo).
        local w = getFileWriter(path, true, false)
        if not w then error("getFileWriter retornou nil") end
        w:write(content)
        w:close()
    end)

    if ok then
        RankLog.info("Arquivo exportado: " .. path)
    else
        RankLog.error("Falha ao exportar " .. path .. ": " .. tostring(err))
    end
    return ok
end
