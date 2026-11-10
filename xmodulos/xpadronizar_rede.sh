#!/bin/bash
# xpadronizar_rede.sh — Padronizar rede (versão gráfica)
# Sem lógica própria: janelas por cima de modulos/padronizar_rede.sh.
# 1) mostra a situação (cabo, velocidade, wifi); 2) oferece desligar o
# wifi automático das máquinas que estão no cabo E no wifi.
cd "$(dirname "$0")/.." || exit 1
LAB_GUI=1
source modulos/_comum.sh && carregar_conf && exigir_ips || exit 1
source xmodulos/_xmotor.sh

x_motor "Padronizar Rede" "Verificando cabo e wifi das máquinas..." "" modulos/padronizar_rede.sh verificar
CANDIDATAS=$(sed -n 's/^📶 No cabo E no wifi ([0-9]*): //p' <<< "$X_SAIDA_TXT" | tail -n 1)
[ -n "$CANDIDATAS" ] || exit 0
N=$(wc -w <<< "$CANDIDATAS")
zenity --question --title="🌐 Padronizar Rede" --width=460 \
    --text="<b>$N</b> máquina(s) estão no cabo <b>e</b> no wifi:\n\n$CANDIDATAS\n\nSe o cabo falhar, elas seguem pelo wifi, somem do mapeamento e ficam fora do Modo Prova.\n\nDesligar a conexão automática do wifi nelas?\n(Só onde o cabo está funcionando. Dá para desfazer.)" \
    --ok-label="Desligar o wifi" --cancel-label="Deixar como está" 2>/dev/null || exit 0
# shellcheck disable=SC2086
x_motor "Padronizar Rede" "Desligando o wifi..." "" modulos/padronizar_rede.sh desligar-wifi $CANDIDATAS
