#!/bin/bash

# xcoletar_inventario.sh — Inventário gráfico com popup correto + HTML estilizado

cd "$(dirname "$0")/.." || exit 1

CONF_FILE="configs/lablivre.conf"
if [ -f "$CONF_FILE" ]; then source "$CONF_FILE"
else LAB_USUARIO="ufpr"; LAB_SENHA="UFPR"; LAB_NOME="LabLivre"
fi

ARQUIVO_IPS="ips_atuais.txt"
RELATORIO="logs/inventario_lab.txt"
HTML="web/inventario.html"
TMP_STATS="/tmp/lablivre_inv_stats.$$"
TMP_HTML_ROWS="/tmp/lablivre_inv_rows.$$"

mkdir -p logs web

if [ ! -f "$ARQUIVO_IPS" ]; then
    zenity --error --text="Arquivo de IPs não encontrado!\nExecute o mapeamento de rede primeiro." --width=300
    exit 1
fi

# Contagem real de alvos (online, incluindo local)
TOTAL_ALVO=0
while read -r mac ip nome resto; do
    [[ -z "$mac" ]] && continue
    [[ "$ip" == "OFFLINE" ]] && continue
    ((TOTAL_ALVO++))
done < <(tail -n +3 "$ARQUIVO_IPS")
[ "$TOTAL_ALVO" -eq 0 ] && TOTAL_ALVO=1

# Payload chave=valor
PAYLOAD=$(cat <<'PAYLOAD_EOF'
echo "SISTEMA=$(lsb_release -ds 2>/dev/null || grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '\"')"
echo "CPU=$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | sed 's/^[ \t]*//')"
echo "RAM=$(free -h | awk 'NR==2 {print $2}')"
echo "DISCO=$(df -h / | awk 'NR==2 {print $2}')"
echo "DISCO_USO=$(df -h / | awk 'NR==2 {print $5}')"
echo "GPU=$(lspci 2>/dev/null | grep -i vga | cut -d: -f3 | head -n1 | sed 's/^[ \t]*//')"
echo "BIOS=$(sudo -n dmidecode -s bios-version 2>/dev/null || echo 'N/D')"
echo "KERNEL=$(uname -r)"
echo "PACOTES=$(dpkg -l 2>/dev/null | grep -c '^ii')"
echo "UPTIME=$(uptime -p 2>/dev/null | sed 's/^up //')"
PAYLOAD_EOF
)

{
    echo "========================================================"
    echo "    RELATÓRIO DE INVENTÁRIO - LABLIVRE"
    echo "    Laboratório: $LAB_NOME"
    echo "    Data: $(date '+%d/%m/%Y %H:%M:%S')"
    echo "    Máquinas alvo: $TOTAL_ALVO"
    echo "========================================================"
} > "$RELATORIO"

: > "$TMP_STATS"
: > "$TMP_HTML_ROWS"

