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
  "-4 route get 1.1.1.1") echo "1.1.1.1 via 10.9.0.254 dev eno1 src 10.9.0.1 uid 1000";;
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
# NTP "não sincronizado" nas máquinas simuladas: sem isto o teste usaria o
# timedatectl real do orquestrador e dependeria do NTP desta máquina.
cat > "$B/timedatectl" <<'EOF'
#!/bin/bash
[ "$1" = "show" ] && { echo no; exit 0; }
exit 0
EOF
chmod +x "$B/date" "$B/timedatectl"
SAIDA=$(roda bash modulos/sincronizar_horario.sh < /dev/null 2>&1)
rm -f "$B/date" "$B/timedatectl"
assert_ok "relógio 10 min atrasado é acertado pela hora do orquestrador" "grep -q 'AJUSTADO' <<< \"\$SAIDA\" && [ -s '$H/date.log' ]"
assert_ok "relógio certo não é mexido" "[ ! -f '$T42/hosts/10.9.0.33/date.log' ]"

# ================================================================
echo ""
echo "[42-6] 4.2.2: ligar, desligar, diagnóstico, teste, web"
# ================================================================
cp "$T42/ips_bom.txt" "$P/ips_atuais.txt"
printf '#!/bin/bash\necho "$*" >> "%s/wol.log"\n' "$T42" > "$B/wakeonlan"
cat > "$B/hostname" <<'EOF'
#!/bin/bash
case "$HOME" in */10.9.0.2) echo pc02;; */10.9.0.33) echo pc03;; *) echo orquestrador;; esac
EOF
# porta 22 "aberta" só nas máquinas simuladas
cat > "$B/timeout" <<EOF
#!/bin/bash
for a in "\$@"; do case "\$a" in */dev/tcp/*) ip=\${a#*/dev/tcp/}; ip=\${ip%%/*}; [ -d "$T42/hosts/\$ip" ]; exit;; esac; done
shift; exec "\$@"
EOF
chmod +x "$B"/*

roda bash modulos/ligar_labold.sh --sem-esperar >/dev/null 2>&1
assert_eq "ligar: 3 rodadas × 2 destinos para cada placa" "6" "$(grep -c 'aa:00:00:00:00:02' "$T42/wol.log")"
assert_ok "ligar: usa o broadcast da sub-rede" "grep -q -- '-i 10.9.0.255 aa:00:00:00:00:02' '$T42/wol.log'"
assert_ok "ligar: acorda também a 2ª placa (macs.txt)" "grep -q 'bb:00:00:00:00:03' '$T42/wol.log'"
assert_ok "ligar: não manda para esta máquina" "! grep -q 'aa:00:00:00:00:01' '$T42/wol.log'"
: > "$T42/wol.log"
roda bash modulos/ligar_labold.sh pc04 --sem-esperar >/dev/null 2>&1
assert_ok "ligar: só as máquinas citadas" "grep -q 'aa:00:00:00:00:04' '$T42/wol.log' && ! grep -q 'aa:00:00:00:00:02' '$T42/wol.log'"

rm -f "$H/timer.log"
SAIDA=$(roda bash modulos/desligar_labold.sh --sim < /dev/null 2>&1)
assert_ok "desligar: desligamento agendado na máquina (poweroff)" "grep -q 'poweroff' '$H/timer.log'"
assert_ok "desligar: senha fora da linha de comando" "! grep -q 'LAB_SENHA' '$PROJ_DIR/modulos/desligar_labold.sh' '$PROJ_DIR/modulos/desligar_agendado.sh'"
assert_ok "desligar: resumo" "grep -q 'CONCLUÍDO.*2 de 2' <<< \"\$SAIDA\""

SAIDA=$(roda bash modulos/diagnosticar_ssh.sh --sem-remapear < /dev/null 2>&1)
assert_ok "diagnóstico: máquina ok" "grep -q 'pc02.*✅' <<< \"\$SAIDA\""
assert_ok "diagnóstico: offline separada" "grep -q 'pc04.*💀' <<< \"\$SAIDA\""
sed -i 's/^LAB_SENHA=.*/LAB_SENHA="errada"/' "$P/configs/lablivre.conf"
assert_ok "diagnóstico: sudo recusado é apontado" "roda bash modulos/diagnosticar_ssh.sh --sem-remapear < /dev/null 2>&1 | grep -q 'pc02.*sudo recusa'"
sed -i 's/^LAB_SENHA=.*/LAB_SENHA="certa"/' "$P/configs/lablivre.conf"
cp "$B/hostname" "$T42/hn.bak"; printf '#!/bin/bash\necho outro-nome\n' > "$B/hostname"
assert_ok "diagnóstico: hostname diferente é só informativo (✅ + ℹ️)" "roda bash modulos/diagnosticar_ssh.sh --sem-remapear < /dev/null 2>&1 | grep -q 'pc02.*✅.*ℹ️.*outro-nome'"
cp "$T42/hn.bak" "$B/hostname"

printf '10.9.0.2\taa:00:00:00:00:02\tDell\n10.9.0.33\tbb:00:00:00:00:03\tWifi\n' > "$T42/arp.txt"
SAIDA=$(cd "$P" && PATH="$B:/usr/bin:/bin" ARPSCAN="$T42/arp.txt" bash modulos/testar_conexao.sh < /dev/null 2>&1)
assert_ok "teste de conexão remapeia antes" "grep -q 'Método: arp-scan' <<< \"\$SAIDA\""
assert_ok "teste de conexão: SSH ok" "grep -q '✅ pc02' <<< \"\$SAIDA\""
assert_ok "teste de conexão: fora da rede" "grep -q '❌ pc04' <<< \"\$SAIDA\""

printf '%s\n1\n' "oi" | roda bash modulos/enviar_mensagem.sh > "$T42/msg.txt" 2>&1
assert_ok "mensagem: resumo separa entregue / sem aluno / erro" "grep -q 'entregue: .* sem aluno logado: .* erro: ' '$T42/msg.txt'"

# servidor web: este, nenhum, outro
cat > "$B/curl" <<'EOF'
#!/bin/bash
case "$CURL_MODO" in este) cat "$LAB_WEB_RAIZ/web/lablivre-raiz.txt";; nada) exit 7;; outro) exit 22;; esac
EOF
chmod +x "$B/curl"
for m in este:0 nada:1 outro:2; do
    assert_eq "estado_servidor_web: ${m%%:*}" "${m#*:}" \
        "$(cd "$P" && PATH="$B:/usr/bin:/bin" CURL_MODO=${m%%:*} LAB_WEB_RAIZ="$P" bash -c 'source modulos/_comum.sh; estado_servidor_web; echo $?')"
