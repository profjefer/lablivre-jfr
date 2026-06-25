#!/bin/bash

cd "$(dirname "$0")/.." || exit 1

CONF_FILE="configs/lablivre.conf"
if [ -f "$CONF_FILE" ]; then source "$CONF_FILE"; else LAB_USUARIO="ufpr"; LAB_SENHA="UFPR"; fi
source modulos/_log.sh 2>/dev/null || true
source modulos/_ssh.sh 2>/dev/null || true
source modulos/_dryrun.sh 2>/dev/null || true
ARQUIVO_IPS="ips_atuais.txt"
FLAG_PROVA="logs/modo_prova.status"
mkdir -p logs

echo "========================================================"
echo "           🔒 CONTROLE DE REDE (MODO PROVA)             "
echo "========================================================"

# Mostra status atual
if [ -f "$FLAG_PROVA" ]; then
    ATIVADO_EM=$(cat "$FLAG_PROVA")
    echo "  Status atual: 🔴 MODO PROVA ATIVO (desde $ATIVADO_EM)"
else
    echo "  Status atual: 🟢 Internet LIBERADA"
fi

echo ""
echo "1) 🔴 ATIVAR Modo Prova (Bloquear Internet, manter Intranet)"
echo "2) 🟢 DESATIVAR Modo Prova (Liberar Internet Geral)"
echo "--------------------------------------------------------"
read -p "Escolha a ação (1 ou 2): " ACAO

if [[ "$ACAO" == "1" ]]; then
    STATUS_MSG="[BLOQUEADO]"
    # Aviso visual fullscreen na tela do aluno (Zenity warning, modo not-cancellable)
    CMD_AVISO="export DISPLAY=:0; export XDG_RUNTIME_DIR=/run/user/\$(id -u);         zenity --warning --title='🔒 PROVA EM ANDAMENTO'         --text='<big><b>MODO PROVA ATIVO</b></big>\n\nAcesso à internet pública BLOQUEADO.\nApenas a rede do campus está disponível.\n\nUso de IA, mensageiros e navegação externa foram desativados pelo professor.\n\n<i>Esta janela pode ser fechada — mas o bloqueio permanece.</i>'         --width=550 --no-wrap >/dev/null 2>&1 &"

    CMD_REMOTO="echo '$LAB_SENHA' | sudo -S iptables -F OUTPUT 2>/dev/null; \
                echo '$LAB_SENHA' | sudo -S iptables -P OUTPUT DROP 2>/dev/null; \
                echo '$LAB_SENHA' | sudo -S iptables -I OUTPUT -o lo -j ACCEPT 2>/dev/null; \
                echo '$LAB_SENHA' | sudo -S iptables -I OUTPUT -d 10.0.0.0/8 -j ACCEPT 2>/dev/null; \
                echo '$LAB_SENHA' | sudo -S iptables -I OUTPUT -d 172.16.0.0/12 -j ACCEPT 2>/dev/null; \
                echo '$LAB_SENHA' | sudo -S iptables -I OUTPUT -d 192.168.0.0/16 -j ACCEPT 2>/dev/null; \
                echo '$LAB_SENHA' | sudo -S iptables -I OUTPUT -d 200.236.0.0/16 -j ACCEPT 2>/dev/null"
elif [[ "$ACAO" == "2" ]]; then
    STATUS_MSG="[LIBERADO]"
    CMD_REMOTO="echo '$LAB_SENHA' | sudo -S iptables -P OUTPUT ACCEPT 2>/dev/null; \
                echo '$LAB_SENHA' | sudo -S iptables -F OUTPUT 2>/dev/null"
else
    echo "[ERRO] Opção inválida."
    exit 1
fi

echo ">> Aplicando regras de firewall..."
echo "--------------------------------------------------------"

while read -r mac ip nome resto; do
    if [[ -z "$mac" ]] || [[ "$ip" == "OFFLINE" ]] || [[ "$resto" == *"(ESTA MÁQUINA)"* ]]; then continue; fi

    echo -n "Configurando: $nome ($ip)... "
    ssh_remote "$ip" "$CMD_REMOTO"
    STATUS_IPT=$?

    # Se ativando modo prova, dispara aviso visual na tela do aluno (best-effort)
    if [[ "$ACAO" == "1" ]] && [ $STATUS_IPT -eq 0 ]; then
        ssh_remote "$ip" "$CMD_AVISO" >/dev/null 2>&1
    fi

    [ $STATUS_IPT -eq 0 ] && echo "$STATUS_MSG" || echo "[ERRO]"
done < <(tail -n +3 "$ARQUIVO_IPS")

# Atualiza flag de status
if [[ "$ACAO" == "1" ]]; then
    date '+%d/%m/%Y %H:%M:%S' > "$FLAG_PROVA"
    echo "--------------------------------------------------------"
    echo "[CONCLUÍDO] Modo Prova ATIVADO e registrado em $FLAG_PROVA"
    log_acao "modo_prova_ativar" "online=$(tail -n +3 ips_atuais.txt | grep -v OFFLINE | grep -v 'ESTA MÁQUINA' | wc -l)" 2>/dev/null
else
    rm -f "$FLAG_PROVA"
    echo "--------------------------------------------------------"
    echo "[CONCLUÍDO] Internet LIBERADA. Flag de prova removida."
    log_acao "modo_prova_desativar" "" 2>/dev/null
fi


# Regenera api.json para refletir no dashboard imediatamente
echo "--------------------------------------------------------"
echo ">> Atualizando dashboards..."
if bash modulos/gerar_estado.sh; then
    echo "[OK] Dashboard de Modo Prova atualizado."
    echo "     Veja em: http://localhost:8080/dashboard_prova.html"
else
    echo "[AVISO] Não foi possível atualizar o api.json automaticamente."
    echo "        O firewall foi aplicado, mas o dashboard pode não refletir."
    echo "        Verifique permissões: ls -la web/"
fi
