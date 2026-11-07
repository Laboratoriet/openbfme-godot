// OpenBFME. GPL-3.0.
//
// Lane IOS-45: IOSInputDevices, the connected mice and keyboards of the iOS build (IOSInputDevicesBridge.h). Compiled and registered on iOS
// only (OPENBFME_IOS_INPUT, engine/CMakeLists.txt): elsewhere the class does not exist, and scripts/touch/touch_controls.gd, which asks
// ClassDB.class_exists("IOSInputDevices"), treats no input event as a mouse's. The mouse, trackpad, Pencil and keyboard events themselves come
// from the input bridge (GodotIOSTouch.mm) as Godot's own input events.

#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>

namespace godot
{

class IOSInputDevices : public RefCounted
{
	GDCLASS(IOSInputDevices, RefCounted)

public:
	// {"mice": GCMouse.mice.count, "keyboard": a GCKeyboard is connected, "on_mac": the build runs on a Mac ("Designed for iPad")}
	Dictionary status() const;

protected:
	static void _bind_methods();
};

} // namespace godot
