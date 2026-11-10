#!/bin/bash
# ================================================================
# modulos/remoto/sincronizar_horario.sh — roda NA MÁQUINA DO ALUNO
#
#     ssh ... "bash -s -- EPOCH_DO_ORQUESTRADOR"
#   (SENHA do sudo prefixada no stdin)
#
# 1. Ativa o NTP (systemd-timesyncd) — o relógio se mantém certo sozinho.
# 2. Se a diferença para o orquestrador passar de 5 s e o NTP não estiver
#    sincronizado (rede bloqueia NTP externo, Modo Prova ativo...), acerta
#    o relógio pela hora do orquestrador.
#
# Saída: __STATUS=OK | AJUSTADO | ERRO_SUDO | ERRO   e   __DIFERENCA=<s>
# ================================================================

comosudo() {
    if sudo -n true 2>/dev/null; then
        sudo -n "$@"
    else
        printf '%s\n' "${SENHA:-}" | sudo -S -p '' "$@"
    fi
}

principal() {
    local ref="$1" t0 dif sinc
    t0=$(date +%s)          # mede a diferença antes de qualquer espera
    [[ "$ref" =~ ^[0-9]+$ ]] || { echo "__STATUS=ERRO"; return 1; }
    comosudo true 2>/dev/null || { echo "__STATUS=ERRO_SUDO"; return 1; }

    if command -v timedatectl >/dev/null 2>&1; then
        comosudo timedatectl set-ntp true >/dev/null 2>&1
        comosudo systemctl restart systemd-timesyncd >/dev/null 2>&1
        sleep 2
        sinc=$(timedatectl show -p NTPSynchronized --value 2>/dev/null)
    fi

    dif=$(( t0 - ref ))
    echo "__DIFERENCA=$dif"

    if [ "${dif#-}" -gt 5 ] && [ "$sinc" != "yes" ]; then
        # hora do orquestrador + o tempo que passou aqui desde a chegada
        if comosudo date -s "@$(( ref + $(date +%s) - t0 ))" >/dev/null 2>&1; then
            echo "__STATUS=AJUSTADO"
        else
            echo "__STATUS=ERRO"
            return 1
        fi
    else
        echo "__STATUS=OK"
    fi
}

principal "$@" < /dev/null
