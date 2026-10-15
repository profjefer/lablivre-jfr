# Escopo e próximos passos — LabLivre

Este documento registra **decisões de escopo** e o que está planejado.
Ele vale mais que qualquer texto antigo (artigo, wiki, apresentação) que diga o contrário.

---

## Decisões de escopo (valem desde a 4.2.1)

### 1. Somente IPv4
O LabLivre trabalha **apenas com IPv4**: mapeamento, SSH, Wake-on-LAN e Modo Prova.

- O Modo Prova bloqueia só o tráfego **IPv4** (`iptables`). Ele **não** mexe em `ip6tables`.
- Se a rede do laboratório passar a entregar IPv6 com rota para a internet, o
  Modo Prova **não bloqueia** esse tráfego. Para conferir numa máquina de aluno:

  ```bash
  ip -6 route show default     # vazio = sem IPv6 para fora (bloqueio é completo)
  ```

  Se aparecer uma rota, a saída mais simples é desativar o IPv6 nas máquinas
  dos alunos ou pedir à TI que não o entregue na VLAN do laboratório.

### 2. O `configs/macs.txt` é fornecido pelo usuário
O arquivo com os **MACs e nomes** das máquinas é o ponto de partida obrigatório.
**O LabLivre não gera esse arquivo sozinho.** Nos testes reais, a descoberta automática
nunca foi confiável o bastante: máquinas desligadas não aparecem, celulares e
roteador aparecem, e os nomes precisam ser definidos por uma pessoa.

- Como obter o MAC de uma máquina: `ip link` (a placa `en…`/`eth…` é o cabo, a `wl…` é o wifi).
- A partir do `macs.txt`, todo o resto é automático: IPs (opção 1), Wake-on-LAN,
  dashboards, histórico e inventário.
- O mapeamento **ajuda** a manter o arquivo: lista em `logs/macs_desconhecidos.log`
  os MACs que respondem na rede mas não estão cadastrados.
- Geração automática do `macs.txt` fica como **experimento futuro**, sem prazo.

---

## Próximo passo: versão 4.3 — sudo sem senha nas máquinas dos alunos

**Problema.** Vários módulos ainda mandam a senha para o `sudo` remoto dentro do
próprio comando (`echo 'senha' | sudo -S ...`). Enquanto o comando roda, um aluno
logado consegue ver essa senha com `ps aux`. Isso acontece **mesmo no modo chave
SSH**, porque a chave dispensa a senha do SSH mas não a do `sudo`.

**O que a 4.2.1 já resolveu.** Mensagem, Modo Prova, sincronização de horário e
inventário mandam a senha pelo **stdin** do SSH. Ela não aparece mais no `ps`.
Ainda usam o formato antigo: desligar (manual e agendado), manutenção APT,
vacina APT e os xmodulos.

**Plano para a 4.3.**
1. Nova opção no menu, "Preparar máquinas", que instala uma vez em cada aluno o arquivo
   `/etc/sudoers.d/lablivre` (validado com `visudo -c`), liberando **sem senha e só para
   o usuário do LabLivre** apenas os comandos necessários:
   `iptables`, `shutdown`, `apt-get`, `dpkg`, `dmidecode`, `ethtool`, `timedatectl`, `date`,
   `systemctl` (unidades `lablivre-prova*`), `install`/`rm` dos arquivos do Modo Prova.
2. Todos os módulos passam a usar `sudo -n` (sem senha). O plano B pelo stdin só vale
   para máquinas ainda não preparadas.
3. Com chave SSH + sudoers, a senha deixa de ser usada na operação normal e pode
   sair do `lablivre.conf`.
4. Testes automatizados para o arquivo sudoers gerado e para o plano B.

---

## Depois da 4.3

- **xmodulos (fase 2):** transformar `xenviar_mensagem`, `xdistribuir_material`,
  `xdesligar_labold`, `xmanutencao_sistema` e os demais em janelas por cima dos
  módulos de texto, como já foi feito com `xatualizar_ips`, `xmodo_prova` e
  `xsincronizar_horario`. Uma lógica só, duas interfaces.
- **Meta-dashboard** consolidando vários laboratórios (exportação já existe, *opt-in*).
- **Imagem de disco** (PXE + FOG Project), depois de validar que o PXE funciona na rede da UFPR.
- Integração com calendário de reservas e *bot* de consulta (Telegram ou similar).
