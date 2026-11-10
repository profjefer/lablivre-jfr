# Modo Prova — como funciona (4.2.1)

Bloqueia a **internet (IPv4)** das máquinas dos alunos e mantém a **rede do campus**
funcionando. Menu texto: opção **3**. Menu gráfico: "Modo Prova".

| Opção | O que faz |
|---|---|
| 1 — Ativar | Bloqueia todas as máquinas online e mostra o aviso na tela dos alunos |
| 2 — Liberar | Remove o bloqueio e avisa que a prova acabou |
| 3 — Situação real | Pergunta a cada máquina se o bloqueio está ativo de verdade |
| 4 — Reaplicar | Bloqueia as máquinas que foram ligadas depois da ativação |

Também por linha de comando (útil no cron ou em scripts):
```bash
bash modulos/modo_prova.sh ativar 3     # 3 horas de validade máxima
bash modulos/modo_prova.sh liberar
bash modulos/modo_prova.sh status
bash modulos/modo_prova.sh ativar 1 --dry-run   # só mostra o que faria
```

## O que acontece em cada máquina

1. **Cadeia própria no firewall.** É criada a cadeia `LABLIVRE_PROVA`, com um salto no
   topo do `OUTPUT`:
   - destino em rede liberada → `RETURN` (segue para o firewall que já existir, como o ufw);
   - todo o resto → `REJECT` (o navegador mostra erro na hora, sem ficar carregando).

   A política do `OUTPUT` não muda e nada é apagado com `iptables -F`. Liberar é só remover a cadeia.
2. **Persistente no boot.** É instalado o serviço `lablivre-prova.service`, que reaplica o
   bloqueio antes da rede subir. **Reiniciar a máquina não derruba a prova.**
3. **Validade máxima.** Ao ativar, o professor escolhe a duração (padrão: 4 h).
   - Passado esse tempo, o bloqueio se desfaz sozinho (timer do systemd).
   - Se a máquina estiver desligada e for ligada depois do prazo, o serviço se desativa sozinho.
   - **Uma máquina esquecida nunca fica bloqueada para sempre.**
4. **Aviso na tela** do aluno, que funciona em Wayland e X11.

## Máquinas que ligam depois ou desligam no meio

- **Ligou depois da ativação:** a opção 4 (Reaplicar) bloqueia. O cron de hora em hora
  (mapeamento de rede) também reaplica sozinho enquanto a prova estiver ativa.
- **Estava desligada na liberação:** fica registrada como **pendente**
  (`logs/modo_prova.pendentes`) e é liberada sozinha quando volta a ligar (cron de hora em hora).
  De qualquer forma, ela também se libera ao fim da validade.

## Configuração (`configs/lablivre.conf`)

```bash
# Redes IPv4 que continuam acessíveis durante a prova (separadas por espaço).
# O IP do orquestrador é sempre liberado automaticamente.
LAB_PROVA_REDES="10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 200.236.0.0/16"

# Validade padrão do bloqueio, em horas (1 a 24)
LAB_PROVA_HORAS="4"
```

> **DNS:** se as máquinas usam um DNS externo (ex.: 8.8.8.8), durante a prova nenhum nome
> será resolvido, nem os do campus. Com o DNS da UFPR (rede interna), tudo funciona.

## Limitações conhecidas

- **Somente IPv4** (decisão de escopo, ver `docs/ROADMAP.md`). Se a rede entregar IPv6 com
  rota para fora, esse tráfego não é bloqueado. Para conferir: `ip -6 route show default`.
- Um aluno com acesso de **administrador (sudo)** na máquina consegue remover o bloqueio.
  O usuário dos alunos não deve ter sudo.

## Conferir à mão numa máquina de aluno

```bash
sudo iptables -S LABLIVRE_PROVA          # regras da prova (erro = não está ativa)
systemctl status lablivre-prova          # serviço de persistência
systemctl list-timers | grep lablivre    # fim automático agendado
curl -sI https://www.google.com          # deve falhar durante a prova
```

## Atualizando da 4.2.0 ou anterior

As versões antigas usavam `iptables -F OUTPUT` e `-P OUTPUT DROP`, sem persistência.
Ao **Liberar** ou **Ativar** pela 4.2.1, essas regras antigas são detectadas e limpas sozinhas
(a saída mostra "regras antigas removidas").
