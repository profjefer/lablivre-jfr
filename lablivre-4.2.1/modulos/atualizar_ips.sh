#!/bin/bash
# ================================================================
# atualizar_ips.sh — Mapeia MAC → IP das máquinas do laboratório
#
# Gera ips_atuais.txt (na raiz do projeto), lido por TODOS os
# módulos (menu.sh e xmenu.sh) e regenera os JSON da web. Formato:
#   linha 1-2 : cabeçalho
#   linha 3   : esta máquina (orquestrador) + "(ESTA MÁQUINA)"
#   linha 4+  : MAC  IP|OFFLINE  NOME
#
# Varredura, em ordem de preferência:
#   1. arp-scan (root)      — mais confiável para MAC
#   2. nmap -sn -PR (root)  — fallback
#   3. ping sweep + ip neigh — sem root e sem pacotes extras
# Se NENHUM host responder (nem o gateway), a varredura é
# considerada falha e o ips_atuais.txt anterior é PRESERVADO.
# ================================================================

cd "$(dirname "$0")/.." || exit 1

source modulos/_comum.sh && carregar_conf || exit 1

ARQUIVO_IPS="ips_atuais.txt"
ARQUIVO_MACS="configs/macs.txt"
mkdir -p logs
LOG_SCAN="logs/atualizar_ips_$(date +%Y%m%d_%H%M%S).log"

echo "========================================================"
echo "           MAPEAMENTO DE REDE (MODO TEXTO)              "
echo "========================================================"

# ----------------------------------------------------------------
# 1. VALIDAÇÃO DO macs.txt
# ----------------------------------------------------------------
if [ ! -f "$ARQUIVO_MACS" ]; then
    echo "[ERRO CRÍTICO] Arquivo '$ARQUIVO_MACS' não encontrado!"
    echo ">> Formato esperado (uma por linha):  aa:bb:cc:dd:ee:ff   PC01"
    exit 1
fi

# Máquina com mais de uma placa (cabo + wifi): repita o NOME em outra
# linha. A PRIMEIRA linha é o MAC principal (cabo) — é ele que vai
# para o ips_atuais.txt e é usado pelo Wake-on-LAN.
#   d0:94:66:e1:81:57   lula-molusco      # cabo (principal)
#   48:ad:9a:88:3a:92   lula-molusco      # wifi
RE_MAC='^([0-9a-f]{2}:){5}[0-9a-f]{2}$'
declare -a LISTA_NOME          # nomes únicos, na ordem do arquivo
declare -A VISTO_MAC           # mac  -> nome (todas as placas)
declare -A MAC_PRINCIPAL       # nome -> mac principal
declare -A MACS_EXTRAS         # nome -> macs secundários (separados por espaço)
AVISOS=0
TOTAL_EXTRAS=0

while read -r mac nome _; do
    [[ -z "$mac" || "$mac" == "#"* || "$mac" == "-"* || "${mac^^}" == "MAC"* ]] && continue
    mac="${mac,,}"
    if [[ ! "$mac" =~ $RE_MAC ]]; then
        echo "[AVISO] MAC inválido no macs.txt, ignorado: '$mac' ($nome)"
        ((AVISOS++)); continue
    fi
    if [ -z "$nome" ]; then
        echo "[AVISO] MAC $mac sem nome no macs.txt, ignorado."
        ((AVISOS++)); continue
    fi
    if [ -n "${VISTO_MAC[$mac]}" ]; then
        echo "[AVISO] MAC duplicado: $mac ('${VISTO_MAC[$mac]}' e '$nome') — mantido só '${VISTO_MAC[$mac]}'"
        ((AVISOS++)); continue
    fi
    VISTO_MAC[$mac]="$nome"
    if [ -n "${MAC_PRINCIPAL[$nome]}" ]; then
        MACS_EXTRAS[$nome]+=" $mac"
        ((TOTAL_EXTRAS++))
    else
        MAC_PRINCIPAL[$nome]="$mac"
        LISTA_NOME+=("$nome")
    fi
