#!/bin/bash
# ================================================================
# _preservar_macs.sh — Não deixa o configs/macs.txt se perder
#
# O macs.txt é feito à mão e é a âncora do laboratório. Atualizar o
# pacote por cima nunca o apaga, mas reinstalar do zero (apt purge,
# rm -rf /opt/lablivre, máquina nova) apagava, e era preciso copiar
# de volta à mão.
#
#   _preservar_macs.sh salvar      guarda uma cópia FORA do /opt
#   _preservar_macs.sh restaurar   se o macs.txt estiver vazio ou sem
#                                  nenhum MAC, traz a melhor cópia
#
# Chamado pelo .deb (preinst, postinst, postrm) e pelo gitinstall.sh,
# como root. Como usuário comum, o "salvar" grava só na pasta pessoal.
#
# Onde ficam as cópias (todas sobrevivem a apt purge):
#   /var/backups/lablivre/macs.txt          (+ até 10 versões antigas)
#   ~<operador>/.local/share/lablivre/macs.txt
#
# Ordem da restauração (vale a primeira que tiver algum MAC):
#   1. /var/backups/lablivre/macs.txt
#   2. ~<operador>/.local/share/lablivre/macs.txt
#   3. o backup mais novo em configs/.backups/
#   4. instalação antiga: /opt/scriptlab-jfr/configs/macs-lablivre.txt
#      e /opt/scriptlab-jfr/configs/macs.txt
#
# Variáveis (para testes): LAB_DIR, LAB_BACKUP_DIR, LAB_HOME_BACKUP,
# LAB_LEGADO (lista de arquivos antigos, separada por espaço).
# ================================================================

LAB_DIR="${LAB_DIR:-/opt/lablivre}"
MACS="$LAB_DIR/configs/macs.txt"
BACKUP_DIR="${LAB_BACKUP_DIR:-/var/backups/lablivre}"
LEGADO="${LAB_LEGADO-/opt/scriptlab-jfr/configs/macs-lablivre.txt /opt/scriptlab-jfr/configs/macs.txt}"

# Pasta pessoal do operador (o dono da instalação, não o root)
home_operador() {
    local u="${SUDO_USER:-}"
    if [ -z "$u" ] || [ "$u" = root ]; then
        u=$(stat -c %U "$LAB_DIR" 2>/dev/null)
    fi
    if [ -z "$u" ] || [ "$u" = root ] || [ "$u" = UNKNOWN ]; then
        u=$(awk -F: '$3 >= 1000 && $3 < 65534 {print $1; exit}' /etc/passwd)
    fi
    [ -n "$u" ] && getent passwd "$u" | cut -d: -f6
}
HOME_BACKUP="${LAB_HOME_BACKUP:-$(home_operador)/.local/share/lablivre}"

# Tem pelo menos uma linha "aa:bb:cc:dd:ee:ff nome"?
tem_macs() {
    [ -s "$1" ] && grep -qE '^[[:space:]]*([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}[[:space:]]+[^[:space:]]' "$1"
}

guardar_em() {   # guardar_em <pasta> [manter_versoes]
    local dir="$1" manter="${2:-0}"
    mkdir -p "$dir" 2>/dev/null || return 1
    cmp -s "$MACS" "$dir/macs.txt" && return 0
    if [ "$manter" -gt 0 ] && [ -f "$dir/macs.txt" ]; then
        cp -p "$dir/macs.txt" "$dir/macs_$(date '+%Y%m%d_%H%M%S').txt" 2>/dev/null
        ls -t "$dir"/macs_*.txt 2>/dev/null | tail -n +$((manter + 1)) | xargs -r rm -f
    fi
    cp -p "$MACS" "$dir/macs.txt" 2>/dev/null
}

salvar() {
    tem_macs "$MACS" || return 0      # nunca sobrescreve uma cópia boa com um arquivo vazio
    local ok=""
    if [ "$(id -u)" = 0 ] || [ -n "${LAB_BACKUP_DIR:-}" ]; then
        guardar_em "$BACKUP_DIR" 10 && chmod 755 "$BACKUP_DIR" 2>/dev/null && ok="$BACKUP_DIR"
    fi
    if [ -n "$HOME_BACKUP" ] && [ "$HOME_BACKUP" != "/.local/share/lablivre" ]; then
        if guardar_em "$HOME_BACKUP"; then
            # Como root: o que acabou de ser criado na pasta pessoal fica
            # do dono dela (senão ~/.local viraria do root).
            if [ "$(id -u)" = 0 ]; then
                local base="${HOME_BACKUP%/.local/share/lablivre}" dono d
                dono=$(stat -c %U:%G "$base" 2>/dev/null)
                for d in "$base/.local" "$base/.local/share" "$HOME_BACKUP" "$HOME_BACKUP/macs.txt"; do
                    [ -n "$dono" ] && [ "$(stat -c %u "$d" 2>/dev/null)" = 0 ] && chown "$dono" "$d" 2>/dev/null
                done
            fi
            ok="${ok:+$ok e }$HOME_BACKUP"
        fi
    fi
    [ -n "$ok" ] && echo "[macs.txt] cópia de segurança em $ok"
    return 0
}

restaurar() {
    tem_macs "$MACS" && return 0      # já tem MACs: não mexe
    local c ultimo
    ultimo=$(ls -t "$LAB_DIR"/configs/.backups/macs_*.txt 2>/dev/null | head -n 1)
    for c in "$BACKUP_DIR/macs.txt" "$HOME_BACKUP/macs.txt" $ultimo $LEGADO; do
        [ -n "$c" ] && tem_macs "$c" || continue
        mkdir -p "$LAB_DIR/configs"
        [ -s "$MACS" ] && cp -p "$MACS" "$MACS.antes_de_restaurar"
        cp "$c" "$MACS"
        echo "[macs.txt] RESTAURADO de $c ($(grep -cE '^[[:space:]]*([0-9A-Fa-f]{2}[:-]){5}' "$MACS") placas)."
        echo "           Confira com: nano $MACS"
        return 0
    done
    echo "[macs.txt] vazio e sem cópia para restaurar: preencha $MACS"
    return 0
}

case "${1:-}" in
    salvar)    salvar ;;
    restaurar) restaurar ;;
    *) echo "Uso: $0 salvar|restaurar" >&2; exit 2 ;;
esac
