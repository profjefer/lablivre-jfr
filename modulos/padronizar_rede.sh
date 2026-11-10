#!/bin/bash
# ================================================================
# padronizar_rede.sh — Cabo como única rede das máquinas do lab
#
#   bash modulos/padronizar_rede.sh                 → mostra e pergunta (terminal)
#   bash modulos/padronizar_rede.sh verificar       → só mostra
#   bash modulos/padronizar_rede.sh desligar-wifi [máquinas...]
#   bash modulos/padronizar_rede.sh religar-wifi  [máquinas...]
#   (todos aceitam --dry-run)
#
# Máquina no cabo E no wifi: se o cabo falha, ela segue pelo wifi
# (outra sub-rede), some do mapeamento e escapa do Modo Prova sem
# ninguém perceber. "desligar-wifi" tira a conexão automática das
# redes wifi e desconecta o wifi — só onde o cabo está funcionando.
# "religar-wifi" desfaz exatamente o que foi mexido.
#
# Também mostra a velocidade do cabo de cada máquina (10/100/1000 Mb/s).
# ================================================================

cd "$(dirname "$0")/.." || exit 1
source modulos/_comum.sh && carregar_conf && exigir_ips || exit 1
source modulos/_log.sh 2>/dev/null || true
source modulos/_dryrun.sh "$@" 2>/dev/null || true

SCRIPT_REMOTO="modulos/remoto/padronizar_rede.sh"
RELATORIO="logs/padronizar_rede.txt"
mkdir -p logs

ACAO=""; ALVOS=()
for a in "$@"; do
    case "$a" in
        verificar|desligar-wifi|religar-wifi) ACAO="$a" ;;
        -*) ;;
        *) ALVOS+=("$a") ;;
    esac
done
PERGUNTAR=0
if [ -z "$ACAO" ]; then
    ACAO=verificar
    [ -t 0 ] && PERGUNTAR=1
fi

campo() { sed -n "s/^__$1=//p" <<< "$2" | tail -n 1; }

# "enp0s31f6:100:full:ok" → "100 Mb/s"
fmt_cabo() {
    local placa vel dup sit
    IFS=: read -r placa vel dup sit <<< "$1"
    case "$placa" in sem-placa|"") echo "sem placa de cabo"; return ;; esac
    case "$vel" in
        sem-link) echo "❌ sem link" ;;
        1000)     echo "1 Gb/s" ;;
        10000)    echo "10 Gb/s" ;;
        *)        if [ "$vel" -lt 100 ] 2>/dev/null; then echo "⚠️  $vel Mb/s"; else echo "$vel Mb/s"; fi ;;
    esac
    [ "$dup" = half ] && echo " (half-duplex)"
    case "$sit" in sem-ip) echo " · sem IP" ;; desconectado) echo " · desconectado" ;; esac
}

# "wlp0s20f3:connected:UFPR_SEM_FIO" → texto
fmt_wifi() {
    local placa est rede
    [ "$1" = sem-placa ] && { echo "sem placa wifi"; return; }
    IFS=: read -r placa est rede <<< "$1"
    case "$est" in
        connected)            echo "📶 conectado: $rede" ;;
        disconnected)         echo "desconectado" ;;
        unavailable)          echo "desligado" ;;
        unmanaged)            echo "fora do NetworkManager" ;;
        *)                    echo "${est:-?}" ;;
    esac
}

titulo() {
    echo "========================================================"
    echo "  🌐 PADRONIZAR REDE — $1"
    echo "========================================================"
}

declare -A VEL_CONTA=()
TOTAL=0; OK=0; CANDIDATAS=(); PROBLEMAS=()

executar() {
    local mac="$1" ip="$2" nome="$3" saida rc st cabo wifi auto vel linha
    if [ "${#ALVOS[@]}" -gt 0 ] && [[ " ${ALVOS[*]} " != *" $nome "* ]]; then return; fi
    ((TOTAL++))
    saida=$(rodar_remoto "$ip" "$SCRIPT_REMOTO" "$ACAO_REMOTA"); rc=$?
    if lab_dryrun; then
        printf "%-17s [DRY-RUN] %s\n" "$nome" "$ACAO_REMOTA"; return
    fi
    st=$(status_remoto "$saida"); cabo=$(campo CABO "$saida")
    wifi=$(campo WIFI "$saida"); auto=$(campo WIFI_AUTO "$saida")
    if [ -z "$st" ]; then
        linha="❌ $(erro_ssh "$rc")"; PROBLEMAS+=("$nome: $(erro_ssh "$rc")")
    else
        vel=$(cut -d: -f2 <<< "$cabo"); VEL_CONTA[$vel]=$(( ${VEL_CONTA[$vel]:-0} + 1 ))
        linha="cabo $(fmt_cabo "$cabo" | tr -d '\n') · wifi $(fmt_wifi "$wifi")"
        [ -n "$auto" ] && linha+=" · automático: $auto"
        case "$ACAO_REMOTA:$st" in
            verificar:OK)
                ((OK++))
                if [[ "$cabo" == *:ok ]] && { [ -n "$auto" ] || [[ "$wifi" == *:connected:* ]]; }; then
                    CANDIDATAS+=("$nome"); linha+="  ← no cabo E no wifi"
                fi ;;
            desligar-wifi:OK)     ((OK++)); linha="✅ wifi desligado · cabo $(fmt_cabo "$cabo" | tr -d '\n')" ;;
            desligar-wifi:JA_OK)  ((OK++)); linha="✅ já estava só no cabo · cabo $(fmt_cabo "$cabo" | tr -d '\n')" ;;
            desligar-wifi:SEM_WIFI) ((OK++)); linha="✅ sem placa wifi" ;;
            desligar-wifi:CABO_RUIM)
                linha="⚠️  wifi MANTIDO: o cabo não está funcionando ($(fmt_cabo "$cabo" | tr -d '\n'))"
                PROBLEMAS+=("$nome: cabo com problema — troque o cabo/porta antes de tirar o wifi") ;;
            religar-wifi:OK)      ((OK++)); linha="✅ conexão automática do wifi devolvida" ;;
            religar-wifi:JA_OK)   ((OK++)); linha="✅ nada a desfazer (o LabLivre não tinha mexido)" ;;
            *:ERRO_SUDO)          linha="❌ sudo recusou a senha"; PROBLEMAS+=("$nome: sudo") ;;
            *)                    linha="❌ não foi possível ($st) · $linha"; PROBLEMAS+=("$nome: falhou ($st)") ;;
        esac
    fi
    printf "%-17s %s\n" "$nome" "$linha"
    echo "$nome ($ip): $linha" >> "$RELATORIO"
}

