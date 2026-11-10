# LabLivre — Orquestrador de Laboratório de Informática

**Administre um laboratório inteiro de máquinas Linux a partir do computador do professor.**
Ligar e desligar tudo pela rede, bloquear a internet durante a prova, mandar material e
mensagens para as telas, atualizar pacotes, levantar o inventário de hardware e acompanhar
tudo num portal web que se atualiza sozinho.

Funciona por SSH, **sem instalar nada nas máquinas dos alunos** (modelo *agentless*).
É escrito em Bash, com um pequeno servidor web em Python, e tem testes automatizados.
Desenvolvido e usado no dia a dia nos laboratórios da **UFPR Palotina**.

**Versão atual:** 4.2.7 · Software livre · Ubuntu 24.04+ · **somente IPv4**

| O que faz | Como |
|---|---|
| 🗺️ Descobre os IPs das máquinas | arp-scan + nmap + ARP, a partir do `macs.txt` |
| ⚡ Liga e desliga o laboratório | Wake-on-LAN (3 rodadas) e desligamento agendado |
| 📝 Modo Prova | bloqueia a internet IPv4, mantém a rede local, tem validade e sobrevive a reboot |
| 📦 Material e mensagens | envia arquivos para a Área de Trabalho e mostra avisos na tela |
| 🔧 Manutenção | APT, repositórios quebrados, horário, limpeza de Downloads |
| 🖥️ Inventário e portal web | hardware de cada máquina, painéis para TV, mapa de calor, auditoria |

---

## 🚀 Instalação

### Opção A — Pacote .deb (recomendado)

