// OpenBFME. GPL-3.0.
//
// Lane IOS-47: the device's battery and thermal state for the benchmark (scripts/benchmark/benchmark_run.gd samples them every few seconds):
// UIDevice's batteryLevel / batteryState (battery monitoring is switched on at the first read) and NSProcessInfo's thermalState. Godot has no API for
// either on iOS. Plain C++ on purpose, as IOSAudioSessionBridge.h: IOSDeviceStatusBridge.mm includes no godot-cpp header. Read on the main thread
// (Godot's iOS main loop runs there).

#pragma once

#include <string>

namespace IOSDeviceStatusBridge
{

struct Status
{
	float batteryLevel = -1.0f;   // 0 .. 1; -1 when unknown (a simulator, monitoring not available)
	std::string batteryState;     // "unknown", "unplugged", "charging", "full"
	std::string thermalState;     // "nominal", "fair", "serious", "critical"
	bool lowPowerMode = false;    // NSProcessInfo isLowPowerModeEnabled
	std::string model;            // the hardware model (utsname machine: "iPhone18,3"); "" when unknown
};

Status read();

} // namespace IOSDeviceStatusBridge
