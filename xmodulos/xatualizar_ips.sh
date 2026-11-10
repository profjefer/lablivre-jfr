#!/bin/bash
# ================================================================
# xatualizar_ips.sh — Mapeamento de rede (versão gráfica)
#
# Não tem lógica própria: executa o MESMO motor do menu texto
# (modulos/atualizar_ips.sh) e mostra o resultado em janelas zenity.
# Assim texto e gráfico sempre geram o mesmo ips_atuais.txt.
# ================================================================

cd "$(dirname "$0")/.." || exit 1

LAB_GUI=1
source modulos/_comum.sh && carregar_conf || exit 1

SAIDA_TMP=$(mktemp)

# Sem terminal: o motor não pede senha interativa; se LAB_SENHA não
# servir para o sudo local, ele cai sozinho no modo ping + ARP.
( bash modulos/atualizar_ips.sh < /dev/null > "$SAIDA_TMP" 2>&1; echo $? > "$SAIDA_TMP.rc" ) &
PID_MOTOR=$!

(
    while kill -0 "$PID_MOTOR" 2>/dev/null; do
        ULTIMA=$(grep -v '^\s*$' "$SAIDA_TMP" | tail -n 1)
        echo "# ${ULTIMA:-Iniciando varredura...}"
        sleep 0.5
    done
) | zenity --progress --pulsate --auto-close \
        --title="Mapeamento de Rede" \
        --text="Varrendo a rede..." --width=480

if [ $? -ne 0 ]; then
    kill "$PID_MOTOR" 2>/dev/null
    rm -f "$SAIDA_TMP" "$SAIDA_TMP.rc"
    zenity --warning --title="Aviso" --text="Mapeamento cancelado. O ips_atuais.txt anterior foi mantido." --width=360
    exit 1
fi

wait "$PID_MOTOR" 2>/dev/null
RC=$(cat "$SAIDA_TMP.rc" 2>/dev/null || echo 1)

ONLINE=$(grep -c '^\[ONLINE\]' "$SAIDA_TMP")
OFFLINE=$(grep -c '^\[OFFLINE\]' "$SAIDA_TMP")
METODO=$(grep -m1 '^>> Método:' "$SAIDA_TMP" | sed 's/^>> Método: //')

if [ "$RC" -eq 0 ]; then
    TITULO="✅ Mapeamento concluído — 🟢 $ONLINE online · 🔴 $OFFLINE offline"
else
    TITULO="❌ Mapeamento falhou — o ips_atuais.txt anterior foi mantido"
fi

{ echo "$TITULO"; echo "Método: ${METODO:-?}"; echo; cat "$SAIDA_TMP"; } > "$SAIDA_TMP.view"
zenity --text-info --title="Mapeamento de Rede" --width=700 --height=560 \
    --font="Monospace 10" --filename="$SAIDA_TMP.view" 2>/dev/null

rm -f "$SAIDA_TMP" "$SAIDA_TMP.rc" "$SAIDA_TMP.view"
exit "$RC"
