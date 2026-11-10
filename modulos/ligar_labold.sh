#!/bin/bash
# ================================================================
# ligar_labold.sh — Liga o laboratório por Wake-on-LAN
#
#   bash modulos/ligar_labold.sh                 → todas do macs.txt
#   bash modulos/ligar_labold.sh donatelo thor   → só as citadas
#   bash modulos/ligar_labold.sh --esperar 90    → espera e remapeia
#   bash modulos/ligar_labold.sh --sem-esperar   → só envia
#
# Desde 4.2.2:
#  * usa o macs.txt (todas as placas, inclusive a 2ª de cada máquina),
#    não o ips_atuais.txt — ligar não depende de mapear antes;
#  * manda 3 rodadas de pacotes, para 255.255.255.255 E para o
#    broadcast da sub-rede (alguns switches só repassam um dos dois);
#  * pode esperar as máquinas subirem, remapear a rede e dizer quem
#    NÃO ligou (com as causas mais comuns).
#
# Observação: o Wake-on-LAN DESTA máquina não importa para ENVIAR
# pacotes; importa o das máquinas dos alunos (BIOS + placa armada,
# o que o "Desligar Laboratório" faz antes de desligar).
# ================================================================

cd "$(dirname "$0")/.." || exit 1

source modulos/_comum.sh || exit 1
source modulos/_log.sh 2>/dev/null || true

RODADAS=3
ESPERAR=""          # vazio = perguntar (no terminal) | 0 = não | N = segundos
ALVOS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --esperar)     ESPERAR="${2:-90}"; shift ;;
        --sem-esperar) ESPERAR=0 ;;
        --dry-run|-n)  DRYRUN=1 ;;
        *)             ALVOS+=("$1") ;;
    esac
    shift
done

echo "========================================================"
echo "          ⚡ LIGAR LABORATÓRIO (WAKE-ON-LAN)            "
echo "========================================================"

if ! command -v wakeonlan >/dev/null 2>&1; then
    lab_erro "O pacote 'wakeonlan' não está instalado. Instale: sudo apt install wakeonlan"
    exit 1
fi
if [ ! -s "$ARQUIVO_MACS" ]; then
    lab_erro "configs/macs.txt vazio ou ausente — é ele que diz o MAC de cada máquina."
    exit 1
fi

IFACE=$(ip route show default 2>/dev/null | awk '{print $5; exit}')
BROADCAST=$(ip -o -f inet addr show dev "$IFACE" 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="brd"){print $(i+1); exit}}')
MEUS_MACS=" $( { cat /sys/class/net/*/address; ip link show dev "$IFACE" | awk '/ether/ {print $2}'; } 2>/dev/null | tr 'A-F\n' 'a-f ') "

# Lista "mac nome" (macs.txt), sem esta máquina e, se pedido, só os alvos
declare -A NOMES_ALVO=()
LISTA=()
while read -r mac nome _; do
    [[ "$mac" =~ ^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$ ]] || continue
    mac="${mac,,}"
    [[ "$MEUS_MACS" == *" $mac "* ]] && continue
    if [ "${#ALVOS[@]}" -gt 0 ] && [[ " ${ALVOS[*]} " != *" $nome "* ]]; then continue; fi
    [[ " ${LISTA[*]} " == *" $mac=$nome "* ]] && continue      # linha repetida
    LISTA+=("$mac=$nome"); NOMES_ALVO[$nome]=1
done < "$ARQUIVO_MACS"

if [ "${#LISTA[@]}" -eq 0 ]; then
    lab_erro "Nenhuma máquina para ligar (confira os nomes: ${ALVOS[*]:-macs.txt vazio})."
    exit 1
fi

echo ">> Placa $IFACE · broadcast ${BROADCAST:-?} · ${#NOMES_ALVO[@]} máquina(s), ${#LISTA[@]} placa(s)"
echo ">> Enviando $RODADAS rodadas de pacotes mágicos..."
echo "--------------------------------------------------------"
for r in $(seq 1 "$RODADAS"); do
    for item in "${LISTA[@]}"; do
        mac="${item%%=*}"; nome="${item#*=}"
        [ "$r" = 1 ] && printf "  %-20s %s\n" "$nome" "$mac"
        if [ "${DRYRUN:-0}" = 1 ]; then continue; fi
        wakeonlan "$mac" >/dev/null 2>&1
        [ -n "$BROADCAST" ] && wakeonlan -i "$BROADCAST" "$mac" >/dev/null 2>&1
    done
    [ "$r" -lt "$RODADAS" ] && sleep 1
done
echo "--------------------------------------------------------"
echo "[ENVIADO] Pacotes enviados para ${#NOMES_ALVO[@]} máquina(s)."
[ "${DRYRUN:-0}" = 1 ] || log_acao "ligar_lab" "maquinas=${#NOMES_ALVO[@]}" 2>/dev/null || true

# ----------------------------------------------------------------
# Espera e confere quem ligou
# ----------------------------------------------------------------
if [ -z "$ESPERAR" ]; then
    if [ -t 0 ]; then
        read -r -p "Esperar 90 s e conferir quem ligou? (S/n): " R
        [[ "${R,,}" == "n" ]] && ESPERAR=0 || ESPERAR=90
    else
        ESPERAR=0
    fi
fi
if [ "$ESPERAR" = 0 ] || [ "${DRYRUN:-0}" = 1 ]; then
    echo ">> As máquinas levam ~1 min para subir. Depois rode a opção 1 (Mapear Rede)."
    exit 0
fi

echo ">> Aguardando ${ESPERAR}s para as máquinas iniciarem..."
for ((s = ESPERAR; s > 0; s -= 10)); do
    echo "   ...faltam ${s}s"
    sleep $(( s < 10 ? s : 10 ))
done
echo ">> Remapeando a rede..."
bash modulos/atualizar_ips.sh < /dev/null > logs/ligar_mapeamento.log 2>&1

LIGARAM=(); NAO=()
for nome in "${!NOMES_ALVO[@]}"; do
    if tail -n +3 "$ARQUIVO_IPS" 2>/dev/null | awk -v n="$nome" '$3==n && $2!="OFFLINE"' | grep -q .; then
        LIGARAM+=("$nome")
    else
        NAO+=("$nome")
    fi
done
echo "--------------------------------------------------------"
echo "🟢 Ligaram (${#LIGARAM[@]}): $(printf '%s\n' "${LIGARAM[@]}" | sort | paste -sd' ' -)"
if [ "${#NAO[@]}" -gt 0 ]; then
    echo "🔴 Não responderam (${#NAO[@]}): $(printf '%s\n' "${NAO[@]}" | sort | paste -sd' ' -)"
    echo ""
    echo "   Causas mais comuns, nesta ordem:"
    echo "   1. Sem energia: filtro de linha/estabilizador desligado, cabo de força."
    echo "   2. BIOS: 'Wake on LAN' / 'Power On by PCI-E' desativado, ou 'ErP' / 'Deep"
    echo "      Sleep' ativado (corta a placa de rede quando desligada)."
    echo "   3. Desligada no botão ou por queda de energia: a placa pode ficar sem WoL"
    echo "      armado. Ligue uma vez na mão e desligue pelo LabLivre (opção Desligar),"
    echo "      que arma o WoL antes de desligar."
    echo "      → Mais simples: ligue na mão e rode o menu 18 (Preparar Wake-on-LAN) uma vez."
    echo "   4. Ligou, mas demorou: rode a opção 1 (Mapear Rede) daqui a pouco."
    echo "   5. Só na Wi-Fi ou cabo solto: WoL só funciona pelo cabo."
fi
