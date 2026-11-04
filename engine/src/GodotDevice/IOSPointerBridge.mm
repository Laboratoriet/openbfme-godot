// OpenBFME. GPL-3.0.
//
// Lane IOS-14: the mouse, trackpad and hardware keyboard bridge of the iOS build (IOSPointerBridge.h says why). Built for iOS only, with ARC.
//
// Sources:
//   the pointer's place ..... UIHoverGestureRecognizer on Godot's view (no button down), the pointer touch's place (a button down)
//   the left button ......... the pointer's touch (UITouchTypeIndirectPointer; or, in UIKit's compatibility mode without
//                             UIApplicationSupportsIndirectInputEvents, the direct touch that begins where the pointer hovered or as GCMouse's
//                             left button goes down). The touch observer sees it before Godot's view does and records a claim: Godot's own
//                             screen touch of that click is then dropped by touch_controls.gd (claimTouch).
//   right / middle .......... GCMouse's buttons and the pointer touch's UIEvent.buttonMask, merged (one press while either holds the button); a
//                             UIKit secondary tap stands in when neither told the click
//   the wheel ............... a UIPanGestureRecognizer for scroll events only (allowedTouchTypes empty: it never takes a finger). Not GCMouse's
//                             scroll: UIKit's is what the Mac's "Designed for iPad" host and the simulator deliver too, and two sources would scroll twice
//   keys .................... GCKeyboard's keyChangedHandler (presses and releases; touch_controls.gd uses its releases)
//   an Apple Pencil ......... lane IOS-35: the touch observer records where a UITouchTypePencil touch began (a pencil claim); Godot's own screen
//                             touch of it stays a touch, and touch_controls.gd asks claimPencil to give it the select mode's gestures (a drag
//                             is a selection box when one finger pans: the scheme of daisyhasacat/openbfme-godot 607d6406, whose bridge tells the
//                             Pencil apart in its own hook of Godot's view; here the observer that already sees every touch first does it)
// Godot's view keeps every touch: no recognizer here cancels or delays touches.

#import <GameController/GameController.h>
#import <UIKit/UIGestureRecognizerSubclass.h>
#import <UIKit/UIKit.h>

#include "GodotDevice/IOSPointerBridge.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <mutex>

#if !__has_feature(objc_arc)
#error "IOSPointerBridge.mm needs ARC (-fobjc-arc, engine/CMakeLists.txt)"
#endif

using IOSPointerBridge::Event;
using IOSPointerBridge::EventType;

namespace
{

constexpr double kClaimSeconds = 1.0;           // Godot's copy of a pointer touch comes in the same UIKit event: a second is ample
constexpr float kClaimPixels = 2.0f;            // Godot truncates a touch's pixels to whole numbers
constexpr CGFloat kHoverMatchPoints = 6.0;      // compatibility mode: a direct touch this near the last hover is the pointer's click ...
constexpr double kGcLeftSeconds = 0.15;         // ... as is one this soon after GCMouse's left button went down
constexpr double kSecondaryTapSeconds = 1.5;    // a secondary tap this soon after a right press is that press's click (no second one)
constexpr double kUIKitPointerFreshSeconds = 0.05; // GCMouse's deltas move the pointer only when UIKit has not placed it for this long
constexpr std::size_t kQueueLimit = 4096;
constexpr std::size_t kClaimLimit = 64;
constexpr int kLeft = 1, kRight = 2, kMiddle = 4; // Godot's MouseButtonMask

struct Claim
{
	float x, y;
	double at;
};

struct State
{
	std::mutex lock; // the queue and the claims (every caller is on the main thread; cheap insurance)
	std::vector<Event> queue;
	std::vector<Claim> claims;
	std::vector<Claim> pencilClaims; // lane IOS-35
	bool started = false;
	float x = -1.0f, y = -1.0f;     // the pointer in window pixels; -1: never placed
	double placedAt = -1.0;         // when UIKit last placed it
	CGPoint hover = CGPointZero;    // the last hover, view points
	bool hoverValid = false;
	int uikitButtons = 0;           // held by pointer touches
	int gcButtons = 0;              // right / middle held by GCMouse
	int buttons = 0;                // what the game was told: uikitButtons | gcButtons
	bool gcLeft = false;
	double gcLeftAt = -1.0;
	double rightAt = -1e9;          // the last right press told
	bool pointerSeen = false;
	IOSPointerBridge::Status counts;
};

State &S()
{
	static State s;
	return s;
}

double Now()
{
	return std::chrono::duration<double>(std::chrono::steady_clock::now().time_since_epoch()).count();
}

int MaskOf(int button)
{
	return button == 1 ? kLeft : button == 2 ? kRight : button == 3 ? kMiddle : 0;
}

void Push(const Event &e)
{
	State &s = S();
	std::lock_guard<std::mutex> guard(s.lock);
	if (e.type == EventType::Motion && !s.queue.empty() && s.queue.back().type == EventType::Motion)
	{
		s.queue.back() = e; // a reader once a frame needs the last place only
		return;
	}
	if (s.queue.size() >= kQueueLimit)
	{
		s.queue.erase(s.queue.begin());
	}
	s.queue.push_back(e);
}

void AddClaim(std::vector<Claim> &claims, float x, float y)
{
	State &s = S();
	std::lock_guard<std::mutex> guard(s.lock);
	if (claims.size() >= kClaimLimit)
	{
		claims.erase(claims.begin());
	}
	claims.push_back(Claim{ x, y, Now() });
}

void AddClaim(float x, float y)
{
	AddClaim(S().claims, x, y);
}

// true (once) when a claim of `claims` began at (x, y) within the last kClaimSeconds; stale claims go
bool TakeClaim(std::vector<Claim> &claims, float x, float y)
{
	State &s = S();
	std::lock_guard<std::mutex> guard(s.lock);
	const double t = Now();
	bool found = false;
	for (auto it = claims.begin(); it != claims.end();)
	{
		if (t - it->at > kClaimSeconds)
		{
			it = claims.erase(it);
		}
		else if (!found && std::fabs(it->x - x) <= kClaimPixels && std::fabs(it->y - y) <= kClaimPixels)
		{
			it = claims.erase(it);
			found = true;
		}
		else
		{
			++it;
		}
	}
	return found;
}

} // namespace

