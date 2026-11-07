// OpenBFME. GPL-3.0.
//
// Lane IOS-47: IOSDeviceStatusBridge.h over UIDevice and NSProcessInfo.

#include "GodotDevice/IOSDeviceStatusBridge.h"

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include <sys/utsname.h>

namespace IOSDeviceStatusBridge
{

Status read()
{
	Status s;
	UIDevice *device = [UIDevice currentDevice];
	if (!device.batteryMonitoringEnabled)
		device.batteryMonitoringEnabled = YES;
	s.batteryLevel = device.batteryLevel; // -1.0 while unknown
	switch (device.batteryState)
	{
	case UIDeviceBatteryStateUnplugged: s.batteryState = "unplugged"; break;
	case UIDeviceBatteryStateCharging: s.batteryState = "charging"; break;
	case UIDeviceBatteryStateFull: s.batteryState = "full"; break;
	default: s.batteryState = "unknown"; break;
	}
	NSProcessInfo *info = [NSProcessInfo processInfo];
	switch (info.thermalState)
	{
	case NSProcessInfoThermalStateNominal: s.thermalState = "nominal"; break;
	case NSProcessInfoThermalStateFair: s.thermalState = "fair"; break;
	case NSProcessInfoThermalStateSerious: s.thermalState = "serious"; break;
	case NSProcessInfoThermalStateCritical: s.thermalState = "critical"; break;
	default: s.thermalState = "unknown"; break;
	}
	s.lowPowerMode = info.lowPowerModeEnabled;
	struct utsname u;
	if (uname(&u) == 0)
		s.model = u.machine;
	return s;
}

} // namespace IOSDeviceStatusBridge
