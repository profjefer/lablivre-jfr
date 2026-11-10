#!/bin/bash
# ================================================================
# desligar_labold.sh — Desliga as máquinas online do laboratório
#
#   bash modulos/desligar_labold.sh               → pergunta e desliga todas
#   bash modulos/desligar_labold.sh --sim         → sem perguntar (menu gráfico)
#   bash modulos/desligar_labold.sh thor hulk     → só as máquinas citadas
#
# Antes de desligar, ARMA o Wake-on-LAN em cada máquina (ethtool
# wol g), para o "Ligar Laboratório" funcionar depois. O script
# remoto é modulos/remoto/desligar.sh (senha do sudo vai pelo stdin).
# ================================================================

cd "$(dirname "$0")/.." || exit 1

source modulos/_comum.sh && carregar_conf && exigir_ips || exit 1
source modulos/_log.sh 2>/dev/null || true
source modulos/_dryrun.sh "$@" 2>/dev/null || true

SIM=0; ALVOS=()
for a in "$@"; do
    case "$a" in
        --sim|-y) SIM=1 ;;
        --dry-run|-n) ;;
        *) ALVOS+=("$a") ;;
    esac
done

echo "========================================================"
echo "         🔌 DESLIGAR LABORATÓRIO (SHUTDOWN)             "
echo "========================================================"
if [ "$SIM" = 0 ] && [ -t 0 ] && ! lab_dryrun; then
    read -r -p "Desligar ${ALVOS[*]:-TODAS as máquinas online}? (s/N): " R
    [[ "${R,,}" == "s" ]] || { echo "Cancelado."; exit 0; }
fi
echo "--------------------------------------------------------"

TOTAL=0; OK=0; SEM_WOL=()

desligar() {
    local mac="$1" ip="$2" nome="$3" saida rc status wol
    if [ "${#ALVOS[@]}" -gt 0 ] && [[ " ${ALVOS[*]} " != *" $nome "* ]]; then return; fi
    ((TOTAL++))
    printf "Desligando: %-26s " "$nome ($ip)..."
    saida=$(rodar_remoto "$ip" modulos/remoto/desligar.sh)
    rc=$?
    status=$(status_remoto "$saida")
    wol=$(sed -n 's/^__WOL=//p' <<< "$saida" | tail -n 1)
    if lab_dryrun; then echo "[DRY-RUN]"; return; fi
    case "$status" in
        OK)        ((OK++)); echo "[OK] WoL: ${wol:-sem ethtool}"
                   [[ "$wol" == *:g* ]] || SEM_WOL+=("$nome") ;;
        ERRO_SUDO) echo "[ERRO] sudo recusou a senha" ;;
        *)         echo "[ERRO] $(erro_ssh "$rc")" ;;
    esac
}

para_cada_maquina desligar

echo "--------------------------------------------------------"
echo "[CONCLUÍDO] $OK de $TOTAL máquinas desligando."
if [ "${#SEM_WOL[@]}" -gt 0 ]; then
    echo "⚠️  Sem Wake-on-LAN armado (não vão ligar pela rede): ${SEM_WOL[*]}"
    echo "    Ligue-as e rode o menu 18 (Preparar Wake-on-LAN): instala o ethtool e deixa o WoL permanente."
    echo "    Se continuar, é a BIOS: 'Wake on LAN' / 'Power on by PCI-E' ativado e 'ErP/Deep Sleep' desativado."
fi
lab_dryrun || log_acao "desligar_lab" "desligadas=$OK de=$TOTAL" 2>/dev/null || true
