#!/bin/bash

# relatorio_status.sh — Gera relatório TXT rápido do estado do laboratório
# Não faz SSH (rápido) — usa os dados já mapeados em ips_atuais.txt
# Para inventário detalhado de hardware, use a opção de Inventário (via SSH).

cd "$(dirname "$0")/.." || exit 1

CONF_FILE="configs/lablivre.conf"
[ -f "$CONF_FILE" ] && source "$CONF_FILE"
LAB_NOME="${LAB_NOME:-LabLivre}"

ARQUIVO_IPS="ips_atuais.txt"
FLAG_PROVA="logs/modo_prova.status"
RELATORIO="logs/relatorio_status_$(date +%Y%m%d_%H%M%S).txt"

mkdir -p logs

if [ ! -f "$ARQUIVO_IPS" ]; then
    echo "[ERRO] $ARQUIVO_IPS não encontrado. Rode o mapeamento de rede (opção 1) primeiro."
    exit 1
fi

# Conta status
TOTAL=0; ONLINE=0; OFFLINE=0
while read -r mac ip nome resto; do
    [[ -z "$mac" ]] && continue
    ((TOTAL++))
    if [[ "$ip" == "OFFLINE" ]]; then ((OFFLINE++)); else ((ONLINE++)); fi
done < <(tail -n +3 "$ARQUIVO_IPS")

# Gera o relatório
{
    echo "════════════════════════════════════════════════════════════════"
    echo "          RELATÓRIO DE STATUS — LABLIVRE"
    echo "════════════════════════════════════════════════════════════════"
    echo "  Laboratório : $LAB_NOME"
    echo "  Data/Hora   : $(date '+%d/%m/%Y %H:%M:%S')"
    echo "  Orquestrador: $(hostname) ($(hostname -I | awk '{print $1}'))"
    echo "════════════════════════════════════════════════════════════════"
    echo ""
    echo "  RESUMO DA REDE"
    echo "  ──────────────────────────────────────────────────────────────"
    printf "  %-20s %s\n" "Total de máquinas:" "$TOTAL"
    printf "  %-20s %s\n" "🟢 Online:" "$ONLINE"
    printf "  %-20s %s\n" "🔴 Offline:" "$OFFLINE"

    # Modo prova
    if [ -f "$FLAG_PROVA" ]; then
        printf "  %-20s %s\n" "🔒 Modo Prova:" "ATIVO desde $(cat "$FLAG_PROVA")"
    else
        printf "  %-20s %s\n" "🔓 Modo Prova:" "Inativo (internet liberada)"
    fi

    # Modo de autenticação
    if [ "${LAB_AUTH_MODE:-senha}" = "chave" ] && [ -f "configs/lablivre_key" ]; then
        printf "  %-20s %s\n" "🔐 Autenticação:" "Chave SSH"
    else
        printf "  %-20s %s\n" "🔓 Autenticação:" "Senha"
    fi

    echo ""
    echo "  DETALHE DAS MÁQUINAS"
    echo "  ──────────────────────────────────────────────────────────────"
    printf "  %-18s %-16s %-20s %s\n" "MAC" "IP" "NOME" "STATUS"
    echo "  ──────────────────────────────────────────────────────────────"

    while read -r mac ip nome resto; do
        [[ -z "$mac" ]] && continue
        if [[ "$ip" == "OFFLINE" ]]; then
            STATUS="🔴 OFFLINE"
        elif [[ "$resto" == *"(ESTA MÁQUINA)"* ]]; then
            STATUS="🟢 ONLINE (esta)"
        else
            STATUS="🟢 ONLINE"
        fi
        printf "  %-18s %-16s %-20s %s\n" "$mac" "$ip" "$nome" "$STATUS"
    done < <(tail -n +3 "$ARQUIVO_IPS")

    echo ""
    echo "════════════════════════════════════════════════════════════════"
    echo "  Gerado pelo LabLivre v$(cat VERSION 2>/dev/null || echo '?')"
    echo "════════════════════════════════════════════════════════════════"
} | tee "$RELATORIO"

echo ""
echo "📄 Relatório salvo em: $RELATORIO"
log_acao "relatorio_status" "" 2>/dev/null || true
