#!/bin/bash
# xligar_labold.sh — Ligar laboratório (versão gráfica)
# Sem lógica própria: janelas por cima de modulos/ligar_labold.sh.
cd "$(dirname "$0")/.." || exit 1
LAB_GUI=1
source modulos/_comum.sh || exit 1
source xmodulos/_xmotor.sh

if zenity --question --title="⚡ Ligar Laboratório" --width=420 \
    --text="Enviar Wake-on-LAN para todas as máquinas do macs.txt.\n\nEsperar 90 s e conferir quem ligou?" \
    --ok-label="Enviar e conferir" --cancel-label="Só enviar" 2>/dev/null; then
    ARGS=(--esperar 90)
else
    ARGS=(--sem-esperar)
fi
x_motor "Ligar Laboratório" "Enviando pacotes mágicos..." "" modulos/ligar_labold.sh "${ARGS[@]}"
