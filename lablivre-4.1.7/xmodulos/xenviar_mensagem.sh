#!/bin/bash

# Garante que o script localize a raiz do projeto
cd "$(dirname "$0")/.." || exit 1

CONF_FILE="configs/lablivre.conf"
if [ -f "$CONF_FILE" ]; then source "$CONF_FILE"; else LAB_USUARIO="ufpr"; LAB_SENHA="UFPR"; fi
ARQUIVO_IPS="ips_atuais.txt"

if [ ! -f "$ARQUIVO_IPS" ]; then
    zenity --error --text="Arquivo de IPs não encontrado!\nExecute o mapeamento de rede primeiro." --width=300
    exit 1
fi

# ===================================================================
# 1. INTERFACE DE ENTRADA (Texto da Mensagem)
# ===================================================================
MENSAGEM=$(zenity --entry \
    --title="📩 Enviar Mensagem" \
    --text="Digite a mensagem que deseja enviar para toda a turma:" \
    --width=450)

# Se cancelar ou deixar vazio, sai silenciosamente
if [ -z "$MENSAGEM" ]; then
    exit 0
fi

# ===================================================================
# 2. INTERFACE DE ESCOLHA (Tipo de Envio)
# ===================================================================
TIPO_MSG=$(zenity --list --title="Formato da Mensagem" --text="Como os alunos devem receber o aviso?" \
    --radiolist --column="Marcar" --column="ID" --column="Formato" \
    TRUE "1" "🖥️ Gráfica (Pop-up obrigatório no meio da tela)" \
    FALSE "2" "⬛ Terminal (Apenas texto, exige terminal aberto)" \
    --hide-column=2 --print-column=2 --width=450 --height=220)

if [ -z "$TIPO_MSG" ]; then
    exit 0
fi

# Define os payloads (comandos) baseados na escolha
if [[ "$TIPO_MSG" == "1" ]]; then
    # Payload Gráfico Ninja
    PAYLOAD="export DISPLAY=:0; export XDG_RUNTIME_DIR=/run/user/\$(id -u); zenity --warning --title='Aviso do Professor' --text='$MENSAGEM' --width=450 >/dev/null 2>&1 &"
    Aviso_Barra="Enviando pop-up visual..."
else
    # Payload Texto Wall
    PAYLOAD="echo 'AVISO DO PROFESSOR: $MENSAGEM' | wall"
    Aviso_Barra="Enviando broadcast no terminal..."
fi

TOTAL_MAQUINAS=$(tail -n +3 "$ARQUIVO_IPS" | grep -v -w "OFFLINE" | grep -v "ESTA MÁQUINA" | wc -l)
[ "$TOTAL_MAQUINAS" -eq 0 ] && TOTAL_MAQUINAS=1

# ===================================================================
# 3. EXECUÇÃO COM BARRA DE PROGRESSO (GUI)
# ===================================================================
(
    ATUAL=0
    SUCESSO=0
    FALHA=0

    while read -r mac ip nome resto; do
        # Pula as offline e a própria máquina do professor
        if [[ -z "$mac" ]] || [[ "$ip" == "OFFLINE" ]] || [[ "$resto" == *"(ESTA MÁQUINA)"* ]]; then 
            continue
        fi
        
        echo "# Disparando para: $nome ($ip)..."
        
        # O '-n' mágico que protege o loop no ambiente gráfico também
        sshpass -p "$LAB_SENHA" ssh -n -q -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$LAB_USUARIO@$ip" "$PAYLOAD"
        
        if [ $? -eq 0 ]; then
            ((SUCESSO++))
        else
            ((FALHA++))
        fi
        
        ((ATUAL++))
        PERCENT=$(( ATUAL * 100 / TOTAL_MAQUINAS ))
        echo "$PERCENT"
    done < <(tail -n +3 "$ARQUIVO_IPS")
    
    echo "100"
    echo "# Envio concluído!"
    
    # Salva o status temporário
    echo "$SUCESSO|$FALHA" > /tmp/lablivre_msg_stats.tmp

) | zenity --progress \
    --title="Enviando Mensagens" \
    --text="$Aviso_Barra" \
    --percentage=0 \
    --auto-close \
    --auto-kill \
    --width=400

# Se o professor apertar "Cancelar" no meio do caminho
if [ $? -ne 0 ]; then
    zenity --warning --text="Envio interrompido pelo usuário." --width=300
    exit 1
fi

# ===================================================================
# 4. RESUMO FINAL VISUAL
# ===================================================================
if [ -f /tmp/lablivre_msg_stats.tmp ]; then
    IFS='|' read -r SUCESSO FALHA < /tmp/lablivre_msg_stats.tmp
    rm -f /tmp/lablivre_msg_stats.tmp
    
    zenity --info \
        --title="Envio Finalizado" \
        --text="✅ <b>Mensagens entregues!</b>\n\n🟢 <b>$SUCESSO</b> alunos receberam o aviso.\n🔴 <b>$FALHA</b> falhas de comunicação." \
        --width=300
fi
