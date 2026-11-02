#!/bin/sh
# IOS-3: adjust an exported iOS Xcode project (tools/ios/run_simulator.sh calls this after Godot's export).
#
#   tools/ios/patch_export.sh <export folder> <scheme>
#
# Godot 4.7.2's iOS template writes UIRequiresFullScreen = true into the app's Info.plist. On the iPhone Duo's inner screen an app that
# requires full screen runs in the compatibility mode: drawn at the outer screen's size (2034x1398) and scaled up. A resizable app gets
# the window it is shown in, at the screen's own pixels (Godot sizes its window from the view's bounds), and survives rotation and the
# fold. The orientations themselves come from the project (display/window/handheld/orientation).
#
# IOS-4: the game reads the player's game folders from its Documents folder (Godot's user://) as RotWK and BFME2 (InstallLocator.h "iOS").
# UIFileSharingEnabled shows that folder in Finder's device window (Files) for copying from a Mac; LSSupportsOpeningDocumentsInPlace with it
# shows it in the Files app as On My iPhone > OpenBFME, writable, for copying from iCloud Drive or a USB drive. Saves, replays, logs and
# install-paths.cfg (the simulator's) live there too and become visible with it.
set -eu

EXPORT=$1
SCHEME=$2
PLIST="$EXPORT/$SCHEME/$SCHEME-Info.plist"
[ -f "$PLIST" ] || { echo "IOS no $PLIST" >&2; exit 1; }

plutil -replace UIRequiresFullScreen -bool NO "$PLIST"
echo "IOS $PLIST: UIRequiresFullScreen off (resizable: native size on every screen)"

plutil -replace UIFileSharingEnabled -bool YES "$PLIST"
plutil -replace LSSupportsOpeningDocumentsInPlace -bool YES "$PLIST"
echo "IOS $PLIST: Documents shared (Finder's Files, the Files app's On My iPhone > OpenBFME: copy RotWK and BFME2 there)"
