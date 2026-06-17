# PZ Community Rank

Mod para **Project Zomboid Build 42+** que adiciona um sistema de ranking comunitário baseado em sobrevivência. Quando o personagem morre, o mod coleta as estatísticas da run e gera um código único que pode ser submetido ao site de ranking da comunidade.

---

## Funcionalidades

- Coleta automaticamente as estatísticas do personagem ao morrer
- Exibe uma janela com resumo da run (mortes, tempo sobrevivido, habilidades)
- Gera um código de submissão codificado para o ranking comunitário
- Acesso via menu de contexto (clique direito no mundo)
- Sem necessidade de internet ou configuração
- Integrado à UI nativa do jogo

## Dados coletados

- Nome do personagem
- Peso do personagem
- Tempo de sobrevivência (anos, dias, horas, minutos)
- Total de zumbis abatidos
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
4. Alternativamente, clique com o botão direito em qualquer objeto do mundo e acesse a opção **Gerar Rank**

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
            └── RankLog.lua    # Sistema de logs
```

## Formato do código de submissão

O código gerado segue o formato `PZRX1:<dados_codificados>`, onde os dados são codificados com XOR + Base64. A obfuscação é intencionalmente leve para garantir transparência — o objetivo é dificultar edições manuais, não esconder informações.

## Versão

**1.3.0** — compatível com Project Zomboid 42.19+

## Licença

Este projeto é distribuído como mod open-source para a comunidade de Project Zomboid.
