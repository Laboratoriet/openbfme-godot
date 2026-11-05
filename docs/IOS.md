# iOS and iPadOS

OpenBFME builds for iPhone and iPad (arm64, iOS 17 or newer) from a Mac. This page covers the build and the export. The game still needs
the player's own game files on the device, and input other than Godot's own (touch controls, a mouse or trackpad as a mouse) is not
part of this step.

## Build and export

You need a Mac with Xcode (its iOS SDK), CMake, Ninja, Python 3 and Godot 4.7.2 with its export templates (or the official templates
`.tpz`, see below).

1. Build the macOS extension as in [Build from source](../README.md#build-from-source). The Godot editor loads it to import the project
   before it exports the iOS one.
2. Build the iOS extension:

   ```sh
   tools/release/build_ios.sh            # a device; "simulator" or "both" for the simulator slice
   ```

   It configures `engine/` with `engine/cmake/toolchains/ios-arm64.cmake` for each SDK (build trees in `engine/build/ios-<sdk>/`), builds
   the extension as a dynamic `openbfme.framework` and joins the frameworks into `godot/bin/openbfme.ios.xcframework`, which
   `godot/openbfme.gdextension` names. Xcode picks the slice it builds for.
3. Export the Xcode project:

   ```sh
   python3 tools/release/package_ios.py
   ```

   It copies `godot/` to a stage, exports the **iOS** preset of `godot/export_presets.cfg` as an Xcode project into
   `engine/build/ios-export/export/` (or `--output-dir`; an existing export is never overwritten) and adjusts it (below).
   `--templates <Godot_v4.7.2-stable_export_templates.tpz>` takes the iOS template from Godot's official templates file instead of the
   editor's installed templates.
4. Open `OpenBFME.xcodeproj` in Xcode, choose your team under *Signing & Capabilities*, and run it on your device. Or, from the command
   line:

   ```sh
   xcodebuild -project engine/build/ios-export/export/OpenBFME.xcodeproj -scheme OpenBFME -sdk iphoneos -configuration Debug \
     -allowProvisioningUpdates DEVELOPMENT_TEAM=<your team> build
   ```

Nothing in the repository holds a signing team or a personal bundle id. `--team-id` (or `APPLE_TEAM_ID`) writes your team into the
export, and `--bundle-id` (or `OPENBFME_IOS_BUNDLE_ID`) replaces the preset's `org.openbfme.game`, for example when that id is taken
in your Apple account. A free personal team works; its apps expire after 7 days.

## What the export adds

`package_ios.py` sets these on top of Godot's template:

| Where | Key | Why |
|---|---|---|
| Info.plist | `UIRequiresFullScreen` = NO | A resizable app gets the window it is shown in, at the screen's own pixels. An app that requires full screen runs in a compatibility mode on a larger screen (an iPad, a foldable's inner screen): drawn at another size and scaled. |
| Info.plist | `UIFileSharingEnabled`, `LSSupportsOpeningDocumentsInPlace` = YES | The app's Documents folder (Godot's `user://`) shows in Finder's device window and in the Files app (*On My iPhone › OpenBFME*), so files can be copied there. |
| Info.plist | `UIApplicationSupportsIndirectInputEvents` = YES | A mouse or trackpad click arrives as a pointer touch with its button, not as a finger. |
| Entitlements | `com.apple.developer.kernel.increased-memory-limit` | A skirmish holds about 1 GB of video memory besides the game's archives, close to iOS's default per-app limit on phones. Xcode's automatic signing adds the capability to the App ID. |
| Icons | `icons/icon_1024x1024` | Made at export time from the 256 px frame of `godot/assets/app_icon/openbfme.ico`, so no extra image is committed. |

The device build also links **MetalFX** into the extension (`engine/CMakeLists.txt`). Godot 4.7.2's Metal driver checks for MetalFX with
a run-time class lookup, and its iOS export links no MetalFX framework, so without the link the lookup fails, Godot reports "MetalFX
spatial upscaling is not supported" and the 3D view is scaled bilinear. The simulator SDK has no MetalFX.

## Not covered here

- **Game files on the device**: an iOS app can only read its own folders, so the game files have to be copied into the app.
- **Touch controls**, the on-screen keyboard and the HUD for small screens.
- **The simulator**: the official 4.7.2 template's simulator library holds x86_64 code only, so an Apple silicon simulator needs a
  Godot library built from source. `build_ios.sh simulator` builds the extension's slice for it.
- **Distribution**: the export is for building and running on your own device.
