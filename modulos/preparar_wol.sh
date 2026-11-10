#!/bin/bash
# ================================================================
# preparar_wol.sh — Deixa o Wake-on-LAN permanente nas máquinas
#
#   bash modulos/preparar_wol.sh             → todas as online
#   bash modulos/preparar_wol.sh donatelo    → só as citadas
#
# Para máquina que "não liga pela rede" (ex.: desligada no botão ou
# por queda de energia, NetworkManager desarmando o WoL, ethtool
# faltando). Roda uma vez com as máquinas LIGADAS. O que este script
# não resolve é a BIOS (Wake on LAN / Power On by PCI-E / ErP).
# ================================================================

cd "$(dirname "$0")/.." || exit 1
source modulos/_comum.sh && carregar_conf && exigir_ips || exit 1
source modulos/_log.sh 2>/dev/null || true
source modulos/_dryrun.sh "$@" 2>/dev/null || true

ALVOS=()
for a in "$@"; do [[ "$a" == -* ]] || ALVOS+=("$a"); done

echo "========================================================"
echo "        ⚡ PREPARAR WAKE-ON-LAN (permanente)            "
echo "========================================================"
echo ">> Instala o ethtool se faltar, arma o WoL, cria o serviço que"
echo "   rearma a cada boot e ajusta o NetworkManager."
echo "--------------------------------------------------------"

TOTAL=0; OK=0; PROBLEMAS=()

preparar() {
    local mac="$1" ip="$2" nome="$3" saida rc status wol eth
    if [ "${#ALVOS[@]}" -gt 0 ] && [[ " ${ALVOS[*]} " != *" $nome "* ]]; then return; fi
    ((TOTAL++))
    printf "%-20s " "$nome"
    saida=$(rodar_remoto "$ip" modulos/remoto/preparar_wol.sh); rc=$?
    if lab_dryrun; then echo "[DRY-RUN]"; return; fi
    status=$(status_remoto "$saida")
    wol=$(sed -n 's/^__WOL=//p' <<< "$saida" | tail -n1)
    eth=$(sed -n 's/^__ETHTOOL=//p' <<< "$saida" | tail -n1)
    case "$status" in
        OK)          ((OK++)); echo "✅ WoL permanente · placas: $wol$([ "$eth" = instalado ] && echo ' · ethtool instalado agora')" ;;
        SEM_SUPORTE) echo "❌ nenhuma placa cabeada aceita WoL ($wol) — ver BIOS/placa"; PROBLEMAS+=("$nome: placa sem suporte (BIOS?)") ;;
        SEM_ETHTOOL) echo "❌ sem ethtool e a instalação falhou (sem internet/apt?)"; PROBLEMAS+=("$nome: instale o ethtool (menu 8)") ;;
        ERRO_SUDO)   echo "❌ sudo recusou a senha"; PROBLEMAS+=("$nome: sudo") ;;
        *)           echo "❌ $(erro_ssh "$rc")"; PROBLEMAS+=("$nome: $(erro_ssh "$rc")") ;;
    esac
}
para_cada_maquina preparar

echo "--------------------------------------------------------"
echo "Resumo: ✅ $OK de $TOTAL máquina(s) com WoL permanente."
if [ "${#PROBLEMAS[@]}" -gt 0 ]; then
    echo "🔴 Problemas:"; printf '   • %s\n' "${PROBLEMAS[@]}"
fi
echo "   'atual/suporta' = g/pumbg: g é o pacote mágico. Se mesmo assim não ligar,"
echo "   o que falta é a BIOS: Wake on LAN / Power On by PCI-E ligado, ErP / Deep Sleep desligado."
lab_dryrun || log_acao "preparar_wol" "ok=$OK de=$TOTAL" 2>/dev/null || true
