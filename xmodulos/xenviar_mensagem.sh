#!/bin/bash
# xenviar_mensagem.sh — Enviar mensagem (versão gráfica)
# Sem lógica própria: janelas por cima de modulos/enviar_mensagem.sh,
# o mesmo motor do menu texto (pop-up Wayland/X11, base64, relatório).
cd "$(dirname "$0")/.." || exit 1
LAB_GUI=1
source modulos/_comum.sh && carregar_conf && exigir_ips || exit 1
source xmodulos/_xmotor.sh

MENSAGEM=$(zenity --entry --title="📩 Enviar Mensagem" \
    --text="Mensagem para a turma:" --width=480 2>/dev/null)
[ -z "${MENSAGEM// /}" ] && exit 0

TIPO=$(zenity --list --radiolist --title="Formato" --text="Como os alunos recebem?" \
    --column="" --column="ID" --column="Formato" \
    TRUE  1 "🖥️  Pop-up na tela (só aparece para quem está logado)" \
    FALSE 2 "⬛ Terminal (wall) — só em terminais abertos" \
    FALSE 3 "📣 Os dois" \
    --hide-column=2 --print-column=2 --width=480 --height=260 2>/dev/null)
[ -z "$TIPO" ] && exit 0

x_motor "Enviar Mensagem" "Enviando para as máquinas online..." \
    "$MENSAGEM"$'\n'"$TIPO" modulos/enviar_mensagem.sh
