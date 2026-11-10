#!/bin/bash
# xdiagnosticar_ssh.sh — Diagnóstico SSH (versão gráfica)
# Sem lógica própria: janelas por cima de modulos/diagnosticar_ssh.sh.
# Remapeia antes, para não testar IPs velhos.
cd "$(dirname "$0")/.." || exit 1
LAB_GUI=1
source modulos/_comum.sh && carregar_conf || exit 1
source xmodulos/_xmotor.sh
x_motor "Diagnóstico SSH" "Mapeando e testando cada máquina..." "" modulos/diagnosticar_ssh.sh --remapear
