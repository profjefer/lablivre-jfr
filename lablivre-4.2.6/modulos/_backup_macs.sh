#!/bin/bash

# _backup_macs.sh — Cria backup datado de configs/macs.txt
# Mantém últimos 30 backups. Chamado pelo configurar_lab + cron semanal.

cd "$(dirname "$0")/.." || exit 1

ORIGEM="configs/macs.txt"
DIR_BACKUP="configs/.backups"

[ ! -f "$ORIGEM" ] && exit 0
[ ! -s "$ORIGEM" ] && exit 0  # não fazer backup de arquivo vazio

mkdir -p "$DIR_BACKUP"

DESTINO="$DIR_BACKUP/macs_$(date '+%Y%m%d_%H%M%S').txt"

# Só faz backup se o conteúdo mudou desde o último backup
ULTIMO=$(ls -t "$DIR_BACKUP"/macs_*.txt 2>/dev/null | head -n 1)
if [ -n "$ULTIMO" ] && cmp -s "$ORIGEM" "$ULTIMO"; then
    exit 0  # idêntico, não precisa backup
fi

cp "$ORIGEM" "$DESTINO"

# Mantém só os últimos 30 backups
ls -t "$DIR_BACKUP"/macs_*.txt 2>/dev/null | tail -n +31 | xargs -r rm -f

echo "[backup] $DESTINO"
