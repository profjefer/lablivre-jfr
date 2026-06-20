#!/bin/bash

MEU_IP=$(ip route get 8.8.8.8 | awk '{print $7; exit}')
# Garante que o script sempre rode na pasta base
cd "$(dirname "$0")/.." || exit 1

# --- BUSCA CONFIGURAÇÃO GLOBAL (Princípio DRY) ---
CONF_FILE="configs/lablivre.conf"
[ -f "$CONF_FILE" ] || CONF_FILE="../configs/lablivre.conf"

if [ -f "$CONF_FILE" ]; then
    source "$CONF_FILE"
else
    LAB_USUARIO="ufpr"
    LAB_SENHA="UFPR"
fi

USUARIO_SSH="$LAB_USUARIO"
SENHA_SSH="$LAB_SENHA"
ARQUIVO_IPS="ips_atuais.txt"
RELATORIO_MANUTENCAO="logs/relatorio_manutencao_$(date +%Y%m%d_%H%M%S).txt"

if [ ! -f "$ARQUIVO_IPS" ]; then
    zenity --error --text="Erro: Arquivo '$ARQUIVO_IPS' não encontrado."
    exit 1
fi
mkdir -p logs

# ========================================================
# 1. INTERFACE DE ENTRADA (ZENITY)
# ========================================================
OPCAO=$(zenity --list \
    --title="🔧 Manutenção do Sistema - LabLivre" \
    --text="Selecione a rotina de manutenção para o laboratório:" \
    --column="ID" --column="Ação" --hide-column=1 \
    "1" "🔄 Atualização Completa (Update + Upgrade)" \
    "2" "🧹 Limpeza de Sistema (Autoremove + Clean)" \
    "3" "📦 Instalar Pacote Específico (APT)" \
    --width=480 --height=250 --window-icon=system-software-update)

if [ $? -ne 0 ]; then exit 0; fi

# Blindagem contra travamentos de interatividade do APT
APT_BLINDADO="DEBIAN_FRONTEND=noninteractive apt-get -y -q -o Dpkg::Options::=\"--force-confold\""

if [ "$OPCAO" == "1" ]; then
    # Confirmação extra pois demora
    zenity --question --title="Atenção: Tempo de Execução" --text="A atualização completa pode levar vários minutos dependendo da rede e do disco.\nDeseja iniciar?" --width=350
    if [ $? -ne 0 ]; then exit 0; fi
    COMANDO_SUDO="$APT_BLINDADO update && $APT_BLINDADO upgrade && $APT_BLINDADO autoremove && $APT_BLINDADO autoclean"
    ACAO_NOME="Atualização Completa"

elif [ "$OPCAO" == "2" ]; then
    COMANDO_SUDO="$APT_BLINDADO autoremove && $APT_BLINDADO autoclean"
    ACAO_NOME="Limpeza de Sistema"

elif [ "$OPCAO" == "3" ]; then
    PACOTE=$(zenity --entry --title="📦 Instalar Pacote" --text="Digite o nome do pacote (ex: gnuplot, vlc, git):" --width=350)
    if [ -z "$PACOTE" ]; then exit 0; fi
    COMANDO_SUDO="$APT_BLINDADO update && $APT_BLINDADO install $PACOTE"
    ACAO_NOME="Instalação do pacote: $PACOTE"
fi

COMANDO_REMOTO="echo '$SENHA_SSH' | sudo -S sh -c '$COMANDO_SUDO'"

# ========================================================
# 2. EXECUÇÃO COM LOG NO TERMINAL E NO ARQUIVO
# ========================================================
echo "==========================================" | tee "$RELATORIO_MANUTENCAO"
echo "  MANUTENÇÃO: $ACAO_NOME" | tee -a "$RELATORIO_MANUTENCAO"
echo "==========================================" | tee -a "$RELATORIO_MANUTENCAO"
echo "Aviso: Processos do APT podem demorar. Aguarde o final..."
echo "--------------------------------------------------------" | tee -a "$RELATORIO_MANUTENCAO"

while read -r mac ip nome resto; do
    if [[ -z "$mac" ]] || [[ "$ip" == "OFFLINE" ]]; then continue; fi

    echo -n "Processando: $nome ($ip)... " | tee -a "$RELATORIO_MANUTENCAO"
    
    # Aumentamos drasticamente o Timeout pois o apt-get upgrade demora muito
    if [[ "$resto" == *"(ESTA MÁQUINA)"* ]]; then
        SAIDA=$(eval "$COMANDO_REMOTO" 2>&1)
        if [ $? -eq 0 ]; then 
            echo "[OK]" | tee -a "$RELATORIO_MANUTENCAO"
        else 
            echo "[ERRO]" | tee -a "$RELATORIO_MANUTENCAO"
            echo "   -> Motivo: $(echo "$SAIDA" | tail -n 2 | tr '\n' ' ')" >> "$RELATORIO_MANUTENCAO"
        fi
    else
        SAIDA=$(sshpass -p "$SENHA_SSH" ssh -n -o StrictHostKeyChecking=no -o ConnectTimeout=10 "${USUARIO_SSH}@${ip}" "$COMANDO_REMOTO" 2>&1)
        if [ $? -eq 0 ]; then 
            echo "[OK]" | tee -a "$RELATORIO_MANUTENCAO"
        else 
            echo "[ERRO]" | tee -a "$RELATORIO_MANUTENCAO"
            echo "   -> Detalhe: $(echo "$SAIDA" | tail -n 2 | tr '\n' ' ')" >> "$RELATORIO_MANUTENCAO"
        fi
    fi
done < <(tail -n +3 "$ARQUIVO_IPS")

echo "--------------------------------------------------------" | tee -a "$RELATORIO_MANUTENCAO"
echo "[CONCLUÍDO] Log salvo em: $RELATORIO_MANUTENCAO"

# ========================================================
# 3. INTERFACE DE SAÍDA (ZENITY)
# ========================================================
zenity --text-info \
    --title="Relatório de Manutenção" \
    --text="Rotina concluída:\n<b>$ACAO_NOME</b>" \
    --filename="$RELATORIO_MANUTENCAO" \
    --width=650 --height=450 --font="Monospace 10" \
    --ok-label="Fechar"
