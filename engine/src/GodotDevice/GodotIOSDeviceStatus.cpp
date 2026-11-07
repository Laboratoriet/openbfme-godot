// OpenBFME. GPL-3.0.
//
// Lane IOS-47: IOSDeviceStatus (GodotIOSDeviceStatus.h), over IOSDeviceStatusBridge.mm.

#include "GodotDevice/GodotIOSDeviceStatus.h"

#include "GodotDevice/IOSDeviceStatusBridge.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/string.hpp>

namespace godot
{

Dictionary IOSDeviceStatus::status()
{
	const IOSDeviceStatusBridge::Status s = IOSDeviceStatusBridge::read();
	Dictionary d;
	d["battery_level"] = s.batteryLevel;
	d["battery_state"] = String::utf8(s.batteryState.c_str());
	d["thermal_state"] = String::utf8(s.thermalState.c_str());
	d["low_power_mode"] = s.lowPowerMode;
	d["model"] = String::utf8(s.model.c_str());
	return d;
}

void IOSDeviceStatus::_bind_methods()
{
	ClassDB::bind_static_method("IOSDeviceStatus", D_METHOD("status"), &IOSDeviceStatus::status);
}

} // namespace godot
