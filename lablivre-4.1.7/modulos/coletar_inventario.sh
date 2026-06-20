#!/bin/bash

# Garante que o script localize a raiz do projeto
cd "$(dirname "$0")/.." || exit 1

CONF_FILE="configs/lablivre.conf"
if [ -f "$CONF_FILE" ]; then source "$CONF_FILE"; else LAB_USUARIO="ufpr"; LAB_SENHA="UFPR"; fi
source modulos/_log.sh 2>/dev/null || true
source modulos/_ssh.sh 2>/dev/null || true
ARQUIVO_IPS="ips_atuais.txt"
RELATORIO="logs/inventario_lab.txt"

mkdir -p logs

if [ ! -f "$ARQUIVO_IPS" ]; then
    echo "[ERRO] Arquivo '$ARQUIVO_IPS' não encontrado."
    echo ">> Execute primeiro a opção 1 (Mapear Rede) no menu."
    exit 1
fi

echo "========================================================"
echo "      📊 COLETA CENTRALIZADA DE INVENTÁRIO              "
echo "========================================================"
echo ">> Coletando dados de hardware. Aguarde..."
echo "--------------------------------------------------------"

# Cabeçalho do relatório
echo "========================================================" > "$RELATORIO"
echo "    RELATÓRIO DE INVENTÁRIO - LABLIVRE                  " >> "$RELATORIO"
echo "    Data da Coleta: $(date '+%d/%m/%Y %H:%M:%S')        " >> "$RELATORIO"
echo "========================================================" >> "$RELATORIO"

# PAYLOAD BLINDADO:
# - Heredoc com aspas simples (<<'EOF') = sem interpolação aqui no professor
# - A senha é passada via variável de ambiente LAB_SENHA_ENV para o sudo remoto
#   evitando que apareça em texto puro dentro do script enviado pelo pipe
PAYLOAD=$(cat <<'EOF'
echo "SISTEMA: $(lsb_release -ds 2>/dev/null || grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')"
echo "CPU: $(grep -m 1 'model name' /proc/cpuinfo | cut -d':' -f2 | sed 's/^[[:space:]]*//')"
echo "RAM: $(free -h | awk 'NR==2 {print $2}')"
echo "DISCO: $(df -h / | awk 'NR==2 {print $2}')"
echo "GPU: $(lspci 2>/dev/null | grep -i vga | cut -d':' -f3 | head -n 1 | sed 's/^[[:space:]]*//')"
echo "BIOS: $(echo "$LAB_SENHA_ENV" | sudo -S dmidecode -s bios-version 2>/dev/null)"
echo "KERNEL: $(uname -r)"
echo "PACOTES: $(dpkg -l 2>/dev/null | grep -c '^ii') instalados no total"
EOF
)

# Laço principal — lê 4 colunas para capturar $resto e identificar (ESTA MÁQUINA)
# Redirecionamento direto (< <()) em vez de pipe: o SSH recebe o payload via pipe
# sem conflitar com o stdin do loop while
while read -r mac ip nome resto; do
    if [[ -z "$mac" ]] || [[ "$ip" == "OFFLINE" ]]; then continue; fi

    echo -n "Coletando de: $nome ($ip)... "

    {
        echo ""
        echo "--------------------------------------------------------"
        echo "MÁQUINA: $nome ($ip | $mac)"
        echo "--------------------------------------------------------"
    } >> "$RELATORIO"

    if [[ "$resto" == *"(ESTA MÁQUINA)"* ]]; then
        # Executa localmente exportando a senha como variável de ambiente
        LAB_SENHA_ENV="$LAB_SENHA" eval "$PAYLOAD" >> "$RELATORIO" 2>/dev/null
        echo "[OK] (Local)"
    else
        # Envia o PAYLOAD via pipe ao bash remoto
        # ssh_remote_stdin não usa flag -n (precisamos do stdin para o pipe)
        echo "$PAYLOAD" | ssh_remote_stdin "$ip" \
            "LAB_SENHA_ENV='$LAB_SENHA' bash" >> "$RELATORIO" 2>/dev/null

        if [ ${PIPESTATUS[1]} -eq 0 ]; then
            echo "[OK]"
        else
            echo "[ERRO]"
            echo "A máquina não respondeu (Timeout/Erro SSH)." >> "$RELATORIO"
        fi
    fi
done < <(tail -n +3 "$ARQUIVO_IPS")

echo "--------------------------------------------------------"
echo "[CONCLUÍDO] Inventário salvo com sucesso!"
log_acao "coletar_inventario" "" 2>/dev/null || true
echo "📄 Relatório em: $RELATORIO"

# Gera também HTML estilizado para a web
bash modulos/inventario_para_html.sh 2>&1 | tail -2
