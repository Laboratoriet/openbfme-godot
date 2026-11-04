#!/bin/sh
# IOS-31: copy a mod into OpenBFME's Mods folder on a connected iPhone / iPad (Documents/Mods/<name>, what the Files app shows as
# On My iPhone > OpenBFME > Mods). The Options > Mods tab then lists it; turn it on there, ACCEPT, and restart OpenBFME.
#
#   tools/ios/copy_mod_to_device.sh [--dry-run] [--name <name>] <mod folder or .big> [device name or id]
#
# A mod is what the desktop Mods folder takes (docs/MODS.md): a -mod folder, a .big, or an install-folder mod such as Edain laid out by
# tools/mod/aio_package.py (the package's own folder: its install/ folder and openbfme-aio.json, e.g. <corpus>/Edain). The folder is copied
# as it is, recursively (devicectl copies a directory and skips files that have not changed, so a second run only sends what changed);
# nothing of the mod is edited. --name gives it another name on the device (default: the folder's or file's own name).
# Needs: Xcode's devicectl, the device connected, unlocked and in Developer Mode, and OpenBFME installed on it (tools/ios/build_device.sh)
# with the bundle id BUNDLE_ID (default org.openbfme.game, as build_device.sh). Edain 4.8.5.4 is about 6.2 GB on disk: check the device's
# free space first (Settings > General > iPhone Storage). At about 14 MB/s over the cable that is about 8 minutes.
# --dry-run prints the devicectl command and the size, and touches no device.
set -eu

BUNDLE_ID=${BUNDLE_ID:-org.openbfme.game}
DRY=0
NAME=""
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY=1; shift ;;
        --name) NAME=$2; shift 2 ;;
        --) shift; break ;;
        -*) echo "usage: $0 [--dry-run] [--name <name>] <mod folder or .big> [device]" >&2; exit 2 ;;
        *) break ;;
    esac
done
SRC=${1:?usage: $0 [--dry-run] [--name <name>] <mod folder or .big> [device]}
DEVICE=${2:-}
[ -e "$SRC" ] || { echo "IOS no such mod: $SRC" >&2; exit 1; }
SRC=$(cd "$(dirname "$SRC")" && pwd)/$(basename "$SRC")
[ -n "$NAME" ] || NAME=$(basename "$SRC")
case "$NAME" in
    */*|*\;*|.*) echo "IOS the name '$NAME' cannot be a Mods folder entry (no '/', ';' or leading '.')" >&2; exit 1 ;;
esac
if [ -d "$SRC" ] && find "$SRC" -type l | grep -q .; then
    echo "IOS $SRC holds a symbolic link, which the Mods folder refuses (docs/MODS.md): copy the files themselves" >&2
    exit 1
fi
KIND="a -mod folder"
if [ -f "$SRC" ]; then
    KIND="a mod archive"
elif [ -f "$SRC/openbfme-aio.json" ]; then
    KIND="an install-folder mod (All In One package)"
elif [ -d "$SRC/install" ] || ls "$SRC"/lang/*.big "$SRC"/LANG/*.big >/dev/null 2>&1; then
    KIND="an install-folder mod"
fi
SIZE=$(du -sk "$SRC" | awk '{printf "%.1f GB", $1 * 1024 / 1e9}')
DEST="Documents/Mods/$NAME"
echo "IOS copying $SRC ($KIND, $SIZE) to $DEST in $BUNDLE_ID's container"

if [ "$DRY" = 1 ]; then
    echo "IOS dry run: xcrun devicectl device copy to --device ${DEVICE:-<first connected iPhone / iPad>} --source \"$SRC\" --destination \"$DEST\" --domain-type appDataContainer --domain-identifier $BUNDLE_ID"
    exit 0
fi
if [ -z "$DEVICE" ]; then
    DEVICE=$(xcrun devicectl list devices 2>/dev/null | awk '/available/ && /iPhone|iPad/ {print $3; exit}')
fi
[ -n "$DEVICE" ] || { echo "IOS no connected device found" >&2; exit 1; }
xcrun devicectl device copy to --device "$DEVICE" --source "$SRC" --destination "$DEST" \
    --domain-type appDataContainer --domain-identifier "$BUNDLE_ID"
echo "IOS done: open OpenBFME > Options > Mods, turn on $NAME, ACCEPT, and restart the app"
