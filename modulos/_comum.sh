#!/bin/bash
# ================================================================
# _comum.sh — Base comum dos módulos do LabLivre (desde 4.2.0)
#
# Uso (no topo do módulo, depois do cd para a raiz):
#     cd "$(dirname "$0")/.." || exit 1
#     source modulos/_comum.sh && carregar_conf || exit 1
#
# Módulos gráficos (xmodulos) definem LAB_GUI=1 antes do source
# para os erros aparecerem em janela zenity.
#
# Fornece:
#   Caminhos : LAB_RAIZ, CONF_FILE, ARQUIVO_MACS, ARQUIVO_IPS
#   Config   : carregar_conf (sem senha padrão embutida), salvar_conf_var
#   Máquinas : exigir_ips, para_cada_maquina
#   Saída    : lab_erro
#   SSH      : tudo do _ssh.sh (ssh_remote, ssh_remote_stdin, scp_remote...)
# ================================================================

[ -n "${_LABLIVRE_COMUM:-}" ] && return 0
_LABLIVRE_COMUM=1

LAB_RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONF_FILE="$LAB_RAIZ/configs/lablivre.conf"
ARQUIVO_MACS="$LAB_RAIZ/configs/macs.txt"
ARQUIVO_IPS="$LAB_RAIZ/ips_atuais.txt"

# Cores no terminal: verde = online/ok, vermelho = offline/erro, amarelo =
# aviso. Só quando a saída é um terminal de verdade: arquivos de log, portal
# e janelas do zenity ficam sem códigos de cor. NO_COLOR=1 desliga.
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${LAB_GUI:-0}" != 1 ] && [ "${TERM:-dumb}" != dumb ]; then
    COR_OK=$'\e[1;32m'; COR_ERRO=$'\e[1;31m'; COR_AVISO=$'\e[1;33m'; COR_FIM=$'\e[0m'
else
    COR_OK=""; COR_ERRO=""; COR_AVISO=""; COR_FIM=""
fi

# Módulos gráficos: esconde o ruído inofensivo do GTK/zenity no terminal
# (avisos de opção descontinuada, "GtkDialog mapped without a transient
# parent", GLib-CRITICAL em sessão SSH -X). Erros de verdade continuam.
if [ "${LAB_GUI:-0}" = 1 ] && ! declare -F zenity >/dev/null; then
    export NO_AT_BRIDGE=1
    zenity() {
        command zenity "$@" 2> >(grep -v -E "GLib-GObject-CRITICAL|GLib-GIO-CRITICAL|g_object_unref|assertion '|Gtk-Message|transient parent|descontinuad|deprecated" >&2)
    }
fi

lab_erro() {
    echo "[ERRO] $1" >&2
    if [ "${LAB_GUI:-0}" = 1 ] && command -v zenity >/dev/null 2>&1; then
        zenity --error --title="LabLivre" --text="$1" --width=420 2>/dev/null
    fi
}

# Carrega configs/lablivre.conf + _ssh.sh. Sem conf o módulo PARA,
# em vez de tentar a antiga senha padrão ufpr/UFPR.
carregar_conf() {
    if [ ! -f "$CONF_FILE" ]; then
        lab_erro "configs/lablivre.conf não encontrado. Execute a opção 99 (Configurações Globais) primeiro."
        return 1
    fi
    # shellcheck source=/dev/null
    source "$CONF_FILE"
    if [ -z "${LAB_USUARIO:-}" ]; then
        lab_erro "LAB_USUARIO não definido em configs/lablivre.conf. Execute a opção 99."
        return 1
    fi
    LAB_NOME="${LAB_NOME:-LabLivre}"
    LAB_PASTA_MATERIAL="${LAB_PASTA_MATERIAL:-envia_material}"
    # _ssh.sh usa caminhos relativos à raiz
    pushd "$LAB_RAIZ" >/dev/null || return 1
    # shellcheck source=/dev/null
    source "$LAB_RAIZ/modulos/_ssh.sh"
    popd >/dev/null || true
    # _ssh.sh define estes como relativos; deixa absolutos
    CONF_FILE="$LAB_RAIZ/configs/lablivre.conf"
    CHAVE_SSH="$LAB_RAIZ/configs/lablivre_key"
    if [ "$LAB_AUTH_MODE" = "senha" ] && [ -z "${LAB_SENHA:-}" ]; then
        lab_erro "LAB_SENHA vazia e nenhuma chave SSH configurada. Execute a opção 99."
        return 1
    fi
    return 0
}

# Altera (ou acrescenta) UMA variável do conf, preservando as demais
# (LAB_AUTH_MODE, LAB_IDIOMA, LAB_REDE...).  Uso: salvar_conf_var VAR "valor"
salvar_conf_var() {
    local var="$1" valor="$2" tmp
    mkdir -p "$(dirname "$CONF_FILE")"
    touch "$CONF_FILE"
    valor="${valor//\\/\\\\}"
    valor="${valor//\"/\\\"}"
    tmp=$(mktemp "${CONF_FILE}.XXXXXX") || return 1
    grep -v "^${var}=" "$CONF_FILE" > "$tmp"
    printf '%s="%s"\n' "$var" "$valor" >> "$tmp"
    chmod 600 "$tmp"
    mv -f "$tmp" "$CONF_FILE"
}

exigir_ips() {
    if [ ! -f "$ARQUIVO_IPS" ]; then
        lab_erro "ips_atuais.txt não encontrado. Execute a opção 1 (Mapear Rede) primeiro."
        return 1
    fi
}

