#!/bin/bash

export LIBGL_ALWAYS_SOFTWARE=1

# Silencia warnings inofensivos do GTK/GLib que aparecem em sessões SSH -X/-Y
# (ex: "GLib-GObject-CRITICAL g_object_unref: assertion 'G_IS_OBJECT' failed")
# Mantém erros reais visíveis, filtra só o ruído conhecido.
export NO_AT_BRIDGE=1
export G_MESSAGES_DEBUG=""
zenity() {
    command zenity "$@" 2> >(grep -v -E "GLib-GObject-CRITICAL|GLib-GIO-CRITICAL|g_object_unref|assertion '" >&2)
}

# ========================================================
# LabLivre v3 - Painel Central de Orquestração Premium
# UFPR - Laboratórios Linux
# ========================================================

# Vai para a raiz do projeto, funcione de onde for chamado:
# - Se xmenu.sh estiver na raiz: cd "$(dirname "$0")"
# - Se xmenu.sh estiver em xmodulos/: cd "$(dirname "$0")/.."
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -d "$SCRIPT_DIR/xmodulos" ]; then
    # Estou na raiz (existe pasta xmodulos como filha)
    cd "$SCRIPT_DIR" || exit 1
elif [ -d "$SCRIPT_DIR/../xmodulos" ]; then
    # Estou dentro de xmodulos (existe pasta xmodulos como irmã)
    cd "$SCRIPT_DIR/.." || exit 1
else
    echo "[ERRO] Não foi possível localizar a raiz do projeto LabLivre."
    exit 1
fi

# Verificar/Instalar dependências
DEPENDENCIAS=(
    "zenity"
    "sshpass"
    "wakeonlan"
    "avahi-utils"
    "jq"
    "bc"
    "nmap"
    "netcat"
    "ethtool"
    "dmidecode"
)

# Atualiza repositórios uma única vez
#sudo apt-get update -y 2>/dev/null

#for dep in "${DEPENDENCIAS[@]}"; do
#    if ! command -v "$dep" &> /dev/null; then
#        echo "Instalando dependência: $dep"
#        sudo apt-get install -y "$dep" 2>/dev/null || true
#    fi
#done

ARQUIVO_IPS="ips_atuais.txt"
ARQUIVO_HISTORICO="logs/historico.log"
FLAG_PROVA="logs/modo_prova.status"
LOGO_ICON="computer"

# Garante que as pastas essenciais existam
mkdir -p logs
mkdir -p web
mkdir -p configs

# ========================================================
# PRIMEIRA EXECUÇÃO: conf não existe ainda
# ========================================================
if [ ! -f "configs/lablivre.conf" ]; then
    zenity --info \
        --title="⚠️ Primeira Execução" \
        --text="<b>Bem-vindo ao LabLivre!</b>\n\nO arquivo <i>configs/lablivre.conf</i> não foi encontrado.\nIniciando configuração inicial..." \
        --width=400
    bash xmodulos/xconfigurar_lab.sh
fi

# Carrega configurações
CONF_FILE="configs/lablivre.conf"
[ -f "$CONF_FILE" ] && source "$CONF_FILE"
LAB_NOME="${LAB_NOME:-LabLivre}"

# Aviso se macs.txt vazio
if [ ! -s "configs/macs.txt" ]; then
    zenity --warning \
        --title="⚠️ Lista de MACs vazia" \
        --text="O arquivo <b>configs/macs.txt</b> está vazio!\n\nSem ele o mapeamento de rede não funciona.\nPreencha antes de usar o sistema:\n\n<i>aa:bb:cc:dd:ee:ff   nome-da-maquina</i>" \
        --width=450
fi


# --------------------------------------------------------
# FUNÇÃO 1: TESTE DE REDE INTERNO
# --------------------------------------------------------
testar_rede() {
    if [ ! -f "$ARQUIVO_IPS" ]; then
        zenity --error --text="Arquivo de IPs não encontrado!\nExecute 'Atualizar IPs' primeiro."
        return 1
    fi

    local RESULTADO="╔════════════════════════════════════════════════════════════════╗\n║                    📡 TESTE DE CONECTIVIDADE                     ║\n╚════════════════════════════════════════════════════════════════╝\n\n"
    local ONLINE=0
    local OFFLINE=0
    local MEU_IP=$(hostname -I | awk '{print $1}')

    while read -r mac ip nome resto; do
        [[ -z "$mac" ]] && continue

        # Se está marcada como "ESTA MÁQUINA" ou IP coincide com o local,
        # considera ONLINE sem fazer ping (loopback nem sempre responde)
        if [[ "$resto" == *"(ESTA MÁQUINA)"* ]] || [[ "$ip" == "$MEU_IP" ]]; then
            RESULTADO+="✅ $nome ($ip) - ONLINE (local)\n"
            ((ONLINE++))
        elif [[ "$ip" != "OFFLINE" ]] && ping -c 1 -W 1 "$ip" &>/dev/null; then
            RESULTADO+="✅ $nome ($ip) - ONLINE\n"
            ((ONLINE++))
        else
            RESULTADO+="❌ $nome ($ip) - OFFLINE\n"
            ((OFFLINE++))
        fi
    done < <(tail -n +3 "$ARQUIVO_IPS" 2>/dev/null)

    RESULTADO+="\n════════════════════════════════════════════════════════════════\n📊 RESUMO: $ONLINE online(s) | $OFFLINE offline(s)\n════════════════════════════════════════════════════════════════\n"

    TMP=$(mktemp)
    echo -e "$RESULTADO" > "$TMP"

    zenity --text-info \
        --title="Resultado do Teste" \
        --width=600 --height=500 \
        --filename="$TMP" \
        --font="Monospace 10"

    rm -f "$TMP"

}

