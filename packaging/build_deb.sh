#!/bin/bash

# build_deb.sh — Monta o pacote .deb do LabLivre
# Uso: bash packaging/build_deb.sh
# Saída (pasta dist/, que vai para o git e para a Release do GitHub):
#   dist/lablivre_VERSAO_all.deb    pacote para apt install
#   dist/lablivre-VERSAO.tar.gz     o projeto compactado (pasta lablivre-VERSAO/)

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
for s in preinst postinst postrm; do
    cp "packaging/debian/DEBIAN/$s" "$TMP/$PACOTE/DEBIAN/"
    chmod 755 "$TMP/$PACOTE/DEBIAN/$s"
done

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
    --exclude='./web/mapa_calor.json' \
    --exclude='./web/status.html' \
    --exclude='./web/lablivre-raiz.txt' \
    --exclude='./packaging' \
    --exclude='./.git' \
    --exclude='./.github' \
    --exclude='./dist' \
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

# Pasta dist/: só a versão atual (as antigas ficam no histórico do git
# e nas Releases do GitHub)
mkdir -p dist
rm -f dist/lablivre_*_all.deb dist/lablivre-*.tar.gz
mv "$TMP/$PACOTE.deb" dist/
rm -rf "$TMP"

# Projeto compactado: os arquivos do git (sem dados locais nem dist/)
echo ">> Compactando o projeto..."
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    TMPT=$(mktemp -d)
    mkdir "$TMPT/lablivre-$VERSAO"
    # arquivos versionados + novos ainda não commitados, respeitando o .gitignore
    git ls-files -z --cached --others --exclude-standard | grep -zv '^dist/' | \
        xargs -0 -I{} sh -c '[ -e "$1" ] && cp --parents -p "$1" "$2"' _ {} "$TMPT/lablivre-$VERSAO"
    tar -czf "dist/lablivre-$VERSAO.tar.gz" -C "$TMPT" "lablivre-$VERSAO"
    rm -rf "$TMPT"
else
    echo "   (fora de um clone git: o .tar.gz não foi gerado)"
fi

# Mostra info
TAMANHO=$(du -h "dist/$PACOTE.deb" | awk '{print $1}')

echo ""
echo "═══════════════════════════════════════════════════════"
echo "✓ Pacote gerado: dist/$PACOTE.deb ($TAMANHO)"
[ -f "dist/lablivre-$VERSAO.tar.gz" ] && echo "✓ Projeto:       dist/lablivre-$VERSAO.tar.gz ($(du -h "dist/lablivre-$VERSAO.tar.gz" | awk '{print $1}'))"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "Para instalar:"
echo "  sudo apt install ./dist/$PACOTE.deb"
echo ""
echo "Para distribuir:"
echo "  scp dist/$PACOTE.deb usuario@servidor:~"
echo ""
echo "Para validar (sem instalar):"
echo "  dpkg-deb -I dist/$PACOTE.deb     # info do pacote"
echo "  dpkg-deb -c dist/$PACOTE.deb     # lista arquivos"
