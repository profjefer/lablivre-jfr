# LabLivre — Orquestrador de Laboratório de Informática

Sistema de administração remota para laboratórios Linux (Ubuntu 24.04+).  
Permite controlar todas as máquinas do lab a partir da máquina do professor via SSH.

**Versão atual:** 4.1.7 · Software livre · UFPR Palotina

---

## 🚀 Instalação rápida

### Opção A — Via pacote .deb (recomendado)
```bash
sudo apt install ./lablivre_4.1.7_all.deb
```

### Opção B — Via Git (um comando)
```bash
curl -fsSL https://raw.githubusercontent.com/SEU_USUARIO/lablivre/main/gitinstall.sh | bash
```

Ambos instalam em `/opt/lablivre`, criam os comandos `lablivre` (texto) e `lablivre-gui` (gráfico), e configuram permissões.

### Depois de instalar (qualquer opção):
```bash
# 1. Preencha os MACs do seu lab
nano /opt/lablivre/configs/macs.txt

# 2. Configure (instala deps, define senha SSH, cron, servidor web)
lablivre        # → opção 99

# 3. Mapeie a rede
lablivre        # → opção 1
```

---

## 📁 Estrutura de Pastas

```
/opt/lablivre/          ← raiz do projeto (ou onde instalar)
├── menu.sh             ← menu principal (modo texto)
├── xmenu.sh            ← menu gráfico (Zenity)
├── configurar_lab.sh   ← configuração inicial (rodar primeiro!)
├── gitinstall.sh       ← instalador via Git
│
├── configs/
│   ├── lablivre.conf   ← credenciais e configurações do lab
│   └── macs.txt        ← lista de MACs das máquinas (OBRIGATÓRIO)
│
├── modulos/            ← scripts do menu texto
│   ├── atualizar_ips.sh
│   ├── distribuir_material.sh
│   ├── modo_prova.sh
│   ├── coletar_inventario.sh
│   ├── enviar_mensagem.sh
│   ├── ligar_labold.sh
│   ├── desligar_labold.sh
│   ├── manutencao_sistema.sh
│   ├── corrigir_quebrados.sh
│   ├── diagnosticar_ssh.sh
│   └── configurar_lab.sh
│
├── xmodulos/           ← scripts do menu gráfico (Zenity)
├── envia_material/     ← pasta de onde o material é distribuído
├── logs/               ← relatórios gerados automaticamente
├── web/                ← relatórios HTML publicados localmente
└── docs/               ← documentação extra
```

---

## ⚙️ Instalação

### Via Git (recomendado)
```bash
curl -sL https://raw.githubusercontent.com/SEU_USUARIO/lablivre/main/gitinstall.sh | bash
```
Ou manualmente:
```bash
git clone https://github.com/profjefer/lablivre-jfr.git /opt/lablivre
cd /opt/lablivre
bash gitinstall.sh
```

### Manual
```bash
sudo mkdir -p /opt/lablivre
sudo chown $USER:$USER /opt/lablivre
# copie os arquivos para /opt/lablivre
cd /opt/lablivre
bash configurar_lab.sh
```

---

## 🚀 Primeiros Passos (OBRIGATÓRIO)

### 1. Preencher o arquivo de MACs
Antes de qualquer coisa, cadastre as máquinas do laboratório:
```bash
nano /opt/lablivre/configs/macs.txt
```
Formato (uma máquina por linha):
```
aa:bb:cc:dd:ee:ff   nome-da-maquina
d0:94:66:e1:7f:dd   michelangelo
d0:94:66:e1:82:a0   raphael
```
> ⚠️ Sem este arquivo preenchido o mapeamento de rede não funciona.

### 2. Executar a configuração inicial
```bash
cd /opt/lablivre
bash configurar_lab.sh
```
Este script:
- Instala dependências (`nmap`, `sshpass`, `wakeonlan`, etc.)
- Cria a estrutura de pastas
- Salva usuário/senha SSH e nome do laboratório em `configs/lablivre.conf`
- Ativa Wake-on-LAN na placa de rede do professor
- Configura cron para atualizar IPs a cada hora

### 3. Iniciar o orquestrador
```bash
cd /opt/lablivre
bash menu.sh
```

---

## 📋 Funcionalidades

| Opção | Função |
|-------|--------|
| 1 | Mapear rede (atualiza `ips_atuais.txt` com MACs e IPs reais) |
| 2 | Distribuir material para o Desktop dos alunos |
| 3 | Modo Prova (bloqueia/libera internet via iptables) |
| 4 | Inventário de hardware de todas as máquinas |
| 5 | Enviar mensagem (pop-up Zenity ou terminal wall) |
| 6 | Ligar laboratório (Wake-on-LAN) |
| 7 | Desligar laboratório (shutdown remoto) |
| 8 | Manutenção (APT update/upgrade ou instalar pacote) |
| 9 | Corrigir repositórios APT quebrados |
| 10 | Diagnosticar conexão SSH das máquinas |
| 99 | Configurações globais (usuário, senha, nome do lab) |

---

## 📦 Dependências
- `nmap` — varredura de rede
- `sshpass` — SSH com senha em script
- `wakeonlan` — Wake-on-LAN
- `zenity` — pop-ups gráficos (xmodulos)
- `dmidecode` — informações de BIOS/hardware
- `ethtool` — configuração da placa de rede (WoL)
- `avahi-utils` — resolução de nomes na rede local

---

## 🔧 Configuração (`configs/lablivre.conf`)

```bash
LAB_NOME="UFPR Palotina"
LAB_USUARIO="softwarelivre"
LAB_SENHA="ufpr1234"
LAB_PASTA_MATERIAL="envia_material"
```

Para alterar, edite o arquivo diretamente ou rode a opção `99` no menu.

---

## 🔄 Atualização do projeto
```bash
cd /opt/lablivre
git pull
bash configurar_lab.sh   # re-aplica permissões e cron
```

---

## 📝 Logs gerados
| Arquivo | Conteúdo |
|---------|----------|
| `logs/inventario_lab.txt` | Hardware de todas as máquinas |
| `logs/relatorio_distribuicao.txt` | Status do último envio de material |
| `logs/relatorio_manutencao.txt` | Status da última manutenção APT |
| `logs/cron_ips.log` | Log das atualizações automáticas de IP |
| `ips_atuais.txt` | Mapa atual MAC→IP→Nome das máquinas |
