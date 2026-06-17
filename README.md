# PZ Community Rank

Mod para **Project Zomboid Build 42+** que adiciona um sistema de ranking comunitário baseado em sobrevivência. Quando o personagem morre, o mod coleta as estatísticas da run e gera um código único que pode ser submetido ao site de ranking da comunidade.

---

## Funcionalidades

- Janela automática ao morrer com resumo completo da run
- Exportação automática do código em arquivo `.txt` a cada geração
- Status da run (vivo ou morto) incluído no código de submissão
- Acesso manual via menu de contexto (clique direito no mundo)
- Sem necessidade de internet ou configuração
- Integrado à UI nativa do jogo

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
3. Copie o código gerado e acesse o site da comunidade para submeter seu resultado
4. O código também é salvo automaticamente em arquivo `.txt` (veja **Arquivos gerados**)
5. Alternativamente, clique com o botão direito em qualquer objeto do mundo e acesse a opção **Gerar Rank**

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

## Formato do código de submissão

A partir da **v1.4.0**, o código gerado segue o formato `PZRX2:<dados_codificados>` (7 campos). O prefixo `PZRX1:` era o formato legado com 6 campos (sem o campo de status). O site (`src/app.ts`) deve verificar o prefixo para selecionar o parser correto.

Campos (formato `PZRX2:`): `PZR|nome|profissão|kills|minutos|habilidades|status`

Os dados são codificados com XOR + Base64. A obfuscação é intencionalmente leve — o objetivo é dificultar edições manuais, não esconder informações.

## Histórico de versões

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
