# PZ Community Rank

Mod para **Project Zomboid Build 42+** que adiciona um sistema de ranking comunitário baseado em sobrevivência. Quando o personagem morre, o mod coleta as estatísticas da run e gera um código único que pode ser submetido ao site de ranking da comunidade.

---

## Funcionalidades

- Janela automática ao morrer com resumo completo da run
- Exportação automática do código em arquivo `.txt` a cada geração (morte, level up, save, a cada ~5 min)
- Status da run (vivo ou morto) incluído no código de submissão
- Acesso manual via menu de contexto (clique direito no mundo)
- Sem necessidade de internet ou configuração no jogo
- Integrado à UI nativa do jogo
- Integração com **PZ-Rank-Companion** — app que monitora a pasta e envia o código ao site automaticamente

## Dados coletados

- Nome do personagem
- Status: vivo (geração manual) ou morto (ao morrer)
- Tempo de sobrevivência (anos, dias, horas, minutos)
- Total de zumbis abatidos
- Profissão do personagem
- 35 habilidades: combate, artesanato, sobrevivência, culinária e mais

## Compatibilidade

| Build | Suporte |
|-------|---------|
| 42.19+ | ✔ Compatível |
| Build 41 e anteriores | ✗ Não suportado |

## Instalação

**Via Steam Workshop:**
1. Assine o mod na Steam Workshop
2. Ative-o nas opções de mods do Project Zomboid
3. Inicie uma nova partida

**Manual:**
1. Clone ou baixe este repositório
2. Copie a pasta `PZCommunityRank/Contents/mods/PZCommunityRank` para:
   - Windows: `%USERPROFILE%\Zomboid\mods\`
   - Linux: `~/.local/share/Zomboid/mods/`
3. Ative o mod no launcher do jogo

## Como usar

1. Jogue normalmente — o mod funciona em segundo plano
2. Quando seu personagem morrer, uma janela aparecerá automaticamente com as estatísticas da run
3. O código é copiado da janela e também salvo automaticamente em arquivo `.txt` (veja **Arquivos gerados**)
4. Use o **PZ-Rank-Companion** para sincronização automática: o app monitora a pasta e envia o código ao site sem intervenção manual
5. Alternativamente, clique com o botão direito em qualquer objeto do mundo e acesse **Gerar Rank** para gerar o código manualmente (personagem vivo)

O mod também gera arquivos silenciosos (sem abrir a janela) nas seguintes situações:

- Ao subir de nível em qualquer habilidade
- Ao salvar o jogo ou sair para o menu principal
- A cada ~5 minutos automaticamente

## Arquivos gerados

A cada código gerado (morte ou menu de contexto), o mod cria um arquivo `.txt` com o resumo da run:

```
Windows : %USERPROFILE%\Zomboid\Lua\pz_rank\
Linux   : ~/.local/share/Zomboid/Lua/pz_rank/
```

Nome do arquivo: `pz_rank_YYYY-MM-DD_HH-MM-SS_N.txt`

Conteúdo de exemplo:

```
=== PZ Community Rank ===
Data/Hora : 2026-06-17 14-30-45
Personagem: João Silva
Profissao : Desconhecida
Status    : Morto
Sobrev.   : 3 dias, 12h, 5m
Zumbis    : 47

--- Codigo de Submissao ---
PZRX2:...
```

O log interno do mod fica em `%USERPROFILE%\Zomboid\Lua\PZRank_log.txt` e registra cada etapa da coleta de dados — útil para diagnóstico em caso de problemas.

## Estrutura do projeto

```
PZCommunityRank/
└── Contents/mods/PZCommunityRank/
    └── 42/
        ├── mod.info
        └── media/lua/client/RankMod/
            ├── RankMain.lua   # Registro de eventos e ponto de entrada
            ├── RankData.lua   # Coleta de estatísticas do jogador
            ├── RankCode.lua   # Geração do código de submissão (XOR + Base64)
            ├── RankUI.lua     # Janela de exibição dos resultados
            ├── RankFile.lua   # Exportação do código para arquivo .txt
            └── RankLog.lua    # Sistema de logs
```

O sync com o site é feito pelo **PZ-Rank-Companion** (repositório separado), que monitora a pasta `pz_rank/` e envia o código via API. O mod em si não faz nenhuma requisição de rede.

## Formato do código de submissão

A partir da **v1.4.0**, o código gerado segue o formato `PZRX2:<dados_codificados>` (7 campos). O prefixo `PZRX1:` era o formato legado com 6 campos (sem o campo de status). O site (`src/app.ts`) deve verificar o prefixo para selecionar o parser correto.

Campos (formato `PZRX2:`): `PZR|nome|profissão|kills|minutos|habilidades|status`

Os dados são codificados com XOR + Base64. A obfuscação é intencionalmente leve — o objetivo é dificultar edições manuais, não esconder informações.

## Histórico de versões

### v1.6.0 — auto-sync sem rede no mod

**Novidades:**

- Geração automática de arquivos em 3 novos gatilhos: `Events.LevelPerk` (level up), `Events.OnSave` (save/saída) e `OnTick` periódico (~5 min)
- Deduplicação via `_lastSilentCode` — sem arquivos repetidos se o estado não mudou
- Integração com **PZ-Rank-Companion**: o app externo monitora a pasta e envia ao site

**Limpeza:**

- Removido bridge Java (`RankAPI.lua`, `RankModData.lua`, `RankingAPI.jar`) — `luajava` é null no client B42.19 e o código era 100% dead
- Removidos campos `weight_str` e `traits_str` de `RankData.collect()` — nunca exibidos na UI nem incluídos no código de submissão

---

### v1.4.0 — compatível com Project Zomboid 42.19+

**Novidades:**

- Janela de rank ao morrer corrigida para B42.19 (posição, temporizador e flag de controle)
- Campo `status` (`morto`/`vivo`) adicionado ao código de submissão (formato PZRX2)
- Exportação automática do código para arquivo `.txt` em `Lua/pz_rank/`

**Correções:**

- Janela era criada fora da tela após a morte (coordenadas negativas) — corrigido
- Temporizador de delay usava evento pausado durante tela de morte — corrigido
- Flag `submitted` bloqueava silenciosamente o disparo automático pós-morte — corrigido
- `RuntimeException` logados pelo PZ ao acessar métodos não registrados no bridge Kahlua — eliminados com guards de existência em todos os pontos críticos

## Licença

Este projeto é distribuído como mod open-source para a comunidade de Project Zomboid.
