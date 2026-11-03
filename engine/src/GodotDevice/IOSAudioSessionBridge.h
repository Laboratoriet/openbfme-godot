// OpenBFME. GPL-3.0.
//
// Lane IOS-20: the iOS audio session (AVAudioSession) set live from the game's options. Godot 4.7.2 sets the session's category once, at launch, from
// the project settings audio/general/ios/session_category (0: Ambient, which the ring / silent switch mutes) and audio/general/ios/mix_with_others
// (drivers/apple_embedded/app_delegate_service.mm, application:didFinishLaunchingWithOptions:), and never again. The owner's choices (2026-11-03):
// the game follows the silent switch by default, mixes with other apps' audio (his music keeps playing), and an option "Play sound in silent mode"
// (OpenBFMEIOSSilentSound, scripts/game_options.gd) switches to the Playback category, which the silent switch does not mute.
//
//   play in silent mode off: AVAudioSessionCategoryAmbient  + AVAudioSessionCategoryOptionMixWithOthers (the switch mutes the game)
//   play in silent mode on:  AVAudioSessionCategoryPlayback + AVAudioSessionCategoryOptionMixWithOthers (the switch does not)
//
// Interruptions (a call, an alarm): Godot's onAudioInterruption only tells the OS focus out / in; it does not set the category again, and the session
// keeps its category through an interruption, so nothing is re-applied there. A media services reset (AVAudioSessionMediaServicesWereResetNotification)
// does discard the session's configuration: the bridge sets the last choice again then (Godot itself does not handle that notification).
//
// Plain C++ on purpose, as IOSPointerBridge.h: IOSAudioSessionBridge.mm includes no godot-cpp header. Every call runs on the main thread (Godot's iOS
// main loop runs there; the reset observer is on the main queue).

#pragma once

#include <string>

namespace IOSAudioSessionBridge
{

struct Result
{
	bool ok = false;              // the category was set (false: `error` says why; the session keeps what it had)
	std::string category;         // the session's category afterwards, short: "Ambient", "Playback", "SoloAmbient", ... (read back, not assumed)
	bool mixWithOthers = false;   // AVAudioSessionCategoryOptionMixWithOthers is among the session's options afterwards
	bool silentSwitchMutes = false; // the category is one the ring / silent switch mutes (Ambient, SoloAmbient)
	std::string options;          // the session's category options afterwards, as text ("mix with others", "none", ...)
	std::string error;            // NSError's description when setting failed
	int reapplied = 0;            // how many times a media services reset made the bridge set the choice again
};

// Sets the category for `playInSilentMode` (above) with MixWithOthers, remembers the choice for a media services reset, and reads the session back.
Result apply(bool playInSilentMode);
// The session as it is now (no change).
Result current();

} // namespace IOSAudioSessionBridge
