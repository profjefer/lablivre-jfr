#!/bin/bash
# xligar_labold.sh — Ligar laboratório (versão gráfica)
# Sem lógica própria: janelas por cima de modulos/ligar_labold.sh.
cd "$(dirname "$0")/.." || exit 1
LAB_GUI=1
source modulos/_comum.sh || exit 1
source xmodulos/_xmotor.sh
[ -z "${LAB_ESPERA_LIGAR:-}" ] && LAB_ESPERA_LIGAR=$(sed -n 's/^LAB_ESPERA_LIGAR="\{0,1\}\([0-9]*\)"\{0,1\}[[:space:]]*$/\1/p' configs/lablivre.conf 2>/dev/null | tail -n 1)
ESPERA="${LAB_ESPERA_LIGAR:-20}"; [[ "$ESPERA" =~ ^[0-9]+$ ]] || ESPERA=20

if zenity --question --title="⚡ Ligar Laboratório" --width=420 \
    --text="Enviar Wake-on-LAN para todas as máquinas do macs.txt.\n\nEsperar ${ESPERA} s e conferir quem ligou?" \
    --ok-label="Enviar e conferir" --cancel-label="Só enviar" 2>/dev/null; then
    ARGS=(--esperar "$ESPERA")
else
    ARGS=(--sem-esperar)
fi
x_motor "Ligar Laboratório" "Enviando pacotes mágicos..." "" modulos/ligar_labold.sh "${ARGS[@]}"
