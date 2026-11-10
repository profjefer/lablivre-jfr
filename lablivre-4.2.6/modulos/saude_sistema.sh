#!/bin/bash
# ================================================================
# saude_sistema.sh — Confere se o LabLivre está montado direito
# NESTA máquina (o orquestrador) e, se pedir, corrige.
#
#   bash modulos/saude_sistema.sh             → só verifica
#   bash modulos/saude_sistema.sh --corrigir  → verifica e corrige
#
# Confere: instalação, configuração, macs.txt, dependências,
# mapeamento, servidor web (inclusive se a porta 8080 está com
# um servidor de OUTRA pasta), tarefas do cron e serviços.
# ================================================================

cd "$(dirname "$0")/.." || exit 1
source modulos/_comum.sh

USER="${USER:-$(id -un)}"
CORRIGIR=0; SO_VERIFICAR=0
for a in "$@"; do
    [ "$a" = "--corrigir" ] && CORRIGIR=1
    [ "$a" = "--so-verificar" ] && SO_VERIFICAR=1
done

PROBLEMAS=0; AVISOS=0
ok()    { printf '  ✅ %s\n' "$1"; }
aviso() { printf '  ⚠️  %s\n' "$1"; ((AVISOS++)); }
falha() { printf '  ❌ %s\n' "$1"; ((PROBLEMAS++)); }
dica()  { printf '       → %s\n' "$1"; }
secao() { echo ""; echo "── $1 ──────────────────────────────────────"; }

idade_min() {   # minutos desde a última modificação do arquivo
    local f="$1"; [ -e "$f" ] || { echo -1; return; }
    echo $(( ( $(date +%s) - $(stat -c %Y "$f") ) / 60 ))
}

echo "========================================================"
echo "        🩺 SAÚDE DO SISTEMA — LabLivre $(cat VERSION 2>/dev/null)"
echo "========================================================"
echo "  Instalação: $LAB_RAIZ   ·   usuário: $USER   ·   $(date '+%d/%m %H:%M')"

# ----------------------------------------------------------------
secao "Instalação e configuração"
DONO=$(stat -c %U "$LAB_RAIZ")
if [ "$DONO" = "$USER" ]; then ok "Pasta pertence a $USER"
else falha "Pasta pertence a '$DONO', não a '$USER' (gravações vão falhar)"; dica "sudo chown -R $USER:$USER $LAB_RAIZ"; fi

if [ -f "$CONF_FILE" ]; then
    # shellcheck source=/dev/null
    source "$CONF_FILE"
    ok "lablivre.conf: usuário '${LAB_USUARIO:-?}', autenticação '${LAB_AUTH_MODE:-senha}'"
else
    falha "configs/lablivre.conf não existe"; dica "menu → 99"
fi

if [ -s "$ARQUIVO_MACS" ]; then
    VALIDOS=$(grep -cE '^[[:space:]]*([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}[[:space:]]+[^[:space:]]' "$ARQUIVO_MACS")
    NOMES=$(grep -E '^[[:space:]]*([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' "$ARQUIVO_MACS" | awk '{print $2}' | sort -u | wc -l)
    ok "macs.txt: $NOMES máquinas, $VALIDOS placas cadastradas"
    DUP=$(grep -E '^[[:space:]]*([0-9a-fA-F]{2}:){5}' "$ARQUIVO_MACS" | awk '{print tolower($1)}' | sort | uniq -d)
    for m in $DUP; do
        aviso "MAC repetido no macs.txt: $m ($(grep -i "^[[:space:]]*$m" "$ARQUIVO_MACS" | awk '{print $2}' | paste -sd' ' -))"
        dica "apague a linha repetida"
    done
else
    falha "configs/macs.txt vazio ou ausente (é obrigatório e feito por você)"
fi

# ----------------------------------------------------------------
secao "Dependências"
FALTAM=()
for c in arp-scan nmap sshpass wakeonlan zenity python3 curl ethtool; do
    command -v "$c" >/dev/null 2>&1 || [ -x "/usr/sbin/$c" ] || FALTAM+=("$c")
done
if [ "${#FALTAM[@]}" -eq 0 ]; then ok "Todas instaladas"
else falha "Faltando: ${FALTAM[*]}"; dica "sudo apt install ${FALTAM[*]}"; fi

# ----------------------------------------------------------------
secao "Mapeamento da rede"
if [ -f "$ARQUIVO_IPS" ]; then
    IDADE=$(idade_min "$ARQUIVO_IPS")
    TOT=$(tail -n +3 "$ARQUIVO_IPS" | grep -vc "(ESTA MÁQUINA)")
    ONL=$(tail -n +3 "$ARQUIVO_IPS" | grep -v "(ESTA MÁQUINA)" | awk '$2!="OFFLINE"' | wc -l)
    if [ "$IDADE" -le 70 ]; then ok "ips_atuais.txt de $IDADE min atrás: $ONL de $TOT online"
    else aviso "ips_atuais.txt tem $IDADE min (o cron devia renovar a cada hora): $ONL de $TOT online"
         dica "veja a seção Cron abaixo; para agora: menu → 1"; fi
