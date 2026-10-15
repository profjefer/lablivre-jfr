#!/bin/bash

# Garante que o script localize a raiz do projeto
cd "$(dirname "$0")/.." || exit 1

ARQUIVO_IPS="ips_atuais.txt"

# 1. VERIFICAÇÃO DE DEPENDÊNCIA
if ! command -v wakeonlan &> /dev/null; then
    zenity --error --title="Erro de Dependência" --text="O pacote <b>wakeonlan</b> não foi encontrado.\nInstale-o com: <i>sudo apt install wakeonlan</i>" --width=350
    exit 1
fi

# Conta o total de máquinas no inventário
TOTAL_MAQUINAS=$(tail -n +3 "$ARQUIVO_IPS" | grep -v "ESTA MÁQUINA" | wc -l)
[ "$TOTAL_MAQUINAS" -eq 0 ] && TOTAL_MAQUINAS=1

# ===================================================================
# 2. EXECUÇÃO COM BARRA DE PROGRESSO
# ===================================================================
(
    ATUAL=0
    
    while read -r mac ip nome resto; do
        # Pula a própria máquina
        if [[ -z "$mac" ]] || [[ "$resto" == *"(ESTA MÁQUINA)"* ]]; then 
            continue
        fi
        
        echo "# Acionando: $nome ($mac)..."
        
        # Dispara o Magic Packet
        wakeonlan "$mac" >/dev/null 2>&1
        
        # Pequeno intervalo para evitar saturação da rede
        sleep 0.1
        
        ((ATUAL++))
        PERCENT=$(( ATUAL * 100 / TOTAL_MAQUINAS ))
        echo "$PERCENT"
    done < <(tail -n +3 "$ARQUIVO_IPS")
    
    echo "100"
    echo "# Todos os pacotes de despertar foram enviados!"

) | zenity --progress \
    --title="⚡ Wake-on-LAN" \
    --text="Enviando pacotes de despertar..." \
    --percentage=0 \
    --auto-close \
    --auto-kill \
    --width=400

zenity --info --title="Sucesso" --text="✅ <b>Comando enviado!</b>\nAs máquinas configuradas na BIOS deverão ligar em breve." --width=300
