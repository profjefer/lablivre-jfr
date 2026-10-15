#!/bin/bash
# ================================================================
# xmodo_prova.sh — Modo Prova (versão gráfica)
#
# Sem lógica própria: janelas zenity por cima do MESMO motor do menu
# texto (modulos/modo_prova.sh). Assim as duas interfaces aplicam o
# mesmo bloqueio (cadeia própria, persistente no boot, com validade).
# ================================================================

cd "$(dirname "$0")/.." || exit 1

LAB_GUI=1
source modulos/_comum.sh && carregar_conf && exigir_ips || exit 1

FLAG_PROVA="logs/modo_prova.status"
if [ -f "$FLAG_PROVA" ]; then
    STATUS_ATUAL="🔴 ATIVO desde $(cat "$FLAG_PROVA")"
    [ -f logs/modo_prova.expira ] && STATUS_ATUAL+=" — fim automático $(date -d "@$(cat logs/modo_prova.expira)" '+%d/%m %H:%M')"
else
    STATUS_ATUAL="🟢 Internet liberada"
fi

ACAO=$(zenity --list --title="🔒 Modo Prova" \
    --text="<b>Status:</b> $STATUS_ATUAL\n<i>Somente IPv4.</i>\n\nSelecione a ação:" \
    --radiolist --column="" --column="ID" --column="Ação" \
    TRUE  ativar    "🔴 Ativar (bloquear internet, manter rede local)" \
    FALSE liberar   "🟢 Liberar internet" \
    FALSE status    "🔍 Ver situação real em cada máquina" \
    FALSE reaplicar "♻️  Reaplicar nas máquinas que ligaram depois" \
    --hide-column=2 --print-column=2 --width=560 --height=330) || exit 0
[ -z "$ACAO" ] && exit 0

ARGS=("$ACAO")
if [ "$ACAO" = "ativar" ]; then
    HORAS=$(zenity --scale --title="Duração máxima" \
        --text="O bloqueio se desfaz sozinho depois de quantas horas?\n(mesmo que ninguém clique em Liberar)" \
        --min-value=1 --max-value=12 --value="${LAB_PROVA_HORAS:-4}" --step=1) || exit 0
    ARGS+=("$HORAS")
fi

SAIDA=$(mktemp)
( bash modulos/modo_prova.sh "${ARGS[@]}" < /dev/null > "$SAIDA" 2>&1 ) &
PID=$!
(
    while kill -0 "$PID" 2>/dev/null; do
        echo "# $(grep -v '^\s*$' "$SAIDA" | tail -n 1)"
        sleep 0.5
    done
) | zenity --progress --pulsate --auto-close --no-cancel \
        --title="Modo Prova" --text="Aplicando..." --width=480
wait "$PID"

zenity --text-info --title="Modo Prova — resultado" --width=720 --height=520 \
    --font="Monospace 10" --filename="$SAIDA" 2>/dev/null
rm -f "$SAIDA"
