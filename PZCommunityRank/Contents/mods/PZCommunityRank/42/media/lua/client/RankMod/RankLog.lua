-- ============================================================
--  RankLog.lua — Log próprio do mod (facilita diagnóstico)
--
--  Grava em <pasta do Zomboid>/Lua/PZRank_log.txt, além do
--  console padrão (prefixo [PZRank]). Não trava o mod se a
--  escrita em arquivo falhar — vira só um print no console.
-- ============================================================

RankLog = {}

local LOG_FILE = "PZRank_log.txt"

local function timestamp()
    local ok, str = pcall(function() return os.date("%Y-%m-%d %H:%M:%S") end)
    if ok and str then return str end
    local okTime, t = pcall(function() return os.time() end)
    return okTime and tostring(t) or "?"
end

local function writeLine(level, msg)
    local line = string.format("[%s] [%s] %s", timestamp(), level, tostring(msg))
    print("[PZRank] " .. line)

    -- B42.19: getFileWriter(name, overwrite, append). Sem fallback que sobrescreva.
    local ok, writer = pcall(getFileWriter, LOG_FILE, false, true)
    if ok and writer then
        pcall(function()
            writer:write(line .. "\n")
            writer:close()
        end)
    end
end

function RankLog.info(msg)  writeLine("INFO", msg)  end
function RankLog.warn(msg)  writeLine("WARN", msg)  end
function RankLog.error(msg) writeLine("ERROR", msg) end
