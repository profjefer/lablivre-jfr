#!/bin/bash

cd "$(dirname "$0")/.." || exit 1

CONF_FILE="configs/lablivre.conf"
if [ -f "$CONF_FILE" ]; then source "$CONF_FILE"; else LAB_USUARIO="ufpr"; LAB_SENHA="UFPR"; fi
ARQUIVO_IPS="ips_atuais.txt"

if [ ! -f "$ARQUIVO_IPS" ]; then
    zenity --error --text="Arquivo de IPs não encontrado!\nExecute o mapeamento de rede primeiro." --width=300
    exit 1
fi

zenity --question \
    --title="💊 Corrigir Repositórios Quebrados" \
    --text="Este script remove entradas problemáticas do APT (Dell, R, etc) em todas as máquinas online.\n\nDeseja continuar?" \
    --width=400

if [ $? -ne 0 ]; then exit 0; fi

TOTAL_MAQUINAS=$(tail -n +3 "$ARQUIVO_IPS" | grep -v -w "OFFLINE" | wc -l)
[ "$TOTAL_MAQUINAS" -eq 0 ] && TOTAL_MAQUINAS=1

CMD_REMOTO="echo '$LAB_SENHA' | sudo -S find /etc/apt/ -type f \
    -exec sed -i '/dell.archive.canonical.com/s/^/#/' {} + 2>/dev/null; \
    echo '$LAB_SENHA' | sudo -S find /etc/apt/ -type f \
    -exec sed -i '/cloud.r-project.org/s/^/#/' {} + 2>/dev/null; \
    echo '$LAB_SENHA' | sudo -S apt update >/dev/null 2>&1"

(
    ATUAL=0
    SUCESSO=0
    FALHA=0

    while read -r mac ip nome resto; do
        if [[ -z "$mac" ]] || [[ "$ip" == "OFFLINE" ]]; then continue; fi

        echo "# Vacinando: $nome ($ip)..."

        if [[ "$resto" == *"(ESTA MÁQUINA)"* ]]; then
            echo "$LAB_SENHA" | sudo -S find /etc/apt/ -type f \
                -exec sed -i '/dell.archive.canonical.com/s/^/#/' {} + 2>/dev/null
            echo "$LAB_SENHA" | sudo -S find /etc/apt/ -type f \
                -exec sed -i '/cloud.r-project.org/s/^/#/' {} + 2>/dev/null
            echo "$LAB_SENHA" | sudo -S apt update >/dev/null 2>&1
            ((SUCESSO++))
        else
            sshpass -p "$LAB_SENHA" ssh -n -q \
                -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
                "$LAB_USUARIO@$ip" "$CMD_REMOTO"
            [ $? -eq 0 ] && ((SUCESSO++)) || ((FALHA++))
        fi

        ((ATUAL++))
        PERCENT=$(( ATUAL * 100 / TOTAL_MAQUINAS ))
        echo "$PERCENT"
    done < <(tail -n +3 "$ARQUIVO_IPS")

    echo "100"
    echo "# Vacinação concluída!"
    echo "$SUCESSO|$FALHA" > /tmp/lablivre_vacina_stats.tmp

) | zenity --progress \
    --title="Corrigindo Repositórios APT" \
    --text="Aplicando vacina no APT do laboratório..." \
    --percentage=0 \
    --auto-close \
    --auto-kill \
    --width=450

if [ -f /tmp/lablivre_vacina_stats.tmp ]; then
    IFS='|' read -r SUCESSO FALHA < /tmp/lablivre_vacina_stats.tmp
    rm -f /tmp/lablivre_vacina_stats.tmp

    zenity --info \
        --title="Vacinação Concluída" \
        --text="✅ <b>Repositórios corrigidos!</b>\n\n🟢 $SUCESSO máquinas vacinadas\n🔴 $FALHA falhas\n\n<i>Repositórios problemáticos (Dell, R) foram comentados.</i>" \
        --width=400
fi
