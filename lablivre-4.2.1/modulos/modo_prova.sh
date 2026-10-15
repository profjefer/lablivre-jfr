#!/bin/bash
# ================================================================
# modo_prova.sh — Bloqueia a internet (IPv4) mantendo a rede local
#
# Uso interativo (menu):  bash modulos/modo_prova.sh
# Uso direto / cron:      bash modulos/modo_prova.sh ativar [HORAS]
#                         bash modulos/modo_prova.sh liberar
#                         bash modulos/modo_prova.sh status
#                         bash modulos/modo_prova.sh reaplicar         (máquinas que ligaram depois)
#                         bash modulos/modo_prova.sh liberar-pendentes (as que estavam desligadas na liberação)
#   --silencioso : sem pop-up/perguntas (usado pelo cron/atualizar_ips)
#   --dry-run    : só mostra o que faria
#
# O trabalho em cada máquina é feito por modulos/remoto/modo_prova.sh:
# cadeia própria no iptables, persistência no boot e validade máxima.
#
# Arquivos de estado (logs/):
#   modo_prova.status     → data de ativação (lido pelos dashboards)
#   modo_prova.expira     → epoch do fim automático
#   modo_prova.maquinas   → MACs bloqueados
#   modo_prova.pendentes  → MACs a liberar quando voltarem a ligar
# ================================================================

cd "$(dirname "$0")/.." || exit 1

source modulos/_comum.sh && carregar_conf || exit 1
source modulos/_log.sh 2>/dev/null || true
source modulos/_dryrun.sh "$@" 2>/dev/null || true

SCRIPT_REMOTO="modulos/remoto/modo_prova.sh"
SCRIPT_AVISO="modulos/remoto/mostrar_mensagem.sh"
FLAG_PROVA="logs/modo_prova.status"
ARQ_EXPIRA="logs/modo_prova.expira"
ARQ_MAQUINAS="logs/modo_prova.maquinas"
ARQ_PENDENTES="logs/modo_prova.pendentes"
mkdir -p logs

# Redes IPv4 que continuam acessíveis durante a prova (lablivre.conf)
LAB_PROVA_REDES="${LAB_PROVA_REDES:-10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 200.236.0.0/16}"
LAB_PROVA_HORAS="${LAB_PROVA_HORAS:-4}"

ACAO=""; SILENCIOSO=0; HORAS=""
for arg in "$@"; do
    case "$arg" in
        ativar|liberar|status|reaplicar|liberar-pendentes) ACAO="$arg" ;;
        --silencioso) SILENCIOSO=1 ;;
        --dry-run|-n) ;;
        [0-9]|[0-9][0-9]) HORAS="$arg" ;;
    esac
done

# O orquestrador também é liberado explicitamente (caso esteja fora das redes acima)
MEU_IP=$(awk '/\(ESTA MÁQUINA\)/ {print $2; exit}' "$ARQUIVO_IPS" 2>/dev/null)
REDES="$LAB_PROVA_REDES"
[[ "$MEU_IP" =~ ^[0-9.]+$ ]] && REDES="$REDES $MEU_IP/32"
REDES_B64=$(printf '%s' "$REDES" | base64 -w0)

MSG_PROVA="MODO PROVA ATIVO

O acesso à internet foi bloqueado pelo professor.
Apenas a rede do campus está disponível.

Esta janela pode ser fechada — o bloqueio continua, mesmo se a máquina for reiniciada."
MSG_FIM="Prova encerrada. A internet foi liberada."

diz() { [ "$SILENCIOSO" = 1 ] || echo "$@"; }

# ---------- listas de MACs (uma por linha) ----------
lista_tem()     { [ -f "$1" ] && grep -qx "$2" "$1"; }
lista_poe()     { lista_tem "$1" "$2" || echo "$2" >> "$1"; }
lista_tira()    { [ -f "$1" ] && { grep -vx "$2" "$1" > "$1.tmp"; mv -f "$1.tmp" "$1"; }; }

