#!/bin/bash

# inventario_para_html.sh — Converte logs/inventario_lab.txt em web/inventario.html
# Útil para o modo texto também ter HTML disponível na web.
# Chamado opcionalmente após coletar_inventario.sh.

cd "$(dirname "$0")/.." || exit 1

CONF_FILE="configs/lablivre.conf"
[ -f "$CONF_FILE" ] && source "$CONF_FILE"
LAB_NOME="${LAB_NOME:-LabLivre}"

TXT="logs/inventario_lab.txt"
HTML="web/inventario.html"
VERSAO_LAB=$(cat VERSION 2>/dev/null || echo "?")

if [ ! -f "$TXT" ]; then
    echo "[ERRO] $TXT não encontrado. Rode primeiro: bash modulos/coletar_inventario.sh"
    exit 1
fi

mkdir -p web

# Parser simples: separa por "MÁQUINA: nome (ip | mac)"
DATA_FMT=$(date '+%d/%m/%Y %H:%M:%S')

# Pula cabeçalho até a primeira "MÁQUINA:"
TOTAL=0; SUCESSO=0; FALHA=0
TMP_ROWS=$(mktemp)

# Estado de parser
NOME=""; IP=""; MAC=""; DADOS=""

flush_row() {
    [ -z "$NOME" ] && return
    ((TOTAL++))
    if [[ "$DADOS" == *"não respondeu"* ]] || [[ -z "$DADOS" ]]; then
        ((FALHA++))
        cat >> "$TMP_ROWS" <<ROW
<tr class="erro">
  <td class="nome">$NOME</td>
  <td class="ip">$IP</td>
  <td colspan="14" class="err">⚠ Não respondeu</td>
</tr>
ROW
    else
        ((SUCESSO++))
        campo() { echo "$DADOS" | grep -i "^$1:" | head -1 | cut -d: -f2- | sed 's/^ //'; }
        SISTEMA=$(campo SISTEMA); MODELO=$(campo MODELO); SERIE=$(campo SERIE)
        CPU=$(campo CPU); RAM=$(campo RAM); DISCO=$(campo DISCO); GPU=$(campo GPU)
        BIOS=$(campo BIOS); KERNEL=$(campo KERNEL); UPTIME=$(campo UPTIME)
        WOL=$(campo WOL); USB=$(campo USB); PYTHON=$(campo PYTHON); NODE=$(campo NODE)
        PACOTES=$(campo PACOTES | awk '{print $1}')
        CLASSE_WOL=""; [[ "$WOL" == DESATIVADO* ]] && CLASSE_WOL=' class="err"'
        cat >> "$TMP_ROWS" <<ROW
<tr class="ok">
  <td class="nome">$NOME</td>
  <td class="ip">$IP</td>
  <td>${SERIE:--}</td>
  <td>$(echo "${MODELO:--}" | cut -c1-30)</td>
  <td>$SISTEMA</td>
  <td>$(echo "$CPU" | cut -c1-45)</td>
  <td>$RAM</td>
  <td>$DISCO</td>
  <td>$(echo "$GPU" | cut -c1-30)</td>
  <td>$BIOS</td>
  <td>${KERNEL:--}</td>
  <td${CLASSE_WOL}>${WOL:--}</td>
  <td title="$USB">$(echo "${USB:--}" | cut -d: -f1)</td>
  <td>py ${PYTHON:--} · node ${NODE:--}</td>
  <td>$PACOTES</td>
  <td>${UPTIME:--}</td>
</tr>
ROW
    fi
}

while IFS= read -r linha; do
    if [[ "$linha" =~ ^MÁQUINA:\ (.+)\ \((.+)\ \|\ (.+)\)$ ]]; then
        flush_row
        NOME="${BASH_REMATCH[1]}"
        IP="${BASH_REMATCH[2]}"
        MAC="${BASH_REMATCH[3]}"
        DADOS=""
    elif [[ -n "$NOME" ]]; then
        DADOS+="$linha"$'\n'
    fi
done < "$TXT"
flush_row

cat > "$HTML" << HTML_EOF
<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="UTF-8">
<title>Inventário · $LAB_NOME</title>
<style>
:root{--bg:#0d1117;--bg-card:#111820;--green:#00ff88;--cyan:#00d4ff;--amber:#ffb347;--red:#ff6b6b;--text:#c9d1d9;--dim:#6e7681}
*{box-sizing:border-box;margin:0;padding:0}
body{background:var(--bg);color:var(--text);font-family:'JetBrains Mono','Consolas',monospace;padding:32px;line-height:1.5}
header{border-bottom:2px solid var(--green);padding-bottom:20px;margin-bottom:28px}
h1{color:#fff;font-size:2rem}h1 span{color:var(--green)}
.meta{color:var(--dim);margin-top:6px;font-size:14px}
.summary{display:grid;grid-template-columns:repeat(4,1fr);gap:16px;margin-bottom:28px}
.stat{background:var(--bg-card);border:1px solid rgba(255,255,255,0.08);border-radius:10px;padding:18px}
.stat .label{color:var(--dim);font-size:12px;letter-spacing:1px;text-transform:uppercase}
.stat .val{font-size:2rem;font-weight:700;margin-top:6px}
.stat.ok .val{color:var(--green)}.stat.err .val{color:var(--red)}.stat.total .val{color:var(--cyan)}
.stat.lab .val{color:var(--amber);font-size:1.4rem}
table{width:100%;border-collapse:collapse;background:var(--bg-card);border-radius:10px;overflow:hidden;font-size:13px}
th{background:rgba(0,255,136,0.08);color:var(--green);padding:12px 10px;text-align:left;text-transform:uppercase;font-size:11px}
td{padding:10px;border-top:1px solid rgba(255,255,255,0.05)}
tr.ok td.nome{color:var(--green);font-weight:600}
tr.ok td.ip{color:var(--cyan)}
tr.erro td.nome{color:var(--red)}
tr.erro .err{color:var(--red);font-style:italic}
footer{margin-top:30px;padding-top:20px;border-top:1px solid rgba(255,255,255,0.08);color:var(--dim);font-size:12px;text-align:center}
footer a{color:var(--cyan);text-decoration:none}
</style>
</head>
<body>
<header>
  <h1>📊 Inventário · <span>$LAB_NOME</span></h1>
  <div class="meta">Convertido em $DATA_FMT</div>
</header>
<div class="summary">
  <div class="stat lab"><div class="label">Laboratório</div><div class="val">$LAB_NOME</div></div>
  <div class="stat total"><div class="label">Total</div><div class="val">$TOTAL</div></div>
  <div class="stat ok"><div class="label">Responderam</div><div class="val">$SUCESSO</div></div>
  <div class="stat err"><div class="label">Falharam</div><div class="val">$FALHA</div></div>
</div>
<table>
<thead><tr>
<th>Nome</th><th>IP</th><th>Série</th><th>Modelo</th><th>Sistema</th><th>CPU</th><th>RAM</th>
<th>Disco</th><th>GPU</th><th>BIOS</th><th>Kernel</th><th>Wake-on-LAN</th><th>USB</th><th>Python/Node</th><th>Pacotes</th><th>Uptime</th>
</tr></thead>
<tbody>
$(cat "$TMP_ROWS")
</tbody>
</table>
<footer>Gerado pelo LabLivre v$VERSAO_LAB · <a href="index.html">↩ Voltar ao portal</a></footer>
</body>
</html>
HTML_EOF

chmod 644 "$HTML"
rm -f "$TMP_ROWS"
echo "[OK] HTML gerado: $HTML"
echo "     Acesse: http://localhost:8080/inventario.html"
