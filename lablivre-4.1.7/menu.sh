#!/bin/bash

# Resolve o caminho real, mesmo quando chamado via symlink
# (ex: /usr/local/bin/lablivre → /opt/lablivre/menu.sh)
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
    DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
    SOURCE="$(readlink "$SOURCE")"
    [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"

if [ -d "$SCRIPT_DIR/modulos" ]; then
    cd "$SCRIPT_DIR" || exit 1
elif [ -d "$SCRIPT_DIR/../modulos" ]; then
    cd "$SCRIPT_DIR/.." || exit 1
else
    echo "[ERRO] Não foi possível localizar a raiz do projeto LabLivre."
    exit 1
fi

# Suporte a modo dry-run (passa adiante para os módulos via env)
export DRYRUN=0
for arg in "$@"; do
    case "$arg" in
        --dry-run|-n) export DRYRUN=1 ;;
    esac
done

# ================================================
# PRIMEIRA EXECUÇÃO: conf não existe ainda
# ================================================
if [ ! -f "configs/lablivre.conf" ]; then
    clear
    echo "========================================================"
    echo "   ⚠️  PRIMEIRA EXECUÇÃO DETECTADA — BEM-VINDO!        "
    echo "========================================================"
    echo ""
    echo "  O arquivo configs/lablivre.conf não foi encontrado."
    echo "  Iniciando configuração inicial agora..."
    echo ""
    read -p "  Pressione ENTER para continuar..."
    bash configurar_lab.sh
fi

# ================================================
# CARREGA CONFIGURAÇÕES
# ================================================
CONF_FILE="configs/lablivre.conf"
source "$CONF_FILE"
LAB_NOME="${LAB_NOME:-LabLivre}"

# Detecta modo de autenticação para exibir no cabeçalho
if [ -f "configs/lablivre_key" ] && [ "${LAB_AUTH_MODE:-}" = "chave" ]; then
    AUTH_INFO="🔐 Chave SSH"
elif [ -f "configs/lablivre_key" ]; then
    AUTH_INFO="🔓 Senha (chave disponível mas inativa)"
else
    AUTH_INFO="🔓 Senha em texto puro — execute opção 12 para migrar"
fi

# ================================================
# AVISO: macs.txt vazio
# ================================================
if [ ! -s "configs/macs.txt" ]; then
    clear
    echo "========================================================"
    echo "   ⚠️  ATENÇÃO: configs/macs.txt está vazio!           "
    echo "========================================================"
    echo ""
    echo "  Sem a lista de MACs o mapeamento de rede não funciona."
    echo "  Preencha antes de usar: nano configs/macs.txt"
    echo "  Formato:  aa:bb:cc:dd:ee:ff   nome-da-maquina"
    echo ""
    read -p "  Pressione ENTER para entrar no menu mesmo assim..."
fi

# ================================================
# MENU PRINCIPAL
# ================================================
while true; do
    # Contagem de máquinas online/offline a partir do ips_atuais.txt
    if [ -f "ips_atuais.txt" ]; then
        TOTAL=$(tail -n +3 ips_atuais.txt | grep -v "ESTA MÁQUINA" | wc -l)
        ONLINE=$(tail -n +3 ips_atuais.txt | grep -v "ESTA MÁQUINA" | awk '$2 != "OFFLINE"' | wc -l)
        OFFLINE=$((TOTAL - ONLINE))
        INFO_REDE="🟢 ${ONLINE} online  🔴 ${OFFLINE} offline  (${TOTAL} total)"
    else
        INFO_REDE="⚠️  Execute opção 1 para mapear a rede"
    fi

    # Status do modo prova
    if [ -f "logs/modo_prova.status" ]; then
        DESDE=$(cat logs/modo_prova.status)
        INFO_PROVA="🔴 MODO PROVA ATIVO desde $DESDE"
    else
        INFO_PROVA="🟢 Internet liberada"
    fi

    clear
    echo "========================================================"
    echo "  Auth : $AUTH_INFO"
    echo "========================================================"
    echo "      LabLivre — Orquestrador $LAB_NOME"
    echo "========================================================"
    echo "  Rede  : $INFO_REDE"
    echo "  Prova : $INFO_PROVA"
    echo "========================================================"
    echo "99 - ⚙️  Configurações Globais (Usuário, Senha, Lab)"
    echo "--------------------------------------------------------"
    echo "1  - 📡 Mapear Rede (Atualizar IPs manualmente)"
    echo "2  - 📚 Distribuir Material Didático (Área de Trabalho)"
    echo "3  - 🔒 Controle de Rede (Ativar/Desativar Modo Prova)"
    echo "4  - 📊 Inventário de Hardware (CPU/RAM/Disco/BIOS → TXT + HTML)"
    echo "5  - 💬 Enviar Mensagem (Terminal ou Pop-up)"
    echo "6  - ⚡ Ligar Laboratório (Wake-on-LAN)"
    echo "7  - 🔌 Desligar Laboratório (Shutdown Remoto)"
    echo "8  - 🛠️  Manutenção do Sistema (APT Update/Install)"
    echo "9  - 💊 Corrigir Repositórios Quebrados (Vacina APT)"
    echo "10 - 🔍 Diagnosticar Conexão SSH das Máquinas"
    echo "11 - 📜 Ver Auditoria (logs estruturados)"
    echo "12 - 🔐 Configurar Chave SSH (segurança)"
    echo "13 - 🌐 Abrir Portal Web (dashboards e inventário)"
    echo "14 - 📄 Relatório de Status (TXT rápido)"
    echo "--------------------------------------------------------"
    echo "0  - ❌ Sair"
    echo "========================================================"
    read -p "Escolha uma opção: " OPCAO

    echo ""
    case $OPCAO in
        1)
            echo "Iniciando varredura na rede. Aguarde..."
            bash modulos/atualizar_ips.sh
            ;;
        2)  bash modulos/distribuir_material.sh ;;
        3)  bash modulos/modo_prova.sh ;;
        4)  bash modulos/coletar_inventario.sh ;;
        5)  bash modulos/enviar_mensagem.sh ;;
        6)  bash modulos/ligar_labold.sh ;;
        7)  bash modulos/desligar_labold.sh ;;
        8)  bash modulos/manutencao_sistema.sh ;;
        9)  bash modulos/corrigir_quebrados.sh ;;
        10) bash modulos/diagnosticar_ssh.sh ;;
        11) bash modulos/ver_auditoria.sh ;;
        12) bash modulos/configurar_chave_ssh.sh ;;
        13) bash modulos/abrir_portal_web.sh ;;
        14) bash modulos/relatorio_status.sh ;;
        99)
            bash configurar_lab.sh
            source "$CONF_FILE"
            LAB_NOME="${LAB_NOME:-LabLivre}"

# Detecta modo de autenticação para exibir no cabeçalho
if [ -f "configs/lablivre_key" ] && [ "${LAB_AUTH_MODE:-}" = "chave" ]; then
    AUTH_INFO="🔐 Chave SSH"
elif [ -f "configs/lablivre_key" ]; then
    AUTH_INFO="🔓 Senha (chave disponível mas inativa)"
else
    AUTH_INFO="🔓 Senha em texto puro — execute opção 12 para migrar"
fi
            ;;
        0)  echo "Saindo do LabLivre. Até logo!"; exit 0 ;;
        *)  echo "Opção inválida! Tente novamente." ;;
    esac

    echo ""
    read -p "Pressione ENTER para voltar ao menu principal..."
done