done < "$ARQUIVO_MACS"

if [ "${#LISTA_NOME[@]}" -eq 0 ]; then
    echo "[ERRO] Nenhum MAC válido em '$ARQUIVO_MACS'."
    exit 1
fi
echo ">> macs.txt: ${#LISTA_NOME[@]} máquinas, $TOTAL_EXTRAS placa(s) extra(s) ($AVISOS aviso(s))"

# ----------------------------------------------------------------
# 2. DESCOBERTA DA REDE LOCAL
# ----------------------------------------------------------------
IFACE_ATIVA=$(ip route show default 2>/dev/null \
    | awk '$5 !~ /^(lo|tun|tap|docker|virbr|br-|veth)/ {print $5; exit}')
if [ -z "$IFACE_ATIVA" ]; then
    echo "[ERRO] Nenhuma rota padrão encontrada. Verifique: ip route"
    exit 1
fi

REDE_LAB=$(ip -o -f inet addr show dev "$IFACE_ATIVA" | awk '{print $4; exit}')
if [ -z "$REDE_LAB" ]; then
    echo "[ERRO] Não foi possível detectar a sub-rede da placa $IFACE_ATIVA."
    exit 1
fi

MEU_IP="${REDE_LAB%/*}"
MEU_MAC=$(ip link show dev "$IFACE_ATIVA" | awk '/ether/ {print tolower($2); exit}')
MEU_NOME=$(hostname)
# Se esta máquina está no macs.txt, usa o nome cadastrado
[ -n "$MEU_MAC" ] && [ -n "${VISTO_MAC[$MEU_MAC]}" ] && MEU_NOME="${VISTO_MAC[$MEU_MAC]}"

echo ">> Placa de rede : $IFACE_ATIVA"
echo ">> Sub-rede      : $REDE_LAB"
echo ">> Esta máquina  : $MEU_NOME — $MEU_IP ($MEU_MAC)"
echo "--------------------------------------------------------"

# ----------------------------------------------------------------
# 3. SUDO LOCAL (necessário para arp-scan / nmap com MAC)
# ----------------------------------------------------------------
SUDO_MODO=""   # "n" = já autorizado | "senha" = via LAB_SENHA | "" = sem root
if sudo -n true 2>/dev/null; then
    SUDO_MODO="n"
elif [ -n "$LAB_SENHA" ] && printf '%s\n' "$LAB_SENHA" | sudo -S -p '' -v 2>/dev/null; then
    SUDO_MODO="senha"
elif [ -t 0 ]; then
    echo "[AVISO] A senha do lablivre.conf (LAB_SENHA) não funcionou no sudo DESTA máquina."
    echo ">> Digite a senha de sudo local (ou ENTER/Ctrl+C para seguir sem root):"
    sudo -v && SUDO_MODO="n"
fi

rodar_root() {
    case "$SUDO_MODO" in
        n)     sudo -n "$@" ;;
        senha) printf '%s\n' "$LAB_SENHA" | sudo -S -p '' "$@" ;;
        *)     return 1 ;;
    esac
}

# ----------------------------------------------------------------
# 4. VARREDURA → TABELA "mac ip"
# ----------------------------------------------------------------
TABELA=""
METODO=""

if [ -n "$SUDO_MODO" ] && command -v arp-scan >/dev/null 2>&1; then
    METODO="arp-scan"
    echo ">> Varredura com arp-scan. Aguarde..."
    SAIDA=$(rodar_root arp-scan --interface="$IFACE_ATIVA" --localnet --retry=3 2>>"$LOG_SCAN")
    echo "$SAIDA" >> "$LOG_SCAN"
    TABELA=$(echo "$SAIDA" | awk '$1 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ {print tolower($2), $1}')
fi

