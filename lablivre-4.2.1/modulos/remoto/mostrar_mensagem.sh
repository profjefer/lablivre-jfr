#!/bin/bash
# ================================================================
# modulos/remoto/mostrar_mensagem.sh — roda NA MÁQUINA DO ALUNO
#
# Enviado pelo enviar_mensagem.sh via stdin:
#     ssh ... "bash -s -- MODO MENSAGEM_BASE64 [TITULO_BASE64]"
#   MODO: popup | wall | ambos
#   A variável SENHA (sudo) pode vir prefixada no stdin — só é usada
#   se a tela estiver aberta por OUTRO usuário que não o do SSH.
#
# Por que não basta DISPLAY=:0: no Ubuntu 24.04 a sessão costuma ser
# Wayland e o zenity precisa de WAYLAND_DISPLAY/XAUTHORITY/DBUS da
# sessão real. Este script copia o ambiente de um processo da sessão
# gráfica que já está aberta.
#
# Saída: uma linha "__STATUS=..." que o orquestrador interpreta.
# ================================================================

# sudo sem expor a senha: tenta sem senha; senão manda pelo stdin.
# (Não usa "sudo -v" + "sudo -n": numa sessão SSH sem terminal o
#  cache do sudo pode não valer para o comando seguinte.)
comosudo() {
    if sudo -n true 2>/dev/null; then
        sudo -n "$@"
    else
        printf '%s\n' "${SENHA:-}" | sudo -S -p '' "$@"
    fi
}

TITULO="Mensagem do Professor"

principal() {
    local MODO="$1" MSG
    MSG=$(printf '%s' "$2" | base64 -d 2>/dev/null)
    if [ -z "$MSG" ]; then echo "__STATUS=ERRO_MSG"; return 1; fi
    if [ -n "${3:-}" ]; then
        TITULO=$(printf '%s' "$3" | base64 -d 2>/dev/null)
        [ -z "$TITULO" ] && TITULO="Mensagem do Professor"
    fi

    local ST_POPUP="" ST_WALL=""
    if [ "$MODO" = "popup" ] || [ "$MODO" = "ambos" ]; then
        ST_POPUP=$(mostrar_popup "$MSG")
    fi
    if [ "$MODO" = "wall" ] || [ "$MODO" = "ambos" ]; then
        if printf '%s:\n%s\n' "${TITULO^^}" "$MSG" | wall 2>/dev/null; then
            ST_WALL="OK"
        else
            ST_WALL="ERRO_WALL"
        fi
    fi

    case "$MODO" in
        popup) echo "__STATUS=$ST_POPUP" ;;
        wall)  echo "__STATUS=$ST_WALL" ;;
        *)     echo "__STATUS=${ST_POPUP}+${ST_WALL}" ;;
    esac
}

# Usuário dono da sessão gráfica ativa e local (não SSH)
usuario_grafico() {
    local sid uid user resto tipo ativo remoto
    while read -r sid uid user resto; do
        [ -z "$sid" ] && continue
        tipo=$(loginctl show-session "$sid" -p Type --value 2>/dev/null)
        ativo=$(loginctl show-session "$sid" -p Active --value 2>/dev/null)
        remoto=$(loginctl show-session "$sid" -p Remote --value 2>/dev/null)
        if [ "$ativo" = "yes" ] && [ "$remoto" != "yes" ] && { [ "$tipo" = "x11" ] || [ "$tipo" = "wayland" ]; }; then
            echo "$user"; return 0
        fi
    done < <(loginctl list-sessions --no-legend 2>/dev/null)
    # Plano B: who mostra (:0) para login gráfico
    who 2>/dev/null | awk '/\(:[0-9]/ {print $1; exit}'
}

# Imprime VAR=valor do ambiente gráfico de um processo do usuário (uid)
ambiente_grafico_de() {
    local pid
    for pid in $(pgrep -u "$1" 2>/dev/null); do
        [ -r "/proc/$pid/environ" ] || continue
        if tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | grep -qE '^(WAYLAND_DISPLAY|DISPLAY)='; then
            tr '\0' '\n' < "/proc/$pid/environ" \
                | grep -E '^(DISPLAY|WAYLAND_DISPLAY|XAUTHORITY|DBUS_SESSION_BUS_ADDRESS|XDG_RUNTIME_DIR)='
            return 0
        fi
    done
    return 1
}

mostrar_popup() {
    local msg="$1" alvo eu texto pid
    command -v zenity >/dev/null 2>&1 || { echo "SEM_ZENITY"; return 1; }

    eu=$(id -un)
    alvo=$(usuario_grafico)
    [ -z "$alvo" ] && { echo "SEM_SESSAO"; return 1; }

    # zenity interpreta marcação Pango: escapa & < >
    # (sed, não ${x//a/b}: no bash 5.2 o "&" da substituição vira o texto achado)
    texto=$(printf '%s' "$msg" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g')
    local ZEN=(zenity --warning --title="$TITULO" --text="$texto" --width=550)

    local -a ENVS
    if [ "$alvo" = "$eu" ]; then
        mapfile -t ENVS < <(ambiente_grafico_de "$(id -u)")
        [ "${#ENVS[@]}" -eq 0 ] && { echo "SEM_TELA"; return 1; }
        env "${ENVS[@]}" setsid "${ZEN[@]}" >/dev/null 2>&1 < /dev/null &
        pid=$!
    else
        # Tela aberta por outro usuário: precisa de sudo
        if ! comosudo true 2>/dev/null; then
            echo "SEM_SUDO($alvo)"; return 1
        fi
        mapfile -t ENVS < <(comosudo bash -c "$(declare -f ambiente_grafico_de); ambiente_grafico_de $(id -u "$alvo")")
        [ "${#ENVS[@]}" -eq 0 ] && { echo "SEM_TELA"; return 1; }
        comosudo -u "$alvo" env "${ENVS[@]}" setsid "${ZEN[@]}" >/dev/null 2>&1 &
        pid=$!
    fi

    # Se o zenity não conseguiu abrir a janela, ele morre logo
    sleep 1.5
    if kill -0 "$pid" 2>/dev/null; then
        echo "OK"
    else
        echo "ZENITY_FALHOU"
        return 1
    fi
}

# Tudo com stdin em /dev/null: o próprio script chega pelo stdin
# (bash -s) e nenhum comando pode "comer" o restante dele.
principal "$@" < /dev/null
