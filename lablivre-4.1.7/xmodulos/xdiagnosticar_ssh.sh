#!/bin/bash

cd "$(dirname "$0")/.." || exit 1

CONF_FILE="configs/lablivre.conf"
if [ -f "$CONF_FILE" ]; then source "$CONF_FILE"; else LAB_USUARIO="ufpr"; LAB_SENHA="UFPR"; fi
ARQUIVO_IPS="ips_atuais.txt"
RELATORIO="logs/diagnostico_ssh.txt"
mkdir -p logs

if [ ! -f "$ARQUIVO_IPS" ]; then
    zenity --error --text="Arquivo de IPs não encontrado!\nExecute o mapeamento de rede primeiro." --width=300
    exit 1
fi

TOTAL_MAQUINAS=$(tail -n +3 "$ARQUIVO_IPS" | grep -v "ESTA MÁQUINA" | wc -l)
[ "$TOTAL_MAQUINAS" -eq 0 ] && TOTAL_MAQUINAS=1

{
    echo "========================================================"
    echo "    DIAGNÓSTICO SSH - $(date '+%d/%m/%Y %H:%M:%S')      "
    echo "========================================================"
} > "$RELATORIO"

(
    ATUAL=0
    OK=0
    PING_FAIL=0
    SSH_FAIL=0
    AUTH_FAIL=0

    while read -r mac ip nome resto; do
        if [[ -z "$mac" ]] || [[ "$resto" == *"(ESTA MÁQUINA)"* ]]; then continue; fi

        echo "# Testando: $nome ($ip)..."

        if [[ "$ip" == "OFFLINE" ]]; then
            echo "[OFFLINE]   $nome — não responde ping (no último mapeamento)" >> "$RELATORIO"
            ((PING_FAIL++))
        else
            # Testa ping
            if ! ping -c 1 -W 2 "$ip" > /dev/null 2>&1; then
                echo "[PING FAIL] $nome ($ip) — não responde ping" >> "$RELATORIO"
                ((PING_FAIL++))
            # Testa porta 22
            elif ! nc -z -w 2 "$ip" 22 > /dev/null 2>&1; then
                echo "[SSH FAIL]  $nome ($ip) — porta 22 fechada (SSH não está rodando)" >> "$RELATORIO"
                ((SSH_FAIL++))
            # Testa autenticação
            elif ! sshpass -p "$LAB_SENHA" ssh -n -q \
                    -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
                    "$LAB_USUARIO@$ip" "exit" 2>/dev/null; then
                echo "[AUTH FAIL] $nome ($ip) — SSH responde mas senha/usuário inválidos" >> "$RELATORIO"
                ((AUTH_FAIL++))
            else
                echo "[OK]        $nome ($ip) — tudo funcional" >> "$RELATORIO"
                ((OK++))
            fi
        fi

        ((ATUAL++))
        PERCENT=$(( ATUAL * 100 / TOTAL_MAQUINAS ))
        echo "$PERCENT"
    done < <(tail -n +3 "$ARQUIVO_IPS")

    echo "100"
    echo "# Diagnóstico concluído!"

    {
        echo ""
        echo "========================================================"
        echo "RESUMO:"
        echo "  ✅ $OK máquinas funcionais"
        echo "  💀 $PING_FAIL sem ping (desligadas/sem rede)"
        echo "  🔒 $SSH_FAIL com SSH fechado"
        echo "  🔑 $AUTH_FAIL com falha de autenticação"
        echo "========================================================"
    } >> "$RELATORIO"

    echo "$OK|$PING_FAIL|$SSH_FAIL|$AUTH_FAIL" > /tmp/lablivre_diag_stats.tmp

) | zenity --progress \
    --title="Diagnóstico SSH" \
    --text="Testando conectividade SSH em todas as máquinas..." \
    --percentage=0 \
    --auto-close \
    --auto-kill \
    --width=450

if [ -f /tmp/lablivre_diag_stats.tmp ]; then
    IFS='|' read -r OK PING_FAIL SSH_FAIL AUTH_FAIL < /tmp/lablivre_diag_stats.tmp
    rm -f /tmp/lablivre_diag_stats.tmp

    zenity --question \
        --title="Diagnóstico Concluído" \
        --text="📊 <b>Resumo:</b>\n\n✅ <b>$OK</b> funcionais\n💀 <b>$PING_FAIL</b> sem ping\n🔒 <b>$SSH_FAIL</b> SSH fechado\n🔑 <b>$AUTH_FAIL</b> falha de autenticação\n\nDeseja visualizar o relatório completo?" \
        --width=400

    if [ $? -eq 0 ]; then
        zenity --text-info \
            --title="Diagnóstico SSH Detalhado" \
            --filename="$RELATORIO" \
            --width=800 --height=600 \
            --font="Monospace 11"
    fi
fi
