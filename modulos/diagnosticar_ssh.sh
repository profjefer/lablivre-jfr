#!/bin/bash
# ================================================================
# diagnosticar_ssh.sh — Testa cada máquina em camadas e diz O QUE
# fazer quando falha.
#
#   rede (ARP) → ping → porta 22 → login SSH → sudo → nome confere
#
#   bash modulos/diagnosticar_ssh.sh              → pergunta se remapeia
#   bash modulos/diagnosticar_ssh.sh --remapear   → mapeia antes (recomendado)
#   bash modulos/diagnosticar_ssh.sh thor hulk    → só as citadas
#
# Desde 4.2.2: ping bloqueado NÃO é mais "sem conexão" (muitas
# máquinas respondem ao ARP e ao SSH mas não ao ping); falha de login
# diz se a máquina RECUSA senha (PasswordAuthentication no) ou se a
# senha está errada; confere o sudo e se o nome da máquina bate.
# ================================================================

cd "$(dirname "$0")/.." || exit 1

source modulos/_comum.sh && carregar_conf || exit 1

REMAPEAR=""; ALVOS=()
for a in "$@"; do
    case "$a" in
        --remapear)     REMAPEAR=1 ;;
        --sem-remapear) REMAPEAR=0 ;;
        *)              ALVOS+=("$a") ;;
    esac
done

RELATORIO="logs/diagnostico_ssh.txt"
mkdir -p logs

echo "========================================================"
echo "         🔍 DIAGNÓSTICO DE CONEXÃO SSH                  "
echo "========================================================"

if [ -z "$REMAPEAR" ]; then
    REMAPEAR=0
    if [ -f "$ARQUIVO_IPS" ] && [ $(( $(date +%s) - $(stat -c %Y "$ARQUIVO_IPS") )) -gt 600 ] && [ -t 0 ]; then
        read -r -p "O mapa da rede tem mais de 10 min. Remapear antes? (S/n): " R
        [[ "${R,,}" == "n" ]] || REMAPEAR=1
    fi
    [ -f "$ARQUIVO_IPS" ] || REMAPEAR=1
