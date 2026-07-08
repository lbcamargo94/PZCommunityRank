-- ============================================================
--  RankCode.lua - Gerador do codigo de submissao
--
--  Formato atual (antes da ofuscacao) - 9 campos:
--  PZR|<nome>|<profissao>|<kills>|<minutos>|<skills>|<status>|<sandbox>|<traits>
--
--  <status>:  "morto" ou "vivo"
--  <sandbox>: "ok" ou "invalido"
--  <traits>:  IDs separados por virgula (ex: "Athletic,Lucky,Smoker"); pode ser vazio
--
--  Prefixo "PZRX2:" (v1.4+, 9 campos). Prefixo "PZRX1:" era o
--  formato legado com 6 campos (sem status, sandbox ou traits).
--  O site (src/app.ts) deve checar o prefixo para saber o formato.
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

-- Gera o codigo (com prefixo de formato) a partir dos dados coletados
-- PZRX2: 9 campos - nome|profissao|kills|tempo|skills|status|sandbox|traits
-- Campo sandbox: "ok" = configuracoes validas; "invalido" = sandbox diverge do desafio
-- Campo traits: IDs separados por virgula (ex: "Athletic,Lucky,Smoker")
function RankCode.generate(entry)
    local skillsStr  = table.concat(entry.skills or {}, ",")
    local traitsStr  = table.concat(entry.traits or {}, ",")
    local charName   = (entry.character_name or "Sobrevivente"):gsub("|", " ")
    local profession = (entry.profession or "Desconhecida"):gsub("|", " ")
    local status     = entry.is_dead and "morto" or "vivo"
    local sandbox    = (entry.sandbox_ok == false) and "invalido" or "ok"

    local plain = string.format("PZR|%s|%s|%d|%d|%s|%s|%s|%s",
        charName,
        profession,
        entry.kills or 0,
        entry.time_raw or 0,
        skillsStr,
        status,
        sandbox,
        traitsStr
    )

    return "PZRX2:" .. obfuscate(plain)
end

-- Valida se uma string e um codigo PZRX1 (v1.3, 6 campos) ou PZRX2 (v1.4+, 7 campos).
function RankCode.isValid(code)
    if not code or type(code) ~= "string" then return false end
    local prefix, encoded = code:match("^(PZRX[12]:)(.+)$")
    if not prefix then return false end

    local ok, plain = pcall(deobfuscate, encoded)
    if not ok or not plain then return false end

    return plain:match("^PZR|[^|]*|[^|]*|%d+|%d+|") ~= nil
end