static __weak UIView *gView = nil;
static NSMutableSet<GCMouse *> *gMice = nil;
static GCKeyboard *gKeyboard = nil;
static NSMutableArray *gNotificationTokens = nil;

// the pointer at `p` (view points), placed by UIKit
static void PlacePointer(CGPoint p)
{
	UIView *v = gView;
	const CGFloat scale = v != nil ? v.contentScaleFactor : 1.0;
	State &s = S();
	s.x = (float)(p.x * scale);
	s.y = (float)(p.y * scale);
	s.placedAt = Now();
}

// a button before the pointer was ever placed (a click before any hover): the view's middle
static void EnsurePointer()
{
	UIView *v = gView;
	if (S().x < 0.0f && v != nil)
	{
		PlacePointer(CGPointMake(CGRectGetMidX(v.bounds), CGRectGetMidY(v.bounds)));
	}
}

static void EmitMotion()
{
	const State &s = S();
	Event e;
	e.type = EventType::Motion;
	e.x = s.x;
	e.y = s.y;
	e.buttons = s.buttons;
	Push(e);
}

static void EmitButton(int button, bool pressed, bool doubleClick)
{
	State &s = S();
	const int mask = MaskOf(button);
	s.buttons = pressed ? (s.buttons | mask) : (s.buttons & ~mask);
	if (pressed && button == 2)
	{
		s.rightAt = Now();
	}
	Event e;
	e.type = EventType::Button;
	e.button = button;
	e.pressed = pressed;
	e.doubleClick = pressed && doubleClick;
	e.x = s.x;
	e.y = s.y;
	e.buttons = s.buttons;
	Push(e);
}

// the two sources' buttons; the game is told each change of their union (a button both hold is pressed once, released when both let go)
static void SetButtons(int uikit, int gc, bool doubleClick)
{
	State &s = S();
	s.uikitButtons = uikit;
	s.gcButtons = gc;
	const int want = uikit | gc;
	for (int button = 1; button <= 3; ++button)
	{
		const int mask = MaskOf(button);
		if ((want & mask) != (s.buttons & mask))
		{
			EmitButton(button, (want & mask) != 0, doubleClick && button == 1);
		}
	}
}