Baixe o pacote da [última versão](https://github.com/profjefer/lablivre-jfr/releases/latest)
(ou da pasta [`dist/`](dist/) deste repositório) e instale:

```bash
wget https://github.com/profjefer/lablivre-jfr/raw/main/dist/lablivre_4.2.7_all.deb
sudo apt install ./lablivre_4.2.7_all.deb
```

**Para atualizar**, instale o pacote novo por cima, com o mesmo comando.

### Opção B — Via Git

```bash
curl -fsSL https://raw.githubusercontent.com/profjefer/lablivre-jfr/main/gitinstall.sh | bash
```

**Para atualizar**, rode o mesmo comando (ele faz `git pull`). Use uma opção ou a outra:
se a máquina já tem o pacote `.deb`, o instalador via Git avisa e explica como trocar.

Nos dois casos, o LabLivre fica em `/opt/lablivre`, com os comandos `lablivre` (texto) e
`lablivre-gui` (gráfico). Atualizar **nunca** mexe no `lablivre.conf`, no `macs.txt` e
nos logs.

### O `macs.txt` não se perde mais

A cada instalação, atualização ou remoção, o LabLivre guarda uma cópia do `macs.txt`
**fora do `/opt`**, em `/var/backups/lablivre/` (com as 10 versões anteriores) e em
`~/.local/share/lablivre/`. O backup semanal do cron também atualiza a segunda cópia.

Numa instalação do zero (depois de um `apt purge`, de um `rm -rf /opt/lablivre` ou
vindo do scriptlab), se o `macs.txt` estiver vazio, ele é **restaurado sozinho**. A ordem
de busca é: essas cópias, depois `configs/.backups/`, depois
`/opt/scriptlab-jfr/configs/macs-lablivre.txt`. A instalação mostra de onde ele veio.

### Baixar o projeto compactado

O código também está compactado em [`dist/lablivre-4.2.7.tar.gz`](dist/) e nas
[Releases](https://github.com/profjefer/lablivre-jfr/releases). Para gerar o pacote a
partir do código: `bash packaging/build_deb.sh` (saída em `dist/`).

### Depois de instalar
```bash
# 1. OBRIGATÓRIO: cadastre os MACs e nomes das máquinas (veja abaixo)
nano /opt/lablivre/configs/macs.txt

# 2. Configure: dependências, usuário/senha SSH, cron, servidor web
lablivre        # → opção 99

# 3. Mapeie a rede
lablivre        # → opção 1

# 4. Confira se ficou tudo de pé (cron, servidor web, serviços)
lablivre        # → opção 17
```

> **Veio de uma instalação antiga** (scriptlab, `/opt/scriptlab-jfr`…)? Ela pode ter
> deixado um servidor web na porta 8080 e tarefas no cron apontando para a pasta velha.
> Os sintomas são: o portal mostra uma lista de arquivos, os painéis dizem "todas offline"
> e o inventário dá "Error response". A opção **17** detecta e corrige isso.

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
| 6 | **Ligar** o laboratório (Wake-on-LAN): 3 rodadas, broadcast da sub-rede, todas as placas do `macs.txt`; pode esperar e dizer quem não ligou |
| 7 | **Desligar** o laboratório (pula a máquina do professor). **Arma o Wake-on-LAN** de cada máquina antes de desligar |
| 8 | **Manutenção APT** (update/upgrade/instalar pacote) |
| 9 | **Corrigir repositórios** quebrados (vacina APT) |
| 10 | **Diagnosticar conexão SSH**: rede → ping → porta 22 → login → sudo → nome. Diz o que fazer em cada falha (ex.: máquina que não aceita senha) |
| 11 | **Ver auditoria** (`logs/auditoria.jsonl`) |
| 12 | **Configurar chave SSH** (dispensa a senha do SSH) |
| 13 | **Abrir o portal web** (dashboards e inventário) |
| 14 | **Relatório de status** (TXT rápido) |
| 15 | **Limpar Downloads e Lixeira** de todas as máquinas |
| 16 | **Sincronizar horário** (NTP; se não houver NTP, usa a hora do orquestrador) |
| 17 | **Saúde do sistema:** instalação, `macs.txt`, dependências, idade do mapa, servidor web (inclusive o de instalação antiga na porta 8080), cron e serviços. Oferece corrigir |
| 18 | **Preparar Wake-on-LAN** (permanente): ethtool, `wol g`, serviço que rearma no boot, NetworkManager |
| 99 | **Configurações globais** (nome do lab, usuário, senha, pasta de material) |

Os módulos que agem nas máquinas aceitam `--dry-run` (só mostram o que fariam). Para simular tudo: `lablivre --dry-run`.

O menu gráfico (`lablivre-gui`) oferece as mesmas funções. Mapeamento, Modo Prova, horário,
mensagem, ligar, desligar, diagnóstico e inventário usam **exatamente o mesmo motor** do modo
texto: as janelas só mostram o andamento e o resultado.

### Páginas web (sempre por `http://localhost:8080`)

O Firefox do Ubuntu (snap) não abre arquivos de `/opt` por `file://`, então o LabLivre
abre todas as páginas pelo servidor da porta 8080 (`modulos/servidor_web.py`).

**Sempre atuais:** com uma página de estado aberta, a rede é remapeada sozinha sempre que o
mapa passa de 5 minutos. Também há o botão "Atualizar agora". O painel do **Modo Prova tem
botões** (ativar, liberar, reaplicar, situação real), que só aparecem na máquina do professor
ou nos IPs de `LAB_WEB_ADMINS`. A opção 13 mostra o endereço com o IP real
(`http://<ip>:8080`), que serve também quando você acessa por SSH.

| Página | O que mostra |
|---|---|
| `index.html` | Portal com todos os painéis |
| `maquinas.html` | **Tabela única e sempre atual** das máquinas (substitui os antigos `relatorio_*.html` e `status.html`). Avisa quando o mapa está velho |
| `dashboard_*.html` | Operacional, TV, Prova, NetOps, Auditoria |
| `inventario.html` | Hardware (aparece um aviso até a primeira coleta) |
| `mapa_calor.html` | Uso das máquinas ao longo do tempo |

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
├── packaging/              ← geração do .deb (build_deb.sh, preinst/postinst/postrm)
├── dist/                   ← .deb e .tar.gz da versão atual (só no repositório)
└── gitinstall.sh           ← instalar/atualizar pelo Git
```

Fora do `/opt`: `/var/backups/lablivre/` e `~/.local/share/lablivre/` guardam as cópias do
`macs.txt`. O `apt purge` não apaga essas pastas.

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

# Portal web (opcional): IPs que também podem usar os botões do Modo Prova
LAB_WEB_ADMINS="10.158.28.50"
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
Os testes rodam com comandos simulados (SSH, sudo, iptables, systemd…), então não tocam a
rede nem o sistema. São 190 asserções na 4.2.7.

---

## 🔐 Segurança e próximos passos

- [docs/SEGURANCA.md](docs/SEGURANCA.md): senha × chave SSH e cuidados.
- [docs/ROADMAP.md](docs/ROADMAP.md): decisões de escopo (IPv4, `macs.txt` manual) e o plano
  da **4.3**, com `sudo` sem senha restrito aos comandos do LabLivre, para a senha não
  aparecer no `ps` dos alunos.