done
assert_ok "abrir_pagina_web recusa servidor de outra pasta" \
    "! ( cd '$P' && PATH='$B:/usr/bin:/bin' CURL_MODO=outro bash -c 'source modulos/_comum.sh; abrir_pagina_web x.html' >/dev/null 2>&1 )"
rm -f "$P/web/inventario.html"
roda bash modulos/gerar_estado.sh >/dev/null 2>&1
assert_ok "inventário ausente vira página-aviso (não 404)" "grep -q 'ainda não coletado' '$P/web/inventario.html'"
assert_ok "xmenu não gera mais relatorio_*.html nem status.html" "! grep -qE 'web/relatorio_|status\.html' '$PROJ_DIR/xmodulos/xmenu.sh'"
assert_ok "nenhum xmodulo abre file://" "! grep -rq 'file://' '$PROJ_DIR/xmodulos'"

# ================================================================
echo ""
echo "[42-7] 4.2.3: servidor web com API (páginas sempre atuais, botões do Modo Prova)"
# ================================================================
W="$T42/srv"; mkdir -p "$W/modulos" "$W/web"
cp "$PROJ_DIR/modulos/servidor_web.py" "$W/modulos/"
printf 'echo mapeando; sleep 1; echo x > ips_atuais.txt\n' > "$W/modulos/atualizar_ips.sh"
printf 'echo "prova $*"\n' > "$W/modulos/modo_prova.sh"
PORTA=$(( 20000 + RANDOM % 20000 ))
( cd "$W" && exec python3 modulos/servidor_web.py --porta "$PORTA" >/dev/null 2>&1 ) &
PID_SRV=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do curl -s "localhost:$PORTA/api/info" >/dev/null 2>&1 && break; sleep 0.3; done
U="http://localhost:$PORTA"
HJ=(-H 'X-LabLivre: 1' -H 'Content-Type: application/json')
assert_ok "servidor: escreve o marcador desta instalação" "grep -qx '$W' '$W/web/lablivre-raiz.txt'"
assert_ok "servidor: /api/info responde e reconhece localhost" "curl -s '$U/api/info' | grep -q '\"local\": true'"
assert_ok "servidor: POST sem cabeçalho X-LabLivre é recusado" "curl -s -o /dev/null -w '%{http_code}' -X POST '$U/api/atualizar' | grep -q 403"
assert_ok "servidor: mapa velho → remapeia" "curl -s ${HJ[*]@Q} -X POST '$U/api/atualizar' -d '{}' | grep -q '\"iniciado\": true'"
sleep 2
assert_ok "servidor: mapa recente → não remapeia" "curl -s ${HJ[*]@Q} -X POST '$U/api/atualizar' -d '{\"se_mais_velho_que\": 0}' | grep -q recente"
assert_ok "servidor: ação de prova inválida é recusada" "curl -s ${HJ[*]@Q} -X POST '$U/api/prova' -d '{\"acao\": \"rm\"}' | grep -q 'inválida'"
assert_ok "servidor: duração fora de 1–24 h é recusada" "curl -s ${HJ[*]@Q} -X POST '$U/api/prova' -d '{\"acao\": \"ativar\", \"horas\": 48}' | grep -q 'inválida'"
curl -s "${HJ[@]}" -X POST "$U/api/prova" -d '{"acao": "ativar", "horas": 3}' >/dev/null
sleep 1
assert_ok "servidor: ativar chama modo_prova.sh ativar 3" "curl -s '$U/api/tarefa' | grep -q 'prova ativar 3'"
assert_ok "servidor: JSON e páginas sem cache" "curl -sI '$U/lablivre-raiz.txt' >/dev/null; echo '{}' > '$W/web/api.json'; curl -sI '$U/api.json' | grep -qi 'no-store'"
assert_eq "servidor: Modo Prova recusado para quem não é desta máquina" "False" \
    "$(cd "$W/modulos" && python3 -c "
