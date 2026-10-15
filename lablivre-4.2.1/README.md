# LabLivre — Orquestrador de Laboratório de Informática

Sistema de administração remota para laboratórios Linux (Ubuntu 24.04+).
Controla todas as máquinas do laboratório a partir da máquina do professor, via SSH,
**sem instalar nada nos alunos** (modelo *agentless*).

**Versão atual:** 4.2.1 · Software livre · UFPR Palotina · **somente IPv4**

---

## 🚀 Instalação rápida

### Opção A — Pacote .deb (recomendado)
```bash
sudo apt install ./lablivre_4.2.1_all.deb
```

### Opção B — Via Git
```bash
curl -fsSL https://raw.githubusercontent.com/profjefer/lablivre-jfr/main/gitinstall.sh | bash
```

As duas opções instalam em `/opt/lablivre` e criam os comandos `lablivre` (texto) e
`lablivre-gui` (gráfico). Atualizar é instalar o pacote novo por cima: `lablivre.conf`,
`macs.txt` e logs são preservados.

### Depois de instalar
```bash
# 1. OBRIGATÓRIO: cadastre os MACs e nomes das máquinas (veja abaixo)
nano /opt/lablivre/configs/macs.txt

# 2. Configure: dependências, usuário/senha SSH, cron, servidor web
lablivre        # → opção 99

# 3. Mapeie a rede
lablivre        # → opção 1
```

---

## 📋 O arquivo `configs/macs.txt` (obrigatório, feito por você)

É a **âncora de hardware** do laboratório e o ponto de partida de tudo. O LabLivre
**não gera este arquivo sozinho**: os MACs e os nomes vêm de você. A partir dele, todo o
resto é automático (IPs, Wake-on-LAN, dashboards, histórico, inventário).

```
# MAC                NOME            (comentários em linha própria, com #)
d0:94:66:e1:7f:dd    michelangelo
d0:94:66:e1:82:a0    raphael
d0:94:66:e1:81:57    lula-molusco
48:ad:9a:88:3a:92    lula-molusco
```

- **Como achar o MAC:** rode `ip link` em cada máquina. A placa `en…`/`eth…` é o cabo, a `wl…` é o wifi.
- **Mais de uma placa (cabo + wifi):** repita o **mesmo nome**. A **primeira** linha é a principal
  e é a usada pelo Wake-on-LAN, que só funciona pelo cabo.
- **A máquina do professor** pode estar na lista. Ela é reconhecida pelo MAC e marcada como `(ESTA MÁQUINA)`.
- **MAC inválido ou duplicado** gera aviso na opção 1.
- **MACs que respondem na rede mas não estão no arquivo** vão para `logs/macs_desconhecidos.log`.

---

## 📋 Menu (modo texto — `lablivre`)

| Opção | Função |
|------:|--------|
| 1 | **Mapear rede.** arp-scan → nmap → ping + ARP; cruza com o `macs.txt` e gera `ips_atuais.txt` |
| 2 | **Distribuir material** para `<Área de Trabalho>/Material_Aulas/` (português ou inglês) |
| 3 | **Modo Prova.** Bloqueia a internet IPv4 e mantém a rede local; persiste no reboot e tem validade máxima ([detalhes](docs/MODO_PROVA.md)) |
| 4 | **Inventário:** série, modelo, CPU, RAM, disco, GPU, BIOS, Wake-on-LAN, USB, Python/Node… (TXT + HTML) |
| 5 | **Mensagem:** pop-up na tela, terminal (`wall`) ou os dois |
| 6 | **Ligar** o laboratório (Wake-on-LAN) |
| 7 | **Desligar** o laboratório (pula a máquina do professor) |
| 8 | **Manutenção APT** (update/upgrade/instalar pacote) |
| 9 | **Corrigir repositórios** quebrados (vacina APT) |
| 10 | **Diagnosticar conexão SSH** (ping → porta 22 → autenticação) |
| 11 | **Ver auditoria** (`logs/auditoria.jsonl`) |
| 12 | **Configurar chave SSH** (dispensa a senha do SSH) |
| 13 | **Abrir o portal web** (dashboards e inventário) |
| 14 | **Relatório de status** (TXT rápido) |
| 15 | **Limpar Downloads e Lixeira** de todas as máquinas |
| 16 | **Sincronizar horário** (NTP; se não houver NTP, usa a hora do orquestrador) |
| 99 | **Configurações globais** (nome do lab, usuário, senha, pasta de material) |

