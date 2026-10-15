#!/bin/bash

# configurar_chave_ssh.sh — Gera chave SSH e distribui para as máquinas do lab
# Após isso, o LabLivre pode operar SEM senha em texto puro no conf.

cd "$(dirname "$0")/.." || exit 1

CONF_FILE="configs/lablivre.conf"
[ -f "$CONF_FILE" ] && source "$CONF_FILE"
ARQUIVO_IPS="ips_atuais.txt"
CHAVE="configs/lablivre_key"

echo "========================================================"
echo "    🔐 CONFIGURAÇÃO DE CHAVE SSH (segurança)            "
echo "========================================================"
echo ""
echo "  Esta operação:"
echo "    1. Gera um par de chaves SSH específico do LabLivre"
echo "    2. Distribui a chave pública para todas as máquinas"
echo "    3. Habilita o modo CHAVE no lablivre.conf"
echo ""
echo "  Após isso, a senha em texto puro deixa de ser usada"
echo "  na operação normal (mas continua salva como fallback)."
echo ""
echo "  ⚠️  É necessário ter o macs.txt preenchido e a opção 1"
echo "      (mapear rede) executada antes de continuar."
echo ""
echo "--------------------------------------------------------"

if [ ! -f "$ARQUIVO_IPS" ]; then
    echo "[ERRO] $ARQUIVO_IPS não encontrado. Execute opção 1 antes."
    exit 1
fi

if [ -z "$LAB_SENHA" ]; then
    echo "[ERRO] Senha não definida no conf. Execute configurar_lab.sh antes."
    exit 1
fi

read -p "Continuar? (s/N): " CONFIRMA
[[ "${CONFIRMA,,}" != "s" ]] && exit 0

# 1. Gerar par de chaves se ainda não existe
if [ -f "$CHAVE" ]; then
    echo ">> Chave SSH já existe em $CHAVE"
    read -p "   Sobrescrever? (s/N): " SOBRE
    if [[ "${SOBRE,,}" == "s" ]]; then
        rm -f "$CHAVE" "$CHAVE.pub"
    fi
fi

if [ ! -f "$CHAVE" ]; then
    echo ">> Gerando par de chaves Ed25519..."
    ssh-keygen -t ed25519 -f "$CHAVE" -N "" -C "lablivre@$(hostname)" -q
    chmod 600 "$CHAVE"
    chmod 644 "$CHAVE.pub"
    echo "   ✓ Chave gerada"
fi

# 2. Distribuir chave pública para cada máquina online
echo ""
echo ">> Distribuindo chave pública para o laboratório..."
echo "--------------------------------------------------------"

CHAVE_PUB=$(cat "$CHAVE.pub")
SUCESSO=0
FALHA=0
JA_TINHA=0

while read -r mac ip nome resto; do
    if [[ -z "$mac" ]] || [[ "$ip" == "OFFLINE" ]] || [[ "$resto" == *"(ESTA MÁQUINA)"* ]]; then
        continue
    fi

    echo -n "Configurando: $nome ($ip)... "

    # Testa se a chave já funciona
    if ssh -n -i "$CHAVE" \
        -o StrictHostKeyChecking=no \
        -o PasswordAuthentication=no \
        -o BatchMode=yes \
        -o ConnectTimeout=3 \
        "$LAB_USUARIO@$ip" "exit" 2>/dev/null; then
        echo "[JÁ CONFIGURADA]"
        ((JA_TINHA++))
        continue
    fi

    # Adiciona a chave via SSH com senha
    INSTALAR="mkdir -p ~/.ssh && chmod 700 ~/.ssh && \
              grep -q -F '$CHAVE_PUB' ~/.ssh/authorized_keys 2>/dev/null || \
              echo '$CHAVE_PUB' >> ~/.ssh/authorized_keys && \
              chmod 600 ~/.ssh/authorized_keys"

    if sshpass -p "$LAB_SENHA" ssh -n \
        -o StrictHostKeyChecking=no \
        -o ConnectTimeout=5 \
        "$LAB_USUARIO@$ip" "$INSTALAR" 2>/dev/null; then
        # Valida que ficou funcional
        if ssh -n -i "$CHAVE" \
            -o StrictHostKeyChecking=no \
            -o PasswordAuthentication=no \
            -o BatchMode=yes \
            -o ConnectTimeout=3 \
            "$LAB_USUARIO@$ip" "exit" 2>/dev/null; then
            echo "[OK]"
            ((SUCESSO++))
        else
            echo "[INSTALADA, MAS NÃO VALIDA]"
            ((FALHA++))
        fi
    else
        echo "[ERRO SSH]"
        ((FALHA++))
    fi
done < <(tail -n +3 "$ARQUIVO_IPS")

echo "--------------------------------------------------------"
echo "Resultado: $SUCESSO novas · $JA_TINHA já tinham · $FALHA falhas"

# 3. Atualiza o conf para usar chave
if [ $SUCESSO -gt 0 ] || [ $JA_TINHA -gt 0 ]; then
    echo ""
    read -p ">> Habilitar modo CHAVE no lablivre.conf? (s/N): " HABILITAR
    if [[ "${HABILITAR,,}" == "s" ]]; then
        # Remove linha anterior se existir
        sed -i '/^LAB_AUTH_MODE=/d' "$CONF_FILE"
        echo 'LAB_AUTH_MODE="chave"' >> "$CONF_FILE"
        chmod 600 "$CONF_FILE"
        echo "✅ Modo CHAVE habilitado."
        echo ""
        echo "  A partir de agora, o LabLivre usa chave SSH."
        echo "  A senha permanece no conf apenas como fallback"
        echo "  para máquinas que ainda não receberam a chave."
        echo ""
        echo "  Para voltar para senha: edite $CONF_FILE"
        echo "  e mude LAB_AUTH_MODE para \"senha\""
    fi
fi

if [ $FALHA -gt 0 ]; then
    echo ""
    echo "  ⚠️  $FALHA máquinas falharam. Elas continuarão usando senha"
    echo "     no fallback. Rode este script novamente quando estiverem"
    echo "     online para completar a migração."
fi
