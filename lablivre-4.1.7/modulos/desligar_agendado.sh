#!/bin/bash

# desligar_agendado.sh
# Chamado pelo cron às 23h — desliga todos os PCs do lab silenciosamente
# Não desliga a máquina do professor (ESTA MÁQUINA)
# Log salvo em logs/cron_desligar.log

cd "$(dirname "$0")" || exit 1

CONF_FILE="configs/lablivre.conf"
if [ -f "$CONF_FILE" ]; then source "$CONF_FILE"; else LAB_USUARIO="ufpr"; LAB_SENHA="UFPR"; fi
source modulos/_ssh.sh 2>/dev/null || true
ARQUIVO_IPS="ips_atuais.txt"
LOG="logs/cron_desligar.log"
mkdir -p logs

echo "========================================================" >> "$LOG"
echo "DESLIGAMENTO AGENDADO — $(date '+%d/%m/%Y %H:%M:%S')" >> "$LOG"
echo "========================================================" >> "$LOG"

TOTAL=0
ERROS=0

while read -r mac ip nome resto; do
    if [[ -z "$mac" ]] || [[ "$ip" == "OFFLINE" ]] || [[ "$resto" == *"(ESTA MÁQUINA)"* ]]; then continue; fi

    ssh_remote "$ip" "echo '$LAB_SENHA' | sudo -S shutdown -h now 2>/dev/null"

    if [ $? -eq 0 ]; then
        echo "[OK]     $nome ($ip)" >> "$LOG"
    else
        echo "[ERRO]   $nome ($ip)" >> "$LOG"
        ((ERROS++))
    fi
    ((TOTAL++))
done < <(tail -n +3 "$ARQUIVO_IPS")

echo "Resultado: $((TOTAL - ERROS)) desligados, $ERROS erros de $TOTAL máquinas." >> "$LOG"
echo "" >> "$LOG"
