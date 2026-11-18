#!/usr/bin/env bash
# Run after copying a new build into the game's AddOns folder (and after the
# tests pass). Installs the dev reload addon (tools/devreload) if it's missing
# or out of date, then presses its key in the running game, so Daylight UI asks
# "Reload?" with a one-click Reload button. The game refuses ReloadUI() from
# addon code, so that click stays yours.
#
#   tools/game_reload.sh            install if needed, then ask the game
#   DAYLIGHT_GAME=/path/_forever_   another game folder
#
# Exit codes: 0 asked, 2 the game isn't running or its window can't be found,
# 3 the addon was just installed (one /reload by hand loads it the first time).

set -u
GAME="${DAYLIGHT_GAME:-/var/mnt/data/Jeux - Installations/World of Warcraft/_forever_}"
ADDONS="$GAME/Interface/AddOns"
NAME="DaylightUI_DevReload"
SRC="$(cd "$(dirname "$0")" && pwd)/devreload/$NAME"
DEST="$ADDONS/$NAME"
KEYS="ctrl+alt+shift+F12"   # DevReload.lua's KEY

if [ ! -d "$ADDONS" ]; then
    echo "No AddOns folder at: $ADDONS" >&2
    exit 1
fi

# The game reads files with CRLF fine either way; copy as is.
fresh=0
mkdir -p "$DEST"
for f in "$SRC"/*; do
    base="$(basename "$f")"
    if [ ! -f "$DEST/$base" ]; then fresh=1; fi
    if ! cmp -s "$f" "$DEST/$base"; then cp "$f" "$DEST/$base"; echo "installed $NAME/$base"; fi
done

win="$(xdotool search --name '^World of Warcraft$' 2>/dev/null | head -n 1)"
[ -z "$win" ] && win="$(xdotool search --class 'wow' 2>/dev/null | head -n 1)"
if [ -z "$win" ]; then
    echo "World of Warcraft isn't running (or its window isn't visible): reload by hand when you start it."
    exit 2
fi

if [ "$fresh" = 1 ]; then
    echo "$NAME was just installed: /reload once by hand to load it; after that this asks for you."
    exit 3
fi

# Bring the game forward and press the keys. Wine ignores keys sent to a window
# that isn't focused, hence the activate first.
if xdotool windowactivate --sync "$win" 2>/dev/null && sleep 0.3 && xdotool key --clearmodifiers "$KEYS"; then
    echo "Asked the game to reload (Daylight's Reload box is up)."
    exit 0
fi

# Fallback: ydotool types into whatever has focus (needs ydotoold running).
if command -v ydotool >/dev/null 2>&1; then
    # ctrl 29, alt 56, shift 42, F12 88
    if ydotool key 29:1 56:1 42:1 88:1 88:0 42:0 56:0 29:0 >/dev/null 2>&1; then
        echo "Asked the game to reload through ydotool (if WoW had focus)."
        exit 0
    fi
fi
echo "Couldn't reach the game window: reload by hand." >&2
exit 2