# Chama uma função para cada máquina do ips_atuais.txt.
#   para_cada_maquina minha_funcao            → só as ONLINE
#   para_cada_maquina minha_funcao --todas    → inclui OFFLINE (ex.: WoL)
# A função recebe: mac ip nome. Esta máquina (orquestrador) é sempre pulada.
# O laço lê pelo descritor 3: a função pode usar stdin (tar-pipe, read).
para_cada_maquina() {
    local funcao="$1" todas="${2:-}" mac ip nome resto
    exigir_ips || return 1
    while read -r mac ip nome resto <&3; do
        [ -z "$mac" ] && continue
        [[ "$resto" == *"(ESTA MÁQUINA)"* ]] && continue
        [ "$ip" = "OFFLINE" ] && [ "$todas" != "--todas" ] && continue
        "$funcao" "$mac" "$ip" "$nome"
    done 3< <(tail -n +3 "$ARQUIVO_IPS")
}

# ----------------------------------------------------------------
# Scripts remotos (modulos/remoto/*.sh)
# ----------------------------------------------------------------
# Executa um script de modulos/remoto/ NA máquina do aluno, enviado
# pelo stdin do SSH. A senha do sudo vai junto pelo stdin — nunca na
# linha de comando (não aparece no "ps" do aluno).
#   saida=$(rodar_remoto "$ip" modulos/remoto/x.sh arg1 arg2)
#   status=$(status_remoto "$saida")
rodar_remoto() {
    local ip="$1" script="$2" args="" a
    shift 2
    for a in "$@"; do args+=" $(printf '%q' "$a")"; done
    { printf 'SENHA=%q\n' "${LAB_SENHA:-}"; cat "$LAB_RAIZ/$script"; } \
        | ssh_remote_stdin "$ip" "bash -s --$args" 2>&1
}

status_remoto() {
    sed -n 's/^__STATUS=//p' <<< "$1" | tail -n 1
}

# Explica códigos de saída do sshpass/ssh quando não veio __STATUS
erro_ssh() {
    case "$1" in
        5)   echo "senha SSH recusada" ;;
        255) echo "sem conexão SSH" ;;
        *)   echo "SSH retornou $1" ;;
    esac
}

lab_dryrun() { [ "${DRYRUN:-0}" = "1" ]; }

# ----------------------------------------------------------------
# Servidor web (porta 8080) e páginas
# ----------------------------------------------------------------
# O navegador do Ubuntu (Firefox snap) NÃO abre arquivos em /opt via
# file://, então toda página do LabLivre é aberta por http://localhost:8080.
# Um arquivo-marcador com o caminho desta instalação permite saber se
# quem responde na porta é ESTE LabLivre ou um servidor antigo/de outra pasta.
WEB_PORTA=8080
WEB_MARCADOR="lablivre-raiz.txt"

# 0 = este LabLivre responde · 1 = nada na porta · 2 = OUTRO servidor na porta
estado_servidor_web() {
    local corpo rc
    mkdir -p "$LAB_RAIZ/web"
    printf '%s\n' "$LAB_RAIZ" > "$LAB_RAIZ/web/$WEB_MARCADOR" 2>/dev/null
    chmod 644 "$LAB_RAIZ/web/$WEB_MARCADOR" 2>/dev/null
    corpo=$(curl -sf --max-time 3 "http://localhost:$WEB_PORTA/$WEB_MARCADOR" 2>/dev/null)
    rc=$?
    case "$rc" in
        0)  [ "$corpo" = "$LAB_RAIZ" ] && return 0 || return 2 ;;
        7|28) return 1 ;;            # conexão recusada / tempo esgotado
        *)  return 2 ;;              # respondeu, mas sem o marcador (404) = outra pasta
    esac
}

# Sobe o servidor desta instalação (serviço systemd ou, sem sudo, em segundo plano)
iniciar_servidor_web() {
    if systemctl cat lablivre-web.service >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
        sudo -n systemctl restart lablivre-web.service >/dev/null 2>&1
    else
        nohup python3 "$LAB_RAIZ/modulos/servidor_web.py" --porta "$WEB_PORTA" >/dev/null 2>&1 &
    fi
    local i
    for i in 1 2 3 4 5; do
        sleep 1
        estado_servidor_web && return 0
    done
    return 1
}

# Endereço do portal pela rede (IP real desta máquina): funciona daqui,
# de outro computador e por SSH. Sem IP, cai para localhost.
url_portal() {
    local ip
    ip=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')
    [ -z "$ip" ] && ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    echo "http://${ip:-localhost}:$WEB_PORTA/${1:-}"
}

# Abre uma página do portal no navegador. Uso: abrir_pagina_web [arquivo.html]
# Imprime a URL (com o IP real). Numa sessão SSH sem tela, só imprime.
abrir_pagina_web() {
    local pagina="${1:-}" url
    url=$(url_portal "$pagina")
    estado_servidor_web
    case $? in
        0) ;;
        1) iniciar_servidor_web || {
               lab_erro "O servidor web não subiu. Use a opção 'Saúde do sistema' para diagnosticar."
               return 1; } ;;
        2) lab_erro "A porta $WEB_PORTA está ocupada por OUTRO servidor (provavelmente de uma instalação antiga), que mostra páginas velhas. Use a opção 'Saúde do sistema' → corrigir."
           return 1 ;;
    esac
    if { [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; } && command -v xdg-open >/dev/null 2>&1; then
        xdg-open "$url" >/dev/null 2>&1 &
    fi
    echo "$url"
}
