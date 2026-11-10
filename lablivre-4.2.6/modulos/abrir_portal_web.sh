#!/bin/bash
# ================================================================
# abrir_portal_web.sh — Abre o portal web do LabLivre
#
#   bash modulos/abrir_portal_web.sh                 → portal (index)
#   bash modulos/abrir_portal_web.sh maquinas.html   → uma página
#
# Sempre por http://<IP>:8080 (o Firefox snap do Ubuntu não
# abre file:///opt/...). Se a porta estiver com o servidor de uma
# instalação ANTIGA, avisa em vez de abrir páginas velhas.
# ================================================================

cd "$(dirname "$0")/.." || exit 1
source modulos/_comum.sh || exit 1

echo "========================================================"
echo "           🌐 PORTAL WEB LABLIVRE                       "
echo "========================================================"
URL=$(abrir_pagina_web "${1:-}") || {
    echo "   Diagnóstico e correção: menu → 17 (Saúde do sistema)"
    exit 1
}
if [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
    echo "[OK] Aberto no navegador: $URL"
else
    echo "[OK] Servidor no ar. Sem tela nesta sessão (SSH): abra no navegador do seu computador:"
fi
echo ""
echo "   $URL"
echo ""
echo "   (vale de qualquer computador da rede; os botões do Modo Prova"
echo "    só aparecem quando aberto na máquina do professor)"
