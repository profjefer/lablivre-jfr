#!/bin/bash

# Garante que o script sempre rode na pasta base
cd "$(dirname "$0")/.." || exit 1

# --- BUSCA CONFIGURAÇÃO GLOBAL (Princípio DRY) ---
CONF_FILE="configs/lablivre.conf"
[ -f "$CONF_FILE" ] || CONF_FILE="../configs/lablivre.conf"

if [ -f "$CONF_FILE" ]; then
    source "$CONF_FILE"
else
    LAB_USUARIO="ufpr"
    LAB_SENHA="UFPR"
fi

USUARIO_SSH="$LAB_USUARIO"
SENHA_SSH="$LAB_SENHA"
ARQUIVO_IPS="ips_atuais.txt"

if [ ! -f "$ARQUIVO_IPS" ]; then
    zenity --error --text="Erro: Arquivo '$ARQUIVO_IPS' não encontrado."
    exit 1
fi

# ========================================================
# 1. INTERFACE DE ENTRADA (SELETOR DE DIRETÓRIO ZENITY)
# ========================================================
# Abre uma janela gráfica para o professor escolher a pasta
PASTA_ORIGEM=$(zenity --file-selection --directory \
    --title="📚 Selecione a Pasta com o Material de Aula" \
    --width=600 --height=400)

# Se o usuário clicar em "Cancelar" ou fechar a janela
if [ -z "$PASTA_ORIGEM" ]; then
    exit 0
fi

# Extrai apenas o nome final da pasta (ex: "Aula01_Python")
NOME_PASTA=$(basename "$PASTA_ORIGEM")

# Pede uma última confirmação antes de disparar na rede
zenity --question \
    --title="Confirmar Envio" \
    --text="Você está prestes a enviar a pasta:\n<b>$NOME_PASTA</b>\n\nDestino: <i>Área de Trabalho</i> de todas as máquinas ativas.\n\nDeseja iniciar a transferência?" \
    --width=400
if [ $? -ne 0 ]; then exit 0; fi

# ========================================================
# 2. EXECUÇÃO COM LOG NO TERMINAL E ESTRATÉGIA DE PONTE
# ========================================================
echo "=========================================="
echo "        DISTRIBUIÇÃO DE MATERIAL          "
echo "=========================================="
echo ">> Material: $NOME_PASTA"
echo ">> Estratégia: Transferência Segura via Ponte (/tmp)"
echo "--------------------------------------------------------"

while read -r mac ip nome resto; do
    if [[ -z "$mac" ]] || [[ "$ip" == "OFFLINE" ]]; then continue; fi

    echo -n "Enviando para: $nome ($ip)... "
    
    if [[ "$resto" == *"(ESTA MÁQUINA)"* ]]; then
        echo "[IGNORADO] (Servidor Local)"
    else
        # PASSO 1: Envia para a pasta /tmp (sem caracteres especiais, a rede não quebra)
        SAIDA_SCP=$(sshpass -p "$SENHA_SSH" scp -o StrictHostKeyChecking=no -o ConnectTimeout=8 -r "$PASTA_ORIGEM" "${USUARIO_SSH}@${ip}:/tmp/" 2>&1)
        
        if [ $? -ne 0 ]; then
            echo "[ERRO SCP] -> $(echo "$SAIDA_SCP" | tail -n 1 | tr '\n' ' ')"
            continue
        fi
        
        # PASSO 2: Entra via SSH e move localmente do /tmp para a Área de Trabalho do aluno
        # Nota: O rm -rf antes previne erros se o professor mandar a mesma pasta duas vezes
        COMANDO_MV="mkdir -p ~/Área\ de\ Trabalho; rm -rf ~/Área\ de\ Trabalho/'$NOME_PASTA'; mv '/tmp/$NOME_PASTA' ~/Área\ de\ Trabalho/"
        SAIDA_SSH=$(sshpass -p "$SENHA_SSH" ssh -n -o StrictHostKeyChecking=no -o ConnectTimeout=5 "${USUARIO_SSH}@${ip}" "$COMANDO_MV" 2>&1)
        
        if [ $? -eq 0 ]; then
            echo "[OK]"
        else
            echo "[ERRO SSH] -> $(echo "$SAIDA_SSH" | tail -n 1 | tr '\n' ' ')"
        fi
    fi
done < <(tail -n +3 "$ARQUIVO_IPS")

echo "--------------------------------------------------------"

# ========================================================
# 3. INTERFACE DE SAÍDA
# ========================================================
zenity --info \
    --title="Distribuição Concluída" \
    --text="✅ <b>Sucesso!</b>\n\nO material <b>$NOME_PASTA</b> foi distribuído com sucesso para a Área de Trabalho dos alunos ativos." \
    --width=350