import servidor_web as s
class F: pass
f = F(); f.client_address = ('10.99.99.99', 1)
s.meus_ips = lambda: {'10.0.0.5'}
print(s.Manipulador.eh_local(f))")"
mkdir -p "$W/configs"; echo 'LAB_WEB_ADMINS="10.99.99.99"' > "$W/configs/lablivre.conf"
assert_eq "servidor: LAB_WEB_ADMINS libera os botões para outro IP" "True" \
    "$(cd "$W/modulos" && python3 -c "
import servidor_web as s
class F: pass
f = F(); f.client_address = ('10.99.99.99', 1)
s.meus_ips = lambda: set()
print(s.Manipulador.eh_local(f))")"
assert_ok "url_portal usa o IP real, não localhost" "cd '$P' && PATH='$B:/usr/bin:/bin' bash -c 'source modulos/_comum.sh; url_portal x.html' | grep -q '^http://10\.9\.0\.1:8080/x.html'"
kill "$PID_SRV" 2>/dev/null; wait "$PID_SRV" 2>/dev/null
assert_ok "todas as páginas de estado usam lablivre.js (atualização automática)" \
    "for f in index maquinas dashboard_operacional dashboard_tv dashboard_hacker dashboard_prova; do grep -q 'LabLivre.manterAtual' '$PROJ_DIR/web/'\$f.html || exit 1; done"
assert_ok "serviço web usa o servidor novo" "grep -q 'servidor_web.py' '$PROJ_DIR/_provisionar.sh'"

# ================================================================
echo ""
echo "[42-8] 4.2.5: 2ª placa no portal, fabricante dos desconhecidos"
# ================================================================
printf '10.9.0.254\t00:11:22:33:44:55\tExtreme Networks\n10.9.0.2\taa:00:00:00:00:02\tDell\n10.9.0.33\tbb:00:00:00:00:03\tIntel\n' > "$T42/arp.txt"
SAIDA=$(cd "$P" && PATH="$B:/usr/bin:/bin" ARPSCAN="$T42/arp.txt" bash modulos/atualizar_ips.sh < /dev/null 2>&1)
assert_ok "ips_atuais registra a 2ª placa que respondeu" "grep -q 'pc03 (via bb:00:00:00:00:03)' '$P/ips_atuais.txt'"
assert_ok "api.json leva a 2ª placa (via)" "grep -q '\"nome\":\"pc03\",\"status\":\"online\",\"esta_maquina\":false,\"via\":\"bb:00:00:00:00:03\"' '$P/web/api.json'"
assert_ok "desconhecido mostra fabricante e gateway" "grep -q '00:11:22:33:44:55 (10.9.0.254).*roteador/gateway · Extreme Networks' <<< \"\$SAIDA\""
assert_ok "mapeamento termina com o endereço do portal" "grep -q 'Portal atualizado: http://10.9.0.1:8080/maquinas.html' <<< \"\$SAIDA\""
assert_ok "para_cada_maquina continua lendo o nome certo com '(via ...)'" "[ \"\$(roda bash -c 'source modulos/_comum.sh; f(){ [ \"\$3\" = pc03 ] && echo ok; }; para_cada_maquina f')\" = ok ]"