else
    falha "ips_atuais.txt ainda não existe"; dica "menu → 1"
fi

# ----------------------------------------------------------------
secao "Servidor web (porta $WEB_PORTA)"
estado_servidor_web; EST_WEB=$?
PID_WEB=""; CWD_WEB=""
if command -v ss >/dev/null 2>&1; then
    PID_WEB=$( { ss -ltnpH "sport = :$WEB_PORTA" 2>/dev/null; sudo -n ss -ltnpH "sport = :$WEB_PORTA" 2>/dev/null; } \
               | grep -o 'pid=[0-9]*' | head -1 | cut -d= -f2)
fi
if [ -z "$PID_WEB" ] && command -v fuser >/dev/null 2>&1; then
    PID_WEB=$(fuser -n tcp "$WEB_PORTA" 2>/dev/null | awk '{print $1}')
fi
if [ -n "$PID_WEB" ]; then
    CWD_WEB=$(readlink "/proc/$PID_WEB/cwd" 2>/dev/null || sudo -n readlink "/proc/$PID_WEB/cwd" 2>/dev/null)
fi
case "$EST_WEB" in
    0) ok "Responde e serve ESTA instalação: $(url_portal)" ;;
    1) falha "Ninguém responde na porta $WEB_PORTA (portal e painéis não abrem)" ;;
    2) falha "A porta $WEB_PORTA está com OUTRO servidor${PID_WEB:+ (PID $PID_WEB)}${CWD_WEB:+, servindo $CWD_WEB}"
       dica "é ele que mostra a lista de arquivos, os relatórios velhos e 'todas offline'"
       [ -n "$CWD_WEB" ] && [ "$CWD_WEB" != "$LAB_RAIZ" ] && dica "depois de corrigir, a pasta antiga $CWD_WEB pode ser apagada (guarde o macs.txt dela, se precisar)" ;;
esac
if systemctl cat lablivre-web.service >/dev/null 2>&1; then
    WD=$(systemctl show -p WorkingDirectory --value lablivre-web.service 2>/dev/null)
    ATIVO=$(systemctl is-active lablivre-web.service 2>/dev/null)
    HAB=$(systemctl is-enabled lablivre-web.service 2>/dev/null)
    EXEC=$(systemctl show -p ExecStart --value lablivre-web.service 2>/dev/null)
    if [ "$WD" != "$LAB_RAIZ" ]; then falha "Serviço lablivre-web aponta para '$WD' (devia ser $LAB_RAIZ)"
    elif [[ "$EXEC" != *servidor_web.py* ]]; then falha "Serviço lablivre-web é da versão anterior (sem atualização automática nem botões do Modo Prova)"
    elif [ "$ATIVO" != "active" ]; then falha "Serviço lablivre-web está '$ATIVO' (habilitado: $HAB)"
    else ok "Serviço lablivre-web ativo e habilitado no boot"; fi
else
    falha "Serviço lablivre-web não instalado"
fi

