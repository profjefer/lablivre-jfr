#!/bin/bash
# ================================================================
# modulos/remoto/modo_prova.sh — roda NA MÁQUINA DO ALUNO
#
# Enviado pelo modulos/modo_prova.sh via stdin:
#     ssh ... "bash -s -- ACAO REDES_BASE64 EXPIRA_EPOCH"
#   ACAO  : ativar | liberar | status
#   REDES : redes IPv4 liberadas durante a prova (separadas por espaço)
#   EXPIRA: data/hora (epoch) em que o bloqueio se desfaz sozinho
#   A variável SENHA (sudo) vem prefixada no stdin, nunca na linha
#   de comando (não aparece no "ps" do aluno).
#
# Como o bloqueio funciona (somente IPv4 — ver docs/ROADMAP.md):
#   • Cadeia própria LABLIVRE_PROVA, com salto no topo do OUTPUT.
#     Redes liberadas → RETURN (o firewall que já existir continua valendo);
#     o resto → REJECT (o navegador falha na hora, sem ficar "carregando").
#     Não usa "iptables -F OUTPUT" nem muda a política: não apaga ufw.
#   • Persistência: serviço systemd lablivre-prova reaplica no boot.
#     Reiniciar a máquina NÃO derruba mais a prova.
#   • Validade: o bloqueio se desfaz sozinho em EXPIRA (timer systemd)
#     e, se a máquina ligar depois disso, o serviço se desativa.
#     Uma máquina esquecida nunca fica bloqueada para sempre.
#
# Saída: uma linha "__STATUS=..." para o orquestrador.
# ================================================================

SCRIPT_CLIENTE="/usr/local/sbin/lablivre-prova"
UNIDADE="/etc/systemd/system/lablivre-prova.service"

# sudo sem expor a senha: tenta sem senha; senão manda pelo stdin
comosudo() {
    if sudo -n true 2>/dev/null; then
        sudo -n "$@"
    else
        printf '%s\n' "${SENHA:-}" | sudo -S -p '' "$@"
    fi
}

gerar_script_cliente() {
    local redes="$1" expira="$2"
    cat <<EOF
#!/bin/bash
# LabLivre — Modo Prova (gerado automaticamente pelo orquestrador; não editar)
REDES="$redes"
EXPIRA=$expira
CADEIA=LABLIVRE_PROVA

aplicar() {
    iptables -N "\$CADEIA" 2>/dev/null || iptables -F "\$CADEIA"
    iptables -A "\$CADEIA" -o lo -j RETURN
    for r in \$REDES; do iptables -A "\$CADEIA" -d "\$r" -j RETURN; done
    iptables -A "\$CADEIA" -p tcp -j REJECT --reject-with tcp-reset
    iptables -A "\$CADEIA" -j REJECT
    iptables -C OUTPUT -j "\$CADEIA" 2>/dev/null || iptables -I OUTPUT 1 -j "\$CADEIA"
}

remover() {
    while iptables -D OUTPUT -j "\$CADEIA" 2>/dev/null; do :; done
    iptables -F "\$CADEIA" 2>/dev/null
    iptables -X "\$CADEIA" 2>/dev/null
    return 0
}

agendar_expiracao() {
    local resta=\$(( EXPIRA - \$(date +%s) ))
    [ "\$resta" -lt 1 ] && resta=1
    systemctl stop lablivre-prova-expira.timer lablivre-prova-expira.service >/dev/null 2>&1
    systemd-run --no-block --unit=lablivre-prova-expira --on-active="\${resta}s" \\
        "$SCRIPT_CLIENTE" expirar >/dev/null 2>&1
}

case "\$1" in
    start)
        if [ "\$(date +%s)" -ge "\$EXPIRA" ]; then
            remover
            systemctl disable lablivre-prova.service >/dev/null 2>&1
            exit 0
        fi
        aplicar
        agendar_expiracao
        ;;
    stop)    remover ;;
    expirar) remover; systemctl disable lablivre-prova.service >/dev/null 2>&1 ;;
    *)       echo "uso: \$0 start|stop|expirar"; exit 1 ;;
esac
EOF
}

gerar_unidade() {
    cat <<EOF
[Unit]
Description=LabLivre - Modo Prova (bloqueio de internet IPv4)
DefaultDependencies=no
After=local-fs.target
Before=network-pre.target
Wants=network-pre.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$SCRIPT_CLIENTE start
ExecStop=$SCRIPT_CLIENTE stop

[Install]
WantedBy=multi-user.target
EOF
}

