#!/bin/bash

# configurar_lab.sh — Configuração inicial (modo texto)
# Coleta credenciais via prompt e chama _provisionar.sh

cd "$(dirname "$0")" || exit 1

ARQUIVO_CONF="configs/lablivre.conf"

echo "========================================================"
echo "      🚀 PREPARAÇÃO E CONFIGURAÇÃO DO ORQUESTRADOR      "
echo "========================================================"

# 1. Dependências (lista completa via helper centralizado)
echo ">> [1/3] Verificando ferramentas de sistema..."
source modulos/_instalar_deps.sh
instalar_deps_lablivre || {
    echo "[ERRO] Falha ao instalar dependências. Verifique sua conexão e tente:"
    echo "       sudo apt update && sudo apt install -y nmap sshpass zenity wakeonlan ethtool dmidecode netcat-openbsd python3 jq bc"
    exit 1
}

# Cria pasta configs antes de tudo
mkdir -p configs

# Backup preventivo do macs.txt (se existir)
bash modulos/_backup_macs.sh 2>/dev/null || true

# Carrega valores existentes como padrão
if [ -f "$ARQUIVO_CONF" ]; then source "$ARQUIVO_CONF"; fi

DEFAULT_NOME="${LAB_NOME:-UFPR Palotina}"
DEFAULT_USR="${LAB_USUARIO:-softwarelivre}"
DEFAULT_PWD="${LAB_SENHA:-ufpr1234}"
DEFAULT_MATERIAL="${LAB_PASTA_MATERIAL:-envia_material}"

# 2. Configuração interativa
echo ">> [2/3] Definindo identidade e credenciais do laboratório..."
echo "--------------------------------------------------------"
read -p ">> Nome do laboratório/instituição [$DEFAULT_NOME]: " IN_NOME
read -p ">> Usuário SSH das máquinas dos alunos [$DEFAULT_USR]: " IN_USR
read -s -p ">> Senha SSH (não aparecerá no terminal): " IN_PWD
echo ""
read -p ">> Pasta de envio de material [$DEFAULT_MATERIAL]: " IN_MATERIAL

NOVO_NOME="${IN_NOME:-$DEFAULT_NOME}"
NOVO_USR="${IN_USR:-$DEFAULT_USR}"
NOVO_PWD="${IN_PWD:-$DEFAULT_PWD}"
NOVO_MATERIAL="${IN_MATERIAL:-$DEFAULT_MATERIAL}"

# Salva conf
{
    echo "LAB_NOME=\"$NOVO_NOME\""
    echo "LAB_USUARIO=\"$NOVO_USR\""
    echo "LAB_SENHA=\"$NOVO_PWD\""
    echo "LAB_PASTA_MATERIAL=\"$NOVO_MATERIAL\""
    echo "LAB_IDIOMA=\"${LAB_IDIOMA:-pt_BR}\""
} > "$ARQUIVO_CONF"

# 3. Provisionamento (estrutura, permissões, WoL, cron, servidor web)
echo ">> [3/3] Provisionando infraestrutura (pastas, WoL, cron, servidor web)..."
echo "--------------------------------------------------------"
eval $(bash _provisionar.sh)

echo "--------------------------------------------------------"
echo "✅ CONFIGURAÇÃO CONCLUÍDA COM SUCESSO!"
echo "   Instalação em  : $PROVISIONADO_DIR"
echo "   Laboratório    : $NOVO_NOME"
echo "   Usuário SSH    : $NOVO_USR"
echo "   Pasta material : $NOVO_MATERIAL"
echo "   WoL ativo em   : $PROVISIONADO_IFACE"
echo "   Cron IPs       : a cada hora"
echo "   Cron Desligar  : todos os dias às 23h"
echo "   Cron Horário   : sincroniza às 07h"
echo "   Servidor Web   : http://localhost:8080"
echo "--------------------------------------------------------"
echo "⚠️  PRÓXIMO PASSO OBRIGATÓRIO:"
echo "   Preencha configs/macs.txt com os MACs das máquinas:"
echo "   nano configs/macs.txt"
echo "   Formato:  aa:bb:cc:dd:ee:ff   nome-da-maquina"
echo "--------------------------------------------------------"
