#!/bin/sh
# IOS-3: adjust an exported iOS Xcode project (tools/ios/run_simulator.sh calls this after Godot's export).
#
#   tools/ios/patch_export.sh <export folder> <scheme>
#
# Godot 4.7.2's iOS template writes UIRequiresFullScreen = true into the app's Info.plist. On the iPhone Duo's inner screen an app that
# requires full screen runs in the compatibility mode: drawn at the outer screen's size (2034x1398) and scaled up. A resizable app gets
# the window it is shown in, at the screen's own pixels (Godot sizes its window from the view's bounds), and survives rotation and the
# fold. The orientations themselves come from the project (display/window/handheld/orientation).
set -eu

EXPORT=$1
SCHEME=$2
PLIST="$EXPORT/$SCHEME/$SCHEME-Info.plist"
[ -f "$PLIST" ] || { echo "IOS no $PLIST" >&2; exit 1; }

plutil -replace UIRequiresFullScreen -bool NO "$PLIST"
echo "IOS $PLIST: UIRequiresFullScreen off (resizable: native size on every screen)"
