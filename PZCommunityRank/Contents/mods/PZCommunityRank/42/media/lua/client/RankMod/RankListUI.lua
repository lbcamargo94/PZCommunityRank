-- ============================================================
--  RankListUI.lua - Tela de rank in-game (B42.19+)
--  Le pz_rank/pz_rank_rank.log escrito pelo PZ Rank Companion.
-- ============================================================

require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISLabel"
require "ISUI/ISScrollingListBox"
require "RankMod/RankLog"

-- ─── Painel principal ──────────────────────────────────────────────────────

RankListUI = ISPanel:derive("RankListUI")

local W   = 520
local H   = 480
local PAD = 12

-- Botões ficam NO TOPO (antes da lista) para nunca serem encobertos
local BTN_ROW_Y = PAD + 24        -- y dos botões de ação
local SEP1_Y    = BTN_ROW_Y + 32  -- separador abaixo dos botões
local HDR_Y     = SEP1_Y + 4      -- cabeçalhos de coluna
local SEP2_Y    = HDR_Y + 16      -- separador abaixo dos cabeçalhos
local LIST_Y    = SEP2_Y + 4      -- lista começa aqui
local LIST_H    = H - LIST_Y - PAD

local COLS = {
    { x =   2, w =  28, title = "#"       },
    { x =  36, w = 178, title = "Jogador" },
    { x = 220, w =  68, title = "Pontos"  },
    { x = 294, w = 110, title = "Tempo"   },
    { x = 410, w =  66, title = "Zumbis"  },
}

local function readRankFile()
    local entries    = {}
    local fileFound  = false
    pcall(function()
        local r = getFileReader("pz_rank/pz_rank_rank.log", false)
        if not r then return end
        fileFound = true
        local line = r:readLine()
        while line do
            if line ~= "" and line:sub(1, 1) ~= "#" then
                local pos, nick, _, score, _, time, kills =
                    line:match("^(%d+)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)$")
                if pos then
                    entries[#entries + 1] = {
                        pos   = tonumber(pos),
                        nick  = nick ~= "" and nick or "?",
                        score = tonumber(score) or 0,
                        time  = time  ~= "" and time  or "?",
                        kills = tonumber(kills) or 0,
                    }
                end
            end
            line = r:readLine()
        end
        r:close()
    end)
    return entries, fileFound
end

function RankListUI:new(playerIndex)
    local screenW = getCore():getScreenWidth()
    local screenH = getCore():getScreenHeight()
    local x = math.floor((screenW - W) / 2)
    local y = math.floor((screenH - H) / 2)
    local o = ISPanel.new(self, x, y, W, H)
    o.playerIndex = playerIndex or 0
    setmetatable(o, self)
    self.__index = self
    return o
end

function RankListUI:initialise()
    ISPanel.initialise(self)

    -- Título
    local title = ISLabel:new(PAD, PAD, 22,
        "PZ Community Rank", 1, 0.84, 0.2, 1, UIFont.Medium, true)
    title:initialise()
    self:addChild(title)

    -- Botões no topo (adicionados ANTES da lista para ficarem em cima na ordem de render)
    local btnW   = 145
    local gap    = 10
    local startX = math.floor((W - 2 * btnW - gap) / 2)

    local btnRefresh = ISButton:new(startX, BTN_ROW_Y, btnW, 26,
        "Atualizar", self, RankListUI.onRefresh)
    btnRefresh:initialise()
    self:addChild(btnRefresh)

    local btnClose = ISButton:new(startX + btnW + gap, BTN_ROW_Y, btnW, 26,
        "Fechar", self, RankListUI.onClose)
    btnClose:initialise()
    self:addChild(btnClose)

    -- Label de aviso (Companion desconectado)
    self.warnLabel = ISLabel:new(PAD, LIST_Y + 16, 20,
        "PZ Rank Companion nao encontrado.", 1, 0.55, 0, 1, UIFont.Small, false)
    self.warnLabel:initialise()
    self.warnLabel:setVisible(false)
    self:addChild(self.warnLabel)

    local self2 = self
    self.warnLabel2 = ISLabel:new(PAD, LIST_Y + 36, 20,
        "Abra o PZ Rank Companion e aguarde alguns segundos.", 0.85, 0.85, 0.85, 1, UIFont.Small, false)
    self.warnLabel2:initialise()
    self.warnLabel2:setVisible(false)
    self:addChild(self.warnLabel2)

    -- Lista (adicionada por último — ficará visualmente abaixo dos botões)
    self.list = ISScrollingListBox:new(PAD, LIST_Y, W - PAD * 2, LIST_H)
    self.list:initialise()
    self.list.drawBorder = true
    self.list.font       = UIFont.Small
    self.list.itemHeight = 22

    local panel = self
    self.list.doDrawItem = function(listbox, y2, item, alt)
        panel:drawRow(listbox, y2, item, alt)
    end
    self:addChild(self.list)

    self:populate()
