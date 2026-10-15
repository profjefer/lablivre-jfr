#!/bin/bash
# ================================================================
# enviar_mensagem.sh — Mensagem para as máquinas dos alunos
#
# A mensagem vai em base64 e o script remoto (modulos/remoto/
# mostrar_mensagem.sh) segue pelo stdin do SSH: aspas, acentos,
# & < > e quebras não quebram mais o comando.
# ================================================================

cd "$(dirname "$0")/.." || exit 1

source modulos/_comum.sh && carregar_conf && exigir_ips || exit 1
source modulos/_log.sh 2>/dev/null || true
source modulos/_dryrun.sh "$@" 2>/dev/null || true

SCRIPT_REMOTO="modulos/remoto/mostrar_mensagem.sh"
RELATORIO="logs/relatorio_mensagens.txt"
mkdir -p logs

echo "========================================================"
echo "               📩 ENVIO DE MENSAGENS                    "
echo "========================================================"
read -r -e -p "Digite a mensagem para a turma: " MENSAGEM

if [ -z "${MENSAGEM// /}" ]; then
    echo "[ERRO] A mensagem não pode ser vazia."
    exit 1
fi

echo "--------------------------------------------------------"
echo "1) 🖥️  Pop-up na tela (zenity)"
echo "2) ⬛ Terminal (wall) — só aparece em terminais abertos"
echo "3) 📣 Os dois"
echo "--------------------------------------------------------"
read -r -p "Escolha o formato (1, 2 ou 3): " TIPO_MSG

case "$TIPO_MSG" in
    1) MODO="popup"; TIPO_NOME="Pop-up" ;;
    2) MODO="wall";  TIPO_NOME="Terminal (wall)" ;;
    3) MODO="ambos"; TIPO_NOME="Pop-up + Terminal" ;;
    *) echo "[ERRO] Opção inválida."; exit 1 ;;
esac

MSG_B64=$(printf '%s' "$MENSAGEM" | base64 -w0)

echo ">> Disparando mensagem ($TIPO_NOME)..."
echo "--------------------------------------------------------"
{
    echo "Envio de mensagem — $(date '+%d/%m/%Y %H:%M:%S')"
    echo "Formato : $TIPO_NOME"
    echo "Mensagem: $MENSAGEM"
    echo "--------------------------------------------------------"
} > "$RELATORIO"

TOTAL=0; OK=0

explicar() {
    case "$1" in
        OK)          echo "ok" ;;
        SEM_SESSAO)  echo "ninguém logado na tela" ;;
        SEM_TELA)    echo "não achou a tela da sessão gráfica" ;;
        SEM_ZENITY)  echo "zenity não instalado" ;;
        ZENITY_FALHOU) echo "o pop-up não abriu (zenity fechou na hora)" ;;
        SEM_SUDO*)   echo "tela aberta por outro usuário ${1#SEM_SUDO} e o sudo falhou" ;;
        ERRO_WALL)   echo "wall falhou" ;;
        *)           echo "$1" ;;
    esac
}

traduzir_status() {
    local popup wall
    if [[ "$1" == *+* ]]; then            # modo "ambos": POPUP+WALL
        popup="${1%%+*}"; wall="${1#*+}"
        if [ "$popup" = OK ] && [ "$wall" = OK ]; then echo "[OK]"
        elif [ "$popup" = OK ] || [ "$wall" = OK ]; then
            echo "[PARCIAL] pop-up: $(explicar "$popup") · terminal: $(explicar "$wall")"
        else
            echo "[ERRO] pop-up: $(explicar "$popup") · terminal: $(explicar "$wall")"
        fi
    elif [ "$1" = OK ]; then
        echo "[OK]"
    elif [ "$1" = SEM_SESSAO ]; then
        echo "[SEM ALUNO] $(explicar "$1")"
    else
        echo "[ERRO] $(explicar "$1")"
    fi
}

enviar_para() {
    local mac="$1" ip="$2" nome="$3" saida rc status resultado
    ((TOTAL++))
    printf "Enviando para: %-26s " "$nome ($ip)..."

    saida=$(rodar_remoto "$ip" "$SCRIPT_REMOTO" "$MODO" "$MSG_B64")
    rc=$?
    status=$(status_remoto "$saida")

    if lab_dryrun; then
        resultado="[DRY-RUN]"
    elif [ -z "$status" ]; then
        resultado="[ERRO] $(erro_ssh "$rc")"
    else
        resultado=$(traduzir_status "$status")
    fi

    [[ "$resultado" == "[OK]"* ]] && ((OK++))
    echo "$resultado"
    echo "$nome ($ip): $resultado" >> "$RELATORIO"
}

para_cada_maquina enviar_para

echo "--------------------------------------------------------"
echo "[CONCLUÍDO] Mensagem entregue em $OK de $TOTAL máquinas online."
echo ">> Relatório: $RELATORIO"
echo "Resultado: $OK de $TOTAL" >> "$RELATORIO"
lab_dryrun || log_acao "enviar_mensagem" "formato=$MODO entregues=$OK de=$TOTAL" 2>/dev/null || true
