#!/bin/bash

# xlimpar_downloads.sh — Versão gráfica (Zenity) da limpeza de Downloads e Lixeira

cd "$(dirname "$0")/.." || exit 1

CONF_FILE="configs/lablivre.conf"
if [ -f "$CONF_FILE" ]; then
    source "$CONF_FILE"
else
    LAB_USUARIO="ufpr"
    LAB_SENHA="UFPR"
fi

source modulos/_log.sh 2>/dev/null || true
source modulos/_ssh.sh 2>/dev/null || true

ARQUIVO_IPS="ips_atuais.txt"
RELATORIO="logs/relatorio_limpeza.txt"
TMP_STATS="/tmp/lablivre_limpeza_stats.$$"
mkdir -p logs

if [ ! -f "$ARQUIVO_IPS" ]; then
    zenity --error --text="Arquivo de IPs não encontrado!\nExecute o mapeamento de rede primeiro." --width=300
    exit 1
fi

TOTAL_ALVO=$(tail -n +3 "$ARQUIVO_IPS" | awk '$2 != "OFFLINE" && $4 != "(ESTA" {c++} END {print c+0}')
[ "$TOTAL_ALVO" -eq 0 ] && TOTAL_ALVO=1

# Confirmação destrutiva
zenity --question \
    --title="Limpar Downloads e Lixeira" \
    --text="🧹 <b>Limpeza de Downloads e Lixeira</b>\n\nSerá apagado em <b>$TOTAL_ALVO máquinas online</b>:\n  • A pasta Downloads do usuário <b>$LAB_USUARIO</b>\n  • A Lixeira (Trash)\n\n⚠️ <b>Esta ação é DESTRUTIVA e irreversível.</b>\n\nDeseja continuar?" \
    --width=420 \
    --ok-label="🗑️ Sim, limpar tudo" \
    --cancel-label="Cancelar"

if [ $? -ne 0 ]; then
    exit 0
fi

# Cabeçalho do relatório
{
    echo "Relatório de Limpeza - $(date '+%d/%m/%Y %H:%M:%S')"
    echo "Usuário: $LAB_USUARIO"
    echo "--------------------------------------------------------"
} > "$RELATORIO"

CMD_REMOTO='
DL=$(xdg-user-dir DOWNLOAD 2>/dev/null)
[ -z "$DL" ] || [ "$DL" = "$HOME" ] && { for d in "Downloads" "Transferências" "Descargas"; do [ -d "$HOME/$d" ] && DL="$HOME/$d" && break; done; }
[ -z "$DL" ] && DL="$HOME/Downloads"
N_DL=0
if [ -d "$DL" ]; then
    N_DL=$(find "$DL" -mindepth 1 2>/dev/null | wc -l)
    rm -rf "$DL"/* "$DL"/.[!.]* 2>/dev/null
fi
N_TRASH=0
TRASH="$HOME/.local/share/Trash"
if [ -d "$TRASH" ]; then
    N_TRASH=$(find "$TRASH/files" -mindepth 1 2>/dev/null | wc -l)
    rm -rf "$TRASH/files"/* "$TRASH/files"/.[!.]* 2>/dev/null
    rm -rf "$TRASH/info"/* 2>/dev/null
fi
echo "ITENS_DOWNLOADS=$N_DL"
echo "ITENS_LIXEIRA=$N_TRASH"
'

: > "$TMP_STATS"

(
    ATUAL=0; SUCESSO=0; FALHA=0; TOTAL_ITENS=0

    while read -r mac ip nome resto; do
        [[ -z "$mac" ]] && continue
        [[ "$ip" == "OFFLINE" ]] && continue
        [[ "$resto" == *"(ESTA MÁQUINA)"* ]] && continue

        ((ATUAL++))
        PERCENT=$(( ATUAL * 100 / TOTAL_ALVO ))
        echo "$PERCENT"
        echo "# [$ATUAL/$TOTAL_ALVO] Limpando $nome ($ip)..."

        SAIDA=$( { echo "$CMD_REMOTO" | ssh_remote_stdin "$ip" "bash" 2>&1; echo "__RC=$?"; } )
        STATUS=$(echo "$SAIDA" | grep -o '__RC=[0-9]*' | cut -d= -f2)

        if [ "${STATUS:-1}" -eq 0 ]; then
            N_DL=$(echo "$SAIDA" | grep '^ITENS_DOWNLOADS=' | cut -d= -f2); N_DL=${N_DL:-0}
            N_TR=$(echo "$SAIDA" | grep '^ITENS_LIXEIRA=' | cut -d= -f2); N_TR=${N_TR:-0}
            TOTAL_ITENS=$((TOTAL_ITENS + N_DL + N_TR))
            echo "$nome ($ip): [OK] Downloads=$N_DL Lixeira=$N_TR" >> "$RELATORIO"
            ((SUCESSO++))
        else
            echo "$nome ($ip): [ERRO]" >> "$RELATORIO"
            ((FALHA++))
        fi
    done < <(tail -n +3 "$ARQUIVO_IPS")

    echo "100"
    echo "# Finalizando..."
    { echo "SUCESSO=$SUCESSO"; echo "FALHA=$FALHA"; echo "TOTAL_ITENS=$TOTAL_ITENS"; } > "$TMP_STATS"

) | zenity --progress \
    --title="Limpando Downloads e Lixeira" \
    --text="Iniciando..." \
    --percentage=0 --auto-close --auto-kill --width=480

STATUS_PIPE=${PIPESTATUS[1]}
if [ "$STATUS_PIPE" -ne 0 ]; then
    rm -f "$TMP_STATS"
    zenity --warning --text="Limpeza cancelada pelo usuário." --width=300
    exit 1
fi

# Lê stats do arquivo
if [ -f "$TMP_STATS" ]; then
    source "$TMP_STATS"
    rm -f "$TMP_STATS"
else
    SUCESSO=0; FALHA=0; TOTAL_ITENS=0
fi

log_acao "limpar_downloads" "maquinas=$SUCESSO itens=$TOTAL_ITENS" 2>/dev/null || true

zenity --info \
    --title="Limpeza Concluída" \
    --text="✅ <b>Limpeza finalizada!</b>\n\n🟢 <b>$SUCESSO</b> máquinas limpas\n🔴 <b>$FALHA</b> falharam\n🗑️ <b>$TOTAL_ITENS</b> itens apagados no total\n\n<i>Downloads e Lixeira do usuário $LAB_USUARIO</i>\n\nRelatório: logs/relatorio_limpeza.txt" \
    --width=420
