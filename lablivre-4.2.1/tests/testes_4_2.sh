#!/bin/bash
# ================================================================
# tests/testes_4_2.sh — Testes das partes novas da 4.2.x
# Carregado pelo tests/run_tests.sh (usa assert_ok/assert_eq e os
# contadores de lá). Tudo roda num diretório temporário com comandos
# FALSOS no PATH (sshpass, sudo, iptables, systemctl, arp-scan...):
# nada é executado de verdade na rede nem no sistema.
# ================================================================

T42=$(mktemp -d)
B="$T42/bin"; mkdir -p "$B" "$T42/hosts"

# ---------- comandos falsos ----------
# sshpass: "executa" o comando na máquina simulada $T42/hosts/<ip>
cat > "$B/sshpass" <<EOF
#!/bin/bash
shift 2; shift
while [ \$# -gt 0 ]; do case "\$1" in -o) shift 2;; -n|-q) shift;; *@*) alvo="\${1#*@}"; shift; break;; *) shift;; esac; done
[ -d "$T42/hosts/\$alvo" ] || { cat >/dev/null; exit 255; }
export HOME="$T42/hosts/\$alvo" PATH="$B:/usr/bin:/bin"
exec bash -c "\$1"
EOF
# sudo: senha "certa" obrigatória, sem cache
cat > "$B/sudo" <<'EOF'
#!/bin/bash
[ "$1" = "-n" ] && exit 1
[ "$1" = "-S" ] || exit 1
shift; [ "$1" = "-p" ] && shift 2
read -r pw; [ "$pw" = "certa" ] || exit 1
[ "$1" = "-v" ] && exit 0
[ "$1" = "-u" ] && shift 2
exec "$@"
EOF
# iptables com estado em $HOME/iptables.state
cat > "$B/iptables" <<'EOF'
#!/bin/bash
F="$HOME/iptables.state"; touch "$F"; grep -q '^policy ' "$F" || echo "policy ACCEPT" >> "$F"
case "$1" in
 -N) grep -qx "chain $2" "$F" && exit 1; echo "chain $2" >> "$F";;
 -F) grep -v "^rule $2 " "$F" > "$F.t"; mv "$F.t" "$F";;
 -X) grep -qx "chain $2" "$F" || exit 1; grep -vx "chain $2" "$F" > "$F.t"; mv "$F.t" "$F";;
 -A) c=$2; shift 2; echo "rule $c $*" >> "$F";;
 -I) c=$2; shift 3; echo "rule $c $*" >> "$F";;
 -C) c=$2; shift 2; grep -qx "rule $c $*" "$F";;
 -D) c=$2; shift 2; l="rule $c $*"; grep -qx "$l" "$F" || exit 1; awk -v l="$l" '!d && $0==l {d=1; next} 1' "$F" > "$F.t"; mv "$F.t" "$F";;
 -P) grep -v '^policy ' "$F" > "$F.t"; echo "policy $3" >> "$F.t"; mv "$F.t" "$F";;
 -S) echo "-P OUTPUT $(awk '/^policy/{print $2}' "$F")"; sed -n "s/^rule $2 /-A $2 /p" "$F";;
esac
EOF
# install/systemctl/systemd-run: "disco" da máquina em $HOME/fs
cat > "$B/install" <<'EOF'
#!/bin/bash
while [ "${1#-}" != "$1" ]; do shift 2; done
mkdir -p "$HOME/fs$(dirname "$2")"; cp "$1" "$HOME/fs$2"; chmod +x "$HOME/fs$2"
EOF
cat > "$B/systemctl" <<'EOF'
#!/bin/bash
E="$HOME/fs/enabled"; mkdir -p "$E"; SCR="$HOME/fs/usr/local/sbin/lablivre-prova"
now=0; a=(); for x in "$@"; do [ "$x" = --now ] && now=1 || a+=("$x"); done; set -- "${a[@]}"
case "$1" in
 enable) touch "$E/$2";;
 disable) rm -f "$E/$2"; [ $now = 1 ] && [ -x "$SCR" ] && "$SCR" stop;;
 restart) [ -x "$SCR" ] && { "$SCR" stop; "$SCR" start; };;
 is-enabled) [ -f "$E/$2" ];;
