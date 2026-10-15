#!/bin/bash

# snapshot_diario.sh — Captura snapshot do estado do laboratório
# Roda no cron 1x por dia (23h59) e grava 1 linha em logs/historico.jsonl
# Cada linha é um JSON com: data, total, online, offline, prova_ativacoes

cd "$(dirname "$0")/.." || exit 1

ARQUIVO_IPS="ips_atuais.txt"
LOG_AUD="logs/auditoria.jsonl"
HISTORICO="logs/historico.jsonl"
HOJE=$(date '+%Y-%m-%d')

mkdir -p logs

# Contadores a partir do ips_atuais.txt
TOTAL=0; ONLINE=0; OFFLINE=0
if [ -f "$ARQUIVO_IPS" ]; then
    while read -r mac ip nome resto; do
        [[ -z "$mac" ]] && continue
        ((TOTAL++))
        [[ "$ip" == "OFFLINE" ]] && ((OFFLINE++)) || ((ONLINE++))
    done < <(tail -n +3 "$ARQUIVO_IPS")
fi

# Contadores a partir da auditoria do dia
PROVAS_ATIV=0
MANUTENCOES=0
DISTRIBUICOES=0
if [ -f "$LOG_AUD" ]; then
    PROVAS_ATIV=$(grep "\"ts\":\"$HOJE" "$LOG_AUD" | grep -c "modo_prova_ativar" || echo 0)
    MANUTENCOES=$(grep "\"ts\":\"$HOJE" "$LOG_AUD" | grep -c "manutencao_sistema" || echo 0)
    DISTRIBUICOES=$(grep "\"ts\":\"$HOJE" "$LOG_AUD" | grep -c "distribuir_material" || echo 0)
fi

printf '{"data":"%s","total":%d,"online":%d,"offline":%d,"provas_ativadas":%d,"manutencoes":%d,"distribuicoes":%d}\n' \
    "$HOJE" "$TOTAL" "$ONLINE" "$OFFLINE" "$PROVAS_ATIV" "$MANUTENCOES" "$DISTRIBUICOES" \
    >> "$HISTORICO"

echo "[snapshot] $HOJE: $ONLINE/$TOTAL online, $PROVAS_ATIV provas hoje"
