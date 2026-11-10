#!/bin/bash
# xlimpar_downloads.sh — Limpar Downloads e Lixeira (versão gráfica)
# Sem lógica própria: janelas por cima de modulos/limpar_downloads.sh.
# O resultado (quantas limparam, quais falharam e por quê) aparece na janela.
cd "$(dirname "$0")/.." || exit 1
LAB_GUI=1
source modulos/_comum.sh && carregar_conf && exigir_ips || exit 1
source xmodulos/_xmotor.sh

N=$(tail -n +3 "$ARQUIVO_IPS" | grep -v "(ESTA MÁQUINA)" | awk '$2!="OFFLINE"' | wc -l)
zenity --question --title="🧹 Limpar Downloads e Lixeira" --width=420 \
    --text="Apagar <b>definitivamente</b> a pasta Downloads e a Lixeira do usuário <b>$LAB_USUARIO</b> em <b>$N</b> máquina(s) online?\n\nNão dá para desfazer." \
    --ok-label="Apagar" --cancel-label="Cancelar" 2>/dev/null || exit 0
x_motor "Limpar Downloads" "Limpando as máquinas..." "SIM" modulos/limpar_downloads.sh
