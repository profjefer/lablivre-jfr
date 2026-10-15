#!/bin/bash

# build_deb.sh — Monta o pacote .deb do LabLivre
# Uso: bash packaging/build_deb.sh
# Saída: lablivre_VERSAO_all.deb

set -e

cd "$(dirname "$0")/.." || exit 1

# Verifica dependências mínimas para build
for cmd in dpkg-deb tar; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "[ERRO] Comando '$cmd' não encontrado. Instale com:"
        echo "       sudo apt install dpkg-dev"
        exit 1
    fi
done

VERSAO=$(cat VERSION)
PACOTE="lablivre_${VERSAO}_all"
TMP=$(mktemp -d)

echo ">> Construindo pacote: $PACOTE.deb"
echo ">> Versão: $VERSAO"

# Estrutura de diretórios do .deb
mkdir -p "$TMP/$PACOTE/DEBIAN"
mkdir -p "$TMP/$PACOTE/opt/lablivre"

# Copia metadados Debian (control, postinst, postrm)
cp packaging/debian/DEBIAN/control "$TMP/$PACOTE/DEBIAN/"
cp packaging/debian/DEBIAN/postinst "$TMP/$PACOTE/DEBIAN/"
cp packaging/debian/DEBIAN/postrm "$TMP/$PACOTE/DEBIAN/"
chmod 755 "$TMP/$PACOTE/DEBIAN/postinst"
chmod 755 "$TMP/$PACOTE/DEBIAN/postrm"

# Atualiza versão no control (caso esteja desatualizada)
sed -i "s/^Version:.*/Version: $VERSAO/" "$TMP/$PACOTE/DEBIAN/control"

# Copia o projeto via tar com exclusões (mais portável que rsync)
echo ">> Copiando arquivos..."
tar -cf - \
    --exclude='./logs' \
    --exclude='./ips_atuais.txt' \
    --exclude='./configs/lablivre.conf' \
    --exclude='./configs/macs.txt' \
    --exclude='./configs/.backups' \
    --exclude='./configs/lablivre_key' \
    --exclude='./configs/lablivre_key.pub' \
    --exclude='./envia_material' \
    --exclude='./web/api.json' \
    --exclude='./web/auditoria.json' \
    --exclude='./web/relatorio_*.html' \
    --exclude='./web/inventario.html' \
    --exclude='./packaging' \
    --exclude='./.git' \
    --exclude='./lablivre_*.deb' \
    --exclude='./lablivre-*.tar.gz' \
    --exclude='./*.swp' \
    . | tar -xf - -C "$TMP/$PACOTE/opt/lablivre/"

# Permissões corretas no conteúdo
chmod -R go-w "$TMP/$PACOTE/opt/lablivre/"
chmod 755 "$TMP/$PACOTE/opt/lablivre/"*.sh
chmod 755 "$TMP/$PACOTE/opt/lablivre/modulos/"*.sh 2>/dev/null || true
chmod 755 "$TMP/$PACOTE/opt/lablivre/xmodulos/"*.sh 2>/dev/null || true
chmod 755 "$TMP/$PACOTE/opt/lablivre/tests/"*.sh 2>/dev/null || true

# Constrói o pacote
echo ">> Empacotando..."
dpkg-deb --build --root-owner-group "$TMP/$PACOTE"

mv "$TMP/$PACOTE.deb" .
rm -rf "$TMP"

# Mostra info
TAMANHO=$(du -h "$PACOTE.deb" | awk '{print $1}')

echo ""
echo "═══════════════════════════════════════════════════════"
echo "✓ Pacote gerado: $PACOTE.deb ($TAMANHO)"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "Para instalar:"
echo "  sudo apt install ./$PACOTE.deb"
echo ""
echo "Para distribuir:"
echo "  scp $PACOTE.deb usuario@servidor:~"
echo ""
echo "Para validar (sem instalar):"
echo "  dpkg-deb -I $PACOTE.deb     # info do pacote"
echo "  dpkg-deb -c $PACOTE.deb     # lista arquivos"
