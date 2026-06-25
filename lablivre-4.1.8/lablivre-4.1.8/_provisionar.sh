#!/bin/bash

# ============================================================
# _provisionar.sh — Lógica comum de provisionamento
# ============================================================
# Chamado por configurar_lab.sh (texto) e xconfigurar_lab.sh (gráfico)
# após coletar credenciais. NÃO é chamado pelos menus diretamente.
#
# Faz:
#  - Cria estrutura de pastas
#  - Aplica permissões de execução
#  - Ativa Wake-on-LAN persistente via systemd
#  - Instala/atualiza crons (sem duplicar, usa marcador # LabLivre)
# ============================================================

cd "$(dirname "$0")" || exit 1
BASE_DIR="$(pwd)"

# ============================================================
# 1. ESTRUTURA DE PASTAS
# ============================================================
mkdir -p logs modulos xmodulos configs web docs envia_material dashboards/html
touch configs/macs.txt 2>/dev/null

# ============================================================
# 1.5. SEGURANÇA: proteger arquivos sensíveis
# ============================================================
# Conf tem senha SSH — só o dono lê
if [ -f configs/lablivre.conf ]; then
    chmod 600 configs/lablivre.conf
fi
# Pasta configs em geral: só dono lê/grava
chmod 700 configs 2>/dev/null
# Backups de macs.txt também
[ -d configs/.backups ] && chmod 700 configs/.backups
# Chave SSH se existir
[ -f configs/lablivre_key ] && chmod 600 configs/lablivre_key
[ -f configs/lablivre_key.pub ] && chmod 644 configs/lablivre_key.pub
# Logs podem ter informação operacional
chmod 700 logs 2>/dev/null

# ============================================================
# 1.6. PERMISSÕES DE ACESSO WEB
# ============================================================
# A pasta web/ precisa ser legível pelo servidor HTTP (que roda como $USER).
# Se o LabLivre estiver em /opt/lablivre, garantir que o caminho seja
# atravessável (cada diretório do path precisa de +x para outros).
chmod 755 "$BASE_DIR" 2>/dev/null
chmod 755 web 2>/dev/null
chmod 644 web/*.html 2>/dev/null
chmod 644 web/*.json 2>/dev/null
# Se /opt/lablivre, garantir que /opt seja atravessável
if [[ "$BASE_DIR" == /opt/* ]]; then
    sudo chmod 755 /opt 2>/dev/null
fi

# ============================================================
# 2. PERMISSÕES DE EXECUÇÃO
# ============================================================
chmod +x *.sh 2>/dev/null
chmod +x modulos/*.sh 2>/dev/null
chmod +x xmodulos/*.sh 2>/dev/null

# ============================================================
# 3. WAKE-ON-LAN PERSISTENTE
# ============================================================
IFACE=$(ip route | awk '/default/ {print $5}' | head -n 1)

if [ -n "$IFACE" ]; then
    # Tenta ativar (silencioso se não puder)
    sudo ethtool -s "$IFACE" wol g 2>/dev/null

    # Cria/atualiza serviço systemd para persistir após reboot
    SERVICE_FILE="/etc/systemd/system/wol-${IFACE}.service"
    sudo bash -c "cat > $SERVICE_FILE" << EOF
[Unit]
Description=Wake-on-LAN para $IFACE
After=network.target

[Service]
Type=oneshot
ExecStart=/sbin/ethtool -s $IFACE wol g
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload 2>/dev/null
    sudo systemctl enable "wol-${IFACE}.service" >/dev/null 2>&1
    sudo systemctl start "wol-${IFACE}.service" >/dev/null 2>&1
fi

# ============================================================
# 4. CRONS — instala com marcador # LabLivre (evita duplicação)
# ============================================================
# Estratégia: remove TODAS as linhas com "# LabLivre" e reinsere as atuais.
# Assim modo texto e gráfico podem chamar isso sem duplicar.

CRON_TMP="/tmp/lablivre_cron.tmp"

# Crontab atual SEM as linhas LabLivre antigas
crontab -l 2>/dev/null | grep -v "# LabLivre" > "$CRON_TMP"

# Adiciona as linhas atuais (fonte única da verdade)
{
    # A cada hora: atualizar IPs e regenerar api.json
    echo "0 * * * * cd $BASE_DIR && bash modulos/atualizar_ips.sh >> logs/cron_ips.log 2>&1 && bash modulos/gerar_estado.sh >> logs/cron_estado.log 2>&1 && bash modulos/gerar_auditoria_json.sh >> logs/cron_estado.log 2>&1 && bash modulos/gerar_mapa_calor.sh >> logs/cron_estado.log 2>&1 # LabLivre"
    # Diariamente às 23h: desligar laboratório
    echo "0 23 * * * cd $BASE_DIR && bash modulos/desligar_agendado.sh >> logs/cron_desligar.log 2>&1 # LabLivre"
    # Diariamente às 7h: sincronizar horário
    echo "0 7 * * * cd $BASE_DIR && bash xmodulos/xsincronizar_horario.sh >> logs/cron_horario.log 2>&1 # LabLivre"
    # Domingo 03h: backup do macs.txt
    # 23h59 todo dia: snapshot do histórico
    echo "59 23 * * * cd $BASE_DIR && bash modulos/snapshot_diario.sh >> logs/cron_snapshot.log 2>&1 # LabLivre"
    echo "0 3 * * 0 cd $BASE_DIR && bash modulos/_backup_macs.sh >> logs/cron_backup.log 2>&1 # LabLivre"
} >> "$CRON_TMP"

crontab "$CRON_TMP"
rm -f "$CRON_TMP"

# ============================================================
# 5. SERVIDOR WEB (systemd, não @reboot do cron)
# ============================================================
# Mais robusto que @reboot do cron — reinicia se cair
SERVICE_WEB="/etc/systemd/system/lablivre-web.service"
sudo bash -c "cat > $SERVICE_WEB" << EOF
[Unit]
Description=LabLivre Web Dashboard
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$BASE_DIR
ExecStart=/usr/bin/python3 -m http.server 8080 --directory web/
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload 2>/dev/null
sudo systemctl enable lablivre-web.service >/dev/null 2>&1
sudo systemctl restart lablivre-web.service >/dev/null 2>&1

# ============================================================
# 6. GERA api.json INICIAL (mesmo sem ips_atuais.txt ainda)
# ============================================================
bash "$BASE_DIR/modulos/gerar_estado.sh" >/dev/null 2>&1 || true

# ============================================================
# RETORNA INFO PARA O CHAMADOR
# ============================================================
echo "PROVISIONADO_IFACE=$IFACE"
echo "PROVISIONADO_DIR=$BASE_DIR"
