#!/bin/bash

cd "$(dirname "$0")/.." || exit 1

CONF_FILE="configs/lablivre.conf"
if [ -f "$CONF_FILE" ]; then source "$CONF_FILE"; else LAB_USUARIO="ufpr"; LAB_SENHA="UFPR"; fi
source modulos/_ssh.sh 2>/dev/null || true
ARQUIVO_IPS="ips_atuais.txt"

echo "========================================================"
echo "               📩 ENVIO DE MENSAGENS                    "
echo "========================================================"
read -p "Digite a mensagem para a turma: " MENSAGEM

if [ -z "$MENSAGEM" ]; then
    echo "[ERRO] A mensagem não pode ser vazia."
    exit 1
fi

echo "--------------------------------------------------------"
echo "1) 🖥️  Mensagem Gráfica (Pop-up Zenity)"
echo "2) ⬛ Mensagem de Terminal (wall)"
echo "--------------------------------------------------------"
read -p "Escolha o formato (1 ou 2): " TIPO_MSG

if [[ "$TIPO_MSG" == "1" ]]; then
    PAYLOAD="export DISPLAY=:0; export XDG_RUNTIME_DIR=/run/user/\$(id -u); zenity --warning --title='Mensagem do Professor' --text='$MENSAGEM' --width=450 >/dev/null 2>&1 &"
    TIPO_NOME="Gráfica (Zenity)"
elif [[ "$TIPO_MSG" == "2" ]]; then
    PAYLOAD="echo 'MENSAGEM DO PROFESSOR: $MENSAGEM' | wall"
    TIPO_NOME="Terminal (Wall)"
else
    echo "[ERRO] Opção inválida."
    exit 1
fi

echo ">> Disparando Mensagem $TIPO_NOME..."
echo "--------------------------------------------------------"

while read -r mac ip nome resto; do
    if [[ -z "$mac" ]] || [[ "$ip" == "OFFLINE" ]] || [[ "$resto" == *"(ESTA MÁQUINA)"* ]]; then continue; fi

    echo -n "Enviando para: $nome ($ip)... "
    ssh_remote "$ip" "$PAYLOAD"
    [ $? -eq 0 ] && echo "[OK]" || echo "[ERRO]"
done < <(tail -n +3 "$ARQUIVO_IPS")

echo "--------------------------------------------------------"
echo "[CONCLUÍDO] Envio finalizado!"
