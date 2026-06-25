#!/bin/bash

# _log.sh — Função de log estruturado em JSON
# Uso: source modulos/_log.sh && log_acao "nome_acao" "detalhe1=valor1 detalhe2=valor2"

log_acao() {
    local acao="$1"
    local detalhes="${2:-}"
    local arquivo_log="${LABLIVRE_AUDIT_LOG:-logs/auditoria.jsonl}"
    local raiz_proj
    raiz_proj="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

    mkdir -p "$raiz_proj/logs"

    local ts=$(date -Iseconds)
    local usuario="${USER:-desconhecido}"
    local host=$(hostname)

    # Monta o campo detalhes em JSON a partir de "key1=val1 key2=val2"
    local det_json="{}"
    if [ -n "$detalhes" ]; then
        det_json="{"
        local first=true
        for pair in $detalhes; do
            local key="${pair%%=*}"
            local val="${pair#*=}"
            # Escapar aspas no valor
            val=$(echo "$val" | sed 's/\\/\\\\/g; s/"/\\"/g')

            if [ "$first" = true ]; then
                first=false
            else
                det_json+=","
            fi
            det_json+="\"$key\":\"$val\""
        done
        det_json+="}"
    fi

    # Linha JSON única (JSONL)
    printf '{"ts":"%s","host":"%s","usuario":"%s","acao":"%s","detalhes":%s}\n' \
        "$ts" "$host" "$usuario" "$acao" "$det_json" \
        >> "$raiz_proj/$arquivo_log"
}

# Função opcional: dump das últimas N entradas em formato legível
log_recentes() {
    local n="${1:-20}"
    local arquivo_log="${LABLIVRE_AUDIT_LOG:-logs/auditoria.jsonl}"
    local raiz_proj
    raiz_proj="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

    if [ ! -f "$raiz_proj/$arquivo_log" ]; then
        echo "Nenhuma entrada de auditoria ainda."
        return
    fi

    tail -n "$n" "$raiz_proj/$arquivo_log"
}
