// OpenBFME. GPL-3.0.
//
// Lane IOS-14: IOSPointer (GodotIOSPointer.h), over IOSPointerBridge.mm.

#include "GodotDevice/GodotIOSPointer.h"

#include "GodotDevice/IOSPointerBridge.h"

#include <godot_cpp/classes/display_server.hpp>
#include <godot_cpp/classes/global_constants.hpp>
#include <godot_cpp/core/class_db.hpp>

#include <cstdint>
#include <vector>

namespace godot
{

namespace
{

// The USB HID usage of a key -> the Key Godot's iOS layer gives that key as its physical keycode (Godot 4.7.2
// drivers/apple_embedded/key_mapping_apple_embedded.mm KeyMappingAppleEmbedded::initialize, UIKeyboardHIDUsage values, its choices kept:
// Quote is QUOTEDBL, the grave accent BAR, NonUSPound ASCIITILDE). touch_controls.gd matches the bridge's key releases to Godot's own presses by
// this code, so it must be exactly Godot's.
Key IosPhysicalKey(long hid)
{
	if (hid >= 0x04 && hid <= 0x1D) // a .. z
	{
		return (Key)((int64_t)KEY_A + (hid - 0x04));
	}
	if (hid >= 0x1E && hid <= 0x26) // 1 .. 9
	{
		return (Key)((int64_t)KEY_1 + (hid - 0x1E));
	}
	if (hid >= 0x3A && hid <= 0x45) // F1 .. F12
	{
		return (Key)((int64_t)KEY_F1 + (hid - 0x3A));
	}
	if (hid >= 0x68 && hid <= 0x73) // F13 .. F24
	{
		return (Key)((int64_t)KEY_F13 + (hid - 0x68));
	}
	if (hid >= 0x59 && hid <= 0x61) // keypad 1 .. 9
	{
		return (Key)((int64_t)KEY_KP_1 + (hid - 0x59));
	}
	switch (hid)
	{
		case 0x27: return KEY_0;
		case 0x28: return KEY_ENTER;        // ReturnOrEnter
		case 0x29: return KEY_ESCAPE;
		case 0x2A: return KEY_BACKSPACE;    // DeleteOrBackspace
		case 0x2B: return KEY_TAB;
		case 0x2C: return KEY_SPACE;
		case 0x2D: return KEY_MINUS;        // Hyphen
		case 0x2E: return KEY_EQUAL;
		case 0x2F: return KEY_BRACKETLEFT;
		case 0x30: return KEY_BRACKETRIGHT;
		case 0x31: return KEY_BACKSLASH;
		case 0x32: return KEY_ASCIITILDE;   // NonUSPound
		case 0x33: return KEY_SEMICOLON;
		case 0x34: return KEY_QUOTEDBL;     // Quote
		case 0x35: return KEY_BAR;          // GraveAccentAndTilde
		case 0x36: return KEY_COMMA;
		case 0x37: return KEY_PERIOD;
		case 0x38: return KEY_SLASH;
		case 0x39: return KEY_CAPSLOCK;
		case 0x46: return KEY_PRINT;        // PrintScreen
		case 0x47: return KEY_SCROLLLOCK;
		case 0x48: return KEY_PAUSE;
		case 0x49: return KEY_INSERT;
		case 0x4A: return KEY_HOME;
		case 0x4B: return KEY_PAGEUP;
		case 0x4C: return KEY_DELETE;       // DeleteForward
		case 0x4D: return KEY_END;
		case 0x4E: return KEY_PAGEDOWN;
		case 0x4F: return KEY_RIGHT;
		case 0x50: return KEY_LEFT;
		case 0x51: return KEY_DOWN;
		case 0x52: return KEY_UP;
		case 0x53: return KEY_NUMLOCK;      // KeypadNumLock
		case 0x54: return KEY_KP_DIVIDE;
		case 0x55: return KEY_KP_MULTIPLY;
		case 0x56: return KEY_KP_SUBTRACT;
		case 0x57: return KEY_KP_ADD;
		case 0x58: return KEY_KP_ENTER;
		case 0x62: return KEY_KP_0;
		case 0x63: return KEY_KP_PERIOD;
		case 0x64: return KEY_SECTION;      // NonUSBackslash
		case 0x75: return KEY_HELP;
		case 0x76: return KEY_MENU;
		case 0x78: return KEY_STOP;
		case 0x7E: return KEY_SEARCH;       // Find
		case 0x7F: return KEY_VOLUMEMUTE;
		case 0x80: return KEY_VOLUMEUP;
		case 0x81: return KEY_VOLUMEDOWN;
		case 0x9A: return KEY_SYSREQ;       // SysReqOrAttention
		case 0x9E: return KEY_ENTER;        // Return
		case 0x9F: return KEY_SECTION;      // Separator
		case 0x90: return KEY_JIS_EISU;     // LANG1
		case 0x91: return KEY_JIS_KANA;     // LANG2
		case 0xE0: return KEY_CTRL;         // LeftControl
		case 0xE1: return KEY_SHIFT;
		case 0xE2: return KEY_ALT;
		case 0xE3: return KEY_META;         // LeftGUI
		case 0xE4: return KEY_CTRL;         // RightControl
		case 0xE5: return KEY_SHIFT;
		case 0xE6: return KEY_ALT;
		case 0xE7: return KEY_META;
		case 0x01AE: return KEY_KEYBOARD;   // the on-screen keyboard key of a smart connector keyboard
		case 0x029D: return KEY_GLOBE;
		default: return KEY_NONE;
	}
}

} // namespace

bool IOSPointer::start()
{
	DisplayServer *ds = DisplayServer::get_singleton();
	if (ds == nullptr)
	{
		return false;
	}
	// Godot 4.7.2 DisplayServerAppleEmbedded::window_get_native_handle(WINDOW_VIEW): the GDTView (a UIView) that takes the touches
	void *view = (void *)(intptr_t)ds->window_get_native_handle(DisplayServer::WINDOW_VIEW);
	return IOSPointerBridge::start(view);
}

Array IOSPointer::poll()
{
	std::vector<IOSPointerBridge::Event> events;
	IOSPointerBridge::poll(events);
	Array out;
	for (const IOSPointerBridge::Event &e : events)
	{
		Dictionary d;
		switch (e.type)
		{
			case IOSPointerBridge::EventType::Motion:
				d["type"] = "motion";
				d["position"] = Vector2(e.x, e.y);
				d["buttons"] = e.buttons;
				break;
			case IOSPointerBridge::EventType::Button:
				d["type"] = "button";
				d["button"] = e.button;
				d["pressed"] = e.pressed;
				d["double_click"] = e.doubleClick;
				d["position"] = Vector2(e.x, e.y);
				d["buttons"] = e.buttons;
				break;
			case IOSPointerBridge::EventType::Scroll:
				d["type"] = "scroll";
				d["delta"] = Vector2(e.dx, e.dy);
				d["position"] = Vector2(e.x, e.y);
				d["ended"] = e.ended;
				break;
			case IOSPointerBridge::EventType::Key:
				d["type"] = "key";
				d["physical"] = (int64_t)IosPhysicalKey(e.hidUsage);
				d["hid"] = (int64_t)e.hidUsage;
				d["pressed"] = e.pressed;
				break;
			case IOSPointerBridge::EventType::Leave:
				d["type"] = "leave";
				d["position"] = Vector2(e.x, e.y);
				break;
		}
		out.push_back(d);
	}
	return out;
}

bool IOSPointer::claim_touch(const Vector2 &position)
{
	return IOSPointerBridge::claimTouch(position.x, position.y);
}

bool IOSPointer::is_mouse_connected() const
{
	return IOSPointerBridge::mouseConnected();
}

bool IOSPointer::is_keyboard_connected() const
{
	return IOSPointerBridge::keyboardConnected();
}

int64_t IOSPointer::buttons_down() const
{
	return IOSPointerBridge::buttonsDown();
}

Dictionary IOSPointer::status() const
{
	const IOSPointerBridge::Status s = IOSPointerBridge::status();
	Dictionary d;
	d["started"] = s.started;
	d["mice"] = s.mice;
	d["keyboard"] = s.keyboard;
	d["pointer_seen"] = s.pointerSeen;
	d["on_mac"] = s.onMac;
	d["hovers"] = s.hovers;
	d["pointer_touches"] = s.pointerTouches;
	d["indirect_touches"] = s.indirectTouches;
	d["scrolls"] = s.scrolls;
	d["gc_buttons"] = s.gcButtons;
	d["secondary_taps"] = s.secondaryTaps;
	d["keys"] = s.keys;
	d["claims"] = s.claims;
	return d;
}

void IOSPointer::_bind_methods()
{
	ClassDB::bind_method(D_METHOD("start"), &IOSPointer::start);
	ClassDB::bind_method(D_METHOD("poll"), &IOSPointer::poll);
	ClassDB::bind_method(D_METHOD("claim_touch", "position"), &IOSPointer::claim_touch);
	ClassDB::bind_method(D_METHOD("is_mouse_connected"), &IOSPointer::is_mouse_connected);
	ClassDB::bind_method(D_METHOD("is_keyboard_connected"), &IOSPointer::is_keyboard_connected);
	ClassDB::bind_method(D_METHOD("buttons_down"), &IOSPointer::buttons_down);
	ClassDB::bind_method(D_METHOD("status"), &IOSPointer::status);
}

} // namespace godot
