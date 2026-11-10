#!/bin/bash
# ================================================================
#  gitinstall.sh — Instala ou atualiza o LabLivre pelo Git
#
#  Uso (instalar ou atualizar, o mesmo comando):
#    curl -fsSL https://raw.githubusercontent.com/profjefer/lablivre-jfr/main/gitinstall.sh | bash
#  ou, de dentro de um clone:
#    bash gitinstall.sh
#
#  Instala em /opt/lablivre e cria os comandos lablivre e lablivre-gui.
#  O macs.txt, o lablivre.conf e os logs NÃO estão no git: atualizar
#  nunca mexe neles. Se o macs.txt estiver vazio (instalação do zero),
#  ele é restaurado da cópia guardada fora do /opt ou da instalação
#  antiga (/opt/scriptlab-jfr).
# ================================================================

set -e

REPO_URL="https://github.com/profjefer/lablivre-jfr.git"
BRANCH="main"
INSTALL_DIR="/opt/lablivre"

echo "========================================================"
echo "        🚀 INSTALADOR LABLIVRE (via Git)                "
echo "========================================================"

# Usuário operador real (não o root do sudo): é o dono da instalação
USUARIO_REAL="${SUDO_USER:-$USER}"
if [ -z "$USUARIO_REAL" ] || [ "$USUARIO_REAL" = "root" ]; then
    USUARIO_REAL=$(awk -F: '$3 >= 1000 && $3 < 65534 {print $1; exit}' /etc/passwd)
fi
GRUPO_REAL=$(id -gn "$USUARIO_REAL" 2>/dev/null || echo "$USUARIO_REAL")
# git roda como o operador (rodar como root numa pasta do usuário dá
# "dubious ownership" e deixa arquivos do root no meio da instalação)
como_operador() { sudo -u "$USUARIO_REAL" -H "$@"; }

# 1. git
echo ">> [1/6] Conferindo o git..."
if ! command -v git >/dev/null 2>&1; then
    sudo apt-get update -qq
    sudo apt-get install -y git
fi

# 2. Clona, atualiza ou converte
if [ -d "$INSTALL_DIR/.git" ]; then
    echo ">> [2/6] Já instalado pelo Git. Atualizando (git pull)..."
    sudo chown -R "$USUARIO_REAL:$GRUPO_REAL" "$INSTALL_DIR"
    if ! como_operador git -C "$INSTALL_DIR" pull --ff-only origin "$BRANCH"; then
        echo ""
        echo "[ERRO] O git pull não conseguiu atualizar (arquivos do LabLivre"
        echo "       alterados à mão em $INSTALL_DIR?). Veja com:"
        echo "         git -C $INSTALL_DIR status"
        echo "       Para descartar as alterações e atualizar:"
        echo "         git -C $INSTALL_DIR checkout -- . && bash $INSTALL_DIR/gitinstall.sh"
        echo "       (macs.txt, lablivre.conf e logs não são afetados.)"
        exit 1
    fi
elif [ -d "$INSTALL_DIR" ] && [ -n "$(ls -A "$INSTALL_DIR" 2>/dev/null)" ]; then
    if dpkg -s lablivre >/dev/null 2>&1; then
        echo ""
        echo "[AVISO] O LabLivre desta máquina foi instalado pelo pacote .deb"
        echo "        ($(dpkg-query -W -f='${Version}' lablivre 2>/dev/null))."
        echo "        Git e pacote não podem cuidar da mesma pasta."
        echo ""
        echo "  • Para continuar no pacote (recomendado), baixe o .deb novo em"
        echo "      https://github.com/profjefer/lablivre-jfr/releases/latest"
        echo "    e instale por cima:  sudo apt install ./lablivre_*_all.deb"
        echo ""
        echo "  • Para passar a atualizar pelo Git:"
        echo "      sudo apt remove lablivre     (NÃO use purge: mantém macs.txt e lablivre.conf)"
        echo "    e rode este instalador de novo."
        exit 1
    fi
    echo ">> [2/6] $INSTALL_DIR existe sem Git (instalação antiga). Convertendo..."
    echo "         (macs.txt, lablivre.conf, logs e o que não é do LabLivre ficam)"
    sudo chown -R "$USUARIO_REAL:$GRUPO_REAL" "$INSTALL_DIR"
    como_operador git -C "$INSTALL_DIR" init -q
    como_operador git -C "$INSTALL_DIR" remote remove origin 2>/dev/null || true
    como_operador git -C "$INSTALL_DIR" remote add origin "$REPO_URL"
    como_operador git -C "$INSTALL_DIR" fetch -q origin "$BRANCH"
    como_operador git -C "$INSTALL_DIR" checkout -q -f -B "$BRANCH" "origin/$BRANCH"
