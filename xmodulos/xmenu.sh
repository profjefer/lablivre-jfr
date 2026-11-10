#!/bin/bash

export LIBGL_ALWAYS_SOFTWARE=1

# Silencia warnings inofensivos do GTK/GLib que aparecem em sessões SSH -X/-Y
# (ex: "GLib-GObject-CRITICAL g_object_unref: assertion 'G_IS_OBJECT' failed")
# Mantém erros reais visíveis, filtra só o ruído conhecido.
export NO_AT_BRIDGE=1
export G_MESSAGES_DEBUG=""
# Ruído inofensivo do GTK/zenity (sessão SSH -X, zenity 4 do Ubuntu 24.04)
export ZENITY_RUIDO="GLib-GObject-CRITICAL|GLib-GIO-CRITICAL|g_object_unref|assertion '|Gtk-Message|transient parent|descontinuad|deprecated"
zenity() {
    command zenity "$@" 2> >(grep -v -E "$ZENITY_RUIDO" >&2)
}
export -f zenity      # vale também para os xmodulos chamados pelo menu

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

LAB_GUI=1
source modulos/_comum.sh      # abrir_pagina_web, caminhos
source xmodulos/_xmotor.sh    # x_motor, x_terminal

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
    # Remapeia ANTES de testar (o teste antigo usava o mapa velho e
    # mostrava todas sem conexão) e testa ping + porta 22.
    x_motor "Teste de Conexão" "Mapeando a rede e testando..." "" modulos/testar_conexao.sh
}

