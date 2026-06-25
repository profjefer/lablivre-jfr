#!/bin/bash

# xconfigurar_lab.sh — Configuração inicial (modo gráfico)
# Coleta credenciais via Zenity e chama _provisionar.sh

cd "$(dirname "$0")/.." || exit 1

ARQUIVO_CONF="configs/lablivre.conf"

mkdir -p configs

# Carrega valores existentes
if [ -f "$ARQUIVO_CONF" ]; then
    source "$ARQUIVO_CONF"
fi

VAL_NOME="${LAB_NOME:-UFPR Palotina}"
VAL_USR="${LAB_USUARIO:-softwarelivre}"
VAL_PWD="${LAB_SENHA:-ufpr1234}"
VAL_MATERIAL="${LAB_PASTA_MATERIAL:-envia_material}"

# ========================================================
# PASSO 1: FORMULÁRIO GRÁFICO
# ========================================================
SAIDA=$(zenity --forms \
    --title="⚙️ Configurações Globais - LabLivre" \
    --text="Defina a identidade e credenciais do laboratório:" \
    --add-entry="Nome do Laboratório (Atual: $VAL_NOME)" \
    --add-entry="Usuário SSH (Atual: $VAL_USR)" \
    --add-password="Senha SSH" \
    --add-entry="Pasta de Material (Atual: $VAL_MATERIAL)" \
    --separator="|" \
    --width=500)

if [ $? -ne 0 ]; then exit 0; fi

IN_NOME=$(echo "$SAIDA" | awk -F'|' '{print $1}')
IN_USR=$(echo "$SAIDA" | awk -F'|' '{print $2}')
IN_PWD=$(echo "$SAIDA" | awk -F'|' '{print $3}')
IN_MATERIAL=$(echo "$SAIDA" | awk -F'|' '{print $4}')

NOVO_NOME="${IN_NOME:-$VAL_NOME}"
NOVO_USR="${IN_USR:-$VAL_USR}"
NOVO_PWD="${IN_PWD:-$VAL_PWD}"
NOVO_MATERIAL="${IN_MATERIAL:-$VAL_MATERIAL}"

# ========================================================
# PASSO 2: SALVA NO CONF
# ========================================================
{
    echo "LAB_NOME=\"$NOVO_NOME\""
    echo "LAB_USUARIO=\"$NOVO_USR\""
    echo "LAB_SENHA=\"$NOVO_PWD\""
    echo "LAB_PASTA_MATERIAL=\"$NOVO_MATERIAL\""
} > "$ARQUIVO_CONF"

# ========================================================
# PASSO 3: PROVISIONAMENTO (com confirmação)
# ========================================================
zenity --question \
    --title="🤖 Provisionar Infraestrutura?" \
    --text="Deseja instalar/atualizar a infraestrutura desta máquina?\n\nIsso configurará:\n👉 Estrutura de pastas\n👉 Wake-on-LAN persistente (boot)\n👉 Cron: atualizar IPs a cada hora\n👉 Cron: desligar lab às 23h\n👉 Cron: sincronizar horário às 7h\n👉 Servidor Web Dashboard (porta 8080)\n\n<i>Recomendado apenas para o computador Orquestrador (professor).</i>" \
    --width=550

if [ $? -eq 0 ]; then
    # Chama lógica comum (texto e gráfico usam o mesmo)
    eval $(bash _provisionar.sh 2>/dev/null)

    MEU_IP=$(hostname -I | awk '{print $1}')
    MENSAGEM_PROV="\n\n⚙️ <b>Infraestrutura provisionada!</b>\n\n• Pastas e permissões criadas\n• WoL ativo em <b>$PROVISIONADO_IFACE</b>\n• Crons instalados (sem duplicar)\n• Dashboard Web: <i>http://$MEU_IP:8080</i>"
else
    MENSAGEM_PROV="\n\n⏸️ <i>Provisionamento ignorado. Apenas as credenciais foram salvas.</i>"
fi

# ========================================================
# PASSO 4: CONFIRMAÇÃO FINAL
# ========================================================
zenity --info \
    --title="Setup Concluído" \
    --text="✅ Configurações salvas em <b>$ARQUIVO_CONF</b>!\n\n📍 Laboratório: <b>$NOVO_NOME</b>\n👤 Usuário SSH: <b>$NOVO_USR</b>\n📁 Pasta material: <b>$NOVO_MATERIAL</b>$MENSAGEM_PROV" \
    --width=500
