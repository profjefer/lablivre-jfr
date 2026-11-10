#!/bin/bash
# ================================================================
# testar_conexao.sh — Teste rápido: quem está na rede AGORA
#
# 1. Remapeia a rede (o mesmo motor da opção 1) — o teste antigo
#    usava o ips_atuais.txt velho e dava "todas sem conexão".
# 2. Para cada máquina online, testa ping e porta 22 em paralelo.
#    Ping bloqueado com porta 22 aberta = máquina OK (firewall).
# ================================================================

cd "$(dirname "$0")/.." || exit 1
source modulos/_comum.sh || exit 1

echo "========================================================"
echo "            📡 TESTE DE CONECTIVIDADE                   "
echo "========================================================"
echo ">> Mapeando a rede..."
bash modulos/atualizar_ips.sh < /dev/null > logs/teste_mapeamento.log 2>&1
RC=$?
[ "$RC" -ne 0 ] && echo "[AVISO] Mapeamento falhou; usando o mapa anterior (veja logs/teste_mapeamento.log)."
exigir_ips || exit 1
echo "   $(grep -m1 '^>> Método:' logs/teste_mapeamento.log)"
echo "--------------------------------------------------------"

TMP=$(mktemp -d)
testar() {
    local mac="$1" ip="$2" nome="$3" p s
    [ "$ip" = OFFLINE ] && { echo "OFF" > "$TMP/$nome"; return; }
    (
        ping -c 1 -W 2 "$ip" >/dev/null 2>&1 && p=ok || p=bloq
        timeout 3 bash -c "exec 3<>/dev/tcp/$ip/22" 2>/dev/null && s=ok || s=fechada
        echo "$ip $p $s" > "$TMP/$nome"
    ) &
}
para_cada_maquina testar --todas
wait

ON=0; OFF=0; ALERTA=0
for f in $(ls "$TMP" | sort); do
    read -r ip p s < "$TMP/$f"
    if [ "$ip" = OFF ]; then
        printf "❌ %-20s fora da rede\n" "$f"; ((OFF++)); continue
    fi
    ((ON++))
    if [ "$s" = ok ]; then
        printf "✅ %-20s %-15s SSH ok%s\n" "$f" "$ip" "$([ "$p" = ok ] || echo ' · ping bloqueado')"
    else
        printf "⚠️  %-20s %-15s na rede, mas porta 22 fechada\n" "$f" "$ip"; ((ALERTA++))
    fi
done
rm -rf "$TMP"
echo "--------------------------------------------------------"
echo "Resumo: 🟢 $ON na rede ($ALERTA sem SSH) · 🔴 $OFF fora da rede"
[ "$OFF" -gt 0 ] && echo "   'fora da rede' = desligada, cabo solto ou conectada só na Wi-Fi de outra rede."
