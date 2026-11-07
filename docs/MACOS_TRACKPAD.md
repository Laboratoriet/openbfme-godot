# macOS trackpad camera controls

This is an enhanced camera feature shared by BFME2 and RotWK. It does not change
simulation rules, commands, saved state or RNG.

Over the game world:

- Slide two fingers to pan the camera in both axes.
- Twist two fingers to rotate the camera heading.
- Spread fingers to zoom in; pinch together to zoom out.

Gestures over the HUD, outside the viewport, while input is disabled, or while a
modal menu is open leave the camera unchanged. Mouse-wheel zoom keeps its existing
behavior. Camera movement uses the existing zoom limits and map constraints.
Gestures update client camera state directly, without waiting for a logic frame.

Godot supplies incremental `InputEventPanGesture` and `InputEventMagnifyGesture`
events. Its macOS content view has no rotation-event implementation, so the
extension installs an AppKit local monitor for `NSEventMaskRotate`, scoped to the
HUD's focused native window. Rotation is in degrees. The monitor is removed when
the HUD leaves the tree, is rebuilt or destroyed, and on extension shutdown.
No global event monitoring or Accessibility permission is used.

Sources: [Godot gesture definitions](https://github.com/godotengine/godot/blob/master/core/input/input_event.h),
[Godot macOS delivery](https://github.com/godotengine/godot/blob/master/platform/macos/godot_content_view.mm),
and [Apple local event monitoring](https://developer.apple.com/documentation/appkit/nsevent/addlocalmonitorforevents(matching:handler:)).

Run `godot --headless --path godot --script res://tests/macos_trackpad_test.gd`
with ROTWK_INSTALL and BFME2_INSTALL set. This checks viewport-injected Godot pan/pinch
input, the rotation adapter, invalid values, disabled input, HUD exclusion and
unchanged simulation hashes. Run without `--headless` on macOS to check native
monitor installation as well.

Physical-device acceptance: in a skirmish, pan horizontally and vertically,
twist both directions, and pinch/spread. Repeat over the radar and command bar,
with the pause/options menu open, after switching focus to another application,
and after leaving and restarting the game. Verify ordinary mouse-wheel zoom still
works. Synthetic event checks cannot prove physical trackpad delivery or feel.

## iPad and iPhone (ios-port, lane IOS-48)

The iOS input bridge (`engine/src/GodotDevice/GodotIOSTouch.mm`) gives the same events: a trackpad's (or Magic Mouse's) two-finger
scroll is an `InputEventPanGesture` of device 0 and pans the camera over the game world, a trackpad pinch an
`InputEventMagnifyGesture` that zooms, as on a Mac. A mouse wheel's scrolling reaches UIKit as scrolling too, so the bridge sends it as a
pan gesture of device `WheelDevice` (1002, `GodotIOSTouch.h`), which the HUD does not take: the touch layer
(`godot/scripts/touch/touch_controls.gd`) makes it wheel notches, the zoom, as a wheel is on a Mac. A trackpad scroll the HUD does not
take (over the HUD, in the menus) is wheel notches too, as before. Rotation needs a native rotation recognizer the bridge does not add
yet; finger touches keep the touch layer's own two-finger pan, pinch and twist (they are screen touches, never these gestures).
