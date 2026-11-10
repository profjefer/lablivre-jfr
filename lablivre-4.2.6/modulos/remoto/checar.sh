#!/bin/bash
# ================================================================
# modulos/remoto/checar.sh — roda NA MÁQUINA DO ALUNO (diagnóstico)
#
# Não muda nada. Responde:
#   __HOST=<hostname>      (para conferir se o IP é mesmo daquela máquina)
#   __SESSAO=<usuário>     (quem está logado na tela; vazio = ninguém)
#   __STATUS=OK | ERRO_SUDO
# ================================================================
echo "__HOST=$(hostname)"
sessao=""
while read -r sid _ user _; do
    [ -z "$sid" ] && continue
    [ "$(loginctl show-session "$sid" -p Class --value 2>/dev/null)" = user ] || continue
    [ "$(loginctl show-session "$sid" -p Remote --value 2>/dev/null)" = yes ] && continue
    case "$(loginctl show-session "$sid" -p Type --value 2>/dev/null)" in x11|wayland) sessao="$user"; break ;; esac
done < <(loginctl list-sessions --no-legend 2>/dev/null)
echo "__SESSAO=$sessao"
# Wake-on-LAN de cada placa cabeada (atual/suporta), sem mudar nada
ET=$(command -v ethtool || { [ -x /usr/sbin/ethtool ] && echo /usr/sbin/ethtool; })
wol=""
for dev in "${LAB_SYS_NET:-/sys/class/net}"/*; do
    n="${dev##*/}"
    [ "$n" = lo ] || [ -d "$dev/wireless" ] || [ ! -e "$dev/device" ] && continue
    if [ -z "$ET" ]; then wol="sem-ethtool"; break; fi
    info=$( { sudo -n "$ET" "$n" 2>/dev/null || printf '%s\n' "${SENHA:-}" | sudo -S -p '' "$ET" "$n" 2>/dev/null; } )
    wol+="$n:$(awk '/^[[:space:]]*Wake-on:/ {print $2}' <<< "$info")/$(awk '/Supports Wake-on:/ {print $3}' <<< "$info") "
done
echo "__WOL=${wol% }"
systemctl is-enabled lablivre-wol.service >/dev/null 2>&1 && echo "__WOL_PERMANENTE=sim"
if sudo -n true 2>/dev/null || printf '%s\n' "${SENHA:-}" | sudo -S -p '' true 2>/dev/null; then
    echo "__STATUS=OK"
else
    echo "__STATUS=ERRO_SUDO"
fi