if [ -z "$TABELA" ] && [ -n "$SUDO_MODO" ] && command -v nmap >/dev/null 2>&1; then
    METODO="nmap"
    echo ">> Varredura com nmap. Aguarde..."
    SAIDA=$(rodar_root nmap -sn -PR "$REDE_LAB" 2>>"$LOG_SCAN")
    echo "$SAIDA" >> "$LOG_SCAN"
    TABELA=$(echo "$SAIDA" | awk '
        /^Nmap scan report for/ { ip = $NF; gsub(/[()]/, "", ip) }
        /^MAC Address:/         { print tolower($3), ip }')
fi

if [ -z "$TABELA" ]; then
    METODO="ping+arp (sem root)"
    [ -z "$SUDO_MODO" ] && echo "[AVISO] Sem sudo local: usando ping + tabela ARP (menos preciso)."
    [ -n "$SUDO_MODO" ] && echo "[AVISO] arp-scan/nmap não instalados ou sem resultado. Sugestão: sudo apt install arp-scan"
    PREFIXO="${REDE_LAB#*/}"
    if [ "$PREFIXO" -lt 22 ]; then
        echo "[ERRO] Sub-rede /$PREFIXO grande demais para ping sweep. Instale arp-scan."
        exit 1
    fi
    echo ">> Pingando a sub-rede inteira em paralelo. Aguarde..."
    IFS=. read -r a b c d <<< "$MEU_IP"
    N=$(( (a<<24) | (b<<16) | (c<<8) | d ))
    MASCARA=$(( (0xFFFFFFFF << (32 - PREFIXO)) & 0xFFFFFFFF ))
    INICIO=$(( (N & MASCARA) + 1 ))
    FIM=$(( (N | (~MASCARA & 0xFFFFFFFF)) - 1 ))
    for ((i = INICIO; i <= FIM; i++)); do
        echo "$(( i>>24 & 255 )).$(( i>>16 & 255 )).$(( i>>8 & 255 )).$(( i & 255 ))"
    done | xargs -P 64 -I{} ping -c 1 -W 1 {} >/dev/null 2>&1
    # Quem respondeu ao ARP fica REACHABLE (mesmo com ICMP bloqueado)
    SAIDA=$(ip -4 neigh show dev "$IFACE_ATIVA")
    echo "$SAIDA" >> "$LOG_SCAN"
    TABELA=$(echo "$SAIDA" | awk '/REACHABLE|DELAY|PROBE/ {
        for (k = 1; k < NF; k++) if ($k == "lladdr") print tolower($(k+1)), $1 }')
fi

TOTAL_HOSTS=$(echo "$TABELA" | grep -c '[0-9a-f]')
echo ">> Método: $METODO — $TOTAL_HOSTS dispositivo(s) responderam na rede."
echo "--------------------------------------------------------"

# Rede inteira muda = falha da varredura, não laboratório desligado
if [ "$TOTAL_HOSTS" -eq 0 ]; then
    echo "[ERRO] Nenhum dispositivo respondeu (nem o roteador)."
    echo ">> Isso é falha da varredura, não laboratório desligado."
    echo ">> O $ARQUIVO_IPS anterior foi MANTIDO. Log bruto: $LOG_SCAN"
    exit 1
fi

# ----------------------------------------------------------------
# 5. CRUZAMENTO macs.txt × varredura → ips_atuais.txt (atômico)
# ----------------------------------------------------------------
TMP_IPS=$(mktemp "${ARQUIVO_IPS}.XXXXXX")
{
    echo "MAC_ADDRESS        IP_ADDRESS       NOME_MAQUINA"
    echo "------------------------------------------------"
    printf "%-18s %-16s %s (ESTA MÁQUINA)\n" \
        "${MEU_MAC:-00:00:00:00:00:00}" "${MEU_IP:-127.0.0.1}" "$MEU_NOME"
} > "$TMP_IPS"

TOTAL_ONLINE=0
TOTAL_MAQUINAS=0
MEU_NOME_CADASTRADO=""
[ -n "$MEU_MAC" ] && MEU_NOME_CADASTRADO="${VISTO_MAC[$MEU_MAC]}"

for nome in "${LISTA_NOME[@]}"; do
    mac="${MAC_PRINCIPAL[$nome]}"
    # Esta máquina já está na linha 3
    [ "$nome" = "$MEU_NOME_CADASTRADO" ] && continue
    ((TOTAL_MAQUINAS++))

    # Procura o principal primeiro, depois as placas extras (wifi)
    IP_MATCH=""
    VIA=""
    for m in "$mac" ${MACS_EXTRAS[$nome]}; do
        IP_MATCH=$(echo "$TABELA" | awk -v m="$m" '$1 == m {print $2; exit}')
        if [ -n "$IP_MATCH" ]; then
            [ "$m" != "$mac" ] && VIA="  ← pela placa secundária $m"
            break
        fi
    done

    if [ -n "$IP_MATCH" ]; then
        # Grava sempre o MAC PRINCIPAL (o Wake-on-LAN depende dele)
        printf "%-18s %-16s %s\n" "$mac" "$IP_MATCH" "$nome" >> "$TMP_IPS"
        echo "[ONLINE]  $nome ($IP_MATCH)$VIA"
        ((TOTAL_ONLINE++))
    else
        printf "%-18s %-16s %s\n" "$mac" "OFFLINE" "$nome" >> "$TMP_IPS"
        echo "[OFFLINE] $nome"
    fi
done

chmod 644 "$TMP_IPS"
mv -f "$TMP_IPS" "$ARQUIVO_IPS"

echo "--------------------------------------------------------"
echo "[CONCLUÍDO] $TOTAL_ONLINE online de $TOTAL_MAQUINAS máquinas (fora esta)."
echo ">> Log bruto da varredura: $LOG_SCAN"

# ----------------------------------------------------------------
# 6. MACs NA REDE QUE NÃO ESTÃO NO macs.txt (segurança/auditoria)
# ----------------------------------------------------------------
DESCONHECIDOS=""
while read -r mac ip; do
    [ -z "$mac" ] && continue
    [ "$mac" = "$MEU_MAC" ] && continue
    [ -n "${VISTO_MAC[$mac]}" ] && continue
    DESCONHECIDOS+="  • $mac ($ip)"$'\n'
done <<< "$TABELA"

if [ -n "$DESCONHECIDOS" ]; then
    echo "--------------------------------------------------------"
    echo "⚠️  Na rede, mas NÃO cadastrados em configs/macs.txt:"
    printf '%s' "$DESCONHECIDOS"
    echo "  (roteador, visitantes, celulares ou máquinas novas?)"
    {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] MACs desconhecidos detectados ($METODO):"
        printf '%s' "$DESCONHECIDOS"
    } >> logs/macs_desconhecidos.log
fi

# ----------------------------------------------------------------
# 7. MODO PROVA: bloqueia quem ligou depois / libera pendentes
# ----------------------------------------------------------------
if [ -f logs/modo_prova.status ]; then
    bash modulos/modo_prova.sh reaplicar --silencioso
elif [ -s logs/modo_prova.pendentes ]; then
    bash modulos/modo_prova.sh liberar-pendentes --silencioso
fi

# ----------------------------------------------------------------
# 8. REGENERA OS DADOS DOS DASHBOARDS WEB
# ----------------------------------------------------------------
echo "--------------------------------------------------------"
echo "[OK] Regenerando dados web..."
bash modulos/gerar_estado.sh 2>&1 | tail -1
bash modulos/gerar_auditoria_json.sh 2>&1 | tail -1 || true
bash modulos/gerar_mapa_calor.sh 2>&1 | tail -1 || true

if [ -f web/api.json ] && python3 -c "import json; json.load(open('web/api.json'))" 2>/dev/null; then
    echo "[OK] web/api.json gerado com sucesso."
else
    echo "[AVISO] web/api.json não foi gerado corretamente. Verifique: ls -la web/"
fi
