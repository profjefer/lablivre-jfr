#!/bin/bash
# ================================================================
# sincronizar_horario.sh — Acerta o relógio de todas as máquinas
#
# Menu texto (opção 16) e cron das 7h (sem perguntas, sem janelas).
# O trabalho em cada máquina é do modulos/remoto/sincronizar_horario.sh:
# ativa o NTP e, se o NTP não funcionar, usa a hora do orquestrador.
# ================================================================

cd "$(dirname "$0")/.." || exit 1

source modulos/_comum.sh && carregar_conf && exigir_ips || exit 1
source modulos/_log.sh 2>/dev/null || true
source modulos/_dryrun.sh "$@" 2>/dev/null || true

SCRIPT_REMOTO="modulos/remoto/sincronizar_horario.sh"
RELATORIO="logs/relatorio_horario.txt"
mkdir -p logs

echo "========================================================"
echo "         ⏰ SINCRONIZAR HORÁRIO DO LABORATÓRIO          "
echo "========================================================"

# Orquestrador primeiro: ele é a referência
if command -v timedatectl >/dev/null 2>&1; then
    SINC_LOCAL=$(timedatectl show -p NTPSynchronized --value 2>/dev/null)
    echo ">> Esta máquina: $(date '+%d/%m/%Y %H:%M:%S') — NTP sincronizado: ${SINC_LOCAL:-?}"
    if [ "$SINC_LOCAL" != "yes" ]; then
        echo "[AVISO] O relógio do orquestrador não está sincronizado por NTP."
        echo "        Ele será a referência das máquinas que não alcançarem NTP."
    fi
fi
echo "--------------------------------------------------------"

{
    echo "Sincronização de horário — $(date '+%d/%m/%Y %H:%M:%S')"
    echo "--------------------------------------------------------"
} > "$RELATORIO"

TOTAL=0; OK=0

sincronizar() {
    local mac="$1" ip="$2" nome="$3" saida rc st dif res
    ((TOTAL++))
    printf "Sincronizando: %-26s " "$nome ($ip)..."
    saida=$(rodar_remoto "$ip" "$SCRIPT_REMOTO" "$(date +%s)"); rc=$?
    st=$(status_remoto "$saida")
    dif=$(sed -n 's/^__DIFERENCA=//p' <<< "$saida" | tail -n 1)
    if lab_dryrun; then res="[DRY-RUN]"
    else
        case "$st" in
            OK)        res="[OK] diferença ${dif:-?}s"; ((OK++)) ;;
            AJUSTADO)  res="[AJUSTADO] estava ${dif}s fora; acertado pela hora do orquestrador"; ((OK++)) ;;
            ERRO_SUDO) res="[ERRO] sudo recusou a senha" ;;
            "")        res="[ERRO] $(erro_ssh "$rc")" ;;
            *)         res="[ERRO] não foi possível acertar o relógio" ;;
        esac
    fi
    echo "$res"
    echo "$nome ($ip): $res" >> "$RELATORIO"
}

para_cada_maquina sincronizar

echo "--------------------------------------------------------"
echo "[CONCLUÍDO] $OK de $TOTAL máquinas online com horário certo."
echo ">> Relatório: $RELATORIO"
echo "Resultado: $OK de $TOTAL" >> "$RELATORIO"
lab_dryrun || log_acao "sincronizar_horario" "ok=$OK de=$TOTAL" 2>/dev/null || true