end

function RankListUI:populate()
    self.list:clear()
    self.warnLabel:setVisible(false)
    self.warnLabel2:setVisible(false)
    self.list:setVisible(true)

    local entries, fileFound = readRankFile()

    if not fileFound then
        self.warnLabel:setVisible(true)
        self.warnLabel2:setVisible(true)
        self.list:setVisible(false)
        return
    end

    if #entries == 0 then
        self.list:addItem("Nenhum jogador no ranking ainda.", {})
    else
        for _, e in ipairs(entries) do
            self.list:addItem(e.nick, e)
        end
    end
end

function RankListUI:drawRow(listbox, y2, item, alt)
    local e = item.item
    if not e or not e.pos then return end

    local bg = alt and 0.08 or 0.03
    listbox:drawRect(0, y2, listbox.width, listbox.itemHeight, bg, 1, 1, 1)

    local r, g, b = 1, 1, 1
    if     e.pos == 1 then r, g, b = 1.0,  0.84, 0.2
    elseif e.pos == 2 then r, g, b = 0.85, 0.85, 0.85
    elseif e.pos == 3 then r, g, b = 0.8,  0.5,  0.2
    end

    local function draw(col, text)
        listbox:drawText(tostring(text or ""), col.x, y2 + 3, r, g, b, 1, UIFont.Small)
    end
    draw(COLS[1], e.pos)
    draw(COLS[2], e.nick)
    draw(COLS[3], e.score)
    draw(COLS[4], e.time)
    draw(COLS[5], e.kills)
end

function RankListUI:render()
    ISPanel.render(self)

    -- Separadores e cabeçalhos (só quando lista visível)
    if self.list:isVisible() then
        self:drawRect(PAD, SEP1_Y, W - PAD * 2, 1, 0.8, 0.3, 0.3, 0.3)
        for _, col in ipairs(COLS) do
            self:drawText(col.title, PAD + col.x, HDR_Y, 0.6, 0.6, 0.6, 1, UIFont.Small)
        end
        self:drawRect(PAD, SEP2_Y, W - PAD * 2, 1, 0.8, 0.3, 0.3, 0.3)
    end
end

function RankListUI:onRefresh()
    self:populate()
end

function RankListUI:onClose()
    self:removeFromUIManager()
end

function RankListUI.open(playerIndex)
    local ui = RankListUI:new(playerIndex or 0)
    ui:initialise()
    ui:addToUIManager()
    RankLog.info("RankListUI aberta: playerIndex=" .. tostring(playerIndex or 0))
end

-- ─── Botão lateral arrastável ──────────────────────────────────────────────
-- Sem ISButton filho: o painel inteiro responde a clique e drag.
-- Clique (sem movimento) → abre RankListUI.
-- Botão direito → menu Travar / Destravar.
-- Posição e estado de trava salvos no ModData do jogador.

RankSidePanel = ISPanel:derive("RankSidePanel")

local SB_W = 90
local SB_H = 26

function RankSidePanel:new(playerIndex, x, y, locked)
    local screenW = getCore():getScreenWidth()
    local screenH = getCore():getScreenHeight()
    x = x or (screenW - SB_W - 4)
    y = y or math.floor(screenH * 0.38)
    x = math.max(0, math.min(screenW - SB_W, x))
    y = math.max(0, math.min(screenH - SB_H, y))

    local o = ISPanel.new(self, x, y, SB_W, SB_H)
    o.playerIndex = playerIndex or 0
    o.locked      = locked == true
    o.dragging    = false
    o.didDrag     = false
    setmetatable(o, self)
    self.__index  = self
    return o
