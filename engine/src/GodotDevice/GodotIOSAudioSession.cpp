// OpenBFME. GPL-3.0.
//
// Lane IOS-20: IOSAudioSession (GodotIOSAudioSession.h), over IOSAudioSessionBridge.mm.

#include "GodotDevice/GodotIOSAudioSession.h"

#include "GodotDevice/IOSAudioSessionBridge.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/string.hpp>

namespace godot
{

namespace
{

Dictionary ToDictionary(const IOSAudioSessionBridge::Result &r)
{
	Dictionary d;
	d["ok"] = r.ok;
	d["category"] = String::utf8(r.category.c_str());
	d["mix_with_others"] = r.mixWithOthers;
	d["silent_switch_mutes"] = r.silentSwitchMutes;
	d["options"] = String::utf8(r.options.c_str());
	d["error"] = String::utf8(r.error.c_str());
	d["reapplied"] = r.reapplied;
	return d;
}

} // namespace

Dictionary IOSAudioSession::set_play_in_silent_mode(bool on)
{
	return ToDictionary(IOSAudioSessionBridge::apply(on));
}

Dictionary IOSAudioSession::status()
{
	return ToDictionary(IOSAudioSessionBridge::current());
}

void IOSAudioSession::_bind_methods()
{
	ClassDB::bind_static_method("IOSAudioSession", D_METHOD("set_play_in_silent_mode", "on"), &IOSAudioSession::set_play_in_silent_mode);
	ClassDB::bind_static_method("IOSAudioSession", D_METHOD("status"), &IOSAudioSession::status);
}

} // namespace godot
