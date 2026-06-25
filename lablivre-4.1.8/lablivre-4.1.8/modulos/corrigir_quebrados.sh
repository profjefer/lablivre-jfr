#!/bin/bash

cd "$(dirname "$0")/.." || exit 1

CONF_FILE="configs/lablivre.conf"
if [ -f "$CONF_FILE" ]; then source "$CONF_FILE"; else LAB_USUARIO="ufpr"; LAB_SENHA="UFPR"; fi
source modulos/_log.sh 2>/dev/null || true
source modulos/_ssh.sh 2>/dev/null || true
ARQUIVO_IPS="ips_atuais.txt"

echo "========================================================"
echo "       🛠️  CORREÇÃO EM LOTE: REPOSITÓRIOS APT           "
echo "========================================================"
echo ">> Aplicando vacina no APT do laboratório. Aguarde..."
echo "--------------------------------------------------------"

CMD_REMOTO="echo '$LAB_SENHA' | sudo -S find /etc/apt/ -type f \
    -exec sed -i '/dell.archive.canonical.com/s/^/#/' {} + 2>/dev/null; \
    echo '$LAB_SENHA' | sudo -S apt update >/dev/null 2>&1"

while read -r mac ip nome resto; do
    if [[ -z "$mac" ]] || [[ "$ip" == "OFFLINE" ]]; then continue; fi

    echo -n "Vacinando: $nome ($ip)... "

    if [[ "$resto" == *"(ESTA MÁQUINA)"* ]]; then
        echo "$LAB_SENHA" | sudo -S find /etc/apt/ -type f \
            -exec sed -i '/dell.archive.canonical.com/s/^/#/' {} + 2>/dev/null
        echo "$LAB_SENHA" | sudo -S apt update >/dev/null 2>&1
        echo "[OK] (Local)"
    else
        ssh_remote "$ip" "$CMD_REMOTO"
        [ $? -eq 0 ] && echo "[OK]" || echo "[ERRO]"
    fi
done < <(tail -n +3 "$ARQUIVO_IPS")

echo "--------------------------------------------------------"
echo "[CONCLUÍDO] Repositório Dell desativado e APT limpo!"
log_acao "corrigir_quebrados" "" 2>/dev/null || true