# --------------------------------------------------------
# FUNÇÃO 2: RELATÓRIO HTML COMPLETO (OPÇÃO 14)
# --------------------------------------------------------
gerar_relatorio_completo() {
    local RELATORIO="web/relatorio_$(date +%Y%m%d_%H%M%S).html"
    
    cat > "$RELATORIO" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Relatório LabLivre</title>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; background: #f5f5f5; padding: 20px; }
        .container { max-width: 1200px; margin: 0 auto; background: white; border-radius: 15px; box-shadow: 0 10px 30px rgba(0,0,0,0.1); overflow: hidden; }
        .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 30px; text-align: center; }
        .content { padding: 30px; }
        table { width: 100%; border-collapse: collapse; margin-top: 15px; }
        th, td { padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background: #667eea; color: white; }
        .status-online { color: #2ecc71; font-weight: bold; }
        .status-offline { color: #e74c3c; font-weight: bold; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>📊 LabLivre - Relatório de Laboratório</h1>
            <p>Universidade Federal do Paraná - Setor Palotina</p>
        </div>
        <div class="content">
            <h2>💻 Status das Máquinas</h2>
            <table>
                <tr><th>MAC</th><th>IP</th><th>Nome</th><th>Status</th></tr>
EOF

    if [ -f "$ARQUIVO_IPS" ]; then
        while read -r mac ip nome; do
            [[ -z "$mac" ]] && continue
            if [[ "$ip" != "OFFLINE" ]]; then
                echo "<tr><td>$mac</td><td>$ip</td><td>$nome</td><td class='status-online'>🟢 ONLINE</td></tr>" >> "$RELATORIO"
            else
                echo "<tr><td>$mac</td><td>$ip</td><td>$nome</td><td class='status-offline'>🔴 OFFLINE</td></tr>" >> "$RELATORIO"
            fi
        done < <(tail -n +3 "$ARQUIVO_IPS" 2>/dev/null)
    fi
    
    cat >> "$RELATORIO" << 'EOF'
            </table>
        </div>
    </div>
</body>
</html>
EOF
    
    if command -v xdg-open &> /dev/null; then
    xdg-open "$RELATORIO"
elif command -v firefox &> /dev/null; then
    firefox "$RELATORIO"
fi

}

# --------------------------------------------------------
# FUNÇÃO 3: DASHBOARD E MENU PRINCIPAL
# --------------------------------------------------------
mostrar_dashboard() {
    local ONLINE=0
    local OFFLINE=0
    
    if [ -f "$ARQUIVO_IPS" ]; then
        while read -r mac ip nome; do
            [[ -z "$mac" ]] && continue
            if [[ "$ip" == "OFFLINE" ]]; then
                ((OFFLINE++))
            else
                ((ONLINE++))
            fi
        done < <(tail -n +3 "$ARQUIVO_IPS" 2>/dev/null)
    fi
    
    local TOTAL=$((ONLINE + OFFLINE))
    if [ $TOTAL -eq 0 ]; then TOTAL=1; fi

    local PERCENT_ONLINE=$((ONLINE * 100 / TOTAL))
    local PERCENT_OFFLINE=$((OFFLINE * 100 / TOTAL))

    # Barras de tamanho fixo 30 (cabem dentro de 64 col com folga)
    local BARRA_LEN=30
    local BLOCOS_ON=$((PERCENT_ONLINE * BARRA_LEN / 100))
    local BLOCOS_OFF=$((BARRA_LEN - BLOCOS_ON))
    local BARRA_ONLINE=""
    local BARRA_OFFLINE=""
    [ $BLOCOS_ON -gt 0 ]  && BARRA_ONLINE=$(printf "█%.0s" $(seq 1 $BLOCOS_ON))
    [ $BLOCOS_OFF -gt 0 ] && BARRA_OFFLINE=$(printf "░%.0s" $(seq 1 $BLOCOS_OFF))

    local STATUS_TXT="╔══════════════════════════════════════════════════════════════════════════╗\n"
    STATUS_TXT+="║                         📊 STATUS DO LABORATÓRIO                          ║\n"
    STATUS_TXT+="╠══════════════════════════════════════════════════════════════════════════╣\n"
    STATUS_TXT+=$(printf "║ 🟢 ONLINE:  %3d  [%-30s] %3d%%" "$ONLINE" "$BARRA_ONLINE" "$PERCENT_ONLINE")" ║\n"
    STATUS_TXT+=$(printf "║ 🔴 OFFLINE: %3d  [%-30s] %3d%%" "$OFFLINE" "$BARRA_OFFLINE" "$PERCENT_OFFLINE")" ║\n"
    STATUS_TXT+=$(printf "║ 📊 TOTAL:   %3d máquinas no laboratório" "$TOTAL")" ║\n"

    # Status do modo prova
    if [ -f "$FLAG_PROVA" ]; then
        local PROVA_DESDE=$(cat "$FLAG_PROVA")
        STATUS_TXT+=$(printf "║ 🔴 MODO PROVA ATIVO desde %s" "$PROVA_DESDE")" ║\n"
    else
        STATUS_TXT+="║ 🟢 Internet liberada (modo prova desativado)                              ║\n"
    fi

    STATUS_TXT+="╚══════════════════════════════════════════════════════════════════════════╝"
    
    # Gera o HTML Visual do Dashboard continuamente no fundo (Caminho Relativo Corrigido)
    HTML_PREVIEW="web/status.html"

if [ -f "$ARQUIVO_IPS" ] && { [ ! -f "$HTML_PREVIEW" ] || [ "$ARQUIVO_IPS" -nt "$HTML_PREVIEW" ]; }; then
    cat > "$HTML_PREVIEW" << EOF
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <style>
        body { font-family: 'Segoe UI', Tahoma, sans-serif; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); margin: 0; padding: 20px; color: white; }
        .dashboard { max-width: 1200px; margin: 0 auto; text-align: center; }
        h1 { font-size: 3em; margin-bottom: 5px; }
        .stats { display: flex; justify-content: center; gap: 20px; margin-top: 30px; }
        .card { background: rgba(255,255,255,0.1); backdrop-filter: blur(10px); border-radius: 15px; padding: 30px; min-width: 200px; }
        .number { font-size: 4em; font-weight: bold; margin: 10px 0; }
        .online { border-bottom: 5px solid #2ecc71; }
        .offline { border-bottom: 5px solid #e74c3c; }
    </style>
</head>
<body>
    <div class="dashboard">
        <h1>🎮 LabLivre Dashboard</h1>
        <p>Atualizado em: $(date '+%d/%m/%Y %H:%M:%S')</p>
        <div class="stats">
            <div class="card online">
                <h3>🟢 ONLINE</h3>
                <div class="number">$ONLINE</div>
            </div>
            <div class="card offline">
                <h3>🔴 OFFLINE</h3>
                <div class="number">$OFFLINE</div>
            </div>
        </div>
    </div>
</body>
</html>
EOF
fi
    
    # Zenity List com as contra-barras corrigidas em todas as linhas
    zenity --list \
        --title="🌟 LabLivre — $LAB_NOME" \
        --window-icon="$LOGO_ICON" \
        --text="<big><b>🎯 Bem-vindo ao LabLivre — $LAB_NOME</b></big>\n\n$STATUS_TXT\n\n<b>Selecione uma operação:</b>" \
        --column="ID" --column="Categoria" --column="Ação" --column="Descrição" --column="Ícone" \
        --hide-column=1 --print-column=1 \
        --width=1000 --height=700 \
        --ok-label="Executar" --cancel-label="Sair" \
        "99" "⚙️ Sistema" "Configurações Globais" "Ajustar Senhas, Lab e Material" "🔧" \
        "1" "📡 Rede" "Atualizar IPs" "Mapeia a rede e detecta máquinas ativas" "🌐" \
        "2" "📡 Rede" "Ligar Laboratório" "Envia Wake-on-LAN para todas as máquinas" "🔌" \
        "3" "📡 Rede" "Desligar Laboratório" "Executa shutdown remoto" "⏻" \
        "4" "📡 Rede" "Modo Prova" "Bloqueia internet mantendo rede local" "📝" \
        "5" "📡 Rede" "Teste de Conexão" "Pinga todas as máquinas" "📊" \
        "6" "📚 Pedagógico" "Distribuir Material" "Copia pastas para os alunos" "📁" \
        "7" "📚 Pedagógico" "Enviar Mensagem" "Envia popup ou texto" "💬" \
        "8" "📚 Pedagógico" "Sincronizar Horários" "Ajusta relógio via NTP" "⏰" \
        "9" "🛠 Administração" "Inventário do Lab" "Coleta hardware das máquinas" "📋" \
        "10" "🛠 Administração" "Manutenção" "Atualiza pacotes (apt-get)" "🔧" \
        "11" "🛠 Administração" "Corrigir Repositórios" "Vacina APT (remove repos quebrados)" "💊" \
        "12" "🛠 Administração" "Diagnosticar SSH" "Testa conectividade SSH das máquinas" "🔍" \
        "16" "🛠 Administração" "Limpar Downloads" "Apaga Downloads e Lixeira das máquinas" "🧹" \
        "13" "📊 Relatórios" "Visualizar Logs" "Lê históricos gerados" "📄" \
        "14" "📊 Relatórios" "Tabela Completa HTML" "Gera lista Web detalhada" "📑" \
        "15" "🌐 Web" "Portal LabLivre" "Abre o portal central com todos os dashboards" "🌐" \
        "20" "🖥️ Dashboards" "Painel Operacional" "Monitoramento geral" "📊" \
        "21" "🖥️ Dashboards" "TV Mode" "Exibição fullscreen" "📺" \
        "22" "🖥️ Dashboards" "Modo Prova Visual" "Painel de prova" "📝" \
        "23" "🖥️ Dashboards" "Hacker Mode" "Terminal cyberpunk" "💻" \
        "24" "🖥️ Dashboards" "Auditoria" "Timeline de eventos" "📜" \
        "25" "🖥️ Dashboards" "Inventário HTML" "Hardware estilizado" "📋" \
        "26" "🖥️ Dashboards" "Mapa de Calor" "Máquinas mais usadas" "🔥" \
        "0" "⚙️ Sistema" "Sair" "Fecha o LabLivre" "🚪"
}

# ========================================================
# LOOP PRINCIPAL DO SISTEMA
# ========================================================
echo "$(date): LabLivre v3 (Gráfico) iniciado" >> "$ARQUIVO_HISTORICO" 2>/dev/null

while true; do
    ESCOLHA=$(mostrar_dashboard)
    
    if [ $? -ne 0 ] || [ -z "$ESCOLHA" ]; then
        echo "$(date): LabLivre v3 encerrado" >> "$ARQUIVO_HISTORICO" 2>/dev/null
        exit 0
    fi
    
    case $ESCOLHA in
        1) bash xmodulos/xatualizar_ips.sh ;;
        2) bash xmodulos/xligar_labold.sh ;;
        3) bash xmodulos/xdesligar_labold.sh ;;
        4) bash xmodulos/xmodo_prova.sh ;;
        5) testar_rede ;;
        6) bash xmodulos/xdistribuir_material.sh ;;
        7) bash xmodulos/xenviar_mensagem.sh ;;
        8) bash xmodulos/xsincronizar_horario.sh ;;
        9) bash xmodulos/xcoletar_inventario.sh ;;
        10) bash xmodulos/xmanutencao_sistema.sh ;;
        11) bash xmodulos/xcorrigir_quebrados.sh ;;
        12) bash xmodulos/xdiagnosticar_ssh.sh ;;
        13)
            REL_ESCOLHIDO=$(zenity --file-selection --title="Selecione o Relatório" --filename="$(pwd)/logs/" --file-filter="*.txt")
            if [ -n "$REL_ESCOLHIDO" ]; then
                zenity --text-info --title="Visualizador" --width=1000 --height=600 --filename="$REL_ESCOLHIDO" --font="Monospace 10"
            fi
            ;;
        14) gerar_relatorio_completo ;;
        15) bash modulos/abrir_portal_web.sh ;;
        16) bash xmodulos/xlimpar_downloads.sh ;;
        99)
            bash xmodulos/xconfigurar_lab.sh
            # Recarrega conf após configuração
            [ -f "$CONF_FILE" ] && source "$CONF_FILE"
            LAB_NOME="${LAB_NOME:-LabLivre}"
            ;;
        
        20) (xdg-open "http://localhost:8080/dashboard_operacional.html") > /dev/null 2>&1 & ;;
        21) (xdg-open "http://localhost:8080/dashboard_tv.html") > /dev/null 2>&1 & ;;
        22) (xdg-open "http://localhost:8080/dashboard_prova.html") > /dev/null 2>&1 & ;;
        23) (xdg-open "http://localhost:8080/dashboard_hacker.html") > /dev/null 2>&1 & ;;
        24) (xdg-open "http://localhost:8080/dashboard_auditoria.html") > /dev/null 2>&1 & ;;
        25) (xdg-open "http://localhost:8080/inventario.html") > /dev/null 2>&1 & ;;
        26) (xdg-open "http://localhost:8080/mapa_calor.html") > /dev/null 2>&1 & ;;
        
        0) exit 0 ;;
        *) zenity --error --text="Opção inválida!" --width=300 ;;
    esac
done
