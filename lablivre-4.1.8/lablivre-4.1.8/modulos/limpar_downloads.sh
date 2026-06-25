#!/bin/bash

# limpar_downloads.sh — Limpa a pasta Downloads e a Lixeira de todas as
# máquinas online do laboratório (do usuário SSH configurado).
# AÇÃO DESTRUTIVA: apaga arquivos permanentemente.

cd "$(dirname "$0")/.." || exit 1

CONF_FILE="configs/lablivre.conf"
if [ -f "$CONF_FILE" ]; then
    source "$CONF_FILE"
else
    LAB_USUARIO="ufpr"
    LAB_SENHA="UFPR"
fi

# Carrega helpers SEMPRE (fora do if)
source modulos/_log.sh 2>/dev/null || true
source modulos/_ssh.sh 2>/dev/null || true

ARQUIVO_IPS="ips_atuais.txt"
RELATORIO="logs/relatorio_limpeza.txt"
mkdir -p logs

if [ ! -f "$ARQUIVO_IPS" ]; then
    echo "[ERRO] $ARQUIVO_IPS não encontrado. Rode o mapeamento de rede (opção 1) primeiro."
    exit 1
fi

echo "========================================================"
echo "       🧹 LIMPEZA DE DOWNLOADS E LIXEIRA                "
echo "========================================================"
echo ">> Usuário alvo: $LAB_USUARIO"
echo ">> Será limpo em cada máquina online:"
echo "   • A pasta Downloads (~/Downloads ou equivalente)"
echo "   • A Lixeira (~/.local/share/Trash)"
echo "--------------------------------------------------------"

# Conta máquinas alvo
TOTAL_ALVO=$(tail -n +3 "$ARQUIVO_IPS" | awk '$2 != "OFFLINE" && $4 != "(ESTA" {c++} END {print c+0}')
echo "⚠️  ATENÇÃO: esta ação é DESTRUTIVA e irreversível."
echo "    $TOTAL_ALVO máquinas online serão limpas."
echo ""
read -p "Digite SIM (maiúsculas) para confirmar: " CONFIRMA

if [ "$CONFIRMA" != "SIM" ]; then
    echo "Operação cancelada. Nada foi apagado."
    exit 0
fi

echo ""
echo "--------------------------------------------------------"
echo ">> Iniciando limpeza..."
echo "--------------------------------------------------------"

# Cabeçalho do relatório
{
    echo "Relatório de Limpeza - $(date '+%d/%m/%Y %H:%M:%S')"
    echo "Usuário: $LAB_USUARIO"
    echo "--------------------------------------------------------"
} > "$RELATORIO"

# Comando remoto: descobre Downloads com xdg-user-dir (lida com idioma/variações),
# conta o que será apagado, esvazia a pasta e a Lixeira.
CMD_REMOTO='
DL=$(xdg-user-dir DOWNLOAD 2>/dev/null)
[ -z "$DL" ] || [ "$DL" = "$HOME" ] && { for d in "Downloads" "Transferências" "Descargas"; do [ -d "$HOME/$d" ] && DL="$HOME/$d" && break; done; }
[ -z "$DL" ] && DL="$HOME/Downloads"

N_DL=0
if [ -d "$DL" ]; then
    N_DL=$(find "$DL" -mindepth 1 2>/dev/null | wc -l)
    rm -rf "$DL"/* "$DL"/.[!.]* 2>/dev/null
fi

# Lixeira (padrão XDG)
N_TRASH=0
TRASH="$HOME/.local/share/Trash"
if [ -d "$TRASH" ]; then
    N_TRASH=$(find "$TRASH/files" -mindepth 1 2>/dev/null | wc -l)
    rm -rf "$TRASH/files"/* "$TRASH/files"/.[!.]* 2>/dev/null
    rm -rf "$TRASH/info"/* 2>/dev/null
fi

echo "DOWNLOADS_DIR=$DL"
echo "ITENS_DOWNLOADS=$N_DL"
echo "ITENS_LIXEIRA=$N_TRASH"
'

SUCESSO=0
FALHA=0
TOTAL_ITENS=0

while read -r mac ip nome resto; do
    [[ -z "$mac" ]] && continue
    [[ "$ip" == "OFFLINE" ]] && continue
    [[ "$resto" == *"(ESTA MÁQUINA)"* ]] && continue

    echo -n "Limpando: $nome ($ip)... "

    # Executa e captura saída + status (padrão __RC para evitar reset de PIPESTATUS)
    SAIDA=$( { echo "$CMD_REMOTO" | ssh_remote_stdin "$ip" "bash" 2>&1; echo "__RC=$?"; } )
    STATUS=$(echo "$SAIDA" | grep -o '__RC=[0-9]*' | cut -d= -f2)

    if [ "${STATUS:-1}" -eq 0 ]; then
        N_DL=$(echo "$SAIDA" | grep '^ITENS_DOWNLOADS=' | cut -d= -f2)
        N_TR=$(echo "$SAIDA" | grep '^ITENS_LIXEIRA=' | cut -d= -f2)
        N_DL=${N_DL:-0}; N_TR=${N_TR:-0}
        TOTAL_ITENS=$((TOTAL_ITENS + N_DL + N_TR))
        echo "[OK] (Downloads: $N_DL, Lixeira: $N_TR)"
        echo "$nome ($ip): [OK] Downloads=$N_DL Lixeira=$N_TR" >> "$RELATORIO"
        ((SUCESSO++))
    else
        ERRO=$(echo "$SAIDA" | grep -v '__RC=' | head -1)
        echo "[ERRO] ${ERRO:0:50}"
        echo "$nome ($ip): [ERRO] $ERRO" >> "$RELATORIO"
        ((FALHA++))
    fi
done < <(tail -n +3 "$ARQUIVO_IPS")

echo "--------------------------------------------------------"
echo "[CONCLUÍDO] Limpeza finalizada."
echo "   🟢 $SUCESSO máquinas limpas"
echo "   🔴 $FALHA falharam"
echo "   🗑️  $TOTAL_ITENS itens apagados no total"
echo "📄 Relatório salvo em: $RELATORIO"
log_acao "limpar_downloads" "maquinas=$SUCESSO itens=$TOTAL_ITENS" 2>/dev/null || true