esac
exit 0
EOF
printf '#!/bin/bash\necho "$@" >> "$HOME/timer.log"\n' > "$B/systemd-run"
cat > "$B/wall" <<'EOF'
#!/bin/bash
cat >> "$HOME/wall.log"
EOF
cat > "$B/xdg-user-dir" <<'EOF'
#!/bin/bash
[ -f "$HOME/xdg_desktop" ] && cat "$HOME/xdg_desktop" || echo "$HOME"
EOF
# rede do orquestrador
cat > "$B/ip" <<'EOF'
#!/bin/bash
case "$*" in
  "route show default") echo "default via 10.9.0.254 dev eno1 proto dhcp";;
  "-o -f inet addr show dev eno1") echo "2: eno1    inet 10.9.0.1/24 brd 10.9.0.255 scope global eno1";;
  "link show dev eno1") echo "    link/ether aa:00:00:00:00:01 brd ff:ff:ff:ff:ff:ff";;
  "-4 neigh show dev eno1") [ -f "$NEIGH" ] && cat "$NEIGH";;
esac
EOF
printf '#!/bin/bash\necho orquestrador\n' > "$B/hostname"
cat > "$B/arp-scan" <<'EOF'
#!/bin/bash
[ -f "$ARPSCAN" ] && cat "$ARPSCAN"
EOF
printf '#!/bin/bash\nexit 0\n' > "$B/ping"
for c in loginctl zenity; do printf '#!/bin/bash\nexit 0\n' > "$B/$c"; done
chmod +x "$B"/*

# ---------- projeto de teste ----------
P="$T42/lab"
mkdir -p "$P/configs" "$P/logs" "$P/web"
cp -r "$PROJ_DIR/modulos" "$P/"
cat > "$P/configs/lablivre.conf" <<'EOF'
LAB_NOME="Lab Teste"
LAB_USUARIO="aluno"
LAB_SENHA="certa"
LAB_AUTH_MODE="senha"
EOF
roda() { ( cd "$P" && PATH="$B:/usr/bin:/bin" "$@" ); }

# ================================================================
echo ""
echo "[42-1] Base comum (_comum.sh)"
# ================================================================
roda bash -c 'source modulos/_comum.sh && carregar_conf && salvar_conf_var LAB_AUTH_MODE chave && salvar_conf_var LAB_NOME "Lab \"Livre\""'
assert_eq "salvar_conf_var troca só a variável pedida" "aluno" "$(roda bash -c 'source configs/lablivre.conf; echo $LAB_USUARIO')"
assert_eq "salvar_conf_var grava aspas com segurança" 'Lab "Livre"' "$(roda bash -c 'source configs/lablivre.conf; echo "$LAB_NOME"')"
assert_eq "salvar_conf_var não duplica a linha" "1" "$(grep -c '^LAB_AUTH_MODE=' "$P/configs/lablivre.conf")"
roda bash -c 'source modulos/_comum.sh && salvar_conf_var LAB_AUTH_MODE senha'
mv "$P/configs/lablivre.conf" "$P/configs/x.conf"
assert_ok "carregar_conf falha sem lablivre.conf (sem senha padrão)" "! ( cd '$P' && bash -c 'source modulos/_comum.sh && carregar_conf' 2>/dev/null )"
mv "$P/configs/x.conf" "$P/configs/lablivre.conf"

cat > "$P/ips_atuais.txt" <<'EOF'
MAC_ADDRESS        IP_ADDRESS       NOME_MAQUINA
------------------------------------------------
aa:00:00:00:00:01  10.9.0.1         orquestrador (ESTA MÁQUINA)
aa:00:00:00:00:02  10.9.0.2         pc02
aa:00:00:00:00:03  OFFLINE          pc03
aa:00:00:00:00:04  10.9.0.4         pc04
EOF
assert_eq "para_cada_maquina: só online, pula esta máquina" "pc02 pc04" \
    "$(roda bash -c 'source modulos/_comum.sh; f(){ printf "%s " "$3"; }; para_cada_maquina f' | sed 's/ $//')"
assert_eq "para_cada_maquina --todas inclui OFFLINE" "pc02 pc03 pc04" \
    "$(roda bash -c 'source modulos/_comum.sh; f(){ printf "%s " "$3"; }; para_cada_maquina f --todas' | sed 's/ $//')"
assert_eq "para_cada_maquina: função pode ler stdin sem pular máquinas" "2" \
    "$(roda bash -c 'source modulos/_comum.sh; f(){ cat >/dev/null; echo x; }; para_cada_maquina f < /dev/null' | wc -l)"

# ================================================================
echo ""
echo "[42-2] Mapeamento de rede (atualizar_ips.sh)"
# ================================================================
cat > "$P/configs/macs.txt" <<'EOF'
# comentário
aa:00:00:00:00:01  orquestrador
aa:00:00:00:00:02  pc02
aa:00:00:00:00:03  pc03
bb:00:00:00:00:03  pc03
aa:00:00:00:00:04  pc04
aa:00:00:00:00:xx  pc-invalido
aa:00:00:00:00:04  pc04-duplicado
EOF
printf '10.9.0.254\t00:11:22:33:44:55\tRoteador\n10.9.0.2\tAA:00:00:00:00:02\tDell\n10.9.0.33\tbb:00:00:00:00:03\tWifi\n' > "$T42/arp.txt"
SAIDA=$(cd "$P" && PATH="$B:/usr/bin:/bin" ARPSCAN="$T42/arp.txt" bash modulos/atualizar_ips.sh < /dev/null 2>&1)
assert_ok "arp-scan + sudo pela LAB_SENHA" "grep -q 'Método: arp-scan' <<< \"\$SAIDA\""
assert_ok "MAC inválido é avisado" "grep -q 'MAC inválido' <<< \"\$SAIDA\""
assert_ok "MAC duplicado é avisado" "grep -q 'MAC duplicado' <<< \"\$SAIDA\""
assert_ok "esta máquina reconhecida pelo MAC" "grep -q 'orquestrador (ESTA MÁQUINA)' '$P/ips_atuais.txt'"
assert_eq "máquina online pelo cabo" "10.9.0.2" "$(awk '$3=="pc02"{print $2}' "$P/ips_atuais.txt")"
assert_eq "cabo+wifi: online pela wifi" "10.9.0.33" "$(awk '$3=="pc03"{print $2}' "$P/ips_atuais.txt")"
assert_eq "cabo+wifi: grava o MAC do cabo (WoL)" "aa:00:00:00:00:03" "$(awk '$3=="pc03"{print $1}' "$P/ips_atuais.txt")"
assert_eq "máquina sem resposta fica OFFLINE" "OFFLINE" "$(awk '$3=="pc04"{print $2}' "$P/ips_atuais.txt")"
assert_ok "MAC desconhecido é listado" "grep -q '00:11:22:33:44:55' <<< \"\$SAIDA\""

cp "$P/ips_atuais.txt" "$T42/ips_bom.txt"
: > "$T42/arp.txt"
(cd "$P" && PATH="$B:/usr/bin:/bin" ARPSCAN="$T42/arp.txt" bash modulos/atualizar_ips.sh < /dev/null >/dev/null 2>&1)
assert_ok "varredura vazia NÃO apaga o ips_atuais.txt anterior" "cmp -s '$P/ips_atuais.txt' '$T42/ips_bom.txt'"

printf '10.9.0.4 lladdr aa:00:00:00:00:04 REACHABLE\n10.9.0.254 lladdr 00:11:22:33:44:55 STALE\n' > "$T42/neigh.txt"
mv "$B/arp-scan" "$B/arp-scan.off"
SAIDA=$(cd "$P" && PATH="$B:/usr/bin:/bin" NEIGH="$T42/neigh.txt" bash modulos/atualizar_ips.sh < /dev/null 2>&1)
mv "$B/arp-scan.off" "$B/arp-scan"
assert_ok "sem arp-scan/nmap: cai no ping + ARP" "grep -q 'ping+arp' <<< \"\$SAIDA\""
assert_eq "ping + ARP usa só entradas REACHABLE" "10.9.0.4" "$(awk '$3=="pc04"{print $2}' "$P/ips_atuais.txt")"

# ================================================================
echo ""
echo "[42-3] Scripts remotos: mensagem e material"
# ================================================================
cp "$T42/ips_bom.txt" "$P/ips_atuais.txt"
mkdir -p "$T42/hosts/10.9.0.2/Área de trabalho" "$T42/hosts/10.9.0.33/Desktop"
echo "$T42/hosts/10.9.0.2/Área de trabalho" > "$T42/hosts/10.9.0.2/xdg_desktop"
MSG="Não esqueçam o 'trabalho' & a <prova> \"amanhã\"; \$(id)"
printf '%s\n2\n' "$MSG" | roda bash modulos/enviar_mensagem.sh >/dev/null 2>&1
assert_ok "mensagem com aspas e símbolos chega intacta (wall)" "grep -qF -- \"\$MSG\" '$T42/hosts/10.9.0.2/wall.log'"

mkdir -p "$T42/aula 03"; echo pdf > "$T42/aula 03/exercício.pdf"
printf '%s\n\n' "'$T42/aula 03' " | roda bash modulos/distribuir_material.sh >/dev/null 2>&1
assert_ok "material: Desktop em português via xdg-user-dir" "[ -f '$T42/hosts/10.9.0.2/Área de trabalho/Material_Aulas/aula 03/exercício.pdf' ]"
assert_ok "material: Desktop em inglês (plano B)" "[ -f '$T42/hosts/10.9.0.33/Desktop/Material_Aulas/aula 03/exercício.pdf' ]"
assert_ok "material: não cria 'Área de Trabalho' falsa" "[ ! -d '$T42/hosts/10.9.0.33/Área de Trabalho' ]"
assert_ok "material: registrado na auditoria" "grep -q 'distribuir_material' '$P/logs/auditoria.jsonl'"

# ================================================================
echo ""
echo "[42-4] Modo Prova"
# ================================================================
H="$T42/hosts/10.9.0.2"
printf 'policy DROP\nrule OUTPUT -d 10.0.0.0/8 -j ACCEPT\n' > "$H/iptables.state"   # resto da 4.2.0
roda bash modulos/modo_prova.sh ativar 2 >/dev/null 2>&1
assert_ok "ativar: salto para a cadeia LABLIVRE_PROVA" "grep -qx 'rule OUTPUT -j LABLIVRE_PROVA' '$H/iptables.state'"
assert_ok "ativar: redes liberadas com RETURN" "grep -qx 'rule LABLIVRE_PROVA -d 10.0.0.0/8 -j RETURN' '$H/iptables.state'"
assert_ok "ativar: resto é REJECT" "grep -qx 'rule LABLIVRE_PROVA -j REJECT' '$H/iptables.state'"
assert_ok "ativar: limpa a política DROP antiga" "grep -qx 'policy ACCEPT' '$H/iptables.state'"
assert_ok "ativar: persistente (serviço habilitado)" "[ -f '$H/fs/enabled/lablivre-prova.service' ]"
assert_ok "ativar: fim automático agendado" "grep -q 'lablivre-prova-expira' '$H/timer.log'"
assert_ok "ativar: estado registrado no orquestrador" "[ -f '$P/logs/modo_prova.status' ] && [ -s '$P/logs/modo_prova.expira' ]"

printf 'policy ACCEPT\n' > "$H/iptables.state"     # simula reboot
(HOME="$H" PATH="$B:/usr/bin:/bin" "$H/fs/usr/local/sbin/lablivre-prova" start)
assert_ok "reboot: o serviço reaplica o bloqueio" "grep -qx 'rule OUTPUT -j LABLIVRE_PROVA' '$H/iptables.state'"

mv "$T42/hosts/10.9.0.33" "$T42/off33"     # pc03 desliga
roda bash modulos/modo_prova.sh liberar >/dev/null 2>&1
assert_ok "liberar: remove o salto e a cadeia" "! grep -q 'LABLIVRE_PROVA' '$H/iptables.state'"
assert_ok "liberar: desabilita o serviço" "[ ! -f '$H/fs/enabled/lablivre-prova.service' ]"
assert_ok "liberar: desligada vira pendente" "grep -qx 'bb:00:00:00:00:03\|aa:00:00:00:00:03' '$P/logs/modo_prova.pendentes'"
mv "$T42/off33" "$T42/hosts/10.9.0.33"
roda bash modulos/modo_prova.sh liberar-pendentes --silencioso >/dev/null 2>&1
assert_ok "pendente é liberada quando volta" "[ ! -s '$P/logs/modo_prova.pendentes' ] && ! grep -q LABLIVRE_PROVA '$T42/hosts/10.9.0.33/iptables.state'"

roda bash modulos/modo_prova.sh ativar 1 >/dev/null 2>&1
sed -i 's/^EXPIRA=.*/EXPIRA=1000/' "$H/fs/usr/local/sbin/lablivre-prova"
printf 'policy ACCEPT\n' > "$H/iptables.state"
(HOME="$H" PATH="$B:/usr/bin:/bin" "$H/fs/usr/local/sbin/lablivre-prova" start)
assert_ok "vencido: ao ligar não bloqueia e se desativa" "! grep -q LABLIVRE_PROVA '$H/iptables.state' && [ ! -f '$H/fs/enabled/lablivre-prova.service' ]"
roda bash modulos/modo_prova.sh liberar >/dev/null 2>&1

