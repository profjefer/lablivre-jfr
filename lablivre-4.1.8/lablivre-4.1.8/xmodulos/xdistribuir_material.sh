#!/bin/bash

# Garante que o script localize a raiz do projeto
cd "$(dirname "$0")/.." || exit 1

CONF_FILE="configs/lablivre.conf"
if [ -f "$CONF_FILE" ]; then 
    source "$CONF_FILE"
else 
    LAB_USUARIO="ufpr"
    LAB_SENHA="UFPR"
fi

ARQUIVO_IPS="ips_atuais.txt"
RELATORIO="logs/relatorio_distribuicao.txt"
mkdir -p logs

# Pasta padrão de material (definida no conf, com fallback)
PASTA_PADRAO="$(pwd)/${LAB_PASTA_MATERIAL:-envia_material}"
mkdir -p "$PASTA_PADRAO" 2>/dev/null

# ===================================================================
# 1. INTERFACE DE ENTRADA (Seleção de pasta OU arquivos)
# ===================================================================
# Pergunta primeiro: enviar uma pasta inteira ou arquivos avulsos?
TIPO_ENVIO=$(zenity --list --radiolist \
    --title="O que deseja distribuir?" \
    --text="Escolha o tipo de conteúdo a enviar aos alunos:" \
    --column="" --column="Tipo" --column="Descrição" \
    TRUE  "pasta"    "Uma pasta inteira (com subpastas)" \
    FALSE "arquivos" "Um ou mais arquivos avulsos" \
    --width=480 --height=240)

# Cancelou?
[ -z "$TIPO_ENVIO" ] && exit 0

if [ "$TIPO_ENVIO" = "pasta" ]; then
    # Seletor de PASTA (só mostra diretórios)
    PASTA_ORIGEM=$(zenity --file-selection --directory \
        --filename="$PASTA_PADRAO/" \
        --title="Selecione a PASTA para enviar aos alunos")
else
    # Seletor de ARQUIVOS (permite múltiplos, arquivos ficam selecionáveis)
    ARQUIVOS_SEL=$(zenity --file-selection --multiple \
        --filename="$PASTA_PADRAO/" \
        --separator="|" \
        --title="Selecione o(s) ARQUIVO(S) para enviar aos alunos")

    [ -z "$ARQUIVOS_SEL" ] && exit 0

    # Copia os arquivos selecionados para uma pasta temporária com nome
    # amigável (vira o nome da pasta no destino) e permissão legível
    PASTA_TMP="/tmp/Arquivos_$(date +%Y%m%d_%H%M)"
    rm -rf "$PASTA_TMP"
    mkdir -p "$PASTA_TMP"
    chmod 755 "$PASTA_TMP"
    IFS='|' read -ra LISTA <<< "$ARQUIVOS_SEL"
    for arq in "${LISTA[@]}"; do
        cp -r "$arq" "$PASTA_TMP/" 2>/dev/null
    done
    PASTA_ORIGEM="$PASTA_TMP"
fi

# Verifica se o professor clicou em "Cancelar" ou fechou a janela
if [ -z "$PASTA_ORIGEM" ]; then
    exit 0
fi

if [ ! -e "$PASTA_ORIGEM" ]; then
    zenity --error --text="O caminho '$PASTA_ORIGEM' não foi encontrado." --width=300
    exit 1
fi

# Prepara caminhos (remove barra final se houver)
PASTA_ORIGEM="${PASTA_ORIGEM%/}"
NOME_BASE=$(basename "$PASTA_ORIGEM")
DIR_PAI=$(dirname "$PASTA_ORIGEM")

MEU_IP=$(hostname -I | awk '{print $1}')
echo "Relatório de Distribuição - $(date)" > "$RELATORIO"

# Conta quantas máquinas válidas existem para a barra de progresso
TOTAL_MAQUINAS=$(tail -n +3 "$ARQUIVO_IPS" | grep -v -w "OFFLINE" | grep -v "ESTA MÁQUINA" | wc -l)
[ "$TOTAL_MAQUINAS" -eq 0 ] && TOTAL_MAQUINAS=1

# Descobre o destino REAL consultando a primeira máquina online (rápido)
# Assim o popup final mostra exatamente o caminho onde os arquivos foram parar.
DESTINO_REAL=""
PRIMEIRO_IP=$(tail -n +3 "$ARQUIVO_IPS" | awk '$2 != "OFFLINE" && $4 != "(ESTA" {print $2; exit}')
if [ -n "$PRIMEIRO_IP" ]; then
    DESTINO_REAL=$(sshpass -p "$LAB_SENHA" ssh -q -o StrictHostKeyChecking=no \
        -o ConnectTimeout=3 "$LAB_USUARIO@$PRIMEIRO_IP" \
        'D=$(xdg-user-dir DESKTOP 2>/dev/null); [ -z "$D" ] || [ "$D" = "$HOME" ] && { for d in "Área de trabalho" "Área de Trabalho" "Desktop"; do [ -d "$HOME/$d" ] && D="$HOME/$d" && break; done; }; echo "$D"' 2>/dev/null)
