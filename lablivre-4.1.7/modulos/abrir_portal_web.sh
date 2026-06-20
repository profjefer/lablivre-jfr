#!/bin/bash

# abrir_portal_web.sh — Abre o portal web do LabLivre (dashboards + inventário)
# Verifica se servidor está rodando, sobe se necessário, e abre no navegador

cd "$(dirname "$0")/.." || exit 1

URL="http://localhost:8080/"
PORT=8080

echo "========================================================"
echo "           🌐 PORTAL WEB LABLIVRE                       "
echo "========================================================"

# Verifica se servidor está rodando
if curl -s --connect-timeout 2 "$URL" >/dev/null 2>&1; then
    echo "[OK] Servidor web ativo em $URL"
else
    echo "[!] Servidor web não responde. Tentando subir..."

    # Tenta via systemd primeiro
    if sudo systemctl is-enabled lablivre-web.service >/dev/null 2>&1; then
        sudo systemctl restart lablivre-web.service
        sleep 2
    else
        # Fallback: sobe em background
        echo "[!] Serviço systemd não configurado. Subindo manualmente..."
        nohup python3 -m http.server $PORT --directory web/ >/dev/null 2>&1 &
        sleep 2
    fi

    if ! curl -s --connect-timeout 2 "$URL" >/dev/null 2>&1; then
        echo "[ERRO] Não foi possível subir o servidor."
        echo "       Verifique manualmente: sudo systemctl status lablivre-web.service"
        echo "       Ou execute: bash _provisionar.sh"
        exit 1
    fi
    echo "[OK] Servidor subido."
fi

echo ""
echo ">> Abrindo $URL no navegador..."

# Tenta abrir no navegador (xdg-open, sensible-browser, ou exibe a URL)
if command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$URL" >/dev/null 2>&1 &
elif command -v sensible-browser >/dev/null 2>&1; then
    sensible-browser "$URL" >/dev/null 2>&1 &
else
    echo ""
    echo "Não foi possível abrir o navegador automaticamente."
    echo "Acesse manualmente: $URL"
fi

echo ""
echo "Você pode acessar também de outros dispositivos na rede:"
echo "  http://$(hostname -I | awk '{print $1}'):$PORT/"
