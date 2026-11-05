// OpenBFME. GPL-3.0.
//
// The iOS / iPadOS input bridge (GodotIOSTouch.h). UIKit keeps UITouch.type, which Godot's stock screen-touch events omit, so the touches
// of Godot's view are split before Godot sees them:
//   a finger ................ stays a Godot screen touch (Godot's own handling, unchanged);
//   an Apple Pencil ......... becomes mouse events (left button, pressure, tilt) with device id PencilDevice;
//   a mouse or trackpad ..... becomes mouse events with macOS click semantics (UIEvent.buttonMask; Control-click is a right click), never a
//                             touch. Hover, scroll and the trackpad's pinch come from gesture recognizers on the view.
// Only the public UIResponder touch methods of Godot's view class are wrapped (Apple WWDC20, "Handle trackpad and mouse input").
//
// From the other iOS port, through GameController:
//   GCMouse ................. right and middle buttons, merged with the touch's (ButtonUnion), for a press that reaches the view as no
//                             touch at all;
//   GCKeyboard .............. a key release Godot did not get: on an iPad app running on a Mac ("Designed for iPad") a hardware key's
//                             release never reached the app, so a held key stayed held. Shortly after GCKeyboard's release, a key Godot
//                             still holds is released (an InputEventKey of the same physical key).
#include "GodotDevice/GodotIOSTouch.h"
#import <GameController/GameController.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <godot_cpp/classes/global_constants.hpp>
#include <godot_cpp/classes/input.hpp>
#include <godot_cpp/classes/input_event_key.hpp>
#include <godot_cpp/classes/input_event_mouse_button.hpp>
#include <godot_cpp/classes/input_event_mouse_motion.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <cmath>
#include <cstdint>
#include <godot_cpp/classes/input_event_pan_gesture.hpp>
#include <godot_cpp/classes/input_event_magnify_gesture.hpp>

#if !__has_feature(objc_arc)
#error "GodotIOSTouch.mm needs ARC (-fobjc-arc, engine/CMakeLists.txt)"
#endif

// UIKit pointer input must remain mouse input, independent of direct touch controls.
@interface OpenBFMETrackpad : NSObject <UIGestureRecognizerDelegate> {
@public
    OpenBFMEIOSTouch::PointerClick click;
    OpenBFMEIOSTouch::ButtonUnion sources;
}
@property(nonatomic, weak) UIView *view;
@property(nonatomic) NSUInteger buttons;
@property(nonatomic) CGPoint last;
@property(nonatomic) BOOL hasLast;
@property(nonatomic) BOOL placed; // the pointer was ever over the view (last is where)
@property(nonatomic, strong) NSMutableArray<UIGestureRecognizer *> *recognizers;
- (void)hover:(UIHoverGestureRecognizer *)gesture;
- (void)scroll:(UIPanGestureRecognizer *)gesture;
- (void)pinch:(UIPinchGestureRecognizer *)gesture;
@end