# ================================================================
echo ""
echo "[42-9] 4.2.6: Wake-on-LAN permanente, diagnóstico do WoL, limpeza"
# ================================================================
mkdir -p "$T42/sysnet/eno1/device" "$T42/sysnet/wlp2s0/device" "$T42/sysnet/wlp2s0/wireless" "$T42/sysnet/lo"
cat > "$B/ethtool" <<'EOF'
#!/bin/bash
F="$HOME/wol.$1"; [ "$1" = -s ] && { echo "$4" > "$HOME/wol.$2"; exit 0; }
printf '\tSupports Wake-on: pumbg\n\tWake-on: %s\n' "$(cat "$F" 2>/dev/null || echo d)"
EOF
chmod +x "$B/ethtool"
SAIDA=$(cd "$P" && PATH="$B:/usr/bin:/bin" LAB_SYS_NET="$T42/sysnet" bash modulos/diagnosticar_ssh.sh --sem-remapear < /dev/null 2>&1)
assert_ok "diagnóstico mostra WoL desarmado" "grep -q 'pc02.*WoL desarmado (eno1:d/pumbg)' <<< \"\$SAIDA\""
assert_ok "diagnóstico indica o menu 18" "grep -q 'menu 18' <<< \"\$SAIDA\""
SAIDA=$(cd "$P" && PATH="$B:/usr/bin:/bin" LAB_SYS_NET="$T42/sysnet" bash modulos/preparar_wol.sh < /dev/null 2>&1)
assert_ok "preparar WoL: arma só a placa cabeada" "[ \"\$(cat '$H/wol.eno1')\" = g ] && [ ! -f '$H/wol.wlp2s0' ]"
assert_ok "preparar WoL: serviço permanente criado e habilitado" "grep -q 'ethtool -s eno1 wol g' '$H/fs/etc/systemd/system/lablivre-wol.service' && [ -f '$H/fs/enabled/lablivre-wol.service' ]"
assert_ok "preparar WoL: resumo" "grep -q 'Resumo: ✅ 2 de 2' <<< \"\$SAIDA\""
mv "$B/ethtool" "$B/ethtool.off"
printf '#!/bin/bash\nexit 1\n' > "$B/apt-get"; chmod +x "$B/apt-get"
SAIDA=$(cd "$P" && PATH="$B:/usr/bin:/bin" LAB_SYS_NET="$T42/sysnet" LAB_ETHTOOL_EXTRA="" bash modulos/preparar_wol.sh pc02 < /dev/null 2>&1)
mv "$B/ethtool.off" "$B/ethtool"; rm -f "$B/apt-get"
assert_ok "preparar WoL: sem ethtool e sem apt é explicado" "grep -q 'pc02.*sem ethtool' <<< \"\$SAIDA\""
SAIDA=$(printf 'SIM\n' | roda bash modulos/limpar_downloads.sh 2>&1)
assert_ok "limpeza: resumo com limpas / falharam / itens" "grep -q '^Resumo: 🟢 2 máquina(s) limpa(s) · 🔴 0 falharam' <<< \"\$SAIDA\""
assert_ok "barra de progresso gráfica não escapa texto (&gt;)" "! grep -q 'x_escapar)\"' '$PROJ_DIR/xmodulos/_xmotor.sh'"

