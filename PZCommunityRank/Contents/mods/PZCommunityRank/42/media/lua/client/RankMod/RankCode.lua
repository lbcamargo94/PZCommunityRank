-- ============================================================
--  RankCode.lua - Gerador do codigo de submissao
--
--  Formato PZRX9 slim (v2.16+, 12 campos):
--  PZR|<nome>|<profissao>|<kills>|<minutos>|<skills>|<status>|<sandbox>|
--      <traits>|<motivo>|<ts>|<modver>|<death_cause>
--
--  <status>:     "morto" ou "vivo"
--  <sandbox>:    "ok" ou "invalido"
--  <traits>:     IDs separados por virgula (ex: "Athletic,Lucky,Smoker"); pode ser vazio
--  <death_cause>: string; vazio em syncs periodicos (so preenchido na morte)
--
--  Stats de conquistas (33 campos) agora ficam em arquivo separado:
--    pz_rank_stats_<personagem>.log  (gravado pelo RankFile.saveStats)
--  Nao sao enviados ao backend — consumo local pelo Companion apenas.
--
--  Formatos legados aceitos pelo backend (retrocompat.):
--    PZRX1: 6 campos (sem status/sandbox/traits)
--    PZRX2: 11 campos (sem extended stats)
--    PZRX3: 17 campos
--    PZRX4: 21 campos
--    PZRX5: 22 campos
--    PZRX6-PZRX8: ate 44 campos (sem death_cause)
--    PZRX9 v2.15: 45 campos (legado — substituido pelo slim acima)
--
--  IMPORTANTE: isto e OFUSCACAO, nao criptografia forte - o mod e
--  Lua aberto (Workshop) e o site e JS aberto no navegador, entao
--  a chave abaixo nao e secreta de verdade. Serve so para impedir
--  edicao casual do arquivo num editor de texto.
--
--  A XOR_KEY abaixo precisa ser IDENTICA a constante XOR_KEY em
--  src/app.ts no site, byte a byte.
-- ============================================================

require "RankMod/RankLog"

RankCode = {}

local MOD_VERSION = "2.16.1"
local XOR_KEY = "PZRank-Community-2026-Key!"
local B64_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

-- XOR de um byte sem operadores de bit (compativel com Kahlua/Lua 5.1)
local function byteXor(a, b)
    local result = 0
    local bitval = 1
    while a > 0 or b > 0 do
        local abit = a % 2
        local bbit = b % 2
        if abit ~= bbit then result = result + bitval end
        a = math.floor(a / 2)
        b = math.floor(b / 2)
        bitval = bitval * 2
    end
    return result
end

local function xorBytes(data, key)
    local out = {}
    local keyLen = #key
    for i = 1, #data do
        local dByte = string.byte(data, i)
        local kByte = string.byte(key, ((i - 1) % keyLen) + 1)
        out[i] = string.char(byteXor(dByte, kByte))
    end
    return table.concat(out)
end

local function base64Encode(data)
    local out = {}
    local len = #data
    local i = 1
    while i <= len do
        local b1 = string.byte(data, i)
        local b2 = string.byte(data, i + 1)
        local b3 = string.byte(data, i + 2)
        local n = b1 * 65536 + (b2 or 0) * 256 + (b3 or 0)

        local c1 = math.floor(n / 262144) % 64
        local c2 = math.floor(n / 4096) % 64
        local c3 = math.floor(n / 64) % 64
        local c4 = n % 64

        local chunk = {
            string.sub(B64_CHARS, c1 + 1, c1 + 1),
            string.sub(B64_CHARS, c2 + 1, c2 + 1),
            b2 and string.sub(B64_CHARS, c3 + 1, c3 + 1) or "=",
            b3 and string.sub(B64_CHARS, c4 + 1, c4 + 1) or "=",
        }
        table.insert(out, table.concat(chunk))
        i = i + 3
    end
    return table.concat(out)
end

