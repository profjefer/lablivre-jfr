#!/bin/bash

# gerar_auditoria_json.sh — Converte auditoria.jsonl em web/auditoria.json
# Chamado pelo cron junto com gerar_estado.sh

cd "$(dirname "$0")/.." || exit 1

LOG="logs/auditoria.jsonl"
OUT="web/auditoria.json"
mkdir -p web

if [ ! -f "$LOG" ]; then
    echo "[]" > "$OUT"
    exit 0
fi

# Pega últimas 100 entradas, vira array JSON ordenado mais recente primeiro
python3 << PY > "$OUT"
import json
entradas = []
try:
    with open("$LOG") as f:
        for linha in f:
            linha = linha.strip()
            if not linha: continue
            try: entradas.append(json.loads(linha))
            except: pass
except Exception:
    pass
entradas = list(reversed(entradas))[:100]
print(json.dumps(entradas, ensure_ascii=False, indent=2))
PY

echo "[OK] auditoria.json gerada com $(wc -l < "$LOG") entradas totais"
