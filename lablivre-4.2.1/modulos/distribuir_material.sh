#!/bin/bash
# ================================================================
# distribuir_material.sh — Copia uma pasta/arquivo para a Área de
# Trabalho dos alunos, em <Área de Trabalho>/Material_Aulas/
#
# Tar-pipe: empacota uma vez e transmite direto pelo SSH, sem
# arquivo temporário. O lado remoto (modulos/remoto/receber_material.sh)
# acha a pasta certa do Desktop em qualquer idioma.
# ================================================================

cd "$(dirname "$0")/.." || exit 1

source modulos/_comum.sh && carregar_conf && exigir_ips || exit 1
source modulos/_log.sh 2>/dev/null || true
source modulos/_dryrun.sh "$@" 2>/dev/null || true

SCRIPT_REMOTO="modulos/remoto/receber_material.sh"
SUBPASTA="Material_Aulas"
RELATORIO="logs/relatorio_distribuicao.txt"
mkdir -p logs

PASTA_PADRAO="$LAB_RAIZ/$LAB_PASTA_MATERIAL"
mkdir -p "$PASTA_PADRAO"

echo "========================================================"
echo "      📚 DISTRIBUIÇÃO DE MATERIAL (TAR-PIPE)            "
echo "========================================================"
echo ">> Pasta padrão: $PASTA_PADRAO"
echo ">> ENTER = enviar a pasta padrão inteira"
echo ">> Ou digite/arraste outro caminho (TAB completa)"
read -r -e -p "Caminho: " PASTA_ORIGEM

# Limpa o que o terminal coloca ao arrastar um arquivo: aspas e espaço final
PASTA_ORIGEM="${PASTA_ORIGEM%"${PASTA_ORIGEM##*[![:space:]]}"}"
PASTA_ORIGEM="${PASTA_ORIGEM#\'}"; PASTA_ORIGEM="${PASTA_ORIGEM%\'}"
PASTA_ORIGEM="${PASTA_ORIGEM#\"}"; PASTA_ORIGEM="${PASTA_ORIGEM%\"}"
PASTA_ORIGEM="${PASTA_ORIGEM/#\~/$HOME}"
PASTA_ORIGEM="${PASTA_ORIGEM:-$PASTA_PADRAO}"

if [ ! -e "$PASTA_ORIGEM" ]; then
    echo "[ERRO] '$PASTA_ORIGEM' não foi encontrado."
    echo ">> Coloque os arquivos em: $PASTA_PADRAO"
    exit 1
fi

PASTA_ORIGEM=$(realpath "$PASTA_ORIGEM")
NOME_BASE=$(basename "$PASTA_ORIGEM")
# Pasta padrão: envia o CONTEÚDO (Material_Aulas/arquivo.pdf).
# Outra pasta/arquivo: envia com o nome (Material_Aulas/aula-03/...).
if [ "$PASTA_ORIGEM" = "$(realpath "$PASTA_PADRAO")" ]; then
    TAR_DIR="$PASTA_ORIGEM"; TAR_ITEM="."; DESTINO_VISTO="$SUBPASTA/"
else
    TAR_DIR=$(dirname "$PASTA_ORIGEM"); TAR_ITEM="$NOME_BASE"; DESTINO_VISTO="$SUBPASTA/$NOME_BASE"
fi

if [ -d "$PASTA_ORIGEM" ] && [ -z "$(find "$PASTA_ORIGEM" -mindepth 1 ! -name .gitkeep -print -quit)" ]; then
    echo "[ERRO] A pasta '$PASTA_ORIGEM' está vazia."
    exit 1
fi

TAMANHO=$(du -sh "$PASTA_ORIGEM" 2>/dev/null | cut -f1)
N_ARQ=$(find "$PASTA_ORIGEM" -type f ! -name .gitkeep 2>/dev/null | wc -l)
N_ALVOS=$(tail -n +3 "$ARQUIVO_IPS" | grep -v "(ESTA MÁQUINA)" | awk '$2 != "OFFLINE"' | wc -l)

echo "--------------------------------------------------------"
echo ">> Enviar   : $NOME_BASE  ($N_ARQ arquivo(s), $TAMANHO)"
echo ">> Destino  : <Área de Trabalho>/$DESTINO_VISTO"
echo ">> Máquinas : $N_ALVOS online (usuário $LAB_USUARIO)"
echo "--------------------------------------------------------"
read -r -p "Confirmar envio? (S/n): " CONFIRMA
[[ "${CONFIRMA,,}" == "n" ]] && { echo "Cancelado."; exit 0; }

{
    echo "Relatório de Distribuição — $(date '+%d/%m/%Y %H:%M:%S')"
    echo "Origem: $PASTA_ORIGEM ($N_ARQ arquivo(s), $TAMANHO)"
    echo "--------------------------------------------------------"
} > "$RELATORIO"

# Script remoto vai como argumento do bash -c (o stdin é o tar)
CMD_REMOTO="bash -c $(printf '%q' "$(cat "$SCRIPT_REMOTO")") _ $(printf '%q' "$SUBPASTA")"

TOTAL=0; OK=0

enviar_para() {
    local mac="$1" ip="$2" nome="$3" saida rc dest resultado
    ((TOTAL++))
    printf "Enviando para: %-26s " "$nome ($ip)..."

    saida=$(tar -cf - --exclude=.gitkeep -C "$TAR_DIR" "$TAR_ITEM" 2>/dev/null \
            | ssh_remote_stdin "$ip" "$CMD_REMOTO" 2>&1)
    # O código real vem DENTRO da saída (PIPESTATUS não sobrevive ao $(...))
    rc=$(sed -n 's/^__RC=//p' <<< "$saida" | tail -n 1)
    dest=$(sed -n 's/^__DEST=//p' <<< "$saida" | tail -n 1)

    if lab_dryrun; then
        resultado="[DRY-RUN]"
    elif [ "$rc" = "0" ]; then
        resultado="[OK] → $dest"
        ((OK++))
    elif [ "$rc" = "90" ]; then
        resultado="[ERRO] sem permissão para criar $dest"
    elif [ -n "$rc" ]; then
        resultado="[ERRO] tar falhou no aluno (código $rc)"
    else
        resultado="[ERRO] sem conexão SSH / senha recusada"
    fi
    echo "$resultado"
    echo "$nome ($ip): $resultado" >> "$RELATORIO"
}

para_cada_maquina enviar_para

echo "--------------------------------------------------------"
echo "[CONCLUÍDO] Material entregue em $OK de $TOTAL máquinas online."
echo ">> Relatório: $RELATORIO"
echo "Resultado: $OK de $TOTAL" >> "$RELATORIO"
lab_dryrun || log_acao "distribuir_material" "origem=${NOME_BASE// /_} arquivos=$N_ARQ entregues=$OK de=$TOTAL" 2>/dev/null || true