static const void *trackpadKey = &trackpadKey;
static godot::Vector2 pointerPoint(UIView *view, CGPoint point) {
    return godot::Vector2(point.x * view.contentScaleFactor, point.y * view.contentScaleFactor);
}
static void pointerModifiers(godot::InputEventWithModifiers *event, UIKeyModifierFlags flags) {
    event->set_shift_pressed((flags & UIKeyModifierShift) != 0);
    event->set_ctrl_pressed((flags & UIKeyModifierControl) != 0);
    event->set_alt_pressed((flags & UIKeyModifierAlternate) != 0);
    event->set_meta_pressed((flags & UIKeyModifierCommand) != 0);
}
// A press or release for each button (1 left, 2 right, 3 middle) whose state differs between what Godot was told and `next`.
static void emitButtons(UIView *view, OpenBFMETrackpad *bridge, NSUInteger next, CGPoint point, UIKeyModifierFlags flags, NSUInteger taps,
                        bool canceled) {
    auto *input = godot::Input::get_singleton();
    if (!input) return;
    const NSUInteger changed = bridge.buttons ^ next;
    for (int index = 1; index <= 3; ++index) {
        const NSUInteger mask = 1u << (index-1);
        if (!(changed & mask)) continue;
        godot::Ref<godot::InputEventMouseButton> button;
        button.instantiate();
        pointerModifiers(button.ptr(), flags);
        button->set_position(pointerPoint(view, point));
        button->set_global_position(button->get_position());
        button->set_button_index(static_cast<godot::MouseButton>(index));
        button->set_button_mask(godot::BitField<godot::MouseButtonMask>(next));
        button->set_pressed((next & mask) != 0);
        button->set_double_click(OpenBFMEIOSTouch::pointerDoubleClick(index, (next & mask) != 0, taps));
        button->set_canceled(canceled);
        input->parse_input_event(button);
    }
    bridge.buttons = next;
}
@implementation OpenBFMETrackpad
- (void)hover:(UIHoverGestureRecognizer *)gesture {
    auto *input = godot::Input::get_singleton();
    if (!input) return;
    const CGPoint point = [gesture locationInView:self.view];
    godot::Ref<godot::InputEventMouseMotion> motion;
    motion.instantiate();
    pointerModifiers(motion.ptr(), gesture.modifierFlags);
    motion->set_position(pointerPoint(self.view, point));
    motion->set_global_position(motion->get_position());
    if (self.hasLast) motion->set_relative(pointerPoint(self.view, CGPointMake(point.x-self.last.x, point.y-self.last.y)));
    motion->set_screen_relative(motion->get_relative());
    motion->set_button_mask(godot::BitField<godot::MouseButtonMask>(self.buttons));
    input->parse_input_event(motion);
    self.last = point;
    self.placed = YES;
    self.hasLast = gesture.state != UIGestureRecognizerStateEnded && gesture.state != UIGestureRecognizerStateCancelled;
}
- (void)scroll:(UIPanGestureRecognizer *)gesture {
    const CGPoint delta = [gesture translationInView:self.view];
    [gesture setTranslation:CGPointMake(0, 0) inView:self.view];
    if (!godot::Input::get_singleton() || (delta.x == 0 && delta.y == 0)) return;
    godot::Ref<godot::InputEventPanGesture> event;
    event.instantiate();
    pointerModifiers(event.ptr(), gesture.modifierFlags);
    event->set_position(pointerPoint(self.view, [gesture locationInView:self.view]));
    // Match Godot macOS scrollWheel/processPanEvent: precise point deltas * 0.03, opposite content movement.
    event->set_delta(godot::Vector2(-delta.x * 0.03, -delta.y * 0.03));
    godot::Input::get_singleton()->parse_input_event(event);
}
- (void)pinch:(UIPinchGestureRecognizer *)gesture {
    const double factor = gesture.scale;
    gesture.scale = 1;
    if (!godot::Input::get_singleton() || !std::isfinite(factor) || factor <= 0 || factor == 1) return;
    godot::Ref<godot::InputEventMagnifyGesture> event;
    event.instantiate();
    pointerModifiers(event.ptr(), gesture.modifierFlags);
    event->set_position(pointerPoint(self.view, [gesture locationInView:self.view]));
    event->set_factor(factor);
    godot::Input::get_singleton()->parse_input_event(event);
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)a shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)b { return YES; }
@end