mostrar_aviso() {   # ip mensagem
    [ "$SILENCIOSO" = 1 ] && return 0
    rodar_remoto "$1" "$SCRIPT_AVISO" popup \
        "$(printf '%s' "$2" | base64 -w0)" "$(printf '%s' "🔒 LabLivre — Modo Prova" | base64 -w0)" >/dev/null 2>&1 &
}

TOTAL=0; OK=0

# ---------- por máquina ----------
bloquear_maquina() {
    local mac="$1" ip="$2" nome="$3" saida rc st res
    ((TOTAL++))
    [ "$SILENCIOSO" = 1 ] || printf "Bloqueando: %-26s " "$nome ($ip)..."
    saida=$(rodar_remoto "$ip" "$SCRIPT_REMOTO" ativar "$REDES_B64" "$EXPIRA"); rc=$?
    st=$(status_remoto "$saida")
    if lab_dryrun; then res="[DRY-RUN]"
    else
        case "$st" in
            OK)                  res="[BLOQUEADO]"; ((OK++)); lista_poe "$ARQ_MAQUINAS" "$mac"; mostrar_aviso "$ip" "$MSG_PROVA" ;;
            OK_SEM_PERSISTENCIA) res="[BLOQUEADO] (sem systemd: um reboot libera)"; ((OK++)); lista_poe "$ARQ_MAQUINAS" "$mac"; mostrar_aviso "$ip" "$MSG_PROVA" ;;
            ERRO_SUDO)           res="[ERRO] sudo recusou a senha" ;;
            SEM_IPTABLES)        res="[ERRO] iptables não instalado" ;;
            ERRO_IPTABLES)       res="[ERRO] a regra não ficou ativa" ;;
            "")                  res="[ERRO] $(erro_ssh "$rc")" ;;
            *)                   res="[ERRO] $st" ;;
        esac
    fi
    [ "$SILENCIOSO" = 1 ] && [[ "$res" != "[ERRO]"* ]] && echo "Modo Prova reaplicado: $nome ($ip) $res"
    [ "$SILENCIOSO" = 1 ] && [[ "$res" == "[ERRO]"* ]] && echo "Modo Prova FALHOU em $nome ($ip): $res"
    [ "$SILENCIOSO" = 1 ] || echo "$res"
}

liberar_maquina() {
    local mac="$1" ip="$2" nome="$3" saida rc st res
    ((TOTAL++))
    [ "$SILENCIOSO" = 1 ] || printf "Liberando:  %-26s " "$nome ($ip)..."
    saida=$(rodar_remoto "$ip" "$SCRIPT_REMOTO" liberar); rc=$?
    st=$(status_remoto "$saida")
    if lab_dryrun; then res="[DRY-RUN]"
    elif [ "$st" = OK ]; then
        res="[LIBERADO]"; ((OK++))
        lista_tira "$ARQ_MAQUINAS" "$mac"; lista_tira "$ARQ_PENDENTES" "$mac"
        grep -q '^__ANTIGO=1' <<< "$saida" && res="$res (regras antigas da 4.2.0 removidas)"
        mostrar_aviso "$ip" "$MSG_FIM"
    elif [ "$st" = ERRO_SUDO ]; then res="[ERRO] sudo recusou a senha"; lista_poe "$ARQ_PENDENTES" "$mac"
    elif [ -z "$st" ]; then          res="[ERRO] $(erro_ssh "$rc")";   lista_poe "$ARQ_PENDENTES" "$mac"
    else                             res="[ERRO] $st";                 lista_poe "$ARQ_PENDENTES" "$mac"
    fi
    [ "$SILENCIOSO" = 1 ] && echo "Modo Prova: $nome ($ip) $res"
    [ "$SILENCIOSO" = 1 ] || echo "$res"
}

