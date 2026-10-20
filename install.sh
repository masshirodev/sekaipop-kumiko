#!/bin/sh
# Links the three widgets into SekaiPop's plugins folder and reloads the shell's plugins.
# Run it from the clone; `git pull` there later updates them (then reload again).
#
#   ./install.sh            link kumiko-hours, kumiko-lists, kumiko-notifications
#   ./install.sh --remove   take the links away (their saved settings stay)
set -eu
here=$(cd "$(dirname "$0")" && pwd)
plugins="${XDG_CONFIG_HOME:-$HOME/.config}/sekaipop/plugins"
mkdir -p "$plugins"
for p in "$here"/kumiko-*/; do
    id=$(basename "$p")
    dest="$plugins/$id"
    if [ "${1:-}" = "--remove" ]; then
        [ -L "$dest" ] && rm "$dest" && echo "removed $id"
        continue
    fi
    if [ -e "$dest" ] && [ ! -L "$dest" ]; then
        echo "$dest exists and is not a link: left alone" >&2
        continue
    fi
    ln -sfn "${p%/}" "$dest"
    echo "linked $id"
done
command -v qs >/dev/null 2>&1 && qs -c sekaipop ipc call plugins reload >/dev/null 2>&1 || true
[ "${1:-}" = "--remove" ] || echo "Add them from Edit Desktop. The token goes in ~/.config/sekaipop-kumiko/token (or KUMIKO_TOKEN)."
