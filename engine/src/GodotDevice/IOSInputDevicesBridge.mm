// OpenBFME. GPL-3.0.
//
// Lane IOS-45: IOSInputDevicesBridge.h says why. Built for iOS only, with ARC.

#import <Foundation/Foundation.h>
#import <GameController/GameController.h>

#include "GodotDevice/IOSInputDevicesBridge.h"

#if !__has_feature(objc_arc)
#error "IOSInputDevicesBridge.mm needs ARC (-fobjc-arc, engine/CMakeLists.txt)"
#endif

int IOSInputDevicesBridge::mice()
{
	return (int)GCMouse.mice.count;
}

bool IOSInputDevicesBridge::keyboard()
{
	return GCKeyboard.coalescedKeyboard != nil;
}

bool IOSInputDevicesBridge::onMac()
{
	return NSProcessInfo.processInfo.isiOSAppOnMac;
}
