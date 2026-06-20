#!/bin/bash

# diagnosticar_ssh.sh — Testa conectividade SSH em camadas
# (ping → porta 22 → autenticação)

cd "$(dirname "$0")/.." || exit 1

CONF_FILE="configs/lablivre.conf"
if [ -f "$CONF_FILE" ]; then source "$CONF_FILE"; else LAB_USUARIO="ufpr"; LAB_SENHA="UFPR"; fi
source modulos/_ssh.sh 2>/dev/null || true

ARQUIVO_IPS="ips_atuais.txt"
RELATORIO="logs/diagnostico_ssh.txt"
mkdir -p logs

if [ ! -f "$ARQUIVO_IPS" ]; then
    echo "[ERRO] Arquivo $ARQUIVO_IPS não encontrado."
    echo ">> Execute primeiro a opção 1 (Mapear Rede)."
    exit 1
fi

echo "========================================================"
echo "         🔍 DIAGNÓSTICO DE CONEXÃO SSH                  "
echo "========================================================"
echo "Modo de autenticação: ${LAB_AUTH_MODE:-senha}"
echo "--------------------------------------------------------"

{
    echo "Diagnóstico SSH - $(date '+%d/%m/%Y %H:%M:%S')"
    echo "Modo: ${LAB_AUTH_MODE:-senha}"
    echo "----"
} > "$RELATORIO"

OK=0; PING_FAIL=0; SSH_FAIL=0; AUTH_FAIL=0

while read -r mac ip nome resto; do
    if [[ -z "$mac" ]] || [[ "$resto" == *"(ESTA MÁQUINA)"* ]]; then continue; fi

    echo -n "Testando: $nome ($ip)... "

    if [[ "$ip" == "OFFLINE" ]]; then
        echo "💀 OFFLINE"
        echo "[OFFLINE] $nome — sem ping no último mapeamento" >> "$RELATORIO"
        ((PING_FAIL++))
    elif ! ping -c 1 -W 2 "$ip" > /dev/null 2>&1; then
        echo "💀 sem ping"
        echo "[PING FAIL] $nome ($ip)" >> "$RELATORIO"
        ((PING_FAIL++))
    elif ! nc -z -w 2 "$ip" 22 > /dev/null 2>&1; then
        echo "🔒 SSH fechado"
        echo "[SSH FAIL] $nome ($ip) — porta 22 fechada" >> "$RELATORIO"
        ((SSH_FAIL++))
    elif ! ssh_remote "$ip" "exit" 2>/dev/null; then
        echo "🔑 auth falhou"
        echo "[AUTH FAIL] $nome ($ip) — credenciais inválidas" >> "$RELATORIO"
        ((AUTH_FAIL++))
    else
        echo "✅ OK"
        echo "[OK] $nome ($ip)" >> "$RELATORIO"
        ((OK++))
    fi
done < <(tail -n +3 "$ARQUIVO_IPS")

echo "--------------------------------------------------------"
echo "Resumo: ✅ $OK funcionais · 💀 $PING_FAIL sem ping · 🔒 $SSH_FAIL SSH fechado · 🔑 $AUTH_FAIL auth falhou"
echo ""
echo "Relatório completo em: $RELATORIO"

{
    echo "----"
    echo "RESUMO: $OK ok · $PING_FAIL sem ping · $SSH_FAIL SSH fechado · $AUTH_FAIL auth falhou"
} >> "$RELATORIO"
