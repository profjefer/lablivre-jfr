#!/bin/bash

# _ssh.sh — Wrapper único para conexões SSH do LabLivre
# Decide automaticamente entre autenticação por CHAVE ou SENHA.
#
# Uso:
#   source modulos/_ssh.sh
#   ssh_remote "$ip" "comando"           # SSH
#   scp_remote arquivo "$ip:/destino"    # SCP
#   tar_pipe_remote pasta "$ip" "$cmd"   # Tar-pipe streaming
#
# Modo de autenticação (definido pelo lablivre.conf):
#   LAB_AUTH_MODE="senha"   → usa sshpass + $LAB_SENHA (padrão, compatível)
#   LAB_AUTH_MODE="chave"   → usa configs/lablivre_key (mais seguro)
#
# Detecção automática: se LAB_AUTH_MODE não definido mas existe a chave, usa chave.

CONF_FILE="configs/lablivre.conf"
[ -f "$CONF_FILE" ] && source "$CONF_FILE"

CHAVE_SSH="configs/lablivre_key"

# Determina modo automático se não explicitado
if [ -z "${LAB_AUTH_MODE:-}" ]; then
    if [ -f "$CHAVE_SSH" ]; then
        LAB_AUTH_MODE="chave"
    else
        LAB_AUTH_MODE="senha"
    fi
fi

# Opções SSH comuns
SSH_OPTS=(
    -o StrictHostKeyChecking=no
    -o UserKnownHostsFile=/dev/null
    -o ConnectTimeout=5
    -o LogLevel=ERROR
    -q
)

# === SSH remoto ===
# Uso: ssh_remote "ip" "comando" [extra_opts...]
ssh_remote() {
    local ip="$1"
    local cmd="$2"
    shift 2

    if [ "$LAB_AUTH_MODE" = "chave" ] && [ -f "$CHAVE_SSH" ]; then
        ssh -n -i "$CHAVE_SSH" "${SSH_OPTS[@]}" "$@" "$LAB_USUARIO@$ip" "$cmd"
    else
        sshpass -p "$LAB_SENHA" ssh -n "${SSH_OPTS[@]}" "$@" "$LAB_USUARIO@$ip" "$cmd"
    fi
}

# === SSH sem -n (para receber stdin via pipe, ex: payload do inventário) ===
ssh_remote_stdin() {
    local ip="$1"
    local cmd="$2"
    shift 2

    if [ "$LAB_AUTH_MODE" = "chave" ] && [ -f "$CHAVE_SSH" ]; then
        ssh -i "$CHAVE_SSH" "${SSH_OPTS[@]}" "$@" "$LAB_USUARIO@$ip" "$cmd"
    else
        sshpass -p "$LAB_SENHA" ssh "${SSH_OPTS[@]}" "$@" "$LAB_USUARIO@$ip" "$cmd"
    fi
}

# === SCP remoto ===
# Uso: scp_remote arquivo_local "ip:/destino"
scp_remote() {
    local origem="$1"
    local destino="$2"

    if [ "$LAB_AUTH_MODE" = "chave" ] && [ -f "$CHAVE_SSH" ]; then
        scp -i "$CHAVE_SSH" "${SSH_OPTS[@]}" "$origem" "$LAB_USUARIO@$destino"
    else
        sshpass -p "$LAB_SENHA" scp "${SSH_OPTS[@]}" "$origem" "$LAB_USUARIO@$destino"
    fi
}

# === Verifica se está usando modo chave ===
ssh_modo_chave() {
    [ "$LAB_AUTH_MODE" = "chave" ] && [ -f "$CHAVE_SSH" ]
}

# === Diagnóstico ===
# Verifica se a chave SSH foi distribuída para um IP
ssh_testar_chave() {
    local ip="$1"
    [ ! -f "$CHAVE_SSH" ] && return 1
    ssh -n -i "$CHAVE_SSH" \
        -o StrictHostKeyChecking=no \
        -o PasswordAuthentication=no \
        -o BatchMode=yes \
        -o ConnectTimeout=3 \
        "$LAB_USUARIO@$ip" "exit" 2>/dev/null
}
