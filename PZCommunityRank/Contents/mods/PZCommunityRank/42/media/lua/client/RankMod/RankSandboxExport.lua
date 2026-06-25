-- ============================================================
--  RankSandboxExport.lua — Exporta configurações completas do Sandbox
--
--  Gera um arquivo JSON com TODAS as opções do SandboxVars ativo,
--  sem filtros, para auditoria pelos moderadores no painel web.
--
--  Arquivo gerado: <Zomboid>/Lua/pz_rank/pz_rank_sandbox_<Personagem>.json
--  Formato separado do PZRX2 — não interfere no fluxo de ranking.
-- ============================================================

require "RankMod/RankLog"

RankSandboxExport = {}

-- ── Serializador JSON seguro para Lua 5.1 / Kahlua ───────────────────────────
-- Suporta: nil, boolean, number, string, table (aninhada)
-- Userdata / functions → "null" ou representação de string.

local MAX_DEPTH = 10

local function escapeStr(s)
    s = tostring(s)
    -- Kahlua nao suporta classes de caracteres com bytes nulos em gsub
    -- (ex: '[\000-\031]' lanca "malformed pattern") — usa loop char-a-char
    local out = {}
    for i = 1, #s do
        local c = s:sub(i, i)
        local b = string.byte(c)
        if     c == '\\' then out[#out+1] = '\\\\'
        elseif c == '"'  then out[#out+1] = '\\"'
        elseif c == '\n' then out[#out+1] = '\\n'
        elseif c == '\r' then out[#out+1] = '\\r'
        elseif c == '\t' then out[#out+1] = '\\t'
        elseif b < 32    then out[#out+1] = string.format('\\u%04x', b)
        else                  out[#out+1] = c
        end
    end
    return '"' .. table.concat(out) .. '"'
end

local function encodeVal(val, depth)
    depth = depth or 0
    if depth > MAX_DEPTH then return '"<truncated>"' end

    local t = type(val)

    if val == nil          then return 'null' end
    if t == 'boolean'      then return tostring(val) end
    if t == 'string'       then return escapeStr(val) end

    if t == 'number' then
        if val ~= val        then return '"NaN"' end     -- NaN
        if val ==  math.huge then return '"Infinity"' end
        if val == -math.huge then return '"-Infinity"' end
        -- Inteiro → sem casas decimais
        if val == math.floor(val) and math.abs(val) < 1e15 then
            return string.format('%d', val)
        end
        return string.format('%.6g', val)
    end

    if t == 'table' then
        -- Detecta se é array puro (chaves 1..n sem buracos)
        local count = 0
        for _ in pairs(val) do count = count + 1 end

        if count == 0 then return '{}' end

        local isArray = (count == #val and count > 0)

        if isArray then
            local parts = {}
            for _, v in ipairs(val) do
                table.insert(parts, encodeVal(v, depth + 1))
            end
            return '[' .. table.concat(parts, ',') .. ']'
        end

        -- Objeto — ordena chaves para saída estável
        local parts = {}
        local keys  = {}
        for k in pairs(val) do
            if type(k) == 'string' or type(k) == 'number' then
                table.insert(keys, tostring(k))
            end
        end
        table.sort(keys)

        for _, k in ipairs(keys) do
            local v = val[k] ~= nil and val[k] or val[tonumber(k)]
            table.insert(parts, escapeStr(k) .. ':' .. encodeVal(v, depth + 1))
        end
        return '{' .. table.concat(parts, ',') .. '}'
    end

    -- userdata, function, thread → tenta tostring, senão null
    if t == 'userdata' or t == 'function' then
        local ok2, s = pcall(tostring, val)
        if ok2 and type(s) == 'string' then return escapeStr('[' .. t .. ':' .. s .. ']') end
    end

    return 'null'
end

-- Kahlua não implementa next() — usa pairs() para verificar tabela não-vazia
local function tableHasItems(t)
    for _ in pairs(t) do return true end
    return false
end

-- ── Captura segura de SandboxVars ────────────────────────────────────────────
-- Percorre dinamicamente todas as categorias disponíveis.
-- Categorias que falharem ao iterar são ignoradas (pcall em cada).

local function captureSandbox()
    local result = {}
    if type(SandboxVars) ~= 'table' then
        RankLog.warn("RankSandboxExport: SandboxVars nao e uma tabela")
        return result
    end

    for catKey, catVal in pairs(SandboxVars) do
        if type(catKey) == 'string' then
            local t = type(catVal)

            if t == 'table' then
                local sub = {}
                local ok, err = pcall(function()
                    for k, v in pairs(catVal) do
                        if type(k) == 'string' then
                            local vt = type(v)
                            if vt == 'number' or vt == 'boolean' or vt == 'string' then
                                sub[k] = v
                            elseif vt == 'table' then
                                -- Um nível extra (ex: ZombieConfig.SubTable)
                                local sub2 = {}
                                for k2, v2 in pairs(v) do
                                    local vt2 = type(v2)
                                    if type(k2) == 'string' and (vt2 == 'number' or vt2 == 'boolean' or vt2 == 'string') then
                                        sub2[k2] = v2
                                    end
                                end
                                if tableHasItems(sub2) then sub[k] = sub2 end
                            end
                        end
                    end
                end)
                if not ok then
                    RankLog.warn("RankSandboxExport: erro ao iterar " .. catKey .. ": " .. tostring(err))
                end
                if tableHasItems(sub) then result[catKey] = sub end

            elseif t == 'number' or t == 'boolean' or t == 'string' then
                -- Valor primitivo no nível raiz
                result[catKey] = catVal
            end
        end
    end

    return result
end

-- ── Timestamp real ─────────────────────────────────────────────────────────
local function systemTime()
    local ok, s = pcall(function() return os.date("%Y-%m-%dT%H:%M:%S") end)
    if ok and type(s) == 'string' and #s > 10 then return s end

    local ok2, ms = pcall(function()
        return luajava.bindClass('java.lang.System'):currentTimeMillis()
    end)
    if ok2 and ms then
        local t = math.floor(tonumber(tostring(ms)) / 1000)
        local ok3, s3 = pcall(function() return os.date("%Y-%m-%dT%H:%M:%S", t) end)
        if ok3 and type(s3) == 'string' then return s3 end
    end

    return '?'
end

-- ── Sanitiza nome de personagem para nome de arquivo ──────────────────────
local function sanitizeName(name)
    local s = (name or 'Sobrevivente'):gsub('[<>:"/\\|?*]', ''):gsub('%s+', '_')
    return (s ~= '' and s) or 'Sobrevivente'
end

-- ── Exportação principal ───────────────────────────────────────────────────
-- Chame com o nome do personagem (já sanitizado ou não).
-- Retorna true em sucesso, false em falha.

function RankSandboxExport.export(charName)
    local ok, err = pcall(function()
        local name      = sanitizeName(charName or 'Sobrevivente')
        local filePath  = 'pz_rank/pz_rank_sandbox_' .. name .. '.json'
        local sandboxData = captureSandbox()

        local payload = {
            type      = 'sandbox_config',
            version   = 1,
            character = charName or name,
            timestamp = systemTime(),
            sandbox   = sandboxData,
        }

        local json = encodeVal(payload)

        local w = getFileWriter(filePath, true, false)  -- overwrite (não acumular)
        if not w then error('getFileWriter retornou nil') end
        w:write(json)
        w:close()

        RankLog.info('RankSandboxExport: exportado -> ' .. filePath)
    end)

    if not ok then
        RankLog.error('RankSandboxExport.export falhou: ' .. tostring(err))
    end
    return ok
end