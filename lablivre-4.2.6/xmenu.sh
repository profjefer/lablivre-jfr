#!/bin/bash
# Proxy: chama o xmenu.sh real em xmodulos/
# Resolve symlink (ex: /usr/local/bin/lablivre-gui → /opt/lablivre/xmenu.sh)
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
    DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
    SOURCE="$(readlink "$SOURCE")"
    [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
exec bash "$SCRIPT_DIR/xmodulos/xmenu.sh" "$@"