// a touch on Godot's view that is the pointer's (a mouse or trackpad click), not a finger's
static bool IsPointerTouch(UITouch *touch, UIView *view)
{
	State &s = S();
	if (touch.type == UITouchTypeIndirectPointer)
	{
		s.pointerSeen = true;
		s.counts.indirectTouches++;
		return true;
	}
	if (touch.type != UITouchTypeDirect || s.counts.indirectTouches > 0)
	{
		return false; // a pencil; or the app gets indirect pointer touches, so a direct one is a finger
	}
	// UIKit's compatibility mode: a click is a direct touch. It begins where the pointer hovered ...
	if (s.hoverValid)
	{
		const CGPoint p = [touch locationInView:view];
		if (std::hypot(p.x - s.hover.x, p.y - s.hover.y) <= kHoverMatchPoints)
		{
			return true;
		}
	}
	// ... or as the mouse's left button goes down
	return s.gcLeft && Now() - s.gcLeftAt <= kGcLeftSeconds;
}

// the button a pointer touch holds: 1 left, 2 right, 3 middle, 0 none (another button: the touch is only claimed)
static int ButtonOf(UITouch *touch, UIEvent *event)
{
	if (touch.type != UITouchTypeIndirectPointer)
	{
		return 1;
	}
	const UIEventButtonMask mask = event.buttonMask;
	if (mask & UIEventButtonMaskPrimary)
	{
		return 1;
	}
	if (mask & UIEventButtonMaskSecondary)
	{
		return 2;
	}
	if (mask & UIEventButtonMaskForButtonNumber(3))
	{
		return 3;
	}
	return mask == 0 ? 1 : 0;
}

// Observes the touches of Godot's view and never recognizes: the pointer's touches become mouse buttons and claims, the fingers' are left alone.
@interface OBFMEPointerObserver : UIGestureRecognizer
@end

@implementation OBFMEPointerObserver
{
	NSMapTable<UITouch *, NSNumber *> *_held; // the pointer touches in progress -> the button each holds
}

- (instancetype)init
{
	self = [super initWithTarget:nil action:NULL];
	if (self != nil)
	{
		_held = [NSMapTable mapTableWithKeyOptions:(NSPointerFunctionsStrongMemory | NSPointerFunctionsObjectPointerPersonality)
									  valueOptions:NSPointerFunctionsStrongMemory];
		self.cancelsTouchesInView = NO;
		self.delaysTouchesBegan = NO;
		self.delaysTouchesEnded = NO;
		self.requiresExclusiveTouchType = NO;
		self.allowedTouchTypes = @[ @(UITouchTypeDirect), @(UITouchTypeIndirectPointer), @(UITouchTypePencil) ]; // IOS-35: the Pencil's claims
	}
	return self;
}

- (int)heldMask
{
	int mask = 0;
	for (UITouch *touch in _held)
	{
		mask |= MaskOf([[_held objectForKey:touch] intValue]);
	}
	return mask;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
	[super touchesBegan:touches withEvent:event];
	UIView *view = self.view;
	if (view == nil)
	{
		return;
	}
	const CGFloat scale = view.contentScaleFactor;
	bool any = false;
	bool doubleClick = false;
	for (UITouch *touch in touches)
	{
		if (touch.type == UITouchTypePencil)
		{
			// lane IOS-35: the Pencil's touch stays Godot's (a screen touch); only its start is recorded, for claimPencil
			const CGPoint p = [touch locationInView:view];
			AddClaim(S().pencilClaims, (float)(int)(p.x * scale), (float)(int)(p.y * scale));
			S().counts.pencilTouches++;
			continue;
		}
		if (!IsPointerTouch(touch, view))
		{
			continue;
		}
		[_held setObject:@(ButtonOf(touch, event)) forKey:touch];
		const CGPoint p = [touch locationInView:view];
		AddClaim((float)(int)(p.x * scale), (float)(int)(p.y * scale)); // the pixels Godot's touch_press gets (int)
		PlacePointer(p);
		S().counts.pointerTouches++;
		doubleClick = doubleClick || touch.tapCount > 1;
		any = true;
	}
	if (any)
	{
		EmitMotion(); // the pointer to the click first (the press happens where the game saw the pointer)
		SetButtons([self heldMask], S().gcButtons, doubleClick);
	}
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
	[super touchesMoved:touches withEvent:event];
	UIView *view = self.view;
	bool any = false;
	for (UITouch *touch in touches)
	{
		if (view != nil && [_held objectForKey:touch] != nil)
		{
			PlacePointer([touch locationInView:view]);
			any = true;
		}
	}
	if (any)
	{
		EmitMotion();
	}
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
	[super touchesEnded:touches withEvent:event];
	[self endTouches:touches event:event];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
	[super touchesCancelled:touches withEvent:event];
	[self endTouches:touches event:event];
}

