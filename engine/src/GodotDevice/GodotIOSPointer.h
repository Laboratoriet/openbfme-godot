// OpenBFME. GPL-3.0.
//
// Lane IOS-14: IOSPointer, the Godot view of IOSPointerBridge (the mouse, trackpad and hardware keyboard of the iOS build). Compiled and registered
// on iOS only (OPENBFME_IOS_POINTER, engine/CMakeLists.txt): on every other platform the class does not exist and scripts/touch/touch_controls.gd,
// which asks ClassDB.class_exists("IOSPointer"), leaves the input alone. The bridge's state is global: every instance sees the same pointer.

#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/vector2.hpp>

namespace godot
{

class IOSPointer : public RefCounted
{
	GDCLASS(IOSPointer, RefCounted)

public:
	// Installs the bridge on Godot's view (DisplayServer WINDOW_VIEW). Idempotent; false when the view is not there.
	bool start();
	// The events since the last poll, oldest first, each a Dictionary with "type":
	//   "motion"  position (Vector2, window pixels), buttons (MouseButtonMask)
	//   "button"  button (MouseButton 1 / 2 / 3), pressed, double_click, position, buttons (after it)
	//   "scroll"  delta (Vector2, points; +y: the content moves down, a wheel turned up), position, ended (the scroll gesture's last event)
	//   "key"     physical (Key, as Godot's iOS layer names that key: KeyMappingAppleEmbedded), hid (the USB HID usage), pressed
	//   "leave"   position: the pointer stopped hovering with no button down (left the view, or hid)
	Array poll();
	// True (once) when Godot's screen touch that began at `position` is a pointer click the bridge reports itself.
	bool claim_touch(const Vector2 &position);
	bool is_mouse_connected() const;
	bool is_keyboard_connected() const;
	int64_t buttons_down() const;
	Dictionary status() const;

protected:
	static void _bind_methods();
};

} // namespace godot
