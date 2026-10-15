#!/bin/bash

# =============================================================
#  gitinstall.sh — Instalador do LabLivre via Git
#  Uso: bash gitinstall.sh
#  Instala o projeto em /opt/lablivre e configura o ambiente
#  (espelha o que o pacote .deb faz no postinst)
# =============================================================

set -e

REPO_URL="https://github.com/profjefer/lablivre-jfr.git"
INSTALL_DIR="/opt/lablivre"

echo "========================================================"
echo "        🚀 INSTALADOR LABLIVRE (via Git)                "
echo "========================================================"

# Descobre o usuário operador real (não o root do sudo)
USUARIO_REAL="${SUDO_USER:-$USER}"
if [ -z "$USUARIO_REAL" ] || [ "$USUARIO_REAL" = "root" ]; then
    USUARIO_REAL=$(awk -F: '$3 >= 1000 && $3 < 65534 {print $1; exit}' /etc/passwd)
fi
GRUPO_REAL=$(id -gn "$USUARIO_REAL" 2>/dev/null || echo "$USUARIO_REAL")

# 1. Dependência mínima para clonar (git)
echo ">> [1/6] Instalando git (mínimo para clonar)..."
sudo apt update -qq
sudo apt install -y git

# 2. Clona ou atualiza o repositório
if [ -d "$INSTALL_DIR/.git" ]; then
    echo ">> [2/6] Repositório já existe. Atualizando (git pull)..."
    sudo git -C "$INSTALL_DIR" pull
else
    echo ">> [2/6] Clonando repositório em $INSTALL_DIR..."
    sudo git clone "$REPO_URL" "$INSTALL_DIR"
fi

# 3. Cria estrutura de pastas que não vem no git
echo ">> [3/6] Criando estrutura de diretórios..."
sudo mkdir -p "$INSTALL_DIR"/{logs,configs,configs/.backups,envia_material,web,docs}
sudo touch "$INSTALL_DIR/configs/macs.txt" 2>/dev/null || true

# 4. Cede propriedade ao usuário operador (igual ao .deb)
echo ">> [4/6] Atribuindo propriedade a $USUARIO_REAL:$GRUPO_REAL..."
sudo chown -R "$USUARIO_REAL:$GRUPO_REAL" "$INSTALL_DIR"

# 5. Permissões (igual ao postinst do .deb)
echo ">> [5/6] Aplicando permissões..."
chmod +x "$INSTALL_DIR"/*.sh 2>/dev/null || true
chmod +x "$INSTALL_DIR"/modulos/*.sh 2>/dev/null || true
chmod +x "$INSTALL_DIR"/xmodulos/*.sh 2>/dev/null || true
chmod +x "$INSTALL_DIR"/tests/*.sh 2>/dev/null || true
chmod +x "$INSTALL_DIR"/packaging/build_deb.sh 2>/dev/null || true
# /opt atravessável + web legível pelo servidor HTTP
sudo chmod 755 /opt 2>/dev/null || true
chmod 755 "$INSTALL_DIR" 2>/dev/null || true
chmod 755 "$INSTALL_DIR"/web 2>/dev/null || true
chmod 644 "$INSTALL_DIR"/web/*.html 2>/dev/null || true
chmod 644 "$INSTALL_DIR"/web/*.json 2>/dev/null || true
# configs/ e logs/ restritos (contêm senha e dados)
chmod 700 "$INSTALL_DIR"/configs 2>/dev/null || true
chmod 700 "$INSTALL_DIR"/logs 2>/dev/null || true

# 6. Cria symlinks globais (igual ao .deb)
echo ">> [6/6] Criando atalhos lablivre e lablivre-gui..."
sudo ln -sf "$INSTALL_DIR"/menu.sh  /usr/local/bin/lablivre
sudo ln -sf "$INSTALL_DIR"/xmenu.sh /usr/local/bin/lablivre-gui

echo ""
echo "========================================================"
echo "✅ INSTALAÇÃO CONCLUÍDA!"
echo "========================================================"
echo "   Projeto instalado em : $INSTALL_DIR"
echo "   Operado por          : $USUARIO_REAL"
echo "   Comandos             : lablivre      (menu texto)"
echo "                          lablivre-gui  (menu gráfico)"
echo ""
echo "⚠️  PRÓXIMOS PASSOS:"
echo ""
echo "  1. Preencha a lista de MACs das máquinas do laboratório:"
echo "     nano $INSTALL_DIR/configs/macs.txt"
echo "     Formato:  aa:bb:cc:dd:ee:ff   nome-da-maquina"
echo ""
echo "  2. Inicie o orquestrador e faça a configuração inicial:"
echo "     lablivre"
echo "     → escolha a opção 99 (Configurações) para instalar"
echo "       dependências, definir credenciais SSH, cron e web."
echo ""
echo "  3. No menu, escolha a opção 1 (Mapear Rede) para começar."
echo ""
echo "  Documentação: $INSTALL_DIR/docs/wiki_lablivre.html"
echo "========================================================"
