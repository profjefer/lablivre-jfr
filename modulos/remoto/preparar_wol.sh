#!/bin/bash
# ================================================================
# modulos/remoto/preparar_wol.sh — roda NA MÁQUINA DO ALUNO
#
# Deixa o Wake-on-LAN ligado de forma PERMANENTE:
#   1. instala o ethtool se faltar;
#   2. arma "wol g" em cada placa cabeada;
#   3. cria o serviço lablivre-wol (rearma a cada boot — cobre
#      desligar no botão, queda de energia, driver que esquece);
#   4. avisa o NetworkManager (802-3-ethernet.wake-on-lan magic),
#      que no Ubuntu desktop costuma desarmar o WoL sozinho.
#
# Saída: __WOL=<placa:atual/suporta ...>  __ETHTOOL=ja|instalado|falhou
#        __STATUS=OK | ERRO_SUDO | SEM_ETHTOOL | SEM_SUPORTE
# ================================================================

comosudo() {
    if sudo -n true 2>/dev/null; then sudo -n "$@"
    else printf '%s\n' "${SENHA:-}" | sudo -S -p '' "$@"; fi
}

comosudo true 2>/dev/null || { echo "__STATUS=ERRO_SUDO"; exit 1; }

# O ethtool fica em /usr/sbin, que nem sempre está no PATH do usuário.
# LAB_ETHTOOL_EXTRA permite trocar esses caminhos (os testes usam vazio).
acha_ethtool() {
    local f
    command -v ethtool 2>/dev/null && return 0
    for f in ${LAB_ETHTOOL_EXTRA-/usr/sbin/ethtool /sbin/ethtool}; do
        [ -x "$f" ] && { echo "$f"; return 0; }
    done
    return 1
}

if ETHTOOL=$(acha_ethtool); then
    echo "__ETHTOOL=ja"
else
    comosudo env DEBIAN_FRONTEND=noninteractive apt-get install -y -q ethtool >/dev/null 2>&1
    if ETHTOOL=$(acha_ethtool); then echo "__ETHTOOL=instalado"
    else echo "__ETHTOOL=falhou"; echo "__STATUS=SEM_ETHTOOL"; exit 1; fi
fi

placas=(); wol=""; algum_g=0
for dev in "${LAB_SYS_NET:-/sys/class/net}"/*; do
    nome="${dev##*/}"
    [ "$nome" = lo ] || [ -d "$dev/wireless" ] || [ ! -e "$dev/device" ] && continue
    comosudo "$ETHTOOL" -s "$nome" wol g >/dev/null 2>&1
    info=$(comosudo "$ETHTOOL" "$nome" 2>/dev/null)
    sup=$(awk '/Supports Wake-on:/ {print $3}' <<< "$info")
    atual=$(awk '/^[[:space:]]*Wake-on:/ {print $2}' <<< "$info")
    wol+="$nome:${atual:-?}/${sup:-?} "
    [[ "$sup" == *g* ]] && { placas+=("$nome"); [ "$atual" = g ] && algum_g=1; }
done
echo "__WOL=${wol% }"

if [ "${#placas[@]}" -eq 0 ]; then
    echo "__STATUS=SEM_SUPORTE"; exit 1
fi

# Serviço que rearma a cada boot
{
    echo "[Unit]"
    echo "Description=LabLivre: Wake-on-LAN sempre armado"
    echo "After=network.target"
    echo ""
    echo "[Service]"
    echo "Type=oneshot"
    for p in "${placas[@]}"; do echo "ExecStart=-$ETHTOOL -s $p wol g"; done
    echo ""
    echo "[Install]"
    echo "WantedBy=multi-user.target"
} > /tmp/lablivre-wol.service
comosudo install -m 644 /tmp/lablivre-wol.service /etc/systemd/system/lablivre-wol.service
rm -f /tmp/lablivre-wol.service
comosudo systemctl daemon-reload >/dev/null 2>&1
comosudo systemctl enable lablivre-wol.service >/dev/null 2>&1

# NetworkManager: grava "magic" nas conexões cabeadas
if command -v nmcli >/dev/null 2>&1; then
    while IFS=: read -r con tipo; do
        [ "$tipo" = "802-3-ethernet" ] || continue
        comosudo nmcli connection modify "$con" 802-3-ethernet.wake-on-lan magic >/dev/null 2>&1
    done < <(nmcli -t -f NAME,TYPE connection show 2>/dev/null)
fi

echo "__STATUS=OK"