fi
[ -z "$DESTINO_REAL" ] && DESTINO_REAL='$HOME/Área de trabalho'

# ===================================================================
# 2. EXECUÇÃO COM BARRA DE PROGRESSO (GUI)
# ===================================================================
(
    echo "5"
    echo "# Preparando empacotamento de: $NOME_BASE"
    
    ATUAL=0
    SUCESSO=0
    FALHA=0

    while read -r mac ip nome resto; do
        # Ignora offline, linhas vazias ou a própria máquina
        if [[ -z "$mac" ]] || [[ "$ip" == "OFFLINE" ]] || [[ "$nome" == *"(ESTA MÁQUINA)"* ]]; then 
            continue
        fi
        
        echo "# Enviando para: $nome ($ip)..."

        # COMANDO REMOTO: descobre Desktop real com xdg-user-dir
        # (lida com "Área de trabalho" vs "Área de Trabalho" vs "Desktop" etc.)
        CMD_REMOTO='DEST=$(xdg-user-dir DESKTOP 2>/dev/null); [ -z "$DEST" ] || [ "$DEST" = "$HOME" ] && { for d in "Área de trabalho" "Área de Trabalho" "Desktop" "Escritorio"; do [ -d "$HOME/$d" ] && DEST="$HOME/$d" && break; done; }; [ -z "$DEST" ] && DEST="$HOME"; mkdir -p "$DEST/Material_Aulas"; tar -xf - -C "$DEST/Material_Aulas"'

        # Tar-Pipe Stream — captura status real do SSH
        SAIDA=$( { tar -cf - -C "$DIR_PAI" "$NOME_BASE" 2>/dev/null | \
            sshpass -p "$LAB_SENHA" ssh -o StrictHostKeyChecking=no \
            -o ConnectTimeout=5 "$LAB_USUARIO@$ip" "$CMD_REMOTO" 2>&1; \
            echo "__RC=${PIPESTATUS[1]}"; } )
        STATUS_SSH=$(echo "$SAIDA" | grep -o '__RC=[0-9]*' | cut -d= -f2)

        if [ "${STATUS_SSH:-1}" -eq 0 ]; then
            echo "$nome ($ip): [OK]" >> "$RELATORIO"
            ((SUCESSO++))
        else
            ERRO=$(echo "$SAIDA" | grep -v '__RC=' | head -1)
            echo "$nome ($ip): [ERRO] $ERRO" >> "$RELATORIO"
            ((FALHA++))
        fi

        # Atualiza a porcentagem da barra
        ((ATUAL++))
        PERCENT=$(( 5 + (ATUAL * 95 / TOTAL_MAQUINAS) ))
        echo "$PERCENT"

    done < <(tail -n +3 "$ARQUIVO_IPS")
    
    echo "100"
    echo "# Distribuição Concluída!"
    
    # Salva o resultado num arquivo temporário para mostrar no resumo
    echo "$SUCESSO|$FALHA" > /tmp/lablivre_dist_stats.tmp

) | zenity --progress \
    --title="Distribuindo Material" \
    --text="Iniciando transferência na rede..." \
    --percentage=0 \
    --auto-close \
    --auto-kill \
    --width=450

# Verifica se o usuário apertou "Cancelar" na barra de progresso
if [ $? -ne 0 ]; then
    zenity --warning --text="Distribuição cancelada pelo usuário." --width=300
    exit 1
fi

# ===================================================================
# 3. RESUMO FINAL VISUAL
# ===================================================================
if [ -f /tmp/lablivre_dist_stats.tmp ]; then
    IFS='|' read -r SUCESSO FALHA < /tmp/lablivre_dist_stats.tmp
    rm -f /tmp/lablivre_dist_stats.tmp
    
    zenity --info \
        --title="Distribuição Concluída" \
        --text="✅ <b>Material enviado com sucesso!</b>\n\n📦 <b>Enviado:</b> <i>$NOME_BASE</i>\n\n📍 <b>Destino nas máquinas dos alunos:</b>\n<tt>$DESTINO_REAL/Material_Aulas/</tt>\n\n📊 <b>Resumo:</b>\n🟢 $SUCESSO terminais receberam\n🔴 $FALHA terminais falharam\n\n<i>Log detalhado: logs/relatorio_distribuicao.txt</i>" \
        --width=480
fi

# Limpa pasta temporária se foi criada para arquivos avulsos
if [[ "$PASTA_ORIGEM" == /tmp/Arquivos_* ]]; then
    rm -rf "$PASTA_ORIGEM"
fi
