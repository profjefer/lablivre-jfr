# snapshot_diario.sh — Documentação

## O que faz

Captura **uma fotografia diária** do estado do laboratório e do uso da ferramenta, gravando essa fotografia em `logs/historico.jsonl`. Cada execução adiciona **uma linha JSON** ao arquivo, contendo:

- **`data`** — data da captura (ex: `2026-06-09`)
- **`total`** — total de máquinas conhecidas (do `ips_atuais.txt`)
- **`online`** — quantas estavam ligadas no momento da captura
- **`offline`** — quantas estavam desligadas
- **`provas_ativadas`** — quantas vezes o modo prova foi ativado HOJE
- **`manutencoes`** — quantas operações de manutenção (apt update/upgrade) HOJE
- **`distribuicoes`** — quantas distribuições de material HOJE

### Exemplo de linha gerada

```json
{"data":"2026-06-09","total":18,"online":12,"offline":6,"provas_ativadas":2,"manutencoes":1,"distribuicoes":4}
```

## Quando executa

Automaticamente pelo cron, **todo dia às 23h59**.

A linha de cron (instalada pelo `_provisionar.sh`):

```cron
59 23 * * * cd /opt/lablivre && bash modulos/snapshot_diario.sh >> logs/cron_snapshot.log 2>&1 # LabLivre
```

## Para que serve

O `historico.jsonl` funciona como uma **série temporal** do laboratório. A partir dele é possível:

- Gerar **gráficos longitudinais** (uso ao longo do semestre)
- Identificar **dias de pico** (quando o lab teve mais máquinas ligadas)
- Quantificar **avaliações** realizadas no período
- Avaliar **carga de manutenção** acumulada
- Servir como **fonte de dados** para futuros dashboards analíticos

## Como consultar manualmente

```bash
# Ver o histórico completo
cat logs/historico.jsonl

# Ver apenas o último dia
tail -1 logs/historico.jsonl | jq .

# Total de provas no mês de junho/2026
grep '"data":"2026-06' logs/historico.jsonl | jq '.provas_ativadas' | awk '{s+=$1} END {print s}'

# Dia com mais máquinas online no histórico
jq -s 'max_by(.online)' logs/historico.jsonl
```

## Fontes de dados

| Métrica | Fonte | Como |
|---------|-------|------|
| `total`, `online`, `offline` | `ips_atuais.txt` | Conta linhas e classifica por status |
| `provas_ativadas` | `logs/auditoria.jsonl` | Conta eventos `modo_prova_ativar` do dia |
| `manutencoes` | `logs/auditoria.jsonl` | Conta eventos `manutencao_sistema` do dia |
| `distribuicoes` | `logs/auditoria.jsonl` | Conta eventos `distribuir_material` do dia |

## Limitações conhecidas

1. **Não acumula** entradas do mesmo dia: se rodar duas vezes no mesmo dia, gera duas linhas duplicadas.
   - *Mitigação*: o cron está fixo às 23h59 para evitar conflito.
2. **Não detecta gaps**: se a máquina ficar desligada às 23h59 por vários dias, esses dias simplesmente não aparecem no histórico.
3. **Snapshot pontual**: representa o estado em um único momento do dia, não a média.

## Relação com `gerar_mapa_calor.sh`

São complementares mas distintos:

- **`snapshot_diario.sh`**: agrega 1 linha/dia sobre o lab inteiro
- **`gerar_mapa_calor.sh`**: registra 1 linha por máquina a cada mapeamento de rede em `logs/historico_maquinas.jsonl`, permitindo análise granular por máquina

Os dois alimentam diferentes dashboards e visualizações analíticas no portal web.
