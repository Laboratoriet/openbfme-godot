// OpenBFME. GPL-3.0.
//
// Lane IOS-47: IOSDeviceStatus, the Godot view of IOSDeviceStatusBridge (battery and thermal state, for the benchmark). Compiled and registered on iOS
// only (OPENBFME_IOS_DEVICE_STATUS, engine/CMakeLists.txt): elsewhere the class does not exist and scripts/benchmark/benchmark_run.gd, which asks
// ClassDB.class_exists("IOSDeviceStatus"), reports "n/a".

#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>

namespace godot
{

class IOSDeviceStatus : public RefCounted
{
	GDCLASS(IOSDeviceStatus, RefCounted)

public:
	// { battery_level (0 .. 1, -1 unknown), battery_state, thermal_state ("nominal", "fair", "serious", "critical"), low_power_mode, model }
	static Dictionary status();

protected:
	static void _bind_methods();
};

} // namespace godot
