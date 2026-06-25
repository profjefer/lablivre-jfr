#!/bin/bash

# _dryrun.sh — Suporte a modo de simulação
# Quando DRYRUN=1 (env ou flag --dry-run), comandos SSH viram echo.
#
# Funciona em conjunto com _ssh.sh — sobrescreve a função ssh_remote
# quando em modo dry-run.

# Detecta flag --dry-run nos argumentos do script chamador
for arg in "$@"; do
    case "$arg" in
        --dry-run|-n) DRYRUN=1 ;;
    esac
done

if [ "${DRYRUN:-0}" = "1" ]; then
    echo "========================================================"
    echo "         🔬 MODO DRY-RUN — NENHUMA AÇÃO EXECUTADA       "
    echo "         Comandos serão apenas exibidos.                "
    echo "========================================================"

    # Sobrescreve ssh_remote/ssh_remote_stdin para apenas exibir
    ssh_remote() {
        local ip="$1"
        local cmd="$2"
        echo "  [DRY-RUN] ssh $LAB_USUARIO@$ip \"$cmd\""
        return 0
    }

    ssh_remote_stdin() {
        local ip="$1"
        local cmd="$2"
        echo "  [DRY-RUN] echo \$PAYLOAD | ssh $LAB_USUARIO@$ip \"$cmd\""
        return 0
    }

    scp_remote() {
        local origem="$1"
        local destino="$2"
        echo "  [DRY-RUN] scp $origem $LAB_USUARIO@$destino"
        return 0
    }
fi
