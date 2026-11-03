// OpenBFME. GPL-3.0.
//
// Lane IOS-14: a mouse, a trackpad and a hardware keyboard on iOS (an iPad's, the simulator's with the Mac's pointer captured, the iPhone build on
// an Apple Silicon Mac "Designed for iPad"). Godot 4.7's iOS layer (drivers/apple_embedded) knows no mouse: a click reaches it as a screen touch,
// left button only, with no hover, no right button and no wheel; and on the Mac a hardware key's release never reaches it. This bridge reads the
// pointer from UIKit (a hover recognizer, a touch observer and a scroll recognizer on Godot's view) and the buttons and keys from GameController
// (GCMouse, GCKeyboard), and queues them for the Godot side (GodotIOSPointer.cpp: the IOSPointer class; scripts/touch/touch_controls.gd).
//
// Plain C++ on purpose: IOSPointerBridge.mm is the only Objective-C++ file and includes no godot-cpp header. Every function runs on the main
// thread (UIKit's and GameController's handlers are set to the main queue; Godot's iOS main loop runs there too).

#pragma once

#include <cstdint>
#include <vector>

namespace IOSPointerBridge
{

enum class EventType : std::uint8_t
{
	Motion, // the pointer moved (x, y; buttons)
	Button, // a mouse button changed (button, pressed, x, y; buttons after it; doubleClick)
	Scroll, // a wheel or two-finger scroll (dx, dy in points; x, y the pointer; ended: the scroll gesture's last event)
	Key,    // a hardware key changed (hidUsage, pressed)
	Leave,  // the pointer stopped hovering with no button down (x, y: its last place): it left the view (the Mac host's window), or hid
};

struct Event
{
	EventType type = EventType::Motion;
	float x = 0.0f;           // the pointer in Godot window pixels (UIKit points x the view's contentScaleFactor, as Godot's touches)
	float y = 0.0f;
	float dx = 0.0f;          // Scroll: the scroll since the previous event in points; +y: the content moves down (a wheel turned up)
	float dy = 0.0f;
	int button = 0;           // Button: 1 left, 2 right, 3 middle (Godot's MouseButton)
	bool pressed = false;     // Button, Key
	bool doubleClick = false; // Button: a second click (UITouch.tapCount > 1)
	bool ended = false;       // Scroll
	int buttons = 0;          // Motion, Button: the buttons down after the event (Godot's MouseButtonMask: 1 left, 2 right, 4 middle)
	long hidUsage = 0;        // Key: the key's USB HID usage (GCKeyCode, the keyboard page)
};

struct Status
{
	bool started = false;
	int mice = 0;             // GCMouse.mice
	bool keyboard = false;    // GCKeyboard.coalescedKeyboard
	bool pointerSeen = false; // a hover or an indirect pointer touch since the last mouse went
	bool onMac = false;       // NSProcessInfo.isiOSAppOnMac: the iPhone / iPad build on an Apple Silicon Mac
	int hovers = 0;           // counters for the log
	int pointerTouches = 0;
	int indirectTouches = 0;
	int scrolls = 0;
	int gcButtons = 0;
	int secondaryTaps = 0;
	int keys = 0;
	int claims = 0;           // Godot screen touches recognised as the pointer's
};

// Installs the recognizers on Godot's view (a UIView*, DisplayServer WINDOW_VIEW) and the GameController handlers. Idempotent; false without a view.
bool start(void *uiView);
// Moves the queued events into `out` (appends).
void poll(std::vector<Event> &out);
// True (once) when a pointer touch began at (x, y) window pixels within the last second: Godot's screen touch there is the mouse's click.
bool claimTouch(float x, float y);
// A pointer is in use: it hovered, moved, clicked or scrolled (a GCMouse merely listed does not count: IOS-17).
bool mouseConnected();
bool keyboardConnected();
int buttonsDown();
Status status();

} // namespace IOSPointerBridge
