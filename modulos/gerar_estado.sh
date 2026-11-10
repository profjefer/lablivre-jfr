#!/bin/bash

# gerar_estado.sh — Gera web/api.json com estado atual do laboratório
# Lê: ips_atuais.txt, configs/lablivre.conf, logs/modo_prova.status

cd "$(dirname "$0")/.." || exit 1

CONF_FILE="configs/lablivre.conf"
[ -f "$CONF_FILE" ] && source "$CONF_FILE"
LAB_NOME="${LAB_NOME:-LabLivre}"
LAB_NOME_JSON=$(printf '%s' "$LAB_NOME" | sed 's/\\/\\\\/g; s/"/\\"/g')

ARQUIVO_IPS="ips_atuais.txt"
FLAG_PROVA="logs/modo_prova.status"
API_JSON="web/api.json"

mkdir -p web 2>/dev/null

# Verifica se conseguimos escrever no web/
if [ ! -w web ]; then
    echo "[ERRO] Não tenho permissão de escrita em $(pwd)/web/" >&2
    echo "       Rode: sudo chown -R \$USER:\$USER $(pwd)/web/" >&2
    exit 1
fi

if [ -f "$ARQUIVO_IPS" ]; then
    IPS_UPDATED=$(stat -c '%y' "$ARQUIVO_IPS" 2>/dev/null | cut -d'.' -f1)
else
    IPS_UPDATED="never"
fi

IFACE=$(ip route | awk '/default/ {print $5}' | head -n 1)
SUBNET=$(ip -o -f inet addr show dev "$IFACE" 2>/dev/null | awk '{print $4}' | head -n 1)

if [ -f "$FLAG_PROVA" ]; then
    PROVA_ATIVO="true"
    PROVA_DESDE=$(cat "$FLAG_PROVA")
    PROVA_EXPIRA=""
    [ -s logs/modo_prova.expira ] && PROVA_EXPIRA=$(date -d "@$(cat logs/modo_prova.expira)" '+%d/%m/%Y %H:%M' 2>/dev/null)
else
    PROVA_ATIVO="false"
    PROVA_DESDE=""
    PROVA_EXPIRA=""
fi
PROVA_BLOQUEADAS=$(grep -c . logs/modo_prova.maquinas 2>/dev/null || true)
PROVA_PENDENTES=$(grep -c . logs/modo_prova.pendentes 2>/dev/null || true)

TOTAL=0; ONLINE=0; OFFLINE=0
MAQUINAS_JSON=""

if [ -f "$ARQUIVO_IPS" ]; then
    PRIMEIRO=true
    while read -r mac ip nome resto; do
        if [[ -z "$mac" ]]; then continue; fi

        ESTA="false"
        [[ "$resto" == *"(ESTA MÁQUINA)"* ]] && ESTA="true"
        VIA=""
        [[ "$resto" =~ \(via\ ([0-9a-f:]{17})\) ]] && VIA="${BASH_REMATCH[1]}"

        if [[ "$ip" == "OFFLINE" ]]; then
            STATUS="offline"
            ((OFFLINE++))
        else
            STATUS="online"
            ((ONLINE++))
        fi
        ((TOTAL++))

        NOME_ESC=$(echo "$nome" | sed 's/\\/\\\\/g; s/"/\\"/g')

        if [ "$PRIMEIRO" = true ]; then
            PRIMEIRO=false
        else
            MAQUINAS_JSON+=","
        fi

        MAQUINAS_JSON+=$(printf '{"mac":"%s","ip":"%s","nome":"%s","status":"%s","esta_maquina":%s,"via":"%s"}' \
            "$mac" "$ip" "$NOME_ESC" "$STATUS" "$ESTA" "$VIA")
    done < <(tail -n +3 "$ARQUIVO_IPS")
fi

cat > "$API_JSON" << EOF
{
  "lab": {
    "nome": "$LAB_NOME_JSON",
    "ips_atualizado_em": "$IPS_UPDATED"
  },
  "rede": {
    "total": $TOTAL,
    "online": $ONLINE,
    "offline": $OFFLINE,
    "interface": "$IFACE",
    "sub_rede": "$SUBNET"
  },
  "modo_prova": {
    "ativo": $PROVA_ATIVO,
    "desde": "$PROVA_DESDE",
    "expira": "$PROVA_EXPIRA",
    "bloqueadas": ${PROVA_BLOQUEADAS:-0},
    "pendentes": ${PROVA_PENDENTES:-0}
  },
  "maquinas": [$MAQUINAS_JSON],
  "ultima_atualizacao": "$(date -Iseconds)"
}
EOF

# Inventário ainda não coletado: página-aviso em vez do "Error 404"
if [ ! -f web/inventario.html ]; then
    cat > web/inventario.html <<'HTML'
<!DOCTYPE html><html lang="pt-BR"><head><meta charset="UTF-8"><title>LabLivre — Inventário</title>
<style>body{font-family:system-ui,sans-serif;background:#0a0a0f;color:#f5f5f7;display:grid;place-items:center;min-height:100vh;margin:0}
div{max-width:520px;text-align:center;padding:24px}h1{font-size:28px}p{color:#8b8b9b;line-height:1.6}a{color:#818cf8}</style></head>
<body><div><h1>📋 Inventário ainda não coletado</h1>
<p>Rode <b>Inventário de Hardware</b> (menu texto opção 4, ou menu gráfico opção 9) com as máquinas ligadas. Esta página é substituída pelo relatório.</p>
<p><a href="index.html">← Portal</a></p></div></body></html>
HTML
fi

echo "[OK] api.json gerado: $TOTAL máquinas ($ONLINE online, $OFFLINE offline)"
