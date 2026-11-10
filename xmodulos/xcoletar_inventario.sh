#!/bin/bash
# xcoletar_inventario.sh — Inventário de hardware (versão gráfica)
# Sem lógica própria: janelas por cima de modulos/coletar_inventario.sh,
# que gera logs/inventario_lab.txt e web/inventario.html.
cd "$(dirname "$0")/.." || exit 1
LAB_GUI=1
source modulos/_comum.sh && carregar_conf && exigir_ips || exit 1
source xmodulos/_xmotor.sh

x_motor "Inventário de Hardware" "Coletando CPU, RAM, disco, GPU e BIOS..." "" modulos/coletar_inventario.sh

if zenity --question --title="Inventário" --width=400 \
    --text="Coleta concluída.\n\nAbrir a página do inventário no navegador?" \
    --ok-label="🌐 Abrir página" --cancel-label="📄 Ver TXT" 2>/dev/null; then
    abrir_pagina_web inventario.html >/dev/null
else
    zenity --text-info --title="Inventário (TXT)" --filename="logs/inventario_lab.txt" \
        --width=900 --height=600 --font="Monospace 10" 2>/dev/null
fi
