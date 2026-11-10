#!/bin/bash
# ================================================================
# modulos/remoto/desligar.sh — roda NA MÁQUINA DO ALUNO
#
#     ssh ... "bash -s --"      (SENHA do sudo prefixada no stdin)
#
# 1. Arma o Wake-on-LAN (ethtool wol g) em todas as placas cabeadas,
#    para a máquina poder ser LIGADA de novo pela rede. Sem isso,
#    várias placas desligam com WoL desativado e o "Ligar Lab" falha.
# 2. Agenda o desligamento para daqui a 2 s — assim o SSH volta com
#    o resultado antes da conexão cair.
#
# Saída: __WOL=<placa:estado ...>   __STATUS=OK | ERRO_SUDO
# ================================================================

comosudo() {
    if sudo -n true 2>/dev/null; then
        sudo -n "$@"
    else
        printf '%s\n' "${SENHA:-}" | sudo -S -p '' "$@"
    fi
}

principal() {
    local wol="" dev nome estado
    comosudo true 2>/dev/null || { echo "__STATUS=ERRO_SUDO"; return 1; }

    if command -v ethtool >/dev/null 2>&1; then
        for dev in /sys/class/net/*; do
            nome="${dev##*/}"
            [ "$nome" = lo ] && continue
            [ -d "$dev/wireless" ] && continue          # Wi-Fi não acorda por WoL
            [ -e "$dev/device" ] || continue            # só placas físicas
            comosudo ethtool -s "$nome" wol g >/dev/null 2>&1
            estado=$(comosudo ethtool "$nome" 2>/dev/null | awk '/^[[:space:]]*Wake-on:/ {print $2}')
            wol+="$nome:${estado:-?} "
        done
    fi
    echo "__WOL=${wol% }"

    echo "__STATUS=OK"      # antes: se a conexão cair no desligamento, o resultado já foi
    comosudo systemd-run --quiet --on-active=2 systemctl poweroff >/dev/null 2>&1 \
        || comosudo shutdown -h now >/dev/null 2>&1
}

principal "$@"