# Quem mais sobe um http.server na 8080 no boot (instalações antigas)?
OUTRAS_UNIDADES=(); OUTROS_AUTOSTART=()
for u in /etc/systemd/system/*.service; do
    [ -f "$u" ] || continue
    [ "$(basename "$u")" = lablivre-web.service ] && continue
    grep -q "http.server.*$WEB_PORTA\|http.server$" "$u" 2>/dev/null && OUTRAS_UNIDADES+=("$(basename "$u")")
done
for d in "$HOME/.config/autostart" /etc/xdg/autostart; do
    for f in "$d"/*.desktop; do
        [ -f "$f" ] && grep -q "http.server" "$f" 2>/dev/null && OUTROS_AUTOSTART+=("$f")
    done
done
CRON_ROOT=$(sudo -n crontab -l 2>/dev/null | grep -E "http\.server|atualizar_ips\.sh|desligar_agendado\.sh" | grep -vF "cd $LAB_RAIZ &&")
for u in "${OUTRAS_UNIDADES[@]}"; do falha "Serviço '$u' também sobe um servidor web (instalação antiga?)"; done
for f in "${OUTROS_AUTOSTART[@]}"; do falha "Início automático da sessão sobe servidor web: $f"; done
[ -n "$CRON_ROOT" ] && { falha "Cron do ROOT tem tarefa LabLivre antiga:"; printf '       %s\n' "$CRON_ROOT"; dica "sudo crontab -e"; }

# ----------------------------------------------------------------
secao "Tarefas agendadas (cron)"
if systemctl is-active cron >/dev/null 2>&1; then ok "Serviço cron ativo"
else falha "Serviço cron parado"; dica "sudo systemctl enable --now cron"; fi

CRON=$(crontab -l 2>/dev/null)
PADRAO_LL='atualizar_ips\.sh|desligar_agendado\.sh|xdesligar_labold\.sh|sincronizar_horario\.sh|snapshot_diario\.sh|_backup_macs\.sh|http\.server 8080|# LabLivre'
LINHAS_LL=$(grep -E "$PADRAO_LL" <<< "$CRON")
ALHEIAS=$(grep -E "$PADRAO_LL" <<< "$CRON" | grep -vF "cd $LAB_RAIZ &&")
for script in atualizar_ips desligar_agendado sincronizar_horario snapshot_diario _backup_macs; do
    if grep -F "cd $LAB_RAIZ &&" <<< "$LINHAS_LL" | grep -q "modulos/$script.sh"; then
        QUANDO=$(grep -F "cd $LAB_RAIZ &&" <<< "$LINHAS_LL" | grep "modulos/$script.sh" | head -1 | awk '{print $1,$2,$3,$4,$5}')
        ok "$script ($QUANDO)"
    else
        falha "Falta a tarefa: $script"
    fi
done
if [ -n "$ALHEIAS" ]; then
    falha "$(wc -l <<< "$ALHEIAS") tarefa(s) do LabLivre apontando para OUTRA pasta (instalação antiga):"
    while IFS= read -r l; do printf '       %s\n' "$(cut -c1-110 <<< "$l")"; done <<< "$ALHEIAS"
fi
for par in "cron_ips.log:mapeamento" "cron_horario.log:horário" "cron_desligar.log:desligamento"; do
    f="logs/${par%%:*}"; n="${par#*:}"
    if [ -f "$f" ]; then echo "       última execução ($n): $(date -r "$f" '+%d/%m %H:%M')"
    else echo "       última execução ($n): nunca"; fi
done

# ----------------------------------------------------------------
secao "Wake-on-LAN e Modo Prova"
IFACE=$(ip route show default 2>/dev/null | awk '{print $5; exit}')
if systemctl is-enabled "wol-${IFACE}.service" >/dev/null 2>&1; then ok "WoL persistente na placa $IFACE"
else aviso "Serviço wol-${IFACE} não habilitado (WoL desta máquina some após reboot)"; fi
if [ -f logs/modo_prova.status ]; then aviso "Modo Prova ATIVO desde $(cat logs/modo_prova.status)"
else ok "Modo Prova desligado"; fi

# ----------------------------------------------------------------
echo ""
echo "========================================================"
if [ "$PROBLEMAS" -eq 0 ]; then
    echo "  ✅ Tudo certo ($AVISOS aviso(s))."
else
    echo "  ❌ $PROBLEMAS problema(s), $AVISOS aviso(s)."
fi
echo "========================================================"

[ "$PROBLEMAS" -eq 0 ] && exit 0
[ "$SO_VERIFICAR" = 1 ] && exit 1
if [ "$CORRIGIR" = 0 ]; then
    if [ -t 0 ]; then
        read -r -p "Corrigir agora (cron, serviço web, servidor antigo)? Pede a senha do sudo. (s/N): " R
        [[ "${R,,}" == "s" ]] || exit 1
    else
        echo "Para corrigir: bash modulos/saude_sistema.sh --corrigir"
        exit 1
    fi
fi

# ================================================================
# CORREÇÃO
# ================================================================
echo ""
echo ">> Corrigindo..."
if [ -n "$ALHEIAS" ]; then
    crontab -l 2>/dev/null | grep -vxF -f <(printf '%s\n' "$ALHEIAS") | crontab -
    echo "   - tarefas de outras pastas removidas do cron"
fi
for u in "${OUTRAS_UNIDADES[@]}"; do
    sudo systemctl disable --now "$u" >/dev/null 2>&1 && echo "   - serviço antigo '$u' desativado"
done
for f in "${OUTROS_AUTOSTART[@]}"; do
    if [ -w "$f" ]; then mv "$f" "$f.desativado-lablivre"; else sudo mv "$f" "$f.desativado-lablivre"; fi \
        && echo "   - início automático desativado: $f"
done
if [ "$EST_WEB" = 2 ]; then
    sudo systemctl stop lablivre-web.service 2>/dev/null
    sudo fuser -k -n tcp "$WEB_PORTA" >/dev/null 2>&1
    sleep 1
    echo "   - servidor antigo da porta $WEB_PORTA encerrado"
fi
echo "   - reinstalando cron, serviço web e WoL (_provisionar.sh)"
bash _provisionar.sh >/dev/null
sleep 2
bash modulos/gerar_estado.sh >/dev/null 2>&1
echo ""
echo ">> Conferindo de novo:"
exec bash modulos/saude_sistema.sh --so-verificar
