// OpenBFME. GPL-3.0.
//
// Lane IOS-45: which mice and keyboards GameController lists, and whether the iOS build runs on a Mac. The input itself (the pointer, the
// buttons, the keys) is the input bridge's (GodotIOSTouch.mm), which hands Godot ordinary input events; this only answers what the touch
// layer (scripts/touch/touch_controls.gd) cannot tell from those events: that the last mouse went (IOS-17: touch play again until a pointer
// shows itself). It sets no handler and adds nothing to Godot's view.
//
// Plain C++ on purpose, as IOSAudioSessionBridge.h: IOSInputDevicesBridge.mm includes no godot-cpp header. Called on the main thread.

#pragma once

namespace IOSInputDevicesBridge
{

int mice();      // GCMouse.mice.count (the iPhone Duo lists one with nothing paired: a count is no proof of a mouse, IOS-17)
bool keyboard(); // GCKeyboard.coalescedKeyboard
bool onMac();    // NSProcessInfo.isiOSAppOnMac: the iPhone / iPad build on an Apple Silicon Mac ("Designed for iPad")

} // namespace IOSInputDevicesBridge
