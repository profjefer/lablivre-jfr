#!/bin/bash

# _i18n.sh — Carrega arquivo de tradução baseado em LAB_IDIOMA do conf
# Source este arquivo nos scripts. Strings ficam disponíveis como $T_*

CONF_FILE="configs/lablivre.conf"
[ -f "$CONF_FILE" ] && source "$CONF_FILE"

IDIOMA="${LAB_IDIOMA:-pt_BR}"
ARQ_I18N="configs/i18n/${IDIOMA}.conf"

# Fallback para pt_BR se idioma não existe
[ ! -f "$ARQ_I18N" ] && ARQ_I18N="configs/i18n/pt_BR.conf"

[ -f "$ARQ_I18N" ] && source "$ARQ_I18N"
