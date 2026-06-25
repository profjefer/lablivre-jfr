# Segurança — LabLivre

## Modelo de Autenticação

O LabLivre suporta duas formas de autenticar nas máquinas dos alunos:

### 🔓 Modo Senha (padrão / compatibilidade)

A senha SSH fica em texto puro em `configs/lablivre.conf`:
```
LAB_SENHA="ufpr1234"
```

**Riscos:**
- Qualquer pessoa com acesso ao arquivo lê a senha
- Senha é repassada em cada comando SSH via `sshpass`
- Difícil de revogar (precisa trocar em todas as máquinas)

**Proteções aplicadas automaticamente:**
- `chmod 600 configs/lablivre.conf` (só o dono lê) — feito pelo `_provisionar.sh`
- `chmod 700 configs/` (pasta inteira) — feito pelo `_provisionar.sh`
- `chmod 700 logs/` (logs podem ter info operacional)

### 🔐 Modo Chave SSH (recomendado)

Uma chave Ed25519 específica do LabLivre (`configs/lablivre_key`) é gerada
e distribuída para todas as máquinas via `ssh-copy-id`. A partir daí,
o LabLivre opera sem precisar da senha em texto puro.

**Vantagens:**
- Senha permanece no conf apenas como **fallback** para máquinas novas
- Chave pode ser revogada (apaga `~/.ssh/authorized_keys` nas máquinas)
- Chave tem permissão `600` automaticamente
- Sem `sshpass` em runtime → menos chance de senha vazar em `ps` ou logs

## Como ativar o Modo Chave

### Pré-requisitos
1. `configs/lablivre.conf` configurado (senha funcionando)
2. `ips_atuais.txt` atualizado (opção 1 do menu)
3. Máquinas do lab ligadas

### Procedimento
Execute no menu principal:
```
12 - 🔐 Configurar Chave SSH (segurança)
```

Ou direto:
```bash
bash modulos/configurar_chave_ssh.sh
```

O script:
1. Gera o par `configs/lablivre_key` (privada) e `configs/lablivre_key.pub`
2. Para cada máquina online: instala a chave pública em `~/.ssh/authorized_keys`
3. Valida que a chave funciona
4. Pergunta se deve ativar `LAB_AUTH_MODE="chave"` no conf

A partir daí, todas as operações usam a chave automaticamente
(via wrapper `modulos/_ssh.sh`).

### Distribuir a chave para máquinas novas
Quando uma máquina nova entra no lab, ela ainda só tem a senha. Basta
rodar a opção 12 novamente — o script detecta quem já tem a chave e só
configura as faltantes.

## Voltar para Modo Senha

Edite `configs/lablivre.conf` e troque:
```
LAB_AUTH_MODE="chave"
```
para:
```
LAB_AUTH_MODE="senha"
```

A senha continuou salva durante todo o processo.

## Boas práticas adicionais

### 1. Senha forte para `LAB_SENHA`
Mesmo no modo chave, a senha fica salva como fallback. Use uma senha forte
(20+ caracteres) e troque periodicamente em todas as máquinas.

### 2. Não comitar `configs/` no Git
Adicione ao `.gitignore`:
```
configs/lablivre.conf
configs/macs.txt
configs/lablivre_key*
configs/.backups/
```

### 3. Auditoria
Toda ação destrutiva é registrada em `logs/auditoria.jsonl`. Veja com:
```
menu.sh → opção 11 (Ver Auditoria)
```

### 4. MACs desconhecidos
A opção 1 detecta MACs presentes na rede que não estão no `macs.txt` e
salva em `logs/macs_desconhecidos.log`. Útil para identificar dispositivos
não autorizados.

## Em caso de comprometimento

Se você suspeita que a senha vazou:

1. **Imediato**: trocar a senha em todas as máquinas
   ```bash
   # Em cada máquina do lab:
   sudo passwd softwarelivre
   ```

2. **Curto prazo**: revogar a chave SSH antiga
   ```bash
   # Em cada máquina:
   sed -i '/lablivre@/d' ~/.ssh/authorized_keys
   ```

3. **Reconfigurar**: rodar `configurar_chave_ssh.sh` para gerar nova chave

4. **Investigar**: examinar `logs/auditoria.jsonl` para ações suspeitas