(
    ATUAL=0; SUCESSO=0; FALHA=0

    while read -r mac ip nome resto; do
        [[ -z "$mac" ]] && continue
        [[ "$ip" == "OFFLINE" ]] && continue

        ((ATUAL++))
        PERCENT=$(( ATUAL * 100 / TOTAL_ALVO ))
        echo "$PERCENT"
        echo "# [$ATUAL/$TOTAL_ALVO] Consultando: $nome ($ip)..."

        {
            echo ""
            echo "--------------------------------------------------------"
            echo "MÁQUINA: $nome ($ip | $mac)"
            echo "--------------------------------------------------------"
        } >> "$RELATORIO"

        if [[ "$resto" == *"(ESTA MÁQUINA)"* ]]; then
            SAIDA=$(eval "$PAYLOAD" 2>/dev/null)
            STATUS_COLETA=$?
        else
            SAIDA=$(echo "$PAYLOAD" | sshpass -p "$LAB_SENHA" ssh -q \
                -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
                "$LAB_USUARIO@$ip" "bash" 2>/dev/null)
            STATUS_COLETA=$?
        fi

        if [ $STATUS_COLETA -eq 0 ] && [ -n "$SAIDA" ]; then
            echo "$SAIDA" >> "$RELATORIO"
            ((SUCESSO++))

            SISTEMA=$(echo "$SAIDA" | grep '^SISTEMA=' | cut -d= -f2-)
            CPU=$(echo "$SAIDA" | grep '^CPU=' | cut -d= -f2-)
            RAM=$(echo "$SAIDA" | grep '^RAM=' | cut -d= -f2-)
            DISCO=$(echo "$SAIDA" | grep '^DISCO=' | cut -d= -f2-)
            DISCO_USO=$(echo "$SAIDA" | grep '^DISCO_USO=' | cut -d= -f2-)
            GPU=$(echo "$SAIDA" | grep '^GPU=' | cut -d= -f2-)
            BIOS=$(echo "$SAIDA" | grep '^BIOS=' | cut -d= -f2-)
            KERNEL=$(echo "$SAIDA" | grep '^KERNEL=' | cut -d= -f2-)
            PACOTES=$(echo "$SAIDA" | grep '^PACOTES=' | cut -d= -f2-)
            UPTIME=$(echo "$SAIDA" | grep '^UPTIME=' | cut -d= -f2-)

            cat >> "$TMP_HTML_ROWS" << ROW_EOF
<tr class="ok">
  <td class="nome">$nome</td>
  <td class="ip">$ip</td>
  <td>$SISTEMA</td>
  <td title="$CPU">$(echo "$CPU" | cut -c1-40)</td>
  <td>$RAM</td>
  <td>$DISCO <span class="dim">($DISCO_USO)</span></td>
  <td title="$GPU">$(echo "$GPU" | cut -c1-30)</td>
  <td>$BIOS</td>
  <td>$KERNEL</td>
  <td>$PACOTES</td>
  <td>$UPTIME</td>
</tr>
ROW_EOF
        else
            echo "A máquina não respondeu (timeout/erro SSH)." >> "$RELATORIO"
            ((FALHA++))
            cat >> "$TMP_HTML_ROWS" << ROW_EOF
<tr class="erro">
  <td class="nome">$nome</td>
  <td class="ip">$ip</td>
  <td colspan="9" class="err">⚠ Não respondeu (timeout/erro SSH)</td>
</tr>
ROW_EOF
        fi
    done < <(tail -n +3 "$ARQUIVO_IPS")

    echo "100"
    echo "# Finalizando..."

    # IMPORTANTE: escreve stats em arquivo (variáveis do subshell se perdem)
    {
        echo "SUCESSO=$SUCESSO"
        echo "FALHA=$FALHA"
        echo "TOTAL_ALVO=$TOTAL_ALVO"
    } > "$TMP_STATS"

) | zenity --progress \
    --title="Coleta de Inventário" \
    --text="Iniciando varredura de hardware..." \
    --percentage=0 \
    --auto-close --auto-kill --width=500

STATUS_PIPE=${PIPESTATUS[1]}
if [ "$STATUS_PIPE" -ne 0 ]; then
    rm -f "$TMP_STATS" "$TMP_HTML_ROWS"
    zenity --warning --text="Coleta cancelada pelo usuário." --width=300
    exit 1
fi

# Lê stats do arquivo (fora do subshell)
if [ -f "$TMP_STATS" ]; then
    source "$TMP_STATS"
else
    SUCESSO=0; FALHA=0
fi

# Gera HTML estilizado
DATA_FMT=$(date '+%d/%m/%Y %H:%M:%S')
VERSAO_LAB=$(cat VERSION 2>/dev/null || echo "?")