- (void)endTouches:(NSSet<UITouch *> *)touches event:(UIEvent *)event
{
	UIView *view = self.view;
	bool any = false;
	for (UITouch *touch in touches)
	{
		if ([_held objectForKey:touch] == nil)
		{
			continue;
		}
		if (view != nil)
		{
			PlacePointer([touch locationInView:view]);
		}
		[_held removeObjectForKey:touch];
		any = true;
	}
	if (any)
	{
		EmitMotion();
		SetButtons([self heldMask], S().gcButtons, false);
	}
	// every touch of the event over: fail, so the recognizer resets for the next sequence (it never recognizes anything)
	for (UITouch *touch in event.allTouches)
	{
		if (touch.phase != UITouchPhaseEnded && touch.phase != UITouchPhaseCancelled)
		{
			return;
		}
	}
	if (self.state == UIGestureRecognizerStatePossible)
	{
		self.state = UIGestureRecognizerStateFailed;
	}
}

- (void)reset
{
	[super reset];
	if (_held.count > 0)
	{
		[_held removeAllObjects]; // a sequence UIKit ended without telling us: nothing stays held
		SetButtons(0, S().gcButtons, false);
	}
}

@end

// The target and delegate of the hover, scroll and secondary-tap recognizers (and the observer's delegate).
@interface OBFMEPointerTarget : NSObject <UIGestureRecognizerDelegate>
@end

@implementation OBFMEPointerTarget

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
		shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
	return YES; // none of ours excludes another (the hover must not fail the touch observer)
}

- (void)hover:(UIHoverGestureRecognizer *)recognizer
{
	const UIGestureRecognizerState state = recognizer.state;
	UIView *view = recognizer.view;
	if (view == nil || recognizer.zOffset > 0.0)
	{
		return; // (zOffset: an Apple Pencil above the screen, not a pointer)
	}
	State &s = S();
	if (state == UIGestureRecognizerStateEnded || state == UIGestureRecognizerStateCancelled)
	{
		if (s.buttons == 0 && s.x >= 0.0f)
		{
			Event e;
			e.type = EventType::Leave; // the pointer left the view (or a button went down: a touch follows at the same place)
			e.x = s.x;
			e.y = s.y;
			Push(e);
		}
		return;
	}
	if (state != UIGestureRecognizerStateBegan && state != UIGestureRecognizerStateChanged)
	{
		return;
	}
	s.hover = [recognizer locationInView:view];
	s.hoverValid = true;
	s.pointerSeen = true;
	s.counts.hovers++;
	PlacePointer(s.hover);
	EmitMotion();
}

- (void)scroll:(UIPanGestureRecognizer *)recognizer
{
	const UIGestureRecognizerState state = recognizer.state;
	UIView *view = recognizer.view;
	if (view == nil || (state != UIGestureRecognizerStateBegan && state != UIGestureRecognizerStateChanged &&
						   state != UIGestureRecognizerStateEnded && state != UIGestureRecognizerStateCancelled))
	{
		return;
	}
	const CGPoint t = [recognizer translationInView:view];
	[recognizer setTranslation:CGPointZero inView:view]; // each event: the scroll since the last
	State &s = S();
	s.pointerSeen = true; // scroll events come from a wheel or a trackpad only (allowedTouchTypes is empty)
	Event e;
	e.type = EventType::Scroll;
	e.dx = (float)t.x;
	e.dy = (float)t.y;
	e.ended = state == UIGestureRecognizerStateEnded || state == UIGestureRecognizerStateCancelled;
	if (s.x >= 0.0f)
	{
		e.x = s.x;
		e.y = s.y;
	}
	else
	{
		const CGPoint p = [recognizer locationInView:view];
		e.x = (float)(p.x * view.contentScaleFactor);
		e.y = (float)(p.y * view.contentScaleFactor);
	}
	s.counts.scrolls++;
	Push(e);
}

- (void)secondaryTap:(UITapGestureRecognizer *)recognizer
{
	if (recognizer.state != UIGestureRecognizerStateEnded)
	{
		return;
	}
	State &s = S();
	s.counts.secondaryTaps++;
	if ((s.buttons & kRight) || Now() - s.rightAt < kSecondaryTapSeconds)
	{
		return; // GCMouse or the pointer touch told this click already
	}
	if (recognizer.view != nil)
	{
		PlacePointer([recognizer locationInView:recognizer.view]);
	}
	EmitMotion();
	EmitButton(2, true, false);
	EmitButton(2, false, false);
}

