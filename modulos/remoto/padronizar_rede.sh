#!/bin/bash
# ================================================================
# modulos/remoto/padronizar_rede.sh — roda NA MÁQUINA DO ALUNO
#
#     ssh ... "bash -s -- verificar|desligar-wifi|religar-wifi"
#   (SENHA do sudo prefixada no stdin)
#
# Máquina no cabo E no wifi ao mesmo tempo: se o cabo falha, ela
# continua pelo wifi (outra sub-rede), some do mapeamento e fica fora
# do Modo Prova sem ninguém perceber. Aqui:
#   verificar      só informa (cabo, velocidade, wifi)
#   desligar-wifi  tira a conexão automática das redes wifi e desconecta
#                  o wifi — SÓ se o cabo estiver funcionando
#   religar-wifi   devolve a conexão automática às redes que o
#                  desligar-wifi mexeu (anotadas em /etc/lablivre/)
#
# Saída: __CABO=<placa>:<velocidade Mb/s ou sem-link>:<duplex>:<ok|sem-ip|desconectado>
#        __WIFI=<placa>:<estado>:<rede>     (ou __WIFI=sem-placa)
#        __WIFI_AUTO=<redes wifi com conexão automática, separadas por ,>
#        __STATUS=OK | JA_OK | CABO_RUIM | SEM_WIFI | ERRO_SUDO | ERRO
# ================================================================

ACAO="${1:-verificar}"
MARCA="${LAB_MARCA_WIFI:-/etc/lablivre/wifi_autoconnect_desligado}"

comosudo() {
    if sudo -n true 2>/dev/null; then sudo -n "$@"
    else printf '%s\n' "${SENHA:-}" | sudo -S -p '' "$@"; fi
}

NET="${LAB_SYS_NET:-/sys/class/net}"

# ---------- cabo ----------
CABO=""
for d in "$NET"/*; do
    n="${d##*/}"
    case "$n" in en*|eth*) CABO="$n"; break ;; esac
done
cabo_info="sem-placa:-:-:desconectado"; cabo_ok=0
if [ -n "$CABO" ]; then
    vel=$(cat "$NET/$CABO/speed" 2>/dev/null)
    dup=$(cat "$NET/$CABO/duplex" 2>/dev/null)
    car=$(cat "$NET/$CABO/carrier" 2>/dev/null)
    { [ "$car" != 1 ] || [ -z "$vel" ] || [ "$vel" -le 0 ] 2>/dev/null; } && vel="sem-link"
    estado=$(nmcli -t -f DEVICE,STATE device 2>/dev/null | awk -F: -v d="$CABO" '$1==d {print $2}')
    tem_ip=$(ip -4 -o addr show dev "$CABO" 2>/dev/null | grep -c inet)
    if [ "$vel" != "sem-link" ] && [ "$tem_ip" -gt 0 ] && [ "${estado:-connected}" = connected ]; then
        cabo_ok=1; sit=ok
    elif [ "$vel" != "sem-link" ] && [ "$tem_ip" -eq 0 ]; then
        sit=sem-ip
    else
        sit=desconectado
    fi
    cabo_info="$CABO:$vel:${dup:--}:$sit"
fi
echo "__CABO=$cabo_info"

# ---------- wifi ----------
WIFI=""
for d in "$NET"/*; do
    n="${d##*/}"
    case "$n" in wl*) WIFI="$n"; break ;; esac
done
if [ -z "$WIFI" ]; then
    echo "__WIFI=sem-placa"; echo "__WIFI_AUTO="
    [ "$ACAO" = verificar ] && echo "__STATUS=OK" || echo "__STATUS=SEM_WIFI"
    exit 0
fi
linha=$(nmcli -t -f DEVICE,STATE,CONNECTION device 2>/dev/null | awk -F: -v d="$WIFI" '$1==d')
w_estado=$(cut -d: -f2 <<< "$linha"); w_rede=$(cut -d: -f3- <<< "$linha")
echo "__WIFI=$WIFI:${w_estado:-?}:${w_rede}"

# Conexões wifi (UUID, conexão automática, nome). O UUID vem primeiro porque
# o nome pode ter ":".
wifi_cons() {
    nmcli -t -f UUID,TYPE,AUTOCONNECT,NAME connection show 2>/dev/null \
        | awk -F: '$2=="802-11-wireless"'
}
auto=$(wifi_cons | awk -F: '$3=="yes" {sub(/^[^:]*:[^:]*:[^:]*:/,""); print}' | paste -sd, -)
echo "__WIFI_AUTO=$auto"

case "$ACAO" in
    verificar)
        echo "__STATUS=OK" ;;

    desligar-wifi)
        if [ "$cabo_ok" != 1 ]; then echo "__STATUS=CABO_RUIM"; exit 0; fi
        if [ -z "$auto" ] && [ "$w_estado" != connected ]; then echo "__STATUS=JA_OK"; exit 0; fi
        comosudo true 2>/dev/null || { echo "__STATUS=ERRO_SUDO"; exit 1; }
        comosudo mkdir -p "${MARCA%/*}"
        mexidas=""
        while IFS=: read -r uuid _ ac _; do
            [ "$ac" = yes ] || continue
            comosudo nmcli connection modify "$uuid" connection.autoconnect no >/dev/null 2>&1 \
                && mexidas+="$uuid"$'\n'
        done < <(wifi_cons)
        # acrescenta à anotação (sem repetir), para o religar-wifi desfazer
        # (sem "| comosudo tee": o comosudo usa o stdin para a senha do sudo)
        if [ -n "$mexidas" ]; then
            tmp=$(mktemp)
            { comosudo cat "$MARCA" 2>/dev/null; printf '%s' "$mexidas"; } | sort -u | grep . > "$tmp"
            comosudo cp "$tmp" "$MARCA" && comosudo chmod 644 "$MARCA"
            rm -f "$tmp"
        fi
        [ "$w_estado" = connected ] && comosudo nmcli device disconnect "$WIFI" >/dev/null 2>&1
        # confere
        sobra=$(wifi_cons | awk -F: '$3=="yes"' | wc -l)
        agora=$(nmcli -t -f DEVICE,STATE device 2>/dev/null | awk -F: -v d="$WIFI" '$1==d {print $2}')
        if [ "$sobra" -eq 0 ] && [ "$agora" != connected ]; then echo "__STATUS=OK"
        else echo "__STATUS=ERRO"; exit 1; fi ;;

    religar-wifi)
        comosudo true 2>/dev/null || { echo "__STATUS=ERRO_SUDO"; exit 1; }
        if ! comosudo test -s "$MARCA"; then echo "__STATUS=JA_OK"; exit 0; fi
        while read -r uuid; do
            [ -n "$uuid" ] && comosudo nmcli connection modify "$uuid" connection.autoconnect yes >/dev/null 2>&1
        done < <(comosudo cat "$MARCA")
        comosudo rm -f "$MARCA"
        comosudo nmcli device connect "$WIFI" >/dev/null 2>&1 || true
        echo "__STATUS=OK" ;;

    *)
        echo "__STATUS=ERRO"; exit 1 ;;
esac
