#!/bin/bash

# _instalar_deps.sh — Instala dependências necessárias do LabLivre
# Pode ser chamado idempotentemente (só instala o que falta)
# Uso: source modulos/_instalar_deps.sh && instalar_deps_lablivre

instalar_deps_lablivre() {
    # Lista completa de pacotes necessários
    local DEPS=(
        nmap            # mapeamento de rede com ARP ping
        sshpass         # autenticação SSH por senha
        zenity          # diálogos gráficos (menu gráfico)
        wakeonlan       # ligar máquinas remotamente
        ethtool         # info de placa de rede e WoL
        dmidecode       # info de BIOS no inventário
        netcat-openbsd  # diagnóstico SSH (porta 22)
        python3         # servidor web embutido + parse JSON
        jq              # processar JSON na linha de comando
        bc              # cálculos (% no xmenu)
        avahi-utils     # opcional, descoberta mDNS
    )

    # ntpdate é fallback do timedatectl — instala só se timedatectl não existir
    if ! command -v timedatectl >/dev/null 2>&1; then
        DEPS+=(ntpdate)
    fi

    # Detecta o que falta
    local FALTANDO=()
    for dep in "${DEPS[@]}"; do
        # netcat-openbsd fornece o comando 'nc'
        local cmd_check
        case "$dep" in
            netcat-openbsd) cmd_check="nc" ;;
            avahi-utils)    cmd_check="avahi-browse" ;;
            *)              cmd_check="$dep" ;;
        esac
        if ! command -v "$cmd_check" >/dev/null 2>&1; then
            FALTANDO+=("$dep")
        fi
    done

    if [ ${#FALTANDO[@]} -eq 0 ]; then
        echo "[deps] ✓ Todas as dependências já instaladas."
        return 0
    fi

    echo "[deps] Faltam ${#FALTANDO[@]} pacote(s): ${FALTANDO[*]}"
    echo "[deps] Instalando..."

    # Detecta gestor de pacotes (apt, dnf, pacman)
    if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update -qq
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${FALTANDO[@]}"
    elif command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y "${FALTANDO[@]}"
    elif command -v pacman >/dev/null 2>&1; then
        sudo pacman -S --noconfirm "${FALTANDO[@]}"
    else
        echo "[deps] ⚠ Gestor de pacotes não detectado. Instale manualmente:"
        echo "       ${FALTANDO[*]}"
        return 1
    fi

    # Validação pós-instalação
    local AINDA_FALTANDO=()
    for dep in "${FALTANDO[@]}"; do
        local cmd_check
        case "$dep" in
            netcat-openbsd) cmd_check="nc" ;;
            avahi-utils)    cmd_check="avahi-browse" ;;
            *)              cmd_check="$dep" ;;
        esac
        command -v "$cmd_check" >/dev/null 2>&1 || AINDA_FALTANDO+=("$dep")
    done

    if [ ${#AINDA_FALTANDO[@]} -gt 0 ]; then
        echo "[deps] ⚠ Alguns pacotes não puderam ser instalados: ${AINDA_FALTANDO[*]}"
        echo "[deps] Tente manualmente: sudo apt install ${AINDA_FALTANDO[*]}"
        return 1
    fi

    echo "[deps] ✓ Todas as dependências instaladas com sucesso."
    return 0
}

# Se chamado diretamente (não via source), executa
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    instalar_deps_lablivre
fi
