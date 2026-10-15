#!/bin/bash
# ================================================================
# xsincronizar_horario.sh — Sincronizar horário (versão gráfica)
#
# Sem lógica própria: janela zenity por cima do motor do menu texto
# (modulos/sincronizar_horario.sh). O cron das 7h chama o motor
# direto, porque no cron não existe tela para o zenity.
# ================================================================

cd "$(dirname "$0")/.." || exit 1

LAB_GUI=1
source modulos/_comum.sh && carregar_conf && exigir_ips || exit 1

SAIDA=$(mktemp)
( bash modulos/sincronizar_horario.sh < /dev/null > "$SAIDA" 2>&1 ) &
PID=$!
(
    while kill -0 "$PID" 2>/dev/null; do
        echo "# $(grep -v '^\s*$' "$SAIDA" | tail -n 1)"
        sleep 0.5
    done
) | zenity --progress --pulsate --auto-close --no-cancel \
        --title="Sincronização de Horário" --text="Ajustando relógios..." --width=480
wait "$PID"

zenity --text-info --title="Sincronização de Horário — resultado" --width=720 --height=500 \
    --font="Monospace 10" --filename="$SAIDA" 2>/dev/null
rm -f "$SAIDA"