sed -i 's/^LAB_SENHA=.*/LAB_SENHA="errada"/' "$P/configs/lablivre.conf"
assert_ok "senha de sudo errada é informada" "roda bash modulos/modo_prova.sh ativar 1 2>&1 | grep -q 'sudo recusou'"
sed -i 's/^LAB_SENHA=.*/LAB_SENHA="certa"/' "$P/configs/lablivre.conf"
rm -f "$P/logs/modo_prova.status" "$P/logs/modo_prova.expira"

assert_ok "dry-run não aplica nada" "roda bash modulos/modo_prova.sh ativar 1 --dry-run >/dev/null 2>&1; ! grep -q LABLIVRE_PROVA '$H/iptables.state'"
assert_ok "senha não vai na linha de comando remota" "! grep -n 'ssh_remote_stdin \"\$ip\" \".*LAB_SENHA' '$PROJ_DIR'/modulos/{modo_prova,enviar_mensagem,coletar_inventario,sincronizar_horario}.sh"

# ================================================================
echo ""
echo "[42-5] Sincronizar horário"
# ================================================================
cat > "$B/date" <<'EOF'
#!/bin/bash
[ "$1" = "-s" ] && { echo "$2" >> "$HOME/date.log"; exit 0; }
if [ "$1" = "+%s" ] && [[ "$HOME" == */10.9.0.2 ]]; then echo $(( $(/bin/date +%s) - 600 )); exit; fi
exec /bin/date "$@"
EOF
chmod +x "$B/date"
SAIDA=$(roda bash modulos/sincronizar_horario.sh < /dev/null 2>&1)
rm -f "$B/date"
assert_ok "relógio 10 min atrasado é acertado pela hora do orquestrador" "grep -q 'AJUSTADO' <<< \"\$SAIDA\" && [ -s '$H/date.log' ]"
assert_ok "relógio certo não é mexido" "[ ! -f '$T42/hosts/10.9.0.33/date.log' ]"

rm -rf "$T42"
cd "$PROJ_DIR"
