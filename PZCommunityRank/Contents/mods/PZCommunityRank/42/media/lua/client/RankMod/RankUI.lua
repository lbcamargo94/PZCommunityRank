-- ============================================================
--  RankUI.lua — Janela de resultado (B42.19+)
-- ============================================================

require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISTextEntryBox"
require "ISUI/ISLabel"
require "RankMod/RankLog"

RankSubmitUI = ISPanel:derive("RankSubmitUI")

local W   = 476
local PAD = 12
local iW  = W - PAD * 2
local COL2 = PAD + 150

-- Layout vertical
-- Seção de progresso: cabeçalho + 4 linhas (tempo, kills, profissão, status)
local BTN_W     = 140
local ROW_H     = 26
local PROG_SEC  = { y = ROW_H + 20, h = 100 }  -- y=46, h=100 (4 linhas)
local SEP_Y     = PROG_SEC.y + PROG_SEC.h + 8  -- 154
local H         = SEP_Y + 46                    -- 200

local function addRow(parent, x, y, key, value)
    local lKey = ISLabel:new(x, y, 16, key, 1, 1, 1, 1, UIFont.Small, true)
    lKey:initialise(); parent:addChild(lKey)
    local lVal = ISLabel:new(COL2, y, 16, value, 0.78, 0.78, 0.78, 1, UIFont.Small, false)
    lVal:initialise(); parent:addChild(lVal)
end

local function addSectionHeader(parent, x, y, text)
    local l = ISLabel:new(x, y, 16, text, 1, 1, 1, 1, UIFont.Small, true)
    l:initialise(); parent:addChild(l)
end

function RankSubmitUI:new(entry, code, playerIndex)
    playerIndex = playerIndex or 0

    -- getPlayerScreenWidth/Height retornam 0 para o slot de jogador morto no B42.19,
    -- posicionando o painel em coordenadas negativas (fora da tela).
    -- getCore():getScreenWidth/Height() sempre retorna as dimensões reais da janela.
    local screenW = getCore():getScreenWidth()
    local screenH = getCore():getScreenHeight()

    local x = (screenW / 2) - (W / 2)
    local y = (screenH / 2) - (H / 2)

    local o = ISPanel.new(self, x, y, W, H)
    o.entry       = entry
    o.code        = code
    o.playerIndex = playerIndex
    setmetatable(o, self)
    self.__index  = self
    return o
end

function RankSubmitUI:initialise()
    ISPanel.initialise(self)

    -- ── Linha: campo do código + botão selecionar ─────────────
    local boxW = iW - BTN_W - 6
    self.codeBox = ISTextEntryBox:new(self.code or "", PAD, PAD, boxW, ROW_H, self, false)
    self.codeBox:initialise(); self:addChild(self.codeBox)

    self.btnSelect = ISButton:new(PAD + boxW + 6, PAD, BTN_W, ROW_H,
        "selecionar código", self, RankSubmitUI.onSelectCode)
    self.btnSelect:initialise(); self:addChild(self.btnSelect)

    -- ── Seção: Progresso ──────────────────────────────────────
    local py = PROG_SEC.y
    local statusLabel = self.entry.is_dead and "Morto" or "Vivo"
    addSectionHeader(self, PAD + 4, py + 4,  "Progresso:")
    addRow(self, PAD + 4, py + 22, "Sobrevivência:",          self.entry.time_str or "?")
    addRow(self, PAD + 4, py + 40, "Zumbis mortos:",          tostring(self.entry.kills or 0))
    addRow(self, PAD + 4, py + 58, "Profissão:",              self.entry.profession or "Desconhecida")
    addRow(self, PAD + 4, py + 76, "Status:",                 statusLabel)

    -- ── Botão fechar ──────────────────────────────────────────
    self.btnClose = ISButton:new(W / 2 - 75, SEP_Y + 10, 150, 30,
        "Fechar", self, RankSubmitUI.onClose)
    self.btnClose:initialise(); self:addChild(self.btnClose)
end

function RankSubmitUI:onSelectCode()
    -- Foca o campo e seleciona todo o texto para o usuario pressionar Ctrl+C
    if self.codeBox and self.codeBox.focus then
        pcall(function() self.codeBox:focus() end)
    end
    if self.codeBox and self.codeBox.selectAll then
        pcall(function() self.codeBox:selectAll() end)
    end
end

function RankSubmitUI:onClose()
    self:removeFromUIManager()
end

function RankSubmitUI:render()
    ISPanel.render(self)

    local c = { 0.3, 0.3, 0.3 }

    self:drawRectBorder(PAD, PROG_SEC.y, iW, PROG_SEC.h, 1, c[1], c[2], c[3])
    self:drawRect(PAD, PROG_SEC.y + 18, iW, 1, 0.7, c[1], c[2], c[3])
    self:drawRect(PAD, SEP_Y, iW, 1, 0.7, c[1], c[2], c[3])
end

function RankSubmitUI.open(entry, code, playerIndex)
    local ui = RankSubmitUI:new(entry, code, playerIndex or 0)
    ui:initialise()
    ui:addToUIManager()
    RankLog.info("RankSubmitUI aberta: playerIndex=" .. (playerIndex or 0))
end