status_maquina() {
    local mac="$1" ip="$2" nome="$3" saida rc st
    ((TOTAL++))
    printf "  %-26s " "$nome ($ip)"
    saida=$(rodar_remoto "$ip" "$SCRIPT_REMOTO" status); rc=$?
    st=$(status_remoto "$saida")
    case "$st" in
        ATIVO_ANTIGO) echo "🔴 bloqueada (regra antiga da 4.2.0 — use Liberar e Ativar de novo)"; ((OK++)) ;;
        "ATIVO "*)    echo "🔴 bloqueada até ${st#ATIVO }"; ((OK++)) ;;
        ATIVO)        echo "🔴 bloqueada"; ((OK++)) ;;
        LIVRE)        echo "🟢 livre" ;;
        ERRO_SUDO)    echo "❓ sudo recusou a senha" ;;
        "")           lab_dryrun && echo "[DRY-RUN]" || echo "❓ $(erro_ssh "$rc")" ;;
        *)            echo "❓ $st" ;;
    esac
}

reaplicar_se_nova() {   # só máquinas ainda não bloqueadas
    lista_tem "$ARQ_MAQUINAS" "$1" && return 0
    bloquear_maquina "$@"
}

liberar_se_pendente() {
    lista_tem "$ARQ_PENDENTES" "$1" || return 0
    liberar_maquina "$@"
}

# ---------- ações ----------
acao_ativar() {
    local horas="${HORAS:-}"
    if [ -z "$horas" ] && [ "$SILENCIOSO" = 0 ]; then
        read -r -p "Duração máxima do bloqueio em horas [$LAB_PROVA_HORAS]: " horas
    fi
    horas="${horas:-$LAB_PROVA_HORAS}"
    [[ "$horas" =~ ^[0-9]+$ ]] && [ "$horas" -ge 1 ] && [ "$horas" -le 24 ] || { echo "[ERRO] Duração inválida (1 a 24 horas)."; exit 1; }

    EXPIRA=$(( $(date +%s) + horas * 3600 ))
    diz ">> Liberado durante a prova: $REDES"
    diz ">> Fim automático: $(date -d "@$EXPIRA" '+%d/%m %H:%M') (mesmo que ninguém libere)"
    diz "--------------------------------------------------------"
    # (a lista de bloqueadas não é zerada: se esta tentativa falhar,
    #  as bloqueadas antes continuam registradas para a liberação)
    para_cada_maquina bloquear_maquina
    lab_dryrun && return 0
    if [ "$OK" -gt 0 ]; then
        date '+%d/%m/%Y %H:%M:%S' > "$FLAG_PROVA"
        echo "$EXPIRA" > "$ARQ_EXPIRA"
        log_acao "modo_prova_ativar" "bloqueadas=$OK de=$TOTAL horas=$horas" 2>/dev/null || true
    fi
    diz "--------------------------------------------------------"
    diz "[CONCLUÍDO] Bloqueadas $OK de $TOTAL máquinas online."
    diz ">> Máquinas que ligarem depois: menu → 3 → 4 (Reaplicar). O cron também reaplica a cada hora."
}

acao_liberar() {
    # Todas as que foram bloqueadas + as online (cobre bloqueios antigos)
    para_cada_maquina liberar_maquina
    lab_dryrun && return 0
    # Bloqueadas que estão desligadas agora → pendentes
    if [ -s "$ARQ_MAQUINAS" ]; then
        while read -r mac; do
            [ -n "$mac" ] && lista_poe "$ARQ_PENDENTES" "$mac"
        done < "$ARQ_MAQUINAS"
        : > "$ARQ_MAQUINAS"
    fi
    rm -f "$FLAG_PROVA" "$ARQ_EXPIRA"
    log_acao "modo_prova_desativar" "liberadas=$OK de=$TOTAL" 2>/dev/null || true
    diz "--------------------------------------------------------"
    diz "[CONCLUÍDO] Internet liberada em $OK de $TOTAL máquinas online."
    if [ -s "$ARQ_PENDENTES" ]; then
        diz "⚠️  $(wc -l < "$ARQ_PENDENTES") máquina(s) bloqueada(s) estão desligadas ou falharam."
        diz "   Serão liberadas automaticamente quando ligarem (cron de hora em hora),"
        diz "   e o bloqueio expira sozinho de qualquer forma."
    fi
}

