#!/bin/bash

cd "$(dirname "$0")/.." || exit 1

CONF_FILE="configs/lablivre.conf"
if [ -f "$CONF_FILE" ]; then source "$CONF_FILE";
else LAB_USUARIO="ufpr"; LAB_SENHA="UFPR";
fi
source modulos/_ssh.sh 2>/dev/null || true

USUARIO_SSH="$LAB_USUARIO"
SENHA_SSH="$LAB_SENHA"
ARQUIVO_IPS="ips_atuais.txt"
RELATORIO="logs/relatorio_manutencao.txt"
mkdir -p logs

if [ ! -f "$ARQUIVO_IPS" ]; then
    echo "[ERRO] Arquivo '$ARQUIVO_IPS' não encontrado."
    echo ">> Execute primeiro a opção 1 (Mapear Rede) no menu."
    exit 1
fi

source modulos/_dryrun.sh 2>/dev/null || true
first_echo=1
echo "========================================================"
echo "              🛠️  MANUTENÇÃO DO SISTEMA                 "
echo "========================================================"
echo "1 - 🔄 Atualização Completa (Limpa repositórios + update/upgrade)"
echo "2 - 📦 Instalar Novo Pacote/Software"
echo "--------------------------------------------------------"
read -p "Escolha (1 ou 2): " OPCAO_MANUTENCAO

if [ "$OPCAO_MANUTENCAO" == "1" ]; then
    VACINA="sed -i '/cloud.r-project.org/d' /etc/apt/sources.list 2>/dev/null; \
            sed -i '/dell.archive.canonical.com/d' /etc/apt/sources.list 2>/dev/null; \
            find /etc/apt/sources.list.d/ -type f \
                -exec sed -i '/cloud.r-project.org/d' {} + 2>/dev/null; \
            find /etc/apt/sources.list.d/ -type f \
                -exec sed -i '/dell.archive.canonical.com/d' {} + 2>/dev/null;"
    COMANDO_REMOTO="echo '$SENHA_SSH' | sudo -S sh -c \
        'export DEBIAN_FRONTEND=noninteractive; \
         $VACINA \
         apt-get update -y && apt-get upgrade -y && \
         apt-get autoremove -y && apt-get autoclean -y'"
    MENSAGEM_ACAO="Limpando repositórios e atualizando sistemas"

elif [ "$OPCAO_MANUTENCAO" == "2" ]; then
    read -p "Digite o nome do pacote (ex: htop, geany, python3-pip): " NOME_PACOTE
    if [ -z "$NOME_PACOTE" ]; then
        echo "[ERRO] O nome do pacote não pode estar vazio."
        exit 1
    fi
    COMANDO_REMOTO="echo '$SENHA_SSH' | sudo -S sh -c \
        'export DEBIAN_FRONTEND=noninteractive; apt-get install -y $NOME_PACOTE'"
    MENSAGEM_ACAO="Instalando o pacote '$NOME_PACOTE'"
else
    echo "Opção inválida! Retornando..."
    exit 1
fi

echo "--------------------------------------------------------"
echo ">> $MENSAGEM_ACAO no laboratório..."
echo ">> Aviso: Isso pode demorar alguns minutos."
echo "--------------------------------------------------------"

{
    echo "========================================================================="
    echo "RELATÓRIO DE MANUTENÇÃO - $(date '+%d/%m/%Y %H:%M:%S')"
    echo "Ação: $MENSAGEM_ACAO"
    echo "========================================================================="
    printf "%-18s | %-16s | %-15s | %s\n" "MAC" "IP" "MÁQUINA" "STATUS"
    echo "-------------------------------------------------------------------------"
} > "$RELATORIO"

while read -r mac ip nome resto; do
    if [[ -z "$mac" ]] || [[ "$ip" == "OFFLINE" ]]; then continue; fi

    echo -n "Processando: $nome ($ip)... "

    if [[ "$resto" == *"(ESTA MÁQUINA)"* ]]; then
        SAIDA=$(eval "$COMANDO_REMOTO" 2>&1)
        STATUS=$?
    else
        SAIDA=$(ssh_remote "$ip" "$COMANDO_REMOTO" -o ServerAliveInterval=3 2>&1)
        STATUS=$?
    fi

    if [ $STATUS -eq 0 ]; then
        echo "[OK]"
        printf "%-18s | %-16s | %-15s | %s\n" "$mac" "$ip" "$nome" "[OK] Sucesso" >> "$RELATORIO"
    else
        echo "[ERRO]"
        MOTIVO=$(echo "$SAIDA" | tail -n 2 | tr '\n' ' ')
        echo "   -> Detalhe: $MOTIVO"
        printf "%-18s | %-16s | %-15s | %s\n" "$mac" "$ip" "$nome" "[ERRO] $MOTIVO" >> "$RELATORIO"
    fi
done < <(tail -n +3 "$ARQUIVO_IPS")

echo "--------------------------------------------------------"
echo "[CONCLUÍDO] Manutenção finalizada!"
log_acao "manutencao_sistema" "acao=$OPCAO_MANUTENCAO" 2>/dev/null || true
echo "📄 Relatório salvo em: $RELATORIO"
