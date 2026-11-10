#!/bin/bash

# gerar_mapa_calor.sh — Gera web/mapa_calor.json com estatísticas de uso por máquina
# Fonte: logs/historico_maquinas.jsonl (atualizado a cada mapeamento de rede)
# Cada linha do arquivo de origem: {"ts":"...","mac":"...","nome":"...","ip":"...","status":"online|offline"}

cd "$(dirname "$0")/.." || exit 1

CONF_FILE="configs/lablivre.conf"
[ -f "$CONF_FILE" ] && source "$CONF_FILE"
LAB_NOME="${LAB_NOME:-LabLivre}"

ARQUIVO_IPS="ips_atuais.txt"
HIST_MAQ="logs/historico_maquinas.jsonl"
SAIDA="web/mapa_calor.json"

mkdir -p logs web

# ===================================================================
# 1. Registra snapshot atual no histórico
# ===================================================================
if [ -f "$ARQUIVO_IPS" ]; then
    TS=$(date -Iseconds)
    while read -r mac ip nome resto; do
        [[ -z "$mac" ]] && continue
        STATUS="online"
        [[ "$ip" == "OFFLINE" ]] && STATUS="offline"
        printf '{"ts":"%s","mac":"%s","nome":"%s","ip":"%s","status":"%s"}\n' \
            "$TS" "$mac" "$nome" "$ip" "$STATUS" >> "$HIST_MAQ"
    done < <(tail -n +3 "$ARQUIVO_IPS")
fi

# Limita o histórico a 30 dias (10080 mapeamentos a cada hora)
if [ -f "$HIST_MAQ" ] && [ $(wc -l < "$HIST_MAQ") -gt 10080 ]; then
    tail -n 10080 "$HIST_MAQ" > "${HIST_MAQ}.tmp"
    mv "${HIST_MAQ}.tmp" "$HIST_MAQ"
fi

# ===================================================================
# 2. Agrega: para cada MAC, conta quantas vezes esteve online
# ===================================================================
if ! command -v jq >/dev/null 2>&1; then
    # Fallback sem jq: contagem usando grep
    echo "[!] jq não instalado. Usando fallback simples."
    USAR_JQ=false
else
    USAR_JQ=true
fi

MAQUINAS_JSON=""
TOTAL_OBSERVACOES=0
MAX_USO=0
TOTAL_MAQUINAS=0

if [ -f "$HIST_MAQ" ]; then
    TOTAL_OBSERVACOES=$(wc -l < "$HIST_MAQ")

    # Lista única de MACs vistos
    if [ "$USAR_JQ" = true ]; then
        MACS_UNICOS=$(jq -r '.mac' "$HIST_MAQ" 2>/dev/null | sort -u)
    else
        MACS_UNICOS=$(grep -oE '"mac":"[^"]*"' "$HIST_MAQ" | sort -u | sed 's/.*"\([^"]*\)"$/\1/')
    fi

    # Construir lista temporária com contadores
    declare -A USO_POR_MAC
    declare -A NOME_POR_MAC
    declare -A ULTIMO_TS_POR_MAC

    while IFS= read -r linha; do
        if [ "$USAR_JQ" = true ]; then
            MAC=$(echo "$linha" | jq -r '.mac' 2>/dev/null)
            STATUS=$(echo "$linha" | jq -r '.status' 2>/dev/null)
            NOME=$(echo "$linha" | jq -r '.nome' 2>/dev/null)
            TS=$(echo "$linha" | jq -r '.ts' 2>/dev/null)
        else
            MAC=$(echo "$linha" | grep -oE '"mac":"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
            STATUS=$(echo "$linha" | grep -oE '"status":"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
            NOME=$(echo "$linha" | grep -oE '"nome":"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
            TS=$(echo "$linha" | grep -oE '"ts":"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
        fi
        [ -z "$MAC" ] && continue
        NOME_POR_MAC[$MAC]="$NOME"
        ULTIMO_TS_POR_MAC[$MAC]="$TS"
        if [ "$STATUS" = "online" ]; then
            USO_POR_MAC[$MAC]=$((${USO_POR_MAC[$MAC]:-0} + 1))
            (( ${USO_POR_MAC[$MAC]} > MAX_USO )) && MAX_USO=${USO_POR_MAC[$MAC]}
        fi
    done < "$HIST_MAQ"

    [ $MAX_USO -eq 0 ] && MAX_USO=1

    PRIMEIRO=true
    for MAC in "${!NOME_POR_MAC[@]}"; do
        ((TOTAL_MAQUINAS++))
        USO=${USO_POR_MAC[$MAC]:-0}
        INTENSIDADE=$((USO * 100 / MAX_USO))
        if [ "$PRIMEIRO" = true ]; then
            PRIMEIRO=false
        else
            MAQUINAS_JSON+=","
        fi
        MAQUINAS_JSON+=$(printf '{"mac":"%s","nome":"%s","uso":%d,"intensidade":%d,"ultimo_visto":"%s"}' \
            "$MAC" "${NOME_POR_MAC[$MAC]}" "$USO" "$INTENSIDADE" "${ULTIMO_TS_POR_MAC[$MAC]}")
    done
fi

# ===================================================================
# 3. Grava JSON final
# ===================================================================
cat > "$SAIDA" << EOF
{
  "lab": "$LAB_NOME",
  "gerado_em": "$(date -Iseconds)",
  "observacoes_totais": $TOTAL_OBSERVACOES,
  "max_uso": $MAX_USO,
  "total_maquinas": $TOTAL_MAQUINAS,
  "maquinas": [$MAQUINAS_JSON]
}
EOF

chmod 644 "$SAIDA" 2>/dev/null
echo "[OK] mapa_calor.json gerado ($TOTAL_MAQUINAS máquinas, $TOTAL_OBSERVACOES observações)"