acao_status() {
    if [ "${VEIO_DO_MENU:-0}" = 1 ]; then
        :   # o cabeçalho do menu já mostrou o registro
    elif [ -f "$FLAG_PROVA" ]; then
        echo "  Registro: 🔴 ATIVO desde $(cat "$FLAG_PROVA")"
        [ -f "$ARQ_EXPIRA" ] && echo "  Fim automático: $(date -d "@$(cat "$ARQ_EXPIRA")" '+%d/%m %H:%M')"
    else
        echo "  Registro: 🟢 Internet liberada"
    fi
    [ -s "$ARQ_PENDENTES" ] && echo "  Pendentes de liberação: $(wc -l < "$ARQ_PENDENTES")"
    echo "--------------------------------------------------------"
    echo "  Situação real em cada máquina online:"
    para_cada_maquina status_maquina
    echo "--------------------------------------------------------"
    echo "  $OK de $TOTAL máquinas online com bloqueio ativo."
}

acao_reaplicar() {
    [ -f "$FLAG_PROVA" ] && [ -f "$ARQ_EXPIRA" ] || { diz "Modo Prova não está ativo."; return 0; }
    EXPIRA=$(cat "$ARQ_EXPIRA")
    if [ "$(date +%s)" -ge "$EXPIRA" ]; then
        rm -f "$FLAG_PROVA" "$ARQ_EXPIRA"; : > "$ARQ_MAQUINAS"
        log_acao "modo_prova_expirou" "" 2>/dev/null || true
        echo "Modo Prova expirou (fim automático)."
        return 0
    fi
    para_cada_maquina reaplicar_se_nova
    diz "[CONCLUÍDO] $OK nova(s) máquina(s) bloqueada(s)."
}

acao_liberar_pendentes() {
    [ -s "$ARQ_PENDENTES" ] || return 0
    [ -f "$FLAG_PROVA" ] && return 0      # prova ativa: não libera ninguém
    para_cada_maquina liberar_se_pendente
}

# ---------- menu ----------
if [ -z "$ACAO" ]; then
    VEIO_DO_MENU=1
    echo "========================================================"
    echo "           🔒 CONTROLE DE REDE (MODO PROVA)             "
    echo "========================================================"
    if [ -f "$FLAG_PROVA" ]; then
        echo "  Status: 🔴 MODO PROVA ATIVO (desde $(cat "$FLAG_PROVA"))"
        [ -f "$ARQ_EXPIRA" ] && echo "  Fim automático: $(date -d "@$(cat "$ARQ_EXPIRA")" '+%d/%m %H:%M')"
    else
        echo "  Status: 🟢 Internet LIBERADA"
    fi
    echo "  (somente IPv4 — ver docs/ROADMAP.md)"
    echo ""
    echo "1) 🔴 ATIVAR Modo Prova (bloquear internet, manter rede local)"
    echo "2) 🟢 LIBERAR internet"
    echo "3) 🔍 Ver situação real em cada máquina"
    echo "4) ♻️  Reaplicar nas máquinas que ligaram depois"
    echo "--------------------------------------------------------"
    read -r -p "Escolha (1-4): " OP
    case "$OP" in
        1) ACAO=ativar ;; 2) ACAO=liberar ;; 3) ACAO=status ;; 4) ACAO=reaplicar ;;
        *) echo "[ERRO] Opção inválida."; exit 1 ;;
    esac
    echo "--------------------------------------------------------"
fi

case "$ACAO" in
    ativar)            acao_ativar ;;
    liberar)           acao_liberar ;;
    status)            acao_status ;;
    reaplicar)         acao_reaplicar ;;
    liberar-pendentes) acao_liberar_pendentes ;;
esac

# Dashboards refletem o estado na hora
if [ "$ACAO" != "status" ] && ! lab_dryrun; then
    bash modulos/gerar_estado.sh >/dev/null 2>&1 \
        && diz ">> Dashboard atualizado: http://localhost:8080/dashboard_prova.html"
fi
