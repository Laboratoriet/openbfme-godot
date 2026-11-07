// OpenBFME. GPL-3.0.
//
// Lane IOS-45: GodotIOSInputDevices.h says why.

#include "GodotDevice/GodotIOSInputDevices.h"

#include "GodotDevice/IOSInputDevicesBridge.h"

#include <godot_cpp/core/class_db.hpp>

namespace godot
{

Dictionary IOSInputDevices::status() const
{
	Dictionary d;
	d["mice"] = IOSInputDevicesBridge::mice();
	d["keyboard"] = IOSInputDevicesBridge::keyboard();
	d["on_mac"] = IOSInputDevicesBridge::onMac();
	return d;
}

void IOSInputDevices::_bind_methods()
{
	ClassDB::bind_method(D_METHOD("status"), &IOSInputDevices::status);
}

} // namespace godot
