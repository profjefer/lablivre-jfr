#!/bin/bash

cd "$(dirname "$0")/.." || exit 1

CONF_FILE="configs/lablivre.conf"
if [ -f "$CONF_FILE" ]; then
    source "$CONF_FILE"
else
    LAB_USUARIO="ufpr"
    LAB_SENHA="UFPR"
fi

ARQUIVO_IPS="ips_atuais.txt"
FLAG_PROVA="logs/modo_prova.status"
mkdir -p logs

if [ ! -f "$ARQUIVO_IPS" ]; then
    zenity --error --text="Arquivo de IPs não encontrado!\nExecute o mapeamento de rede primeiro." --width=300
    exit 1
fi

# Status atual
if [ -f "$FLAG_PROVA" ]; then
    STATUS_ATUAL="🔴 ATIVO desde $(cat $FLAG_PROVA)"
else
    STATUS_ATUAL="🟢 Internet liberada"
fi

# ===================================================================
# 1. INTERFACE DE ESCOLHA
# ===================================================================
OPCAO_PROVA=$(zenity --list \
    --title="🔒 Modo Prova" \
    --text="<b>Status atual:</b> $STATUS_ATUAL\n\nSelecione a ação:" \
    --radiolist --column="Marcar" --column="ID" --column="Ação" \
    TRUE "1" "🔴 ATIVAR (Bloquear Internet, manter rede local)" \
    FALSE "2" "🟢 DESATIVAR (Liberar Internet geral)" \
    --hide-column=2 --print-column=2 --width=500 --height=250)

if [ -z "$OPCAO_PROVA" ]; then
    exit 0
fi

# ===================================================================
# 2. DEFINIÇÃO DAS REGRAS
# ===================================================================
if [[ "$OPCAO_PROVA" == "1" ]]; then
    MENSAGEM="Bloqueando Internet e criando Túnel VIP local..."
    CMD_REMOTO="echo '$LAB_SENHA' | sudo -S iptables -F OUTPUT 2>/dev/null; \
                echo '$LAB_SENHA' | sudo -S iptables -P OUTPUT DROP 2>/dev/null; \
                echo '$LAB_SENHA' | sudo -S iptables -I OUTPUT -o lo -j ACCEPT 2>/dev/null; \
                echo '$LAB_SENHA' | sudo -S iptables -I OUTPUT -d 10.0.0.0/8 -j ACCEPT 2>/dev/null; \
                echo '$LAB_SENHA' | sudo -S iptables -I OUTPUT -d 172.16.0.0/12 -j ACCEPT 2>/dev/null; \
                echo '$LAB_SENHA' | sudo -S iptables -I OUTPUT -d 192.168.0.0/16 -j ACCEPT 2>/dev/null; \
                echo '$LAB_SENHA' | sudo -S iptables -I OUTPUT -d 200.236.0.0/16 -j ACCEPT 2>/dev/null"
else
    MENSAGEM="Restaurando configurações e liberando Internet..."
    CMD_REMOTO="echo '$LAB_SENHA' | sudo -S iptables -P OUTPUT ACCEPT 2>/dev/null; \
                echo '$LAB_SENHA' | sudo -S iptables -F OUTPUT 2>/dev/null"
fi

TOTAL_MAQUINAS=$(tail -n +3 "$ARQUIVO_IPS" | grep -v -w "OFFLINE" | grep -v "ESTA MÁQUINA" | wc -l)
[ "$TOTAL_MAQUINAS" -eq 0 ] && TOTAL_MAQUINAS=1

# ===================================================================
# 3. EXECUÇÃO COM BARRA DE PROGRESSO
# ===================================================================
(
    ATUAL=0

    while read -r mac ip nome resto; do
        if [[ -z "$mac" ]] || [[ "$ip" == "OFFLINE" ]] || [[ "$resto" == *"(ESTA MÁQUINA)"* ]]; then
            continue
        fi

        echo "# Configurando firewall em: $nome ($ip)..."
        sshpass -p "$LAB_SENHA" ssh -n -q -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$LAB_USUARIO@$ip" "$CMD_REMOTO"

        ((ATUAL++))
        PERCENT=$(( ATUAL * 100 / TOTAL_MAQUINAS ))
        echo "$PERCENT"
    done < <(tail -n +3 "$ARQUIVO_IPS")

    echo "100"
    echo "# Regras aplicadas!"

) | zenity --progress \
    --title="Controle de Rede" \
    --text="$MENSAGEM" \
    --percentage=0 \
    --auto-close \
    --auto-kill \
    --width=450

if [ $? -ne 0 ]; then
    zenity --warning --text="Operação interrompida." --width=300
    exit 1
fi

# ===================================================================
# 4. ATUALIZA FLAG DE STATUS E RESUMO
# ===================================================================
if [[ "$OPCAO_PROVA" == "1" ]]; then
    date '+%d/%m/%Y %H:%M:%S' > "$FLAG_PROVA"
    zenity --info \
        --title="Modo Prova ATIVO" \
        --text="🔴 <b>Modo Prova ATIVADO!</b>\n\nInternet bloqueada em todas as máquinas online.\nRede local permanece ativa.\n\n<i>Status salvo em logs/modo_prova.status</i>" \
        --width=400
else
    rm -f "$FLAG_PROVA"
    zenity --info \
        --title="Modo Prova DESATIVADO" \
        --text="🟢 <b>Internet LIBERADA!</b>\n\nRegras de firewall removidas em todas as máquinas online." \
        --width=400
fi

# Regenera api.json para o dashboard refletir o novo status imediatamente
bash modulos/gerar_estado.sh >/dev/null 2>&1 || true
