# lablivre-jfr

DESCRIÇÃO DO REPOSITÓRIO
Orquestrador de laboratórios Linux via SSH. Gerencie dezenas de máquinas Ubuntu de um único ponto: mapeamento de rede, modo prova, distribuição de material, inventário e dashboards web. Em Shell Script, sem agentes. Feito na UFPR Palotina.

WIKI
 https://profjefer.github.io/lablivre-jfr/docs/wiki_lablivre.html

## LabLivre v4.1.7

Orquestrador de laboratórios Linux via SSH. Gerencie todo o laboratório
da máquina do professor, sem instalar nada nas máquinas dos alunos.

### Instalação rápida

**Via .deb (recomendado):**
```bash
sudo apt install ./lablivre_4.1.7_all.deb
```

**Via Git:**
```bash
curl -fsSL https://raw.githubusercontent.com/profjefer/lablivre-jfr/main/gitinstall.sh | bash
```

### Principais recursos
- 📡 Mapeamento automático da rede (nmap + ARP)
- 📚 Distribuição de material didático (tar-pipe SSH)
- 🔒 Modo Prova (bloqueia internet via iptables)
- 📊 Inventário de hardware (CPU, RAM, disco, BIOS)
- 🌐 7 dashboards web em tempo real
- ⚡ Wake-on-LAN e desligamento remoto
- 🔥 Mapa de calor das máquinas mais usadas
- 🔐 Autenticação por senha ou chave SSH

### Nesta versão
- Correção definitiva da distribuição de material (detecção do Desktop via xdg-user-dir)
- gitinstall.sh alinhado ao .deb (symlinks, permissões, ownership)
- .gitignore protegendo credenciais

Veja o CHANGELOG.md para detalhes.


═══════════════════════════════════════════════════════════════════
  COMANDOS PARA SUBIR O CÓDIGO (cole no terminal, em /opt/lablivre)
═══════════════════════════════════════════════════════════════════

  cd /opt/lablivre

  # Confirme que a senha está protegida:
  cat .gitignore | grep lablivre.conf

  git init
  git add .

  # ⚠️ CONFIRA antes de continuar — lablivre.conf NÃO pode aparecer:
  git status

  git commit -m "LabLivre v4.1.7 - orquestrador de laboratorios Linux via SSH"
  git branch -M main
  git remote add origin https://github.com/profjefer/lablivre-jfr.git
  git push -u origin main

  # Se pedir autenticação, use um Personal Access Token (não a senha):
  # GitHub → Settings → Developer settings → Personal access tokens

