// OpenBFME. GPL-3.0.
//
// Lane IOS-20: the iOS audio session bridge (IOSAudioSessionBridge.h says what and why). Built for iOS only, with ARC.

#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>

#include "GodotDevice/IOSAudioSessionBridge.h"

#include <cstdio>

#if !__has_feature(objc_arc)
#error "IOSAudioSessionBridge.mm needs ARC (-fobjc-arc, engine/CMakeLists.txt)"
#endif

namespace
{

bool gChosen = false;          // apply() ran at least once (the reset observer has a choice to put back)
bool gPlayInSilentMode = false;
int gReapplied = 0;
id gResetObserver = nil;

std::string ShortCategory(NSString *category)
{
	if (category == nil)
	{
		return "none";
	}
	if ([category isEqualToString:AVAudioSessionCategoryAmbient]) return "Ambient";
	if ([category isEqualToString:AVAudioSessionCategorySoloAmbient]) return "SoloAmbient";
	if ([category isEqualToString:AVAudioSessionCategoryPlayback]) return "Playback";
	if ([category isEqualToString:AVAudioSessionCategoryRecord]) return "Record";
	if ([category isEqualToString:AVAudioSessionCategoryPlayAndRecord]) return "PlayAndRecord";
	if ([category isEqualToString:AVAudioSessionCategoryMultiRoute]) return "MultiRoute";
	return std::string(category.UTF8String); // a category this list does not name: its own constant's text
}

std::string OptionsText(AVAudioSessionCategoryOptions options)
{
	std::string out;
	auto add = [&out](const char *name) {
		out += out.empty() ? "" : ", ";
		out += name;
	};
	if (options & AVAudioSessionCategoryOptionMixWithOthers) add("mix with others");
	if (options & AVAudioSessionCategoryOptionDuckOthers) add("duck others");
	if (options & AVAudioSessionCategoryOptionInterruptSpokenAudioAndMixWithOthers) add("interrupt spoken audio");
	if (options & AVAudioSessionCategoryOptionDefaultToSpeaker) add("default to speaker");
	const AVAudioSessionCategoryOptions named = AVAudioSessionCategoryOptionMixWithOthers | AVAudioSessionCategoryOptionDuckOthers
		| AVAudioSessionCategoryOptionInterruptSpokenAudioAndMixWithOthers | AVAudioSessionCategoryOptionDefaultToSpeaker;
	if (options & ~named)
	{
		char other[32];
		std::snprintf(other, sizeof(other), "other 0x%lx", (unsigned long)(options & ~named));
		add(other);
	}
	return out.empty() ? "none" : out;
}

IOSAudioSessionBridge::Result ReadBack()
{
	AVAudioSession *session = [AVAudioSession sharedInstance];
	IOSAudioSessionBridge::Result r;
	r.ok = true;
	r.category = ShortCategory(session.category);
	const AVAudioSessionCategoryOptions options = session.categoryOptions;
	r.mixWithOthers = (options & AVAudioSessionCategoryOptionMixWithOthers) != 0;
	r.silentSwitchMutes = [session.category isEqualToString:AVAudioSessionCategoryAmbient] || [session.category isEqualToString:AVAudioSessionCategorySoloAmbient];
	r.options = OptionsText(options);
	r.reapplied = gReapplied;
	return r;
}

bool SetCategory(bool playInSilentMode, std::string &error)
{
	AVAudioSessionCategory category = playInSilentMode ? AVAudioSessionCategoryPlayback : AVAudioSessionCategoryAmbient;
	NSError *err = nil;
	if (![[AVAudioSession sharedInstance] setCategory:category withOptions:AVAudioSessionCategoryOptionMixWithOthers error:&err])
	{
		error = err != nil ? std::string(err.localizedDescription.UTF8String) : std::string("setCategory failed with no error");
		return false;
	}
	return true;
}

void InstallResetObserver()
{
	if (gResetObserver != nil)
	{
		return;
	}
	gResetObserver = [[NSNotificationCenter defaultCenter] addObserverForName:AVAudioSessionMediaServicesWereResetNotification
																	   object:[AVAudioSession sharedInstance]
																		queue:[NSOperationQueue mainQueue]
																   usingBlock:^(NSNotification *) {
																	   if (!gChosen)
																	   {
																		   return;
																	   }
																	   std::string error;
																	   const bool ok = SetCategory(gPlayInSilentMode, error);
																	   gReapplied++;
																	   NSLog(@"AUDIO iOS session: media services reset, category set again (%s): %s", gPlayInSilentMode ? "Playback" : "Ambient",
																		   ok ? "ok" : error.c_str());
																   }];
}

} // namespace

namespace IOSAudioSessionBridge
{

Result apply(bool playInSilentMode)
{
	InstallResetObserver();
	gChosen = true;
	gPlayInSilentMode = playInSilentMode;
	std::string error;
	const bool ok = SetCategory(playInSilentMode, error);
	Result r = ReadBack();
	r.ok = ok;
	r.error = error;
	return r;
}

Result current()
{
	return ReadBack();
}

} // namespace IOSAudioSessionBridge