@end

static OBFMEPointerTarget *gTarget = nil;

static void GcButton(int button, BOOL pressed)
{
	State &s = S();
	s.counts.gcButtons++;
	s.pointerSeen = true;
	EnsurePointer();
	const int mask = MaskOf(button);
	SetButtons(s.uikitButtons, pressed ? (s.gcButtons | mask) : (s.gcButtons & ~mask), false);
}

// GCMouse's raw deltas move the pointer only while a GCMouse button is held and UIKit stopped placing it (a right or middle drag, when the
// system reports no hover during it). Units: one delta step a point; GameController's y grows upwards.
static void GcMoved(float dx, float dy)
{
	State &s = S();
	UIView *view = gView;
	if (view == nil || s.gcButtons == 0 || s.x < 0.0f || Now() - s.placedAt < kUIKitPointerFreshSeconds)
	{
		return;
	}
	const CGFloat scale = view.contentScaleFactor;
	s.x = std::min(std::max(s.x + (float)(dx * scale), 0.0f), (float)(view.bounds.size.width * scale));
	s.y = std::min(std::max(s.y - (float)(dy * scale), 0.0f), (float)(view.bounds.size.height * scale));
	EmitMotion();
}

static void AttachMouse(GCMouse *mouse)
{
	if (mouse == nil || [gMice containsObject:mouse])
	{
		return;
	}
	[gMice addObject:mouse];
	mouse.handlerQueue = dispatch_get_main_queue();
	GCMouseInput *input = mouse.mouseInput;
	if (input == nil)
	{
		return;
	}
	// the left button is the pointer touch's (its exact place, and Godot's copy is claimed); GCMouse's only helps recognise that touch
	input.leftButton.pressedChangedHandler = ^(GCControllerButtonInput *button, float value, BOOL pressed) {
		(void)button;
		(void)value;
		State &s = S();
		s.gcLeft = pressed;
		if (pressed)
		{
			s.gcLeftAt = Now();
		}
		s.counts.gcButtons++;
		s.pointerSeen = true;
	};
	input.rightButton.pressedChangedHandler = ^(GCControllerButtonInput *button, float value, BOOL pressed) {
		(void)button;
		(void)value;
		GcButton(2, pressed);
	};
	input.middleButton.pressedChangedHandler = ^(GCControllerButtonInput *button, float value, BOOL pressed) {
		(void)button;
		(void)value;
		GcButton(3, pressed);
	};
	input.mouseMovedHandler = ^(GCMouseInput *mouseInput, float deltaX, float deltaY) {
		(void)mouseInput;
		if (deltaX != 0.0f || deltaY != 0.0f)
		{
			S().pointerSeen = true; // a mouse that moves is a real one (IOS-17: mouseConnected)
		}
		GcMoved(deltaX, deltaY);
	};
}

static void DetachMouse(GCMouse *mouse)
{
	if (mouse == nil || ![gMice containsObject:mouse])
	{
		return;
	}
	[gMice removeObject:mouse];
	State &s = S();
	s.gcLeft = false;
	SetButtons(s.uikitButtons, 0, false); // nothing stays held by a mouse that went
	if ([GCMouse mice].count == 0)
	{
		s.pointerSeen = false; // touch-only again until a pointer shows itself
		s.hoverValid = false;
	}
}

static void AttachKeyboard(GCKeyboard *keyboard)
{
	if (keyboard == nil || keyboard == gKeyboard)
	{
		return;
	}
	gKeyboard = keyboard;
	keyboard.handlerQueue = dispatch_get_main_queue();
	keyboard.keyboardInput.keyChangedHandler = ^(GCKeyboardInput *input, GCDeviceButtonInput *key, GCKeyCode keyCode, BOOL pressed) {
		(void)input;
		(void)key;
		Event e;
		e.type = EventType::Key;
		e.hidUsage = (long)keyCode;
		e.pressed = pressed;
		S().counts.keys++;
		Push(e);
	};
}

