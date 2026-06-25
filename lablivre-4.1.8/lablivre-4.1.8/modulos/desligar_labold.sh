#!/bin/bash

cd "$(dirname "$0")/.." || exit 1

CONF_FILE="configs/lablivre.conf"
if [ -f "$CONF_FILE" ]; then source "$CONF_FILE"; else LAB_USUARIO="ufpr"; LAB_SENHA="UFPR"; fi
source modulos/_log.sh 2>/dev/null || true
source modulos/_ssh.sh 2>/dev/null || true
source modulos/_dryrun.sh 2>/dev/null || true
ARQUIVO_IPS="ips_atuais.txt"

echo "========================================================"
echo "         🔌 DESLIGAR LABORATÓRIO (SHUTDOWN)             "
echo "========================================================"
echo ">> Enviando comando de desligamento..."
echo "--------------------------------------------------------"

while read -r mac ip nome resto; do
    if [[ -z "$mac" ]] || [[ "$ip" == "OFFLINE" ]] || [[ "$resto" == *"(ESTA MÁQUINA)"* ]]; then continue; fi

    echo -n "Desligando: $nome ($ip)... "
    ssh_remote "$ip" "echo '$LAB_SENHA' | sudo -S shutdown -h now 2>/dev/null"
    [ $? -eq 0 ] && echo "[OK]" || echo "[ERRO]"
done < <(tail -n +3 "$ARQUIVO_IPS")

echo "--------------------------------------------------------"
echo "[CONCLUÍDO] Sinal de desligamento enviado."
log_acao "desligar_lab" "" 2>/dev/null || true
