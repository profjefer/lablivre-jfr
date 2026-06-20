#!/bin/bash

# Garante que o script localize a raiz do projeto
cd "$(dirname "$0")/.." || exit 1

CONF_FILE="configs/lablivre.conf"
if [ -f "$CONF_FILE" ]; then
    source "$CONF_FILE"
else
    LAB_USUARIO="ufpr"
    LAB_SENHA="UFPR"
    LAB_PASTA_MATERIAL="envia_material"
fi

# Carrega helpers SEMPRE (fora do if) — senão ssh_remote_stdin fica indefinida
source modulos/_log.sh 2>/dev/null || true
source modulos/_ssh.sh 2>/dev/null || true

ARQUIVO_IPS="ips_atuais.txt"
RELATORIO="logs/relatorio_distribuicao.txt"
mkdir -p logs

# Pasta de origem padrão vem do conf, mas professor pode sobrescrever
PASTA_PADRAO="$(pwd)/${LAB_PASTA_MATERIAL:-envia_material}"

echo "========================================================"
echo "      DISTRIBUIÇÃO DE MATERIAL (TAR-PIPE STREAMING)     "
echo "========================================================"
echo ">> Pasta padrão de envio: $PASTA_PADRAO"
echo ">> (ENTER para usar a padrão, ou digite outro caminho)"
read -p "Caminho da pasta/arquivo: " PASTA_ORIGEM

# Se vazio usa a pasta padrão do conf
PASTA_ORIGEM="${PASTA_ORIGEM:-$PASTA_PADRAO}"

if [ ! -e "$PASTA_ORIGEM" ]; then
    echo "[ERRO] O caminho '$PASTA_ORIGEM' não foi encontrado."
    echo ">> Coloque os arquivos na pasta: $PASTA_PADRAO"
    exit 1
fi

PASTA_ORIGEM="${PASTA_ORIGEM%/}"
NOME_BASE=$(basename "$PASTA_ORIGEM")
DIR_PAI=$(dirname "$PASTA_ORIGEM")

echo "--------------------------------------------------------"
echo ">> Empacotando e enviando: $NOME_BASE"
echo ">> Usuário SSH: $LAB_USUARIO"
echo "--------------------------------------------------------"

# Descobre o destino REAL consultando a primeira máquina online (rápido, 1 SSH)
# Isso permite mostrar o caminho exato no fim, evitando confusão entre
# "Área de Trabalho" (T maiúsculo) e "Área de trabalho" (t minúsculo)
DESTINO_REAL=""
PRIMEIRO_IP=$(tail -n +3 "$ARQUIVO_IPS" | awk '$2 != "OFFLINE" && $4 != "(ESTA" {print $2; exit}')
if [ -n "$PRIMEIRO_IP" ]; then
    DESTINO_REAL=$(sshpass -p "$LAB_SENHA" ssh -q -o StrictHostKeyChecking=no \
        -o ConnectTimeout=3 "$LAB_USUARIO@$PRIMEIRO_IP" \
        'D=$(xdg-user-dir DESKTOP 2>/dev/null); [ -z "$D" ] || [ "$D" = "$HOME" ] && { for d in "Área de trabalho" "Área de Trabalho" "Desktop"; do [ -d "$HOME/$d" ] && D="$HOME/$d" && break; done; }; echo "$D"' 2>/dev/null)
fi
[ -z "$DESTINO_REAL" ] && DESTINO_REAL='$HOME/Área de trabalho'

echo "Relatório de Distribuição - $(date)" > "$RELATORIO"
echo "Origem: $PASTA_ORIGEM" >> "$RELATORIO"
echo "--------------------------------------------------------" >> "$RELATORIO"

while read -r mac ip nome resto; do
    # Ignora offline, linhas vazias e a própria máquina (via $resto)
    if [[ -z "$mac" ]] || [[ "$ip" == "OFFLINE" ]] || [[ "$resto" == *"(ESTA MÁQUINA)"* ]]; then
        continue
    fi

    echo -n "Enviando para: $nome ($ip)... "

    # Comando remoto: usa xdg-user-dir para obter o Desktop CORRETO
    # (funciona em PT "Área de Trabalho", PT "Área de trabalho", EN "Desktop", etc.)
    # Fallbacks: se xdg-user-dir não existir ou retornar vazio, tenta as variações conhecidas.
    CMD_REMOTO='DEST=$(xdg-user-dir DESKTOP 2>/dev/null); [ -z "$DEST" ] || [ "$DEST" = "$HOME" ] && { for d in "Área de trabalho" "Área de Trabalho" "Desktop" "Escritorio"; do [ -d "$HOME/$d" ] && DEST="$HOME/$d" && break; done; }; [ -z "$DEST" ] && DEST="$HOME"; mkdir -p "$DEST/Material_Aulas"; tar -xf - -C "$DEST/Material_Aulas"'

    # Executa o tar-pipe capturando saída de erro E o status do SSH juntos.
    # O 'echo __RC=$?' embute o código de retorno na própria saída, evitando
    # o problema de PIPESTATUS ser resetado pela atribuição $(...).
    SAIDA=$( { tar -cf - -C "$DIR_PAI" "$NOME_BASE" 2>/dev/null | \
        ssh_remote_stdin "$ip" "$CMD_REMOTO" 2>&1; echo "__RC=${PIPESTATUS[1]}"; } )
    STATUS_SSH=$(echo "$SAIDA" | grep -o '__RC=[0-9]*' | cut -d= -f2)
    ERRO_SSH=$(echo "$SAIDA" | grep -v '__RC=')

    if [ "${STATUS_SSH:-1}" -eq 0 ]; then
        echo "[OK]"
        echo "$nome ($ip): [OK]" >> "$RELATORIO"
    else
        echo "[ERRO] ${ERRO_SSH:0:60}"
        echo "$nome ($ip): [ERRO] $ERRO_SSH" >> "$RELATORIO"
    fi
done < <(tail -n +3 "$ARQUIVO_IPS")

echo "--------------------------------------------------------"
echo "[CONCLUÍDO] Material enviado para:"
echo "            $DESTINO_REAL/Material_Aulas/"
echo "            (em cada máquina do laboratório)"
echo "📄 Relatório salvo em: $RELATORIO"
log_acao "distribuir_material" "pasta=$NOME_BASE destino=$DESTINO_REAL" 2>/dev/null || true