bool IOSPointerBridge::start(void *uiView)
{
	State &s = S();
	if (s.started)
	{
		return true;
	}
	UIView *view = (__bridge UIView *)uiView;
	if (view == nil)
	{
		return false;
	}
	gView = view;
	gTarget = [[OBFMEPointerTarget alloc] init];

	OBFMEPointerObserver *observer = [[OBFMEPointerObserver alloc] init];
	observer.delegate = gTarget;
	[view addGestureRecognizer:observer];

	UIHoverGestureRecognizer *hover = [[UIHoverGestureRecognizer alloc] initWithTarget:gTarget action:@selector(hover:)];
	hover.delegate = gTarget;
	hover.cancelsTouchesInView = NO;
	[view addGestureRecognizer:hover];

	UIPanGestureRecognizer *scroll = [[UIPanGestureRecognizer alloc] initWithTarget:gTarget action:@selector(scroll:)];
	scroll.allowedScrollTypesMask = UIScrollTypeMaskAll;
	scroll.allowedTouchTypes = @[]; // scroll events only, never a touch
	scroll.cancelsTouchesInView = NO;
	scroll.delaysTouchesBegan = NO;
	scroll.delaysTouchesEnded = NO;
	scroll.delegate = gTarget;
	[view addGestureRecognizer:scroll];

	UITapGestureRecognizer *secondary = [[UITapGestureRecognizer alloc] initWithTarget:gTarget action:@selector(secondaryTap:)];
	secondary.buttonMaskRequired = UIEventButtonMaskSecondary;
	secondary.allowedTouchTypes = @[ @(UITouchTypeIndirectPointer) ]; // buttonMaskRequired is not evaluated for fingers: they never reach it
	secondary.cancelsTouchesInView = NO;
	secondary.delaysTouchesBegan = NO;
	secondary.delaysTouchesEnded = NO;
	secondary.delegate = gTarget;
	[view addGestureRecognizer:secondary];

	gMice = [NSMutableSet set];
	for (GCMouse *mouse in [GCMouse mice])
	{
		AttachMouse(mouse);
	}
	AttachKeyboard(GCKeyboard.coalescedKeyboard);

	NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
	NSOperationQueue *main = NSOperationQueue.mainQueue;
	gNotificationTokens = [NSMutableArray array];
	[gNotificationTokens addObject:[center addObserverForName:GCMouseDidConnectNotification object:nil queue:main usingBlock:^(NSNotification *note) {
		AttachMouse((GCMouse *)note.object);
	}]];
	[gNotificationTokens addObject:[center addObserverForName:GCMouseDidDisconnectNotification object:nil queue:main usingBlock:^(NSNotification *note) {
		DetachMouse((GCMouse *)note.object);
	}]];
	[gNotificationTokens addObject:[center addObserverForName:GCKeyboardDidConnectNotification object:nil queue:main usingBlock:^(NSNotification *note) {
		AttachKeyboard((GCKeyboard *)note.object);
	}]];
	[gNotificationTokens addObject:[center addObserverForName:GCKeyboardDidDisconnectNotification object:nil queue:main usingBlock:^(NSNotification *note) {
		(void)note;
		gKeyboard = nil;
	}]];

	s.started = true;
	return true;
}

void IOSPointerBridge::poll(std::vector<Event> &out)
{
	State &s = S();
	std::lock_guard<std::mutex> guard(s.lock);
	out.insert(out.end(), s.queue.begin(), s.queue.end());
	s.queue.clear();
}

bool IOSPointerBridge::claimTouch(float x, float y)
{
	const bool found = TakeClaim(S().claims, x, y);
	if (found)
	{
		S().counts.claims++;
	}
	return found;
}

bool IOSPointerBridge::claimPencil(float x, float y)
{
	const bool found = TakeClaim(S().pencilClaims, x, y);
	if (found)
	{
		S().counts.pencilClaims++;
	}
	return found;
}

// IOS-17: a mouse only once one has hovered, moved, clicked or scrolled. GCMouse lists a mouse on a phone with none attached (the iPhone
// Duo, nothing paired: "mice": 1 from the start), and that alone switched touch play to the desktop's right-click orders
bool IOSPointerBridge::mouseConnected()
{
	return S().pointerSeen;
}

bool IOSPointerBridge::keyboardConnected()
{
	return GCKeyboard.coalescedKeyboard != nil;
}

int IOSPointerBridge::buttonsDown()
{
	return S().buttons;
}

IOSPointerBridge::Status IOSPointerBridge::status()
{
	State &s = S();
	Status r = s.counts;
	r.started = s.started;
	r.mice = (int)[GCMouse mice].count;
	r.keyboard = GCKeyboard.coalescedKeyboard != nil;
	r.pointerSeen = s.pointerSeen;
	r.onMac = NSProcessInfo.processInfo.isiOSAppOnMac;
	return r;
}
