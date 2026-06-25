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

# 1. VALIDAÇÃO DO ARQUIVO DE MACS
if [ ! -f "$ARQUIVO_MACS" ]; then
    zenity --error \
        --title="Erro Crítico" \
        --text="Arquivo <b>$ARQUIVO_MACS</b> não encontrado!\n\nCrie o arquivo com a lista de MACs do laboratório.\nFormato: <i>aa:bb:cc:dd:ee:ff   nome-da-maquina</i>" \
        --width=450
    exit 1
fi

# 2. DESCOBERTA DE REDE
IFACE_ATIVA=$(ip route | awk '/default/ {print $5}' | head -n 1)
REDE_LAB=$(ip -o -f inet addr show dev "$IFACE_ATIVA" | awk '{print $4}' | head -n 1)

if [ -z "$REDE_LAB" ]; then
    zenity --error --title="Erro de Rede" --text="Não foi possível detectar a sub-rede da placa $IFACE_ATIVA." --width=350
    exit 1
fi

MEU_IP=$(hostname -I | awk '{print $1}')
MEU_MAC=$(ip link show dev "$IFACE_ATIVA" | awk '/ether/{print $2}' | head -n 1)
MEU_NOME=$(hostname)

# Conta máquinas válidas para a barra
TOTAL_LINHAS=$(grep -v -E "^$|^#|^-|^MAC|^mac" "$ARQUIVO_MACS" | wc -l)
[ "$TOTAL_LINHAS" -eq 0 ] && TOTAL_LINHAS=1

# ===================================================================
# 3. EXECUÇÃO COM BARRA DE PROGRESSO
# ===================================================================
(
    echo "10"
    echo "# Disparando varredura nmap na rede $REDE_LAB..."

    # Captura saída normal do nmap direto na variável (formato único que inclui MAC)
    SAIDA_NMAP=$(echo "$LAB_SENHA" | sudo -S nmap -sn -PR -PE "$REDE_LAB" 2>/dev/null)

    echo "35"
    echo "# Extraindo pares IP→MAC da saída do nmap..."

    # Parse: "Nmap scan report for IP" + "MAC Address: XX:XX:XX"
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

    echo "50"
    echo "# Cruzando MACs do macs.txt com os encontrados na rede..."

    # Monta arquivo de saída
    echo "MAC_ADDRESS        IP_ADDRESS       NOME_MAQUINA" > "$ARQUIVO_IPS"
    echo "------------------------------------------------" >> "$ARQUIVO_IPS"
    printf "%-18s %-16s %s (ESTA MÁQUINA)\n" "${MEU_MAC:-00:00:00:00:00:00}" "${MEU_IP:-127.0.0.1}" "$MEU_NOME" >> "$ARQUIVO_IPS"

    ATUAL=0
    ONLINE=0
    OFFLINE=0

    while read -r mac nome; do
        if [[ -z "$mac" ]] || [[ "$mac" == "#"* ]] || [[ "$mac" == "-"* ]] || [[ "${mac^^}" == "MAC"* ]]; then 
            continue
        fi

        # Busca case-insensitive na tabela do nmap
        IP_MATCH=$(echo "$TABELA_NMAP" | awk -v m="${mac,,}" '$2==m {print $1}' | head -n 1)

        if [ -n "$IP_MATCH" ]; then
            printf "%-18s %-16s %s\n" "$mac" "$IP_MATCH" "$nome" >> "$ARQUIVO_IPS"
            ((ONLINE++))
        else
            printf "%-18s %-16s %s\n" "$mac" "OFFLINE" "$nome" >> "$ARQUIVO_IPS"
            ((OFFLINE++))
        fi

        ((ATUAL++))
        PERCENT=$(( 50 + (ATUAL * 50 / TOTAL_LINHAS) ))
        echo "$PERCENT"
        echo "# Processando: $nome..."
        sleep 0.02
    done < "$ARQUIVO_MACS"

    echo "100"
    echo "# Mapeamento concluído!"

    # Stats temporários para o resumo
    echo "$ONLINE|$OFFLINE|$TOTAL_LINHAS" > /tmp/lablivre_stats.tmp

) | zenity --progress \
    --title="Mapeamento de Rede" \
    --text="Inicializando varredura em $REDE_LAB..." \
    --percentage=0 \
    --auto-close \
    --auto-kill \
    --width=450

if [ $? -ne 0 ]; then
    zenity --warning --title="Aviso" --text="Mapeamento cancelado pelo usuário." --width=300
    exit 1
fi

# ===================================================================
# 4. RESUMO FINAL
# ===================================================================
if [ -f /tmp/lablivre_stats.tmp ]; then
    IFS='|' read -r ONLINE OFFLINE TOTAL_LINHAS < /tmp/lablivre_stats.tmp
    rm -f /tmp/lablivre_stats.tmp

    zenity --info \
        --title="Mapeamento Concluído" \
        --text="✅ <b>Varredura finalizada!</b>\n\n🌐 <b>Rede:</b> $REDE_LAB\n🔌 <b>Interface:</b> $IFACE_ATIVA\n\n📊 <b>Resumo:</b>\n🟢 $ONLINE máquinas Online\n🔴 $OFFLINE máquinas Offline\n\n<i>Total processado: $TOTAL_LINHAS terminais.</i>" \
        --width=350
fi