# ================================================================
echo ""
echo "[42-10] 4.2.7: macs.txt sobrevive à reinstalação, gitinstall"
# ================================================================
PM="$T42/pm"; mkdir -p "$PM/lab/configs" "$PM/legado"
pm() { LAB_DIR="$PM/lab" LAB_BACKUP_DIR="$PM/var" LAB_HOME_BACKUP="$PM/home" LAB_LEGADO="$PM/legado/macs-lablivre.txt" bash "$PROJ_DIR/modulos/_preservar_macs.sh" "$@"; }
printf '# lab\naa:00:00:00:00:01  pc01\naa:00:00:00:00:02  pc02\n' > "$PM/lab/configs/macs.txt"
pm salvar >/dev/null
assert_ok "salvar: cópia fora do /opt e na pasta pessoal" "cmp -s '$PM/lab/configs/macs.txt' '$PM/var/macs.txt' && cmp -s '$PM/lab/configs/macs.txt' '$PM/home/macs.txt'"
: > "$PM/lab/configs/macs.txt"; pm salvar >/dev/null
assert_ok "salvar: arquivo vazio não apaga a cópia boa" "grep -q pc02 '$PM/var/macs.txt'"
SAIDA=$(pm restaurar)
assert_ok "restaurar: macs.txt vazio volta da cópia" "grep -q pc02 '$PM/lab/configs/macs.txt' && grep -q RESTAURADO <<< \"\$SAIDA\""
printf 'bb:00:00:00:00:09  outro\n' > "$PM/lab/configs/macs.txt"; pm restaurar >/dev/null
assert_ok "restaurar: macs.txt com MACs não é mexido" "grep -q outro '$PM/lab/configs/macs.txt' && ! grep -q pc02 '$PM/lab/configs/macs.txt'"
printf '# só comentário\n' > "$PM/lab/configs/macs.txt"; pm restaurar >/dev/null
assert_ok "restaurar: só comentários conta como vazio (guarda o antigo)" "grep -q pc02 '$PM/lab/configs/macs.txt' && [ -f '$PM/lab/configs/macs.txt.antes_de_restaurar' ]"
rm -rf "$PM/var" "$PM/home"; : > "$PM/lab/configs/macs.txt"
printf 'cc:00:00:00:00:07  tocha\n' > "$PM/legado/macs-lablivre.txt"
SAIDA=$(pm restaurar)
assert_ok "restaurar: sem cópias, usa a instalação antiga (scriptlab)" "grep -q tocha '$PM/lab/configs/macs.txt' && grep -q 'legado/macs-lablivre.txt' <<< \"\$SAIDA\""
for i in $(seq 1 13); do printf 'aa:00:00:00:00:%02d  pc%s\n' "$i" "$i" > "$PM/lab/configs/macs.txt"; pm salvar >/dev/null; sleep 0.01; touch -d "-$((20-i)) min" "$PM"/var/macs_*.txt 2>/dev/null; done
assert_ok "salvar: guarda no máximo 10 versões antigas" "[ \$(ls '$PM'/var/macs_*.txt | wc -l) -le 10 ]"
: > "$PM/lab/configs/macs.txt"; rm -rf "$PM/var" "$PM/home" "$PM/legado"
assert_ok "restaurar: sem nada, avisa e não falha" "pm restaurar | grep -q 'sem cópia'"

D="$PROJ_DIR/packaging/debian/DEBIAN"
assert_ok "pacote: preinst, postinst e postrm válidos" "bash -n '$D/preinst' && bash -n '$D/postinst' && bash -n '$D/postrm'"
assert_ok "pacote: build inclui o preinst" "grep -q 'for s in preinst postinst postrm' '$PROJ_DIR/packaging/build_deb.sh'"
assert_ok "pacote: postinst restaura antes de dar posse e salva depois" "grep -n '_preservar_macs.sh restaurar' '$D/postinst' | grep -q . && grep -q '_preservar_macs.sh salvar' '$D/postinst'"
assert_ok "pacote: postrm guarda o macs.txt antes do purge" "awk '/salvar_macs \\|\\| true/{a=NR} /rm -rf \\/opt\\/lablivre/{b=NR} END{exit !(a && b && a<b)}' '$D/postrm'"
assert_ok "pacote: postinst não dá touch num macs.txt existente" "! grep -qE '^touch .*macs.txt' '$D/postinst'"
assert_ok "gitinstall: git roda como o operador (não sudo git)" "! grep -qE 'sudo git ' '$PROJ_DIR/gitinstall.sh' && grep -q 'como_operador git' '$PROJ_DIR/gitinstall.sh'"
assert_ok "gitinstall: na raiz do repositório e restaura o macs.txt" "[ -f '$PROJ_DIR/gitinstall.sh' ] && [ -f '$PROJ_DIR/menu.sh' ] && grep -q '_preservar_macs.sh\" restaurar' '$PROJ_DIR/gitinstall.sh'"
assert_ok "git: macs.txt e lablivre.conf ficam fora do repositório" "grep -qx 'configs/macs.txt' '$PROJ_DIR/.gitignore' && grep -qx 'configs/lablivre.conf' '$PROJ_DIR/.gitignore'"

rm -rf "$T42"
cd "$PROJ_DIR"