# Modo Prova antigo (≤ 4.2.0) deixava política DROP + regras soltas no OUTPUT.
# Aquela versão já tinha feito "iptables -F OUTPUT", então limpar aqui não
# apaga nada que ainda existisse. Retorna 0 se encontrou e limpou.
limpar_regras_antigas() {
    if comosudo iptables -S OUTPUT 2>/dev/null | grep -q '^-P OUTPUT DROP'; then
        comosudo iptables -F OUTPUT
        comosudo iptables -P OUTPUT ACCEPT
        return 0
    fi
    return 1
}

ativar() {
    local redes="$1" expira="$2" tmp_s tmp_u
    comosudo true 2>/dev/null || { echo "__STATUS=ERRO_SUDO"; return 1; }
    command -v iptables >/dev/null 2>&1 || [ -x /usr/sbin/iptables ] || { echo "__STATUS=SEM_IPTABLES"; return 1; }
    limpar_regras_antigas && echo "__ANTIGO=1"

    # Arquivos temporários do usuário → instalados com sudo
    # (o stdin do sudo é a senha, então o conteúdo não pode ir por pipe)
    tmp_s=$(mktemp); tmp_u=$(mktemp)
    gerar_script_cliente "$redes" "$expira" > "$tmp_s"
    gerar_unidade > "$tmp_u"
    comosudo install -m 755 -o root -g root "$tmp_s" "$SCRIPT_CLIENTE"
    rm -f "$tmp_s"

    if command -v systemctl >/dev/null 2>&1 && [ -d /etc/systemd/system ]; then
        comosudo install -m 644 -o root -g root "$tmp_u" "$UNIDADE"
        comosudo systemctl daemon-reload
        comosudo systemctl enable lablivre-prova.service >/dev/null 2>&1
        # restart = remove + aplica com as redes/validade novas
        comosudo systemctl restart lablivre-prova.service
    else
        comosudo "$SCRIPT_CLIENTE" start
    fi
    rm -f "$tmp_u"

    if comosudo iptables -C OUTPUT -j LABLIVRE_PROVA 2>/dev/null; then
        if comosudo systemctl is-enabled lablivre-prova.service >/dev/null 2>&1; then
            echo "__STATUS=OK"
        else
            echo "__STATUS=OK_SEM_PERSISTENCIA"
        fi
    else
        echo "__STATUS=ERRO_IPTABLES"
        return 1
    fi
}

liberar() {
    comosudo true 2>/dev/null || { echo "__STATUS=ERRO_SUDO"; return 1; }
    comosudo systemctl stop lablivre-prova-expira.timer lablivre-prova-expira.service >/dev/null 2>&1
    comosudo systemctl disable --now lablivre-prova.service >/dev/null 2>&1
    # Garante a remoção mesmo sem o serviço (ex.: versão antiga)
    comosudo bash -c 'while iptables -D OUTPUT -j LABLIVRE_PROVA 2>/dev/null; do :; done
                      iptables -F LABLIVRE_PROVA 2>/dev/null; iptables -X LABLIVRE_PROVA 2>/dev/null; true'
    comosudo rm -f "$UNIDADE" "$SCRIPT_CLIENTE"
    comosudo systemctl daemon-reload >/dev/null 2>&1

    limpar_regras_antigas && echo "__ANTIGO=1"

    if comosudo iptables -C OUTPUT -j LABLIVRE_PROVA 2>/dev/null; then
        echo "__STATUS=ERRO_IPTABLES"; return 1
    fi
    echo "__STATUS=OK"
}

estado() {
    comosudo true 2>/dev/null || { echo "__STATUS=ERRO_SUDO"; return 1; }
    if comosudo iptables -C OUTPUT -j LABLIVRE_PROVA 2>/dev/null; then
        local exp
        exp=$(sed -n 's/^EXPIRA=//p' "$SCRIPT_CLIENTE" 2>/dev/null)
        if [ -n "$exp" ]; then
            echo "__STATUS=ATIVO $(date -d "@$exp" '+%H:%M' 2>/dev/null)"
        else
            echo "__STATUS=ATIVO"
        fi
    elif comosudo iptables -S OUTPUT 2>/dev/null | grep -q '^-P OUTPUT DROP'; then
        echo "__STATUS=ATIVO_ANTIGO"
    else
        echo "__STATUS=LIVRE"
    fi
}

principal() {
    local acao="$1" redes expira="${3:-0}"
    redes=$(printf '%s' "${2:-}" | base64 -d 2>/dev/null)
    case "$acao" in
        ativar)
            if [ -z "$redes" ] || ! [[ "$expira" =~ ^[0-9]+$ ]]; then
                echo "__STATUS=ERRO_PARAMETROS"; return 1
            fi
            ativar "$redes" "$expira" ;;
        liberar) liberar ;;
        status)  estado ;;
        *)       echo "__STATUS=ERRO_PARAMETROS"; return 1 ;;
    esac
}

# stdin em /dev/null: o próprio script chega pelo stdin (bash -s)
principal "$@" < /dev/null
