#!/bin/bash
# ================================================================
# modulos/remoto/receber_material.sh — roda NA MÁQUINA DO ALUNO
#
# Chamado pelo distribuir_material.sh como:
#     tar -cf - ... | ssh ... "bash -c '<este script>' _ NOME_SUBPASTA"
# O stdin é o tar (por isso o script vai como argumento, não pelo stdin).
#
# Detecta a Área de Trabalho de verdade (xdg-user-dir), com plano B
# para "Área de Trabalho", "Área de trabalho" e "Desktop", e extrai
# UMA vez só (o stdin não pode ser lido duas vezes).
#
# Saída: "__DEST=<pasta>" e "__RC=<código do tar>".
# ================================================================

SUBPASTA="${1:-Material_Aulas}"

BASE=$(xdg-user-dir DESKTOP 2>/dev/null)
# xdg-user-dir devolve o próprio $HOME quando não há Desktop configurado
if [ -z "$BASE" ] || [ "$BASE" = "$HOME" ] || [ ! -d "$BASE" ]; then
    BASE=""
    for d in "$HOME/Área de Trabalho" "$HOME/Área de trabalho" "$HOME/Desktop"; do
        if [ -d "$d" ]; then BASE="$d"; break; fi
    done
fi
[ -z "$BASE" ] && BASE="$HOME/Desktop"

DEST="$BASE/$SUBPASTA"
# Mostra com ~ no lugar do home (mais curto no relatório)
case "$DEST" in "$HOME"/*) echo "__DEST=~${DEST#"$HOME"}" ;; *) echo "__DEST=$DEST" ;; esac

if ! mkdir -p "$DEST" 2>/dev/null; then
    cat > /dev/null          # esvazia o tar para o SSH terminar limpo
    echo "__RC=90"
    exit 90
fi

tar -xf - -C "$DEST" --no-same-owner 2>&1
RC=$?
echo "__RC=$RC"
exit "$RC"