else
    echo ">> [2/6] Clonando em $INSTALL_DIR..."
    sudo install -d -o "$USUARIO_REAL" -g "$GRUPO_REAL" "$INSTALL_DIR"
    como_operador git clone -q -b "$BRANCH" "$REPO_URL" "$INSTALL_DIR"
fi

# 3. Pastas que não vêm no git + macs.txt
echo ">> [3/6] Criando pastas e conferindo o macs.txt..."
sudo mkdir -p "$INSTALL_DIR"/{logs,configs,configs/.backups,envia_material,web}
sudo SUDO_USER="$USUARIO_REAL" bash "$INSTALL_DIR/modulos/_preservar_macs.sh" restaurar
[ -e "$INSTALL_DIR/configs/macs.txt" ] || sudo touch "$INSTALL_DIR/configs/macs.txt"
sudo SUDO_USER="$USUARIO_REAL" bash "$INSTALL_DIR/modulos/_preservar_macs.sh" salvar

# 4. Dono: o operador (igual ao .deb)
echo ">> [4/6] Atribuindo a instalação a $USUARIO_REAL:$GRUPO_REAL..."
sudo chown -R "$USUARIO_REAL:$GRUPO_REAL" "$INSTALL_DIR"

# 5. Permissões (igual ao postinst do .deb)
echo ">> [5/6] Aplicando permissões..."
chmod +x "$INSTALL_DIR"/*.sh "$INSTALL_DIR"/modulos/*.sh "$INSTALL_DIR"/xmodulos/*.sh \
         "$INSTALL_DIR"/tests/*.sh "$INSTALL_DIR"/packaging/build_deb.sh 2>/dev/null || true
sudo chmod 755 /opt 2>/dev/null || true
chmod 755 "$INSTALL_DIR" "$INSTALL_DIR"/web 2>/dev/null || true
chmod 644 "$INSTALL_DIR"/web/*.html "$INSTALL_DIR"/web/*.json "$INSTALL_DIR"/web/*.js 2>/dev/null || true
# configs/ e logs/ restritos (contêm senha e dados)
chmod 700 "$INSTALL_DIR"/configs "$INSTALL_DIR"/logs 2>/dev/null || true

# 6. Atalhos + servidor web (se a opção 99 já o criou)
echo ">> [6/6] Criando os comandos lablivre e lablivre-gui..."
sudo ln -sf "$INSTALL_DIR"/menu.sh  /usr/local/bin/lablivre
sudo ln -sf "$INSTALL_DIR"/xmenu.sh /usr/local/bin/lablivre-gui
UNIT=/etc/systemd/system/lablivre-web.service
if [ -f "$UNIT" ] && grep -q "WorkingDirectory=$INSTALL_DIR" "$UNIT"; then
    sudo sed -i "s|^ExecStart=.*|ExecStart=/usr/bin/python3 $INSTALL_DIR/modulos/servidor_web.py --porta 8080|" "$UNIT"
    sudo systemctl daemon-reload 2>/dev/null || true
    sudo systemctl restart lablivre-web.service 2>/dev/null || true
    echo "         Servidor web (porta 8080) reiniciado."
fi

echo ""
echo "========================================================"
echo "✅ LABLIVRE $(cat "$INSTALL_DIR/VERSION" 2>/dev/null) PRONTO!"
echo "========================================================"
echo "   Instalado em : $INSTALL_DIR"
echo "   Operado por  : $USUARIO_REAL"
echo "   Comandos     : lablivre      (menu texto)"
echo "                  lablivre-gui  (menu gráfico)"
echo "   Atualizar    : rode este mesmo instalador de novo"
echo ""
if grep -qE '^[[:space:]]*([0-9A-Fa-f]{2}[:-]){5}' "$INSTALL_DIR/configs/macs.txt" 2>/dev/null; then
    echo "  macs.txt: $(grep -cE '^[[:space:]]*([0-9A-Fa-f]{2}[:-]){5}' "$INSTALL_DIR/configs/macs.txt") placas cadastradas."
    echo ""
    echo "  Próximo passo: lablivre → opção 17 (Saúde do sistema)."
    echo "  Se for a primeira vez nesta máquina: opção 99 (Configurações)."
else
    echo "⚠️  PRÓXIMOS PASSOS:"
    echo ""
    echo "  1. Cadastre os MACs das máquinas do laboratório:"
    echo "       nano $INSTALL_DIR/configs/macs.txt"
    echo "     Formato:  aa:bb:cc:dd:ee:ff   nome-da-maquina"
    echo ""
    echo "  2. lablivre → opção 99 (dependências, usuário/senha SSH, cron, web)"
    echo "  3. lablivre → opção 1 (Mapear rede)"
fi
echo ""
echo "  Documentação: $INSTALL_DIR/docs/wiki_lablivre.html"
echo "========================================================"
