#!/bin/bash

# gerar_estado.sh — Gera web/api.json com estado atual do laboratório
# Lê: ips_atuais.txt, configs/lablivre.conf, logs/modo_prova.status

cd "$(dirname "$0")/.." || exit 1

CONF_FILE="configs/lablivre.conf"
[ -f "$CONF_FILE" ] && source "$CONF_FILE"
LAB_NOME="${LAB_NOME:-LabLivre}"

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
else
    PROVA_ATIVO="false"
    PROVA_DESDE=""
fi

TOTAL=0; ONLINE=0; OFFLINE=0
MAQUINAS_JSON=""

if [ -f "$ARQUIVO_IPS" ]; then
    PRIMEIRO=true
    while read -r mac ip nome resto; do
        if [[ -z "$mac" ]]; then continue; fi

        ESTA="false"
        [[ "$resto" == *"(ESTA MÁQUINA)"* ]] && ESTA="true"

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

        MAQUINAS_JSON+=$(printf '{"mac":"%s","ip":"%s","nome":"%s","status":"%s","esta_maquina":%s}' \
            "$mac" "$ip" "$NOME_ESC" "$STATUS" "$ESTA")
    done < <(tail -n +3 "$ARQUIVO_IPS")
fi

cat > "$API_JSON" << EOF
{
  "lab": {
    "nome": "$LAB_NOME",
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
    "desde": "$PROVA_DESDE"
  },
  "maquinas": [$MAQUINAS_JSON],
  "ultima_atualizacao": "$(date -Iseconds)"
}
EOF

echo "[OK] api.json gerado: $TOTAL máquinas ($ONLINE online, $OFFLINE offline)"
