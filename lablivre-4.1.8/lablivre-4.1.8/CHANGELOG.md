# Changelog — LabLivre

Todas as mudanças relevantes neste projeto serão documentadas aqui.

O formato segue [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/),
e o projeto adota [Versionamento Semântico](https://semver.org/lang/pt-BR/).

---

## [4.1.8] — 2026-06-18

### Adicionado
- **Limpeza de Downloads e Lixeira** em todas as máquinas online (opção 15 no menu texto, opção 16 no gráfico). Apaga o conteúdo da pasta Downloads e da Lixeira (Trash) do usuário SSH, com confirmação obrigatória antes de executar (é ação destrutiva).
  - Usa `xdg-user-dir DOWNLOAD` para localizar a pasta Downloads correta (lida com idioma/variações, mesma técnica do Desktop).
  - Conta e reporta quantos itens foram apagados por máquina.
  - Preserva a pasta Downloads em si (apenas esvazia o conteúdo).
  - Módulos: `modulos/limpar_downloads.sh` (texto) e `xmodulos/xlimpar_downloads.sh` (gráfico).

---

## [4.1.7] — 2026-06-11

### Corrigido
- **Distribuição entregava no Desktop errado**: máquinas com pasta `Área de trabalho` (t minúsculo — padrão atual do Ubuntu) recebiam o material em `Área de Trabalho` (T maiúsculo — nome antigo), que era criado vazio. Os arquivos chegavam, mas no Desktop "fantasma" que o usuário não via.

### Melhorado
- **CMD_REMOTO usa `xdg-user-dir DESKTOP`** para obter o caminho real do Desktop do usuário (forma oficial do XDG). Fallback inteligente cobre: "Área de trabalho", "Área de Trabalho", "Desktop", "Escritorio", e `$HOME` como último recurso.
- **Antes do envio, consulta uma máquina online** para descobrir o destino real e exibe esse caminho exato tanto na saída texto quanto no popup gráfico final.
- **Pasta temporária do envio de arquivos avulsos** (gráfico) agora tem nome amigável `Arquivos_AAAAMMDD_HHMM/` em vez de `lablivre_envio.XXXXXX`, e permissão 755 (legível).

---

## [4.1.6] — 2026-06-11

Correção crítica na distribuição de material.

### Corrigido
- **Distribuição de material (texto e gráfico) falhava em todas as máquinas**: o `PIPESTATUS` era resetado pela atribuição `$(...)`, deixando `STATUS_SSH` vazio (erro "esperava operador unário"). Agora o código de retorno é embutido na saída via `echo __RC=$?` e extraído com segurança.
- **Comando remoto consumia o stdin duas vezes**: o encadeamento `tar -xf - || tar -xf -` fazia o primeiro tar consumir todo o stream, e o material não era extraído (gráfico "terminava sem erro mas nada chegava"). Agora resolve o destino (`DEST`) numa variável e faz um único `tar -xf -`.
- **`_ssh.sh` não era carregado** no distribuir_material.sh (estava dentro do bloco `if`), deixando `ssh_remote_stdin` indefinida.

### Melhorado
- Mensagem de erro real do SSH agora aparece ao lado de cada `[ERRO]` (não mais silenciada por `2>/dev/null`).
- Popup gráfico e saída texto mostram o **destino** do material: `~/Área de Trabalho/Material_Aulas/`.

---

## [4.1.5] — 2026-06-09

Release de **correções e melhorias** baseado em feedback de uso em produção em múltiplas máquinas.

### Corrigido
- **`xmenu.sh` na raiz**: faltava no tarball anterior; agora é um proxy que delega para `xmodulos/xmenu.sh`
- **`wiki_lablivre.html`**: movido definitivamente para `docs/`, removido da raiz
- **`build_deb.sh`**: substituído `rsync` (nem sempre instalado) por `tar` com excludes; reescrito `postinst` removendo `useradd -r` que causava falha de instalação
- **Permissões `/opt/lablivre/web/`**: provisionar agora aplica `chmod 755` no caminho e `chmod 644` nos arquivos, garantindo que o servidor HTTP do `lablivre-web.service` consiga ler
- **Teste de conectividade**: máquina rodando o script era marcada como `OFFLINE` (loopback não respondendo ping); agora detecta `ESTA MÁQUINA` ou IP local e considera ONLINE sem ping
- **Inventário gráfico**: popup final exibia 0 sucessos/falhas; variáveis perdidas no subshell (pipe para Zenity progress); corrigido escrevendo stats em arquivo
- **`api.json` não atualizando**: `atualizar_ips.sh` agora gera api.json verbosamente e valida o resultado; `gerar_estado.sh` verifica permissão de escrita em `web/` antes de gravar
- **Dependências incompletas na primeira execução**: criado `modulos/_instalar_deps.sh` idempotente que detecta o que falta e instala (nmap, sshpass, zenity, wakeonlan, ethtool, dmidecode, netcat-openbsd, jq, bc, python3, avahi-utils, ntpdate)
- **Cabeçalho do xmenu**: barras de progresso (`█████`) estouravam a largura da caixa; reduzidas para tamanho fixo de 30 caracteres

### Adicionado
- **`modulos/abrir_portal_web.sh`**: novo módulo que sobe o servidor web se necessário e abre `http://localhost:8080/` no navegador
- **Opção 13 no menu texto**: "🌐 Abrir Portal Web"
- **Opções 24, 25, 26 no menu gráfico**: atalhos diretos para Auditoria, Inventário HTML e Mapa de Calor
- **`modulos/inventario_para_html.sh`**: converte `logs/inventario_lab.txt` em HTML estilizado para a web
- **`web/inventario.html`** (gerado): relatório de hardware com identidade visual do LabLivre (cards de estatísticas + tabela detalhada)
- **`modulos/gerar_mapa_calor.sh`**: agrega `logs/historico_maquinas.jsonl` por MAC e produz `web/mapa_calor.json`
- **`web/mapa_calor.html`**: novo dashboard com **mapa de calor** mostrando quais máquinas são mais usadas (5 níveis de intensidade: Hot, Warm, Mild, Cold, Frozen), ordenado por frequência
- **`docs/snapshot_diario.md`**: documentação completa do `snapshot_diario.sh` — o que faz, quando roda, como consultar
- **Portal `index.html`** com cards adicionais para Inventário e Mapa de Calor

### Modificado
- **`configurar_lab.sh`** agora usa `_instalar_deps.sh` (helper centralizado)
- **`gitinstall.sh`** simplificado: instala apenas `git` (resto é delegado ao `configurar_lab.sh`)
- **`atualizar_ips.sh`** agora gera os 3 JSONs ao final: `api.json`, `auditoria.json`, `mapa_calor.json`
- **Cron horário** atualizado para incluir geração do mapa de calor

### Internas
- **Pacote .deb agora em versão 4.1.5** com dependências corretas (`netcat-openbsd`, `jq`, `bc` adicionados; `ntpdate` movido para opcional)

---

## [4.1.0] — 2026-06-02

Release focado em **segurança**.

### Adicionado
- **Wrapper SSH unificado** (`modulos/_ssh.sh`) com `ssh_remote`, `ssh_remote_stdin`, `scp_remote`
- **Autenticação por chave SSH** opcional (`LAB_AUTH_MODE="chave"`)
- **`configurar_chave_ssh.sh`**: gera Ed25519 e distribui via `ssh-copy-id` para todas as máquinas online (opção 12 do menu)
- **Detecção automática** de modo: se `configs/lablivre_key` existe, usa chave por padrão; senão usa senha
- **Indicador visual no menu**: cabeçalho mostra modo de auth atual (🔐 chave / 🔓 senha)
- **`docs/SEGURANCA.md`** explicando modelo de autenticação e procedimento de migração
- **Permissões automáticas**: `chmod 600` no conf e chave, `chmod 700` em configs/ e logs/
- **9 novos testes** para o wrapper SSH e modo dry-run

### Modificado
- **Todos os scripts críticos** agora usam `ssh_remote()` em vez de `sshpass` direto
  - Sem `sshpass` em runtime quando em modo chave → senha não aparece em `ps`
- **Modo dry-run** agora sobrescreve as funções do `_ssh.sh` para apenas exibir comandos
- **`_provisionar.sh`** aplica permissões restritivas automaticamente

### Segurança
- Senha SSH não é mais necessária em runtime após migração para chave
- Chave permanece somente leitura pelo dono (`chmod 600`)
- Pasta `configs/` inteira fica com `chmod 700`
- Fallback automático para senha em máquinas que ainda não receberam a chave
- Auditoria de quem fez o quê continua funcionando independente do modo

---

## [4.0.0] — 2026-06-02

Versão de reescrita arquitetural. Quebras de compatibilidade em relação à v3.x.

### Adicionado
- **API JSON central**: `web/api.json` como fonte única de verdade para dashboards
- **Auditoria estruturada**: `logs/auditoria.jsonl` com função `log_acao` comum
- **4 dashboards web em tempo real** com auto-refresh de 30s
- **Portal `web/index.html`** com cards para todos os dashboards
- **Dashboard de auditoria**: timeline filtrável por tipo de ação
- **Servidor web via systemd** (`lablivre-web.service`) — mais robusto que `@reboot`
- **Suíte de testes** em `tests/run_tests.sh` (47 asserções)
- **Backup automático do macs.txt** (semanal + preventivo no configurar_lab)
- **Detecção de MACs desconhecidos** na rede
- **Histórico diário** em `logs/historico.jsonl` (snapshot 23h59)
- **Aviso fullscreen Zenity** na tela do aluno ao ativar modo prova
- **Visualizador de auditoria** no menu texto (opção 11)
- **Modo dry-run** nos scripts destrutivos (flag `-n` ou `DRYRUN=1`)
- **i18n leve**: strings em `configs/i18n/pt_BR.conf`
- **Exportação para meta-dashboard** (opt-in via conf)
- **Snapshot diário** automático via cron
- **Scripts faltantes**: `xcorrigir_quebrados.sh`, `xdiagnosticar_ssh.sh`
- **`_provisionar.sh`**: lógica única de provisionamento usada por modo texto e gráfico
- **`gerar_estado.sh`** chamado automaticamente após `atualizar_ips.sh` no fluxo manual

### Modificado
- **Conf agora em `configs/lablivre.conf`** (antes era na raiz)
- **MACs agora em `configs/macs.txt`** (antes era na raiz)
- **Detecção via parse direto do nmap** em vez de `ip neigh` (mais confiável)
- **Loops com `< <(tail)`** em vez de `tail | while` (evita SSH consumir stdin)
- **Cron centralizado** com marcador `# LabLivre` para evitar duplicação
- **`LAB_PASTA_MATERIAL`** configurável (antes era hardcoded `envia_material`)
- **`LAB_NOME`** configurável e exibido no menu (antes era "UFPR Palotina" fixo)
- **Flag persistente do modo prova** em `logs/modo_prova.status`
- **Detecção da própria máquina via `$resto`** em vez de `$MEU_IP`
- **`tail -n +3`** no xmenu (antes `+4`, perdia primeira máquina silenciosamente)

### Corrigido
- SSH consumindo stdin do loop `while read` (gerava só primeira máquina processada)
- `xatualizar_ips.sh` que não funcionava em redes onde o kernel não populava ARP
- Bug de duplicação do cron entre modo texto e gráfico
- Senha SSH exposta em texto puro no payload (heredoc com aspas simples)

### Segurança
- `chmod 600` automático em `configs/lablivre.conf`
- Backup preventivo do `macs.txt` antes de qualquer alteração
- Detecção e log de MACs não cadastrados (intrusos potenciais)

---

## [3.0.0] — versão anterior

- Modo texto + Modo gráfico (Zenity) funcional
- Wake-on-LAN, shutdown remoto, modo prova, distribuir material
- Dashboards HTML estáticos
- Servidor web via `python3 -m http.server` em `@reboot`

---

## Política de versionamento

- **MAJOR** (X.0.0): mudanças incompatíveis (renomear arquivo de config, mudar API JSON, etc)
- **MINOR** (4.X.0): novas funcionalidades sem quebrar compatibilidade
- **PATCH** (4.0.X): correções de bugs e ajustes pontuais

Para atualizar:
```bash
cd /opt/lablivre
git pull
bash configurar_lab.sh   # reaplica permissões e crons
bash tests/run_tests.sh  # garante que está tudo OK
```
