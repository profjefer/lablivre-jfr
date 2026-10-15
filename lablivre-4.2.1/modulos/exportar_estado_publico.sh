#!/bin/bash

# exportar_estado_publico.sh
# Copia/envia o web/api.json para um servidor central (meta-dashboard de múltiplos labs)
#
# Configuração:
#   No configs/lablivre.conf adicione (opcional):
#     LAB_ID="palotina-lab1"               # identificador único deste lab
#     META_DASHBOARD_HOST="servidor.ufpr.br"  # destino
#     META_DASHBOARD_USER="lablivre"          # usuário SSH
#     META_DASHBOARD_PATH="/var/www/labs/"    # pasta no destino
#
# Sem essas variáveis o script sai silenciosamente.
# Roda no cron a cada hora (após gerar_estado).

cd "$(dirname "$0")/.." || exit 1

CONF_FILE="configs/lablivre.conf"
[ -f "$CONF_FILE" ] && source "$CONF_FILE"

# Se não há destino configurado, ignora silenciosamente
[ -z "$META_DASHBOARD_HOST" ] && exit 0
[ -z "$LAB_ID" ] && exit 0
[ ! -f "web/api.json" ] && exit 0

# Copia api.json renomeado com o ID do lab
DESTINO="$META_DASHBOARD_USER@$META_DASHBOARD_HOST:$META_DASHBOARD_PATH/$LAB_ID.json"

# Usa o wrapper ssh do LabLivre (chave ou senha conforme conf)
source modulos/_ssh.sh 2>/dev/null || true
scp_remote web/api.json "$DESTINO" 2>/dev/null

[ $? -eq 0 ] && echo "[export] $LAB_ID enviado para $META_DASHBOARD_HOST" \
             || echo "[export] falha ao enviar"
