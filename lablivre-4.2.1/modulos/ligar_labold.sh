#!/bin/bash

cd "$(dirname "$0")/.." || exit 1

ARQUIVO_IPS="ips_atuais.txt"

echo "========================================================"
echo "          ⚡ LIGAR LABORATÓRIO (WAKE-ON-LAN)            "
echo "========================================================"

# Verifica se wakeonlan está instalado
if ! command -v wakeonlan &> /dev/null; then
    echo "[ERRO] O pacote 'wakeonlan' não está instalado."
    echo ">> Instale rodando: sudo apt install wakeonlan"
    exit 1
fi

# Verifica se o WoL está ativo na placa de rede do professor
IFACE=$(ip route | awk '/default/ {print $5}' | head -n 1)
WOL_STATUS=$(sudo ethtool "$IFACE" 2>/dev/null | grep "Wake-on:" | tail -n1 | awk '{print $2}')

if [[ "$WOL_STATUS" != *"g"* ]]; then
    echo "========================================================"
    echo "  ⚠️  AVISO: Wake-on-LAN NÃO está ativo nesta máquina!"
    echo "========================================================"
    echo "  Os pacotes serão enviados, mas as máquinas dos alunos"
    echo "  só ligarão se o WoL estiver habilitado nelas também."
    echo ""
    echo "  Para corrigir, execute a opção 99 (Configurações) ou:"
    echo "  sudo ethtool -s $IFACE wol g"
    echo "========================================================"
    echo ""
    read -p "Continuar mesmo assim? (s/N): " CONFIRMA
    if [[ "${CONFIRMA,,}" != "s" ]]; then
        echo "Operação cancelada."
        exit 0
    fi
else
    echo ">> WoL ativo na placa $IFACE. ✅"
fi

# Verifica se o macs.txt tem conteúdo útil
if [ ! -f "$ARQUIVO_IPS" ]; then
    echo "[ERRO] Arquivo '$ARQUIVO_IPS' não encontrado."
    echo ">> Execute primeiro a opção 1 (Mapear Rede) no menu."
    exit 1
fi

echo ">> Disparando Pacotes Mágicos (Magic Packets)..."
echo "--------------------------------------------------------"

# Não filtra OFFLINE: a intenção é ligar quem está desligado
while read -r mac ip nome resto; do
    if [[ -z "$mac" ]] || [[ "$resto" == *"(ESTA MÁQUINA)"* ]]; then continue; fi

    echo -n "Despertando: $nome ($mac)... "
    wakeonlan "$mac" >/dev/null 2>&1
    echo "[ENVIADO]"
    sleep 0.2
done < <(tail -n +3 "$ARQUIVO_IPS")

echo "--------------------------------------------------------"
echo "[CONCLUÍDO] Pacotes enviados. Aguarde ~60s para as máquinas iniciarem."
log_acao "ligar_lab" "" 2>/dev/null || true
echo ">> Dica: rode a opção 1 (Mapear Rede) em seguida para confirmar."
