#!/bin/bash

# ver_auditoria.sh — Visualizador de logs de auditoria estruturados

cd "$(dirname "$0")/.." || exit 1

LOG="logs/auditoria.jsonl"

if [ ! -f "$LOG" ]; then
    echo "[INFO] Nenhuma auditoria registrada ainda."
    echo ">> O arquivo logs/auditoria.jsonl será criado na primeira ação registrada."
    exit 0
fi

echo "========================================================"
echo "         📜 AUDITORIA DO LABLIVRE                       "
echo "========================================================"
echo ""
echo "1 - Últimas 20 ações"
echo "2 - Últimas 50 ações"
echo "3 - Ações de hoje"
echo "4 - Ações dos últimos 7 dias"
echo "5 - Filtrar por tipo de ação"
echo "0 - Voltar"
echo "========================================================"
read -p "Escolha: " OPCAO

# Função para formatar uma linha JSONL de forma legível
formatar() {
    python3 -c "
import json, sys
for linha in sys.stdin:
    linha = linha.strip()
    if not linha: continue
    try:
        d = json.loads(linha)
        ts = d.get('ts','?')[:19].replace('T',' ')
        usr = d.get('usuario','?')
        host = d.get('host','?')
        acao = d.get('acao','?')
        det = d.get('detalhes',{})
        det_str = ' '.join(f'{k}={v}' for k,v in det.items()) if det else ''
        print(f'{ts}  {usr}@{host:<18}  {acao:<25}  {det_str}')
    except Exception as e:
        pass
"
}

case $OPCAO in
    1) echo ""; tail -n 20 "$LOG" | formatar ;;
    2) echo ""; tail -n 50 "$LOG" | formatar ;;
    3)
        HOJE=$(date '+%Y-%m-%d')
        echo ""
        grep "\"ts\":\"$HOJE" "$LOG" | formatar
        ;;
    4)
        echo ""
        for d in 0 1 2 3 4 5 6; do
            DIA=$(date -d "$d days ago" '+%Y-%m-%d' 2>/dev/null)
            grep "\"ts\":\"$DIA" "$LOG"
        done | formatar
        ;;
    5)
        echo ""
        echo "Tipos de ação disponíveis:"
        python3 -c "
import json
with open('$LOG') as f:
    acoes = set()
    for linha in f:
        try: acoes.add(json.loads(linha).get('acao'))
        except: pass
for a in sorted(acoes): print(f'  - {a}')
"
        read -p "Digite o tipo (ex: modo_prova_ativar): " TIPO
        grep "\"acao\":\"$TIPO\"" "$LOG" | formatar
        ;;
    0) exit 0 ;;
    *) echo "Opção inválida." ;;
esac
