#!/usr/bin/env bash
# Run after copying a new build into the game's AddOns folder (and after the
# tests pass). Installs the dev reload addon (tools/devreload) if it's missing
# or out of date, then presses its key in the running game. The key clicks the
# addon's secure /reload button, so the game reloads at once. The addon needs no
# other addon (the game refuses ReloadUI() from addon code, a macro is fine).
#
#   tools/game_reload.sh            install if needed, then ask the game
#   DAYLIGHT_GAME=/path/_forever_   another game folder
#
# After pressing the key it waits for the reload to show: the game writes its
# saved variables (WTF/Account/**/SavedVariables) on every reload.
#
# Exit codes: 0 the game reloaded, 2 the game isn't running or its window can't
# be found, 3 the addon was just installed or updated (one /reload by hand loads
# it), 4 the key was pressed but no reload showed within RELOAD_WAIT seconds.

set -u
GAME="${DAYLIGHT_GAME:-/var/mnt/data/Jeux - Installations/World of Warcraft/_forever_}"
ADDONS="$GAME/Interface/AddOns"
NAME="DaylightUI_DevReload"
SRC="$(cd "$(dirname "$0")" && pwd)/devreload/$NAME"
DEST="$ADDONS/$NAME"
KEYS="ctrl+alt+shift+F9"    # DevReload.lua's KEY (not F12: Steam takes it for screenshots)
RELOAD_WAIT="${RELOAD_WAIT:-30}"   # seconds to wait for the reload to show

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
    if ! cmp -s "$f" "$DEST/$base"; then cp "$f" "$DEST/$base"; fresh=1; echo "installed $NAME/$base"; fi
done

win="$(xdotool search --name '^World of Warcraft$' 2>/dev/null | head -n 1)"
[ -z "$win" ] && win="$(xdotool search --class 'wow' 2>/dev/null | head -n 1)"
if [ -z "$win" ]; then
    echo "World of Warcraft isn't running (or its window isn't visible): reload by hand when you start it."
    exit 2
fi

if [ "$fresh" = 1 ]; then
    echo "$NAME was just installed or updated: /reload once by hand to load it; after that this reloads for you."
    exit 3
fi

# Saved variables written after this mark mean the game reloaded.
MARK="$(mktemp)"
trap 'rm -f "$MARK"' EXIT
confirm() {
    local tries=$((RELOAD_WAIT * 2)) hit
    while [ "$tries" -gt 0 ]; do
        hit="$(find "$GAME/WTF/Account" -path '*SavedVariables*' -name '*.lua' -newer "$MARK" -print -quit 2>/dev/null)"
        if [ -n "$hit" ]; then
            echo "$1 The game reloaded (saved variables written at $(date +%H:%M:%S))."
            exit 0
        fi
        sleep 0.5
        tries=$((tries - 1))
    done
    echo "$1 But no reload showed within ${RELOAD_WAIT}s: the key may not have reached the game (in combat, or another window took it). Reload by hand." >&2
    exit 4
}

# On KDE Wayland, KWin refuses xdotool's activate while a Wayland window (the
# terminal this runs from) has focus, and the keys then go nowhere. A KWin
# script, loaded over D-Bus, may focus a window: it raises the game first.
kwin_focus() {
    local qdbus js id
    qdbus="$(command -v qdbus-qt6 || command -v qdbus6 || command -v qdbus)" || return 1
    js="$(mktemp --suffix=.js)"
    cat > "$js" <<'JS'
for (const w of workspace.windowList()) {
    if (w.caption === "World of Warcraft") { workspace.activeWindow = w; break; }
}
JS
    "$qdbus" org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript game-reload-focus >/dev/null 2>&1
    id="$("$qdbus" org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript "$js" game-reload-focus 2>/dev/null)"
    [ -n "$id" ] && "$qdbus" org.kde.KWin "/Scripting/Script$id" org.kde.kwin.Script.run >/dev/null 2>&1
    sleep 0.3
    "$qdbus" org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript game-reload-focus >/dev/null 2>&1
    rm -f "$js"
}
kwin_focus

# Bring the game forward and press the keys. Wine ignores keys sent to a window
# that isn't focused, hence the activate first. A text box with the cursor (chat,
# the Send Mail fields) takes every key, so key bindings don't fire: Escape first
# takes the cursor out. With no cursor anywhere, Escape closes a window or opens
# the game menu, which the reload right after makes moot.
if xdotool windowactivate --sync "$win" 2>/dev/null && sleep 0.3 \
    && xdotool key --clearmodifiers Escape && sleep 0.2 && xdotool key --clearmodifiers "$KEYS"; then
    confirm "Pressed the reload key in the game."
fi

# Fallback: ydotool types into whatever has focus (needs ydotoold running).
if command -v ydotool >/dev/null 2>&1; then
    # Escape 1 (out of any text box, as above), then ctrl 29, alt 56, shift 42, F9 67
    if ydotool key 1:1 1:0 >/dev/null 2>&1 && sleep 0.2 \
        && ydotool key 29:1 56:1 42:1 67:1 67:0 42:0 56:0 29:0 >/dev/null 2>&1; then
        confirm "Pressed the reload key through ydotool."
    fi
fi
echo "Couldn't reach the game window: reload by hand." >&2
exit 2
