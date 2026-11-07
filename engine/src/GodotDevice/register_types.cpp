// OpenBFME. GPL-3.0.
// GDExtension entry point: registers the device-layer classes.

#include "GodotDevice/GodotAptPlayer.h"
#include "GodotDevice/GodotGameAudio.h"
#include "GodotDevice/GodotGammaComposite.h"
#include "GodotDevice/GodotGameWorld.h"
#include "GodotDevice/GodotInGameHud.h"
#include "GodotDevice/GodotFXPlayer.h"
#include "GodotDevice/GodotLogicClock.h"
#include "GodotDevice/GodotMapObjectBuilder.h"
#include "GodotDevice/GodotMapTerrain.h"
#include "GodotDevice/GodotPathfindView.h"
#include "GodotDevice/GodotGlowEffect.h"
#include "GodotDevice/GodotPostEffects.h"
#include "GodotDevice/GodotRelease.h"
#include "Common/ConsoleFilter.h"
#include "Common/WindowsCrashDump.h"
#include "GodotDevice/GodotRetailFileSystem.h"
#include "GodotDevice/GodotW3DInstancer.h"
#include "GodotDevice/GodotW3DMaterial.h"
#include "GodotDevice/GodotVideoStream.h"
#include "GodotDevice/GodotW3DModelBuilder.h"
#include "GodotDevice/GodotLivingWorld.h" // WOTR-1
#if defined(OPENBFME_IOS_INPUT)
// IOS-45: the iOS input bridge (Pencil, mouse / trackpad, keyboard; after daisyhasacat/openbfme-godot) and the IOSInputDevices class
// (IOS-14 / IOS-17: which mice and keyboards are connected). iOS builds only (engine/CMakeLists.txt)
#include "GodotDevice/GodotIOSTouch.h"
#include "GodotDevice/GodotIOSInputDevices.h"
#endif
#if defined(OPENBFME_IOS_AUDIO_SESSION)
#include "GodotDevice/GodotIOSAudioSession.h" // IOS-20: iOS builds only (engine/CMakeLists.txt)
#endif
#if defined(OPENBFME_IOS_FILES)
#include "GodotDevice/GodotIOSFiles.h" // IOS-36: iOS builds only (engine/CMakeLists.txt)
#endif

#include <gdextension_interface.h>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

using namespace godot;

static void initialize_openbfme(ModuleInitializationLevel p_level)
{
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE)
	{
		return;
	}
	GDREGISTER_CLASS(RetailFileSystem);
	GDREGISTER_CLASS(W3DModelBuilder);
	GDREGISTER_CLASS(MapTerrainBuilder);
	GDREGISTER_CLASS(MapObjectBuilder);
	GDREGISTER_CLASS(PathfindView);
	GDREGISTER_CLASS(W3DInstancer);
	GDREGISTER_CLASS(LogicClock);
	GDREGISTER_CLASS(AptMenuPlayer);
	GDREGISTER_CLASS(GameWorld);
	GDREGISTER_CLASS(InGameHudNode); // HUD-1
	GDREGISTER_CLASS(FXPlayer); // FX-1
	GDREGISTER_CLASS(GameAudio);
	GDREGISTER_CLASS(GammaCompositeEffect); // RENDER-3 (S-831)
	GDREGISTER_CLASS(GammaCompositeHost);
	GDREGISTER_CLASS(LookupTablePostEffect); // RENDER-4 (S-1650)
	GDREGISTER_CLASS(MapPostEffectsHost);
	GDREGISTER_CLASS(GlowPostEffect); // GLOW-1 (S-5231)
	GDREGISTER_CLASS(GlowPostEffectHost);
	GDREGISTER_CLASS(ReleaseInfo); // RELEASE-1
	GDREGISTER_CLASS(SessionLogger);
	GDREGISTER_CLASS(InstallSetup);
	GDREGISTER_CLASS(VP6MovieStream); // CAMP-2
	GDREGISTER_CLASS(LivingWorldGame); // WOTR-1
#if defined(OPENBFME_IOS_INPUT)
	GDREGISTER_CLASS(IOSInputDevices); // IOS-45: the connected mice and keyboards (scripts/touch/touch_controls.gd)
	OpenBFMEIOSTouch::install(); // splits the touches of Godot's view (GodotIOSTouch.mm)
#endif
#if defined(OPENBFME_IOS_AUDIO_SESSION)
	GDREGISTER_CLASS(IOSAudioSession); // IOS-20: the audio session's category (Play sound in silent mode)
#endif
#if defined(OPENBFME_IOS_FILES)
	GDREGISTER_CLASS(IOSFiles); // IOS-36: Files' document picker (Choose game file…), backup exclusion
#endif
}

static void uninitialize_openbfme(ModuleInitializationLevel p_level)
{
	if (p_level == MODULE_INITIALIZATION_LEVEL_SCENE)
	{
#if defined(OPENBFME_IOS_INPUT)
		OpenBFMEIOSTouch::uninstall();
#endif
		WindowsCrashDump::uninstall();
		ConsoleFilter::uninstall(); // RELEASE-1: the original stdout / stderr back before the extension's code goes
		GammaComposite::shutdown();
		W3DMaterialFactory::Release_Warm_Shaders(); // lane IOS-11
	}
}

extern "C"
{
GDExtensionBool GDE_EXPORT openbfme_library_init(GDExtensionInterfaceGetProcAddress p_get_proc_address,
	GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization)
{
	GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
	init_obj.register_initializer(initialize_openbfme);
	init_obj.register_terminator(uninitialize_openbfme);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_obj.init();
}
}
