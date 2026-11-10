#!/bin/bash
# ================================================================
# _xmotor.sh — Janelas zenity por cima dos motores do menu texto
#
# Os xmodulos não repetem a lógica: chamam o mesmo script de
# modulos/ que o menu texto usa, mostram o andamento numa barra e
# o resultado numa janela. Texto e gráfico fazem sempre a mesma coisa.
#
#   x_motor "Título" "Texto da barra" "respostas-stdin" modulos/x.sh [args...]
#
# "respostas-stdin" são as respostas que o motor pediria no terminal
# (uma por linha), ex.: "$MENSAGEM"$'\n'"1". Use "" para nenhuma.
# Retorna o código de saída do motor; a saída fica em $X_SAIDA_TXT.
# ================================================================

x_escapar() { sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'; }

x_motor() {
    local titulo="$1" texto="$2" entrada="$3" saida pid
    shift 3
    saida=$(mktemp)
    ( printf '%s\n' "$entrada" | bash "$@" > "$saida" 2>&1; echo $? > "$saida.rc" ) &
    pid=$!
    (
        while kill -0 "$pid" 2>/dev/null; do
            # (a barra do zenity mostra o texto cru: sem escapar, senão aparece "&gt;")
            echo "# $(grep -v '^\s*$' "$saida" | tail -n 1 | sed 's/^>> *//' | cut -c1-90)"
            sleep 0.5
        done
    ) | zenity --progress --pulsate --auto-close --no-cancel \
            --title="$titulo" --text="$texto" --width=520 2>/dev/null
    wait "$pid"
    X_RC=$(cat "$saida.rc" 2>/dev/null || echo 1)
    X_SAIDA_TXT=$(cat "$saida")
    # Resumo no topo, saída completa embaixo
    {
        grep -E '^\[(CONCLU|ENVIADO|ERRO)|^Resumo:|^🟢|^🔴|^⚠️|^📶|^Velocidade' "$saida"
        echo "────────────────────────────────────────────────────────"
        cat "$saida"
    } > "$saida.view"
    zenity --text-info --title="$titulo — resultado" --width=780 --height=540 \
        --font="Monospace 10" --filename="$saida.view" 2>/dev/null
    rm -f "$saida" "$saida.rc" "$saida.view"
    return "$X_RC"
}

# Abre um comando num terminal (para o que pede senha do sudo).
# Retorna 1 se não houver emulador de terminal.
x_terminal() {
    local cmd="$1; echo; read -r -p 'ENTER para fechar...' _"
    if command -v gnome-terminal >/dev/null 2>&1; then
        gnome-terminal --wait -- bash -c "$cmd" 2>/dev/null
    elif command -v x-terminal-emulator >/dev/null 2>&1; then
        x-terminal-emulator -e bash -c "$cmd" 2>/dev/null
    elif command -v xterm >/dev/null 2>&1; then
        xterm -e bash -c "$cmd"
    else
        return 1
    fi
}