namespace {
using TouchMethod = void (*)(id, SEL, NSSet *, UIEvent *);
struct Hook {
    const char *name;
    IMP original = nullptr;
    IMP replacement = nullptr;
};
Hook hooks[] = {{"touchesBegan:withEvent:"}, {"touchesMoved:withEvent:"},
    {"touchesEnded:withEvent:"}, {"touchesCancelled:withEvent:"}};
Class view_class = Nil;

IMP originalMovedToWindow = nullptr;
IMP movedToWindowHook = nullptr;
NSHashTable<UIView *> *pointerViews;
void install_pointer(UIView *view) {
    if (objc_getAssociatedObject(view, trackpadKey)) return;
    OpenBFMETrackpad *bridge = [OpenBFMETrackpad new];
    bridge.view = view;
    UIHoverGestureRecognizer *hover = [[UIHoverGestureRecognizer alloc] initWithTarget:bridge action:@selector(hover:)];
    hover.allowedTouchTypes = @[@(UITouchTypeIndirectPointer)];
    UIPanGestureRecognizer *scroll = [[UIPanGestureRecognizer alloc] initWithTarget:bridge action:@selector(scroll:)];
    scroll.allowedTouchTypes = @[]; // Scroll events only; fingers keep the existing touch controls.
    scroll.allowedScrollTypesMask = UIScrollTypeMaskContinuous;
    UIPinchGestureRecognizer *pinch = [[UIPinchGestureRecognizer alloc] initWithTarget:bridge action:@selector(pinch:)];
    pinch.allowedTouchTypes = @[@(UITouchTypeIndirectPointer)];
    bridge.recognizers = [NSMutableArray arrayWithArray:@[hover, scroll, pinch]];
    for (UIGestureRecognizer *gesture in bridge.recognizers) {
        gesture.cancelsTouchesInView = NO;
        gesture.delaysTouchesBegan = NO;
        gesture.delaysTouchesEnded = NO;
        gesture.delegate = bridge;
        [view addGestureRecognizer:gesture];
    }
    objc_setAssociatedObject(view, trackpadKey, bridge, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [pointerViews addObject:view];
}
void find_pointer_views(UIView *view) {
    if ([view isKindOfClass:view_class]) install_pointer(view);
    for (UIView *child in view.subviews) find_pointer_views(child);
}
void emit_pointer(UIView *view, UITouch *touch, UIEvent *native, int phase) {
    install_pointer(view);
    OpenBFMETrackpad *bridge = objc_getAssociatedObject(view, trackpadKey);
    auto *input = godot::Input::get_singleton();
    if (!input) return;
    const CGPoint point = [touch locationInView:view];
    // UIKit primary/secondary bits match Godot's left/right button masks.
    const NSUInteger touchButtons = bridge->click.update(native.buttonMask, phase, (native.modifierFlags & UIKeyModifierControl) != 0);
    const NSUInteger next = bridge->sources.fromUIKit(touchButtons);
    bridge.last = point; bridge.hasLast = YES; bridge.placed = YES;
    if (phase == 1) {
        godot::Ref<godot::InputEventMouseMotion> motion;
        motion.instantiate();
        pointerModifiers(motion.ptr(), native.modifierFlags);
        motion->set_position(pointerPoint(view, point));
        motion->set_global_position(motion->get_position());
        const CGPoint previous = [touch previousLocationInView:view];
        motion->set_relative(pointerPoint(view, CGPointMake(point.x-previous.x, point.y-previous.y)));
        motion->set_screen_relative(motion->get_relative());
        motion->set_button_mask(godot::BitField<godot::MouseButtonMask>(next));
        input->parse_input_event(motion);
    }
    emitButtons(view, bridge, next, point, native.modifierFlags, touch.tapCount, phase == 3);
}

void emit_pencil(UIView *view, UITouch *touch, int phase) {
    auto *input = godot::Input::get_singleton();
    if (!input) return;
    const CGPoint point = [touch locationInView:view];
    const CGFloat scale = view.contentScaleFactor;
    const godot::Vector2 position(point.x * scale, point.y * scale);
    if (phase == 1) {
        godot::Ref<godot::InputEventMouseMotion> motion;
        motion.instantiate();
        motion->set_device(OpenBFMEIOSTouch::PencilDevice);
        motion->set_position(position);
        motion->set_global_position(position);
        motion->set_button_mask(godot::MOUSE_BUTTON_MASK_LEFT);
        const CGPoint previous = [touch previousLocationInView:view];
        const godot::Vector2 relative((point.x - previous.x) * scale, (point.y - previous.y) * scale);
        motion->set_relative(relative);
        motion->set_screen_relative(relative);
        motion->set_pressure(touch.maximumPossibleForce > 0 ? touch.force / touch.maximumPossibleForce : 0);
        const CGVector azimuth = [touch azimuthUnitVectorInView:view];
        const double tilt = std::cos(touch.altitudeAngle);
        motion->set_tilt(godot::Vector2(azimuth.dx * tilt, azimuth.dy * tilt));
        input->parse_input_event(motion);
    } else {
        godot::Ref<godot::InputEventMouseButton> button;
        button.instantiate();
        button->set_device(OpenBFMEIOSTouch::PencilDevice);
        button->set_position(position);
        button->set_global_position(position);
        button->set_button_index(godot::MOUSE_BUTTON_LEFT);
        button->set_button_mask(phase == 0 ? godot::MOUSE_BUTTON_MASK_LEFT : godot::BitField<godot::MouseButtonMask>(0));
        button->set_pressed(phase == 0);
        button->set_double_click(phase == 0 && touch.tapCount > 1);
        button->set_canceled(phase == 3);
        input->parse_input_event(button);
    }
}

// ---- GameController: a mouse's right / middle buttons, missing key releases ------------------------------------------------------------

NSUInteger gcButtons = 0;               // GCMouse's right (2) and middle (4) buttons held
NSHashTable<GCMouse *> *mice;           // the mice whose handlers are set
GCKeyboard *keyboard = nil;             // the keyboard whose handler is set
NSMutableArray *observers;              // the connect / disconnect notifications' tokens
constexpr double kReleaseCheckSeconds = 0.1; // Godot's own release has come by then, if it comes at all

void gc_buttons(NSUInteger buttons) {
    gcButtons = buttons;
    for (UIView *view in pointerViews) {
        OpenBFMETrackpad *bridge = objc_getAssociatedObject(view, trackpadKey);
        if (!bridge || !view.window) continue;
        const NSUInteger next = bridge->sources.fromGameController(buttons);
        const CGPoint point = bridge.placed ? bridge.last : CGPointMake(CGRectGetMidX(view.bounds), CGRectGetMidY(view.bounds));
        emitButtons(view, bridge, next, point, 0, 1, false);
    }
}

void attach_mouse(GCMouse *mouse) {
    if (!mouse || [mice containsObject:mouse] || !mouse.mouseInput) return;
    [mice addObject:mouse];
    mouse.handlerQueue = dispatch_get_main_queue();
    mouse.mouseInput.rightButton.pressedChangedHandler = ^(GCControllerButtonInput *button, float value, BOOL pressed) {
        (void)button; (void)value;
        gc_buttons(pressed ? (gcButtons | 2u) : (gcButtons & ~2u));
    };
    mouse.mouseInput.middleButton.pressedChangedHandler = ^(GCControllerButtonInput *button, float value, BOOL pressed) {
        (void)button; (void)value;
        gc_buttons(pressed ? (gcButtons | 4u) : (gcButtons & ~4u));
    };
}

void detach_mouse(GCMouse *mouse) {
    if (!mouse || ![mice containsObject:mouse]) return;
    mouse.mouseInput.rightButton.pressedChangedHandler = nil;
    mouse.mouseInput.middleButton.pressedChangedHandler = nil;
    [mice removeObject:mouse];
    if (gcButtons) gc_buttons(0); // nothing stays held by a mouse that went
}

// The USB HID usage of a key -> the Key Godot's iOS layer gives that key as its physical keycode (Godot 4.7.2
// drivers/apple_embedded/key_mapping_apple_embedded.mm KeyMappingAppleEmbedded::initialize, its choices kept: Quote is QUOTEDBL, the
// grave accent BAR, NonUSPound ASCIITILDE). The release below matches Godot's own press by this code, so it must be exactly Godot's.
godot::Key hid_key(long hid) {
    using namespace godot;
    if (hid >= 0x04 && hid <= 0x1D) return (Key)((int64_t)KEY_A + (hid - 0x04));     // a .. z
    if (hid >= 0x1E && hid <= 0x26) return (Key)((int64_t)KEY_1 + (hid - 0x1E));     // 1 .. 9
    if (hid >= 0x3A && hid <= 0x45) return (Key)((int64_t)KEY_F1 + (hid - 0x3A));    // F1 .. F12
    if (hid >= 0x68 && hid <= 0x73) return (Key)((int64_t)KEY_F13 + (hid - 0x68));   // F13 .. F24
    if (hid >= 0x59 && hid <= 0x61) return (Key)((int64_t)KEY_KP_1 + (hid - 0x59));  // keypad 1 .. 9
    switch (hid) {
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

void attach_keyboard(GCKeyboard *candidate) {
    if (!candidate || candidate == keyboard) return;
    keyboard = candidate;
    keyboard.handlerQueue = dispatch_get_main_queue();
    keyboard.keyboardInput.keyChangedHandler = ^(GCKeyboardInput *board, GCDeviceButtonInput *button, GCKeyCode code, BOOL pressed) {
        (void)board; (void)button;
        const godot::Key key = hid_key((long)code);
        if (pressed || key == godot::KEY_NONE) return;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kReleaseCheckSeconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            auto *input = godot::Input::get_singleton();
            if (!input || !input->is_physical_key_pressed(key)) return; // Godot's own release came
            godot::Ref<godot::InputEventKey> release;
            release.instantiate();
            release->set_physical_keycode(key);
            release->set_keycode(key);
            release->set_pressed(false);
            input->parse_input_event(release);
        });
    };
}

void detach_keyboard() {
    if (keyboard) keyboard.keyboardInput.keyChangedHandler = nil;
    keyboard = nil;
}

void install_game_controller() {
    mice = [NSHashTable hashTableWithOptions:NSPointerFunctionsStrongMemory | NSPointerFunctionsObjectPointerPersonality];
    for (GCMouse *mouse in GCMouse.mice) attach_mouse(mouse);
    attach_keyboard(GCKeyboard.coalescedKeyboard);
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    NSOperationQueue *main = NSOperationQueue.mainQueue;
    observers = [NSMutableArray array];
    [observers addObject:[center addObserverForName:GCMouseDidConnectNotification object:nil queue:main usingBlock:^(NSNotification *note) {
        attach_mouse((GCMouse *)note.object);
    }]];
    [observers addObject:[center addObserverForName:GCMouseDidDisconnectNotification object:nil queue:main usingBlock:^(NSNotification *note) {
        detach_mouse((GCMouse *)note.object);
    }]];
    [observers addObject:[center addObserverForName:GCKeyboardDidConnectNotification object:nil queue:main usingBlock:^(NSNotification *note) {
        attach_keyboard((GCKeyboard *)note.object);
    }]];
    [observers addObject:[center addObserverForName:GCKeyboardDidDisconnectNotification object:nil queue:main usingBlock:^(NSNotification *note) {
        (void)note;
        detach_keyboard();
    }]];
}

void uninstall_game_controller() {
    for (id token in observers) [NSNotificationCenter.defaultCenter removeObserver:token];
    observers = nil;
    for (GCMouse *mouse in [mice allObjects]) detach_mouse(mouse);
    mice = nil;
    detach_keyboard();
    gcButtons = 0;
}

void on_main(dispatch_block_t action) {
    if ([NSThread isMainThread]) action();
    else dispatch_sync(dispatch_get_main_queue(), action);
}
}

void OpenBFMEIOSTouch::install() {
    on_main(^{
        if (view_class) return;
        // Godot 4.7 renamed GodotView to GDTView. Both are public ObjC runtime
        // class names in the stock engine, not private UIKit APIs.
        Class candidate = NSClassFromString(@"GDTView");
        if (!candidate) candidate = NSClassFromString(@"GodotView");
        if (!candidate) {
            godot::UtilityFunctions::push_error("iOS input bridge: Godot rendering view class is unavailable.");
            return;
        }
        for (auto &hook : hooks) {
            if (!class_getInstanceMethod(candidate, sel_registerName(hook.name))) {
                godot::UtilityFunctions::push_error("iOS input bridge: Godot rendering view has incompatible touch methods.");
                return;
            }
        }
        view_class = candidate;
        pointerViews = [NSHashTable weakObjectsHashTable];
        const SEL moved = @selector(didMoveToWindow);
        Method movedMethod = class_getInstanceMethod(candidate, moved);
        originalMovedToWindow = method_getImplementation(movedMethod);
        movedToWindowHook = imp_implementationWithBlock(^(UIView *view) {
            reinterpret_cast<void (*)(id, SEL)>(originalMovedToWindow)(view, moved);
            if (view.window) install_pointer(view);
        });
        class_replaceMethod(candidate, moved, movedToWindowHook, method_getTypeEncoding(movedMethod));
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes)
            if ([scene isKindOfClass:UIWindowScene.class])
                for (UIWindow *window in ((UIWindowScene *)scene).windows) find_pointer_views(window);
        for (int phase = 0; phase < 4; ++phase) {
            auto &hook = hooks[phase];
            const SEL selector = sel_registerName(hook.name);
            Method method = class_getInstanceMethod(view_class, selector);
            hook.original = method_getImplementation(method);
            hook.replacement = imp_implementationWithBlock(^(UIView *view, NSSet *touches, UIEvent *event) {
                NSMutableSet *fingers = [NSMutableSet setWithCapacity:touches.count];
                for (UITouch *touch in touches) {
                    if (touch.type == UITouchTypePencil) emit_pencil(view, touch, phase);
                    else if (touch.type == UITouchTypeIndirectPointer) emit_pointer(view, touch, event, phase);
                    else [fingers addObject:touch];
                }
                if (fingers.count) reinterpret_cast<TouchMethod>(hooks[phase].original)(view, selector, fingers, event);
            });
            // class_replaceMethod also handles an inherited implementation
            // without modifying UIResponder's method for unrelated UIKit views.
            class_replaceMethod(view_class, selector, hook.replacement, method_getTypeEncoding(method));
        }
        install_game_controller();
    });
}

