#!/bin/bash

# Garante que o script localize a raiz do projeto
cd "$(dirname "$0")/.." || exit 1

source modulos/_comum.sh && carregar_conf || exit 1
source modulos/_log.sh 2>/dev/null || true
source modulos/_ssh.sh 2>/dev/null || true
source modulos/_dryrun.sh "$@" 2>/dev/null || true
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

# PAYLOAD (roda no aluno, enviado pelo stdin do SSH):
# - Heredoc com aspas simples (<<'EOF') = nada é expandido aqui no professor
# - A senha do sudo vai numa linha LAB_SENHA_ENV=... ANTES do payload, também
#   pelo stdin: não aparece na linha de comando (nem no "ps" do aluno)
PAYLOAD=$(cat <<'EOF'
s() { sudo -n "$@" 2>/dev/null || printf '%s\n' "$LAB_SENHA_ENV" | sudo -S -p '' "$@" 2>/dev/null; }
IFACE=$(ip route show default 2>/dev/null | awk '{print $5; exit}')
echo "SISTEMA: $(lsb_release -ds 2>/dev/null || grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')"
echo "MODELO: $(s dmidecode -s system-manufacturer) $(s dmidecode -s system-product-name)"
echo "SERIE: $(s dmidecode -s system-serial-number)"
echo "CPU: $(grep -m 1 'model name' /proc/cpuinfo | cut -d':' -f2 | sed 's/^[[:space:]]*//') ($(nproc) núcleos)"
echo "CARGA: $(cut -d' ' -f1-3 /proc/loadavg)"
echo "RAM: $(free -h | awk 'NR==2 {print $2}') (em uso: $(free -h | awk 'NR==2 {print $3}'))"
echo "DISCO: $(df -h / | awk 'NR==2 {print $2 " (" $5 " usado)"}')"
echo "GPU: $(lspci 2>/dev/null | grep -i vga | cut -d':' -f3 | head -n 1 | sed 's/^[[:space:]]*//')"
echo "BIOS: $(s dmidecode -s bios-version)"
echo "KERNEL: $(uname -r)"
echo "UPTIME: $(uptime -p 2>/dev/null | sed 's/^up //')"
WOL=$(s ethtool "$IFACE" | awk '/^[[:space:]]*Wake-on:/ {print $2}')
case "$WOL" in *g*) WOL="ativo ($WOL)" ;; "") WOL="desconhecido" ;; *) WOL="DESATIVADO ($WOL)" ;; esac
echo "WOL: $WOL em ${IFACE:-?}"
if command -v lsusb >/dev/null 2>&1; then
    echo "USB: $(lsusb | grep -vic 'root hub') dispositivo(s): $(lsusb | grep -vi 'root hub' | cut -d' ' -f7- | cut -c1-40 | paste -sd';' -)"
else
    echo "USB: lsusb não instalado"
fi
echo "PYTHON: $(python3 --version 2>/dev/null | awk '{print $2}')"
echo "NODE: $(node -v 2>/dev/null || echo 'não instalado')"
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
        { printf 'LAB_SENHA_ENV=%q\n' "$LAB_SENHA"; echo "$PAYLOAD"; } \
            | ssh_remote_stdin "$ip" "bash" >> "$RELATORIO" 2>/dev/null

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