Os módulos que agem nas máquinas aceitam `--dry-run` (só mostram o que fariam). Para simular tudo: `lablivre --dry-run`.

O menu gráfico (`lablivre-gui`) oferece as mesmas funções. O mapeamento, o Modo Prova e o
horário dele usam exatamente o mesmo motor do modo texto.

---

## ⏰ Tarefas automáticas (instaladas pela opção 99)

| Quando | O que |
|---|---|
| A cada hora | Mapeia a rede, atualiza os dashboards, **reaplica o Modo Prova** nas máquinas que ligaram e libera as pendentes |
| 07:00 | Sincroniza os relógios |
| 23:00 | Desliga o laboratório |
| 23:59 | Snapshot diário (histórico) |
| Domingo 03:00 | Backup do `macs.txt` (mantém os últimos 30) |
| No boot | Servidor web dos dashboards (porta 8080) |

---

## 📁 Estrutura de pastas

```
/opt/lablivre/
├── menu.sh / xmenu.sh      ← menus texto e gráfico
├── configurar_lab.sh       ← configuração (opção 99)
├── _provisionar.sh         ← WoL, cron, servidor web, permissões
├── configs/
│   ├── lablivre.conf       ← credenciais e opções (chmod 600, fora do git)
│   └── macs.txt            ← MACs e nomes (OBRIGATÓRIO, fora do git)
├── modulos/                ← módulos do menu texto
│   ├── _comum.sh           ← base comum: conf, laço das máquinas, scripts remotos
│   ├── _ssh.sh _log.sh _dryrun.sh _i18n.sh _instalar_deps.sh
│   └── remoto/             ← scripts que rodam NA máquina do aluno (enviados via SSH)
├── xmodulos/               ← janelas Zenity
├── web/                    ← dashboards + api.json (porta 8080)
├── logs/                   ← relatórios, auditoria.jsonl, histórico
├── docs/                   ← MODO_PROVA.md, SEGURANCA.md, ROADMAP.md, wiki
├── tests/run_tests.sh      ← suíte de testes automatizados
└── packaging/              ← geração do .deb
```

---

## 🔧 Configuração (`configs/lablivre.conf`)

```bash
LAB_NOME="UFPR Palotina"
LAB_USUARIO="softwarelivre"
LAB_SENHA="********"
LAB_PASTA_MATERIAL="envia_material"
LAB_AUTH_MODE="senha"            # "chave" depois da opção 12
LAB_IDIOMA="pt_BR"

# Modo Prova (opcionais)
LAB_PROVA_REDES="10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 200.236.0.0/16"
LAB_PROVA_HORAS="4"
```

Para alterar, use a opção **99** (ela preserva as outras variáveis) ou edite o arquivo.

---

## 🧩 Requisitos

- **Máquina do professor:** Ubuntu 24.04+. A opção 99 instala `arp-scan`, `nmap`, `sshpass`,
  `wakeonlan`, `zenity`, `ethtool`, `dmidecode`, `jq` e `python3`.
- **Máquinas dos alunos:** o mesmo usuário e senha em todas, com `sudo`. Também precisam de
  servidor SSH ativo e Wake-on-LAN ligado na BIOS (desativar o *Deep Sleep*).
- **Rede:** **somente IPv4**. Veja [docs/ROADMAP.md](docs/ROADMAP.md) para o que isso
  significa no Modo Prova.

---

## 🧪 Testes
```bash
bash tests/run_tests.sh
```
Os testes rodam com comandos simulados (SSH, sudo, iptables, systemd…), então não tocam a rede.

---

## 🔐 Segurança e próximos passos

- [docs/SEGURANCA.md](docs/SEGURANCA.md): senha × chave SSH e cuidados.
- [docs/ROADMAP.md](docs/ROADMAP.md): decisões de escopo (IPv4, `macs.txt` manual) e o plano
  da **4.3**, com `sudo` sem senha restrito aos comandos do LabLivre, para a senha não
  aparecer no `ps` dos alunos.