void OpenBFMEIOSTouch::uninstall() {
    on_main(^{
        if (!view_class) return;
        uninstall_game_controller();
        for (auto &hook : hooks) {
            const SEL selector = sel_registerName(hook.name);
            Method method = class_getInstanceMethod(view_class, selector);
            if (method_getImplementation(method) == hook.replacement) {
                class_replaceMethod(view_class, selector, hook.original, method_getTypeEncoding(method));
                imp_removeBlock(hook.replacement);
            } else {
                // Another component has wrapped us; keep the block alive until
                // process shutdown rather than leave its method chain dangling.
                godot::UtilityFunctions::push_error("iOS input bridge: touch method changed before shutdown; retaining hook.");
            }
        }
        for (UIView *view in pointerViews) {
            OpenBFMETrackpad *bridge = objc_getAssociatedObject(view, trackpadKey);
            for (UIGestureRecognizer *gesture in bridge.recognizers) [view removeGestureRecognizer:gesture];
            objc_setAssociatedObject(view, trackpadKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        pointerViews = nil;
        const SEL moved = @selector(didMoveToWindow);
        Method method = class_getInstanceMethod(view_class, moved);
        if (method_getImplementation(method) == movedToWindowHook) {
            class_replaceMethod(view_class, moved, originalMovedToWindow, method_getTypeEncoding(method));
            imp_removeBlock(movedToWindowHook);
        }
        view_class = Nil;
    });
}