local function base64Decode(str)
    str = str:gsub("%s+", "")

    local reverse = {}
    for i = 1, #B64_CHARS do
        reverse[string.sub(B64_CHARS, i, i)] = i - 1
    end

    local out = {}
    local len = #str
    local i = 1
    while i <= len do
        local s1 = string.sub(str, i, i)
        local s2 = string.sub(str, i + 1, i + 1)
        local s3 = string.sub(str, i + 2, i + 2)
        local s4 = string.sub(str, i + 3, i + 3)

        local c1 = reverse[s1] or 0
        local c2 = reverse[s2] or 0
        local c3 = reverse[s3]
        local c4 = reverse[s4]

        local n = c1 * 262144 + c2 * 4096 + (c3 or 0) * 64 + (c4 or 0)

        table.insert(out, string.char(math.floor(n / 65536) % 256))
        if s3 ~= "=" and s3 ~= "" then
            table.insert(out, string.char(math.floor(n / 256) % 256))
        end
        if s4 ~= "=" and s4 ~= "" then
            table.insert(out, string.char(n % 256))
        end
        i = i + 4
    end
    return table.concat(out)
end

local function obfuscate(plain)
    return base64Encode(xorBytes(plain, XOR_KEY))
end

local function deobfuscate(encoded)
    return xorBytes(base64Decode(encoded), XOR_KEY)
end

-- Retorna o timestamp Unix atual em segundos (campo 11 do payload).
-- Usado pelo backend para verificar freshness e detectar replay de codigos antigos.
local function unixTimestamp()
    -- luajava pode ser null no Kahlua VM em certos contextos; indexar null lanca
    -- RuntimeException Java que o pcall Lua nao captura — guarda aqui, fora do pcall.
    if luajava then
        local ok, ms = pcall(function()
            return luajava.bindClass("java.lang.System"):currentTimeMillis()
        end)
        if ok and ms then
            return math.floor(tonumber(tostring(ms)) / 1000)
        end
    end
    local ok2, t = pcall(os.time)
    if ok2 and t then return math.floor(t) end
    return 0
end

-- Gera o codigo slim (12 campos) a partir dos dados coletados.
-- PZRX9 slim (v2.16+): nome|profissao|kills|tempo|skills|status|sandbox|traits|motivo|ts|modVersion|death_cause
-- Stats de conquistas ficam em pz_rank_stats_<char>.log (gravado pelo RankFile.saveStats).
-- Campo sandbox: "ok" = configuracoes validas; "invalido" = violacao detectada
-- Campo motivo: "sandbox" | "debug" | "mods" | "" (vazio quando sandbox_ok=true)
-- Campo ts: Unix timestamp em segundos — detecta replay de codigos antigos
-- Campo death_cause: string; vazio em syncs periodicos (so preenchido na morte)
function RankCode.generate(entry)
    local skillsStr  = table.concat(entry.skills or {}, ",")
    local traitsStr  = table.concat(entry.traits or {}, ",")
    local charName   = (entry.character_name or "Sobrevivente"):gsub("|", " ")
    local profession = (entry.profession or "Desconhecida"):gsub("|", " ")
    local status     = entry.is_dead and "morto" or "vivo"
    local sandbox    = (entry.sandbox_ok == false) and "invalido" or "ok"
    local motivo     = (entry.sandbox_ok == false) and (entry.disqualification_reason or "sandbox") or ""
    local ts         = unixTimestamp()
    local deathCause = ((entry.death_cause or "")):gsub("|", " ")

    local plain = string.format("PZR|%s|%s|%d|%d|%s|%s|%s|%s|%s|%d|%s|%s",
        charName,
        profession,
        entry.kills or 0,
        entry.time_raw or 0,
        skillsStr,
        status,
        sandbox,
        traitsStr,
        motivo,
        ts,
        MOD_VERSION,
        deathCause
    )

    return "PZRX9:" .. obfuscate(plain)
end

-- Valida se uma string e um codigo PZRX1-PZRX8.
function RankCode.isValid(code)
    if not code or type(code) ~= "string" then return false end
    local prefix, encoded = code:match("^(PZRX[123456789]:)(.+)$")
    if not prefix then return false end

    local ok, plain = pcall(deobfuscate, encoded)
    if not ok or not plain then return false end

    return plain:match("^PZR|[^|]*|[^|]*|%d+|%d+|") ~= nil
end