end

function RankSidePanel:initialise()
    ISPanel.initialise(self)
    self.background      = true
    self.borderColor     = { r = 0.4, g = 0.4, b = 0.4, a = 1 }
    self.backgroundColor = { r = 0.1, g = 0.1, b = 0.1, a = 0.88 }
end

function RankSidePanel:render()
    ISPanel.render(self)

    local label = "Ver Rank"
    local tw = getTextManager():MeasureStringX(UIFont.Small, label)
    local th = getTextManager():getFontHeight(UIFont.Small)
    local tx = math.floor((SB_W - tw) / 2)
    local ty = math.floor((SB_H - th) / 2)

    local r, g, b = 1, 1, 1
    if self.locked then
        -- borda laranja quando travado
        self:drawRectBorder(0, 0, SB_W, SB_H, 1, 0.8, 0.5, 0)
        r, g, b = 1, 0.82, 0.3
    end
    self:drawText(label, tx, ty, r, g, b, 1, UIFont.Small)
end

function RankSidePanel:onMouseDown(x, y)
    if not self.locked then
        self.dragging = true
        self.didDrag  = false
    end
    return true
end

function RankSidePanel:onMouseMove(dx, dy)
    if not self.dragging then return end
    local screenW = getCore():getScreenWidth()
    local screenH = getCore():getScreenHeight()
    local nx = math.max(0, math.min(screenW - self.width,  self:getX() + dx))
    local ny = math.max(0, math.min(screenH - self.height, self:getY() + dy))
    self:setX(nx)
    self:setY(ny)
    if math.abs(dx) > 1 or math.abs(dy) > 1 then
        self.didDrag = true
    end
end

function RankSidePanel:onMouseMoveOutside(dx, dy)
    self:onMouseMove(dx, dy)
end

function RankSidePanel:onMouseUp(x, y)
    local dragged = self.didDrag
    self.dragging = false
    self.didDrag  = false
    if not dragged then
        RankListUI.open(self.playerIndex)
    else
        self:savePosition()
    end
end

function RankSidePanel:onMouseUpOutside(x, y)
    if self.dragging then
        self.dragging = false
        if self.didDrag then self:savePosition() end
        self.didDrag = false
    end
end

function RankSidePanel:onRightMouseUp(x, y)
    local ax = self:getX() + x
    local ay = self:getY() + y
    local context = ISContextMenu.get(0, ax, ay)
    if not context then return end
    if self.locked then
        context:addOption("Destravar", self, RankSidePanel.unlock)
    else
        context:addOption("Travar aqui", self, RankSidePanel.lock)
    end
end

function RankSidePanel:lock()
    self.locked = true
    self:savePosition()
end

function RankSidePanel:unlock()
    self.locked = false
    self:savePosition()
end

function RankSidePanel:savePosition()
    pcall(function()
        local player = getPlayer()
        if not player then return end
        local md = player:getModData()
        md["PZRank_SidePanelX"]      = self:getX()
        md["PZRank_SidePanelY"]      = self:getY()
        md["PZRank_SidePanelLocked"] = self.locked
    end)
end

function RankSidePanel.loadPosition()
    local x, y, locked = nil, nil, false
    pcall(function()
        local player = getPlayer()
        if not player then return end
        local md = player:getModData()
        x = tonumber(md["PZRank_SidePanelX"])
        y = tonumber(md["PZRank_SidePanelY"])
        locked = md["PZRank_SidePanelLocked"] == true
    end)
    return x, y, locked
end

function RankSidePanel.show(playerIndex)
    local x, y, locked = RankSidePanel.loadPosition()
    local panel = RankSidePanel:new(playerIndex or 0, x, y, locked)
    panel:initialise()
    panel:addToUIManager()
    RankLog.info("RankSidePanel criado. locked=" .. tostring(locked))
    return panel
end
