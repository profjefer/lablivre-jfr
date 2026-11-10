# Changelog — LabLivre

Todas as mudanças relevantes neste projeto serão documentadas aqui.

O formato segue [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/),
e o projeto adota [Versionamento Semântico](https://semver.org/lang/pt-BR/).

---

## [4.2.7] — 2026-11-10

Instalação e repositório: o `macs.txt` não se perde mais e a instalação via Git voltou a funcionar.

### Corrigido
- **Toda atualização do `.deb` apagava o cron, o serviço web e os serviços `wol-*`.** Numa atualização, o dpkg chama o `postrm` da versão antiga com o argumento `upgrade`, e o nosso removia tudo em qualquer chamada. Depois de atualizar, o mapeamento de hora em hora, o desligamento das 23h, o horário das 7h, o snapshot e o backup paravam, e o portal ficava sem serviço. Visto no lab na atualização 4.2.5 → 4.2.6. Agora:
  - o `postrm` só remove isso num `remove` ou `purge`;
  - para atualizações a partir de versões antigas, cujo `postrm` ainda apaga tudo: o `preinst` guarda o serviço web, os `wol-*` e as tarefas do cron em `/var/backups/lablivre/estado/`, e o `postinst` recoloca o que tiver sumido e avisa;
  - o `postinst` libera a porta 8080 antes de reiniciar o serviço, porque um servidor avulso aberto pelo menu impedia o serviço de subir.
- **O `macs.txt` sumia ao reinstalar do zero** (`apt purge`, `rm -rf /opt/lablivre`, máquina nova). Era preciso copiá-lo de volta à mão do `/opt/scriptlab-jfr`. Agora o arquivo é guardado fora do `/opt` e volta sozinho (ver *Adicionado*).
- **Instalação via Git quebrada**: o `curl .../gitinstall.sh` dava 404, porque o código estava numa subpasta do repositório. Com a subpasta, os comandos `lablivre` e `lablivre-gui` também apontavam para arquivos que não existiam. O código agora fica na raiz.
- **`gitinstall.sh` atualizando**: rodava `sudo git pull` numa pasta do usuário, e o git recusava (*dubious ownership*). O git agora roda como o operador. Se a máquina já tem o pacote `.deb`, o instalador explica como trocar, em vez de misturar os dois.
- A instalação (`postinst`, opção 99) não muda mais a data do `macs.txt` com `touch`.

### Adicionado
- **`modulos/_preservar_macs.sh`** (`salvar` / `restaurar`):
  - **salvar**: guarda o `macs.txt` em `/var/backups/lablivre/`, com as 10 versões anteriores, e em `~/.local/share/lablivre/`. Nunca troca uma cópia boa por um arquivo vazio.
  - **restaurar**: se o `macs.txt` estiver vazio ou só com comentários, traz a primeira cópia que tiver MACs. A ordem é: as cópias acima, depois `configs/.backups/`, depois o `/opt/scriptlab-jfr/configs/macs-lablivre.txt` (e o `macs.txt` de lá). O arquivo anterior fica em `macs.txt.antes_de_restaurar`.
- O pacote ganhou um **`preinst`**, que salva antes de instalar ou atualizar. O `postinst` restaura e salva, e o `postrm` salva antes do `remove` ou do `purge`. O `gitinstall.sh` também restaura e salva, e o backup semanal (cron) atualiza a cópia em `~/.local/share/lablivre/`.
- **Repositório reorganizado**: código na raiz, e o `.deb` e o projeto compactado (`.tar.gz`) da versão atual em `dist/`. O `packaging/build_deb.sh` gera os dois em `dist/`.
- README: nova descrição do projeto, instalação e atualização pelas duas opções e o funcionamento das cópias do `macs.txt`.
- Testes: 195 asserções.

---

## [4.2.6] — 2026-11-03

### Corrigido
- **A barra de progresso das janelas mostrava `&gt;`**: o texto era escapado, mas o zenity mostra a barra sem interpretar. Agora vai cru (sem o `>>` do começo).
- **Limpar Downloads (gráfico) não mostrava o resultado**: virou janela por cima do motor de texto. Mostra quantas limparam, quantas falharam, os itens apagados e o nome das que falharam, com o motivo.

### Adicionado
- **Opção 18 — Preparar Wake-on-LAN** (`modulos/preparar_wol.sh`, também no menu gráfico), para as máquinas que não ligam pela rede. Com elas ligadas, em cada uma:
  - instala o `ethtool` se faltar;
  - arma `wol g` nas placas cabeadas;
  - cria o serviço `lablivre-wol`, que rearma a cada boot;
  - grava `wake-on-lan magic` no NetworkManager.

  Avisa quando a placa não suporta WoL; nesse caso o problema é a BIOS.
- **Diagnóstico SSH mostra o Wake-on-LAN** de cada máquina (ok, permanente, desarmado ou sem ethtool) e indica a opção 18.
- Desligar e Ligar apontam para a opção 18 quando o WoL não está garantido.
- Testes: 173 asserções.

### Testes
- **Dois testes dependiam da máquina onde rodavam** e falhavam em orquestradores reais:
  - *relógio 10 min atrasado* usava o `timedatectl` de verdade; com o NTP do orquestrador sincronizado, o ajuste não acontecia. Agora as máquinas simuladas têm `timedatectl` falso ("não sincronizado").
  - *preparar WoL sem ethtool* achava o `/usr/sbin/ethtool` real. O script remoto agora procura o ethtool por `acha_ethtool`, com os caminhos extras em `LAB_ETHTOOL_EXTRA` (o teste usa vazio).

---

## [4.2.5] — 2026-11-03

Ajustes do terceiro teste de campo (portal e mapeamento).

### Corrigido
- **`api.json` inválido quando o nome do laboratório tem aspas** (todas as páginas ficavam sem dados). O nome agora é escapado.
- **Portal sem botão de voltar** no Operacional e nos outros painéis: toda página ganhou "← Portal" no canto inferior esquerdo (no TV Mode fica discreto e aparece ao passar o mouse).

### Adicionado
- **Fontes maiores** em todos os painéis: NetOps +35%; Operacional, Máquinas, Auditoria, Mapa de Calor, Prova e Inventário +20–25%; Portal +15%. O TV Mode e os números grandes ficaram como estavam.
- **Endereço do portal sempre à vista**: no cabeçalho do menu texto e do gráfico, e no fim do mapeamento (`Portal atualizado: http://<ip>:8080/maquinas.html`).
- **Máquina com duas placas**: quando o cabo não responde e a 2ª placa (wifi) sim, o mapeamento diz, e a página Máquinas mostra "online pela 2ª placa (wifi)". O `ips_atuais.txt` grava `(via <mac>)`. O MAC principal (o do WoL) continua o mesmo.
- **Dispositivos desconhecidos** aparecem com o fabricante (arp-scan) e com o roteador/gateway identificado, mais uma dica de como descobrir de quem é.
- **Painel do Modo Prova fora da máquina do professor**: em vez de esconder os botões sem explicação, mostra o IP do computador e a linha `LAB_WEB_ADMINS` para liberá-lo.
- Testes: 163 asserções.

---

## [4.2.4] — 2026-10-28

Ajustes do teste remoto (por SSH).

### Corrigido
- **Diagnóstico SSH (opção 10)**: máquinas que funcionam, mas cujo hostname é diferente do nome no `macs.txt`, apareciam com ❓ vermelho, como se fosse erro. Agora aparecem com ✅ e um ℹ️ azul com o hostname. O resumo explica que hostname repetido é típico de imagem clonada e que o LabLivre usa o MAC.
- **Opção 13 e mensagens do sistema mostravam `localhost`**: agora mostram o endereço com o IP real (`http://<ip>:8080/`), que funciona de outro computador. Numa sessão SSH sem tela, a opção só mostra o endereço, sem tentar abrir navegador.
- **Menu gráfico por SSH (`ssh -X`) poluía o terminal** com avisos do GTK e do zenity 4 (`--window-icon foi descontinuada`, `GtkDialog mapped without a transient parent`). A opção descontinuada saiu, e o ruído conhecido é filtrado no menu e em todos os módulos gráficos. Erros de verdade continuam aparecendo.

### Adicionado
- `LAB_WEB_ADMINS` no `lablivre.conf`: IPs que também podem usar os botões do Modo Prova no portal (ex.: o notebook do professor). Não precisa reiniciar o serviço.
- `url_portal` em `_comum.sh`.
- Testes: 158 asserções.

---

## [4.2.3] — 2026-10-28

Ajustes do segundo teste de campo (portal web e Modo Prova).

### Corrigido
- **O portal mostrava números velhos** (ex.: 15 online quando já tinham desligado). As páginas só liam o `api.json` do último cron, que podia ter até 1 h. Agora, com qualquer página de estado aberta (portal, Máquinas, Operacional, TV, NetOps, Prova), a rede é **remapeada sozinha quando o mapa passa de 5 min**. Enquanto o mapa novo não chega, os números do portal aparecem apagados. Há também um botão **"Atualizar agora"**.
- **Inventário dizia só `[ERRO]`**: agora diz o motivo (senha recusada / sem conexão SSH) e lista no fim as máquinas sem coleta.

### Adicionado
- **Botões no painel do Modo Prova**:
  - ativar (com duração de 1 a 8 h), liberar, reaplicar e situação real;
  - mostram a saída ao vivo;
  - só aparecem na máquina do professor; quem abre o portal de outra máquina só vê o painel;
  - o painel mostra o horário do fim automático e quantas máquinas estão bloqueadas.
- **`modulos/servidor_web.py`** substitui o `python3 -m http.server`. Serve a pasta `web/` e uma pequena API:
  - `GET /api/info`, `GET /api/tarefa`;
  - `POST /api/atualizar`, `POST /api/prova`.

  Ele roda só scripts fixos com argumentos validados, uma tarefa por vez, e exige o cabeçalho `X-LabLivre`. O Modo Prova só aceita pedidos da própria máquina.
- `web/lablivre.js`, comum às páginas.
- O mapeamento usa uma trava (`flock`): cron, menu e portal não mapeiam ao mesmo tempo.
- O `api.json` traz `modo_prova.expira`, `bloqueadas` e `pendentes`.
- Ao atualizar o pacote, o `postinst` troca o serviço `lablivre-web` para o servidor novo e o reinicia. A opção 17 avisa se o serviço ainda é o antigo.
- Testes: 156 asserções.

---

## [4.2.2] — 2026-10-27

Correções a partir do teste de campo no laboratório (michelangelo, 20 máquinas).

### Corrigido
- **Portal, painéis e inventário "não funcionavam"** (lista de arquivos, "todas offline", "Error response"). A causa era um servidor web de uma instalação antiga (`/opt/scriptlab-jfr`) segurando a porta 8080. Com isso, o serviço `lablivre-web` ficava em loop de reinício. Agora:
  - a opção 99 (`_provisionar.sh`) libera a porta e remove tarefas antigas do cron;
  - um arquivo-marcador (`web/lablivre-raiz.txt`) mostra se quem responde na porta é ESTA instalação;
  - toda página é aberta por `abrir_pagina_web`, que recusa servidor de outra pasta e explica o que fazer.
- **Firefox não abria o HTML por `file://`** (snap não lê `/opt`). Nenhuma página é mais aberta por `file://`.
- **Três arquivos de status diferentes** (`relatorio_*.html` a cada clique, `status.html`, `api.json`): os dois primeiros saíram. Agora há uma página só, `maquinas.html`, sempre atual.
- **"Teste de Conexão" (gráfico) mostrava todas sem conexão**: testava IPs do mapa velho, sem pingar quem estava OFFLINE. Agora remapeia antes e testa ping e porta 22. Ping bloqueado com SSH aberto conta como máquina OK.
- **Pop-up dizia "12 receberam"** com só 2 alunos logados: o módulo gráfico contava só o retorno do SSH. Agora ele usa o motor do modo texto, e a tela de login (gdm) não conta como sessão. O resumo separa *entregue / sem aluno logado / parcial / erro*.
- **"Visualizar Logs" só abria a pasta**: agora lista os relatórios do mais novo para o mais antigo e abre o escolhido.
- **Diagnóstico SSH**:
  - "sem ping" não é mais "sem conexão";
  - quando o login falha, diz se a máquina **não aceita senha** (`PasswordAuthentication no`), se a senha está errada ou se o sshd derruba a conexão (fail2ban/AllowUsers). Mostra o comando para resolver;
  - confere o sudo e se o nome da máquina bate com o `macs.txt`.
- **Desligar** passava a senha na linha de comando (`echo 'senha' | sudo -S`, visível no `ps`). Agora usa `modulos/remoto/desligar.sh`, com a senha pelo stdin.

### Adicionado
- **Opção 17 — Saúde do sistema** (`modulos/saude_sistema.sh`, também no menu gráfico). Confere:
  - dono da pasta, conf, `macs.txt` (MAC repetido) e dependências;
  - idade do mapa;
  - servidor web (PID e pasta de quem ocupa a 8080), serviço `lablivre-web`, outros serviços ou inícios automáticos que sobem `http.server`;
  - cron (tarefas faltando, tarefas de outra pasta, última execução);
  - WoL e Modo Prova.

  Com `--corrigir`, conserta o que der.
- **Ligar laboratório**:
  - usa o `macs.txt` (não depende de mapear antes) e todas as placas;
  - 3 rodadas de pacotes, para `255.255.255.255` e para o broadcast da sub-rede;
  - pode ligar só algumas máquinas (`ligar_labold.sh donatelo thor`);
  - pode esperar, remapear e listar quem não ligou, com as causas prováveis (energia, BIOS/ErP, WoL desarmado).
- **Desligar arma o Wake-on-LAN** (`ethtool -s <placa> wol g`) em cada máquina antes de desligar e avisa quais ficaram sem. O cron das 23h faz o mesmo.
- `web/maquinas.html` (busca, filtro e ordenação; aviso de mapa velho) e card "Máquinas" no portal.
- Página-aviso `inventario.html` até a primeira coleta (em vez de 404).
- `modulos/testar_conexao.sh`, `modulos/remoto/checar.sh`, `modulos/remoto/desligar.sh`.
- `xmodulos/_xmotor.sh`: janelas zenity por cima dos motores do modo texto. Usado pelos módulos gráficos de mensagem, ligar, desligar, diagnóstico e inventário.
- Testes: 144 asserções (eram 116).

---

## [4.2.1] — 2026-10-14

Versão "completa": tudo o que a documentação e o artigo descrevem, funcionando e testado.

### Corrigido
- **Modo Prova**:
  - **reiniciar a máquina derrubava o bloqueio** (bastava o aluno reiniciar). Agora um serviço systemd (`lablivre-prova`) reaplica no boot;
  - **apagava o firewall da máquina** (`iptables -F OUTPUT` + política DROP). Agora usa cadeia própria `LABLIVRE_PROVA`: rede liberada → `RETURN`, resto → `REJECT`. As regras da 4.2.0 são limpas sozinhas;
  - **o aviso em tela não aparecia** (`DISPLAY=:0`). Agora usa o mesmo mecanismo das mensagens (Wayland/X11);
  - **o `[BLOQUEADO]` não garantia nada**: refletia só o último comando. Agora é conferido com `iptables -C` em cada máquina;
  - **quem ligava depois da ativação ficava com internet**. Agora há a opção "Reaplicar", e o cron de hora em hora reaplica sozinho.
- **Sincronização das 7h nunca rodava**: o cron chamava um módulo gráfico, e sem tela o zenity derrubava o laço. Criado `modulos/sincronizar_horario.sh` (texto), usado pelo cron e pela nova opção 16 do menu.
- **Auditoria e dry-run perdidos na 4.2.0**: material e mensagem voltaram a registrar em `auditoria.jsonl`. Todos os módulos que agem nas máquinas aceitam `--dry-run`.
- **Inventário**:
  - a senha do sudo ia na linha de comando remota (aparecia no `ps` do aluno). Agora vai pelo stdin;
  - o módulo texto não coletava o que a documentação promete.
- **`sudo` dos scripts remotos** não depende mais do cache do sudo, que pode não valer numa sessão SSH sem terminal. A senha vai pelo stdin a cada comando.

### Adicionado
- **Modo Prova**:
  - validade máxima: o bloqueio se desfaz sozinho, mesmo com a máquina desligada ou esquecida;
  - liberação pendente: as máquinas desligadas na hora de liberar são liberadas quando voltam;
  - opção "Ver situação real";
  - linha de comando: `ativar [HORAS]`, `liberar`, `status`, `reaplicar`;
  - configuração `LAB_PROVA_REDES` e `LAB_PROVA_HORAS`.
- **Horário**: se o NTP não funcionar (bloqueado na rede ou durante a prova), o relógio do aluno é acertado pela hora do orquestrador. O relatório mostra a diferença em segundos de cada máquina.
- **Inventário**: série (patrimônio), fabricante e modelo, núcleos e carga, RAM em uso, % de disco, status do Wake-on-LAN, dispositivos USB, versões de Python e Node, uptime. Tudo também no `web/inventario.html`.
- **`modulos/_comum.sh`**: `rodar_remoto`, `status_remoto`, `erro_ssh`, `lab_dryrun`.
- **`modulos/remoto/`**: `modo_prova.sh` e `sincronizar_horario.sh`.
- **Testes**: 116 asserções (eram 67) com comandos simulados (SSH, sudo, iptables, systemd, arp-scan…). Cobrem:
  - base comum;
  - mapeamento: cabo + wifi, varredura vazia, sem arp-scan;
  - mensagem com aspas e Desktop em português e inglês;
  - Modo Prova inteiro: ativar, reboot, liberar, pendentes, validade, sudo errado, dry-run;
  - horário.
- **Documentação**:
  - `docs/MODO_PROVA.md`;
  - `docs/ROADMAP.md`, com as decisões de escopo (somente IPv4; `macs.txt` fornecido pelo usuário, sem geração automática) e o plano da 4.3 (sudoers);
  - README reescrito, com todas as opções do menu e as tarefas automáticas.

### Modificado
- **Telas gráficas** `xmodo_prova.sh` e `xsincronizar_horario.sh`: viraram janelas por cima dos motores de texto.

### Próximo passo (4.3)
- `sudo` sem senha restrito aos comandos do LabLivre (`/etc/sudoers.d/lablivre`) e fim do `echo senha | sudo -S` nos módulos restantes. Ver `docs/ROADMAP.md`.

---

## [4.2.0] — 2026-10-14

Base: 4.1.8. Corrige o mapeamento de rede, a mensagem pop-up e o desligamento agendado.

### Corrigido
- **Mapeamento de rede (opção 1) marcava todas as máquinas como OFFLINE**, sem aviso, quando o `sudo` local falhava ou o nmap não estava instalado. O erro era engolido por `2>/dev/null`. Isso derrubava junto o painel do xmenu, o "pingar todas" e a opção 10.
- **Pop-up de mensagem (opção 5) não aparecia**: só definia `DISPLAY=:0`, o que não basta na sessão Wayland do Ubuntu 24.04. Agora o script remoto copia `WAYLAND_DISPLAY`, `XAUTHORITY`, `DBUS_SESSION_BUS_ADDRESS` e `DISPLAY` da sessão gráfica aberta. Funciona também com a tela logada por outro usuário, via sudo.
- **Mensagem com aspas** quebrava o comando remoto. Agora vai em base64, e `& < >` aparecem corretamente no pop-up (o `&` era interpretado pelo bash 5.2).
- **Desligamento das 23h (`desligar_agendado.sh`) não funcionava**: rodava de dentro de `modulos/`, não achava o conf nem o `ips_atuais.txt` e caía na senha padrão `ufpr`/`UFPR`.
- **Opção 99 (texto e gráfico) sobrescrevia o `lablivre.conf` inteiro** e apagava o `LAB_AUTH_MODE="chave"` gravado pela opção 12. Agora grava variável por variável.
- **Senha padrão `ufpr`/`UFPR` removida de todos os módulos**: sem conf, o módulo para com uma mensagem clara.
- **Primeira configuração aceitava senha vazia**, que virava `ufpr1234` sem aviso.

### Adicionado
- **`modulos/_comum.sh`**: `carregar_conf`, `salvar_conf_var`, `exigir_ips` e `para_cada_maquina`. O laço lê pelo descritor 3, então o stdin fica livre para tar-pipe e `read`. Ele carrega o `_ssh.sh`.
- **`modulos/remoto/`**: scripts que rodam na máquina do aluno, em arquivos próprios e testáveis:
  - `mostrar_mensagem.sh`;
  - `receber_material.sh`.
- **Novo `atualizar_ips.sh`**:
  - varredura em cascata: arp-scan → nmap → ping + ARP (funciona até sem root);
  - testa o sudo antes e, no terminal, pede a senha local se a `LAB_SENHA` não servir;
  - se ninguém responder (nem o roteador), mantém o `ips_atuais.txt` anterior;
  - reconhece o orquestrador pelo MAC;
  - valida o `macs.txt`: MAC inválido, duplicado, nome duplicado;
  - continua listando os MACs desconhecidos e regenerando os JSON da web.
- **Várias placas por máquina** no `macs.txt` (cabo + wifi): basta repetir o nome. A 1ª linha é a principal e é usada no Wake-on-LAN.
- **Mensagem**:
  - opção 3, pop-up e terminal juntos;
  - motivo da falha em cada máquina: ninguém logado na tela, zenity ausente, pop-up não abriu, senha recusada, sem conexão;
  - relatório em `logs/relatorio_mensagens.txt`.
- **Material**:
  - aceita TAB, arrastar e soltar (tira as aspas) e `~`;
  - mostra tamanho, arquivos e máquinas, e pede confirmação;
  - recusa pasta vazia;
  - pasta padrão: envia o conteúdo;
  - outra pasta: chega com o próprio nome;
  - o `[OK]` vem do código real do `tar` no aluno.
- **`arp-scan`** nas dependências (`_instalar_deps.sh` e `.deb`).

### Modificado
- **`xatualizar_ips.sh`** usa o mesmo motor do modo texto (janela de progresso + resultado). Texto e gráfico geram sempre o mesmo `ips_atuais.txt`.

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
