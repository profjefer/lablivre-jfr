#!/bin/bash

# run_tests.sh — Executa toda a suíte de testes do LabLivre
# Uso: bash tests/run_tests.sh

cd "$(dirname "$0")/.." || exit 1
PROJ_DIR="$(pwd)"

PASSED=0
FAILED=0
FALHAS=()

assert_ok() {
    local desc="$1"
    local cmd="$2"
    if eval "$cmd" >/dev/null 2>&1; then
        echo "  ✓ $desc"
        ((PASSED++))
    else
        echo "  ✗ $desc"
        FALHAS+=("$desc")
        ((FAILED++))
    fi
}

assert_eq() {
    local desc="$1"
    local esperado="$2"
    local obtido="$3"
    if [ "$esperado" = "$obtido" ]; then
        echo "  ✓ $desc"
        ((PASSED++))
    else
        echo "  ✗ $desc — esperado '$esperado', obtido '$obtido'"
        FALHAS+=("$desc")
        ((FAILED++))
    fi
}

echo "========================================================"
echo "        EXECUTANDO SUÍTE DE TESTES LABLIVRE             "
echo "========================================================"

# === Testes de sintaxe ===
echo ""
echo "[1] Sintaxe de todos os scripts shell"
for f in *.sh modulos/*.sh xmodulos/*.sh; do
    [ -f "$f" ] && assert_ok "$f" "bash -n '$f'"
done

# === Testes do gerar_estado.sh ===
echo ""
echo "[2] Geração de api.json"

TMPDIR=$(mktemp -d)
mkdir -p "$TMPDIR/configs" "$TMPDIR/logs" "$TMPDIR/web" "$TMPDIR/modulos"
cp modulos/gerar_estado.sh "$TMPDIR/modulos/"

cat > "$TMPDIR/configs/lablivre.conf" << EOF
LAB_NOME="Lab Teste"
LAB_USUARIO="teste"
LAB_SENHA="x"
EOF

cat > "$TMPDIR/ips_atuais.txt" << EOF
MAC_ADDRESS        IP_ADDRESS       NOME_MAQUINA
------------------------------------------------
aa:bb:cc:dd:ee:01  192.168.1.10     pc-prof (ESTA MÁQUINA)
aa:bb:cc:dd:ee:02  192.168.1.11     pc01
aa:bb:cc:dd:ee:03  OFFLINE          pc02
EOF

(cd "$TMPDIR" && bash modulos/gerar_estado.sh >/dev/null 2>&1)

assert_ok "api.json foi gerado" "[ -f '$TMPDIR/web/api.json' ]"
assert_ok "api.json é JSON válido" "python3 -c 'import json; json.load(open(\"$TMPDIR/web/api.json\"))'"

# Conteúdo correto
if [ -f "$TMPDIR/web/api.json" ]; then
    TOTAL=$(python3 -c "import json; print(json.load(open('$TMPDIR/web/api.json'))['rede']['total'])")
    ONLINE=$(python3 -c "import json; print(json.load(open('$TMPDIR/web/api.json'))['rede']['online'])")
    OFFLINE=$(python3 -c "import json; print(json.load(open('$TMPDIR/web/api.json'))['rede']['offline'])")
    NOME=$(python3 -c "import json; print(json.load(open('$TMPDIR/web/api.json'))['lab']['nome'])")

    assert_eq "Total de máquinas" "3" "$TOTAL"
    assert_eq "Máquinas online" "2" "$ONLINE"
    assert_eq "Máquinas offline" "1" "$OFFLINE"
    assert_eq "Nome do lab" "Lab Teste" "$NOME"
fi

rm -rf "$TMPDIR"

# === Testes do _log.sh ===
echo ""
echo "[3] Sistema de auditoria"

TMPDIR=$(mktemp -d)
mkdir -p "$TMPDIR/logs" "$TMPDIR/modulos"
cp modulos/_log.sh "$TMPDIR/modulos/"
(
    cd "$TMPDIR"
    source modulos/_log.sh
    log_acao "teste_acao" "key1=val1 key2=val2"
)

assert_ok "auditoria.jsonl foi criado" "[ -f '$TMPDIR/logs/auditoria.jsonl' ]"
assert_ok "linha é JSON válido" "python3 -c 'import json; [json.loads(l) for l in open(\"$TMPDIR/logs/auditoria.jsonl\")]'"

if [ -f "$TMPDIR/logs/auditoria.jsonl" ]; then
    ACAO=$(python3 -c "import json; print(json.loads(open('$TMPDIR/logs/auditoria.jsonl').read())['acao'])")
    assert_eq "Ação registrada corretamente" "teste_acao" "$ACAO"
fi

rm -rf "$TMPDIR"

# === Testes do snapshot_diario ===
echo ""
echo "[4] Snapshot diário"

TMPDIR=$(mktemp -d)
mkdir -p "$TMPDIR/logs" "$TMPDIR/modulos"
cp modulos/snapshot_diario.sh "$TMPDIR/modulos/"
cat > "$TMPDIR/ips_atuais.txt" << EOF
MAC_ADDRESS        IP_ADDRESS       NOME_MAQUINA
------------------------------------------------
aa:bb:cc:dd:ee:01  192.168.1.10     pc01
aa:bb:cc:dd:ee:02  OFFLINE          pc02
EOF

(cd "$TMPDIR" && bash modulos/snapshot_diario.sh >/dev/null 2>&1)
assert_ok "historico.jsonl foi criado" "[ -f '$TMPDIR/logs/historico.jsonl' ]"
assert_ok "snapshot é JSON válido" "python3 -c 'import json; json.loads(open(\"$TMPDIR/logs/historico.jsonl\").read())'"

rm -rf "$TMPDIR"


# === Testes do _ssh.sh (modo chave vs senha) ===
echo ""
echo "[X] Wrapper SSH (_ssh.sh)"

TMPDIR=$(mktemp -d)
mkdir -p "$TMPDIR/configs" "$TMPDIR/modulos"
cp modulos/_ssh.sh "$TMPDIR/modulos/"

# Modo senha (sem chave existente)
cat > "$TMPDIR/configs/lablivre.conf" << EOF
LAB_USUARIO="teste"
LAB_SENHA="x"
EOF

MODO=$(cd "$TMPDIR" && source modulos/_ssh.sh && echo "$LAB_AUTH_MODE")
assert_eq "Modo auto detectado quando sem chave" "senha" "$MODO"

# Modo chave (chave existe)
touch "$TMPDIR/configs/lablivre_key"
MODO=$(cd "$TMPDIR" && source modulos/_ssh.sh && echo "$LAB_AUTH_MODE")
assert_eq "Modo auto detectado quando chave existe" "chave" "$MODO"

# Modo explícito sobrescreve auto-detecção
cat > "$TMPDIR/configs/lablivre.conf" << EOF
LAB_USUARIO="teste"
LAB_SENHA="x"
LAB_AUTH_MODE="senha"
EOF
MODO=$(cd "$TMPDIR" && source modulos/_ssh.sh && echo "$LAB_AUTH_MODE")
assert_eq "Modo explícito 'senha' respeitado" "senha" "$MODO"

# Funções disponíveis
assert_ok "ssh_remote definida" "cd '$TMPDIR' && source modulos/_ssh.sh && declare -F ssh_remote"
assert_ok "ssh_remote_stdin definida" "cd '$TMPDIR' && source modulos/_ssh.sh && declare -F ssh_remote_stdin"
assert_ok "scp_remote definida" "cd '$TMPDIR' && source modulos/_ssh.sh && declare -F scp_remote"

rm -rf "$TMPDIR"

# === Testes do _dryrun.sh ===
echo ""
echo "[X2] Modo dry-run"

cd "$PROJ_DIR"

TMPDIR=$(mktemp -d)
mkdir -p "$TMPDIR/configs" "$TMPDIR/modulos"
cp "$PROJ_DIR/modulos/_ssh.sh" "$PROJ_DIR/modulos/_dryrun.sh" "$TMPDIR/modulos/"
cat > "$TMPDIR/configs/lablivre.conf" << EOF
LAB_USUARIO="teste"
LAB_SENHA="x"
EOF

# Em dry-run, ssh_remote deve apenas exibir, sem executar
cd "$TMPDIR"
SAIDA=$(DRYRUN=1 bash -c "source modulos/_ssh.sh && source modulos/_dryrun.sh && ssh_remote 1.2.3.4 'echo ola'" 2>&1)
cd - >/dev/null
if echo "$SAIDA" | grep -q "DRY-RUN"; then
    echo "  ✓ ssh_remote respeita DRYRUN=1"
    ((PASSED++))
else
    echo "  ✗ ssh_remote não respeita DRYRUN=1 (saída: $SAIDA)"
    FALHAS+=("dryrun ssh_remote")
    ((FAILED++))
fi

rm -rf "$TMPDIR"

# === Resumo ===
echo ""
echo "========================================================"
echo "  RESULTADO: $PASSED passou, $FAILED falhou"
echo "========================================================"

if [ $FAILED -gt 0 ]; then
    echo ""
    echo "Falhas:"
    for f in "${FALHAS[@]}"; do
        echo "  - $f"
    done
    exit 1
fi