ver_logs() {
    # Lista os relatórios do mais novo para o mais antigo e abre o escolhido
    local itens=() f escolhido
    while IFS= read -r f; do
        itens+=("$f" "$(date -r "$f" '+%d/%m %H:%M')" "$(du -h "$f" | cut -f1)")
    done < <(ls -t logs/*.txt logs/*.log 2>/dev/null)
    if [ "${#itens[@]}" -eq 0 ]; then
        zenity --info --text="Nenhum relatório em logs/ ainda." --width=300; return
    fi
    escolhido=$(zenity --list --title="📄 Relatórios e logs" --text="Mais recentes primeiro:" \
        --column="Arquivo" --column="Data" --column="Tamanho" \
        --width=640 --height=520 "${itens[@]}" 2>/dev/null)
    [ -n "$escolhido" ] && zenity --text-info --title="$escolhido" --width=1000 --height=600 \
        --filename="$escolhido" --font="Monospace 10" 2>/dev/null
}

saude_sistema() {
    local tmp; tmp=$(mktemp)
    bash modulos/saude_sistema.sh --so-verificar > "$tmp" 2>&1
    local rc=$?
    if [ "$rc" -eq 0 ]; then
        zenity --text-info --title="🩺 Saúde do Sistema" --width=820 --height=600 \
            --font="Monospace 10" --filename="$tmp" 2>/dev/null
    elif zenity --text-info --title="🩺 Saúde do Sistema — há problemas" --width=820 --height=600 \
            --font="Monospace 10" --filename="$tmp" \
            --ok-label="Corrigir (pede senha)" --cancel-label="Fechar" 2>/dev/null; then
        x_terminal "cd '$LAB_RAIZ' && bash modulos/saude_sistema.sh --corrigir" || \
            zenity --info --width=420 --text="Abra um terminal e rode:\n\n<tt>lablivre</tt> → opção 17 (Saúde do sistema)" 2>/dev/null
    fi
    rm -f "$tmp"
}

# --------------------------------------------------------
# FUNÇÃO 3: DASHBOARD E MENU PRINCIPAL
# --------------------------------------------------------
mostrar_dashboard() {
    local ONLINE=0
    local OFFLINE=0
    
    if [ -f "$ARQUIVO_IPS" ]; then
        while read -r mac ip nome resto; do
            [[ -z "$mac" ]] && continue
            [[ "$resto" == *"(ESTA MÁQUINA)"* ]] && continue
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
    local IDADE="?"
    [ -f "$ARQUIVO_IPS" ] && IDADE=$(( ( $(date +%s) - $(stat -c %Y "$ARQUIVO_IPS") ) / 60 ))
    STATUS_TXT+=$(printf "║ 📊 TOTAL:   %3d máquinas · mapa de %s min atrás" "$TOTAL" "$IDADE")" ║\n"

    # Status do modo prova
    if [ -f "$FLAG_PROVA" ]; then
        local PROVA_DESDE=$(cat "$FLAG_PROVA")
        STATUS_TXT+=$(printf "║ 🔴 MODO PROVA ATIVO desde %s" "$PROVA_DESDE")" ║\n"
    else
        STATUS_TXT+="║ 🟢 Internet liberada (modo prova desativado)                              ║\n"
    fi

    STATUS_TXT+="║ 🌐 Portal: $(url_portal) (opção 15)\n"
    STATUS_TXT+="╚══════════════════════════════════════════════════════════════════════════╝"
    
    # Zenity List com as contra-barras corrigidas em todas as linhas
    zenity --list \
        --title="🌟 LabLivre — $LAB_NOME" \
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
        "5" "📡 Rede" "Teste de Conexão" "Remapeia e testa ping + SSH" "📊" \
        "6" "📚 Pedagógico" "Distribuir Material" "Copia pastas para os alunos" "📁" \
        "7" "📚 Pedagógico" "Enviar Mensagem" "Envia popup ou texto" "💬" \
        "8" "📚 Pedagógico" "Sincronizar Horários" "Ajusta relógio via NTP" "⏰" \
        "9" "🛠 Administração" "Inventário do Lab" "Coleta hardware das máquinas" "📋" \
        "10" "🛠 Administração" "Manutenção" "Atualiza pacotes (apt-get)" "🔧" \
        "11" "🛠 Administração" "Corrigir Repositórios" "Vacina APT (remove repos quebrados)" "💊" \
        "12" "🛠 Administração" "Diagnosticar SSH" "Testa cada máquina e diz o que fazer" "🔍" \
        "18" "🛠 Administração" "Preparar Wake-on-LAN" "Deixa o WoL permanente (máquinas que não ligam)" "⚡" \
        "17" "🛠 Administração" "Saúde do Sistema" "Confere cron, servidor web e serviços (e corrige)" "🩺" \
        "16" "🛠 Administração" "Limpar Downloads" "Apaga Downloads e Lixeira das máquinas" "🧹" \
        "13" "📊 Relatórios" "Visualizar Logs" "Relatórios do mais novo ao mais antigo" "📄" \
        "14" "📊 Relatórios" "Tabela de Máquinas (web)" "Página única, sempre atualizada" "📑" \
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
        13) ver_logs ;;
        14) abrir_pagina_web maquinas.html >/dev/null ;;
        15) abrir_pagina_web >/dev/null ;;
        17) saude_sistema ;;
        18) x_motor "Preparar Wake-on-LAN" "Ajustando as máquinas online..." "" modulos/preparar_wol.sh ;;
        16) bash xmodulos/xlimpar_downloads.sh ;;
        99)
            bash xmodulos/xconfigurar_lab.sh
            # Recarrega conf após configuração
            [ -f "$CONF_FILE" ] && source "$CONF_FILE"
            LAB_NOME="${LAB_NOME:-LabLivre}"
            ;;
        
        20) abrir_pagina_web dashboard_operacional.html >/dev/null ;;
        21) abrir_pagina_web dashboard_tv.html >/dev/null ;;
        22) abrir_pagina_web dashboard_prova.html >/dev/null ;;
        23) abrir_pagina_web dashboard_hacker.html >/dev/null ;;
        24) abrir_pagina_web dashboard_auditoria.html >/dev/null ;;
        25) abrir_pagina_web inventario.html >/dev/null ;;
        26) abrir_pagina_web mapa_calor.html >/dev/null ;;
        
        0) exit 0 ;;
        *) zenity --error --text="Opção inválida!" --width=300 ;;
    esac
done
