#!/bin/bash
# xdesligar_labold.sh — Desligar laboratório (versão gráfica)
# Sem lógica própria: janelas por cima de modulos/desligar_labold.sh
# (que arma o Wake-on-LAN de cada máquina antes de desligar).
cd "$(dirname "$0")/.." || exit 1
LAB_GUI=1
source modulos/_comum.sh && carregar_conf && exigir_ips || exit 1
source xmodulos/_xmotor.sh

zenity --question --title="🔌 Desligar Laboratório" --width=380 \
    --text="Desligar <b>todas</b> as máquinas online agora?" 2>/dev/null || exit 0
x_motor "Desligar Laboratório" "Desligando..." "" modulos/desligar_labold.sh --sim
