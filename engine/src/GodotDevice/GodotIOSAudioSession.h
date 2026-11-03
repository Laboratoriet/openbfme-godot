// OpenBFME. GPL-3.0.
//
// Lane IOS-20: IOSAudioSession, the Godot view of IOSAudioSessionBridge (the iOS audio session's category, set live). Compiled and registered on iOS
// only (OPENBFME_IOS_AUDIO_SESSION, engine/CMakeLists.txt): on every other platform the class does not exist, and scripts/game_options.gd, which asks
// ClassDB.class_exists("IOSAudioSession"), neither shows "Play sound in silent mode" nor touches the audio.

#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>

namespace godot
{

class IOSAudioSession : public RefCounted
{
	GDCLASS(IOSAudioSession, RefCounted)

public:
	// Playback (true: the silent switch does not mute the game) or Ambient (false: it does), both mixing with other apps' audio. Returns the session
	// read back: { ok, category ("Ambient", "Playback", ...), mix_with_others, silent_switch_mutes, options (text), error ("" when ok), reapplied }.
	static Dictionary set_play_in_silent_mode(bool on);
	// The session as it is now, the same keys (ok always true, error "").
	static Dictionary status();

protected:
	static void _bind_methods();
};

} // namespace godot
