# Meta-Dashboard — Múltiplos Labs

O LabLivre pode reportar seu estado para um servidor central, permitindo que
a coordenação visualize TODOS os labs do campus em uma única tela.

## Como funciona

1. Cada lab gera seu `web/api.json` localmente (já funciona hoje)
2. O script `modulos/exportar_estado_publico.sh` envia esse arquivo para um servidor central via SCP, renomeado como `<LAB_ID>.json`
3. O servidor central tem um dashboard HTML que lê todos os `*.json` da pasta e mostra um grid

## Configuração por lab

Edite `configs/lablivre.conf` e adicione:

```bash
LAB_ID="palotina-lab1"
META_DASHBOARD_HOST="servidor.ufpr.br"
META_DASHBOARD_USER="lablivre"
META_DASHBOARD_PATH="/var/www/labs"
```

E adicione ao cron:

```cron
5 * * * * cd /opt/lablivre && bash modulos/exportar_estado_publico.sh >> logs/cron_export.log 2>&1 # LabLivre
```

## Servidor central

No servidor central, basta um Nginx/Apache servindo a pasta `/var/www/labs/` e
um dashboard HTML que lista todos os JSONs e renderiza um grid.

(Implementação do dashboard central fica para fase futura — esta versão entrega
apenas a infraestrutura de exportação.)
