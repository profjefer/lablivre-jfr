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

# 1. CONFIRMAÇÃO DE SEGURANÇA
zenity --question \
    --title="🔌 Desligar Laboratório" \
    --text="Tem certeza que deseja <b>DESLIGAR</b> todos os terminais online agora?" \
    --width=350

if [ $? -ne 0 ]; then
    exit 0
fi

# Conta os terminais online (exclui a própria máquina)
TOTAL_MAQUINAS=$(tail -n +3 "$ARQUIVO_IPS" | grep -v -w "OFFLINE" | grep -v "ESTA MÁQUINA" | wc -l)
[ "$TOTAL_MAQUINAS" -eq 0 ] && TOTAL_MAQUINAS=1

# ===================================================================
# 2. EXECUÇÃO COM BARRA DE PROGRESSO
# ===================================================================
(
    ATUAL=0
    
    while read -r mac ip nome resto; do
        # Pula máquinas offline e o orquestrador
        if [[ -z "$mac" ]] || [[ "$ip" == "OFFLINE" ]] || [[ "$resto" == *"(ESTA MÁQUINA)"* ]]; then 
            continue
        fi
        
        echo "# Desligando: $nome ($ip)..."
        
        # Envia o sinal de shutdown com injeção de sudo
        sshpass -p "$LAB_SENHA" ssh -n -q -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$LAB_USUARIO@$ip" "echo '$LAB_SENHA' | sudo -S shutdown -h now 2>/dev/null"
        
        ((ATUAL++))
        PERCENT=$(( ATUAL * 100 / TOTAL_MAQUINAS ))
        echo "$PERCENT"
    done < <(tail -n +3 "$ARQUIVO_IPS")
    
    echo "100"
    echo "# Comando de desligamento enviado!"

) | zenity --progress \
    --title="Encerrando Laboratório" \
    --text="Enviando sinal de desligamento..." \
    --percentage=0 \
    --auto-close \
    --auto-kill \
    --width=400

zenity --info --title="Concluído" --text="✅ <b>Sinal enviado!</b>\nAs máquinas serão desligadas em instantes." --width=300
