#!/bin/bash

# Garante que o script localize a raiz do projeto
cd "$(dirname "$0")/.." || exit 1

CONF_FILE="configs/lablivre.conf"
if [ -f "$CONF_FILE" ]; then 
    source "$CONF_FILE"
else 
    LAB_USUARIO="ufpr"
    LAB_SENHA="UFPR"
fi

ARQUIVO_IPS="ips_atuais.txt"
ARQUIVO_MACS="configs/macs.txt"

echo "========================================================"
echo "           MAPEAMENTO DE REDE (MODO TEXTO)              "
echo "========================================================"

# 1. VALIDAÇÃO DA ÂNCORA DE HARDWARE
if [ ! -f "$ARQUIVO_MACS" ]; then
    echo "[ERRO CRÍTICO] Arquivo '$ARQUIVO_MACS' não encontrado!"
    echo ">> Crie o arquivo 'configs/macs.txt' com os MACs e nomes das máquinas."
    echo ">> Formato esperado (uma por linha):  aa:bb:cc:dd:ee:ff   PC01"
    exit 1
fi

# 2. DESCOBERTA DE REDE
IFACE_ATIVA=$(ip route | awk '/default/ {print $5}' | head -n 1)
REDE_LAB=$(ip -o -f inet addr show dev "$IFACE_ATIVA" | awk '{print $4}' | head -n 1)

if [ -z "$REDE_LAB" ]; then
    echo "[ERRO] Não foi possível detectar a sub-rede da placa $IFACE_ATIVA."
    exit 1
fi

MEU_IP=$(hostname -I | awk '{print $1}')
MEU_MAC=$(ip link show dev "$IFACE_ATIVA" | awk '/ether/{print $2}' | head -n 1)
MEU_NOME=$(hostname)

echo ">> Placa de rede principal: $IFACE_ATIVA"
echo ">> Sub-rede detectada: $REDE_LAB"
echo ">> Disparando varredura nmap. Aguarde..."
echo "--------------------------------------------------------"

# 3. VARREDURA: saída normal do nmap (sem -oG) — único formato que inclui MAC
# Captura direto na variável, sem arquivo temporário
SAIDA_NMAP=$(echo "$LAB_SENHA" | sudo -S nmap -sn -PR -PE "$REDE_LAB" 2>/dev/null)

# 4. PARSE: extrai pares "IP MAC" da saída normal do nmap
# "Nmap scan report for IP" ou "Nmap scan report for nome (IP)"
# "MAC Address: XX:XX:XX (fabricante)"
TABELA_NMAP=$(echo "$SAIDA_NMAP" | awk '
    /^Nmap scan report for/ {
        last = $NF
        gsub(/[()]/, "", last)
        ip = last
        mac = ""
    }
    /^MAC Address:/ {
        mac = tolower($3)
        print ip, mac
    }
')

echo ">> Máquinas encontradas pelo nmap:"
if [ -z "$TABELA_NMAP" ]; then
    echo "   [AVISO] Nenhuma entrada com MAC encontrada."
else
    echo "$TABELA_NMAP" | while read -r ip mac; do
        echo "   $mac -> $ip"
    done
fi
echo "--------------------------------------------------------"

# 5. MONTA O ARQUIVO DE IPS
echo "MAC_ADDRESS        IP_ADDRESS       NOME_MAQUINA" > "$ARQUIVO_IPS"
echo "------------------------------------------------" >> "$ARQUIVO_IPS"
printf "%-18s %-16s %s (ESTA MÁQUINA)\n" \
    "${MEU_MAC:-00:00:00:00:00:00}" "${MEU_IP:-127.0.0.1}" "$MEU_NOME" >> "$ARQUIVO_IPS"

TOTAL_MAQUINAS=0
TOTAL_ONLINE=0

# 6. CRUZAMENTO: para cada MAC do macs.txt, busca na tabela do nmap
while read -r mac nome; do
    # Pula linhas vazias, comentários e cabeçalho
    if [[ -z "$mac" ]] || [[ "$mac" == "#"* ]] || [[ "$mac" == "-"* ]] || [[ "${mac^^}" == "MAC"* ]]; then
        continue
    fi

    # Compara em minúsculo (nmap retorna maiúsculo, convertemos com tolower no awk acima)
    IP_MATCH=$(echo "$TABELA_NMAP" | awk -v m="${mac,,}" '$2==m {print $1}' | head -n 1)

    if [ -n "$IP_MATCH" ]; then
        printf "%-18s %-16s %s\n" "$mac" "$IP_MATCH" "$nome" >> "$ARQUIVO_IPS"
        echo "[ONLINE]  $nome ($IP_MATCH)"
        ((TOTAL_ONLINE++))
    else
        printf "%-18s %-16s %s\n" "$mac" "OFFLINE" "$nome" >> "$ARQUIVO_IPS"
        echo "[OFFLINE] $nome"
    fi
    ((TOTAL_MAQUINAS++))
done < "$ARQUIVO_MACS"

echo "--------------------------------------------------------"
echo "[CONCLUÍDO] $TOTAL_ONLINE online de $TOTAL_MAQUINAS máquinas em configs/macs.txt."


# 7. DETECÇÃO DE MACs NÃO CADASTRADOS (segurança)
# Lista todo MAC que apareceu no nmap mas NÃO está no macs.txt
DESCONHECIDOS=$(echo "$TABELA_NMAP" | awk -v meu_mac="${MEU_MAC,,}" -v meu_ip="${MEU_IP}" '
    NR==FNR {
        # Carrega MACs conhecidos do macs.txt
        if ($1 ~ /^[0-9a-fA-F:]+$/) { conhecidos[tolower($1)] = 1 }
        next
    }
    {
        mac = $2
        ip = $1
        if (!(mac in conhecidos) && mac != meu_mac && ip != meu_ip) {
            print "  • " mac " (" ip ")"
        }
    }
' "$ARQUIVO_MACS" -)

if [ -n "$DESCONHECIDOS" ]; then
    echo "--------------------------------------------------------"
    echo "⚠️  MACs encontrados na rede mas NÃO cadastrados em $ARQUIVO_MACS:"
    echo "$DESCONHECIDOS"
    echo "  (Visitantes, dispositivos pessoais, ou máquinas novas?)"
    # Salva em log para auditoria
    {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] MACs desconhecidos detectados:"
        echo "$DESCONHECIDOS"
    } >> logs/macs_desconhecidos.log
fi

# Regenera api.json e auditoria.json para os dashboards web
echo "[OK] Regenerando dados web..."
bash modulos/gerar_estado.sh 2>&1 | tail -1
bash modulos/gerar_auditoria_json.sh 2>&1 | tail -1 || true
bash modulos/gerar_mapa_calor.sh 2>&1 | tail -1 || true

# Verificação rápida: api.json existe e é válido?
if [ -f web/api.json ] && python3 -c "import json; json.load(open('web/api.json'))" 2>/dev/null; then
    echo "[OK] web/api.json gerado com sucesso."
else
    echo "[ERRO] web/api.json não foi gerado corretamente!"
    echo "       Verifique permissões: ls -la web/"
fi
