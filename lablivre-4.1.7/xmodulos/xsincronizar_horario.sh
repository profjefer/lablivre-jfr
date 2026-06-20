#!/bin/bash

# xsincronizar_horario.sh
# Sincroniza relógio do orquestrador + todas as máquinas do lab via SSH.
# Usa timedatectl (systemd-timesyncd) que vem padrão no Ubuntu moderno.
# Mantém ntpdate como fallback se timedatectl não estiver disponível.

cd "$(dirname "$0")/.." || exit 1

CONF_FILE="configs/lablivre.conf"
[ -f "$CONF_FILE" ] && source "$CONF_FILE"
source modulos/_ssh.sh 2>/dev/null || true

USUARIO_SSH="${LAB_USUARIO:-ufpr}"
SENHA_SSH="${LAB_SENHA:-UFPR}"
ARQUIVO_IPS="ips_atuais.txt"

# Comando de sincronização: tenta timedatectl primeiro, ntpdate como fallback
# Aceita a senha do sudo via stdin (echo $SENHA | sudo -S)
SYNC_CMD="echo '$SENHA_SSH' | sudo -S bash -c '
    if command -v timedatectl >/dev/null 2>&1; then
        timedatectl set-ntp true 2>/dev/null
        systemctl restart systemd-timesyncd 2>/dev/null
        echo SYNC_OK_TIMEDATECTL
    elif command -v ntpdate >/dev/null 2>&1; then
        ntpdate -u pool.ntp.org 2>&1
    else
        echo SYNC_FAIL_NO_TOOL
        exit 1
    fi
' 2>&1"

TOTAL_MAQUINAS=$(tail -n +3 "$ARQUIVO_IPS" 2>/dev/null | grep -v -w "OFFLINE" | wc -l)
[ "$TOTAL_MAQUINAS" -eq 0 ] && TOTAL_MAQUINAS=1

(
    echo "5"
    echo "# Sincronizando servidor local (orquestrador)..."

    # Sincroniza a própria máquina primeiro
    if command -v timedatectl >/dev/null 2>&1; then
        echo "$SENHA_SSH" | sudo -S timedatectl set-ntp true 2>/dev/null
        echo "$SENHA_SSH" | sudo -S systemctl restart systemd-timesyncd 2>/dev/null
    elif command -v ntpdate >/dev/null 2>&1; then
        echo "$SENHA_SSH" | sudo -S ntpdate -u pool.ntp.org >/dev/null 2>&1
    fi

    ATUAL=0
    SUCESSO=0
    FALHA=0

    while read -r mac ip nome resto; do
        if [[ -z "$mac" ]] || [[ "$ip" == "OFFLINE" ]] || [[ "$resto" == *"(ESTA MÁQUINA)"* ]]; then
            continue
        fi

        echo "# Sincronizando: $nome ($ip)..."

        SAIDA=$(ssh_remote "$ip" "$SYNC_CMD" 2>&1)
        STATUS=$?

        if [ $STATUS -eq 0 ] && [[ "$SAIDA" != *"FAIL"* ]]; then
            ((SUCESSO++))
        else
            ((FALHA++))
        fi

        ((ATUAL++))
        PERCENT=$(( 5 + (ATUAL * 95 / TOTAL_MAQUINAS) ))
        echo "$PERCENT"
    done < <(tail -n +3 "$ARQUIVO_IPS" 2>/dev/null)

    echo "100"
    echo "# Sincronização concluída!"
    echo "$SUCESSO|$FALHA" > /tmp/lablivre_sync_stats.tmp

) | zenity --progress \
    --title="Sincronização de Horário" \
    --text="Ajustando relógios via NTP..." \
    --percentage=0 \
    --auto-close \
    --auto-kill \
    --width=450

if [ -f /tmp/lablivre_sync_stats.tmp ]; then
    IFS='|' read -r SUCESSO FALHA < /tmp/lablivre_sync_stats.tmp
    rm -f /tmp/lablivre_sync_stats.tmp

    zenity --info \
        --title="Sincronização Concluída" \
        --text="✅ <b>Relógios sincronizados!</b>\n\n🟢 $SUCESSO máquinas OK\n🔴 $FALHA falhas\n\n<i>Método: $(command -v timedatectl >/dev/null && echo 'timedatectl (NTP automático)' || echo 'ntpdate (legado)')</i>" \
        --width=400
fi