fi
if [ "$REMAPEAR" = 1 ]; then
    echo ">> Mapeando a rede (opção 1)..."
    bash modulos/atualizar_ips.sh < /dev/null > logs/diagnostico_mapeamento.log 2>&1
    echo "   $(grep -m1 "^\[CONCLU" logs/diagnostico_mapeamento.log)"
fi
exigir_ips || exit 1

echo "Usuário: $LAB_USUARIO · autenticação: ${LAB_AUTH_MODE:-senha}"
echo "--------------------------------------------------------"
{
    echo "Diagnóstico SSH - $(date '+%d/%m/%Y %H:%M:%S')"
    echo "Usuário: $LAB_USUARIO · modo: ${LAB_AUTH_MODE:-senha}"
    echo "----"
} > "$RELATORIO"

OK=0; OFF=0; PORTA=0; LOGIN=0; SUDO=0; HOSTS_DIF=(); SEM_WOL=()
DICAS=()

porta_aberta() { timeout 3 bash -c "exec 3<>/dev/tcp/$1/22" 2>/dev/null; }

# Quais métodos de login o servidor SSH aceita? (sem tentar senha)
metodos_ssh() {
    ssh -o BatchMode=yes -o PreferredAuthentications=none -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o LogLevel=ERROR \
        "$LAB_USUARIO@$1" true </dev/null 2>&1 | grep -o 'Permission denied ([^)]*)' | sed 's/.*(\(.*\))/\1/'
}

registrar() { echo "$1" >> "$RELATORIO"; }

testar() {
    local mac="$1" ip="$2" nome="$3" ping_ok saida rc status host sessao metodos erro
    if [ "${#ALVOS[@]}" -gt 0 ] && [[ " ${ALVOS[*]} " != *" $nome "* ]]; then return; fi
    printf "%-20s " "$nome"

    if [ "$ip" = OFFLINE ]; then
        echo "💀 não respondeu na rede (desligada, cabo, ou em outra rede/Wi-Fi)"
        registrar "[OFFLINE]   $nome"
        ((OFF++)); return
    fi
    ping -c 1 -W 2 "$ip" >/dev/null 2>&1 && ping_ok="" || ping_ok=" (ping bloqueado)"

    if ! porta_aberta "$ip"; then
        echo "🔒 $ip: porta 22 fechada$ping_ok"
        registrar "[PORTA 22]  $nome ($ip) — sshd parado ou firewall"
        DICAS+=("$nome: na máquina, 'sudo systemctl enable --now ssh' e 'sudo ufw allow 22/tcp'")
        ((PORTA++)); return
    fi

    saida=$(rodar_remoto "$ip" modulos/remoto/checar.sh)
    rc=$?
    status=$(status_remoto "$saida")
    host=$(sed -n 's/^__HOST=//p' <<< "$saida" | tail -n1)
    sessao=$(sed -n 's/^__SESSAO=//p' <<< "$saida" | tail -n1)
    local wol wolp
    wol=$(sed -n 's/^__WOL=//p' <<< "$saida" | tail -n1)
    wolp=$(grep -q '^__WOL_PERMANENTE=sim' <<< "$saida" && echo 1)

    if [ -z "$status" ]; then
        metodos=$(metodos_ssh "$ip")
        if [ "${LAB_AUTH_MODE:-senha}" = senha ] && [ -n "$metodos" ] && [[ ",$metodos," != *",password,"* ]] && [[ ",$metodos," != *",keyboard-interactive,"* ]]; then
            erro="o servidor SSH NÃO aceita senha (aceita: $metodos)"
            DICAS+=("$nome: na máquina, em /etc/ssh/sshd_config(.d/*) deixe 'PasswordAuthentication yes' e rode 'sudo systemctl restart ssh' — confira com 'sudo sshd -T | grep -i passwordauth'")
        elif [ "$rc" = 5 ]; then
            erro="senha recusada para '$LAB_USUARIO'"
            DICAS+=("$nome: confira se o usuário '$LAB_USUARIO' existe nela e a senha é a do lablivre.conf ('sudo passwd $LAB_USUARIO')")
        elif [ -z "$metodos" ]; then
            erro="a conexão cai antes do login${ping_ok}"
            DICAS+=("$nome: o sshd derruba ESTA máquina — veja 'sudo journalctl -u ssh -n 30' nela; causas comuns: fail2ban bloqueou o IP $(hostname -I | awk '{print $1}') ('sudo fail2ban-client status sshd'), AllowUsers/DenyUsers no sshd_config, /etc/hosts.deny")
        else
            erro="login falhou ($(erro_ssh "$rc"); aceita: $metodos)"
        fi
        echo "🔑 $ip: $erro"
        registrar "[LOGIN]     $nome ($ip) — $erro"
        ((LOGIN++)); return
    fi

    if [ "$status" = ERRO_SUDO ]; then
        echo "⚠️  $ip: entra, mas o sudo recusa a senha"
        registrar "[SUDO]      $nome ($ip) — '$LAB_USUARIO' sem sudo ou senha diferente"
        DICAS+=("$nome: 'sudo usermod -aG sudo $LAB_USUARIO' nela (mensagem, material, prova e desligar precisam de sudo)")
        ((SUDO++)); return
    fi

    # Funcionou. Hostname diferente do macs.txt é só informativo (comum em
    # laboratório com imagem clonada: todas com o mesmo hostname).
    local info=""
    if [ -n "$host" ] && [ "${host,,}" != "${nome,,}" ]; then
        info=" · ℹ️  hostname '$host'"
        HOSTS_DIF+=("$host")
    fi
    local wtxt=""
    if [ "$wol" = sem-ethtool ]; then wtxt=" · ⚠️  WoL ? (sem ethtool)"; SEM_WOL+=("$nome")
    elif [[ "$wol" == *:g/* ]]; then wtxt=" · WoL ok${wolp:+ (permanente)}"; [ -z "$wolp" ] && SEM_WOL+=("$nome")
    elif [ -n "$wol" ]; then wtxt=" · ⚠️  WoL desarmado ($wol)"; SEM_WOL+=("$nome"); fi
    echo "✅ $ip ok${ping_ok}${sessao:+ · aluno logado: $sessao}$info$wtxt"
    registrar "[OK]        $nome ($ip)${ping_ok}${sessao:+ · sessão: $sessao}${info:+ · hostname: $host}"
    ((OK++))
}

para_cada_maquina testar --todas

echo "--------------------------------------------------------"
RESUMO="✅ $OK ok · 💀 $OFF fora da rede · 🔒 $PORTA porta 22 · 🔑 $LOGIN login · ⚠️ $SUDO sudo"
echo "Resumo: $RESUMO"
if [ "${#HOSTS_DIF[@]}" -gt 0 ]; then
    REPETIDOS=$(printf '%s\n' "${HOSTS_DIF[@]}" | sort | uniq -c | sort -rn | awk '$1>1 {printf "%s%s (%d máquinas)", sep, $2, $1; sep=", "}')
    echo "ℹ️  ${#HOSTS_DIF[@]} máquina(s) funcionando com hostname diferente do nome no macs.txt (não é erro)."
    [ -n "$REPETIDOS" ] && echo "   Hostname repetido: $REPETIDOS — típico de imagem clonada; o LabLivre usa o MAC, não o hostname."
fi
if [ "${#SEM_WOL[@]}" -gt 0 ]; then
    echo "⚡ Wake-on-LAN não garantido em: ${SEM_WOL[*]}"
    echo "   → menu 18 (Preparar Wake-on-LAN) instala o ethtool e deixa o WoL permanente."
fi
if [ "${#DICAS[@]}" -gt 0 ]; then
    echo ""
    echo "O que fazer:"
    printf '  • %s\n' "${DICAS[@]}"
fi
echo ""
echo "Relatório: $RELATORIO"
{
    echo "----"
    echo "RESUMO: $RESUMO"
    [ "${#DICAS[@]}" -gt 0 ] && printf '  • %s\n' "${DICAS[@]}"
} >> "$RELATORIO"