rodar() {   # rodar <ação> [máquinas...]
    ACAO_REMOTA="$1"; shift
    [ $# -gt 0 ] && ALVOS=("$@")
    TOTAL=0; OK=0; CANDIDATAS=(); PROBLEMAS=(); VEL_CONTA=()
    { echo ""; echo "== $ACAO_REMOTA — $(date '+%d/%m/%Y %H:%M:%S')"; } >> "$RELATORIO"
    para_cada_maquina executar
    echo "--------------------------------------------------------"
}

resumo_velocidade() {
    local v partes=()
    for v in $(printf '%s\n' "${!VEL_CONTA[@]}" | sort -n); do
        case "$v" in sem-link) partes+=("${VEL_CONTA[$v]}× sem link") ;; *) partes+=("${VEL_CONTA[$v]}× $v Mb/s") ;; esac
    done
    [ "${#partes[@]}" -gt 0 ] || return 0
    echo "Velocidade do cabo: $(IFS='·'; echo "${partes[*]}" | sed 's/·/ · /g')"
    if [ -n "${VEL_CONTA[100]:-}" ] && [ -z "${VEL_CONTA[1000]:-}" ]; then
        echo "   (tudo a 100 Mb/s costuma ser o switch ou o cabeamento, não as máquinas)"
    fi
    for v in "${!VEL_CONTA[@]}"; do
        [ "$v" != sem-link ] && [ "$v" -lt 100 ] 2>/dev/null && \
            echo "   ⚠️  abaixo de 100 Mb/s: cabo, conector ou porta do switch com defeito"
    done | sort -u
}

problemas() {
    [ "${#PROBLEMAS[@]}" -gt 0 ] || return 0
    echo "🔴 Atenção:"; printf '   • %s\n' "${PROBLEMAS[@]}"
}

case "$ACAO" in
    verificar)
        titulo "situação das máquinas"
        rodar verificar
        echo "Resumo: $OK de $TOTAL máquina(s) responderam."
        resumo_velocidade
        problemas
        if [ "${#CANDIDATAS[@]}" -gt 0 ]; then
            echo "📶 No cabo E no wifi (${#CANDIDATAS[@]}): ${CANDIDATAS[*]}"
            echo "   Se o cabo delas falhar, elas seguem pelo wifi, somem do mapeamento"
            echo "   e ficam fora do Modo Prova."
            if [ "$PERGUNTAR" = 1 ]; then
                echo ""
                read -r -p "Desligar o wifi automático dessas ${#CANDIDATAS[@]} máquina(s)? (s/N): " R
                if [[ "${R,,}" == s* ]]; then
                    echo ""
                    titulo "desligando o wifi"
                    rodar desligar-wifi "${CANDIDATAS[@]}"
                    echo "Resumo: ✅ $OK de $TOTAL máquina(s) só no cabo."
                    problemas
                    echo "   Para desfazer: bash modulos/padronizar_rede.sh religar-wifi [máquinas]"
                    lab_dryrun || log_acao "padronizar_rede" "acao=desligar-wifi ok=$OK de=$TOTAL" 2>/dev/null || true
                fi
            else
                echo "   Para desligar: bash modulos/padronizar_rede.sh desligar-wifi"
            fi
        else
            echo "✅ Nenhuma máquina no cabo e no wifi ao mesmo tempo."
        fi ;;
    desligar-wifi)
        titulo "desligando o wifi (só onde o cabo funciona)"
        rodar desligar-wifi
        echo "Resumo: ✅ $OK de $TOTAL máquina(s) só no cabo."
        resumo_velocidade
        problemas
        echo "   Para desfazer: bash modulos/padronizar_rede.sh religar-wifi [máquinas]"
        lab_dryrun || log_acao "padronizar_rede" "acao=desligar-wifi ok=$OK de=$TOTAL" 2>/dev/null || true ;;
    religar-wifi)
        titulo "devolvendo o wifi automático"
        rodar religar-wifi
        echo "Resumo: ✅ $OK de $TOTAL máquina(s)."
        problemas
        lab_dryrun || log_acao "padronizar_rede" "acao=religar-wifi ok=$OK de=$TOTAL" 2>/dev/null || true ;;
esac
echo ">> Relatório: $RELATORIO"
