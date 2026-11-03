#!/bin/sh
# IOS-14: replace the game data (scripts, scenes) of the iPhone build running on this Mac without re-signing it: a debug build loads
# <its Documents>/OpenBFME-dev.pck at start (release.gd). Exports the iOS preset's pack, puts it there, restarts the app. Delete the file to
# go back to the app's own pack.
# Engine (C++) changes are not in the pack: they need run_mac.sh again.
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
GODOT=${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}
BUNDLE_ID=${BUNDLE_ID:-no.alkemist.openbfme}
DEST=""
for c in "$HOME"/Library/Containers/*/; do
    if plutil -p "$c.com.apple.containermanagerd.metadata.plist" 2>/dev/null | grep -q "\"$BUNDLE_ID\""; then
        DEST="${c}Data/Documents/OpenBFME-dev.pck"
    fi
done
[ -n "$DEST" ] || { echo "IOS no container of $BUNDLE_ID" >&2; exit 1; }
"$GODOT" --headless --path "$ROOT/godot" --export-pack "iOS" "$DEST.new"
mv "$DEST.new" "$DEST"
pkill -f "Wrapper/OpenBFME.app/OpenBFME" 2>/dev/null || true
sleep 1
open "$ROOT/workspace/ios-mac/OpenBFME-Mac.app"
echo "IOS pack pushed: $DEST"
