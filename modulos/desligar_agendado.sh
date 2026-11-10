#!/bin/bash

# desligar_agendado.sh
# Chamado pelo cron às 23h — desliga todos os PCs do lab silenciosamente
# Não desliga a máquina do professor (ESTA MÁQUINA)
# Log salvo em logs/cron_desligar.log

cd "$(dirname "$0")/.." || exit 1

source modulos/_comum.sh && carregar_conf && exigir_ips || exit 1
source modulos/_dryrun.sh "$@" 2>/dev/null || true
LOG="logs/cron_desligar.log"
mkdir -p logs

echo "========================================================" >> "$LOG"
echo "DESLIGAMENTO AGENDADO — $(date '+%d/%m/%Y %H:%M:%S')" >> "$LOG"
echo "========================================================" >> "$LOG"

TOTAL=0
ERROS=0

desligar() {
    local mac="$1" ip="$2" nome="$3" saida status
    ((TOTAL++))
    saida=$(rodar_remoto "$ip" modulos/remoto/desligar.sh)
    status=$(status_remoto "$saida")
    if [ "$status" = OK ]; then
        echo "[OK]     $nome ($ip) $(sed -n 's/^__WOL=/WoL: /p' <<< "$saida")" >> "$LOG"
    else
        echo "[ERRO]   $nome ($ip) ${status:-sem resposta SSH}" >> "$LOG"
        ((ERROS++))
    fi
}
para_cada_maquina desligar

echo "Resultado: $((TOTAL - ERROS)) desligados, $ERROS erros de $TOTAL máquinas." >> "$LOG"
echo "" >> "$LOG"