cat > "$HTML" << HTML_EOF
<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="UTF-8">
<title>Inventário · $LAB_NOME</title>
<style>
:root {
  --bg:#0d1117; --bg-card:#111820; --green:#00ff88; --cyan:#00d4ff;
  --amber:#ffb347; --red:#ff6b6b; --text:#c9d1d9; --dim:#6e7681;
}
*{box-sizing:border-box;margin:0;padding:0}
body{background:var(--bg);color:var(--text);font-family:'JetBrains Mono','Consolas',monospace;padding:32px;line-height:1.5}
header{border-bottom:2px solid var(--green);padding-bottom:20px;margin-bottom:28px}
h1{color:#fff;font-size:2rem;font-weight:700}
h1 span{color:var(--green)}
.meta{color:var(--dim);margin-top:6px;font-size:14px}
.summary{display:grid;grid-template-columns:repeat(4,1fr);gap:16px;margin-bottom:28px}
.stat{background:var(--bg-card);border:1px solid rgba(255,255,255,0.08);border-radius:10px;padding:18px}
.stat .label{color:var(--dim);font-size:12px;letter-spacing:1px;text-transform:uppercase}
.stat .val{font-size:2rem;font-weight:700;margin-top:6px}
.stat.ok .val{color:var(--green)}
.stat.err .val{color:var(--red)}
.stat.total .val{color:var(--cyan)}
.stat.lab .val{color:var(--amber);font-size:1.4rem}
table{width:100%;border-collapse:collapse;background:var(--bg-card);border-radius:10px;overflow:hidden;font-size:13px}
th{background:rgba(0,255,136,0.08);color:var(--green);padding:12px 10px;text-align:left;text-transform:uppercase;font-size:11px;letter-spacing:0.5px}
td{padding:10px;border-top:1px solid rgba(255,255,255,0.05)}
tr.ok td.nome{color:var(--green);font-weight:600}
tr.ok td.ip{color:var(--cyan)}
tr.erro td.nome{color:var(--red)}
tr.erro .err{color:var(--red);font-style:italic}
.dim{color:var(--dim)}
footer{margin-top:30px;padding-top:20px;border-top:1px solid rgba(255,255,255,0.08);color:var(--dim);font-size:12px;text-align:center}
footer a{color:var(--cyan);text-decoration:none}
@media (max-width:900px){.summary{grid-template-columns:repeat(2,1fr)}}
</style>
</head>
<body>
<header>
  <h1>📊 Inventário · <span>$LAB_NOME</span></h1>
  <div class="meta">Coleta realizada em $DATA_FMT</div>
</header>

<div class="summary">
  <div class="stat lab"><div class="label">Laboratório</div><div class="val">$LAB_NOME</div></div>
  <div class="stat total"><div class="label">Máquinas Alvo</div><div class="val">$TOTAL_ALVO</div></div>
  <div class="stat ok"><div class="label">Responderam</div><div class="val">$SUCESSO</div></div>
  <div class="stat err"><div class="label">Falharam</div><div class="val">$FALHA</div></div>
</div>

<table>
<thead>
<tr>
  <th>Nome</th><th>IP</th><th>Sistema</th><th>CPU</th><th>RAM</th>
  <th>Disco (uso)</th><th>GPU</th><th>BIOS</th><th>Kernel</th>
  <th>Pacotes</th><th>Uptime</th>
</tr>
</thead>
<tbody>
$(cat "$TMP_HTML_ROWS")
</tbody>
</table>

<footer>
  Gerado pelo LabLivre v$VERSAO_LAB · <a href="index.html">↩ Voltar ao portal</a>
</footer>
</body>
</html>
HTML_EOF

chmod 644 "$HTML" 2>/dev/null
rm -f "$TMP_STATS" "$TMP_HTML_ROWS"

# Resumo final
RESUMO_TEXTO="✅ <b>Inventário finalizado!</b>

🎯 <b>Total alvo:</b> $TOTAL_ALVO máquinas
🟢 <b>Responderam:</b> $SUCESSO
🔴 <b>Falharam:</b> $FALHA

📄 Relatório texto: <tt>$RELATORIO</tt>
🌐 Relatório web: <tt>$HTML</tt>

Como deseja visualizar?"

zenity --question \
    --title="Coleta Concluída" \
    --text="$RESUMO_TEXTO" \
    --width=480 \
    --ok-label="🌐 Abrir HTML" \
    --cancel-label="📄 Ver TXT"
ESCOLHA=$?

if [ $ESCOLHA -eq 0 ]; then
    URL="http://localhost:8080/inventario.html"
    if curl -s --connect-timeout 2 "$URL" >/dev/null 2>&1; then
        xdg-open "$URL" >/dev/null 2>&1 &
    else
        xdg-open "file://$(pwd)/$HTML" >/dev/null 2>&1 &
    fi
else
    zenity --text-info \
        --title="Relatório de Inventário (TXT)" \
        --filename="$RELATORIO" \
        --width=900 --height=600 \
        --font="Monospace 10"
fi
